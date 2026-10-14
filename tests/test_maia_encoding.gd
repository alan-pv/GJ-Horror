extends TestCase
## Compara la codificación en GDScript con lo que produjo maia2 (PyTorch)
## en tests/fixtures/maia2_reference.json (generado por tools/export_maia2_onnx.py).

const FIXTURE := "res://tests/fixtures/maia2_reference.json"


func _casos() -> Array:
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not (datos is Dictionary):
		failures.append("no se pudo leer " + FIXTURE)
		return []
	return datos["casos"]


func test_vocabulario() -> void:
	check_eq(MaiaEncoding.moves().size(), 1880, "tamaño del vocabulario")
	check_eq(MaiaEncoding.move_to_index(MaiaEncoding.moves()[100]), 100, "ida y vuelta")


func test_elo_category() -> void:
	for par in [[400, 0], [1099, 0], [1100, 1], [1199, 1], [1200, 2], [1500, 5], [1999, 9], [2000, 10], [2800, 10]]:
		check_eq(MaiaEncoding.elo_category(par[0]), par[1], "elo %d" % par[0])
	for c in _casos():
		check_eq(MaiaEncoding.elo_category(int(c["elo_self"])), int(c["cat_self"]), "cat_self " + c["fen"])
		check_eq(MaiaEncoding.elo_category(int(c["elo_oppo"])), int(c["cat_oppo"]), "cat_oppo " + c["fen"])


func test_encode_board_exacto() -> void:
	var casos := _casos()
	check(casos.size() >= 6, "hay casos de referencia")
	for c in casos:
		var b := BoardState.from_fen(c["fen"])
		var t := MaiaEncoding.encode_board(b)
		var ref: Array = c["board"]
		check_eq(t.size(), ref.size(), "longitud " + c["fen"])
		var difs := 0
		for i in mini(t.size(), ref.size()):
			if t[i] != float(ref[i]):
				difs += 1
		check_eq(difs, 0, "casillas distintas en " + c["fen"])


func test_indices_de_jugadas_legales() -> void:
	for c in _casos():
		var b := BoardState.from_fen(c["fen"])
		var mapa := MaiaEncoding.legal_index_map(b)
		var ucis: Array = mapa.values()
		ucis.sort()
		var esperado: Array = c["legal_uci"]
		check_eq(ucis, esperado, "jugadas legales " + c["fen"])
		# Las 5 mejores de PyTorch deben tener índice en el mapa.
		for t in c["top5"]:
			check(ucis.has(t["uci"]), "top5 %s legal en %s" % [t["uci"], c["fen"]])


func test_mirror_uci() -> void:
	check_eq(MaiaEncoding.mirror_uci("e2e4"), "e7e5")
	check_eq(MaiaEncoding.mirror_uci("a7a8q"), "a2a1q")


func test_maia_brain_sin_web_usa_respaldo() -> void:
	var brain := MaiaBrain.new()
	var policy: Dictionary = await brain.get_policy(BoardState.start_position(), 1500, 1500)
	check_eq(policy.size(), 20, "20 jugadas legales iniciales")
	var total := 0.0
	for k in policy:
		total += policy[k]
	check(absf(total - 1.0) < 1e-4, "la política suma 1")
