class_name TorsoLeanModifier
extends SkeletonModifier3D
## Inclina el tronco hacia adelante (rotación sobre el eje lateral del esqueleto) repartida
## entre la pelvis (Hips), Spine y Chest, y compensa con Neck y Head para que la cabeza siga mirando al frente.
## Sirve para alcanzar casillas lejanas (el IK del brazo solo llega a ~0,55 m del hombro) y
## para los espasmos de tos. Va ANTES de la mirada y del IK en el orden de modificadores.

## Reparto del ángulo total (los negativos de cuello y cabeza compensan).
## La pelvis aporta la parte que se inclina "desde la cadera" (el torso entero pivota sobre el
## asiento); los muslos se contrarrotan para que las piernas no se muevan. Spine y Chest suman
## el resto, de modo que la espalda se curva poco.
const SHARES := {"Hips": 0.6, "Spine": 0.2, "Chest": 0.2, "Neck": -0.27, "Head": -0.27}
## Huesos que se contrarrotan con la pelvis (conservan su orientación global).
const COUNTER_BONES := ["Thigh.L", "Thigh.R"]

## Inclinación en radianes; positivo = hacia adelante (+Z del modelo).
var lean: float = 0.0
## Giro del tronco sobre la vertical en radianes; positivo = hacia la izquierda de la figura.
var twist: float = 0.0
## Reparto del giro entre Spine y Chest.
const TWIST_SHARES := {"Spine": 0.4, "Chest": 0.6}


func _process_modification() -> void:
	if absf(lean) < 0.0005 and absf(twist) < 0.0005:
		return
	var sk := get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	if sk == null:
		return
	# Orientación global previa de los muslos: la pelvis los arrastraría y se restituyen después.
	var keep := {}
	for cb in COUNTER_BONES:
		var ci := sk.find_bone(cb)
		if ci >= 0:
			keep[ci] = sk.get_bone_global_pose(ci).basis
	for bone_name in SHARES:
		var idx := sk.find_bone(bone_name)
		if idx < 0:
			continue
		var gp := sk.get_bone_global_pose(idx)
		var parent := sk.get_bone_parent(idx)
		var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var rot := Basis(Vector3.UP, twist * float(TWIST_SHARES.get(bone_name, 0.0))) * Basis(Vector3.RIGHT, lean * float(SHARES[bone_name]))
		var local := pb.inverse() * rot * gp.basis
		sk.set_bone_pose_rotation(idx, local.orthonormalized().get_rotation_quaternion())
	for ci in keep:
		var par := sk.get_bone_parent(ci)
		var pbasis := sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(ci, (pbasis.inverse() * (keep[ci] as Basis)).orthonormalized().get_rotation_quaternion())
