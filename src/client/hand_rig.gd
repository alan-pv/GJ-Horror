class_name HandRig
extends Node3D
## Mano y brazo de un personaje (`SeatedFigure`) movidos por IK. Recibe el PUNTO DE PINZA
## deseado en el mundo (`set_grip`) y, cada fotograma:
##  - coloca la mano: orientación (dedos hacia la pieza, palma abajo) y muñeca (= pinza menos el
##    desplazamiento de la mano), con un temblor que crece con el estrés;
##  - inclina el torso hacia adelante lo justo para que la muñeca quede al alcance del brazo
##    (el IK llega a ~0,55 m del hombro);
##  - lleva el codo por FUERA y algo por DETRÁS de la mano, lo más bajo que permite la mesa (el
##    polo se recalcula cada fotograma, ver `_update_pole`), para que NUNCA la atraviese;
##  - cierra los dedos y el pulgar según la pose (abierta, pinza, puño).
## La pieza que se lleva cuelga de un ancla que sigue el punto de pinza de la mano real.
##
## Cuando no hay trabajo (`set_active(false)`) el IK se desvanece y el brazo vuelve a la
## animación del personaje (reposo, pensar, etc.).

enum Pose { OPEN, PINCH, GRIP }

## Alcance cómodo de la muñeca desde el hombro (el brazo mide ~0,59 m).
const REACH_COMFORT := 0.55
const LEAN_MAX := 0.95
## Cuánto puede adelantarse el cuerpo entero cuando la inclinación no basta.
const SHIFT_MAX := 0.08
const TWIST_MAX := 0.55
## Mesa (superficie) y margen mínimo del codo sobre ella cuando está sobre la mesa.
const TABLE_TOP := 0.72
const TABLE_HALF := Vector2(0.65, 0.45)
const ELBOW_MARGIN := 0.05
## Dirección del codo en el plano perpendicular al brazo: ángulo preferido (0 = hacia fuera,
## negativo = hacia abajo) y máximo; cuánto se desvía hacia atrás.
const ELBOW_PREF := deg_to_rad(-50.0)
const ELBOW_MAX := deg_to_rad(70.0)
const ELBOW_BACK := 0.35
## Punto de pinza en el sistema local de la mano (Y = hacia los dedos): cerca de la yema.
const PINCH_Y := 0.165
const PINCH_PALM := 0.012
## Geometría de la figura sentada (espacio local de la figura), medida con `sit_idle`.
const PIVOT := Vector3(0.0, 0.61, 0.03)
const CHEST := Vector3(0.0, 0.7387, 0.0481)
const UPPER_R := Vector3(-0.18, 0.8919, 0.0907)
## Cierre (dedos, pulgar) en radianes de cada pose.
const POSE_CURLS := {
	Pose.OPEN: Vector2(0.15, 0.0),
	Pose.PINCH: Vector2(0.75, 0.55),
	Pose.GRIP: Vector2(1.35, 0.9),
}

var figure: SeatedFigure
var side: StringName = &"R"
## Temblor en 0..1 (más estrés = más temblor).
var stress: float = 0.0
var carried: Node3D = null
var target: Marker3D
var pole: Marker3D
var carry_anchor: Node3D
## Posición de la mano (nodo) para efectos: igual que el ancla.
var hand_modifier: ArmPoseModifier

## false en la mano que solo descansa: no inclina ni gira el tronco (lo hace la mano que trabaja).
var drives_posture: bool = true

var _grip: Vector3 = Vector3.ZERO
var _pitch: float = deg_to_rad(55.0)
var _roll: float = 0.0
var _phase := Vector3(1.3, 4.1, 2.7)
var _time: float = 0.0
var _active: bool = false
var _influence: float = 0.0
var _curl := Vector2(0.15, 0.0)
var _pose_tween: Tween
var _influence_tween: Tween
var _hand_basis := Basis.IDENTITY
var _lean_want: float = 0.0
var _owns_posture: bool = false
var _pal: float = 1.0
var _len_upper: float = 0.30
var _len_fore: float = 0.29
var _elbow_angle: float = ELBOW_PREF


