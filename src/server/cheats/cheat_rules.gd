class_name CheatRules
## Clasificación, validación y aplicación de trampas sobre el tablero físico.
## El jugador agarra cualquier pieza (no rey) y la deja donde quiere; aquí se
## decide de qué clase es la trampa y qué tan sospechosa resulta (nivel).
## Límites: nunca se toca un rey, nunca queda en jaque el rey del tramposo
## y nunca queda en jaque el bando al que no le toca (posición imposible).
##
## Niveles de sospecha (enteros; 0 = jugada legal, no es trampa):
## - Pieza propia: d = distancia de rey mínima del destino a las casillas a las
##   que esa pieza podría ir legalmente (jugando como si fuera su turno; si no
##   tiene ninguna, a su casilla). En tu turno nivel = d; fuera de él, d + 1.
## - Pieza rival: distancia de rey entre origen y destino.
## - A la pila de capturas propia: `PILE_LEVEL`.


## Destino especial: la pila de capturas de quien hace la trampa (solo robo).
const TO_PILE := -2
## Nivel de un robo (el máximo).
const PILE_LEVEL := 5

const REASON_KING := "kings cannot be touched"
const REASON_ENEMY_ONLY := "enemy pieces only"
const REASON_LEGAL := "that is a legal move"


# --- Consulta de niveles ------------------------------------------------------

## Clase de trampa (`CheatDef.Kind`) que sería agarrar la pieza de `from`;
## -1 si no hay pieza o es un rey.
static func kind_of(b: BoardState, color: int, from: int) -> int:
	if from < 0 or from > 63:
		return -1
	var piece := b.squares[from]
	if piece == ChessPiece.NONE or ChessPiece.type_of(piece) == ChessPiece.KING:
		return -1
	if ChessPiece.color_of(piece) == color:
		return CheatDef.Kind.OWN_MOVE
	return CheatDef.Kind.MOVE_ENEMY


## Nivel de sospecha de llevar la pieza de `from` a `to` (o a `TO_PILE`); -1 si
## no es válido y 0 si es una jugada legal propia en tu turno. Pura.
static func level(b: BoardState, color: int, from: int, to: int, turn_ready: int = -1) -> int:
	var ctx := context(b, color, from, turn_ready)
	if ctx.is_empty():
		return -1
	return dest_level(ctx, to)


## Todos los destinos válidos de la pieza de `from` con su nivel: {casilla: nivel}
## (más `TO_PILE` si es rival). Vacío si no hay pieza o es un rey.
static func preview(b: BoardState, color: int, from: int, turn_ready: int = -1) -> Dictionary:
	var out := {}
	var ctx := context(b, color, from, turn_ready)
	if ctx.is_empty():
		return out
	for to in 64:
		var lv := dest_level(ctx, to)
		if lv >= 0:
			out[to] = lv
	if not ctx.own:
		out[TO_PILE] = PILE_LEVEL
	return out


## Resultado completo para el servidor y los bots:
## {ok, reason, kind, level, distance, as_move}. `allow_legal` acepta el nivel 0
## (solo al re-validar una trampa que ya estaba en curso).
static func validate(b: BoardState, color: int, from: int, to: int, allow_legal: bool = false, turn_ready: int = -1) -> Dictionary:
	var res := {"ok": false, "reason": "", "kind": -1, "level": -1, "distance": 0, "as_move": false}
	if from < 0 or from > 63:
		res.reason = "invalid square"
		return res
	if b.squares[from] == ChessPiece.NONE:
		res.reason = "no piece there"
		return res
	if ChessPiece.type_of(b.squares[from]) == ChessPiece.KING:
		res.reason = REASON_KING
		return res
	var ctx := context(b, color, from, turn_ready)
	var lv := dest_level(ctx, to)
	res.kind = CheatDef.Kind.STEAL if to == TO_PILE and not ctx.own else ctx.kind
	if lv < 0:
		res.reason = ctx.reason
		return res
	if lv == 0 and not allow_legal:
		res.reason = REASON_LEGAL
		return res
	res.ok = true
	res.level = lv
	res.distance = 0 if to == TO_PILE else king_distance(from, to)
	res.as_move = ctx.own and ctx.in_turn and lv >= 1
	return res


# --- Contexto reutilizable -------------------------------------------------------

