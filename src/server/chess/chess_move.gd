class_name ChessMove
extends RefCounted
## Jugada de ajedrez normal (no trampa). `promotion` es un tipo de pieza o 0.

var from: int
var to: int
var promotion: int


func _init(p_from: int = -1, p_to: int = -1, p_promotion: int = 0) -> void:
	from = p_from
	to = p_to
	promotion = p_promotion


func uci() -> String:
	var s := ChessPiece.square_name(from) + ChessPiece.square_name(to)
	if promotion != 0:
		s += ".pnbrqk"[promotion]
	return s


func equals(other: ChessMove) -> bool:
	return other != null and from == other.from and to == other.to and promotion == other.promotion


static func from_uci(s: String) -> ChessMove:
	if s.length() < 4:
		return null
	var f := ChessPiece.square_from_name(s.substr(0, 2))
	var t := ChessPiece.square_from_name(s.substr(2, 2))
	if f < 0 or t < 0:
		return null
	var promo := 0
	if s.length() >= 5:
		promo = ".pnbrqk".find(s[4].to_lower())
		if promo <= ChessPiece.PAWN or promo == ChessPiece.KING:
			return null
	return ChessMove.new(f, t, promo)