func setup(p_figure: SeatedFigure, p_side: StringName) -> void:
	figure = p_figure
	side = p_side
	_pal = 1.0 if side == &"R" else -1.0
	process_priority = -5
	target = figure.enable_arm_ik(side, true)
	pole = figure.arm_pole(side)
	hand_modifier = figure.arm_pose_modifier(side)
	_len_upper = figure.bone_global(StringName("UpperArm." + side)).origin.distance_to(figure.bone_global(StringName("Forearm." + side)).origin)
	_len_fore = figure.bone_global(StringName("Forearm." + side)).origin.distance_to(figure.bone_global(StringName("Hand." + side)).origin)
	set_active(false, 0.0)
	carry_anchor = Node3D.new()
	carry_anchor.name = "AnclaPieza"
	carry_anchor.top_level = true
	add_child(carry_anchor)
	figure.skeleton().skeleton_updated.connect(_update_anchor)
	_grip = shoulder_position() + figure.global_basis * Vector3(0.0, -0.3, 0.45)
	_set_curl(_curl)


func shoulder_position() -> Vector3:
	return figure.bone_global(StringName("UpperArm." + side)).origin


## Punto de pinza deseado en el mundo; la mano se coloca para que lo alcance.
func set_grip(world_pos: Vector3, pitch_deg: float = 55.0, roll_deg: float = 0.0) -> void:
	_grip = world_pos
	_pitch = deg_to_rad(pitch_deg)
	_roll = deg_to_rad(roll_deg)


func get_grip() -> Vector3:
	return _grip


func get_pitch_deg() -> float:
	return rad_to_deg(_pitch)


## Activa el IK (con un fundido de `fade` s) o devuelve el brazo a la animación del personaje.
func set_active(on: bool, fade: float = 0.3) -> void:
	_active = on
	if _influence_tween != null and _influence_tween.is_valid():
		_influence_tween.kill()
	if fade <= 0.0 or not is_inside_tree():
		_apply_influence(1.0 if on else 0.0)
		return
	_influence_tween = create_tween()
	_influence_tween.tween_method(_apply_influence, _influence, 1.0 if on else 0.0, fade)


## Deja la mano quieta en `world_pos` (brazo sin animador).
func rest_at(world_pos: Vector3, pitch_deg: float = 25.0) -> void:
	set_grip(world_pos, pitch_deg)
	drives_posture = false
	set_active(true, 0.0)


func is_active() -> bool:
	return _active


func _apply_influence(v: float) -> void:
	_influence = v
	figure.set_arm_ik_influence(side, v)
	hand_modifier.influence = v
	hand_modifier.controlled = v > 0.001
	figure.enable_arm_ik(side, v > 0.001)


func _process(delta: float) -> void:
	_time += delta
	if figure == null:
		return
	if _active or _influence > 0.001:
		_update_arm()
		_owns_posture = true
	elif _owns_posture:
		# Terminó de soltarse: el cuerpo se endereza (si otro brazo no lo ha tomado).
		_owns_posture = false
		if figure.get_meta("posture_owner", null) == self:
			figure.set_lean(0.0)
			figure.set_twist(0.0)
			figure.set_shift(0.0)


