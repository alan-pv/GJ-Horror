class_name TournamentGame
extends RefCounted
## Una partida de la ronda en curso: quién juega con qué color, en qué mesa y
## cómo terminó. Los ids son los de `PlayerSession.id` del torneo.

## Mesa del salón: índice de `HallLayout` (0..15; la del humano es `HallLayout.human_table`),
## -2 = sin mesa visible (más partidas que mesas). `TABLE_MAIN` ya no se asigna.
const TABLE_MAIN := -1
const TABLE_NONE := -2

var white: int
var black: int
## 1 o 2 (la final se juega a dos partidas con colores invertidos).
var game_no: int = 1
var table: int = TABLE_NONE
var done: bool = false
var winner_color: int = -1
var reason: String = ""
## Segundos que sobraron en el reloj de cada color al terminar.
var time_left: PackedFloat64Array = [0.0, 0.0]


func _init(p_white: int = -1, p_black: int = -1, p_game_no: int = 1) -> void:
	white = p_white
	black = p_black
	game_no = p_game_no


func involves(id: int) -> bool:
	return id == white or id == black


func color_of(id: int) -> int:
	return ChessPiece.WHITE if id == white else ChessPiece.BLACK


func player_of(color: int) -> int:
	return white if color == ChessPiece.WHITE else black


func opponent_of(id: int) -> int:
	return black if id == white else white


## Asiento (color) del perdedor, o -1 si no hay resultado.
func loser_seat() -> int:
	return -1 if winner_color < 0 else ChessPiece.opposite(winner_color)


func winner_id() -> int:
	return -1 if winner_color < 0 else player_of(winner_color)


func loser_id() -> int:
	return -1 if winner_color < 0 else player_of(ChessPiece.opposite(winner_color))


## Segundos sobrantes del jugador `id` en esta partida.
func time_left_of(id: int) -> float:
	return time_left[color_of(id)]
