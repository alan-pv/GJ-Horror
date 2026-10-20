extends TestCase
## Entrada del jugador con el diseño "agarra cualquier pieza": enrutado de clics
## (`PieceInteraction`: nivel 0 → jugada, otro nivel → trampa, pila → robo), selección de
## pieza rival, rey ignorado, deselección, mano ocupada, y colores del mapa de calor.
## No necesita nodos ni entrada real: se usa un `MatchServer` sin vista.

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK
const PILE := CheatRules.TO_PILE


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


## Servidor listo con las tres clases de trampa y una interacción del lado de `color`.
func _make(fen: String = BoardState.START_FEN, color: int = W) -> Array:
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	for id in ["own", "enemy", "steal"]:
		cfg.cheats.append(load("res://data/cheats/%s.tres" % id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), fen, 3)
	m.start()
	var pi := PieceInteraction.new()
	pi.setup(m, null, color)
	return [m, pi]


# --- Colores del mapa de calor --------------------------------------------------------------

func test_heat_colors_by_level() -> void:
	var g := BoardView.heat_color(0)
	var o := BoardView.heat_color(1)
	var r := BoardView.heat_color(2)
	check(g.g > g.r and g.g > g.b, "nivel 0 verde")
	check(o.r > 0.9 and o.g > 0.4 and o.g < 0.75 and o.b < 0.3, "nivel 1 naranja")
	check(r.r > 0.8 and r.g < 0.3 and r.b < 0.3, "nivel 2 rojo")
	check(BoardView.heat_color(3).r < r.r, "nivel 3 rojo más oscuro")
	check(BoardView.heat_color(4).r < BoardView.heat_color(3).r, "nivel 4 más oscuro todavía")
	check(absf(g.a - 0.55) < 0.001, "opacidad nivel 0")
	check(absf(o.a - 0.45) < 0.001, "opacidad nivel 1")
	check(absf(r.a - 0.30) < 0.001, "opacidad nivel 2")
	check(absf(BoardView.heat_color(3).a - 0.12) < 0.001, "opacidad nivel 3")
	check(absf(BoardView.heat_color(4).a - 0.04) < 0.001, "opacidad nivel 4")
	var prev := 1.0
	for lv in 12:
		var a := BoardView.heat_color(lv).a
		check(a <= prev, "la opacidad nunca sube con el nivel")
		prev = a
	check_eq(BoardView.heat_color(9), BoardView.heat_color(4), "los niveles altos usan el último")
	check_eq(BoardView.heat_color(-3), BoardView.heat_color(0), "negativos como 0")


func test_pile_zone_geometry() -> void:
	var cx := BoardView.PILE_X
	var cz := BoardView.PILE_ZONE_Z
	check(BoardView.zone_hit(Vector3(cx, 0, cz), true), "centro de la pila cercana")
	check(not BoardView.zone_hit(Vector3(cx, 0, cz), false), "no es la pila lejana")
	check(BoardView.zone_hit(Vector3(cx, 0, -cz), false), "centro de la pila lejana")
	check(not BoardView.zone_hit(Vector3(0.0, 0, 0.0), true), "el centro del tablero no es la pila")
	check(not BoardView.zone_hit(Vector3(cx + 0.3, 0, cz), true), "lejos en X")
	# Las casillas del tablero (±0,22 m) quedan fuera de la zona.
	check(not BoardView.zone_hit(Vector3(0.22, 0, 0.22), true), "esquina del tablero fuera")


# --- Enrutado de clics -----------------------------------------------------------------------

func test_level_zero_click_submits_move() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	check_eq(pi.click(_sq("e2")), "select", "elegir el peón")
	check_eq(pi.level_of(_sq("e4")), 0, "e4 es jugada legal (verde)")
	check_eq(pi.click(_sq("e4")), "move", "nivel 0 es una jugada")
	check_eq(m.ply, 1, "el servidor registró la jugada")
	check_eq(m.board.squares[_sq("e4")], ChessPiece.make(W, ChessPiece.PAWN), "peón en e4")
	check(not m.is_hand_busy(W), "no es una trampa")
	check_eq(pi.selected, -1, "se suelta la selección")


func test_other_level_click_starts_cheat() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	pi.click(_sq("e2"))
	check(pi.level_of(_sq("e5")) >= 1, "e5 es trampa")
	check_eq(pi.click(_sq("e5")), "cheat", "nivel > 0 es una trampa")
	check(m.is_hand_busy(W), "la mano está en una trampa")
	check_eq(m.active_cheat(W).cheat_id, &"own", "clase propia")
	check_eq(m.active_cheat(W).to, _sq("e5"), "destino e5")
	check_eq(pi.click(_sq("d2")), "busy", "con la mano ocupada no se elige")
	check_eq(pi.selected, -1, "y no hay selección")


