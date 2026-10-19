class_name CheatRules
## Validación y aplicación de trampas sobre el tablero físico.
## Límites: nunca se toca un rey, nunca queda en jaque el rey del tramposo
## y nunca queda en jaque el bando al que no le toca (posición imposible).


const REASON_KING := "kings cannot be touched"
const REASON_OWN_ONLY := "own pieces only"
const REASON_ENEMY_ONLY := "enemy pieces only"


## Devuelve {ok, reason, distance, duration}.
static func validate(b: BoardState, color: int, def: CheatDef, from: int, to: int) -> Dictionary:
	var res := {"ok": false, "reason": "", "distance": 0, "duration": 0.0}
	if from < 0 or from > 63:
		res.reason = "invalid square"
		return res
	var piece := b.squares[from]
	if piece == ChessPiece.NONE:
		res.reason = "no piece there"
		return res
	if ChessPiece.type_of(piece) == ChessPiece.KING:
		res.reason = REASON_KING
		return res
	var own := ChessPiece.color_of(piece) == color
	var distance := 0

	match def.kind:
		CheatDef.Kind.NUDGE:
			if not own:
				res.reason = REASON_OWN_ONLY
				return res
			if to != from + 8 * ChessRules.pawn_dir(color):
				res.reason = "it only moves one square"
				return res
			distance = 1
		CheatDef.Kind.SLIDE:
			if not own:
				res.reason = REASON_OWN_ONLY
				return res
			distance = _line_distance(b, from, to)
			if distance <= 0:
				res.reason = "must be in a line with no pieces in between"
				return res
		CheatDef.Kind.STEAL:
			if own:
				res.reason = REASON_ENEMY_ONLY
				return res
			to = -1
		CheatDef.Kind.MOVE_ENEMY:
			if own:
				res.reason = REASON_ENEMY_ONLY
				return res
			distance = _king_distance(from, to)
			if distance <= 0:
				res.reason = "invalid destination"
				return res

	if to >= 0:
		if to > 63 or b.squares[to] != ChessPiece.NONE:
			res.reason = "the destination must be empty"
			return res
		if ChessPiece.type_of(piece) == ChessPiece.PAWN and (ChessPiece.rank_of(to) == 0 or ChessPiece.rank_of(to) == 7):
			res.reason = "a pawn cannot end up on the first or last rank"
			return res
	if def.max_distance > 0 and distance > def.max_distance:
		res.reason = "too far"
		return res

	var after := b.clone()
	_apply_squares(after, color, from, to)
	if ChessRules.in_check(after, color):
		res.reason = "it would leave your king in check"
		return res
	if ChessRules.in_check(after, ChessPiece.opposite(after.side_to_move)):
		res.reason = "it would put the side not to move in check"
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
