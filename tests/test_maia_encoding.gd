extends TestCase
## Compara la codificación en GDScript con lo que produjo maia3 (PyTorch)
## en tests/fixtures/maia3_reference.json (generado por tools/export_maia3_onnx.py).

const FIXTURE := "res://tests/fixtures/maia3_reference.json"


func _casos() -> Array:
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not (datos is Dictionary):
		failures.append("no se pudo leer " + FIXTURE)
		return []
	return datos["casos"]


func _tableros(caso: Dictionary) -> Array:
	var out := []
	for fen in caso["fens"]:
		out.append(BoardState.from_fen(fen))
	return out


func test_vocabulario() -> void:
	check_eq(MaiaEncoding.moves().size(), 4352, "tamaño del vocabulario")
	check_eq(MaiaEncoding.move_to_index(MaiaEncoding.moves()[100]), 100, "ida y vuelta")
	check_eq(MaiaEncoding.move_to_index("a7a8q"), 4096, "primera coronación")
	check_eq(MaiaEncoding.move_to_index("h7h8n"), 4351, "última coronación")


func test_elo_continuo() -> void:
	check_eq(MaiaEncoding.elo_value(1537.0), 1537.0, "sin categorías")
	check_eq(MaiaEncoding.elo_value(-20.0), 0.0, "mínimo")
	check_eq(MaiaEncoding.elo_value(9000.0), 5000.0, "máximo")


func test_encode_history_exacto() -> void:
	var casos := _casos()
	check(casos.size() >= 8, "hay casos de referencia")
	for c in casos:
		var t := MaiaEncoding.encode_history(_tableros(c))
		var ref: Array = c["tokens"]
		check_eq(t.size(), 64 * 96, "longitud " + c["jugadas"])
		check_eq(t.size(), ref.size(), "longitud igual al fixture " + c["jugadas"])
		var difs := 0
		for i in mini(t.size(), ref.size()):
			if t[i] != float(ref[i]):
				difs += 1
		check_eq(difs, 0, "valores distintos en '%s' (%s)" % [c["jugadas"], c["inicio"]])


func test_indices_de_jugadas_legales() -> void:
	for c in _casos():
		var b := BoardState.from_fen(c["fens"][-1])
		var mapa := MaiaEncoding.legal_index_map(b)
		var ucis: Array = mapa.values()
		ucis.sort()
		var esperado: Array = c["legal_uci"]
		check_eq(ucis, esperado, "jugadas legales " + c["fens"][-1])
		for e in c["elos"]:
			for t in e["top5"]:
				check(ucis.has(t["uci"]), "top5 %s legal en %s" % [t["uci"], c["fens"][-1]])


func test_mirror_uci() -> void:
	check_eq(MaiaEncoding.mirror_uci("e2e4"), "e7e5")
	check_eq(MaiaEncoding.mirror_uci("a7a8q"), "a2a1q")


## Reproduce una partida pidiendo política solo en los turnos de `color` (como un bot)
## y comprueba que el historial reconstruido coincide con las posiciones reales.
## Con `estricto` falso solo se exige la posición actual: algunas intermedias son
## ambiguas (d7-d5 + exd6 al paso da lo mismo que d7-d6 + exd6) y se acepta cualquiera.
func _reconstruye(jugadas: Array, color: int, estricto: bool = true) -> void:
	var b := BoardState.start_position()
	var reales: Array = [b.clone()]
	var h := MaiaHistory.new()
	for u in jugadas:
		if b.side_to_move == color:
			var obtenido := h.observe(b)
			var n := mini(reales.size(), 8)
			check_eq(obtenido.size(), n, "tamaño del historial en ply %d" % (reales.size() - 1))
			for i in (range(n) if estricto else [n - 1]):
				var real: BoardState = reales[reales.size() - n + i]
				var rec: BoardState = obtenido[obtenido.size() - n + i]
				check_eq(rec.position_key(), real.position_key(), "posición %d en ply %d" % [i, reales.size() - 1])
		var m := ChessRules.find_legal(b, ChessMove.from_uci(u))
		ChessRules.apply_move(b, m)
		reales.append(b.clone())


func test_historial_se_reconstruye_para_un_bot() -> void:
	var jug := "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1 f8c5 d2d3 d7d6 c1g5 h7h6 g5h4 e8g8 b1c3 c8e6".split(" ")
	_reconstruye(Array(jug), ChessPiece.WHITE)
	_reconstruye(Array(jug), ChessPiece.BLACK)


func test_historial_con_captura_al_paso_y_enroque() -> void:
	var jug := "e2e4 a7a6 e4e5 d7d5 e5d6 g8f6 g1f3 b8c6 f1e2 e7d6 e1g1 c8e6".split(" ")
	_reconstruye(Array(jug), ChessPiece.WHITE, false)
	_reconstruye(Array(jug), ChessPiece.BLACK, false)


func test_historial_cerebro_compartido_por_ambos_bandos() -> void:
	var b := BoardState.start_position()
	var h := MaiaHistory.new()
	for u in "e2e4 e7e5 g1f3 b8c6".split(" "):
		h.observe(b)
		ChessRules.apply_move(b, ChessRules.find_legal(b, ChessMove.from_uci(u)))
	var trail := h.observe(b)
	check_eq(trail.size(), 5, "una posición por jugada")
	check_eq(h.observe(b).size(), 5, "pedir la misma posición no duplica")


func test_historial_tolera_cambios_por_fuera_de_las_reglas() -> void:
	var b := BoardState.start_position()
	var h := MaiaHistory.new()
	h.observe(b)
	# Una trampa mueve piezas sin jugada legal que lo explique.
	var c := BoardState.from_fen("rnbqkbnr/pppppppp/8/8/8/3N4/PPPPPPPP/R1BQKBNR w KQkq - 0 1")
	var trail := h.observe(c)
	check_eq(trail.back().position_key(), c.position_key(), "termina en la posición actual")
	check(trail.size() <= MaiaEncoding.HISTORIA, "no pasa de 8 posiciones")
	# La partida nueva reinicia.
	check_eq(h.observe(BoardState.start_position()).size(), 1, "partida nueva")


func test_maia_brain_sin_web_usa_respaldo() -> void:
	var brain := MaiaBrain.new()
	var policy: Dictionary = await brain.get_policy(BoardState.start_position(), 1500, 1500)
	check_eq(policy.size(), 20, "20 jugadas legales iniciales")
	var total := 0.0
	for k in policy:
		total += policy[k]
	check(absf(total - 1.0) < 1e-4, "la política suma 1")
