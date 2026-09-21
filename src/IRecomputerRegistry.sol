// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRecomputerRegistry — politicas aprobadas para nuevos compromisos
/// @notice El registro fija la frontera que antes elegia libremente el agente.
///         Una politica puede desactivarse para commits futuros, pero sus campos
///         no se editan y los compromisos ya creados conservan una copia de ellos.
interface IRecomputerRegistry {
    struct Policy {
        address recomputer;
        bytes32 codeHash;
        uint128 challengeDeposit;
        uint32 recomputeGasLimit;
        uint32 validateGasLimit;
        uint32 maxEvidenceLen;
        bool active;
    }

    function getPolicy(bytes32 policyId) external view returns (Policy memory policy);
}
