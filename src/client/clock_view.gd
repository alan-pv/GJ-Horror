class_name ClockView
extends Node3D
## Reloj de ajedrez digital de torneo (`chess_clock.glb`) al costado de la mesa, con el frente
## (LCD) mirando al centro del tablero. Los dos tiempos son dígitos de 7 segmentos hechos con
## mallas planas pegadas al LCD (sombreadas por la luz de la escena, sin brillo propio): el
## campo derecho (visto de frente, lado +Z) es del jugador cercano y el izquierdo, del lejano.
## En el centro hay dos flechas de turno (▶ ◀) y los dos puntos del que corre parpadean.
## Arriba, un balancín (`Rocker`) reemplaza a los botones: el jugador pulsa su mitad, que baja,
## y la contraria sube. Hace tic-tac (`AudioStreamPlayer3D`, bus SFX) cada segundo que corre
## un reloj.

const POSITION := Vector3(0.42, BoardView.TABLE_TOP, 0.0)
const MODEL_PATH := "res://assets/models/props/chess_clock.glb"
## Escala del modelo (mayor que el real para que los tiempos se lean desde el asiento).
const MODEL_SCALE := 1.3
## Inclinación del balancín (rad) y rebote extra al pulsar.
const ROCKER_TILT := deg_to_rad(6.0)
const ROCKER_BOUNCE := deg_to_rad(2.5)
const TICK_PATH := "res://assets/audio/sfx/clock_tick.wav"
const TOCK_PATH := "res://assets/audio/sfx/clock_tock.wav"
## Por debajo de esto (del jugador) el tic-tac se vuelve más intenso.
const URGENT_SECONDS := 20.0

# Geometría del LCD (coordenadas locales de LCD_Anchor: x derecha, y arriba, en metros).
const DIGIT_W := 0.0115
const DIGIT_H := 0.030
const SEG_T := 0.0026
const DIGIT_GAP := 0.0022
const COLON_W := 0.0038
const FIELD_CENTER := 0.0425  ## |x| del centro de cada campo de tiempo
const SKEW := 0.12  ## inclinación de los dígitos (como en un LCD real)
const INK := Color(0.06, 0.07, 0.06)
const GHOST := Color(0.625, 0.68, 0.605)  # ~93 % del LCD (sRGB)
## Segmentos por dígito: a b c d e f g (bits).
const SEG_MASK := {
	"0": 0b0111111, "1": 0b0000110, "2": 0b1011011, "3": 0b1001111, "4": 0b1100110,
	"5": 0b1101101, "6": 0b1111101, "7": 0b0000111, "8": 0b1111111, "9": 0b1101111, " ": 0,
}

var near_color: int = ChessPiece.WHITE
var _running: int = -1
var _last_sec: Array[int] = [-1, -1]  # por color: segundo entero mostrado
var _remaining: Array[float] = [180.0, 180.0]
var _shown: Array[String] = ["", ""]  # por color: cadena dibujada en el campo
var _applied: Array[String] = ["", ""]  # por color: cadena + estado de los dos puntos en la malla
var _model: Node3D
var _anchor: Node3D
var _fields: Array[MeshInstance3D] = [null, null]  # por color
var _colon_dots: Array[MeshInstance3D] = [null, null]  # por color
var _arrows: Array[MeshInstance3D] = [null, null]  # por color (apunta al campo de ese color)
var _ink_mat: StandardMaterial3D
var _rocker: Node3D
var _contacts: Array[Node3D] = [null, null]  # por lado: 0 = cercano, 1 = lejano
var _rocker_down: int = -1  # lado hundido (-1 = ninguno)
var _rocker_tw: Tween
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
	# LCD_Anchor viene del eje convertido de Blender (Y = normal, -Z = arriba): se cuelga un
	# nodo con ejes propios (x derecha, y arriba, z normal saliente) para dibujar el LCD.
	var lcd_anchor := _model.find_child("LCD_Anchor", true, false) as Node3D
	_anchor = Node3D.new()
	_anchor.name = "LCDPlane"
	_anchor.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	lcd_anchor.add_child(_anchor)
	_rocker = _model.find_child("Rocker", true, false) as Node3D
	# Lado cercano (+Z de Godot) = derecha vista de frente.
	_contacts[0] = _model.find_child("Contact_Right", true, false) as Node3D
	_contacts[1] = _model.find_child("Contact_Left", true, false) as Node3D
	_build_lcd()
	_build_tick()
	set_running(-1)
	set_times(180.0, 180.0)


