class_name ScoresheetView
extends Node3D
## Las dos planillas de la mesa principal (`scoresheet.glb`) con su pluma (`pen.glb`), a la
## derecha-delante de cada jugador: la del humano en (+X, +Z), junto al reloj, y la del rival en
## (-X, -Z), que es su derecha (escribe con la mano derecha y pulsa el reloj con la izquierda). El servidor avisa de cada
## jugada anotada (`add_entry`); la mano la escribe (`HandAnimator`) y, al terminar, la
## jugada aparece en la hoja (`reveal_next`) como texto en renglones, en una columna y
## 11 filas por página (al llenarse se pasa a una hoja en blanco).
##
## Las hojas se sirven por color de piezas (`near_color` es el del humano).

const SHEET_PATH := "res://assets/models/props/scoresheet.glb"
const PEN_PATH := "res://assets/models/props/pen.glb"
const SHEET_SCALE := 1.1
const SHEET_POS := Vector3(0.54, BoardView.TABLE_TOP, 0.30)
const ROWS := 11
const COLUMNS := 1
## Posición de los renglones en el espacio del modelo (m): primera fila y separación.
const ROW_Z0 := -0.0464
const ROW_DZ := 0.01435
const COLUMN_X := [-0.062]
const INK := Color(0.07, 0.08, 0.20)
## Pluma en reposo (local de la hoja): la punta y la dirección, sobre la franja de arriba.
const PEN_REST_TIP := Vector3(-0.07, 0.0085, -0.078)
## Distancia de la yema a la punta cuando se escribe.
const PEN_GRIP := 0.04

var near_color: int = ChessPiece.WHITE
## Por color: {root, sheet, pen, labels: Array[Label3D], pending: Array[Dictionary], written: int}.
var _sheets: Array[Dictionary] = [{}, {}]


func setup(p_near_color: int) -> void:
	near_color = p_near_color
	name = "Planillas"
	for color in 2:
		_sheets[color] = _build_sheet(color)


func _build_sheet(color: int) -> Dictionary:
	var near := color == near_color
	var root := Node3D.new()
	root.name = "Planilla_" + ("Humano" if near else "Rival")
	# El rival está al otro lado de la mesa: su planilla es el punto simétrico (giro de 180 grados
	# sobre la mesa), girada 180 grados: queda a su derecha.
	root.position = SHEET_POS if near else Vector3(-SHEET_POS.x, SHEET_POS.y, -SHEET_POS.z)
	root.rotation.y = 0.0 if near else PI
	add_child(root)
	var sheet := (load(SHEET_PATH) as PackedScene).instantiate() as Node3D
	sheet.scale = Vector3.ONE * SHEET_SCALE
	root.add_child(sheet)
	var pen := (load(PEN_PATH) as PackedScene).instantiate() as Node3D
	pen.name = "Pluma"
	root.add_child(pen)
	pen.position = PEN_REST_TIP * SHEET_SCALE
	var labels: Array[Label3D] = []
	for i in ROWS * COLUMNS:
		var l := Label3D.new()
		l.name = "Linea_%d" % i
		l.font_size = 40
		l.pixel_size = 0.00040
		l.shaded = false
		l.double_sided = false
		l.modulate = INK
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.rotation.x = deg_to_rad(-90.0)
		var col := i / ROWS
		var row := i % ROWS
		l.position = Vector3(float(COLUMN_X[col]), 0.0072, ROW_Z0 + ROW_DZ * row) * SHEET_SCALE
		l.text = ""
		root.add_child(l)
		labels.append(l)
	return {"root": root, "sheet": sheet, "pen": pen, "labels": labels, "pending": [], "written": 0}


# --- Datos --------------------------------------------------------------------------

## El servidor anotó una jugada de `color`: queda por escribir a mano.
func add_entry(color: int, move_number: int, san: String) -> void:
	(_sheets[color].pending as Array).append({"number": move_number, "san": san})


func has_pending(color: int) -> bool:
	return not (_sheets[color].pending as Array).is_empty()


## Jugadas ya escritas en la hoja de `color`.
func written_count(color: int) -> int:
	return int(_sheets[color].written)


