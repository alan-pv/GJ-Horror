class_name ClockView
extends Node3D
## Reloj de ajedrez 3D al costado de la mesa (`chess_clock.glb`): cada cara tiene DOS
## pantallas (`Label3D` sobre las esferas del modelo), una por jugador, y un botón
## (`Button_A`/`Button_B`) que se hunde al pulsarlo. En cada cara el tiempo de su dueño va
## a la izquierda (visto desde su asiento) y el del rival a la derecha; la pantalla del que
## corre se ve encendida. Hace tic-tac (`AudioStreamPlayer3D`, bus SFX) cada segundo que corre
## un reloj.
##
## El lado cercano (humano) es la cara A (+Z); el lejano, la B (-Z).

const POSITION := Vector3(0.42, BoardView.TABLE_TOP, 0.0)
const MODEL_PATH := "res://assets/models/props/chess_clock.glb"
## Escala del modelo (un poco mayor que el real para que los tiempos se lean desde el asiento).
const MODEL_SCALE := 1.15
const BUTTON_TRAVEL := 0.008
## Altura del botón sobre su base (modelo) y desplazamiento de las esferas respecto al centro.
const BUTTON_HEIGHT := 0.014
const DIAL_X := 0.034
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
var _model: Node3D
var _tick_player: AudioStreamPlayer3D
var _tick_streams: Array[AudioStream] = []
var _tick_toggle: bool = false


func setup(p_near_color: int) -> void:
	near_color = p_near_color
	position = POSITION
	name = "Reloj"
	_model = (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	# Las agujas analógicas sobran: los tiempos son digitales.
	for n in ["Hand_A_Left", "Hand_A_Right", "Hand_B_Left", "Hand_B_Right"]:
		var h := _model.find_child(n, true, false)
		if h != null:
			(h as Node3D).visible = false
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
	var face := _model.find_child("Face_A" if side == 0 else "Face_B", true, false) as Node3D
	var owner_color := _owner_of(side)
	var labels := {}
	var plates := {}
	# Visto desde el asiento de la cara, +X local queda a la derecha en ambas.
	for col in 2:
		var color := owner_color if col == 0 else ChessPiece.opposite(owner_color)
		var cx := -DIAL_X if col == 0 else DIAL_X
		var plate_mat := StandardMaterial3D.new()
		plate_mat.albedo_color = Color(0.05, 0.07, 0.05)
		plate_mat.emission_enabled = true
		plate_mat.emission = Color(1.0, 0.65, 0.2)
		plate_mat.emission_energy_multiplier = 0.0
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.048, 0.03, 0.002)
		plate.mesh = pm
		plate.material_override = plate_mat
		plate.position = Vector3(cx, 0.0, 0.0072)
		face.add_child(plate)
		plates[color] = plate_mat

		var label := Label3D.new()
		label.text = "3:00"
		label.font_size = 48
		label.pixel_size = 0.00042
		label.shaded = false
		label.double_sided = false
		label.modulate = DIM
		label.outline_size = 0
		label.position = Vector3(cx, 0.0, 0.0085)
		face.add_child(label)
		labels[color] = label

	var button := _model.find_child("Button_A" if side == 0 else "Button_B", true, false) as MeshInstance3D
	return {"root": face, "labels": labels, "plates": plates, "button": button,
		"button_rest": button.position.y}


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


## Posición global de la cara superior del botón de `color`.
func button_top_world(color: int) -> Vector3:
	var b: MeshInstance3D = _faces[_side_of(color)].button
	return b.global_position + Vector3(0, BUTTON_HEIGHT * MODEL_SCALE, 0)


## El botón se hunde y vuelve (corrutina).
func press_button(color: int) -> void:
	var b: MeshInstance3D = _faces[_side_of(color)].button
	var rest: float = _faces[_side_of(color)].button_rest
	var tw := create_tween()
	tw.tween_property(b, "position:y", rest - BUTTON_TRAVEL / MODEL_SCALE, 0.06)
	tw.tween_property(b, "position:y", rest, 0.16)
	await tw.finished


static func format_time(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 10.0:
		return "%d.%d" % [int(s), int(fmod(s, 1.0) * 10.0)]
	var total := int(ceil(s))
	return "%d:%02d" % [total / 60, total % 60]
