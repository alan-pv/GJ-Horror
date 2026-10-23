class_name PlayerController
extends Node3D
## Jugador humano en primera persona, sentado en su silla (+Z, mirando a -Z). Su cuerpo es una
## `SeatedFigure` (`body`) con la cabeza oculta y la cámara en los ojos; su brazo derecho es el
## que mueve las piezas (`hand_rig`, por IK). Mira con el ratón (capturado;
## en web hay que hacer clic para capturarlo, Esc lo suelta), manda su mirada
## al servidor unas 10 veces por segundo y elige casillas con un rayo desde
## el centro de la pantalla contra el plano del tablero.
##
## Clic en cualquier pieza (reyes incluidos; propia o rival, en tu turno o fuera de él) → mapa de
## calor de adónde puede ir → clic en destino. Nivel 0 = jugada normal (`submit_move`, coronación
## siempre a dama); otro nivel = trampa (`start_cheat`); la pila propia = robo. Toda esa lógica
## vive en `PieceInteraction`; aquí solo se convierte el rayo en destino. Solo se actúa con la
## mano libre (anotar en la planilla no cuenta: la mano suelta la pluma y atiende el gesto).
## `X` aborta la trampa en curso, clic derecho o `Esc` sueltan la pieza, `A` acusa.

signal mouse_capture_changed(captured: bool)

