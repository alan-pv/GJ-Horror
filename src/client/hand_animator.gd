class_name HandAnimator
extends Node
## Secuencias de la mano con `await`, una función por fase: alcanzar, agarrar,
## trasladar, soltar, volver y golpear el reloj. Es PURAMENTE visual: la
## jugada ya está registrada en el servidor. Una cola por mano ejecuta las
## jugadas en orden, y el tablero impide que dos manos se muevan a la vez.
##
## Casos: jugada normal, captura (primero la pieza rival va a la pila),
## enroque (rey y luego torre) y coronación (se cambia la pieza al llegar).
## Variación humana: velocidad distinta en cada jugada, más rápida con estrés,
## y el temblor del `HandRig` crece con el estrés.
##
## Trampas: `enqueue_cheat` pone en cola un movimiento propio de cada trampa
## (empujón, arrastre, robo, pieza enemiga) con la duración que dicta el
## servidor. No pide el cerrojo de movimiento (las trampas pueden coincidir
## con la jugada de la otra mano) y espera a `resolve_cheat` para soltar la
## pieza con el descentrado definitivo, o para deshacer el gesto si se aborta.

signal phase_changed(phase: StringName)
signal idle
## Se emite al terminar cada animación de la cola (jugada o titubeo).
signal job_done(kind: String)

## Holgura sobre la pieza más alta (rey) al trasladar.
const CARRY_CLEARANCE := 0.02
const KING_HEIGHT := 0.095
## Escala global de velocidad de las animaciones.
const SPEED := 1.3

var rig: HandRig
var board: BoardView
var clock: ClockView
var color: int = ChessPiece.WHITE
## Pose de reposo del punto de pinza (mundo).
var rest_grip: Vector3 = Vector3.ZERO
var rest_pitch: float = 40.0
## Fase actual: idle, reach, grab, carry, release, press, return, hesitate.
var phase: StringName = &"idle"

var _queue: Array[Dictionary] = []
var _running: bool = false
var _job_speed: float = 1.0
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _current_job: Dictionary = {}


func setup(p_rig: HandRig, p_board: BoardView, p_clock: ClockView, p_color: int, p_rest_grip: Vector3) -> void:
	rig = p_rig
	board = p_board
	clock = p_clock
	color = p_color
	rest_grip = p_rest_grip
	_rng.randomize()
	rig.set_grip(rest_grip, rest_pitch)


func is_busy() -> bool:
	return _running or not _queue.is_empty()


## Pone en cola la animación de una jugada ya registrada. `info` es el que
## emite `MatchServer.move_made` (captura, enroque).
func enqueue_move(uci: String, info: Dictionary) -> void:
	_push({"kind": "move", "uci": uci, "info": info})


## La mano se acerca a la pieza y se detiene (jugada bloqueada por el aviso).
func enqueue_hesitate(uci: String) -> void:
	_push({"kind": "hesitate", "uci": uci})


func _process(delta: float) -> void:
	_clock += delta


## Pone en cola el gesto de una trampa. `kind` es `CheatDef.Kind`; `to_sq` es -1
## en el robo. `duration` es la del servidor: el tablero cambia al terminar.
func enqueue_cheat(kind: int, from_sq: int, to_sq: int, duration: float) -> void:
	_push({
		"kind": "cheat", "cheat_kind": kind, "from": from_sq, "to": to_sq,
		"duration": duration, "deadline": _clock + duration,
		"resolved": false, "applied": false, "offset": Vector2.ZERO,
	})


## El servidor terminó (`applied`, con el descentrado final de la pieza) o abortó la trampa.
func resolve_cheat(applied: bool, offset: Vector2 = Vector2.ZERO) -> void:
	var job := _open_cheat_job()
	if job.is_empty():
		return
	job.resolved = true
	job.applied = applied
	job.offset = offset


func _open_cheat_job() -> Dictionary:
	if _current_job.get("kind", "") == "cheat" and not _current_job.resolved:
		return _current_job
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].kind == "cheat" and not _queue[i].resolved:
			return _queue[i]
	return {}


func _push(job: Dictionary) -> void:
	board.hold_sync()
	_queue.append(job)
	_pump()


