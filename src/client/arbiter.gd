class_name Arbiter
extends Node3D
## El árbitro verdugo: patrulla sin parar los pasillos del salón (entre columnas y
## filas de mesas y por el perímetro) con pausas mirando una mesa, y a veces pasa por
## detrás del jugador. Sus pasos son sonido 3D sincronizado con la zancada.
##
## Atiende, por prioridad: la ejecución del propio jugador (primera persona), la
## acusación del humano (revisa las dos planillas y anuncia el veredicto) y la cola de
## ejecuciones (la del humano primero; después la más cercana). Mientras espera su turno
## el condenado reacciona (`Condemned`). Es puramente visual: quién pierde lo decide el
## servidor y `GameRoot` pide las ejecuciones.
##
## Depuración (argumentos tras `--`, ver `ArbiterModule`): --force-execution, --lose-now.

## Terminó la ejecución de quien estaba en `seat` (0 = blancas, 1 = negras) de la mesa `table`
## (índice de `HallLayout`; la del humano es `HallLayout.human_table`).
signal executed(table: int, seat: int)
## Terminó de atender la acusación (veredicto dado y gesto hecho).
signal accusation_done
## Terminó la secuencia en primera persona (ya en negro).
signal player_executed

const SFX := "res://assets/audio/sfx/"
## Velocidad de patrulla (m/s) y de camino a una ejecución con la cola corta.
const PATROL_SPEED := 1.0
const BRISK_SPEED := 1.25
const MAX_SPEED := 1.9
## Pasos: sonido 3D con atenuación por distancia (ver `footstep_gain_db`).
const STEP_UNIT_SIZE := 4.0
const STEP_MAX_DISTANCE := 28.0
const STEP_BASE_DB := -2.0
## En la animación `walk` (1,30 s) los pies tocan el suelo en 0,00 y 0,65 s.
const WALK_LENGTH := 1.30
const STEP_PHASES: Array[float] = [0.0, 0.65]
const NEAR_RADIUS := 2.0

enum Urgency { NONE = 0, QUEUE = 1, ACCUSATION = 2, PLAYER = 3 }

var root: GameRoot
var figure: ArbiterFigure
var queue := ExecutionQueue.new()

var _rng := RandomNumberGenerator.new()
var _cond: Dictionary = {}          # clave de ExecutionQueue -> Condemned
var _temp_figures: Dictionary = {}
var _step_players: Array[AudioStreamPlayer3D] = []
var _step_next: int = 0
var _prev_anim_pos: float = 0.0
var _flash: OmniLight3D
var _sparks: CPUParticles3D
var _forced_route: Array[Vector3] = []
var _forced_speed: float = 0.8
var _acc: Dictionary = {}           # {accuser, deadline, verdict}
var _player_job: Dictionary = {}
var _preset: Dictionary = {}        # clave -> Condemned.Mode forzado (depuración)
var _running: bool = false
var _fp_audio: Array[AudioStreamPlayer] = []
var _black: CanvasLayer
## Mesas con partida en juego que patrulla; `_active_set` false = aún no se informó (todas).
var _active_tables: Array[int] = []
var _active_set: bool = false
## Foco que lo ilumina durante el discurso (`begin_address`).
var _address_light: SpotLight3D
## Mesas ya revisadas (por una acusación o antes de una ejecución): no se repite.
var _reviewed: Dictionary = {}
## Discurso: mientras dure, el árbitro está plantado en `_address_pos` y no patrulla.
var _addressing: bool = false
var _address_pos := Vector3.ZERO


## Arma la figura y empieza a patrullar. `p_root` puede ser null (pruebas).
func setup(p_root: GameRoot) -> void:
	name = "Arbitro"
	root = p_root
	_rng.randomize()
	figure = ArbiterFigure.new()
	add_child(figure)
	figure.play(&"idle", 0.0)
	_build_steps()
	_build_flash()
	position = Vector3(ArbiterRoutes.aisle_xs()[0], 0.0, ArbiterRoutes.aisle_zs()[1])
	if root != null:
		_run.call_deferred()


