class_name ChessRules
## Reglas del ajedrez evaluadas sobre el tablero FÍSICO actual.
## Si una trampa quitó una pieza, las jugadas se calculan como si nunca hubiera estado.

const KNIGHT_STEPS := [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]
const KING_STEPS := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const ROOK_DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const BISHOP_DIRS := [[1, 1], [1, -1], [-1, 1], [-1, -1]]
const PROMOTIONS := [ChessPiece.QUEEN, ChessPiece.ROOK, ChessPiece.BISHOP, ChessPiece.KNIGHT]


## Las jugadas "enteras" (`int`) de los métodos *_int codifican origen | destino << 6 |
## promoción << 12. Son la vía rápida para los bucles calientes (bots, ayuda): no
## reservan objetos y se prueban con hacer/deshacer sobre el propio tablero.

# Tablas precalculadas (se llenan una vez, la primera vez que hacen falta).
static var _ready_tables := false
## Por casilla: casillas a las que salta un caballo / se mueve un rey.
static var _knight_to: Array = []
static var _king_to: Array = []
## Índice casilla * 8 + dirección (0..3 torre, 4..7 alfil): casillas del rayo, de cerca a lejos.
static var _rays: Array = []
## Índice color * 64 + casilla: casillas desde las que un peón de ese color ataca la casilla.
static var _pawn_from: Array = []


static func _init_tables() -> void:
	_ready_tables = true
	_knight_to.resize(64)
	_king_to.resize(64)
	_rays.resize(64 * 8)
	_pawn_from.resize(128)
	var dirs: Array = ROOK_DIRS + BISHOP_DIRS
	for sq in 64:
		var f := sq % 8
		var r := sq / 8
		var kn := PackedInt32Array()
		for s in KNIGHT_STEPS:
			if _on_board(f + s[0], r + s[1]):
				kn.append((r + s[1]) * 8 + f + s[0])
		_knight_to[sq] = kn
		var kg := PackedInt32Array()
		for s in KING_STEPS:
			if _on_board(f + s[0], r + s[1]):
				kg.append((r + s[1]) * 8 + f + s[0])
		_king_to[sq] = kg
		for d in 8:
			var ray := PackedInt32Array()
			var cf: int = f + dirs[d][0]
			var cr: int = r + dirs[d][1]
			while _on_board(cf, cr):
				ray.append(cr * 8 + cf)
				cf += dirs[d][0]
				cr += dirs[d][1]
			_rays[sq * 8 + d] = ray
		for color in 2:
			var pf := PackedInt32Array()
			var pr := r - pawn_dir(color)
			for df: int in [-1, 1]:
				if _on_board(f + df, pr):
					pf.append(pr * 8 + f + df)
			_pawn_from[color * 64 + sq] = pf


static func _on_board(f: int, r: int) -> bool:
	return f >= 0 and f < 8 and r >= 0 and r < 8


static func pawn_dir(color: int) -> int:
	return 1 if color == ChessPiece.WHITE else -1


## ¿Ataca `by_color` la casilla `sq`?
static func is_square_attacked(b: BoardState, sq: int, by_color: int) -> bool:
	if not _ready_tables:
		_init_tables()
	var sqs := b.squares
	var base := by_color << 3
	var pawn := base | ChessPiece.PAWN
	for s: int in _pawn_from[by_color * 64 + sq]:
		if sqs[s] == pawn:
			return true
	var knight := base | ChessPiece.KNIGHT
	for s: int in _knight_to[sq]:
		if sqs[s] == knight:
			return true
	var king := base | ChessPiece.KING
	for s: int in _king_to[sq]:
		if sqs[s] == king:
			return true
	var queen := base | ChessPiece.QUEEN
	var rook := base | ChessPiece.ROOK
	var bishop := base | ChessPiece.BISHOP
	var i := sq * 8
	for d in 4:
		for s: int in _rays[i + d]:
			var p := sqs[s]
			if p != 0:
				if p == rook or p == queen:
					return true
				break
	for d in range(4, 8):
		for s: int in _rays[i + d]:
			var p := sqs[s]
			if p != 0:
				if p == bishop or p == queen:
					return true
				break
	return false


