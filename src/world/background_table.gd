class_name BackgroundTable
extends Node3D
## Vida de una mesa del salón que no es la del humano: dos `CharacterFigure` sentadas
## (una por color; blancas en +Z, negras en -Z) con comportamiento ambiental creíble aunque
## su partida no se vea, y el tablero de piezas estáticas que refleja la partida real.
##
## Comportamiento:
##  - alternan `sit_idle` / `sit_think` / `sit_nervous` (a veces `sit_write`) según de quién
##    es el turno y el reloj de su `BackgroundMatch`;
##  - miran alrededor con `set_look`: al tablero, a otras mesas, a su rival, al árbitro si
##    pasa cerca, hacia los ruidos (`notice_noise`) y, rara vez, al jugador;
##  - cuando su partida hace una jugada, quien movió reproduce `sit_move_piece` ->
##    `sit_press_clock` -> `sit_write` en secuencia (`play_once`); el tablero cambia a la
##    mitad del gesto;
##  - al terminar la partida (`on_game_over`) el ganador se queda quieto y aliviado y el
##    perdedor espera nervioso;
##  - `condemn(seat)` entrega la figura a quien la va a ejecutar (el árbitro): deja de
##    controlarla; `send_away(seat)` es el respaldo sin árbitro (la figura se levanta y se va).
##
## Rendimiento: `tick()` mide la distancia y si la mesa está en pantalla. Las lejanas o fuera
## de cuadro mueven su animación y su esqueleto a mano (`advance`) a 10 o 2 Hz en vez de
## cada fotograma.

## A menos de esta distancia (y a la vista) se anima cada fotograma.
const NEAR_DISTANCE := 6.0
const FAR_STEP := 0.1
const HIDDEN_STEP := 0.5
## Retardo entre la jugada del servidor y el cambio visible en el tablero (mitad del gesto).
const BOARD_DELAY := 0.9
const BOARD_PITCH := -0.5
## Mezclas (s) entre poses: las ambientales y el paso a la jugada son lentas porque las poses
## (recostado pensando / erguido moviendo) son muy distintas.
const AMBIENT_BLEND := 0.8
const MOVE_BLEND := 0.7
const PRESS_BLEND := 0.4
const WRITE_BLEND := 0.6

const POSES_TURN := {&"sit_think": 6.0, &"sit_idle": 2.0}
const POSES_WAIT := {&"sit_idle": 5.0, &"sit_think": 2.0, &"sit_write": 0.6}

var table_index: int = -1
var hall: Hall
var bg: BackgroundMatch
## Posiciones (mundo) de otras mesas con gente, a las que miran de vez en cuando.
var neighbors: Array[Vector3] = []
var figures: Array[CharacterFigure] = [null, null]

var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
## Por asiento: {present, stage, gen, until, pose_t, look_t, calm, noise_pos, noise_until, manual}.
## stage: ambient | move | press | write | relief | doomed | condemned | left.
var _seats: Array[Dictionary] = []
var _decide_acc: float = 0.0
var _anim_acc: float = 0.0
var _tier: int = 0
var _board_due: float = -1.0
var _arbiter_pos: Variant = null
var _cam_pos := Vector3.ZERO
var _game_over: bool = false


