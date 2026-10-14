class_name HandRig
extends Node3D
## Brazo procedural con IK. Un `Skeleton3D` armado en código (brazo → antebrazo
## → mano, en reposo a lo largo de +Y) y un `TwoBoneIK3D` que lleva la muñeca
## a un `Marker3D`. Un marcador de polo detrás y debajo del codo evita que el
## brazo se doble raro. Las cápsulas del brazo cuelgan de `BoneAttachment3D`.
##
## La mano (palma y dedos de cajas) cuelga del marcador objetivo, porque la
## muñeca coincide con él y así su orientación se controla directamente
## (palma hacia abajo, dedos inclinados hacia la pieza). La pieza que se lleva
## cuelga de un ancla que cuelga del `BoneAttachment3D` de la mano, pero se
## mantiene siempre derecha en el punto de pinza.
##
## Convención local del nodo: el hombro está en el origen y la mesa queda
## hacia -Z. `side` = +1 brazo derecho, -1 izquierdo.

const UPPER_LEN := 0.40
const FORE_LEN := 0.38
const REACH := (UPPER_LEN + FORE_LEN) * 0.995

const BONE_UPPER := "brazo"
const BONE_FORE := "antebrazo"
const BONE_HAND := "mano"

## Poses de dedos: curvaturas (base, punta) de índice, corazón, anular, meñique
## y destino de la punta del pulgar en el sistema local de la mano.
enum Pose { OPEN, PINCH, GRIP }

var side: float = 1.0
var skin_color := Color(0.78, 0.60, 0.48)
var sleeve_color := Color(0.15, 0.17, 0.30)
## Temblor en 0..1 (más estrés = más temblor).
var stress: float = 0.0
var carried: Node3D = null
var skeleton: Skeleton3D
var ik: TwoBoneIK3D
var target: Marker3D
var pole: Marker3D
var hand_root: Node3D
var hand_attachment: BoneAttachment3D
var carry_anchor: Node3D

var _grip: Vector3 = Vector3.ZERO
var _pitch: float = deg_to_rad(55.0)
var _roll: float = 0.0
var _phase := Vector3(1.3, 4.1, 2.7)
var _time: float = 0.0
var _fingers: Array[Array] = []  # [pivot_base, pivot_tip]
var _thumb: Node3D
var _thumb_mesh: MeshInstance3D
var _thumb_base := Vector3.ZERO
var _pose_curls: Array = []
var _pose_thumb: Vector3 = Vector3.ZERO
var _pose_tween: Tween
## Punto de pinza en el sistema local de la mano (entre pulgar e índice).
var pinch_local: Vector3 = Vector3.ZERO


func setup(p_side: float, p_sleeve: Color, p_skin: Color) -> void:
	side = p_side
	sleeve_color = p_sleeve
	skin_color = p_skin
	_build_skeleton()
	_build_arm_meshes()
	_build_hand()
	_set_pose_immediate(Pose.OPEN)
	_grip = to_global(Vector3(side * 0.05, -0.30, -0.45))
	_update_target()


func shoulder_position() -> Vector3:
	return global_position


## Punto de pinza deseado en el mundo; la mano se coloca para que lo alcance.
func set_grip(world_pos: Vector3, pitch_deg: float = 55.0, roll_deg: float = 0.0) -> void:
	_grip = world_pos
	_pitch = deg_to_rad(pitch_deg)
	_roll = deg_to_rad(roll_deg)


func get_grip() -> Vector3:
	return _grip


func _process(delta: float) -> void:
	_time += delta
	_update_target()


func _update_target() -> void:
	var to := _grip - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dir_h := (-global_basis.z) if flat.length() < 0.02 else flat.normalized()
	var fingers := dir_h * cos(_pitch) + Vector3.DOWN * sin(_pitch)
	var b := Basis.looking_at(fingers, Vector3.UP)
	b = b * Basis(Vector3(0, 0, 1), _roll)
	var wrist := _grip - b * pinch_local
	wrist += _tremor_offset()
	var from_shoulder := wrist - global_position
	if from_shoulder.length() > REACH:
		wrist = global_position + from_shoulder.normalized() * REACH
	target.global_transform = Transform3D(b, wrist)
	carry_anchor.global_transform = Transform3D(Basis.IDENTITY, target.to_global(pinch_local))


