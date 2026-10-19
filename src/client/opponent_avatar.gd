class_name OpponentAvatar
extends Node3D
## El rival: una `SeatedFigure` (modelo de Blender) sentada en su silla, mirando a +Z hacia el
## jugador. La cabeza sigue la mirada del bot (`BotController.looked`: la misma cámara virtual
## con la que el servidor decide si mira el tablero), que es lo que el jugador debe leer. En
## reposo alterna animaciones (`sit_idle`, `sit_think`, `sit_nervous`); los eventos (toser,
## tirar una pieza) se resuelven con el tronco y la cabeza. Es dueño de la mano (`HandRig`)
## del rival, que usa el brazo izquierdo: así queda del mismo lado que el reloj y que su pila
## de capturas.
##
## El nodo se coloca en el suelo bajo el asiento; la figura mira a +Z sin girar.

## Ojos de la figura sentada, en el espacio local del nodo (medido con `sit_idle`).
const EYE_LOCAL := Vector3(0.0, 1.146, 0.27)
## Animaciones de reposo y rango (s) entre cambios.
const IDLE_ANIMS: Array[StringName] = [&"sit_idle", &"sit_think", &"sit_nervous"]
const IDLE_CHANGE := Vector2(5.0, 12.0)
## Altura de los ojos de las siluetas de primitivas (`build_figure`).
const EYE_HEIGHT := 1.13

var figure: SeatedFigure
## Marcador pegado al hueso de la cabeza (posición de la cabeza para efectos y sonidos).
var head: Node3D
var hand_rig: HandRig
## Mano derecha (libre): descansa sobre la mesa.
var idle_rig: HandRig
var bot: BotController

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Sacudida de eventos (toser, tirar una pieza): cabeza (cabeceo, rad) y torso (inclinación, rad).
var _head_kick: float = 0.0
var _body_kick: float = 0.0
var _event_tween: Tween
var _idle_timer: float = 3.0
var _rng := RandomNumberGenerator.new()


## Posición global de los ojos (la usa el bot como cámara virtual). No sigue la animación:
## es siempre la de la figura sentada derecha, para que la mirada sea estable.
func eye_position() -> Vector3:
	return global_transform * EYE_LOCAL


## Crea la figura y el brazo. `look` es el aspecto (ver `CharacterFigure.random_look`).
## `arm_side`: `&"L"` = brazo izquierdo de la figura (el del lado del reloj).
func build(look: Dictionary, arm_side: StringName = &"L") -> void:
	name = "Rival"
	_rng.randomize()
	figure = SeatedFigure.new()
	figure.name = "Figura"
	add_child(figure)
	figure.setup(look)
	figure.play(&"sit_idle", 0.0)
	head = Marker3D.new()
	head.name = "Cabeza"
	figure.attach(head, &"Head")
	hand_rig = HandRig.new()
	hand_rig.name = "ManoRival"
	add_child(hand_rig)
	hand_rig.setup(figure, arm_side)
	idle_rig = HandRig.new()
	idle_rig.name = "ManoLibreRival"
	add_child(idle_rig)
	idle_rig.setup(figure, &"R" if arm_side == &"L" else &"L")
	idle_rig.rest_at(Vector3(-0.34, BoardView.TABLE_TOP + 0.03, -0.40))


func bind_bot(p_bot: BotController) -> void:
	bot = p_bot
	bot.looked.connect(_on_looked)
	_on_looked(bot.look_yaw, bot.look_pitch)


## El bot mira con la convención de la cámara (yaw 0 = hacia -Z del mundo); la figura mira a
## +Z y su yaw positivo es hacia su izquierda: hay medio giro de diferencia.
func _on_looked(yaw: float, pitch: float) -> void:
	_look_yaw = wrapf(yaw + PI - rotation.y, -PI, PI)
	_look_pitch = pitch
	_apply_head()


func _apply_head() -> void:
	figure.set_look(_look_yaw, _look_pitch + _head_kick)
	figure.set_lean_extra(_body_kick)


func _process(delta: float) -> void:
	# Mientras dura una sacudida se reaplica cada fotograma (el bot solo avisa al girar).
	if _event_tween != null and _event_tween.is_valid():
		_apply_head()
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = _rng.randf_range(IDLE_CHANGE.x, IDLE_CHANGE.y)
		_next_idle()


## Cambia de animación de reposo si la mano no está trabajando ni hay un evento en curso.
func _next_idle() -> void:
	if (_event_tween != null and _event_tween.is_valid()):
		return
	var options := IDLE_ANIMS.filter(func(a: StringName) -> bool: return a != figure.current())
	figure.play(options[_rng.randi() % options.size()], 0.6)


## Tos: dos espasmos, cabeza y torso se doblan hacia adelante.
func play_cough() -> void:
	_start_event_tween()
	_event_tween.tween_method(_cough_step, 0.0, 1.0, 0.9)
	_event_tween.tween_callback(_end_event)


