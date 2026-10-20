extends TestCase
## El rival condenado deja de animarse: sin poses de reposo, mirada ni eventos.


func test_condemned_avatar_stays_still() -> void:
	var av := OpponentAvatar.new()
	# Sin árbol no se monta la mano: solo la figura sentada.
	av.figure = SeatedFigure.new()
	av.figure.setup(CharacterFigure.bot_look(RandomNumberGenerator.new(), {}))
	av.figure.play(&"death_slump_table", 0.0)
	av.condemn()
	check(av.condemned, "queda marcado como condenado")
	av._idle_timer = 0.0
	av._process(1.0)
	check_eq(av.figure.current(), &"death_slump_table", "no cambia de pose")
	av.play_cough()
	check(av._event_tween == null or not av._event_tween.is_valid(), "no tose")
	av._on_looked(1.0, 0.3)
	check_eq(av._look_yaw, 0.0, "no sigue la mirada")
	av.free()