## Suelo bajo el centro del asiento (la silla del salón está a 0,80 m; se avanza un poco para llegar al tablero).
const SEAT := Vector3(0.0, 0.0, 0.72)
## Ojos del jugador: los de la figura sentada (que está girada 180 grados).
const EYE_POSITION := Vector3(0.0, OpponentAvatar.EYE_LOCAL.y, SEAT.z - OpponentAvatar.EYE_LOCAL.z)
const MOUSE_SENSITIVITY := 0.0022
## Un evento de ratón que salta más que esto (píxeles de pantalla) se descarta: en web,
## el bloqueo de puntero a veces entrega un salto falso al capturar o al cambiar de ventana.
const MOUSE_SPIKE_PX := 400.0
## Filtro de picos (web, por evento): un evento mayor que `SPIKE_SOFT_PX` que además supera
## `SPIKE_RATIO` veces el tamaño reciente (media móvil, con suelo `SPIKE_FLOOR`) es un salto aislado
## (los de los foros de Godot en Firefox/Chrome) y se descarta; un giro rápido real crece por pasos.
const SPIKE_SOFT_PX := 150.0
const SPIKE_RATIO := 30.0
const SPIKE_FLOOR := 2.0
const SPIKE_AVG := 0.25
## Constante de tiempo (s) del suavizado del giro: reparte los saltos de píxel entero del
## ratón entre fotogramas para que la cámara no avance a escalones con sensibilidad alta.
const LOOK_SMOOTH := 0.025
## En web no se suaviza (0 = se aplica directo): el retraso de 60 ms que tenía hacía flotar la cámara,
## y los pasos de píxel entero de Chrome en Linux (0,0022 rad, ~1,5 px de pantalla) no se notan.
const LOOK_SMOOTH_WEB := 0.0
## Web: ratón en el navegador. Este módulo (una sola vez por página) hace tres cosas:
## 1. Pide el bloqueo de puntero SINCRÓNICAMENTE en el `mousedown`/`mouseup` del lienzo cuando el juego
##    lo quiere (`__look.want`), que es cuando el navegador concede el bloqueo fuera de pantalla
##    completa (exige un gesto de usuario). Las peticiones de Godot (`canvas.requestPointerLock()` desde
##    su bucle principal, sin gesto) se desvían a la misma función. Pide `unadjustedMovement` (crudo, sin
##    aceleración del sistema) solo si el navegador lo admite; el resultado se recuerda.
## 2. Si el navegador deniega el bloqueo (`pointerlockerror`: iframe sin permiso, ~1 s tras Esc en Chrome,
##    sin gesto), pasa a modo "libre": la cámara sigue usando `movementX/Y` mientras el ratón está sobre
##    el lienzo (el cursor sigue oculto) y se reintenta el bloqueo en cada clic.
## 3. Acumula los `movementX/Y` crudos (píxeles CSS, independientes del tamaño del lienzo y del
##    estiramiento de Godot, que con el "fullscreen" de itch.io disparaba la proporción) en una lista de
##    eventos que `_process` recoge una vez por fotograma. Descarta lo que supere el tope por evento y los
##    60 ms posteriores a un cambio de bloqueo (salto falso al capturar).
## Escala de Firefox: si en una prueba real el giro sale distinto que en Chrome, `?look_scale=<k>` en la
## URL multiplica el movimiento (p. ej. 0.5 si Firefox da píxeles físicos con dpr 2); sin detección
## automática porque no se pudo probar en Firefox.
const WEB_MOUSE_JS := """
if (!window.__look) {
	var L = window.__look = {buf: [], want: false, locked: false, denied: false, unadj: null, mode: 'none',
		err: '', errors: 0, events: 0, dropped: 0, pending: false, yaw: 0, pitch: 0, gmode: 0, scale: 1,
		grace: 0, requests: 0, lastRequest: ''};
	try { var u = localStorage.getItem('look_unadj'); if (u === '0') L.unadj = false; if (u === '1') L.unadj = true; } catch (e) {}
	try { var q = parseFloat(new URLSearchParams(location.search).get('look_scale')); if (q > 0) L.scale = q; } catch (e) {}
	var nativeLock = Element.prototype.requestPointerLock;
	var save = function () { try { localStorage.setItem('look_unadj', L.unadj ? '1' : '0'); } catch (e) {} };
	var cv = function () { return document.querySelector('canvas'); };
	var fail = function (e) { L.err = (e && e.name) ? e.name : String(e); };
	L.request = function (el) {
		el = el || cv();
		if (!el || document.pointerLockElement === el || L.pending) return undefined;
		L.requests++;
		var raw = L.unadj !== false;
		L.lastRequest = raw ? 'raw' : 'plain';
		var p;
		try { p = raw ? nativeLock.call(el, {unadjustedMovement: true}) : nativeLock.call(el); } catch (e) { fail(e); return undefined; }
		if (!p || !p.then) { if (raw) { L.unadj = false; } return p; }  // Firefox: sin promesa ni opciones
		L.pending = true;
		return p.then(function () {
			L.pending = false;
			if (raw && L.unadj !== true) { L.unadj = true; save(); }
		}, function (e) {
			L.pending = false;
			fail(e);
			if (!raw) return;
			// El crudo falló (no soportado, o Chrome en Linux): se repite el normal sin perder el gesto
			// (la activación del usuario dura ~5 s) y se recuerda cuál funcionó.
			var again;
			try { again = nativeLock.call(el); } catch (e2) { fail(e2); return; }
			if (again && again.then) {
				L.pending = true;
				again.then(function () { L.pending = false; L.unadj = false; save(); },
					function (e3) { L.pending = false; fail(e3); });
			}
		});
	};
	// Las peticiones de Godot pasan por aquí (una sola decisión sobre las opciones).
	Element.prototype.requestPointerLock = function () { return L.request(this); };
	var onGesture = function (e) {
		if (L.want && !document.pointerLockElement && e.target && e.target.tagName === 'CANVAS') L.request(e.target);
	};
	document.addEventListener('mousedown', onGesture, true);
	document.addEventListener('mouseup', onGesture, true);
	document.addEventListener('pointerlockchange', function () {
		L.locked = !!document.pointerLockElement;
		L.grace = performance.now() + 60;
		if (L.locked) { L.denied = false; L.err = ''; }
	}, true);
	document.addEventListener('pointerlockerror', function () {
		L.errors++;
		if (!L.err) L.err = 'pointerlockerror';
		if (L.want) L.denied = true;
	}, true);
	window.addEventListener('focus', function () { L.grace = performance.now() + 60; }, true);
	document.addEventListener('mousemove', function (e) {
		var free = L.want && !L.locked && L.denied && e.target && e.target.tagName === 'CANVAS';
		if (!L.locked && !free) return;
		if (performance.now() < L.grace) { L.dropped++; return; }
		var dx = e.movementX * L.scale, dy = e.movementY * L.scale;
		if (Math.abs(dx) + Math.abs(dy) > __SPIKE__) { L.dropped++; return; }
		L.events++;
		L.buf.push(dx, dy);
		if (L.buf.length > 4000) L.buf.splice(0, 2000);
	}, {capture: true, passive: true});
}
"""
## Recoge lo acumulado: "bloqueo,libre,dx,dy,dx,dy,...". Recibe yaw/pitch/modo de Godot para el diagnóstico.
const WEB_MOUSE_TAKE := ("(function(){var L=window.__look;L.yaw=%f;L.pitch=%f;L.gmode=%d;var b=L.buf;L.buf=[];"
		+ "var f=L.want&&!L.locked&&L.denied;L.mode=L.locked?(L.unadj===true?'raw':'plain'):(f?'free':'none');"
		+ "return (L.locked?1:0)+','+(f?1:0)+(b.length?','+b.join(','):'');})()")
