class_name CheatRules
## Validación y aplicación de trampas sobre el tablero físico.
## Límites: nunca se toca un rey, nunca queda en jaque el rey del tramposo
## y nunca queda en jaque el bando al que no le toca (posición imposible).


## Devuelve {ok, reason, distance, duration}.
static func validate(b: BoardState, color: int, def: CheatDef, from: int, to: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "distance": 0, "duration": 0.0}
	if from < 0 or from > 63:
		res.reason = "casilla inválida"
		return res
	var piece := b.squares[from]
	if piece == ChessPiece.NONE:
		res.reason = "no hay pieza"
		return res
	if ChessPiece.type_of(piece) == ChessPiece.KING:
		res.reason = "los reyes no se tocan"
		return res
	var own := ChessPiece.color_of(piece) == color
	var distance := 0

	match def.kind:
		CheatDef.Kind.NUDGE:
			if not own:
				res.reason = "solo piezas propias"
				return res
			if to != from + 8 * ChessRules.pawn_dir(color):
				res.reason = "solo avanza una casilla"
				return res
			distance = 1
		CheatDef.Kind.SLIDE:
			if not own:
				res.reason = "solo piezas propias"
				return res
			distance = _line_distance(b, from, to)
			if distance <= 0:
				res.reason = "debe ser en línea y sin piezas en medio"
				return res
		CheatDef.Kind.STEAL:
			if own:
				res.reason = "solo piezas enemigas"
				return res
			to = -1
		CheatDef.Kind.MOVE_ENEMY:
			if own:
				res.reason = "solo piezas enemigas"
				return res
			distance = _king_distance(from, to)
			if distance <= 0:
				res.reason = "destino inválido"
				return res

	if to >= 0:
		if to > 63 or b.squares[to] != ChessPiece.NONE:
			res.reason = "el destino debe estar vacío"
			return res
		if ChessPiece.type_of(piece) == ChessPiece.PAWN and (ChessPiece.rank_of(to) == 0 or ChessPiece.rank_of(to) == 7):
			res.reason = "un peón no puede quedar en la primera ni en la última fila"
			return res
	if def.max_distance > 0 and distance > def.max_distance:
		res.reason = "demasiado lejos"
		return res

	var after := b.clone()
	_apply_squares(after, color, from, to)
	if ChessRules.in_check(after, color):
		res.reason = "dejaría a tu rey en jaque"
		return res
	if ChessRules.in_check(after, ChessPiece.opposite(after.side_to_move)):
		res.reason = "dejaría en jaque al bando que no mueve"
		return res

	res.ok = true
	res.distance = distance
	res.duration = def.base_time + def.time_per_square * distance
	return res


## Aplica la trampa (ya validada). `rng` decide hacia dónde queda descentrada la pieza.
static func apply(b: BoardState, color: int, def: CheatDef, from: int, to: int, rng: RandomNumberGenerator) -> void:
	if def.kind == CheatDef.Kind.STEAL:
		to = -1
	_apply_squares(b, color, from, to)
	if to >= 0 and def.offset_amount > 0.0:
		var ang := rng.randf() * TAU
		b.offsets[to] = Vector2(cos(ang), sin(ang)) * def.offset_amount
	ChessRules.update_castling_rights(b, from)
	if to >= 0:
		ChessRules.update_castling_rights(b, to)
	# La regla de 50 jugadas se reinicia con cualquier trampa.
	b.halfmove_clock = 0


static func _apply_squares(b: BoardState, color: int, from: int, to: int) -> void:
	var piece := b.squares[from]
	b.squares[from] = ChessPiece.NONE
	b.offsets[from] = Vector2.ZERO
	if to < 0:
		b.hand[color].append(piece)
	else:
		b.squares[to] = piece
		b.offsets[to] = Vector2.ZERO


static func _king_distance(a: int, c: int) -> int:
	if c < 0 or c > 63 or a == c:
		return 0
	return maxi(absi(ChessPiece.file_of(a) - ChessPiece.file_of(c)), absi(ChessPiece.rank_of(a) - ChessPiece.rank_of(c)))


## Distancia si `from`→`to` es una línea recta (torre o alfil) libre; 0 si no.
static func _line_distance(b: BoardState, from: int, to: int) -> int:
	if to < 0 or to > 63 or from == to:
		return 0
	var df := ChessPiece.file_of(to) - ChessPiece.file_of(from)
	var dr := ChessPiece.rank_of(to) - ChessPiece.rank_of(from)
	if df != 0 and dr != 0 and absi(df) != absi(dr):
		return 0
	var steps := maxi(absi(df), absi(dr))
	var sf := signi(df)
	var sr := signi(dr)
	for i in range(1, steps):
		if b.squares[ChessPiece.square(ChessPiece.file_of(from) + sf * i, ChessPiece.rank_of(from) + sr * i)] != ChessPiece.NONE:
			return 0
	return steps
