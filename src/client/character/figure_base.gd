class_name FigureBase
extends Node3D
## Base común de `CharacterFigure` y `ArbiterFigure`: envuelve un `.glb` de personaje
## (Skeleton3D de 23 huesos + AnimationPlayer) y ofrece animación con mezcla suave,
## mirada aditiva, recoloreado por material y acceso a huesos.
##
## Convención: la figura mira a +Z; el origen está en el suelo bajo el centro del asiento.
## Las subclases solo dicen qué `.glb` cargan (`_model_path`) y qué animaciones son cíclicas
## (`_loops`); el modelo se construye en `_init`, así que `skeleton()` ya sirve antes de
## entrar al árbol.

## Termina una animación NO cíclica (`play_once`); no se emite en las cíclicas.
signal anim_finished(anim: StringName)
## Interno: cambió la animación actual o terminó (despierta a `play_once`).
signal _state_changed

## Rapidez (1/s) con que la mirada alcanza su objetivo; más alto = más brusco.
@export var look_speed: float = 9.0

const MAX_YAW := deg_to_rad(80.0)
const MAX_PITCH := deg_to_rad(35.0)
## Hueso -> nombre del material que lleva `setup`.
const LOOK_MATERIALS := {
	"skin": "Skin", "shirt": "Shirt", "jacket": "Jacket",
	"pants": "Pants", "shoes": "Shoes", "hair": "Hair", "eyes": "Eyes",
}
## Posición aproximada entre los ojos / centro de la cabeza respecto al origen del hueso
## Head en reposo, en ejes del esqueleto (el modelo mira a +Z).
const EYE_REST_OFFSET := Vector3(0.0, 0.19, 0.10)
const HEAD_CENTER_REST_OFFSET := Vector3(0.0, 0.11, 0.0)

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _look_mod: FigureLookModifier
var _current: StringName = &""
var _finished: bool = false
var _has_pose: bool = false
## Instante (ms) en que termina la mezcla de la última `play`.
var _blend_end_ms: int = 0
var _look_target := Vector2.ZERO  # x = yaw, y = pitch
var _look_now := Vector2.ZERO
var _attachments: Dictionary = {}
var _materials: Dictionary = {}  # nombre de material -> Array[StandardMaterial3D] propios
var _pose_cache: Array[Transform3D] = []  # poses globales YA modificadas (mirada, IK)
var _eye_local := Vector3.ZERO
var _head_local := Vector3.ZERO


## Ruta del `.glb` del personaje (la define la subclase).
func _model_path() -> String:
	return ""


## Animaciones cíclicas del modelo (la define la subclase).
func _loops() -> Array:
	return []


func _init() -> void:
	var scene := load(_model_path()) as PackedScene
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	_player = _find(_model, "AnimationPlayer") as AnimationPlayer
	# La animación se evalúa antes que los modificadores del esqueleto.
	_player.process_priority = -10
	_mark_loops()
	_own_materials(_model)
	_look_mod = FigureLookModifier.new()
	_look_mod.name = "Mirada"
	_skeleton.add_child(_look_mod)
	_player.animation_finished.connect(_on_animation_finished)
	_skeleton.skeleton_updated.connect(_cache_poses)
	var head := _skeleton.find_bone("Head")
	var inv := _skeleton.get_bone_global_rest(head).basis.inverse()
	_eye_local = inv * EYE_REST_OFFSET
	_head_local = inv * HEAD_CENTER_REST_OFFSET
	_show_only_hair("short")


## Tras animación y modificadores el esqueleto devuelve las poses sin modificar; se
## guardan aquí las finales para que `bone_global` y los ojos reflejen mirada e IK.
func _cache_poses() -> void:
	var n := _skeleton.get_bone_count()
	_pose_cache.resize(n)
	for i in n:
		_pose_cache[i] = _skeleton.get_bone_global_pose(i)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-look_speed * delta)
	_look_now = _look_now.lerp(_look_target, k)
	_look_mod.yaw = _look_now.x
	_look_mod.pitch = _look_now.y


# --- Aspecto ----------------------------------------------------------------------

