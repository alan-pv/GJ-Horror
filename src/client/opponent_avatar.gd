class_name OpponentAvatar
extends Node3D
## El rival: una `SeatedFigure` (modelo de Blender) sentada en su silla, mirando a +Z hacia el
## jugador. La cabeza sigue la mirada del bot (`BotController.looked`: la misma cámara virtual
## con la que el servidor decide si mira el tablero), que es lo que el jugador debe leer. En
## reposo pide ROLES de animación (`sit_wait` esperando, `sit_think` en su turno, `sit_nervous`
## con poco reloj) y cambia de variante cada 5-12 s sin pisar una mezcla. Toser (`sit_cough`),
## recoger la pieza (`sit_pick_up`) y sobresaltarse (`sit_startle`) también son roles. Es dueño
## de la mano (`HandRig`) del rival, que usa el brazo izquierdo: así queda del mismo lado que el
## reloj y que su pila de capturas.
##
## IK <-> animación: en reposo el IK de AMBOS brazos se apaga (influencia 0, mezcla de 0,45 s)
## para que se vean las poses con la mano en la cara. Se vigila al `HandAnimator` del rival
## (`bind_animator`): en cuanto tiene trabajo (jugada, trampa, pulsación, escritura) el IK vuelve
## a 1 en 0,35 s, y se apaga 0,8 s después de quedar libre.
##
## El nodo se coloca en el suelo bajo el asiento; la figura mira a +Z sin girar.

## Ojos de la figura sentada, en el espacio local del nodo (medido con `sit_idle`).
const EYE_LOCAL := Vector3(0.0, 1.146, 0.27)
## Rango (s) entre cambios de variante de la pose de reposo, y mínimo en una pose antes de
## cambiar de rol por el estado de la partida (turno, reloj).
const IDLE_CHANGE := Vector2(5.0, 12.0)
const STATE_DWELL := 2.5
## Con menos segundos que estos en su reloj, el rival está nervioso.
const LOW_CLOCK := 30.0
## IK: mezcla (s) al encenderlo/apagarlo y espera tras quedar libre el animador.
const IK_FADE_IN := 0.35
const IK_FADE_OUT := 0.45
const IK_OFF_DELAY := 0.8
## Retraso (s) del sonido de la tos respecto al inicio de `sit_cough` (los espasmos empiezan ~0,55 s).
const COUGH_SOUND_DELAY := 0.55

## Se agarró la pieza caída (mitad de `sit_pick_up`).
signal piece_grabbed

var figure: SeatedFigure
## Marcador pegado al hueso de la cabeza (posición de la cabeza para efectos y sonidos).
var head: Node3D
var hand_rig: HandRig
## La otra mano (derecha): descansa sobre la mesa y es la que escribe en la planilla (`HandAnimator.write_rig`).
var idle_rig: HandRig
var bot: BotController
## Animador de manos del rival: se vigila para encender/apagar el IK.
var animator: HandAnimator

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
## Sacudida de eventos (toser, tirar una pieza): cabeza (cabeceo, rad) y torso (inclinación, rad).
var _head_kick: float = 0.0
var _body_kick: float = 0.0
var _event_tween: Tween
var _role: StringName = &"sit_wait"
var _role_age: float = 0.0
var _dwell: float = 6.0
var _once_busy: bool = false
var _ik_on: bool = true
var _ik_idle: float = 0.0
var _ik_synced: bool = false
var _find_t: float = 0.0
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
	_role = &"sit_wait"
	figure.play_role(_role, _rng)
	_dwell = _rng.randf_range(IDLE_CHANGE.x, IDLE_CHANGE.y)
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


## Vigila al animador de manos (ver cabecera). Si no se llama, se busca el hermano `AnimadorRival`.
func bind_animator(p_animator: HandAnimator) -> void:
	animator = p_animator


func bind_bot(p_bot: BotController) -> void:
	bot = p_bot
	bot.looked.connect(_on_looked)
	bot.startled.connect(startle)
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
	_find_animator(delta)
	_update_ik(delta)
	_update_pose(delta)


func _find_animator(delta: float) -> void:
	if animator != null or get_parent() == null:
		return
	_find_t -= delta
	if _find_t > 0.0:
		return
	_find_t = 0.5
	animator = get_parent().get_node_or_null("AnimadorRival") as HandAnimator


# --- IK <-> animación --------------------------------------------------------------

## Enciende el IK de ambos brazos en cuanto el animador tiene trabajo y lo apaga cuando lleva
## `IK_OFF_DELAY` s libre. Sin animador no toca nada.
func _update_ik(delta: float) -> void:
	if animator == null:
		return
	if animator.is_busy():
		_ik_idle = 0.0
		if not _ik_on:
			_set_ik(true, IK_FADE_IN)
		return
	_ik_idle += delta
	if _ik_on and (_ik_idle >= IK_OFF_DELAY or not _ik_synced):
		# La primera vez (el animador acaba de encender el IK al montar la mesa) se apaga sin mezcla.
		_set_ik(false, IK_FADE_OUT if _ik_synced else 0.0)
		_ik_synced = true


