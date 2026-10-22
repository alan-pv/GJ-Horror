class_name StressModule
extends Node
## Módulo de estrés del jugador humano. Alimenta un `StressModel` con lo que ocurre en la
## partida (reloj, torneo, material, disparos, acusaciones, miradas, árbitro, apagón...) y lo
## traduce en efectos suaves: balanceo y sacudida de cámara, visión de túnel (desenfoque de los
## bordes), viñeta que late, latido y respiración, filtro paso bajo del bus SFX, zumbido tras un
## disparo cercano y FOV más cerrado. Además escribe el valor en `root.extra_stress` (la mano tiembla).
##
## Argumentos de depuración (después de `--`):
##   --no-stress     desactiva todos los efectos
##   --stress=V      fija el estrés en V (0..1), p. ej. para capturas

const SFX := "res://assets/audio/sfx/"
const BLUR_SHADER := "res://assets/shaders/stress_blur.gdshader"
## Capa del desenfoque: sobre el 3D, por debajo del HUD (10).
const BLUR_LAYER := 5

# Cámara.
## Balanceo máximo (grados) con estrés 1.
const SWAY_MAX_DEG := 1.5
## Bamboleo de respiración (grados) en calma y con estrés 1.
const BREATH_DEG_CALM := 0.08
const BREATH_DEG_MAX := 0.35
## Sacudida máxima (grados) con trauma 1 (se aplica trauma²).
const SHAKE_MAX_DEG := 3.0
const FOV_CALM := PlayerController.BASE_FOV
const FOV_MAX_STRESS := 57.0

# Suavizado del valor mostrado (constantes de tiempo, s).
const SMOOTH_UP := 0.25
const SMOOTH_DOWN := 0.8

# Disparos.
const NEAR_RANGE := 6.0
const DEAF_RANGE := 4.0
const DISTRACTION_RANGE := 9.0
const SHAKE_TABLE := 1.0
const SHAKE_NEAR := 0.7
const SHAKE_FAR := 0.25

# Desenfoque periférico.
const BLUR_MIN_STRESS := 0.05

# Audio.
const AUDIO_ON_STRESS := 0.3
const PANIC_ON_STRESS := 0.6
const SILENT_DB := -60.0
const HEART_DB_MAX := -8.0
const PANIC_DB_MAX := -14.0
## Latidos por minuto que tiene `heartbeat_loop.wav` sin alterar (dos golpes en 1,6 s).
const HEART_LOOP_BPM := 75.0
const CUTOFF_OPEN := 20500.0
const CUTOFF_STRESSED := 2500.0
const CUTOFF_DEAF := 500.0
const DEAF_SECONDS := 1.5
const RING_DB := -6.0

var root: GameRoot
var model := StressModel.new()
## Valor suavizado que usan los efectos.
var shown: float = 0.0

var _enabled: bool = true
var _fixed: float = -1.0
var _active: bool = false
var _time: float = 0.0
var _heart_phase: float = 0.0
var _noise := FastNoiseLite.new()
var _blur_layer: CanvasLayer
var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _heart: AudioStreamPlayer
var _panic: AudioStreamPlayer
var _ring: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _bus: int = -1
var _deaf_left: float = 0.0
var _condemned: bool = false
var _was_dark: bool = false
var _watched_cheat: Variant = null
var _last_material_check: float = 0.0
var _material: float = 0.0


func install(p_root: GameRoot) -> void:
	name = "ModuloEstres"
	root = p_root
	var args := root.get_args()
	_enabled = not args.has("no-stress")
	if args.has("stress"):
		_fixed = clampf(float(args["stress"]), 0.0, 1.0)
	if not _enabled:
		set_process(false)
		return
	_noise.seed = 7
	_noise.frequency = 1.0
	add_to_group(Distraction.GROUP)
	_build_blur()
	_build_audio()
	root.human_condemned.connect(_on_condemned)
	var server := root.server
	if server != null:
		server.move_made.connect(_on_move_made)
		server.accusation_started.connect(_on_accusation_started)
		server.accusation_resolved.connect(_on_accusation_resolved)
	root.match_started.connect(func(_s: MatchServer) -> void: _active = true)
	if root.match_begun():
		_active = true


func _exit_tree() -> void:
	# El bus persiste entre recargas de escena: se deja neutro.
	if _bus != -1 and _lowpass != null:
		_lowpass.cutoff_hz = CUTOFF_OPEN
		var idx := _lowpass_index()
		if idx != -1:
			AudioServer.set_bus_effect_enabled(_bus, idx, false)


# --- Entradas ---------------------------------------------------------------------------------

func _on_condemned() -> void:
	_condemned = true
	model.condemn()
	model.add_shake(0.5)
	for p in [_heart, _panic]:
		if p != null:
			p.stop()


