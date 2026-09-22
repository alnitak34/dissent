// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "../IRecomputer.sol";

/// @title ArfInfrastructureP1Recomputer
/// @notice Independent bounded representation of the public reference property
///         P1 in petter2025us/arf-pattern-examples at commit
///         b0282d789da01a9c3b94d9684d7945db024ebba8 (Apache-2.0 source).
/// @dev This is not ARF production code and makes no claim about ARF's private
///      engine or execution controls. It compares outcome parity only.
contract ArfInfrastructureP1Recomputer is IRecomputer {
    bytes32 public constant POLICY_SPEC_HASH = 0xf237d77c5db8f7b5bd7ebe92982ce3e601af319a81bfd88de4b9d860a6c677b0;
    bytes20 public constant ORIGIN_COMMIT = hex"b0282d789da01a9c3b94d9684d7945db024ebba8";
    bytes32 public constant POLICY_ID = "infrastructure.change";
    bytes32 public constant POLICY_VERSION = "1.0.0";
    bytes32 public constant PROPERTY_ID = "P1";
    uint256 public constant PRODUCTION_CEILING = 5;

    bytes32 private constant PRODUCTION = "production";
    bytes32 private constant STAGING = "staging";
    bytes32 private constant DEV = "dev";
    bytes32 private constant DELETE_SNAPSHOT = "delete_snapshot";
    bytes32 private constant PURGE_BACKUP = "purge_backup";
    bytes32 private constant DESTROY_KEY_MATERIAL = "destroy_key_material";

    uint256 private constant REVERSIBILITY_MISSING = 0;
    uint256 private constant REVERSIBLE = 1;
    uint256 private constant COMPENSABLE = 2;
    uint256 private constant IRREVERSIBLE = 3;
    uint256 private constant EVIDENCE_LENGTH = 352;

    bytes32 private constant REASON_OK = bytes32(0);
    bytes32 private constant REASON_BAD_INPUTS = "BAD_POLICY_INPUTS";
    bytes32 private constant REASON_BAD_LENGTH = "EVIDENCE_BAD_LENGTH";
    bytes32 private constant REASON_BAD_REVERSIBILITY = "BAD_REVERSIBILITY";
    bytes32 private constant REASON_BAD_APPROVALS = "BAD_APPROVALS";
    bytes32 private constant REASON_BAD_WINDOW = "BAD_CHANGE_WINDOW";
    bytes32 private constant REASON_OUTSIDE_P1 = "OUTSIDE_P1_DOMAIN";

    enum Outcome {
        Approve,
        Deny,
        Escalate
    }

    struct PolicyInputs {
        bytes32 policySpecHash;
        bytes20 originCommit;
        bytes32 policyId;
        bytes32 policyVersion;
        bytes32 propertyId;
        uint256 productionCeiling;
    }

    struct Approval {
        bytes32 approver;
        bytes32 at;
    }

    /// @dev Every field is a full ABI word. No dynamic offset or narrow scalar
    ///      is decoded from challenger bytes, so arbitrary 352-byte evidence
    ///      cannot make abi.decode revert.
    struct ProposalEvidence {
        bytes32 action;
        bytes32 environment;
        bytes32 resourceId;
        uint256 blastRadius;
        uint256 reversibilityCode;
        Approval[2] approvals;
        uint256 approvalCount;
        uint256 changeWindowOpen;
    }

    function scale() external pure returns (uint256) {
        return 1;
    }

    function domain() external pure returns (bytes32) {
        return "arf.reference.p1.v1";
    }

    function canonicalInputs() external pure returns (bytes memory) {
        return abi.encode(
            PolicyInputs({
                policySpecHash: POLICY_SPEC_HASH,
                originCommit: ORIGIN_COMMIT,
                policyId: POLICY_ID,
                policyVersion: POLICY_VERSION,
                propertyId: PROPERTY_ID,
                productionCeiling: PRODUCTION_CEILING
            })
        );
    }

    function validateEvidence(bytes calldata inputs, bytes calldata evidence)
        external
        pure
        returns (bool ok, bytes32 reason)
    {
        if (!_validInputs(inputs)) return (false, REASON_BAD_INPUTS);
        (bool structurallyValid, ProposalEvidence memory proposal, bytes32 structuralReason) =
            _decodeAndValidate(evidence);
        if (!structurallyValid) return (false, structuralReason);
        if (!_inP1Domain(proposal)) return (false, REASON_OUTSIDE_P1);
        return (true, REASON_OK);
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        if (!_validInputs(inputs)) revert("BAD_POLICY_INPUTS");
        if (evidence.length == 0) return 0;
        (bool structurallyValid, ProposalEvidence memory proposal,) = _decodeAndValidate(evidence);
        if (!structurallyValid) revert("BAD_EVIDENCE");
        if (!_inP1Domain(proposal)) revert("OUTSIDE_P1_DOMAIN");
        return _evaluate(proposal) == Outcome.Approve ? int256(1) : int256(0);
    }

    /// @notice Developer/reviewer helper. It evaluates structurally valid cases
    ///         outside P1 too, so the boundary and control cases are inspectable.
    function evaluate(bytes calldata evidence) external pure returns (Outcome) {
        (bool structurallyValid, ProposalEvidence memory proposal,) = _decodeAndValidate(evidence);
        if (!structurallyValid) revert("BAD_EVIDENCE");
        return _evaluate(proposal);
    }

    function _validInputs(bytes calldata inputs) private pure returns (bool) {
        if (inputs.length != 192) return false;
        PolicyInputs memory value = abi.decode(inputs, (PolicyInputs));
        return value.policySpecHash == POLICY_SPEC_HASH && value.originCommit == ORIGIN_COMMIT
            && value.policyId == POLICY_ID && value.policyVersion == POLICY_VERSION && value.propertyId == PROPERTY_ID
            && value.productionCeiling == PRODUCTION_CEILING;
    }

    function _decodeAndValidate(bytes calldata evidence)
        private
        pure
        returns (bool ok, ProposalEvidence memory proposal, bytes32 reason)
    {
        if (evidence.length != EVIDENCE_LENGTH) return (false, proposal, REASON_BAD_LENGTH);
        proposal = abi.decode(evidence, (ProposalEvidence));
        if (proposal.reversibilityCode > IRREVERSIBLE) {
            return (false, proposal, REASON_BAD_REVERSIBILITY);
        }
        if (proposal.changeWindowOpen > 1) return (false, proposal, REASON_BAD_WINDOW);
        if (proposal.approvalCount > 2) return (false, proposal, REASON_BAD_APPROVALS);

        for (uint256 i = 0; i < 2; i++) {
            bool used = i < proposal.approvalCount;
            bool empty = proposal.approvals[i].approver == bytes32(0) && proposal.approvals[i].at == bytes32(0);
            if ((used && empty) || (!used && !empty)) return (false, proposal, REASON_BAD_APPROVALS);
            if (used && (proposal.approvals[i].approver == bytes32(0) || proposal.approvals[i].at == bytes32(0))) {
                return (false, proposal, REASON_BAD_APPROVALS);
            }
        }
        return (true, proposal, REASON_OK);
    }

    function _inP1Domain(ProposalEvidence memory proposal) private pure returns (bool) {
        return proposal.environment == PRODUCTION && proposal.blastRadius > PRODUCTION_CEILING;
    }

    function _evaluate(ProposalEvidence memory proposal) private pure returns (Outcome) {
        uint256 reversibility = proposal.reversibilityCode;
        if (
            proposal.action == DELETE_SNAPSHOT || proposal.action == PURGE_BACKUP
                || proposal.action == DESTROY_KEY_MATERIAL
        ) {
            reversibility = IRREVERSIBLE;
        }

        if (reversibility == REVERSIBILITY_MISSING) return Outcome.Escalate;
        if (reversibility == IRREVERSIBLE && proposal.environment == PRODUCTION) return Outcome.Deny;
        if (proposal.blastRadius > _ceiling(proposal.environment)) return Outcome.Deny;

        if (proposal.environment == PRODUCTION && reversibility == COMPENSABLE && proposal.approvalCount == 0) {
            return Outcome.Escalate;
        }
        if (proposal.environment == PRODUCTION && proposal.changeWindowOpen == 0) return Outcome.Escalate;
        return Outcome.Approve;
    }

    function _ceiling(bytes32 environment) private pure returns (uint256) {
        if (environment == STAGING) return 50;
        if (environment == DEV) return 500;
        return PRODUCTION_CEILING;
    }
}