func _log(text: String) -> void:
	if root != null and (root.get_args().has("verbose") or root.get_args().has("autoplay")):
		print("[arbitro] ", text)


# --- API pública -------------------------------------------------------------------

## Encola la ejecución del perdedor sentado en (`table`, `seat`): el árbitro irá a esa
## mesa y le disparará. Repetirla no hace nada; el condenado empieza a reaccionar ya.
func request_execution(table: int, seat: int) -> void:
	if queue.was_done(table, seat):
		executed.emit.call_deferred(table, seat)
		return
	var human_color := root.human_color if root != null else ChessPiece.WHITE
	var spot := ArbiterRoutes.execution_spot(table, seat, human_color)
	if queue.push(table, seat, spot, table == HallLayout.human_table):
		_condemn(table, seat)


## Descarta las ejecuciones en cola de las mesas distintas de `except_table` (corte de ronda):
## quedan como hechas, sus condenados dejan de reaccionar y nunca pasan por el árbitro. Devuelve
## las entradas descartadas `{table, seat, ...}`.
func skip_pending(except_table: int) -> Array[Dictionary]:
	var skipped := queue.skip_pending(except_table)
	for e in skipped:
		_silence(int(e.table), int(e.seat))
	return skipped


## El perdedor de (`table`, `seat`) se resuelve en silencio, sin que el árbitro lo ejecute:
## sale de la cola si estaba, cuenta como hecho y su figura (si existe) queda en manos del
## árbitro, quieta y callada. No emite `executed`.
func resolve_silently(table: int, seat: int) -> void:
	if queue.current == ExecutionQueue.key(table, seat):
		return  # la está ejecutando ahora: sigue su curso
	queue.drop(table, seat)
	queue.mark_done(table, seat)
	_silence(table, seat)


func _silence(table: int, seat: int) -> void:
	var k := ExecutionQueue.key(table, seat)
	if _cond.has(k):
		(_cond[k] as Condemned).silence()
	elif root != null:
		root.condemn_seat(table, seat)  # entrega la figura (queda quieta, sin vida ambiental)


## Informa qué mesas tienen partida en juego: la patrulla y sus pausas se limitan a los
## pasillos que las rodean. Sin mesas activas se queda quieto donde está.
func set_active_tables(tables: Array[int]) -> void:
	_active_tables = tables.duplicate()
	_active_set = true


## Mesas que patrulla ahora (todas mientras no se haya informado).
func patrol_tables() -> Array[int]:
	if _active_set:
		return _active_tables
	var all: Array[int] = []
	for i in HallLayout.table_count():
		all.append(i)
	return all


## Fuerza la reacción del condenado de (`table`, `seat`) (depuración); antes de pedir su ejecución.
func preset_mode(table: int, seat: int, mode: Condemned.Mode) -> void:
	_preset[ExecutionQueue.key(table, seat)] = mode


## ¿Quedan ejecuciones o una acusación por atender? La ronda no termina mientras sea true.
func has_pending_work() -> bool:
	return queue.busy() or not _acc.is_empty() or not _player_job.is_empty()


## Espera (corrutina) a que se haya ejecutado (`table`, `seat`); tope de 90 s por si algo falla.
func wait_executed(table: int, seat: int) -> void:
	var waited := 0.0
	while not queue.was_done(table, seat) and waited < 90.0 and is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		waited += 0.25


## ¿Está atendiendo una acusación (desde que empieza hasta el gesto final)?
func accusation_active() -> bool:
	return not _acc.is_empty()


## Camina despacio por detrás de la silla del jugador (cruza el pasillo de su espalda de
## un lado al otro en `seconds` s) y sigue patrullando. Lo usa el evento disuasivo
## `arbitro_pasa`. Se ignora si está ocupado con una ejecución o una acusación.
func pass_behind(_target: Vector3, seconds: float) -> void:
	if _urgency() > Urgency.NONE or not _forced_route.is_empty():
		return
	if _addressing or queue.current >= 0 or not _acc.is_empty() or not _player_job.is_empty():
		return
	_forced_route = ArbiterRoutes.behind_player_route(position)
	var xs := ArbiterRoutes.aisle_xs()
	var cross := absf(xs[HallLayout.cell_of(HallLayout.human_table).x + 1] - xs[HallLayout.cell_of(HallLayout.human_table).x])
	_forced_speed = clampf(cross / maxf(seconds, 1.0), 0.6, 1.1)


