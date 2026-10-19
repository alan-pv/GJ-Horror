class_name BeginnerHelper
## Detecta errores graves antes de aceptar una jugada: permitir mate en 1 o
## perder mucho material comparado con la mejor alternativa. Nunca sugiere
## la mejor jugada; solo avisa que esa es mala.
##
## Búsqueda corta (jugada, respuesta, recaptura estimada) para que tarde
## unas décimas de segundo, sin motor externo. Se evalúa sobre el tablero
## físico, con trampas incluidas.

const PIECE_NAMES := {
	ChessPiece.PAWN: "the pawn",
	ChessPiece.KNIGHT: "the knight",
	ChessPiece.BISHOP: "the bishop",
	ChessPiece.ROOK: "the rook",
	ChessPiece.QUEEN: "the queen",
}
const MATE_SCORE := 100000


## Presupuesto de script por fotograma (microsegundos) en `precompute_async`.
const SLICE_USEC := 3000

## Mejor puntuación de la última posición precalculada (clave = `position_key`).
static var _cache_key := ""
static var _cache_best := 0


## Devuelve la frase que murmura el personaje, o "" si la jugada es aceptable.
## Mismo resultado que evaluar todas las jugadas a fondo, pero con poda: primero se
## puntúa la jugada elegida entera y las demás se abandonan en cuanto una respuesta
## demuestra que no pueden superar la mejor puntuación vista (solo importa el máximo).
## Trabaja sobre una copia del tablero con hacer/deshacer, sin reservar objetos.
## Si `precompute_async` ya analizó esta posición, solo puntúa la jugada elegida.
static func check_move(b: BoardState, move: ChessMove, threshold_cp: int) -> String:
	var work := b.clone()
	var moves := ChessRules.legal_moves_int(work)
	if moves.size() <= 1:
		return ""
	var us := work.side_to_move
	var weights := _weights(us)
	var base := _balance(work, us)
	var chosen_mv := -1
	if move != null:
		for mv in moves:
			if (mv & 63) == move.from and ((mv >> 6) & 63) == move.to and ((mv >> 12) & 7) == move.promotion:
				chosen_mv = mv
				break
	if chosen_mv < 0:
		return ""
	var chosen := _score_move(work, chosen_mv, base, weights, -MATE_SCORE * 4)
	var best: int = chosen.score
	if _cache_key != "" and _cache_key == work.position_key():
		best = maxi(best, _cache_best)
	else:
		for mv in _by_priority(work, moves):
			if mv != chosen_mv:
				best = maxi(best, _score_move(work, mv, base, weights, best).score)
	if chosen.allows_mate and best > -MATE_SCORE:
		return "...wait, that allows mate."
	if chosen.score <= best - threshold_cp:
		var lost: int = chosen.lost_piece
		if PIECE_NAMES.has(lost):
			return "...no, that leaves %s hanging." % PIECE_NAMES[lost]
		return "...hmm, no. That loses material."
	return ""


## Peor caso para quien mueve tras `mv`: el rival elige la respuesta que más nos
## perjudica y luego nosotros tomamos la mejor captura disponible. Si la puntuación
## baja a `cut` o menos se devuelve en cuanto se sabe (ya no puede ser la mejor);
## entonces `score` es una cota superior, no el valor exacto.
static func _score_move(work: BoardState, mv: int, base: int, weights: PackedInt32Array, cut: int) -> Dictionary:
	var us := work.side_to_move
	var undo := PackedInt32Array()
	undo.resize(12)
	var undo_r := PackedInt32Array()
	undo_r.resize(12)
	ChessRules.make_int(work, mv, undo)
	var bal := base + _delta(work, undo, weights)
	var replies := PackedInt32Array()
	ChessRules.gen_pseudo_int(work, replies)
	# Casillas con piezas rivales (posibles víctimas): solo cambian con la respuesta.
	var victims := PackedInt32Array()
	for sq in 64:
		var p := work.squares[sq]
		if p != 0 and ((p >> 3) & 1) != us and (p & 7) != ChessPiece.KING:
			victims.append(sq)
	var worst := MATE_SCORE * 2
	var worst_lost := 0
	var allows_mate := false
	var any_reply := false
	# Con poda (cut > -inf) primero las capturas: refutan antes y cortan antes. La jugada
	# elegida se recorre en el orden normal en una sola pasada (desempata `lost_piece`).
	var pruning := cut > -MATE_SCORE * 4
	var done := false
	for pass_index in (2 if pruning else 1):
		for r in replies:
			var target := work.squares[(r >> 6) & 63]
			if (target & 7) == ChessPiece.KING:
				continue
			if pruning and (target != 0) == (pass_index == 1):
				continue
			var lost := target & 7
			ChessRules.make_int(work, r, undo_r)
			if not ChessRules.mover_king_safe(work):
				ChessRules.unmake_int(work, undo_r)
				continue
			any_reply = true
			var score: int
			if ChessRules.in_check(work, us) and not ChessRules.has_legal_move(work):
				score = -MATE_SCORE
				allows_mate = true
			else:
				score = bal + _delta(work, undo_r, weights)
				# La captura propia solo suma (>= 0): si el balance ya no baja el mínimo, se omite.
				if score >= worst:
					ChessRules.unmake_int(work, undo_r)
					continue
				score += _best_capture_gain(work, us, victims, undo_r, worst - score)
			ChessRules.unmake_int(work, undo_r)
			if score < worst:
				worst = score
				worst_lost = lost
				if worst <= cut:
					done = true
					break
		if done:
			break
	var result: Dictionary
	if not any_reply:
		# Mate dado (excelente) o ahogado (las tablas ganan negras).
		var after_side := work.side_to_move
		var score: int
		if ChessRules.in_check(work, after_side):
			score = MATE_SCORE
		else:
			score = MATE_SCORE if us == ChessPiece.BLACK else -MATE_SCORE / 2
		result = {"score": score, "allows_mate": false, "lost_piece": 0}
	else:
		result = {"score": worst, "allows_mate": allows_mate, "lost_piece": worst_lost}
	ChessRules.unmake_int(work, undo)
	return result