func _cough_step(t: float) -> void:
	var spasm := maxf(sin(t * TAU * 2.0), 0.0) * (1.0 - t * 0.4)
	_head_kick = -spasm * 0.45
	_body_kick = spasm * 0.16


## Se le escapa una pieza: mira hacia abajo, hacia el suelo, un momento.
func play_drop_piece() -> void:
	_start_event_tween()
	_event_tween.tween_method(_dip_step, 0.0, 1.0, 0.25).set_ease(Tween.EASE_OUT)
	_event_tween.tween_interval(0.7)
	_event_tween.tween_method(_dip_step, 1.0, 0.0, 0.5)
	_event_tween.tween_callback(_end_event)


func _dip_step(k: float) -> void:
	_head_kick = -k * 0.8
	_body_kick = k * 0.22


func _start_event_tween() -> void:
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()


func _end_event() -> void:
	_head_kick = 0.0
	_body_kick = 0.0
	_apply_head()


## Figura sentada reutilizable (también para las mesas decorativas).
## Mira hacia -Z local. Devuelve {root, head}.
static func build_figure(skin: Color, cloth: Color, detailed: bool, static_arms: bool = false) -> Dictionary:
	var root := Node3D.new()
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = cloth
	cloth_mat.roughness = 0.9
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = skin
	skin_mat.roughness = 0.7

	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.19
	tm.height = 0.74
	tm.radial_segments = 14
	tm.rings = 4
	torso.mesh = tm
	torso.material_override = cloth_mat
	torso.position = Vector3(0.0, 0.70, 0.13)
	root.add_child(torso)

	# Muslos hacia adelante (casi ocultos bajo la mesa).
	for s in [-1.0, 1.0]:
		var thigh := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.08
		cm.height = 0.5
		thigh.mesh = cm
		thigh.material_override = cloth_mat
		thigh.rotation.x = deg_to_rad(90.0)
		thigh.position = Vector3(s * 0.11, 0.50, -0.12)
		root.add_child(thigh)

	var head := Node3D.new()
	head.name = "Cabeza"
	head.position = Vector3(0.0, EYE_HEIGHT - 0.01, -0.03)
	root.add_child(head)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.105
	sm.height = 0.23
	sm.radial_segments = 20
	sm.rings = 10
	skull.mesh = sm
	skull.material_override = skin_mat
	head.add_child(skull)

	if detailed:
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.92, 0.92, 0.88)
		white.roughness = 0.4
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.02, 0.02, 0.02)
		var hair := StandardMaterial3D.new()
		hair.albedo_color = Color(0.05, 0.035, 0.03)
		hair.roughness = 0.9
		for s in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.019
			em.height = 0.038
			eye.mesh = em
			eye.material_override = white
			eye.position = Vector3(s * 0.043, 0.022, -0.087)
			head.add_child(eye)
			var pupil := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.0095
			pm.height = 0.019
			pupil.mesh = pm
			pupil.material_override = black
			pupil.position = Vector3(s * 0.043, 0.022, -0.104)
			head.add_child(pupil)
			var brow := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.008, 0.01)
			brow.mesh = bm
			brow.material_override = hair
			brow.position = Vector3(s * 0.043, 0.052, -0.093)
			brow.rotation.z = s * deg_to_rad(8.0)
			head.add_child(brow)
		var nose := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.0
		nm.bottom_radius = 0.02
		nm.height = 0.055
		nose.mesh = nm
		nose.material_override = skin_mat
		nose.rotation.x = deg_to_rad(-90.0)
		nose.position = Vector3(0.0, -0.008, -0.118)
		head.add_child(nose)
		var cap := MeshInstance3D.new()
		var cpm := SphereMesh.new()
		cpm.radius = 0.108
		cpm.height = 0.216
		cap.mesh = cpm
		cap.material_override = hair
		cap.scale = Vector3(1.0, 0.7, 1.0)
		cap.position = Vector3(0.0, 0.035, 0.018)
		head.add_child(cap)
	else:
		# Silueta: solo una nariz mínima para intuir hacia dónde mira.
		var nose2 := MeshInstance3D.new()
		var nm2 := SphereMesh.new()
		nm2.radius = 0.016
		nm2.height = 0.032
		nose2.mesh = nm2
		nose2.material_override = skin_mat
		nose2.position = Vector3(0.0, -0.01, -0.105)
		head.add_child(nose2)

	if static_arms:
		for s in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var am := CapsuleMesh.new()
			am.radius = 0.04
			am.height = 0.55
			arm.mesh = am
			arm.material_override = cloth_mat
			arm.rotation.x = deg_to_rad(75.0)
			arm.position = Vector3(s * 0.22, 0.86, -0.12)
			root.add_child(arm)
	return {"root": root, "head": head}