func _on_move_made(color: int, _uci: String, info: Dictionary) -> void:
	var me := root.human_color
	if color == me:
		return
	var captured := int(info.get("captured", ChessPiece.NONE))
	if captured != ChessPiece.NONE and ChessPiece.color_of(captured) == me:
		var t := ChessPiece.type_of(captured)
		if t == ChessPiece.ROOK or t == ChessPiece.QUEEN:
			model.add_spike(StressModel.SPIKE_MAJOR_LOST)
	if ChessRules.in_check(root.server.board, me):
		model.add_spike(StressModel.SPIKE_CHECK)


func _on_accusation_started(accuser: int) -> void:
	if accuser != root.human_color:
		model.set_sustained(&"accused", StressModel.SUSTAIN_ACCUSED)


func _on_accusation_resolved(accuser: int, correct: bool, _warnings: int) -> void:
	model.set_sustained(&"accused", 0.0)
	if accuser == root.human_color and not correct:
		model.add_spike(StressModel.SPIKE_FALSE_ACCUSE)


## Avisos del salón (ver `Distraction`).
func on_distraction(kind: StringName, pos: Vector3, table: int = -1, _chance: float = -1.0) -> void:
	if not _enabled or root == null or root.player == null:
		return
	var dist := pos.distance_to(root.player.global_position)
	match kind:
		&"gunshot":
			if table == HallLayout.human_table:
				model.add_spike(StressModel.SPIKE_SHOT_TABLE)
				model.add_shake(SHAKE_TABLE)
			elif dist < NEAR_RANGE:
				model.add_spike(StressModel.SPIKE_SHOT_NEAR)
				model.add_shake(SHAKE_NEAR)
			else:
				model.add_spike(StressModel.SPIKE_SHOT_FAR)
				model.add_shake(SHAKE_FAR)
			if not _condemned and (table == HallLayout.human_table or dist < DEAF_RANGE):
				_start_deafness()
		&"accusation":
			if table != HallLayout.human_table:
				model.add_spike(StressModel.SPIKE_OTHER_DRAMA)
		&"plea":
			if dist < DISTRACTION_RANGE and table != HallLayout.human_table:
				model.add_spike(StressModel.SPIKE_OTHER_DRAMA)


func _poll_state() -> void:
	var server := root.server
	var me := root.human_color
	# El rival mira mientras haces trampa: una vez por trampa.
	var cheat: Variant = server.active_cheat(me)
	if cheat == null:
		_watched_cheat = null
	elif cheat != _watched_cheat and server.is_looking(root.rival_color):
		_watched_cheat = cheat
		model.add_spike(StressModel.SPIKE_RIVAL_WATCHES)
	model.set_sustained(&"arbiter", StressModel.SUSTAIN_ARBITER if server.is_arbiter_near() else 0.0)
	var dark := server.is_blackout()
	if dark and not _was_dark:
		model.add_spike(StressModel.SPIKE_BLACKOUT)
	_was_dark = dark
	# Piso: reloj propio, torneo y material (el material, dos veces por segundo basta).
	_last_material_check -= get_process_delta_time()
	if _last_material_check <= 0.0:
		_last_material_check = 0.5
		_material = StressModel.material_deficit(server.board, me)
	var over := server.is_over()
	var remaining := INF if over else server.clock.remaining[me]
	model.set_floor_inputs(remaining, root.players_left(), root.manager.player_count, 0.0 if over else _material)


# --- Efectos ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active or root.server == null or root.player == null:
		return
	_time += delta
	if _fixed < 0.0:
		_poll_state()
		model.step(delta)
	var target := _fixed if _fixed >= 0.0 else model.value
	var tau := SMOOTH_UP if target > shown else SMOOTH_DOWN
	shown = lerpf(shown, target, 1.0 - exp(-delta / tau))
	if _fixed >= 0.0:
		shown = _fixed
	if root.extra_stress.size() > root.human_color:
		root.extra_stress[root.human_color] = shown
	_heart_phase += delta * StressModel.bpm(shown) / 60.0
	_update_camera()
	_update_blur()
	_update_hud()
	_update_audio(delta)


func _noise_at(channel: float, speed: float) -> float:
	return _noise.get_noise_2d(_time * speed, channel * 31.7)


