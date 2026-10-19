extends SceneTree
## Coste por jugada de las partidas de fondo (BackgroundMatch).
##   godot --headless --path . --script res://tools/bench_background.gd
func _init() -> void:
	var worst := 0.0
	var total := 0.0
	var n := 0
	var matches: Array[BackgroundMatch] = []
	for i in 7:
		var g := TournamentGame.new(1, 2)
		matches.append(BackgroundMatch.new(g, PlayerSession.new(1, "A", true), PlayerSession.new(2, "B", true), 1400, 1400, 100 + i, 180.0))
	for step in 4000:
		for bg in matches:
			if bg.is_over():
				continue
			var t0 := Time.get_ticks_usec()
			var moved := bg.tick(0.1, true)
			var dt := (Time.get_ticks_usec() - t0) / 1000.0
			if moved:
				total += dt
				n += 1
				worst = maxf(worst, dt)
	print("jugadas %d, media %.3f ms, peor %.3f ms" % [n, total / maxf(n, 1), worst])
	quit()
