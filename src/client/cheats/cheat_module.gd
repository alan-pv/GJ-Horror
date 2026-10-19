class_name CheatModule
extends Node
## Módulo de gameplay "trampas y árbitro" (Hito 2A). `GameRoot` lo instancia y
## llama a `install`. Conecta las señales de trampas del servidor con las
## animaciones de AMBAS manos, crea la entrada del jugador (teclas 1-4), el
## panel de trampas y el árbitro. No decide nada: solo dibuja lo que el
## servidor confirma.
##
## Depuración (argumentos tras `--`):
##   --cheat-demo=NOMBRE   guion automático de trampas: steal, slide, nudge,
##                         move, abort, accuse o all (ver `_demo_steps`).
##                         Conviene `--fen=...` con líneas abiertas y `--human=white`.

signal installed

var root: GameRoot
var server: MatchServer
var input: CheatInput
var panel: CheatPanel
var arbiter: Arbiter

var _demo: Array[Dictionary] = []
var _demo_time: float = 0.0
var _verify_wait: float = 0.0
var _verified: bool = false


func install(p_root: GameRoot) -> void:
	root = p_root
	server = root.server
	name = "ModuloTrampas"

	server.cheat_started.connect(_on_cheat_started)
	server.cheat_finished.connect(_on_cheat_finished)
	server.cheat_aborted.connect(_on_cheat_aborted)
	for a in root.animators:
		a.job_done.connect(_on_job_done)

	arbiter = Arbiter.new()
	root.add_child(arbiter)
	arbiter.setup(root)
	root.arbiter = arbiter

	if not root.get_args().has("autoplay"):
		panel = CheatPanel.new()
		panel.name = "PanelTrampas"
		add_child(panel)
		var names: Array[String] = []
		for def in server.config.cheats.slice(0, 4):
			names.append(def.display_name)
		panel.setup(names)
		input = CheatInput.new()
		input.name = "EntradaTrampas"
		add_child(input)
		input.setup(root, panel)

	var demo := str(root.get_args().get("cheat-demo", ""))
	if demo != "":
		_demo = _demo_steps(demo)
	installed.emit()


# --- Señales del servidor ---------------------------------------------------------------

func _on_cheat_started(color: int, cheat_id: StringName, from: int, to: int, duration: float) -> void:
	var def := server.get_cheat(cheat_id)
	if def == null:
		return
	root.animators[color].enqueue_cheat(def.kind, from, to, duration)


func _on_cheat_finished(color: int, _cheat_id: StringName, _from: int, to: int) -> void:
	var offset := server.board.offsets[to] if to >= 0 else Vector2.ZERO
	root.animators[color].resolve_cheat(true, offset)


func _on_cheat_aborted(color: int, _cheat_id: StringName) -> void:
	root.animators[color].resolve_cheat(false)


## Al terminar el gesto la vista se reconcilia con el tablero físico del servidor
## (piezas exactamente donde dice, con su descentrado: es la evidencia).
func _on_job_done(kind: String) -> void:
	if kind == "cheat":
		root.board_view.sync(server.board)


# --- Guion de demostración -------------------------------------------------------------

func _process(delta: float) -> void:
	if not server.started:
		return
	if _demo.is_empty():
		_verify_demo(delta)
		return
	_demo_time += delta
	while not _demo.is_empty() and _demo_time >= float(_demo[0].t):
		_run_step(_demo.pop_front())
	_verify_wait = 0.0


## Tras el guion, cuando las manos descansan, comprueba que la vista coincida con el servidor.
func _verify_demo(delta: float) -> void:
	if not root.get_args().has("cheat-demo") or _verified:
		return
	for a in root.animators:
		if a.is_busy():
			_verify_wait = 0.0
			return
	_verify_wait += delta
	if _verify_wait < 1.0:
		return
	_verified = true
	var bad := 0
	for sq in 64:
		var node: Node3D = root.board_view.pieces.get(sq)
		var code := server.board.squares[sq]
		if (node == null) != (code == ChessPiece.NONE):
			bad += 1
		elif node != null:
			var want := root.board_view.square_to_world(sq, true, server.board.offsets[sq])
			if int(node.get_meta("code")) != code or node.global_position.distance_to(want) > 0.002:
				bad += 1
	print("[trampas] vista == servidor: %s (casillas distintas: %d, mano.carga=%s)" % [bad == 0, bad, root.animators.map(func(a: HandAnimator) -> bool: return a.rig.carried != null)])


func _run_step(s: Dictionary) -> void:
	var color: int = root.human_color if s.get("who", "human") == "human" else root.rival_color
	match s.kind:
		"cheat":
			var r := server.start_cheat(color, s.id, ChessPiece.square_from_name(s.from), ChessPiece.square_from_name(s.get("to", "a1")) if s.has("to") else -1)
			print("[trampas %.1f] %s %s %s->%s: %s %s" % [_demo_time, s.who, s.id, s.from, s.get("to", "-"), "ok" if r.ok else "RECHAZADA", r.reason])
		"abort":
			print("[trampas %.1f] %s aborta: %s" % [_demo_time, s.who, server.abort_cheat(color)])
		"arm":
			if input != null:
				input.arm(int(s.idx))
		"click":
			if input != null:
				input.click_square(ChessPiece.square_from_name(s.sq))
				print("[trampas %.1f] clic en %s (fase %d)" % [_demo_time, s.sq, input.state.phase])
		"accuse":
			var r := server.accuse(color)
			print("[trampas %.1f] %s acusa: %s %s" % [_demo_time, s.who, r.ok, r.reason])


## Guiones por nombre (el humano debe ser blancas). Tiempos en segundos desde el inicio.
func _demo_steps(name_: String) -> Array[Dictionary]:
	var steal := {"t": 1.0, "who": "human", "kind": "cheat", "id": &"steal", "from": "a7"}
	var slide := {"t": 1.0, "who": "rival", "kind": "cheat", "id": &"slide", "from": "a8", "to": "d8"}
	var nudge := {"t": 1.0, "who": "human", "kind": "cheat", "id": &"nudge", "from": "h2", "to": "h3"}
	var move := {"t": 1.0, "who": "human", "kind": "cheat", "id": &"move_enemy", "from": "c6", "to": "b4"}
	match name_:
		"steal":
			return [steal]
		"slide":
			return [slide]
		"nudge":
			return [nudge]
		"move":
			return [move]
		"abort":
			return [move, {"t": 1.7, "who": "human", "kind": "abort"}]
		"accuse":
			return [slide, {"t": 3.6, "who": "human", "kind": "accuse"}]
		"both":
			return [steal, slide]
		"input":
			# Recorre la entrada del jugador: armar, elegir pieza y destino.
			return [
				{"t": 1.0, "kind": "arm", "idx": 2},
				{"t": 1.1, "kind": "click", "sq": "a7"},
				{"t": 3.5, "kind": "arm", "idx": 3},
				{"t": 3.6, "kind": "click", "sq": "a2"},
				{"t": 3.7, "kind": "click", "sq": "c6"},
				{"t": 3.8, "kind": "click", "sq": "b4"},
			]
	# all: todo en secuencia, con las dos manos coincidiendo al principio.
	var out: Array[Dictionary] = [steal, slide]
	var n := nudge.duplicate()
	n.t = 4.5
	out.append(n)
	var m := move.duplicate()
	m.t = 6.0
	out.append(m)
	var m2 := {"t": 9.5, "who": "human", "kind": "cheat", "id": &"move_enemy", "from": "e6", "to": "f5"}
	out.append(m2)
	out.append({"t": 10.4, "who": "human", "kind": "abort"})
	return out
