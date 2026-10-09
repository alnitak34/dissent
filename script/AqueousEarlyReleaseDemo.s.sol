// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {IRecomputerRegistry} from "../src/IRecomputerRegistry.sol";
import {RecomputerRegistry} from "../src/RecomputerRegistry.sol";
import {AqueousFlatDeliveryRecomputer, IAqueousJobs} from "../src/adapters/AqueousFlatDeliveryRecomputer.sol";

interface IAqueousDemo is IAqueousJobs {
    struct Terms {
        address agent;
        address token;
        uint128 amount;
        uint128 pricePerUnit;
        uint64 deadline;
        bytes32 termsHash;
        bytes32 salt;
    }

    function createJob(Terms calldata t) external returns (bytes32 jobId);
    function release(bytes32 jobId) external;
    function jobIdFor(address buyer, address agent, bytes32 salt) external pure returns (bytes32);
}

interface IERC20Demo {
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
}

/// @notice Coordinated demonstration of the Aqueous flat-delivery rule: one flat USDC job is released
///         early on purpose and an independent challenger proves it. See
///         docs/demo/aqueous-early-release.md for the full sequence and the fork rehearsal.
///
/// Every contract below is one participant's single transaction. Without `--broadcast` forge only
/// simulates, so broadcasting is opt-in per step. Addresses, the reward and all salts come from the
/// environment; salts never live in this repository.
///
/// The challenger defaults to nothing. The rehearsal uses TEST_ONLY_CHALLENGER, a placeholder with no
/// known key. Only the challenger steps (seal, reveal, withdraw) read DEMO_CHALLENGER, and they refuse
/// the placeholder unless DEMO_REHEARSAL=true. That flag is an operator override: the script cannot
/// tell a local fork from mainnet, so it does not prove the RPC is local.
abstract contract AqueousEarlyReleaseDemoBase is Script {
    uint256 internal constant MONAD_MAINNET_CHAIN_ID = 143;

    DissentCore internal constant CORE = DissentCore(0x9D673a8B5EfE76D42593b45972Fa0426648967E1);
    RecomputerRegistry internal constant REGISTRY = RecomputerRegistry(0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38);
    AqueousFlatDeliveryRecomputer internal constant RECOMPUTER =
        AqueousFlatDeliveryRecomputer(0x4d1A62869D16AB2Bac95408445129C4927f88457);
    IAqueousDemo internal constant AQUEOUS = IAqueousDemo(0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32);
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    uint128 internal constant DEPOSIT = 0.1 ether;
    uint32 internal constant RECOMPUTE_GAS_LIMIT = 1_500_000;
    uint32 internal constant VALIDATE_GAS_LIMIT = 200_000;
    uint32 internal constant MAX_EVIDENCE_LEN = 32;

    uint128 internal constant JOB_AMOUNT = 100_000; // 0.10 USDC
    uint64 internal constant JOB_DURATION = 3 days;
    /// keccak256 of the bytes of docs/demo/aqueous-early-release.terms.txt
    bytes32 internal constant TERMS_HASH = 0x6661ad444cb7963a313a077b89755439c73b96fc48a459bedeb52b42c1057db7;

    int256 internal constant THRESHOLD = 0;
    uint64 internal constant WINDOW = 2 hours;
    string internal constant ACTION = "Kanmani x Dissent coordinated demo: Aqueous early release v1";

    /// Test-only placeholder. Nobody holds a key for it; it exists so the rehearsal never needs a real
    /// challenger address. The challenger steps refuse it unless DEMO_REHEARSAL=true.
    address internal constant TEST_ONLY_CHALLENGER =
        address(uint160(uint256(keccak256("dissent.demo.challenger.TEST-ONLY-PLACEHOLDER"))));

    function _agent() internal view returns (address) {
        return vm.envAddress("DEMO_AGENT");
    }

    function _buyer() internal view returns (address) {
        return vm.envAddress("DEMO_BUYER");
    }

    function _challenger() internal view returns (address c) {
        c = vm.envAddress("DEMO_CHALLENGER");
        require(c != address(0), "challenger is empty");
        if (c == TEST_ONLY_CHALLENGER) require(vm.envOr("DEMO_REHEARSAL", false), "placeholder is rehearsal only");
    }

    function _reward() internal view returns (uint256) {
        return vm.envUint("DEMO_REWARD_WEI");
    }

    function _jobSalt() internal view returns (bytes32 s) {
        s = vm.envBytes32("DEMO_JOB_SALT");
        require(s != bytes32(0), "empty job salt");
    }

    function _jobId() internal view returns (bytes32) {
        return AQUEOUS.jobIdFor(_buyer(), _agent(), _jobSalt());
    }

    function _policyId() internal view returns (bytes32) {
        return REGISTRY.computePolicyId(
            address(RECOMPUTER),
            address(RECOMPUTER).codehash,
            DEPOSIT,
            RECOMPUTE_GAS_LIMIT,
            VALIDATE_GAS_LIMIT,
            MAX_EVIDENCE_LEN
        );
    }

    function _inputs() internal view returns (bytes memory) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = _jobId();
        return abi.encode(_agent(), ids);
    }

    function _evidence() internal pure returns (bytes memory) {
        return abi.encode(uint256(0));
    }

    function _requireDeployment() internal view {
        require(block.chainid == MONAD_MAINNET_CHAIN_ID, "only Monad Mainnet 143 or a fork of it");
        require(address(CORE.registry()) == address(REGISTRY), "unexpected registry");
        require(address(RECOMPUTER.aqueous()) == address(AQUEOUS), "unexpected Aqueous");
        require(RECOMPUTER.token() == USDC, "unexpected token");
        require(RECOMPUTER.scale() == 1, "unexpected scale");
        require(RECOMPUTER.domain() == keccak256("kanmani.aqueous.flat-paid-without-delivery.v1"), "unexpected domain");
        address agent = _agent();
        address buyer = _buyer();
        require(agent != address(0) && buyer != address(0), "empty participant");
        require(agent != buyer, "agent and buyer must differ");
    }

    function _requirePolicy() internal view {
        IRecomputerRegistry.Policy memory p = REGISTRY.getPolicy(_policyId());
        require(p.active, "policy not registered or inactive");
        require(p.recomputer == address(RECOMPUTER), "unexpected policy recomputer");
        require(p.codeHash == address(RECOMPUTER).codehash, "unexpected policy codehash");
    }

    function _requireSender(address expected) internal view {
        // forge-lint: disable-next-line(unused-return)
        (, address sender,) = vm.readCallers();
        require(sender == expected, "wrong signing account");
    }

    function _job() internal view returns (IAqueousJobs.Job memory) {
        return AQUEOUS.jobs(_jobId());
    }

    function _commitment() internal view returns (bytes32 id, DissentCore.Commitment memory c) {
        id = vm.envBytes32("DEMO_COMMITMENT_ID");
        c = CORE.getCommitment(id);
        require(c.agent == _agent(), "unexpected commitment agent");
        require(c.policyId == _policyId(), "unexpected commitment policy");
        require(c.inputsHash == keccak256(_inputs()), "unexpected commitment inputs");
        require(c.threshold == THRESHOLD && c.comparator == DissentCore.Comparator.AtMost, "unexpected claim");
        require(c.reward == _reward(), "unexpected reward");
        require(c.actionHash == keccak256(bytes(ACTION)), "unexpected action");
    }
}

