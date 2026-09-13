# -*- coding: utf-8 -*-
"""El nucleo del puente: de un replay de arena.dev.fun a los bytes que espera
AlnitakRiverRecomputer.decodeInputs.

SOLO BIBLIOTECA ESTANDAR. Ni web3, ni eth-abi, ni pycryptodome, ni requests. La
razon es el punto entero de verificar.py: alguien que no tiene este repo, ni el
corpus, ni ninguna credencial, tiene que poder correrlo. Cada dependencia que se
agregue es una persona menos que lo va a hacer.

NO INVENTA NINGUN VALOR. Todo sale del replay salvo dos cosas, y las dos estan
marcadas como tales:

  - VR_MIX, la tabla del modelo. No esta en el replay ni puede estarlo: es una
    afirmacion sobre como juega el campo, medida aparte. Es el limite 5 del
    README. Lo que el replay SI determina es la fila de la tabla (la clase de
    presion); la tabla en si hay que aceptarla o rechazarla como modelo.
  - El umbral. Es una eleccion del agente, no un hecho de la mano. Se deriva del
    precio por una regla declarada (umbral = precio), pero la regla es una
    decision, no un dato.

Si algo no esta en el replay, extraer() levanta FaltaDato con el nombre del campo
en vez de rellenarlo.
"""

# ── keccak256, en python puro ────────────────────────────────────────────────
# Keccak-f[1600] con padding 0x01 (el de Ethereum, NO el de SHA3-256, que usa
# 0x06). Se comprueba contra `cast keccak` en las pruebas del puente.

_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [
    [0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56], [27, 20, 39, 8, 14],
]
_M = (1 << 64) - 1


def _rotl(x, n):
    return ((x << n) | (x >> (64 - n))) & _M


def _keccak_f(a):
    for rnd in range(24):
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rotl(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                a[x][y] ^= d[x]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rotl(a[x][y], _ROT[x][y])
        for x in range(5):
            for y in range(5):
                a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y] & _M) & b[(x + 2) % 5][y])
        a[0][0] ^= _RC[rnd]
    return a


