class_name ArbiterFigure
extends FigureBase
## Figura del árbitro (`arbiter.glb`): alto, con máscara y un revólver en la mano
## derecha (Empty `Muzzle`). Misma API de animación y mirada que `CharacterFigure`.
## Mira a +Z; el origen está en el suelo, bajo los pies (de pie).

const MODEL_PATH := "res://assets/models/characters/arbiter.glb"
## Animaciones cíclicas.
const LOOPS: Array[StringName] = [&"idle", &"walk", &"aim_hold"]
## Velocidad (m/s) a la que avanza la animación `walk` con velocidad 1 (paso 0,483 m).
const WALK_SPEED := 0.744

var _walk_factor: float = 1.0
var _speed: float = 1.0


func _model_path() -> String:
	return MODEL_PATH


## El exportador de glTF de Blender coloca los hijos de hueso respecto a la cola del hueso, pero
## Godot los cuelga de la cabeza: sin corrección la pistola queda 9 cm (el largo de `Hand.R`)
## hacia el antebrazo y la mano asoma por debajo. En el modelo la empuñadura ya está modelada
## respecto a la cabeza del hueso, así que se anula ese desplazamiento.
func _init() -> void:
	super()
	var gun := _find_named(_model, "Pistol") as Node3D
	if gun != null:
		gun.position = Vector3.ZERO


func _loops() -> Array:
	return LOOPS


## Ajusta el ritmo de `walk` para que los pies no patinen al moverse a `mps` m/s.
## Vale también si ya está caminando.
func set_walk_speed(mps: float) -> void:
	_walk_factor = maxf(mps, 0.0) / WALK_SPEED
	if _current == &"walk":
		_player.speed_scale = _speed * _walk_factor


func play(anim: StringName, blend: float = 0.25, speed: float = 1.0) -> void:
	_speed = speed
	super.play(anim, blend, speed)
	if anim == &"walk":
		_player.speed_scale = speed * _walk_factor


## Punta del cañón (Empty `Muzzle`, -Z local = dirección de disparo).
func muzzle() -> Node3D:
	return _find_named(_model, "Muzzle") as Node3D


func pistol() -> Node3D:
	return _find_named(_model, "Pistol") as Node3D


## Muestra u oculta la pistola.
func set_gun_visible(on: bool) -> void:
	pistol().visible = on
