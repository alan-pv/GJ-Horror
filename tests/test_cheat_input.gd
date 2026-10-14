extends TestCase
## Lógica pura de la entrada de trampas: destinos válidos, máquina de estados
## de armado/clic y geometría del árbitro. No necesita nodos ni entrada real.

const W := ChessPiece.WHITE
const B := ChessPiece.BLACK


func _sq(n: String) -> int:
	return ChessPiece.square_from_name(n)


func _def(id: String) -> CheatDef:
	return load("res://data/cheats/%s.tres" % id)


func test_nudge_targets_only_forward() -> void:
	var b := BoardState.start_position()
	var t := CheatTargeting.targets(b, W, _def("nudge"), _sq("e2"))
	check_eq(t, [_sq("e3")] as Array[int], "el empujón solo avanza una casilla")
	check(CheatTargeting.targets(b, W, _def("nudge"), _sq("e7")).is_empty(), "no se empuja una pieza enemiga")


func test_slide_targets_follow_lines() -> void:
	var b := BoardState.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
	var t := CheatTargeting.targets(b, W, _def("slide"), _sq("a1"))
	check(_sq("a4") in t, "la torre desliza en columna (4 casillas)")
	check(not (_sq("a6") in t), "pero no más allá del alcance")
	check(_sq("b2") in t, "o en diagonal")
	check(not (_sq("b3") in t), "pero no como caballo")
	check(not (_sq("e1") in t), "ni sobre su propio rey")


func test_steal_targets() -> void:
	var b := BoardState.start_position()
	check_eq(CheatTargeting.targets(b, W, _def("steal"), _sq("a7")), [-1] as Array[int], "robar no tiene destino")
	check(CheatTargeting.targets(b, W, _def("steal"), _sq("a2")).is_empty(), "no se roba una pieza propia")
	check(CheatTargeting.targets(b, W, _def("steal"), _sq("e8")).is_empty(), "no se roba un rey")


func test_why_not_reasons() -> void:
	var b := BoardState.start_position()
	check_eq(CheatTargeting.why_not(b, W, _def("steal"), _sq("e8")), "los reyes no se tocan", "rey")
	check_eq(CheatTargeting.why_not(b, W, _def("steal"), _sq("a2")), "solo piezas enemigas", "propia")
	check_eq(CheatTargeting.why_not(b, W, _def("nudge"), _sq("a7")), "solo piezas propias", "enemiga")
	check_eq(CheatTargeting.why_not(b, W, _def("nudge"), _sq("e4")), "no hay pieza", "vacía")
	check_eq(CheatTargeting.why_not(b, W, _def("steal"), _sq("a7")), "", "robable")


func test_arm_toggle_and_cancel() -> void:
	var s := CheatArmState.new()
	check(not s.is_armed(), "empieza en reposo")
	check(s.toggle(2), "armar la 3")
	check(s.is_armed() and s.index == 2, "queda armada la 3")
	check(s.toggle(0), "cambiar a la 1")
	check_eq(s.index, 0, "ahora la 1")
	check(not s.toggle(0), "pulsar la misma desarma")
	check(not s.is_armed(), "de vuelta en reposo")
	s.toggle(1)
	s.cancel()
	check(not s.is_armed() and s.index == -1, "cancelar limpia")


func test_click_flow_two_step() -> void:
	var b := BoardState.start_position()
	var def := _def("nudge")
	var s := CheatArmState.new()
	check_eq(s.on_square(_sq("e2"), b, W, def).action, "none", "sin armar no hace nada")
	s.toggle(0)
	var r := s.on_square(_sq("e7"), b, W, def)
	check_eq(r.action, "reject", "pieza enemiga rechazada")
	check_eq(r.reason, "solo piezas propias", "con motivo")
	r = s.on_square(_sq("e2"), b, W, def)
	check_eq(r.action, "select", "pieza propia elegida")
	check_eq(s.phase, CheatArmState.Phase.PIECE, "fase pieza")
	check_eq(s.targets, [_sq("e3")] as Array[int], "destinos guardados")
	r = s.on_square(_sq("e5"), b, W, def)
	check_eq(r.action, "reject", "destino inválido rechazado")
	check_eq(s.phase, CheatArmState.Phase.PIECE, "sigue con la pieza elegida")
	r = s.on_square(_sq("e3"), b, W, def)
	check_eq(r.action, "execute", "destino válido ejecuta")
	check_eq(r.from, _sq("e2"), "desde e2")
	check_eq(r.to, _sq("e3"), "hacia e3")
	check(not s.is_armed(), "tras ejecutar vuelve a reposo")


func test_click_changes_selection_and_backs_out() -> void:
	var b := BoardState.start_position()
	var def := _def("nudge")
	var s := CheatArmState.new()
	s.toggle(0)
	s.on_square(_sq("e2"), b, W, def)
	var r := s.on_square(_sq("d2"), b, W, def)
	check_eq(r.action, "select", "otra pieza propia cambia la selección")
	check_eq(s.from, _sq("d2"), "ahora d2")
	r = s.on_square(_sq("d2"), b, W, def)
	check_eq(r.action, "back", "clic en la misma pieza la suelta")
	check_eq(s.phase, CheatArmState.Phase.ARMED, "sigue armada")
	s.on_square(_sq("d2"), b, W, def)
	s.back()
	check_eq(s.phase, CheatArmState.Phase.ARMED, "atrás: de pieza a armada")
	s.back()
	check(not s.is_armed(), "atrás otra vez: reposo")


func test_steal_executes_on_first_click() -> void:
	var b := BoardState.start_position()
	var def := _def("steal")
	var s := CheatArmState.new()
	s.toggle(2)
	var r := s.on_square(_sq("b7"), b, W, def)
	check_eq(r.action, "execute", "robar no necesita destino")
	check_eq(r.from, _sq("b7"), "pieza b7")
	check_eq(r.to, -1, "sin destino")
	check_eq(r.action == "execute" and not s.is_armed(), true, "vuelve a reposo")


func test_executed_cheat_is_accepted_by_server() -> void:
	# Lo que la entrada decide ejecutar, el servidor lo acepta.
	var cfg := MatchConfig.new()
	cfg.beginner_help = false
	for id in ["nudge", "slide", "steal", "move_enemy"]:
		cfg.cheats.append(_def(id))
	var m := MatchServer.new(cfg, PlayerSession.new(1, "Blancas"), PlayerSession.new(2, "Negras", true), BoardState.START_FEN, 3)
	m.start()
	var s := CheatArmState.new()
	s.toggle(3)
	s.on_square(_sq("e7"), m.board, W, cfg.cheats[3])
	var r := s.on_square(_sq("e6"), m.board, W, cfg.cheats[3])
	check_eq(r.action, "execute", "mover pieza enemiga e7->e6")
	var res := m.start_cheat(W, cfg.cheats[3].id, r.from, r.to)
	check(res.ok, "el servidor lo acepta: %s" % res.reason)


func test_arbiter_is_near() -> void:
	var a := Arbiter.new()
	a.position = Vector3(2.0, 0.0, 1.0)
	check(a.is_near(Vector3(2.5, 1.0, 1.0), 0.6), "cerca ignora la altura")
	check(not a.is_near(Vector3(4.0, 0.0, 1.0), 1.0), "lejos")
	a.free()
