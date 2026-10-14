#!/usr/bin/env python3
"""Comprueba que web/maia3_5m.onnx reproduce las politicas de PyTorch guardadas en
tests/fixtures/maia3_reference.json (usa SOLO los tensores del fixture, no maia3).
Necesita: pip install onnxruntime numpy"""
import json
import os
import sys

import numpy as np
import onnxruntime as ort

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
moves = json.load(open(os.path.join(RAIZ, "data/maia3/moves.json")))
idx = {m: i for i, m in enumerate(moves)}
ref = json.load(open(os.path.join(RAIZ, "tests/fixtures/maia3_reference.json")))["casos"]
sess = ort.InferenceSession(os.path.join(RAIZ, "web/maia3_5m.onnx"), providers=["CPUExecutionProvider"])


def espejar(u):
	return u[0] + str(9 - int(u[1])) + u[2] + str(9 - int(u[3])) + u[4:]


fallos = 0
for c in ref:
	negras = c["fens"][-1].split()[1] == "b"
	tok = np.array(c["tokens"], dtype=np.float32).reshape(1, 64, 96)
	legales = c["legal_uci"]
	if not legales:
		print("OK ", c["fens"][-1][:40].ljust(40), "sin jugadas legales")
		continue
	ids = [idx[espejar(u) if negras else u] for u in legales]
	for e in c["elos"]:
		logits = sess.run(None, {"tokens": tok,
								 "elo_self": np.array([e["elo_self"]], dtype=np.float32),
								 "elo_oppo": np.array([e["elo_oppo"]], dtype=np.float32)})[0]
		z = logits[0][ids]
		p = np.exp(z - z.max())
		p /= p.sum()
		pol = dict(zip(legales, p))
		top = sorted(pol, key=lambda k: -pol[k])[:5]
		err = max(abs(pol[t["uci"]] - t["p"]) for t in e["top5"])
		# Un empate dentro del error permitido puede cambiar el orden entre fp16 y fp32.
		dudoso = len(e["top5"]) > 1 and e["top5"][0]["p"] - e["top5"][1]["p"] < 4e-3
		ok = (top[0] == e["top5"][0]["uci"] or dudoso) and err < 2e-3
		fallos += 0 if ok else 1
		print("OK " if ok else "MAL", c["fens"][-1][:40].ljust(40), "%d/%d" % (e["elo_self"], e["elo_oppo"]),
			  "top1", top[0], "err_max_prob %.1e" % err)
print("fallos:", fallos)
sys.exit(1 if fallos else 0)
