#!/usr/bin/env python3
"""Exporta Maia-3 5M (CSSLab, "Chessformer") a ONNX y genera los datos que usa el juego.

Uso:
    pip install torch python-chess onnx onnxruntime onnxscript numpy huggingface_hub
    pip install git+https://github.com/CSSLab/maia3        # o: --maia3-repo ruta/al/clon
    python tools/export_maia3_onnx.py [--checkpoint ruta/maia3-5m.pt]

Sin --checkpoint descarga maia3-5m.pt de Hugging Face (UofTCSSLab/Maia3-5M).

Genera:
  web/maia3_5m.onnx                    modelo (pesos grandes en fp16 + Cast a fp32)
  data/maia3/moves.json                indice -> uci (vocabulario de 4352 jugadas, perspectiva de blancas)
  tests/fixtures/maia3_reference.json  tensores de entrada y politicas de referencia de PyTorch

Entradas del ONNX (batch dinamico):
  tokens    float32 [B, 64, 96]  8 posiciones (la mas antigua primero) x 12 canales por casilla.
                                 Cada posicion se codifica DESDE EL PUNTO DE VISTA de quien movia
                                 en ella (tablero espejado si movian negras); canales 0-5 = peon,
                                 caballo, alfil, torre, dama, rey de quien mueve; 6-11 = los del rival.
                                 Con menos de 8 posiciones se rellena delante con la mas antigua.
  elo_self  float32 [B]          Elo de quien juega (continuo; el modelo lo recorta a 0..5000)
  elo_oppo  float32 [B]          Elo del rival
Salida: logits float32 [B, 4352] (aplicar softmax SOLO sobre las jugadas legales).

Maia-3: Monroe et al., "Chessformer: A Unified Architecture for Chess Modeling", ICLR 2026.
Codigo y pesos AGPL-3.0, (c) CSSLab, Universidad de Toronto: https://github.com/CSSLab/maia3
"""
import argparse
import copy
import json
import os
import random
import sys
from collections import deque
from types import SimpleNamespace

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HISTORIA = 8
CANALES = 12

# --maia3-repo debe procesarse antes de importar `maia3`.
for _i, _a in enumerate(sys.argv):
	if _a == "--maia3-repo" and _i + 1 < len(sys.argv):
		sys.path.insert(0, sys.argv[_i + 1])
	elif _a.startswith("--maia3-repo="):
		sys.path.insert(0, _a.split("=", 1)[1])

import chess  # noqa: E402
import numpy as np  # noqa: E402
import onnx  # noqa: E402
import torch  # noqa: E402
from onnx import TensorProto, helper, numpy_helper  # noqa: E402

from maia3.dataset import get_historical_tokens, tokenize_board  # noqa: E402
from maia3.model_registry import MODEL_SPECS  # noqa: E402
from maia3.models import MAIA3Model  # noqa: E402
from maia3.utils import get_all_possible_moves, mirror_move  # noqa: E402

# (fen inicial o None, jugadas UCI desde ahi, [(elo_self, elo_oppo), ...])
# Cubre: inicio (historial todo relleno), negras a mover, enroques, captura al paso,
# promociones de ambos bandos, historial completo de 8 y jaque mate.
CASOS_REFERENCIA = [
	(None, "", [(1500, 1500), (800, 2200)]),
	(None, "e2e4", [(1100, 1900), (1500, 1500)]),
	(None, "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5", [(1800, 1700), (1200, 1200), (2400, 2400)]),
	(None, "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5 c1e3 c5b6 b1c3 d7d6 d1d2 c8e6", [(2100, 1200), (1000, 1000)]),
	(None, "e2e4 a7a6 e4e5 d7d5", [(900, 1000), (1700, 1700)]),  # captura al paso e5xd6
	(None, "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1 f8c5 d2d3 d7d6 c1g5 h7h6 g5h4 e8g8", [(1950, 2050), (1300, 1300)]),
	(None, "a2a4 b7b5 a4b5 a7a6 b5a6 c7c6 a6a7 c6c5", [(1300, 1300), (2000, 1500)]),  # a7xb8 = promocion
	("8/P5k1/8/8/8/8/5K2/8 w - - 0 1", "f2e2 g7f7", [(1600, 1400), (1100, 1100)]),  # a8 = promocion
	("8/8/8/8/8/6K1/3p4/5k2 b - - 0 1", "", [(1600, 1400), (2000, 900)]),  # negras: d2d1 = promocion
	("1r4k1/P4ppp/8/8/8/8/5PPP/6K1 w - - 0 1", "g1h1 g8h8", [(1700, 1700)]),
	(None, "e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7", [(1400, 1400)]),  # jaque mate (sin jugadas legales)
]