func _pump() -> void:
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var is_cheat: bool = job.kind == "cheat"
		if not is_cheat:
			await board.acquire_motion()
		_current_job = job
		_job_speed = _rng.randf_range(0.85, 1.25)
		match job.kind:
			"move":
				await _run_move(job)
			"hesitate":
				await _run_hesitate(job)
			"cheat":
				await _run_cheat(job)
		_current_job = {}
		if not is_cheat:
			board.release_motion()
		board.release_sync()
		job_done.emit(job.kind)
	_running = false
	_set_phase(&"idle")
	idle.emit()


# --- Jugadas ------------------------------------------------------------------

func _run_move(job: Dictionary) -> void:
	var move := ChessMove.from_uci(job.uci)
	var info: Dictionary = job.info
	if move == null:
		return
	await _pause(_rng.randf_range(0.05, 0.25))
	# 1) Captura: la pieza rival sale primero hacia la pila propia.
	if int(info.get("capture_square", -1)) >= 0:
		await _carry(int(info.capture_square), -1, true)
	# 2) La pieza que se mueve.
	await _carry(move.from, move.to, false)
	# 3) Enroque: la torre.
	if int(info.get("rook_from", -1)) >= 0:
		await _carry(int(info.rook_from), int(info.rook_to), false)
	# 4) Coronación: se cambia la pieza al llegar.
	if move.promotion != 0:
		await _pause(0.12)
		board.replace_piece(move.to, ChessPiece.make(color, move.promotion))
		await _pause(0.15)
	# 5) Reloj y vuelta.
	await _press_clock()
	await _return_home()


func _run_hesitate(job: Dictionary) -> void:
	var move := ChessMove.from_uci(job.uci)
	if move == null:
		return
	var node: Node3D = board.pieces.get(move.from)
	if node == null:
		return
	var code := int(node.get_meta("code"))
	var grip := node.global_position + Vector3(0, PieceFactory.grip_height(code), 0)
	_set_phase(&"hesitate")
	await _move_to(grip + Vector3(0, 0.07, 0), _dur(0.5), 0.07)
	await _move_to(grip + Vector3(0, 0.025, 0), _dur(0.25), 0.0)
	await _pause(_rng.randf_range(0.9, 1.4))
	await _return_home()


## Lleva la pieza de `from_sq` a `to_sq`, o a la pila propia si `to_pile`.
func _carry(from_sq: int, to_sq: int, to_pile: bool) -> void:
	var node: Node3D = board.take_piece(from_sq)
	if node == null:
		push_warning("HandAnimator: no hay pieza visual en %s" % ChessPiece.square_name(from_sq))
		return
	var code := int(node.get_meta("code"))
	var gh := PieceFactory.grip_height(code)
	var grip_a := node.global_position + Vector3(0, gh, 0)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh

	# Alcanzar: arco alto desde donde esté la mano hasta sobre la pieza.
	_set_phase(&"reach")
	rig.set_pose(HandRig.Pose.OPEN, _dur(0.25))
	await _move_to(Vector3(grip_a.x, grip_a.y + 0.06, grip_a.z), _dur(0.6), 0.09, 58.0)
	# Agarrar: baja, cierra la pinza y sujeta.
	_set_phase(&"grab")
	await _move_to(grip_a, _dur(0.22), 0.0, 62.0)
	await rig.set_pose(HandRig.Pose.PINCH, _dur(0.14))
	rig.attach_piece(node, gh)
	await _pause(0.06)
	# Trasladar: sube recto hasta librar las piezas y cruza en arco.
	_set_phase(&"carry")
	await _move_to(Vector3(grip_a.x, clear_y, grip_a.z), _dur(0.28), 0.0, 58.0)
	var dest := Vector3.ZERO
	var drop_slot := Vector3.ZERO
	if to_pile:
		var n: int = board.piles[color].size()
		drop_slot = board.pile_slot(color, n)
		dest = drop_slot
	else:
		dest = board.square_to_world(to_sq)
	var above := Vector3(dest.x, clear_y, dest.z)
	await _move_to(above, _dur(0.55), 0.025, 58.0)
	await _move_to(Vector3(dest.x, dest.y + gh + 0.004, dest.z), _dur(0.3), 0.0, 62.0)
	# Soltar.
	_set_phase(&"release")
	var held := rig.release_piece()
	if to_pile:
		board.add_to_pile(held, color)
	else:
		board.put_piece(held, to_sq)
	await rig.set_pose(HandRig.Pose.OPEN, _dur(0.15))
	await _move_to(Vector3(dest.x, dest.y + gh + 0.07, dest.z), _dur(0.2), 0.0, 55.0)


