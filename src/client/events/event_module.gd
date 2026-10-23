class_name EventModule
extends Node
## Módulo de eventos y director de tensión (Hito 3). Es dueño de un
## `TensionDirector`, lo avanza cada fotograma, muestra cada evento con
## `EventStage` (luces, figuras, sonido espacial) y reparte las distracciones
## (`Distraction`, grupo `distraction_listeners`) a los bots (`notice_event`) y a las
## mesas de fondo (`BackgroundTable.notice_event`). También anima los eventos del rival que confirma
## el servidor (`rival_event`) y maneja el disuasivo: el árbitro que pasa por
## detrás, durante lo cual el servidor marca las trampas como vistas.
##
## Argumentos de depuración (después de `--`):
##   --event=apagon|ruido|acusacion|arbitro|toser   fuerza un evento
##   --event-at=S       segundos de partida antes de forzarlo (por defecto 1)
##   --event-table=N    mesa decorativa de origen (0-8) para la acusación
##   --event-side=human fuerza toser sobre el humano en vez del rival
##   --no-events        sin eventos automáticos

## Referencia de "detrás del jugador" para el árbitro (él elige el pasillo de su espalda).
const ARBITER_BEHIND := Vector3(0.0, 0.0, 0.45)

## Segundos entre que el jugador dice la frase del apagón y que las luces empiezan a apagarse.
const BLACKOUT_LEAD := 1.5

const DEMO_IDS := {
	"apagon": &"apagon", "ruido": &"ruido_detras", "acusacion": &"acusacion_ajena",
	"arbitro": &"arbitro_pasa",
	"toser": &"cough",
}

var root: GameRoot
var director: TensionDirector
var stage: EventStage

var _demo_id: StringName = &""
var _demo_at: float = 1.0
var _demo_table: int = -1
var _demo_human: bool = false
var _time: float = 0.0
var _enabled: bool = true


func install(p_root: GameRoot) -> void:
	name = "Eventos"
	root = p_root
	var defs := TensionDirector.load_defs()
	director = TensionDirector.new(defs, int(root.get_args().get("seed", -1)))
	# Solo mesas con alguien sentado (las vacías no tienen quién acuse).
	var all_tables := Hall.table_positions()
	for i in all_tables.size():
		if i != HallLayout.human_table:
			director.table_positions.append(all_tables[i])
	director.listener_pos = root.player.global_position
	director.listener_forward = (BoardView.CENTER - root.player.global_position) * Vector3(1.0, 0.0, 1.0)
	director.event_triggered.connect(_on_event)

	stage = EventStage.new()
	root.add_child(stage)
	stage.root = root
	stage.setup(root.hall, root.get_node_or_null("Entorno"))
	add_to_group(Distraction.GROUP)
	# El cliente solo informa de la oscuridad; el servidor decide qué deja de verse.
	stage.darkness_changed.connect(root.server.set_blackout)

	root.server.rival_event.connect(_on_rival_event)
	root.server.accusation_started.connect(_on_accusation_shout)
	root.players_remaining_changed.connect(set_players_remaining)
	set_players_remaining(root.players_left(), root.manager.player_count)

	var args := root.get_args()
	_enabled = not args.has("no-events")
	if args.has("event"):
		_demo_id = DEMO_IDS.get(str(args["event"]), &"")
		_demo_at = float(args.get("event-at", 1.0))
		_demo_table = int(args.get("event-table", -1))
		_demo_human = str(args.get("event-side", "")) == "human"
		# En la demostración solo sale el evento pedido.
		director.enabled = false


## Para el torneo: cuántos jugadores quedan (sube la frecuencia de los eventos).
func set_players_remaining(remaining: int, total: int) -> void:
	director.set_players_remaining(remaining, total)


func _process(delta: float) -> void:
	var server := root.server
	if server == null or not server.started or server.is_over():
		return
	_time += delta
	if _enabled and not server.accusation_pending():
		director.tick(delta)
	if _demo_id != &"" and _time >= _demo_at:
		var id := _demo_id
		_demo_id = &""
		_run_demo(id)


func _run_demo(id: StringName) -> void:
	var def := director.get_def(id)
	if def == null:
		return
	if def.kind == EventDef.Kind.RIVAL:
		var color := root.human_color if _demo_human else root.rival_color
		root.server.trigger_rival_event(color, id)
		return
	var origin: Variant = null
	if _demo_table >= 0 and _demo_table < director.table_positions.size():
		origin = director.table_positions[_demo_table]
	director.fire(id, origin)


# --- Eventos globales ----------------------------------------------------------------------