const YAW_LIMIT := deg_to_rad(120.0)
const PITCH_MIN := deg_to_rad(-80.0)
const PITCH_MAX := deg_to_rad(55.0)
const GAZE_INTERVAL := 0.1
## Campo de visión de la cámara sin estrés (grados).
const BASE_FOV := 62.0

var server: MatchServer
var board: BoardView
var animator: HandAnimator
var color: int = ChessPiece.WHITE
var camera: Camera3D
var hand_rig: HandRig
## Mano izquierda (libre): descansa sobre la mesa.
var idle_rig: HandRig
## Cuerpo del jugador (la cabeza se oculta: se ve el torso y los brazos).
var body: SeatedFigure
## Si es false no se manda la mirada (modo autoplay, donde la manda un bot).
var send_gaze: bool = true
## true si la cámara está fija en un punto de depuración (`--shot-cam`).
var debug_camera: bool = false
## true durante la ejecución en primera persona: no se puede mover, hacer trampa, acusar ni mirar
## (la cámara la gira el árbitro hacia el cañón).
var input_locked: bool = false
## true durante el paseo entre rondas (`RoundWalk`): se puede girar la cabeza con el ratón, pero no
## hay clics ni teclas de juego. Implica `input_locked`.
var walking: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
## Para los subtítulos (lo asigna `GameRoot` al crear el HUD).
var hud: Hud
## Selección de piezas, mapa de calor y envío de jugadas y trampas.
var interaction: PieceInteraction
## Casilla de la pieza elegida (-1 si ninguna).
var selected: int:
	get:
		return interaction.selected if interaction != null else -1

var _head: Node3D
## Entre la cabeza y la cámara: balanceo y sacudida del estrés (`set_camera_sway`).
var _sway: Node3D
var _gaze_timer: float = 0.0
var _headless: bool = false
## Captura que el juego pidió; si el navegador la suelta por su cuenta se avisa al HUD.
var _captured: bool = false
## El bloqueo de puntero llega con retraso en web: solo cuenta como perdido si ya se vio activo.
var _lock_seen: bool = false
var _debug_timer: float = 0.0
## Giro del ratón (rad) aún por aplicar; `_process` lo consume con el suavizado.
var _pending_look: Vector2 = Vector2.ZERO
var _web_mouse: bool = false
## Web: el navegador denegó el bloqueo y la cámara sigue con el ratón sin bloquear (modo "libre").
var _web_free: bool = false
## Web: ¿bloqueo de puntero concedido ahora mismo? (lo informa el módulo JS en cada fotograma).
var _web_locked: bool = false
## Tamaño reciente de los eventos de ratón (media móvil) para el filtro de picos.
var _recent_len: float = 0.0


func setup(p_server: MatchServer, p_board: BoardView, p_color: int, look: Dictionary = {}) -> void:
	server = p_server
	board = p_board
	color = p_color
	name = "Jugador"
	position = EYE_POSITION
	_headless = DisplayServer.get_name() == "headless"
	if not _headless and OS.has_feature("web"):
		_web_mouse = true
		JavaScriptBridge.eval(WEB_MOUSE_JS.replace("__SPIKE__", str(int(MOUSE_SPIKE_PX))), true)
	_head = Node3D.new()
	_head.name = "Cabeza"
	add_child(_head)
	# Nodo intermedio para el balanceo y la sacudida (estrés): solo mueve la imagen; la mirada
	# que se manda al servidor sale de la cabeza, sin esto.
	_sway = Node3D.new()
	_sway.name = "Balanceo"
	_head.add_child(_sway)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.02
	camera.far = 60.0
	camera.current = true
	_sway.add_child(camera)
	# Empieza mirando el centro del tablero.
	pitch = rest_pitch()
	_apply_look()

	# Cuerpo: sentado, mirando a -Z, con la cabeza oculta.
	body = SeatedFigure.new()
	body.name = "Cuerpo"
	body.position = SEAT - EYE_POSITION
	body.rotation.y = PI
	add_child(body)
	body.setup(CharacterFigure.random_look(RandomNumberGenerator.new()) if look.is_empty() else look)
	body.set_hidden_for_first_person(true)
	body.play(&"sit_idle", 0.0)
	# Brazo derecho (el del personaje: queda hacia +X del mundo, del lado del reloj).
	hand_rig = HandRig.new()
	hand_rig.name = "ManoJugador"
	add_child(hand_rig)
	hand_rig.setup(body, &"R")
	idle_rig = HandRig.new()
	idle_rig.name = "ManoLibre"
	add_child(idle_rig)
	idle_rig.setup(body, &"L")
	idle_rig.rest_at(Vector3(-0.34, BoardView.TABLE_TOP + 0.03, 0.40), 20.0)
	_apply_debug_camera()

	interaction = PieceInteraction.new()
	interaction.setup(server, board, color)
	interaction.subtitle = func(text: String, seconds: float) -> void:
		if hud != null:
			hud.show_subtitle(text, seconds)
	interaction.player_ok = func() -> bool:
		return not input_locked and (animator == null or not animator.is_busy_for_action())


