class_name ArmPoseModifier
extends SkeletonModifier3D
## Va DESPUÉS del IK del brazo: el IK solo coloca la muñeca, así que aquí se orienta la mano
## (dedos y palma hacia donde se pide) y se cierran los dedos y el pulgar para pinzar.
##
## Ejes del hueso `Hand.*` (medidos con la figura sentada): +Y hacia los dedos, el eje
## transversal es Z local y la normal de la palma es -X local en la mano derecha y +X en la
## izquierda. Los dedos se doblan hacia la palma girando sobre Z de la mano.

var side: StringName = &"R"
## Orientación deseada de la mano en el MUNDO (Y = hacia los dedos).
var hand_basis: Basis = Basis.IDENTITY
## Si es false el modificador no toca nada (la mano sigue a la animación).
var controlled: bool = false
## Cierre de los dedos y del pulgar en radianes (0 = abierta).
var finger_curl: float = 0.0
var thumb_curl: float = 0.0


func _process_modification() -> void:
	if not controlled:
		return
	var sk := get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D
	if sk == null:
		return
	var hand := sk.find_bone("Hand." + side)
	if hand < 0:
		return
	var parent := sk.get_bone_parent(hand)
	var pb := sk.get_bone_global_pose(parent).basis
	var sk_basis := sk.global_transform.basis if sk.is_inside_tree() else Basis.IDENTITY
	var want := sk_basis.orthonormalized().inverse() * hand_basis
	sk.set_bone_pose_rotation(hand, (pb.inverse() * want).orthonormalized().get_rotation_quaternion())
	# Sentido del cierre: hacia la normal de la palma (-X local en R, +X en L).
	var sgn := 1.0 if side == &"R" else -1.0
	_curl(sk, "Fingers." + side, finger_curl * sgn)
	_curl(sk, "Thumb." + side, thumb_curl * sgn)


func _curl(sk: Skeleton3D, bone_name: String, angle: float) -> void:
	var idx := sk.find_bone(bone_name)
	if idx < 0 or absf(angle) < 0.0005:
		return
	var cur := sk.get_bone_pose_rotation(idx)
	var rot := Quaternion(Vector3(0, 0, 1), angle)
	sk.set_bone_pose_rotation(idx, rot * cur)
