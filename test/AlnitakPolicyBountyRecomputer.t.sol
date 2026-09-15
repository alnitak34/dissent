// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";
import {DissentCore} from "../src/DissentCore.sol";

contract AlnitakPolicyBountyRecomputerTest is Test {
    AlnitakPolicyBountyRecomputer internal rc;
    DissentCore internal core;
    address internal agent = makeAddr("policy-agent");
    address internal challenger = makeAddr("policy-challenger");

    bytes32 internal constant POLICY_HASH = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0;
    bytes20 internal constant ORIGIN = hex"e6a7e49857602ac84257dc78f0960506f87cd7f3";

    function setUp() public {
        rc = new AlnitakPolicyBountyRecomputer();
        core = new DissentCore();
        vm.deal(agent, 100 ether);
        vm.deal(challenger, 100 ether);
    }

    function _inputs() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.PolicyInputs({
                policySpecHash: POLICY_HASH, originCommit: ORIGIN, marginBp: 1500
            })
        );
    }

    function _jhjd() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"030f000000000000",
                traceLength: 2
            })
        );
    }

    function _control() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"123a380e192a20",
                potFacingDecision: 486,
                callAmount: 162,
                aggressiveTrace: hex"0506070000000000",
                traceLength: 3
            })
        );
    }

    function _qhjs() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"322f1e1f332a08",
                potFacingDecision: 132,
                callAmount: 51,
                aggressiveTrace: hex"0102030f00000000",
                traceLength: 4
            })
        );
    }

    function _ac8c() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"3820371e153026",
                potFacingDecision: 450,
                callAmount: 225,
                aggressiveTrace: hex"0106070000000000",
                traceLength: 3
            })
        );
    }

    function _relaxedFallbackRegression() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"080d3a34322e2b",
                potFacingDecision: 70,
                callAmount: 30,
                aggressiveTrace: hex"030f000000000000",
                traceLength: 2
            })
        );
    }

    function test_identidad_y_base_canonicas() public view {
        assertEq(rc.POLICY_SPEC_HASH(), POLICY_HASH);
        assertEq(rc.ORIGIN_COMMIT(), ORIGIN);
        assertEq(rc.canonicalInputs(), _inputs());
        assertEq(rc.scale(), 1);
        assertEq(rc.domain(), bytes32("alnitak.river.safety.v1"));
        assertEq(rc.recompute(_inputs(), ""), 0);
    }

    function test_jhjd_reproduce_el_contraejemplo_exacto() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), _jhjd());
        assertTrue(ok);
        assertEq(reason, bytes32(0));

        AlnitakPolicyBountyRecomputer.Evaluation memory value = rc.evaluate(_inputs(), _jhjd());
        assertEq(value.oldEquityWad, 568_941_504_178_272_980);
        assertEq(value.conditionedEquityWad, 320_045_667_447_306_791);
        assertEq(value.thresholdWad, 424_170_274_170_274_170);
        assertEq(value.pressure, 3, "raise/any");
        assertTrue(value.oldAuthorizes);
        assertFalse(value.conditionedAuthorizes);
        assertTrue(value.violation);
        assertEq(rc.recompute(_inputs(), _jhjd()), 1);
    }

    function test_4hah_es_control_positivo_no_condenado() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), _control());
        assertTrue(ok);
        assertEq(reason, bytes32(0));

        AlnitakPolicyBountyRecomputer.Evaluation memory value = rc.evaluate(_inputs(), _control());
        assertEq(value.oldEquityWad, 730_375_426_621_160_409);
        assertEq(value.conditionedEquityWad, 772_440_501_043_841_336);
        assertEq(value.thresholdWad, 400_000_000_000_000_000);
        assertEq(value.pressure, 1, "multi/small");
        assertTrue(value.oldAuthorizes);
        assertTrue(value.conditionedAuthorizes);
        assertFalse(value.violation);
        assertEq(rc.recompute(_inputs(), _control()), 0);
    }

    function test_qhjs_del_corpus_es_un_segundo_contraejemplo() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), _qhjs());
        assertTrue(ok);
        assertEq(reason, bytes32(0));

        AlnitakPolicyBountyRecomputer.Evaluation memory value = rc.evaluate(_inputs(), _qhjs());
        assertEq(value.oldEquityWad, 706_278_026_905_829_596);
        assertEq(value.conditionedEquityWad, 301_571_022_727_272_727);
        assertEq(value.thresholdWad, 428_688_524_590_163_934);
        assertEq(value.pressure, 3, "raise/any");
        assertTrue(value.oldAuthorizes);
        assertFalse(value.conditionedAuthorizes);
        assertTrue(value.violation);
        assertEq(rc.recompute(_inputs(), _qhjs()), 1);
    }

    function test_ac8c_del_corpus_es_un_tercer_contraejemplo() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), _ac8c());
        assertTrue(ok);
        assertEq(reason, bytes32(0));

        AlnitakPolicyBountyRecomputer.Evaluation memory value = rc.evaluate(_inputs(), _ac8c());
        assertEq(value.oldEquityWad, 818_734_793_187_347_931);
        assertEq(value.conditionedEquityWad, 79_284_931_506_849_315);
        assertEq(value.thresholdWad, 483_333_333_333_333_333);
        assertEq(value.pressure, 2, "multi/big");
        assertTrue(value.oldAuthorizes);
        assertFalse(value.conditionedAuthorizes);
        assertTrue(value.violation);
        assertEq(rc.recompute(_inputs(), _ac8c()), 1);
    }

    function test_fallback_relajado_reproduce_e6a7e49_y_no_inventa_violacion() public view {
        AlnitakPolicyBountyRecomputer.Evaluation memory value = rc.evaluate(_inputs(), _relaxedFallbackRegression());
        assertEq(value.oldEquityWad, 0, "45 combos relaxed all beat hero");
        assertEq(value.conditionedEquityWad, 17_000_000_000_000_000);
        assertEq(value.thresholdWad, 450_000_000_000_000_000);
        assertFalse(value.oldAuthorizes);
        assertFalse(value.conditionedAuthorizes);
        assertFalse(value.violation);
        assertEq(rc.recompute(_inputs(), _relaxedFallbackRegression()), 0);
    }

    function test_no_acepta_identidad_de_politica_alterada() public view {
        bytes memory bad = abi.encode(
            AlnitakPolicyBountyRecomputer.PolicyInputs({
                policySpecHash: bytes32(uint256(1)), originCommit: ORIGIN, marginBp: 1500
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(bad, _jhjd());
        assertFalse(ok);
        assertEq(reason, bytes32("BAD_POLICY_INPUTS"));
    }

    function test_no_acepta_cartas_duplicadas() public view {
        bytes memory duplicate = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2e14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"030f000000000000",
                traceLength: 2
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), duplicate);
        assertFalse(ok);
        assertEq(reason, bytes32("INVALID_CARDS"));
    }

    function test_no_acepta_single_small_bet() public view {
        bytes memory outside = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"123a380e192a20",
                potFacingDecision: 486,
                callAmount: 162,
                aggressiveTrace: hex"0700000000000000",
                traceLength: 1
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), outside);
        assertFalse(ok);
        assertEq(reason, bytes32("OUTSIDE_HIGH_PRESSURE"));
    }

    function test_no_acepta_raise_sin_apuesta_anterior() public view {
        bytes memory impossible = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"0f00000000000000",
                traceLength: 1
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), impossible);
        assertFalse(ok);
        assertEq(reason, bytes32("INVALID_TRACE"));
    }

    function test_no_acepta_dos_bets_en_la_misma_calle() public view {
        bytes memory impossible = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"0307000000000000",
                traceLength: 2
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), impossible);
        assertFalse(ok);
        assertEq(reason, bytes32("INVALID_TRACE"));
    }

    function test_no_acepta_raise_del_mismo_actor() public view {
        bytes memory impossible = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"070f000000000000",
                traceLength: 2
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), impossible);
        assertFalse(ok);
        assertEq(reason, bytes32("INVALID_TRACE"));
    }

    function test_no_acepta_eventos_despues_de_all_in() public view {
        bytes memory impossible = abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2d14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"1607000000000000",
                traceLength: 2
            })
        );
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), impossible);
        assertFalse(ok);
        assertEq(reason, bytes32("INVALID_TRACE"));
    }

    function _dirtyEvidence() internal pure returns (bytes memory) {
        bytes32 dirtyCards = bytes32(uint256(bytes32(hex"2e2d14270a1a10")) | 1);
        return abi.encode(dirtyCards, uint256(503), uint256(190), bytes32(hex"030f000000000000"), uint256(2));
    }

    function test_padding_sucio_se_rechaza_sin_revertir() public view {
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), _dirtyEvidence());
        assertFalse(ok);
        assertEq(reason, bytes32("NON_CANONICAL_EVIDENCE"));
    }

    function testFuzz_validateEvidence_no_revierte_con_160_bytes(
        bytes32 cardsWord,
        uint256 potWord,
        uint256 callWord,
        bytes32 traceWord,
        uint256 traceLengthWord
    ) public view {
        bytes memory arbitraryEvidence = abi.encode(cardsWord, potWord, callWord, traceWord, traceLengthWord);
        (bool callOk, bytes memory returned) = address(rc)
            .staticcall(abi.encodeCall(AlnitakPolicyBountyRecomputer.validateEvidence, (_inputs(), arbitraryEvidence)));
        assertTrue(callOk, "invalid challenger bytes must not become AdapterFault");
        assertEq(returned.length, 64, "canonical (bool,bytes32) return");
    }

    function test_gas_recompute_de_los_dos_casos() public view {
        uint256 start = gasleft();
        rc.recompute(_inputs(), _jhjd());
        uint256 jhjdGas = start - gasleft();

        start = gasleft();
        rc.recompute(_inputs(), _control());
        uint256 controlGas = start - gasleft();
        console.log("policy bounty JhJd recompute gas: %s", jhjdGas);
        console.log("policy bounty 4hAh recompute gas: %s", controlGas);
    }

    function test_flujo_completo_paga_el_contraejemplo() public {
        bytes memory inputs = _inputs();
        bytes memory evidence = _jhjd();
        uint128 deposit = 0.1 ether;
        uint256 txRequired = core.txRequired(100_000, 20_000_000, inputs.length, 160);
        uint256 minReward = core.minGasBackedReward(100_000, 20_000_000, inputs.length, 160);
        assertLe(txRequired, core.MONAD_TX_GAS_LIMIT());
        assertLe(minReward, 3 ether);
        console.log("policy bounty txRequired: %s", txRequired);
        console.log("policy bounty min reward: %s", minReward);

        vm.prank(agent);
        bytes32 id = core.commit{value: 3 ether}(
            address(rc),
            inputs,
            0,
            DissentCore.Comparator.AtMost,
            "Alnitak River Safety Reference v1",
            deposit,
            1 days,
            20_000_000,
            100_000,
            160,
            bytes32("policy-demo")
        );
        assertEq(core.getCommitment(id).baseValue, 0);

        bytes32 revealSalt = bytes32("counterexample");
        bytes32 seal = keccak256(abi.encode(evidence, revealSalt, challenger));
        vm.prank(challenger);
        core.challengeCommit{value: deposit}(id, seal);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());

        uint256 start = gasleft();
        vm.prank(challenger);
        core.challengeReveal{gas: 30_000_000}(id, inputs, evidence, revealSalt);
        console.log("policy bounty full reveal gas: %s", start - gasleft());

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
        assertEq(core.credits(challenger), 3.1 ether);
        assertEq(core.credits(agent), 0);
    }

    function test_evidencia_no_canonica_no_roba_la_recompensa() public {
        bytes memory inputs = _inputs();
        bytes memory evidence = _dirtyEvidence();
        uint128 deposit = 0.1 ether;

        vm.prank(agent);
        bytes32 id = core.commit{value: 3 ether}(
            address(rc),
            inputs,
            0,
            DissentCore.Comparator.AtMost,
            "Alnitak River Safety Reference v1",
            deposit,
            1 days,
            20_000_000,
            100_000,
            160,
            bytes32("dirty-evidence")
        );

        bytes32 revealSalt = bytes32("dirty");
        vm.prank(challenger);
        core.challengeCommit{value: deposit}(id, keccak256(abi.encode(evidence, revealSalt, challenger)));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal{gas: 30_000_000}(id, inputs, evidence, revealSalt);

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertEq(core.credits(challenger), deposit, "only returns challenger deposit");
        assertEq(core.credits(agent), 0);
    }
}
