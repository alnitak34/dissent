// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {MockRecomputer} from "./mocks/MockRecomputer.sol";
import {AlnitakRiverRecomputer} from "../src/adapters/AlnitakRiverRecomputer.sol";

/// @notice Commit 2: respaldo economico (MIN_GAS_BACKED_REWARD) y precio efectivo.
contract EconomicBackingTest is Test {
    DissentCore core;
    MockRecomputer rc;
    AlnitakRiverRecomputer al;
    address agent = makeAddr("agent");

    int256 constant BASE = 200;
    int256 constant THRESHOLD = 100;
    uint128 constant DEPOSIT = 0.1 ether;
    uint64 constant WINDOW = 1 hours;
    uint32 constant RGL = 1_000_000;
    uint32 constant VGL = 200_000;
    uint32 constant MEL = 64;

    function setUp() public {
        core = new DissentCore();
        rc = new MockRecomputer();
        al = new AlnitakRiverRecomputer();
        vm.deal(agent, 1000 ether);
    }

    function _commit(uint256 value, uint32 r, uint32 v, uint32 mel) internal returns (bytes32 id) {
        vm.prank(agent);
        id = core.commit{value: value}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, r, v, mel, bytes32(0)
        );
    }

    // ── precio efectivo segun block.basefee ──────────────────────────────────
    function test_basefee_cero_usa_reference() public {
        vm.fee(0);
        assertEq(core.effectiveReferenceGasPrice(), core.REFERENCE_GAS_PRICE());
        assertEq(core.REFERENCE_GAS_PRICE(), 100 gwei);
    }

    function test_basefee_igual_a_100gwei_usa_100gwei() public {
        vm.fee(100 gwei);
        assertEq(core.effectiveReferenceGasPrice(), 100 gwei);
    }

    function test_basefee_mayor_usa_basefee() public {
        vm.fee(250 gwei);
        assertEq(core.effectiveReferenceGasPrice(), 250 gwei);
    }

    // ── reward exacta vs exacta-1 ─────────────────────────────────────────────
    function test_reward_exacta_pasa() public {
        vm.fee(0); // precio = REFERENCE
        uint256 minR = core.minGasBackedReward(VGL, RGL, 32, MEL);
        bytes32 id = _commit(minR, RGL, VGL, MEL);
        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertEq(core.getCommitment(id).effectiveGasPrice, 100 gwei);
    }

    function test_reward_exacta_menos_uno_revierte() public {
        vm.fee(0);
        uint256 minR = core.minGasBackedReward(VGL, RGL, 32, MEL);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.RewardBelowGasBacking.selector, minR - 1, minR));
        core.commit{value: minR - 1}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, MEL, bytes32(0)
        );
    }

    // ── precio guardado y en la identidad ─────────────────────────────────────
    function test_precio_efectivo_queda_guardado() public {
        vm.fee(300 gwei);
        uint256 minR = core.minGasBackedReward(VGL, RGL, 32, MEL);
        bytes32 id = _commit(minR, RGL, VGL, MEL);
        assertEq(core.getCommitment(id).effectiveGasPrice, 300 gwei, "guarda max(100gwei, basefee)");
    }

    function test_precio_efectivo_cambia_el_id() public {
        // AISLAR el precio: MISMA recompensa en ambos commits (reward ya entra en
        // el id; si difiere, no aislaria el efecto del precio). Usamos una reward
        // suficiente para la basefee MAYOR (200 gwei), y el mismo timestamp/salt.
        vm.warp(1_000_000);
        vm.fee(200 gwei);
        uint256 reward = core.minGasBackedReward(VGL, RGL, 32, MEL); // sirve para ambas basefees

        // commit 1: basefee 120 gwei, misma reward
        vm.fee(120 gwei);
        vm.prank(agent);
        bytes32 id1 = core.commit{value: reward}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, MEL, bytes32(0)
        );
        // commit 2: basefee 200 gwei, MISMA reward, mismo timestamp/salt/params
        vm.fee(200 gwei);
        vm.prank(agent);
        bytes32 id2 = core.commit{value: reward}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, MEL, bytes32(0)
        );

        assertTrue(id1 != id2, "solo cambia el precio -> id distinto");
        assertEq(core.getCommitment(id1).effectiveGasPrice, 120 gwei, "id1 guarda 120");
        assertEq(core.getCommitment(id2).effectiveGasPrice, 200 gwei, "id2 guarda 200");
        // el timestamp fue el mismo, asi que windowEnds coincide: el unico cambio
        // real entre los dos ids es effectiveGasPrice.
        assertEq(core.getCommitment(id1).windowEnds, core.getCommitment(id2).windowEnds, "mismo windowEnds");

        // Prueba directa de computeCommitmentId: mismos argumentos salvo el precio.
        uint64 we = core.getCommitment(id1).windowEnds;
        bytes32 h = keccak256(abi.encode(BASE));
        assertTrue(
            core.computeCommitmentId(agent, address(rc), h, THRESHOLD, DissentCore.Comparator.AtLeast, uint128(reward), DEPOSIT, we, RGL, VGL, MEL, 120 gwei, bytes32(0))
                != core.computeCommitmentId(agent, address(rc), h, THRESHOLD, DissentCore.Comparator.AtLeast, uint128(reward), DEPOSIT, we, RGL, VGL, MEL, 200 gwei, bytes32(0)),
            "computeCommitmentId depende solo del precio aqui"
        );
    }

    function test_evento_CommitGasPolicy_exacto() public {
        vm.fee(150 gwei); // > 100 gwei -> effectiveGasPrice = 150 gwei
        uint256 effPrice = 150 gwei;
        uint256 totalGasBacking = core.txRequired(VGL, RGL, 32, MEL) + core.CHALLENGE_COMMIT_GAS();
        uint256 minReward = totalGasBacking * effPrice;

        // el id lo calculamos con los mismos parametros (reward = minReward exacta);
        // computeCommitmentId es view y toma `agent` como argumento, no msg.sender.
        uint64 we = uint64(block.timestamp) + WINDOW;
        bytes32 id = core.computeCommitmentId(
            agent, address(rc), keccak256(abi.encode(BASE)), THRESHOLD, DissentCore.Comparator.AtLeast,
            uint128(minReward), DEPOSIT, we, RGL, VGL, MEL, effPrice, bytes32(0)
        );
        vm.expectEmit(true, false, false, true, address(core));
        emit DissentCore.CommitGasPolicy(id, RGL, VGL, MEL, effPrice, totalGasBacking, minReward);
        vm.prank(agent);
        core.commit{value: minReward}(
            address(rc), abi.encode(BASE), THRESHOLD, DissentCore.Comparator.AtLeast, "call", DEPOSIT, WINDOW, RGL, VGL, MEL, bytes32(0)
        );
    }

    function test_suba_de_basefee_posterior_no_cambia_lo_guardado() public {
        vm.fee(100 gwei);
        uint256 minR = core.minGasBackedReward(VGL, RGL, 32, MEL);
        bytes32 id = _commit(minR, RGL, VGL, MEL);
        assertEq(core.getCommitment(id).effectiveGasPrice, 100 gwei);
        // la base fee sube DESPUES del commit: el valor guardado no se mueve.
        vm.fee(500 gwei);
        assertEq(core.getCommitment(id).effectiveGasPrice, 100 gwei, "el precio se fijo al commit");
    }

    // ── caso Alnitak: ~1.9143602 MON con V=100k, R=18M, inputs=352, maxEv=32 ────
    function test_alnitak_min_reward_referencia() public {
        vm.fee(0); // precio = 100 gwei
        uint256 minR = core.minGasBackedReward(100_000, 18_000_000, 352, 32);
        console.log("Alnitak minGasBackedReward (wei): %s", minR);
        // 18.943.602 gas de tx + 200.000 challengeCommit = 19.143.602 ; *100gwei
        assertEq(minR, 19_143_602 * uint256(100 gwei), "coincide con el calculo de diseno");
        // ~1.9143602 MON
        assertApproxEqAbs(minR, 1_914_360_200_000_000_000, 1e12, "~1.9143602 MON");
    }

    // ── el minimo NO incluye el deposito ──────────────────────────────────────
    function test_min_reward_no_incluye_deposito() public {
        vm.fee(0);
        // minGasBackedReward == totalGasBacking * precio, sin sumar DEPOSIT.
        uint256 minR = core.minGasBackedReward(VGL, RGL, 32, MEL);
        uint256 totalGasBacking = core.txRequired(VGL, RGL, 32, MEL) + core.CHALLENGE_COMMIT_GAS();
        assertEq(minR, totalGasBacking * 100 gwei, "solo gas, sin deposito");
    }

    // ── sin saturacion silenciosa (nunca trunca) ─────────────────────────────
    // vm.fee exige basefee < 2^64, asi que total(~2M)*basefee(<2^64) no puede
    // desbordar uint256 por este camino; el overflow real lo cubre el checked-mul
    // de Solidity 0.8 (Panic 0x11), no un cast. Aca probamos la propiedad
    // demostrable: en TODO el rango valido, el resultado es total*price EXACTO,
    // nunca un valor truncado por debajo.
    function testFuzz_sin_saturacion_silenciosa(uint256 basefee) public {
        basefee = bound(basefee, 100 gwei, type(uint64).max - 1);
        vm.fee(basefee);
        uint256 total = core.txRequired(VGL, RGL, 32, MEL) + core.CHALLENGE_COMMIT_GAS();
        uint256 expected = total * basefee; // checked; si desbordara, revertiria aca
        assertEq(core.minGasBackedReward(VGL, RGL, 32, MEL), expected, "sin truncar");
        assertGe(core.minGasBackedReward(VGL, RGL, 32, MEL), total * 100 gwei, "nunca por debajo del piso");
    }
}
