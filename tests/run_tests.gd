extends SceneTree
## Ejecuta todas las pruebas sin ventana:
##   godot --headless --path . --script res://tests/run_tests.gd
## Opcional: `-- --filter=nombre` para correr solo los archivos que contengan el texto.

const TEST_FILES := [
	"res://tests/test_chess_rules.gd",
	"res://tests/test_match_server.gd",
	"res://tests/test_cheats.gd",
	"res://tests/test_beginner_helper.gd",
	"res://tests/test_gaze.gd",
	"res://tests/test_bots.gd",
	"res://tests/test_bot_cheats.gd",
	"res://tests/test_maia_encoding.gd",
	"res://tests/test_tension_director.gd",
	"res://tests/test_rival_events.gd",
]


func _init() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var total := 0
	var failed := 0
	for path in TEST_FILES:
		if filter != "" and not path.contains(filter):
			continue
		if not ResourceLoader.exists(path):
			continue
		var suite: Object = load(path).new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.set("failures", [])
			var t0 := Time.get_ticks_msec()
			suite.call(name)
			var errors: Array = suite.get("failures")
			var ms := Time.get_ticks_msec() - t0
			if errors.is_empty():
				print("  ok   %s::%s (%d ms)" % [path.get_file(), name, ms])
			else:
				failed += 1
				print("  FAIL %s::%s" % [path.get_file(), name])
				for e in errors:
					print("       ", e)
	print("\n%d pruebas, %d fallos" % [total, failed])
	quit(1 if failed > 0 else 0)