func _side_of(color: int) -> int:
	return 0 if color == near_color else 1


## Centro (x) del campo de `color` en el LCD: el cercano a la derecha.
func _field_x(color: int) -> float:
	return FIELD_CENTER if color == near_color else -FIELD_CENTER


# --- LCD de 7 segmentos --------------------------------------------------------------

func _lcd_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_lcd() -> void:
	_ink_mat = _lcd_material(INK)
	var ghost_mat := _lcd_material(GHOST)
	for color in 2:
		var cx := _field_x(color)
		# Fantasma de segmentos apagados (muy tenue), 0.5 mm sobre el LCD.
		var ghost := MeshInstance3D.new()
		ghost.name = "Ghost%d" % color
		ghost.mesh = _field_mesh("88:88", true)
		ghost.material_override = ghost_mat
		ghost.position = Vector3(cx, 0.0, 0.0005)
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_anchor.add_child(ghost)
		var f := MeshInstance3D.new()
		f.name = "Time%d" % color
		f.material_override = _ink_mat
		f.position = Vector3(cx, 0.0, 0.001)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_anchor.add_child(f)
		_fields[color] = f
	# Flechas de turno en el separador central: la del lado `color` apunta a su campo.
	var arrow_ghost := MeshInstance3D.new()
	arrow_ghost.mesh = _arrow_mesh(1.0, true)
	arrow_ghost.material_override = ghost_mat
	arrow_ghost.position = Vector3(0, 0, 0.0005)
	arrow_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anchor.add_child(arrow_ghost)
	for color in 2:
		var a := MeshInstance3D.new()
		a.name = "Arrow%d" % color
		# La flecha del campo derecho (cercano) apunta a +x.
		a.mesh = _arrow_mesh(1.0 if _field_x(color) > 0.0 else -1.0, false)
		a.material_override = _ink_mat
		a.position = Vector3(0, 0, 0.001)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_anchor.add_child(a)
		_arrows[color] = a


## Segmento horizontal (hexágono alargado) centrado en (cx, cy).
static func _hseg(cx: float, cy: float, w: float, t: float) -> Array:
	var h := t * 0.5
	var l := w * 0.5
	return [Vector2(cx - l, cy), Vector2(cx - l + h, cy + h), Vector2(cx + l - h, cy + h),
		Vector2(cx + l, cy), Vector2(cx + l - h, cy - h), Vector2(cx - l + h, cy - h)]


static func _vseg(cx: float, cy: float, hgt: float, t: float) -> Array:
	var h := t * 0.5
	var l := hgt * 0.5
	return [Vector2(cx, cy + l), Vector2(cx + h, cy + l - h), Vector2(cx + h, cy - l + h),
		Vector2(cx, cy - l), Vector2(cx - h, cy - l + h), Vector2(cx - h, cy + l - h)]


