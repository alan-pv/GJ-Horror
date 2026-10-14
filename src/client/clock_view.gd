class_name ClockView
extends Node3D
## Reloj de ajedrez 3D al costado de la mesa, con dos pantallas (`Label3D`) y
## dos botones que se hunden al pulsarlos. El lado que corre se ve encendido.
##
## Cada jugador tiene su pantalla inclinada hacia él y su botón en su extremo.
## El lado cercano (humano) está en +Z; el lejano, en -Z.

const POSITION := Vector3(0.42, BoardView.TABLE_TOP, 0.0)
const BUTTON_TRAVEL := 0.008
const DISPLAY_TILT_DEG := 38.0

var near_color: int = ChessPiece.WHITE
var _faces: Array[Dictionary] = [{}, {}]  # por lado: 0 = cercano, 1 = lejano
var _running: int = -1
var _last_text: Array[String] = ["", ""]
var _case_mat: StandardMaterial3D


func setup(p_near_color: int) -> void:
	near_color = p_near_color
	position = POSITION
	name = "Reloj"
	_case_mat = StandardMaterial3D.new()
	_case_mat.albedo_color = Color(0.09, 0.09, 0.10)
	_case_mat.roughness = 0.55
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.105, 0.04, 0.23)
	body.mesh = bm
	body.material_override = _case_mat
	body.position = Vector3(0, 0.02, 0)
	add_child(body)
	for side in 2:
		_faces[side] = _build_side(side)
	set_running(-1)


func _side_of(color: int) -> int:
	return 0 if color == near_color else 1


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

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.05, 0.07, 0.05)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(1.0, 0.65, 0.2)
	plate_mat.emission_energy_multiplier = 0.0
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.088, 0.003, 0.05)
	plate.mesh = pm
	plate.material_override = plate_mat
	face.add_child(plate)

	var label := Label3D.new()
	label.text = "3:00"
	label.font_size = 64
	label.pixel_size = 0.00055
	label.shaded = false
	label.double_sided = false
	label.modulate = Color(0.4, 0.3, 0.15)
	label.outline_size = 0
	label.rotation.x = deg_to_rad(-90.0)
	label.position = Vector3(0, 0.003, 0)
	face.add_child(label)

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
	led.position = Vector3(0.036, 0.043, 0.075)
	root.add_child(led)

	return {"root": root, "label": label, "plate_mat": plate_mat, "button": button,
		"led_mat": led_mat, "button_rest": button.position.y}


## Actualiza los textos (barato: solo cambia el texto si cambió la cadena).
func set_times(white_seconds: float, black_seconds: float) -> void:
	_set_time(ChessPiece.WHITE, white_seconds)
	_set_time(ChessPiece.BLACK, black_seconds)


func _set_time(color: int, seconds: float) -> void:
	var side := _side_of(color)
	var text := format_time(seconds)
	if text != _last_text[side]:
		_last_text[side] = text
		_faces[side].label.text = text
	_refresh_side(color)


## Marca qué lado corre (-1 = ninguno).
func set_running(color: int) -> void:
	_running = color
	for c in 2:
		_refresh_side(c)


func _refresh_side(color: int) -> void:
	var side := _side_of(color)
	var f: Dictionary = _faces[side]
	var on := color == _running
	var low := _last_text[side].find(":") < 0  # menos de 10 s: se muestran décimas
	f.plate_mat.emission_energy_multiplier = 0.55 if on else 0.0
	f.led_mat.emission_energy_multiplier = 2.0 if on else 0.0
	var lit := Color(1.0, 0.35, 0.2) if low else Color(1.0, 0.8, 0.35)
	f.label.modulate = lit if on else Color(0.45, 0.38, 0.2)


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
