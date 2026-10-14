#!/usr/bin/env python3
"""Exporta Maia-2 (blitz) a ONNX y genera los datos que usa el juego.

Uso (necesita `pip install maia2 onnx onnxruntime onnxscript`):
    python tools/export_maia2_onnx.py [--weights ruta/blitz_model.pt] [--config ruta/config.yaml]

Genera:
  web/maia2_blitz.onnx               modelo (pesos fp16 + Cast a fp32 -> mitad de tamano)
  data/maia2/moves.json              indice -> uci (vocabulario de Maia-2, perspectiva de blancas)
  data/maia2/elo_buckets.json        mapeo Elo -> categoria
  tests/fixtures/maia2_reference.json  tensores y politicas de referencia de PyTorch

Maia-2 es MIT (c) CSSLab, Universidad de Toronto: https://github.com/CSSLab/maia2
"""
import argparse
import json
import os
import random
import sys

import numpy as np
import torch
import chess
import gdown
import onnx
from onnx import TensorProto, helper, numpy_helper

from maia2.main import MAIA2Model
from maia2.utils import (create_elo_dict, get_all_possible_moves, map_to_category,
						 mirror_move, parse_args)
from maia2.inference import preprocessing
from maia2.train import load_model_state_dict

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL_BLITZ = "https://drive.google.com/uc?id=1X-Z4J3PX3MQFJoa8gRt3aL8CIH0PWoyt"
URL_CFG = "https://drive.google.com/uc?id=1GQTskYMVMubNwZH2Bi6AmevI15CS6gk0"