## ¿Está a menos de `radius` metros (en el plano del suelo) de `point`?
func is_near(point: Vector3, radius: float) -> bool:
	var here := global_position if is_inside_tree() else position
	return Vector2(here.x - point.x, here.z - point.z).length() <= radius


## La acusación empezó: va a la mesa del humano para revisar las planillas.
func begin_accusation(accuser: int) -> void:
	var delay := root.config.arbiter_delay if root != null else 3.0
	_acc = {"accuser": accuser, "deadline": delay - 0.3, "verdict": null}


## El servidor decidió: se anunciará cuando termine de revisar las planillas.
func resolve_accusation(accuser: int, correct: bool, warnings: int) -> void:
	if _acc.is_empty():
		_announce_now(accuser, correct, warnings)
		return
	_acc["verdict"] = {"accuser": accuser, "correct": correct, "warnings": warnings}


## Ejecución del jugador en primera persona. Corrutina: vuelve cuando la pantalla quedó negra.
func execute_player() -> void:
	if _player_job.is_empty():
		_player_job = {"state": "walking"}
	await player_executed


## Discurso del árbitro (lo usa el módulo del arranque). Lo planta de inmediato, sin caminar, de
## pie y en `idle` en un punto de pasillo visible desde la silla del humano (`ArbiterRoutes.address_spot`),
## mirando al jugador, y suspende la patrulla hasta `end_address()`.
func begin_address() -> void:
	_addressing = true
	_forced_route = []
	_address_pos = ArbiterRoutes.address_spot()
	position = _address_pos
	_hold_address(0.0)
	figure.play(&"idle", 0.0)
	_prev_anim_pos = 0.0
	# Un foco cenital tenue para que se le lea la figura en el rincón oscuro del pasillo.
	if _address_light == null:
		_address_light = SpotLight3D.new()
		_address_light.name = "FocoDiscurso"
		_address_light.light_color = Color(1.0, 0.88, 0.72)
		_address_light.light_energy = 2.2
		_address_light.spot_range = 4.0
		_address_light.spot_angle = 24.0
		_address_light.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		_address_light.position = Vector3(0.0, 3.0, 0.25)
		add_child(_address_light)
	_address_light.visible = true


## Posición global de la cabeza del árbitro (para que la cámara del jugador lo mire).
func address_head_position() -> Vector3:
	if figure != null and figure.is_inside_tree():
		return figure.head_global_position()
	return position + Vector3(0.0, 1.65, 0.0)


## Fin del discurso: reanuda la patrulla (se aleja caminando).
func end_address() -> void:
	_addressing = false
	figure.set_look(0.0, 0.0)
	if _address_light != null:
		_address_light.visible = false


## ¿Está dando el discurso?
func is_addressing() -> bool:
	return _addressing


## Lo mantiene en su sitio mirando al jugador (cuerpo y cabeza).
func _hold_address(dt: float) -> void:
	position = _address_pos
	var eye := Vector3(0.0, 1.2, 0.2)
	if root != null and root.player != null:
		eye = root.player.global_position
	_face_toward(eye, dt)
	if figure != null and is_inside_tree():
		figure.look_at_point(eye)


## Pérdida de ganancia (dB) de un paso a `distance` metros: modelo de distancia inversa de
## Godot con `STEP_UNIT_SIZE` y el volumen base, con el tope de 3 dB del motor. Más allá de
## `STEP_MAX_DISTANCE` no se oye.
static func footstep_gain_db(distance: float) -> float:
	if distance >= STEP_MAX_DISTANCE:
		return -80.0
	var att := 20.0 * log(STEP_UNIT_SIZE / maxf(distance, 0.001)) / log(10.0) + STEP_BASE_DB
	return minf(att, 3.0)


# --- Bucle principal ---------------------------------------------------------------------

