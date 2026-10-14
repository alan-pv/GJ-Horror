class_name ChessRules
## Reglas del ajedrez evaluadas sobre el tablero FÍSICO actual.
## Si una trampa quitó una pieza, las jugadas se calculan como si nunca hubiera estado.

const KNIGHT_STEPS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_STEPS := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const ROOK_DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const BISHOP_DIRS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const PROMOTIONS := [ChessPiece.QUEEN, ChessPiece.ROOK, ChessPiece.BISHOP, ChessPiece.KNIGHT]


static func _on_board(f: int, r: int) -> bool:
	return f >= 0 and f < 8 and r >= 0 and r < 8


static func pawn_dir(color: int) -> int:
	return 1 if color == ChessPiece.WHITE else -1


## ¿Ataca `by_color` la casilla `sq`?
static func is_square_attacked(b: BoardState, sq: int, by_color: int) -> bool:
	var f := ChessPiece.file_of(sq)
	var r := ChessPiece.rank_of(sq)
	# Peones: miran hacia atrás desde la casilla atacada.
	var pr := r - pawn_dir(by_color)
	for df in [-1, 1]:
		if _on_board(f + df, pr) and b.squares[ChessPiece.square(f + df, pr)] == ChessPiece.make(by_color, ChessPiece.PAWN):
			return true
	for s in KNIGHT_STEPS:
		if _on_board(f + s[0], r + s[1]) and b.squares[ChessPiece.square(f + s[0], r + s[1])] == ChessPiece.make(by_color, ChessPiece.KNIGHT):
			return true
	for s in KING_STEPS:
		if _on_board(f + s[0], r + s[1]) and b.squares[ChessPiece.square(f + s[0], r + s[1])] == ChessPiece.make(by_color, ChessPiece.KING):
			return true
	if _slider_attacks(b, f, r, by_color, ROOK_DIRS, ChessPiece.ROOK):
		return true
	return _slider_attacks(b, f, r, by_color, BISHOP_DIRS, ChessPiece.BISHOP)


static func _slider_attacks(b: BoardState, f: int, r: int, by_color: int, dirs: Array, slider: int) -> bool:
	var queen := ChessPiece.make(by_color, ChessPiece.QUEEN)
	var own := ChessPiece.make(by_color, slider)
	for d in dirs:
		var cf: int = f + d[0]
		var cr: int = r + d[1]
		while _on_board(cf, cr):
			var p := b.squares[ChessPiece.square(cf, cr)]
			if p != ChessPiece.NONE:
				if p == own or p == queen:
					return true
				break
			cf += d[0]
			cr += d[1]
	return false


static func in_check(b: BoardState, color: int) -> bool:
	var k := b.king_square(color)
	return k >= 0 and is_square_attacked(b, k, ChessPiece.opposite(color))


## Jugadas pseudo-legales del bando al que le toca (pueden dejar al rey en jaque).
static func pseudo_moves(b: BoardState) -> Array[ChessMove]:
	var moves: Array[ChessMove] = []
	var us := b.side_to_move
	for sq in 64:
		var p := b.squares[sq]
		if p == ChessPiece.NONE or ChessPiece.color_of(p) != us:
			continue
		var f := ChessPiece.file_of(sq)
		var r := ChessPiece.rank_of(sq)
		match ChessPiece.type_of(p):
			ChessPiece.PAWN:
				_pawn_moves(b, sq, f, r, us, moves)
			ChessPiece.KNIGHT:
				_step_moves(b, sq, f, r, us, KNIGHT_STEPS, moves)
			ChessPiece.BISHOP:
				_slide_moves(b, sq, f, r, us, BISHOP_DIRS, moves)
			ChessPiece.ROOK:
				_slide_moves(b, sq, f, r, us, ROOK_DIRS, moves)
			ChessPiece.QUEEN:
				_slide_moves(b, sq, f, r, us, ROOK_DIRS, moves)
				_slide_moves(b, sq, f, r, us, BISHOP_DIRS, moves)
			ChessPiece.KING:
				_step_moves(b, sq, f, r, us, KING_STEPS, moves)
				_castle_moves(b, sq, us, moves)
	return moves


static func _add_pawn_move(from: int, to: int, moves: Array[ChessMove]) -> void:
	var tr := ChessPiece.rank_of(to)
	if tr == 0 or tr == 7:
		for promo in PROMOTIONS:
			moves.append(ChessMove.new(from, to, promo))
	else:
		moves.append(ChessMove.new(from, to))


