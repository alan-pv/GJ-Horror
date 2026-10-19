class_name SeatedFigure
extends CharacterFigure
## `CharacterFigure` sentada con los añadidos del cliente de la mesa principal: inclinación del
## tronco (`set_lean`) y control de la orientación y los dedos de la mano que mueve el IK
## (`arm_pose_modifier`). Orden de los modificadores: inclinación, mirada, IK, mano.

## Rapidez (1/s) con que el tronco alcanza la inclinación pedida.
@export var lean_speed: float = 7.0

var _lean_mod: TorsoLeanModifier
var _pose_mods: Dictionary = {}  # lado -> ArmPoseModifier
var _lean_now: float = 0.0
var _lean_target: float = 0.0
var _lean_extra: float = 0.0
var _twist_now: float = 0.0
var _twist_target: float = 0.0
var _shift_now: float = 0.0
var _shift_target: float = 0.0


func _init() -> void:
	super()
	_lean_mod = TorsoLeanModifier.new()
	_lean_mod.name = "Inclinacion"
	_skeleton.add_child(_lean_mod)
	_skeleton.move_child(_lean_mod, 0)


func _process(delta: float) -> void:
	super._process(delta)
	_lean_now = lerpf(_lean_now, _lean_target, 1.0 - exp(-lean_speed * delta))
	_lean_mod.lean = _lean_now + _lean_extra
	_shift_now = lerpf(_shift_now, _shift_target, 1.0 - exp(-lean_speed * delta))
	_model.position.z = _shift_now
	_twist_now = lerpf(_twist_now, _twist_target, 1.0 - exp(-lean_speed * delta))
	_lean_mod.twist = _twist_now


## Inclinación del tronco hacia adelante en radianes (suavizada); con `instant` salta.
func set_lean(radians: float, instant: bool = false) -> void:
	_lean_target = radians
	if instant:
		_lean_now = radians
		_lean_mod.lean = radians + _lean_extra


## Inclinación adicional instantánea (espasmos de tos, tirar una pieza), se suma a `set_lean`.
func set_lean_extra(radians: float) -> void:
	_lean_extra = radians


## Desplaza todo el cuerpo hacia adelante (m, en ejes de la figura): se acerca a la mesa
## para llegar a casillas lejanas. Se suaviza igual que la inclinación.
func set_shift(meters: float) -> void:
	_shift_target = meters


## Giro del tronco sobre la vertical (rad, positivo = a su izquierda), suavizado.
func set_twist(radians: float) -> void:
	_twist_target = radians


func twist_now() -> float:
	return _twist_now


func shift_now() -> float:
	return _shift_now


func lean_now() -> float:
	return _lean_now


## Modificador de la mano del lado `side` (se crea tras el IK de ese brazo).
func arm_pose_modifier(side: StringName) -> ArmPoseModifier:
	if _pose_mods.has(side):
		return _pose_mods[side]
	enable_arm_ik(side, false)  # asegura que el IK ya exista y quede antes de este modificador
	var mod := ArmPoseModifier.new()
	mod.name = "PoseMano_" + side
	mod.side = side
	_skeleton.add_child(mod)
	_pose_mods[side] = mod
	return mod
