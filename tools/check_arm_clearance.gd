extends SceneTree
## Comprueba que el brazo (codo y antebrazo) nunca atraviesa la mesa (superficie a 0,72 m,
## 1,30 x 0,90 m) ni el torso la atraviesa, con el brazo de la mesa del jugador yendo a todas
## las casillas, al botón del reloj y a la planilla, con las piezas a distintas alturas.
## Uso: godot --headless --path . --script res://tools/check_arm_clearance.gd

const TABLE_HALF := Vector2(0.65, 0.45)
const TABLE_TOP := 0.72
## Margen bajo el cual un punto del brazo dentro de la huella de la mesa cuenta como atravesada.
const SLAB_BOTTOM := 0.60
## Altura del hombro con la figura erguida (el tronco inclinado lo baja, así que se mide contra esta).
const SHOULDER_REST_Y := 0.892

## Métricas de naturalidad acumuladas (una entrada por postura alcanzada).
var _dbg := 0
var _nat_rel_sh: Array[float] = []  # altura del codo menos la del hombro (m)
var _nat_above: Array[float] = []   # altura del codo sobre la mesa (m)
var _nat_out: Array[float] = []     # desplazamiento lateral del codo hacia fuera (m)
var _nat_back: Array[float] = []    # cuánto queda el codo detrás de la mano (m)


func _init() -> void:
	await process_frame
	await _run()


func _run() -> void:
	var worst := 99.0
	var max_err := 0.0
	var fails := 0
	var far := 0
	var checked := 0
	for who in 2:
		var fig := SeatedFigure.new()
		fig.lean_speed = 1000.0
		root.add_child(fig)
		var rig := HandRig.new()
		root.add_child(rig)
		var sgn := 1.0
		if who == 0:
			fig.position = Vector3(0, 0, 0.8)
			fig.rotation.y = PI
			fig.play(&"sit_idle", 0.0)
			rig.setup(fig, &"R")
		else:
			fig.position = Vector3(0, 0, -0.8)
			sgn = -1.0
			fig.play(&"sit_idle", 0.0)
			rig.setup(fig, &"L")
		rig.set_active(true, 0.0)
		var targets: Array[Vector3] = []
		var board := BoardView.new()
		root.add_child(board)
		board.setup(ChessPiece.WHITE)
		for sq in 64:
			var p := board.square_to_world(sq)
			for h in [0.0, 0.07]:
				targets.append(p + Vector3(0, 0.05 + h, 0))
		targets.append(Vector3(0.42, 0.83, sgn * 0.06))
		targets.append(Vector3(0.58, 0.745, sgn * 0.30))
		targets.append(Vector3(0.34, 0.75, sgn * 0.40))
		targets.append(Vector3(0.16, 0.78, sgn * 0.44))
		targets.append(Vector3(0.12, 0.60, sgn * 0.58))
		for t in targets:
			for pitch in [40.0, 58.0, 75.0, 80.0]:
				rig.set_grip(t, pitch)
				for i in 4:
					await process_frame
				var c := _clearance(fig, rig.side)
				if checked % 100000 == 0:
					print("muestra figura %d objetivo %s: codo %s mano %s holgura %.3f" % [who, t, fig.bone_global(StringName("Forearm." + rig.side)).origin, fig.bone_global(StringName("Hand." + rig.side)).origin, c])
				checked += 1
				var err := rig.carry_anchor.global_position.distance_to(t)
				max_err = maxf(max_err, err)
				if err > 0.03:
					far += 1
					if far < 6:
						print("no alcanza: figura %d objetivo %s pitch %.0f error %.3f lean %.2f" % [who, t, pitch, err, fig.lean_now()])
				worst = minf(worst, c)
				if err < 0.03:
					_sample_naturalness(fig, rig.side)
					if OS.get_cmdline_user_args().has("--debug") and _nat_rel_sh[-1] > 0.05 and _dbg < 12:
						_dbg += 1
						print("DBG fig %d t %s pitch %.0f rel %.3f lean %.2f sh.y %.3f el %s hand %s" % [who, t, pitch, _nat_rel_sh[-1], fig.lean_now(), fig.bone_global(StringName("UpperArm." + rig.side)).origin.y, fig.bone_global(StringName("Forearm." + rig.side)).origin, fig.bone_global(StringName("Hand." + rig.side)).origin])
				if c < 0.0:
					fails += 1
					if fails < 8:
						print("ATRAVIESA: figura %d objetivo %s pitch %.0f holgura %.3f" % [who, t, pitch, c])
		fig.queue_free()
		rig.queue_free()
		board.queue_free()
	_report_naturalness()
	await _check_rest()
	print("[brazo] %d posturas, %d atraviesan la mesa, holgura mínima %.3f m, error máximo de pinza %.3f m" % [checked, fails, worst, max_err])
	quit(1 if fails > 0 else 0)


