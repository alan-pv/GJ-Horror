class_name HandAnimator
extends Node
## Secuencias de la mano con `await`, una función por fase: alcanzar, agarrar,
## trasladar, soltar, golpear el reloj, escribir en la planilla y volver. Es PURAMENTE
## visual: la jugada ya está registrada en el servidor (el turno solo pasa cuando la mano
## golpea el reloj: señal `clock_hit`). Una cola por mano ejecuta las jugadas en orden, y el
## tablero impide que dos manos se muevan a la vez.
##
## Cada jugada es: MOVER la pieza y PULSAR el reloj (trabajo "move"), y después ANOTAR en la
## planilla con la pluma (~2 s) en un trabajo aparte ("write") que no toca piezas: no toma el
## cerrojo de movimiento y se interrumpe si llega una jugada o una trampa (la entrada sigue
## pendiente y se retoma después).
##
## Movimiento: cada gesto es UNA curva suave (Catmull-Rom centrípeta por puntos de paso,
## `_flow`) recorrida por longitud de arco con perfil de mínimo jerk; la mano solo se detiene
## donde hay contacto real (pieza, reloj, pluma). La aproximación final es lenta y vertical, la
## salida rápida, y los dedos se abren y cierran antes del contacto.
## La mano mueve el brazo del personaje (`HandRig`, IK); en reposo el antebrazo queda apoyado en
## la mesa, junto al tablero (`rest_grip`), para no tapar las piezas. (Las animaciones de
## sentado dejan las manos sobre el propio tablero, por eso el reposo también va por IK.)
## La planilla se puede escribir con la OTRA mano (`write_rig`, p. ej. el rival escribe con la
## derecha y pulsa el reloj con la izquierda).
##
## Casos: jugada normal, captura (primero la pieza rival va a la pila),
## enroque (rey y luego torre) y coronación (se cambia la pieza al llegar).
## Variación humana: velocidad distinta en cada jugada, más rápida con estrés,
## y el temblor del `HandRig` crece con el estrés.
##
## Trampas: `enqueue_cheat` pone en cola el gesto de cada clase (pieza propia o rival a distancia
## 1: empujón sin levantarla; a distancia 2 o más: se levanta y se lleva en arco; robo: pinza,
## levanta y la deja en la pila propia) con la duración que dicta el
## servidor. Si la trampa fue la jugada del turno, `enqueue_press` encola la pulsación del reloj. No pide el cerrojo de movimiento (las trampas pueden coincidir
## con la jugada de la otra mano) y espera a `resolve_cheat` para soltar la
## pieza con el descentrado definitivo, o para deshacer el gesto si se aborta.

signal phase_changed(phase: StringName)
signal idle
## La mano golpeó el botón del reloj: quien escucha llama a `MatchServer.press_clock(color)`.
signal clock_hit(color: int)
## Se emite al terminar cada animación de la cola (jugada o titubeo).
signal job_done(kind: String)

## Holgura sobre la pieza más alta (rey) al trasladar.
const CARRY_CLEARANCE := 0.02
const KING_HEIGHT := 0.095
## Escala global de velocidad de las animaciones.
const SPEED := 1.3
## Muestras por tramo de la curva de un gesto.
const FLOW_STEPS := 10
## Peso de velocidad de los trazos de escritura (pequeños y lentos frente al resto del gesto).
const WRITE_STROKE_WEIGHT := 0.1
## Duración del gesto rápido con que se deja la pluma al interrumpir la escritura.
const WRITE_ABORT_TIME := 0.25
## Postura de la mano derecha al escribir (pitch y giro, grados); en la izquierda el giro se invierte.
const WRITE_PITCH := 10.0
const WRITE_ROLL := 50.0
## Cuánto se desliza la mano a lo largo del renglón (m): los trazos salen de los dedos, no del brazo.
const WRITE_SLIDE := 0.025
## Valor de `roll` de `_wp` que significa "sin giro pedido".
const NO_ROLL := -1000.0

var rig: HandRig
## Mano que escribe en la planilla (por defecto la misma `rig`).
var write_rig: HandRig
var board: BoardView
var clock: ClockView
## Planillas de la mesa (opcional): si existe, tras pulsar el reloj la mano anota la jugada.
var sheet: ScoresheetView
var color: int = ChessPiece.WHITE
## Pose de reposo del punto de pinza (mundo).
var rest_grip: Vector3 = Vector3.ZERO
var rest_pitch: float = 20.0
var write_rest_grip: Vector3 = Vector3.ZERO
var write_rest_pitch: float = 25.0
## Fase actual: idle, reach, grab, carry, release, press, return, hesitate.
var phase: StringName = &"idle"

var _queue: Array[Dictionary] = []
var _running: bool = false
## Cola y estado de la escritura cuando se hace con la OTRA mano (`write_rig != rig`): corre en
## paralelo a la cola de acciones, sin interrumpirse por jugadas ni trampas.
var _wqueue: Array[Dictionary] = []
var _writing: bool = false
var _job_speed: float = 1.0
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _current_job: Dictionary = {}
## Mano que se está moviendo ahora (`rig` o `write_rig`).
var _cur: HandRig
## true si la mano acaba de tocar algo: el gesto siguiente empieza subiendo (`_lift_wps`).
var _at_contact: bool = false


func setup(p_rig: HandRig, p_board: BoardView, p_clock: ClockView, p_color: int, p_rest_grip: Vector3) -> void:
	rig = p_rig
	board = p_board
	clock = p_clock
	color = p_color
	rest_grip = p_rest_grip
	_rng.randomize()
	write_rig = rig
	_cur = rig
	rig.set_grip(rest_grip, rest_pitch)
	rig.set_active(true, 0.0)