static func _pawn_moves(b: BoardState, sq: int, f: int, r: int, us: int, moves: Array[ChessMove]) -> void:
	var dir := pawn_dir(us)
	var r1 := r + dir
	if not _on_board(f, r1):
		return
	var one := ChessPiece.square(f, r1)
	if b.squares[one] == ChessPiece.NONE:
		_add_pawn_move(sq, one, moves)
		var start_rank := 1 if us == ChessPiece.WHITE else 6
		if r == start_rank:
			var two := ChessPiece.square(f, r + 2 * dir)
			if b.squares[two] == ChessPiece.NONE:
				moves.append(ChessMove.new(sq, two))
	for df in [-1, 1]:
		if not _on_board(f + df, r1):
			continue
		var t := ChessPiece.square(f + df, r1)
		var target := b.squares[t]
		if target != ChessPiece.NONE and ChessPiece.color_of(target) != us:
			_add_pawn_move(sq, t, moves)
		elif t == b.ep_square and target == ChessPiece.NONE:
			# Al paso: el peón rival debe seguir físicamente ahí.
			var victim := ChessPiece.square(f + df, r)
			if b.squares[victim] == ChessPiece.make(ChessPiece.opposite(us), ChessPiece.PAWN):
				moves.append(ChessMove.new(sq, t))


static func _step_moves(b: BoardState, sq: int, f: int, r: int, us: int, steps: Array, moves: Array[ChessMove]) -> void:
	for s in steps:
		var cf: int = f + s[0]
		var cr: int = r + s[1]
		if not _on_board(cf, cr):
			continue
		var t := ChessPiece.square(cf, cr)
		var target := b.squares[t]
		if target == ChessPiece.NONE or ChessPiece.color_of(target) != us:
			moves.append(ChessMove.new(sq, t))


static func _slide_moves(b: BoardState, sq: int, f: int, r: int, us: int, dirs: Array, moves: Array[ChessMove]) -> void:
	for d in dirs:
		var cf: int = f + d[0]
		var cr: int = r + d[1]
		while _on_board(cf, cr):
			var t := ChessPiece.square(cf, cr)
			var target := b.squares[t]
			if target == ChessPiece.NONE:
				moves.append(ChessMove.new(sq, t))
			else:
				if ChessPiece.color_of(target) != us:
					moves.append(ChessMove.new(sq, t))
				break
			cf += d[0]
			cr += d[1]


static func _castle_moves(b: BoardState, sq: int, us: int, moves: Array[ChessMove]) -> void:
	var home := 4 if us == ChessPiece.WHITE else 60
	if sq != home:
		return
	var them := ChessPiece.opposite(us)
	var rook := ChessPiece.make(us, ChessPiece.ROOK)
	var k_right := BoardState.CASTLE_WK if us == ChessPiece.WHITE else BoardState.CASTLE_BK
	var q_right := BoardState.CASTLE_WQ if us == ChessPiece.WHITE else BoardState.CASTLE_BQ
	if b.castling & k_right and b.squares[home + 3] == rook \
			and b.squares[home + 1] == ChessPiece.NONE and b.squares[home + 2] == ChessPiece.NONE \
			and not is_square_attacked(b, home, them) and not is_square_attacked(b, home + 1, them) \
			and not is_square_attacked(b, home + 2, them):
		moves.append(ChessMove.new(home, home + 2))
	if b.castling & q_right and b.squares[home - 4] == rook \
			and b.squares[home - 1] == ChessPiece.NONE and b.squares[home - 2] == ChessPiece.NONE \
			and b.squares[home - 3] == ChessPiece.NONE \
			and not is_square_attacked(b, home, them) and not is_square_attacked(b, home - 1, them) \
			and not is_square_attacked(b, home - 2, them):
		moves.append(ChessMove.new(home, home - 2))


static func legal_moves(b: BoardState) -> Array[ChessMove]:
	var legal: Array[ChessMove] = []
	var us := b.side_to_move
	for m in pseudo_moves(b):
		# Nunca se captura un rey: si el rival está en jaque en nuestro turno
		# (posición imposible), esa captura no es una jugada.
		if ChessPiece.type_of(b.squares[m.to]) == ChessPiece.KING:
			continue
		var c := b.clone()
		apply_move(c, m)
		if not in_check(c, us):
			legal.append(m)
	return legal


## Busca entre las jugadas legales la que coincide con `m`. Devuelve null si es ilegal.
static func find_legal(b: BoardState, m: ChessMove) -> ChessMove:
	if m == null:
		return null
	for lm in legal_moves(b):
		if lm.from == m.from and lm.to == m.to:
			if lm.promotion == m.promotion:
				return lm
			# Coronación sin pieza indicada: dama por defecto.
			if m.promotion == 0 and lm.promotion == ChessPiece.QUEEN:
				return lm
	return null


static func is_capture(b: BoardState, m: ChessMove) -> bool:
	if b.squares[m.to] != ChessPiece.NONE:
		return true
	return ChessPiece.type_of(b.squares[m.from]) == ChessPiece.PAWN and m.to == b.ep_square \
			and ChessPiece.file_of(m.from) != ChessPiece.file_of(m.to)


static func is_castle(b: BoardState, m: ChessMove) -> bool:
	return ChessPiece.type_of(b.squares[m.from]) == ChessPiece.KING and absi(m.to - m.from) == 2


