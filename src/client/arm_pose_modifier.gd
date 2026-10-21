class_name ArmPoseModifier
extends SkeletonModifier3D
## Va DESPUÉS del IK del brazo: el IK solo coloca la muñeca, así que aquí se orienta la mano
## (dedos y palma hacia donde se pide) y se flexiona cada dedo, falange por falange.
##
## Ejes del hueso `Hand.*` (medidos con la figura sentada): +Y hacia los dedos, el eje
## transversal es Z local y la normal de la palma es -X local en la mano derecha y +X en la
## izquierda. Los dedos se doblan hacia la palma girando sobre Z: `Quaternion(Z, +a)` en R y
## `-a` en L, antepuesto a la rotación de reposo del hueso.
##
## Esqueleto nuevo: por lado `sd`, `Thumb1..3.sd`, `Index1..3.sd`, `Middle1..3.sd`,
## `Ring1..3.sd`, `Pinky1..3.sd` (X1 hijo de `Hand.sd`; X3 termina en la yema). Respaldo con el
## esqueleto viejo: un solo hueso `Fingers.sd` (hace de índice y medio, anular y meñique) y
## `Thumb.sd`. Las longitudes de falange salen del reposo del esqueleto; la longitud de la
## yema y su grosor, de la malla de piel (se miden una vez por malla).
##
## Cada dedo se controla con UNA flexión `c` (0 = abierto) que se reparte entre las falanges
## con `W`. Con un agarre activo (`grasp`) los dedos que participan se cierran hasta que su
## yema toca la superficie de la pieza (superficie de revolución sobre el eje del agarre):
## `c` se resuelve por búsqueda (marcha + bisección) a partir del valor del fotograma anterior.

const THUMB := 0
const INDEX := 1
const MIDDLE := 2
const RING := 3
const PINKY := 4
const FINGER_NAMES: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
## Reparto de la flexión `c` entre las tres falanges de cada dedo.
const W: Array[Vector3] = [
	Vector3(0.25, 0.5, 0.5),
	Vector3(1.0, 1.1, 0.7),
	Vector3(1.0, 1.1, 0.7),
	Vector3(1.0, 1.1, 0.75),
	Vector3(1.0, 1.1, 0.8),
]
## Flexión máxima de un dedo (≈ puño cerrado) y paso de la búsqueda de contacto.
const C_MAX := 1.45
const C_STEP := 0.1
const BISECT_STEPS := 6
## Rapidez máxima (unidades de `c` por segundo) con que un dedo cambia de flexión; al cerrarse
## contra una pieza el tope nunca se supera (no la atraviesa).
const C_SLEW := 14.0
## Margen de la yema (m) por debajo del cual se considera tocando.
const CONTACT_EPS := 0.0004
## Longitud de yema y grosor de respaldo (sin malla de piel).
const FALLBACK_TIP_RATIO := 0.8
const FALLBACK_PAD := 0.006
## Flexión "nominal" del índice con la que se calcula el punto de pinza.
const PINCH_C := 0.55