func _update_arm() -> void:
	# Orientación de la mano: dedos hacia delante y abajo según `_pitch`, palma abajo.
	var to := _grip - shoulder_position()
	var flat := Vector3(to.x, 0.0, to.z)
	var fwd := figure.global_basis * Vector3(0, 0, 1)
	var dir_h := fwd if flat.length() < 0.02 else flat.normalized()
	var d := (dir_h * cos(_pitch) + Vector3.DOWN * sin(_pitch)).normalized()
	var up_perp := (Vector3.UP - d * d.dot(Vector3.UP)).normalized()
	var x_axis := up_perp * _pal
	var b := Basis(x_axis, d, x_axis.cross(d))
	if absf(_roll) > 0.0001:
		b = b * Basis(Vector3(0, 1, 0), _roll)
	_hand_basis = b.orthonormalized()
	hand_modifier.hand_basis = _hand_basis
	var wrist := _grip - _hand_basis * _pinch_local() + _tremor_offset()

	# Inclinación del torso para que la muñeca quede al alcance.
	var inv := figure.global_transform.affine_inverse()
	var w_local := inv * wrist
	# Si la muñeca está al otro lado del cuerpo, el tronco gira para adelantar ese hombro.
	var u0 := UPPER_R if side == &"R" else Vector3(-UPPER_R.x, UPPER_R.y, UPPER_R.z)
	var cross := (w_local.x - u0.x) * (1.0 if side == &"R" else -1.0)
	var twist := clampf(cross * 1.6, 0.0, TWIST_MAX) * (1.0 if side == &"R" else -1.0)
	var k := _influence
	var plan := _solve_lean(w_local, twist)
	_lean_want = plan.x
	if drives_posture:
		figure.set_meta("posture_owner", self)
		figure.set_twist(twist * k)
		figure.set_lean(plan.x * k)
		figure.set_shift(plan.y * k)
	var sh := _upper_arm_after_lean(figure.lean_now()) + Vector3(0, 0, figure.shift_now() - u0.x * sin(figure.twist_now()))
	# Si aun así queda lejos, se acorta hacia el hombro (el IK no se estira).
	var from_sh := w_local - sh
	if from_sh.length() > REACH_COMFORT + 0.03:
		w_local = sh + from_sh.normalized() * (REACH_COMFORT + 0.03)
	target.global_position = figure.global_transform * w_local

	_update_pole(sh, w_local)

	# Dedos.
	hand_modifier.finger_curl = _curl.x
	hand_modifier.thumb_curl = _curl.y


## Polo del codo, recalculado cada fotograma (espacio local de la figura). El codo se coloca
## por fuera y algo por detrás de la mano; se busca el ángulo más bajo (más natural: el codo
## cuelga) con el que, sobre la mesa, queda al menos `ELBOW_MARGIN` por encima de ella.
func _update_pole(sh: Vector3, wrist: Vector3) -> void:
	var to := wrist - sh
	var d := maxf(to.length(), 0.05)
	var u := to / d
	var out := Vector3(-_pal, 0.0, 0.0)
	var e1 := out + Vector3(0.0, 0.0, -ELBOW_BACK)
	e1 = (e1 - u * e1.dot(u)).normalized()
	var e2 := u.cross(e1) * -_pal
	# Intersección de las esferas de radio upper/fore: distancia a lo largo del eje y altura.
	var a := (_len_upper * _len_upper - _len_fore * _len_fore + d * d) / (2.0 * d)
	var h := sqrt(maxf(_len_upper * _len_upper - a * a, 0.0))
	var xf := figure.global_transform
	var ang := ELBOW_PREF
	while ang < ELBOW_MAX:
		var e := sh + u * a + (e1 * cos(ang) + e2 * sin(ang)) * h
		var ew := xf * e
		var over := absf(ew.x) < TABLE_HALF.x + 0.05 and absf(ew.z) < TABLE_HALF.y + 0.05
		if not over or ew.y >= TABLE_TOP + ELBOW_MARGIN:
			break
		ang += deg_to_rad(4.0)
	# Sube de golpe (nunca atraviesa la mesa) y baja suavemente.
	if ang >= _elbow_angle:
		_elbow_angle = ang
	else:
		_elbow_angle = lerpf(_elbow_angle, ang, 1.0 - exp(-8.0 * get_process_delta_time()))
	_elbow_angle = maxf(_elbow_angle, ang)
	pole.position = sh + u * a + (e1 * cos(_elbow_angle) + e2 * sin(_elbow_angle)) * (h + 0.3)


