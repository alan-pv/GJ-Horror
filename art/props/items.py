"""Reloj de ajedrez, planilla, pluma y pistola."""
import math

from lib import *  # noqa: F401,F403

X90 = (math.pi / 2, 0, 0)


def _prisma(perfil, y0, y1):
	"""Extrusión a lo largo de Y de un perfil convexo (x, z); normales hacia fuera."""
	n = len(perfil)
	v = [(x, y0, z) for x, z in perfil] + [(x, y1, z) for x, z in perfil]
	f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
	f.append(tuple(range(n)))
	f.append(tuple(n + i for i in range(n)))
	c = [sum(p[k] for p in v) / len(v) for k in range(3)]
	out = []
	for cara in f:
		a, b, d = (Vector(v[cara[k]]) for k in range(3))
		nor = (b - a).cross(d - b)
		cen = sum((Vector(v[i]) for i in cara), Vector()) / len(cara)
		out.append(cara if nor.dot(cen - Vector(c)) > 0 else tuple(reversed(cara)))
	return (v, out)


def _mx(g, m):
	return ([tuple(m @ Vector(p)) for p in g[0]], g[1])


def reloj():
	"""Reloj digital de torneo. Frente (LCD) hacia -X de Blender (= -X de Godot): el reloj va a un
	costado del tablero (en +X) y mira al centro. Visto de frente, la derecha es -Y de Blender
	(= +Z de Godot). Origen: centro de la base."""
	reset()
	coleccion("ChessClock")
	raiz = empty("ChessClock", tipo='PLAIN_AXES', tam=0.06)
	# perfil lateral (x, z): frente inclinado ~17 grados hacia atras, chaflan y cubierta
	B0 = Vector((-0.030, 0.003))
	P = [(-0.030, 0.003), (0.030, 0.003), (0.030, 0.082), (-0.002, 0.082), (-0.007, 0.076)]
	W2 = 0.081
	v2 = Vector((0.023, 0.073)).normalized()      # a lo largo de la pendiente (x, z)
	n2 = Vector((-v2.y, v2.x))                      # normal saliente (x, z)
	L = 0.0794
	# base de ejes de la pendiente: X_l = derecha del jugador (-Y), Y_l = subida, Z_l = normal
	Bm = Matrix(((0, v2.x, n2.x), (-1, 0, 0), (0, v2.y, n2.y)))

	def sobre(u, t, off=0.0):
		"""Punto de la pendiente a derecha u y altura t (a lo largo de ella)."""
		return Vector((B0.x + v2.x * t + n2.x * off, -u, B0.y + v2.y * t + n2.y * off))

	def plano(g, u, t, off=0.0):
		return _mx(g, Matrix.Translation(sobre(u, t, off)) @ Bm.to_4x4())

	cuerpo = []
	mats = ["Clock_Wood_A", "Clock_Wood_B", "Clock_Wood_A", "Clock_Wood_C", "Clock_Wood_B", "Clock_Wood_C"]
	n = len(mats)
	for i, m in enumerate(mats):   # veteado: franjas de tonos de madera ligeramente distintos
		cuerpo.append((_prisma(P, -W2 + 2 * W2 * i / n, -W2 + 2 * W2 * (i + 1) / n), m))
	inset = [(x * 0.92, z * 0.96 + 0.003) for x, z in P]
	cuerpo.append((_prisma(inset, -W2 - 0.004, W2 + 0.004), "Clock_Wood_C"))   # bisel de los costados
	cuerpo.append((box(0.062, 0.176, 0.003, (0, 0, 0.0015)), "Clock_Plastic"))   # zócalo
	# pivote del balancín
	cuerpo.append((box(0.020, 0.030, 0.006, (0.012, 0, 0.085)), "Clock_Plastic"))
	# marco del LCD y soportes
	LW, LH, LT = 0.150, 0.048, 0.0015
	tc = 0.0475
	mw = 0.0028
	marco = [(box(LW + 2 * mw, mw, 0.0026, (0, tc + LH / 2 + mw / 2, 0.0013)), "LCD_Bezel"),
		(box(LW + 2 * mw, mw, 0.0026, (0, tc - LH / 2 - mw / 2, 0.0013)), "LCD_Bezel"),
		(box(mw, LH, 0.0026, (LW / 2 + mw / 2, tc, 0.0013)), "LCD_Bezel"),
		(box(mw, LH, 0.0026, (-LW / 2 - mw / 2, tc, 0.0013)), "LCD_Bezel")]
	for g, m in marco:
		cuerpo.append((plano(g, 0, 0), m))
	# la rejilla se mide en coordenadas locales de la pendiente: box(sx, sy, sz, c) con c=(u, t, z)
	obj("ClockBody", cuerpo, parent=raiz)
	# LCD: losa gris verdosa (los dígitos los dibuja el juego sobre ella)
	obj("LCD", [(plano(box(LW, LH, LT, (0, tc, LT / 2)), 0, 0), "LCD_Glass")], parent=raiz)
	# ancla: centro del LCD sobre su superficie; +Z local = normal, +Y = arriba, +X = derecha del jugador
	e = empty("LCD_Anchor", tuple(sobre(0, tc, LT)), tipo='ARROWS', tam=0.02, parent=raiz)
	e.rotation_mode = 'XYZ'
	e.rotation_euler = Bm.to_euler('XYZ')
	# teclitas (decorativas): + / play-pausa / -, origen en la base de cada una
	kw, kh, kt = 0.020, 0.0085, 0.0025
	for i, (u, sig) in enumerate(((-0.05, "mas"), (0.0, "play"), (0.05, "menos")), start=1):
		partes = [(box(kw, kh, kt, (0, 0, kt / 2)), "Key_White")]
		z = kt + 0.0002
		if sig == "mas":
			partes += [(box(0.008, 0.0016, 0.0004, (0, 0, z)), "Key_Mark"), (box(0.0016, 0.008, 0.0004, (0, 0, z)), "Key_Mark")]
		elif sig == "menos":
			partes += [(box(0.008, 0.0016, 0.0004, (0, 0, z)), "Key_Mark")]
		else:
			partes += [(([(-0.0035, -0.0033, z), (0.0, -0.0033, z), (0.0, 0.0033, z), (-0.0035, 0.0033, z)], [(0, 1, 2, 3)]), "Key_Mark"),
				(([(0.0012, -0.0033, z), (0.0058, 0.0, z), (0.0012, 0.0033, z)], [(0, 1, 2)]), "Key_Mark")]
		k = obj(f"Button_{i}", partes, tuple(sobre(u, 0.0115)), parent=raiz)
		k.rotation_euler = Bm.to_euler('XYZ')
	# balancín: pivote en el centro de la cubierta, gira sobre X; mitad -Y (derecha del jugador,
	# lado de +Z de Godot) blanca y mitad +Y roja
	pz = 0.088
	rocker = empty("Rocker", (0.012, 0, pz), tipo='PLAIN_AXES', tam=0.03, parent=raiz)

	def mitad(sg, m):
		g = tbox((0.026, 0.074), (0.020, 0.068), -0.004, 0.009, (0, 0))
		g = xf(g, (0, sg * 0.0375, 0))
		return (g, m)

	cab = obj("RockerBar", [mitad(-1, "Rocker_White"), mitad(1, "Rocker_Red")], parent=rocker)
	# puntos de contacto (lado derecho = -Y = +Z de Godot, el de quien se sienta en +Z)
	empty("Contact_Right", (0, -0.045, 0.009), parent=rocker, tipo='SPHERE', tam=0.006)
	empty("Contact_Left", (0, 0.045, 0.009), parent=rocker, tipo='SPHERE', tam=0.006)
	return guardar("chess_clock")