## Holgura mínima (m) entre el brazo y el volumen de la mesa: negativa = atraviesa.
func _clearance(fig: SeatedFigure, side: StringName) -> float:
	var shoulder := fig.bone_global(StringName("UpperArm." + side)).origin
	var elbow := fig.bone_global(StringName("Forearm." + side)).origin
	var hand := fig.bone_global(StringName("Hand." + side)).origin
	var worst := 99.0
	for seg in [[shoulder, elbow], [elbow, hand]]:
		for i in 11:
			var p: Vector3 = (seg[0] as Vector3).lerp(seg[1], i / 10.0)
			worst = minf(worst, _inside_depth(p))
	return worst


## Holgura de un punto respecto de la losa de la mesa (positiva = fuera).
func _inside_depth(p: Vector3) -> float:
	var dx := TABLE_HALF.x - absf(p.x)
	var dz := TABLE_HALF.y - absf(p.z)
	var dy_top := p.y - TABLE_TOP
	var dy_bot := SLAB_BOTTOM - p.y
	# Dentro si es "interior" en los tres ejes; la holgura es la salida más corta.
	return maxf(maxf(-dx, -dz), maxf(dy_top, dy_bot))


## Anota la naturalidad de la postura actual: el codo debe quedar por fuera y por detrás de la
## mano, por encima de la mesa pero no a la altura del hombro ("brazo en ala").
func _sample_naturalness(fig: SeatedFigure, side: StringName) -> void:
	var inv := fig.global_transform.affine_inverse()
	var sh: Vector3 = inv * fig.bone_global(StringName("UpperArm." + side)).origin
	var el: Vector3 = inv * fig.bone_global(StringName("Forearm." + side)).origin
	var ha: Vector3 = inv * fig.bone_global(StringName("Hand." + side)).origin
	var outward := -1.0 if side == &"R" else 1.0
	_nat_rel_sh.append(el.y - SHOULDER_REST_Y)
	_nat_above.append(fig.bone_global(StringName("Forearm." + side)).origin.y - TABLE_TOP)
	_nat_out.append((el.x - lerpf(sh.x, ha.x, 0.5)) * outward)
	_nat_back.append(ha.z - el.z)


func _stat(a: Array[float]) -> String:
	if a.is_empty():
		return "sin datos"
	var sum := 0.0
	for v in a:
		sum += v
	return "min %.3f  media %.3f  max %.3f" % [a.min(), sum / a.size(), a.max()]


func _report_naturalness() -> void:
	var wing := 0
	var above := 0
	for v in _nat_rel_sh:
		if v > -0.03:
			wing += 1
		if v > 0.0:
			above += 1
	print("[natural] %d posturas alcanzadas" % _nat_rel_sh.size())
	print("[natural] codo - hombro erguido (m, ideal < 0):  ", _stat(_nat_rel_sh))
	print("[natural] codo sobre la mesa (m):        ", _stat(_nat_above))
	print("[natural] codo hacia fuera (m, > 0):     ", _stat(_nat_out))
	print("[natural] codo detras de la mano (m, > 0): ", _stat(_nat_back))
	print("[natural] codo a la altura del hombro o mas (en ala): %.1f %%" % (100.0 * wing / maxf(_nat_rel_sh.size(), 1)))
	print("[natural] codo por encima del hombro: %.1f %%" % (100.0 * above / maxf(_nat_rel_sh.size(), 1)))


## Reposo: con el IK apagado manda la animación; se mide dónde quedan codo y mano y la holgura.
func _check_rest() -> void:
	for anim in [&"sit_idle", &"sit_think", &"sit_nervous"]:
		for who in 2:
			var fig := SeatedFigure.new()
			root.add_child(fig)
			fig.position = Vector3(0, 0, 0.8 if who == 0 else -0.8)
			fig.rotation.y = PI if who == 0 else 0.0
			fig.play(anim, 0.0)
			for i in 6:
				await process_frame
			for side in [&"R", &"L"]:
				var inv := fig.global_transform.affine_inverse()
				var el: Vector3 = fig.bone_global(StringName("Forearm." + side)).origin
				var ha: Vector3 = fig.bone_global(StringName("Hand." + side)).origin
				var sh: Vector3 = fig.bone_global(StringName("UpperArm." + side)).origin
				print("[reposo] %s %s figura %d: codo %s mano %s (local %s) holgura %.3f codo-hombro %.3f" % [anim, side, who, el, ha, inv * ha, _clearance(fig, side), el.y - sh.y])
			fig.queue_free()
