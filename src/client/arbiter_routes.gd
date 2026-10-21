class_name ArbiterRoutes
extends RefCounted
## Pasillos del salón y rutas del árbitro (lógica pura, sin nodos).
##
## Las mesas forman la cuadrícula de `HallLayout`; entre columnas y entre filas, y
## alrededor, quedan pasillos. Una ruta solo recorre pasillos (líneas verticales
## `aisle_xs` y horizontales `aisle_zs`), así que nunca cruza una mesa ni una silla.
## Los puntos fuera de la red (junto a una silla) se unen a ella con un tramo recto
## corto ("ramal") que cada llamador garantiza libre.

## Semiextensión (X, Z) del bloque mesa + sillas + ocupantes.
const TABLE_HALF := Vector2(0.75, 1.15)
## Distancia del asiento al centro de la mesa (sillas a 0,80 m).
const SEAT_Z := 0.80
## Separación lateral del árbitro respecto al condenado al ejecutarlo.
const SIDE_OFFSET := 0.85
## Junto al extremo de la mesa del humano (lado derecho del jugador): desde aquí
## revisa las planillas y apunta al jugador.
const HUMAN_SIDE_SPOT := Vector3(0.95, 0.0, 0.0)


## Líneas verticales de pasillo (X): entre columnas y los dos bordes.
static func aisle_xs() -> Array[float]:
	var out: Array[float] = []
	var human_col := HallLayout.cell_of(HallLayout.human_table).x
	for c in range(-1, HallLayout.COLS):
		out.append(float(c - human_col) * HallLayout.SPACING_X + HallLayout.SPACING_X * 0.5)
	return out


## Líneas horizontales de pasillo (Z): entre filas y los dos bordes.
static func aisle_zs() -> Array[float]:
	var out: Array[float] = []
	var human_row := HallLayout.cell_of(HallLayout.human_table).y
	for r in range(-1, HallLayout.ROWS):
		out.append(float(r - human_row) * HallLayout.SPACING_Z + HallLayout.SPACING_Z * 0.5)
	return out


## Intersecciones de pasillo (los nodos de la red).
static func nodes() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var zs := aisle_zs()
	for z in zs:
		for x in aisle_xs():
			out.append(Vector3(x, 0.0, z))
	return out


## Pasillo que pasa justo detrás de la silla del jugador (z de la fila del humano + media separación).
static func behind_player_z() -> float:
	return HallLayout.SPACING_Z * 0.5


## Signo en Z del asiento: +1 = lado +Z, -1 = lado -Z. Blancas en +Z y negras en -Z, salvo en
## la mesa del humano, donde el humano está siempre en +Z.
static func seat_sign(table: int, seat: int, human_color: int) -> float:
	if table == HallLayout.human_table:
		return 1.0 if seat == human_color else -1.0
	return 1.0 if seat == ChessPiece.WHITE else -1.0


## Centro del asiento (a ras de suelo, sobre el podio si es el caso) en el mundo.
static func seat_position(table: int, seat: int, human_color: int) -> Vector3:
	var p := HallLayout.table_position(table) + Vector3(0.0, 0.0, seat_sign(table, seat, human_color) * SEAT_Z)
	p.y = HallLayout.floor_y(p)
	return p


## Dónde se planta el árbitro para ejecutar a quien está en el asiento.
static func execution_spot(table: int, seat: int, human_color: int) -> Vector3:
	var s := seat_position(table, seat, human_color)
	return s + Vector3(SIDE_OFFSET, 0.0, 0.0)


## Rectángulos (mínimo y máximo en XZ) ocupados por las mesas con sus sillas.
static func table_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in HallLayout.table_count():
		var p := HallLayout.table_position(i)
		out.append(Rect2(p.x - TABLE_HALF.x, p.z - TABLE_HALF.y, TABLE_HALF.x * 2.0, TABLE_HALF.y * 2.0))
	return out


## ¿El segmento a-b (en XZ) atraviesa el interior de alguna mesa?
static func segment_hits_table(a: Vector3, b: Vector3) -> bool:
	for r in table_rects():
		if _segment_hits_rect(Vector2(a.x, a.z), Vector2(b.x, b.z), r.grow(-0.01)):
			return true
	return false


## ¿El segmento a-b (en XZ) atraviesa el interior del rectángulo `r` (en XZ)?
static func segment_hits_rect(a: Vector3, b: Vector3, r: Rect2) -> bool:
	return _segment_hits_rect(Vector2(a.x, a.z), Vector2(b.x, b.z), r)


