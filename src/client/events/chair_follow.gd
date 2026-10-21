class_name ChairFollow
extends RefCounted
## Retirada de la silla calculada a partir de la pose REAL de la figura (no de un tween fijo).
##
## Trabaja en el marco de la silla: +Z hacia la mesa (la dirección a la que mira la figura sentada),
## Y arriba, origen en el centro del asiento a ras de suelo. La silla se retira `r` metros por -Z.
## `need` mide cuánto hay que retirarla para que las piernas (muslos, rodillas y tobillos por
## debajo del asiento) no la atraviesen; `desired` es la retirada "de guion" según la altura de la
## pelvis; el resultado es el mayor de los dos, así que si cambia el clip la silla sigue al cuerpo.

## Mitad del asiento (m) y altura de su cara superior.
const SEAT_HALF := 0.22
const SEAT_TOP := 0.44
## Radio de las piernas (m) y holgura extra que se deja entre ellas y la silla.
const LEG_RADIUS := 0.07
const MARGIN := 0.08
## Altura de la pelvis sentado y de pie (m): da el avance del movimiento de levantarse.
const HIPS_SEATED := 0.54
const HIPS_STANDING := 0.86
## Velocidad máxima (m/s) a la que la silla va hacia su retirada "de guion".
const SPEED := 1.6
## Huesos (sin lado) que forman la pierna, de la cadera al tobillo.
const LEG_BONES: Array[String] = ["Thigh", "Shin", "Foot"]


## Retirada mínima (m, >= 0) para que las piernas de `fig` no atraviesen la silla que está en
## `home` (transformación mundial de la silla en su sitio). Cuenta solo lo que queda bajo la cara
## superior del asiento y dentro de su ancho: lo que está encima (muslos apoyados) no choca.
static func need(fig: CharacterFigure, home: Transform3D) -> float:
	var inv := home.affine_inverse()
	var worst := 0.0
	for side in ["L", "R"]:
		var pts: Array[Vector3] = []
		for b in LEG_BONES:
			pts.append(inv * fig.bone_global(StringName("%s.%s" % [b, side])).origin)
		for i in range(pts.size() - 1):
			for k in 7:
				var p := pts[i].lerp(pts[i + 1], k / 6.0)
				if p.y >= SEAT_TOP or absf(p.x) > SEAT_HALF + LEG_RADIUS:
					continue
				worst = maxf(worst, SEAT_HALF - p.z + LEG_RADIUS)
	return worst


## Avance (0-1) de la pelvis entre sentado y de pie.
static func rise_progress(fig: CharacterFigure, home: Transform3D) -> float:
	var y: float = (home.affine_inverse() * fig.bone_global(&"Hips").origin).y
	return clampf(inverse_lerp(HIPS_SEATED, HIPS_STANDING, y), 0.0, 1.0)


## Retirada "de guion" (m) para el avance `p` de la pelvis: sale mientras sube y vuelve a la par
## mientras baja (al sentarse `p` decrece). `full` = retirada final de pie.
static func desired(p: float, full: float) -> float:
	return full * smoothstep(0.0, 0.85, p)


## Un paso: nueva retirada a partir de la actual `r`. Nunca baja de `need + MARGIN` (con la holgura
## desvaneciéndose a 0 al acabar si `fade` = 1) ni de `floor_r` (retirada mínima del contrato);
## hacia `want` se mueve a lo sumo `SPEED * dt`.
static func step(r: float, need_r: float, want: float, floor_r: float, dt: float, fade: float = 0.0) -> float:
	var moved := move_toward(r, want, SPEED * dt)
	var safe := need_r + MARGIN * (1.0 - fade) if need_r > 0.0 else 0.0
	return maxf(maxf(moved, safe), floor_r)
