"""Ambientación del salón. Frente = +Z de Godot (-Y de Blender); la espalda queda en el plano y=0."""
import math

from lib import *  # noqa: F401,F403


def columna():
	reset()
	coleccion("Pillar")
	# origen en el suelo, centro de la columna; altura 3.0 m
	obj("Pillar", [
		(cyl(0.34, 0.34, 0.0, 0.12, 8, giro=math.pi / 8), "Stone"),
		(cyl(0.26, 0.24, 0.12, 2.75, 8, giro=math.pi / 8), "Stone"),
		(cyl(0.30, 0.30, 2.75, 2.90, 8, giro=math.pi / 8), "Stone"),
		(box(0.62, 0.62, 0.10, (0, 0, 2.95)), "Stone"),
		(cyl(0.27, 0.27, 0.60, 0.66, 8, giro=math.pi / 8), "Brass"),
	])
	return guardar("pillar")


def puerta():
	reset()
	coleccion("Door")
	raiz = empty("Door", tipo='PLAIN_AXES', tam=0.1)
	# vano de 1.7 x 2.4 m; origen en el suelo, centro del vano, cara frontal hacia -Y (Godot +Z)
	m = [(box(0.12, 0.14, 2.45, (-0.91, 0.07, 1.225)), "Wood_Dark"),
		(box(0.12, 0.14, 2.45, (0.91, 0.07, 1.225)), "Wood_Dark"),
		(box(1.94, 0.14, 0.12, (0, 0.07, 2.46)), "Wood_Dark")]
	obj("DoorFrame", m, parent=raiz)
	for nombre, sgn in (("DoorLeaf_L", -1), ("DoorLeaf_R", 1)):
		# la hoja gira sobre su bisagra exterior: el origen del objeto es la bisagra
		bx = sgn * 0.85
		hoja = [(box(0.84, 0.04, 2.38, (-sgn * 0.42, 0.07, 1.20)), "Wall_Wood")]
		for pz in (0.65, 1.75):
			hoja.append((box(0.60, 0.02, 0.80 if pz < 1 else 0.90, (-sgn * 0.42, 0.05, pz)), "Wood_Dark"))
		hoja.append((box(0.03, 0.05, 0.14, (-sgn * 0.78, 0.04, 1.05)), "Brass"))
		obj(nombre, hoja, (bx, 0, 0), parent=raiz)
	return guardar("door")


def panel():
	reset()
	coleccion("WallPanel")
	# zócalo de madera de 1.0 m de ancho x 1.2 m de alto; origen en el suelo, centro; sobresale hacia -Y
	obj("WallPanel", [
		(box(1.0, 0.03, 1.2, (0, -0.015, 0.6)), "Wall_Wood"),
		(box(0.84, 0.02, 0.84, (0, -0.04, 0.60)), "Wood_Dark"),
		(box(1.04, 0.06, 0.07, (0, -0.03, 1.235)), "Wood_Mid"),
		(box(1.0, 0.05, 0.10, (0, -0.025, 0.05)), "Wood_Mid"),
	])
	return guardar("wall_panel")


def estandarte():
	reset()
	coleccion("Banner")
	# origen en el centro de la barra superior; cuelga hacia -Z; frente hacia -Y (Godot +Z)
	obj("Banner", [
		(xf(cyl(0.012, 0.012, -0.45, 0.45, 6), (0, 0, 0), (0, math.pi / 2, 0)), "Banner_Gold"),
		(box(0.8, 0.01, 1.6, (0, 0, -0.82)), "Banner_Red"),
		(box(0.7, 0.012, 0.04, (0, -0.001, -1.55)), "Banner_Gold"),
		(box(0.06, 0.012, 0.50, (0, -0.001, -0.72)), "Banner_Gold"),
		(box(0.30, 0.012, 0.06, (0, -0.001, -0.62)), "Banner_Gold"),
		(tbox((0.02, 0.01), (0.02, 0.01), -1.64, -1.6, (-0.35, 0)), "Banner_Gold"),
		(tbox((0.02, 0.01), (0.02, 0.01), -1.64, -1.6, (0.35, 0)), "Banner_Gold"),
	])
	return guardar("banner")
