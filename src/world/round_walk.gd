class_name RoundWalk
extends Node
## Paseo en primera persona entre rondas: tras ganar, el cuerpo del jugador se levanta (`stand_up`,
## con la silla que se retira siguiendo sus piernas: `ChairFollow`), camina por los pasillos
## (`walk`, 1,1 m/s) hasta la silla de la mesa nueva y se sienta (`sit_down`). La cámara va en los
## ojos de la figura. Todo ocurre en la escena vieja, donde la mesa destino está en las coordenadas
## de la mesa actual (`HallWalk.route`); al sentarse `GameRoot` recarga la escena y la nueva (con el
## salón desplazado) deja la cámara en la misma pose, así que el corte no se nota.
##
## Para que el corte no delate nada, en el primer parpadeo (con los ojos cerrados) la mesa destino se
## deja como la verá la escena nueva: sus ocupantes viejos desaparecen, el rival de la ronda ya está
## sentado (figura igual a la de `OpponentAvatar`), el tablero muestra la posición inicial girada
## según el color y la lámpara toma el aspecto de la del humano. Espacio salta el paseo (corte directo).
##
## Quien lo usa: `GameRoot._walk_to_next_round`. Se instala como hijo de `GameRoot`.

## Se emite al terminar (o al saltarlo); `GameRoot` recarga entonces la escena.
signal finished

const SFX := "res://assets/audio/sfx/"
const SPEED := CharacterFigure.WALK_SPEED
## Frecuencia (1/s) del resorte amortiguado con que el cuerpo gira, y su velocidad angular máxima.
const TURN_OMEGA := 5.5
const TURN_MAX := 3.0
## Metros por delante sobre la ruta a los que apunta el cuerpo (empieza a girar antes del vértice).
const LOOK_AHEAD := 0.8
## Segundos tras empezar a levantarse en que se cierran los ojos para vaciar las mesas.
const BLINK_DELAY := 0.4
## Distancia al destino a partir de la cual se retira la silla y se ajusta la lámpara.
const ARRIVAL_PREP := 3.2
## Metros antes de la silla en que empieza a girarse hacia la mesa.
const FINAL_TURN := 1.4
## Segundos del final de `sit_down` en que la cámara se funde con la pose de reposo.
const CAMERA_BLEND := 0.9
## Cabeceo de la mirada al caminar (rad; algo hacia abajo).
const WALK_PITCH := deg_to_rad(-10.0)

var root: GameRoot
var from_table: int = -1
var to_table: int = -1
var path: Array[Vector3] = []
var skipped: bool = false
var done: bool = false

var _player: PlayerController
var _body: SeatedFigure
var _hall: Hall
var _from_chair: Node3D
var _to_chair: Node3D
## Transformación original de la silla destino (antes de retirarla).
var _to_home := Transform3D.IDENTITY
var _pos := Vector3.ZERO
var _yaw: float = PI
var _running: bool = false
var _eye_offset := Vector3.ZERO
var _blend: float = 0.0
var _final_eye := Vector3.ZERO
var _to_prepared: bool = false
var _step_player: AudioStreamPlayer
var _prev_phase: float = 0.0
var _rng := RandomNumberGenerator.new()
var _rival_proxy: CharacterFigure
var _next_color: int = ChessPiece.WHITE
var _next_rival: int = -1
var _yaw_vel: float = 0.0
var _blink: BlinkOverlay
var _skipping: bool = false


## `p_to_table`: mesa destino (índice, en las coordenadas de la escena actual); `next_color`: color
## del humano en la ronda siguiente; `next_rival`: id del rival siguiente (-1 si descansa).
func setup(p_root: GameRoot, p_to_table: int, next_color: int, next_rival: int) -> void:
	name = "PaseoRonda"
	root = p_root
	from_table = HallLayout.human_table
	to_table = p_to_table
	_next_color = next_color
	_next_rival = next_rival
	path = HallWalk.route(from_table, to_table)
	_rng.randomize()


## Duración aproximada (s) del paseo entero (levantarse + caminar + sentarse).
func estimated_seconds() -> float:
	return 2.2 + HallWalk.length(from_table, path) / SPEED + 2.4


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		skip()
		get_viewport().set_input_as_handled()


## Salta el paseo: corte directo a la escena nueva.
func skip() -> void:
	if done or _skipping:
		return
	skipped = true
	_skipping = true
	await _close_eyes()
	_finish()


func _finish() -> void:
	if done:
		return
	done = true
	_running = false
	finished.emit()