## Hace que `r` (la otra mano de la figura) escriba en la planilla; descansa en `rest`.
func set_write_rig(r: HandRig, rest: Vector3) -> void:
	write_rig = r
	if r != rig:
		write_rest_grip = rest
		write_rest_pitch = rest_pitch
		r.rest_at(rest, rest_pitch)


func is_busy() -> bool:
	return _running or not _queue.is_empty() or _writing or not _wqueue.is_empty()


## ¿Se escribe con la otra mano? Entonces la anotación va en paralelo a jugadas y trampas.
func _parallel_write() -> bool:
	return write_rig != null and write_rig != rig


## ¿La anotación va a la cola paralela de la otra mano?
func _goes_to_write_queue(job: Dictionary) -> bool:
	return job.kind == "write" and _parallel_write()


## ¿Debe la escritura dejar la pluma ahora? Solo si hay una acción en espera y escribe la misma
## mano que actúa (con la otra mano nunca hace falta el mismo brazo).
func _write_should_abort() -> bool:
	return not _parallel_write() and _action_waiting()


## Como `is_busy`, pero ignora la anotación en la planilla: la escritura se interrumpe sola
## cuando llega una jugada o una trampa, así que el humano puede actuar mientras escribe.
func is_busy_for_action() -> bool:
	if _running and not _current_job.is_empty() and _current_job.kind != "write":
		return true
	return _action_waiting()


## Hay en cola un trabajo que no es de escritura (interrumpe la pluma).
func _action_waiting() -> bool:
	for j in _queue:
		if j.kind != "write":
			return true
	return false


## Pone en cola la animación de una jugada ya registrada. `info` es el que
## emite `MatchServer.move_made` (captura, enroque).
func enqueue_move(uci: String, info: Dictionary) -> void:
	_push({"kind": "move", "uci": uci, "info": info})


## La mano se acerca a la pieza y se detiene (jugada bloqueada por el aviso).
func enqueue_hesitate(uci: String) -> void:
	_push({"kind": "hesitate", "uci": uci})


func _process(delta: float) -> void:
	_clock += delta
	if _parallel_write():
		write_rig.stress = rig.stress
		# Con las dos manos a la vez, el tronco lo sigue la que juega; si no, la que escribe.
		if _writing:
			rig.drives_posture = _running
			write_rig.drives_posture = not _running


## Pone en cola el gesto de una trampa. `kind` es `CheatDef.Kind`; `to_sq` es
## `CheatRules.TO_PILE` en el robo. `duration` es la del servidor: el tablero cambia al terminar.
func enqueue_cheat(kind: int, from_sq: int, to_sq: int, duration: float) -> void:
	var dist := CheatRules.king_distance(from_sq, to_sq) if to_sq >= 0 else 0
	_push({
		"kind": "cheat", "cheat_kind": kind, "from": from_sq, "to": to_sq, "distance": dist,
		"duration": duration, "deadline": _clock + duration,
		"resolved": false, "applied": false, "offset": Vector2.ZERO,
	})


## Encola solo la pulsación del reloj (tras una trampa que fue la jugada del turno): la mano pulsa
## y vuelve al reposo, sin escribir en la planilla (no hay SAN que anotar).
func enqueue_press() -> void:
	_push({"kind": "press"})


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
	if _goes_to_write_queue(job):
		# La otra mano escribe: su propia cola, sin esperar ni interrumpir a la de acciones.
		_wqueue.append(job)
		_pump_write()
		return
	if job.kind != "write":
		board.hold_sync()
	_queue.append(job)
	_pump()


func _pump() -> void:
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		# Si la escena se recargó, se abandona la cola (los nodos ya no existen).
		if not is_inside_tree() or not is_instance_valid(board):
			_queue.clear()
			break
		var job: Dictionary = _queue.pop_front()
		# Una anotación nunca pasa por delante de una jugada o trampa en espera.
		if job.kind == "write" and _action_waiting():
			_queue.append(job)
			continue
		var is_cheat: bool = job.kind == "cheat"
		var is_write: bool = job.kind == "write"
		# Las trampas, la escritura y la pulsación suelta no mueven piezas: no piden el cerrojo.
		var locks: bool = not (is_cheat or is_write or job.kind == "press")
		_current_job = job
		if locks:
			await board.acquire_motion()
			if not is_inside_tree():
				_queue.clear()
				break
		_current_job = job
		_cur = rig
		_job_speed = _rng.randf_range(0.85, 1.25)
		match job.kind:
			"move":
				await _run_move(job)
			"hesitate":
				await _run_hesitate(job)
			"write":
				await _run_write(job)
			"press":
				await _run_press()
			"cheat":
				await _run_cheat(job)
		_current_job = {}
		if not is_inside_tree() or not is_instance_valid(board):
			_queue.clear()
			break
		if locks:
			board.release_motion()
		if not is_write:
			board.release_sync()
		job_done.emit(job.kind)
	_running = false
	if not is_inside_tree():
		return
	if _writing:
		_set_phase(&"write")
		return
	_set_phase(&"idle")
	idle.emit()