def planilla():
	reset()
	coleccion("Scoresheet")
	raiz = empty("Scoresheet", tipo='PLAIN_AXES', tam=0.05)
	tab = [(box(0.16, 0.23, 0.006, (0, 0, 0.003)), "Hardboard")]
	obj("Clipboard", tab, parent=raiz)
	papel = [(box(0.148, 0.205, 0.0008, (0, -0.005, 0.0064)), "Paper")]
	obj("Sheet", papel, parent=raiz)
	lineas = []
	zl = 0.0069
	for i in range(24):  # renglones de jugadas
		y = -0.1 + i * 0.0072 - 0.005
		if y < 0.065:
			lineas.append((quad(0.136, 0.0004, (0, y, zl)), "Ink_Line"))
	for x in (-0.068, -0.045, 0.0, 0.045, 0.068):  # columnas: nº, blancas, negras
		lineas.append((quad(0.0004, 0.165, (x, -0.0175, zl)), "Ink_Line"))
	lineas.append((quad(0.136, 0.0004, (0, 0.067, zl)), "Ink_Line"))
	lineas.append((quad(0.100, 0.0008, (0, 0.088, zl)), "Ink_Line"))  # línea de título
	obj("SheetLines", lineas, parent=raiz)
	obj("Clip", [(box(0.06, 0.022, 0.008, (0, 0.104, 0.010)), "Metal_Aged"),
		(box(0.03, 0.012, 0.004, (0, 0.108, 0.0135)), "Metal_Aged")], parent=raiz)
	return guardar("scoresheet")


