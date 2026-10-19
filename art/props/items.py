"""Reloj de ajedrez, planilla, pluma y pistola."""
import math

from lib import *  # noqa: F401,F403

X90 = (math.pi / 2, 0, 0)


def reloj():
	reset()
	coleccion("ChessClock")
	raiz = empty("ChessClock", tipo='PLAIN_AXES', tam=0.06)
	W, L, H = 0.15, 0.18, 0.085   # X, Y de Blender (= Z de Godot, entre jugadores), Z
	cuerpo = [
		(tbox((W, L), (W - 0.01, L - 0.01), 0.008, H), "Clock_Case"),
		(box(W + 0.01, L + 0.01, 0.008, (0, 0, 0.004)), "Metal_Aged"),    # base
	]
	for sy in (-1, 1):
		yf = sy * L / 2
		for sx in (-1, 1):
			cx, cz = sx * 0.034, 0.045
			# bisel de latón y esfera, ejes a lo largo de Y
			cuerpo.append((xf(cyl(0.033, 0.033, 0.0, 0.004, 12), (cx, yf - sy * 0.002, cz), (-sy * math.pi / 2, 0, 0)), "Brass"))
			cuerpo.append((xf(cyl(0.030, 0.030, 0.0, 0.005, 12), (cx, yf - sy * 0.002, cz), (-sy * math.pi / 2, 0, 0)), "Dial_White"))
			for k in range(12):
				a = math.pi * 2 * k / 12
				l = 0.006 if k % 3 == 0 else 0.003
				r = 0.026 - l / 2
				cuerpo.append((box(0.002, 0.0008, l, (cx + r * math.sin(a), yf + sy * 0.0034, cz + r * math.cos(a))), "Tick_Black"))
	obj("ClockBody", cuerpo, parent=raiz)
	# botones sobre la tapa (se hunden en -Z local): origen en la base del botón
	obj("Button_A", [(cyl(0.017, 0.015, 0.0, 0.014, 10), "Button_A")], (0, -0.05, H), parent=raiz)
	obj("Button_B", [(cyl(0.017, 0.015, 0.0, 0.014, 10), "Button_B")], (0, 0.05, H), parent=raiz)
	# Face_X: +Z local (Godot) = normal saliente de la cara; +Y = arriba
	empty("Face_A", (0, -L / 2, 0.045), (0, 0, 0), raiz, 'ARROWS', 0.03)
	empty("Face_B", (0, L / 2, 0.045), (0, 0, math.pi), raiz, 'ARROWS', 0.03)
	# agujas: pivote en el centro de cada esfera; apuntan a las 12; rotar sobre Z local (Godot)
	aguja = [(box(0.003, 0.0012, 0.027, (0, 0, 0.0115)), "Hand_Black"), (box(0.006, 0.0012, 0.006, (0, 0, -0.004)), "Hand_Black")]
	# "Left/Right" = como las ve el jugador de ese lado
	lado = {"A": (-1, -L / 2, 0.0), "B": (1, L / 2, math.pi)}
	for nombre, (sgn, yf, rz) in lado.items():
		sy = -1 if nombre == "A" else 1
		for pos, sx in (("Left", sgn * 0.034), ("Right", -sgn * 0.034)):
			obj(f"Hand_{nombre}_{pos}", aguja, (sx, yf + sy * 0.0062, 0.045), (0, 0, rz), raiz)
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