class Chain:
	var finger: int = 0
	var bones: PackedInt32Array = PackedInt32Array()
	## Transformación local de reposo de cada hueso (origen y rotación) respecto de su padre.
	var rest: Array[Transform3D] = []
	var tip_len: float = 0.0
	var pad: float = 0.006
	var w: Vector3 = Vector3(1, 1, 1)
	## Punto de contacto de la yema en el marco del último hueso.
	var contact_local: Vector3 = Vector3.ZERO

	## Marco del último hueso, en el espacio de la mano, con flexión `c` (signo `sgn` = lado).
	func last_frame(c: float, sgn: float, sw: float = 0.0) -> Transform3D:
		var t := Transform3D.IDENTITY
		for k in bones.size():
			var a := c * w[k] * sgn
			var b := Basis(Vector3(0, 0, 1), a) * rest[k].basis
			if k == 0 and sw != 0.0:
				# Abducción (solo pulgar): lo acerca o aleja de los demás dedos, sobre X de la mano.
				b = Basis(Vector3(1, 0, 0), -sgn * sw) * b
			t = t * Transform3D(b, rest[k].origin)
		return t

	## Punto de contacto de la yema en el espacio de la mano.
	func pad_point(c: float, sgn: float, sw: float = 0.0) -> Vector3:
		return last_frame(c, sgn, sw) * contact_local

	## Extremo del dedo (la punta del hueso) en el espacio de la mano.
	func tip_point(c: float, sgn: float) -> Vector3:
		return last_frame(c, sgn) * Vector3(0, tip_len, 0)

	## Direcciones de la yema (hacia la palma) en el espacio de la mano.
	func pad_normal(c: float, sgn: float) -> Vector3:
		return last_frame(c, sgn).basis * Vector3(contact_local.x, 0, 0).normalized()

	## Posiciones de las articulaciones y la yema (para pruebas).
	func joints(c: float, sgn: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		var t := Transform3D.IDENTITY
		for k in bones.size():
			var b := Basis(Vector3(0, 0, 1), c * w[k] * sgn) * rest[k].basis
			t = t * Transform3D(b, rest[k].origin)
			out.append(t.origin)
		out.append(t * Vector3(0, tip_len, 0))
		return out

static var _tip_cache: Dictionary = {}
## Planes de pinza ya calculados (los esqueletos de las figuras son idénticos): clave lado + parámetros.
static var _plans: Dictionary = {}

var side: StringName = &"R"
## Orientación deseada de la mano en el MUNDO (Y = hacia los dedos).
var hand_basis: Basis = Basis.IDENTITY
## Si es false el modificador no toca nada (la mano sigue a la animación).
var controlled: bool = false
## Flexión de cada dedo (`THUMB`..`PINKY`) cuando no hay agarre, o su valor de partida.
var curls: PackedFloat32Array = PackedFloat32Array([0.05, 0.12, 0.16, 0.2, 0.26])
## Atajos de la API vieja: cierre de los dedos y del pulgar (si se fijan, pisan `curls`).
var finger_curl: float:
	set(v):
		for f in range(1, 5):
			curls[f] = v
var thumb_curl: float:
	set(v):
		curls[THUMB] = v
## Agarre activo (vacío = sin agarre). Claves: `axis_point` (punto del eje, mundo), `axis_dir`
## (dirección unitaria, mundo), `profile` (PackedFloat32Array de radios desde `axis_point` a lo
## largo del eje cada `step` m), `step`, `contact` (PackedInt32Array de dedos que tocan),
## `weight` (0..1 cuánto se cierran), `relax` (flexión de los que no tocan).
var grasp: Dictionary = {}
## Temblor de los dedos: amplitud en radianes y tiempo (lo fija el dueño).
var tremor: float = 0.0
var time: float = 0.0
## Paso de tiempo para limitar la rapidez de los dedos (lo fija el dueño; 0 = sin límite).
var dt: float = 0.0

var _sk: Skeleton3D
var _hand: int = -1
var _chains: Array = []  # Chain por dedo (null si no hay hueso)
var _c_out := PackedFloat32Array([0.05, 0.12, 0.16, 0.2, 0.26])
var _c_prev := PackedFloat32Array([0.5, 0.5, 0.5, 0.5, 0.5])
var _touch := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0, -1.0])
var _legacy: bool = false
## Abducción actual del pulgar (rad): la fija el agarre (`thumb_swing`) y vuelve a 0 sin agarre.
var _swing: float = 0.0
var _swing_goal: float = 0.0


func _process_modification() -> void:
	if not controlled:
		return
	var sk := _skeleton()
	if sk == null:
		return
	if not _ensure_chains(sk):
		return
	var parent := sk.get_bone_parent(_hand)
	var pb := _global(sk, parent).basis
	var sk_xf := sk.global_transform if sk.is_inside_tree() else Transform3D.IDENTITY
	var want := sk_xf.basis.orthonormalized().inverse() * hand_basis
	sk.set_bone_pose_rotation(_hand, (pb.inverse() * want).orthonormalized().get_rotation_quaternion())
	var sgn := _sign()
	var targets := _targets(sk, sk_xf)
	if _legacy:
		# Un solo hueso para los cuatro dedos: promedio de sus flexiones.
		targets[INDEX] = (targets[1] + targets[2] + targets[3] + targets[4]) * 0.25
	for f in 5:
		var ch: Chain = _chains[f]
		if ch == null:
			continue
		var c: float = targets[f]
		if dt > 0.0:
			c = move_toward(_c_out[f], c, C_SLEW * dt) if c > _c_out[f] else c
		if _touch[f] >= 0.0:
			c = minf(c, _touch[f])
		_c_out[f] = c
		_apply(sk, ch, c - _tremor(f), sgn, _swing if f == THUMB else 0.0)


