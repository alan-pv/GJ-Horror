class_name BoardState
extends RefCounted
## Estado FÍSICO del tablero: lo que hay sobre la mesa, no lo que resultaría
## de las jugadas legales. Las trampas lo modifican por fuera de las reglas.
## Casillas: índice = fila * 8 + columna (a1 = 0, h8 = 63).

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

var squares: PackedInt32Array
## Desplazamiento fino de cada pieza dentro de su casilla (en fracciones de casilla).
## Es la evidencia visual de una trampa (pieza descentrada).
var offsets: PackedVector2Array
var side_to_move: int = ChessPiece.WHITE
var castling: int = 0
var ep_square: int = -1
var halfmove_clock: int = 0
var fullmove_number: int = 1
## Piezas capturadas POR cada color (la pila junto a ese jugador).
var captured: Array = [[], []]
## Piezas escondidas en la mano/regazo de cada color.
var hand: Array = [[], []]


func _init() -> void:
	squares.resize(64)
	offsets.resize(64)


static func from_fen(fen: String) -> BoardState:
	var b := BoardState.new()
	var parts := fen.strip_edges().split(" ", false)
	var rank := 7
	var file := 0
	for c in parts[0]:
		if c == "/":
			rank -= 1
			file = 0
		elif c.is_valid_int():
			file += int(c)
		else:
			b.squares[ChessPiece.square(file, rank)] = ChessPiece.from_char(c)
			file += 1
	b.side_to_move = ChessPiece.BLACK if parts.size() > 1 and parts[1] == "b" else ChessPiece.WHITE
	if parts.size() > 2:
		for c in parts[2]:
			match c:
				"K": b.castling |= CASTLE_WK
				"Q": b.castling |= CASTLE_WQ
				"k": b.castling |= CASTLE_BK
				"q": b.castling |= CASTLE_BQ
	if parts.size() > 3 and parts[3] != "-":
		b.ep_square = ChessPiece.square_from_name(parts[3])
	if parts.size() > 4:
		b.halfmove_clock = int(parts[4])
	if parts.size() > 5:
		b.fullmove_number = int(parts[5])
	return b


static func start_position() -> BoardState:
	return from_fen(START_FEN)


func clone() -> BoardState:
	var b := BoardState.new()
	b.squares = squares.duplicate()
	b.offsets = offsets.duplicate()
	b.side_to_move = side_to_move
	b.castling = castling
	b.ep_square = ep_square
	b.halfmove_clock = halfmove_clock
	b.fullmove_number = fullmove_number
	b.captured = [captured[0].duplicate(), captured[1].duplicate()]
	b.hand = [hand[0].duplicate(), hand[1].duplicate()]
	return b


func piece_at(sq: int) -> int:
	return squares[sq]


func placement_fen() -> String:
	var s := ""
	for rank in range(7, -1, -1):
		var empty := 0
		for file in 8:
			var p := squares[ChessPiece.square(file, rank)]
			if p == ChessPiece.NONE:
				empty += 1
			else:
				if empty > 0:
					s += str(empty)
					empty = 0
				s += ChessPiece.to_char(p)
		if empty > 0:
			s += str(empty)
		if rank > 0:
			s += "/"
	return s


func castling_fen() -> String:
	var s := ""
	if castling & CASTLE_WK: s += "K"
	if castling & CASTLE_WQ: s += "Q"
	if castling & CASTLE_BK: s += "k"
	if castling & CASTLE_BQ: s += "q"
	return s if s != "" else "-"


func to_fen() -> String:
	return "%s %s %s %s %d %d" % [
		placement_fen(),
		"w" if side_to_move == ChessPiece.WHITE else "b",
		castling_fen(),
		ChessPiece.square_name(ep_square) if ep_square >= 0 else "-",
		halfmove_clock,
		fullmove_number,
	]


## Clave para la regla de repetición: posición física, turno, enroques y al paso.
func position_key() -> String:
	return "%s %d %d %d" % [placement_fen(), side_to_move, castling, ep_square]


func king_square(color: int) -> int:
	return squares.find(ChessPiece.make(color, ChessPiece.KING))