## Polígonos (hexágonos) de los 7 segmentos de un dígito con esquina inferior izquierda (ox, 0).
static func _digit_polys(mask: int, ox: float) -> Array:
	var w := DIGIT_W
	var hh := DIGIT_H
	var t := SEG_T
	var g := t * 0.12
	var cx := ox + w * 0.5
	var yb := -hh * 0.5
	var ym := 0.0
	var yt := hh * 0.5
	var vl := hh * 0.5 - t * 0.5 - g * 2.0
	var hw := w - t - g * 2.0
	var all := [
		_hseg(cx, yt - t * 0.5, hw, t),                       # a
		_vseg(ox + w - t * 0.5, (yt + ym) * 0.5, vl, t),      # b
		_vseg(ox + w - t * 0.5, (yb + ym) * 0.5, vl, t),      # c
		_hseg(cx, yb + t * 0.5, hw, t),                       # d
		_vseg(ox + t * 0.5, (yb + ym) * 0.5, vl, t),          # e
		_vseg(ox + t * 0.5, (yt + ym) * 0.5, vl, t),          # f
		_hseg(cx, ym, hw, t),                                 # g
	]
	var out := []
	for i in 7:
		if mask & (1 << i) != 0:
			out.append(all[i])
	return out


## Convierte polígonos convexos en una malla plana (cara hacia +Z) con la inclinación del LCD.
static func _polys_to_mesh(polys: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for poly_in in polys:
		var poly: Array = poly_in
		# Orientación horaria (cara frontal en Godot, hacia +Z) para que la luz use la normal correcta.
		var area := 0.0
		for i in poly.size():
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % poly.size()]
			area += a.x * b.y - b.x * a.y
		if area > 0.0:
			poly = poly.duplicate()
			poly.reverse()
		var base := verts.size()
		for p: Vector2 in poly:
			verts.append(Vector3(p.x + p.y * SKEW, p.y, 0.0))
			norms.append(Vector3(0, 0, 1))
		for i in range(1, poly.size() - 1):
			idx.append_array([base, base + i, base + i + 1])
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Malla de un campo de 5 posiciones "dd:dd" (el separador puede ser ":" o "."). `ghost` dibuja
## todo apagado-visible (todos los segmentos y los dos puntos).
static func _field_mesh(text: String, ghost: bool, colon_on: bool = true) -> ArrayMesh:
	var total := 4.0 * DIGIT_W + 4.0 * DIGIT_GAP + COLON_W
	var x := -total * 0.5
	var polys := []
	var dot := SEG_T * 1.1
	for i in text.length():
		var ch := text[i]
		if i == 2:
			if ch == ":" and (colon_on or ghost):
				for yy in [DIGIT_H * 0.2, -DIGIT_H * 0.2]:
					polys.append(_quad_poly(x + COLON_W * 0.5, yy, dot))
			elif ch == ".":
				polys.append(_quad_poly(x + COLON_W * 0.5, -DIGIT_H * 0.5 + dot * 0.5, dot))
			x += COLON_W + DIGIT_GAP
			continue
		polys.append_array(_digit_polys(0b1111111 if ghost else int(SEG_MASK.get(ch, 0)), x))
		x += DIGIT_W + DIGIT_GAP
	return _polys_to_mesh(polys)


static func _quad_poly(cx: float, cy: float, s: float) -> Array:
	var h := s * 0.5
	return [Vector2(cx - h, cy - h), Vector2(cx + h, cy - h), Vector2(cx + h, cy + h), Vector2(cx - h, cy + h)]


## Triángulos de turno en el separador central: `ghost` dibuja los dos; si no, solo el que
## apunta hacia `dir` (+1 derecha, -1 izquierda).
static func _arrow_mesh(dir: float, ghost: bool) -> ArrayMesh:
	var polys := []
	var s := 0.0045
	for d in [-1.0, 1.0]:
		if ghost or d == dir:
			var cx: float = 0.0052 * d
			polys.append([Vector2(cx - s * d, -s), Vector2(cx + s * d, 0.0), Vector2(cx - s * d, s)])
	return _polys_to_mesh(polys)


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

