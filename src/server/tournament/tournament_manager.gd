class_name TournamentManager
extends RefCounted
## Lógica pura del torneo (sin nodos): emparejamiento aleatorio, descansos
## ("bye") cuando el número es impar, rondas sincronizadas, final a dos
## partidas con colores invertidos y desempate por tiempo sobrante, campeón
## y torneo nuevo. No sabe nada de la vista: quien la use informa de los
## resultados con `report_result()` y llama a `finish_round()` y `start_round()`.
##
## Ciclo: `start_round()` -> (partidas) `report_result()` -> `round_complete()`
## -> `finish_round()` -> `start_round()` ... hasta que `champion_id >= 0`.

enum Phase { IDLE, PLAYING, ROUND_DONE, FINISHED }

const BOT_NAMES := [
	"Arthur", "Beatrice", "Cosmo", "Dahlia", "Ernest", "Fiona", "Gideon", "Hilda",
	"Ignatius", "Juniper", "Lazarus", "Mirabel", "Nigel", "Ophelia", "Percival", "Rosalind",
	"Sebastian", "Thaddeus", "Ulysses", "Valerie", "Wendell", "Xanthe", "Yorick", "Zelda",
	"Barnaby", "Cordelia", "Desmond", "Eloise", "Fletcher", "Griselda", "Horace", "Imogen",
]

var rng := RandomNumberGenerator.new()
var player_count: int
## sessions[id]: las sesiones sobreviven a las partidas (llevan las advertencias).
var sessions: Array[PlayerSession] = []
## Elo de cada jugador (sesga a los bots de las mesas de fondo y la personalidad).
var elo: Array[int] = []
var human_id: int = 0
## Jugadores aún en el torneo.
var alive: Array[int] = []
## Número de ronda (la final cuenta como ronda; sus dos partidas comparten número).
var round_no: int = 0
var phase: Phase = Phase.IDLE
## Partidas de la ronda en curso (en la final, solo la partida en juego).
var games: Array[TournamentGame] = []
## Jugadores que pasan la ronda sin jugar.
var byes: Array[int] = []
## Mesa de cada descanso: {id: mesa}.
var bye_tables: Dictionary = {}
var bye_counts: Dictionary = {}
var champion_id: int = -1
## Partidas ya terminadas de la final.
var final_games: Array[TournamentGame] = []
var is_final: bool = false
## Registro de eliminados: {id, round, table, reason}.
var eliminated_log: Array[Dictionary] = []
## Cuántos jugadores había al empezar cada ronda.
var round_sizes: Array[int] = []


func _init(p_player_count: int = 32, seed_value: int = -1, human_name: String = "You") -> void:
	player_count = maxi(p_player_count, 2)
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_populate(human_name)


func _populate(human_name: String) -> void:
	sessions.clear()
	elo.clear()
	var names := BOT_NAMES.duplicate()
	for i in names.size():
		var j := rng.randi_range(i, names.size() - 1)
		var t: String = names[i]
		names[i] = names[j]
		names[j] = t
	for id in player_count:
		var is_human := id == human_id
		var pname := human_name
		if not is_human:
			pname = str(names[(id - 1) % names.size()])
			if id > names.size():
				pname += " %d" % (((id - 1) / names.size()) + 1)
		sessions.append(PlayerSession.new(id, pname, not is_human))
		elo.append(1300 if is_human else rng.randi_range(900, 1700))
	_reset_state()


func _reset_state() -> void:
	alive.clear()
	for id in player_count:
		alive.append(id)
		sessions[id].reset_for_tournament()
	round_no = 0
	phase = Phase.IDLE
	games.clear()
	byes.clear()
	bye_tables.clear()
	bye_counts.clear()
	champion_id = -1
	final_games.clear()
	is_final = false
	eliminated_log.clear()
	round_sizes.clear()


## Torneo nuevo con los mismos jugadores: advertencias a cero (cola automática).
func new_tournament() -> void:
	_reset_state()


func is_alive(id: int) -> bool:
	return alive.has(id)