## Transformación global (espacio del esqueleto) de un hueso. Fuera del árbol (pruebas) el esqueleto
## no recalcula las globales, así que se componen desde las poses locales.
func _global(sk: Skeleton3D, bone: int) -> Transform3D:
	if bone < 0:
		return Transform3D.IDENTITY
	if sk.is_inside_tree():
		return sk.get_bone_global_pose(bone)
	return _global(sk, sk.get_bone_parent(bone)) * Transform3D(Basis(sk.get_bone_pose_rotation(bone)), sk.get_bone_pose_position(bone))


func _skeleton() -> Skeleton3D:
	var sk := get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	return sk


func _sign() -> float:
	return 1.0 if side == &"R" else -1.0


# --- Cadenas de dedos --------------------------------------------------------------

## Construye (una vez) las cadenas de falanges a partir del reposo del esqueleto.
func _ensure_chains(sk: Skeleton3D) -> bool:
	if _sk == sk and _hand >= 0:
		return true
	_sk = sk
	_hand = sk.find_bone("Hand." + side)
	if _hand < 0:
		return false
	_chains.clear()
	_chains.resize(5)
	_legacy = false
	for f in 5:
		var idx := PackedInt32Array()
		for k in 3:
			var b := sk.find_bone("%s%d.%s" % [FINGER_NAMES[f], k + 1, side])
			if b >= 0:
				idx.append(b)
		if idx.size() == 3:
			_chains[f] = _make_chain(sk, f, idx)
	if _chains.all(func(c: Variant) -> bool: return c == null):
		# Esqueleto viejo: un hueso para los cuatro dedos y otro para el pulgar.
		_legacy = true
		var fb := sk.find_bone("Fingers." + side)
		var tb := sk.find_bone("Thumb." + side)
		if fb >= 0:
			_chains[INDEX] = _make_chain(sk, INDEX, PackedInt32Array([fb]))
		if tb >= 0:
			_chains[THUMB] = _make_chain(sk, THUMB, PackedInt32Array([tb]))
	return true


func _make_chain(sk: Skeleton3D, f: int, idx: PackedInt32Array) -> Chain:
	var ch := Chain.new()
	ch.finger = f
	ch.bones = idx
	for b in idx:
		ch.rest.append(sk.get_bone_rest(b))
	ch.w = W[f] if idx.size() == 3 else Vector3(1.0 if f != THUMB else 0.55, 0, 0)
	var last := idx[idx.size() - 1]
	var seg := 0.0
	if idx.size() >= 2:
		seg = ch.rest[idx.size() - 1].origin.length()
	var meas := _measure(sk, last)
	ch.tip_len = meas.x if meas.x > 0.0 else (seg * FALLBACK_TIP_RATIO if seg > 0.0 else 0.075)
	ch.pad = meas.y if meas.y > 0.0 else FALLBACK_PAD
	ch.contact_local = Vector3(-_sign() * ch.pad, maxf(ch.tip_len - ch.pad, 0.0), 0.0)
	return ch


## Longitud de la yema (hasta el vértice más lejano a lo largo de Y) y grosor hacia la palma
## de la última falange, medidos en la malla de piel del esqueleto. Vector2.ZERO si no hay.
func _measure(sk: Skeleton3D, bone: int) -> Vector2:
	var bone_name := sk.get_bone_name(bone)
	for child in sk.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.skin == null or not (mi.mesh is ArrayMesh):
			continue
		var key := mi.mesh.get_instance_id()
		if not _tip_cache.has(key):
			_tip_cache[key] = _scan_skin(mi.mesh as ArrayMesh, mi.skin)
		var table: Dictionary = _tip_cache[key]
		if table.has(bone_name):
			return table[bone_name]
	return Vector2.ZERO