static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	# Recorte de Liang-Barsky.
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	return t0 < t1


## Punto de la red más cercano a `p`. Con empate (o casi) prefiere el pasillo vertical.
static func snap(p: Vector3) -> Vector3:
	var xs := aisle_xs()
	var zs := aisle_zs()
	var best_x := xs[0]
	for x in xs:
		if absf(x - p.x) < absf(best_x - p.x):
			best_x = x
	var best_z := zs[0]
	for z in zs:
		if absf(z - p.z) < absf(best_z - p.z):
			best_z = z
	var on_v := Vector3(best_x, 0.0, clampf(p.z, zs[0], zs[zs.size() - 1]))
	var on_h := Vector3(clampf(p.x, xs[0], xs[xs.size() - 1]), 0.0, best_z)
	return on_v if absf(best_x - p.x) <= absf(best_z - p.z) + 0.02 else on_h


## Ruta de `from` a `to` por los pasillos: lista de puntos a recorrer en orden (sin `from`,
## con `to` al final). `from` y `to` pueden estar fuera de la red (ramal recto hasta ella).
static func route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var a := snap(from)
	var b := snap(to)
	var path := _network_path(a, b)
	var out: Array[Vector3] = []
	if _flat_dist(from, a) > 0.03:
		out.append(a)
	for i in range(1, path.size()):
		out.append(path[i])
	if _flat_dist(b, to) > 0.03:
		out.append(to)
	return out


## Longitud total de una ruta que parte de `from`.
static func route_length(from: Vector3, path: Array[Vector3]) -> float:
	var total := 0.0
	var prev := from
	for p in path:
		total += _flat_dist(prev, p)
		prev = p
	return total


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))


## Camino por la red entre dos puntos que ya están en ella (Dijkstra); incluye ambos.
static func _network_path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var pts: Dictionary = {}  # clave -> Vector3
	for n in nodes():
		pts[_key(n)] = n
	pts[_key(a)] = a
	pts[_key(b)] = b
	var adj: Dictionary = {}  # clave -> Array[Vector2i]
	for k in pts:
		adj[k] = []
	# Puntos sobre cada pasillo, ordenados, unidos de dos en dos.
	for x in aisle_xs():
		var on: Array[Vector3] = []
		for k in pts:
			if absf(pts[k].x - x) < 0.006:
				on.append(pts[k])
		on.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.z < q.z)
		_link(on, adj)
	for z in aisle_zs():
		var on: Array[Vector3] = []
		for k in pts:
			if absf(pts[k].z - z) < 0.006:
				on.append(pts[k])
		on.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.x < q.x)
		_link(on, adj)
	var ka := _key(a)
	var kb := _key(b)
	var dist: Dictionary = {ka: 0.0}
	var prev: Dictionary = {}
	var open: Array = [ka]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur == kb:
			break
		for nb: Vector2i in adj[cur]:
			var nd: float = dist[cur] + _flat_dist(pts[cur], pts[nb])
			if nd < dist.get(nb, INF):
				dist[nb] = nd
				prev[nb] = cur
				open.append(nb)
	var rev: Array[Vector3] = []
	var k := kb
	rev.append(pts[k])
	while k != ka and prev.has(k):
		k = prev[k]
		rev.append(pts[k])
	rev.reverse()
	return rev


static func _link(sorted_pts: Array[Vector3], adj: Dictionary) -> void:
	for i in range(1, sorted_pts.size()):
		var k0 := _key(sorted_pts[i - 1])
		var k1 := _key(sorted_pts[i])
		if k0 == k1:
			continue
		if not (adj[k0] as Array).has(k1):
			(adj[k0] as Array).append(k1)
		if not (adj[k1] as Array).has(k0):
			(adj[k1] as Array).append(k0)


## Destino de patrulla: una intersección al azar distinta de `avoid` (lejos de ella al menos 2 m).
static func patrol_target(rng: RandomNumberGenerator, avoid: Vector3) -> Vector3:
	var ns := nodes()
	for _i in 12:
		var n: Vector3 = ns[rng.randi() % ns.size()]
		if _flat_dist(n, avoid) >= 2.0:
			return n
	return ns[rng.randi() % ns.size()]


