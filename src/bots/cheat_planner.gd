class_name CheatPlanner
extends RefCounted
## Lógica pura (sin nodos) para decidir si un bot hace trampa y cuál.
## Enumera las trampas válidas con `CheatRules`, las puntúa por la ganancia
## de evaluación menos el riesgo (duración y evidencia) y elige una al azar
## ponderada: la mejor es la más probable, pero no siempre sale.

## Ganancia mínima (centipeones) para que valga la pena arriesgarse.
const MIN_GAIN := 15.0
## Cuánto pesa cada segundo de mano ocupada y cada punto de evidencia (en unidades de puntaje).
const DURATION_PENALTY := 0.5
const EVIDENCE_PENALTY := 3.0
## Rendimientos decrecientes: la ganancia (en peones) pasa por log(1 + g) * GAIN_SCALE.
const GAIN_SCALE := 1.6
## Castigo extra por lo llamativo de llevarse una pieza grande (por peón de valor).
const NOTICEABLE_PENALTY := 0.45
## El apetito de riesgo (0..1) multiplica el castigo de riesgo entre estos extremos.
const RISK_MULT_CAUTIOUS := 1.6
const RISK_MULT_BOLD := 0.6
## Temperatura del muestreo (mayor = más aleatorio).
const PICK_TEMPERATURE := 1.2
## Máximo de candidatas válidas por tipo de trampa (acota el costo).
const MAX_PER_DEF := 24
## Escala de `cheat_chance` (por oportunidad) a probabilidad por evaluación (~0.5 s).
const TICK_SCALE := 0.2