func _update_camera() -> void:
	var player := root.player
	if player.debug_camera:
		return
	var sway := deg_to_rad(SWAY_MAX_DEG) * shown
	var breath_hz := lerpf(0.22, 0.6, shown)
	var breath := deg_to_rad(lerpf(BREATH_DEG_CALM, BREATH_DEG_MAX, shown)) * sin(_time * TAU * breath_hz)
	var trauma := model.shake_trauma * model.shake_trauma
	var shake := deg_to_rad(SHAKE_MAX_DEG) * trauma
	var rot := Vector3(
		_noise_at(0.0, 0.45) * sway + breath + _noise_at(3.0, 30.0) * shake,
		_noise_at(1.0, 0.4) * sway + _noise_at(4.0, 30.0) * shake,
		_noise_at(2.0, 0.35) * sway * 0.6 + _noise_at(5.0, 30.0) * shake * 0.8)
	player.set_camera_sway(rot)
	if not root.get_args().has("shot-rel"):
		player.camera.fov = lerpf(FOV_CALM, FOV_MAX_STRESS, shown)


func _build_blur() -> void:
	if not ResourceLoader.exists(BLUR_SHADER):
		return
	_blur_layer = CanvasLayer.new()
	_blur_layer.layer = BLUR_LAYER
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = load(BLUR_SHADER)
	_blur_rect.material = _blur_mat
	_blur_rect.visible = false
	_blur_layer.add_child(_blur_rect)
	add_child(_blur_layer)


func _update_blur() -> void:
	if _blur_rect == null:
		return
	# Sin estrés el rectángulo se oculta: no cuesta ni una lectura de pantalla.
	_blur_rect.visible = shown > BLUR_MIN_STRESS
	if _blur_rect.visible:
		_blur_mat.set_shader_parameter("amount", shown)


func _update_hud() -> void:
	if root.hud != null:
		root.hud.set_stress_vignette(shown, StressModel.heart_pulse(_heart_phase))


# --- Audio ------------------------------------------------------------------------------------

func _sfx_bus() -> StringName:
	return &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"


func _loop_player(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _sfx_bus()
	p.stream = load(SFX + file)
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _build_audio() -> void:
	_heart = _loop_player("heartbeat_loop.wav")
	_panic = _loop_player("panic_breath_loop.wav")
	_ring = AudioStreamPlayer.new()
	_ring.bus = _sfx_bus()
	_ring.stream = load(SFX + "ear_ring.wav")
	_ring.volume_db = RING_DB
	add_child(_ring)
	_bus = AudioServer.get_bus_index(_sfx_bus())
	if _bus == -1:
		return
	# El filtro se añade una sola vez al bus (persiste entre recargas de escena).
	var idx := _lowpass_index()
	if idx == -1:
		AudioServer.add_bus_effect(_bus, AudioEffectLowPassFilter.new())
		idx = _lowpass_index()
	_lowpass = AudioServer.get_bus_effect(_bus, idx) as AudioEffectLowPassFilter
	_lowpass.cutoff_hz = CUTOFF_OPEN
	AudioServer.set_bus_effect_enabled(_bus, idx, true)


func _lowpass_index() -> int:
	if _bus == -1:
		return -1
	for i in AudioServer.get_bus_effect_count(_bus):
		if AudioServer.get_bus_effect(_bus, i) is AudioEffectLowPassFilter:
			return i
	return -1


func _start_deafness() -> void:
	_deaf_left = DEAF_SECONDS
	if _ring != null:
		_ring.play()


func _update_audio(delta: float) -> void:
	if _condemned:
		# La ejecución en primera persona pone su propio latido y respiración.
		_set_cutoff(CUTOFF_OPEN)
		return
	_set_loop(_heart, HEART_DB_MAX, AUDIO_ON_STRESS, true)
	_set_loop(_panic, PANIC_DB_MAX, PANIC_ON_STRESS, false)
	var cutoff := lerpf(CUTOFF_OPEN, CUTOFF_STRESSED, smoothstep(0.6, 1.0, shown))
	if _deaf_left > 0.0:
		_deaf_left -= delta
		# Se abre en escala logarítmica (el oído oye frecuencias así).
		var open := 1.0 - clampf(_deaf_left / DEAF_SECONDS, 0.0, 1.0)
		cutoff = minf(cutoff, CUTOFF_DEAF * pow(CUTOFF_OPEN / CUTOFF_DEAF, open * open))
	_set_cutoff(cutoff)


func _set_loop(p: AudioStreamPlayer, max_db: float, from_stress: float, is_heart: bool) -> void:
	if p == null:
		return
	var t := clampf((shown - from_stress) / (1.0 - from_stress), 0.0, 1.0)
	if t <= 0.0:
		if p.playing:
			p.stop()
		return
	p.volume_db = lerpf(SILENT_DB, max_db, sqrt(t))
	if is_heart:
		p.pitch_scale = clampf(StressModel.bpm(shown) / HEART_LOOP_BPM, 0.8, 1.6)
	if not p.playing:
		p.play()


func _set_cutoff(hz: float) -> void:
	if _lowpass != null:
		_lowpass.cutoff_hz = hz
