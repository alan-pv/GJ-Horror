extends SceneTree
## Benchmark del flujo "soltar la jugada -> respuesta del bot" (hilo principal).
##   godot --headless --path . --script res://tools/bench_turn.gd
## Mide en ms (peor de varias repeticiones) cada pieza que corre en el frame del
## clic: generación de jugadas legales, BeginnerHelper.check_move,
## FallbackBrain.get_policy y MaiaHistory.observe (reconstrucción de la jugada intermedia).

const POSITIONS := {
	"1 apertura (inicial)": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
	"2 apertura (1.e4 e5 2.Nf3 Nc6)": "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
	"3 medio juego (Kiwipete)": "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
	"4 medio juego (italiana)": "r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 0 6",
	"5 tactica (pos4)": "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
	"6 tactica (pos5)": "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
}
const REPS := 5


func _init() -> void:
	print("(ms; helper y 'cerebro total' en el peor de %d repeticiones; 'h.cach' = helper con precalculo; 'trozo' = lo peor que corre en UN fotograma)" % REPS)
	print("%-32s %7s %7s %7s %7s %9s %7s %7s %7s %7s" % ["posicion", "legal", "helper", "h.med", "h.cach", "cerebro", "trozo", "history", "maia", "trampa"])
	var worst_frame := 0.0
	var defs: Array = []
	for id in ["own", "enemy", "steal"]:
		defs.append(load("res://data/cheats/%s.tres" % id))
	for name in POSITIONS:
		var b := BoardState.from_fen(POSITIONS[name])
		var moves := ChessRules.legal_moves(b)
		var legal_ms := _time(func(): ChessRules.legal_moves(b))
		var mv: ChessMove = moves[0]
		var helper_ms := _time(func(): BeginnerHelper.check_move(b, mv, 150))
		var helper_med := _median(func(): BeginnerHelper.check_move(b, mv, 150))
		BeginnerHelper.precompute_async(b, false)  # el análisis que haría el cliente mientras el jugador piensa
		var helper_cached := _median(func(): BeginnerHelper.check_move(b, mv, 150))
		BeginnerHelper._cache_key = ""
		var brain := FallbackBrain.new()
		var policy_ms := _time(func(): brain.get_policy_sync(b, 1200, 1200))
		var chunk_ms := _brain_chunk(b)
		var hist_ms := _history_cost(b)
		var maia_ms := _time(func(): _maia_request(b))
		var rng := RandomNumberGenerator.new()
		var cheat_ms := _time(func(): CheatPlanner.plan(b, b.side_to_move, defs, rng))
		print("%-32s %7.2f %7.2f %7.2f %7.2f %9.2f %7.2f %7.2f %7.2f %7.2f" % [name, legal_ms, helper_ms, helper_med, helper_cached, policy_ms, chunk_ms, hist_ms, maia_ms, cheat_ms])
		worst_frame = maxf(worst_frame, maxf(helper_ms, maxf(chunk_ms, maxf(hist_ms, cheat_ms))))
	print("peor trabajo de script en un solo fotograma (helper sincrono / trozo del bot / historia): %.2f ms" % worst_frame)
	quit()


## Trabajo web previo al envío a Maia (jugadas, historia, tensor).
func _maia_request(b: BoardState) -> void:
	var mapa := MaiaEncoding.legal_index_map(b)
	var h := MaiaHistory.new()
	var posiciones := h.observe(b)
	JSON.stringify({"tokens": Array(MaiaEncoding.encode_history(posiciones)), "legal": mapa.keys()})


## Lo peor que ocupa un fotograma al calcular la política por trozos: el presupuesto
## de FallbackBrain.SLICE_USEC más la jugada raíz que lo rebasa (se mide la mayor).
func _brain_chunk(b: BoardState) -> float:
	var work := b.clone()
	var us := work.side_to_move
	var e0 := FallbackBrain.evaluate(work, us)
	var worst_move := 0.0
	var acc := 0.0
	var worst_chunk := 0.0
	for mv in ChessRules.legal_moves_int(work):
		var t0 := Time.get_ticks_usec()
		FallbackBrain._score_move(work, mv, us, e0)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst_move = maxf(worst_move, dt)
		acc += dt
		if acc * 1000.0 > FallbackBrain.SLICE_USEC:
			worst_chunk = maxf(worst_chunk, acc)
			acc = 0.0
	return maxf(worst_chunk, acc)


func _median(f: Callable) -> float:
	var xs: Array[float] = []
	for i in 9:
		var t0 := Time.get_ticks_usec()
		f.call()
		xs.append((Time.get_ticks_usec() - t0) / 1000.0)
	xs.sort()
	return xs[4]


## Peor de REPS ejecuciones, en ms.
func _time(f: Callable) -> float:
	var worst := 0.0
	for i in REPS:
		var t0 := Time.get_ticks_usec()
		f.call()
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	return worst


## Coste de MaiaHistory.observe cuando entre dos peticiones pasaron dos jugadas.
func _history_cost(b: BoardState) -> float:
	var legal := ChessRules.legal_moves(b)
	if legal.is_empty():
		return 0.0
	var prev := b.clone()
	var mid := b.clone()
	ChessRules.apply_move(mid, legal[0])
	var replies := ChessRules.legal_moves(mid)
	if replies.is_empty():
		return 0.0
	var cur := mid.clone()
	ChessRules.apply_move(cur, replies[replies.size() / 2])
	var worst := 0.0
	for i in REPS:
		var h := MaiaHistory.new()
		h.trail = [prev.clone()]
		var t0 := Time.get_ticks_usec()
		h.observe(cur)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	return worst