func _urgency() -> int:
	if not _player_job.is_empty():
		return Urgency.PLAYER
	if not _acc.is_empty():
		return Urgency.ACCUSATION
	if not queue.is_empty() or not _forced_route.is_empty():
		return Urgency.QUEUE
	return Urgency.NONE


func _run() -> void:
	if _running:
		return
	_running = true
	# Espera a que la partida arranque para no caminar durante el montaje.
	while is_inside_tree():
		if _addressing and _player_job.is_empty():
			_hold_address(get_process_delta_time())
		elif not _player_job.is_empty():
			await _do_player_execution()
		elif not _acc.is_empty():
			await _do_accusation()
		elif not queue.is_empty():
			await _do_execution(queue.take_next(position))
		elif not _forced_route.is_empty():
			var route := _forced_route
			_forced_route = []
			await _walk_path(route, _forced_speed, Urgency.QUEUE)
			if not route.is_empty():
				_idle()
		else:
			await _patrol_step()
		if not is_inside_tree():
			return
		await get_tree().process_frame


func _patrol_step() -> void:
	var tables := patrol_tables()
	if tables.is_empty():
		# Nada en juego: espera donde está.
		_idle()
		await get_tree().create_timer(0.5).timeout
		return
	var path := ArbiterRoutes.patrol_route(_rng, position, tables)
	# De vez en cuando rodea por la espalda del jugador (si su mesa sigue en juego).
	if tables.has(HallLayout.human_table) and _rng.randf() < 0.12:
		path = ArbiterRoutes.behind_player_route(position)
	var speed := PATROL_SPEED * _rng.randf_range(0.9, 1.1)
	if not await _walk_path(path, speed, Urgency.NONE):
		return
	if _rng.randf() < 0.55:
		await _pause_looking(_rng.randf_range(1.6, 4.0))


## Se detiene y mira el centro de la mesa más cercana.
func _pause_looking(seconds: float) -> void:
	_idle()
	var table := HallLayout.table_position(ArbiterRoutes.nearest_table(position, patrol_tables()))
	var t := 0.0
	while t < seconds and _urgency() == Urgency.NONE and _forced_route.is_empty() and not _addressing and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_face_toward(table, dt)
		figure.look_at_point(table + Vector3(0.0, 0.9, 0.0))
	figure.set_look(0.0, 0.0)


func _idle() -> void:
	figure.play(&"idle", 0.3)
	_prev_anim_pos = 0.0


# --- Ejecuciones --------------------------------------------------------------------------

func _do_execution(e: Dictionary) -> void:
	if e.is_empty():
		return
	var table: int = e.table
	var seat: int = e.seat
	var cond := _condemn(table, seat)
	var human_color := root.human_color if root != null else ChessPiece.WHITE
	var seat_pos := ArbiterRoutes.seat_position(table, seat, human_color)
	var spot := seat_pos + Vector3(ArbiterRoutes.SIDE_OFFSET, 0.0, 0.0)
	# Primero llega al costado de la mesa para revisarla; después se coloca junto al condenado.
	var review_spot := HallLayout.table_position(table) + ArbiterRoutes.HUMAN_SIDE_SPOT
	var path: Array[Vector3] = []
	if not _reviewed.has(table):
		path = ArbiterRoutes.route(position, review_spot)
	else:
		path = ArbiterRoutes.route(position, spot)
	_log("va a ejecutar mesa %d asiento %d (%s, cola %d)" % [table, seat, Condemned.Mode.keys()[cond.mode] if cond != null else "-", queue.size()])
	var speed := clampf(BRISK_SPEED + 0.12 * float(queue.size()), BRISK_SPEED, MAX_SPEED)
	if not await _walk_path(path, speed, Urgency.QUEUE):
		queue.requeue(e)
		return
	if not _reviewed.has(table):
		await _review_table(table)
		if not is_inside_tree():
			return
		if not await _walk_path(ArbiterRoutes.route(position, spot), BRISK_SPEED, Urgency.QUEUE):
			queue.requeue(e)
			return
	var head := _victim_head(cond, seat_pos)
	await _turn_to(head, 0.35)
	# Amartilla, apunta y se toma un instante antes de disparar.
	_play_at(SFX + "gun_cock.wav", figure.global_position + Vector3(0.0, 1.3, 0.0), 0.0, 14.0, 40.0)
	await figure.play_once(&"aim", 0.25)
	figure.play(&"aim_hold", 0.1)
	var hold := _rng.randf_range(1.0, 2.5)
	var t := 0.0
	while t < hold and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_face_toward(_victim_head(cond, seat_pos), dt)
	_fire(table)
	if cond != null:
		cond.die()
	await figure.play_once(&"shoot", 0.02)
	await figure.play_once(&"lower_gun", 0.1)
	queue.finish()
	_log("ejecutado mesa %d asiento %d" % [table, seat])
	executed.emit(table, seat)
	_idle()