## Texto de una línea de la hoja (para pruebas): índice dentro de la página.
func line_text(color: int, index: int) -> String:
	return (_sheets[color].labels[index] as Label3D).text


## Escribe en la hoja la siguiente jugada pendiente; el texto aparece letra a letra en
## `seconds` (corrutina). Devuelve el texto escrito ("" si no había nada).
func reveal_next(color: int, seconds: float = 0.5) -> String:
	var s: Dictionary = _sheets[color]
	if (s.pending as Array).is_empty():
		return ""
	var entry: Dictionary = (s.pending as Array).pop_front()
	var label := _slot_label(color)
	var text := "%d. %s" % [entry.number, entry.san]
	s.written = int(s.written) + 1
	if seconds > 0.0 and is_inside_tree():
		label.text = ""
		var tw := create_tween()
		tw.tween_method(func(k: float) -> void: label.text = text.substr(0, int(ceil(k * text.length()))), 0.0, 1.0, seconds)
		await tw.finished
	label.text = text
	return text


## Etiqueta donde se escribirá la siguiente jugada; si empieza una página nueva, borra la anterior.
func _slot_label(color: int) -> Label3D:
	var s: Dictionary = _sheets[color]
	var n: int = s.written
	var page_size := ROWS * COLUMNS
	if n > 0 and n % page_size == 0:
		for l in s.labels:
			(l as Label3D).text = ""
	return s.labels[n % page_size]


## Escritura a mano interrumpible: muestra la fracción `k` (0..1) de la jugada pendiente sin
## sacarla de la cola. Si la mano se interrumpe, `clear_partial` borra lo escrito a medias y la
## entrada sigue pendiente (se reescribe entera al retomar); si termina, `reveal_next(color, 0.0)` la fija.
func show_partial(color: int, k: float) -> void:
	var s: Dictionary = _sheets[color]
	if (s.pending as Array).is_empty():
		return
	var entry: Dictionary = (s.pending as Array)[0]
	var text := "%d. %s" % [entry.number, entry.san]
	_slot_label(color).text = text.substr(0, int(ceil(clampf(k, 0.0, 1.0) * text.length())))


## Borra el texto a medias de la jugada pendiente (la entrada no se pierde).
func clear_partial(color: int) -> void:
	_slot_label(color).text = ""


# --- Geometría para la mano ---------------------------------------------------------

## Punto del mundo (sobre el papel) de la siguiente línea que se escribe, en su inicio.
func write_point(color: int) -> Vector3:
	var s: Dictionary = _sheets[color]
	var n: int = s.written % (ROWS * COLUMNS)
	var col := n / ROWS
	var row := n % ROWS
	var local := Vector3(float(COLUMN_X[col]) + 0.004, 0.0072, ROW_Z0 + ROW_DZ * row) * SHEET_SCALE
	return (s.root as Node3D).to_global(local)


## Dirección (en el mundo) a lo largo de la línea de escritura (hacia la derecha del jugador).
func line_direction(color: int) -> Vector3:
	return (_sheets[color].root as Node3D).global_basis * Vector3(1, 0, 0)


## Punto de agarre de la pluma en reposo (a `PEN_GRIP` de la punta, en el mundo).
func pen_rest_grip(color: int) -> Vector3:
	var pen: Node3D = _sheets[color].pen
	return pen.to_global(Vector3(PEN_GRIP, 0.0, 0.0))


func pen(color: int) -> Node3D:
	return _sheets[color].pen


## La pluma vuelve a su sitio sobre la hoja (corrutina: se asienta en `seconds`).
func rest_pen(color: int, seconds: float = 0.2) -> void:
	var s: Dictionary = _sheets[color]
	var pen: Node3D = s.pen
	if pen.get_parent() != s.root:
		pen.reparent(s.root, true)
	var rest := Transform3D(Basis.IDENTITY, PEN_REST_TIP * SHEET_SCALE)
	if seconds <= 0.0 or not is_inside_tree():
		pen.transform = rest
		return
	var from := pen.transform
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void: pen.transform = from.interpolate_with(rest, k), 0.0, 1.0, seconds)
	await tw.finished
