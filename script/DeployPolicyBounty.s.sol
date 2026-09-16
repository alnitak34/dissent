// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";

/// @title DeployPolicyBounty — despliega la campaña sobre un núcleo endurecido nuevo.
/// @notice No reutiliza el DissentCore de testnet desplegado el 2026-09-14: ese
///         contrato conserva la semántica anterior para fallos técnicos del
///         adaptador. Este script crea juntos el núcleo de esta rama y el
///         recomputer Policy Bounty. No contiene claves, cuentas personales ni
///         RPC con credenciales.
contract DeployPolicyBounty is Script {
    uint256 internal constant MONAD_TESTNET_CHAIN_ID = 10143;

    function run() external returns (DissentCore core, AlnitakPolicyBountyRecomputer recomputer) {
        require(block.chainid == MONAD_TESTNET_CHAIN_ID, "no es Monad testnet (10143)");

        vm.startBroadcast();
        core = new DissentCore();
        recomputer = new AlnitakPolicyBountyRecomputer();
        vm.stopBroadcast();

        console.log("chainid                           ", block.chainid);
        console.log("DissentCore hardened              ", address(core));
        console.log("AlnitakPolicyBountyRecomputer    ", address(recomputer));

        require(core.MIN_WINDOW() == 1 hours, "MIN_WINDOW != 1 hours");
        require(core.MONAD_TX_GAS_LIMIT() == 30_000_000, "tx gas limit inesperado");
        require(core.REFERENCE_GAS_PRICE() == 100 gwei, "reference gas price inesperado");
        require(core.CHALLENGE_COMMIT_GAS() == 200_000, "challenge gas inesperado");
        require(core.MAX_EVIDENCE_LEN() == 131_072, "max evidence inesperado");
        require(core.escrowed() == 0, "escrowed != 0");

        require(recomputer.scale() == 1, "scale != 1");
        require(recomputer.domain() == bytes32("alnitak.river.safety.v1"), "domain inesperado");
        require(
            recomputer.POLICY_SPEC_HASH() == 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0,
            "policy hash inesperado"
        );
        require(recomputer.ORIGIN_COMMIT() == hex"e6a7e49857602ac84257dc78f0960506f87cd7f3", "origin inesperado");
        require(recomputer.MARGIN_BP() == 1500, "margin != 1500 bp");
        require(recomputer.canonicalInputs().length == 96, "inputs no canonicos");
    }
}
