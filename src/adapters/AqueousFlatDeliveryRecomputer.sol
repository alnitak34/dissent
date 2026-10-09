// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "../IRecomputer.sol";

/// @notice The read-only slice of Kanmani's Aqueous escrow this recomputer uses.
/// @dev Aqueous on Monad mainnet: 0xd75f7786D0DD42c8F161Bd78E87D37001044Fc32, Sourcify exact match,
///      source revision 190e91f of github.com/zkasuran/kanmani (contracts/src/Aqueous.sol).
interface IAqueousJobs {
    enum State {
        None,
        Open,
        Delivered,
        Settled,
        Refunded
    }

    struct Job {
        address buyer;
        uint64 deadline;
        State state;
        address agent;
        uint64 deliveredAt;
        address token;
        uint128 amount;
        uint128 pricePerUnit;
        bytes32 termsHash;
        bytes32 deliverableHash;
    }

    function jobs(bytes32 jobId) external view returns (Job memory);
}

/// @title AqueousFlatDeliveryRecomputer
/// @notice Claim: "No listed flat USDC Aqueous job will pay this agent before an onchain delivery record."
///
/// WHAT IT CHECKS, FROM THE AQUEOUS SOURCE
/// A flat job (pricePerUnit == 0) reaches Settled only by `release` / `releaseWithAuthorization`
/// (buyer, from Open or Delivered, pays `amount` to `agent`) or by `claimDelivered` (agent, requires
/// Delivered). `settleMetered` reverts NotMetered on a flat job and opening reverts ZeroAmount, so a
/// flat Settled job always paid `amount > 0` to that agent. `deliveredAt` is written only by `deliver()`
/// and never reset, and Settled is terminal. So flat + Settled + deliveredAt == 0 means exactly "the
/// buyer released payment with no onchain delivery record", and once true it stays true. It says
/// nothing about work quality or delivery through another channel.
///
/// SCOPE: AN EXPLICIT LIST FIXED AT COMMIT, NOT A CUTOFF
/// Aqueous stores no creation block and anyone can open a job naming any agent, so a cutoff would let a
/// challenger open a fresh flat job for the agent after the commit and release it at once. The claim
/// therefore covers exactly the job ids in `inputs`, which DissentCore binds by hash at commit. Evidence
/// can only point inside that list. The recomputer cannot prove the list is complete: no per-agent job
/// index is readable from a contract. Completeness is checkable off chain from Aqueous `JobCreated`
/// logs, whose `agent` topic is indexed. The claim is "none of these N jobs", not "none of this agent's".
///
/// INTERFACE
///   inputs   abi.encode(address agent, bytes32[] jobIds), 1 to MAX_JOBS ids, no duplicates. Every id
///            must exist, name `agent`, be flat and use `token`, or recompute reverts (so commit
///            reverts).
///   evidence abi.encode(uint256 index), an index into jobIds. Empty at commit.
///   recompute(inputs, "")       the number of listed jobs in violation. It reads the whole list, so a
///                               0 does mean every listed job was inspected.
///   recompute(inputs, evidence) 1 if jobIds[index] is in violation, else 0.
///   threshold                   0 with Comparator.AtMost.
///   scale 1 (an integer count). A failed read of Aqueous reverts and lands on DissentCore's fault
///   path. It is never returned as a clean 0.
///
/// TOKEN: ONE PINNED, REVIEWED TOKEN
/// Aqueous pays with `IERC20(token).transfer` and trusts its boolean return. A token that returns true
/// without moving balances would make a job Settled while the agent received nothing. So every listed
/// job must use the immutable `token`, in both the base and the evidence computation. The deployment
/// pins Circle's native USDC on Monad, 0x754704Bc059F8C67012fEd69BC8A327a5aafb603 (listed at
/// developers.circle.com/stablecoins/usdc-contract-addresses). Trust assumptions: it is an upgradeable
/// FiatToken proxy, so Circle could change its transfer semantics; Circle's blacklister or pauser can
/// pause it or blacklist the agent. The proxy is Sourcify verified (FiatTokenProxy, version() "2"); the
/// implementation behind it, 0xbd520ea8cbb4f81b62aff3c3ffe7affd69800b6d, is not on Sourcify. The fork
/// tests check its behaviour at the pinned block instead: release moves exactly `amount` to the agent,
/// and with the token paused or the agent blacklisted release reverts, so no Settled state appears
/// without a payment.
///
/// BUYER CONTROL: A PROSPECTIVE PROMISE OVER THE COMMITTED LIST
/// Commit refuses a list that already holds a violation (the base must be 0). So the campaign is a
/// promise about what happens next to the listed jobs: none of them will be released before the agent
/// records delivery. `release` is the buyer's call. Aqueous lets the buyer release an Open job at any
/// time, also after its deadline, until it is refunded. A listed buyer can therefore break the claim on
/// purpose and challenge it. That is allowed escrow behaviour, and a successful challenge alone does not
/// show agent misconduct; it shows that a listed buyer paid before a delivery record. The agent should
/// list only jobs whose buyers it knows, or keep the reward at or below the smallest listed `amount`:
/// a buyer who forces a violation then pays the agent at least as much as the bounty it collects.
///
/// TIMING (DissentCore rules, not this contract's)
/// A job is exposed while it is Open. It stops being exposed once it is Delivered (deliveredAt is set
/// for good), Refunded or Settled. Challengers seal before `windowEnds` (commit time + `window`, at least
/// 1 hour) and reveal 5 to 7,205 blocks after their seal; a live seal blocks the agent's reclaim. An
/// agent who wants the promise to cover every listed job until it is delivered or refundable should set
/// `window` past the latest listed deadline.
///
/// LIMIT: metered jobs are excluded. A metered Settled job does not store how much was paid (only the
/// Settled event carries it), so one settled for 0 units would look like a payment.
contract AqueousFlatDeliveryRecomputer is IRecomputer {
    IAqueousJobs public immutable aqueous;
    address public immutable token;

    uint256 public constant MAX_JOBS = 32;
    bytes32 public constant DOMAIN = keccak256("kanmani.aqueous.flat-paid-without-delivery.v1");

    bytes32 private constant REASON_BAD_LENGTH = "EVIDENCE_NOT_ONE_WORD";
    bytes32 private constant REASON_OUT_OF_LIST = "INDEX_OUTSIDE_LIST";

    error ZeroAqueous();
    error ZeroToken();
    error WrongToken(bytes32 jobId, address recorded, address pinned);
    error EmptyList();
    error ListTooLong(uint256 length, uint256 max);
    error DuplicateJob(bytes32 jobId);
    error NoSuchJob(bytes32 jobId);
    error WrongAgent(bytes32 jobId, address recorded, address claimed);
    error MeteredJob(bytes32 jobId);
    error BadEvidence();

    constructor(address aqueous_, address token_) {
        if (aqueous_ == address(0) || aqueous_.code.length == 0) revert ZeroAqueous();
        if (token_ == address(0) || token_.code.length == 0) revert ZeroToken();
        aqueous = IAqueousJobs(aqueous_);
        token = token_;
    }

    function scale() external pure returns (uint256) {
        return 1;
    }

    function domain() external pure returns (bytes32) {
        return DOMAIN;
    }

    function validateEvidence(bytes calldata inputs, bytes calldata evidence)
        external
        pure
        returns (bool ok, bytes32 reason)
    {
        if (evidence.length != 32) return (false, REASON_BAD_LENGTH);
        (, bytes32[] memory ids) = abi.decode(inputs, (address, bytes32[]));
        uint256 index = abi.decode(evidence, (uint256));
        if (index >= ids.length) return (false, REASON_OUT_OF_LIST);
        return (true, bytes32(0));
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external view returns (int256) {
        (address agent, bytes32[] memory ids) = abi.decode(inputs, (address, bytes32[]));
        _checkList(ids);

        if (evidence.length == 0) {
            int256 count;
            for (uint256 i; i < ids.length; ++i) {
                if (_violates(agent, ids[i])) ++count;
            }
            return count;
        }

        // validateEvidence runs first in DissentCore, so a bad shape here is a fault, not a clean 0.
        if (evidence.length != 32) revert BadEvidence();
        uint256 index = abi.decode(evidence, (uint256));
        if (index >= ids.length) revert BadEvidence();
        // The whole list is re-read so a job that stopped being eligible can never be hidden behind an
        // index. It cannot happen with Aqueous (agent and price are immutable) and costs little.
        for (uint256 i; i < ids.length; ++i) {
            if (i != index) _eligible(agent, ids[i]);
        }
        return _violates(agent, ids[index]) ? int256(1) : int256(0);
    }

    function _checkList(bytes32[] memory ids) private pure {
        if (ids.length == 0) revert EmptyList();
        if (ids.length > MAX_JOBS) revert ListTooLong(ids.length, MAX_JOBS);
        for (uint256 i; i < ids.length; ++i) {
            for (uint256 j = i + 1; j < ids.length; ++j) {
                if (ids[i] == ids[j]) revert DuplicateJob(ids[i]);
            }
        }
    }

    function _eligible(address agent, bytes32 jobId) private view returns (IAqueousJobs.Job memory j) {
        j = aqueous.jobs(jobId);
        if (j.state == IAqueousJobs.State.None) revert NoSuchJob(jobId);
        if (j.agent != agent) revert WrongAgent(jobId, j.agent, agent);
        if (j.pricePerUnit != 0) revert MeteredJob(jobId);
        if (j.token != token) revert WrongToken(jobId, j.token, token);
    }

    function _violates(address agent, bytes32 jobId) private view returns (bool) {
        IAqueousJobs.Job memory j = _eligible(agent, jobId);
        return j.state == IAqueousJobs.State.Settled && j.deliveredAt == 0;
    }
}
