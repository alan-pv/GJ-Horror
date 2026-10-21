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

enum Pose { OPEN, PINCH, GRIP, PRESS }

## Alcance cómodo de la muñeca desde el hombro (el brazo mide ~0,59 m).
const REACH_COMFORT := 0.55
## Tope de la inclinación del tronco (rad, ~34°), repartida entre pelvis, Spine y Chest
## (`TorsoLeanModifier.SHARES`): con más la espalda se encorva y la cabeza roza la mesa.
const LEAN_MAX := 0.70
## Cuánto puede adelantarse la cadera (todo el cuerpo) cuando la inclinación no basta.
const SHIFT_MAX := 0.20
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
## Radio del eje de pinza cuando no hay agarre, y de la pluma.
const DEFAULT_R := 0.014
const PEN_R := 0.0045
## Flexión de índice, medio y anular al pulsar con los dedos juntos (casi extendidos, algo curvos).
const PRESS_C := 0.2
## Pitch con el que se planea la pinza de la pluma y la mano sin agarre (grados).
const PLAN_PITCH := 55.0
## Superficie bajo la mano, para que los dedos no la atraviesen: la mesa, el tablero (sobre su huella,
## con el marco) o la hoja de la planilla (al escribir).
const BOARD_HALF := 0.24
const PAPER_TOP := TABLE_TOP + 0.008
## Eje de la pluma (de la punta hacia atrás) en el espacio de la mano derecha, al tomarla de la mesa
## (cruzada ante los dedos, pinza de frente) y al escribir (apoyada en la membrana entre pulgar e
## índice, en diagonal sobre los dedos sin atravesarlos). En la mano izquierda se reflejan (X
## invertida). Entre una y otra la pluma pivota en la pinza (`set_tool_blend`).
## Oposición pulgar-índice al escribir (grados): las yemas sujetan la pluma de lado, no diametrales; el medio la sostiene por debajo.
const PEN_WRITE_OPP := 150.0
const PEN_AXIS_GRASP := Vector3(0.0, 0.2, -0.98)
const PEN_AXIS_WRITE := Vector3(0.91, -0.34, 0.23)
## Distancia (m) del punto de pinza a la pieza a la que la mano ya adopta la orientación de agarre.
const GRASP_NEAR := 0.02
const GRASP_FAR := 0.11
## Geometría de la figura sentada (espacio local de la figura), medida con `sit_idle`.
const HIPS := Vector3(0.0, 0.54, 0.03)
const PIVOT := Vector3(0.0, 0.61, 0.03)
const CHEST := Vector3(0.0, 0.7387, 0.0481)
const UPPER_R := Vector3(-0.18, 0.8919, 0.0907)
## Flexión de cada dedo (pulgar, índice, medio, anular, meñique) de cada pose, en las unidades
## de `ArmPoseModifier` (0 = abierto). Con un agarre activo, PINCH cierra hasta tocar la pieza.
const POSE_CURLS := {
	Pose.OPEN: [0.05, 0.12, 0.16, 0.20, 0.26],
	Pose.PINCH: [0.55, 0.60, 0.9, 1.2, 1.3],
	Pose.GRIP: [0.90, 1.20, 1.30, 1.35, 1.40],
	Pose.PRESS: [0.70, 0.20, 0.20, 0.24, 0.32],
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
var _curls := PackedFloat32Array([0.05, 0.12, 0.16, 0.2, 0.26])
## Cuánto se cierra la mano sobre el agarre activo (0 = abierta, 1 = tocando) y cuánto pulsa con los dedos juntos.
var _grasp_w: float = 0.0
var _press_w: float = 0.0
## Agarre activo: datos de `PieceFactory.grasp_for` (o de una herramienta); vacío = ninguno.
var _grasp: Dictionary = {}
var _grasp_kind: StringName = &""
var _grasp_node: Node3D = null
var _grasp_data: Dictionary = {}
var _pinch_cur := Vector3(-0.012, 0.165, 0.0)
var _pinch_init: bool = false
## Pluma sujeta: orientación de la pluma respecto de la mano (fija mientras se sujeta) y si la
## mano la lleva rígida (`hold_tool`).
var _tool_local := Basis.IDENTITY
var _tool_local_w := Basis.IDENTITY
var _tool_blend: float = 0.0
var _tool_rigid: bool = false
var _plan_swing: float = 0.0
## Flexión de índice y pulgar del plan de pinza actual (`_pinch_target`): los dedos que tocan parten de ella.
var _plan_ci: float = -1.0
var _plan_ct: float = -1.0
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
	_set_curls(POSE_CURLS[Pose.OPEN])
	_prewarm_plans()


## Calcula de antemano los planes de pinza de cada pieza y de la pluma (el primero cuesta ~5 ms).
func _prewarm_plans() -> void:
	for t in [ChessPiece.PAWN, ChessPiece.ROOK, ChessPiece.KNIGHT, ChessPiece.BISHOP, ChessPiece.QUEEN, ChessPiece.KING]:
		var g := PieceFactory.grasp_for(t)
		hand_modifier.pinch_plan(maxf(float(g.radius), 0.0045), deg_to_rad(float(g.pitch)), deg_to_rad(float(g.roll)), 0.0, Vector3.ZERO, float(g.opposition))
	hand_modifier.pinch_plan(DEFAULT_R, deg_to_rad(PLAN_PITCH), 0.0)
	hand_modifier.pinch_plan(PEN_R, deg_to_rad(PLAN_PITCH), 0.0, 0.0, pen_axis(false))
	hand_modifier.pinch_plan(PEN_R, deg_to_rad(PLAN_PITCH), 0.0, 0.0, pen_axis(true), PEN_WRITE_OPP)


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


func get_roll_deg() -> float:
	return rad_to_deg(_roll)


## Activa el IK (con un fundido de `fade` s) o devuelve el brazo a la animación del personaje.
func set_active(on: bool, fade: float = 0.3) -> void:
	set_ik_weight(1.0 if on else 0.0, fade)


## Lleva la influencia del IK a `weight` (0 = solo la animación del personaje, 1 = la muñeca va al
## objetivo) con una mezcla suave de `seconds`. Con 0 el brazo muestra la animación (p. ej. la mano
## en la cara de `sit_wait__chin`); con 1 obedece a `set_grip`.
func set_ik_weight(weight: float, seconds: float = 0.4) -> void:
	weight = clampf(weight, 0.0, 1.0)
	_active = weight > 0.001
	if _influence_tween != null and _influence_tween.is_valid():
		_influence_tween.kill()
	if seconds <= 0.0 or not is_inside_tree():
		_apply_influence(weight)
		return
	_influence_tween = create_tween()
	_influence_tween.tween_method(_apply_influence, _influence, weight, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Influencia actual del IK (0..1).
func ik_weight() -> float:
	return _influence


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
	var dt := get_process_delta_time()
	_ensure_grasp()
	# Orientación de la mano: dedos hacia delante y abajo según el pitch, palma abajo. Cerca de la
	# pieza el pitch pasa suavemente al del agarre (la palma mira a la pieza).
	var to := _grip - shoulder_position()
	var flat := Vector3(to.x, 0.0, to.z)
	var fwd := figure.global_basis * Vector3(0, 0, 1)
	var dir_h := fwd if flat.length() < 0.02 else flat.normalized()
	_hand_basis = basis_for(dir_h, _effective_pitch(), _effective_roll(), _pal)
	hand_modifier.hand_basis = _hand_basis
	var pt := _pinch_target()
	_pinch_cur = pt if not _pinch_init else _pinch_cur.lerp(pt, 1.0 - exp(-25.0 * dt))
	_pinch_init = true
	var wrist := _grip - _hand_basis * _pinch_cur + _tremor_offset()

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

	_feed_fingers(dt)


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


## Base de la mano: Y hacia los dedos (hacia `dir_h` e inclinada `pitch` rad hacia abajo), palma
## abajo; `roll` gira sobre Y. `pal` = +1 (R) / -1 (L).
static func basis_for(dir_h: Vector3, pitch: float, roll: float, pal: float) -> Basis:
	var d := (dir_h * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()
	var up_perp := (Vector3.UP - d * d.dot(Vector3.UP)).normalized()
	var x_axis := up_perp * pal
	var b := Basis(x_axis, d, x_axis.cross(d))
	if absf(roll) > 0.0001:
		b = b * Basis(Vector3(0, 1, 0), roll)
	return b.orthonormalized()


## Punto de pinza en el espacio de la mano (suavizado): donde queda el eje de la pieza (o la
## pluma) entre las yemas.
func _pinch_local() -> Vector3:
	return _pinch_cur


## Punto de pinza deseado (espacio de la mano): el eje de la pieza entre las yemas de pulgar e
## índice, derivado de la geometría real de los dedos (`ArmPoseModifier.pinch_plan`). Con la pose
## PRESS es el punto de las yemas de índice, medio y anular juntas.
func _pinch_target() -> Vector3:
	var r: float = DEFAULT_R
	# Pitch y giro fijos (los del agarre o unos por defecto): el plan se calcula una vez por radio.
	var pitch := deg_to_rad(PLAN_PITCH)
	var roll := 0.0
	var opp := 180.0
	if not _grasp.is_empty():
		r = maxf(float(_grasp.get("radius", DEFAULT_R)), 0.0045)
		opp = float(_grasp.get("opposition", 180.0))
		if float(_grasp.get("pitch", -1.0)) > 0.0:
			pitch = deg_to_rad(float(_grasp.pitch))
			roll = deg_to_rad(float(_grasp.get("roll", 0.0)))
	var plan: Dictionary
	if _grasp_kind == &"tool":
		# La pinza se mueve del plan de la toma al del agarre de escritura según la pluma pivota.
		var pg: Dictionary = hand_modifier.pinch_plan(r, pitch, roll, 0.0, pen_axis(false))
		var pw: Dictionary = hand_modifier.pinch_plan(r, pitch, roll, 0.0, pen_axis(true), PEN_WRITE_OPP)
		plan = pg.duplicate()
		plan["a"] = (pg.a as Vector3).lerp(pw.a as Vector3, _tool_blend)
		plan["sw"] = lerpf(float(pg.sw), float(pw.sw), _tool_blend)
		plan["ci"] = lerpf(float(pg.ci), float(pw.ci), _tool_blend)
		plan["ct"] = lerpf(float(pg.ct), float(pw.ct), _tool_blend)
	else:
		plan = hand_modifier.pinch_plan(r, pitch, roll, 0.0, Vector3.ZERO, opp)
	_plan_swing = float(plan.get("sw", 0.0))
	_plan_ci = float(plan.get("ci", -1.0))
	_plan_ct = float(plan.get("ct", -1.0))
	var a: Vector3 = plan.a
	if _press_w > 0.001:
		a = a.lerp(hand_modifier.press_point(PRESS_C), _press_w)
	return a


## Altura de la superficie sobre la que está la mano en `p` (mundo): hoja con la pluma, tablero sobre
## su huella, y la mesa en el resto.
func surface_height(p: Vector3) -> float:
	if _grasp_kind == &"tool":
		return PAPER_TOP
	if absf(p.x) < BOARD_HALF and absf(p.z) < BOARD_HALF:
		return BoardView.BOARD_TOP
	return TABLE_TOP


func _axis_dir() -> Vector3:
	if _grasp_kind == &"tool" and carried != null and is_instance_valid(carried):
		return carried.global_basis.x.normalized()
	return Vector3.UP


## Cuánto domina el agarre sobre la orientación pedida: 1 con la pieza en la mano o con el punto de
## pinza sobre ella, 0 lejos (la mano sigue la orientación del traslado).
func _grasp_weight() -> float:
	if _grasp.is_empty() or _grasp_kind != &"piece":
		return 0.0
	if carried != null or _grasp_node == null or not is_instance_valid(_grasp_node):
		return 1.0
	var p := _grasp_node.global_position + Vector3(0, float(_grasp.height), 0)
	return 1.0 - smoothstep(GRASP_NEAR, GRASP_FAR, _grip.distance_to(p))


## Pitch efectivo: el pedido por el gesto, llevado al del agarre cuando la mano está sobre la pieza.
func _effective_pitch() -> float:
	var w := _grasp_weight()
	if w <= 0.0:
		return _pitch
	return lerp_angle(_pitch, deg_to_rad(float(_grasp.pitch)), w)


## Giro efectivo sobre los dedos: palma de lado (pulgar arriba) al agarrar.
func _effective_roll() -> float:
	var w := _grasp_weight()
	if w <= 0.0:
		return _roll
	return lerp_angle(_roll, deg_to_rad(float(_grasp.get("roll", 0.0))) * _pal, w)


## Hombro (raíz del brazo) tras inclinar el torso `phi` radianes, en espacio local de la figura.
func _upper_arm_after_lean(phi: float) -> Vector3:
	var u := UPPER_R if side == &"R" else Vector3(-UPPER_R.x, UPPER_R.y, UPPER_R.z)
	# Cinemática directa desde el hombro: primero Chest, luego Spine y por último la pelvis.
	var p := CHEST + Basis(Vector3.RIGHT, phi * float(TorsoLeanModifier.SHARES["Chest"])) * (u - CHEST)
	p = PIVOT + Basis(Vector3.RIGHT, phi * float(TorsoLeanModifier.SHARES["Spine"])) * (p - PIVOT)
	return HIPS + Basis(Vector3.RIGHT, phi * float(TorsoLeanModifier.SHARES["Hips"])) * (p - HIPS)


func _upper_x() -> float:
	return UPPER_R.x if side == &"R" else -UPPER_R.x


## Devuelve Vector2(inclinación, adelanto) mínimos para que la muñeca quede al alcance.
func _solve_lean(w_local: Vector3, twist: float) -> Vector2:
	for shift in [0.0, SHIFT_MAX * 0.5, SHIFT_MAX]:
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
	if _tool_rigid and carried != null and is_instance_valid(carried) and carried.get_parent() == carry_anchor:
		# La pluma va fija en la mano: su orientación sale de la de la mano y el punto de agarre
		# (a `PEN_GRIP` de la punta) queda en la pinza.
		var pb := (hb * _tool_local.slerp(_tool_local_w, _tool_blend)).orthonormalized()
		carried.transform = Transform3D(pb, -pb.x * ScoresheetView.PEN_GRIP)


# --- Pieza sujeta -----------------------------------------------------------------

## La pieza pasa a colgar del ancla de la mano, derecha, con la pinza a `grip_h` de su base.
func attach_piece(piece: Node3D, grip_h: float) -> void:
	if _grasp_node != piece or _grasp.is_empty():
		begin_grasp(piece)
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
	_begin_tool_grasp(tool_node)


## Suelta la pieza (sigue siendo hija del ancla hasta que el tablero la reciba).
func release_piece() -> Node3D:
	var p := carried
	carried = null
	end_grasp()
	return p


# --- Agarre ---------------------------------------------------------------------------

## Empieza a agarrar `piece` (un nodo de `PieceFactory`, con su meta `code`): la mano se
## orienta hacia ella al acercarse y, con la pose PINCH, los dedos se cierran hasta tocarla.
## Llamarlo antes de alcanzarla; `attach_piece` lo hace sola si no se llamó.
func begin_grasp(piece: Node3D) -> void:
	if piece == null or not piece.has_meta("code"):
		return
	_grasp = PieceFactory.grasp_for(int(piece.get_meta("code")))
	_grasp_kind = &"piece"
	_grasp_node = piece


## Fin del agarre (se llama sola al soltar con `release_piece`).
func end_grasp() -> void:
	_tool_rigid = false
	_tool_blend = 0.0
	_grasp = {}
	_grasp_kind = &""
	_grasp_node = null
	hand_modifier.grasp = {}


func has_grasp() -> bool:
	return not _grasp.is_empty()


func _begin_tool_grasp(tool_node: Node3D) -> void:
	_grasp = {
		"radius": PEN_R, "pitch": -1.0, "height": 0.0,
		"contact": PackedInt32Array([ArmPoseModifier.THUMB, ArmPoseModifier.INDEX, ArmPoseModifier.MIDDLE]),
		"profile": PackedFloat32Array([PEN_R, PEN_R]), "step": 1.0,
	}
	_grasp_kind = &"tool"
	_grasp_node = tool_node


## Eje de la pluma en el espacio de ESTA mano (reflejado en la izquierda): el de la toma o el de
## escribir.
func pen_axis(writing: bool) -> Vector3:
	var u := PEN_AXIS_WRITE if writing else PEN_AXIS_GRASP
	return Vector3(u.x * _pal, u.y, u.z).normalized()


## Pivote de la pluma entre los dedos: 0 = como se tomó, 1 = en postura de escribir. La pluma gira
## sobre la pinza (el ángulo respecto de los dedos cambia, como al reacomodar el lápiz).
func set_tool_blend(k: float) -> void:
	_tool_blend = clampf(k, 0.0, 1.0)


## Prepara el agarre de la pluma (en la mesa o ya en la mano) para que la mano se oriente y los
## dedos la rodeen desde la aproximación.
func begin_tool(tool_node: Node3D) -> void:
	_begin_tool_grasp(tool_node)


## La pluma pasa a la mano sin saltos: cuelga del ancla y mantiene su orientación actual respecto
## de la mano; desde aquí la mano la lleva rígida (la orientación de la pluma sale de la de la
## mano, así gira al girar la muñeca).
func hold_tool(tool_node: Node3D) -> void:
	if _grasp_kind != &"tool" or _grasp_node != tool_node:
		_begin_tool_grasp(tool_node)
	var hb := figure.bone_global(StringName("Hand." + side)).basis.orthonormalized()
	_tool_local = (hb.inverse() * tool_node.global_basis).orthonormalized()
	# Postura de escribir: el giro más corto del eje actual al de escribir, sobre la pinza.
	var ax := _tool_local.x.normalized()
	_tool_local_w = (Basis(Quaternion(ax, pen_axis(true))) * _tool_local).orthonormalized()
	_tool_blend = 0.0
	tool_node.reparent(carry_anchor, true)
	carried = tool_node
	_tool_rigid = true


## Pitch y roll (grados) con los que ESTA mano, mirando hacia `dir_h` (horizontal), lleva el eje de
## toma de la pluma hacia `want` (dirección mundo de la punta hacia atrás). `z` del resultado es el
## error angular en grados.
func orient_for_pen(want: Vector3, dir_h: Vector3, pitch_pref: float = 55.0) -> Vector3:
	return orient_for_axis(pen_axis(false), want, dir_h, _pal, pitch_pref)


## Dirección mundo del eje de escribir de la pluma con la mano a `dir_h`, `pitch` y `roll` (grados).
func pen_write_axis_world(dir_h: Vector3, pitch_deg: float, roll_deg: float) -> Vector3:
	return basis_for(dir_h, deg_to_rad(pitch_deg), deg_to_rad(roll_deg), _pal) * pen_axis(true)


## Busca (pitch, roll) en grados con los que una mano con `pal` (+1 R / -1 L), mirando a `dir_h`,
## lleva el eje `u` (espacio de la mano) hacia `want` (mundo). Devuelve Vector3(pitch, roll, error
## en grados). Rejilla más refinamiento; prefiere posturas cerca de `pitch_pref` y sin giros
## exagerados.
static func orient_for_axis(u: Vector3, want: Vector3, dir_h: Vector3, pal: float, pitch_pref: float = 62.0) -> Vector3:
	var w := want.normalized()
	var best := Vector3(pitch_pref, 0.0, 180.0)
	var best_cost := 1e18
	var step := 4.0
	var p0 := 5.0
	var r0 := -120.0
	var p1 := 85.0
	var r1 := 120.0
	for _pass in 3:
		var p := p0
		while p <= p1:
			var r := r0
			while r <= r1:
				var b := basis_for(dir_h, deg_to_rad(p), deg_to_rad(r), pal)
				var err := rad_to_deg((b * u).angle_to(w))
				var cost := err * err * 10.0 + pow((p - pitch_pref) * 0.05, 2.0) + pow(r * 0.03, 2.0)
				if cost < best_cost:
					best_cost = cost
					best = Vector3(p, r, err)
				r += step
			p += step
		step *= 0.25
		p0 = best.x - step * 4.0
		p1 = best.x + step * 4.0
		r0 = best.y - step * 4.0
		r1 = best.y + step * 4.0
	return best


## Si algo cuelga de la mano sin pasar por `attach_*`, se deduce el agarre (pieza o herramienta).
func _ensure_grasp() -> void:
	if carried == null or not _grasp.is_empty() or not is_instance_valid(carried):
		return
	if carried.has_meta("code"):
		begin_grasp(carried)
	else:
		_begin_tool_grasp(carried)


## Pasa a los dedos las flexiones, el agarre y el temblor de este fotograma.
func _feed_fingers(dt: float) -> void:
	var m := hand_modifier
	m.curls = _curls
	m.time = _time
	m.dt = dt
	m.tremor = lerpf(0.006, 0.07, pow(clampf(stress, 0.0, 1.0), 1.5))
	m.floor_y = surface_height(_grip)
	if _grasp.is_empty():
		m.grasp = {}
		return
	var base := Vector3.ZERO
	var dir := Vector3.UP
	if _grasp_kind == &"tool" and _grasp_node != null and is_instance_valid(_grasp_node):
		base = _grasp_node.global_position
		dir = _grasp_node.global_basis.x.normalized()
	elif _grasp_node != null and is_instance_valid(_grasp_node):
		base = _grasp_node.global_position
	else:
		base = _grip - Vector3(0, float(_grasp.height), 0)
	_grasp_data["axis_point"] = base
	_grasp_data["axis_dir"] = dir
	_grasp_data["profile"] = _grasp.profile
	_grasp_data["step"] = _grasp.step
	_grasp_data["contact"] = _grasp.contact
	_grasp_data["weight"] = _grasp_w
	_grasp_data["relax"] = 0.7
	_grasp_data["thumb_swing"] = _plan_swing
	_grasp_data["plan_ci"] = _plan_ci
	_grasp_data["plan_ct"] = _plan_ct
	m.grasp = _grasp_data


# --- Poses de dedos -----------------------------------------------------------------

## Mezcla hacia una pose en `duration` segundos (corrutina: se puede esperar). PINCH con un
## agarre activo cierra los dedos hasta tocar la pieza; PRESS estira los dedos juntos (pulsar el reloj).
func set_pose(pose: Pose, duration: float = 0.2) -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()
	var goal := PackedFloat32Array(POSE_CURLS[pose])
	var g_goal := 1.0 if pose == Pose.PINCH else 0.0
	var p_goal := 1.0 if pose == Pose.PRESS else 0.0
	if duration <= 0.0 or not is_inside_tree():
		_set_curls(goal)
		_grasp_w = g_goal
		_press_w = p_goal
		return
	var from := _curls.duplicate()
	var g0 := _grasp_w
	var p0 := _press_w
	_pose_tween = create_tween()
	_pose_tween.tween_method(func(t: float) -> void:
		var c := PackedFloat32Array()
		c.resize(5)
		for i in 5:
			c[i] = lerpf(from[i], goal[i], t)
		_set_curls(c)
		_grasp_w = lerpf(g0, g_goal, t)
		_press_w = lerpf(p0, p_goal, t), 0.0, 1.0, duration) \
			.set_trans(Tween.TRANS_SINE)
	await _pose_tween.finished


func _set_curls(c: PackedFloat32Array) -> void:
	_curls = c
	if hand_modifier != null:
		hand_modifier.curls = c