## Disparo: animación, estampido 3D, fogonazo y chispas.
## `table` = mesa del condenado (-1 si no importa): el disparo avisa a todo el salón (`gunshot`).
func _fire(table: int = -1) -> void:
	_play_at(SFX + "gunshot.wav", figure.muzzle().global_position, 3.0, 12.0, 70.0)
	if table >= 0:
		Distraction.broadcast(self, &"gunshot", figure.muzzle().global_position, table)
	_muzzle_flash()


func _muzzle_flash() -> void:
	_flash.visible = true
	_flash.light_energy = 7.0
	_sparks.restart()
	_sparks.emitting = true
	var tw := create_tween()
	tw.tween_interval(0.05)
	tw.tween_property(_flash, "light_energy", 0.0, 0.07)
	tw.tween_callback(func() -> void: _flash.visible = false)


func _victim_head(cond: Condemned, seat_pos: Vector3) -> Vector3:
	if cond != null and cond.figure != null and cond.figure.is_inside_tree():
		return cond.figure.head_global_position()
	return seat_pos + Vector3(0.0, 1.15, 0.0)


## Crea (o reutiliza) al condenado de (`table`, `seat`) y le hace empezar a reaccionar.
func _condemn(table: int, seat: int) -> Condemned:
	var k := ExecutionQueue.key(table, seat)
	if _cond.has(k):
		return _cond[k]
	if root == null:
		return null
	var fig := _figure_for(table, seat)
	if fig == null:
		return null
	var rich := table / HallLayout.COLS <= 2
	var c := Condemned.new()
	_cond[k] = c
	c.table = table
	c.start(fig, _preset.get(k, Condemned.pick_mode(rich, _rng)), rich, ArbiterRoutes.seat_sign(table, seat, root.human_color), self)
	return c


## Figura del condenado: la que entrega `GameRoot.condemn_seat`; si aún no existe, una temporal
## en la silla (en la mesa del humano oculta al rival de primitivas).
func _figure_for(table: int, seat: int) -> CharacterFigure:
	var fig := root.condemn_seat(table, seat)
	if fig != null:
		return fig
	var k := ExecutionQueue.key(table, seat)
	if _temp_figures.has(k):
		return _temp_figures[k]
	var f := CharacterFigure.new()
	root.add_child(f)
	f.setup(CharacterFigure.bot_look(_rng))
	var sgn := ArbiterRoutes.seat_sign(table, seat, root.human_color)
	f.global_position = ArbiterRoutes.seat_position(table, seat, root.human_color)
	f.rotation.y = PI if sgn > 0.0 else 0.0
	f.play(&"sit_idle", 0.0)
	_temp_figures[k] = f
	if table == HallLayout.human_table and seat != root.human_color and root.avatar != null:
		root.avatar.visible = false
	return f


# --- Revisión de la mesa -----------------------------------------------------------------------