# --- Trampas -------------------------------------------------------------------------

## Máximo que espera a que el servidor cierre la trampa (p. ej. si hay una acusación en curso).
const CHEAT_RESOLVE_TIMEOUT := 20.0
## Mínimo que dura el gesto aunque la trampa llegue tarde a la cola.
const CHEAT_MIN_TIME := 0.5


func _run_cheat(job: Dictionary) -> void:
	# Si ya fue abortada antes de empezar, no hay gesto.
	if job.resolved and not job.applied:
		return
	# El gesto debe acabar cuando el servidor aplica el cambio: se ajusta al tiempo que queda.
	var total := maxf(job.deadline - _clock, CHEAT_MIN_TIME)
	var ok := false
	match int(job.cheat_kind):
		CheatDef.Kind.NUDGE:
			ok = await _cheat_nudge(job, total)
		CheatDef.Kind.SLIDE:
			ok = await _cheat_drag(job, total, false)
		CheatDef.Kind.MOVE_ENEMY:
			ok = await _cheat_drag(job, total, true)
		CheatDef.Kind.STEAL:
			ok = await _cheat_steal(job, total)
	# Regreso visible, con el puño cerrado si se llevó una pieza.
	var fist: bool = ok and int(job.cheat_kind) == CheatDef.Kind.STEAL
	await _return_home_cheat(fist)


## Empujoncito: la mano empuja la pieza una casilla, sin levantarla.
func _cheat_nudge(job: Dictionary, total: float) -> bool:
	var node: Node3D = board.take_piece(job.from)
	if node == null:
		return false
	var gh := PieceFactory.grip_height(int(node.get_meta("code")))
	var start := node.global_position
	var delta := board.square_to_world(job.to) - board.square_to_world(job.from)
	delta.y = 0.0
	var dir := delta.normalized()
	var contact := start + Vector3(0, gh * 0.7, 0) - dir * 0.02
	_set_phase(&"reach")
	rig.set_pose(HandRig.Pose.GRIP, 0.25)
	if not await _cmove(job, contact + Vector3(0, 0.07, 0) - dir * 0.02, total * 0.40, 0.08, 72.0):
		return _cheat_restore(node, job.from)
	if not await _cmove(job, contact, total * 0.12, 0.0, 78.0):
		return _cheat_restore(node, job.from)
	_set_phase(&"cheat")
	var step := func(t: float) -> void:
		node.global_position = start + delta * t
	if not await _cmove(job, contact + delta, total * 0.38, 0.0, 78.0, step):
		node.global_position = start
		return _cheat_restore(node, job.from)
	if not await _wait_resolved(job):
		node.global_position = start
		return _cheat_restore(node, job.from)
	board.put_piece(node, job.to, job.offset)
	await _cmove(null, contact + delta + Vector3(0, 0.06, 0), total * 0.10, 0.0, 70.0)
	return true