/// Step 1, curator: register the reviewed policy.
contract DemoRegisterPolicy is AqueousEarlyReleaseDemoBase {
    function run() external returns (bytes32 policyId) {
        _requireDeployment();
        policyId = _policyId();
        require(REGISTRY.getPolicy(policyId).recomputer == address(0), "policy already registered");
        vm.startBroadcast();
        _requireSender(REGISTRY.curator());
        policyId = REGISTRY.registerPolicy(
            address(RECOMPUTER), DEPOSIT, RECOMPUTE_GAS_LIMIT, VALIDATE_GAS_LIMIT, MAX_EVIDENCE_LEN
        );
        vm.stopBroadcast();
        console.log("policy id:");
        console.logBytes32(policyId);
    }
}

/// Step 2, buyer: approve exactly the job amount to Aqueous.
contract DemoBuyerApprove is AqueousEarlyReleaseDemoBase {
    function run() external {
        _requireDeployment();
        require(IERC20Demo(USDC).balanceOf(_buyer()) >= JOB_AMOUNT, "buyer has under 0.10 USDC");
        vm.startBroadcast();
        _requireSender(_buyer());
        require(IERC20Demo(USDC).approve(address(AQUEOUS), JOB_AMOUNT), "approve failed");
        vm.stopBroadcast();
    }
}