## Cámara de depuración para capturas: `--shot-cam=side|px,py,pz,tx,ty,tz[,fov]`.
func _apply_debug_camera() -> void:
	var spec := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-cam="):
			spec = a.substr(11)
	if spec == "":
		return
	var pos := Vector3(1.5, 0.95, 0.0)
	var at := Vector3(0.0, 0.8, 0.0)
	var fov := 40.0
	match spec:
		"side":
			pass
		"sidenear":
			pos = Vector3(1.2, 0.95, 0.35)
			at = Vector3(0.2, 0.8, 0.35)
		"sidefar":
			pos = Vector3(1.2, 0.95, -0.35)
			at = Vector3(0.2, 0.8, -0.35)
		_:
			var v := spec.split(",")
			if v.size() >= 6:
				pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
				at = Vector3(float(v[3]), float(v[4]), float(v[5]))
				if v.size() >= 7:
					fov = float(v[6])
	camera.top_level = true
	camera.fov = fov
	camera.look_at_from_position(pos, at)
	debug_camera = true


## ¿El juego tiene el ratón? En web también cuenta el modo libre (bloqueo denegado, cámara con el
## ratón sobre el lienzo): así el aviso de captura desaparece y los clics juegan, y se reintenta el
## bloqueo en cada clic (lo hace el módulo JS dentro del gesto).
func is_mouse_captured() -> bool:
	if _headless:
		return false
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (_web_free and _captured)


func set_look(p_yaw: float, p_pitch: float) -> void:
	yaw = clampf(p_yaw, -YAW_LIMIT, YAW_LIMIT)
	pitch = clampf(p_pitch, PITCH_MIN, PITCH_MAX)
	_apply_look()


## Rotación extra de la imagen (radianes: pitch, yaw, roll) por el estrés. No cambia hacia dónde
## mira el jugador para el servidor ni la cabeza que gira el árbitro.
func set_camera_sway(rot: Vector3) -> void:
	if _sway != null:
		_sway.rotation = rot


func _apply_look() -> void:
	_head.rotation = Vector3(pitch, yaw, 0.0)


## Bloquea o devuelve toda la entrada del jugador (movimiento, trampas, acusación y mirada).
func set_input_locked(on: bool) -> void:
	input_locked = on
	if on:
		interaction.deselect()
		board.set_hover(-1)
		board.set_pile_hover(false)


## Empieza el paseo entre rondas: sin juego, con el brazo libre de IK para que se levante con el
## cuerpo. El que lo mueve es `RoundWalk`.
func begin_walk() -> void:
	walking = true
	set_input_locked(true)
	for rig in [hand_rig, idle_rig]:
		if rig != null:
			rig.set_ik_weight(0.0, 0.15)
	body.set_lean(0.0)
	body.set_twist(0.0)
	body.set_shift(0.0)
	body.set_lean_extra(0.0)


## Postura de reposo de la cabeza al sentarse (mira el centro del tablero): la de `setup`.
static func rest_pitch() -> float:
	return asin((BoardView.CENTER - EYE_POSITION).normalized().y)


func _unhandled_input(event: InputEvent) -> void:
	if _headless or (input_locked and not walking):
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		if not _web_mouse:
			_pending_look += look_delta(event.screen_relative, _sensitivity_scale())
	elif walking:
		return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_mouse_captured():
			capture_mouse(true)
		else:
			interaction.click(pick_target())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		interaction.deselect()
	elif event.is_action_pressed("ui_cancel"):
		interaction.deselect()
		capture_mouse(false)
	elif event.is_action_pressed("cheat_abort"):
		if server.started and server.abort_cheat(color) and hud != null:
			hud.show_subtitle("...better not")
	elif event.is_action_pressed("accuse"):
		if server.started and not server.is_over():
			server.accuse(color)