## El árbitro revisa la mesa antes de decidir: mira el tablero, las dos planillas y a cada
## jugador (~3 s). Reutiliza `inspect_sheets` y la mirada. `on_frame(dt)` se llama cada
## fotograma (la ejecución en primera persona gira la cámara del jugador). Solo una vez por mesa.
func _review_table(table: int, on_frame: Callable = Callable()) -> void:
	_reviewed[table] = true
	_log("revisa la mesa %d" % table)
	var center := HallLayout.table_position(table)
	var human_color := root.human_color if root != null else ChessPiece.WHITE
	var seats: Array[Vector3] = []
	for s in [ChessPiece.WHITE, ChessPiece.BLACK]:
		seats.append(ArbiterRoutes.seat_position(table, s, human_color) + Vector3(0.0, 1.15, 0.0))
	_idle()
	# Tablero, luego las planillas (clip) y por último cada jugador.
	var phases: Array = [[center + Vector3(0.0, 0.8, 0.0), 0.7], [center + Vector3(0.0, 0.8, 0.0), 0.0],
			[seats[0], 0.55], [seats[1], 0.55], [center + Vector3(0.0, 0.8, 0.0), 0.35]]
	var clip_started := false
	for ph in phases:
		var look: Vector3 = ph[0]
		var secs: float = ph[1]
		if secs <= 0.0:
			# Fase de planillas: la animación manda el tiempo.
			if not clip_started:
				clip_started = true
				figure.play_once(&"inspect_sheets", 0.3)
			var guard := 0.0
			while not figure.is_finished() and guard < 3.0 and is_inside_tree():
				await get_tree().process_frame
				if not is_inside_tree():
					return
				var dt := get_process_delta_time()
				guard += dt
				_face_toward(center, dt)
				figure.look_at_point(center + Vector3(0.0, 0.8, 0.0))
				if on_frame.is_valid():
					on_frame.call(dt)
			continue
		var t := 0.0
		while t < secs and is_inside_tree():
			await get_tree().process_frame
			if not is_inside_tree():
				return
			var dt := get_process_delta_time()
			t += dt
			_face_toward(center, dt)
			figure.look_at_point(look)
			if on_frame.is_valid():
				on_frame.call(dt)
	if not is_inside_tree():
		return
	figure.set_look(0.0, 0.0)
	_log("termina de revisar la mesa %d" % table)
	_idle()


# --- Acusación -------------------------------------------------------------------------------

func _do_accusation() -> void:
	var t0 := Time.get_ticks_msec()
	var spot := ArbiterRoutes.HUMAN_SIDE_SPOT
	var path := ArbiterRoutes.route(position, spot)
	var left := float(_acc.deadline) - 0.0
	# Llega a tiempo si puede: acelera hasta MAX_SPEED.
	var need := ArbiterRoutes.route_length(position, path) / maxf(left, 0.5)
	var speed := clampf(need, BRISK_SPEED, MAX_SPEED)
	if not await _walk_path(path, speed, Urgency.ACCUSATION):
		# Lo interrumpe la ejecución del jugador: la acusación ya no importa.
		_acc = {}
		accusation_done.emit()
		return
	await _turn_to(Vector3(0.0, 0.0, 0.0), 0.4)
	# Revisa las dos planillas (la del jugador, en +Z, y la del rival).
	await figure.play_once(&"inspect_sheets", 0.3)
	_idle()
	_reviewed[HallLayout.human_table] = true
	var waited := 0.0
	while _acc.get("verdict") == null and waited < 8.0 and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	var v: Dictionary = _acc.get("verdict") if _acc.get("verdict") != null else {}
	if not v.is_empty():
		_announce_now(v.accuser, v.correct, v.warnings)
		await _verdict_gesture(v.accuser, v.correct)
	_acc = {}
	accusation_done.emit()
	if OS.is_debug_build() and root != null and root.get_args().has("verbose"):
		print("[arbitro] acusación atendida en %d ms" % (Time.get_ticks_msec() - t0))


## Gesto: si hubo trampa, señala al acusado; si no, niega con la cabeza.
func _verdict_gesture(accuser: int, correct: bool) -> void:
	if correct:
		var accused := ChessPiece.opposite(accuser)
		var sgn := ArbiterRoutes.seat_sign(HallLayout.human_table, accused, root.human_color)
		await _turn_to(Vector3(0.0, 1.0, sgn * 0.8), 0.35)
		await figure.play_once(&"point_accuse", 0.2)
		await get_tree().create_timer(0.6).timeout
	else:
		for yaw in [0.6, -0.6, 0.45, -0.45, 0.0]:
			figure.set_look(yaw, 0.0)
			await get_tree().create_timer(0.28).timeout
	_idle()


