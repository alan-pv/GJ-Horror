class_name ArbiterModule
extends Node
## Módulo del árbitro verdugo: crea el `Arbiter` y lo asigna a `root.arbiter`, avisa al
## servidor cuando está cerca de la mesa del humano (`set_arbiter_near`: las trampas en
## curso cuentan como vistas) y atiende las ejecuciones de las mesas de fondo si nadie más
## las pide. `GameRoot` le encarga las acusaciones y las ejecuciones del humano y del rival.
##
## Argumentos de depuración (después de `--`):
##   --force-execution=mesa,asiento[,modo][;...]  ejecuta a ese asiento (0 = blancas, 1 = negras);
##                        modo opcional de reacción: beg, cry, frozen, sob
##   --force-at=S         segundos de partida antes de pedirla (3)
##   --lose-now           el humano pierde a los `--force-at` s (ejecución en primera persona)
##   --win-now            el humano gana a los `--force-at` s (ejecutan al rival)
##   --arb-start=x,z      posición inicial del árbitro
##                        (para capturas mientras el salón no use la cuadrícula)

## Radio (m) desde el centro de la mesa del humano en que el árbitro cuenta como "cerca".
const NEAR_RADIUS := 2.0
## Distancia (m) al centro de la mesa del humano a la que el rival lo ve pasar de reojo, y
## espera mínima (s) entre dos avisos (`Distraction` tipo `arbiter_pass`).
const GLANCE_RADIUS := 3.6
const GLANCE_COOLDOWN := 18.0

var root: GameRoot
var arbiter: Arbiter

var _active_key: String = "?"
var _near: bool = false
var _glance_in: bool = false
var _glance_ready: float = 0.0
var _time: float = 0.0
var _forced: Array[Dictionary] = []
var _force_at: float = 3.0
var _lose_now: bool = false
var _win_now: bool = false


func install(p_root: GameRoot) -> void:
	root = p_root
	name = "ModuloArbitro"
	var args := root.get_args()
	arbiter = Arbiter.new()
	root.add_child(arbiter)
	arbiter.setup(root)
	root.arbiter = arbiter
	if args.has("arb-start"):
		var p := str(args["arb-start"]).split(",")
		if p.size() == 2:
			arbiter.position = Vector3(float(p[0]), 0.0, float(p[1]))
	# Respaldo: si nadie pide la ejecución de una mesa de fondo, la pide este módulo.
	root.table_eliminated.connect(_on_table_eliminated)
	_force_at = float(args.get("force-at", 3.0))
	_lose_now = args.has("lose-now")
	_win_now = args.has("win-now")
	if args.has("force-execution"):
		for item in str(args["force-execution"]).split(";"):
			var f := item.split(",")
			if f.size() >= 2:
				_forced.append({"table": int(f[0]), "seat": int(f[1]), "mode": f[2] if f.size() > 2 else ""})


func _on_table_eliminated(table: int, _pos: Vector3, seat: int) -> void:
	arbiter.request_execution(table, seat)


func _process(delta: float) -> void:
	var server := root.server
	if server == null or not server.started:
		return
	_time += delta
	_update_active_tables(server)
	_update_near(server)
	_update_glance(server)
	if _time >= _force_at:
		for f in _forced:
			_run_forced(f)
		_forced.clear()
		if _lose_now:
			_lose_now = false
			root._on_game_over(root.rival_color, "debug resignation")
		if _win_now:
			_win_now = false
			root._on_game_over(root.human_color, "debug resignation")


func _run_forced(f: Dictionary) -> void:
	var mode: String = f.mode
	if mode != "":
		# Crea al condenado con la reacción pedida antes de encolar.
		var modes := {"sob": Condemned.Mode.SOB, "beg": Condemned.Mode.BEG, "cry": Condemned.Mode.CRY,
				"frozen": Condemned.Mode.FROZEN}
		if modes.has(mode):
			arbiter.preset_mode(f.table, f.seat, modes[mode])
	arbiter.request_execution(f.table, f.seat)


## Mientras el árbitro esté cerca de la mesa del humano, las trampas en curso se ven.
func _update_near(server: MatchServer) -> void:
	var near := not server.is_over() and arbiter.is_near(Vector3.ZERO, NEAR_RADIUS)
	if near == _near:
		return
	_near = near
	server.set_arbiter_near(near)
	if root.get_args().has("verbose") or root.get_args().has("autoplay"):
		print("[arbitro %.1f] %s de la mesa (pos=%s)" % [_time, "cerca" if near else "lejos", arbiter.position])


## Aviso `arbiter_pass`: cuando el árbitro entra a `GLANCE_RADIUS` de la mesa del humano (cerca o
## por detrás) quien está sentado puede mirarlo de reojo. No avisa durante su acusación.
func _update_glance(server: MatchServer) -> void:
	var inside := not server.is_over() and not arbiter.accusation_active() \
			and arbiter.is_near(Vector3.ZERO, GLANCE_RADIUS)
	if inside and not _glance_in and _time >= _glance_ready:
		_glance_ready = _time + GLANCE_COOLDOWN
		Distraction.broadcast(self, &"arbiter_pass", arbiter.global_position + Vector3(0.0, 1.5, 0.0))
	_glance_in = inside


## Mesas con partida en juego: la del humano (si no terminó) y las de fondo sin terminar.
## Solo informa al árbitro cuando cambian. Sin torneo no se limita la patrulla.
func active_tables() -> Array[int]:
	var out: Array[int] = []
	if root.server != null and not root.server.is_over():
		out.append(HallLayout.human_table)
	for bg in root.background:
		if bg.table >= 0 and bg.server != null and not bg.server.is_over() and not out.has(bg.table):
			out.append(bg.table)
	return out


func _update_active_tables(server: MatchServer) -> void:
	if root.tgame == null:
		return
	var tables := active_tables()
	var key := str(tables)
	if key == _active_key:
		return
	_active_key = key
	arbiter.set_active_tables(tables)
	if root.get_args().has("verbose"):
		print("[arbitro %.1f] mesas activas: %s" % [_time, key])
