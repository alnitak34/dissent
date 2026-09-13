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

# Politica de gas RECOMENDADA para el adaptador Alnitak. NO es autoridad: son
# valores sugeridos que el agente pasa a commit(). El recompute peor caso medido
# de Alnitak ronda 17.92M; 20M deja margen. La evidencia del adaptador es
# abi.encode(uint256 tier), 32 bytes exactos, asi que maxEvidenceLen = 32.
ALNITAK_RECOMPUTE_GAS_LIMIT = 20_000_000
ALNITAK_VALIDATE_GAS_LIMIT = 100_000
ALNITAK_MAX_EVIDENCE_LEN = 32
# Recompensa minima de REFERENCIA a 100 gwei para esa politica, calculada OFFLINE
# y SOLO ORIENTATIVA (no reimplementamos la formula del contrato aca). La
# autoridad es minGasBackedReward(...) leido del contrato justo antes del commit;
# si block.basefee subio, el resultado onchain manda. ~2.1175348 MON con R=20M.
# Origen verificable de este snapshot: el test on-chain
# EconomicBackingTest.test_alnitak_politica_recomendada_R20M, que afirma este
# mismo valor exacto contra minGasBackedReward del contrato.
ALNITAK_MIN_REWARD_REF_WEI = 2_117_534_800_000_000_000


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
    action_str = "river call %s vs %s @ %s#%s" % (
        "".join(d["holeTxt"]), " ".join(d["boardTxt"]), d["tableId"], d["sequence"])
    print("ARGUMENTOS DE commit()  (orden exacto de DissentCore.commit)")
    print("  1  recomputer       : <address del AlnitakRiverRecomputer desplegado>")
    print("  2  inputs           : 0x%s" % raw.hex())
    print("                        (inputsLength = %d bytes)" % len(raw))
    print("  3  threshold        : %d   (= %d bp en WAD; es el precio)" % (umbral, d["priceBp"]))
    print("  4  comparator       : 0 (AtLeast)")
    print("  5  action           : %r" % action_str)
    print("  6  deposit          : <wei; lo fija el agente, p.ej. 0.1 ether>")
    print("  7  window           : <segundos; >= MIN_WINDOW (1 hora)>")
    print("  8  recomputeGasLimit : %d   (recomendado Alnitak)" % ALNITAK_RECOMPUTE_GAS_LIMIT)
    print("  9  validateGasLimit  : %d      (recomendado)" % ALNITAK_VALIDATE_GAS_LIMIT)
    print("  10 maxEvidenceLen    : %d           (evidencia Alnitak = 32 bytes)" % ALNITAK_MAX_EVIDENCE_LEN)
    print("  11 salt              : <bytes32 a eleccion del agente>")
    print("")
    print("  reward: es msg.value (el MON enviado con la llamada), NO un argumento.")
    print("")
    print("EVIDENCIA QUE ESPERA EL ADAPTADOR (la que trae el retador)")
    print("  abi.encode(uint256 tier), tier en {0,1,2}  ->  32 bytes exactos")
    print("")
    print("RECOMPENSA MINIMA DE REFERENCIA  (calculo OFFLINE, orientativo)")
    print("  a 100 gwei, con la politica recomendada: ~%.7f MON (%d wei)"
          % (ALNITAK_MIN_REWARD_REF_WEI / WAD, ALNITAK_MIN_REWARD_REF_WEI))
    print("  NO ES AUTORIDAD. Antes del commit, leer del contrato:")
    print("    minGasBackedReward(validateGasLimit, recomputeGasLimit, inputs.length, maxEvidenceLen)")
    print("  y enviar msg.value >= ese valor. Si block.basefee subio, manda el resultado ONCHAIN.")
    print("  (origen del snapshot: test EconomicBackingTest.test_alnitak_politica_recomendada_R20M)")
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
        d2["inputsLength"] = len(raw)
        d2["threshold"] = umbral
        d2["action"] = action_str
        d2["recomputeGasLimit"] = ALNITAK_RECOMPUTE_GAS_LIMIT
        d2["validateGasLimit"] = ALNITAK_VALIDATE_GAS_LIMIT
        d2["maxEvidenceLen"] = ALNITAK_MAX_EVIDENCE_LEN
        d2["evidenceFormat"] = "abi.encode(uint256 tier), 32 bytes"
        d2["minRewardRefWei"] = ALNITAK_MIN_REWARD_REF_WEI
        d2["minRewardRefNote"] = (
            "orientativo offline a 100 gwei; la autoridad es minGasBackedReward(...) "
            "onchain justo antes del commit. reward es msg.value, no un argumento."
        )
        d2["urlPublica"] = mano.url_replay(d["tableId"])
        with open(args.salida_json, "w", encoding="utf-8", newline="\n") as f:
            json.dump(d2, f, indent=1, sort_keys=True)
        print("")
        print("(escrito %s)" % args.salida_json)


if __name__ == "__main__":
    main()
