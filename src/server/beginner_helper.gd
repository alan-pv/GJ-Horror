class_name BeginnerHelper
## Detecta errores graves antes de aceptar una jugada: permitir mate en 1 o
## perder mucho material comparado con la mejor alternativa. Nunca sugiere
## la mejor jugada; solo avisa que esa es mala.
##
## Búsqueda corta (jugada, respuesta, recaptura estimada) para que tarde
## unas décimas de segundo, sin motor externo. Se evalúa sobre el tablero
## físico, con trampas incluidas.

const PIECE_NAMES := {
	ChessPiece.PAWN: "el peón",
	ChessPiece.KNIGHT: "el caballo",
	ChessPiece.BISHOP: "el alfil",
	ChessPiece.ROOK: "la torre",
	ChessPiece.QUEEN: "la dama",
}
const MATE_SCORE := 100000


## Devuelve la frase que murmura el personaje, o "" si la jugada es aceptable.
static func check_move(b: BoardState, move: ChessMove, threshold_cp: int) -> String:
	var moves := ChessRules.legal_moves(b)
	if moves.size() <= 1:
		return ""
	var best := -MATE_SCORE * 2
	var chosen := {}
	for m in moves:
		var r := _score_move(b, m)
		best = maxi(best, r.score)
		if m.equals(move):
			chosen = r
	if chosen.is_empty():
		return ""
	if chosen.allows_mate and best > -MATE_SCORE:
		return "...espera, eso permite mate."
	if chosen.score <= best - threshold_cp:
		var lost: int = chosen.lost_piece
		if PIECE_NAMES.has(lost):
			var name: String = PIECE_NAMES[lost]
			var colgado := "colgada" if name.begins_with("la") else "colgado"
			return "...no, eso deja %s %s." % [name, colgado]
		return "...mmm, no. Eso pierde material."
	return ""


## Peor caso para quien mueve tras `m`: el rival elige la respuesta que más
## nos perjudica y luego nosotros tomamos la mejor captura disponible.
static func _score_move(b: BoardState, m: ChessMove) -> Dictionary:
	var us := b.side_to_move
	var after := b.clone()
	ChessRules.apply_move(after, m)
	var replies := ChessRules.legal_moves(after)
	if replies.is_empty():
		# Mate dado (excelente) o ahogado (las tablas ganan negras).
		if ChessRules.in_check(after, after.side_to_move):
			return {"score": MATE_SCORE, "allows_mate": false, "lost_piece": 0}
		var draw := MATE_SCORE if us == ChessPiece.BLACK else -MATE_SCORE / 2
		return {"score": draw, "allows_mate": false, "lost_piece": 0}
	var worst := MATE_SCORE * 2
	var worst_lost := 0
	var allows_mate := false
	for r in replies:
		var lost := ChessPiece.type_of(after.squares[r.to]) if after.squares[r.to] != ChessPiece.NONE else 0
		var after_r := after.clone()
		ChessRules.apply_move(after_r, r)
		var score: int
		if ChessRules.in_check(after_r, us) and ChessRules.legal_moves(after_r).is_empty():
			score = -MATE_SCORE
			allows_mate = true
		else:
			score = _balance(after_r, us) + _best_capture_gain(after_r, us)
		if score < worst:
			worst = score
			worst_lost = lost
	return {"score": worst, "allows_mate": allows_mate, "lost_piece": worst_lost}


static func _balance(b: BoardState, color: int) -> int:
	return ChessRules.material(b, color) - ChessRules.material(b, ChessPiece.opposite(color))


## Ganancia estimada de nuestra mejor captura: valor capturado menos el valor
## de la pieza que captura si la casilla está defendida.
static func _best_capture_gain(b: BoardState, color: int) -> int:
	var best := 0
	for m in ChessRules.pseudo_moves(b):
		var victim := b.squares[m.to]
		if victim == ChessPiece.NONE or ChessPiece.type_of(victim) == ChessPiece.KING:
			continue
		var gain := ChessPiece.value_of(victim)
		if ChessRules.is_square_attacked(b, m.to, ChessPiece.opposite(color)):
			if ChessPiece.type_of(b.squares[m.from]) == ChessPiece.KING:
				continue
			gain -= ChessPiece.value_of(b.squares[m.from])
		best = maxi(best, gain)
	return best
