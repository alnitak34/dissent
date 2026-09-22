// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArfInfrastructureP1Recomputer} from "../src/adapters/ArfInfrastructureP1Recomputer.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {RegistryTestSupport} from "./helpers/RegistryTestSupport.sol";

contract ArfInfrastructureP1RecomputerTest is Test, RegistryTestSupport {
    ArfInfrastructureP1Recomputer internal rc;
    DissentCore internal core;
    bytes32 internal policyId;
    address internal agent = makeAddr("arf-reference-agent");
    address internal challenger = makeAddr("arf-reference-challenger");

    bytes32 internal constant SPEC_HASH = 0xf237d77c5db8f7b5bd7ebe92982ce3e601af319a81bfd88de4b9d860a6c677b0;
    bytes20 internal constant ORIGIN = hex"b0282d789da01a9c3b94d9684d7945db024ebba8";

    function setUp() public {
        rc = new ArfInfrastructureP1Recomputer();
        core = _deployRegistryCore();
        policyId = _policy(address(rc), 0.01 ether, 500_000, 200_000, 352);
        vm.deal(agent, 100 ether);
        vm.deal(challenger, 100 ether);
    }

    function _inputs() internal pure returns (bytes memory) {
        return abi.encode(
            ArfInfrastructureP1Recomputer.PolicyInputs({
                policySpecHash: SPEC_HASH,
                originCommit: ORIGIN,
                policyId: bytes32("infrastructure.change"),
                policyVersion: bytes32("1.0.0"),
                propertyId: bytes32("P1"),
                productionCeiling: 5
            })
        );
    }

    function _approval(string memory who, string memory at)
        internal
        pure
        returns (ArfInfrastructureP1Recomputer.Approval memory)
    {
        return ArfInfrastructureP1Recomputer.Approval({approver: _word(who), at: _word(at)});
    }

    function _proposal(
        string memory action,
        string memory environment,
        uint256 blastRadius,
        uint256 reversibilityCode,
        uint256 approvalCount,
        bool changeWindowOpen
    ) internal pure returns (bytes memory) {
        ArfInfrastructureP1Recomputer.Approval[2] memory approvals;
        if (approvalCount > 0) approvals[0] = _approval("sre-oncall", "2026-09-21T09:00:00Z");
        if (approvalCount > 1) approvals[1] = _approval("platform-lead", "2026-09-21T09:01:00Z");
        return abi.encode(
            ArfInfrastructureP1Recomputer.ProposalEvidence({
                action: _word(action),
                environment: _word(environment),
                resourceId: bytes32("svc-reference"),
                blastRadius: blastRadius,
                reversibilityCode: reversibilityCode,
                approvals: approvals,
                approvalCount: approvalCount,
                changeWindowOpen: changeWindowOpen ? 1 : 0
            })
        );
    }

    function _word(string memory value) internal pure returns (bytes32 result) {
        bytes memory encoded = bytes(value);
        require(encoded.length <= 32, "test word too long");
        assembly ("memory-safe") {
            result := mload(add(encoded, 32))
        }
    }

    function test_identidad_y_base_canonicas() public view {
        assertEq(rc.POLICY_SPEC_HASH(), SPEC_HASH);
        assertEq(rc.ORIGIN_COMMIT(), ORIGIN);
        assertEq(rc.canonicalInputs(), _inputs());
        assertEq(rc.scale(), 1);
        assertEq(rc.domain(), bytes32("arf.reference.p1.v1"));
        assertEq(rc.recompute(_inputs(), ""), 0);
    }

    function test_36_combinaciones_publicas_nunca_aprueban() public view {
        uint256[3] memory radii = [uint256(6), 12, 250];
        for (uint256 r = 0; r < radii.length; r++) {
            for (uint256 reversibility = 0; reversibility < 4; reversibility++) {
                for (uint256 approvalCount = 0; approvalCount < 3; approvalCount++) {
                    bytes memory evidence =
                        _proposal("resize_cluster", "production", radii[r], reversibility, approvalCount, true);
                    (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), evidence);
                    assertTrue(ok, "P1 corpus case must be admissible");
                    assertEq(reason, bytes32(0));
                    assertTrue(
                        rc.evaluate(evidence) != ArfInfrastructureP1Recomputer.Outcome.Approve,
                        "P1 corpus case must not approve"
                    );
                    assertEq(rc.recompute(_inputs(), evidence), 0, "conforming case is not a counterexample");
                }
            }
        }
    }

    function test_frontera_5_puede_aprobar_y_6_no() public view {
        bytes memory atCeiling = _proposal("resize_cluster", "production", 5, 1, 2, true);
        bytes memory above = _proposal("resize_cluster", "production", 6, 1, 2, true);
        assertEq(uint8(rc.evaluate(atCeiling)), uint8(ArfInfrastructureP1Recomputer.Outcome.Approve));
        assertEq(uint8(rc.evaluate(above)), uint8(ArfInfrastructureP1Recomputer.Outcome.Deny));

        (bool atOk, bytes32 atReason) = rc.validateEvidence(_inputs(), atCeiling);
        assertFalse(atOk);
        assertEq(atReason, bytes32("OUTSIDE_P1_DOMAIN"));
        (bool aboveOk,) = rc.validateEvidence(_inputs(), above);
        assertTrue(aboveOk);
    }

    function test_prod_no_es_production() public view {
        bytes memory evidence = _proposal("resize_cluster", "prod", 6, 1, 1, true);
        (bool ok, bytes32 reason) = rc.validateEvidence(_inputs(), evidence);
        assertFalse(ok);
        assertEq(reason, bytes32("OUTSIDE_P1_DOMAIN"));
    }

    function test_approval_conserva_objeto_y_slots_canonicos() public view {
        bytes memory canonical = _proposal("resize_cluster", "production", 6, 1, 1, true);
        (bool canonicalOk,) = rc.validateEvidence(_inputs(), canonical);
        assertTrue(canonicalOk);

        ArfInfrastructureP1Recomputer.Approval[2] memory approvals;
        approvals[1] = _approval("dirty-unused", "2026-09-21T09:01:00Z");
        bytes memory dirty = abi.encode(
            ArfInfrastructureP1Recomputer.ProposalEvidence({
                action: bytes32("resize_cluster"),
                environment: bytes32("production"),
                resourceId: bytes32("svc-reference"),
                blastRadius: 6,
                reversibilityCode: 1,
                approvals: approvals,
                approvalCount: 1,
                changeWindowOpen: 1
            })
        );
        (bool dirtyOk, bytes32 reason) = rc.validateEvidence(_inputs(), dirty);
        assertFalse(dirtyOk);
        assertEq(reason, bytes32("BAD_APPROVALS"));
    }

    function test_ramas_de_control_fuera_de_P1() public view {
        bytes memory staging = _proposal("restart_service", "staging", 40, 1, 0, true);
        assertEq(uint8(rc.evaluate(staging)), uint8(ArfInfrastructureP1Recomputer.Outcome.Approve));

        bytes memory unknown = _proposal("restart_service", "prodction", 6, 1, 0, true);
        assertEq(uint8(rc.evaluate(unknown)), uint8(ArfInfrastructureP1Recomputer.Outcome.Deny));

        bytes memory missing = _proposal("resize_cluster", "production", 1, 0, 0, true);
        assertEq(uint8(rc.evaluate(missing)), uint8(ArfInfrastructureP1Recomputer.Outcome.Escalate));

        bytes memory forcedIrreversible = _proposal("delete_snapshot", "production", 1, 1, 2, true);
        assertEq(uint8(rc.evaluate(forcedIrreversible)), uint8(ArfInfrastructureP1Recomputer.Outcome.Deny));

        bytes memory compensableNoApproval = _proposal("delete_volume", "production", 1, 2, 0, true);
        assertEq(uint8(rc.evaluate(compensableNoApproval)), uint8(ArfInfrastructureP1Recomputer.Outcome.Escalate));
        bytes memory compensableApproved = _proposal("delete_volume", "production", 1, 2, 1, true);
        assertEq(uint8(rc.evaluate(compensableApproved)), uint8(ArfInfrastructureP1Recomputer.Outcome.Approve));

        bytes memory closedWindow = _proposal("restart_service", "production", 1, 1, 0, false);
        assertEq(uint8(rc.evaluate(closedWindow)), uint8(ArfInfrastructureP1Recomputer.Outcome.Escalate));
    }

    function testFuzz_validateEvidence_no_revierte_con_352_bytes(bytes32[11] memory words) public view {
        bytes memory arbitrary = abi.encode(words);
        (bool callOk, bytes memory returned) = address(rc)
            .staticcall(abi.encodeCall(ArfInfrastructureP1Recomputer.validateEvidence, (_inputs(), arbitrary)));
        assertTrue(callOk, "challenger bytes must not become AdapterFault");
        assertEq(returned.length, 64, "canonical (bool,bytes32) return");
    }

    function test_flujo_conforme_no_paga_y_permanece_abierto() public {
        bytes memory inputs = _inputs();
        bytes memory evidence = _proposal("resize_cluster", "production", 6, 1, 2, true);
        uint128 deposit = 0.01 ether;
        uint256 reward = core.minGasBackedReward(200_000, 500_000, inputs.length, 352);

        vm.prank(agent);
        bytes32 id = core.commit{value: reward}(
            policyId,
            inputs,
            0,
            DissentCore.Comparator.AtMost,
            "ARF public reference P1 conformance",
            1 days,
            bytes32("arf-public-p1")
        );

        bytes32 salt = bytes32("conforming-case");
        vm.prank(challenger);
        core.challengeCommit{value: deposit}(id, keccak256(abi.encode(evidence, salt, challenger)));
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal{gas: 3_000_000}(id, inputs, evidence, salt);

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Open));
        assertEq(core.credits(challenger), 0, "failed challenger forfeits the deposit");
        assertEq(core.credits(agent), deposit, "agent receives only the failed challenge deposit");
    }
}
