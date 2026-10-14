#!/usr/bin/env python3
"""Comprueba que web/maia2_blitz.onnx reproduce las politicas de PyTorch guardadas
en tests/fixtures/maia2_reference.json (usa SOLO el tensor del fixture, no maia2).
Necesita: pip install onnxruntime numpy"""
import json
import os
import sys

import numpy as np
import onnxruntime as ort

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
moves = json.load(open(os.path.join(RAIZ, "data/maia2/moves.json")))
idx = {m: i for i, m in enumerate(moves)}
ref = json.load(open(os.path.join(RAIZ, "tests/fixtures/maia2_reference.json")))["casos"]
sess = ort.InferenceSession(os.path.join(RAIZ, "web/maia2_blitz.onnx"), providers=["CPUExecutionProvider"])


def espejar(u):
	return u[0] + str(9 - int(u[1])) + u[2] + str(9 - int(u[3])) + u[4:]


fallos = 0
for c in ref:
	negras = c["fen"].split()[1] == "b"
	tab = np.array(c["board"], dtype=np.float32).reshape(1, 18, 8, 8)
	logits, _ = sess.run(None, {"board": tab,
								"elo_self": np.array([c["cat_self"]], dtype=np.int64),
								"elo_oppo": np.array([c["cat_oppo"]], dtype=np.int64)})
	legales = c["legal_uci"]
	ids = [idx[espejar(u) if negras else u] for u in legales]
	z = logits[0][ids]
	p = np.exp(z - z.max())
	p /= p.sum()
	pol = dict(zip(legales, p))
	top = sorted(pol, key=lambda k: -pol[k])[:5]
	esperado = [t["uci"] for t in c["top5"]]
	err = max(abs(pol[t["uci"]] - t["p"]) for t in c["top5"])
	ok = top == esperado and err < 2e-3
	fallos += 0 if ok else 1
	print("OK " if ok else "MAL", c["fen"][:40].ljust(40), "top1", top[0], "err_max_prob %.1e" % err)
print("fallos:", fallos)
sys.exit(1 if fallos else 0)