func remaining_count() -> int:
	return alive.size()


func is_finished() -> bool:
	return phase == Phase.FINISHED


func player_name(id: int) -> String:
	return sessions[id].display_name


# --- Rondas -------------------------------------------------------------------

## Arma la ronda siguiente (o la segunda partida de la final). Devuelve las partidas.
func start_round() -> Array[TournamentGame]:
	assert(phase != Phase.PLAYING and phase != Phase.FINISHED, "ronda en curso o torneo terminado")
	games = []
	byes = []
	bye_tables = {}
	if alive.size() == 2:
		_start_final_game()
	else:
		round_no += 1
		is_final = false
		round_sizes.append(alive.size())
		var pool := alive.duplicate()
		_shuffle(pool)
		if pool.size() % 2 == 1:
			# Descansa quien menos veces haya descansado.
			var best := -1
			var best_n := 1 << 30
			for id in pool:
				var n: int = bye_counts.get(id, 0)
				if n < best_n:
					best_n = n
					best = id
			pool.erase(best)
			byes.append(best)
			bye_counts[best] = bye_counts.get(best, 0) + 1
		for i in range(0, pool.size(), 2):
			games.append(_random_colors(pool[i], pool[i + 1]))
	_assign_tables()
	phase = Phase.PLAYING
	return games


func _random_colors(a: int, b: int) -> TournamentGame:
	return TournamentGame.new(a, b) if rng.randf() < 0.5 else TournamentGame.new(b, a)


func _start_final_game() -> void:
	if final_games.is_empty():
		round_no += 1
		round_sizes.append(2)
		is_final = true
		games.append(_random_colors(alive[0], alive[1]))
	else:
		# Segunda partida: colores invertidos.
		var first := final_games[0]
		games.append(TournamentGame.new(first.black, first.white, 2))


## Mesas fijas del salón (`HallLayout`): el humano siempre en `HUMAN_TABLE`; las
## demás partidas y descansos, en las mesas más cercanas a él primero.
func _assign_tables() -> void:
	var slots: Array[int] = HallLayout.tables_by_distance()
	slots.erase(HallLayout.HUMAN_TABLE)
	var human_game := game_of(human_id)
	if human_game != null:
		human_game.table = HallLayout.HUMAN_TABLE
	elif byes.has(human_id):
		bye_tables[human_id] = HallLayout.HUMAN_TABLE
	for g in games:
		if g == human_game:
			continue
		g.table = slots.pop_front() if not slots.is_empty() else TournamentGame.TABLE_NONE
	for id in byes:
		if id == human_id:
			continue
		bye_tables[id] = slots.pop_front() if not slots.is_empty() else TournamentGame.TABLE_NONE


## Fuerza el color del humano en su partida (solo depuración, antes de jugarla).
func force_human_color(color: int) -> void:
	var g := game_of(human_id)
	if g != null and not g.done and g.color_of(human_id) != color:
		var t := g.white
		g.white = g.black
		g.black = t


## La partida en curso del jugador, o null si descansa / no juega.
func game_of(id: int) -> TournamentGame:
	for g in games:
		if g.involves(id):
			return g
	return null


func pending_games() -> Array[TournamentGame]:
	var out: Array[TournamentGame] = []
	for g in games:
		if not g.done:
			out.append(g)
	return out


## Registra el resultado. `time_left` = [segundos blancas, segundos negras].
func report_result(game: TournamentGame, winner_color: int, reason: String = "", time_left: PackedFloat64Array = [0.0, 0.0]) -> void:
	assert(games.has(game) and not game.done, "resultado de una partida desconocida o repetida")
	game.done = true
	game.winner_color = winner_color
	game.reason = reason
	game.time_left = time_left
	if pending_games().is_empty():
		phase = Phase.ROUND_DONE


func round_complete() -> bool:
	return phase == Phase.ROUND_DONE