func _process(_dt: float) -> void:
	# Los dos puntos del reloj que corre parpadean (medio segundo); el resto, fijos.
	if _anchor == null:
		return
	var blink_on := int(Time.get_ticks_msec() / 500) % 2 == 0
	for color in 2:
		var txt: String = _shown[color]
		if txt.length() == 5 and txt[2] == ":" and color == _running:
			_apply_field(color, txt, blink_on)
		elif txt.length() == 5 and txt[2] == ":":
			_apply_field(color, txt, true)


## Actualiza los tiempos (barato: solo reconstruye el campo si cambió la cadena).
func set_times(white_seconds: float, black_seconds: float) -> void:
	_remaining = [white_seconds, black_seconds]
	for color in 2:
		var sec := int(ceil(maxf(_remaining[color], 0.0)))
		# Tic-tac cuando el reloj que corre baja un segundo (el incremento no suena).
		if color == _running and _last_sec[color] >= 0 and sec < _last_sec[color]:
			_tick()
		_last_sec[color] = sec
		var text := lcd_text(_remaining[color])
		if text != _shown[color]:
			_shown[color] = text
			_apply_field(color, text, true)


## Dibuja `text` ("MM:SS" con ceros iniciales en blanco, o " S.d ") en el campo de `color`.
func _apply_field(color: int, text: String, colon_on: bool) -> void:
	var key := text + ("1" if colon_on else "0")
	var f := _fields[color]
	if f != null and key != _applied[color]:
		_applied[color] = key
		f.mesh = _field_mesh(text, false, colon_on)


## Marca qué lado corre (-1 = ninguno): flecha de turno y balancín.
func set_running(color: int) -> void:
	_running = color
	for c in 2:
		if _arrows[c] != null:
			_arrows[c].visible = c == color
	# El que corre tiene su lado del balancín arriba (el rival acaba de hundir el suyo).
	if color == -1:
		_tilt_rocker(-1, false)
	else:
		_tilt_rocker(_side_of(ChessPiece.opposite(color)), false)


# --- Balancín ------------------------------------------------------------------------

func _tilt_angle(down_side: int) -> float:
	# Lado cercano (+Z) hundido = rotación +X; lejano, -X.
	return 0.0 if down_side < 0 else (ROCKER_TILT if down_side == 0 else -ROCKER_TILT)


func _tilt_rocker(down_side: int, bounce: bool) -> void:
	if _rocker == null or (not bounce and down_side == _rocker_down):
		return
	_rocker_down = down_side
	if _rocker_tw != null and _rocker_tw.is_valid():
		_rocker_tw.kill()
	var target := _tilt_angle(down_side)
	_rocker_tw = create_tween()
	if bounce and down_side >= 0:
		var over := target + signf(target) * ROCKER_BOUNCE
		_rocker_tw.tween_property(_rocker, "rotation:x", over, 0.06)
		_rocker_tw.tween_property(_rocker, "rotation:x", target, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_rocker_tw.tween_property(_rocker, "rotation:x", target, 0.12)


## Posición global del punto de contacto de la mitad del balancín de `color` (en su pose actual).
func button_top_world(color: int) -> Vector3:
	return _contacts[_side_of(color)].global_position


## El jugador pulsa su mitad: baja (con rebote) y la contraria sube (corrutina).
func press_button(color: int) -> void:
	_tilt_rocker(_side_of(color), true)
	await get_tree().create_timer(0.2).timeout


## Cadena para el LCD: "M:SS" (5 posiciones, con el dígito de decenas de minuto en blanco)
## o, bajo 10 s, " S.d " con décimas.
static func lcd_text(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 10.0:
		return " %d.%d " % [int(s), int(fmod(s, 1.0) * 10.0)]
	var total := int(ceil(s))
	var mm := total / 60
	return "%s%d:%02d" % [" " if mm < 10 else str(mm / 10), mm % 10, total % 60]


static func format_time(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 10.0:
		return "%d.%d" % [int(s), int(fmod(s, 1.0) * 10.0)]
	var total := int(ceil(s))
	return "%d:%02d" % [total / 60, total % 60]
