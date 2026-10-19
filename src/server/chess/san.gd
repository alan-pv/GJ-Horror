class_name San
extends RefCounted
## Notación algebraica estándar (SAN) de una jugada: "e4", "Nbd7", "exd5",
## "O-O", "e8=Q+", "Qh4#". Lógica pura sobre `BoardState`.

const _LETTERS := ".PNBRQK"


## SAN de `move` calculada sobre `board` ANTES de aplicarla (no lo modifica).
static func of(board: BoardState, move: ChessMove) -> String:
	var piece := board.squares[move.from]
	var type := ChessPiece.type_of(piece)
	var s := ""
	if ChessRules.is_castle(board, move):
		s = "O-O" if move.to > move.from else "O-O-O"
	else:
		var capture := ChessRules.is_capture(board, move)
		if type == ChessPiece.PAWN:
			if capture:
				s += "abcdefgh"[ChessPiece.file_of(move.from)] + "x"
		else:
			s += _LETTERS[type]
			s += _disambiguation(board, move, type)
			if capture:
				s += "x"
		s += ChessPiece.square_name(move.to)
		if move.promotion != 0:
			s += "=" + _LETTERS[move.promotion]
	return s + _check_suffix(board, move)


## Columna, fila o ambas cuando otra pieza igual puede ir a la misma casilla.
static func _disambiguation(board: BoardState, move: ChessMove, type: int) -> String:
	if type == ChessPiece.KING:
		return ""
	var same_file := false
	var same_rank := false
	var ambiguous := false
	for m in ChessRules.legal_moves(board):
		if m.to != move.to or m.from == move.from or board.squares[m.from] != board.squares[move.from]:
			continue
		ambiguous = true
		if ChessPiece.file_of(m.from) == ChessPiece.file_of(move.from):
			same_file = true
		if ChessPiece.rank_of(m.from) == ChessPiece.rank_of(move.from):
			same_rank = true
	if not ambiguous:
		return ""
	var file_name: String = "abcdefgh"[ChessPiece.file_of(move.from)]
	var rank_name := str(ChessPiece.rank_of(move.from) + 1)
	if not same_file:
		return file_name
	if not same_rank:
		return rank_name
	return file_name + rank_name


static func _check_suffix(board: BoardState, move: ChessMove) -> String:
	var after := board.clone()
	ChessRules.apply_move(after, move)
	if not ChessRules.in_check(after, after.side_to_move):
		return ""
	return "#" if ChessRules.legal_moves(after).is_empty() else "+"