/// Step 3, buyer: open the flat job. Its id is fixed by buyer, agent and DEMO_JOB_SALT.
contract DemoBuyerOpenJob is AqueousEarlyReleaseDemoBase {
    function run() external returns (bytes32 jobId) {
        _requireDeployment();
        _requirePolicy();
        require(_job().state == IAqueousJobs.State.None, "job already exists");
        require(IERC20Demo(USDC).allowance(_buyer(), address(AQUEOUS)) >= JOB_AMOUNT, "approve first");
        IAqueousDemo.Terms memory t = IAqueousDemo.Terms({
            agent: _agent(),
            token: USDC,
            amount: JOB_AMOUNT,
            pricePerUnit: 0,
            deadline: uint64(block.timestamp) + JOB_DURATION,
            termsHash: TERMS_HASH,
            salt: _jobSalt()
        });
        vm.startBroadcast();
        _requireSender(_buyer());
        jobId = AQUEOUS.createJob(t);
        vm.stopBroadcast();
        require(jobId == _jobId(), "unexpected job id");
        console.log("job id:");
        console.logBytes32(jobId);
    }
}

/// Step 4, agent: commit the bounty over the one-job list. The base must read 0.
contract DemoAgentCommit is AqueousEarlyReleaseDemoBase {
    function run() external returns (bytes32 id) {
        _requireDeployment();
        _requirePolicy();
        IAqueousJobs.Job memory j = _job();
        require(j.state == IAqueousJobs.State.Open && j.deliveredAt == 0, "job is not Open and undelivered");
        bytes memory inputs = _inputs();
        require(RECOMPUTER.recompute(inputs, "") == 0, "base is not 0");
        uint256 reward = _reward();
        uint256 minimum =
            CORE.minGasBackedReward(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN);
        require(reward >= minimum, "reward below current onchain minimum");
        bytes32 salt = vm.envBytes32("DEMO_AGENT_SALT");
        require(salt != bytes32(0), "empty agent salt");
        vm.startBroadcast();
        _requireSender(_agent());
        // forge-lint: disable-start(arbitrary-send-eth)
        id = CORE.commit{value: reward}(
            _policyId(), inputs, THRESHOLD, DissentCore.Comparator.AtMost, ACTION, WINDOW, salt
        );
        // forge-lint: disable-end(arbitrary-send-eth)
        vm.stopBroadcast();
        DissentCore.Commitment memory c = CORE.getCommitment(id);
        console.log("minGasBackedReward", minimum);
        console.log("base value", uint256(c.baseValue));
        console.log("base gas", uint256(c.baseGas));
        console.log("window ends", uint256(c.windowEnds));
        console.log(
            "txRequired for reveal",
            CORE.txRequired(VALIDATE_GAS_LIMIT, RECOMPUTE_GAS_LIMIT, inputs.length, MAX_EVIDENCE_LEN)
        );
        console.log("simulated commitment id (the Committed event is authoritative):");
        console.logBytes32(id);
    }
}