## Giro (yaw, pitch) en radianes para un movimiento del ratón en píxeles de pantalla.
## Se usa `screen_relative` y no `relative`: este último se escala con el estiramiento de la
## ventana, y el giro cambiaba según el tamaño del lienzo (lento en pantalla completa, desbocado
## en el recuadro de itch.io).
static func look_delta(screen_relative: Vector2, sensitivity: float) -> Vector2:
	if screen_relative.length() > MOUSE_SPIKE_PX:
		return Vector2.ZERO
	return screen_relative * MOUSE_SENSITIVITY * sensitivity


## Parte del giro pendiente que se aplica en un fotograma de `delta` segundos.
## Con `tau <= 0` no hay suavizado: se aplica todo.
static func smooth_take(pending: Vector2, delta: float, tau: float = LOOK_SMOOTH) -> Vector2:
	if tau <= 0.0:
		return pending
	return pending * (1.0 - exp(-delta / tau))


## Filtra los eventos de ratón de un fotograma (lista plana dx,dy,dx,dy,... en píxeles CSS) y
## devuelve `{sum: Vector2 (suma de los aceptados), recent: float (media móvil nueva), dropped: int}`.
## Descarta el evento que supera `MOUSE_SPIKE_PX` o que, siendo mayor que `SPIKE_SOFT_PX`, es
## `SPIKE_RATIO` veces mayor que lo reciente (salto aislado). Los descartados no actualizan la media.
static func filter_events(flat: PackedFloat32Array, recent: float) -> Dictionary:
	var sum := Vector2.ZERO
	var dropped := 0
	var i := 0
	while i + 1 < flat.size():
		var v := Vector2(flat[i], flat[i + 1])
		i += 2
		var n := v.length()
		if n > MOUSE_SPIKE_PX or (n > SPIKE_SOFT_PX and n > SPIKE_RATIO * maxf(recent, SPIKE_FLOOR)):
			dropped += 1
			continue
		sum += v
		recent = lerpf(recent, n, SPIKE_AVG)
	return {"sum": sum, "recent": recent, "dropped": dropped}


## Giro (rad) de una suma de píxeles CSS ya filtrada: independiente del tamaño del lienzo y del dpr.
static func scale_look(pixels: Vector2, sensitivity: float) -> Vector2:
	return pixels * MOUSE_SENSITIVITY * sensitivity


## Texto del panel de diagnóstico (F3): FPS, estado del ratón y, en web, el lienzo.
func debug_text() -> String:
	var t := "FPS %d\nmouse_mode %d  captured %s  lock_seen %s\nyaw %.2f  pitch %.2f  sens %.2f" % [
			Engine.get_frames_per_second(), Input.mouse_mode, _captured, _lock_seen, yaw, pitch,
			_sensitivity_scale()]
	if _web_mouse:
		t += "\n" + str(JavaScriptBridge.eval("(function(){var L=window.__look;var c=document.querySelector('canvas');"
				+ "var r=c.getBoundingClientRect();return 'lock '+L.locked+' want '+L.want+' mode '+L.mode+'  free '+(L.want&&!L.locked&&L.denied)"
				+ "+'\\nrequests '+L.requests+' ('+L.lastRequest+')  errors '+L.errors+'  err '+L.err+'  unadj '+L.unadj"
				+ "+'\\nevents '+L.events+'  dropped '+L.dropped+'  scale '+L.scale"
				+ "+'\\ncanvas '+c.width+'x'+c.height+'  css '+Math.round(r.width)+'x'+Math.round(r.height)+'  dpr '"
				+ "+devicePixelRatio+'  fullscreen '+!!document.fullscreenElement;})()", true))
	return t


