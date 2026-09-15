// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputer} from "../src/IRecomputer.sol";

/// @notice Adaptador honesto en el commit (recompute con evidencia vacia funciona)
///         y configurable en el challenge, para probar cada camino de fallo.
contract FaultRecomputer is IRecomputer {
    enum Mode {
        Honest, // recompute honesto: devuelve abi.decode(inputs)
        RecRevert, // recompute revierte
        RecBurn, // recompute quema todo el gas
        RecBomb, // recompute devuelve returndata enorme
        RecShort, // recompute devuelve < 32 bytes
        ValRevert, // validate revierte
        ValBurn, // validate quema todo el gas
        ValBadSize, // validate devuelve returndata != 64
        ValBadBool // validate devuelve bool no canonico (2)
    }

    Mode public mode;

    constructor(Mode m) {
        mode = m;
    }

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "fault.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external view returns (bool, bytes32) {
        if (evidence.length == 0) return (true, bytes32(0));
        if (mode == Mode.ValRevert) revert("val");
        if (mode == Mode.ValBurn) {
            _burn();
        }
        if (mode == Mode.ValBadSize) {
            assembly {
                return(0, 0x20)
            } // 32 bytes, no 64
        }
        if (mode == Mode.ValBadBool) {
            assembly {
                mstore(0, 2) // bool = 2, no canonico
                mstore(0x20, 0)
                return(0, 0x40)
            }
        }
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256) {
        if (evidence.length == 0) return abi.decode(inputs, (int256));
        if (mode == Mode.RecRevert) revert("rec");
        if (mode == Mode.RecBurn) {
            _burn();
        }
        if (mode == Mode.RecBomb) {
            assembly {
                return(0, 0x100000)
            } // 1 MiB
        }
        if (mode == Mode.RecShort) {
            assembly {
                return(0, 0x10)
            } // 16 bytes
        }
        return abi.decode(inputs, (int256)); // Honest: devuelve BASE=200 (ignora la evidencia)
    }

    function _burn() internal view {
        uint256 x;
        for (uint256 i = 0;; i++) {
            x = x + i + uint256(keccak256(abi.encode(x)));
            if (gasleft() < 2000) break; // por si el cap es generoso, corta cerca del fondo
        }
    }
}

/// @notice recompute honesto pero HAMBRIENTO: exige haber recibido al menos
///         `minGas` (confirma onchain cuanto gas le entregaron) y luego quema
///         casi todo, dejando apenas para retornar. Si el nucleo le entrega menos
///         que lo prometido, revierte -> se clasifica AdapterFault. Sirve para
///         probar que los chequeos inmediatos reservan el encode ademas de R.
contract GasHungryRecomputer is IRecomputer {
    uint256 public immutable minGas;

    constructor(uint256 mg) {
        minGas = mg;
    }

    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "hungry.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256) {
        if (evidence.length == 0) return abi.decode(inputs, (int256)); // commit: barato
        // AFIRMACION ONCHAIN: recibi al menos el limite prometido.
        require(gasleft() >= minGas, "UNDER_DELIVERED");
        uint256 x = 1;
        // quema casi todo lo entregado, dejando margen para RETORNAR 32 bytes.
        // Asignacion (no acumulacion) para no desbordar uint256.
        while (gasleft() > 50000) {
            x = uint256(keccak256(abi.encode(x)));
        }
        require(x != 0, "imposible"); // usa x, evita que el optimizador borre el bucle
        return abi.decode(inputs, (int256)); // = base
    }
}

/// @notice Devuelve como valor el gasleft() observado al comienzo de recompute.
///         Ese valor viaja en ChallengeFailed.newValue, y permite verificar que
///         el CALL entrego el limite R (el adaptador observa R menos su overhead
///         de entrada propio, medido, no un slack arbitrario).
contract RecomputeGasProbe is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "recprobe.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata) external pure returns (bool, bytes32) {
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256) {
        if (evidence.length == 0) return abi.decode(inputs, (int256)); // commit
        return int256(gasleft()); // >= 100 -> no cruza -> ChallengeFailed(newValue=gasleft)
    }
}

