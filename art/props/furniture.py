"""Mesa, silla, tablero y lámpara. Medidas en metros, Blender Z arriba."""
import math

from lib import *  # noqa: F401,F403


def mesa():
	reset()
	coleccion("Table")
	p = []
	# tablero de la mesa: superficie a 0.72 m, 1.3 (X) x 0.9 (Y de Blender = Z de Godot)
	p.append((box(1.30, 0.90, 0.04, (0, 0, 0.70)), "Wood_Mid"))
	p.append((box(1.34, 0.94, 0.012, (0, 0, 0.674)), "Wood_Dark"))  # canto saliente
	# faldón
	for sx in (-1, 1):
		p.append((box(0.03, 0.70, 0.11, (sx * 0.545, 0, 0.615)), "Wood_Dark"))
	for sy in (-1, 1):
		p.append((box(1.06, 0.03, 0.11, (0, sy * 0.335, 0.615)), "Wood_Dark"))
	# patas cónicas con regatón de latón
	for sx in (-1, 1):
		for sy in (-1, 1):
			c = (sx * 0.56, sy * 0.35)
			p.append((tbox((0.07, 0.07), (0.045, 0.045), 0.03, 0.67, c), "Wood_Dark"))
			p.append((tbox((0.035, 0.035), (0.07, 0.07), 0.0, 0.03, c), "Brass"))
	obj("Table", p)
	return guardar("table")


def silla():
	reset()
	coleccion("Chair")
	p = []
	# respaldo hacia +Y de Blender (= -Z de Godot); el jugador mira a -Y (= +Z de Godot)
	for sx in (-1, 1):
		for sy in (-1, 1):
			c = (sx * 0.19, sy * 0.19)
			alto = 0.92 if sy > 0 else 0.42
			p.append((tbox((0.045, 0.045), (0.032, 0.032), 0.0, alto, c), "Wood_Dark"))
	for sx in (-1, 1):  # travesaños laterales
		p.append((box(0.02, 0.36, 0.03, (sx * 0.19, 0, 0.22)), "Wood_Dark"))
	p.append((box(0.36, 0.02, 0.03, (0, -0.19, 0.22)), "Wood_Dark"))
	p.append((box(0.44, 0.44, 0.03, (0, 0, 0.405)), "Wood_Dark"))      # bastidor del asiento
	p.append((box(0.40, 0.40, 0.03, (0, 0, 0.435)), "Upholstery"))      # cojín (cara superior = 0.45)
	p.append((box(0.40, 0.025, 0.05, (0, 0.19, 0.89)), "Wood_Dark"))   # travesaño superior
	p.append((box(0.36, 0.02, 0.32, (0, 0.19, 0.64)), "Upholstery"))   # respaldo tapizado
	p.append((box(0.40, 0.025, 0.04, (0, 0.19, 0.46)), "Wood_Dark"))   # travesaño inferior
	obj("Chair", p)
	return guardar("chair")


def tablero():
	reset()
	coleccion("Board")
	raiz = empty("Board", tipo='PLAIN_AXES', tam=0.05)
	cas = 0.055
	sq = []
	for i in range(8):          # i = columna (a..h) hacia +X
		for j in range(8):      # j = fila (1..8) hacia +Y de Blender (= -Z de Godot)
			x = -0.1925 + i * cas
			y = -0.1925 + j * cas
			sq.append((quad(cas, cas, (x, y, 0.0)), "Dark" if (i + j) % 2 == 0 else "Light"))
	obj("BoardSquares", sq, parent=raiz)
	m = []
	m.append((box(0.44, 0.44, 0.008, (0, 0, -0.004)), "Board_Frame"))      # base bajo las casillas
	m.append((box(0.50, 0.03, 0.026, (0, -0.235, -0.002)), "Board_Frame"))  # marco
	m.append((box(0.50, 0.03, 0.026, (0, 0.235, -0.002)), "Board_Frame"))
	m.append((box(0.03, 0.44, 0.026, (-0.235, 0, -0.002)), "Board_Frame"))
	m.append((box(0.03, 0.44, 0.026, (0.235, 0, -0.002)), "Board_Frame"))
	m.append((box(0.50, 0.50, 0.006, (0, 0, -0.011)), "Board_Frame"))      # zócalo
	obj("BoardFrame", m, parent=raiz)
	return guardar("board")


def lampara():
	reset()
	coleccion("Lamp")
	raiz = empty("Lamp", tipo='PLAIN_AXES', tam=0.05)
	obj("LampCable", [(cyl(0.05, 0.05, -0.04, 0.0, 10), "Metal_Aged"),
		(cyl(0.004, 0.004, -0.93, -0.04, 6), "Cable")], parent=raiz)
	obj("LampShade", [
		(lathe([(0, -0.95), (0.28, -1.2)], 12), "Shade_Inner"),                  # interior
		(lathe([(0.28, -1.2), (0.30, -1.2), (0.055, -0.93), (0, -0.93)], 12), "Shade_Green"),
	], parent=raiz)
	obj("LampBulb", [
		(cyl(0.022, 0.022, -1.0, -0.93, 8), "Brass"),                              # casquillo
		(lathe([(0, -1.12), (0.022, -1.11), (0.04, -1.07), (0.04, -1.03), (0.022, -1.0), (0.0, -1.0)], 8), "Bulb"),
	], parent=raiz)
	empty("LightAnchor", (0, 0, -1.07), parent=raiz, tipo='SPHERE', tam=0.04)
	return guardar("lamp")
