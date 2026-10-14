class_name ChessPiece
## Codificación de piezas: tipo en los 3 bits bajos, color en el bit 3.
## 0 = casilla vacía. Blancas 1..6, negras 9..14.

const NONE := 0
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const WHITE := 0
const BLACK := 1

## Valor material en centipeones (el rey no cuenta).
const VALUES := [0, 100, 320, 330, 500, 900, 0]

const _FEN_CHARS := ".pnbrqk"


static func make(color: int, type: int) -> int:
	return type | (color << 3)


static func type_of(piece: int) -> int:
	return piece & 7


static func color_of(piece: int) -> int:
	return (piece >> 3) & 1


static func value_of(piece: int) -> int:
	return VALUES[piece & 7]


static func opposite(color: int) -> int:
	return 1 - color


static func to_char(piece: int) -> String:
	if piece == NONE:
		return "."
	var c := _FEN_CHARS[type_of(piece)]
	return c.to_upper() if color_of(piece) == WHITE else c


static func from_char(c: String) -> int:
	var t := _FEN_CHARS.find(c.to_lower())
	if t <= 0:
		return NONE
	return make(WHITE if c == c.to_upper() else BLACK, t)


static func square(file: int, rank: int) -> int:
	return rank * 8 + file


static func file_of(sq: int) -> int:
	return sq % 8


static func rank_of(sq: int) -> int:
	return sq / 8


static func square_name(sq: int) -> String:
	return "abcdefgh"[sq % 8] + str(sq / 8 + 1)


static func square_from_name(n: String) -> int:
	if n.length() != 2:
		return -1
	var f := "abcdefgh".find(n[0])
	var r := "12345678".find(n[1])
	if f < 0 or r < 0:
		return -1
	return r * 8 + f