# --- Guion ---------------------------------------------------------------------------------

## Corrutina: se lanza sin `await` o se espera hasta `finished`.
func run() -> void:
	_player = root.player
	_body = _player.body
	_hall = root.hall
	if path.is_empty() or _body == null:
		_finish()
		return
	_from_chair = _hall.chair(from_table, 0)
	_to_chair = _hall.chair(to_table, 0)
	_to_home = _to_chair.global_transform
	_prepare_player()
	_blink = BlinkOverlay.new()
	root.add_child(_blink)
	_running = true
	# Al levantarse la mirada sube al frente (la pose de reposo mira el tablero).
	var yaw0 := _player.yaw
	var pitch0 := _player.pitch
	create_tween().tween_method(func(k: float) -> void:
		if _player.walking:
			_player.set_look(lerpf(yaw0, 0.0, k), lerpf(pitch0, WALK_PITCH, k)), 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	_step_player = AudioStreamPlayer.new()
	_step_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	_step_player.volume_db = -9.0
	add_child(_step_player)

	_blink_clear_tables()
	if _body.has_role(&"stand_up"):
		_play_at_chair(SFX + "chair_scrape.wav", _from_chair.global_position, -8.0)
		_chair_follow(_from_chair, _from_chair.global_transform, true, _body.clip_length(&"stand_up"))
		await _body.play_role_once(&"stand_up")
		if _aborted():
			return
	await _walk()
	if _aborted():
		return
	await _sit()
	if _aborted():
		return
	await _close_eyes()
	_finish()


## Parpadeo al levantarse: con los ojos cerrados se hacen todos los cambios de la ronda nueva
## (`GameRoot.clear_tables_for_next_round`): desaparecen los cadáveres y los ganadores de sus mesas
## viejas, las mesas de la ronda se pueblan con sus emparejamientos y la mesa destino se prepara
## (`_prepare_destination`).
func _blink_clear_tables() -> void:
	await get_tree().create_timer(BLINK_DELAY).timeout
	if _aborted() or _skipping:
		return
	await _shot_arg("walk-pre-shot")
	await _blink.close()
	if root.has_method(&"clear_tables_for_next_round"):
		root.call(&"clear_tables_for_next_round")
	# Con los ojos cerrados también se sienta al rival en la mesa destino: al abrirlos todo el salón
	# ya está como en la ronda nueva.
	_prepare_destination()
	if _aborted() or _skipping:
		return
	await get_tree().create_timer(0.1).timeout
	if _aborted() or _skipping:
		return
	await _blink.open()
	_mid_shot()


## `--walk-pre-shot=ruta` (depuración): captura justo antes del primer parpadeo, con el salón
## todavía como lo dejó la ronda (ver `_blink_clear_tables`).
func _shot_arg(key: String) -> void:
	var args: Dictionary = root.get_args()
	if not args.has(key):
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(args[key]))


## `--walk-mid-shot=ruta` (depuración): ~1 s después de abrir los ojos tras el primer parpadeo guarda
## una captura, para compararla con `--walk-start-shot` (el salón debe verse igual).
func _mid_shot() -> void:
	var args: Dictionary = root.get_args()
	if not args.has("walk-mid-shot"):
		return
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(args["walk-mid-shot"]))


## Cierra los ojos y deja la marca para que la escena nueva los abra (`BlinkOverlay.resume_if_pending`).
func _close_eyes() -> void:
	BlinkOverlay.pending_open = true
	if _blink != null and is_instance_valid(_blink) and _blink.is_inside_tree():
		await _blink.close()


func _aborted() -> bool:
	return done or not is_inside_tree()


## El cuerpo deja de ser hijo del control del jugador (que pasará a seguir sus ojos) y los brazos
## sueltan el IK.
func _prepare_player() -> void:
	var xf := _body.global_transform
	_body.top_level = true
	_body.global_transform = xf
	_pos = _body.global_position
	_yaw = _body.global_rotation.y
	_player.begin_walk()
	var animator: HandAnimator = root.animators[root.human_color]
	if animator != null:
		animator.set_process(false)
	# Continuidad con la cámara actual: el desfase con el ojo del hueso se reabsorbe.
	_eye_offset = _player.global_position - _body.eye_global_position()
	_final_eye = Vector3(HallLayout.table_position(to_table).x, HallWalk.seat_point(to_table).y, HallLayout.table_position(to_table).z) \
			+ PlayerController.EYE_POSITION
	if root.hud != null:
		root.hud.set_walk_mode(true)
		root.hud.show_banner(_banner_title(), _banner_body(), "SPACE: skip the walk")