## Una pasada por la malla: por hueso de dedo, (largo de yema, semigrosor). Un vértice cuenta para
## el hueso que más pesa en él.
static func _scan_skin(mesh: ArrayMesh, skin: Skin) -> Dictionary:
	var wanted := {}
	for k in skin.get_bind_count():
		var n := String(skin.get_bind_name(k))
		for f in FINGER_NAMES:
			if n.begins_with(f) and n.length() > f.length() and n[f.length()] in ["1", "2", "3", "."]:
				wanted[k] = n
	var out := {}
	if wanted.is_empty():
		return out
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if bones.is_empty() or verts.is_empty():
			continue
		var per := bones.size() / verts.size()
		for j in verts.size():
			var best := -1
			var bw := 0.0
			for q in per:
				if weights[j * per + q] > bw:
					bw = weights[j * per + q]
					best = bones[j * per + q]
			if bw < 0.5 or not wanted.has(best):
				continue
			var p: Vector3 = skin.get_bind_pose(best) * verts[j]
			var nm: String = wanted[best]
			var cur: Vector2 = out.get(nm, Vector2.ZERO)
			cur.x = maxf(cur.x, p.y)
			cur.y = maxf(cur.y, absf(p.x))
			out[nm] = cur
	return out


# --- Flexión -------------------------------------------------------------------------

## Pone la flexión `c` en las falanges del dedo (rotación absoluta desde el reposo).
func _apply(sk: Skeleton3D, ch: Chain, c: float, sgn: float, sw: float = 0.0) -> void:
	if ch.bones.is_empty():
		return
	for k in ch.bones.size():
		var a := c * ch.w[k] * sgn
		var q := Quaternion(Vector3(0, 0, 1), a) * ch.rest[k].basis.get_rotation_quaternion()
		if k == 0 and sw != 0.0:
			q = Quaternion(Vector3(1, 0, 0), -sgn * sw) * q
		sk.set_bone_pose_rotation(ch.bones[k], q.normalized())


## Oscilación de la flexión por temblor: solo abre (nunca cierra de más, así no atraviesa).
func _tremor(f: int) -> float:
	if tremor <= 0.0001:
		return 0.0
	var ph := 1.7 * float(f + 1)
	var s := 0.5 + 0.5 * (0.6 * sin(time * 38.0 + ph) + 0.4 * sin(time * 61.0 + ph * 1.9))
	return tremor * s


## Flexión objetivo de cada dedo (con el agarre, hasta tocar la pieza).
func _targets(sk: Skeleton3D, sk_xf: Transform3D) -> PackedFloat32Array:
	var out := curls.duplicate()
	for f in 5:
		_touch[f] = -1.0
	var gw := float(grasp.get("weight", 0.0))
	if grasp.is_empty():
		_swing = 0.0
		_swing_goal = 0.0
	elif _swing_goal == 0.0 and _swing == 0.0:
		_swing_goal = float(grasp.get("thumb_swing", 0.0))
	if grasp.is_empty() or gw <= 0.01:
		return out
	var sgn := _sign()
	# Pose de la mano recién fijada (fuera del árbol la pose global del esqueleto no se recalcula).
	var parent_xf := _global(sk, sk.get_bone_parent(_hand))
	var hand_world := sk_xf * parent_xf * Transform3D(Basis(sk.get_bone_pose_rotation(_hand)), sk.get_bone_pose_position(_hand))
	var inv := hand_world.affine_inverse()
	var p0: Vector3 = inv * (grasp.axis_point as Vector3)
	var u: Vector3 = (inv.basis * (grasp.axis_dir as Vector3)).normalized()
	var relax: float = grasp.get("relax", 0.7)
	var contact: PackedInt32Array = grasp.contact
	var dir_i := Vector3.ZERO
	# Primero los dedos largos (el índice marca de qué lado queda el pulgar), el pulgar al final.
	for f in [INDEX, MIDDLE, RING, PINKY, THUMB]:
		var ch: Chain = _chains[f]
		if ch == null:
			continue
		if not (f in contact):
			out[f] = maxf(curls[f], relax * (1.1 + 0.1 * f) if f != THUMB else 0.35)
			continue
		var ct := -1.0
		if f == THUMB:
			ct = _solve_thumb(ch, sgn, p0, u, dir_i)
		else:
			ct = _solve_touch(ch, sgn, p0, u, f)
			if f == INDEX and ct >= 0.0:
				var rel := ch.pad_point(ct, sgn) - p0
				dir_i = (rel - u * u.dot(rel)).normalized()
		if ct < 0.0:
			# No llega a la pieza: queda relajado, curvo, no en el aire con el dedo estirado.
			out[f] = maxf(curls[f], relax * 0.8) if f != THUMB else maxf(curls[f], 0.35)
			continue
		_touch[f] = ct
		out[f] = lerpf(curls[f], ct, gw)
	return out