func _consume_look(delta: float) -> void:
	if _web_mouse:
		var q := WEB_MOUSE_TAKE % [yaw, pitch, int(Input.mouse_mode)]
		var raw := str(JavaScriptBridge.eval(q, true)).split(",")
		if raw.size() >= 2:
			_web_locked = raw[0] == "1"
			_web_free = raw[1] == "1"
		if raw.size() > 2 and is_mouse_captured():
			var flat := PackedFloat32Array()
			for i in range(2, raw.size()):
				flat.append(raw[i].to_float())
			var f := filter_events(flat, _recent_len)
			_recent_len = f["recent"]
			_pending_look += scale_look(f["sum"], _sensitivity_scale())
	if _pending_look == Vector2.ZERO:
		return
	if not is_mouse_captured() or (input_locked and not walking):
		_pending_look = Vector2.ZERO
		return
	var take := smooth_take(_pending_look, delta, LOOK_SMOOTH_WEB if _web_mouse else LOOK_SMOOTH)
	if _pending_look.length() < 0.0005:
		take = _pending_look
	_pending_look -= take
	set_look(yaw - take.x, pitch - take.y)


## Multiplicador de sensibilidad de los ajustes (1.0 si no existe el autoload).
func _sensitivity_scale() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	return float(settings.mouse_sensitivity) if settings != null else 1.0


func capture_mouse(on: bool) -> void:
	if _headless:
		return
	if _web_mouse:
		# Antes de tocar `Input.mouse_mode`: el módulo JS necesita saber qué quiere el juego, y la
		# petición se hace ya (dentro de la activación del último clic) además de en cada gesto.
		JavaScriptBridge.eval("window.__look.want=%s;%s" % ["true" if on else "false",
				"window.__look.denied=false;window.__look.request();" if on else ""], true)
		if not on:
			_web_free = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	_captured = on
	_lock_seen = false
	mouse_capture_changed.emit(on)


func _process(delta: float) -> void:
	if not _headless:
		_consume_look(delta)
		_debug_timer -= delta
		if hud != null and hud.debug_visible and _debug_timer <= 0.0:
			_debug_timer = 0.25
			hud.set_debug(debug_text())
	if server == null:
		return
	_gaze_timer -= delta
	if _gaze_timer <= 0.0:
		_gaze_timer = GAZE_INTERVAL
		if send_gaze:
			# La mirada sale de la cabeza (sin balanceo ni sacudida); con cámara de depuración, de la cámara.
			var eye: Node3D = camera if debug_camera else _head
			server.set_gaze(color, eye.global_position, -eye.global_basis.z)
	if not _headless:
		_update_hover()
		# El navegador puede soltar el puntero sin avisar (Esc, perder el foco del iframe).
		if _captured and is_mouse_captured():
			_lock_seen = true
		elif _captured and _lock_seen:
			_captured = false
			mouse_capture_changed.emit(false)
		_sync_pointer_hud()
	# Si ya no se puede actuar (mano ocupada, acusación, fin), se suelta la pieza.
	if interaction.selected >= 0 and not interaction.can_act():
		interaction.deselect()


## Pasa al HUD el estado REAL del puntero cada fotograma (`Input.mouse_mode` y el bloqueo de entrada).
## Antes el punto de mira dependía de que `mouse_capture_changed` llegara en el momento justo, y se
## perdía cuando la escena arrancaba con el ratón ya capturado (recarga al empezar una ronda) o al
## terminar el discurso. Si el ratón ya estaba capturado sin que este nodo lo pidiera, se adopta.
func _sync_pointer_hud() -> void:
	var real := is_mouse_captured()
	if real and not _captured:
		_captured = true
		_lock_seen = true
		mouse_capture_changed.emit(true)
	if hud != null:
		hud.set_mouse_captured(real)
		hud.set_input_locked(input_locked)


## Casilla bajo el centro de la pantalla (o -1).
func pick_square() -> int:
	var ray_origin := camera.global_position
	var dir := -camera.global_basis.z
	var p := board.ray_to_board_point(ray_origin, dir)
	if p == Vector3.INF:
		return -1
	return board.world_to_square(p)


## Destino bajo el centro de la pantalla: una casilla, `TO_PILE` si apunta a la zona de la pila
## propia con una pieza rival elegida, o -1.
func pick_target() -> int:
	var sq := pick_square()
	if sq >= 0:
		return sq
	if interaction.levels.has(CheatRules.TO_PILE) \
			and board.ray_to_pile(camera.global_position, -camera.global_basis.z, color):
		return CheatRules.TO_PILE
	return -1


func _update_hover() -> void:
	var sq := -1
	var pile := false
	if is_mouse_captured() and not input_locked and interaction.can_act():
		var t := pick_target()
		if t == CheatRules.TO_PILE:
			pile = true
		else:
			sq = t
	board.set_hover(sq)
	board.set_pile_hover(pile)


## Selecciona una pieza por código (pruebas y capturas de depuración).
func select_square(sq: int) -> void:
	interaction.select(sq)