## Aplica un aspecto. Claves opcionales: `skin`, `shirt`, `jacket`, `pants`, `shoes`,
## `hair`, `eyes` (Color) y `hair_style` ("short", "long", "bald"). Los materiales son propios de
## esta instancia: no tiñe a las demás.
func setup(look: Dictionary) -> void:
	for key in LOOK_MATERIALS:
		if not look.has(key):
			continue
		for mat in _materials.get(LOOK_MATERIALS[key], []):
			(mat as StandardMaterial3D).albedo_color = look[key]
	if look.has("hair_style"):
		_show_only_hair(String(look["hair_style"]))


## Deja visible solo un peinado: "short", "long" o "bald".
func _show_only_hair(style: String) -> void:
	var wanted := "Hair_" + style.capitalize()
	for n in ["Hair_Short", "Hair_Long", "Hair_Bald"]:
		var node := _find_named(_model, n) as Node3D
		if node != null:
			node.visible = (n == wanted)


## Duplica los materiales de cada malla para poder teñirlos sin afectar otras instancias.
func _own_materials(root: Node) -> void:
	var copies := {}  # material original -> copia (misma copia en todas las superficies)
	for mi in _all(root, "MeshInstance3D"):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var orig := mesh.surface_get_material(s)
			if orig == null:
				continue
			if not copies.has(orig):
				var c := orig.duplicate() as Material
				copies[orig] = c
				if c is StandardMaterial3D:
					var arr: Array = _materials.get(c.resource_name, [])
					arr.append(c)
					_materials[c.resource_name] = arr
			(mi as MeshInstance3D).set_surface_override_material(s, copies[orig])


# --- Animación --------------------------------------------------------------------

## Marca como cíclicas las animaciones de `_loops()` (los .glb no traen el flag).
func _mark_loops() -> void:
	for a in _loops():
		if _player.has_animation(a):
			_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR


## Lista de animaciones del modelo.
func animations() -> PackedStringArray:
	return _player.get_animation_list()


func has_animation(anim: StringName) -> bool:
	return _player.has_animation(anim)


## Reproduce `anim` mezclándola con la actual durante `blend` segundos. Si ya es la
## actual y sigue sonando, solo cambia la velocidad. `speed` multiplica el ritmo.
func play(anim: StringName, blend: float = 0.25, speed: float = 1.0) -> void:
	if not _player.has_animation(anim):
		push_warning("%s: no existe la animación '%s'" % [get_class(), anim])
		return
	if anim == _current and _player.is_playing():
		_player.speed_scale = speed
		return
	_current = anim
	_finished = false
	var pose_held := not _player.is_playing() and _has_pose
	if pose_held and blend > 0.0:
		# La animación anterior terminó y su pose sigue sostenida: se vuelve a poner en pausa en
		# su último fotograma y se mezcla desde ella (`play_with_capture` salta de golpe).
		var held := _player.assigned_animation
		if held != &"" and _player.has_animation(held):
			_player.play(held, 0.0, 0.0)
			_player.seek(_player.get_animation(held).length, true)
			_player.pause()
		_player.play(anim, blend)
	else:
		_player.play(anim, blend if _has_pose else 0.0)
	_player.speed_scale = speed
	_has_pose = true
	_blend_end_ms = Time.get_ticks_msec() + int(blend * 1000.0 / maxf(speed, 0.05))
	_state_changed.emit()


## Reproduce `anim` una vez y espera a que termine (corrutina: `await fig.play_once(...)`).
## La pose final queda sostenida (no vuelve a idle). Si otra animación la interrumpe,
## la espera termina igual. Las animaciones cíclicas no terminan: se rechazan.
func play_once(anim: StringName, blend: float = 0.5) -> void:
	if not _player.has_animation(anim):
		push_warning("%s: no existe la animación '%s'" % [get_class(), anim])
		return
	if _player.get_animation(anim).loop_mode != Animation.LOOP_NONE:
		push_warning("%s: '%s' es cíclica; play_once no terminaría" % [get_class(), anim])
		return
	_current = &""  # fuerza reinicio aunque ya fuera la actual
	play(anim, blend, 1.0)
	while _current == anim and not _finished:
		await _state_changed


## True mientras dura la mezcla de la última `play` (para no apilar un cambio de pose sobre otro).
func is_blending() -> bool:
	return Time.get_ticks_msec() < _blend_end_ms