## Deslizar (arrastre bajo sobre el tablero) o mover pieza enemiga (se levanta y se lleva en arco).
func _cheat_drag(job: Dictionary, total: float, lifted: bool) -> bool:
	var node: Node3D = board.take_piece(job.from)
	if node == null:
		return false
	var gh := PieceFactory.grip_height(int(node.get_meta("code")))
	var grip_a := node.global_position + Vector3(0, gh, 0)
	var dest := board.square_to_world(job.to)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh
	_set_phase(&"reach")
	rig.set_pose(HandRig.Pose.OPEN, 0.2)
	if not await _cmove(job, grip_a + Vector3(0, 0.06, 0), total * 0.28, 0.08, 58.0):
		return _cheat_restore(node, job.from)
	_set_phase(&"grab")
	if not await _cmove(job, grip_a, total * 0.10, 0.0, 62.0):
		return _cheat_restore(node, job.from)
	rig.set_pose(HandRig.Pose.PINCH, 0.12)
	rig.attach_piece(node, gh)
	_set_phase(&"cheat")
	var drop_y := dest.y + gh + 0.004
	if lifted:
		if not await _cmove(job, Vector3(grip_a.x, clear_y, grip_a.z), total * 0.12, 0.0, 58.0):
			return await _cheat_return_piece(job)
		if not await _cmove(job, Vector3(dest.x, clear_y, dest.z), total * 0.30, 0.025, 58.0):
			return await _cheat_return_piece(job)
		if not await _cmove(job, Vector3(dest.x, drop_y, dest.z), total * 0.20, 0.0, 62.0):
			return await _cheat_return_piece(job)
	else:
		# Arrastre pegado a la mesa: la pieza apenas se despega.
		var low_a := Vector3(grip_a.x, grip_a.y + 0.006, grip_a.z)
		if not await _cmove(job, low_a, total * 0.05, 0.0, 62.0):
			return await _cheat_return_piece(job)
		if not await _cmove(job, Vector3(dest.x, drop_y + 0.004, dest.z), total * 0.52, 0.0, 62.0):
			return await _cheat_return_piece(job)
		if not await _cmove(job, Vector3(dest.x, drop_y, dest.z), total * 0.05, 0.0, 62.0):
			return await _cheat_return_piece(job)
	if not await _wait_resolved(job):
		return await _cheat_return_piece(job)
	var held := rig.release_piece()
	board.put_piece(held, job.to, job.offset)
	rig.set_pose(HandRig.Pose.OPEN, 0.12)
	await _cmove(null, Vector3(dest.x, dest.y + gh + 0.07, dest.z), total * 0.10, 0.0, 55.0)
	return true


## Robar: pinza, levanta y la lleva al regazo, fuera de la vista; la pieza queda escondida en la mano.
func _cheat_steal(job: Dictionary, total: float) -> bool:
	var node: Node3D = board.take_piece(job.from)
	if node == null:
		return false
	var gh := PieceFactory.grip_height(int(node.get_meta("code")))
	var grip_a := node.global_position + Vector3(0, gh, 0)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh
	var sgn := 1.0 if color == board.near_color else -1.0
	var lap := Vector3(0.12, BoardView.TABLE_TOP - 0.10, sgn * 0.52)
	var edge := Vector3(0.14, BoardView.TABLE_TOP + 0.05, sgn * 0.40)
	_set_phase(&"reach")
	rig.set_pose(HandRig.Pose.OPEN, 0.2)
	if not await _cmove(job, grip_a + Vector3(0, 0.06, 0), total * 0.28, 0.08, 58.0):
		return _cheat_restore(node, job.from)
	_set_phase(&"grab")
	if not await _cmove(job, grip_a, total * 0.10, 0.0, 62.0):
		return _cheat_restore(node, job.from)
	rig.set_pose(HandRig.Pose.PINCH, 0.12)
	rig.attach_piece(node, gh)
	_set_phase(&"cheat")
	if not await _cmove(job, Vector3(grip_a.x, clear_y, grip_a.z), total * 0.12, 0.0, 58.0):
		return await _cheat_return_piece(job)
	# Hacia el borde de la mesa y por debajo, al regazo.
	if not await _cmove(job, edge, total * 0.22, 0.03, 55.0):
		return await _cheat_return_piece(job)
	if not await _cmove(job, lap, total * 0.18, 0.0, 45.0):
		return await _cheat_return_piece(job)
	if not await _wait_resolved(job):
		return await _cheat_return_piece(job)
	# La pieza queda escondida en la mano: se cierra el puño y desaparece.
	var held := rig.release_piece()
	if held != null:
		held.queue_free()
	rig.set_pose(HandRig.Pose.GRIP, 0.12)
	return true


## Abortada con la pieza en el aire: vuelve a su casilla de origen.
func _cheat_return_piece(job: Dictionary) -> bool:
	if rig.carried == null:
		return false
	var gh := PieceFactory.grip_height(int(rig.carried.get_meta("code")))
	var home := board.square_to_world(job.from)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh
	# El gesto de regreso es corto para no alargar la trampa abortada.
	await _cmove(null, Vector3(home.x, clear_y, home.z), 0.35, 0.03, 58.0)
	await _cmove(null, Vector3(home.x, home.y + gh + 0.004, home.z), 0.18, 0.0, 62.0)
	_cheat_restore(rig.release_piece(), job.from)
	rig.set_pose(HandRig.Pose.OPEN, 0.12)
	await _cmove(null, Vector3(home.x, home.y + gh + 0.07, home.z), 0.15, 0.0, 55.0)
	return false


