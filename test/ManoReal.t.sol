// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";
import {DissentCore} from "../src/DissentCore.sol";

/// @notice Los bytes LITERALES que escupio bridge/armar_commit.py, sin reconstruir.
///
/// Los otros tests arman los inputs con abi.encode() desde campos sueltos, asi que
/// prueban el contrato pero no prueban el puente: si el encoder de Python metiera
/// las palabras en otro orden, no se enterarian. Aca la constante de abajo es la
/// salida de
///
///     python bridge/armar_commit.py cmtr0ktvzxa5q15he4ekev8ub 29
///
/// copiada tal cual. Si el puente cambia como codifica, este test se cae.
///
/// La mano: Qd Ad en 2s 2c Tc Qc 9d, heads-up, con 45 fichas a pagar sobre un bote
/// de 79. El rival apostó 45 sobre un bote previo de 34 (132% del bote) en una sola
/// calle -> presion `bet/big`. Cualquiera puede bajarla, sin credenciales, en
/// https://arena.dev.fun/api/arena.getTexasReplay?input={"json":{"tableId":"cmtr0ktvzxa5q15he4ekev8ub"}}
/// y comprobar con bridge/verificar.py que estos bytes son esa mano.
contract ManoRealTest is Test {
    AlnitakRiverRecomputer rc;
    DissentCore core;

    address agent = makeAddr("agent");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    /// @dev Pegado de la salida de bridge/armar_commit.py. NO tocar a mano.
    bytes constant INPUTS =
        hex"0000000000000000000000000000000000000000000000000000000000000031"
        hex"0000000000000000000000000000000000000000000000000000000000000039"
        hex"000000000000000000000000000000000000000000000000000000000000000b"
        hex"0000000000000000000000000000000000000000000000000000000000000008"
        hex"0000000000000000000000000000000000000000000000000000000000000028"
        hex"0000000000000000000000000000000000000000000000000000000000000030"
        hex"0000000000000000000000000000000000000000000000000000000000000025"
        hex"0000000000000000000000000000000000000000000000000000000000002026"
        hex"0000000000000000000000000000000000000000000000000000000000000ac8"
        hex"0000000000000000000000000000000000000000000000000000000000000672"
        hex"0000000000000000000000000000000000000000000000000000000000000e2d";

    bytes32 constant INPUTS_HASH = 0xa174393d39f1e1ec234522a9c80f28e565e8b9908e567c452065e156f56a73ac;

    // Los valores del Python, en la misma aritmetica entera que usa el contrato.
    int256 constant BASE = 685725947521865889; // evidencia vacia: el planteo completo
    int256 constant V_MEDIUM = 673341107871720116;
    int256 constant V_LARGE = 0;
    int256 constant V_OVERBET = 177000000000000000;

    // El umbral que declara el agente: el precio, 3629 bp llevado a WAD.
    int256 constant UMBRAL = 362900000000000000;

    function setUp() public {
        rc = new AlnitakRiverRecomputer();
        core = new DissentCore();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _sealOf(bytes memory ev, bytes32 salt, address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(ev, salt, who));
    }

    // ── que los bytes SON la mano ─────────────────────────────────────────────

    /// @dev El keccak256 que imprime el puente, calculado en python puro, tiene que
    ///      ser el mismo que el de la EVM. Es el hash que DissentCore guarda como
    ///      inputsHash y contra el que valida cada reveal.
    function test_el_keccak_del_puente_es_el_de_la_evm() public pure {
        assertEq(keccak256(INPUTS), INPUTS_HASH);
    }

    function test_los_bytes_decodifican_a_la_mano() public view {
        AlnitakRiverRecomputer.Inputs memory p = rc.decodeInputs(INPUTS);
        assertEq(INPUTS.length, 352, "11 palabras planas, sin offsets");

        assertEq(p.hole[0], 49, "Qd = 12*4 + 1");
        assertEq(p.hole[1], 57, "Ad = 14*4 + 1");
        assertEq(p.board[0], 11, "2s");
        assertEq(p.board[1], 8, "2c");
        assertEq(p.board[2], 40, "Tc");
        assertEq(p.board[3], 48, "Qc");
        assertEq(p.board[4], 37, "9d");

        assertEq(p.mixBp[0], 8230, "bet/big p1");
        assertEq(p.mixBp[1], 2760, "bet/big p2");
        assertEq(p.mixBp[2], 1650, "bet/big p3");
        assertEq(p.priceBp, 3629, "45 / (79+45), truncado a bp");
    }

    /// @dev El board trae 2s 2c: un par servido. El contrato lo CALCULA; si lo
    ///      recibiera, el agente podria declarar 0 y ensanchar todos los buckets.
    function test_el_floor_del_board_se_calcula() public view {
        AlnitakRiverRecomputer.Inputs memory p = rc.decodeInputs(INPUTS);
        assertEq(rc.boardFloorCat(p.board), 1, "22 en el board: un par gratis para todos");
    }

    /// @dev 3629 bp cae del lado de OVERBET. Informativo: el retador puede proponer
    ///      cualquiera de los tres, no solo este.
    function test_el_precio_de_la_mano_implica_overbet() public view {
        assertEq(rc.tierForPrice(3629), rc.TIER_OVERBET());
    }

    // ── el numero ─────────────────────────────────────────────────────────────

    /// @dev EL TEST DEL PUNTO 4: los bytes del puente, adentro del adaptador, dan
    ///      el mismo numero que _exact_river_mix() de strategy.py sobre esta mano.
    function test_recompute_sobre_los_bytes_del_puente_da_el_valor_del_python() public view {
        int256 v = rc.recompute(INPUTS, "");
        console.log("mano real, evidencia vacia: solidity=%s", uint256(v));
        console.log("                            python  =%s", uint256(BASE));
        assertEq(v, BASE, "el puente y el adaptador tienen que dar el mismo numero");
    }

    function test_los_tres_tiers_sobre_la_mano_real() public view {
        assertEq(rc.recompute(INPUTS, abi.encode(uint256(0))), V_MEDIUM, "MEDIUM");
        assertEq(rc.recompute(INPUTS, abi.encode(uint256(1))), V_LARGE, "LARGE");
        assertEq(rc.recompute(INPUTS, abi.encode(uint256(2))), V_OVERBET, "OVERBET");
    }

    /// @dev Con Qd Ad sobre 2s2c Tc Qc 9d tenemos dobles parejas Q y 2. Restringir
    ///      al rival a LARGE (edge >= 2, o sea al menos dobles parejas por encima
    ///      del par del board, o un overpair) lo deja con nada que no nos gane: el
    ///      valor cae a cero exacto, no a "casi cero".
    function test_largo_deja_el_valor_en_cero_exacto() public view {
        assertEq(rc.recompute(INPUTS, abi.encode(uint256(1))), 0);
    }

    // ── el flujo, sobre la mano real ──────────────────────────────────────────

    function test_commit_de_la_mano_real() public {
        vm.prank(agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(rc),
            INPUTS,
            UMBRAL,
            DissentCore.Comparator.AtLeast,
            "river call QdAd vs 2s 2c Tc Qc 9d @ cmtr0ktvzxa5q15he4ekev8ub#29",
            0.1 ether,
            1 days,
            20_000_000,
            100_000,
            32,
            bytes32(0)
        );
        DissentCore.Commitment memory c = core.getCommitment(id);
        assertEq(c.inputsHash, INPUTS_HASH, "el nucleo guarda el hash que imprime el puente");
        assertEq(c.baseValue, BASE);
        assertEq(c.threshold, UMBRAL);
        assertGt(c.baseValue, c.threshold, "0.6857 >= 0.3629: el compromiso se sostiene");
    }

    /// @dev El retador propone OVERBET, el tier que el propio precio implica. El
    ///      valor cae de 0.6857 a 0.1770, por debajo del 0.3629 que hace falta para
    ///      pagar: el challenge triunfa.
    function test_overbet_tumba_el_compromiso() public {
        vm.prank(agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(rc), INPUTS, UMBRAL, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, 20_000_000, 100_000, 32, bytes32(0)
        );
        bytes memory ev = abi.encode(uint256(2));
        vm.prank(alice);
        core.challengeCommit{value: 0.1 ether}(id, _sealOf(ev, "sal", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(alice);
        core.challengeReveal(id, INPUTS, ev, "sal");

        assertEq(core.credits(alice), 1.1 ether, "se lleva la recompensa y su deposito");
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
    }

    /// @dev Y el mismo compromiso resiste MEDIUM: 0.6733 sigue por encima de
    ///      0.3629. El contrato no le da la plata a cualquiera que se presente.
    function test_medium_no_tumba_el_compromiso() public {
        vm.prank(agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(rc), INPUTS, UMBRAL, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, 20_000_000, 100_000, 32, bytes32(0)
        );
        bytes memory ev = abi.encode(uint256(0));
        vm.prank(bob);
        core.challengeCommit{value: 0.1 ether}(id, _sealOf(ev, "sal", bob));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(bob);
        core.challengeReveal(id, INPUTS, ev, "sal");

        assertEq(core.credits(bob), 0, "perdio el deposito");
        assertEq(core.credits(agent), 0.1 ether);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
    }
}