## Animación actual (la última pedida; sigue siendo la actual con la pose sostenida
## tras terminar una `play_once`). Vacío si nunca se reprodujo nada.
func current() -> StringName:
	return _current


## True si la animación actual ya terminó y su pose está sostenida.
func is_finished() -> bool:
	return _finished


## El AnimationPlayer del modelo (para pruebas o ajustes finos).
func animation_player() -> AnimationPlayer:
	return _player


func _on_animation_finished(anim: StringName) -> void:
	if anim != _current:
		return
	_finished = true
	anim_finished.emit(anim)
	_state_changed.emit()


# --- Mirada -----------------------------------------------------------------------

## Orienta cuello y cabeza (y algo el pecho si el giro es grande) encima de la animación.
## `yaw` y `pitch` en radianes, relativos al frente del cuerpo: yaw positivo = hacia la
## IZQUIERDA de la figura, pitch positivo = hacia ARRIBA. Se limitan a ±80° y ±35°.
## La mirada llega suavizada (`look_speed`); con `instant` salta de golpe.
func set_look(yaw: float, pitch: float, instant: bool = false) -> void:
	_look_target = Vector2(clampf(yaw, -MAX_YAW, MAX_YAW), clampf(pitch, -MAX_PITCH, MAX_PITCH))
	if instant:
		_look_now = _look_target
		_look_mod.yaw = _look_now.x
		_look_mod.pitch = _look_now.y


## Mirada actual (ya suavizada) como Vector2(yaw, pitch).
func look_now() -> Vector2:
	return _look_now


## Mira hacia un punto del mundo (conveniencia sobre `set_look`).
func look_at_point(world_pos: Vector3, instant: bool = false) -> void:
	var local := global_transform.affine_inverse() * world_pos
	var origin := _skeleton.get_bone_global_pose(_skeleton.find_bone("Head")).origin
	var d := local - origin
	set_look(atan2(d.x, d.z), atan2(d.y, Vector2(d.x, d.z).length()), instant)


# --- Acceso al esqueleto ------------------------------------------------------------

func skeleton() -> Skeleton3D:
	return _skeleton


## Transformación global del hueso (por nombre, p. ej. &"Hand.R").
func bone_global(bone: StringName) -> Transform3D:
	var idx := _skeleton.find_bone(bone)
	if idx < 0:
		push_warning("No existe el hueso '%s'" % bone)
		return global_transform
	var pose := _pose_cache[idx] if idx < _pose_cache.size() else _skeleton.get_bone_global_pose(idx)
	var base := _skeleton.global_transform if _skeleton.is_inside_tree() else Transform3D.IDENTITY
	return base * pose


## Centro aproximado de la cabeza en el mundo.
func head_global_position() -> Vector3:
	return _unscaled(bone_global(&"Head")) * _head_local


## Punto entre los ojos en el mundo (sigue a la cabeza, incluida la mirada).
func eye_global_position() -> Vector3:
	return _unscaled(bone_global(&"Head")) * _eye_local


## Cuelga `node` de un hueso (BoneAttachment3D propio, reusado para el mismo hueso).
func attach(node: Node3D, bone: StringName) -> BoneAttachment3D:
	var att := _attachments.get(bone) as BoneAttachment3D
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "Adjunto_" + String(bone).replace(".", "_")
		att.bone_name = bone
		_skeleton.add_child(att)
		_attachments[bone] = att
	if node.get_parent() != att:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		att.add_child(node)
	return att


## Quita la escala (la cabeza escondida en primera persona vale ~0).
func _unscaled(t: Transform3D) -> Transform3D:
	return Transform3D(t.basis.orthonormalized(), t.origin)


## Oculta (o muestra) cabeza y pelo para el cuerpo propio en primera persona. Escala el
## hueso Head a ~0 DESPUÉS de la animación (en el modificador), así la malla de cabeza y
## de pelo, que van enlazadas a ese hueso, desaparecen sin tocar materiales. La posición
## de `head_global_position()` y `eye_global_position()` no cambia: la cámara puede
## seguir saliendo de ahí. (Alternativa: capas de render, pero esto vale en Compatibility.)
func set_hidden_for_first_person(on: bool) -> void:
	_look_mod.hide_head = on


# --- Utilidades -------------------------------------------------------------------

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c, cls))
	return out


func _find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null:
			return r
	return null