## Crea las figuras. `present[color]` dice qué asientos están ocupados. Se añade como hijo
## de la raíz de la mesa (`hall.table_root(index)`), con transformación identidad.
func setup(p_hall: Hall, index: int, p_bg: BackgroundMatch, present: Array, seed_value: int) -> void:
	hall = p_hall
	table_index = index
	bg = p_bg
	name = "VidaMesa%d" % index
	_rng.seed = seed_value * 31 + index * 977 + 5
	for color in 2:
		var s := {
			"present": bool(present[color]), "stage": &"ambient", "gen": 0, "until": 0.0,
			"pose_t": _rng.randf_range(0.0, 3.0), "look_t": _rng.randf_range(0.2, 3.0), "calm": false,
			"noise_pos": Vector3.ZERO, "noise_until": -1.0, "manual": false, "flinch": false,
		}
		_seats.append(s)
		if not s.present:
			continue
		var f := CharacterFigure.new()
		f.name = "Jugador%d" % color
		f.position = Hall.seat_local(color)
		f.rotation.y = PI if color == ChessPiece.WHITE else 0.0
		f.setup(CharacterFigure.bot_look(_rng))
		add_child(f)
		f.play(&"sit_idle", 0.0)
		var ap := f.animation_player()
		ap.seek(_rng.randf() * ap.get_animation(&"sit_idle").length, true)
		f.set_look(0.0, BOARD_PITCH, true)
		figures[color] = f
	if bg != null:
		bg.server.move_made.connect(_on_move)
		_refresh_board()
	else:
		hall.set_table_fen(index, BoardState.START_FEN)


## Figura del asiento `seat` (0 = blancas, 1 = negras); null si no hay o ya se fue.
func figure(seat: int) -> CharacterFigure:
	if seat < 0 or seat > 1 or figures[seat] == null:
		return null
	if _seats[seat].stage == &"left":
		return null
	return figures[seat]


func has_figures() -> bool:
	return figure(0) != null or figure(1) != null


## Etapa actual del asiento (para pruebas y depuración).
func stage_of(seat: int) -> StringName:
	return _seats[seat].stage


# --- Bucle -----------------------------------------------------------------------------------

## Lo llama `GameRoot` cada fotograma. `camera` da la distancia y la visibilidad (puede ser
## null); `arbiter_pos` es la posición del árbitro (Vector3) o null si no hay.
func tick(delta: float, camera: Camera3D, arbiter_pos: Variant) -> void:
	_clock += delta
	_arbiter_pos = arbiter_pos
	_update_tier(camera)
	_decide_acc += delta
	if _decide_acc >= 0.1:
		_decide(_decide_acc)
		_decide_acc = 0.0
	_step_animation(delta)


func _update_tier(camera: Camera3D) -> void:
	var tier := 0
	if camera != null:
		_cam_pos = camera.global_position
		var c := global_position + Vector3(0.0, 1.0, 0.0)
		var near := Vector2(_cam_pos.x - c.x, _cam_pos.z - c.z).length() < 2.5
		var seen := near
		if not seen:
			for p in [c, c + Vector3(0, 0, Hall.SEAT_Z), c - Vector3(0, 0, Hall.SEAT_Z)]:
				if camera.is_position_in_frustum(p):
					seen = true
					break
		if not seen:
			tier = 2
		elif _cam_pos.distance_to(c) > NEAR_DISTANCE:
			tier = 1
	if tier != _tier:
		_tier = tier
		for color in 2:
			_apply_manual(color, tier > 0)


## Pasa la figura a animación manual (a baja frecuencia) o de vuelta al motor.
func _apply_manual(color: int, manual: bool) -> void:
	var f := figures[color]
	if f == null or not is_instance_valid(f):
		return
	var s := _seats[color]
	if s.stage == &"condemned" or s.stage == &"left":
		return
	if s.manual == manual:
		return
	s.manual = manual
	f.set_process(not manual)
	f.animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	f.skeleton().modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL if manual else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE


func _step_animation(delta: float) -> void:
	if _tier == 0:
		return
	_anim_acc += delta
	var step := FAR_STEP if _tier == 1 else HIDDEN_STEP
	if _anim_acc < step:
		return
	for color in 2:
		var f := figures[color]
		if f == null or not _seats[color].manual:
			continue
		f._process(_anim_acc)
		f.animation_player().advance(_anim_acc)
		f.skeleton().advance(_anim_acc)
	_anim_acc = 0.0


# --- Decisiones (10 Hz) ------------------------------------------------------------------------

