class_name MaiaEncoding
extends RefCounted
## Port exacto a GDScript de la codificación de entrada de Maia-2
## (maia2/utils.py: board_to_tensor, map_to_category, mirror_move).
##
## Maia-2 siempre ve el tablero DESDE EL PUNTO DE VISTA DE BLANCAS: si juegan
## negras se espeja el tablero (filas invertidas y colores intercambiados), y
## las jugadas del vocabulario también están espejadas. Este archivo hace la
## ida (tablero -> tensor, jugadas legales -> índices) y la vuelta (índice -> UCI real).

const MOVES_PATH := "res://data/maia2/moves.json"
const CANALES := 18
const ELO_MIN := 1100
const ELO_MAX := 2000
const ELO_PASO := 100

static var _moves: PackedStringArray = PackedStringArray()
static var _move_index: Dictionary = {}


## Vocabulario de Maia-2: índice -> UCI (perspectiva de blancas). Se carga una vez.
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


## Categoría de Elo (0..10): <1100 -> 0; 1100-1199 -> 1; ...; 1900-1999 -> 9; >=2000 -> 10.
static func elo_category(elo: int) -> int:
	if elo < ELO_MIN:
		return 0
	if elo >= ELO_MAX:
		return (ELO_MAX - ELO_MIN) / ELO_PASO + 1
	return 1 + (elo - ELO_MIN) / ELO_PASO


## Casilla espejada verticalmente (a1 <-> a8).
static func mirror_square(sq: int) -> int:
	return (7 - sq / 8) * 8 + sq % 8


## UCI espejado verticalmente (e2e4 <-> e7e5); la promoción se conserva.
static func mirror_uci(uci: String) -> String:
	var r1 := str(9 - int(uci[1]))
	var r2 := str(9 - int(uci[3]))
	return uci[0] + r1 + uci[2] + r2 + uci.substr(4)


## Tensor [18][8][8] aplanado (canal, fila, columna). Canales: 0-5 peones, caballos,
## alfiles, torres, dama y rey de quien mueve; 6-11 los del rival; 12 turno (siempre 1
## tras espejar); 13-16 enroques (propio K, Q; rival K, Q); 17 captura al paso.
static func encode_board(board: BoardState) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(CANALES * 64)
	var negras := board.side_to_move == ChessPiece.BLACK
	for sq in 64:
		var p := board.squares[sq]
		if p == 0:
			continue
		var color := ChessPiece.color_of(p)
		var dst := mirror_square(sq) if negras else sq
		# Tras espejar, "propio" (quien mueve) siempre ocupa los canales 0-5.
		var propio := (color == board.side_to_move)
		var canal := (ChessPiece.type_of(p) - 1) + (0 if propio else 6)
		t[canal * 64 + dst] = 1.0
	for i in 64:
		t[12 * 64 + i] = 1.0
	var k_propio := BoardState.CASTLE_BK if negras else BoardState.CASTLE_WK
	var q_propio := BoardState.CASTLE_BQ if negras else BoardState.CASTLE_WQ
	var k_rival := BoardState.CASTLE_WK if negras else BoardState.CASTLE_BK
	var q_rival := BoardState.CASTLE_WQ if negras else BoardState.CASTLE_BQ
	var derechos := [k_propio, q_propio, k_rival, q_rival]
	for i in 4:
		if board.castling & derechos[i] != 0:
			for s in 64:
				t[(13 + i) * 64 + s] = 1.0
	if board.ep_square >= 0:
		var ep := mirror_square(board.ep_square) if negras else board.ep_square
		t[17 * 64 + ep] = 1.0
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
