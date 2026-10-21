class_name CheatModule
extends Node
## Módulo de gameplay "trampas y árbitro" (Hito 2A). `GameRoot` lo instancia y
## llama a `install`. Conecta las señales de trampas del servidor con las
## animaciones de AMBAS manos (humano y bots). La entrada del jugador vive en
## `PlayerController`/`PieceInteraction`. (El árbitro lo crea `ArbiterModule`.)
## No decide nada: solo dibuja lo que el servidor confirma. Si la trampa fue la
## jugada del turno (`awaiting_press`), la mano va después a pulsar el reloj.
##
## Depuración (argumentos tras `--`):
##   --cheat-demo=NOMBRE   guion automático de trampas: own, ownlong, enemy, steal, abort,
##                         rival (solo la trampa del rival), accuse, asmove, input o all (ver `_demo_steps`).
##                         Usar `--human=white` y `--fen="r3k3/p7/2n1p3/8/8/8/PPPP1PPP/R3K2R w - - 0 1"`.

signal installed

const TO_PILE := CheatRules.TO_PILE

var root: GameRoot
var server: MatchServer

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
	# Trampa-jugada: el turno ya pasó en el servidor y falta pulsar el reloj.
	if server.awaiting_press(color):
		root.animators[color].enqueue_press()


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
	# Las pilas de capturas (también las de robos) deben coincidir con las del servidor.
	for c in 2:
		var pile: Array = root.board_view.piles[c]
		if pile.size() != server.board.captured[c].size():
			bad += 1
	print("[trampas] vista == servidor: %s (casillas distintas: %d, mano.carga=%s)" % [bad == 0, bad, root.animators.map(func(a: HandAnimator) -> bool: return a.rig.carried != null)])


func _run_step(s: Dictionary) -> void:
	var color: int = root.human_color if s.get("who", "human") == "human" else root.rival_color
	match s.kind:
		"cheat":
			var to: int = TO_PILE if s.get("to", "") == "pile" else ChessPiece.square_from_name(s.to)
			var r := server.start_cheat(color, ChessPiece.square_from_name(s.from), to)
			print("[trampas %.1f] %s %s->%s: %s %s (clase %s, nivel %d, jugada %s)" % [_demo_time, s.who, s.from, s.to, "ok" if r.ok else "RECHAZADA", r.reason, r.kind_id, r.level, r.as_move])
		"abort":
			print("[trampas %.1f] %s aborta: %s" % [_demo_time, s.who, server.abort_cheat(color)])
		"click":
			# Entrada del jugador: "pile" es la zona de la pila propia.
			var t: int = TO_PILE if s.sq == "pile" else ChessPiece.square_from_name(s.sq)
			var action := root.player.interaction.click(t)
			print("[trampas %.1f] clic en %s: %s" % [_demo_time, s.sq, action])
		"accuse":
			var r := server.accuse(color)
			print("[trampas %.1f] %s acusa: %s %s" % [_demo_time, s.who, r.ok, r.reason])


## Guiones por nombre (el humano debe ser blancas y empezar en la FEN recomendada: blancas
## mueven). Tiempos en segundos desde el inicio.
func _demo_steps(name_: String) -> Array[Dictionary]:
	# Propia corta (a distancia 1, en tu turno: es tu jugada) y larga (en arco).
	var own := {"t": 1.0, "who": "human", "kind": "cheat", "from": "d2", "to": "e3"}
	var own_long := {"t": 1.0, "who": "human", "kind": "cheat", "from": "a1", "to": "a4"}
	var enemy := {"t": 1.0, "who": "human", "kind": "cheat", "from": "e6", "to": "e5"}
	var enemy_far := {"t": 1.0, "who": "human", "kind": "cheat", "from": "c6", "to": "b4"}
	var steal := {"t": 1.0, "who": "human", "kind": "cheat", "from": "a7", "to": "pile"}
	# El rival mueve una pieza propia fuera de su turno (no es jugada).
	var rival_own := {"t": 1.0, "who": "rival", "kind": "cheat", "from": "a8", "to": "d8"}
	match name_:
		"own":
			return [own]
		"ownlong", "asmove":
			return [own_long]
		"enemy":
			return [enemy, {"t": 3.5, "who": "human", "kind": "cheat", "from": "c6", "to": "a5"}]
		"steal":
			return [steal]
		"abort":
			return [enemy_far, {"t": 1.7, "who": "human", "kind": "abort"}]
		"rival":
			return [rival_own]
		"accuse":
			return [rival_own, {"t": 3.6, "who": "human", "kind": "accuse"}]
		"input":
			# Recorre la entrada del jugador: rey propio (se elige y se cambia), pieza rival a la pila, pieza propia a destino legal.
			return [
				{"t": 1.0, "kind": "click", "sq": "e1"},
				{"t": 1.2, "kind": "click", "sq": "a7"},
				{"t": 1.4, "kind": "click", "sq": "pile"},
				{"t": 4.5, "kind": "click", "sq": "d2"},
				{"t": 4.6, "kind": "click", "sq": "d4"},
			]
	# all: todo en secuencia; la última es una jugada hecha con trampa (pasa el turno).
	var out: Array[Dictionary] = [steal, rival_own]
	var e1 := enemy.duplicate()
	e1.t = 3.2
	out.append(e1)
	var e2 := enemy_far.duplicate()
	e2.t = 5.2
	out.append(e2)
	out.append({"t": 5.9, "who": "human", "kind": "abort"})
	var e3 := {"t": 7.0, "who": "human", "kind": "cheat", "from": "c6", "to": "a5"}
	out.append(e3)
	var o := own_long.duplicate()
	o.t = 9.6
	out.append(o)
	return out