func _decide(dt: float) -> void:
	if _board_due >= 0.0 and _clock >= _board_due and (_tier < 2 or _game_over):
		_board_due = -1.0
		_refresh_board()
	for color in 2:
		var s := _seats[color]
		if not s.present or s.stage == &"condemned" or s.stage == &"left":
			continue
		if (s.stage == &"write" or s.stage == &"relief") and _clock >= s.until:
			s.stage = &"ambient"
			s.pose_t = 0.0
		var free: bool = s.stage == &"ambient" or s.stage == &"doomed"
		if free:
			s.pose_t -= dt
			if s.pose_t <= 0.0:
				_pick_pose(color)
		if s.stage != &"move" and s.stage != &"press":
			s.look_t -= dt
			if s.look_t <= 0.0:
				_pick_look(color)


func _pick_pose(color: int) -> void:
	var s := _seats[color]
	var f := figures[color]
	var weights: Dictionary
	if f.is_blending() and not s.flinch:
		return  # reintenta en el próximo ciclo (0,1 s): sin cambios de pose sobre otra mezcla
	var low := bg != null and not bg.server.is_over() and bg.server.clock.remaining[color] < 25.0
	if s.flinch:
		s.flinch = false
		weights = {&"sit_nervous": 1.0}
		s.pose_t = _rng.randf_range(2.0, 3.5)
	elif s.stage == &"doomed":
		weights = {&"sit_nervous": 5.0, &"sit_frozen": 3.0, &"sit_idle": 1.0}
	elif s.calm:
		weights = {&"sit_idle": 6.0, &"sit_think": 1.0}
	elif bg != null and not bg.server.is_over() and bg.server.board.side_to_move == color:
		weights = POSES_TURN.duplicate()
		weights[&"sit_nervous"] = 5.0 if low else 1.0
	else:
		weights = POSES_WAIT.duplicate()
		weights[&"sit_nervous"] = 3.0 if low else 0.5
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := _rng.randf() * total
	var chosen: StringName = &"sit_idle"
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			chosen = k
			break
	f.play(chosen, AMBIENT_BLEND)
	if s.pose_t <= 0.0:
		s.pose_t = _rng.randf_range(3.0, 9.0)


func _pick_look(color: int) -> void:
	var s := _seats[color]
	var f := figures[color]
	s.look_t = _rng.randf_range(1.5, 4.5)
	if s.noise_until > _clock:
		f.look_at_point(s.noise_pos + Vector3(0, 1.1, 0))
		s.look_t = _rng.randf_range(1.0, 2.5)
		return
	var roll := _rng.randf()
	if _arbiter_pos != null:
		var ap: Vector3 = _arbiter_pos
		var d := Vector2(ap.x - global_position.x, ap.z - global_position.z).length()
		var reach := 8.0 if s.stage == &"doomed" else 4.5
		if d < reach and (roll < 0.7 or s.stage == &"doomed"):
			f.look_at_point(ap + Vector3(0, 1.5, 0))
			s.look_t = _rng.randf_range(0.8, 1.6) if s.stage == &"doomed" else _rng.randf_range(2.0, 4.0)
			return
	if roll < 0.5:
		f.set_look(_rng.randf_range(-0.15, 0.15), BOARD_PITCH + _rng.randf_range(-0.05, 0.1))
	elif roll < 0.7 and not neighbors.is_empty():
		var n := neighbors[_rng.randi() % neighbors.size()]
		f.look_at_point(n + Vector3(0, 1.1, 0))
	elif roll < 0.82 and figures[1 - color] != null and _seats[1 - color].present:
		f.look_at_point(figures[1 - color].head_global_position())
	elif roll < 0.88 and _tier == 0 and _cam_pos != Vector3.ZERO and _cam_pos.distance_to(global_position) < 6.0:
		f.look_at_point(_cam_pos)
		s.look_t = _rng.randf_range(0.6, 1.4)
	else:
		f.set_look(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.1, 0.25))