## Valor (centipeones) de la pieza menos valiosa de `by_color` que ataca `sq`, o -1 si
## ninguna. El rey solo cuenta con `include_king` (y entonces se anota como 0).
static func least_attacker_value(b: BoardState, sq: int, by_color: int, include_king: bool = false) -> int:
	if not _ready_tables:
		_init_tables()
	var sqs := b.squares
	var base := by_color << 3
	var pawn := base | ChessPiece.PAWN
	for s: int in _pawn_from[by_color * 64 + sq]:
		if sqs[s] == pawn:
			return 100
	var knight := base | ChessPiece.KNIGHT
	for s: int in _knight_to[sq]:
		if sqs[s] == knight:
			return 320
	var queen := base | ChessPiece.QUEEN
	var rook := base | ChessPiece.ROOK
	var bishop := base | ChessPiece.BISHOP
	var i := sq * 8
	var queen_seen := false
	for d in range(4, 8):
		for s: int in _rays[i + d]:
			var p := sqs[s]
			if p != 0:
				if p == bishop:
					return 330
				if p == queen:
					queen_seen = true
				break
	for d in 4:
		for s: int in _rays[i + d]:
			var p := sqs[s]
			if p != 0:
				if p == rook:
					return 500
				if p == queen:
					queen_seen = true
				break
	if queen_seen:
		return 900
	if include_king:
		var king := base | ChessPiece.KING
		for s: int in _king_to[sq]:
			if sqs[s] == king:
				return 0
	return -1


static func in_check(b: BoardState, color: int) -> bool:
	var k := b.king_square(color)
	return k >= 0 and is_square_attacked(b, k, ChessPiece.opposite(color))


## Jugadas pseudo-legales del bando al que le toca (pueden dejar al rey en jaque).
static func pseudo_moves(b: BoardState) -> Array[ChessMove]:
	var raw := PackedInt32Array()
	gen_pseudo_int(b, raw)
	var moves: Array[ChessMove] = []
	for mv: int in raw:
		moves.append(ChessMove.new(mv & 63, (mv >> 6) & 63, (mv >> 12) & 7))
	return moves


## Versión entera de `pseudo_moves`, añadidas a `out`. Con `captures_only` solo salen
## las capturas directas (sin al paso, enroques ni coronaciones menores).
static func gen_pseudo_int(b: BoardState, out: PackedInt32Array, captures_only: bool = false) -> void:
	if not _ready_tables:
		_init_tables()
	var sqs := b.squares
	var us := b.side_to_move
	for sq in 64:
		var p := sqs[sq]
		if p == 0 or ((p >> 3) & 1) != us:
			continue
		match p & 7:
			ChessPiece.PAWN:
				_gen_pawn(b, sq, us, out, captures_only)
			ChessPiece.KNIGHT:
				_gen_steps(sqs, sq, us, _knight_to[sq], out, captures_only)
			ChessPiece.BISHOP:
				_gen_slides(sqs, sq, us, 4, 8, out, captures_only)
			ChessPiece.ROOK:
				_gen_slides(sqs, sq, us, 0, 4, out, captures_only)
			ChessPiece.QUEEN:
				_gen_slides(sqs, sq, us, 0, 4, out, captures_only)
				_gen_slides(sqs, sq, us, 4, 8, out, captures_only)
			ChessPiece.KING:
				_gen_steps(sqs, sq, us, _king_to[sq], out, captures_only)
				if not captures_only:
					_castle_moves(b, sq, us, out)


static func _gen_steps(sqs: PackedInt32Array, sq: int, us: int, targets: PackedInt32Array, out: PackedInt32Array, captures_only: bool) -> void:
	for t: int in targets:
		var target := sqs[t]
		if target == 0:
			if not captures_only:
				out.append(sq | (t << 6))
		elif ((target >> 3) & 1) != us:
			out.append(sq | (t << 6))


static func _gen_slides(sqs: PackedInt32Array, sq: int, us: int, d_from: int, d_to: int, out: PackedInt32Array, captures_only: bool) -> void:
	var i := sq * 8
	for d in range(d_from, d_to):
		for t: int in _rays[i + d]:
			var target := sqs[t]
			if target == 0:
				if not captures_only:
					out.append(sq | (t << 6))
			else:
				if ((target >> 3) & 1) != us:
					out.append(sq | (t << 6))
				break


