// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {
    MockRecomputer,
    RejectingRecomputer,
    RevertingRecomputer,
    ReentrantRecomputer,
    RejectingAgent
} from "./mocks/MockRecomputer.sol";

contract DissentCoreTest is Test {
    DissentCore core;
    MockRecomputer rc;

    address agent = makeAddr("agent");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint128 constant REWARD = 1 ether;
    uint128 constant DEPOSIT = 0.1 ether;
    uint64 constant WINDOW = 1 days;
    int256 constant BASE = 200;
    int256 constant THRESHOLD = 100;

    function setUp() public {
        core = new DissentCore();
        rc = new MockRecomputer();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _inputs(int256 base) internal pure returns (bytes memory) {
        return abi.encode(base);
    }

    /// @dev El sello, calculado LOCALMENTE. Si se llamara a _sealOf()
    ///     dentro de la lista de argumentos, esa llamada externa se comeria el
    ///     vm.prank y el challengeCommit lo haria este contrato, no el retador.
    function _sealOf(bytes memory ev, bytes32 salt, address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(ev, salt, who));
    }

    function _commit() internal returns (bytes32 id) {
        vm.prank(agent);
        id = core.commit{value: REWARD}(
            address(rc), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, bytes32(0)
        );
    }

    function _reveal(bytes32 id, address who, int256 newValue, bytes32 salt) internal {
        bytes memory ev = abi.encode(newValue);
        vm.prank(who);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, salt, who));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(who);
        core.challengeReveal(id, _inputs(BASE), ev, salt);
    }

    // ── commit ────────────────────────────────────────────────────────────────

    function test_commit_calcula_el_base_el_mismo() public {
        bytes32 id = _commit();
        DissentCore.Commitment memory c = core.getCommitment(id);
        assertEq(c.baseValue, BASE, "el base lo calcula el contrato");
        assertEq(c.threshold, THRESHOLD);
        assertEq(uint8(c.comparator), uint8(DissentCore.Comparator.AtLeast));
        assertEq(uint8(c.status), uint8(DissentCore.Status.Open));
        assertEq(core.escrowed(), REWARD);
        assertEq(address(core).balance, REWARD);
    }

    function test_commit_mide_el_gas_del_base() public {
        bytes32 id = _commit();
        uint32 baseGas = core.getCommitment(id).baseGas;
        assertGt(baseGas, 0, "el nucleo mide, no pregunta");
        console.log("baseGas medido por el nucleo (mock): %s", baseGas);
    }

    function test_commit_rechaza_un_base_que_ya_viola_el_umbral() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.BaseDoesNotSatisfyThreshold.selector, int256(50), THRESHOLD));
        core.commit{value: REWARD}(
            address(rc), _inputs(50), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, bytes32(0)
        );
    }

    function test_commit_duplicado_revierte() public {
        bytes32 id = _commit();
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.CommitmentExists.selector, id));
        core.commit{value: REWARD}(
            address(rc), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, bytes32(0)
        );
    }

    function test_commit_rechaza_recomputer_que_revierte() public {
        RevertingRecomputer bad = new RevertingRecomputer();
        vm.prank(agent);
        vm.expectRevert(DissentCore.RecomputerReverted.selector);
        core.commit{value: REWARD}(
            address(bad), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "x", DEPOSIT, WINDOW, bytes32(0)
        );
    }

    function test_la_accion_no_entra_en_la_identidad() public {
        vm.prank(agent);
        bytes32 id1 = core.commit{value: REWARD}(
            address(rc), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, bytes32(0)
        );
        // mismo todo, otra accion: mismo id -> tiene que revertir por duplicado
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.CommitmentExists.selector, id1));
        core.commit{value: REWARD}(
            address(rc), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "fold", DEPOSIT, WINDOW, bytes32(0)
        );
    }

    // ── challenge en dos fases ────────────────────────────────────────────────

    function test_challenge_exitoso_paga_recompensa_mas_deposito() public {
        bytes32 id = _commit();
        _reveal(id, alice, 50, "s1"); // 50 < 100 -> cruza el umbral
        assertEq(core.credits(alice), uint256(REWARD) + DEPOSIT);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
        assertEq(core.escrowed(), 0);
    }

    function test_challenge_fallido_pierde_el_deposito_y_deja_vivo_el_compromiso() public {
        bytes32 id = _commit();
        _reveal(id, alice, 150, "s1"); // 150 >= 100 -> no cruza
        assertEq(core.credits(alice), 0);
        assertEq(core.credits(agent), DEPOSIT);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open), "un fallido no cierra el compromiso");
    }

    function test_no_se_puede_revelar_antes_de_N_bloques() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() - 1);
        vm.prank(alice);
        vm.expectRevert();
        core.challengeReveal(id, _inputs(BASE), ev, "s");
    }

    function test_no_se_puede_revelar_pasada_la_ventana() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
        vm.prank(alice);
        vm.expectRevert();
        core.challengeReveal(id, _inputs(BASE), ev, "s");
    }

    function test_el_sello_esta_atado_al_retador() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        // alice sella
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        // bob copia el hash y sella igual, pero al revelar el seal no le da
        vm.prank(bob);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(bob);
        vm.expectRevert(DissentCore.SealMismatch.selector);
        core.challengeReveal(id, _inputs(BASE), ev, "s");
    }

    function test_el_segundo_ganador_recupera_su_deposito() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "a", alice));
        vm.prank(bob);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "b", bob));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice);
        core.challengeReveal(id, _inputs(BASE), ev, "a");
        vm.prank(bob);
        core.challengeReveal(id, _inputs(BASE), ev, "b");
        assertEq(core.credits(bob), DEPOSIT, "llego segundo, no hizo nada mal");
        assertEq(core.credits(alice), uint256(REWARD) + DEPOSIT);
    }

    function test_sello_vencido_pierde_el_deposito_y_va_al_agente() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
        core.sweepExpiredSeal(id, alice);
        assertEq(core.credits(agent), DEPOSIT);
        assertEq(core.credits(alice), 0);
    }

    function test_evidencia_rechazada_no_se_queda_con_el_deposito() public {
        RejectingRecomputer rr = new RejectingRecomputer();
        vm.prank(agent);
        bytes32 id = core.commit{value: REWARD}(
            address(rr), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "x", DEPOSIT, WINDOW, bytes32(0)
        );
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.EvidenceRejected.selector, bytes32("ALWAYS_NO")));
        core.challengeReveal(id, _inputs(BASE), ev, "s");
    }

    function test_inputs_que_no_coinciden_revierten() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice);
        vm.expectRevert();
        core.challengeReveal(id, _inputs(999), ev, "s");
    }

    // ── reclaim ───────────────────────────────────────────────────────────────

    function test_no_hay_salida_dentro_de_la_ventana() public {
        bytes32 id = _commit();
        vm.expectRevert(abi.encodeWithSelector(DissentCore.WindowStillOpen.selector, uint64(block.timestamp + WINDOW)));
        core.reclaim(id);
    }

    function test_reclaim_vencida_la_ventana() public {
        bytes32 id = _commit();
        vm.warp(block.timestamp + WINDOW);
        core.reclaim(id);
        assertEq(core.credits(agent), REWARD);
        assertEq(core.escrowed(), 0);
    }

    function test_un_sello_vivo_bloquea_el_reclaim() public {
        bytes32 id = _commit();
        bytes memory ev = abi.encode(int256(50));
        vm.prank(alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.warp(block.timestamp + WINDOW);
        vm.expectRevert();
        core.reclaim(id);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
        core.reclaim(id);
        assertEq(core.credits(agent), REWARD);
    }

    function test_reclaim_lo_puede_llamar_cualquiera_pero_paga_al_agente() public {
        bytes32 id = _commit();
        vm.warp(block.timestamp + WINDOW);
        vm.prank(bob);
        core.reclaim(id);
        assertEq(core.credits(agent), REWARD);
        assertEq(core.credits(bob), 0);
    }

    // ── no hay poder administrativo ───────────────────────────────────────────

    function test_no_existe_ninguna_funcion_de_retiro_administrativo() public view {
        // Si alguna de estas existiera, el contrato tendria el agujero de Once.
        string[6] memory prohibidas =
            ["withdraw(address,uint256)", "owner()", "transferOwnership(address)", "pause()", "rescue(address)", "sweep()"];
        for (uint256 i = 0; i < prohibidas.length; i++) {
            bytes4 sel = bytes4(keccak256(bytes(prohibidas[i])));
            (bool ok,) = address(core).staticcall(abi.encodeWithSelector(sel));
            assertFalse(ok, prohibidas[i]);
        }
    }

    function test_no_acepta_MON_suelto() public {
        vm.prank(alice);
        (bool ok,) = address(core).call{value: 1 ether}("");
        assertFalse(ok, "sin receive ni fallback");
    }

    // ── reentrada ─────────────────────────────────────────────────────────────

    function test_el_recomputer_no_puede_reentrar_escribiendo() public {
        ReentrantRecomputer rr = new ReentrantRecomputer(address(core));
        vm.prank(agent);
        bytes32 id = core.commit{value: REWARD}(
            address(rr), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "x", DEPOSIT, WINDOW, bytes32(0)
        );
        assertTrue(id != bytes32(0), "el commit paso: el STATICCALL impidio la escritura");
    }

    function test_un_agente_que_rechaza_MON_no_bloquea_los_challenges() public {
        RejectingAgent ra = new RejectingAgent();
        vm.deal(address(ra), 10 ether);
        bytes memory data = abi.encodeWithSelector(
            DissentCore.commit.selector,
            address(rc),
            _inputs(BASE),
            THRESHOLD,
            DissentCore.Comparator.AtLeast,
            "x",
            DEPOSIT,
            WINDOW,
            bytes32(0)
        );
        bytes memory ret = ra.commitOn{value: REWARD}(address(core), data);
        bytes32 id = abi.decode(ret, (bytes32));
        // un challenge FALLIDO acredita al agente; con pago push esto revertiria
        _reveal(id, alice, 150, "s1");
        assertEq(core.credits(address(ra)), DEPOSIT, "el credito quedo, sin transferir");
    }

    // ── la unica salida ───────────────────────────────────────────────────────

    function test_withdrawCredit_es_la_unica_salida() public {
        bytes32 id = _commit();
        _reveal(id, alice, 50, "s1");
        uint256 antes = alice.balance;
        vm.prank(alice);
        core.withdrawCredit();
        assertEq(alice.balance - antes, uint256(REWARD) + DEPOSIT);
        assertEq(core.credits(alice), 0);
        assertEq(address(core).balance, 0);
    }

    function test_la_plata_cuadra_siempre() public {
        bytes32 id1 = _commit();
        vm.prank(agent);
        bytes32 id2 = core.commit{value: REWARD}(
            address(rc), _inputs(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, bytes32("x")
        );
        _reveal(id1, alice, 50, "a");
        _reveal(id2, bob, 150, "b");
        uint256 sumaCreditos = core.credits(alice) + core.credits(bob) + core.credits(agent);
        assertEq(address(core).balance, core.escrowed() + sumaCreditos, "balance == escrowed + creditos");
    }
}