## Valor material firmado por pieza desde el punto de vista de `color`.
static func _weights(color: int) -> PackedInt32Array:
	var w := PackedInt32Array()
	w.resize(16)
	for p in 16:
		if (p & 7) == 0 or (p & 7) > ChessPiece.KING:
			continue
		var v := ChessPiece.value_of(p)
		w[p] = v if ((p >> 3) & 1) == color else -v
	return w


## Cambio de balance material por las casillas que tocó la última jugada hecha.
static func _delta(b: BoardState, undo: PackedInt32Array, weights: PackedInt32Array) -> int:
	var d := 0
	for i in undo[3]:
		var sq := undo[4 + 2 * i]
		d += weights[b.squares[sq]] - weights[undo[5 + 2 * i]]
	return d


static func _balance(b: BoardState, color: int) -> int:
	return ChessRules.material(b, color) - ChessRules.material(b, ChessPiece.opposite(color))


## Ganancia estimada de nuestra mejor captura: valor capturado menos el valor
## de la pieza que captura si la casilla está defendida (el rey no captura en
## casillas defendidas). Se razona por víctima, con el atacante más barato.
## `victims` son las casillas rivales antes de la última respuesta (`undo` las
## casillas que esta tocó, donde puede haber víctimas nuevas). Con `limit` se corta en
## cuanto la ganancia llega a ese valor (ya no podría bajar el mínimo del llamador).
static func _best_capture_gain(b: BoardState, color: int, victims: PackedInt32Array, undo: PackedInt32Array, limit: int) -> int:
	var best := 0
	var sqs := b.squares
	for sq in victims:
		best = _victim_gain(b, sq, color, best)
		if best >= limit:
			return best
	for i in undo[3]:
		var sq := undo[4 + 2 * i]
		if not victims.has(sq):
			best = _victim_gain(b, sq, color, best)
	return best


static func _victim_gain(b: BoardState, sq: int, color: int, best: int) -> int:
	var victim := b.squares[sq]
	if victim == 0 or ((victim >> 3) & 1) == color or (victim & 7) == ChessPiece.KING:
		return best
	var value := ChessPiece.value_of(victim)
	if value <= best:
		return best
	if ChessRules.is_square_attacked(b, sq, 1 - color):
		var cheapest := ChessRules.least_attacker_value(b, sq, color)
		if cheapest >= 0:
			return maxi(best, value - cheapest)
	elif ChessRules.least_attacker_value(b, sq, color, true) >= 0:
		return value
	return best


## Capturas valiosas primero: suben pronto la cota `best` y la poda corta más.
static func _by_priority(work: BoardState, moves: PackedInt32Array) -> PackedInt32Array:
	var order := PackedInt32Array()
	for i in moves.size():
		var mv := moves[i]
		var victim := work.squares[(mv >> 6) & 63]
		var key := ChessPiece.value_of(victim) * 8 - (work.squares[mv & 63] & 7) if victim != 0 else 0
		order.append((20000 - key) * 256 + i)
	order.sort()
	var out := PackedInt32Array()
	for packed in order:
		out.append(moves[packed & 255])
	return out


## Coroutine: analiza `b` en trozos de ~3 ms por fotograma y guarda la mejor puntuación
## para que `check_move` de esa misma posición solo puntúe la jugada elegida. Conviene
## lanzarla al empezar el turno del jugador (piensa durante segundos) y sin `await`:
## `BeginnerHelper.precompute_async(board.clone())`. Si el tablero cambia antes de la
## jugada (trampa), la clave ya no coincide y `check_move` calcula todo como siempre.
## Con `sliced = false` calcula de una vez (pruebas, herramientas).
static func precompute_async(b: BoardState, sliced: bool = true) -> void:
	var key := b.position_key()
	if _cache_key == key:
		return
	var work := b.clone()
	var moves := ChessRules.legal_moves_int(work)
	if moves.size() <= 1:
		return
	var tree := Engine.get_main_loop() as SceneTree if sliced else null
	var weights := _weights(work.side_to_move)
	var base := _balance(work, work.side_to_move)
	var best := -MATE_SCORE * 4
	var t0 := Time.get_ticks_usec()
	for mv in _by_priority(work, moves):
		best = maxi(best, _score_move(work, mv, base, weights, best).score)
		if tree != null and Time.get_ticks_usec() - t0 > SLICE_USEC:
			await tree.process_frame
			t0 = Time.get_ticks_usec()
	_cache_key = key
	_cache_best = best