## Cola de escritura de la mano libre (rival): anota una a una sin tocar el cerrojo de movimiento
## ni el estado de la cola de acciones; al acabar deja el tronco al cuidado de la mano que juega.
func _pump_write() -> void:
	if _writing:
		return
	_writing = true
	while not _wqueue.is_empty():
		if not is_inside_tree() or not is_instance_valid(board):
			_wqueue.clear()
			break
		var job: Dictionary = _wqueue.pop_front()
		await _run_write(job)
		if not is_inside_tree() or not is_instance_valid(board):
			_wqueue.clear()
			break
		job_done.emit(job.kind)
	_writing = false
	if not is_inside_tree():
		return
	if write_rig != null:
		write_rig.drives_posture = false
	rig.drives_posture = true
	if not _running:
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
	# 5) Reloj. La anotación es un trabajo aparte ("write"): no toca piezas, así que no retiene
	# el cerrojo de movimiento y se puede interrumpir con una jugada o una trampa.
	await _press_clock()
	if sheet != null and sheet.has_pending(color):
		if _parallel_write():
			# La otra mano escribe a la vez: la anotación arranca ya y la del reloj se retira.
			_push({"kind": "write"})
			await _return_home()
		else:
			_push({"kind": "write"})
	else:
		await _return_home()


## Pulsación suelta del reloj (tras una trampa-jugada): va al botón, pulsa y vuelve al reposo.
func _run_press() -> void:
	await _pause(_rng.randf_range(0.05, 0.2))
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
	rig.begin_grasp(node)
	var wps := _lift_wps(rig)
	wps.append(_wp(grip + Vector3(0, 0.09, 0), 58.0))
	wps.append(_wp(grip + Vector3(0, 0.025, 0), 60.0, 0.5))
	await _flow(rig, wps, _dur(0.75), {"fitts": true, "events": [_ev(0.05, func() -> void: rig.set_pose(HandRig.Pose.OPEN, _dur(0.25)))]})
	await _pause(_rng.randf_range(0.9, 1.4))
	rig.end_grasp()
	await _return_home()


## Lleva la pieza de `from_sq` a `to_sq`, o a la pila propia si `to_pile`. Son dos gestos
## continuos: alcanzar (se detiene al agarrar) y trasladar (se detiene al soltar).
func _carry(from_sq: int, to_sq: int, to_pile: bool) -> void:
	var node: Node3D = board.take_piece(from_sq)
	if node == null:
		push_warning("HandAnimator: no hay pieza visual en %s" % ChessPiece.square_name(from_sq))
		return
	var code := int(node.get_meta("code"))
	var gh := PieceFactory.grip_height(code)
	var grip_a := node.global_position + Vector3(0, gh, 0)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh

	# Alcanzar: desde donde esté la mano, sube (si estaba en contacto), cruza en arco y baja
	# vertical y despacio sobre la pieza (fase de precisión). Los dedos se abren al salir y se
	# cierran un poco antes de llegar.
	_set_phase(&"reach")
	rig.begin_grasp(node)
	var wps := _lift_wps(rig)
	wps.append(_wp(grip_a + Vector3(0, 0.10, 0), 58.0, 1.0))
	wps.append(_wp(grip_a + Vector3(0, 0.04, 0), 60.0, 0.7))
	wps.append(_wp(grip_a, 62.0, 0.45))
	var events := [
		_ev(0.04, func() -> void: rig.set_pose(HandRig.Pose.OPEN, _dur(0.25))),
		_ev(0.82, func() -> void:
			_set_phase(&"grab")
			rig.set_pose(HandRig.Pose.PINCH, _dur(0.16))),
	]
	await _flow(rig, wps, _dur(0.85), {"fitts": true, "events": events})
	# Agarrar: la pinza ya casi está cerrada.
	rig.attach_piece(node, gh)
	await _pause(0.05)

	# Trasladar: sube recto hasta librar las piezas, cruza en arco y baja despacio al soltar.
	_set_phase(&"carry")
	var dest := Vector3.ZERO
	if to_pile:
		dest = board.pile_slot(color, board.piles[color].size())
	else:
		dest = board.square_to_world(to_sq)
	var mid := (grip_a + dest) * 0.5
	var cwps: Array = [
		_wp(grip_a + Vector3(0, (clear_y - grip_a.y) * 0.55, 0), 58.0, 1.2),
		_wp(Vector3(grip_a.x, clear_y, grip_a.z), 58.0, 1.3),
		_wp(Vector3(mid.x, clear_y + 0.02, mid.z), 58.0, 1.0),
		_wp(Vector3(dest.x, clear_y, dest.z), 58.0, 1.1),
		_wp(Vector3(dest.x, dest.y + gh + 0.035, dest.z), 61.0, 0.7),
		_wp(Vector3(dest.x, dest.y + gh + 0.004, dest.z), 62.0, 0.45),
	]
	await _flow(rig, cwps, _dur(1.05), {"fitts": true})
	# Soltar.
	_set_phase(&"release")
	var held := rig.release_piece()
	if to_pile:
		board.add_to_pile(held, color)
	else:
		board.put_piece(held, to_sq)
	rig.set_pose(HandRig.Pose.OPEN, _dur(0.15))
	_at_contact = true
	await _pause(0.08)


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
	var total := _cheat_total(job)
	match int(job.cheat_kind):
		CheatDef.Kind.STEAL:
			await _cheat_steal(job, total)
		_:
			# Pieza propia o rival: a distancia 1 se empuja sin levantarla; si no, se lleva en arco.
			if int(job.distance) <= 1:
				await _cheat_nudge(job, total)
			else:
				await _cheat_drag(job, total)
	await _return_home_cheat()


## Duración de la curva del gesto: el tiempo que falta hasta el `deadline` del servidor.
func _cheat_total(job: Dictionary) -> float:
	return maxf(float(job.deadline) - _clock, CHEAT_MIN_TIME)