def keccak256(data):
    """keccak256 de Ethereum. Devuelve 32 bytes."""
    rate = 136                                  # 1088 bits
    a = [[0] * 5 for _ in range(5)]
    m = bytearray(data)
    m.append(0x01)                              # padding de Keccak, no de SHA3
    while len(m) % rate != 0:
        m.append(0x00)
    m[-1] |= 0x80
    for off in range(0, len(m), rate):
        blk = m[off:off + rate]
        for i in range(rate // 8):
            w = int.from_bytes(blk[i * 8:i * 8 + 8], "little")
            a[i % 5][i // 5] ^= w
        a = _keccak_f(a)
    out = bytearray()
    for i in range(4):                          # 32 bytes salen del primer plano
        out += a[i % 5][i // 5].to_bytes(8, "little")
    return bytes(out)


# ── codificacion ABI del struct Inputs ───────────────────────────────────────
# struct Inputs { uint8[2] hole; uint8[5] board; uint256[3] mixBp; uint256
# priceBp; } -- todos los miembros son estaticos, asi que la tupla es estatica y
# abi.encode() produce 11 palabras planas, sin offsets. Comprobado contra
# `cast abi-encode "f((uint8[2],uint8[5],uint256[3],uint256))"`.

N_PALABRAS = 11


def abi_encode_inputs(hole, board, mix_bp, price_bp):
    """Los 352 bytes exactos que espera AlnitakRiverRecomputer.decodeInputs."""
    if len(hole) != 2:
        raise ValueError("hole tiene que ser 2 cartas, vinieron %d" % len(hole))
    if len(board) != 5:
        raise ValueError("board tiene que ser 5 cartas, vinieron %d" % len(board))
    if len(mix_bp) != 3:
        raise ValueError("mixBp tiene que ser 3 valores, vinieron %d" % len(mix_bp))
    palabras = list(hole) + list(board) + list(mix_bp) + [price_bp]
    assert len(palabras) == N_PALABRAS
    out = b""
    for w in palabras:
        if not isinstance(w, int) or w < 0 or w >= (1 << 256):
            raise ValueError("palabra fuera de rango: %r" % (w,))
        out += w.to_bytes(32, "big")
    return out


def abi_decode_inputs(raw):
    """La vuelta: de los bytes al dict. Rechaza cualquier largo que no sea el exacto."""
    if len(raw) != N_PALABRAS * 32:
        raise ValueError("largo %d, se esperaban %d bytes" % (len(raw), N_PALABRAS * 32))
    w = [int.from_bytes(raw[i * 32:(i + 1) * 32], "big") for i in range(N_PALABRAS)]
    for i, v in enumerate(w[0:7]):
        if v > 255:
            raise ValueError("la palabra %d es una carta y no entra en uint8: %d" % (i, v))
    return {"hole": w[0:2], "board": w[2:7], "mixBp": w[7:10], "priceBp": w[10]}


# ── cartas ───────────────────────────────────────────────────────────────────
# uint8 = rango*4 + palo, con c=0 d=1 h=2 s=3 y rango 2..14. Es la codificacion
# de _mazo() y de boardFloorCat() en el adaptador.

RANKS = {"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
         "T": 10, "J": 11, "Q": 12, "K": 13, "A": 14}
SUITS = {"c": 0, "d": 1, "h": 2, "s": 3}
_INV_R = {v: k for k, v in RANKS.items()}
_INV_S = {v: k for k, v in SUITS.items()}


def carta_a_u8(txt):
    t = str(txt).strip()
    if len(t) != 2 or t[0].upper() not in RANKS or t[1].lower() not in SUITS:
        raise ValueError("carta ilegible: %r" % (txt,))
    return RANKS[t[0].upper()] * 4 + SUITS[t[1].lower()]


def u8_a_carta(c):
    if not (8 <= c <= 59):
        raise ValueError("uint8 fuera del mazo: %r" % (c,))
    return _INV_R[c >> 2] + _INV_S[c & 3]


# ── la tabla del modelo ──────────────────────────────────────────────────────
# Espejo literal de _VR_MIX en strategy.py (alnitak34/poker-bot, 84dbf79). NO
# sale del replay: son proporciones medidas sobre 1.352 apuestas de rivales que
# llegaron a showdown, con el sesgo de supervivencia que eso implica. Ver el
# limite 5 del README. En basis points porque el adaptador trabaja en bp.
VR_MIX_BP = {
    ("bet", "big"):   (8230, 2760, 1650),
    ("multi", "small"): (7190, 1690, 750),
    ("multi", "big"):   (9140, 5520, 3510),
    ("raise", "any"):   (9660, 6670, 3450),
}

CORTE_BIG = 0.65      # frontera medida entre `small` y `big`, respecto del bote previo
PRECIO_MIN = 0.20     # por debajo de esto la rama exacta no se consulta
BOARD_N = {"Preflop": 0, "Flop": 3, "Turn": 4, "River": 5}
FUERA = ("folded", "out", "sittingout", "empty")


class FaltaDato(Exception):
    """El replay no trae algo que hace falta. Nunca se rellena: se levanta."""


class NoAplica(Exception):
    """El replay esta completo pero la rama exacta no corresponde a este spot."""


# ── la extraccion ────────────────────────────────────────────────────────────

def _req(d, k, donde):
    v = (d or {}).get(k)
    if v is None:
        raise FaltaDato("%s.%s no esta en el replay" % (donde, k))
    return v


def presion(eventos_previos, asiento_agresor, call, pot_antes):
    """(clase, tamano) — espejo de _villain_pressure(), derivado del replay crudo.

    clase:  `multi` si ESE asiento apostó o subió en >= 2 calles, si no `bet`.
            `raise` si su ultima accion agresiva fue subir o all-in.
    tamano: `big` si la apuesta supera el 65% del bote ANTES de esa apuesta."""
    if call <= 0:
        raise NoAplica("no hay apuesta enfrente (callChips=%r)" % call)
    if pot_antes <= 0:
        raise NoAplica("el bote antes de la apuesta del rival no es positivo: %r" % pot_antes)
    ult = None
    for e in eventos_previos:
        if str(e["accion"]).lower() in ("bet", "raise", "all-in", "allin"):
            ult = e
    if ult is None:
        raise NoAplica("ningun rival apostó antes: no hay presion que leer")
    if str(ult["accion"]).lower() in ("raise", "all-in", "allin"):
        return ("raise", "any")
    calles = set()
    for e in eventos_previos:
        if e["asiento"] == asiento_agresor and str(e["accion"]).lower() in (
                "bet", "raise", "all-in", "allin"):
            calles.add(str(e["calle"]).lower())
    clase = "multi" if len(calles) >= 2 else "bet"
    return (clase, "big" if (call / pot_antes) > CORTE_BIG else "small")


def extraer(replay, seq):
    """De un replay crudo y un numero de secuencia, todo lo que define la mano.

    `replay` es el json que devuelve arena.getTexasReplay, tal cual: el dict con
    {"result":{"data":{"json":{"table":..., "events":[...]}}}} o ya desenvuelto.
    """
    j = replay
    for k in ("result", "data", "json"):
        if isinstance(j, dict) and k in j:
            j = j[k]
    eventos = j.get("events")
    if not eventos:
        raise FaltaDato("events: el replay no trae eventos")

    aqui = [e for e in eventos if e.get("sequence") == seq]
    if not aqui:
        raise FaltaDato("no hay ningun evento con sequence=%r en esta mesa" % (seq,))
    e = aqui[0]
    if e.get("type") != "ActionTaken":
        raise NoAplica("el evento %s es %r, no una accion" % (seq, e.get("type")))
    calle = e.get("street")
    if calle != "River":
        raise NoAplica("el evento %s es de %r, no de River" % (seq, calle))

    pl = e.get("payload") or {}
    sn = e.get("snapshot") or {}
    if not sn:
        raise FaltaDato("snapshot: el evento %s no lo trae" % seq)
    mi_asiento = _req(pl, "seatNumber", "payload")

    # El bote y el stack del snapshot son POSTERIORES a la accion. Los de antes
    # estan en payload.pot y payload.stackBefore. Sin esto, el precio sale mal.
    pot = float(_req(pl, "pot", "payload"))
    aa = pl.get("allowedActions") or {}
    if not aa:
        raise FaltaDato("payload.allowedActions no esta en el evento %s" % seq)
    call_raw = aa.get("callChips")
    if call_raw is None:
        call_raw = aa.get("callAmount")
    if call_raw is None:
        raise FaltaDato("allowedActions.callChips/callAmount no estan")
    call = float(call_raw)
    if call <= 0:
        raise NoAplica("no habia apuesta enfrente: callChips=%r" % call_raw)
    if pot + call <= 0:
        raise NoAplica("bote + apuesta no es positivo")
    precio = call / (pot + call)
    if precio <= PRECIO_MIN:
        raise NoAplica("precio %.4f <= %.2f: la rama exacta no corre" % (precio, PRECIO_MIN))

    # El board del snapshot trae la calle SIGUIENTE en algunos casos. Se trunca.
    board_txt = list(sn.get("boardCards") or [])
    n = BOARD_N[calle]
    if len(board_txt) < n:
        raise FaltaDato("boardCards trae %d cartas y River necesita %d" % (len(board_txt), n))
    board_txt = board_txt[:n]

    asientos = sn.get("seats") or []
    if not asientos:
        raise FaltaDato("snapshot.seats esta vacio")
    mios = [s for s in asientos if s.get("seatNumber") == mi_asiento]
    if not mios:
        raise FaltaDato("el asiento %r no figura en snapshot.seats" % mi_asiento)
    hole_txt = mios[0].get("holeCards")
    if not hole_txt or len(hole_txt) != 2:
        raise FaltaDato("holeCards del asiento %r: %r" % (mi_asiento, hole_txt))

    vivos = [s for s in asientos
             if str(s.get("status", "")).lower() not in FUERA]
    n_opp = max(1, len(vivos) - 1)
    if n_opp != 1:
        raise NoAplica("hay %d rivales vivos; la rama exacta pide exactamente 1" % n_opp)

    previos = []
    for x in eventos:
        if (x.get("sequence") or 0) >= (e.get("sequence") or 0):
            continue
        if x.get("type") != "ActionTaken":
            continue
        p = x.get("payload") or {}
        previos.append({"accion": p.get("action"), "asiento": p.get("seatNumber"),
                        "calle": x.get("street"), "seq": x.get("sequence")})
    previos.sort(key=lambda z: z["seq"] or 0)

    agresivas = [z for z in previos
                 if str(z["accion"]).lower() in ("bet", "raise", "all-in", "allin")]
    if not agresivas:
        raise NoAplica("nadie apostó antes del evento %s" % seq)
    agresor = agresivas[-1]["asiento"]
    pres = presion(previos, agresor, call, pot - call)
    if pres not in VR_MIX_BP:
        raise NoAplica("la clase de presion %r no esta en la tabla del modelo" % (pres,))

    hole = [carta_a_u8(c) for c in hole_txt]
    board = [carta_a_u8(c) for c in board_txt]
    if len(set(hole + board)) != 7:
        raise FaltaDato("hay cartas repetidas entre hole y board: %r / %r"
                        % (hole_txt, board_txt))

    price_bp = int(precio * 10000)      # truncado, no redondeado
    mix_bp = list(VR_MIX_BP[pres])

    return {
        "tableId": sn.get("tableId") or sn.get("id") or (j.get("table") or {}).get("id"),
        "sequence": seq,
        "agentId": e.get("agentId"),
        "seat": mi_asiento,
        "street": calle,
        "holeTxt": list(hole_txt), "boardTxt": board_txt,
        "hole": hole, "board": board,
        "pot": pot, "call": call, "price": precio, "priceBp": price_bp,
        "presion": pres, "mixBp": mix_bp, "asientoAgresor": agresor,
        "vivos": len(vivos), "nOpp": n_opp,
        # solo informativos, NO entran en los bytes:
        "accionReal": pl.get("action"), "razonReal": pl.get("reasoning"),
    }


def bytes_de(d):
    return abi_encode_inputs(d["hole"], d["board"], d["mixBp"], d["priceBp"])


# ── el endpoint publico ──────────────────────────────────────────────────────

ENDPOINT = "https://arena.dev.fun/api/arena.getTexasReplay"


def url_replay(table_id):
    """La URL exacta, sin credenciales, que cualquiera puede abrir en un navegador."""
    import json as _json
    import urllib.parse
    q = urllib.parse.quote(_json.dumps({"json": {"tableId": table_id}},
                                       separators=(",", ":")), safe="")
    return "%s?input=%s" % (ENDPOINT, q)


def bajar_replay(table_id, timeout=45):
    """Descarga el replay del endpoint publico. Sin cabeceras, sin token, sin cookie.

    Si la validacion TLS de Python falla, reintenta con el `curl` del sistema. NO
    es saltarse la verificacion: curl valida igual, con su propio almacen de CAs.
    El caso real que motivo esto es una maquina con un antivirus que inyecta una
    CA cuyo Basic Constraints no esta marcado critico -- el almacen de Python la
    rechaza y el de curl la acepta. El certificado del servidor se valida en los
    dos caminos.
    """
    import json as _json
    import ssl
    import urllib.error
    import urllib.request
    url = url_replay(table_id)
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            if r.status != 200:
                raise FaltaDato("el endpoint devolvio HTTP %s para %s" % (r.status, table_id))
            return _json.loads(r.read().decode("utf-8"))
    except (ssl.SSLError, urllib.error.URLError) as e:
        motivo = getattr(e, "reason", e)
        if not isinstance(motivo, ssl.SSLError) and not isinstance(e, ssl.SSLError):
            raise
        import shutil
        import subprocess
        curl = shutil.which("curl")
        if not curl:
            raise FaltaDato(
                "TLS fallo (%s) y no hay `curl` para reintentar. Es el almacen de "
                "CAs de esta maquina, no el endpoint: se puede bajar el json a mano "
                "desde %s y pasarlo con --replay." % (motivo, url))
        p = subprocess.run([curl, "-sS", "--fail", "--max-time", str(timeout), url],
                           capture_output=True)
        if p.returncode != 0:
            raise FaltaDato("curl fallo (%d): %s"
                            % (p.returncode, p.stderr.decode("utf-8", "replace").strip()))
        return _json.loads(p.stdout.decode("utf-8"))


# ── autochequeo ──────────────────────────────────────────────────────────────
# `python bridge/mano.py` comprueba las dos piezas que este archivo implementa a
# mano y que se romperian en silencio: keccak256 y la codificacion ABI. Los
# vectores de keccak son los canonicos; el ultimo cruza varios bloques de 136
# bytes, que es donde fallan las implementaciones mal esponjadas. Los del ABI
# salen de `cast abi-encode "f((uint8[2],uint8[5],uint256[3],uint256))"`.

_VECTORES_KECCAK = [
    (b"", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
    (b"abc", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
    (b"The quick brown fox jumps over the lazy dog",
     "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15"),
    (bytes(range(256)) * 3,
     "00e77ce2c4f77212a0d5df106b08157b77058479357a98a6039b457c469723e4"),
]

_VECTOR_ABI = (
    ([44, 48], [43, 52, 9, 27, 18], [7190, 1690, 750], 2156),
    "000000000000000000000000000000000000000000000000000000000000002c"
    "0000000000000000000000000000000000000000000000000000000000000030"
    "000000000000000000000000000000000000000000000000000000000000002b"
    "0000000000000000000000000000000000000000000000000000000000000034"
    "0000000000000000000000000000000000000000000000000000000000000009"
    "000000000000000000000000000000000000000000000000000000000000001b"
    "0000000000000000000000000000000000000000000000000000000000000012"
    "0000000000000000000000000000000000000000000000000000000000001c16"
    "000000000000000000000000000000000000000000000000000000000000069a"
    "00000000000000000000000000000000000000000000000000000000000002ee"
    "000000000000000000000000000000000000000000000000000000000000086c",
)


def autochequeo():
    fallos = []
    for dato, esperado in _VECTORES_KECCAK:
        got = keccak256(dato).hex()
        estado = "ok" if got == esperado else "MAL"
        if got != esperado:
            fallos.append("keccak256(%d bytes) = %s, se esperaba %s" % (len(dato), got, esperado))
        print("  %-3s keccak256 de %4d bytes" % (estado, len(dato)))

    (hole, board, mix, precio), esperado = _VECTOR_ABI
    got = abi_encode_inputs(hole, board, mix, precio).hex()
    if got != esperado:
        fallos.append("abi_encode_inputs no coincide con cast abi-encode")
    print("  %-3s abi_encode_inputs contra cast abi-encode" % ("ok" if got == esperado else "MAL"))

    vuelta = abi_decode_inputs(bytes.fromhex(esperado))
    ida = {"hole": hole, "board": board, "mixBp": mix, "priceBp": precio}
    if vuelta != ida:
        fallos.append("abi_decode_inputs no invierte a abi_encode_inputs: %r" % (vuelta,))
    print("  %-3s ida y vuelta del codificador" % ("ok" if vuelta == ida else "MAL"))

    for txt in ("2c", "Ad", "Th", "Ks"):
        if u8_a_carta(carta_a_u8(txt)) != txt:
            fallos.append("carta %s no sobrevive la ida y vuelta" % txt)
    print("  %-3s ida y vuelta de las cartas" % ("ok" if not fallos else "MAL"))

    if fallos:
        print("")
        for f in fallos:
            print("  FALLA: %s" % f)
        return 1
    print("")
    print("todo bien.")
    return 0


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(autochequeo())
