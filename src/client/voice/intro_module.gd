class_name IntroModule
extends Node
## Inicio del torneo como espectáculo. Retiene el arranque de la partida (`hold_start`), planta al
## árbitro a oscuras (`Arbiter.begin_address`) y sigue esta coreografía:
##   a. paneo lento de la cámara por el salón (solo el discurso completo);
##   b. la cámara termina en el árbitro (oscuro) y hay una pausa;
##   c. el foco teatral se enciende de golpe, con su sonido;
##   d. habla el árbitro (`show_arbiter`);
##   e. el foco se apaga, con su sonido;
##   f. en la oscuridad: "Begin.";
##   g. los jugadores de negras pulsan el reloj: al tocarlo arranca la partida (`end_address`, cámara
##      de vuelta al tablero, `release_start`).
## Versión corta (torneos siguientes del proceso): sin paneo y con una sola frase. Espacio o Enter
## salta a e-f-g. Solo habla de verdad el primer torneo del proceso.
##
## No sale con `--autoplay`, `--screenshot`, `--walk-demo`, `--no-intro`, `--start-round` > 1 ni con
## demostraciones del árbitro/eventos; `--intro` lo fuerza (capturas).

## Terminó el discurso (`full` = el completo). Lo escucha `InnerVoice`.
signal finished(full: bool)

## Las frases pueden llevar bbcode (efectos de `RichTextLabel`); la voz usa el texto plano.
const FULL_LINES: Array[String] = [
	"Good evening. Everyone in this room owes a debt they [tornado radius=2.0 freq=2.0]will never repay[/tornado].",
	"The House has bought every one of those debts. Tonight, it offers you a way out.",
	"You will play chess. Three minutes on your clock, two more seconds for every move.",
	"Win, and you move on to the next round. Lose, and you are eliminated.",
	"There are no draws here. A drawn game goes to Black.",
	"Anyone caught cheating is [shake rate=20.0 level=6]eliminated[/shake].",
	"If you see your opponent cheat, call me. If you are wrong, you will be warned. The third warning is an elimination.",
	"The last player in this room walks out free of debt. And very [rainbow freq=0.4 sat=0.6 val=1.0]rich[/rainbow].",
]
const SHORT_LINES: Array[String] = ["Another night. The same rules."]
const SKIP_LINE := "Begin."
## Argumentos que desactivan el discurso salvo `--intro`.
const BLOCKING_ARGS: Array[String] = [
	"autoplay", "screenshot", "walk-demo", "no-intro", "force-execution", "lose-now", "win-now", "event",
]
const SFX := "res://assets/audio/sfx/"
## Tiempos (s) de la coreografía.
const PAN_SECONDS := 6.0          # paneo por el salón (completo)
const PAN_SETTLE := 0.8           # pausa con la cámara ya en el árbitro a oscuras
const TURN_SECONDS := 1.3         # giro al árbitro en la versión corta
const SHORT_SETTLE := 0.6         # pausa tras el giro (corta)
const LIGHT_ON_BEAT := 0.7        # tras encender el foco, antes de hablar
const PHRASE_GAP := 0.2
const LIGHT_OFF_BEAT := 0.8       # tras apagar el foco, antes de "Begin."
const BEGIN_SECONDS := 1.2        # "Begin." en la oscuridad, antes de las pulsaciones
const RETURN_SECONDS := 0.8       # la cámara vuelve al tablero durante la pulsación
const PRESS_TIMEOUT := 3.5        # tope de espera al contacto con el reloj
## Sonidos del foco (dB).
const LIGHT_SFX_DB := 2.0
## Paneo: tablas visibles (distancia en metros al jugador) y tope de yaw.
const PAN_MIN_DIST := 2.0
const PAN_MAX_DIST := 11.0
const PAN_MAX_YAW := deg_to_rad(105.0)

## El discurso completo ya se dio en este proceso.
static var _full_given: bool = false

var root: GameRoot
var playing: bool = false

var _skip: bool = false
var _returning: bool = false
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


## Permanencia (s) de una frase en pantalla DESPUÉS de escribirse (la escritura sigue a la voz y
## se suma aparte: `Hud.show_arbiter` devuelve la duración total). Debe dar tiempo de leerla.
static func phrase_seconds(text: String) -> float:
	return 1.0 + 0.024 * DialogueText.plain(text).length()


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
	var head := arb.address_head_position() if addressing and arb.has_method("address_head_position") else Vector3.ZERO
	# a-b. Paneo (completo) o giro directo (corto), y pausa en el árbitro a oscuras.
	if addressing:
		if full:
			_log("fase a: paneo")
			await _pan(head)
		else:
			_log("fase b: giro al árbitro")
			await _turn_to(head, TURN_SECONDS)
		await _wait(PAN_SETTLE if full else SHORT_SETTLE)
	if not _alive():
		return
	# c-d. Foco encendido y discurso.
	var lit := false
	if not _skip:
		_log("fase c: luz")
		lit = true
		_stage_light(true, arb if addressing else null)
		await _wait(LIGHT_ON_BEAT)
	for line in lines:
		if _skip or not _alive():
			break
		_log(line)
		var shown: float = root.hud.show_arbiter(line, phrase_seconds(line))
		await _wait(shown + PHRASE_GAP)
	if not _alive():
		return
	# Atajo (o fin normal): a partir de aquí no se interrumpe.
	_skip = false
	_hide_hint()
	# e. Luz fuera.
	if lit:
		_log("fase e: luz fuera")
		_stage_light(false, arb if addressing else null)
		await _wait(LIGHT_OFF_BEAT)
	elif addressing:
		arb.set_address_light(false)
	if not _alive():
		return
	# f. "Begin." en la oscuridad.
	_log("fase f: Begin.")
	root.hud.show_arbiter(SKIP_LINE, BEGIN_SECONDS)
	await _wait(BEGIN_SECONDS)
	if not _alive():
		return
	# g. Las negras pulsan el reloj; al contacto arranca la partida.
	_log("fase g: pulsan el reloj")
	_returning = true
	_return_view.call_deferred()
	await _press_start_clocks()
	if not _alive():
		return
	if addressing and arb.has_method("end_address"):
		arb.end_address()
	playing = false
	_log("terminado (completo=%s)" % full)
	finished.emit(full)
	root.release_start()
	while _returning and _alive():
		await get_tree().process_frame
	if _alive():
		root.player.set_input_locked(false)


