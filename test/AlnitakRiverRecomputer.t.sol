// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AlnitakRiverRecomputer} from "../src/AlnitakRiverRecomputer.sol";
import {DissentCore} from "../src/DissentCore.sol";

/// @notice El adaptador contra el Python de verdad, y el flujo entero de punta a
///         punta con el recalculador real.
///
/// Los valores esperados salen de strategy.py (alnitak34/poker-bot, 84dbf79),
/// recalculados en enteros con la misma aritmetica de punto fijo que usa este
/// contrato. Estan medidos, no elegidos.
contract AlnitakRiverRecomputerTest is Test {
    AlnitakRiverRecomputer rc;
    DissentCore core;

    address agent = makeAddr("agent");
    address alice = makeAddr("alice");

    // carta uint8 = rango*4 + palo, palo c=0 d=1 h=2 s=3
    uint8[2] holeA = [uint8(44), 48]; // Jc Qc
    uint8[5] boardA = [uint8(43), 52, 9, 27, 18]; // Ts Kc 2d 6s 4h
    uint256[3] mixA = [uint256(7190), 1690, 750]; // multi/small
    int256 constant ESPERADO_A = 200128647214854111;

    uint8[2] holeB = [uint8(47), 57]; // Js Ad
    uint8[5] boardB = [uint8(58), 26, 50, 59, 24]; // Ah 6h Qh As 6c
    uint256[3] mixB = [uint256(7190), 1690, 750];
    int256 constant ESPERADO_B = 900477401129943502;

    uint8[2] holeC = [uint8(20), 57]; // 5c Ad
    uint8[5] boardC = [uint8(52), 48, 47, 43, 10]; // Kc Qc Js Ts 2h
    uint256[3] mixC = [uint256(9660), 6670, 3450]; // raise/any
    int256 constant ESPERADO_C = 926316225165562913;

    function setUp() public {
        rc = new AlnitakRiverRecomputer();
        core = new DissentCore();
        vm.deal(agent, 100 ether);
        vm.deal(alice, 100 ether);
    }

    function _in(uint8[2] memory hole, uint8[5] memory board, uint256[3] memory mix, uint256 priceBp)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(AlnitakRiverRecomputer.Inputs({hole: hole, board: board, mixBp: mix, priceBp: priceBp}));
    }

    function _sealOf(bytes memory ev, bytes32 salt, address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(ev, salt, who));
    }

    // ── el valor base contra el Python ────────────────────────────────────────

    function test_base_spotA_igual_al_python() public view {
        int256 v = rc.recompute(_in(holeA, boardA, mixA, 2156), "");
        console.log("SPOT A  solidity=%s", uint256(v));
        assertEq(v, ESPERADO_A);
    }

    function test_base_spotB_igual_al_python() public view {
        int256 v = rc.recompute(_in(holeB, boardB, mixB, 2354), "");
        console.log("SPOT B  solidity=%s", uint256(v));
        assertEq(v, ESPERADO_B);
    }

    function test_base_spotC_igual_al_python() public view {
        int256 v = rc.recompute(_in(holeC, boardC, mixC, 2372), "");
        console.log("SPOT C  solidity=%s", uint256(v));
        assertEq(v, ESPERADO_C);
    }

    function test_es_determinista() public view {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        assertEq(rc.recompute(inp, ""), rc.recompute(inp, ""), "igualdad exacta, sin epsilon");
    }

    // ── la evidencia es una regla ─────────────────────────────────────────────

    function test_los_tres_tiers_son_la_lista_blanca_entera() public view {
        assertEq(rc.TIER_COUNT(), 3);
        for (uint256 t = 0; t < 3; t++) {
            (bool ok, bytes32 reason) = rc.validateEvidence("", abi.encode(t));
            assertTrue(ok, "los tres tiers son validos");
            assertEq(reason, bytes32(0));
        }
    }

    function test_un_tier_fuera_de_la_lista_se_rechaza() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence("", abi.encode(uint256(3)));
        assertFalse(ok);
        assertEq(reason, bytes32("UNKNOWN_TIER"));
    }

    function test_evidencia_con_largo_raro_se_rechaza() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence("", hex"deadbeef");
        assertFalse(ok);
        assertEq(reason, bytes32("EVIDENCE_BAD_LENGTH"));
    }

    function test_el_retador_no_puede_elegir_manos() public view {
        // una lista de combinaciones ya no es evidencia valida: 32 bytes o nada
        uint8[] memory manos = new uint8[](4);
        manos[0] = 54;
        manos[1] = 53;
        manos[2] = 58;
        manos[3] = 57;
        (bool ok,) = rc.validateEvidence("", abi.encode(manos));
        assertFalse(ok, "no se aceptan listas de manos");
    }

    /// @notice Los tres tiers sobre el spot A, con los numeros que de verdad dan.
    ///
    /// Nuestra mano es Jc Qc: carta alta K-Q-J-T-6, edge 0. El reparto medido,
    /// verificado tambien en Python:
    ///
    ///   BASE     990 combos  buckets {0:377, 1:492, 2:90, 3:31}  acc {0:537, resto 0}
    ///   MEDIUM   613 combos  buckets {0:  0, 1:492, 2:90, 3:31}  acc todo 0
    ///   LARGE    127 combos  buckets {0:  0, 1:  6, 2:90, 3:31}  acc todo 0
    ///   OVERBET  414 combos  buckets {0:377, 1:  6, 2: 0, 3:31}  acc {0:537, resto 0}
    ///
    /// De ahi salen dos hechos que NO son bugs y conviene tener presentes:
    ///
    ///   - MEDIUM y LARGE dan CERO. Con carta alta solo le ganamos al bucket 0,
    ///     y los dos tiers lo excluyen entero por definicion: exigen edge >= 1.
    ///     El modelo esta diciendo que contra un rival que ligo algo, una carta
    ///     alta no tiene equity. Es cierto, y hace que cualquier compromiso de
    ///     carta alta con umbral > 0 sea trivialmente retable.
    ///   - OVERBET da EXACTAMENTE el base. No es casualidad: incluye el bucket 0
    ///     completo, que es lo unico que aporta, y le toca el mismo peso 1-p1
    ///     porque en los dos casos hay algun bucket superior no vacio. Para esta
    ///     mano, proponer OVERBET es un challenge que no puede ganar nunca.
    function test_los_tres_tiers_sobre_el_spot_A() public view {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        int256 base = rc.recompute(inp, "");
        int256 t0 = rc.recompute(inp, abi.encode(uint256(0)));
        int256 t1 = rc.recompute(inp, abi.encode(uint256(1)));
        int256 t2 = rc.recompute(inp, abi.encode(uint256(2)));
        console.log("base   = %s", uint256(base));
        console.log("MEDIUM = %s", uint256(t0));
        console.log("LARGE  = %s", uint256(t1));
        console.log("OVERBET= %s", uint256(t2));
        assertEq(t0, 0, "MEDIUM excluye el bucket 0, que es lo unico que ganamos");
        assertEq(t1, 0, "LARGE tambien");
        assertEq(t2, base, "OVERBET incluye el bucket 0 con el mismo peso: da el base");
        assertLt(t0, base, "un tier de valor baja la equity de una carta alta");
    }

    function test_tierForPrice_usa_los_cortes_de_in_range() public view {
        assertEq(rc.tierForPrice(2156), rc.TIER_MEDIUM());
        assertEq(rc.tierForPrice(2800), rc.TIER_MEDIUM());
        assertEq(rc.tierForPrice(2801), rc.TIER_LARGE());
        assertEq(rc.tierForPrice(3330), rc.TIER_LARGE());
        assertEq(rc.tierForPrice(3331), rc.TIER_OVERBET());
    }

    function test_boardFloorCat_se_calcula_no_se_recibe() public view {
        assertEq(rc.boardFloorCat(boardA), 0, "board seco");
        assertEq(rc.boardFloorCat(boardB), 2, "AA66 en el board: dos pares");
        assertEq(rc.boardFloorCat(boardC), 0);
    }

    // ── gas ───────────────────────────────────────────────────────────────────

    function test_gas_del_base() public view {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        uint256 g0 = gasleft();
        rc.recompute(inp, "");
        console.log("recompute BASE (990 combos): %s gas", g0 - gasleft());
    }

    function test_gas_del_challenge() public view {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        bytes memory ev = abi.encode(uint256(1));
        uint256 g0 = gasleft();
        rc.recompute(inp, ev);
        console.log("recompute CHALLENGE (tier LARGE): %s gas", g0 - gasleft());
    }

    // ── el flujo entero con el recalculador real ──────────────────────────────

    function test_flujo_completo_challenge_exitoso() public {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        int256 base = rc.recompute(inp, "");
        int256 conLarge = rc.recompute(inp, abi.encode(uint256(1)));
        // umbral entre los dos: el base lo cumple, el tier LARGE no
        int256 umbral = (base + conLarge) / 2;
        assertGt(base, umbral);
        assertLt(conLarge, umbral);

        vm.prank(agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(rc), inp, umbral, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, bytes32(0)
        );
        DissentCore.Commitment memory c = core.getCommitment(id);
        assertEq(c.baseValue, base, "el nucleo calculo el base el mismo");
        console.log("baseGas medido por el nucleo (adaptador real): %s", c.baseGas);

        bytes memory ev = abi.encode(uint256(1));
        bytes32 sobre = _sealOf(ev, "sal", alice);
        vm.prank(alice);
        core.challengeCommit{value: 0.1 ether}(id, sobre);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        uint256 g0 = gasleft();
        vm.prank(alice);
        core.challengeReveal(id, inp, ev, "sal");
        console.log("challengeReveal exitoso, de punta a punta: %s gas", g0 - gasleft());

        assertEq(core.credits(alice), 1.1 ether);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
    }

    /// @dev El retador propone OVERBET, que sobre esta mano da exactamente el
    ///      base y por lo tanto sigue cumpliendo el umbral. Es un challenge
    ///      legitimo pero equivocado: pierde el deposito.
    function test_flujo_completo_challenge_fallido() public {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        int256 base = rc.recompute(inp, "");
        int256 conOverbet = rc.recompute(inp, abi.encode(uint256(2)));
        assertEq(conOverbet, base, "OVERBET no mueve el valor de esta mano");
        int256 umbral = base / 2; // el base lo cumple, y OVERBET tambien
        assertGt(base, umbral);

        vm.prank(agent);
        bytes32 id = core.commit{value: 1 ether}(
            address(rc), inp, umbral, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, bytes32(0)
        );
        bytes memory ev = abi.encode(uint256(2));
        vm.prank(alice);
        core.challengeCommit{value: 0.1 ether}(id, _sealOf(ev, "sal", alice));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        uint256 g0 = gasleft();
        vm.prank(alice);
        core.challengeReveal(id, inp, ev, "sal");
        console.log("challengeReveal fallido, de punta a punta: %s gas", g0 - gasleft());

        assertEq(core.credits(alice), 0, "perdio el deposito");
        assertEq(core.credits(agent), 0.1 ether);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
    }

    function test_gas_del_commit_con_el_adaptador_real() public {
        bytes memory inp = _in(holeA, boardA, mixA, 2156);
        uint256 g0 = gasleft();
        vm.prank(agent);
        core.commit{value: 1 ether}(
            address(rc), inp, 1, DissentCore.Comparator.AtLeast, "call", 0.1 ether, 1 days, bytes32("g")
        );
        console.log("commit de punta a punta con el adaptador real: %s gas", g0 - gasleft());
    }
}
