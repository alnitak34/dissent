# -*- coding: utf-8 -*-
"""Verificador independiente de Alnitak River Safety Gate v1.

No importa ``strategy.py``, ``mano.py`` ni el contrato Solidity. Implementa con
la biblioteca estándar las reglas públicas mínimas necesarias para comprobar un
estado de river heads-up:

* evaluación de la mejor mano de 5 entre 7 cartas;
* modelo v1 dentro del tier que implica el precio, con su fallback histórico;
* presión derivada de una traza pública mínima, no declarada por el retador;
* equity exacta bajo la mezcla registrada para esa presión;
* mandato ``equity >= pot price + margin``.

El resultado de la mano y las cartas reales del rival no entran al veredicto.
"""

from fractions import Fraction
from itertools import combinations
import json
import os


RANKS = {r: i for i, r in enumerate("23456789TJQKA", start=2)}
SUITS = {s: i for i, s in enumerate("cdhs")}
KNOWN_PRESSURES = {
    ("bet", "big"): (8230, 2760, 1650),
    ("multi", "small"): (7190, 1690, 750),
    ("multi", "big"): (9140, 5520, 3510),
    ("raise", "any"): (9660, 6670, 3450),
}
STREET_ORDER = {"Preflop": 0, "Flop": 1, "Turn": 2, "River": 3}


def card(text):
    if not isinstance(text, str) or len(text) != 2:
        raise ValueError("invalid card: %r" % (text,))
    rank = RANKS.get(text[0].upper())
    suit = SUITS.get(text[1].lower())
    if rank is None or suit is None:
        raise ValueError("invalid card: %r" % (text,))
    return rank, suit


def straight_high(ranks):
    unique = set(ranks)
    if 14 in unique:
        unique.add(1)
    for high in range(14, 4, -1):
        if all(r in unique for r in range(high - 4, high + 1)):
            return high
    return 0


def eval5(cards):
    ranks = [c[0] for c in cards]
    suits = [c[1] for c in cards]
    counts = {}
    for rank in ranks:
        counts[rank] = counts.get(rank, 0) + 1
    groups = sorted(((count, rank) for rank, count in counts.items()), reverse=True)
    flush = len(set(suits)) == 1
    straight = straight_high(ranks)
    if flush and straight:
        return 8, straight
    if groups[0][0] == 4:
        quad = groups[0][1]
        kicker = max(r for r in ranks if r != quad)
        return 7, quad, kicker
    trips = sorted((r for r, n in counts.items() if n == 3), reverse=True)
    pairs = sorted((r for r, n in counts.items() if n == 2), reverse=True)
    if trips and (pairs or len(trips) > 1):
        pair = pairs[0] if pairs else trips[1]
        return 6, trips[0], pair
    if flush:
        return (5,) + tuple(sorted(ranks, reverse=True))
    if straight:
        return 4, straight
    if trips:
        kickers = sorted((r for r in ranks if r != trips[0]), reverse=True)
        return (3, trips[0]) + tuple(kickers)
    if len(pairs) >= 2:
        high, low = pairs[:2]
        kicker = max(r for r in ranks if r not in (high, low))
        return 2, high, low, kicker
    if len(pairs) == 1:
        kickers = sorted((r for r in ranks if r != pairs[0]), reverse=True)
        return (1, pairs[0]) + tuple(kickers)
    return (0,) + tuple(sorted(ranks, reverse=True))


def eval7(cards):
    if len(cards) != 7:
        raise ValueError("eval7 requires seven cards")
    return max(eval5(list(five)) for five in combinations(cards, 5))


def board_floor(board):
    return eval5(board)[0]


def all_villain_hands(hole, board):
    known = set(hole + board)
    deck = [(rank, suit) for rank in range(2, 15) for suit in range(4)
            if (rank, suit) not in known]
    return list(combinations(deck, 2))


def bucket(villain, board, floor):
    edge = max(eval7(list(villain) + board)[0] - floor, 0)
    return min(edge, 3)


def overpair(villain, board):
    board_top = max(rank for rank, _ in board)
    return villain[0][0] == villain[1][0] and villain[0][0] > board_top


def in_old_range(villain, board, floor, price):
    edge = max(eval7(list(villain) + board)[0] - floor, 0)
    op = overpair(villain, board)
    if price <= Fraction(28, 100):
        return edge >= 1
    if price <= Fraction(333, 1000):
        return edge >= 2 or op
    return edge >= 3 or op or edge == 0


def equity(hero, board, villains):
    hero_value = eval7(hero + board)
    score = 0
    for villain in villains:
        value = eval7(list(villain) + board)
        score += 2 if hero_value > value else 1 if hero_value == value else 0
    if not villains:
        raise ValueError("empty opponent range")
    return Fraction(score, 2 * len(villains))


def pressure_equity(hero, board, villains, mix_bp):
    floor = board_floor(board)
    by_bucket = {k: [] for k in range(4)}
    for villain in villains:
        by_bucket[bucket(villain, board, floor)].append(villain)

    p1, p2, p3 = mix_bp
    segments = [
        (p3, (3, 2, 1, 0)),
        (p2 - p3, (2, 3, 1, 0)),
        (p1 - p2, (1, 2, 3, 0)),
        (10000 - p1, (0, 1, 2, 3)),
    ]
    weights = {k: 0 for k in range(4)}
    for probability, order in segments:
        if probability == 0:
            continue
        target = next((k for k in order if by_bucket[k]), None)
        if target is None:
            raise ValueError("all pressure buckets are empty")
        weights[target] += probability

    result = Fraction(0, 1)
    for k in range(4):
        if weights[k]:
            result += Fraction(weights[k], 10000) * equity(hero, board, by_bucket[k])
    return result


