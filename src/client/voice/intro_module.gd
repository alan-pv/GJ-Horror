class_name IntroModule
extends Node
## Discurso del árbitro al empezar la ronda 1 de un torneo. Retiene el arranque de la partida
## (`hold_start`), pone al árbitro de pie delante del jugador (`Arbiter.begin_address`), gira la
## cámara hacia él, dice las frases con `show_arbiter` y devuelve la cámara al tablero antes de
## soltar el arranque. Espacio o Enter lo salta. Solo habla de verdad el primer torneo del proceso;
## en los siguientes (tras morir) dice la versión corta.
##
## No sale con `--autoplay`, `--screenshot`, `--walk-demo`, `--no-intro`, `--start-round` > 1 ni con
## demostraciones del árbitro/eventos; `--intro` lo fuerza (capturas).

## Terminó el discurso (`full` = el completo). Lo escucha `InnerVoice`.
signal finished(full: bool)

const FULL_LINES: Array[String] = [
	"Good evening. Everyone in this room owes a debt they will never repay.",
	"The House has bought every one of those debts. Tonight, it offers you a way out.",
	"You will play chess. Three minutes on your clock, two more seconds for every move.",
	"Win, and you move on to the next round. Lose, and you are eliminated.",
	"There are no draws here. A drawn game goes to Black.",
	"Anyone caught cheating is eliminated.",
	"If you see your opponent cheat, call me. If you are wrong, you will be warned. The third warning is an elimination.",
	"The last player in this room walks out free of debt. And very rich.",
	"I sat where you are sitting, once. Begin.",
]
const SHORT_LINES: Array[String] = ["Another night. The same rules. Begin."]
const SKIP_LINE := "Begin."
## Argumentos que desactivan el discurso salvo `--intro`.
const BLOCKING_ARGS: Array[String] = [
	"autoplay", "screenshot", "walk-demo", "no-intro", "force-execution", "lose-now", "win-now", "event",
]
const TURN_SECONDS := 1.3
const PHRASE_GAP := 0.35

## El discurso completo ya se dio en este proceso.
static var _full_given: bool = false

var root: GameRoot
var playing: bool = false

var _skip: bool = false
var _hint: Label
var _layer: CanvasLayer


## ¿Toca dar el discurso? Lógica pura (se prueba aparte).
static func should_play(args: Dictionary, round_no: int, is_final: bool, has_game: bool) -> bool:
	if not has_game:
		return false
	if args.has("intro"):
		return true
	for a in BLOCKING_ARGS:
		if args.has(a):
			return false
	if int(args.get("start-round", 1)) > 1:
		return false
	return round_no == 1 and not is_final


## Duración (s) que se deja una frase en pantalla.
static func phrase_seconds(text: String) -> float:
	return 1.6 + 0.055 * text.length()


## Para las pruebas: olvida que ya se dio el completo.
static func reset_process_state() -> void:
	_full_given = false


func install(p_root: GameRoot) -> void:
	name = "Discurso"
	root = p_root
	if not should_play(root.get_args(), root.manager.round_no, root.manager.is_final, root.tgame != null):
		return
	playing = true
	root.hold_start()
	_run.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_skip = true
		get_viewport().set_input_as_handled()


func _alive() -> bool:
	return is_inside_tree() and root != null and is_instance_valid(root)


## Espera `seconds` (tiempo de juego); false si se saltó o se recargó la escena.
func _wait(seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if not _alive() or _skip:
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
	return _alive() and not _skip


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _alive():
		return
	var full := not _full_given
	_full_given = true
	var lines := FULL_LINES if full else SHORT_LINES
	var arb := root.arbiter
	var addressing := arb != null and arb.has_method("begin_address")
	if addressing:
		arb.begin_address()
	_show_hint()
	root.player.set_input_locked(true)
	if addressing and arb.has_method("address_head_position"):
		await _turn_to(arb.address_head_position(), TURN_SECONDS)
	for line in lines:
		if _skip or not _alive():
			break
		if root.get_args().has("verbose"):
			print("[discurso] ", line)
		root.hud.show_arbiter(line, phrase_seconds(line))
		await _wait(phrase_seconds(line) + PHRASE_GAP)
	if not _alive():
		return
	if _skip:
		# Atajo: pasa directo a "Begin.".
		root.hud.show_arbiter(SKIP_LINE, 1.2)
		_skip = false
		_hide_hint()
		await _wait(1.0)
		if not _alive():
			return
	_hide_hint()
	if addressing and arb.has_method("end_address"):
		arb.end_address()
	await _turn_back(0.9)
	if not _alive():
		return
	root.player.set_input_locked(false)
	playing = false
	if root.get_args().has("verbose"):
		print("[discurso] terminado (completo=%s)" % full)
	finished.emit(full)
	root.release_start()


# --- Cámara -----------------------------------------------------------------------------------

func _turn_to(target: Vector3, seconds: float) -> void:
	var p := root.player
	var d: Vector3 = p.global_transform.basis.inverse() * (target - p.camera.global_position)
	if d.length() < 0.01:
		return
	var to_yaw := atan2(-d.x, -d.z)
	var to_pitch := asin(clampf(d.y / d.length(), -1.0, 1.0))
	await _blend_look(to_yaw, to_pitch, seconds)


func _turn_back(seconds: float) -> void:
	await _blend_look(0.0, PlayerController.rest_pitch(), seconds)


func _blend_look(to_yaw: float, to_pitch: float, seconds: float) -> void:
	var p := root.player
	var y0 := p.yaw
	var p0 := p.pitch
	var t := 0.0
	while t < seconds and _alive():
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(t / seconds, 0.0, 1.0))
		p.set_look(lerpf(y0, to_yaw, k), lerpf(p0, to_pitch, k))
	if _alive():
		p.set_look(to_yaw, to_pitch)


# --- Pista "SPACE: skip" -------------------------------------------------------------------------

func _show_hint() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 11
	add_child(_layer)
	_hint = Label.new()
	_hint.text = "SPACE: skip"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.67, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -300
	_hint.offset_right = -20
	_hint.offset_top = -44
	_hint.offset_bottom = -20
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_hint)


func _hide_hint() -> void:
	if _layer != null:
		_layer.queue_free()
		_layer = null
