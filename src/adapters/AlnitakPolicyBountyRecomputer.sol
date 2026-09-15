// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRecomputer} from "../IRecomputer.sol";
import {PokerEval} from "./PokerEval.sol";

/// @title AlnitakPolicyBountyRecomputer
/// @notice Deterministic judge for one frozen policy claim, not for all of
///         Alnitak: a high-pressure river call that the old exact range model
///         authorizes must still clear pot price by 15 points after conditioning
///         on the opponent pressure derived from the supplied action trace.
contract AlnitakPolicyBountyRecomputer is IRecomputer {
    bytes32 public constant POLICY_SPEC_HASH = 0xfbfe47b0bc48301022f5aa04390b175eef2701458913f8646a8f3b7b0a7cc7d0;
    bytes20 public constant ORIGIN_COMMIT = hex"e6a7e49857602ac84257dc78f0960506f87cd7f3";
    uint16 public constant MARGIN_BP = 1500;
    uint256 private constant BP = 10_000;
    uint256 private constant MIN_COMBOS = 6;

    uint8 private constant PRESSURE_BET_BIG = 0;
    uint8 private constant PRESSURE_MULTI_SMALL = 1;
    uint8 private constant PRESSURE_MULTI_BIG = 2;
    uint8 private constant PRESSURE_RAISE_ANY = 3;

    bytes32 private constant REASON_OK = bytes32(0);
    bytes32 private constant REASON_BAD_INPUTS = "BAD_POLICY_INPUTS";
    bytes32 private constant REASON_BAD_LENGTH = "EVIDENCE_BAD_LENGTH";
    bytes32 private constant REASON_NON_CANONICAL = "NON_CANONICAL_EVIDENCE";
    bytes32 private constant REASON_BAD_CARDS = "INVALID_CARDS";
    bytes32 private constant REASON_BAD_AMOUNTS = "INVALID_AMOUNTS";
    bytes32 private constant REASON_BAD_TRACE = "INVALID_TRACE";
    bytes32 private constant REASON_OUTSIDE_DOMAIN = "OUTSIDE_HIGH_PRESSURE";

    struct PolicyInputs {
        bytes32 policySpecHash;
        bytes20 originCommit;
        uint16 marginBp;
    }

    struct Counterexample {
        bytes7 cards;
        uint64 potFacingDecision;
        uint64 callAmount;
        bytes8 aggressiveTrace;
        uint8 traceLength;
    }

    struct Tally {
        uint256[4] n;
        uint256[4] acc;
        uint256 nOld;
        uint256 accOld;
        uint256 nAll;
        uint256 accAll;
    }

    struct Evaluation {
        uint256 oldEquityWad;
        uint256 conditionedEquityWad;
        uint256 thresholdWad;
        uint8 pressure;
        bool oldAuthorizes;
        bool conditionedAuthorizes;
        bool violation;
    }

    function scale() external pure returns (uint256) {
        return 1;
    }

    function domain() external pure returns (bytes32) {
        return "alnitak.river.safety.v1";
    }

    function canonicalInputs() external pure returns (bytes memory) {
        return
            abi.encode(
                PolicyInputs({policySpecHash: POLICY_SPEC_HASH, originCommit: ORIGIN_COMMIT, marginBp: MARGIN_BP})
            );
    }

    function validateEvidence(bytes calldata inputs, bytes calldata evidence)
        external
        pure
        returns (bool ok, bytes32 reason)
    {
        if (!_validInputs(inputs)) return (false, REASON_BAD_INPUTS);
        if (evidence.length != 160) return (false, REASON_BAD_LENGTH);
        (bool decoded, Counterexample memory e) = _decodeEvidence(evidence);
        if (!decoded) return (false, REASON_NON_CANONICAL);
        if (!_validCards(e.cards)) return (false, REASON_BAD_CARDS);
        if (e.callAmount == 0 || e.potFacingDecision <= e.callAmount) {
            return (false, REASON_BAD_AMOUNTS);
        }
        (bool traceOk, bool inDomain,) = _derivePressure(e);
        if (!traceOk) return (false, REASON_BAD_TRACE);
        if (!inDomain) return (false, REASON_OUTSIDE_DOMAIN);
        return (true, REASON_OK);
    }

    function recompute(bytes calldata inputs, bytes calldata evidence) external pure returns (int256) {
        if (!_validInputs(inputs)) revert("BAD_POLICY_INPUTS");
        if (evidence.length == 0) return 0;
        Evaluation memory result = evaluate(inputs, evidence);
        return result.violation ? int256(1) : int256(0);
    }

    /// @notice Developer/UI helper. DissentCore only consumes recompute().
    function evaluate(bytes calldata inputs, bytes calldata evidence) public pure returns (Evaluation memory result) {
        if (!_validInputs(inputs)) revert("BAD_POLICY_INPUTS");
        if (evidence.length != 160) revert("EVIDENCE_BAD_LENGTH");
        (bool decoded, Counterexample memory e) = _decodeEvidence(evidence);
        if (!decoded) revert("NON_CANONICAL_EVIDENCE");
        if (!_validCards(e.cards)) revert("INVALID_CARDS");
        if (e.callAmount == 0 || e.potFacingDecision <= e.callAmount) revert("INVALID_AMOUNTS");
        (bool traceOk, bool inDomain, uint8 pressure) = _derivePressure(e);
        if (!traceOk) revert("INVALID_TRACE");
        if (!inDomain) revert("OUTSIDE_HIGH_PRESSURE");

        (uint8[2] memory hole, uint8[5] memory board) = _unpackCards(e.cards);
        Tally memory tally = _enumerate(hole, board, e.callAmount, e.potFacingDecision);
        uint256[3] memory mix = _mix(pressure);

        uint256 oldN = tally.nOld;
        uint256 oldAcc = tally.accOld;
        if (oldN < MIN_COMBOS) {
            // Historical e6a7e49 did not jump straight to a uniform range.
            // On the river draws are impossible, so its loosest non-vacuous
            // fallback (edge >= 1 || strong draw) is exactly buckets 1..3.
            uint256 relaxedN = tally.n[1] + tally.n[2] + tally.n[3];
            if (relaxedN >= MIN_COMBOS) {
                oldN = relaxedN;
                oldAcc = tally.acc[1] + tally.acc[2] + tally.acc[3];
            } else {
                oldN = tally.nAll;
                oldAcc = tally.accAll;
            }
        }
        (uint256 condNum, uint256 condDen) = _conditionedFraction(tally, mix);
        (uint256 thresholdNum, uint256 thresholdDen) = _thresholdFraction(e.callAmount, e.potFacingDecision);

        result.oldEquityWad = oldAcc * 1e18 / (2 * oldN);
        result.conditionedEquityWad = condNum * 1e18 / condDen;
        result.thresholdWad = thresholdNum * 1e18 / thresholdDen;
        result.pressure = pressure;
        result.oldAuthorizes = oldAcc * thresholdDen >= thresholdNum * (2 * oldN);
        result.conditionedAuthorizes = condNum * thresholdDen >= thresholdNum * condDen;
        result.violation = result.oldAuthorizes && !result.conditionedAuthorizes;
    }

    function _validInputs(bytes calldata inputs) private pure returns (bool) {
        if (inputs.length != 96) return false;
        PolicyInputs memory p = abi.decode(inputs, (PolicyInputs));
        return p.policySpecHash == POLICY_SPEC_HASH && p.originCommit == ORIGIN_COMMIT && p.marginBp == MARGIN_BP;
    }

    function _validCards(bytes7 packed) private pure returns (bool) {
        uint256 seen = 0;
        for (uint256 i = 0; i < 7; i++) {
            uint8 c = uint8(packed[i]);
            if (c < 8 || c > 59) return false;
            uint256 bit = uint256(1) << c;
            if (seen & bit != 0) return false;
            seen |= bit;
        }
        return true;
    }

    /// @dev Evidence is challenger-controlled. Decoding directly to uint64,
    ///      uint8 or bytesN may revert on dirty ABI padding, which DissentCore
    ///      would classify as a payable adapter fault. Decode only full words,
    ///      reject non-canonical padding, and narrow after proving the bounds.
    function _decodeEvidence(bytes calldata evidence) private pure returns (bool ok, Counterexample memory e) {
        (bytes32 cardsWord, uint256 potWord, uint256 callWord, bytes32 traceWord, uint256 traceLengthWord) =
            abi.decode(evidence, (bytes32, uint256, uint256, bytes32, uint256));
        if (uint256(cardsWord) & type(uint200).max != 0) return (false, e);
        if (uint256(traceWord) & type(uint192).max != 0) return (false, e);
        if (potWord > type(uint64).max || callWord > type(uint64).max || traceLengthWord > type(uint8).max) {
            return (false, e);
        }

        // bytes7/bytes8 retain the leftmost bytes; the discarded right padding
        // was proven zero above. Integer bounds were proven before narrowing.
        // forge-lint: disable-next-line(unsafe-typecast)
        e.cards = bytes7(cardsWord);
        // forge-lint: disable-next-line(unsafe-typecast)
        e.potFacingDecision = uint64(potWord);
        // forge-lint: disable-next-line(unsafe-typecast)
        e.callAmount = uint64(callWord);
        // forge-lint: disable-next-line(unsafe-typecast)
        e.aggressiveTrace = bytes8(traceWord);
        // forge-lint: disable-next-line(unsafe-typecast)
        e.traceLength = uint8(traceLengthWord);
        return (true, e);
    }

    function _unpackCards(bytes7 packed) private pure returns (uint8[2] memory hole, uint8[5] memory board) {
        hole[0] = uint8(packed[0]);
        hole[1] = uint8(packed[1]);
        for (uint256 i = 0; i < 5; i++) {
            board[i] = uint8(packed[i + 2]);
        }
    }

    /// @dev Event byte: street bits 0..1, actor bit 2 (1=opponent), action
    ///      bits 3..4 (0=bet, 1=raise, 2=all-in). Bits 5..7 must be zero.
    function _derivePressure(Counterexample memory e)
        private
        pure
        returns (bool traceOk, bool inDomain, uint8 pressure)
    {
        if (e.traceLength == 0 || e.traceLength > 8) {
            return (false, false, 0);
        }
        uint8 previousStreet = 0;
        uint8 opponentStreetMask = 0;
        uint8 lastStreet = 0;
        uint8 lastActor = 0;
        uint8 lastAction = 0;
        bool hasAggressionOnStreet = false;
        uint8 previousActorOnStreet = 0;

        for (uint256 i = 0; i < 8; i++) {
            uint8 raw = uint8(e.aggressiveTrace[i]);
            if (i >= e.traceLength) {
                if (raw != 0) return (false, false, 0);
                continue;
            }
            if (raw & 0xE0 != 0) return (false, false, 0);
            uint8 street = raw & 0x03;
            uint8 actor = (raw >> 2) & 0x01;
            uint8 action = (raw >> 3) & 0x03;
            if (action > 2 || (i > 0 && street < previousStreet)) return (false, false, 0);
            if (i == 0 || street > previousStreet) {
                hasAggressionOnStreet = false;
            }
            if (action == 0 && hasAggressionOnStreet) return (false, false, 0);
            if (action == 1 && (!hasAggressionOnStreet || actor == previousActorOnStreet)) {
                return (false, false, 0);
            }
            if (action == 2 && (i + 1 != e.traceLength || (hasAggressionOnStreet && actor == previousActorOnStreet))) {
                return (false, false, 0);
            }
            previousStreet = street;
            previousActorOnStreet = actor;
            hasAggressionOnStreet = true;
            if (actor == 1) opponentStreetMask |= uint8(1 << street);
            lastStreet = street;
            lastActor = actor;
            lastAction = action;
        }

        if (lastStreet != 3 || lastActor != 1) return (false, false, 0);
        if (lastAction == 1 || lastAction == 2) return (true, true, PRESSURE_RAISE_ANY);

        uint256 streets = 0;
        for (uint256 s = 0; s < 4; s++) {
            if (opponentStreetMask & (1 << s) != 0) streets++;
        }
        bool multi = streets >= 2;
        bool big = uint256(e.callAmount) * BP > 6500 * (uint256(e.potFacingDecision) - uint256(e.callAmount));
        if (!multi && !big) return (true, false, 0);
        if (!multi) return (true, true, PRESSURE_BET_BIG);
        return (true, true, big ? PRESSURE_MULTI_BIG : PRESSURE_MULTI_SMALL);
    }

    function _mix(uint8 pressure) private pure returns (uint256[3] memory mix) {
        if (pressure == PRESSURE_BET_BIG) return [uint256(8230), 2760, 1650];
        if (pressure == PRESSURE_MULTI_SMALL) return [uint256(7190), 1690, 750];
        if (pressure == PRESSURE_MULTI_BIG) return [uint256(9140), 5520, 3510];
        return [uint256(9660), 6670, 3450];
    }

    function _thresholdFraction(uint64 callAmount, uint64 potFacing)
        private
        pure
        returns (uint256 numerator, uint256 denominator)
    {
        denominator = BP * (uint256(potFacing) + uint256(callAmount));
        numerator = BP * uint256(callAmount) + MARGIN_BP * (uint256(potFacing) + uint256(callAmount));
    }

    function _boardFloor(uint8[5] memory board) private pure returns (uint256) {
        return _boardFloorFive(board);
    }

    function _boardFloorFive(uint8[5] memory board) private pure returns (uint256) {
        uint256 rankMask = 0;
        uint256[15] memory rc;
        uint256[4] memory suitMask;
        uint256[4] memory suitCount;
        for (uint256 i = 0; i < 5; i++) {
            uint256 r = uint256(board[i]) >> 2;
            uint256 s = uint256(board[i]) & 3;
            rc[r]++;
            rankMask |= 1 << r;
            suitMask[s] |= 1 << r;
            suitCount[s]++;
        }
        uint256 flushSuit = 4;
        for (uint256 s = 0; s < 4; s++) {
            if (suitCount[s] == 5) flushSuit = s;
        }
        if (flushSuit < 4 && PokerEval.bestStraight(suitMask[flushSuit]) != 0) return 8;
        uint256 m1 = 0;
        uint256 m2 = 0;
        for (uint256 r = 2; r <= 14; r++) {
            uint256 count = rc[r];
            if (count > m1) {
                m2 = m1;
                m1 = count;
            } else if (count > m2) {
                m2 = count;
            }
        }
        if (m1 >= 4) return 7;
        if (m1 == 3 && m2 >= 2) return 6;
        if (flushSuit < 4) return 5;
        if (PokerEval.bestStraight(rankMask) != 0) return 4;
        if (m1 == 3) return 3;
        if (m1 == 2 && m2 == 2) return 2;
        if (m1 == 2) return 1;
        return 0;
    }

    function _enumerate(uint8[2] memory hole, uint8[5] memory board, uint64 callAmount, uint64 potFacing)
        private
        pure
        returns (Tally memory tally)
    {
        uint8[45] memory deck;
        uint256 nDeck = 0;
        for (uint256 r = 2; r <= 14; r++) {
            for (uint256 s = 0; s < 4; s++) {
                // r is 2..14 and s is 0..3, so r*4+s is 8..59 and cannot
                // truncate when converted to uint8.
                // forge-lint: disable-next-line(unsafe-typecast)
                uint8 c = uint8(r * 4 + s);
                bool known = c == hole[0] || c == hole[1];
                for (uint256 b = 0; b < 5; b++) {
                    if (c == board[b]) known = true;
                }
                if (!known) deck[nDeck++] = c;
            }
        }

        uint8[7] memory heroCards;
        heroCards[0] = hole[0];
        heroCards[1] = hole[1];
        for (uint256 i = 0; i < 5; i++) {
            heroCards[i + 2] = board[i];
        }
        uint256 heroScore = PokerEval.eval7(heroCards);
        uint256 floor = _boardFloor(board);
        uint256 boardTop = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 rank = uint256(board[i]) >> 2;
            if (rank > boardTop) boardTop = rank;
        }

        uint8[7] memory villainCards;
        for (uint256 i = 0; i < 5; i++) {
            villainCards[i + 2] = board[i];
        }
        for (uint256 i = 0; i < 45; i++) {
            villainCards[0] = deck[i];
            for (uint256 j = i + 1; j < 45; j++) {
                villainCards[1] = deck[j];
                uint256 villainScore = PokerEval.eval7(villainCards);
                uint256 category = PokerEval.categoryOf(villainScore);
                uint256 edge = category > floor ? category - floor : 0;
                uint256 bucket_ = edge > 3 ? 3 : edge;
                uint256 contribution = heroScore > villainScore ? 2 : (heroScore == villainScore ? 1 : 0);
                tally.n[bucket_]++;
                tally.acc[bucket_] += contribution;
                tally.nAll++;
                tally.accAll += contribution;

                uint256 r0 = uint256(deck[i]) >> 2;
                bool overpair = r0 == (uint256(deck[j]) >> 2) && r0 > boardTop;
                if (_inOldRange(edge, overpair, callAmount, potFacing)) {
                    tally.nOld++;
                    tally.accOld += contribution;
                }
            }
        }
    }

    function _inOldRange(uint256 edge, bool overpair, uint64 callAmount, uint64 potFacing) private pure returns (bool) {
        uint256 total = uint256(potFacing) + uint256(callAmount);
        if (uint256(callAmount) * 100 <= 28 * total) return edge >= 1;
        if (uint256(callAmount) * 1000 <= 333 * total) return edge >= 2 || overpair;
        return edge >= 3 || overpair || edge == 0;
    }

    function _conditionedFraction(Tally memory tally, uint256[3] memory mix)
        private
        pure
        returns (uint256 numerator, uint256 denominator)
    {
        uint256[4] memory weights = _weights(mix, tally.n);
        denominator = 1;
        for (uint256 k = 0; k < 4; k++) {
            if (weights[k] == 0) continue;
            uint256 termNumerator = weights[k] * tally.acc[k];
            uint256 termDenominator = BP * 2 * tally.n[k];
            numerator = numerator * termDenominator + termNumerator * denominator;
            denominator *= termDenominator;
        }
    }

    function _weights(uint256[3] memory mix, uint256[4] memory n) private pure returns (uint256[4] memory weights) {
        uint256[4] memory probabilities = [mix[2], mix[1] - mix[2], mix[0] - mix[1], BP - mix[0]];
        uint8[4][4] memory order;
        order[0] = [3, 2, 1, 0];
        order[1] = [2, 3, 1, 0];
        order[2] = [1, 2, 3, 0];
        order[3] = [0, 1, 2, 3];
        for (uint256 segment = 0; segment < 4; segment++) {
            for (uint256 q = 0; q < 4; q++) {
                uint256 bucket_ = order[segment][q];
                if (n[bucket_] != 0) {
                    weights[bucket_] += probabilities[segment];
                    break;
                }
            }
        }
    }
}
