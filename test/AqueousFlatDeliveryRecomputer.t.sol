// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DissentCore} from "../src/DissentCore.sol";
import {RecomputerRegistry} from "../src/RecomputerRegistry.sol";
import {AqueousFlatDeliveryRecomputer, IAqueousJobs} from "../src/adapters/AqueousFlatDeliveryRecomputer.sol";

interface IAqueous is IAqueousJobs {
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
    function deliver(bytes32 jobId, bytes32 deliverableHash) external;
    function release(bytes32 jobId) external;
    function settleMetered(bytes32 jobId, uint256 units) external;
    function refund(bytes32 jobId) external;
}

interface IFiatTokenAdmin {
    function pauser() external view returns (address);
    function blacklister() external view returns (address);
    function pause() external;
    function unpause() external;
    function blacklist(address) external;
}

/// From the review of e25e4e9: takes the deposit, then returns true from transfer without paying.
contract ReviewDishonestToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 value) external {
        balanceOf[to] += value;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value);
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
}

interface IERC20Min {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Runs against Monad mainnet at a pinned block: the real Aqueous, the real DissentCore and
///         the real RecomputerRegistry, with jobs opened on the fork. Set MONAD_RPC_URL to an archive
///         endpoint; the default public RPC usually serves recent blocks.
contract AqueousFlatDeliveryRecomputerForkTest is Test {
    IAqueous constant AQUEOUS = IAqueous(0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32);
    address constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    DissentCore constant CORE = DissentCore(0x9D673a8B5EfE76D42593b45972Fa0426648967E1);
    RecomputerRegistry constant REGISTRY = RecomputerRegistry(0x2a26e33CD2118a2D340bbA810e23a8E5CfdE8E38);
    uint256 constant FORK_BLOCK = 111_811_000;
    address constant DEPLOYED = 0x4d1A62869D16AB2Bac95408445129C4927f88457;

    AqueousFlatDeliveryRecomputer rec;
    address buyer = makeAddr("buyer");
    address agent = makeAddr("agent");
    address other = makeAddr("otherAgent");
    uint256 nonce;

    function setUp() public {
        vm.createSelectFork(vm.envOr("MONAD_RPC_URL", string("https://rpc.monad.xyz")), FORK_BLOCK);
        rec = new AqueousFlatDeliveryRecomputer(address(AQUEOUS), USDC);
        deal(USDC, buyer, 100e6);
        vm.prank(buyer);
        IERC20Min(USDC).approve(address(AQUEOUS), type(uint256).max);
    }

    /* ---------------------------------------------------------------- helpers */

    function _job(address forAgent, uint128 pricePerUnit) internal returns (bytes32 id) {
        vm.prank(buyer);
        id = AQUEOUS.createJob(
            IAqueous.Terms({
                agent: forAgent,
                token: USDC,
                amount: 1e6,
                pricePerUnit: pricePerUnit,
                deadline: uint64(block.timestamp + 3 days),
                termsHash: keccak256("terms"),
                salt: bytes32(++nonce)
            })
        );
    }

    function _jobIn(address tok, address forAgent) internal returns (bytes32 id) {
        vm.prank(buyer);
        id = AQUEOUS.createJob(
            IAqueous.Terms({
                agent: forAgent,
                token: tok,
                amount: 1e6,
                pricePerUnit: 0,
                deadline: uint64(block.timestamp + 3 days),
                termsHash: keccak256("terms"),
                salt: bytes32(++nonce)
            })
        );
    }

    function _inputs(bytes32[] memory ids) internal view returns (bytes memory) {
        return abi.encode(agent, ids);
    }

    function _one(bytes32 a) internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](1);
        ids[0] = a;
    }

    function _two(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](2);
        ids[0] = a;
        ids[1] = b;
    }

    function _ev(uint256 i) internal pure returns (bytes memory) {
        return abi.encode(i);
    }

    /* ---------------------------------------------------------------- semantics */

    function test_deployedInstance_isThisSource() public view {
        assertEq(DEPLOYED.codehash, address(rec).codehash, "mainnet bytecode equals this build");
        assertEq(address(AqueousFlatDeliveryRecomputer(DEPLOYED).aqueous()), address(AQUEOUS));
    }

    function test_identity() public view {
        assertEq(rec.scale(), 1);
        assertEq(rec.domain(), keccak256("kanmani.aqueous.flat-paid-without-delivery.v1"));
        assertEq(address(rec.aqueous()), address(AQUEOUS));
        assertEq(rec.token(), USDC);
    }

    function test_openJob_isNotAViolation() public {
        bytes32 j = _job(agent, 0);
        assertEq(rec.recompute(_inputs(_one(j)), ""), 0);
        assertEq(rec.recompute(_inputs(_one(j)), _ev(0)), 0);
    }

    function test_earlySettlement_withoutDelivery_isAViolation() public {
        bytes32 j = _job(agent, 0);
        uint256 before = IERC20Min(USDC).balanceOf(agent);
        vm.prank(buyer);
        AQUEOUS.release(j);
        assertEq(IERC20Min(USDC).balanceOf(agent) - before, 1e6, "Settled paid the agent");
        assertEq(rec.recompute(_inputs(_one(j)), ""), 1);
        assertEq(rec.recompute(_inputs(_one(j)), _ev(0)), 1);
    }

    function test_recordedDelivery_thenSettled_isNotAViolation() public {
        bytes32 j = _job(agent, 0);
        vm.prank(agent);
        AQUEOUS.deliver(j, keccak256("work"));
        vm.prank(buyer);
        AQUEOUS.release(j);
        assertEq(rec.recompute(_inputs(_one(j)), _ev(0)), 0);
    }

    function test_refundedJob_isNotAViolation() public {
        bytes32 j = _job(agent, 0);
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(buyer);
        AQUEOUS.refund(j);
        assertEq(rec.recompute(_inputs(_one(j)), _ev(0)), 0);
    }

    function test_baseCountsEveryListedViolation() public {
        bytes32 a = _job(agent, 0);
        bytes32 b = _job(agent, 0);
        bytes32 c = _job(agent, 0);
        vm.startPrank(buyer);
        AQUEOUS.release(a);
        AQUEOUS.release(c);
        vm.stopPrank();
        bytes32[] memory ids = new bytes32[](3);
        (ids[0], ids[1], ids[2]) = (a, b, c);
        assertEq(rec.recompute(_inputs(ids), ""), 2);
        assertEq(rec.recompute(_inputs(ids), _ev(1)), 0);
        assertEq(rec.recompute(_inputs(ids), _ev(2)), 1);
    }

    /* ---------------------------------------------------------------- input validity */

    function test_meteredJob_isRejected() public {
        bytes32 j = _job(agent, 10_000);
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.MeteredJob.selector, j));
        rec.recompute(_inputs(_one(j)), "");
    }

    function test_meteredSettledForZero_wouldOtherwiseLookLikeAPayment() public {
        bytes32 j = _job(agent, 10_000);
        vm.prank(buyer);
        AQUEOUS.settleMetered(j, 0);
        // State is Settled and deliveredAt is 0, yet nothing was paid. That is why metered is excluded.
        IAqueousJobs.Job memory r = AQUEOUS.jobs(j);
        assertEq(uint8(r.state), uint8(IAqueousJobs.State.Settled));
        assertEq(r.deliveredAt, 0);
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.MeteredJob.selector, j));
        rec.recompute(_inputs(_one(j)), "");
    }

    function test_nonexistentJob_isRejected() public {
        bytes32 ghost = keccak256("no such job");
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.NoSuchJob.selector, ghost));
        rec.recompute(_inputs(_one(ghost)), "");
    }

    function test_wrongAgentJob_isRejected() public {
        bytes32 j = _job(other, 0);
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.WrongAgent.selector, j, other, agent));
        rec.recompute(_inputs(_one(j)), "");
    }

    function test_listBounds() public {
        vm.expectRevert(AqueousFlatDeliveryRecomputer.EmptyList.selector);
        rec.recompute(_inputs(new bytes32[](0)), "");
        bytes32[] memory big = new bytes32[](33);
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.ListTooLong.selector, 33, 32));
        rec.recompute(_inputs(big), "");
        bytes32 j = _job(agent, 0);
        vm.expectRevert(abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.DuplicateJob.selector, j));
        rec.recompute(_inputs(_two(j, j)), "");
    }

    function test_evidenceValidation() public {
        bytes32 j = _job(agent, 0);
        bytes memory inp = _inputs(_one(j));
        (bool ok, bytes32 why) = rec.validateEvidence(inp, _ev(0));
        assertTrue(ok);
        (ok, why) = rec.validateEvidence(inp, _ev(1));
        assertFalse(ok);
        assertEq(why, bytes32("INDEX_OUTSIDE_LIST"));
        (ok, why) = rec.validateEvidence(inp, hex"01");
        assertFalse(ok);
        assertEq(why, bytes32("EVIDENCE_NOT_ONE_WORD"));
    }

    function test_badEvidenceInRecompute_isAFault_notAZero() public {
        bytes32 j = _job(agent, 0);
        vm.expectRevert(AqueousFlatDeliveryRecomputer.BadEvidence.selector);
        rec.recompute(_inputs(_one(j)), _ev(5));
    }

    function test_failedAqueousRead_reverts_neverAZero() public {
        // An address with code that is not Aqueous: the read fails and recompute reverts.
        AqueousFlatDeliveryRecomputer wrong = new AqueousFlatDeliveryRecomputer(USDC, USDC);
        vm.expectRevert();
        wrong.recompute(abi.encode(agent, _one(bytes32(uint256(1)))), "");
        vm.expectRevert(AqueousFlatDeliveryRecomputer.ZeroAqueous.selector);
        new AqueousFlatDeliveryRecomputer(makeAddr("eoa"), USDC);
        vm.expectRevert(AqueousFlatDeliveryRecomputer.ZeroToken.selector);
        new AqueousFlatDeliveryRecomputer(address(AQUEOUS), makeAddr("eoa2"));
    }

    /* ---------------------------------------------------------------- token (review of e25e4e9) */

    /// The reviewer's case: the job settles with no payment to the agent. It must never count.
    function test_review_unpaidTokenIsRejected_atCommitAndInEvidence() public {
        ReviewDishonestToken bad = new ReviewDishonestToken();
        bad.mint(buyer, 10e6);
        bytes32 j = _jobIn(address(bad), agent);
        bytes32 good = _job(agent, 0);

        // Base: refused, so a commit cannot include it.
        vm.expectRevert(
            abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.WrongToken.selector, j, address(bad), USDC)
        );
        rec.recompute(_inputs(_one(j)), "");
        bytes32 policyId = _registerPolicy();
        vm.deal(agent, 1 ether);
        vm.prank(agent);
        vm.expectRevert(DissentCore.RecomputerReverted.selector);
        CORE.commit{value: 0.5 ether}(
            policyId, _inputs(_one(j)), 0, DissentCore.Comparator.AtMost, "x", 1 days, bytes32("s")
        );

        // After the fake payment the job is Settled with no delivery and the agent got nothing.
        vm.prank(buyer);
        AQUEOUS.release(j);
        assertEq(bad.balanceOf(agent), 0);
        assertEq(uint8(AQUEOUS.jobs(j).state), uint8(IAqueousJobs.State.Settled));
        // Evidence path: a list that mixes it in reverts on any index, so it can only fault, never pay.
        vm.expectRevert(
            abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.WrongToken.selector, j, address(bad), USDC)
        );
        rec.recompute(_inputs(_two(good, j)), _ev(0));
        vm.expectRevert(
            abi.encodeWithSelector(AqueousFlatDeliveryRecomputer.WrongToken.selector, j, address(bad), USDC)
        );
        rec.recompute(_inputs(_two(good, j)), _ev(1));
    }

    function test_pinnedUsdc_pausedOrBlacklisted_releaseReverts_noUnpaidSettled() public {
        bytes32 a = _job(agent, 0);
        bytes32 b = _job(agent, 0);
        IFiatTokenAdmin t = IFiatTokenAdmin(USDC);

        vm.prank(t.pauser());
        t.pause();
        vm.prank(buyer);
        vm.expectRevert();
        AQUEOUS.release(a);
        vm.prank(t.pauser());
        t.unpause();

        vm.prank(t.blacklister());
        t.blacklist(agent);
        vm.prank(buyer);
        vm.expectRevert();
        AQUEOUS.release(b);

        assertEq(uint8(AQUEOUS.jobs(a).state), uint8(IAqueousJobs.State.Open));
        assertEq(uint8(AQUEOUS.jobs(b).state), uint8(IAqueousJobs.State.Open));
        assertEq(rec.recompute(_inputs(_two(a, b)), ""), 0);
    }

    function test_pinnedUsdc_overdraftReverts() public {
        address poor = makeAddr("poor");
        vm.prank(poor);
        vm.expectRevert();
        IERC20Min(USDC).transfer(agent, 1);
    }

    /* ---------------------------------------------------------------- buyer control */

    /// Allowed escrow behaviour: a listed buyer releases early and collects the bounty. It shows a buyer
    /// paid before a delivery record, not agent misconduct, and the agent was paid the full amount.
    function test_buyerControl_listedBuyerCanBreakTheClaim() public {
        bytes32 policyId = _registerPolicy();
        bytes32 j = _job(agent, 0);
        bytes memory inp = _inputs(_one(j));
        (bytes32 id, uint256 reward) = _commit(policyId, inp);
        uint256 agentUsdc = IERC20Min(USDC).balanceOf(agent);

        vm.prank(buyer);
        AQUEOUS.release(j);
        uint256 dep = uint256(CORE.getCommitment(id).deposit);
        _challenge(id, inp, _ev(0), buyer);
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Challenged));
        uint256 before = buyer.balance;
        vm.prank(buyer);
        CORE.withdrawCredit();
        assertEq(buyer.balance - before, reward + dep, "the buyer collects the bounty");
        assertEq(IERC20Min(USDC).balanceOf(agent) - agentUsdc, 1e6, "and paid the agent the full job amount");
    }

    function test_release_isPossibleAfterDeadline_untilRefunded() public {
        bytes32 j = _job(agent, 0);
        vm.warp(block.timestamp + 3 days + 1);
        vm.prank(buyer);
        AQUEOUS.release(j);
        assertEq(rec.recompute(_inputs(_one(j)), ""), 1, "exposure lasts while the job is Open");
    }

    /* ---------------------------------------------------------------- worst-case gas, cold */

    function test_maxList_fullFlow_cold_underProposedCaps() public {
        bytes32 policyId = _registerPolicy();
        bytes32[] memory ids = new bytes32[](32);
        for (uint256 i; i < 32; ++i) {
            ids[i] = _job(agent, 0);
        }
        bytes memory inp = _inputs(ids);

        (bytes32 id, uint256 reward) = _commit(policyId, inp);
        emit log_named_uint("base recompute gas measured by DissentCore at commit", CORE.getCommitment(id).baseGas);
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Open), "commit did not fault");

        vm.prank(buyer);
        AQUEOUS.release(ids[31]);

        address challenger = makeAddr("challenger");
        uint256 dep = uint256(CORE.getCommitment(id).deposit);
        bytes32 seal = CORE.computeSeal(_ev(31), bytes32("salt"), challenger);
        vm.deal(challenger, dep + 1 ether);
        vm.prank(challenger);
        CORE.challengeCommit{value: dep}(id, seal);
        vm.roll(block.number + CORE.REVEAL_DELAY_BLOCKS());
        vm.prank(challenger);
        CORE.challengeReveal(id, inp, _ev(31), bytes32("salt"));
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Challenged), "no fault, challenger won");
        vm.prank(challenger);
        CORE.withdrawCredit();
        assertEq(challenger.balance, reward + dep + 1 ether);
    }

    /* ---------------------------------------------------------------- scope and stability */

    function test_settledRecord_cannotChange() public {
        bytes32 j = _job(agent, 0);
        vm.prank(buyer);
        AQUEOUS.release(j);
        vm.prank(agent);
        vm.expectRevert();
        AQUEOUS.deliver(j, keccak256("late"));
        vm.prank(buyer);
        vm.expectRevert();
        AQUEOUS.release(j);
        assertEq(rec.recompute(_inputs(_one(j)), _ev(0)), 1, "still a violation");
    }

    function test_aJobOpenedAfterCommit_cannotBeUsed() public {
        bytes32 listed = _job(agent, 0);
        bytes memory inp = _inputs(_one(listed));
        assertEq(rec.recompute(inp, ""), 0);
        // A challenger manufactures a violation on a new job for the same agent.
        bytes32 fresh = _job(agent, 0);
        vm.prank(buyer);
        AQUEOUS.release(fresh);
        // The committed inputs still describe only `listed`, and no index reaches `fresh`.
        assertEq(rec.recompute(inp, ""), 0);
        (bool ok,) = rec.validateEvidence(inp, _ev(1));
        assertFalse(ok);
    }

    /* ---------------------------------------------------------------- gas */

    /// Warm figures: the jobs were just created and the evidence call runs after the base read. For the
    /// cold worst case see test_maxList_fullFlow_cold_underProposedCaps.
    function test_gasPerListedJob() public {
        uint256[3] memory sizes = [uint256(1), 8, 32];
        for (uint256 s; s < 3; ++s) {
            bytes32[] memory ids = new bytes32[](sizes[s]);
            for (uint256 i; i < sizes[s]; ++i) {
                ids[i] = _job(agent, 0);
            }
            bytes memory inp = _inputs(ids);
            uint256 g = gasleft();
            rec.recompute(inp, "");
            uint256 base = g - gasleft();
            g = gasleft();
            rec.recompute(inp, _ev(sizes[s] - 1));
            uint256 one = g - gasleft();
            emit log_named_uint(string.concat("jobs ", vm.toString(sizes[s]), " base gas"), base);
            emit log_named_uint(string.concat("jobs ", vm.toString(sizes[s]), " evidence gas"), one);
            assertLt(base, 1_500_000, "fits a 1.5M recompute gas limit");
        }
    }

    /* ---------------------------------------------------------------- the whole Dissent flow */

    function _registerPolicy() internal returns (bytes32 policyId) {
        vm.prank(REGISTRY.curator());
        policyId = REGISTRY.registerPolicy(address(rec), 0.1 ether, 1_500_000, 200_000, 32);
    }

    function _commit(bytes32 policyId, bytes memory inp) internal returns (bytes32 id, uint256 reward) {
        reward = CORE.minGasBackedReward(200_000, 1_500_000, inp.length, 32);
        if (reward < 0.5 ether) reward = 0.5 ether;
        vm.deal(agent, reward + 1 ether);
        vm.prank(agent);
        id = CORE.commit{value: reward}(
            policyId,
            inp,
            0,
            DissentCore.Comparator.AtMost,
            "no flat Aqueous job paid me before I delivered",
            1 days,
            bytes32("s")
        );
    }

    function _challenge(bytes32 id, bytes memory inp, bytes memory evidence, address who) internal {
        DissentCore.Commitment memory c = CORE.getCommitment(id);
        vm.deal(who, uint256(c.deposit) + 1 ether);
        bytes32 seal = CORE.computeSeal(evidence, bytes32("salt"), who); // before the prank, which one call consumes
        vm.prank(who);
        CORE.challengeCommit{value: c.deposit}(id, seal);
        vm.roll(block.number + CORE.REVEAL_DELAY_BLOCKS());
        vm.prank(who);
        CORE.challengeReveal(id, inp, evidence, bytes32("salt"));
    }

    function test_fullFlow_earlyRelease_challengerWins() public {
        bytes32 policyId = _registerPolicy();
        bytes32 j = _job(agent, 0);
        bytes memory inp = _inputs(_one(j));
        (bytes32 id, uint256 reward) = _commit(policyId, inp);

        vm.prank(buyer);
        AQUEOUS.release(j); // the record breaks after the commit

        address challenger = makeAddr("challenger");
        uint256 dep = uint256(CORE.getCommitment(id).deposit);
        _challenge(id, inp, _ev(0), challenger);
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Challenged));

        uint256 before = challenger.balance;
        vm.prank(challenger);
        CORE.withdrawCredit();
        assertEq(challenger.balance - before, reward + dep, "bounty plus deposit");
    }

    function test_fullFlow_deliveredThenReleased_challengerLoses() public {
        bytes32 policyId = _registerPolicy();
        bytes32 j = _job(agent, 0);
        bytes memory inp = _inputs(_one(j));
        (bytes32 id,) = _commit(policyId, inp);
        vm.prank(agent);
        AQUEOUS.deliver(j, keccak256("work"));
        vm.prank(buyer);
        AQUEOUS.release(j);
        _challenge(id, inp, _ev(0), makeAddr("challenger"));
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Open), "claim holds");
    }

    function test_fullFlow_violationBeforeCommit_isRefusedAtCommit() public {
        bytes32 policyId = _registerPolicy();
        bytes32 j = _job(agent, 0);
        vm.prank(buyer);
        AQUEOUS.release(j);
        bytes memory inp = _inputs(_one(j));
        uint256 reward = 1 ether;
        vm.deal(agent, reward);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(DissentCore.BaseDoesNotSatisfyThreshold.selector, int256(1), int256(0)));
        CORE.commit{value: reward}(policyId, inp, 0, DissentCore.Comparator.AtMost, "x", 1 days, bytes32("s"));
    }

    function test_fullFlow_outOfListEvidence_isRejectedAndRefunded() public {
        bytes32 policyId = _registerPolicy();
        bytes32 j = _job(agent, 0);
        bytes memory inp = _inputs(_one(j));
        (bytes32 id,) = _commit(policyId, inp);
        address challenger = makeAddr("challenger");
        uint256 dep = uint256(CORE.getCommitment(id).deposit);
        _challenge(id, inp, _ev(3), challenger);
        assertEq(uint8(CORE.getCommitment(id).status), uint8(DissentCore.Status.Open));
        uint256 before = challenger.balance;
        vm.prank(challenger);
        CORE.withdrawCredit();
        assertEq(challenger.balance - before, dep, "deposit returned on a rejected challenge");
    }
}
