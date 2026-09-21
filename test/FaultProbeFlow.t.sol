// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {FaultProbeRecomputer} from "../script/DeployFaultProbe.s.sol";
import {RegistryTestSupport} from "./helpers/RegistryTestSupport.sol";

contract FaultProbeFlowTest is Test, RegistryTestSupport {
    function test_fault_devuelve_principales_sin_bounty() public {
        vm.fee(100 gwei);
        vm.roll(100);
        address agent = makeAddr("probe-agent");
        address challenger = makeAddr("probe-challenger");
        vm.deal(agent, 1 ether);
        vm.deal(challenger, 1 ether);

        DissentCore core = _deployRegistryCore();
        FaultProbeRecomputer probe = new FaultProbeRecomputer();
        bytes memory inputs = abi.encode(int256(200));
        bytes memory evidence = abi.encode(int256(50));
        bytes32 salt = bytes32(uint256(123)); // Solo prueba local; nunca se usa onchain.
        uint256 reward = 0.25 ether;
        uint128 deposit = 0.01 ether;
        bytes32 policyId = _policy(address(probe), deposit, 1_000_000, 100_000, 32);

        assertLe(core.minGasBackedReward(100_000, 1_000_000, inputs.length, 32), reward);
        vm.prank(agent);
        bytes32 id = core.commit{value: reward}(
            policyId,
            inputs,
            100,
            DissentCore.Comparator.AtLeast,
            "FAULT_PROBE_ONLY",
            1 hours,
            bytes32(uint256(456))
        );

        bytes32 sealedHash = core.computeSeal(evidence, salt, challenger);
        vm.prank(challenger);
        core.challengeCommit{value: deposit}(id, sealedHash);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal(id, inputs, evidence, salt);

        assertEq(uint8(core.getCommitment(id).status), uint8(DissentCore.Status.Faulted));
        assertEq(core.credits(agent), reward);
        assertEq(core.credits(challenger), deposit);
        assertEq(core.escrowed(), 0);

        vm.prank(agent);
        core.withdrawCredit();
        vm.prank(challenger);
        core.withdrawCredit();
        assertEq(core.credits(agent), 0);
        assertEq(core.credits(challenger), 0);
    }
}
