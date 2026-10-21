extends SceneTree
## Vista previa de animaciones del jugador: sienta una figura en una silla frente a una mesa con
## tablero (props reales) y captura cada clip de un rol (o un clip suelto) en varios instantes.
## Necesita pantalla (no vale --headless):
##   DISPLAY=:0 godot --path . --script res://tools/anim_preview.gd -- --role=sit_wait --out=/ruta
##   opciones: --clip=nombre (en vez de --role), --times=0,0.25,0.5,0.75 (fracciones de la duración),
##             --seat=0.72|0.80 (distancia silla-centro de la mesa), --views=side,front,top
##             --bare (sin mesa, silla ni tablero: para ver una mano de cerca)
##             --focus=x,y,z --dist=0.4 (primer plano: la cámara mira a ese punto desde esa distancia)
## Guarda <out>/<clip>_<fracción>_<vista>.png (la figura mira a +Z; la silla está en el origen).

const PROPS := "res://assets/models/props/"

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


func _run() -> void:
	var out := String(_args.get("out", "/tmp/anim_preview"))
	DirAccess.make_dir_recursive_absolute(out)
	var seat := float(_args.get("seat", 0.72))
	var views := String(_args.get("views", "side,front,top")).split(",")
	var fracs: Array = []
	for f in String(_args.get("times", "0,0.25,0.5,0.75")).split(","):
		fracs.append(float(f))
	root.size = Vector2i(640, 640)
	var world := Node3D.new()
	root.add_child(world)
	_add_set(world, seat)
	var fig := CharacterFigure.new()
	world.add_child(fig)
	fig.setup(CharacterFigure.random_look(RandomNumberGenerator.new()))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 32.0
	var clips: Array[StringName] = []
	if _args.has("clip"):
		clips.append(StringName(_args["clip"]))
	else:
		for c in fig.variants(StringName(_args.get("role", "sit_wait"))):
			clips.append(StringName(c))
	var ap := fig.animation_player()
	for clip in clips:
		fig.play(clip, 0.0)
		ap.pause()
		var len := ap.get_animation(clip).length
		for fr in fracs:
			ap.seek(clamp(fr, 0.0, 1.0) * len, true)
			for v in views:
				_place_camera(cam, v, seat)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				var path := "%s/%s_%.2f_%s.png" % [out, clip, fr, v]
				img.save_png(path)
				print("guardado ", path)
	quit(0)


func _place_camera(cam: Camera3D, view: String, seat: float) -> void:
	var target := Vector3(0, 0.95, seat * 0.5)
	if _args.has("focus"):
		var f := String(_args["focus"]).split(",")
		target = Vector3(float(f[0]), float(f[1]), float(f[2]))
		var d := float(_args.get("dist", 0.4))
		match view:
			"side":
				cam.position = target + Vector3(d, 0.0, 0.0)
			"front":
				cam.position = target + Vector3(d * 0.4, d * 0.3, d)
			"under":
				cam.position = target + Vector3(d * 0.2, -d * 0.6, d * 0.8)
			_:
				cam.position = target + Vector3(0.0, d, 0.01)
		cam.look_at(target, Vector3.UP if view != "top" else Vector3(0, 0, -1))
		return
	match view:
		"side":
			cam.position = Vector3(3.6, 1.0, seat * 0.5)
		"front":
			cam.position = Vector3(1.3, 1.5, seat + 2.4)
			target = Vector3(0, 0.95, seat * 0.5)
		_:
			cam.position = Vector3(0, 4.0, seat * 0.5 + 0.01)
			target = Vector3(0, 0, seat * 0.5)
	cam.look_at(target, Vector3.UP if view != "top" else Vector3(0, 0, -1))


func _add_set(world: Node3D, seat: float) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.19, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	world.add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.12, 0.14)
	floor_mesh.material_override = fm
	world.add_child(floor_mesh)
	if _args.has("bare"):
		return
	var chair := (load(PROPS + "chair.glb") as PackedScene).instantiate() as Node3D
	world.add_child(chair)
	var table := (load(PROPS + "table.glb") as PackedScene).instantiate() as Node3D
	table.position = Vector3(0, 0, seat)
	world.add_child(table)
	var board := (load(PROPS + "board.glb") as PackedScene).instantiate() as Node3D
	board.position = Vector3(0, 0.735, seat)
	world.add_child(board)
	# Reloj al costado derecho de la figura (-X, el lado de su mano que pulsa), con el LCD hacia el centro.
	var clock := (load(PROPS + "chess_clock.glb") as PackedScene).instantiate() as Node3D
	clock.scale = Vector3.ONE * 1.3
	clock.position = Vector3(-0.42, BoardView.TABLE_TOP, seat)
	clock.rotation_degrees.y = 180.0
	world.add_child(clock)
