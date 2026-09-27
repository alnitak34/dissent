// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputerRegistry} from "../src/IRecomputerRegistry.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";

/// @notice Four isolated Mainnet phases. Every run emits at most one
///         transaction. Public addresses and the reward come from the local
///         environment; salts never live in this repository.
abstract contract PolicyBountyMainnetBase is Script {
    uint256 internal constant MONAD_MAINNET_CHAIN_ID = 143;

    uint128 internal constant DEPOSIT = 0.1 ether;
    uint64 internal constant WINDOW = 1 days;
    uint32 internal constant RECOMPUTE_GAS_LIMIT = 20_000_000;
    uint32 internal constant VALIDATE_GAS_LIMIT = 100_000;
    uint32 internal constant MAX_EVIDENCE_LEN = 160;
    int256 internal constant THRESHOLD = 0;
    string internal constant ACTION = "Alnitak River Safety Reference v1";

    bytes32 internal constant POLICY_HASH = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0;
    bytes20 internal constant ORIGIN = hex"e6a7e49857602ac84257dc78f0960506f87cd7f3";

    function _coreAddress() internal view returns (address) {
        return vm.envAddress("DISSENT_MAINNET_CORE");
    }

    function _registryAddress() internal view returns (address) {
        return vm.envAddress("DISSENT_MAINNET_REGISTRY");
    }

    function _recomputerAddress() internal view returns (address) {
        return vm.envAddress("DISSENT_MAINNET_RECOMPUTER");
    }

    function _policyId() internal view returns (bytes32) {
        return vm.envBytes32("DISSENT_MAINNET_POLICY_ID");
    }

    function _agent() internal view returns (address) {
        return vm.envAddress("DISSENT_MAINNET_AGENT");
    }

    function _challenger() internal view returns (address) {
        return vm.envAddress("DISSENT_MAINNET_CHALLENGER");
    }

    function _reward() internal view returns (uint256) {
        return vm.envUint("DISSENT_MAINNET_REWARD_WEI");
    }

    function _requireDeployment() internal view {
        require(block.chainid == MONAD_MAINNET_CHAIN_ID, "only Monad Mainnet 143");
        address coreAddress = _coreAddress();
        address registryAddress = _registryAddress();
        address recomputerAddress = _recomputerAddress();
        bytes32 policyId = _policyId();

        require(coreAddress.code.length != 0, "DissentCore not deployed");
        require(registryAddress.code.length != 0, "RecomputerRegistry not deployed");
        require(recomputerAddress.code.length != 0, "Policy Bounty recomputer not deployed");

        DissentCore core = DissentCore(coreAddress);
        require(address(core.registry()) == registryAddress, "unexpected registry");

        IRecomputerRegistry.Policy memory policy = IRecomputerRegistry(registryAddress).getPolicy(policyId);
        require(policy.active, "policy is inactive");
        require(policy.recomputer == recomputerAddress, "unexpected policy recomputer");
        require(policy.codeHash == recomputerAddress.codehash, "unexpected policy codehash");
        require(policy.challengeDeposit == DEPOSIT, "unexpected policy deposit");
        require(policy.recomputeGasLimit == RECOMPUTE_GAS_LIMIT, "unexpected policy R");
        require(policy.validateGasLimit == VALIDATE_GAS_LIMIT, "unexpected policy V");
        require(policy.maxEvidenceLen == MAX_EVIDENCE_LEN, "unexpected policy evidence limit");

        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(recomputerAddress);
        require(recomputer.POLICY_SPEC_HASH() == POLICY_HASH, "unexpected policy hash");
        require(recomputer.ORIGIN_COMMIT() == ORIGIN, "unexpected origin commit");
        require(recomputer.MARGIN_BP() == 1500, "unexpected margin");
        require(recomputer.scale() == 1, "unexpected scale");
        // The ASCII literal is shorter than 32 bytes, so this fixed-width cast cannot truncate it.
        // forge-lint: disable-next-line(unsafe-typecast)
        require(recomputer.domain() == bytes32("alnitak.river.safety.v1"), "unexpected domain");
    }

    function _requireBroadcastSender(address expected) internal view {
        // Only the broadcast sender matters here; caller mode and tx.origin do not affect authorization.
        // forge-lint: disable-next-line(unused-return)
        (, address sender,) = vm.readCallers();
        require(sender == expected, "wrong signing account");
    }

    function _inputs() internal view returns (bytes memory) {
        return AlnitakPolicyBountyRecomputer(_recomputerAddress()).canonicalInputs();
    }

    function _evidence() internal pure returns (bytes memory) {
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

    function _requireCommitment(DissentCore.Commitment memory commitment, bytes memory inputs) internal view {
        require(commitment.status == DissentCore.Status.Open, "commitment is not Open");
        require(commitment.agent == _agent(), "unexpected agent");
        require(commitment.recomputer == _recomputerAddress(), "unexpected recomputer");
        require(commitment.policyId == _policyId(), "unexpected policy id");
        require(commitment.recomputerCodeHash == _recomputerAddress().codehash, "unexpected codehash");
        require(commitment.inputsHash == keccak256(inputs), "unexpected inputs");
        require(commitment.threshold == THRESHOLD, "unexpected threshold");
        require(commitment.comparator == DissentCore.Comparator.AtMost, "unexpected comparator");
        require(commitment.reward == _reward(), "unexpected reward");
        require(commitment.deposit == DEPOSIT, "unexpected deposit");
        require(commitment.recomputeGasLimit == RECOMPUTE_GAS_LIMIT, "unexpected recompute limit");
        require(commitment.validateGasLimit == VALIDATE_GAS_LIMIT, "unexpected validate limit");
        require(commitment.maxEvidenceLen == MAX_EVIDENCE_LEN, "unexpected evidence limit");
        require(commitment.actionHash == keccak256(bytes(ACTION)), "unexpected action");
    }
}

contract PolicyBountyMainnetCommit is PolicyBountyMainnetBase {
    function run() external returns (bytes32 id) {
        _requireDeployment();
        DissentCore core = DissentCore(_coreAddress());
        bytes memory inputs = _inputs();
        bytes32 agentSalt = vm.envBytes32("DISSENT_AGENT_SALT");
        uint256 reward = _reward();
        require(agentSalt != bytes32(0), "empty agent salt");

        uint256 txGas = core.txRequired(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        uint256 minimum =
            core.minGasBackedReward(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        require(txGas <= core.MONAD_TX_GAS_LIMIT(), "reveal exceeds 30M");
        require(reward >= minimum, "reward below current onchain minimum");

        vm.startBroadcast();
        _requireBroadcastSender(_agent());
        // The destination is the previously verified DissentCore deployment; reward is bounded by local approval.
        // forge-lint: disable-start(arbitrary-send-eth)
        id = core.commit{value: reward}(
            _policyId(), inputs, THRESHOLD, DissentCore.Comparator.AtMost, ACTION, WINDOW, agentSalt
        );
        // forge-lint: disable-end(arbitrary-send-eth)
        vm.stopBroadcast();

        console.log("txRequired for reveal", txGas);
        console.log("minGasBackedReward", minimum);
        console.log("commitment id (onchain event is authoritative):");
        console.logBytes32(id);
    }
}

contract PolicyBountyMainnetChallengeCommit is PolicyBountyMainnetBase {
    function run() external returns (bytes32 sealedHash) {
        _requireDeployment();
        DissentCore core = DissentCore(_coreAddress());
        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(_recomputerAddress());
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 challengerSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(challengerSalt != bytes32(0), "empty challenger salt");

        bytes memory inputs = _inputs();
        bytes memory evidence = _evidence();
        _requireCommitment(core.getCommitment(id), inputs);
        (bool valid, bytes32 reason) = recomputer.validateEvidence(inputs, evidence);
        require(valid && reason == bytes32(0), "counterexample rejected");
        require(recomputer.recompute(inputs, evidence) == 1, "evidence does not violate policy");

        sealedHash = core.computeSeal(evidence, challengerSalt, _challenger());
        vm.startBroadcast();
        _requireBroadcastSender(_challenger());
        // The destination is the previously verified DissentCore deployment and DEPOSIT is a fixed policy value.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.stopBroadcast();

        console.log("sealedHash:");
        console.logBytes32(sealedHash);
    }
}

contract PolicyBountyMainnetChallengeReveal is PolicyBountyMainnetBase {
    function run() external {
        _requireDeployment();
        DissentCore core = DissentCore(_coreAddress());
        AlnitakPolicyBountyRecomputer recomputer = AlnitakPolicyBountyRecomputer(_recomputerAddress());
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        bytes32 challengerSalt = vm.envBytes32("DISSENT_CHALLENGER_SALT");
        require(challengerSalt != bytes32(0), "empty challenger salt");

        bytes memory inputs = _inputs();
        bytes memory evidence = _evidence();
        _requireCommitment(core.getCommitment(id), inputs);

        bytes32 expectedSeal = core.computeSeal(evidence, challengerSalt, _challenger());
        (bytes32 storedSeal, uint64 sealBlock, uint128 storedDeposit, bool settled) = core.seals(id, _challenger());
        require(storedSeal == expectedSeal, "salt/evidence does not match seal");
        require(storedDeposit == DEPOSIT, "unexpected sealed deposit");
        require(sealBlock != 0 && !settled, "seal missing or settled");
        require(block.number >= sealBlock + core.REVEAL_DELAY_BLOCKS(), "too early to reveal");
        require(
            block.number <= sealBlock + core.REVEAL_DELAY_BLOCKS() + core.REVEAL_WINDOW_BLOCKS(), "reveal window closed"
        );
        (bool valid, bytes32 reason) = recomputer.validateEvidence(inputs, evidence);
        require(valid && reason == bytes32(0), "counterexample rejected");
        require(recomputer.recompute(inputs, evidence) == 1, "evidence does not violate policy");

        vm.startBroadcast();
        _requireBroadcastSender(_challenger());
        core.challengeReveal(id, inputs, evidence, challengerSalt);
        vm.stopBroadcast();
    }
}

contract PolicyBountyMainnetWithdraw is PolicyBountyMainnetBase {
    function run() external {
        _requireDeployment();
        DissentCore core = DissentCore(_coreAddress());
        bytes32 id = vm.envBytes32("DISSENT_COMMITMENT_ID");
        DissentCore.Commitment memory commitment = core.getCommitment(id);
        require(commitment.status == DissentCore.Status.Challenged, "commitment was not challenged");
        require(core.credits(_challenger()) == _reward() + DEPOSIT, "unexpected challenger credit");

        vm.startBroadcast();
        _requireBroadcastSender(_challenger());
        core.withdrawCredit();
        vm.stopBroadcast();
    }
}
