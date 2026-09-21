// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DissentCore} from "../../src/DissentCore.sol";
import {RecomputerRegistry} from "../../src/RecomputerRegistry.sol";
import {IRecomputerRegistry} from "../../src/IRecomputerRegistry.sol";

/// @dev Utilidad exclusiva de tests. Cada suite es curator de su registro local
///      y registra las politicas exactas que necesita antes de hacer commit.
contract RegistryTestSupport {
    RecomputerRegistry internal policyRegistry;

    function _deployRegistryCore() internal returns (DissentCore deployed) {
        policyRegistry = new RecomputerRegistry(address(this));
        deployed = new DissentCore(address(policyRegistry));
    }

    function _policy(
        address recomputer,
        uint128 challengeDeposit,
        uint32 recomputeGasLimit,
        uint32 validateGasLimit,
        uint32 maxEvidenceLen
    ) internal returns (bytes32 policyId) {
        bytes32 codeHash = recomputer.codehash;
        policyId = policyRegistry.computePolicyId(
            recomputer, codeHash, challengeDeposit, recomputeGasLimit, validateGasLimit, maxEvidenceLen
        );
        IRecomputerRegistry.Policy memory existing = policyRegistry.getPolicy(policyId);
        if (existing.recomputer == address(0)) {
            policyId = policyRegistry.registerPolicy(
                recomputer, challengeDeposit, recomputeGasLimit, validateGasLimit, maxEvidenceLen
            );
        }
    }
}
