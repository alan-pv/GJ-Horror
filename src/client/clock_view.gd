class_name ClockView
extends Node3D
## Reloj de ajedrez 3D al costado de la mesa, como uno de torneo: cada cara tiene
## DOS pantallas (`Label3D`), una por jugador, y un botón que se hunde al pulsarlo.
## En cada cara el tiempo de su dueño va a la izquierda (visto desde su asiento) y
## el del rival a la derecha; la pantalla del que corre se ve encendida.
## Hace tic-tac (`AudioStreamPlayer3D`, bus SFX) cada segundo que corre un reloj.
##
## El lado cercano (humano) está en +Z; el lejano, en -Z.

const POSITION := Vector3(0.42, BoardView.TABLE_TOP, 0.0)
const BUTTON_TRAVEL := 0.008
const DISPLAY_TILT_DEG := 38.0
const BODY_SIZE := Vector3(0.14, 0.04, 0.23)
const COLUMN_X := 0.033
const TICK_PATH := "res://assets/audio/sfx/clock_tick.wav"
const TOCK_PATH := "res://assets/audio/sfx/clock_tock.wav"
## Por debajo de esto (del jugador) el tic-tac se vuelve más intenso.
const URGENT_SECONDS := 20.0

const DIM := Color(0.45, 0.38, 0.2)
const LIT := Color(1.0, 0.8, 0.35)
const LIT_LOW := Color(1.0, 0.35, 0.2)

var near_color: int = ChessPiece.WHITE
var _faces: Array[Dictionary] = [{}, {}]  # por lado: 0 = cercano, 1 = lejano
var _running: int = -1
var _last_text: Array[String] = ["", ""]  # por color
var _last_sec: Array[int] = [-1, -1]  # por color: segundo entero mostrado
var _remaining: Array[float] = [180.0, 180.0]
var _case_mat: StandardMaterial3D
var _tick_player: AudioStreamPlayer3D
var _tick_streams: Array[AudioStream] = []
var _tick_toggle: bool = false


func setup(p_near_color: int) -> void:
	near_color = p_near_color
	position = POSITION
	name = "Reloj"
	_case_mat = StandardMaterial3D.new()
	_case_mat.albedo_color = Color(0.09, 0.09, 0.10)
	_case_mat.roughness = 0.55
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = BODY_SIZE
	body.mesh = bm
	body.material_override = _case_mat
	body.position = Vector3(0, 0.02, 0)
	add_child(body)
	for side in 2:
		_faces[side] = _build_side(side)
	_build_tick()
	set_running(-1)


func _side_of(color: int) -> int:
	return 0 if color == near_color else 1


## Color del dueño de la cara `side`.
func _owner_of(side: int) -> int:
	return near_color if side == 0 else ChessPiece.opposite(near_color)


func _build_side(side: int) -> Dictionary:
	# Se construye el lado +Z y el lejano es el mismo girado 180° en Y.
	var root := Node3D.new()
	root.name = "LadoCercano" if side == 0 else "LadoLejano"
	root.rotation.y = 0.0 if side == 0 else PI
	add_child(root)

	var face := Node3D.new()
	face.position = Vector3(0, 0.043, 0.035)
	face.rotation.x = deg_to_rad(DISPLAY_TILT_DEG)
	root.add_child(face)

	var owner_color := _owner_of(side)
	var labels := {}
	var plates := {}
	# Visto desde el asiento de la cara, +X local queda a la derecha en ambas.
	for col in 2:
		var color := owner_color if col == 0 else ChessPiece.opposite(owner_color)
		var cx := -COLUMN_X if col == 0 else COLUMN_X
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = Color(0.05, 0.07, 0.05)
		plate_mat.emission_enabled = true
		plate_mat.emission = Color(1.0, 0.65, 0.2)
		plate_mat.emission_energy_multiplier = 0.0
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.064, 0.003, 0.05)
		plate.mesh = pm
		plate.material_override = plate_mat
		plate.position = Vector3(cx, 0, 0)
		face.add_child(plate)
		plates[color] = plate_mat

		var label := Label3D.new()
		label.text = "3:00"
		label.font_size = 44
		label.pixel_size = 0.00055
		label.shaded = false
		label.double_sided = false
		label.modulate = DIM
		label.outline_size = 0
		label.rotation.x = deg_to_rad(-90.0)
		label.position = Vector3(cx, 0.003, 0)
		face.add_child(label)
		labels[color] = label

	var btn_mat := StandardMaterial3D.new()
	btn_mat.albedo_color = Color(0.55, 0.08, 0.06)
	btn_mat.roughness = 0.4
	var button := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.021
	cm.bottom_radius = 0.023
	cm.height = 0.014
	button.mesh = cm
	button.material_override = btn_mat
	button.position = Vector3(0, 0.044, 0.086)
	root.add_child(button)

	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.1, 0.25, 0.1)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.2, 1.0, 0.3)
	led_mat.emission_energy_multiplier = 0.0
	var led := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.005
	sm.height = 0.01
	led.mesh = sm
	led.material_override = led_mat
	led.position = Vector3(0.056, 0.043, 0.075)
	root.add_child(led)

	return {"root": root, "labels": labels, "plates": plates, "button": button,
		"led_mat": led_mat, "button_rest": button.position.y}