func _announce_now(accuser: int, correct: bool, warnings: int) -> void:
	if root == null or root.hud == null:
		return
	var by_human := accuser == root.human_color
	var text := ""
	if correct:
		text = "Cheating confirmed. The opponent is disqualified." if by_human else "You were caught cheating."
	else:
		if by_human:
			text = "Nothing irregular. Warning %d of %d." % [warnings, root.config.false_accusations_to_eliminate]
		else:
			text = "Nothing irregular. The accusation was false."
	root.hud.show_arbiter(text, 4.0)
	root.hud.set_warnings(root.server.sessions[root.human_color].warnings, root.config.false_accusations_to_eliminate)


# --- Ejecución del jugador (primera persona) ---------------------------------------------------

func _do_player_execution() -> void:
	var spot := ArbiterRoutes.HUMAN_SIDE_SPOT
	var player := root.player
	player.set_input_locked(true)
	_start_fp_audio()
	var progress := func(remaining: float) -> void:
		var k := clampf(1.0 - remaining / 9.0, 0.0, 1.0)
		_fp_audio[0].volume_db = lerpf(-14.0, -3.0, k)
		_fp_audio[1].volume_db = lerpf(-22.0, -8.0, k)
		if remaining < 3.5:
			_turn_player_view(get_process_delta_time(), 0.9)
	var path := ArbiterRoutes.route(position, spot)
	await _walk_path(path, 1.05, Urgency.PLAYER + 1, progress)
	if not is_inside_tree():
		return
	if not _reviewed.has(HallLayout.human_table):
		await _review_table(HallLayout.human_table, func(dt: float) -> void: _turn_player_view(dt, 0.9))
		if not is_inside_tree():
			return
	# Apunta a la cara del jugador.
	var eye := player.global_position
	var t := 0.0
	_play_at(SFX + "gun_cock.wav", figure.global_position + Vector3(0.0, 1.3, 0.0), 0.0, 14.0, 40.0)
	figure.play_once(&"aim", 0.25)
	while not figure.is_finished() and t < 1.5 and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_face_toward(eye, dt)
		_turn_player_view(dt, 1.6)
	figure.play(&"aim_hold", 0.1)
	var hold := _rng.randf_range(2.2, 3.2)
	t = 0.0
	while t < hold and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_face_toward(eye, dt)
		_turn_player_view(dt, 2.2)
		_fp_audio[0].volume_db = lerpf(-3.0, 2.0, t / hold)
	# Disparo y corte a negro instantáneo.
	_play_at(SFX + "gunshot.wav", figure.muzzle().global_position, 6.0, 12.0, 70.0)
	_muzzle_flash()
	_cut_to_black()
	figure.play(&"shoot", 0.0)
	await get_tree().create_timer(2.2).timeout
	_player_job = {}
	player_executed.emit()


## Gira suavemente la cámara del jugador hacia el árbitro si no lo mira; `rate` en 1/s.
func _turn_player_view(dt: float, rate: float) -> void:
	var player := root.player
	var head_pos := player.global_position
	# Mira al cañón (que le apunta a la cara) con la cabeza del árbitro justo encima.
	var target := figure.muzzle().global_position.lerp(figure.head_global_position(), 0.3) - head_pos
	var want_yaw := atan2(-target.x, -target.z)
	var want_pitch := atan2(target.y, Vector2(target.x, target.z).length())
	var k := clampf(rate * dt, 0.0, 1.0)
	player.set_look(lerp_angle(player.yaw, want_yaw, k), lerpf(player.pitch, want_pitch, k))


func _start_fp_audio() -> void:
	var specs := [["heartbeat_loop.wav", -14.0], ["panic_breath_loop.wav", -22.0]]
	for s in specs:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		p.stream = load(SFX + s[0])
		p.volume_db = s[1]
		add_child(p)
		p.play()
		_fp_audio.append(p)


func _cut_to_black() -> void:
	for p in _fp_audio:
		p.stop()
	_black = CanvasLayer.new()
	_black.layer = 9
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.add_child(r)
	root.add_child(_black)
	var ring := AudioStreamPlayer.new()
	ring.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	ring.stream = load(SFX + "ear_ring.wav")
	ring.volume_db = -3.0
	root.add_child(ring)
	ring.play()


