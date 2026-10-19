class_name TorsoLeanModifier
extends SkeletonModifier3D
## Inclina el tronco hacia adelante (rotación sobre el eje lateral del esqueleto) repartida
## entre Spine y Chest, y compensa con Neck y Head para que la cabeza siga mirando al frente.
## Sirve para alcanzar casillas lejanas (el IK del brazo solo llega a ~0,55 m del hombro) y
## para los espasmos de tos. Va ANTES de la mirada y del IK en el orden de modificadores.

## Reparto del ángulo total (los negativos de cuello y cabeza compensan).
const SHARES := {"Spine": 0.5, "Chest": 0.5, "Neck": -0.45, "Head": -0.45}

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