static func _add_pawn_move(from: int, to: int, out: PackedInt32Array, captures_only: bool) -> void:
	var tr := to >> 3
	if tr == 0 or tr == 7:
		if captures_only:
			out.append(from | (to << 6) | (ChessPiece.QUEEN << 12))
		else:
			for promo in PROMOTIONS:
				out.append(from | (to << 6) | (promo << 12))
	else:
		out.append(from | (to << 6))


static func _gen_pawn(b: BoardState, sq: int, us: int, out: PackedInt32Array, captures_only: bool) -> void:
	var sqs := b.squares
	var f := sq & 7
	var r := sq >> 3
	var dir := 1 if us == ChessPiece.WHITE else -1
	var r1 := r + dir
	if r1 < 0 or r1 > 7:
		return
	var one := r1 * 8 + f
	if not captures_only and sqs[one] == 0:
		_add_pawn_move(sq, one, out, false)
		var start_rank := 1 if us == ChessPiece.WHITE else 6
		if r == start_rank:
			var two := one + 8 * dir
			if sqs[two] == 0:
				out.append(sq | (two << 6))
	var enemy_pawn := ((1 - us) << 3) | ChessPiece.PAWN
	for df: int in [-1, 1]:
		if f + df < 0 or f + df > 7:
			continue
		var t := r1 * 8 + f + df
		var target := sqs[t]
		if target != 0 and ((target >> 3) & 1) != us:
			_add_pawn_move(sq, t, out, captures_only)
		elif not captures_only and t == b.ep_square and target == 0:
			# Al paso: el peón rival debe seguir físicamente ahí.
			if sqs[r * 8 + f + df] == enemy_pawn:
				out.append(sq | (t << 6))


static func _castle_moves(b: BoardState, sq: int, us: int, out: PackedInt32Array) -> void:
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
		out.append(home | ((home + 2) << 6))
	if b.castling & q_right and b.squares[home - 4] == rook \
			and b.squares[home - 1] == ChessPiece.NONE and b.squares[home - 2] == ChessPiece.NONE \
			and b.squares[home - 3] == ChessPiece.NONE \
			and not is_square_attacked(b, home, them) and not is_square_attacked(b, home - 1, them) \
			and not is_square_attacked(b, home - 2, them):
		out.append(home | ((home - 2) << 6))


## Hace la jugada entera `mv` DIRECTAMENTE sobre `b` (solo casillas, enroques, al paso y
## turno; no toca capturadas, relojes ni desplazamientos) y anota en `undo` (tamaño 12)
## lo necesario para `unmake_int`. Es la base de los bucles de búsqueda.
static func make_int(b: BoardState, mv: int, undo: PackedInt32Array) -> void:
	var from := mv & 63
	var to := (mv >> 6) & 63
	var promo := (mv >> 12) & 7
	var sqs := b.squares
	var us := b.side_to_move
	var piece := sqs[from]
	var type := piece & 7
	undo[0] = b.castling
	undo[1] = b.ep_square
	undo[2] = us
	undo[4] = from
	undo[5] = piece
	undo[6] = to
	undo[7] = sqs[to]
	var n := 2
	if type == ChessPiece.PAWN and to == b.ep_square and sqs[to] == 0 and (from & 7) != (to & 7):
		var cap_sq := to - 8 * (1 if us == ChessPiece.WHITE else -1)
		undo[8] = cap_sq
		undo[9] = sqs[cap_sq]
		n = 3
		sqs[cap_sq] = 0
	sqs[to] = (promo | (us << 3)) if promo != 0 else piece
	sqs[from] = 0
	if type == ChessPiece.KING and absi(to - from) == 2:
		var rook_from := from + 3 if to > from else from - 4
		var rook_to := from + 1 if to > from else from - 1
		undo[8] = rook_from
		undo[9] = sqs[rook_from]
		undo[10] = rook_to
		undo[11] = sqs[rook_to]
		n = 4
		sqs[rook_to] = sqs[rook_from]
		sqs[rook_from] = 0
	undo[3] = n
	update_castling_rights(b, from)
	update_castling_rights(b, to)
	b.ep_square = -1
	if type == ChessPiece.PAWN and absi(to - from) == 16:
		var f := to & 7
		var enemy_pawn := ((1 - us) << 3) | ChessPiece.PAWN
		for df: int in [-1, 1]:
			if f + df >= 0 and f + df < 8 and sqs[to + df] == enemy_pawn:
				b.ep_square = (from + to) / 2
	b.side_to_move = 1 - us


