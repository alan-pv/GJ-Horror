class_name PieceInteraction
extends RefCounted
## Única interacción de selección del jugador (sin nodos de entrada): agarrar una pieza
## cualquiera (propia o rival, en tu turno o fuera de él; reyes incluidos), ver el mapa de calor
## de adónde puede ir y soltarla. El servidor clasifica: nivel 0 es una jugada normal
## (`submit_move`); cualquier otro nivel es una trampa (`start_cheat`); la pila de capturas
## propia (`CheatRules.TO_PILE`) es un robo. Solo envía intenciones; no decide nada.
##
## `PlayerController` le pasa los clics ya convertidos en destino (casilla 0-63, `TO_PILE`
## o -1 si no se apuntó a nada) y es el único que consume el clic.

## El jugador agarró una pieza con un clic (no al refrescar el mapa). `rival_piece`: es del rival.
## Lo escucha el monólogo interior para el mini tutorial de trampas.
signal piece_picked(rival_piece: bool)

const TO_PILE := CheatRules.TO_PILE

var server: MatchServer
## Vista del tablero (puede ser null en pruebas: entonces no se dibuja nada).
var board: BoardView
var color: int = ChessPiece.WHITE
## Muestra un subtítulo (texto en inglés). Vacío en pruebas.
var subtitle: Callable = Callable()
## `() -> bool`: true si el jugador puede actuar ahora (entrada no bloqueada y mano sin gesto en
## curso). El servidor aporta el resto de condiciones (partida, acusación, trampa activa).
var player_ok: Callable = Callable()

## Casilla de la pieza elegida (-1 si ninguna).
var selected: int = -1
## Mapa de calor de la selección {casilla: nivel}, con las jugadas legales (capturas incluidas)
## en nivel 0, y `TO_PILE` si la pieza es rival.
var levels: Dictionary = {}

var _sel_code: int = ChessPiece.NONE
var _legal: Array[ChessMove] = []


func setup(p_server: MatchServer, p_board: BoardView, p_color: int) -> void:
	server = p_server
	board = p_board
	color = p_color
	server.state_changed.connect(_on_state_changed)
	server.game_over.connect(func(_w: int, _r: String) -> void: deselect())


## ¿Puede el jugador agarrar piezas ahora?
func can_act() -> bool:
	if not server.started or server.is_over() or server.accusation_pending():
		return false
	if server.is_hand_busy(color):
		return false
	return not player_ok.is_valid() or bool(player_ok.call())


## Procesa un clic sobre `target` (casilla, `TO_PILE` o -1). Devuelve la acción tomada:
## "busy" (mano ocupada), "none", "select", "deselect", "move" (jugada normal),
## "cheat" (trampa empezada), "pile" (robo empezado) o "reject" (servidor o regla).
func click(target: int) -> String:
	if not can_act():
		if server.started and not server.is_over() and (server.is_hand_busy(color) \
				or (player_ok.is_valid() and not bool(player_ok.call()))):
			_say("...my hand is busy")
			return "busy"
		return "none"
	if target == -1:
		if selected < 0:
			return "none"
		deselect()
		return "deselect"
	if target == TO_PILE:
		if selected >= 0 and levels.has(TO_PILE):
			return _start_cheat(selected, TO_PILE)
		deselect()
		return "deselect"
	if target < 0 or target > 63:
		return "none"
	if selected >= 0:
		if target == selected:
			deselect()
			return "deselect"
		if levels.has(target):
			if int(levels[target]) == 0:
				return _play(selected, target)
			return _start_cheat(selected, target)
	var piece := server.board.squares[target]
	if piece == ChessPiece.NONE:
		if selected < 0:
			return "none"
		# Casilla vacía que el servidor no admite: se pregunta para dar el motivo.
		return _start_cheat(selected, target)
	if not select(target):
		return "none"
	piece_picked.emit(ChessPiece.color_of(piece) != color)
	return "select"


## Elige la pieza de `sq` y pide su mapa de calor. false si no se puede agarrar (vacía).
func select(sq: int) -> bool:
	var preview := server.cheat_preview(color, sq)
	if preview.is_empty():
		deselect()
		return false
	selected = sq
	_sel_code = server.board.squares[sq]
	levels = preview.duplicate()
	_overlay_legal(sq)
	_draw()
	return true


func deselect() -> void:
	selected = -1
	_sel_code = ChessPiece.NONE
	levels = {}
	_legal = []
	if board != null:
		board.clear_highlights()


## Nivel del destino `target` en la selección actual (-1 si no es destino).
func level_of(target: int) -> int:
	return int(levels.get(target, -1))


# --- Interno -------------------------------------------------------------------------------

## Las jugadas legales (también capturas, que el servidor no incluye como trampa) van en nivel 0.
func _overlay_legal(sq: int) -> void:
	_legal = []
	if server.turn_ready_for(color) != 1 or ChessPiece.color_of(server.board.squares[sq]) != color:
		return
	for m in server.legal_moves():
		if m.from == sq and (m.promotion == 0 or m.promotion == ChessPiece.QUEEN):
			_legal.append(m)
			levels[m.to] = 0


func _draw() -> void:
	if board == null:
		return
	var captures: Array = []
	for m in _legal:
		if _is_capture(m):
			captures.append(m.to)
	board.set_heatmap(selected, levels, captures)


func _is_capture(m: ChessMove) -> bool:
	if server.board.squares[m.to] != ChessPiece.NONE:
		return true
	# Al paso: un peón que cambia de columna a una casilla vacía.
	return ChessPiece.type_of(server.board.squares[m.from]) == ChessPiece.PAWN \
			and ChessPiece.file_of(m.from) != ChessPiece.file_of(m.to)


func _play(from: int, to: int) -> String:
	for m in _legal:
		if m.from == from and m.to == to:
			# El resultado (incluida la advertencia de principiante) llega por señales.
			server.submit_move(color, m.uci())
			deselect()
			return "move"
	return "none"


func _start_cheat(from: int, to: int) -> String:
	var res := server.start_cheat(color, from, to)
	if not res.ok:
		_say("...no, not that: %s" % res.reason, 2.5)
		return "reject"
	deselect()
	return "pile" if to == TO_PILE else "cheat"


func _say(text: String, seconds: float = 2.0) -> void:
	if subtitle.is_valid():
		subtitle.call(text, seconds)


## El tablero cambió (jugada, trampa, pulsación): se vuelve a pedir el mapa de calor, o se suelta
## la pieza si ya no está donde estaba.
func _on_state_changed() -> void:
	if selected < 0:
		return
	if server.board.squares[selected] != _sel_code or not can_act():
		deselect()
		return
	select(selected)