## Deja la pieza en su casilla de origen. Siempre devuelve false (trampa no consumada).
func _cheat_restore(node: Node3D, from_sq: int) -> bool:
	if node != null:
		board.put_piece(node, from_sq)
	return false


## Espera a que el servidor cierre la trampa. false si fue abortada (o nunca llegó).
func _wait_resolved(job: Dictionary) -> bool:
	var waited := 0.0
	while not job.resolved and waited < CHEAT_RESOLVE_TIMEOUT:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return job.resolved and job.applied


## Movimiento de la mano de una trampa con duración exacta (sin variación humana).
## `job` != null permite abortar: devuelve false en cuanto la trampa se cancela.
## `on_step` recibe el progreso suavizado 0..1 (para arrastrar la pieza sin sujetarla).
func _cmove(job: Variant, dest: Vector3, duration: float, lift: float = 0.0, pitch: float = -1.0, on_step: Callable = Callable()) -> bool:
	var start := rig.get_grip()
	var p0 := rig.get_pitch_deg()
	var p1 := p0 if pitch < 0.0 else pitch
	var delta := dest - start
	var c1 := start + Vector3.UP * lift + delta * 0.25
	var c2 := dest + Vector3.UP * lift - delta * 0.25
	var t := 0.0
	var dur := maxf(duration, 0.03)
	while t < 1.0:
		if job != null and job.resolved and not job.applied:
			return false
		var k := smoothstep(0.0, 1.0, t)
		rig.set_grip(start.bezier_interpolate(c1, c2, dest, k), lerpf(p0, p1, k))
		if on_step.is_valid():
			on_step.call(k)
		await get_tree().process_frame
		t += get_process_delta_time() / dur
	rig.set_grip(dest, p1)
	if on_step.is_valid():
		on_step.call(1.0)
	return job == null or not (job.resolved and not job.applied)


func _return_home_cheat(fist: bool) -> void:
	_set_phase(&"return")
	rig.set_pose(HandRig.Pose.GRIP if fist else HandRig.Pose.OPEN, 0.2)
	await _cmove(null, rest_grip, 0.6, 0.05, rest_pitch)
	rig.set_pose(HandRig.Pose.OPEN, 0.25)


func _press_clock() -> void:
	if clock == null:
		return
	_set_phase(&"press")
	var top := clock.button_top_world(color)
	rig.set_pose(HandRig.Pose.GRIP, _dur(0.2))
	await _move_to(top + Vector3(0, 0.07, 0), _dur(0.45), 0.06, 70.0)
	await _move_to(top + Vector3(0, 0.004, 0), _dur(0.16), 0.0, 75.0)
	clock.press_button(color)
	await _pause(0.12)
	await _move_to(top + Vector3(0, 0.06, 0), _dur(0.2), 0.0, 70.0)


func _return_home() -> void:
	_set_phase(&"return")
	rig.set_pose(HandRig.Pose.OPEN, _dur(0.3))
	await _move_to(rest_grip, _dur(0.55), 0.05, rest_pitch)


# --- Movimiento -----------------------------------------------------------------

## Mueve el punto de pinza por un arco de Bézier (ver `Vector3.bezier_interpolate`)
## con `lift` metros extra de altura en los puntos de control.
func _move_to(dest: Vector3, duration: float, lift: float = 0.0, pitch: float = -1.0) -> void:
	var start := rig.get_grip()
	var p0 := rig.get_pitch_deg()
	var p1 := p0 if pitch < 0.0 else pitch
	var delta := dest - start
	var c1 := start + Vector3.UP * lift + delta * 0.25
	var c2 := dest + Vector3.UP * lift - delta * 0.25
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		rig.set_grip(start.bezier_interpolate(c1, c2, dest, t), lerpf(p0, p1, t)), 0.0, 1.0, maxf(duration, 0.02)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Duración con la variación humana de la jugada, la prisa del estrés y la
## prisa por ponerse al día si hay animaciones atrasadas en cola.
func _dur(base: float) -> float:
	var backlog := 1.0 + 0.7 * maxi(board.pending_jobs() - 1, 0)
	return base * _job_speed * lerpf(1.0, 0.6, clampf(rig.stress, 0.0, 1.0)) / (SPEED * backlog)


func _set_phase(p: StringName) -> void:
	if phase != p:
		phase = p
		phase_changed.emit(p)