static func unmake_int(b: BoardState, undo: PackedInt32Array) -> void:
	var sqs := b.squares
	for i in undo[3]:
		sqs[undo[4 + 2 * i]] = undo[5 + 2 * i]
	b.castling = undo[0]
	b.ep_square = undo[1]
	b.side_to_move = undo[2]


## Tras `make_int`: ¿quedó a salvo el rey de quien acaba de mover?
static func mover_king_safe(b: BoardState) -> bool:
	var us := 1 - b.side_to_move
	var k := b.squares.find((us << 3) | ChessPiece.KING)
	return k < 0 or not is_square_attacked(b, k, b.side_to_move)


## Jugadas legales (enteras) del bando al que le toca. Prueba hacer/deshacer sobre `b`,
## que queda igual al terminar.
static func legal_moves_int(b: BoardState) -> PackedInt32Array:
	var pseudo := PackedInt32Array()
	gen_pseudo_int(b, pseudo)
	var legal := PackedInt32Array()
	var undo := PackedInt32Array()
	undo.resize(12)
	for mv: int in pseudo:
		# Nunca se captura un rey: si el rival está en jaque en nuestro turno
		# (posición imposible), esa captura no es una jugada.
		if (b.squares[(mv >> 6) & 63] & 7) == ChessPiece.KING:
			continue
		make_int(b, mv, undo)
		var ok := mover_king_safe(b)
		unmake_int(b, undo)
		if ok:
			legal.append(mv)
	return legal


## ¿Tiene el bando al que le toca alguna jugada legal? (sale con la primera)
static func has_legal_move(b: BoardState) -> bool:
	if not _ready_tables:
		_init_tables()
	var undo := PackedInt32Array()
	undo.resize(12)
	# Primero las huidas del rey: en jaque casi siempre alguna vale y evita generar todo.
	var us := b.side_to_move
	var ksq := b.squares.find((us << 3) | ChessPiece.KING)
	if ksq >= 0:
		for t: int in _king_to[ksq]:
			var target := b.squares[t]
			if target != 0 and (((target >> 3) & 1) == us or (target & 7) == ChessPiece.KING):
				continue
			make_int(b, ksq | (t << 6), undo)
			var safe := mover_king_safe(b)
			unmake_int(b, undo)
			if safe:
				return true
	var pseudo := PackedInt32Array()
	gen_pseudo_int(b, pseudo)
	for mv: int in pseudo:
		if (b.squares[(mv >> 6) & 63] & 7) == ChessPiece.KING:
			continue
		make_int(b, mv, undo)
		var ok := mover_king_safe(b)
		unmake_int(b, undo)
		if ok:
			return true
	return false


static func legal_moves(b: BoardState) -> Array[ChessMove]:
	var legal: Array[ChessMove] = []
	for mv: int in legal_moves_int(b):
		legal.append(ChessMove.new(mv & 63, (mv >> 6) & 63, (mv >> 12) & 7))
	return legal


## Busca entre las jugadas legales la que coincide con `m`. Devuelve null si es ilegal.
static func find_legal(b: BoardState, m: ChessMove) -> ChessMove:
	if m == null:
		return null
	for mv: int in legal_moves_int(b):
		var promo := (mv >> 12) & 7
		if (mv & 63) == m.from and ((mv >> 6) & 63) == m.to:
			if promo == m.promotion or (m.promotion == 0 and promo == ChessPiece.QUEEN):
				return ChessMove.new(m.from, m.to, promo)
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
		for df: int in [-1, 1]:
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
	var work := b.clone()
	return _perft(work, depth)


static func _perft(b: BoardState, depth: int) -> int:
	var moves := legal_moves_int(b)
	if depth == 1:
		return moves.size()
	var n := 0
	var undo := PackedInt32Array()
	undo.resize(12)
	for mv: int in moves:
		make_int(b, mv, undo)
		n += _perft(b, depth - 1)
		unmake_int(b, undo)
	return n