## Temblor de la mano: pequeño siempre, y crece con el estrés (poco tiempo en el reloj).
func _tremor_offset() -> Vector3:
	var amp := lerpf(0.0003, 0.006, pow(clampf(stress, 0.0, 1.0), 1.6)) * 0.5
	var t := _time
	return Vector3(
		sin(t * 47.0 + _phase.x) + 0.6 * sin(t * 71.0 + _phase.y),
		sin(t * 53.0 + _phase.y) + 0.5 * sin(t * 83.0 + _phase.z),
		sin(t * 43.0 + _phase.z) + 0.6 * sin(t * 67.0 + _phase.x)) * amp


# --- Pieza sujeta -----------------------------------------------------------------

## La pieza pasa a colgar del ancla de la mano, derecha, con la pinza a `grip_h` de su base.
func attach_piece(piece: Node3D, grip_h: float) -> void:
	var yaw := piece.global_rotation.y
	piece.reparent(carry_anchor, false)
	piece.position = Vector3(0.0, -grip_h, 0.0)
	piece.rotation = Vector3(0.0, yaw, 0.0)
	carried = piece


## Suelta la pieza (sigue siendo hija del ancla hasta que el tablero la reciba).
func release_piece() -> Node3D:
	var p := carried
	carried = null
	return p


# --- Poses de dedos -----------------------------------------------------------------

## Mezcla hacia una pose en `duration` segundos (corrutina: se puede esperar).
func set_pose(pose: Pose, duration: float = 0.2) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	if duration <= 0.0 or not is_inside_tree():
		_set_pose_immediate(pose)
		return
	var from_curls := _pose_curls.duplicate()
	var from_thumb := _pose_thumb
	var goal := _pose_data(pose)
	_pose_tween = create_tween()
	_pose_tween.tween_method(func(t: float) -> void:
		var curls: Array = []
		for i in from_curls.size():
			curls.append(lerpf(from_curls[i], goal.curls[i], t))
		_apply_pose(curls, from_thumb.lerp(goal.thumb, t)), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE)
	await _pose_tween.finished


func _set_pose_immediate(pose: Pose) -> void:
	var d := _pose_data(pose)
	_apply_pose(d.curls, d.thumb)


func _pose_data(pose: Pose) -> Dictionary:
	match pose:
		Pose.PINCH:
			return {
				"curls": [0.45, 0.7, 1.0, 1.1, 1.2, 1.2, 1.3, 1.2],
				"thumb": pinch_local + Vector3(-side * 0.006, 0.0, 0.0),
			}
		Pose.GRIP:
			return {
				"curls": [1.1, 1.0, 1.2, 1.0, 1.25, 1.0, 1.3, 1.0],
				"thumb": Vector3(-side * 0.02, -0.035, -0.075),
			}
	return {
		"curls": [0.1, 0.1, 0.12, 0.1, 0.15, 0.1, 0.2, 0.1],
		"thumb": Vector3(-side * 0.085, -0.012, -0.085),
	}


func _apply_pose(curls: Array, thumb_tip: Vector3) -> void:
	_pose_curls = curls
	_pose_thumb = thumb_tip
	for i in 4:
		_fingers[i][0].rotation.x = -float(curls[i * 2])
		_fingers[i][1].rotation.x = -float(curls[i * 2 + 1])
	# El pulgar es un palo entre su base y la punta objetivo.
	var v := thumb_tip - _thumb_base
	var l := maxf(v.length(), 0.01)
	_thumb.position = _thumb_base
	_thumb.basis = Basis.looking_at(v / l, Vector3.UP)
	_thumb_mesh.scale = Vector3(1, 1, l / 0.06)
	_thumb_mesh.position = Vector3(0, 0, -l * 0.5)


# --- Construcción -----------------------------------------------------------------

func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Esqueleto"
	add_child(skeleton)
	skeleton.add_bone(BONE_UPPER)
	skeleton.add_bone(BONE_FORE)
	skeleton.add_bone(BONE_HAND)
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, UPPER_LEN, 0)))
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0, FORE_LEN, 0)))
	skeleton.reset_bone_poses()

	target = Marker3D.new()
	target.name = "ObjetivoMano"
	target.top_level = true
	add_child(target)
	# Polo: detrás, debajo y hacia fuera del codo.
	pole = Marker3D.new()
	pole.name = "PoloCodo"
	pole.position = Vector3(side * 0.40, -0.55, 0.30)
	add_child(pole)

	ik = TwoBoneIK3D.new()
	ik.name = "IKBrazo"
	skeleton.add_child(ik)
	ik.set_setting_count(1)
	ik.set_root_bone_name(0, BONE_UPPER)
	ik.set_middle_bone_name(0, BONE_FORE)
	ik.set_end_bone_name(0, BONE_HAND)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))


