# -*- coding: utf-8 -*-
"""De una mano real de river a los bytes exactos que espera DissentCore.commit.

    python bridge/armar_commit.py <tableId> <sequence> [opciones]

De donde sale el replay, por orden de preferencia:
    --replay ARCHIVO   un json concreto
    --corpus DIR       un directorio con <tableId>.json
    --publico          lo baja del endpoint publico de arena.dev.fun
    (sin nada)         busca bridge/replays/<tableId>.json

Imprime lo que extrajo, los bytes en hexadecimal, su keccak256 y los argumentos
de commit() que se desprenden. NO firma, NO despliega, NO manda nada.

Si algo no esta en el replay no lo rellena: falla diciendo que falta.
"""
import argparse
import json
import os
import sys

# La salida lleva acentos y cajas; en una consola cp1252 se romperia.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mano

WAD = 10 ** 18
BP_TO_WAD = 10 ** 14
AQUI = os.path.dirname(os.path.abspath(__file__))


def cargar(args):
    """Devuelve (replay, de_donde). Una sola fuente, explicita."""
    if args.replay:
        with open(args.replay, encoding="utf-8") as f:
            return json.load(f), "archivo %s" % args.replay
    if args.publico:
        return mano.bajar_replay(args.tableId), "endpoint publico"
    if args.corpus:
        p = os.path.join(args.corpus, args.tableId + ".json")
        if not os.path.exists(p):
            raise SystemExit("no existe %s" % p)
        with open(p, encoding="utf-8") as f:
            return json.load(f), "corpus %s" % p
    p = os.path.join(AQUI, "replays", args.tableId + ".json")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f), "bridge/replays/%s.json" % args.tableId
    raise SystemExit(
        "no encontre el replay de %s.\n"
        "  Pasá --replay ARCHIVO, --corpus DIR, o --publico para bajarlo."
        % args.tableId)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tableId")
    ap.add_argument("sequence", type=int)
    ap.add_argument("--replay", help="ruta a un replay json ya bajado")
    ap.add_argument("--corpus", help="directorio con <tableId>.json")
    ap.add_argument("--publico", action="store_true",
                    help="bajar del endpoint publico de arena.dev.fun (sin credenciales)")
    ap.add_argument("--json", dest="salida_json",
                    help="ademas, escribir todo a este archivo")
    args = ap.parse_args()

    replay, fuente = cargar(args)
    try:
        d = mano.extraer(replay, args.sequence)
    except mano.FaltaDato as e:
        raise SystemExit("FALTA UN DATO EN EL REPLAY: %s\n"
                         "No se rellena nada. Elegí otra mano o revisá el replay." % e)
    except mano.NoAplica as e:
        raise SystemExit("LA RAMA EXACTA NO APLICA A ESTE SPOT: %s" % e)

    raw = mano.bytes_de(d)
    h = mano.keccak256(raw)
    umbral = d["priceBp"] * BP_TO_WAD          # el precio, en WAD

    print("fuente del replay : %s" % fuente)
    print("URL publica       : %s" % mano.url_replay(d["tableId"]))
    print("")
    print("MANO")
    print("  tableId         : %s" % d["tableId"])
    print("  sequence        : %s   (agentId %s, asiento %s)"
          % (d["sequence"], d["agentId"], d["seat"]))
    print("  hole            : %s   -> uint8 %s" % (" ".join(d["holeTxt"]), d["hole"]))
    print("  board           : %s   -> uint8 %s" % (" ".join(d["boardTxt"]), d["board"]))
    print("  rivales vivos   : %d  (n_opp = %d)" % (d["vivos"], d["nOpp"]))
    print("")
    print("PRECIO  (todo del replay)")
    print("  pot antes       : %g   (payload.pot, NO snapshot.potChips)" % d["pot"])
    print("  a pagar         : %g   (allowedActions.callChips)" % d["call"])
    print("  precio          : %g / (%g + %g) = %.10f  -> %d bp (truncado)"
          % (d["call"], d["pot"], d["call"], d["price"], d["priceBp"]))
    print("")
    print("PRESION DEL RIVAL")
    print("  asiento agresor : %s" % d["asientoAgresor"])
    print("  clase / tamano  : %s / %s   (apuesta %g sobre bote previo %g = %.3f)"
          % (d["presion"][0], d["presion"][1], d["call"], d["pot"] - d["call"],
             d["call"] / (d["pot"] - d["call"])))
    print("  mixBp           : %s   <- TABLA DEL MODELO, no sale del replay" % d["mixBp"])
    print("")
    print("BYTES  (abi.encode de AlnitakRiverRecomputer.Inputs, %d bytes)" % len(raw))
    print("  inputs          : 0x%s" % raw.hex())
    print("  keccak256       : 0x%s" % h.hex())
    print("")
    print("ARGUMENTOS DE commit()")
    print("  threshold       : %d          (= %d bp en WAD; es el precio)"
          % (umbral, d["priceBp"]))
    print("  comparator      : 0 (AtLeast)")
    print("  action          : %r" % ("river call %s vs %s @ %s#%s" % (
        "".join(d["holeTxt"]), " ".join(d["boardTxt"]), d["tableId"], d["sequence"])))
    print("")
    print("EN EL REPLAY, PERO FUERA DE LOS BYTES  (informativo, el contrato no lo ve)")
    print("  accion real     : %r" % d["accionReal"])
    print("  reasoning       : %r" % d["razonReal"])
    print("")
    print("NO SALE DEL REPLAY, y verificar.py no lo puede comprobar:")
    print("  - mixBp: la fila la fija la presion leida del replay, pero la TABLA")
    print("    es el modelo. Es el limite 5 del README.")
    print("  - threshold: es una eleccion del agente. Aca se deriva del precio")
    print("    por la regla `umbral = precio`, pero la regla es una decision.")

    if args.salida_json:
        d2 = dict(d)
        d2["inputsHex"] = "0x" + raw.hex()
        d2["inputsHash"] = "0x" + h.hex()
        d2["threshold"] = umbral
        d2["urlPublica"] = mano.url_replay(d["tableId"])
        with open(args.salida_json, "w", encoding="utf-8", newline="\n") as f:
            json.dump(d2, f, indent=1, sort_keys=True)
        print("")
        print("(escrito %s)" % args.salida_json)


if __name__ == "__main__":
    main()