func _banner_title() -> String:
	var m := root.manager
	return m.round_label()


func _banner_body() -> String:
	var m := root.manager
	var t := "Table %d" % HallLayout.number_of(to_table)
	if m.is_final:
		t += " · the final"
	else:
		t += " · %d players left" % m.remaining_count()
	if _next_rival < 0:
		t += "\nYou advance without playing"
	return t


func _walk() -> void:
	_body.play(&"walk", 0.35)
	_prev_phase = 0.0
	for i in path.size():
		var target := path[i]
		var last := i == path.size() - 1
		while true:
			await get_tree().process_frame
			if _aborted():
				return
			var dt := get_process_delta_time()
			var to := target - _pos
			to.y = 0.0
			var d := to.length()
			# Rumbo hacia un punto adelantado de la ruta (empieza a girar antes del vértice); en
			# el último tramo, hacia la mesa. El resorte suaviza el giro.
			var ahead := HallWalk.look_ahead(_pos, path, i, LOOK_AHEAD) - _pos
			ahead.y = 0.0
			var want := HallWalk.yaw_for(ahead) if ahead.length() > 0.05 else _yaw
			var left := _remaining(i, d)
			if last and left < FINAL_TURN:
				want = lerp_angle(want, PI, 1.0 - clampf(left / FINAL_TURN, 0.0, 1.0))
			_turn_step(want, dt)
			if d < 0.02:
				break
			_pos += to / d * minf(SPEED * dt, d)
			_apply_body()
			_footsteps()
			if not _to_prepared and left < ARRIVAL_PREP + 2.0:
				_prepare_destination()
			if _to_prepared and left < ARRIVAL_PREP:
				_retire_destination_chair()
	var goal := path[path.size() - 1]
	_pos = Vector3(goal.x, 0.0, goal.z)
	_apply_body()


## Un paso del giro suave del cuerpo hacia el rumbo `want`.
func _turn_step(want: float, dt: float) -> void:
	var r := HallWalk.smooth_yaw(_yaw, _yaw_vel, want, dt, TURN_OMEGA, TURN_MAX)
	_yaw = r.x
	_yaw_vel = r.y


## Metros que faltan para llegar a la silla desde el punto actual yendo al tramo `i`.
func _remaining(i: int, d_to_target: float) -> float:
	var rest := d_to_target
	for k in range(i + 1, path.size()):
		rest += Vector2(path[k].x - path[k - 1].x, path[k].z - path[k - 1].z).length()
	return rest


func _sit() -> void:
	_prepare_destination()
	_retire_destination_chair()
	if root.hud != null:
		root.hud.hide_banner(1.0)
	var dur := _body.clip_length(&"sit_down")
	_chair_follow(_to_chair, _to_home, false, dur)
	_body.play_role_once(&"sit_down")
	# Al final del movimiento la cámara se funde con la pose de reposo de la escena nueva.
	var t := 0.0
	_player.walking = false
	_rest_hands()
	while t < dur:
		await get_tree().process_frame
		if _aborted():
			return
		var dt := get_process_delta_time()
		t += dt
		_turn_step(PI, dt)
		_apply_body()
		_blend = smoothstep(0.0, 1.0, clampf((t - (dur - CAMERA_BLEND)) / CAMERA_BLEND, 0.0, 1.0))
		_player.set_look(lerpf(_player.yaw, 0.0, _blend), lerpf(_player.pitch, PlayerController.rest_pitch(), _blend))
	_blend = 1.0
	_yaw = PI
	_apply_body()
	_body.global_position = Vector3(_pos.x, HallWalk.seat_point(to_table).y, _pos.z)


## Las manos vuelven a su reposo sobre la mesa destino (donde las dejará la escena nueva).
func _rest_hands() -> void:
	var tp := HallLayout.table_position(to_table)
	var base := Vector3(tp.x, HallWalk.seat_point(to_table).y, tp.z)
	var top := BoardView.TABLE_TOP + 0.03
	_player.hand_rig.rest_at(base + Vector3(0.34, top, 0.40), 20.0)
	_player.idle_rig.rest_at(base + Vector3(-0.34, top, 0.40), 20.0)
	for rig in [_player.hand_rig, _player.idle_rig]:
		rig.set_ik_weight(1.0, 0.8)