## Empujón: la mano empuja la pieza una casilla (también en diagonal), sin levantarla. Es UNA
## curva de duración `total`: llega por encima y por detrás, baja al contacto sin detenerse y
## sigue empujando; la pieza avanza con la proyección de la mano sobre el empujón. La curva acaba
## cuando el servidor aplica el cambio; entonces se asienta con el descentrado definitivo.
func _cheat_nudge(job: Dictionary, total: float) -> bool:
	var node: Node3D = board.take_piece(job.from)
	if node == null:
		return false
	var gh := PieceFactory.grip_height(int(node.get_meta("code")))
	var start := node.global_position
	var delta := board.square_to_world(job.to) - board.square_to_world(job.from)
	delta.y = 0.0
	var plan := _plan_nudge(start, gh, delta)
	var contact: Vector3 = plan.contact
	var dir: Vector3 = plan.dir
	var length := delta.length()
	var st := {"pushing": false}
	var step := func(_s: float, _seg: float) -> void:
		# La pieza va donde la empuja la mano (solo avanza, nunca retrocede de su casilla).
		var t := clampf((rig.get_grip() - contact).dot(dir) / maxf(length, 1e-4), 0.0, 1.0)
		if t > 0.0 and not st.pushing:
			st.pushing = true
			_set_phase(&"cheat")
		node.global_position = start + delta * t
	_set_phase(&"reach")
	rig.set_pose(HandRig.Pose.GRIP, 0.25)
	if not await _flow(rig, plan.wps, total, {"job": job, "on_step": step}):
		node.global_position = start
		return _cheat_restore(node, job.from)
	if not await _wait_resolved(job):
		node.global_position = start
		return _cheat_restore(node, job.from)
	board.put_piece(node, job.to, job.offset)
	_at_contact = true
	return true


## Pieza a distancia 2 o más: un solo gesto (alcanzar, pinza, levantar, cruzar en arco, posar).
func _cheat_drag(job: Dictionary, total: float) -> bool:
	return await _cheat_carry(job, total, board.square_to_world(job.to), false)


## Robar: igual que el arrastre, pero la pieza rival va a la pila de capturas propia, donde queda.
func _cheat_steal(job: Dictionary, total: float) -> bool:
	return await _cheat_carry(job, total, board.pile_slot(color, board.piles[color].size()), true)


## Gesto de llevar una pieza (arrastre y robo): UNA curva de duración `total` por los puntos de
## `_plan_carry`. La mano no se detiene al agarrar: la pinza se cierra al acercarse y la pieza
## pasa a la mano al llegar al punto de agarre (`grab_seg`), a mitad de curva. La curva acaba en el
## destino cuando el servidor aplica el cambio; solo entonces se suelta.
func _cheat_carry(job: Dictionary, total: float, dest: Vector3, to_pile: bool) -> bool:
	var node: Node3D = board.take_piece(job.from)
	if node == null:
		return false
	var gh := PieceFactory.grip_height(int(node.get_meta("code")))
	var grip_a := node.global_position + Vector3(0, gh, 0)
	var plan := _plan_carry(grip_a, gh, dest)
	var grab_seg: float = plan.grab_seg
	var st := {"stage": 0}
	var step := func(_s: float, seg: float) -> void:
		if st.stage == 0 and seg >= grab_seg - 0.45:
			st.stage = 1
			_set_phase(&"grab")
			rig.set_pose(HandRig.Pose.PINCH, 0.14)
		if st.stage == 1 and seg >= grab_seg:
			st.stage = 2
			rig.attach_piece(node, gh)
			_set_phase(&"cheat")
	_set_phase(&"reach")
	var events := [_ev(0.03, func() -> void: rig.set_pose(HandRig.Pose.OPEN, 0.2))]
	if not await _flow(rig, plan.wps, total, {"job": job, "on_step": step, "events": events}):
		return await _cheat_abort_carry(job, node)
	if not await _wait_resolved(job):
		return await _cheat_abort_carry(job, node)
	var held := rig.release_piece()
	if to_pile:
		board.add_to_pile(held, color)
	else:
		board.put_piece(held, job.to, job.offset)
	rig.set_pose(HandRig.Pose.OPEN, 0.12)
	_at_contact = true
	return true


## Puntos de paso del empujón desde la posición `start` de la pieza (altura de pinza `gh`) con
## el desplazamiento horizontal `delta`: llega por encima y por detrás del contacto, baja a él y
## sigue en línea hasta el destino. Devuelve {wps, contact, dir}.
static func _plan_nudge(start: Vector3, gh: float, delta: Vector3) -> Dictionary:
	var dir := delta.normalized()
	var contact := start + Vector3(0, gh * 0.7, 0) - dir * 0.02
	return {
		"contact": contact,
		"dir": dir,
		"wps": [
			_wp(contact + Vector3(0, 0.07, 0) - dir * 0.02, 72.0, 1.0),
			_wp(contact, 78.0, 0.5),
			_wp(contact + delta, 78.0, 0.8),
		],
	}


