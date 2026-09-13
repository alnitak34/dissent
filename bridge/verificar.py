# -*- coding: utf-8 -*-
"""Comprueba que unos bytes de `inputs` son de verdad una mano concreta.

    python bridge/verificar.py <inputsHex> <tableId> [--seq N] [--umbral W]

Baja el replay del endpoint PUBLICO de arena.dev.fun. Sin credenciales, sin
token, sin cookie, sin este repo, sin el corpus de nadie. Solo biblioteca
estandar de Python.

Sin --seq, recorre todas las decisiones de river de esa mesa y dice cual encaja.
Con --seq, compara campo por campo contra esa decision y lista las diferencias.

Imprime OK si todo lo verificable coincide, y SIEMPRE imprime al final lo que NO
se puede verificar con el endpoint. Eso no es un descargo: es parte del
resultado.
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

BP_TO_WAD = 10 ** 14


def campos(d):
    """Lo que los bytes afirman, en forma comparable y legible."""
    return [
        ("hole", tuple(d["hole"])),
        ("board", tuple(d["board"])),
        ("mixBp", tuple(d["mixBp"])),
        ("priceBp", d["priceBp"]),
    ]


def leible(nombre, v):
    if nombre in ("hole", "board"):
        try:
            return " ".join(mano.u8_a_carta(c) for c in v) + "  %s" % (list(v),)
        except ValueError:
            return "%s (no son cartas validas)" % (list(v),)
    if nombre == "mixBp":
        return "%s  = (%.4f, %.4f, %.4f)" % (list(v), v[0] / 1e4, v[1] / 1e4, v[2] / 1e4)
    if nombre == "priceBp":
        return "%d bp = %.4f" % (v, v / 1e4)
    return repr(v)


def comparar(afirmado, real):
    """Devuelve la lista de (campo, afirmado, real) que no coinciden."""
    dif = []
    for (n, va), (_, vb) in zip(campos(afirmado), campos(real)):
        if va != vb:
            dif.append((n, va, vb))
    return dif


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputsHex", help="los bytes de inputs, con o sin 0x")
    ap.add_argument("tableId")
    ap.add_argument("--seq", type=int, help="fijar la decision en vez de buscarla")
    ap.add_argument("--umbral", type=int,
                    help="ademas, comprobar que este umbral (en WAD) es el precio")
    ap.add_argument("--replay", help="usar un replay local en vez de bajarlo "
                                     "(para auditar el propio verificador)")
    args = ap.parse_args()

    hx = args.inputsHex.strip()
    if hx.lower().startswith("0x"):
        hx = hx[2:]
    try:
        raw = bytes.fromhex(hx)
    except ValueError as e:
        raise SystemExit("los inputs no son hexadecimal valido: %s" % e)
    try:
        afirmado = mano.abi_decode_inputs(raw)
    except ValueError as e:
        raise SystemExit("los inputs no tienen la forma de Inputs: %s" % e)

    print("inputs      : 0x%s...%s  (%d bytes)" % (hx[:16], hx[-16:], len(raw)))
    print("keccak256   : 0x%s" % mano.keccak256(raw).hex())
    print("afirman     :")
    for n, v in campos(afirmado):
        print("    %-8s %s" % (n, leible(n, v)))
    print("")

    if args.replay:
        with open(args.replay, encoding="utf-8") as f:
            replay = json.load(f)
        print("replay      : %s  (LOCAL, pasado con --replay)" % args.replay)
    else:
        url = mano.url_replay(args.tableId)
        print("bajando     : %s" % url)
        try:
            replay = mano.bajar_replay(args.tableId)
        except Exception as e:
            raise SystemExit("no se pudo bajar el replay: %s: %s" % (type(e).__name__, e))

    j = replay
    for k in ("result", "data", "json"):
        if isinstance(j, dict) and k in j:
            j = j[k]
    eventos = j.get("events") or []
    print("eventos     : %d" % len(eventos))
    print("")

    if args.seq is not None:
        objetivos = [args.seq]
    else:
        objetivos = sorted({e.get("sequence") for e in eventos
                            if e.get("type") == "ActionTaken" and e.get("street") == "River"
                            and e.get("sequence") is not None})
        print("decisiones de river en esta mesa: %s" % objetivos)

    encaja = []
    fallos = []
    for seq in objetivos:
        try:
            real = mano.extraer(replay, seq)
        except (mano.FaltaDato, mano.NoAplica) as e:
            fallos.append((seq, "%s: %s" % (type(e).__name__, e)))
            continue
        dif = comparar(afirmado, real)
        if not dif:
            encaja.append(real)
        else:
            fallos.append((seq, dif))

    if len(encaja) == 1:
        r = encaja[0]
        print("")
        print("OK — los bytes son esta mano:")
        print("    tableId   %s" % r["tableId"])
        print("    sequence  %s   (agentId %s, asiento %s, calle %s)"
              % (r["sequence"], r["agentId"], r["seat"], r["street"]))
        print("    hole      %s" % " ".join(r["holeTxt"]))
        print("    board     %s" % " ".join(r["boardTxt"]))
        print("    pot %g + call %g -> precio %.10f = %d bp"
              % (r["pot"], r["call"], r["price"], r["priceBp"]))
        print("    presion   %s/%s leida del replay (asiento agresor %s)"
              % (r["presion"][0], r["presion"][1], r["asientoAgresor"]))
        print("    mixBp     %s = la fila de esa presion en la tabla del modelo"
              % r["mixBp"])
        print("    rivales   %d vivo(s): heads-up, que es lo que la rama exige"
              % r["nOpp"])
        print("    (en el replay, fuera de los bytes: accion=%r reasoning=%r)"
              % (r["accionReal"], r["razonReal"]))
        estado = 0
    elif len(encaja) > 1:
        print("")
        print("AMBIGUO — %d decisiones distintas producen los mismos bytes: %s"
              % (len(encaja), [r["sequence"] for r in encaja]))
        print("Los bytes no distinguen cual. Hace falta el sequence.")
        estado = 2
    else:
        print("")
        print("NO COINCIDE — ninguna decision de esta mesa produce estos bytes.")
        for seq, d in fallos:
            if isinstance(d, str):
                print("    seq %-4s descartada: %s" % (seq, d))
            else:
                print("    seq %-4s difiere en %d campo(s):" % (seq, len(d)))
                for n, va, vb in d:
                    print("        %-8s bytes dicen %s" % (n, leible(n, va)))
                    print("        %-8s replay dice %s" % ("", leible(n, vb)))
        estado = 1

    if args.umbral is not None:
        esperado = afirmado["priceBp"] * BP_TO_WAD
        print("")
        if args.umbral == esperado:
            print("umbral      : OK, %d == priceBp(%d) * 1e14"
                  % (args.umbral, afirmado["priceBp"]))
        else:
            print("umbral      : NO, %d != %d (= priceBp %d * 1e14)"
                  % (args.umbral, esperado, afirmado["priceBp"]))
            print("              Ojo: que el umbral sea el precio es una REGLA elegida,")
            print("              no un hecho. El agente puede elegir otro umbral y seguir")
            print("              siendo honesto; simplemente esta afirmando otra cosa.")
            estado = max(estado, 1)

    print("")
    print("LO QUE ESTE ENDPOINT NO PUEDE VERIFICAR")
    print("  1. La tabla del modelo. El replay fija la CLASE de presion")
    print("     (bet/multi/raise x small/big); los tres numeros de mixBp salen de")
    print("     VR_MIX_BP, medida sobre manos que llegaron a showdown. Si rechazás")
    print("     esa tabla, rechazás el compromiso entero, y con razon: es el")
    print("     limite 5 del README.")
    print("  2. El umbral, salvo contra la regla `umbral = precio` (--umbral).")
    print("     Elegir el umbral es del agente.")
    print("  3. Que quien firmo el commit sea quien jugo la mano. El endpoint da")
    print("     un agentId; la cadena da una direccion. Nada los ata.")
    print("  4. Que el replay sea autentico. No viene firmado. Es el archivo de un")
    print("     tercero que hoy esta abierto, no una garantia criptografica.")
    sys.exit(estado)


if __name__ == "__main__":
    main()
