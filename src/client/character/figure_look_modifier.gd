class_name FigureLookModifier
extends SkeletonModifier3D
## Mirada aditiva: gira Chest/Neck/Head ENCIMA de la pose que dejó la animación.
## Lo crea `FigureBase`; no hace falta usarlo directamente.
##
## Los ángulos son relativos al cuerpo (ejes del esqueleto, no de la pose animada):
## `yaw` positivo mira hacia la IZQUIERDA de la figura (+X del modelo, que mira a +Z),
## `pitch` positivo mira hacia ARRIBA. El giro se reparte: cuello y cabeza siempre,
## y el pecho solo ayuda cuando el giro pasa de `CHEST_START`.
## También sabe "esconder" la cabeza (escala casi cero del hueso Head) para el cuerpo
## propio en primera persona; se hace aquí porque la animación pisa la pose cada cuadro.

## A partir de este yaw el pecho acompaña (radianes).
const CHEST_START := deg_to_rad(28.0)
## Fracción del exceso sobre `CHEST_START` que absorbe el pecho.
const CHEST_SHARE := 0.4
const NECK_SHARE := 0.4
const HEAD_SHARE := 0.6
## Al mirar hacia abajo la cabeza se inclina solo esta fraccion del pitch pedido: el rival mira el
## tablero (~-35 grados) y con el pitch completo la barbilla cae sobre el pecho y la cabeza queda
## pegada a la mesa. La direccion de la mirada la decide el servidor, esto es solo el dibujo.
const DOWN_SCALE := 0.75

var yaw: float = 0.0
var pitch: float = 0.0
var hide_head: bool = false
var _head_hidden: bool = false


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		sk = get_parent() as Skeleton3D  # fuera del árbol (pruebas)
	if sk == null:
		return
	var chest := sk.find_bone("Chest")
	var neck := sk.find_bone("Neck")
	var head := sk.find_bone("Head")
	if chest < 0 or neck < 0 or head < 0:
		return
	if absf(yaw) > 0.0005 or absf(pitch) > 0.0005:
		var extra := signf(yaw) * maxf(absf(yaw) - CHEST_START, 0.0) * CHEST_SHARE
		var rest := yaw - extra
		var pit := pitch * (DOWN_SCALE if pitch < 0.0 else 1.0)
		_rotate(sk, chest, extra, 0.0)
		_rotate(sk, neck, rest * NECK_SHARE, pit * NECK_SHARE)
		_rotate(sk, head, rest * HEAD_SHARE, pit * HEAD_SHARE)
	if hide_head:
		sk.set_bone_pose_scale(head, Vector3.ONE * 0.001)
		_head_hidden = true
	elif _head_hidden:
		# Las animaciones no traen pistas de escala: hay que devolverla a mano.
		sk.set_bone_pose_scale(head, Vector3.ONE)
		_head_hidden = false


## Gira el hueso `y` (eje vertical) y `p` (eje lateral, arriba positivo) en espacio del
## esqueleto, dejando fijo su origen.
func _rotate(sk: Skeleton3D, bone: int, y: float, p: float) -> void:
	var gp := sk.get_bone_global_pose(bone)
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var rot := Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, -p)
	var local := pb.inverse() * rot * gp.basis
	sk.set_bone_pose_rotation(bone, local.orthonormalized().get_rotation_quaternion())