## Puntos de paso del gesto de llevar una pieza desde su punto de pinza `grip_a` (altura de pinza
## `gh`) a `dest` (base de la casilla o de la pila): baja vertical y lenta al agarre (`grab_seg`
## = índice fraccionario del punto de agarre en la curva), sube hasta librar las piezas, cruza en
## arco y baja despacio al soltar. Devuelve {wps, grab_seg}.
static func _plan_carry(grip_a: Vector3, gh: float, dest: Vector3) -> Dictionary:
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh
	var mid := (grip_a + dest) * 0.5
	# Dirección horizontal hacia el destino: la mano llega por el lado contrario y sale hacia él,
	# así el agarre es el fondo redondeado de una "U" y no una inversión brusca.
	var dir := Vector3(dest.x - grip_a.x, 0.0, dest.z - grip_a.z).normalized()
	var wps: Array = [
		_wp(grip_a + Vector3(0, 0.10, 0) - dir * 0.03, 58.0, 1.0),
		_wp(grip_a + Vector3(0, 0.04, 0) - dir * 0.012, 60.0, 0.7),
		_wp(grip_a, 62.0, 0.45),
		_wp(grip_a + Vector3(0, (clear_y - grip_a.y) * 0.55, 0) + dir * 0.008, 58.0, 1.2),
		_wp(Vector3(grip_a.x, clear_y, grip_a.z) + dir * 0.02, 58.0, 1.3),
		_wp(Vector3(mid.x, clear_y + 0.02, mid.z), 58.0, 1.0),
		_wp(Vector3(dest.x, clear_y, dest.z), 58.0, 1.1),
		_wp(Vector3(dest.x, dest.y + gh + 0.035, dest.z), 61.0, 0.7),
		_wp(Vector3(dest.x, dest.y + gh + 0.004, dest.z), 62.0, 0.45),
	]
	return {"wps": wps, "grab_seg": 3.0}


## Aborto de un arrastre o robo: si la pieza ya está en la mano la devuelve a su casilla con un
## gesto corto y continuo; si no, la deja donde estaba. Siempre devuelve false.
func _cheat_abort_carry(job: Dictionary, node: Node3D) -> bool:
	if rig.carried == null:
		rig.set_pose(HandRig.Pose.OPEN, 0.12)
		return _cheat_restore(node, job.from)
	return await _cheat_return_piece(job)


## Abortada con la pieza en el aire: vuelve a su casilla de origen en una sola curva corta
## (sube, cruza y baja) y la deja allí.
func _cheat_return_piece(job: Dictionary) -> bool:
	if rig.carried == null:
		return false
	var held := rig.carried
	var gh := PieceFactory.grip_height(int(held.get_meta("code")))
	var home := board.square_to_world(job.from)
	var clear_y := BoardView.BOARD_TOP + KING_HEIGHT + CARRY_CLEARANCE + gh
	var cur := rig.get_grip()
	var wps: Array = [
		_wp(Vector3(cur.x, maxf(cur.y, clear_y), cur.z), 58.0, 1.4),
		_wp(Vector3(home.x, clear_y, home.z), 58.0, 1.0),
		_wp(Vector3(home.x, home.y + gh + 0.035, home.z), 61.0, 0.7),
		_wp(Vector3(home.x, home.y + gh + 0.004, home.z), 62.0, 0.45),
	]
	# El gesto de regreso es corto para no alargar la trampa abortada (sin `job`: no se aborta).
	await _flow(rig, wps, 0.6, {})
	_cheat_restore(rig.release_piece(), job.from)
	rig.set_pose(HandRig.Pose.OPEN, 0.12)
	_at_contact = true
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
		if not is_inside_tree():
			return false
		await get_tree().process_frame
		waited += get_process_delta_time()
	return job.resolved and job.applied


## Tras soltar (o deshacer) el gesto, la mano sube y vuelve al reposo en una sola curva.
func _return_home_cheat() -> void:
	_set_phase(&"return")
	rig.set_pose(HandRig.Pose.OPEN, 0.2)
	var wps := _lift_wps(rig, 0.06)
	wps.append(_wp((rig.get_grip() + rest_grip) * 0.5 + Vector3(0, 0.06, 0), -1.0, 1.0))
	wps.append(_wp(rest_grip, rest_pitch, 0.8))
	await _flow(rig, wps, 0.7, {})
	rig.set_pose(HandRig.Pose.OPEN, 0.25)


func _press_clock() -> void:
	if clock == null:
		return
	_set_phase(&"press")
	var top := clock.button_top_world(color)
	var wps := _lift_wps(rig)
	wps.append(_wp(top + Vector3(0, 0.08, 0), 55.0, 1.0))
	wps.append(_wp(top + Vector3(0, 0.025, 0), 52.0, 0.6))
	wps.append(_wp(top + Vector3(0, 0.004, 0), 50.0, 0.4))
	await _flow(rig, wps, _dur(0.7), {"fitts": true, "events": [_ev(0.05, func() -> void: rig.set_pose(HandRig.Pose.PRESS, _dur(0.2)))]})
	clock.press_button(color)
	clock_hit.emit(color)
	_at_contact = true
	await _pause(0.12)


