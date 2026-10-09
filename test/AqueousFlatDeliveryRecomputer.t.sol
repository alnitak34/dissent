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
    uint256 constant FORK_BLOCK = 111_776_000;
    address constant DEPLOYED = 0x008652FF29d575F4009657805A1D0A0b161DCCd8;

    AqueousFlatDeliveryRecomputer rec;
    address buyer = makeAddr("buyer");
    address agent = makeAddr("agent");
    address other = makeAddr("otherAgent");
    uint256 nonce;

    function setUp() public {
        vm.createSelectFork(vm.envOr("MONAD_RPC_URL", string("https://rpc.monad.xyz")), FORK_BLOCK);
        rec = new AqueousFlatDeliveryRecomputer(address(AQUEOUS));
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
        AqueousFlatDeliveryRecomputer wrong = new AqueousFlatDeliveryRecomputer(USDC);
        vm.expectRevert();
        wrong.recompute(abi.encode(agent, _one(bytes32(uint256(1)))), "");
        vm.expectRevert(AqueousFlatDeliveryRecomputer.ZeroAqueous.selector);
        new AqueousFlatDeliveryRecomputer(makeAddr("eoa"));
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
