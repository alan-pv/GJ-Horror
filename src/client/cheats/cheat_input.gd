class_name CheatInput
extends Node
## Entrada del jugador para hacer trampa: teclas 1-4 arman una trampa, clic en
## la pieza y luego en el destino (el robo no necesita destino), X aborta la
## que está en curso y el clic derecho (o Esc) cancela lo armado. Mientras hay
## una trampa armada los clics del tablero se consumen aquí, así que la jugada
## normal no se dispara. Solo envía intenciones al servidor.

signal state_changed

var root: GameRoot
var server: MatchServer
var board: BoardView
var player: PlayerController
var hud: Hud
var color: int = ChessPiece.WHITE
var state := CheatArmState.new()
var panel: CheatPanel
## Trampas disponibles, en orden de tecla.
var defs: Array[CheatDef] = []


func setup(p_root: GameRoot, p_panel: CheatPanel) -> void:
	root = p_root
	server = p_root.server
	board = p_root.board_view
	player = p_root.player
	hud = p_root.hud
	color = p_root.human_color
	panel = p_panel
	for i in mini(server.config.cheats.size(), 4):
		defs.append(server.config.cheats[i])
	server.cheat_started.connect(func(c: int, _id: StringName, _f: int, _t: int, _d: float) -> void:
		if c == color:
			_refresh())
	server.cheat_finished.connect(func(c: int, _id: StringName, _f: int, _t: int) -> void:
		if c == color:
			_refresh())
	server.cheat_aborted.connect(func(c: int, _id: StringName) -> void:
		if c == color:
			_refresh())
	server.game_over.connect(func(_w: int, _r: String) -> void:
		cancel()
		_refresh())
	_refresh()


func armed_def() -> CheatDef:
	return defs[state.index] if state.index >= 0 and state.index < defs.size() else null


## Arma la trampa `i` (desde la tecla o desde pruebas). Si ya estaba armada la desarma.
func arm(i: int) -> void:
	if i < 0 or i >= defs.size() or not _can_act():
		return
	if not state.is_armed() and (server.is_hand_busy(color) or _animator_busy()):
		hud.show_subtitle("...my hand is busy")
		return
	state.toggle(i)
	_clear_marks()
	_refresh()


func cancel() -> void:
	if state.is_armed():
		state.cancel()
		_clear_marks()
		_refresh()


func _can_act() -> bool:
	return server.started and not server.is_over()


func _animator_busy() -> bool:
	var a: HandAnimator = root.animators[color]
	return a != null and a.is_busy()


func _unhandled_input(event: InputEvent) -> void:
	if server == null or not _can_act():
		return
	for i in 4:
		if event.is_action_pressed("cheat_%d" % (i + 1)):
			arm(i)
			return
	if event.is_action_pressed("cheat_abort"):
		if server.abort_cheat(color):
			hud.show_subtitle("...better not")
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		return
	if event is InputEventMouseButton and event.pressed and state.is_armed():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			state.back()
			_clear_marks()
			_show_targets()
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and player.is_mouse_captured():
			get_viewport().set_input_as_handled()
			click_square(player.pick_square())


func _process(_delta: float) -> void:
	if server == null:
		return
	if state.is_armed() and not _can_act():
		cancel()
	if state.is_armed() and player.is_mouse_captured():
		board.set_hover(player.pick_square())


## Procesa un clic sobre una casilla con la trampa armada (público para pruebas).
func click_square(sq: int) -> void:
	var def := armed_def()
	if def == null:
		return
	if _animator_busy() or server.is_hand_busy(color):
		_reject("your hand is busy")
		return
	var r := state.on_square(sq, server.board, color, def)
	match r.action:
		"select", "back":
			_clear_marks()
			_show_targets()
		"reject":
			_reject(r.reason)
		"execute":
			_clear_marks()
			var res := server.start_cheat(color, def.id, r.from, r.to)
			if not res.ok:
				_reject(res.reason)
	_refresh()


func _reject(reason: String) -> void:
	hud.show_subtitle("...no, not that: %s" % CheatTargeting.visible_reason(reason), 2.5)


func _show_targets() -> void:
	if state.phase != CheatArmState.Phase.PIECE:
		return
	var marks: Array = []
	for t in state.targets:
		marks.append({"sq": t, "capture": false})
	board.set_highlights(state.from, marks)


func _clear_marks() -> void:
	board.clear_highlights()


func _refresh() -> void:
	if panel == null:
		return
	var text := ""
	if server.is_hand_busy(color):
		text = "X: abort"
	elif state.phase == CheatArmState.Phase.ARMED:
		var def := armed_def()
		var enemy := def.kind == CheatDef.Kind.STEAL or def.kind == CheatDef.Kind.MOVE_ENEMY
		text = "Pick %s\n%s" % ["an enemy piece" if enemy else "one of your pieces", def.description]
	elif state.phase == CheatArmState.Phase.PIECE:
		text = "Pick the destination\n(right click: back)"
	panel.set_state(state.index, text)
	state_changed.emit()