## Índice de la mesa cuyo centro está más cerca de `p`. Con `only` no vacío, solo entre esas mesas.
static func nearest_table(p: Vector3, only: Array[int] = []) -> int:
	var best := 0
	var best_d := INF
	for i in HallLayout.table_count():
		if not only.is_empty() and not only.has(i):
			continue
		var d := _flat_dist(HallLayout.table_position(i), p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Ruta que pasa por detrás de la silla del jugador (de un lado al otro), saliendo de `from`.
## Entra por el lado más cercano a `from` y sale por el opuesto.
static func behind_player_route(from: Vector3) -> Array[Vector3]:
	var xs := aisle_xs()
	var z := behind_player_z()
	var human_col := HallLayout.cell_of(HallLayout.human_table).x
	var left := Vector3(xs[human_col], 0.0, z)       # pasillo a la izquierda de la mesa del humano
	var right := Vector3(xs[human_col + 1], 0.0, z)  # y a la derecha
	var first := left if _flat_dist(from, left) <= _flat_dist(from, right) else right
	var second := right if first == left else left
	var out := route(from, first)
	out.append(second)
	return out


# --- Patrulla alrededor de las partidas activas ------------------------------------------------

## Índices (columna de pasillo, fila de pasillo) de las cuatro esquinas de la mesa `table`.
static func table_corners(table: int) -> Array[Vector2i]:
	var c := HallLayout.cell_of(table)
	return [Vector2i(c.x, c.y), Vector2i(c.x + 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x + 1, c.y + 1)]


## Posición en el mundo de un nodo de la red por sus índices (columna, fila de pasillo).
static func node_at(ij: Vector2i) -> Vector3:
	return Vector3(aisle_xs()[ij.x], 0.0, aisle_zs()[ij.y])


## Tramos de pasillo permitidos: los cuatro lados de cada mesa activa. Devuelve la adyacencia
## {Vector2i: Array[Vector2i]} entre nodos vecinos de la cuadrícula de pasillos.
static func active_adjacency(tables: Array[int]) -> Dictionary:
	var adj: Dictionary = {}
	for t in tables:
		var co := table_corners(t)  # (x,y), (x+1,y), (x,y+1), (x+1,y+1)
		for pair in [[0, 1], [2, 3], [0, 2], [1, 3]]:
			var a: Vector2i = co[pair[0]]
			var b: Vector2i = co[pair[1]]
			if not adj.has(a):
				adj[a] = []
			if not adj.has(b):
				adj[b] = []
			if not (adj[a] as Array).has(b):
				(adj[a] as Array).append(b)
			if not (adj[b] as Array).has(a):
				(adj[b] as Array).append(a)
	return adj


## Nodo permitido más cercano a `p`.
static func nearest_active_node(p: Vector3, adj: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for ij: Vector2i in adj:
		var d := _flat_dist(node_at(ij), p)
		if d < best_d:
			best_d = d
			best = ij
	return best


## Camino por nodos permitidos (BFS por número de tramos; la cuadrícula es regular).
## Vacío si no hay conexión. Incluye ambos extremos.
static func active_path(a: Vector2i, b: Vector2i, adj: Dictionary) -> Array[Vector2i]:
	var prev: Dictionary = {a: a}
	var open: Array[Vector2i] = [a]
	while not open.is_empty():
		var cur: Vector2i = open.pop_front()
		if cur == b:
			break
		for nb: Vector2i in adj.get(cur, []):
			if not prev.has(nb):
				prev[nb] = cur
				open.append(nb)
	var out: Array[Vector2i] = []
	if not prev.has(b):
		return out
	var k := b
	out.append(k)
	while k != a:
		k = prev[k]
		out.append(k)
	out.reverse()
	return out


## Ruta de patrulla desde `from`: va a una esquina al azar de una mesa activa (distinta de
## donde está, si puede) y solo usa pasillos que bordean mesas activas. Hasta el primer nodo
## permitido sale por la red normal. Vacía si no hay mesas activas.
static func patrol_route(rng: RandomNumberGenerator, from: Vector3, tables: Array[int]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if tables.is_empty():
		return out
	var adj := active_adjacency(tables)
	var start := nearest_active_node(from, adj)
	var keys: Array = adj.keys()
	var target := start
	for _i in 12:
		var cand: Vector2i = keys[rng.randi() % keys.size()]
		if _flat_dist(node_at(cand), from) >= 2.0:
			target = cand
			break
	out.append_array(route(from, node_at(start)))
	var path := active_path(start, target, adj)
	for i in range(1, path.size()):
		out.append(node_at(path[i]))
	return out
