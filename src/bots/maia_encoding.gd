class_name MaiaEncoding
extends RefCounted
## Port exacto a GDScript de la codificación de entrada de Maia-3
## (maia3/dataset.py: tokenize_board, get_historical_tokens; maia3/utils.py: mirror_move).
##
## Maia-3 ve cada posición DESDE EL PUNTO DE VISTA DE QUIEN MUEVE: si juegan
## negras se espeja el tablero (filas invertidas y colores intercambiados), y las
## jugadas del vocabulario también están espejadas. El modelo recibe además las
## 8 últimas posiciones (la actual y 7 previas), cada una espejada según SU propio
## turno. Este archivo hace la ida (posiciones -> tensor, jugadas legales -> índices)
## y la vuelta (índice -> UCI real). El Elo entra como número continuo (0..5000).

const MOVES_PATH := "res://data/maia3/moves.json"
## Posiciones que ve el modelo (la actual + 7 previas).
const HISTORIA := 8
## Canales por casilla y posición: 6 piezas de quien mueve + 6 del rival.
const CANALES := 12
## Valores por casilla: HISTORIA * CANALES.
const DIM_TOKEN := HISTORIA * CANALES
const ELO_MAX := 5000.0

static var _moves: PackedStringArray = PackedStringArray()
static var _move_index: Dictionary = {}


## Vocabulario de Maia-3: índice -> UCI (perspectiva de blancas, 4352 jugadas
## incluyendo coronaciones). Se carga una vez.
static func moves() -> PackedStringArray:
	if _moves.is_empty():
		_cargar_vocabulario()
	return _moves


static func move_to_index(uci_espejado: String) -> int:
	if _moves.is_empty():
		_cargar_vocabulario()
	return _move_index.get(uci_espejado, -1)


static func _cargar_vocabulario() -> void:
	var texto := ""
	if FileAccess.file_exists(MOVES_PATH):
		texto = FileAccess.get_file_as_string(MOVES_PATH)
	var datos: Variant = null
	if texto != "":
		datos = JSON.parse_string(texto)
	if datos == null and ResourceLoader.exists(MOVES_PATH):
		# En exportaciones el .json puede estar importado como recurso JSON.
		var res := load(MOVES_PATH)
		if res is JSON:
			datos = res.data
	if not (datos is Array):
		push_error("MaiaEncoding: no se pudo cargar " + MOVES_PATH)
		return
	var lista := PackedStringArray()
	for i in datos.size():
		lista.append(str(datos[i]))
		_move_index[str(datos[i])] = i
	_moves = lista


## Elo acotado al rango que entiende el modelo. Es continuo: no hay categorías.
static func elo_value(elo: float) -> float:
	return clampf(elo, 0.0, ELO_MAX)


## Casilla espejada verticalmente (a1 <-> a8).
static func mirror_square(sq: int) -> int:
	return (7 - sq / 8) * 8 + sq % 8


## UCI espejado verticalmente (e2e4 <-> e7e5); la promoción se conserva.
static func mirror_uci(uci: String) -> String:
	var r1 := str(9 - int(uci[1]))
	var r2 := str(9 - int(uci[3]))
	return uci[0] + r1 + uci[2] + r2 + uci.substr(4)


## Tensor [64][96] aplanado (casilla, canal) con las últimas HISTORIA posiciones.
## `boards` va de la más antigua a la actual (la última); si hay menos de 8 se rellena
## por delante con la más antigua disponible, como hace maia3 al empezar la partida.
## Índice = casilla * 96 + posición * 12 + canal, con la posición 0 la más antigua.
## Canales: 0-5 peón, caballo, alfil, torre, dama y rey de quien mueve en ESA posición;
## 6-11 los del rival. No hay canales de turno, enroque ni captura al paso.
static func encode_history(boards: Array) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(64 * DIM_TOKEN)
	var usadas := boards.slice(maxi(0, boards.size() - HISTORIA))
	if usadas.is_empty():
		return t
	var relleno := HISTORIA - usadas.size()
	for h in HISTORIA:
		var b: BoardState = usadas[maxi(0, h - relleno)]
		var negras := b.side_to_move == ChessPiece.BLACK
		for sq in 64:
			var p := b.squares[sq]
			if p == 0:
				continue
			var dst := mirror_square(sq) if negras else sq
			# Tras espejar, "propio" (quien mueve) siempre ocupa los canales 0-5.
			var canal := (ChessPiece.type_of(p) - 1) + (0 if ChessPiece.color_of(p) == b.side_to_move else 6)
			t[dst * DIM_TOKEN + h * CANALES + canal] = 1.0
	return t


## Jugadas legales del tablero como {índice_del_vocabulario: uci_real}.
## Las jugadas ausentes del vocabulario se descartan (no debería haber ninguna).
static func legal_index_map(board: BoardState) -> Dictionary:
	var out := {}
	var negras := board.side_to_move == ChessPiece.BLACK
	for m in ChessRules.legal_moves(board):
		var real := m.uci()
		var idx := move_to_index(mirror_uci(real) if negras else real)
		if idx >= 0:
			out[idx] = real
	return out