func _apply_body() -> void:
	_body.global_position = Vector3(_pos.x, HallLayout.floor_y(_pos), _pos.z)
	_body.global_rotation.y = _yaw


## Cada fotograma: la cámara del jugador en los ojos de la figura (con el desfase inicial que se
## reabsorbe) y, al final, fundida con la pose de reposo.
func _process(delta: float) -> void:
	if not _running or _body == null:
		return
	_eye_offset = _eye_offset.lerp(Vector3.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	var eye := _body.eye_global_position() + _eye_offset
	if _blend > 0.0:
		eye = eye.lerp(_final_eye, _blend)
	_player.global_position = eye
	_player.global_rotation = Vector3(0.0, _body.global_rotation.y + PI, 0.0)


func _footsteps() -> void:
	var player := _body.animation_player()
	var cycle := maxf(player.current_animation_length, 0.01)
	var phase := fmod(player.current_animation_position / cycle, 1.0)
	if (_prev_phase < 0.5 and phase >= 0.5) or phase < _prev_phase:
		_step_player.stream = load(SFX + "footstep_%d.wav" % _rng.randi_range(1, 6))
		_step_player.pitch_scale = _rng.randf_range(0.93, 1.07)
		_step_player.play()
	_prev_phase = phase


# --- Silla --------------------------------------------------------------------------------

## Mantiene `chair` a la distancia que pide la pose real del cuerpo (ver `ChairFollow`) durante
## `seconds`. `standing_up`: sale al levantarse; si no, vuelve a su sitio al sentarse. Corrutina
## sin `await`. `home` = transformación mundial de la silla en su sitio.
func _chair_follow(chair: Node3D, home: Transform3D, standing_up: bool, seconds: float) -> void:
	var back := -home.basis.z
	var full := HallWalk.CHAIR_BACK
	var r := 0.0 if standing_up else full
	var t := 0.0
	while t < seconds and is_inside_tree() and not done:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var want := ChairFollow.desired(ChairFollow.rise_progress(_body, home), full)
		var fade := 0.0 if standing_up else clampf(t / maxf(seconds, 0.01), 0.0, 1.0)
		r = ChairFollow.step(r, ChairFollow.need(_body, home), want, 0.0, dt, fade)
		chair.global_position = home.origin + back * r
	if is_instance_valid(chair):
		chair.global_position = home.origin + back * (full if standing_up else 0.0)


## La silla de la mesa destino se echa hacia atrás para dejar sitio (una sola vez).
var _chair_retired: bool = false


func _retire_destination_chair() -> void:
	if _chair_retired:
		return
	_chair_retired = true
	_play_at_chair(SFX + "chair_scrape.wav", _to_chair.global_position, -6.0)
	var back := -_to_home.basis.z
	var tw := create_tween()
	tw.tween_method(func(r: float) -> void:
		if is_instance_valid(_to_chair):
			_to_chair.global_position = _to_home.origin + back * r, 0.0, HallWalk.CHAIR_BACK, 0.7).set_trans(Tween.TRANS_SINE)


func _play_at_chair(path_s: String, pos: Vector3, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	p.stream = load(path_s)
	p.volume_db = db
	p.unit_size = 4.0
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


# --- Mesa destino ----------------------------------------------------------------------------

## Deja la mesa destino como la verá la escena nueva (ver la cabecera). Se hace una sola vez.
func _prepare_destination() -> void:
	if _to_prepared:
		return
	_to_prepared = true
	var bt: BackgroundTable = root.bg_tables.get(to_table)
	if bt != null:
		for seat in 2:
			var f := bt.figure(seat)
			if f != null:
				f.visible = false
	_hall.set_table_start_position(to_table, _next_color)
	_hall.make_lamp_like_main(to_table, 0.0)
	if _next_rival >= 0:
		var look_rng := RandomNumberGenerator.new()
		look_rng.seed = hash("rival%d" % _next_rival)
		var look := CharacterFigure.bot_look(look_rng)
		_rival_proxy = CharacterFigure.new()
		_rival_proxy.name = "RivalSiguiente"
		root.add_child(_rival_proxy)
		_rival_proxy.setup(CharacterFigure.bot_look(_rng, look))
		var tp := HallLayout.table_position(to_table)
		_rival_proxy.global_position = Vector3(tp.x, HallWalk.seat_point(to_table).y, tp.z) + GameRoot.RIVAL_SEAT
		_rival_proxy.play_role(&"sit_wait", _rng)
