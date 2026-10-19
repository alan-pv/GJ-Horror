"""Juego de piezas: un .blend/.glb por pieza, material único "Piece". Origen en el centro de la base."""
import math

from lib import *  # noqa: F401,F403

S = 10  # lados de las revoluciones


def peon():
	return [(lathe([(0, 0), (.02, 0), (.02, .004), (.015, .008), (.0085, .018), (.0115, .024),
		(.0115, .028), (.0105, .031), (.0125, .035), (.0105, .040), (.005, .0445), (0, .045)], S), "Piece")]


def torre():
	g = [(lathe([(0, 0), (.02, 0), (.02, .005), (.0145, .01), (.0125, .03), (.0165, .034),
		(.0165, .04), (0, .04)], S), "Piece")]
	for sx in (-1, 1):
		for sy in (-1, 1):
			g.append((box(.009, .009, .01, (sx * .0115, sy * .0115, .045)), "Piece"))
	return g


def alfil():
	return [(lathe([(0, 0), (.02, 0), (.02, .005), (.015, .01), (.009, .022), (.013, .027),
		(.009, .031), (.0145, .040), (.012, .050), (.006, .0565), (.004, .058), (.004, .0585),
		(0, .06)], S), "Piece")]


def caballo():
	g = [(lathe([(0, 0), (.02, 0), (.02, .005), (.0155, .01), (.0145, .014), (0, .014)], S), "Piece")]
	g.append((tbox((.026, .026), (.018, .020), .014, .034, (0, 0)), "Piece"))              # torso/cuello
	g.append((xf(box(.014, .034, .016), (0, .009, .046), (-.35, 0, 0)), "Piece"))           # cabeza hacia +Y
	g.append((xf(box(.012, .016, .010), (0, .026, .0455), (-.55, 0, 0)), "Piece"))          # hocico
	g.append((box(.003, .006, .008, (-.005, -.003, .0525)), "Piece"))                       # orejas
	g.append((box(.003, .006, .008, (.005, -.003, .0525)), "Piece"))
	g.append((xf(box(.004, .014, .016), (0, -.012, .042), (.5, 0, 0)), "Piece"))            # crin
	return g


def dama():
	g = [(lathe([(0, 0), (.02, 0), (.02, .005), (.015, .010), (.0095, .025), (.015, .037),
		(.0105, .042), (.0105, .056), (.0175, .066), (.0175, .069), (.012, .071),
		(.006, .071), (0, .071)], 12), "Piece")]
	g.append((lathe([(0, .071), (.006, .071), (.0045, .075), (0, .075)], 6), "Piece"))
	for k in range(6):  # puntas de la corona
		a = math.pi * 2 * k / 6
		g.append((cyl(.0035, 0, .069, .0745, 4, (.0155 * math.cos(a), .0155 * math.sin(a))), "Piece"))
	return g


def rey():
	g = [(lathe([(0, 0), (.02, 0), (.02, .005), (.0155, .011), (.01, .028), (.0165, .042),
		(.0115, .048), (.0115, .054), (.0185, .062), (.0185, .065), (.0125, .068), (.0, .068)], 12), "Piece")]
	g.append((box(.006, .006, .027, (0, 0, .0815)), "Piece"))   # cruz
	g.append((box(.018, .006, .006, (0, 0, .086)), "Piece"))
	return g


PIEZAS = {"pawn": ("Pawn", peon, .045), "rook": ("Rook", torre, .05), "knight": ("Knight", caballo, .055),
	"bishop": ("Bishop", alfil, .06), "queen": ("Queen", dama, .075), "king": ("King", rey, .095)}


def todas():
	res = {}
	for clave, (nombre, fn, _h) in PIEZAS.items():
		reset()
		coleccion("Piece_" + nombre)
		obj(nombre, fn())
		res[clave] = guardar("pieces/" + clave)
	return res