def pluma():
	reset()
	coleccion("Pen")
	# se construye a lo largo de +Z y se gira para que quede a lo largo de +X; origen = punta
	g = [
		(lathe([(0, 0), (0.0012, 0.0), (0.0035, 0.018), (0.0045, 0.019), (0.0055, 0.045),
			(0.0055, 0.125), (0.0045, 0.14), (0, 0.14)], 8), "Pen_Body"),
		(lathe([(0, 0), (0.0012, 0.0), (0.0030, 0.012), (0, 0.012)], 8), "Brass"),
		(box(0.0015, 0.0035, 0.045, (0.0062, 0, 0.1)), "Brass"),  # clip
	]
	g = [(xf(s, (0, 0, 0), (0, math.pi / 2, 0)), m) for s, m in g]
	obj("Pen", g)
	return guardar("pen")


def pistola():
	reset()
	coleccion("Pistol")
	raiz = empty("Pistol", tipo='PLAIN_AXES', tam=0.05)
	# cañón hacia +Y de Blender (= -Z de Godot, "adelante"); origen en el centro de la empuñadura
	inc = (-0.28, 0, 0)  # empuñadura inclinada: la base queda atrás
	cuerpo = [
		(xf(box(0.030, 0.034, 0.095), (0, -0.012, 0.005), inc), "Wood_Grip"),
		(box(0.026, 0.075, 0.030, (0, 0.0125, 0.045)), "Metal_Blued"),              # armazón
		(xf(cyl(0.021, 0.021, -0.022, 0.022, 6, giro=0.26), (0, 0.035, 0.045), (math.pi / 2, 0, 0)), "Metal_Blued"),  # tambor
		(xf(cyl(0.0105, 0.0095, 0, 0.125, 8), (0, 0.06, 0.05), (-math.pi / 2, 0, 0)), "Metal_Blued"),                # cañón
		(box(0.006, 0.010, 0.008, (0, 0.178, 0.0625)), "Metal_Blued"),              # mira
		(box(0.008, 0.020, 0.022, (0, -0.027, 0.07)), "Metal_Blued"),               # martillo
		(box(0.004, 0.008, 0.018, (0, 0.002, 0.021)), "Metal_Blued"),               # gatillo
		(box(0.004, 0.044, 0.004, (0, 0.017, 0.010)), "Metal_Blued"),               # guardamonte
		(box(0.004, 0.004, 0.020, (0, 0.039, 0.020)), "Metal_Blued"),
		(xf(box(0.034, 0.038, 0.008), (0, -0.0255, -0.042), inc), "Metal_Blued"),   # culatín
	]
	obj("PistolBody", cuerpo, parent=raiz)
	empty("Muzzle", (0, 0.185, 0.05), parent=raiz, tipo='ARROWS', tam=0.02)
	return guardar("pistol")