def derive_pressure(trace, call_amount, pot_facing):
    """Deriva el bucket de presión desde acciones observables y ordenadas.

    La regla replica únicamente la parte pública de River Safety Gate v1:
    un raise/all-in final domina; en otro caso dos o más calles de agresión del
    rival cuentan como ``multi``. El tamaño se calcula contra el bote anterior
    a la última apuesta del rival.
    """
    if not isinstance(trace, list) or not trace:
        raise ValueError("actionTrace must be a non-empty list")

    previous_street = -1
    has_aggression_on_street = False
    previous_actor_on_street = None
    normalized = []
    for index, event in enumerate(trace):
        if not isinstance(event, dict):
            raise ValueError("every trace event must be an object")
        street = event.get("street")
        actor = event.get("actor")
        action = event.get("action")
        order = STREET_ORDER.get(street)
        if order is None or order < previous_street:
            raise ValueError("actionTrace streets must be valid and ordered")
        if actor not in ("agent", "opponent"):
            raise ValueError("trace actor must be agent or opponent")
        if action not in ("bet", "raise", "all-in"):
            raise ValueError("trace action must be bet, raise, or all-in")
        if order > previous_street:
            has_aggression_on_street = False
            previous_actor_on_street = None
        if action == "bet" and has_aggression_on_street:
            raise ValueError("a later aggression on one street must be a raise")
        if action == "raise" and (
            not has_aggression_on_street or actor == previous_actor_on_street
        ):
            raise ValueError("raise requires prior aggression by the other actor")
        if action == "all-in" and (
            index + 1 != len(trace)
            or (has_aggression_on_street and actor == previous_actor_on_street)
        ):
            raise ValueError("all-in must be final and alternate after prior aggression")
        previous_street = order
        previous_actor_on_street = actor
        has_aggression_on_street = True
        normalized.append((street, actor, action))

    last_street, last_actor, last_action = normalized[-1]
    if last_street != "River" or last_actor != "opponent":
        raise ValueError("last trace event must be opponent aggression on River")
    if last_action in ("raise", "all-in"):
        return "raise", "any"

    opponent_streets = {street for street, actor, _ in normalized
                        if actor == "opponent"}
    pressure_kind = "multi" if len(opponent_streets) >= 2 else "bet"
    pot_before_opponent = pot_facing - call_amount
    if pot_before_opponent <= 0:
        raise ValueError("potFacingDecision must exceed call")
    pressure_size = (
        "big"
        if Fraction(call_amount, pot_before_opponent) > Fraction(65, 100)
        else "small"
    )
    return pressure_kind, pressure_size


def verify_case(data):
    state = data["state"]
    if state.get("street") != "River":
        raise ValueError("domain only accepts River")
    if state.get("action") != "call":
        raise ValueError("domain only accepts recorded calls")
    hero = [card(c) for c in state["hole"]]
    board = [card(c) for c in state["board"]]
    if len(hero) != 2 or len(board) != 5 or len(set(hero + board)) != 7:
        raise ValueError("cards must be two hole plus five distinct board cards")
    pot = int(state["potFacingDecision"])
    call_amount = int(state["call"])
    if pot <= 0 or call_amount <= 0:
        raise ValueError("pot and call must be positive")
    pressure = derive_pressure(state.get("actionTrace"), call_amount, pot)
    expected_mix = KNOWN_PRESSURES.get(pressure)
    if expected_mix is None:
        raise ValueError("trace is outside the registered high-pressure domain")
    margin_bp = int(data["policy"]["marginBp"])
    if margin_bp != 1500:
        raise ValueError("v1 margin must be the registered 1500 bp")

    price = Fraction(call_amount, pot + call_amount)
    threshold = price + Fraction(margin_bp, 10000)
    villains = all_villain_hands(hero, board)
    floor = board_floor(board)
    old_range = [v for v in villains if in_old_range(v, board, floor, price)]
    if len(old_range) < 6:
        # En river has_strong_draw siempre era falso en e6a7e49. Por eso el
        # fallback histórico ``edge >= 1 or draw`` se reduce a ``edge >= 1``.
        relaxed = [v for v in villains if bucket(v, board, floor) >= 1]
        old_range = relaxed if len(relaxed) >= 6 else villains
    old = equity(hero, board, old_range)
    conditioned = pressure_equity(hero, board, villains, expected_mix)
    violation = old >= threshold and conditioned < threshold
    return {
        "case": data["case"],
        "pressure": pressure,
        "price": price,
        "threshold": threshold,
        "oldEquity": old,
        "conditionedEquity": conditioned,
        "oldAuthorizes": old >= threshold,
        "conditionedAuthorizes": conditioned >= threshold,
        "violation": violation,
        "opponentHands": len(villains),
        "oldRangeHands": len(old_range),
    }


def percent(value):
    return float(value * 100)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def main(paths):
    for path in paths:
        result = verify_case(load(path))
        print(os.path.basename(path))
        print("  price                 %8.4f%%" % percent(result["price"]))
        print("  required              %8.4f%%" % percent(result["threshold"]))
        print("  v1 exact equity       %8.4f%%" % percent(result["oldEquity"]))
        print("  conditioned equity    %8.4f%%" % percent(result["conditionedEquity"]))
        print("  violation             %s" % result["violation"])


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        here = os.path.join(os.path.dirname(__file__), "fixtures")
        sys.argv.extend([
            os.path.join(here, "policy-bounty-jhjd.json"),
            os.path.join(here, "policy-bounty-control-4hah.json"),
        ])
    main(sys.argv[1:])
