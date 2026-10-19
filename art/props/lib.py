"""Utilidades comunes para construir la utilería (Blender 5.x, sin interfaz).

Geometría en Python puro: cada forma es (verts, faces) y se combina en un objeto
con una lista de (forma, nombre_de_material). Sombreado plano, sin texturas.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
ART = os.path.dirname(AQUI)
RAIZ = os.path.dirname(ART)
sys.path.insert(0, ART)
import export_glb  # noqa: E402

# nombre: (color RGB, rugosidad, metálico, emisión o None)
PALETA = {
	"Wood_Dark": ((0.16, 0.085, 0.045), 0.65, 0.0, None),
	"Wood_Mid": ((0.30, 0.17, 0.09), 0.6, 0.0, None),
	"Wood_Light": ((0.55, 0.40, 0.24), 0.6, 0.0, None),
	"Upholstery": ((0.30, 0.05, 0.06), 0.9, 0.0, None),
	"Metal_Aged": ((0.20, 0.20, 0.19), 0.5, 0.8, None),
	"Metal_Blued": ((0.07, 0.08, 0.09), 0.4, 0.9, None),
	"Brass": ((0.55, 0.40, 0.14), 0.4, 0.9, None),
	"Shade_Green": ((0.07, 0.17, 0.12), 0.5, 0.5, None),
	"Shade_Inner": ((0.85, 0.82, 0.72), 0.7, 0.0, None),
	"Bulb": ((1.0, 0.85, 0.55), 0.3, 0.0, (1.0, 0.8, 0.45)),
	"Cable": ((0.03, 0.03, 0.03), 0.8, 0.0, None),
	"Light": ((0.86, 0.78, 0.60), 0.7, 0.0, None),
	"Dark": ((0.20, 0.10, 0.05), 0.7, 0.0, None),
	"Board_Frame": ((0.12, 0.065, 0.035), 0.6, 0.0, None),
	"Piece": ((0.8, 0.8, 0.8), 0.6, 0.0, None),
	"Clock_Case": ((0.07, 0.06, 0.05), 0.5, 0.2, None),
	"Clock_Wood_A": ((0.105, 0.052, 0.028), 0.6, 0.0, None),
	"Clock_Wood_B": ((0.125, 0.064, 0.034), 0.6, 0.0, None),
	"Clock_Wood_C": ((0.088, 0.043, 0.024), 0.6, 0.0, None),
	"Clock_Plastic": ((0.03, 0.03, 0.03), 0.7, 0.0, None),
	"LCD_Glass": ((0.40, 0.48, 0.38), 0.35, 0.0, None),
	"LCD_Bezel": ((0.05, 0.045, 0.04), 0.5, 0.0, None),
	"Rocker_White": ((0.62, 0.62, 0.60), 0.45, 0.0, None),
	"Rocker_Red": ((0.45, 0.04, 0.04), 0.45, 0.0, None),
	"Key_White": ((0.70, 0.70, 0.67), 0.5, 0.0, None),
	"Key_Mark": ((0.08, 0.08, 0.08), 0.6, 0.0, None),
	"Dial_White": ((0.88, 0.85, 0.74), 0.6, 0.0, None),
	"Tick_Black": ((0.02, 0.02, 0.02), 0.8, 0.0, None),
	"Hand_Black": ((0.01, 0.01, 0.01), 0.6, 0.0, None),
	"Button_A": ((0.55, 0.06, 0.05), 0.4, 0.0, None),
	"Button_B": ((0.08, 0.08, 0.08), 0.4, 0.0, None),
	"Hardboard": ((0.30, 0.20, 0.11), 0.8, 0.0, None),
	"Paper": ((0.88, 0.86, 0.78), 0.9, 0.0, None),
	"Ink_Line": ((0.25, 0.30, 0.45), 0.9, 0.0, None),
	"Pen_Body": ((0.03, 0.04, 0.10), 0.3, 0.0, None),
	"Wood_Grip": ((0.22, 0.10, 0.05), 0.5, 0.0, None),
	"Wall_Wood": ((0.14, 0.08, 0.05), 0.7, 0.0, None),
	"Stone": ((0.28, 0.27, 0.25), 0.9, 0.0, None),
	"Banner_Red": ((0.38, 0.04, 0.05), 0.9, 0.0, None),
	"Banner_Gold": ((0.62, 0.46, 0.15), 0.6, 0.3, None),
}
_mats = {}


def mat(nombre):
	if nombre in _mats:
		return _mats[nombre]
	col, rug, met, emi = PALETA[nombre]
	m = bpy.data.materials.new(nombre)
	m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = (*col, 1.0)
	b.inputs["Roughness"].default_value = rug
	b.inputs["Metallic"].default_value = met
	if emi:
		b.inputs["Emission Color"].default_value = (*emi, 1.0)
		b.inputs["Emission Strength"].default_value = 3.0
	m.diffuse_color = (*col, 1.0)
	_mats[nombre] = m
	return m


# ---------- geometría ----------
_CARAS_CAJA = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]


def box(sx, sy, sz, c=(0, 0, 0)):
	x, y, z = sx / 2, sy / 2, sz / 2
	v = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
		(-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
	return ([(a + c[0], b + c[1], d + c[2]) for a, b, d in v], list(_CARAS_CAJA))


def tbox(b, t, z0, z1, c=(0, 0)):
	"""Prisma cuadrangular que se afina: b=(x,y) abajo, t=(x,y) arriba."""
	bx, by, tx, ty = b[0] / 2, b[1] / 2, t[0] / 2, t[1] / 2
	v = [(-bx, -by, z0), (bx, -by, z0), (bx, by, z0), (-bx, by, z0),
		(-tx, -ty, z1), (tx, -ty, z1), (tx, ty, z1), (-tx, ty, z1)]
	return ([(a + c[0], b_ + c[1], d) for a, b_, d in v], list(_CARAS_CAJA))


def quad(sx, sy, c=(0, 0, 0)):
	"""Plano horizontal que mira a +Z."""
	x, y = sx / 2, sy / 2
	return ([(-x + c[0], -y + c[1], c[2]), (x + c[0], -y + c[1], c[2]),
		(x + c[0], y + c[1], c[2]), (-x + c[0], y + c[1], c[2])], [(0, 1, 2, 3)])


def lathe(perfil, seg=8, c=(0, 0), giro=0.0):
	"""Revolución alrededor de Z. perfil = [(r, z), ...] de abajo arriba (normales hacia fuera)."""
	p = [perfil[0]]
	for q in perfil[1:]:
		if q != p[-1]:
			p.append(q)
	verts, anillos = [], []
	for r, z in p:
		if r == 0:
			anillos.append([len(verts)] * seg)
			verts.append((c[0], c[1], z))
		else:
			ids = []
			for j in range(seg):
				a = giro + 2 * math.pi * j / seg
				ids.append(len(verts))
				verts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a), z))
			anillos.append(ids)
	caras = []
	for i in range(len(p) - 1):
		for j in range(seg):
			j2 = (j + 1) % seg
			q = [anillos[i][j], anillos[i][j2], anillos[i + 1][j2], anillos[i + 1][j]]
			d = [q[k] for k in range(4) if q[k] != q[(k - 1) % 4]]
			if len(d) >= 3:
				caras.append(tuple(d))
	return (verts, caras)


def cyl(r0, r1, z0, z1, seg=8, c=(0, 0), giro=0.0):
	return lathe([(0, z0), (r0, z0), (r1, z1), (0, z1)], seg, c, giro)


def xf(g, loc=(0, 0, 0), rot=(0, 0, 0)):
	"""Gira (Euler XYZ, radianes) y luego traslada una forma."""
	m = Matrix.Translation(loc) @ Euler(rot, 'XYZ').to_matrix().to_4x4()
	return ([tuple(m @ Vector(v)) for v in g[0]], g[1])


# ---------- objetos ----------
_col = {}


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.preferences.filepaths.save_version = 0
	_mats.clear()
	_col.clear()


def coleccion(nombre):
	c = bpy.data.collections.new(nombre)
	bpy.context.scene.collection.children.link(c)
	_col["actual"] = c
	return c


def obj(nombre, partes, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
	"""partes = [(forma, material), ...] -> un objeto malla con un slot por material."""
	verts, caras, mids, nombres = [], [], [], []
	for g, mn in partes:
		if mn not in nombres:
			nombres.append(mn)
		o = len(verts)
		verts += g[0]
		for f in g[1]:
			caras.append(tuple(i + o for i in f))
			mids.append(nombres.index(mn))
	me = bpy.data.meshes.new(nombre)
	me.from_pydata(verts, [], caras)
	for mn in nombres:
		me.materials.append(mat(mn))
	for p, mi in zip(me.polygons, mids):
		p.material_index = mi
		p.use_smooth = False
	me.update()
	ob = bpy.data.objects.new(nombre, me)
	_col["actual"].objects.link(ob)
	ob.location, ob.rotation_euler = loc, rot
	if parent:
		ob.parent = parent
	return ob


def empty(nombre, loc=(0, 0, 0), rot=(0, 0, 0), parent=None, tipo='PLAIN_AXES', tam=0.03):
	e = bpy.data.objects.new(nombre, None)
	e.empty_display_type, e.empty_display_size = tipo, tam
	_col["actual"].objects.link(e)
	e.location, e.rotation_euler = loc, rot
	if parent:
		e.parent = parent
	return e


def guardar(rel):
	"""Guarda art/props/<rel>.blend y exporta assets/models/props/<rel>.glb. Devuelve triángulos."""
	b = os.path.join(AQUI, rel + ".blend")
	os.makedirs(os.path.dirname(b), exist_ok=True)
	bpy.ops.wm.save_as_mainfile(filepath=b, compress=False)
	return export_glb.export(os.path.join(RAIZ, "assets", "models", "props", rel + ".glb"))