## Aplica la jugada sin validar. Devuelve un diccionario con lo ocurrido
## (útil para las animaciones de la mano): pieza capturada, casilla de la
## captura y, si hubo enroque, el movimiento de la torre.
static func apply_move(b: BoardState, m: ChessMove) -> Dictionary:
	var us := b.side_to_move
	var them := ChessPiece.opposite(us)
	var piece := b.squares[m.from]
	var type := ChessPiece.type_of(piece)
	var info := {"captured": ChessPiece.NONE, "capture_square": -1, "rook_from": -1, "rook_to": -1}

	var cap_sq := m.to
	if type == ChessPiece.PAWN and m.to == b.ep_square and b.squares[m.to] == ChessPiece.NONE \
			and ChessPiece.file_of(m.from) != ChessPiece.file_of(m.to):
		cap_sq = m.to - 8 * pawn_dir(us)
	var captured := b.squares[cap_sq]
	if captured != ChessPiece.NONE:
		info.captured = captured
		info.capture_square = cap_sq
		b.captured[us].append(captured)
		b.squares[cap_sq] = ChessPiece.NONE
		b.offsets[cap_sq] = Vector2.ZERO

	b.squares[m.to] = ChessPiece.make(us, m.promotion) if m.promotion != 0 else piece
	b.squares[m.from] = ChessPiece.NONE
	# Una jugada normal deja la pieza centrada en su nueva casilla.
	b.offsets[m.to] = Vector2.ZERO
	b.offsets[m.from] = Vector2.ZERO

	if type == ChessPiece.KING and absi(m.to - m.from) == 2:
		var rook_from := m.from + 3 if m.to > m.from else m.from - 4
		var rook_to := m.from + 1 if m.to > m.from else m.from - 1
		b.squares[rook_to] = b.squares[rook_from]
		b.squares[rook_from] = ChessPiece.NONE
		b.offsets[rook_to] = Vector2.ZERO
		b.offsets[rook_from] = Vector2.ZERO
		info.rook_from = rook_from
		info.rook_to = rook_to

	update_castling_rights(b, m.from)
	update_castling_rights(b, m.to)

	b.ep_square = -1
	if type == ChessPiece.PAWN and absi(m.to - m.from) == 16:
		var ep := (m.from + m.to) / 2
		# Solo se anota si un peón rival podría capturar (importa para la repetición).
		var f := ChessPiece.file_of(m.to)
		for df in [-1, 1]:
			if f + df >= 0 and f + df < 8 and b.squares[m.to + df] == ChessPiece.make(them, ChessPiece.PAWN):
				b.ep_square = ep

	if type == ChessPiece.PAWN or captured != ChessPiece.NONE:
		b.halfmove_clock = 0
	else:
		b.halfmove_clock += 1
	if us == ChessPiece.BLACK:
		b.fullmove_number += 1
	b.side_to_move = them
	return info


## Cualquier cosa que sale o llega a una casilla de rey o torre inicial quita el enroque.
static func update_castling_rights(b: BoardState, sq: int) -> void:
	match sq:
		4: b.castling &= ~(BoardState.CASTLE_WK | BoardState.CASTLE_WQ)
		7: b.castling &= ~BoardState.CASTLE_WK
		0: b.castling &= ~BoardState.CASTLE_WQ
		60: b.castling &= ~(BoardState.CASTLE_BK | BoardState.CASTLE_BQ)
		63: b.castling &= ~BoardState.CASTLE_BK
		56: b.castling &= ~BoardState.CASTLE_BQ


static func insufficient_material(b: BoardState) -> bool:
	var minors: Array[int] = []
	var bishop_colors: Array[int] = []
	for sq in 64:
		var p := b.squares[sq]
		match ChessPiece.type_of(p):
			ChessPiece.NONE, ChessPiece.KING:
				pass
			ChessPiece.KNIGHT:
				minors.append(p)
			ChessPiece.BISHOP:
				minors.append(p)
				bishop_colors.append((ChessPiece.file_of(sq) + ChessPiece.rank_of(sq)) % 2)
			_:
				return false
	if minors.size() <= 1:
		return true
	# Solo alfiles, todos en casillas del mismo color.
	if bishop_colors.size() == minors.size():
		return not bishop_colors.has(0) or not bishop_colors.has(1)
	return false


static func material(b: BoardState, color: int) -> int:
	var total := 0
	for sq in 64:
		var p := b.squares[sq]
		if p != ChessPiece.NONE and ChessPiece.color_of(p) == color:
			total += ChessPiece.value_of(p)
	return total


static func perft(b: BoardState, depth: int) -> int:
	if depth == 0:
		return 1
	var moves := legal_moves(b)
	if depth == 1:
		return moves.size()
	var n := 0
	for m in moves:
		var c := b.clone()
		apply_move(c, m)
		n += perft(c, depth - 1)
	return n