def cargar_modelo(checkpoint):
	spec = next(s for s in MODEL_SPECS if s.name == "maia3-5m")
	cfg = SimpleNamespace(**spec.config)
	if checkpoint is None:
		from huggingface_hub import hf_hub_download
		checkpoint = hf_hub_download(repo_id=spec.repo_id, filename=spec.checkpoint_filename)
	modelo = MAIA3Model(cfg)
	ck = torch.load(checkpoint, map_location="cpu", weights_only=True)
	sd = ck["model_state_dict"] if isinstance(ck, dict) and "model_state_dict" in ck else ck
	sd = {k.replace("smolgen", "gab"): v for k, v in sd.items()}
	faltan, sobran = modelo.load_state_dict(sd, strict=False)
	if faltan or sobran:
		raise SystemExit(f"checkpoint incompatible: faltan {faltan[:3]}, sobran {sobran[:3]}")
	modelo.eval()
	n = sum(p.numel() for p in modelo.parameters())
	print(f"checkpoint {checkpoint}: {n / 1e6:.2f} M parametros")
	return modelo, cfg


class Envoltorio(torch.nn.Module):
	"""Solo los logits de jugada (las cabezas de valor y ponder no hacen falta)."""

	def __init__(self, m):
		super().__init__()
		self.m = m

	def forward(self, tokens, elo_self, elo_oppo):
		logits, _, _ = self.m(tokens, elo_self, elo_oppo)
		return logits


def a_fp16_con_cast(modelo: onnx.ModelProto) -> onnx.ModelProto:
	"""Guarda los pesos grandes en fp16 y anade un Cast a fp32 antes de usarlos.
	onnxruntime calcula en fp32, asi que el resultado es casi identico."""
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
	viejos = list(g.node)  # los Cast van antes que sus consumidores
	del g.node[:]
	g.node.extend(casts + viejos)
	return modelo


class RMSNormExplicito(torch.nn.Module):
	"""RMSNorm descompuesto en operaciones basicas: aten::rms_norm no existe en opset 17."""

	def __init__(self, orig):
		super().__init__()
		self.weight = orig.weight
		self.eps = orig.eps if orig.eps is not None else torch.finfo(orig.weight.dtype).eps

	def forward(self, x):
		return x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps) * self.weight


def sustituir_rmsnorm(modulo):
	for nombre, hijo in modulo.named_children():
		if isinstance(hijo, torch.nn.RMSNorm):
			setattr(modulo, nombre, RMSNormExplicito(hijo))
		else:
			sustituir_rmsnorm(hijo)


def exportar_onnx(modelo, ruta, fp16):
	modelo = copy.deepcopy(modelo)  # el original se queda intacto para las comparaciones
	sustituir_rmsnorm(modelo)
	env = Envoltorio(modelo).eval()
	t = torch.zeros(2, 64, CANALES * HISTORIA)
	e = torch.full((2,), 1500.0)
	tmp = ruta + ".fp32.onnx"
	torch.onnx.export(
		env, (t, e, e), tmp, opset_version=17, dynamo=False,
		input_names=["tokens", "elo_self", "elo_oppo"], output_names=["logits"],
		dynamic_axes={"tokens": {0: "batch"}, "elo_self": {0: "batch"},
					  "elo_oppo": {0: "batch"}, "logits": {0: "batch"}},
		do_constant_folding=True)
	m = onnx.load(tmp, load_external_data=True)
	if fp16:
		m = a_fp16_con_cast(m)
	onnx.save(m, ruta)
	for extra in (tmp, tmp + ".data"):
		if os.path.exists(extra):
			os.remove(extra)
	print("modelo:", ruta, round(os.path.getsize(ruta) / 1e6, 2), "MB")


# --- Entradas y politica de referencia (con el codigo oficial de maia3) -------------------------

def tokens_de(boards, cfg):
	"""boards: tableros python-chess (el ultimo es la posicion actual).
	Devuelve el tensor [64, 96] exactamente como lo arma maia3 al inferir."""
	hist = deque((tokenize_board(b) for b in boards[-HISTORIA:]), maxlen=HISTORIA)
	return get_historical_tokens(hist, cfg, 0.0, 0.0, 0.0, 0.0)[:, :CANALES * HISTORIA]


def historial_desde(ini, ucis):
	"""Lista de tableros (copias) desde la posicion inicial, uno por jugada."""
	b = chess.Board(ini) if ini else chess.Board()
	out = [b.copy(stack=False)]
	for u in ucis:
		b.push_uci(u)
		out.append(b.copy(stack=False))
	return out


def logits_torch(modelo, tok, es, eo):
	with torch.no_grad():
		lg, _, _ = modelo(tok.unsqueeze(0), torch.tensor([float(es)]), torch.tensor([float(eo)]))
	return lg[0]


def politica_torch(modelo, cfg, todos, boards, es, eo):
	"""Politica de PyTorch sobre las jugadas legales, en UCI reales (des-espejadas)."""
	d = {m: i for i, m in enumerate(todos)}
	b = boards[-1]
	tok = tokens_de(boards, cfg)
	lg = logits_torch(modelo, tok, es, eo)
	negras = b.turn == chess.BLACK
	idx, reales = [], []
	for mv in b.legal_moves:
		u = mv.uci()
		idx.append(d[mirror_move(u) if negras else u])
		reales.append(u)
	if not idx:
		return tok, {}
	p = lg[idx].softmax(-1).tolist()
	return tok, dict(zip(reales, p))


