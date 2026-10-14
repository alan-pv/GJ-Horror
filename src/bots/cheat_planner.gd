class_name CheatPlanner
extends RefCounted
## Lógica pura (sin nodos) para decidir si un bot hace trampa y cuál.
## Enumera las trampas válidas con `CheatRules`, las puntúa por la ganancia
## de evaluación menos el riesgo (duración y evidencia) y elige una al azar
## ponderada: la mejor es la más probable, pero no siempre sale.

## Ganancia mínima (centipeones) para que valga la pena arriesgarse.
const MIN_GAIN := 15.0
## Cuánto pesa cada segundo de mano ocupada y cada punto de evidencia (en peones).
const DURATION_PENALTY := 0.35
const EVIDENCE_PENALTY := 1.2
## Temperatura del muestreo (mayor = más aleatorio).
const PICK_TEMPERATURE := 1.2
## Máximo de candidatas válidas por tipo de trampa (acota el costo).
const MAX_PER_DEF := 24
## Escala de `cheat_chance` (por oportunidad) a probabilidad por evaluación (~0.5 s).
const TICK_SCALE := 0.2

const _DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## Candidatas válidas: [{def, from, to, duration, gain, score}].
static func candidates(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator) -> Array[Dictionary]:
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
			out.append({
				"def": def, "from": pair.x, "to": pair.y, "duration": v.duration,
				"gain": gain, "score": score(gain, v.duration, def.evidence),
			})
			found += 1
			if found >= MAX_PER_DEF:
				break
	return out


## Puntaje en peones: ganancia menos riesgo.
static func score(gain: float, duration: float, evidence: float) -> float:
	return gain / 100.0 - DURATION_PENALTY * duration - EVIDENCE_PENALTY * evidence


## Elige una candidata con ganancia suficiente, ponderada por puntaje. {} si no hay.
static func pick(cands: Array, rng: RandomNumberGenerator, temperature: float = PICK_TEMPERATURE) -> Dictionary:
	var useful: Array = []
	var best := -INF
	for c: Dictionary in cands:
		if c.gain >= MIN_GAIN:
			useful.append(c)
			best = maxf(best, c.score)
	if useful.is_empty():
		return {}
	var weights: Array[float] = []
	var total := 0.0
	for c: Dictionary in useful:
		var w := exp((c.score - best) / maxf(temperature, 0.05))
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in useful.size():
		r -= weights[i]
		if r <= 0.0:
			return useful[i]
	return useful[useful.size() - 1]


## Atajo: enumera y elige.
static func plan(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator) -> Dictionary:
	return pick(candidates(board, color, defs, rng), rng)


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
