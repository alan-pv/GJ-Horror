class_name OpponentAvatar
extends Node3D
## Figura sentada del rival: torso de cápsula y cabeza esférica con ojos y
## nariz bien visibles, para que el jugador lea hacia dónde mira. La cabeza
## gira según `look_yaw`/`look_pitch` del `BotController` (la misma cámara
## virtual con la que el servidor decide si mira el tablero). Es dueña de la
## mano (`HandRig`) del rival, que usa el brazo izquierdo: así queda del mismo
## lado que el reloj y que su pila de capturas.
##
## El nodo se coloca en el suelo bajo el asiento y se gira para mirar a +Z.

const SEAT_HEIGHT := 0.45
const EYE_HEIGHT := 1.13
const SHOULDER_HEIGHT := 1.0

var head: Node3D
var hand_rig: HandRig
var bot: BotController


## Posición global de los ojos (la usa el bot como cámara virtual).
func eye_position() -> Vector3:
	return head.global_position


## Crea el cuerpo y el brazo. `arm_side`: -1 = brazo izquierdo (local), +1 = derecho.
func build(sleeve: Color, skin: Color, arm_side: float = -1.0) -> void:
	name = "Rival"
	var parts := build_figure(skin, sleeve, true)
	add_child(parts.root)
	head = parts.head
	hand_rig = HandRig.new()
	hand_rig.name = "ManoRival"
	hand_rig.position = Vector3(arm_side * 0.24, SHOULDER_HEIGHT - 0.04, -0.05)
	add_child(hand_rig)
	hand_rig.setup(arm_side, sleeve, skin)


func bind_bot(p_bot: BotController) -> void:
	bot = p_bot
	bot.looked.connect(_on_looked)
	_on_looked(bot.look_yaw, bot.look_pitch)


func _on_looked(yaw: float, pitch: float) -> void:
	# Misma convención que la cámara: sin girar mira hacia -Z.
	head.global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))


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