/// @notice Devuelve (false, bytes32(gasleft() al comienzo de validate)). El valor
///         viaja en ChallengeRejected.reason y permite verificar la entrega de V.
contract ValidateGasProbe is IRecomputer {
    function scale() external pure returns (uint256) {
        return 1e18;
    }

    function domain() external pure returns (bytes32) {
        return "valprobe.v1";
    }

    function validateEvidence(bytes calldata, bytes calldata evidence) external view returns (bool, bytes32) {
        if (evidence.length == 0) return (true, bytes32(0));
        return (false, bytes32(gasleft())); // rechazo canonico -> ChallengeRejected(reason=gasleft)
    }

    function recompute(bytes calldata inputs, bytes calldata) external pure returns (int256) {
        return abi.decode(inputs, (int256));
    }
}

contract AdapterFaultTest is Test {
    DissentCore core;
    address agent = makeAddr("agent");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint128 constant REWARD = 1 ether;
    uint128 constant DEPOSIT = 0.1 ether;
    uint64 constant WINDOW = 1 hours;
    int256 constant BASE = 200;
    int256 constant THRESHOLD = 100;
    uint32 constant RGL = 1_000_000;
    uint32 constant VGL = 300_000;
    uint32 constant MEL = 131_072; // MAX_EVIDENCE_LEN del protocolo: evidencia grande para starvation
    // Debe mantenerse alineado con ENTRY_OVERHEAD de DissentCore. En un test,
    // `{gas: ...}` limita una llamada interna y no reproduce el intrinseco de
    // una transaccion real; por eso estos casos usan floor + overhead de entrada,
    // no txRequired (que incluye calldata + 21k de la transaccion exterior).
    uint256 constant CORE_ENTRY_OVERHEAD = 80_000;

    function setUp() public {
        core = new DissentCore();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _sealOf(bytes memory ev, bytes32 salt, address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(ev, salt, who));
    }

    function _commit(FaultRecomputer rc, uint32 mel) internal returns (bytes32 id) {
        vm.prank(agent, agent);
        id = core.commit{value: REWARD}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, mel, bytes32(0)
        );
    }

    function _seal(bytes32 id, bytes memory ev) internal returns (uint256 selloEn) {
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        selloEn = vm.getBlockNumber();
        vm.roll(selloEn + core.REVEAL_DELAY_BLOCKS());
    }

    function _assertFaultedAtGas(bytes32 id, DissentCore.Phase phase, bytes memory ev, uint256 callGas) internal {
        _seal(id, ev);
        vm.expectEmit(true, true, false, true, address(core));
        emit DissentCore.AdapterFaulted(id, alice, phase, DEPOSIT, REWARD);
        vm.prank(alice, alice);
        core.challengeReveal{gas: callGas}(id, abi.encode(BASE), ev, "s");
        assertEq(core.credits(alice), DEPOSIT, "el retador solo recupera su deposito");
        assertEq(core.credits(agent), REWARD, "la recompensa vuelve al agente");
        assertEq(core.escrowed(), 0, "el fault liquida ambos principales");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Faulted));
        // sello settled: sweep no puede pagarle al agente tras el fault
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS() + 1);
        vm.expectRevert(DissentCore.NoSeal.selector);
        core.sweepExpiredSeal(id, alice);
    }

    function _assertFaulted(bytes32 id, DissentCore.Phase phase, bytes memory ev) internal {
        _assertFaultedAtGas(id, phase, ev, 30_000_000);
    }

    // ── faults de recompute ─────────────────────────────────────────────────
    function test_recompute_revierte_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.RecRevert), 64), DissentCore.Phase.RECOMPUTE, abi.encode(int256(50)));
    }

    function test_recompute_quema_gas_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.RecBurn), 64), DissentCore.Phase.RECOMPUTE, abi.encode(int256(50)));
    }

    function test_recompute_return_bomb_es_fault() public {
        // 1 MiB: el nucleo copia solo 32 bytes; el adaptador OOG al producirlo -> fault
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.RecBomb), 64), DissentCore.Phase.RECOMPUTE, abi.encode(int256(50)));
    }

    function test_recompute_returndata_corto_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.RecShort), 64), DissentCore.Phase.RECOMPUTE, abi.encode(int256(50)));
    }

    // ── faults de validate ──────────────────────────────────────────────────
    function test_validate_revierte_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.ValRevert), 64), DissentCore.Phase.VALIDATION, abi.encode(int256(50)));
    }

    function test_validate_quema_gas_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.ValBurn), 64), DissentCore.Phase.VALIDATION, abi.encode(int256(50)));
    }

    // ── liquidacion de fault con el presupuesto funcional minimo modelado ───
    // Estos dos casos ejercitan la rama mas cara para SETTLE_RESERVE: el
    // adaptador consume practicamente todo el cap y despues el nucleo debe aun
    // escribir DOS creditos (deposito al retador y reward al agente).
    function test_recompute_OOG_liquida_con_floor_mas_entry_overhead() public {
        bytes memory ev = abi.encode(int256(50));
        uint256 callGas = core.functionGasFloor(VGL, RGL, 32, ev.length) + CORE_ENTRY_OVERHEAD;
        _assertFaultedAtGas(
            _commit(new FaultRecomputer(FaultRecomputer.Mode.RecBurn), 64), DissentCore.Phase.RECOMPUTE, ev, callGas
        );
    }

    function test_validate_OOG_liquida_con_floor_mas_entry_overhead() public {
        bytes memory ev = abi.encode(int256(50));
        uint256 callGas = core.functionGasFloor(VGL, RGL, 32, ev.length) + CORE_ENTRY_OVERHEAD;
        _assertFaultedAtGas(
            _commit(new FaultRecomputer(FaultRecomputer.Mode.ValBurn), 64), DissentCore.Phase.VALIDATION, ev, callGas
        );
    }

    function test_validate_returndata_mal_tamano_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.ValBadSize), 64), DissentCore.Phase.VALIDATION, abi.encode(int256(50)));
    }

    function test_validate_bool_no_canonico_es_fault() public {
        _assertFaulted(_commit(new FaultRecomputer(FaultRecomputer.Mode.ValBadBool), 64), DissentCore.Phase.VALIDATION, abi.encode(int256(50)));
    }

    // ── adaptador honesto: NO fault ──────────────────────────────────────────
    function test_honesto_no_cruza_es_ChallengeFailed() public {
        // recompute honesto devuelve 50 >= 100? no -> _satisfies(50,100,AtLeast)=false -> cruza -> Challenged
        // Para probar ChallengeFailed necesitamos que SI cumpla: newValue=150 >= 100.
        FaultRecomputer rc = new FaultRecomputer(FaultRecomputer.Mode.Honest);
        bytes32 id = _commit(rc, 64);
        bytes memory ev = abi.encode(int256(150)); // recompute honesto lo ignora y devuelve inputs...
        // OJO: honest recompute devuelve abi.decode(inputs)=200 (BASE), no la evidencia.
        // 200 >= 100 -> cumple -> ChallengeFailed, deposito al agente.
        _seal(id, ev);
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), ev, "s");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open), "sigue Open");
        assertEq(core.credits(agent), DEPOSIT, "challenge fallido: deposito al agente");
        assertEq(core.credits(alice), 0);
    }

    // ── gas insuficiente del retador: revert, sin pago, sin fault ────────────
    function test_gas_insuficiente_revierte_sin_pago() public {
        FaultRecomputer rc = new FaultRecomputer(FaultRecomputer.Mode.Honest);
        bytes32 id = _commit(rc, 64);
        bytes memory ev = abi.encode(int256(50));
        _seal(id, ev);
        uint256 floor_ = core.functionGasFloor(VGL, RGL, 32, ev.length);

        // exacto - 1 (mas el intrinseco que forge cobra aparte): revierte
        vm.prank(alice, alice);
        vm.expectRevert(DissentCore.InsufficientChallengeGas.selector);
        core.challengeReveal{gas: floor_ - 1}(id, abi.encode(BASE), ev, "s");

        // nadie cobro, el compromiso sigue Open y el sello SIGUE VIVO (el revert
        // por gas del retador es su culpa; el sello sin liquidar lo barre el agente)
        assertEq(core.credits(alice), 0);
        assertEq(core.credits(agent), 0);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertFalse(core.getSeal(id, alice).settled, "sello sigue vivo tras el revert");
    }

    // ── evidence por encima del maximo declarado: revert ─────────────────────
    function test_evidence_sobre_el_maximo_revierte() public {
        FaultRecomputer rc = new FaultRecomputer(FaultRecomputer.Mode.Honest);
        bytes32 id = _commit(rc, 64); // maxEvidenceLen = 64
        bytes memory ev = new bytes(65); // 1 mas
        _seal(id, ev);
        vm.prank(alice, alice);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.EvidenceTooLong.selector, uint256(65), uint256(64)));
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), ev, "s");
    }

    // ── starvation: evidencia grande + adaptador que consume casi exactamente R,
    //    y CONFIRMA onchain que recibio >= R. Si el chequeo inmediato no reservara
    //    el encode, recompute recibiria < R, revertiria "UNDER_DELIVERED" y esto
    //    seria un AdapterFault. Con la reserva correcta: NO hay fault. ──────────────
    function test_starvation_no_produce_fault() public {
        // minGas = R - slack: exige haber recibido casi todo el limite prometido.
        GasHungryRecomputer rc = new GasHungryRecomputer(uint256(RGL) - 20_000);
        vm.prank(agent, agent);
        bytes32 id = core.commit{value: REWARD}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, MEL, bytes32(0)
        );
        bytes memory ev = new bytes(130_000); // grande, <= MEL
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());

        // gas de sobra: el CALL recibe R y el adaptador observa R menos su overhead
        // de entrada, aun con evidencia gigante -> require(gasleft>=minGas) pasa ->
        // resuelve normal (no fault). El gas ENTREGADO exacto lo miden los probes.
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), ev, "s");
        assertTrue(uint8(core.getCommitment(id).status) != uint8(DissentCore.Status.Faulted), "nunca Faulted por starvation");
        assertEq(core.credits(alice), 0, "el retador no cobra por starvation");
        assertEq(core.credits(agent), DEPOSIT, "challenge honesto fallido: deposito al agente");
    }

    // ── commit rechaza limites cuya TX completa supera 30M aunque el floor entre ─
    function test_commit_rechaza_si_tx_supera_30M_aunque_floor_entre() public {
        // Buscamos R tal que functionGasFloor <= 30M < txRequired (con maxEv=MAX).
        // Con maxEv=131072 el intrinseco del reveal ronda ~2.1M; elegimos R que deje
        // el floor apenas debajo de 30M pero la tx completa por encima.
        uint32 maxEv = 131_072;
        uint32 rBig = 27_000_000;
        uint256 floor_ = core.functionGasFloor(VGL, rBig, 32, maxEv);
        uint256 txReq = core.txRequired(VGL, rBig, 32, maxEv);
        assertLe(floor_, 30_000_000, "el floor aislado SI entra");
        assertGt(txReq, 30_000_000, "pero la tx completa NO");

        FaultRecomputer rc = new FaultRecomputer(FaultRecomputer.Mode.Honest); // crear ANTES del expectRevert
        vm.prank(agent, agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.GasLimitsTooLarge.selector, txReq, uint256(30_000_000)));
        core.commit{value: REWARD}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, rBig, VGL, maxEv, bytes32(0)
        );
    }

    // ── el peor caso ACEPTADO entra en 30M ───────────────────────────────────
    function test_peor_caso_aceptado_entra_en_30M() public {
        // Tomamos el R mas grande cuyo txRequired(maxEv) <= 30M y confirmamos que
        // el commit pasa (no revierte por gas).
        uint32 maxEv = 131_072;
        uint32 r = 25_500_000;
        assertLe(core.txRequired(VGL, r, 32, maxEv), 30_000_000, "cabe");
        // reward >= respaldo de gas para este R grande (~3 MON al precio piso).
        uint256 reward = core.minGasBackedReward(VGL, r, 32, maxEv);
        vm.deal(agent, reward + 1 ether);
        vm.prank(agent, agent);
        bytes32 id = core.commit{value: reward}(
            address(new FaultRecomputer(FaultRecomputer.Mode.Honest)),
            abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, r, VGL, maxEv, bytes32(0)
        );
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
    }

    // ── gas del reveal: suficiente completa, por debajo del floor se rechaza,
    //    y en ningun caso se clasifica como AdapterFault. NO afirma el borde
    //    exacto: functionGasFloor es una envolvente con margen, no el punto real
    //    de ejecucion. Dos sellos/compromisos independientes. ───────────────────
    function test_gas_suficiente_completa_insuficiente_rechaza_sin_fault() public {
        bytes memory ev = abi.encode(int256(50));
        uint256 floor_ = core.functionGasFloor(VGL, RGL, 32, ev.length);

        // Sello 1: gas claramente suficiente -> completa. El recompute honesto
        // devuelve BASE=200 >= 100, o sea NO cruza el umbral -> ChallengeFailed,
        // el compromiso sigue Open y el deposito va al agente.
        FaultRecomputer rc1 = new FaultRecomputer(FaultRecomputer.Mode.Honest);
        bytes32 id1 = _commit(rc1, 64);
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id1, _sealOf(ev, "s", alice));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id1, abi.encode(BASE), ev, "s");
        assertEq(uint8(core.getCommitment(id1).status), uint8(DissentCore.Status.Open));
        assertEq(core.credits(agent), DEPOSIT);

        // Sello 2, compromiso independiente: gas por debajo del floor -> se rechaza
        // (InsufficientChallengeGas), sin fault ni pago, sin reutilizar el sello 1.
        FaultRecomputer rc2 = new FaultRecomputer(FaultRecomputer.Mode.Honest);
        bytes32 id2 = _commit(rc2, 64);
        vm.prank(bob, bob);
        core.challengeCommit{value: DEPOSIT}(id2, _sealOf(ev, "s", bob));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());
        vm.prank(bob, bob);
        vm.expectRevert(DissentCore.InsufficientChallengeGas.selector);
        core.challengeReveal{gas: floor_ - 1}(id2, abi.encode(BASE), ev, "s");
        assertEq(core.credits(bob), 0, "no cobro");
        assertTrue(uint8(core.getCommitment(id2).status) != uint8(DissentCore.Status.Faulted), "no fault");
    }

    // ── retador void: no da inputs, no paga floor V+R, no llama al adaptador ──
    function test_retador_void_recupera_deposito_barato() public {
        // Adaptador que REVIERTE en recompute de challenge: el PRIMER retador lo
        // dispara y queda AdapterFault (resuelve, sale de Open). Si el void del
        // SEGUNDO llamara al adaptador, este revertiria de nuevo -> AdapterFault en
        // vez de ChallengeVoided. Que sea Voided prueba que NO se llamo al adaptador.
        FaultRecomputer rc = new FaultRecomputer(FaultRecomputer.Mode.RecRevert);
        bytes32 id = _commit(rc, 64);
        bytes memory ev = abi.encode(int256(50));

        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "a", alice));
        vm.prank(bob, bob);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "b", bob));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());

        // primero: alice dispara el fault -> status Faulted, sale de Open
        vm.prank(alice, alice);
        core.challengeReveal{gas: 30_000_000}(id, abi.encode(BASE), ev, "a");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Faulted));

        // bob quedo void. Revela con gas MUY por debajo del floor de V+R: como el
        // void cortocircuita antes del piso y del adaptador, completa igual.
        uint256 floor_ = core.functionGasFloor(VGL, RGL, 32, ev.length);
        assertGt(floor_, 400_000, "el floor es mucho mayor que el gas de bob");
        vm.expectEmit(true, true, false, true, address(core));
        emit DissentCore.ChallengeVoided(id, bob, "ALREADY_RESOLVED");
        vm.prank(bob, bob);
        core.challengeReveal{gas: 400_000}(id, abi.encode(BASE), ev, "b");
        assertEq(core.credits(bob), DEPOSIT, "el void recupera su deposito");
    }

    // ── gas REALMENTE entregado al adaptador (probes) ────────────────────────
    // El adaptador observa gasleft() al entrar. Verificamos:
    //  (a) observado <= R (nunca mas que el limite), y R - observado es un
    //      overhead de entrada del callee CHICO y ESTABLE (no crece con la
    //      evidencia): el CALL entrega R, la evidencia grande no lo reduce.
    uint256 constant CALLEE_ENTRY_MAX = 3000; // cota medida del overhead de entrada del callee

    function _commitProbe(address rc, uint32 r, uint32 v, uint32 mel) internal returns (bytes32 id) {
        vm.prank(agent, agent);
        id = core.commit{value: REWARD}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, r, v, mel, bytes32(0)
        );
    }

    // devuelve el gasleft observado por recompute, leido de ChallengeFailed.newValue
    function _observedRecomputeGas(bytes32 id, bytes memory ev, uint256 txGas) internal returns (uint256) {
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());
        vm.recordLogs();
        vm.prank(alice, alice);
        core.challengeReveal{gas: txGas}(id, abi.encode(BASE), ev, "s");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ChallengeFailed(bytes32,address,int256,int256,bytes32)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == sig) {
                (int256 nv,,) = abi.decode(logs[i].data, (int256, int256, bytes32));
                return uint256(nv);
            }
        }
        revert("sin ChallengeFailed");
    }

    function _observedValidateGas(bytes32 id, bytes memory ev, uint256 txGas) internal returns (uint256) {
        vm.prank(alice, alice);
        core.challengeCommit{value: DEPOSIT}(id, _sealOf(ev, "s", alice));
        vm.roll(vm.getBlockNumber() + core.REVEAL_DELAY_BLOCKS());
        vm.recordLogs();
        vm.prank(alice, alice);
        core.challengeReveal{gas: txGas}(id, abi.encode(BASE), ev, "s");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ChallengeRejected(bytes32,address,bytes32)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == sig) {
                return uint256(abi.decode(logs[i].data, (bytes32)));
            }
        }
        revert("sin ChallengeRejected");
    }

    function test_recompute_recibe_R_menos_overhead_de_entrada() public {
        uint32 R = 1_000_000;
        uint32 V = 500_000;
        uint32 mel = 131_072;
        bytes memory small = abi.encode(int256(50)); // 32 B
        bytes memory big = new bytes(130_000); // cerca de MAX

        // control 30M
        uint256 oSmall = _observedRecomputeGas(_commitProbe(address(new RecomputeGasProbe()), R, V, mel), small, 30_000_000);
        uint256 oBig = _observedRecomputeGas(_commitProbe(address(new RecomputeGasProbe()), R, V, mel), big, 30_000_000);
        // gas total conservador minimo (el txRequired del propio contrato)
        uint256 minGasSmall = core.txRequired(V, R, 32, small.length);
        uint256 minGasBig = core.txRequired(V, R, 32, big.length);
        uint256 oSmallMin = _observedRecomputeGas(_commitProbe(address(new RecomputeGasProbe()), R, V, mel), small, minGasSmall);
        uint256 oBigMin = _observedRecomputeGas(_commitProbe(address(new RecomputeGasProbe()), R, V, mel), big, minGasBig);

        console.log("recompute observado: small30M=%s big30M=%s", oSmall, oBig);
        console.log("recompute observado: smallMin=%s bigMin=%s", oSmallMin, oBigMin);
        assertLe(oSmall, R, "nunca mas que R");
        assertGe(oSmall, R - CALLEE_ENTRY_MAX, "R menos overhead de entrada chico");
        assertGe(oBig, R - CALLEE_ENTRY_MAX, "evidencia grande NO reduce la entrega");
        assertGe(oBigMin, R - CALLEE_ENTRY_MAX, "ni con gas total minimo");
        // la evidencia grande no cambia la entrega mas alla del ruido de entrada
        assertApproxEqAbs(oBig, oSmall, CALLEE_ENTRY_MAX, "entrega estable vs longitud");
    }

    function test_validate_recibe_V_menos_overhead_de_entrada() public {
        uint32 R = 1_000_000;
        uint32 V = 500_000;
        uint32 mel = 131_072;
        bytes memory small = abi.encode(int256(50));
        bytes memory big = new bytes(130_000);

        uint256 oSmall = _observedValidateGas(_commitProbe(address(new ValidateGasProbe()), R, V, mel), small, 30_000_000);
        uint256 oBig = _observedValidateGas(_commitProbe(address(new ValidateGasProbe()), R, V, mel), big, 30_000_000);
        uint256 oBigMin =
            _observedValidateGas(_commitProbe(address(new ValidateGasProbe()), R, V, mel), big, core.txRequired(V, R, 32, big.length));

        console.log("validate observado: small30M=%s big30M=%s bigMin=%s", oSmall, oBig, oBigMin);
        assertLe(oSmall, V, "nunca mas que V");
        assertGe(oSmall, V - CALLEE_ENTRY_MAX, "V menos overhead de entrada chico");
        assertGe(oBig, V - CALLEE_ENTRY_MAX, "evidencia grande NO reduce la entrega");
        assertGe(oBigMin, V - CALLEE_ENTRY_MAX, "ni con gas total minimo");
        assertApproxEqAbs(oBig, oSmall, CALLEE_ENTRY_MAX, "entrega estable vs longitud");
    }
}
