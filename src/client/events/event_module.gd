class_name EventModule
extends Node
## Módulo de eventos y director de tensión (Hito 3). Es dueño de un
## `TensionDirector`, lo avanza cada fotograma, muestra cada evento con
## `EventStage` (luces, figuras, sonido espacial) y avisa a los bots para que
## volteen (`notice_event`). También anima los eventos del rival que confirma
## el servidor (`rival_event`) y maneja el disuasivo: el árbitro que pasa por
## detrás, durante lo cual el servidor marca las trampas como vistas.
##
## Argumentos de depuración (después de `--`):
##   --event=apagon|ruido|acusacion|eliminacion|arbitro|toser|pieza   fuerza un evento
##   --event-at=S       segundos de partida antes de forzarlo (por defecto 1)
##   --event-table=N    mesa decorativa de origen (0-8) para acusación/eliminación
##   --event-side=human fuerza toser/pieza sobre el humano en vez del rival
##   --no-events        sin eventos automáticos

## Referencia de "detrás del jugador" para el árbitro (él elige el pasillo de su espalda).
const ARBITER_BEHIND := Vector3(0.0, 0.0, 0.45)

const DEMO_IDS := {
	"apagon": &"apagon", "ruido": &"ruido_detras", "acusacion": &"acusacion_ajena",
	"eliminacion": &"eliminacion", "arbitro": &"arbitro_pasa",
	"toser": &"cough", "pieza": &"drop_piece",
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
## Asiento del eliminado cuya salida está en curso (-1 = evento aleatorio, sin asiento);
## solo lo usa el evento `eliminacion` forzado por depuración.
var _drag_seat: int = -1


func install(p_root: GameRoot) -> void:
	name = "Eventos"
	root = p_root
	var defs := TensionDirector.load_defs()
	director = TensionDirector.new(defs, int(root.get_args().get("seed", -1)))
	# Solo mesas con alguien sentado (las vacías no tienen quién acuse ni a quién llevarse).
	var all_tables := Hall.table_positions()
	for i in all_tables.size():
		if int(Hall.DECOR_TABLES[i][2]) > 0:
			director.table_positions.append(all_tables[i])
	director.listener_pos = root.player.global_position
	director.listener_forward = (BoardView.CENTER - root.player.global_position) * Vector3(1.0, 0.0, 1.0)
	director.event_triggered.connect(_on_event)

	stage = EventStage.new()
	root.add_child(stage)
	stage.setup(root.hall, root.get_node_or_null("Entorno"))

	root.server.rival_event.connect(_on_rival_event)
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
	var intensity := def.intensity if def != null else 0.5
	var notice_pos := origin
	if root.get_args().has("verbose") or root.get_args().has("autoplay"):
		print("[evento %.1f] %s en %s (%.1f s)" % [_time, id, origin, duration])
	match id:
		&"apagon":
			stage.blackout(duration)
			stage.play_sound(&"bulb_pop", Vector3(0.0, 2.0, 0.0), 4.0)
			notice_pos = Vector3(0.0, 1.95, 0.0)
		&"ruido_detras":
			stage.fall_behind(origin)
			notice_pos = origin + Vector3(0.0, 0.5, 0.0)
		&"acusacion_ajena":
			stage.accuser(origin, duration, root.player.global_position)
			root.hud.show_subtitle("Cheater!", 2.2)
			notice_pos = origin + Vector3(0.0, 1.5, 0.0)
		&"eliminacion":
			stage.drag_away(origin, duration, _drag_seat)
			_drag_seat = -1
			notice_pos = origin + Vector3(0.0, 1.0, 0.0)
		&"arbitro_pasa":
			if not _start_arbiter_pass(duration):
				return
			intensity = 0.0
	if intensity > 0.0:
		_notify_bots(notice_pos, intensity)


func _notify_bots(pos: Vector3, intensity: float) -> void:
	if root.rival_bot != null:
		root.rival_bot.notice_event(pos, intensity)
	if root.auto_bot != null:
		root.auto_bot.notice_event(pos, intensity)


# --- El árbitro pasa detrás --------------------------------------------------------------------

func _start_arbiter_pass(duration: float) -> bool:
	var arbiter := root.get_node_or_null("Arbitro")
	if arbiter == null or not arbiter.has_method("pass_behind"):
		return false
	arbiter.pass_behind(ARBITER_BEHIND, duration)
	return true


# --- Eventos del rival ----------------------------------------------------------------------------

## El servidor confirmó que `color` tosió o tiró una pieza.
func _on_rival_event(color: int, event_id: StringName) -> void:
	var def := director.get_def(event_id)
	var intensity := def.intensity if def != null else 0.5
	var is_rival := color == root.rival_color
	var pos: Vector3 = root.avatar.head.global_position if is_rival else root.player.global_position
	match event_id:
		&"cough":
			stage.play_sound(&"cough", pos, 2.0)
			if is_rival:
				root.avatar.play_cough()
		&"drop_piece":
			if is_rival:
				root.avatar.play_drop_piece()
				stage.drop_piece(color)
				pos = Vector3(0.6, 0.5, -0.1)
			else:
				stage.play_sound(&"clack", Vector3(0.4, 0.0, 0.7), 2.0)
				pos = Vector3(0.4, 0.0, 0.7)
	# Lo oye (y ve) el otro lado: su bot puede voltear.
	var other_bot: BotController = root.auto_bot if is_rival else root.rival_bot
	if other_bot != null:
		other_bot.notice_event(pos, intensity)
