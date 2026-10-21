class_name Condemned
extends Node
## Reacción de un condenado a muerte mientras espera al árbitro, y su caída.
## Cuelga de la `CharacterFigure` del perdedor (la entrega `GameRoot.condemn_seat`).
## Las mesas que el jugador ve de frente tienen reacciones ricas (suplicar, llorar,
## paralizarse); las lejanas, una más simple. Siempre mueren sentados, sobre la mesa. Los sonidos son 3D en su cabeza.

enum Mode { SOB, BEG, CRY, FROZEN }

const SFX := "res://assets/audio/sfx/"
## Dónde suena la voz respecto al origen de la figura sentada.
const VOICE_SEATED := Vector3(0.0, 1.15, 0.12)

var figure: CharacterFigure
var mode: Mode = Mode.SOB
var rich: bool = false
## Signo en Z del asiento: "atrás" de la figura es +Z mundial si vale +1.
var seat_sign: float = 1.0
var dead: bool = false
## Nodo del que se oye venir al árbitro (para mirarlo).
var threat: Node3D
## Mesa del condenado (-1 si no se conoce): origen del aviso de súplica.
var table: int = -1
## Segundos entre avisos de llanto/súplica a quienes lo oyen (`Distraction` tipo `plea`).
const PLEA_EVERY := Vector2(6.0, 11.0)
var _next_plea: float = 2.0

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
	return Mode.FROZEN


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
			figure.play(&"sit_cry", 0.7, _rng.randf_range(0.9, 1.15))
			_set_loop("sob_loop")
		Mode.CRY, Mode.SOB:
			figure.play(&"sit_cry", 0.7, _rng.randf_range(0.9, 1.1))
			_set_loop("sob_loop")
		Mode.FROZEN:
			figure.play(&"sit_frozen", 0.8)
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
	# Llanto o súplica: avisa a quien lo oiga (los demás pueden voltear). Los paralizados callan.
	_next_plea -= delta
	if _next_plea <= 0.0:
		_next_plea = _rng.randf_range(PLEA_EVERY.x, PLEA_EVERY.y)
		if mode != Mode.FROZEN and is_inside_tree():
			Distraction.broadcast(self, &"plea", figure.head_global_position(), table)
	# Lloriqueos sueltos sobre la respiración o el sollozo.
	_next_whimper -= delta
	if _next_whimper <= 0.0:
		_next_whimper = _rng.randf_range(2.0, 4.5)
		if mode == Mode.BEG or (rich and mode != Mode.FROZEN):
			_voice.stream = load(SFX + "whimper.wav")
			_voice.pitch_scale = _rng.randf_range(0.9, 1.15)
			_voice.play()


## Recibe el disparo y cae sobre la mesa.
## Corrutina: termina cuando el cuerpo ya cayó.
func die() -> void:
	if dead:
		return
	dead = true
	_voice.stop()
	_loop.stop()
	figure.set_look(0.0, 0.0)
	# El cuerpo cae y suena al golpear (tras el tiempo en que llega a la mesa).
	figure.play(&"death_slump_table", 0.04)
	var thud := _make_player(Vector3(0.0, 0.2, 0.0), 2.0)
	thud.stream = load(SFX + "body_slump_table.wav")
	thud.unit_size = 3.0
	thud.max_distance = 20.0
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(thud):
		thud.play()
	await get_tree().create_timer(1.0).timeout