## Anota la jugada pendiente en la planilla: toma la pluma, escribe unos 2 s, la deja y la jugada
## aparece en la hoja. Es interrumpible: si llega una jugada o una trampa a la cola, deja la
## pluma en su sitio de forma rápida (`_write_abort`) y la entrada sigue pendiente, así que se
## vuelve a encolar un trabajo "write" tras el nuevo. No toma el cerrojo de movimiento.
##
## Toda la anotación es UN gesto continuo (`_flow`): la mano baja con la orientación de la pinza
## de frente sobre la pluma tumbada (`HandRig.orient_for_pen`), la cierra sin detenerse y sube
## llevándola; la pluma va fija en la mano (`HandRig.hold_tool`) y pivota en la pinza hasta la
## postura de escribir (`set_tool_blend`) acoplada al avance de la curva, mientras la muñeca gira
## de la postura de toma a la de escribir. Al terminar hace lo inverso y la deja tumbada.
func _run_write(_job: Dictionary) -> void:
	if sheet == null or not sheet.has_pending(color):
		return
	var w := write_rig
	var parallel := _parallel_write()
	if not parallel:
		_set_phase(&"write")
		w.drives_posture = true
		rig.drives_posture = w == rig
		_cur = w
	elif not _running:
		_set_phase(&"write")
	var pen := sheet.pen(color)
	var pen_grip := sheet.pen_rest_grip(color)
	var up := Vector3.UP
	var abort := func() -> bool: return _write_should_abort()
	var pal := 1.0 if w.side == &"R" else -1.0
	var start := sheet.write_point(color)
	# Posturas de la mano: la de la toma (pluma tumbada) y la de escribir.
	var og := w.orient_for_pen(pen.global_basis.x, _flat_dir(w, pen_grip))
	var ow := Vector2(WRITE_PITCH, WRITE_ROLL * pal)
	var axis := w.pen_write_axis_world(_flat_dir(w, start), ow.x, ow.y)
	var off := axis * ScoresheetView.PEN_GRIP
	var mid := Vector2(lerpf(og.x, ow.x, 0.4), lerpf(og.y, ow.y, 0.4))
	var st := {"held": false, "closing": false, "committed": false, "grip": pen_grip, "og": Vector2(og.x, og.y), "blend": 0.0}
	w.begin_tool(pen)
	w.set_pose(HandRig.Pose.OPEN, _dur(0.2))

	# Puntos de paso: aproximación de frente, toma (sin parar), subida con giro, trazos y regreso.
	var wps := _lift_wps(w)
	wps.append(_wp(pen_grip + up * 0.07, og.x, 1.0, og.y))
	wps.append(_wp(pen_grip + up * 0.025, og.x, 0.7, og.y))
	wps.append(_wp(pen_grip, og.x, 0.3, og.y))
	var i_grasp := wps.size()
	wps.append(_wp(pen_grip + up * 0.035, mid.x, 0.8, mid.y))
	wps.append(_wp(start + off + up * 0.03, ow.x, 1.0, ow.y))
	var i_start := wps.size()
	var dir := sheet.line_direction(color)
	var total := _rng.randf_range(1.7, 2.3) / (SPEED * rig_speed())
	var strokes := 7
	var first := wps.size() + 1
	for k in strokes:
		var x := WRITE_SLIDE * float(k + 1) / float(strokes)
		var lift := 0.0035 if k % 2 == 0 else 0.0
		wps.append(_wp(start + dir * x + off + Vector3(0, lift, _rng.randf_range(-0.003, 0.003)), ow.x, WRITE_STROKE_WEIGHT, ow.y))
	var last := wps.size()
	wps.append(_wp(start + dir * WRITE_SLIDE + off + up * 0.03, ow.x, 1.0, ow.y))
	wps.append(_wp(pen_grip + up * 0.035, mid.x, 1.0, mid.y))
	var i_down := wps.size()
	wps.append(_wp(pen_grip + up * 0.012, og.x, 0.6, og.y))
	wps.append(_wp(pen_grip, og.x, 0.4, og.y))

	var color_c := color
	var step := func(_s: float, seg: float) -> void:
		# Dedos: se cierran justo antes de llegar a la pluma.
		if not st.closing and seg >= float(i_grasp) - 1.0:
			st.closing = true
			w.set_pose(HandRig.Pose.PINCH, _dur(0.16))
		# La pluma pasa a la mano al llegar al punto de toma, sin saltos.
		if not st.held and seg >= float(i_grasp):
			st.held = true
			w.hold_tool(pen)
		if st.held:
			if seg < float(i_start):
				st.blend = smoothstep(float(i_grasp), float(i_start), seg)
			elif seg > float(last):
				st.blend = 1.0 - smoothstep(float(last), float(i_down), seg)
			else:
				st.blend = 1.0
			w.set_tool_blend(st.blend)
		if st.committed or seg < float(first):
			return
		if seg >= float(last):
			st.committed = true
			sheet.reveal_next(color_c, 0.0)
		else:
			sheet.show_partial(color_c, (seg - float(first)) / float(last - first))
	var dur := _dur(1.3) + total + _dur(0.6)
	if not await _flow(w, wps, dur, {"abort": abort, "cruise": 0.4, "on_step": step}):
		await _write_abort(w, st)
		return
	if not st.committed:
		sheet.reveal_next(color, 0.0)
	# Suelta la pluma: ya está tumbada en su sitio (solo se asienta lo que falte).
	w.release_piece()
	w.set_pose(HandRig.Pose.OPEN, _dur(0.12))
	await sheet.rest_pen(color, _dur(0.2))
	_at_contact = true
	if parallel:
		# La otra mano vuelve al reposo sin tocar `_cur` (la mano que juega sigue su cola).
		if _wqueue.is_empty():
			await _send_write_home(w)
	elif _queue.is_empty():
		await _return_home()
	elif w != rig:
		_send_write_home(w)


## Dirección horizontal del hombro de `w` al punto `p` (la guía de la mano, igual que `HandRig`).
func _flat_dir(w: HandRig, p: Vector3) -> Vector3:
	var to := p - w.shoulder_position()
	to.y = 0.0
	if to.length() < 0.02:
		return w.figure.global_basis * Vector3(0, 0, 1)
	return to.normalized()