func _on_event(id: StringName, origin: Vector3, duration: float) -> void:
	var def := director.get_def(id)
	var notice_pos := origin
	if root.get_args().has("verbose") or root.get_args().has("autoplay"):
		print("[evento %.1f] %s en %s (%.1f s)" % [_time, id, origin, duration])
	match id:
		&"apagon":
			_start_blackout(duration)
			return
		&"ruido_detras":
			stage.fall_behind(origin)
		&"acusacion_ajena":
			stage.accuser(origin, duration, root.player.global_position)
			notice_pos = origin + Vector3(0.0, 1.5, 0.0)
		&"arbitro_pasa":
			# El aviso lo da `ArbiterModule` cuando el árbitro llega de verdad cerca de la mesa.
			_start_arbiter_pass(duration)
			return
	# Solo los eventos con `turn_chance` hacen voltear (la banqueta, por ejemplo, no).
	if def != null and def.turn_chance > 0.0 and def.distraction != &"":
		on_distraction(def.distraction, notice_pos, _table_of(origin), def.turn_chance)


## El apagón: primero el jugador dice su frase (monólogo interior) y, tras `BLACKOUT_LEAD` s,
## se apagan las luces, suena la bombilla y se reparte la distracción.
func _start_blackout(duration: float) -> void:
	var voice := root.get_node_or_null("MonologoInterior") as InnerVoice
	if voice != null:
		voice.announce_blackout()
	await get_tree().create_timer(BLACKOUT_LEAD).timeout
	if not is_inside_tree() or stage == null or not is_instance_valid(stage):
		return
	stage.blackout(duration)
	stage.play_sound(&"bulb_pop", Vector3(0.0, 2.0, 0.0), 4.0)
	var def := director.get_def(&"apagon")
	if def != null and def.turn_chance > 0.0 and def.distraction != &"":
		on_distraction(def.distraction, Vector3(0.0, 1.95, 0.0), -1, def.turn_chance)


## Mesa del hall más cercana a `pos` (-1 si ninguna a menos de 1,5 m).
func _table_of(pos: Vector3) -> int:
	var best := -1
	var best_d := 1.5
	for i in root.hall.table_count():
		var p := root.hall.table_position(i)
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## Reparte una distracción (ver `Distraction`) a bots y mesas de fondo. `table` = mesa de origen
## (-1 ninguna): los bots de la mesa del humano la ignoran si ocurre en su propia mesa, y en
## `flag` la mesa de origen no reacciona (ya lo sabe). `chance` < 0 = la de la tabla.
func on_distraction(kind: StringName, pos: Vector3, table: int = -1, chance: float = -1.0) -> void:
	if not Distraction.has(kind) or root == null:
		return
	if table != HallLayout.human_table:
		for bot in [root.rival_bot, root.auto_bot]:
			var b := bot as BotController
			if b != null and Distraction.in_range(kind, b.eye_position, pos):
				b.notice_event(pos, chance, kind)
	for t in root.bg_tables:
		if t == table and kind == &"flag":
			continue
		var bt: BackgroundTable = root.bg_tables[t]
		if Distraction.in_range(kind, bt.global_position + Vector3(0.0, 1.1, 0.0), pos):
			bt.notice_event(pos, kind, chance)


# --- El árbitro pasa detrás --------------------------------------------------------------------

func _start_arbiter_pass(duration: float) -> bool:
	var arbiter := root.get_node_or_null("Arbitro")
	if arbiter == null or not arbiter.has_method("pass_behind"):
		return false
	arbiter.pass_behind(ARBITER_BEHIND, duration)
	return true


## Solo cuando el rival acusa al humano suena el grito de 8 bits (desde su cabeza, espacial) y
## sale el subtítulo "Cheater!"; así ese grito significa siempre "te acusaron". Cuando acusa el
## humano, o una figura de otra mesa, no hay grito ni subtítulo.
func _on_accusation_shout(accuser: int) -> void:
	if accuser != root.rival_color:
		return
	stage.shout(root.avatar.head.global_position)
	root.hud.show_subtitle("Cheater!", 2.2, false)


# --- Eventos del rival ----------------------------------------------------------------------------

## El servidor confirmó que `color` tosió.
func _on_rival_event(color: int, event_id: StringName) -> void:
	var is_rival := color == root.rival_color
	var pos: Vector3 = root.avatar.head.global_position if is_rival else root.player.global_position
	match event_id:
		&"cough":
			if is_rival:
				root.avatar.play_cough()
				# Los espasmos de `sit_cough` empiezan ~0,55 s tras el inicio del clip.
				await get_tree().create_timer(OpponentAvatar.COUGH_SOUND_DELAY).timeout
			stage.play_sound(&"cough", pos, 2.0)
	# Tos y ruidos del jugador no hacen voltear (descartados): no hay aviso a los bots.