const _DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## Candidatas válidas: [{def, from, to, duration, gain, score}].
static func candidates(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator, risk_appetite: float = 0.5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base_eval := FallbackBrain.evaluate(board, color)
	for def: CheatDef in defs:
		var raw := _raw_moves(board, color, def)
		_shuffle(raw, rng)
		var found := 0
		for pair: Vector2i in raw:
			var v := CheatRules.validate(board, color, def, pair.x, pair.y)
			if not v.ok:
				continue
			var after := board.clone()
			CheatRules.apply(after, color, def, pair.x, pair.y, rng)
			var gain := FallbackBrain.evaluate(after, color) - base_eval
			# Llevarse una pieza grande a la vista de todos se nota mucho más.
			var noticeable := 0.0
			if def.kind == CheatDef.Kind.STEAL:
				noticeable = ChessPiece.value_of(board.squares[pair.x]) / 100.0
			out.append({
				"def": def, "from": pair.x, "to": pair.y, "duration": v.duration,
				"gain": gain, "score": score(gain, v.duration, def.evidence, risk_appetite, noticeable),
			})
			found += 1
			if found >= MAX_PER_DEF:
				break
	return out


## Puntaje: ganancia con rendimientos decrecientes menos riesgo (evidencia,
## duración y, al robar, el valor de la pieza). Un bot audaz castiga menos el riesgo.
static func score(gain: float, duration: float, evidence: float, risk_appetite: float = 0.5, noticeable: float = 0.0) -> float:
	var benefit := GAIN_SCALE * log(1.0 + maxf(gain, 0.0) / 100.0)
	var risk := EVIDENCE_PENALTY * evidence + DURATION_PENALTY * duration + NOTICEABLE_PENALTY * noticeable
	return benefit - risk * lerpf(RISK_MULT_CAUTIOUS, RISK_MULT_BOLD, clampf(risk_appetite, 0.0, 1.0))


## Elige una candidata con ganancia suficiente en dos pasos: primero el TIPO de
## trampa (ponderado por su mejor puntaje, sin que pese cuántas variantes tenga)
## y luego la candidata dentro del tipo. {} si no hay ninguna útil.
static func pick(cands: Array, rng: RandomNumberGenerator, temperature: float = PICK_TEMPERATURE) -> Dictionary:
	var by_def: Dictionary = {}
	var best := -INF
	for c: Dictionary in cands:
		if c.gain < MIN_GAIN:
			continue
		var id: StringName = c.def.id
		if not by_def.has(id):
			by_def[id] = {"best": -INF, "list": []}
		by_def[id].list.append(c)
		by_def[id].best = maxf(by_def[id].best, c.score)
		best = maxf(best, c.score)
	if by_def.is_empty():
		return {}
	var groups: Array = by_def.values()
	var gw: Array[float] = []
	for g: Dictionary in groups:
		gw.append(exp((g.best - best) / maxf(temperature, 0.05)))
	var group: Dictionary = groups[_weighted_index(gw, rng)]
	var useful: Array = group.list
	var weights: Array[float] = []
	for c: Dictionary in useful:
		weights.append(exp((c.score - group.best) / maxf(temperature, 0.05)))
	return useful[_weighted_index(weights, rng)]


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1


## Atajo: enumera y elige.
static func plan(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator, risk_appetite: float = 0.5) -> Dictionary:
	return pick(candidates(board, color, defs, rng, risk_appetite), rng)


## Probabilidad de intentar una trampa en esta evaluación (~cada 0.5 s).
## Cero si el rival mira el tablero; sube si va perdiendo o con poco reloj.
static func attempt_probability(board: BoardState, color: int, personality: BotPersonality, remaining: float, opponent_looking: bool) -> float:
	if opponent_looking:
		return 0.0
	var p := personality.cheat_chance * TICK_SCALE
	var behind := clampf(-FallbackBrain.evaluate(board, color) / 400.0, 0.0, 1.0)
	p *= 1.0 + 2.0 * behind
	if remaining < 40.0:
		p *= 1.0 + clampf((40.0 - remaining) / 40.0, 0.0, 1.0)
	return clampf(p, 0.0, 0.5)


## Probabilidad de abortar al ser mirado a mitad de trampa (más nervioso = más).
static func abort_probability(personality: BotPersonality, evidence: float) -> float:
	return clampf(personality.abort_chance * lerpf(0.7, 1.0, evidence), 0.0, 1.0)


# --- Enumeración -----------------------------------------------------------

static func _raw_moves(b: BoardState, color: int, def: CheatDef) -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	for sq in 64:
		var p := b.squares[sq]
		if p == ChessPiece.NONE or ChessPiece.type_of(p) == ChessPiece.KING:
			continue
		var own := ChessPiece.color_of(p) == color
		match def.kind:
			CheatDef.Kind.NUDGE:
				if own:
					var to := sq + 8 * ChessRules.pawn_dir(color)
					if to >= 0 and to <= 63:
						res.append(Vector2i(sq, to))
			CheatDef.Kind.SLIDE:
				if own:
					var reach := def.max_distance if def.max_distance > 0 else 7
					for d: Vector2i in _DIRS:
						for i in range(1, reach + 1):
							var f := ChessPiece.file_of(sq) + d.x * i
							var r := ChessPiece.rank_of(sq) + d.y * i
							if f < 0 or f > 7 or r < 0 or r > 7:
								break
							var to := ChessPiece.square(f, r)
							if b.squares[to] != ChessPiece.NONE:
								break
							res.append(Vector2i(sq, to))
			CheatDef.Kind.STEAL:
				if not own:
					res.append(Vector2i(sq, -1))
			CheatDef.Kind.MOVE_ENEMY:
				if not own:
					var reach := def.max_distance if def.max_distance > 0 else 3
					for df in range(-reach, reach + 1):
						for dr in range(-reach, reach + 1):
							var f := ChessPiece.file_of(sq) + df
							var r := ChessPiece.rank_of(sq) + dr
							if (df == 0 and dr == 0) or f < 0 or f > 7 or r < 0 or r > 7:
								continue
							var to := ChessPiece.square(f, r)
							if b.squares[to] == ChessPiece.NONE:
								res.append(Vector2i(sq, to))
	return res


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# --- Acusaciones y eventos ------------------------------------------------------

## Probabilidad por jugada rival de acusar sin haber visto nada. Cada
## advertencia propia la reduce con fuerza: con 2 casi nunca acusa a ciegas.
static func blind_accuse_probability(base_chance: float, warnings: int) -> float:
	return base_chance * pow(0.25, maxf(float(warnings), 0.0)) * (0.0 if warnings >= 2 else 1.0)


## Espera (segundos) entre eventos de distracción según el apetito de riesgo.
static func event_cooldown(risk_appetite: float, rng: RandomNumberGenerator) -> float:
	var base := lerpf(100.0, 55.0, clampf(risk_appetite, 0.0, 1.0))
	return base * rng.randf_range(1.0, 1.4)
