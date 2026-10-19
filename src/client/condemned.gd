class_name Condemned
extends Node
## Reacción de un condenado a muerte mientras espera al árbitro, y su caída.
## Cuelga de la `CharacterFigure` del perdedor (la entrega `GameRoot.condemn_seat`).
## Las mesas que el jugador ve de frente tienen reacciones ricas (suplicar, llorar,
## paralizarse, huir); las lejanas, una más simple. Los sonidos son 3D en su cabeza.

enum Mode { SOB, BEG, CRY, FROZEN, FLEE }

const SFX := "res://assets/audio/sfx/"
## Cuánto retrocede en la animación `stand_flee` (en metros, hacia atrás de la figura).
const FLEE_RISE_BACK := 0.44
## Metros más que huye hacia atrás con el ciclo de huida antes de quedarse a esperar.
const FLEE_RUN := 0.7
## Velocidad de avance del ciclo `stand_flee_cycle` a velocidad de animación 1 (m/s).
const FLEE_SPEED := 0.5
const FLEE_ANIM_SPEED := 1.3
## Dónde suena la voz respecto al origen de la figura sentada / de pie.
const VOICE_SEATED := Vector3(0.0, 1.15, 0.12)
const VOICE_STANDING := Vector3(0.0, 1.55, 0.0)

var figure: CharacterFigure
var mode: Mode = Mode.SOB
var rich: bool = false
## Signo en Z del asiento: "atrás" de la figura es +Z mundial si vale +1.
var seat_sign: float = 1.0
var dead: bool = false
var standing: bool = false
var fleeing: bool = false
var fled: bool = false
## Nodo del que se oye venir al árbitro (para mirarlo).
var threat: Node3D

var _voice: AudioStreamPlayer3D
var _loop: AudioStreamPlayer3D
var _next_whimper: float = 1.0
var _rng := RandomNumberGenerator.new()
var _seed_offset: float = 0.0


## Reparte la reacción según si la mesa es de las que el jugador ve de frente.
static func pick_mode(is_rich: bool, rng: RandomNumberGenerator) -> Mode:
	var r := rng.randf()
	if not is_rich:
		return Mode.SOB if r < 0.55 else Mode.FROZEN
	if r < 0.30:
		return Mode.BEG
	if r < 0.52:
		return Mode.CRY
	if r < 0.74:
		return Mode.FROZEN
	return Mode.FLEE


## Prepara y arranca la reacción. `p_sign` = signo en Z del asiento.
func start(p_figure: CharacterFigure, p_mode: Mode, p_rich: bool, p_sign: float, p_threat: Node3D) -> void:
	name = "Condenado"
	figure = p_figure
	mode = p_mode
	rich = p_rich
	seat_sign = p_sign
	threat = p_threat
	_rng.randomize()
	figure.add_child(self)
	_voice = _make_player(VOICE_SEATED, -3.0 if rich else -9.0)
	_loop = _make_player(VOICE_SEATED, -9.0 if rich else -15.0)
	match mode:
		Mode.BEG:
			figure.play(&"sit_beg", 0.7, _rng.randf_range(0.9, 1.15))
			_set_loop("sob_loop")
		Mode.CRY, Mode.SOB:
			figure.play(&"sit_cry", 0.7, _rng.randf_range(0.9, 1.1))
			_set_loop("sob_loop")
		Mode.FROZEN:
			figure.play(&"sit_frozen", 0.8)
			_set_loop("panic_breath_loop")
		Mode.FLEE:
			# Antes de huir tiembla en la silla.
			figure.play(&"sit_nervous", 0.6, 1.4)
			_set_loop("panic_breath_loop")
	_next_whimper = _rng.randf_range(0.5, 2.5)


