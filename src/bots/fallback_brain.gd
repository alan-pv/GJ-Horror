class_name FallbackBrain
extends ChessBrain
## Cerebro de respaldo en GDScript, sin dependencias. Se usa en el editor y en
## escritorio, o si Maia no carga en el navegador. Busca a 2 plies con
## material y tablas de casillas y convierte las puntuaciones en política con
## un softmax cuya temperatura depende del Elo: un 800 reparte probabilidad
## entre jugadas mediocres, un 2000 casi siempre elige la mejor.

## Tablas de casilla (desde el punto de vista de blancas, a1 = índice 0).
const PST_PAWN := [
	0, 0, 0, 0, 0, 0, 0, 0,
	5, 10, 10, -20, -20, 10, 10, 5,
	5, -5, -10, 0, 0, -10, -5, 5,
	0, 0, 0, 20, 20, 0, 0, 0,
	5, 5, 10, 25, 25, 10, 5, 5,
	10, 10, 20, 30, 30, 20, 10, 10,
	50, 50, 50, 50, 50, 50, 50, 50,
	0, 0, 0, 0, 0, 0, 0, 0,
]
const PST_KNIGHT := [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20, 0, 5, 5, 0, -20, -40,
	-30, 5, 10, 15, 15, 10, 5, -30,
	-30, 0, 15, 20, 20, 15, 0, -30,
	-30, 5, 15, 20, 20, 15, 5, -30,
	-30, 0, 10, 15, 15, 10, 0, -30,
	-40, -20, 0, 0, 0, 0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const PST_CENTER := [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10, 5, 0, 0, 0, 0, 5, -10,
	-10, 10, 10, 10, 10, 10, 10, -10,
	-10, 0, 10, 10, 10, 10, 0, -10,
	-10, 5, 5, 10, 10, 5, 5, -10,
	-10, 0, 5, 10, 10, 5, 0, -10,
	-10, 0, 0, 0, 0, 0, 0, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const PST_KING := [
	20, 30, 10, 0, 0, 10, 30, 20,
	20, 20, 0, 0, 0, 0, 20, 20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
]


func brain_name() -> String:
	return "respaldo (GDScript)"


func get_policy(board: BoardState, elo_self: int, _elo_oppo: int) -> Dictionary:
	var moves := ChessRules.legal_moves(board)
	if moves.is_empty():
		return {}
	var us := board.side_to_move
	var scores := {}
	for m in moves:
		var after := board.clone()
		ChessRules.apply_move(after, m)
		var replies := ChessRules.legal_moves(after)
		var score: float
		if replies.is_empty():
			if ChessRules.in_check(after, after.side_to_move):
				score = 100000.0
			else:
				score = 50000.0 if us == ChessPiece.BLACK else -5000.0
		else:
			score = INF
			for r in replies:
				var after_r := after.clone()
				ChessRules.apply_move(after_r, r)
				score = minf(score, evaluate(after_r, us))
		scores[m.uci()] = score
	return softmax(scores, temperature_for_elo(elo_self))


static func temperature_for_elo(elo: int) -> float:
	var t := clampf((elo - 600.0) / 1600.0, 0.0, 1.0)
	return lerpf(220.0, 25.0, t)


## Evaluación estática desde el punto de vista de `color`.
static func evaluate(b: BoardState, color: int) -> float:
	var total := 0.0
	for sq in 64:
		var p := b.squares[sq]
		if p == ChessPiece.NONE:
			continue
		var c := ChessPiece.color_of(p)
		var idx := sq if c == ChessPiece.WHITE else (7 - ChessPiece.rank_of(sq)) * 8 + ChessPiece.file_of(sq)
		var v := float(ChessPiece.value_of(p))
		match ChessPiece.type_of(p):
			ChessPiece.PAWN: v += PST_PAWN[idx]
			ChessPiece.KNIGHT: v += PST_KNIGHT[idx]
			ChessPiece.BISHOP, ChessPiece.QUEEN: v += PST_CENTER[idx] * 0.5
			ChessPiece.KING: v += PST_KING[idx]
		total += v if c == color else -v
	return total