## La escritura se interrumpió: si ya tenía la pluma la deja en su sitio con un gesto corto y
## rápido (la pluma se tumba mientras la mano baja); borra lo escrito a medias (la entrada sigue
## pendiente) y encola de nuevo la anotación, que se hará tras el trabajo que interrumpió.
func _write_abort(w: HandRig, st: Dictionary) -> void:
	if st.held:
		var pen_grip: Vector3 = st.grip
		var og: Vector2 = st.og
		var blend0: float = st.blend
		var back := func(_s: float, seg: float) -> void:
			w.set_tool_blend(blend0 * (1.0 - smoothstep(0.0, 2.0, seg)))
		await _flow(w, [_wp(pen_grip + Vector3(0, 0.03, 0), og.x, 1.2, og.y), _wp(pen_grip, og.x, 0.5, og.y)], WRITE_ABORT_TIME, {"on_step": back})
		w.release_piece()
		w.set_pose(HandRig.Pose.OPEN, 0.1)
		sheet.rest_pen(color, 0.12)  # se asienta mientras la mano ya se va
		_at_contact = true
	else:
		w.end_grasp()
		w.set_pose(HandRig.Pose.OPEN, 0.1)
	if not st.committed:
		sheet.clear_partial(color)
		if _parallel_write():
			_wqueue.append({"kind": "write"})
		else:
			_queue.append({"kind": "write"})
	if w != rig:
		_send_write_home(w)
	if not _parallel_write():
		_cur = rig
	rig.drives_posture = true


## La mano de escritura (distinta de la que juega) vuelve al reposo sin bloquear la cola.
func _send_write_home(w: HandRig) -> void:
	rig.drives_posture = true
	var wps := _lift_wps(w, 0.05)
	wps.append(_wp((w.get_grip() + write_rest_grip) * 0.5 + Vector3(0, 0.06, 0), -1.0, 1.0))
	wps.append(_wp(write_rest_grip, write_rest_pitch, 1.0))
	await _flow(w, wps, _dur(0.55), {"fitts": true})
	w.drives_posture = false


func _return_home() -> void:
	_set_phase(&"return")
	var hand := _cur
	var home := rest_grip if hand == rig else write_rest_grip
	var pit := rest_pitch if hand == rig else write_rest_pitch
	var wps := _lift_wps(hand, 0.05)
	wps.append(_wp((hand.get_grip() + home) * 0.5 + Vector3(0, 0.06, 0), -1.0, 1.0))
	wps.append(_wp(home, pit, 0.8))
	await _flow(hand, wps, _dur(0.6), {"fitts": true, "events": [_ev(0.0, func() -> void: hand.set_pose(HandRig.Pose.OPEN, _dur(0.3)))]})
	if hand != rig:
		hand.drives_posture = false
		rig.drives_posture = true
	_cur = rig


# --- Movimiento -----------------------------------------------------------------

## Punto de paso de un gesto: posición, pitch de la mano en grados (-1 = el del punto anterior)
## y `speed`, peso de velocidad del tramo que llega a él (menor = más lento; la aproximación
## de precisión usa pesos bajos y la salida pesos altos).
static func _wp(p: Vector3, pitch: float = -1.0, speed: float = 1.0, roll: float = NO_ROLL) -> Dictionary:
	return {"p": p, "pitch": pitch, "w": speed, "roll": roll}


## Evento de un gesto: `fn` se llama al pasar la fracción de tiempo `t` (anticipa los dedos).
static func _ev(t: float, fn: Callable) -> Dictionary:
	return {"t": t, "fn": fn}


## Punto de despegue si la mano acaba de tocar algo (pieza, botón, pluma): el gesto siguiente
## sube primero, así la salida es rápida y no arrastra el contacto.
func _lift_wps(hand: HandRig, height: float = 0.045) -> Array:
	var wps: Array = []
	if _at_contact:
		wps.append(_wp(hand.get_grip() + Vector3(0, height, 0), -1.0, 1.5))
		_at_contact = false
	return wps


## Perfil de mínimo jerk: s = 10t³ - 15t⁴ + 6t⁵. Con `cruise` > 0 la parte central va a
## velocidad constante y solo las rampas (también de mínimo jerk) arrancan y frenan.
static func _profile(t: float, cruise: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if cruise <= 0.001:
		return t * t * t * (10.0 - 15.0 * t + 6.0 * t * t)
	var r := (1.0 - cruise) * 0.5
	var vmax := 1.0 / (r + cruise)
	if t < r:
		var u := t / r
		return vmax * r * u * u * u * u * (2.5 - 3.0 * u + u * u)
	if t > 1.0 - r:
		var u2 := (1.0 - t) / r
		return 1.0 - vmax * r * u2 * u2 * u2 * u2 * (2.5 - 3.0 * u2 + u2 * u2)
	return vmax * (r * 0.5 + (t - r))


## Spline Catmull-Rom centrípeta (Barry-Goldman) entre `p1` y `p2`: continuidad de velocidad
## en los puntos de paso y sin lazos ni cúspides.
static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var t1 := sqrt(maxf(p0.distance_to(p1), 1e-4))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-4))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-4))
	var t := lerpf(t1, t2, u)
	var a1 := p0.lerp(p1, (t - 0.0) / t1)
	var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
	var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
	var b1 := a1.lerp(a2, (t - 0.0) / t2)
	var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
	return b1.lerp(b2, (t - t1) / (t2 - t1))