/// Step 5, buyer: release the payment early, with no delivery recorded.
contract DemoBuyerReleaseEarly is AqueousEarlyReleaseDemoBase {
    function run() external {
        _requireDeployment();
        (, DissentCore.Commitment memory c) = _commitment();
        require(c.status == DissentCore.Status.Open, "commitment is not Open");
        IAqueousJobs.Job memory j = _job();
        require(j.state == IAqueousJobs.State.Open && j.deliveredAt == 0, "job is not Open and undelivered");
        uint256 before = IERC20Demo(USDC).balanceOf(_agent());
        vm.startBroadcast();
        _requireSender(_buyer());
        AQUEOUS.release(_jobId());
        vm.stopBroadcast();
        require(IERC20Demo(USDC).balanceOf(_agent()) - before == JOB_AMOUNT, "agent was not paid");
        console.log("agent paid USDC units", uint256(JOB_AMOUNT));
        console.log("recompute with evidence index 0", uint256(RECOMPUTER.recompute(_inputs(), _evidence())));
    }
}

/// Step 6, challenger: seal the evidence (index 0).
contract DemoChallengerSeal is AqueousEarlyReleaseDemoBase {
    function run() external returns (bytes32 sealedHash) {
        _requireDeployment();
        (bytes32 id, DissentCore.Commitment memory c) = _commitment();
        require(c.status == DissentCore.Status.Open, "commitment is not Open");
        require(block.timestamp < c.windowEnds, "window closed");
        address challenger = _challenger();
        require(challenger != _agent() && challenger != _buyer(), "challenger must be independent");
        (bool ok,) = RECOMPUTER.validateEvidence(_inputs(), _evidence());
        require(ok, "evidence rejected");
        require(RECOMPUTER.recompute(_inputs(), _evidence()) == 1, "no violation to prove");
        bytes32 salt = vm.envBytes32("DEMO_CHALLENGER_SALT");
        require(salt != bytes32(0), "empty challenger salt");
        sealedHash = CORE.computeSeal(_evidence(), salt, challenger);
        vm.startBroadcast();
        _requireSender(challenger);
        // forge-lint: disable-next-line(arbitrary-send-eth)
        CORE.challengeCommit{value: c.deposit}(id, sealedHash);
        vm.stopBroadcast();
        console.log("sealed at block", block.number);
    }
}

/// Step 7, challenger: reveal 5 or more blocks after the seal.
contract DemoChallengerReveal is AqueousEarlyReleaseDemoBase {
    function run() external {
        _requireDeployment();
        (bytes32 id,) = _commitment();
        address challenger = _challenger();
        bytes32 salt = vm.envBytes32("DEMO_CHALLENGER_SALT");
        DissentCore.Seal memory s = CORE.getSeal(id, challenger);
        require(s.sealedHash == CORE.computeSeal(_evidence(), salt, challenger), "salt does not match seal");
        require(s.blockNumber != 0 && !s.settled, "seal missing or settled");
        require(block.number >= s.blockNumber + CORE.REVEAL_DELAY_BLOCKS(), "too early to reveal");
        vm.startBroadcast();
        _requireSender(challenger);
        CORE.challengeReveal(id, _inputs(), _evidence(), salt);
        vm.stopBroadcast();
        DissentCore.Commitment memory c = CORE.getCommitment(id);
        require(c.status == DissentCore.Status.Challenged, "challenge did not succeed");
        console.log("status Challenged; challenger credit", CORE.credits(challenger));
    }
}

/// Step 8, challenger: withdraw reward plus deposit.
contract DemoChallengerWithdraw is AqueousEarlyReleaseDemoBase {
    function run() external {
        _requireDeployment();
        (, DissentCore.Commitment memory c) = _commitment();
        require(c.status == DissentCore.Status.Challenged, "commitment was not challenged");
        address challenger = _challenger();
        uint256 credit = CORE.credits(challenger);
        require(credit >= uint256(c.reward) + uint256(c.deposit), "credit below reward plus deposit");
        uint256 before = challenger.balance;
        vm.startBroadcast();
        _requireSender(challenger);
        CORE.withdrawCredit();
        vm.stopBroadcast();
        console.log("withdrawn wei", challenger.balance - before);
    }
}