# --- Tic-tac -------------------------------------------------------------------------

func _build_tick() -> void:
	_tick_player = AudioStreamPlayer3D.new()
	_tick_player.name = "TicTac"
	_tick_player.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	_tick_player.unit_size = 4.0
	_tick_player.position = Vector3(0, 0.04, 0)
	add_child(_tick_player)
	var tick: AudioStream = load(TICK_PATH) if ResourceLoader.exists(TICK_PATH) else _synth_click(2600.0)
	var tock: AudioStream = load(TOCK_PATH) if ResourceLoader.exists(TOCK_PATH) else _synth_click(1700.0)
	_tick_streams = [tick, tock]


## Respaldo: un clic corto (ráfaga de seno con ruido y caída exponencial), mono 16 bits.
static func _synth_click(freq: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.035)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 140.0)
		var v := (sin(TAU * freq * t) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## Un tic o un toc por segundo entero que corre el reloj activo.
func _tick() -> void:
	if _tick_player == null:
		return
	_tick_toggle = not _tick_toggle
	var urgent: bool = _remaining[near_color] < URGENT_SECONDS
	_tick_player.stream = _tick_streams[1 if _tick_toggle else 0]
	_tick_player.volume_db = 5.0 if urgent else -3.0
	_tick_player.pitch_scale = 1.2 if urgent else 1.0
	_tick_player.play()


# --- Textos --------------------------------------------------------------------------

## Actualiza los textos (barato: solo cambia el texto si cambió la cadena).
func set_times(white_seconds: float, black_seconds: float) -> void:
	_remaining = [white_seconds, black_seconds]
	for color in 2:
		var sec := int(ceil(maxf(_remaining[color], 0.0)))
		# Tic-tac cuando el reloj que corre baja un segundo (el incremento no suena).
		if color == _running and _last_sec[color] >= 0 and sec < _last_sec[color]:
			_tick()
		_last_sec[color] = sec
		_set_time(color, _remaining[color])
	for c in 2:
		_refresh_color(c)


func _set_time(color: int, seconds: float) -> void:
	var text := format_time(seconds)
	if text != _last_text[color]:
		_last_text[color] = text
		for side in 2:
			_faces[side].labels[color].text = text


## Marca qué lado corre (-1 = ninguno).
func set_running(color: int) -> void:
	_running = color
	for c in 2:
		_refresh_color(c)


## Enciende o apaga la pantalla de `color` en ambas caras y el LED del dueño de cada cara.
func _refresh_color(color: int) -> void:
	var on := color == _running
	var low := _last_text[color].find(":") < 0  # menos de 10 s: se muestran décimas
	var lit := LIT_LOW if low else LIT
	for side in 2:
		var f: Dictionary = _faces[side]
		f.plates[color].emission_energy_multiplier = 0.55 if on else 0.0
		f.labels[color].modulate = lit if on else DIM
		if _owner_of(side) == color:
			f.led_mat.emission_energy_multiplier = 2.0 if on else 0.0


## Posición global de la cara superior del botón de `color`.
func button_top_world(color: int) -> Vector3:
	var b: MeshInstance3D = _faces[_side_of(color)].button
	return b.global_position + Vector3(0, 0.007, 0)


## El botón se hunde y vuelve (corrutina).
func press_button(color: int) -> void:
	var b: MeshInstance3D = _faces[_side_of(color)].button
	var rest: float = _faces[_side_of(color)].button_rest
	var tw := create_tween()
	tw.tween_property(b, "position:y", rest - BUTTON_TRAVEL, 0.06)
	tw.tween_property(b, "position:y", rest, 0.16)
	await tw.finished


static func format_time(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 10.0:
		return "%d.%d" % [int(s), int(fmod(s, 1.0) * 10.0)]
	var total := int(ceil(s))
	return "%d:%02d" % [total / 60, total % 60]