## Prepara lo que no depende del destino (copia de trabajo del tablero y, para
## piezas propias, sus destinos legales) para evaluar muchos destinos de una
## misma pieza. {} si no hay pieza trampeable en `from`. Se usa con `dest_level`.
## `turn_ready`: 1 si `color` puede jugar ahora, 0 si no, -1 para deducirlo del
## tablero (le toca). El servidor pasa 0 mientras el rival no pulsó el reloj.
static func context(b: BoardState, color: int, from: int, turn_ready: int = -1) -> Dictionary:
	var kind := kind_of(b, color, from)
	if kind < 0:
		return {}
	var ctx := {
		"b": b.clone(), "color": color, "from": from, "kind": kind,
		"piece": b.squares[from], "own": kind == CheatDef.Kind.OWN_MOVE,
		"in_turn": (b.side_to_move == color) if turn_ready < 0 else turn_ready == 1, "reason": "",
		"legal": PackedByteArray(), "legal_list": PackedInt32Array(),
	}
	if ctx.own:
		var legal := PackedByteArray()
		legal.resize(64)
		var list := PackedInt32Array()
		var c: BoardState = ctx.b.clone()
		c.side_to_move = color
		if b.side_to_move != color:
			c.ep_square = -1
		# Solo se prueban hacer/deshacer las jugadas de esta pieza (no las de todo el bando).
		var pseudo := PackedInt32Array()
		ChessRules.gen_pseudo_int(c, pseudo)
		var undo := PackedInt32Array()
		undo.resize(12)
		for mv: int in pseudo:
			if (mv & 63) != from:
				continue
			var dst := (mv >> 6) & 63
			if legal[dst] == 1 or ChessPiece.type_of(c.squares[dst]) == ChessPiece.KING:
				continue
			ChessRules.make_int(c, mv, undo)
			var safe := ChessRules.mover_king_safe(c)
			ChessRules.unmake_int(c, undo)
			if safe:
				legal[dst] = 1
				list.append(dst)
		ctx.legal = legal
		ctx.legal_list = list
	return ctx


## Nivel del destino `to` según el contexto; -1 si es inválido (el motivo queda
## en `ctx.reason`). `to` puede ser `TO_PILE`.
static func dest_level(ctx: Dictionary, to: int) -> int:
	var from: int = ctx.from
	var color: int = ctx.color
	var sc: BoardState = ctx.b
	ctx.reason = ""
	if to == TO_PILE:
		if ctx.own:
			ctx.reason = REASON_ENEMY_ONLY
			return -1
		return PILE_LEVEL if _safe_after(ctx, to) else -1
	if to < 0 or to > 63:
		ctx.reason = "invalid square"
		return -1
	if sc.squares[to] != ChessPiece.NONE:
		ctx.reason = "the destination must be empty"
		return -1
	var level := 0
	if ctx.own:
		if ctx.in_turn and ctx.legal[to] == 1:
			return 0
		var d := 0
		if ctx.legal_list.is_empty():
			d = king_distance(from, to)
		else:
			d = 8
			for s: int in ctx.legal_list:
				d = mini(d, king_distance(s, to))
		level = d if ctx.in_turn else d + 1
	else:
		level = king_distance(from, to)
	if ChessPiece.type_of(ctx.piece) == ChessPiece.PAWN and (ChessPiece.rank_of(to) == 0 or ChessPiece.rank_of(to) == 7):
		ctx.reason = "a pawn cannot end up on the first or last rank"
		return -1
	return level if _safe_after(ctx, to) else -1


## ¿La posición resultante es posible? Usa la copia de trabajo (la deja igual).
static func _safe_after(ctx: Dictionary, to: int) -> bool:
	var sc: BoardState = ctx.b
	var from: int = ctx.from
	var color: int = ctx.color
	var piece: int = ctx.piece
	sc.squares[from] = ChessPiece.NONE
	if to >= 0:
		sc.squares[to] = piece
	var reason := ""
	if ChessRules.in_check(sc, color):
		reason = "it would leave your king in check"
	elif not (ctx.own and ctx.in_turn) and ChessRules.in_check(sc, ChessPiece.opposite(sc.side_to_move)):
		# Con tu pieza en tu turno la trampa es tu jugada: dar jaque está permitido.
		reason = "it would put the side not to move in check"
	sc.squares[from] = piece
	if to >= 0:
		sc.squares[to] = ChessPiece.NONE
	ctx.reason = reason
	return reason == ""


# --- Aplicación -------------------------------------------------------------------

## Aplica la trampa (ya validada). `rng` decide hacia dónde queda descentrada la pieza.
## No pasa el turno: eso lo hace el servidor cuando la trampa es una jugada (`as_move`).
static func apply(b: BoardState, color: int, def: CheatDef, from: int, to: int, rng: RandomNumberGenerator) -> void:
	var piece := b.squares[from]
	b.squares[from] = ChessPiece.NONE
	b.offsets[from] = Vector2.ZERO
	if to == TO_PILE:
		b.captured[color].append(piece)
	else:
		b.squares[to] = piece
		b.offsets[to] = Vector2.ZERO
		if def.offset_amount > 0.0:
			var ang := rng.randf() * TAU
			b.offsets[to] = Vector2(cos(ang), sin(ang)) * def.offset_amount
		ChessRules.update_castling_rights(b, to)
	ChessRules.update_castling_rights(b, from)
	# La regla de 50 jugadas se reinicia con cualquier trampa.
	b.halfmove_clock = 0


## Distancia de rey (Chebyshev) entre dos casillas.
static func king_distance(a: int, c: int) -> int:
	return maxi(absi(ChessPiece.file_of(a) - ChessPiece.file_of(c)), absi(ChessPiece.rank_of(a) - ChessPiece.rank_of(c)))