## Un ruido en `world_pos`: quienes están sentados voltean a mirar (algunos se sobresaltan).
func notice_noise(world_pos: Vector3) -> void:
	for color in 2:
		var s := _seats[color]
		if not s.present or s.stage == &"condemned" or s.stage == &"left":
			continue
		s.noise_pos = world_pos
		s.noise_until = _clock + _rng.randf_range(2.0, 4.0)
		s.look_t = _rng.randf_range(0.05, 0.5)
		if s.stage == &"ambient" and _rng.randf() < 0.3:
			s.flinch = true
			s.pose_t = _rng.randf_range(0.1, 0.5)


# --- Jugadas y fin de partida --------------------------------------------------------------------

func _on_move(color: int, _uci: String, _info: Dictionary) -> void:
	_board_due = _clock + BOARD_DELAY
	var s := _seats[color]
	if not s.present or s.stage == &"condemned" or s.stage == &"left" or s.stage == &"doomed":
		return
	_sequence(color)


## Mover pieza -> pulsar el reloj -> anotar, con `play_once`; después vuelve a lo ambiental.
func _sequence(color: int) -> void:
	var s := _seats[color]
	var f := figures[color]
	s.gen += 1
	var g: int = s.gen
	s.stage = &"move"
	s.calm = false
	f.set_look(_rng.randf_range(-0.1, 0.1), BOARD_PITCH)
	await f.play_once(&"sit_move_piece", MOVE_BLEND)
	if not _same_job(color, g, &"move"):
		return
	s.stage = &"press"
	await f.play_once(&"sit_press_clock", PRESS_BLEND)
	if not _same_job(color, g, &"press"):
		return
	s.stage = &"write"
	s.until = _clock + _rng.randf_range(1.2, 3.0)
	f.play(&"sit_write", WRITE_BLEND)


func _same_job(color: int, gen: int, stage: StringName) -> bool:
	return is_instance_valid(self) and _seats[color].gen == gen and _seats[color].stage == stage


## La partida terminó: el ganador se queda quieto y aliviado; el perdedor espera su suerte.
func on_game_over(winner: int) -> void:
	_game_over = true
	_board_due = _clock + 0.3
	for color in 2:
		var s := _seats[color]
		if not s.present or s.stage == &"condemned" or s.stage == &"left":
			continue
		s.gen += 1
		var f := figures[color]
		if color == winner:
			s.stage = &"relief"
			s.until = _clock + _rng.randf_range(2.5, 4.0)
			s.calm = true
			f.play(&"sit_frozen", 1.0)
			f.set_look(0.0, BOARD_PITCH)
			s.look_t = s.until - _clock
		else:
			s.stage = &"doomed"
			s.pose_t = 0.0
			s.look_t = 0.0
			f.set_look(0.0, BOARD_PITCH)


## Entrega la figura del asiento a quien la va a controlar (el árbitro): deja de animarla.
func condemn(seat: int) -> CharacterFigure:
	var f := figure(seat)
	if f == null:
		return null
	var s := _seats[seat]
	s.gen += 1
	_apply_manual(seat, false)
	s.stage = &"condemned"
	return f


## Respaldo sin árbitro: la figura se pone de pie, se da la vuelta y se aleja en la oscuridad.
func send_away(seat: int) -> void:
	var f := figure(seat)
	if f == null:
		return
	var s := _seats[seat]
	s.gen += 1
	_apply_manual(seat, false)
	s.stage = &"left"
	f.set_look(0.0, 0.0)
	await f.play_once(&"stand_flee")
	if not is_instance_valid(f):
		return
	f.play(&"stand_flee_cycle", 0.1)
	var away := Hall.seat_local(seat) + Vector3(0.0, 0.0, 3.2 if seat == ChessPiece.WHITE else -3.2)
	var tw := f.create_tween()
	tw.tween_property(f, "rotation:y", f.rotation.y + PI, 0.35)
	tw.tween_property(f, "position", away, 3.0)
	tw.tween_callback(func() -> void: f.visible = false)


# --- Tablero ---------------------------------------------------------------------------------------

func _refresh_board() -> void:
	if bg != null:
		hall.set_table_board(table_index, bg.server.board.squares)