func _build_arm_meshes() -> void:
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = sleeve_color
	sleeve.roughness = 0.9
	var skin := _skin_material()

	var up_att := BoneAttachment3D.new()
	up_att.name = "AdjuntoBrazo"
	up_att.bone_name = BONE_UPPER
	skeleton.add_child(up_att)
	up_att.add_child(_capsule(0.036, UPPER_LEN + 0.02, Vector3(0, UPPER_LEN * 0.5, 0), sleeve))
	var shoulder := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.042
	sph.height = 0.084
	shoulder.mesh = sph
	shoulder.material_override = sleeve
	up_att.add_child(shoulder)

	var fore_att := BoneAttachment3D.new()
	fore_att.name = "AdjuntoAntebrazo"
	fore_att.bone_name = BONE_FORE
	skeleton.add_child(fore_att)
	fore_att.add_child(_capsule(0.029, FORE_LEN + 0.02, Vector3(0, FORE_LEN * 0.5, 0), sleeve))

	hand_attachment = BoneAttachment3D.new()
	hand_attachment.name = "AdjuntoMano"
	hand_attachment.bone_name = BONE_HAND
	skeleton.add_child(hand_attachment)
	# Muñeca: un tramo de piel que asoma de la manga.
	hand_attachment.add_child(_capsule(0.026, 0.07, Vector3(0, 0.0, 0), skin))
	# Ancla de la pieza sujeta: cuelga de la mano pero se orienta derecha.
	carry_anchor = Node3D.new()
	carry_anchor.name = "AnclaPieza"
	carry_anchor.top_level = true
	hand_attachment.add_child(carry_anchor)


func _capsule(radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi


func _skin_material() -> StandardMaterial3D:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = skin_color
	skin.roughness = 0.7
	return skin


## Punta de un dedo de dos falanges con las curvaturas dadas (local de la mano).
static func finger_tip(base: Vector3, c1: float, c2: float) -> Vector3:
	var l1 := 0.035
	var l2 := 0.03
	var p := base
	p += Vector3(0, -sin(c1), -cos(c1)) * l1
	p += Vector3(0, -sin(c1 + c2), -cos(c1 + c2)) * l2
	return p


func _build_hand() -> void:
	var skin := _skin_material()
	hand_root = Node3D.new()
	hand_root.name = "Mano"
	target.add_child(hand_root)
	var palm := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.082, 0.02, 0.09)
	palm.mesh = pm
	palm.material_override = skin
	palm.position = Vector3(0, 0, -0.045)
	hand_root.add_child(palm)
	# Cuatro dedos de dos falanges; el índice queda del lado del pulgar (-side).
	for i in 4:
		var x := -side * (0.03 - i * 0.02)
		var base := Node3D.new()
		base.position = Vector3(x, 0, -0.09)
		hand_root.add_child(base)
		base.add_child(_phalanx(0.035, skin, 0.016))
		var tip := Node3D.new()
		tip.position = Vector3(0, 0, -0.035)
		base.add_child(tip)
		tip.add_child(_phalanx(0.03, skin, 0.014))
		_fingers.append([base, tip])
	var idx_base := Vector3(-side * 0.03, 0, -0.09)
	var idx_tip := finger_tip(idx_base, 0.45, 0.7)
	# Punto de pinza: entre la punta del índice y la del pulgar.
	pinch_local = idx_tip + Vector3(-side * 0.006, 0.0, 0.0)
	_thumb_base = Vector3(-side * 0.046, -0.002, -0.02)
	_thumb = Node3D.new()
	hand_root.add_child(_thumb)
	_thumb_mesh = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.017, 0.017, 0.06)
	_thumb_mesh.mesh = tm
	_thumb_mesh.material_override = skin
	_thumb.add_child(_thumb_mesh)


func _phalanx(length: float, mat: Material, thick: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, length)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(0, 0, -length * 0.5)
	return mi


func get_pitch_deg() -> float:
	return rad_to_deg(_pitch)
