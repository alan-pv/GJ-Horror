class_name OpponentAvatar
extends Node3D
## El rival: una `SeatedFigure` (modelo de Blender) sentada en su silla, mirando a +Z hacia el
## jugador. La cabeza sigue la mirada del bot (`BotController.looked`: la misma cámara virtual
## con la que el servidor decide si mira el tablero), que es lo que el jugador debe leer. En
## reposo alterna animaciones (`sit_idle`, `sit_think`, `sit_nervous`); los eventos (toser,
## tirar una pieza) se resuelven con el tronco y la cabeza. Es dueño de la mano (`HandRig`)
## del rival, que usa el brazo izquierdo: así queda del mismo lado que el reloj y que su pila
## de capturas.
##
## El nodo se coloca en el suelo bajo el asiento; la figura mira a +Z sin girar.

## Ojos de la figura sentada, en el espacio local del nodo (medido con `sit_idle`).
const EYE_LOCAL := Vector3(0.0, 1.146, 0.27)
## Animaciones de reposo y rango (s) entre cambios.
const IDLE_ANIMS: Array[StringName] = [&"sit_idle", &"sit_think", &"sit_nervous"]
const IDLE_CHANGE := Vector2(5.0, 12.0)
## Mezcla (s) entre poses de reposo: lenta, para que no se note el cambio.
const IDLE_BLEND := 0.8

var figure: SeatedFigure
## Marcador pegado al hueso de la cabeza (posición de la cabeza para efectos y sonidos).
var head: Node3D
var hand_rig: HandRig
## La otra mano (derecha): descansa sobre la mesa y es la que escribe en la planilla (`HandAnimator.write_rig`).
var idle_rig: HandRig
var bot: BotController

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Sacudida de eventos (toser, tirar una pieza): cabeza (cabeceo, rad) y torso (inclinación, rad).
var _head_kick: float = 0.0
var _body_kick: float = 0.0
var _event_tween: Tween
var _idle_timer: float = 3.0
var _rng := RandomNumberGenerator.new()
## Condenado: ninguna animación ambiental, mirada ni evento lo mueve; el cadáver es del árbitro.
var condemned: bool = false


## Posición global de los ojos (la usa el bot como cámara virtual). No sigue la animación:
## es siempre la de la figura sentada derecha, para que la mirada sea estable.
func eye_position() -> Vector3:
	return global_transform * EYE_LOCAL


## Crea la figura y el brazo. `look` es el aspecto (ver `CharacterFigure.random_look`); el rival es
## un bot, así que conserva solo su ropa: piel gris y sin rasgos (`CharacterFigure.bot_look`).
## `arm_side`: `&"L"` = brazo izquierdo de la figura (el del lado del reloj).
func build(look: Dictionary, arm_side: StringName = &"L") -> void:
	name = "Rival"
	_rng.randomize()
	figure = SeatedFigure.new()
	figure.name = "Figura"
	add_child(figure)
	figure.setup(CharacterFigure.bot_look(_rng, look))
	figure.play(&"sit_idle", 0.0)
	head = Marker3D.new()
	head.name = "Cabeza"
	figure.attach(head, &"Head")
	hand_rig = HandRig.new()
	hand_rig.name = "ManoRival"
	add_child(hand_rig)
	hand_rig.setup(figure, arm_side)
	idle_rig = HandRig.new()
	idle_rig.name = "ManoLibreRival"
	add_child(idle_rig)
	idle_rig.setup(figure, &"R" if arm_side == &"L" else &"L")
	idle_rig.rest_at(Vector3(-0.34, BoardView.TABLE_TOP + 0.03, -0.40), 20.0)


func bind_bot(p_bot: BotController) -> void:
	bot = p_bot
	bot.looked.connect(_on_looked)
	_on_looked(bot.look_yaw, bot.look_pitch)


## El bot mira con la convención de la cámara (yaw 0 = hacia -Z del mundo); la figura mira a
## +Z y su yaw positivo es hacia su izquierda: hay medio giro de diferencia.
func _on_looked(yaw: float, pitch: float) -> void:
	if condemned:
		return
	_look_yaw = wrapf(yaw + PI - rotation.y, -PI, PI)
	_look_pitch = pitch
	_apply_head()


func _apply_head() -> void:
	figure.set_look(_look_yaw, _look_pitch + _head_kick)
	figure.set_lean_extra(_body_kick)


func _process(delta: float) -> void:
	if condemned:
		return
	# Mientras dura una sacudida se reaplica cada fotograma (el bot solo avisa al girar).
	if _event_tween != null and _event_tween.is_valid():
		_apply_head()
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = _rng.randf_range(IDLE_CHANGE.x, IDLE_CHANGE.y)
		_next_idle()


## Cambia de animación de reposo si la mano no está trabajando ni hay un evento en curso.
func _next_idle() -> void:
	if (_event_tween != null and _event_tween.is_valid()):
		return
	if figure.is_blending():
		_idle_timer = 0.5  # no apilar un cambio de pose sobre otra mezcla en curso
		return
	var options := IDLE_ANIMS.filter(func(a: StringName) -> bool: return a != figure.current())
	figure.play(options[_rng.randi() % options.size()], IDLE_BLEND)


## El rival fue condenado: se detienen poses de reposo, mirada, eventos y brazos. A partir de
## aquí la figura solo la mueve quien la ejecuta (`Condemned`) y luego queda quieta.
func condemn() -> void:
	if condemned:
		return
	condemned = true
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_head_kick = 0.0
	_body_kick = 0.0
	if bot != null and bot.looked.is_connected(_on_looked):
		bot.looked.disconnect(_on_looked)
	set_process(false)
	for rig in [hand_rig, idle_rig]:
		if rig != null:
			rig.set_active(false, 0.2)


## Tos: dos espasmos, cabeza y torso se doblan hacia adelante.
func play_cough() -> void:
	if condemned:
		return
	_start_event_tween()
	_event_tween.tween_method(_cough_step, 0.0, 1.0, 0.9)
	_event_tween.tween_callback(_end_event)


func _cough_step(t: float) -> void:
	var spasm := maxf(sin(t * TAU * 2.0), 0.0) * (1.0 - t * 0.4)
	_head_kick = -spasm * 0.45
	_body_kick = spasm * 0.16


## Se le escapa una pieza: mira hacia abajo, hacia el suelo, un momento.
func play_drop_piece() -> void:
	if condemned:
		return
	_start_event_tween()
	_event_tween.tween_method(_dip_step, 0.0, 1.0, 0.25).set_ease(Tween.EASE_OUT)
	_event_tween.tween_interval(0.7)
	_event_tween.tween_method(_dip_step, 1.0, 0.0, 0.5)
	_event_tween.tween_callback(_end_event)


func _dip_step(k: float) -> void:
	_head_kick = -k * 0.8
	_body_kick = k * 0.22


func _start_event_tween() -> void:
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()


func _end_event() -> void:
	_head_kick = 0.0
	_body_kick = 0.0
	_apply_head()
