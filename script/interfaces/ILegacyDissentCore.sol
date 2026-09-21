// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ABI congelada del DissentCore desplegado antes del registro de
///         recomputers. Solo mantiene operables los scripts historicos; no debe
///         usarse para despliegues nuevos.
interface ILegacyDissentCore {
    enum Comparator {
        AtLeast,
        AtMost
    }

    enum Status {
        None,
        Open,
        Challenged,
        Reclaimed,
        Faulted
    }

    struct Commitment {
        address agent;
        address recomputer;
        bytes32 inputsHash;
        bytes32 domain;
        bytes32 actionHash;
        int256 threshold;
        int256 baseValue;
        uint128 reward;
        uint128 deposit;
        uint64 windowEnds;
        uint64 latestSealBlock;
        uint32 baseGas;
        uint32 recomputeGasLimit;
        uint32 validateGasLimit;
        uint32 maxEvidenceLen;
        uint256 effectiveGasPrice;
        Comparator comparator;
        Status status;
    }

    function commit(
        address recomputer,
        bytes calldata inputs,
        int256 threshold,
        Comparator comparator,
        string calldata action,
        uint128 deposit,
        uint64 window,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen,
        bytes32 salt
    ) external payable returns (bytes32 id);

    function getCommitment(bytes32 id) external view returns (Commitment memory);
    function minGasBackedReward(uint256 validateGasLimit, uint256 recomputeGasLimit, uint256 inLen, uint256 evLen)
        external
        view
        returns (uint256);
    function txRequired(uint256 validateGasLimit, uint256 recomputeGasLimit, uint256 inLen, uint256 evLen)
        external
        pure
        returns (uint256);
    function MONAD_TX_GAS_LIMIT() external view returns (uint256);
    function REVEAL_DELAY_BLOCKS() external view returns (uint64);
    function REVEAL_WINDOW_BLOCKS() external view returns (uint64);
    function computeSeal(bytes calldata evidence, bytes32 salt, address challenger) external pure returns (bytes32);
    function challengeCommit(bytes32 id, bytes32 sealedHash) external payable;
    function challengeReveal(bytes32 id, bytes calldata inputs, bytes calldata evidence, bytes32 salt) external;
    function sweepExpiredSeal(bytes32 id, address challenger) external;
    function reclaim(bytes32 id) external;
    function withdrawCredit() external;
    function credits(address who) external view returns (uint256);
    function seals(bytes32 id, address challenger)
        external
        view
        returns (bytes32 sealedHash, uint64 blockNumber, uint128 deposit, bool settled);
}