# --- Movimiento ---------------------------------------------------------------------------------

## Camina por `path` a `speed` m/s. Devuelve false si lo interrumpió algo más urgente que
## `level`. `on_progress(metros_restantes)` se llama cada fotograma.
func _walk_path(path: Array[Vector3], speed: float, level: int, on_progress: Callable = Callable()) -> bool:
	if path.is_empty():
		return true
	figure.play(&"walk", 0.25)
	figure.set_walk_speed(speed)
	var remaining := ArbiterRoutes.route_length(position, path)
	for p in path:
		while true:
			if not is_inside_tree():
				return false
			if _urgency() > level or (_addressing and level < Urgency.PLAYER):
				_idle()
				return false
			var to := p - position
			to.y = 0.0
			var d := to.length()
			if d < 0.03:
				break
			await get_tree().process_frame
			if not is_inside_tree():
				return false
			var dt := get_process_delta_time()
			var step := minf(speed * dt, d)
			position += to / d * step
			position.y = HallLayout.floor_y(position)
			remaining = maxf(remaining - step, 0.0)
			_face_toward(position + to, dt, 9.0)
			if on_progress.is_valid():
				on_progress.call(remaining)
	return true


## Gira hacia un punto del suelo (suavizado con `rate`; sin `dt` de golpe).
func _face_toward(point: Vector3, dt: float = 0.0, rate: float = 7.0) -> void:
	var d := point - global_position if is_inside_tree() else point - position
	d.y = 0.0
	if d.length() < 0.001:
		return
	var yaw := atan2(d.x, d.z)
	rotation.y = yaw if dt <= 0.0 else lerp_angle(rotation.y, yaw, clampf(dt * rate, 0.0, 1.0))


## Se queda quieto y gira hasta mirar `point` en `seconds` s.
func _turn_to(point: Vector3, seconds: float) -> void:
	_idle()
	var t := 0.0
	while t < seconds and is_inside_tree():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		_face_toward(point, dt, 10.0)


# --- Pasos, sonido y fogonazo -----------------------------------------------------------------

func _process(_delta: float) -> void:
	if figure == null:
		return
	if figure.current() != &"walk":
		_prev_anim_pos = 0.0
		return
	var pos := figure.animation_player().current_animation_position
	var stepped := pos < _prev_anim_pos  # dio la vuelta al ciclo: apoyo del pie en 0
	for ph in STEP_PHASES:
		if ph > 0.0 and _prev_anim_pos < ph and pos >= ph:
			stepped = true
	if stepped:
		_footstep()
	_prev_anim_pos = pos


func _footstep() -> void:
	var p := _step_players[_step_next]
	_step_next = (_step_next + 1) % _step_players.size()
	p.stream = load(SFX + "footstep_%d.wav" % _rng.randi_range(1, 6))
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.volume_db = STEP_BASE_DB + _rng.randf_range(-1.5, 0.5)
	p.play()


func _build_steps() -> void:
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.name = "Paso%d" % i
		p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = STEP_UNIT_SIZE
		p.max_distance = STEP_MAX_DISTANCE
		p.attenuation_filter_cutoff_hz = 4500.0
		p.attenuation_filter_db = -18.0
		p.position = Vector3(0.0, 0.05, 0.0)
		add_child(p)
		_step_players.append(p)


## Reproduce un sonido 3D suelto en el mundo.
func _play_at(path: String, pos: Vector3, db: float, unit_size: float, max_dist: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	p.stream = load(path)
	p.volume_db = db
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	var host: Node = root if root != null else self
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _build_flash() -> void:
	var m := figure.muzzle()
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 5.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.visible = false
	m.add_child(_flash)
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.amount = 14
	_sparks.lifetime = 0.16
	_sparks.direction = Vector3(0.0, 0.0, -1.0)
	_sparks.spread = 28.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 5.0
	_sparks.gravity = Vector3.ZERO
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	mesh.material = mat
	_sparks.mesh = mesh
	m.add_child(_sparks)