## Distancia con signo de la yema (flexión `c`) a la superficie de revolución del agarre.
func _dist(ch: Chain, sgn: float, c: float, p0: Vector3, u: Vector3, sw: float = 0.0) -> float:
	var rel := ch.pad_point(c, sgn, sw) - p0
	var s := rel.dot(u)
	var rho := (rel - u * s).length()
	var prof: PackedFloat32Array = grasp.profile
	var step: float = grasp.step
	if s < 0.0:
		return rho - prof[0]
	var fi := s / step
	var i := int(fi)
	if i >= prof.size() - 1:
		return rho  # por encima de la pieza: no hay superficie
	return rho - lerpf(prof[i], prof[i + 1], fi - float(i))


## Pulgar: busca la abducción (y la flexión que toca) con la que su yema queda frente a la del
## índice (producto de direcciones < -0.5). Parte de la del fotograma anterior.
func _solve_thumb(ch: Chain, sgn: float, p0: Vector3, u: Vector3, dir_i: Vector3) -> float:
	var best_c := -1.0
	var best_sw := _swing
	var best_score := 2.0
	for k in [0.0, 0.12, -0.12, 0.24, -0.24, 0.36]:
		var sw := clampf(_swing_goal + float(k), 0.0, 1.0)
		var c := _solve_touch(ch, sgn, p0, u, THUMB, sw)
		if c < 0.0:
			continue
		var score := -1.0
		if dir_i != Vector3.ZERO:
			var rel := ch.pad_point(c, sgn, sw) - p0
			score = (rel - u * u.dot(rel)).normalized().dot(dir_i)
		if score < best_score:
			best_score = score
			best_c = c
			best_sw = sw
		if score < -0.5:
			break
	_swing_goal = best_sw
	_swing = move_toward(_swing, best_sw, 4.0 * maxf(dt, 0.016))
	# Si con el pulgar abierto (c = 0) la yema ya queda dentro de la pieza, la flexión no puede
	# sacarla: la abducción avanza más rápido que el tope hasta que quede fuera (no atraviesa).
	if best_c >= 0.0:
		var guard := 0
		while _swing != best_sw and guard < 64 and _dist(ch, sgn, 0.0, p0, u, _swing) < -CONTACT_EPS:
			_swing = move_toward(_swing, best_sw, 0.01)
			guard += 1
	if best_c >= 0.0 and absf(_swing - best_sw) > 0.01:
		# Mientras la abducción llega a su valor, la flexión se recalcula con la actual.
		var c2 := _solve_touch(ch, sgn, p0, u, THUMB, _swing)
		if c2 >= 0.0:
			return c2
	return best_c


## Menor flexión con que la yema toca la superficie, o -1 si no llega.
func _solve_touch(ch: Chain, sgn: float, p0: Vector3, u: Vector3, f: int, sw: float = 0.0) -> float:
	var c := clampf(_c_prev[f], 0.0, C_MAX)
	var d := _dist(ch, sgn, c, p0, u, sw)
	var lo := 0.0
	var hi := -1.0
	if d > CONTACT_EPS:
		# Fuera: se cierra hasta cruzar la superficie.
		lo = c
		var x := c
		while x < C_MAX:
			x = minf(x + C_STEP, C_MAX)
			if _dist(ch, sgn, x, p0, u, sw) <= CONTACT_EPS:
				hi = x
				break
			lo = x
		if hi < 0.0:
			return -1.0
	else:
		# Dentro: se abre hasta salir.
		hi = c
		var x2 := c
		lo = -1.0
		while x2 > 0.0:
			x2 = maxf(x2 - C_STEP, 0.0)
			if _dist(ch, sgn, x2, p0, u, sw) > CONTACT_EPS:
				lo = x2
				break
			hi = x2
		if lo < 0.0:
			_c_prev[f] = 0.0
			return 0.0
	for i in BISECT_STEPS:
		var mid := 0.5 * (lo + hi)
		if _dist(ch, sgn, mid, p0, u, sw) > CONTACT_EPS:
			lo = mid
		else:
			hi = mid
	_c_prev[f] = hi
	return hi


# --- Consultas para el dueño (HandRig) y las pruebas ---------------------------------

## Crea las cadenas si hace falta y dice si la mano tiene esqueleto utilizable.
func ready_for_queries() -> bool:
	var sk := _skeleton()
	return sk != null and _ensure_chains(sk)


func chain(f: int) -> Chain:
	if not ready_for_queries():
		return null
	return _chains[f]