func test_legal_capture_is_level_zero() -> void:
	var x := _make("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	pi.click(_sq("e4"))
	check_eq(pi.level_of(_sq("d5")), 0, "la captura legal es verde")
	check_eq(pi.click(_sq("d5")), "move", "y se juega como jugada")
	check_eq(m.board.squares[_sq("d5")], ChessPiece.make(W, ChessPiece.PAWN), "capturó")


func test_enemy_piece_selects_and_pile_steals() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	check_eq(pi.click(_sq("a7")), "select", "una pieza rival se puede agarrar")
	check(pi.levels.has(PILE), "tiene la pila como destino")
	check_eq(pi.level_of(PILE), CheatRules.PILE_LEVEL, "nivel de la pila")
	check(pi.level_of(_sq("a6")) >= 1, "o moverla a otra casilla (trampa)")
	check_eq(pi.click(PILE), "pile", "soltar en la pila roba")
	var c: Dictionary = m.active_cheat(W)
	check_eq(c.cheat_id, &"steal", "clase robo")
	check_eq(c.to, PILE, "destino TO_PILE")
	check_eq(c.from, _sq("a7"), "origen a7")


func test_pile_click_without_enemy_selection_does_nothing() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	pi.click(_sq("e2"))
	check(not pi.levels.has(PILE), "una pieza propia no tiene pila")
	check_eq(pi.click(PILE), "deselect", "la pila no es destino de una pieza propia")
	check(not m.is_hand_busy(W), "sin trampa")
	check_eq(pi.click(PILE), "deselect", "sin selección tampoco")


func test_enemy_piece_to_square_is_enemy_cheat() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	pi.click(_sq("e7"))
	check_eq(pi.click(_sq("e5")), "cheat", "mover pieza rival")
	check_eq(m.active_cheat(W).cheat_id, &"enemy", "clase rival")


func test_king_is_ignored() -> void:
	var x := _make()
	var pi: PieceInteraction = x[1]
	check_eq(pi.click(_sq("e1")), "reject", "el rey propio no se agarra")
	check_eq(pi.click(_sq("e8")), "reject", "ni el rival")
	check_eq(pi.selected, -1, "sin selección")
	pi.click(_sq("e2"))
	check_eq(pi.click(_sq("e1")), "reject", "con una pieza elegida tampoco")
	check_eq(pi.selected, _sq("e2"), "la selección se mantiene")


func test_deselect_and_change_selection() -> void:
	var x := _make()
	var pi: PieceInteraction = x[1]
	pi.click(_sq("e2"))
	check_eq(pi.click(_sq("d2")), "select", "otra pieza propia cambia la selección")
	check_eq(pi.selected, _sq("d2"), "ahora d2")
	check_eq(pi.click(_sq("d7")), "select", "una pieza rival también cambia la selección")
	check_eq(pi.selected, _sq("d7"), "ahora d7")
	check_eq(pi.click(_sq("d7")), "deselect", "clic en la misma la suelta")
	check_eq(pi.selected, -1, "sin selección")
	pi.click(_sq("d2"))
	check_eq(pi.click(-1), "deselect", "clic en el vacío (fuera del tablero) la suelta")
	pi.click(_sq("d2"))
	pi.deselect()
	check(pi.levels.is_empty(), "deselect limpia el mapa")
	check_eq(pi.click(_sq("e4")), "none", "casilla vacía sin selección: nada")


func test_invalid_square_gives_server_reason() -> void:
	var x := _make("4k3/p7/8/8/8/8/8/4K3 w - - 0 1")
	var pi: PieceInteraction = x[1]
	var said: Array = []
	pi.subtitle = func(t: String, _s: float) -> void: said.append(t)
	check_eq(pi.click(_sq("e1")), "reject", "rey")
	check(said.size() == 1 and said[0].contains("king"), "subtítulo del rey")
	pi.click(_sq("a7"))
	check_eq(pi.click(_sq("a1")), "reject", "un peón no puede quedar en la primera fila")
	check(said.back().begins_with("...no, not that"), "subtítulo con motivo")
	check_eq(pi.selected, _sq("a7"), "la pieza sigue elegida")


func test_own_piece_off_turn_has_only_cheat_levels() -> void:
	var x := _make(BoardState.START_FEN, B)
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	check_eq(pi.click(_sq("e7")), "select", "se agarra fuera de turno")
	for sq in pi.levels:
		check(pi.levels[sq] >= 1, "fuera de turno no hay verdes")
	check_eq(pi.click(_sq("e6")), "cheat", "incluso e6 es trampa fuera de turno")
	check(m.is_hand_busy(B), "mano de negras ocupada")
	check(not pi.levels.has(_sq("e6")), "selección limpia tras empezar")


func test_busy_hand_or_locked_input_blocks_clicks() -> void:
	var x := _make()
	var pi: PieceInteraction = x[1]
	var locked := [false]
	pi.player_ok = func() -> bool: return not locked[0]
	check_eq(pi.click(_sq("e2")), "select", "libre")
	locked[0] = true
	check_eq(pi.click(_sq("e4")), "busy", "mano o entrada ocupadas: no hace nada")
	check(not x[0].is_hand_busy(W) and x[0].ply == 0, "no se jugó")
	locked[0] = false
	check_eq(pi.click(_sq("e4")), "move", "al liberarse sigue funcionando")


func test_selection_drops_when_piece_moves() -> void:
	var x := _make()
	var m: MatchServer = x[0]
	var pi: PieceInteraction = x[1]
	pi.click(_sq("d7"))
	check_eq(pi.selected, _sq("d7"), "rival elegida")
	# Una trampa del rival la mueve de sitio: el servidor avisa y la selección se suelta.
	m.board.squares[_sq("d5")] = m.board.squares[_sq("d7")]
	m.board.squares[_sq("d7")] = ChessPiece.NONE
	m.state_changed.emit()
	check_eq(pi.selected, -1, "la pieza ya no está donde estaba")