func _pinch_local() -> Vector3:
	# Normal de la palma: -X local en R, +X en L; la pinza queda un poco hacia la palma.
	return Vector3(-_pal * PINCH_PALM, PINCH_Y, 0.0)


## Hombro (raíz del brazo) tras inclinar el torso `phi` radianes, en espacio local de la figura.
func _upper_arm_after_lean(phi: float) -> Vector3:
	var u := UPPER_R if side == &"R" else Vector3(-UPPER_R.x, UPPER_R.y, UPPER_R.z)
	var r := Basis(Vector3.RIGHT, phi * 0.5)
	var c1 := PIVOT + r * (CHEST - PIVOT)
	var u1 := PIVOT + r * (u - PIVOT)
	return c1 + r * (u1 - c1)


func _upper_x() -> float:
	return UPPER_R.x if side == &"R" else -UPPER_R.x


## Devuelve Vector2(inclinación, adelanto) mínimos para que la muñeca quede al alcance.
func _solve_lean(w_local: Vector3, twist: float) -> Vector2:
	for shift in [0.0, SHIFT_MAX]:
		var phi := 0.0
		while phi < LEAN_MAX:
			var sh := _upper_arm_after_lean(phi) + Vector3(0, 0, shift - _upper_x() * sin(twist))
			if sh.distance_to(w_local) <= REACH_COMFORT:
				return Vector2(phi, shift)
			phi += 0.02
	return Vector2(LEAN_MAX, SHIFT_MAX)


## Temblor de la mano: pequeño siempre, y crece con el estrés (poco tiempo en el reloj).
func _tremor_offset() -> Vector3:
	var amp := lerpf(0.0003, 0.006, pow(clampf(stress, 0.0, 1.0), 1.6)) * 0.5
	var t := _time
	return Vector3(
		sin(t * 47.0 + _phase.x) + 0.6 * sin(t * 71.0 + _phase.y),
		sin(t * 53.0 + _phase.y) + 0.5 * sin(t * 83.0 + _phase.z),
		sin(t * 43.0 + _phase.z) + 0.6 * sin(t * 67.0 + _phase.x)) * amp


## El ancla de la pieza sigue el punto de pinza de la mano YA posada (tras el IK), derecha.
func _update_anchor() -> void:
	if carry_anchor == null or not is_inside_tree():
		return
	var hand := figure.bone_global(StringName("Hand." + side))
	var hb := hand.basis.orthonormalized()
	carry_anchor.global_position = hand.origin + hb * _pinch_local()


# --- Pieza sujeta -----------------------------------------------------------------

## La pieza pasa a colgar del ancla de la mano, derecha, con la pinza a `grip_h` de su base.
func attach_piece(piece: Node3D, grip_h: float) -> void:
	var yaw := piece.global_rotation.y
	piece.reparent(carry_anchor, false)
	piece.position = Vector3(0.0, -grip_h, 0.0)
	piece.rotation = Vector3(0.0, yaw, 0.0)
	carried = piece


## Herramienta (la pluma): cuelga del ancla con el desplazamiento y la orientación dados
## (en ejes del mundo), porque el ancla no gira con la mano.
func attach_tool(tool_node: Node3D, offset: Vector3, basis: Basis) -> void:
	tool_node.reparent(carry_anchor, false)
	tool_node.transform = Transform3D(basis, offset)
	carried = tool_node


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
	var goal: Vector2 = POSE_CURLS[pose]
	if duration <= 0.0 or not is_inside_tree():
		_set_curl(goal)
		return
	var from := _curl
	_pose_tween = create_tween()
	_pose_tween.tween_method(func(t: float) -> void: _set_curl(from.lerp(goal, t)), 0.0, 1.0, duration) \
			.set_trans(Tween.TRANS_SINE)
	await _pose_tween.finished


func _set_curl(c: Vector2) -> void:
	_curl = c
	if hand_modifier != null:
		hand_modifier.finger_curl = c.x
		hand_modifier.thumb_curl = c.y
