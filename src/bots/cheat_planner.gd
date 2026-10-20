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
## Máximo de candidatas válidas por clase de trampa (acota el costo).
const MAX_PER_DEF := 24
## Máximo de destinos que se toman de una misma pieza (uno por nivel de sospecha),
## para que las candidatas no salgan todas de la misma pieza.
const PER_PIECE := 3
## Escala de `cheat_chance` (por oportunidad) a probabilidad por evaluación (~0.5 s).
const TICK_SCALE := 0.2
## Mover una pieza propia en el turno propio REEMPLAZA la jugada: solo vale la pena
## si gana más (centipeones) que la mejor jugada legal, y además pesa un castigo. La
## evaluación estática solo ve material y casillas, así que un margen de 30 cp ya es
## raro: ocurre sobre todo cuando las jugadas legales son pobres (pieza encerrada).
const AS_MOVE_MARGIN := 30.0
const AS_MOVE_PENALTY := 0.8


## Candidatas válidas: [{def, from, to, level, evidence, distance, duration, gain,
## raw_gain, as_move, score}]. Por clase se muestrean destinos de piezas barajadas,
## uno por nivel de sospecha. `turn_ready`: ver `CheatRules.context` (-1 = deducirlo).
static func candidates(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator, risk_appetite: float = 0.5, turn_ready: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base_eval := FallbackBrain.evaluate(board, color)
	var best_legal := NAN  # se calcula solo si hace falta (trampa propia en mi turno)
	for def: CheatDef in defs:
		var pieces := _pieces_for(board, color, def)
		_shuffle(pieces, rng)
		# Reyes al final: se prefieren otras piezas.
		pieces.sort_custom(func(a: int, c: int) -> bool:
			return ChessPiece.type_of(board.squares[a]) != ChessPiece.KING and ChessPiece.type_of(board.squares[c]) == ChessPiece.KING)
		var found := 0
		for from: int in pieces:
			var ctx := CheatRules.context(board, color, from, turn_ready)
			if ctx.is_empty():
				continue
			for to: int in _sample_destinations(ctx, def, rng):
				var level: int = CheatRules.PILE_LEVEL if to == CheatRules.TO_PILE else CheatRules.dest_level(ctx, to)
				var distance := 0 if to == CheatRules.TO_PILE else CheatRules.king_distance(from, to)
				var after := board.clone()
				CheatRules.apply(after, color, def, from, to, rng)
				var raw_gain := FallbackBrain.evaluate(after, color) - base_eval
				var as_move: bool = def.kind == CheatDef.Kind.OWN_MOVE and ctx.in_turn
				var gain := raw_gain
				if as_move:
					if is_nan(best_legal):
						best_legal = _best_legal_gain(board, color, base_eval)
					gain = raw_gain - best_legal
					if gain < AS_MOVE_MARGIN:
						continue
				# Llevarse una pieza grande a la vista de todos se nota mucho más.
				var noticeable := 0.0
				if def.kind == CheatDef.Kind.STEAL:
					noticeable = ChessPiece.value_of(board.squares[from]) / 100.0
				var evidence := def.evidence_for(level)
				var duration := def.duration_for(distance)
				var sc := score(gain, duration, evidence, risk_appetite, noticeable)
				if as_move:
					sc -= AS_MOVE_PENALTY
				out.append({
					"def": def, "from": from, "to": to, "level": level, "evidence": evidence,
					"distance": distance, "duration": duration, "gain": gain, "raw_gain": raw_gain,
					"as_move": as_move, "score": sc,
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
static func plan(board: BoardState, color: int, defs: Array, rng: RandomNumberGenerator, risk_appetite: float = 0.5, turn_ready: int = -1) -> Dictionary:
	return pick(candidates(board, color, defs, rng, risk_appetite, turn_ready), rng)


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

## Casillas con piezas que esta clase puede tocar. Los reyes van al final de la lista
## (ver `candidates`): mover un rey casi nunca aporta, así que solo se prueban si sobran cupos.
static func _pieces_for(b: BoardState, color: int, def: CheatDef) -> Array:
	var res: Array = []
	for sq in 64:
		var p := b.squares[sq]
		if p == ChessPiece.NONE:
			continue
		if (ChessPiece.color_of(p) == color) == (def.kind == CheatDef.Kind.OWN_MOVE):
			res.append(sq)
	return res


## Hasta `PER_PIECE` destinos válidos de la pieza del contexto, de niveles distintos.
static func _sample_destinations(ctx: Dictionary, def: CheatDef, rng: RandomNumberGenerator) -> Array:
	if def.kind == CheatDef.Kind.STEAL:
		return [CheatRules.TO_PILE] if CheatRules.dest_level(ctx, CheatRules.TO_PILE) >= 0 else []
	var by_level := {}
	for to in 64:
		var lv := CheatRules.dest_level(ctx, to)
		if lv < 1:  # inválido (-1) o jugada legal (0): no es trampa
			continue
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(to)
	var picks: Array = []
	for lv in by_level:
		var list: Array = by_level[lv]
		picks.append(list[rng.randi() % list.size()])
	_shuffle(picks, rng)
	return picks.slice(0, PER_PIECE)


## Mejor ganancia de evaluación entre las jugadas legales de `color` (le toca). 0 sin jugadas.
static func _best_legal_gain(board: BoardState, color: int, base_eval: float) -> float:
	var best := -INF
	for m in ChessRules.legal_moves(board):
		var after := board.clone()
		ChessRules.apply_move(after, m)
		best = maxf(best, FallbackBrain.evaluate(after, color) - base_eval)
	return 0.0 if best == -INF else best


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
