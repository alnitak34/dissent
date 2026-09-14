# -*- coding: utf-8 -*-
"""Tests offline del puente. Biblioteca estandar, sin red ni credenciales.

    python -m unittest discover bridge -p "test_*.py"

Usan una fixture minima derivada del caso real. No incluyen el replay completo,
los otros agentes ni eventos que el puente no necesita.
"""
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import armar_commit  # noqa: E402
import mano  # noqa: E402

TABLE = "cmtr0ktvzxa5q15he4ekev8ub"
SEQ = 29
FIXTURE = os.path.join(AQUI, "fixtures", "alnitak-river-minimal.json")
# El mismo hash literal que test/ManoReal.t.sol (INPUTS_HASH). El hash pin̈ea los
# bytes de forma unica: si inputsHex cambiara, el hash cambiaria.
INPUTS_HASH = "0xa174393d39f1e1ec234522a9c80f28e565e8b9908e567c452065e156f56a73ac"


def _replay():
    with open(FIXTURE, encoding="utf-8") as f:
        return json.load(f)


def _extraido():
    return mano.extraer(_replay(), SEQ)


class TestBytesYHash(unittest.TestCase):
    def test_inputs_hex_y_hash_de_la_fixture(self):
        d = _extraido()
        raw = mano.bytes_de(d)
        # inputsHex estable y bytes -> hash exacto (el hash de ManoReal.t.sol).
        self.assertEqual(raw.hex(), mano.bytes_de(_extraido()).hex(), "inputsHex determinista")
        self.assertEqual("0x" + mano.keccak256(raw).hex(), INPUTS_HASH)

    def test_inputs_length_352(self):
        raw = mano.bytes_de(_extraido())
        self.assertEqual(len(raw), 352)


class TestSalidaJSON(unittest.TestCase):
    def _correr_json(self):
        replay = FIXTURE
        fd, out = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        try:
            subprocess.run(
                [sys.executable, os.path.join(AQUI, "armar_commit.py"), TABLE, str(SEQ),
                 "--replay", replay, "--json", out],
                check=True, capture_output=True,
            )
            with open(out, encoding="utf-8") as f:
                return json.load(f)
        finally:
            os.remove(out)

    def test_json_trae_los_tres_limites_e_inputs_length(self):
        j = self._correr_json()
        self.assertEqual(j["recomputeGasLimit"], armar_commit.ALNITAK_RECOMPUTE_GAS_LIMIT)
        self.assertEqual(j["validateGasLimit"], armar_commit.ALNITAK_VALIDATE_GAS_LIMIT)
        self.assertEqual(j["maxEvidenceLen"], armar_commit.ALNITAK_MAX_EVIDENCE_LEN)
        self.assertEqual(j["inputsLength"], 352)
        self.assertEqual(j["inputsHash"], INPUTS_HASH)

    def test_json_marca_la_reward_como_orientativa_no_autoridad(self):
        j = self._correr_json()
        self.assertIn("minRewardRefWei", j)
        nota = j["minRewardRefNote"].lower()
        self.assertIn("orientativo", nota)
        self.assertIn("mingasbackedreward", nota)
        self.assertIn("msg.value", nota)


class TestSalidaTexto(unittest.TestCase):
    def _stdout(self):
        replay = FIXTURE
        r = subprocess.run(
            [sys.executable, os.path.join(AQUI, "armar_commit.py"), TABLE, str(SEQ), "--replay", replay],
            check=True, capture_output=True, text=True, encoding="utf-8",
        )
        return r.stdout

    def test_orden_de_commit_coincide_con_la_firma(self):
        # El orden mostrado tiene que ser el de DissentCore.commit. Acotamos al
        # bloque de argumentos (esas palabras tambien aparecen en otras secciones).
        out = self._stdout()
        ini = out.find("ARGUMENTOS DE commit()")
        fin = out.find("reward: es msg.value")
        self.assertTrue(0 <= ini < fin, "no encontre el bloque de argumentos")
        bloque = out[ini:fin]
        orden = [
            "recomputer", "inputs", "threshold", "comparator", "action",
            "deposit", "window", "recomputeGasLimit", "validateGasLimit",
            "maxEvidenceLen", "salt",
        ]
        pos = [bloque.find(x) for x in orden]
        self.assertTrue(all(p >= 0 for p in pos), "faltan argumentos en el bloque")
        self.assertEqual(pos, sorted(pos), "el orden no coincide con la firma de commit")

    def test_no_presenta_la_reward_offline_como_autoridad_onchain(self):
        out = self._stdout()
        self.assertIn("NO ES AUTORIDAD", out)
        self.assertIn("minGasBackedReward", out)
        self.assertIn("ONCHAIN", out)
        self.assertIn("reward: es msg.value", out)


if __name__ == "__main__":
    unittest.main()