FENS_REFERENCIA = [
	# (fen, elo_self, elo_oppo)
	("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 1500, 1500),
	("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", 1100, 1900),
	("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", 1800, 1700),
	("r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 4 8", 2100, 1200),
	("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3", 900, 1000),
	("8/P5k1/8/8/8/8/5K2/8 w - - 0 1", 1300, 1300),
	("8/8/8/8/8/6K1/3p4/5k2 b - - 0 1", 1600, 1400),
	("r2q1rk1/pp2bppp/2n1pn2/2pp4/3P4/2PBPN2/PP1N1PPP/R1BQ1RK1 b - - 2 9", 1950, 2050),
	("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", 1000, 1000),
	("1r4k1/P4ppp/8/8/8/8/5PPP/6K1 w - - 0 1", 1700, 1700),
]


def cargar_modelo(weights, config):
	cfg = parse_args(config)
	todos = get_all_possible_moves()
	modelo = MAIA2Model(len(todos), create_elo_dict(), cfg)
	ck = torch.load(weights, map_location="cpu")
	load_model_state_dict(modelo, ck["model_state_dict"])
	modelo.eval()
	return modelo, todos


class Envoltorio(torch.nn.Module):
	"""Solo expone logits de jugada y valor (la cabeza de side-info no hace falta)."""

	def __init__(self, m):
		super().__init__()
		self.m = m

	def forward(self, board, elo_self, elo_oppo):
		logits, _, valor = self.m(board, elo_self, elo_oppo)
		return logits, valor


def a_fp16_con_cast(modelo: onnx.ModelProto) -> onnx.ModelProto:
	"""Guarda los pesos grandes en fp16 y anade un Cast a fp32 antes de usarlos.
	onnxruntime-web (wasm) calcula en fp32, asi que el resultado es casi identico."""
	g = modelo.graph
	nuevos, casts = [], []
	for init in g.initializer:
		if init.data_type == TensorProto.FLOAT and int(np.prod(init.dims)) >= 4096:
			arr = numpy_helper.to_array(init)
			nombre16 = init.name + "__fp16"
			nuevos.append(numpy_helper.from_array(arr.astype(np.float16), nombre16))
			casts.append(helper.make_node("Cast", [nombre16], [init.name],
										  to=TensorProto.FLOAT, name="cast_" + init.name))
		else:
			nuevos.append(init)
	del g.initializer[:]
	g.initializer.extend(nuevos)
	# Los Cast deben ir antes que sus consumidores (orden topologico).
	viejos = list(g.node)
	del g.node[:]
	g.node.extend(casts + viejos)
	return modelo


def exportar_onnx(modelo, ruta, fp16):
	env = Envoltorio(modelo).eval()
	b = torch.zeros(2, 18, 8, 8)
	e = torch.zeros(2, dtype=torch.long)
	tmp = ruta + ".fp32.onnx"
	torch.onnx.export(
		env, (b, e, e), tmp, opset_version=17, dynamo=False,
		input_names=["board", "elo_self", "elo_oppo"],
		output_names=["logits", "value"],
		dynamic_axes={"board": {0: "batch"}, "elo_self": {0: "batch"},
					  "elo_oppo": {0: "batch"}, "logits": {0: "batch"}, "value": {0: "batch"}},
		do_constant_folding=True)
	m = onnx.load(tmp, load_external_data=True)
	if fp16:
		m = a_fp16_con_cast(m)
	onnx.save(m, ruta)
	os.remove(tmp)
	for extra in (tmp + ".data",):
		if os.path.exists(extra):
			os.remove(extra)
	print("modelo:", ruta, round(os.path.getsize(ruta) / 1e6, 1), "MB")


def vocab_json(todos, elo_dict):
	os.makedirs(os.path.join(RAIZ, "data/maia2"), exist_ok=True)
	with open(os.path.join(RAIZ, "data/maia2/moves.json"), "w") as f:
		json.dump(todos, f)
	# Elo -> categoria: <1100 => 0; 1100-1199 => 1 ... 1900-1999 => 9; >=2000 => 10
	info = {
		"descripcion": "categoria = 0 si elo<min; 1+floor((elo-min)/paso) si min<=elo<max; n-1 si elo>=max",
		"min": 1100, "max": 2000, "paso": 100, "categorias": len(elo_dict),
		"tabla": elo_dict,
		"ejemplos": {str(e): map_to_category(e, elo_dict) for e in (400, 1099, 1100, 1199, 1500, 1999, 2000, 2800)},
	}
	with open(os.path.join(RAIZ, "data/maia2/elo_buckets.json"), "w") as f:
		json.dump(info, f, indent="\t")


def politica_torch(modelo, todos, fen, es, eo):
	"""Politica de PyTorch sobre jugadas legales, en UCI reales (des-espejadas)."""
	d = {m: i for i, m in enumerate(todos)}
	ed = create_elo_dict()
	tab, cs, co, legal = preprocessing(fen, es, eo, ed, d)
	with torch.no_grad():
		lg, _, val = modelo(tab.unsqueeze(0), torch.tensor([cs]), torch.tensor([co]))
	lg = lg[0].masked_fill(legal == 0, float("-inf"))
	p = lg.softmax(-1)
	negras = fen.split()[1] == "b"
	res = {}
	for idx in legal.nonzero().flatten().tolist():
		mv = todos[idx]
		res[mirror_move(mv) if negras else mv] = float(p[idx])
	return tab, cs, co, res


def fixture(modelo, todos):
	casos = []
	for fen, es, eo in FENS_REFERENCIA:
		tab, cs, co, pol = politica_torch(modelo, todos, fen, es, eo)
		top = sorted(pol.items(), key=lambda kv: -kv[1])[:5]
		casos.append({
			"fen": fen, "elo_self": es, "elo_oppo": eo, "cat_self": cs, "cat_oppo": co,
			"board": [float(x) for x in tab.flatten().tolist()],  # [18][8][8] aplanado
			"legal_uci": sorted(pol.keys()),
			"top5": [{"uci": u, "p": round(p, 6)} for u, p in top],
		})
	with open(os.path.join(RAIZ, "tests/fixtures/maia2_reference.json"), "w") as f:
		json.dump({"nota": "Generado por tools/export_maia2_onnx.py con PyTorch/maia2", "casos": casos}, f)


def posiciones_aleatorias(n, semilla=7):
	"""Posiciones de partidas aleatorias con sesgo a capturas/centro (suficiente para comparar modelos)."""
	rnd = random.Random(semilla)
	out = []
	while len(out) < n:
		b = chess.Board()
		for ply in range(rnd.randint(4, 90)):
			mv = list(b.legal_moves)
			if not mv or b.is_game_over():
				break
			caps = [m for m in mv if b.is_capture(m)]
			b.push(rnd.choice(caps) if caps and rnd.random() < 0.3 else rnd.choice(mv))
		if not b.is_game_over() and list(b.legal_moves):
			out.append(b.fen())
	return out


def comparar_onnx(modelo, todos, ruta, n):
	import onnxruntime as ort
	sess = ort.InferenceSession(ruta, providers=["CPUExecutionProvider"])
	d = {m: i for i, m in enumerate(todos)}
	ed = create_elo_dict()
	rnd = random.Random(3)
	coincide = 0
	kl_max = 0.0
	for fen in posiciones_aleatorias(n):
		es, eo = rnd.randint(800, 2300), rnd.randint(800, 2300)
		tab, cs, co, legal = preprocessing(fen, es, eo, ed, d)
		with torch.no_grad():
			lt, _, _ = modelo(tab.unsqueeze(0), torch.tensor([cs]), torch.tensor([co]))
		lo, _ = sess.run(None, {"board": tab.unsqueeze(0).numpy(),
								"elo_self": np.array([cs], dtype=np.int64),
								"elo_oppo": np.array([co], dtype=np.int64)})
		m = legal.bool().numpy()
		pt = torch.tensor(lt[0].numpy()).masked_fill(torch.tensor(~m), -1e9).softmax(-1).numpy()
		po = torch.tensor(lo[0]).masked_fill(torch.tensor(~m), -1e9).softmax(-1).numpy()
		coincide += int(pt.argmax() == po.argmax())
		kl_max = max(kl_max, float(np.sum(pt[m] * np.log((pt[m] + 1e-12) / (po[m] + 1e-12)))))
	print(f"ONNX vs PyTorch: acuerdo top-1 {coincide}/{n} = {100 * coincide / n:.1f}%  (KL max {kl_max:.2e})")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--weights")
	ap.add_argument("--config")
	ap.add_argument("--fp32", action="store_true", help="no convertir pesos a fp16")
	ap.add_argument("--check", type=int, default=300, help="posiciones para comparar ONNX vs PyTorch")
	a = ap.parse_args()
	cache = os.path.join(RAIZ, ".maia2_cache")
	os.makedirs(cache, exist_ok=True)
	w = a.weights or os.path.join(cache, "blitz_model.pt")
	c = a.config or os.path.join(cache, "config.yaml")
	if not os.path.exists(w):
		gdown.download(URL_BLITZ, w)
	if not os.path.exists(c):
		gdown.download(URL_CFG, c)
	modelo, todos = cargar_modelo(w, c)
	vocab_json(todos, create_elo_dict())
	fixture(modelo, todos)
	ruta = os.path.join(RAIZ, "web/maia2_blitz.onnx")
	os.makedirs(os.path.dirname(ruta), exist_ok=True)
	exportar_onnx(modelo, ruta, fp16=not a.fp32)
	comparar_onnx(modelo, todos, ruta, a.check)


if __name__ == "__main__":
	sys.exit(main())
