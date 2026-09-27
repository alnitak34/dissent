// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {RecomputerRegistry} from "../src/RecomputerRegistry.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";

/// @title DeployPolicyBountyMainnet
/// @notice Prepares the current three-contract Dissent architecture for Monad
///         Mainnet. The signer must equal DISSENT_MAINNET_CURATOR. This file
///         contains no key, mnemonic, wallet address or private RPC URL.
contract DeployPolicyBountyMainnet is Script {
    uint256 internal constant MONAD_MAINNET_CHAIN_ID = 143;

    uint128 internal constant CHALLENGE_DEPOSIT = 0.1 ether;
    uint32 internal constant RECOMPUTE_GAS_LIMIT = 20_000_000;
    uint32 internal constant VALIDATE_GAS_LIMIT = 100_000;
    uint32 internal constant MAX_EVIDENCE_LEN = 160;

    function run()
        external
        returns (DissentCore core, RecomputerRegistry registry, AlnitakPolicyBountyRecomputer recomputer)
    {
        require(block.chainid == MONAD_MAINNET_CHAIN_ID, "not Monad Mainnet (143)");
        address curator = vm.envAddress("DISSENT_MAINNET_CURATOR");
        require(curator != address(0), "DISSENT_MAINNET_CURATOR is empty");

        vm.startBroadcast();
        // Only the broadcast sender matters here; caller mode and tx.origin do not affect deployment identity.
        // forge-lint: disable-next-line(unused-return)
        (, address sender,) = vm.readCallers();
        require(sender == curator, "deployment signer must be the curator");

        recomputer = new AlnitakPolicyBountyRecomputer();
        registry = new RecomputerRegistry(curator);
        bytes32 policyId = registry.registerPolicy(
            address(recomputer), CHALLENGE_DEPOSIT, RECOMPUTE_GAS_LIMIT, VALIDATE_GAS_LIMIT, MAX_EVIDENCE_LEN
        );
        core = new DissentCore(address(registry));
        vm.stopBroadcast();

        console.log("chainid                         ", block.chainid);
        console.log("DissentCore                     ", address(core));
        console.log("RecomputerRegistry              ", address(registry));
        console.log("AlnitakPolicyBountyRecomputer   ", address(recomputer));
        console.log("policyId:");
        console.logBytes32(policyId);

        require(core.MIN_WINDOW() == 1 hours, "MIN_WINDOW != 1 hour");
        require(core.MONAD_TX_GAS_LIMIT() == 30_000_000, "unexpected tx gas limit");
        require(core.REFERENCE_GAS_PRICE() == 100 gwei, "unexpected reference gas price");
        require(core.CHALLENGE_COMMIT_GAS() == 200_000, "unexpected challenge gas");
        require(core.MAX_EVIDENCE_LEN() == 131_072, "unexpected max evidence");
        require(core.escrowed() == 0, "escrowed != 0");
        require(address(core.registry()) == address(registry), "unexpected registry");
        require(registry.curator() == curator, "unexpected curator");

        require(recomputer.scale() == 1, "scale != 1");
        // The ASCII literal is shorter than 32 bytes, so this fixed-width cast cannot truncate it.
        // forge-lint: disable-next-line(unsafe-typecast)
        require(recomputer.domain() == bytes32("alnitak.river.safety.v1"), "unexpected domain");
        require(
            recomputer.POLICY_SPEC_HASH() == 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0,
            "unexpected policy hash"
        );
        require(recomputer.ORIGIN_COMMIT() == hex"e6a7e49857602ac84257dc78f0960506f87cd7f3", "unexpected origin");
        require(recomputer.MARGIN_BP() == 1500, "margin != 1500 bp");
        require(recomputer.canonicalInputs().length == 96, "non-canonical inputs");

        require(
            registry.computePolicyId(
                address(recomputer),
                address(recomputer).codehash,
                CHALLENGE_DEPOSIT,
                RECOMPUTE_GAS_LIMIT,
                VALIDATE_GAS_LIMIT,
                MAX_EVIDENCE_LEN
            ) == policyId,
            "unexpected policy id"
        );
    }
}
