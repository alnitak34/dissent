// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {RecomputerRegistry} from "../src/RecomputerRegistry.sol";
import {AlnitakPolicyBountyRecomputer} from "../src/adapters/AlnitakPolicyBountyRecomputer.sol";
import {DeployPolicyBountyMainnet} from "../script/DeployPolicyBountyMainnet.s.sol";
import {PolicyBountyMainnetBase} from "../script/PolicyBountyMainnetFlow.s.sol";

contract PolicyBountyMainnetHarness is PolicyBountyMainnetBase {
    function requireDeployment() external view {
        _requireDeployment();
    }

    function requireParticipants(address agent, address challenger) external pure {
        _requireParticipants(agent, challenger);
    }

    function requireChallengeCommitState(bytes32 id) external view {
        DissentCore core = DissentCore(_coreAddress());
        _requireChallengeCommitState(core, id, _inputs());
    }

    function requireWithdrawState(bytes32 id) external view returns (uint256) {
        DissentCore core = DissentCore(_coreAddress());
        return _requireWithdrawState(core, id, _inputs());
    }
}

// This suite sends only test VM balances to contracts deployed inside each test.
// forge-lint: disable-start(arbitrary-send-eth)
contract PolicyBountyMainnetScriptsTest is Test {
    uint128 internal constant DEPOSIT = 0.1 ether;
    uint256 internal constant REWARD = 3 ether;

    bytes32 internal constant POLICY_HASH = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0;
    bytes20 internal constant ORIGIN = hex"e6a7e49857602ac84257dc78f0960506f87cd7f3";

    address internal agent = makeAddr("mainnet-agent");
    address internal challenger = makeAddr("mainnet-challenger");

    DissentCore internal core;
    RecomputerRegistry internal registry;
    AlnitakPolicyBountyRecomputer internal recomputer;
    PolicyBountyMainnetHarness internal harness;
    bytes32 internal policyId;

    function setUp() public {
        vm.chainId(143);
        vm.deal(agent, 100 ether);
        vm.deal(challenger, 100 ether);

        recomputer = new AlnitakPolicyBountyRecomputer();
        registry = new RecomputerRegistry(address(this));
        policyId = registry.registerPolicy(address(recomputer), DEPOSIT, 20_000_000, 100_000, 160);
        core = new DissentCore(address(registry));
        harness = new PolicyBountyMainnetHarness();

        _setAddress("DISSENT_MAINNET_CORE", address(core));
        _setAddress("DISSENT_MAINNET_REGISTRY", address(registry));
        _setAddress("DISSENT_MAINNET_RECOMPUTER", address(recomputer));
        vm.setEnv("DISSENT_MAINNET_POLICY_ID", vm.toString(policyId));
        _setAddress("DISSENT_MAINNET_AGENT", agent);
        _setAddress("DISSENT_MAINNET_CHALLENGER", challenger);
        vm.setEnv("DISSENT_MAINNET_REWARD_WEI", vm.toString(REWARD));
    }

    function test_deploy_rechaza_una_red_que_no_es_mainnet() public {
        vm.chainId(10_143);
        _setAddress("DISSENT_MAINNET_CURATOR", address(this));

        DeployPolicyBountyMainnet script = new DeployPolicyBountyMainnet();
        vm.expectRevert(bytes("not Monad Mainnet (143)"));
        // The call must revert before any returned deployment address can exist.
        // forge-lint: disable-next-line(unused-return)
        script.run();
    }

    function test_preflight_acepta_despliegue_y_participantes_esperados() public view {
        harness.requireDeployment();
    }

    function test_preflight_rechaza_agent_y_challenger_iguales() public {
        vm.expectRevert(bytes("agent and challenger must differ"));
        harness.requireParticipants(agent, agent);
    }

    function test_challenge_commit_acepta_compromiso_abierto_sin_sello() public {
        bytes32 id = _commit(keccak256("open"));
        harness.requireChallengeCommitState(id);
    }

    function test_challenge_commit_rechaza_ventana_cerrada_antes_de_broadcast() public {
        bytes32 id = _commit(keccak256("expired"));
        vm.warp(core.getCommitment(id).windowEnds);

        vm.expectRevert(bytes("commitment window closed"));
        harness.requireChallengeCommitState(id);
    }

    function test_challenge_commit_rechaza_sello_vivo_antes_de_broadcast() public {
        bytes32 id = _commit(keccak256("duplicate-seal"));
        bytes memory evidence = _evidence();
        bytes32 salt = keccak256("live-seal");
        bytes32 sealedHash = core.computeSeal(evidence, salt, challenger);

        vm.prank(challenger);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);

        vm.expectRevert(bytes("challenger already has live seal"));
        harness.requireChallengeCommitState(id);
    }

    function test_withdraw_acepta_credito_legitimo_acumulado() public {
        _createRejectedCredit();
        bytes32 challengedId = _createSuccessfulChallenge(keccak256("winner"));

        assertEq(core.credits(challenger), REWARD + (2 * DEPOSIT));
        assertEq(harness.requireWithdrawState(challengedId), REWARD + (2 * DEPOSIT));
    }

    function _setAddress(string memory name, address value) internal {
        vm.setEnv(name, vm.toString(value));
    }

    function _inputs() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.PolicyInputs({
                policySpecHash: POLICY_HASH, originCommit: ORIGIN, marginBp: 1500
            })
        );
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

    function _invalidEvidence() internal pure returns (bytes memory) {
        return abi.encode(
            AlnitakPolicyBountyRecomputer.Counterexample({
                cards: hex"2e2e14270a1a10",
                potFacingDecision: 503,
                callAmount: 190,
                aggressiveTrace: hex"030f000000000000",
                traceLength: 2
            })
        );
    }

    function _commit(bytes32 salt) internal returns (bytes32) {
        vm.prank(agent);
        return core.commit{value: REWARD}(
            policyId, _inputs(), 0, DissentCore.Comparator.AtMost, "Alnitak River Safety Reference v1", 1 days, salt
        );
    }

    function _createRejectedCredit() internal {
        bytes32 id = _commit(keccak256("rejected"));
        bytes memory evidence = _invalidEvidence();
        bytes32 salt = keccak256("invalid-evidence");
        bytes32 sealedHash = core.computeSeal(evidence, salt, challenger);

        vm.prank(challenger);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal{gas: 30_000_000}(id, _inputs(), evidence, salt);
    }

    function _createSuccessfulChallenge(bytes32 commitSalt) internal returns (bytes32 id) {
        id = _commit(commitSalt);
        bytes memory evidence = _evidence();
        bytes32 salt = keccak256("valid-evidence");
        bytes32 sealedHash = core.computeSeal(evidence, salt, challenger);

        vm.prank(challenger);
        core.challengeCommit{value: DEPOSIT}(id, sealedHash);
        vm.roll(block.number + core.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        core.challengeReveal{gas: 30_000_000}(id, _inputs(), evidence, salt);
    }
}
// forge-lint: disable-end(arbitrary-send-eth)