## Cierra la ronda: elimina a los perdedores y, si era la final y ya se
## jugaron las dos partidas, decide el campeón. Devuelve
## {eliminated: [{id, table}], advanced: [ids], champion: id | -1, final_continues: bool}.
func finish_round() -> Dictionary:
	assert(phase == Phase.ROUND_DONE, "la ronda no ha terminado")
	var result := {"eliminated": [], "advanced": [], "champion": -1, "final_continues": false}
	if is_final:
		final_games.append(games[0])
		if final_games.size() < 2:
			result.final_continues = true
			result.advanced = alive.duplicate()
			phase = Phase.IDLE
			return result
		var champ := _final_winner()
		var loser: int = alive[0] if alive[1] == champ else alive[1]
		_eliminate(loser, games[0].table, "lost the final")
		result.eliminated.append({"id": loser, "table": games[0].table})
		champion_id = champ
		result.champion = champ
		result.advanced = [champ]
		phase = Phase.FINISHED
		return result
	for g in games:
		var l := g.loser_id()
		_eliminate(l, g.table, g.reason)
		result.eliminated.append({"id": l, "table": g.table})
		result.advanced.append(g.winner_id())
	for id in byes:
		result.advanced.append(id)
	phase = Phase.IDLE
	return result


## Resumen de la final: {wins: {id: n}, time: {id: segundos sobrantes}}.
func final_summary() -> Dictionary:
	var wins := {}
	var time := {}
	for g in final_games:
		for id in [g.white, g.black]:
			wins[id] = wins.get(id, 0) + (1 if g.winner_id() == id else 0)
			time[id] = time.get(id, 0.0) + g.time_left_of(id)
	return {"wins": wins, "time": time}


## Ganador de la final: más victorias; con 1-1, más tiempo sobrante sumado.
func _final_winner() -> int:
	var a: int = alive[0]
	var b: int = alive[1]
	var s := final_summary()
	if s.wins[a] != s.wins[b]:
		return a if s.wins[a] > s.wins[b] else b
	if not is_equal_approx(s.time[a], s.time[b]):
		return a if s.time[a] > s.time[b] else b
	return a if rng.randf() < 0.5 else b


func _eliminate(id: int, table: int, reason: String) -> void:
	alive.erase(id)
	eliminated_log.append({"id": id, "round": round_no, "table": table, "reason": reason})


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- Utilidades ---------------------------------------------------------------

## Probabilidad de que `a` gane a `b` según el Elo (logística).
func win_chance(a: int, b: int) -> float:
	return 1.0 / (1.0 + pow(10.0, (elo[b] - elo[a]) / 400.0))


## Resuelve una partida de forma estadística (pruebas y avance rápido).
func simulate_result(game: TournamentGame) -> void:
	var wc := ChessPiece.WHITE if rng.randf() < win_chance(game.white, game.black) else ChessPiece.BLACK
	var times: PackedFloat64Array = [rng.randf_range(0.0, 120.0), rng.randf_range(0.0, 120.0)]
	report_result(game, wc, "simulated", times)


## Simula todas las partidas pendientes de la ronda. Si `human_wins`, el
## humano gana las suyas (para saltar rondas en las pruebas visuales).
func simulate_round(human_wins: bool = false) -> void:
	for g in pending_games():
		if human_wins and g.involves(human_id):
			var t: PackedFloat64Array = [60.0, 60.0]
			report_result(g, g.color_of(human_id), "simulated", t)
		else:
			simulate_result(g)


## Número de rondas que durará un torneo de `n` jugadores (la final incluida).
static func rounds_for(n: int) -> int:
	var r := 0
	while n > 2:
		n = (n + 1) / 2
		r += 1
	return r + 1


## Nombre de la ronda en curso para la interfaz.
func round_label() -> String:
	if is_final:
		var no := games[0].game_no if not games.is_empty() else final_games.size() + 1
		return "Final · game %d of 2" % no
	if round_no > 0 and round_no <= round_sizes.size() and round_sizes[round_no - 1] <= 4:
		return "Round %d · Semifinals" % round_no
	return "Round %d" % round_no
