// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "./IRecomputer.sol";
import {IRecomputerRegistry} from "./IRecomputerRegistry.sol";

/// @title RecomputerRegistry — catalogo curado de politicas inmutables
/// @notice El curator puede registrar politicas y cambiar solo su estado activo.
///         No custodia MON, no toca DissentCore y no puede editar los campos de
///         una politica existente. La transferencia del rol requiere dos pasos.
contract RecomputerRegistry is IRecomputerRegistry {
    uint32 public constant MAX_EVIDENCE_LEN = 131_072;

    address public curator;
    address public pendingCurator;

    mapping(bytes32 => Policy) private policies;

    event PolicyRegistered(
        bytes32 indexed policyId,
        address indexed recomputer,
        bytes32 codeHash,
        uint128 challengeDeposit,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen,
        bytes32 domain,
        uint256 scale
    );
    event PolicyStatusChanged(bytes32 indexed policyId, bool active);
    event CuratorTransferStarted(address indexed currentCurator, address indexed pendingCurator);
    event CuratorTransferred(address indexed previousCurator, address indexed newCurator);

    error NotCurator();
    error NotPendingCurator();
    error ZeroAddress();
    error NotContract(address target);
    error ZeroDeposit();
    error ZeroGasLimit();
    error ZeroScale();
    error EvidenceLimitTooLarge(uint256 sent, uint256 maximum);
    error PolicyAlreadyExists(bytes32 policyId);
    error UnknownPolicy(bytes32 policyId);
    error StatusUnchanged(bytes32 policyId, bool active);

    modifier onlyCurator() {
        if (msg.sender != curator) revert NotCurator();
        _;
    }

    constructor(address initialCurator) {
        if (initialCurator == address(0)) revert ZeroAddress();
        curator = initialCurator;
        emit CuratorTransferred(address(0), initialCurator);
    }

    function computePolicyId(
        address recomputer,
        bytes32 codeHash,
        uint128 challengeDeposit,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                recomputer,
                codeHash,
                challengeDeposit,
                recomputeGasLimit,
                validateGasLimit,
                maxEvidenceLen
            )
        );
    }

    function registerPolicy(
        address recomputer,
        uint128 challengeDeposit,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen
    ) external onlyCurator returns (bytes32 policyId) {
        if (recomputer == address(0)) revert ZeroAddress();
        if (recomputer.code.length == 0) revert NotContract(recomputer);
        if (challengeDeposit == 0) revert ZeroDeposit();
        if (recomputeGasLimit == 0 || validateGasLimit == 0) revert ZeroGasLimit();
        if (maxEvidenceLen > MAX_EVIDENCE_LEN) {
            revert EvidenceLimitTooLarge(maxEvidenceLen, MAX_EVIDENCE_LEN);
        }

        bytes32 codeHash = recomputer.codehash;
        bytes32 domain = IRecomputer(recomputer).domain();
        uint256 scale = IRecomputer(recomputer).scale();
        if (scale == 0) revert ZeroScale();

        policyId = computePolicyId(
            recomputer, codeHash, challengeDeposit, recomputeGasLimit, validateGasLimit, maxEvidenceLen
        );
        if (policies[policyId].recomputer != address(0)) revert PolicyAlreadyExists(policyId);

        policies[policyId] = Policy({
            recomputer: recomputer,
            codeHash: codeHash,
            challengeDeposit: challengeDeposit,
            recomputeGasLimit: recomputeGasLimit,
            validateGasLimit: validateGasLimit,
            maxEvidenceLen: maxEvidenceLen,
            active: true
        });

        emit PolicyRegistered(
            policyId,
            recomputer,
            codeHash,
            challengeDeposit,
            recomputeGasLimit,
            validateGasLimit,
            maxEvidenceLen,
            domain,
            scale
        );
    }

    function setPolicyActive(bytes32 policyId, bool active) external onlyCurator {
        Policy storage policy = policies[policyId];
        if (policy.recomputer == address(0)) revert UnknownPolicy(policyId);
        if (policy.active == active) revert StatusUnchanged(policyId, active);
        policy.active = active;
        emit PolicyStatusChanged(policyId, active);
    }

    function proposeCurator(address nextCurator) external onlyCurator {
        if (nextCurator == address(0)) revert ZeroAddress();
        pendingCurator = nextCurator;
        emit CuratorTransferStarted(curator, nextCurator);
    }

    function acceptCurator() external {
        if (msg.sender != pendingCurator) revert NotPendingCurator();
        address previous = curator;
        curator = msg.sender;
        pendingCurator = address(0);
        emit CuratorTransferred(previous, msg.sender);
    }

    function getPolicy(bytes32 policyId) external view returns (Policy memory policy) {
        policy = policies[policyId];
    }
}