## Plan de la pinza pulgar-índice sobre un eje vertical (el de la pieza) de radio `radius`, con la
## mano inclinada `pitch` rad (dedos hacia abajo) y girada `roll` rad sobre los dedos (0 = palma
## abajo; 90° = palma de lado, pulgar arriba; el signo ya se ajusta al lado). Busca las flexiones de
## pulgar e índice cuyas yemas quedan a ambos lados del eje (separación horizontal ≈ 2·radius) y
## devuelve `{a, ct, ci}`: el punto del eje en el espacio de la mano (donde van la pieza y la
## pinza), y las flexiones del pulgar y el índice. `lateral` (0..1) desplaza el eje del carril del
## índice hacia el del medio (corona: la mano rodea con dos dedos). Se deriva de la geometría real
## de los dedos y se guarda por parámetros. Con `axis` (unitario, en el espacio de la mano; la
## pluma) el eje es ese en vez del vertical y `pitch`/`roll` no se usan.
func pinch_plan(radius: float, pitch: float, roll: float = 0.0, lateral: float = 0.0, axis: Vector3 = Vector3.ZERO) -> Dictionary:
	var key := "%s_%d_%d_%d_%d_%d_%d_%d" % [side, roundi(radius * 10000.0), roundi(pitch * 100.0), roundi(roll * 100.0), roundi(lateral * 10.0),
			roundi(axis.x * 1000.0), roundi(axis.y * 1000.0), roundi(axis.z * 1000.0)]
	if _plans.has(key):
		return _plans[key]
	var th := chain(THUMB)
	var ix := chain(INDEX)
	var sgn := _sign()
	var plan := {"a": Vector3(-sgn * 0.045, 0.09, 0.034), "ct": 0.25, "ci": PINCH_C, "sw": 0.0}
	if th == null or ix == null:
		return plan
	# Eje vertical en el espacio de la mano para esa inclinación y giro (la yaw no importa).
	var u := HandRig.basis_for(Vector3(0, 0, 1), pitch, roll * sgn, sgn).transposed() * Vector3.UP
	if axis != Vector3.ZERO:
		u = axis.normalized()
	var best := 1e18
	var ci := 0.3
	var a := Vector3.ZERO
	while ci <= 1.1:
		# El índice toca de frente: el eje queda a un radio de su yema, hacia donde mira la yema.
		var fr := ix.last_frame(ci, sgn)
		var ip := fr * ix.contact_local
		var n := fr.basis * Vector3(-sgn, 0, 0)
		n = n - u * n.dot(u)
		if n.length() > 0.001:
			n = n.normalized()
			var ax := ip + n * radius
			var ct := 0.0
			while ct <= 0.7:
				var sw := 0.0
				while sw <= 0.9:
					var tp := th.pad_point(ct, sgn, sw)
					# La yema del pulgar debe quedar al otro lado del eje (frente a la del índice) y fuera.
					var rel := tp - (ax * 2.0 - ip)
					var up := u.dot(rel)
					var hz := (rel - u * up).length()
					var rr := tp - ax
					var dd := (rr - u * u.dot(rr)).length()
					var cost := pow(hz * 1000.0, 2.0) + pow(up * 1000.0 * 0.5, 2.0) \
							+ 4.0 * pow(ct - 0.25, 2.0) + 2.0 * pow(ci - 0.6, 2.0) + 30.0 * sw * sw
					if dd < radius - 0.0005:
						cost += 1e4  # dentro de la pieza
					if cost < best:
						best = cost
						a = ax
						plan = {"ct": ct, "ci": ci, "sw": sw}
					sw += 0.15
				ct += 0.1
		ci += 0.06
	var mid := chain(MIDDLE)
	if mid != null and lateral > 0.0:
		a.z += lateral * (mid.pad_point(float(plan.ci), sgn).z - ix.pad_point(float(plan.ci), sgn).z)
	plan["a"] = a
	plan["cost"] = best
	_plans[key] = plan
	return plan


## Punto de la yema (pulsar un botón con el dedo extendido) del dedo `finger` con flexión `c`.
func fingertip_point(finger: int, c: float) -> Vector3:
	var ch := chain(finger)
	if ch == null:
		return Vector3(0.0, 0.17, 0.0)
	return ch.tip_point(c, _sign())


## Flexión que cada dedo tiene ahora (para pruebas).
func flex_now(f: int) -> float:
	return _c_out[f]


func is_legacy() -> bool:
	return _legacy
