class_name HallWalk
extends RefCounted
## Ruta del paseo del humano entre rondas (lógica pura, sin nodos). Todo en las coordenadas de
## la escena actual, donde la mesa del humano es el origen (`HallLayout.table_position`).
##
## Quien se levanta queda de pie a la altura de su silla (`seat_point`, z = `PlayerController.SEAT.z`),
## con la silla retirada hacia atrás: sale de lado por el hueco entre su silla y el borde de la mesa
## hasta el pasillo vertical más cercano, recorre los pasillos de `ArbiterRoutes` y entra de lado a la
## silla de la mesa nueva por el mismo hueco. Nunca atraviesa una mesa ajena.

## Cuánto se retira la silla al levantarse y antes de sentarse (m; los clips piden >= 0,40).
const CHAIR_BACK := 0.6
## Distancia del eje de la mesa al pasillo vertical contiguo.
const AISLE_X := HallLayout.SPACING_X * 0.5
## Semiextensión de la mesa propia (sin sillas): por ella no se puede pasar, por el hueco de su silla sí.
const OWN_TABLE_HALF := Vector2(0.72, 0.52)


## Suelo bajo el centro de la silla del humano (lado +Z) de la mesa `table`, sobre el podio si toca.
static func seat_point(table: int) -> Vector3:
	var p := HallLayout.table_position(table) + Vector3(0.0, 0.0, PlayerController.SEAT.z)
	p.y = HallLayout.floor_y(p)
	return p


## Ruta desde la silla de `from_table` hasta la de `to_table`: puntos a recorrer en orden (sin el
## de partida, con la silla de destino al final). Elige el lado de salida y de entrada que acorta el
## trayecto. Vacía si las mesas coinciden.
static func route(from_table: int, to_table: int) -> Array[Vector3]:
	if from_table == to_table:
		return []
	var start := seat_point(from_table)
	var goal := seat_point(to_table)
	var from_x := HallLayout.table_position(from_table).x
	var to_x := HallLayout.table_position(to_table).x
	var best: Array[Vector3] = []
	var best_len := INF
	for sx in [-1.0, 1.0]:
		for sd in [-1.0, 1.0]:
			var exit_pt := Vector3(from_x + sx * AISLE_X, 0.0, start.z)
			var enter_pt := Vector3(to_x + sd * AISLE_X, 0.0, goal.z)
			var path: Array[Vector3] = [exit_pt]
			path.append_array(ArbiterRoutes.route(exit_pt, enter_pt))
			if path[path.size() - 1].distance_to(enter_pt) > 0.01:
				path.append(enter_pt)
			path.append(Vector3(goal.x, 0.0, goal.z))
			var total := ArbiterRoutes.route_length(start, path)
			if total < best_len:
				best_len = total
				best = path
	for i in best.size():
		best[i].y = HallLayout.floor_y(best[i])
	return best


## ¿Algún tramo de la ruta (partiendo de la silla de `from_table`) atraviesa una mesa? Las dos
## mesas de los extremos solo cuentan por su tablero (no por sus sillas: se entra por el hueco).
static func is_blocked(from_table: int, to_table: int, path: Array[Vector3]) -> bool:
	var prev := seat_point(from_table)
	for p in path:
		if blocks_segment(from_table, to_table, prev, p):
			return true
		prev = p
	return false


static func blocks_segment(from_table: int, to_table: int, a: Vector3, b: Vector3) -> bool:
	for i in HallLayout.table_count():
		var c := HallLayout.table_position(i)
		var half := OWN_TABLE_HALF if (i == from_table or i == to_table) else ArbiterRoutes.TABLE_HALF
		var r := Rect2(c.x - half.x, c.z - half.y, half.x * 2.0, half.y * 2.0).grow(-0.01)
		if ArbiterRoutes.segment_hits_rect(a, b, r):
			return true
	return false


## Longitud (m) del paseo.
static func length(from_table: int, path: Array[Vector3]) -> float:
	return ArbiterRoutes.route_length(seat_point(from_table), path)


## Guiño de giro: yaw (rad) de la figura (que mira a +Z) para avanzar en la dirección `d` del suelo.
static func yaw_for(d: Vector3) -> float:
	return atan2(d.x, d.z)


## Punto de la ruta a `dist` metros por delante de `pos`, yendo hacia `path[i]` y siguiendo los
## tramos siguientes (se detiene en el último punto). Apuntar a él hace que el cuerpo empiece a
## girar antes del vértice sin cambiar la trayectoria.
static func look_ahead(pos: Vector3, path: Array[Vector3], i: int, dist: float) -> Vector3:
	var cur := Vector3(pos.x, 0.0, pos.z)
	var left := dist
	for k in range(i, path.size()):
		var tgt := Vector3(path[k].x, 0.0, path[k].z)
		var seg := tgt - cur
		var d := seg.length()
		if d >= left:
			return cur + seg / maxf(d, 0.0001) * left
		left -= d
		cur = tgt
	return cur


## Un paso del giro del cuerpo: resorte críticamente amortiguado (frecuencia `omega`, 1/s) hacia el
## rumbo `want` con la velocidad angular acotada a `max_speed` (rad/s). Devuelve (yaw, velocidad).
## Sin saltos: la velocidad angular es continua aunque `want` cambie de golpe.
static func smooth_yaw(yaw: float, vel: float, want: float, dt: float, omega: float, max_speed: float) -> Vector2:
	var steps := maxi(1, ceili(dt * 60.0))
	var h := dt / steps
	for _s in steps:
		var diff := angle_difference(yaw, want)
		vel += (omega * omega * diff - 2.0 * omega * vel) * h
		vel = clampf(vel, -max_speed, max_speed)
		yaw = wrapf(yaw + vel * h, -PI, PI)
	return Vector2(yaw, vel)