def fixture(modelo, cfg, todos):
	casos = []
	for ini, jugadas, elos in CASOS_REFERENCIA:
		boards = historial_desde(ini, jugadas.split())
		tok = tokens_de(boards, cfg)
		por_elo = []
		for es, eo in elos:
			_, pol = politica_torch(modelo, cfg, todos, boards, es, eo)
			top = sorted(pol.items(), key=lambda kv: -kv[1])[:5]
			por_elo.append({"elo_self": es, "elo_oppo": eo,
							"top5": [{"uci": u, "p": round(p, 6)} for u, p in top]})
		casos.append({
			"inicio": ini or chess.STARTING_FEN,
			"jugadas": jugadas,
			"fens": [b.fen() for b in boards[-HISTORIA:]],  # historial (la mas antigua primero), ultimo = actual
			"tokens": [int(x) for x in tok.flatten().tolist()],  # [64][96] aplanado (casilla*96 + posicion*12 + canal)
			"legal_uci": sorted(m.uci() for m in boards[-1].legal_moves),
			"elos": por_elo,
		})
	with open(os.path.join(RAIZ, "tests/fixtures/maia3_reference.json"), "w") as f:
		json.dump({"nota": "Generado por tools/export_maia3_onnx.py con PyTorch y el codigo oficial de maia3. "
						   "tokens = [64][96], indice casilla*96 + posicion*12 + canal; fens = historial (max 8).",
				   "casos": casos}, f, separators=(",", ":"))
	print("fixture:", len(casos), "posiciones")


def partidas_aleatorias(n, semilla=7):
	"""Partidas aleatorias (con sesgo a capturas) cortadas en n posiciones: lista de historiales."""
	rnd = random.Random(semilla)
	out = []
	while len(out) < n:
		b = chess.Board()
		pila = [b.copy(stack=False)]
		for _ in range(rnd.randint(1, 100)):
			mv = list(b.legal_moves)
			if not mv or b.is_game_over():
				break
			caps = [m for m in mv if b.is_capture(m) or m.promotion]
			b.push(rnd.choice(caps) if caps and rnd.random() < 0.3 else rnd.choice(mv))
			pila.append(b.copy(stack=False))
		if not b.is_game_over() and list(b.legal_moves):
			out.append(pila)
	return out


def comparar_onnx(modelo, cfg, todos, ruta, n):
	import onnxruntime as ort
	sess = ort.InferenceSession(ruta, providers=["CPUExecutionProvider"])
	d = {m: i for i, m in enumerate(todos)}
	rnd = random.Random(3)
	coincide, dmax, kl_max = 0, 0.0, 0.0
	for pila in partidas_aleatorias(n):
		es, eo = rnd.uniform(600, 2800), rnd.uniform(600, 2800)
		tok = tokens_de(pila, cfg)
		lt = logits_torch(modelo, tok, es, eo)
		lo = sess.run(None, {"tokens": tok.unsqueeze(0).numpy(),
							 "elo_self": np.array([es], dtype=np.float32),
							 "elo_oppo": np.array([eo], dtype=np.float32)})[0][0]
		b = pila[-1]
		negras = b.turn == chess.BLACK
		ids = [d[mirror_move(m.uci()) if negras else m.uci()] for m in b.legal_moves]
		pt = lt[ids].softmax(-1).numpy()
		po = torch.tensor(lo)[ids].softmax(-1).numpy()
		coincide += int(pt.argmax() == po.argmax())
		dmax = max(dmax, float(np.abs(pt - po).max()))
		kl_max = max(kl_max, float(np.sum(pt * np.log((pt + 1e-12) / (po + 1e-12)))))
	print(f"ONNX vs PyTorch: acuerdo top-1 {coincide}/{n} = {100 * coincide / n:.1f}%  "
		  f"(dif. max de prob {dmax:.2e}, KL max {kl_max:.2e})")
	return coincide, n


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--checkpoint", help="maia3-5m.pt local (si no, se descarga de Hugging Face)")
	ap.add_argument("--maia3-repo", help="clon de github.com/CSSLab/maia3 (si el paquete no esta instalado)")
	ap.add_argument("--fp32", action="store_true", help="no convertir pesos a fp16")
	ap.add_argument("--check", type=int, default=400, help="posiciones para comparar ONNX vs PyTorch")
	a = ap.parse_args()
	modelo, cfg = cargar_modelo(a.checkpoint)
	todos = get_all_possible_moves()
	assert len(todos) == 4352, len(todos)
	os.makedirs(os.path.join(RAIZ, "data/maia3"), exist_ok=True)
	with open(os.path.join(RAIZ, "data/maia3/moves.json"), "w") as f:
		json.dump(todos, f)
	os.makedirs(os.path.join(RAIZ, "tests/fixtures"), exist_ok=True)
	fixture(modelo, cfg, todos)
	ruta = os.path.join(RAIZ, "web/maia3_5m.onnx")
	os.makedirs(os.path.dirname(ruta), exist_ok=True)
	exportar_onnx(modelo, ruta, fp16=not a.fp32)
	ok, n = comparar_onnx(modelo, cfg, todos, ruta, a.check)
	return 0 if ok / n >= 0.99 else 1


if __name__ == "__main__":
	sys.exit(main())