func _make_player(pos: Vector3, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.position = pos
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	p.unit_size = 2.0
	p.max_distance = 16.0 if rich else 11.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = db
	figure.add_child(p)
	return p


func _set_loop(sfx: String) -> void:
	_loop.stream = load(SFX + sfx + ".wav")
	_loop.pitch_scale = _rng.randf_range(0.92, 1.08)
	_loop.play(_rng.randf() * 1.0)


func _process(delta: float) -> void:
	if dead or figure == null:
		return
	# Mira al árbitro cuando se acerca (o al suelo si llora).
	if threat != null and is_instance_valid(threat) and mode != Mode.CRY and mode != Mode.SOB:
		var tp := threat.global_position + Vector3(0.0, 1.6, 0.0)
		figure.look_at_point(tp)
	elif mode == Mode.CRY or mode == Mode.SOB:
		figure.set_look(0.0, -0.45)
	# Lloriqueos sueltos sobre la respiración o el sollozo.
	_next_whimper -= delta
	if _next_whimper <= 0.0:
		_next_whimper = _rng.randf_range(2.0, 4.5)
		if (mode == Mode.BEG or mode == Mode.FLEE or (rich and mode != Mode.FROZEN)) and not fleeing:
			_voice.stream = load(SFX + "whimper.wav")
			_voice.pitch_scale = _rng.randf_range(0.9, 1.15)
			_voice.play()


## Corre y se queda de pie esperando: para el modo FLEE, cuando el árbitro ya viene.
## Termina cuando se detiene (queda de pie, a `FLEE_RUN` metros del punto de reposo).
func begin_flee() -> void:
	if fleeing or fled or dead or mode != Mode.FLEE:
		return
	fleeing = true
	_set_loop("panic_breath_loop")
	_loop.volume_db = -3.0
	var scrape := _make_player(Vector3(0.0, 0.3, 0.0), -2.0)
	scrape.stream = load(SFX + "chair_scrape.wav")
	scrape.pitch_scale = _rng.randf_range(0.95, 1.05)
	scrape.play()
	figure.set_look(0.0, 0.0)
	await figure.play_once(&"stand_flee", 0.35)
	if dead or not is_inside_tree():
		return
	standing = true
	_voice.position = VOICE_STANDING
	_loop.position = VOICE_STANDING
	# La animación ya retrocedió `FLEE_RISE_BACK`; el ciclo parte del origen, así que se
	# traslada la figura esa distancia para que no salte.
	var back := Vector3(0.0, 0.0, seat_sign)
	figure.global_position += back * FLEE_RISE_BACK
	figure.play(&"stand_flee_cycle", 0.15, FLEE_ANIM_SPEED)
	var run := FLEE_RUN
	var v := FLEE_SPEED * FLEE_ANIM_SPEED
	while run > 0.0 and not dead and is_inside_tree():
		await get_tree().process_frame
		var step := minf(v * get_process_delta_time(), run)
		figure.global_position += back * step
		run -= step
	if dead:
		return
	# Se queda de pie, acorralado, temblando: ciclo lentísimo en el sitio.
	figure.play(&"stand_flee_cycle", 0.3, 0.12)
	fled = true


## Posición de pie final tras huir (para que el árbitro vaya a ese punto), a partir del asiento.
static func flee_spot(seat_pos: Vector3, p_sign: float) -> Vector3:
	return seat_pos + Vector3(0.0, 0.0, p_sign * (FLEE_RISE_BACK + FLEE_RUN))


## Recibe el disparo. `kind`: &"slump" (sobre la mesa), &"fall_back" (de espaldas) o
## &"standing" (de pie). Corrutina: termina cuando el cuerpo ya cayó.
func die(kind: StringName) -> void:
	if dead:
		return
	dead = true
	_voice.stop()
	_loop.stop()
	figure.set_look(0.0, 0.0)
	var anim := &"death_slump_table"
	var floor_sound := false
	match kind:
		&"fall_back":
			anim = &"death_fall_back"
			floor_sound = true
		&"standing":
			anim = &"death_standing"
			floor_sound = true
	# El cuerpo cae y suena al golpear (tras el tiempo en que llega a la mesa o al suelo).
	figure.play(anim, 0.04)
	var thud := _make_player(Vector3(0.0, 0.2, 0.0), 2.0)
	thud.stream = load(SFX + ("body_fall_floor.wav" if floor_sound else "body_slump_table.wav"))
	thud.unit_size = 3.0
	thud.max_distance = 20.0
	await get_tree().create_timer(0.5 if not floor_sound else 0.8).timeout
	if is_instance_valid(thud):
		thud.play()
	await get_tree().create_timer(1.0).timeout