func _set_ik(on: bool, fade: float) -> void:
	_ik_on = on
	for rig in [hand_rig, idle_rig]:
		if rig != null:
			rig.set_ik_weight(1.0 if on else 0.0, fade)


## ¿Puede reproducirse una animación con las manos libres (IK apagado o a punto)? Si el animador
## trabaja, no: la mano obedece al IK.
func _hands_free() -> bool:
	return animator == null or not animator.is_busy()


# --- Pose de reposo -------------------------------------------------------------------

## Rol de reposo que toca según la partida: nervioso con poco reloj, pensar en su turno, esperar.
func desired_role() -> StringName:
	if bot == null or bot.server == null or not bot.server.started or bot.server.is_over():
		return &"sit_wait"
	var s := bot.server
	if s.clock.remaining[bot.color] < LOW_CLOCK:
		return &"sit_nervous"
	if s.board.side_to_move == bot.color and s.pending_press < 0:
		return &"sit_think"
	return &"sit_wait"


func _update_pose(delta: float) -> void:
	_role_age += delta
	if _once_busy or figure.is_blending() or not _hands_free():
		return  # nunca a mitad de una mezcla ni bajo el IK
	var want := desired_role()
	if want != _role:
		if _role_age >= STATE_DWELL:
			_switch_role(want)
	elif _role_age >= _dwell:
		_switch_role(_role)  # otra variante del mismo rol


func _switch_role(role: StringName) -> void:
	_role = role
	_role_age = 0.0
	_dwell = _rng.randf_range(IDLE_CHANGE.x, IDLE_CHANGE.y)
	figure.play_role(role, _rng)


## Vuelve a la pose de reposo tras una animación de una vez.
func _resume_idle() -> void:
	_once_busy = false
	if not condemned:
		_switch_role(desired_role())


## Reproduce un rol de una vez con las manos libres (IK apagado). false si no se puede.
func _play_once_role(role: StringName) -> bool:
	if condemned or _once_busy or not figure.has_role(role) or not _hands_free():
		return false
	_once_busy = true
	if _ik_on:
		_set_ik(false, 0.3)
	await figure.play_role_once(role, _rng)
	_resume_idle()
	return true


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


## Tos: `sit_cough` con la mano en la boca. Si el animador está trabajando (el IK manda en los
## brazos) o el modelo no trae el clip, queda la versión por código: cabeza y torso se doblan.
func play_cough() -> void:
	if condemned:
		return
	if await _play_once_role(&"sit_cough"):
		return
	if condemned:
		return
	_start_event_tween()
	_event_tween.tween_method(_cough_step, 0.0, 1.0, 0.9)
	_event_tween.tween_callback(_end_event)


func _cough_step(t: float) -> void:
	var spasm := maxf(sin(t * TAU * 2.0), 0.0) * (1.0 - t * 0.4)
	_head_kick = -spasm * 0.45
	_body_kick = spasm * 0.16


## Se le escapa una pieza: mira al suelo un momento y la recoge (`sit_pick_up`, inclinándose a
## su derecha). A mitad del gesto se emite `piece_grabbed` y la pieza (si se da) desaparece.
## Sin el clip (o con la mano ocupada) solo mira hacia abajo.
func play_drop_piece(piece: Node3D = null) -> void:
	if condemned:
		return
	_start_event_tween()
	_event_tween.tween_method(_dip_step, 0.0, 1.0, 0.25).set_ease(Tween.EASE_OUT)
	_event_tween.tween_interval(0.5)
	_event_tween.tween_method(_dip_step, 1.0, 0.0, 0.35)
	_event_tween.tween_callback(_end_event)
	await _event_tween.finished
	if condemned or not _hands_free() or not figure.has_role(&"sit_pick_up"):
		return
	# La pieza tarda ~1,2 s en llegar al suelo.
	_grab_later(piece)
	await _play_once_role(&"sit_pick_up")


func _grab_later(piece: Node3D) -> void:
	await get_tree().create_timer(1.55).timeout
	if is_instance_valid(piece):
		piece.visible = false
	piece_grabbed.emit()


func _dip_step(k: float) -> void:
	_head_kick = -k * 0.8
	_body_kick = k * 0.22


## Respingo ante un evento fuerte en `world_pos`: `sit_startle` del lado del origen.
func startle(world_pos: Vector3) -> void:
	if condemned or _once_busy or not figure.has_role(&"sit_startle") or not _hands_free():
		return
	var local := figure.global_transform.affine_inverse() * world_pos
	var clip := &"sit_startle__left" if local.x > 0.0 else &"sit_startle__right"
	if not figure.has_animation(clip):
		_play_once_role(&"sit_startle")
		return
	_once_busy = true
	if _ik_on:
		_set_ik(false, 0.2)
	await figure.play_once(clip, AnimRoles.blend_of(&"sit_startle"))
	_resume_idle()


func _start_event_tween() -> void:
	if _event_tween != null and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()


func _end_event() -> void:
	_head_kick = 0.0
	_body_kick = 0.0
	_apply_head()