## Recorre los puntos de paso `wps` (ver `_wp`) con `hand` como UNA curva suave que parte de la
## posición actual, parametrizada por longitud de arco (ponderada por la velocidad de cada
## tramo) con perfil de mínimo jerk: la mano solo está quieta al principio y al final. El pitch
## se interpola con la misma curva. Opciones (`opts`):
##   fitts: la duración se acorta en trayectos cortos (ley de Fitts, aproximada).
##   cruise: fracción central a velocidad constante (0 = mínimo jerk puro).
##   events: lista de `_ev` (se disparan al pasar su fracción de tiempo).
##   on_step: Callable(s, seg) con el progreso 0..1 y la posición fraccionaria entre puntos.
##   abort: Callable() -> bool; si devuelve true el gesto se corta y devuelve false.
##   job: trabajo de trampa; si se aborta, el gesto se corta y devuelve false.
func _flow(hand: HandRig, wps: Array, duration: float, opts: Dictionary = {}) -> bool:
	if not is_inside_tree():
		return false
	var pts: Array[Vector3] = [hand.get_grip()]
	var pits: Array[float] = [hand.get_pitch_deg()]
	# Giro de la mano sobre los dedos (grados): arranca del actual; sin ningún `roll` en los puntos
	# vuelve a 0 (palma abajo), y con alguno los puntos sin él lo mantienen.
	var rolls: Array[float] = [hand.get_roll_deg()]
	var any_roll := false
	for w in wps:
		if float(w.get("roll", NO_ROLL)) > NO_ROLL + 1.0:
			any_roll = true
	var ws: Array[float] = [1.0]
	var geo := 0.0
	for w in wps:
		geo += pts[-1].distance_to(w.p)
		pts.append(w.p)
		pits.append(pits[-1] if float(w.pitch) < 0.0 else float(w.pitch))
		var wr := float(w.get("roll", NO_ROLL))
		rolls.append(wr if wr > NO_ROLL + 1.0 else (rolls[-1] if any_roll else 0.0))
		ws.append(maxf(float(w.w), 0.05))
	var n := pts.size()
	# Tabla de muestras: posición, pitch, posición entre puntos y longitud ponderada acumulada.
	var sp: Array[Vector3] = [pts[0]]
	var sy: Array[float] = [pits[0]]
	var sr: Array[float] = [rolls[0]]
	var sg: Array[float] = [0.0]
	var sw: Array[float] = [0.0]
	for i in n - 1:
		var p0 := pts[i - 1] if i > 0 else pts[0] * 2.0 - pts[1]
		var p3 := pts[i + 2] if i + 2 < n else pts[n - 1] * 2.0 - pts[n - 2]
		var y0 := pits[i - 1] if i > 0 else pits[0]
		var y3 := pits[i + 2] if i + 2 < n else pits[n - 1]
		var r0 := rolls[i - 1] if i > 0 else rolls[0]
		var r3 := rolls[i + 2] if i + 2 < n else rolls[n - 1]
		for k in range(1, FLOW_STEPS + 1):
			var u := float(k) / float(FLOW_STEPS)
			var q := _catmull(p0, pts[i], pts[i + 1], p3, u)
			sw.append(sw[-1] + q.distance_to(sp[-1]) / ws[i + 1])
			sp.append(q)
			sy.append(cubic_interpolate(pits[i], pits[i + 1], y0, y3, u))
			sr.append(cubic_interpolate(rolls[i], rolls[i + 1], r0, r3, u))
			sg.append(float(i) + u)
	var total_w: float = sw[-1]
	var dur := maxf(duration, 0.03)
	if opts.get("fitts", false):
		dur *= lerpf(0.6, 1.0, clampf(geo / 0.5, 0.0, 1.0))
	var cruise := float(opts.get("cruise", 0.0))
	var events: Array = opts.get("events", [])
	var fired: Array[bool] = []
	fired.resize(events.size())
	var abort: Callable = opts.get("abort", Callable())
	var job: Variant = opts.get("job")
	var on_step: Callable = opts.get("on_step", Callable())
	var t := 0.0
	var idx := 0
	while true:
		if not is_inside_tree():
			return false
		if job != null and job.resolved and not job.applied:
			return false
		if abort.is_valid() and abort.call():
			return false
		var s := _profile(t, cruise)
		var pos := sp[-1]
		var pit := sy[-1]
		var rol := sr[-1]
		var seg := float(n - 1)
		if t < 1.0:
			var target := s * total_w
			while idx < sw.size() - 2 and sw[idx + 1] < target:
				idx += 1
			var span: float = sw[idx + 1] - sw[idx]
			var f := clampf((target - sw[idx]) / span, 0.0, 1.0) if span > 1e-9 else 1.0
			if total_w < 1e-6:
				f = 0.0
				pos = sp[-1]
				pit = lerpf(sy[0], sy[-1], s)
				rol = lerpf(sr[0], sr[-1], s)
			else:
				pos = sp[idx].lerp(sp[idx + 1], f)
				pit = lerpf(sy[idx], sy[idx + 1], f)
				rol = lerpf(sr[idx], sr[idx + 1], f)
			seg = lerpf(sg[idx], sg[idx + 1], f)
		hand.set_grip(pos, pit, rol)
		for e in events.size():
			if not fired[e] and t >= float(events[e].t):
				fired[e] = true
				(events[e].fn as Callable).call()
		if on_step.is_valid():
			on_step.call(s, seg)
		if t >= 1.0:
			break
		await get_tree().process_frame
		t = minf(t + get_process_delta_time() / dur, 1.0)
	return true


func _pause(seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


## Duración con la variación humana de la jugada, la prisa del estrés y la
## prisa por ponerse al día si hay animaciones atrasadas en cola.
func _dur(base: float) -> float:
	var backlog := 1.0 + 0.7 * maxi(board.pending_jobs() - 1, 0)
	return base * _job_speed * lerpf(1.0, 0.6, clampf(rig.stress, 0.0, 1.0)) / (SPEED * backlog)


## Factor de velocidad de la jugada actual (variación humana y prisa por estrés).
func rig_speed() -> float:
	return _job_speed / lerpf(1.0, 0.6, clampf(rig.stress, 0.0, 1.0))


func _set_phase(p: StringName) -> void:
	if phase != p:
		phase = p
		phase_changed.emit(p)