## Mensajes de las fases (solo con `--verbose`).
func _log(text: String) -> void:
	if root != null and root.get_args().has("verbose"):
		print("[discurso] ", text)


## Foco teatral: sonido fuerte (2D, bus SFX) y encendido/apagado de golpe.
func _stage_light(on: bool, arb: Node) -> void:
	if arb != null and arb.has_method("set_address_light"):
		arb.set_address_light(on)
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	p.stream = load(SFX + ("stage_light_on.wav" if on else "stage_light_off.wav"))
	p.volume_db = LIGHT_SFX_DB
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Las manos de negras pulsan el reloj: la del humano (mesa principal; con la entrada bloqueada si él
## es negras) y la figura de negras de cada mesa de fondo. Vuelve al tocar el reloj la mano de la
## mesa del humano (o por tope de tiempo).
func _press_start_clocks() -> void:
	for t in root.bg_tables.values():
		if is_instance_valid(t) and t.has_method("press_start_clock"):
			t.press_start_clock()
	var hand: HandAnimator = root.animators[ChessPiece.BLACK]
	if hand == null:
		return
	var state := {"hit": false}
	var on_hit := func(_c: int) -> void: state.hit = true
	hand.clock_hit.connect(on_hit, CONNECT_ONE_SHOT)
	hand.enqueue_press()
	var t := 0.0
	while not state.hit and t < PRESS_TIMEOUT and _alive():
		await get_tree().process_frame
		t += get_process_delta_time()
	if hand.clock_hit.is_connected(on_hit):
		hand.clock_hit.disconnect(on_hit)


# --- Cámara -----------------------------------------------------------------------------------

## Yaw y pitch (en el marco del jugador) con que la cámara mira `target`.
func _look_to(target: Vector3) -> Vector2:
	var p := root.player
	var d: Vector3 = p.global_transform.basis.inverse() * (target - p.camera.global_position)
	if d.length() < 0.01:
		return Vector2(p.yaw, p.pitch)
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y / d.length(), -1.0, 1.0)))


func _turn_to(target: Vector3, seconds: float) -> void:
	var l := _look_to(target)
	await _blend_look(l.x, l.y, seconds)


func _return_view() -> void:
	await _turn_back(RETURN_SECONDS)
	_returning = false


func _turn_back(seconds: float) -> void:
	await _blend_look(0.0, PlayerController.rest_pitch(), seconds)


func _blend_look(to_yaw: float, to_pitch: float, seconds: float) -> void:
	var p := root.player
	var y0 := p.yaw
	var p0 := p.pitch
	var t := 0.0
	while t < seconds and _alive() and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(t / seconds, 0.0, 1.0))
		p.set_look(lerpf(y0, to_yaw, k), lerpf(p0, to_pitch, k))
	if _alive() and not _skip:
		p.set_look(to_yaw, to_pitch)


## Puntos de mira del paneo: del lado izquierdo al derecho por las mesas con gente a la vista y,
## al final, el árbitro. Cada uno es (yaw, pitch).
func _pan_path(head: Vector3) -> Array[Vector2]:
	var p := root.player
	var cam := p.camera.global_position
	var best_l := Vector2(-INF, 0.0)
	var best_r := Vector2(INF, 0.0)
	for i in HallLayout.table_count():
		if i == HallLayout.human_table:
			continue
		var target := HallLayout.table_position(i) + Vector3(0.0, 0.9, 0.0)
		var dist := Vector2(target.x - cam.x, target.z - cam.z).length()
		if dist < PAN_MIN_DIST or dist > PAN_MAX_DIST:
			continue
		var l := _look_to(target)
		if absf(l.x) > PAN_MAX_YAW:
			continue
		if l.x > best_l.x:
			best_l = l
		if l.x < best_r.x:
			best_r = l
	var path: Array[Vector2] = [Vector2(p.yaw, p.pitch)]
	if best_l.x > -INF and best_r.x < INF:
		path.append(best_l)
		path.append(best_r)
	path.append(_look_to(head))
	return path


## Paneo lento (ease-in-out sobre todo el recorrido) por `_pan_path`.
func _pan(head: Vector3) -> void:
	var path := _pan_path(head)
	var lens: Array[float] = []
	var total := 0.0
	for i in range(1, path.size()):
		var d := (path[i] - path[i - 1]).length()
		lens.append(d)
		total += d
	var t := 0.0
	while t < PAN_SECONDS and _alive() and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, clampf(t / PAN_SECONDS, 0.0, 1.0))
		var at := k * total
		var v := path[path.size() - 1]
		for i in lens.size():
			if at <= lens[i] or i == lens.size() - 1:
				v = path[i].lerp(path[i + 1], clampf(at / maxf(lens[i], 0.0001), 0.0, 1.0))
				break
			at -= lens[i]
		root.player.set_look(v.x, v.y)


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
