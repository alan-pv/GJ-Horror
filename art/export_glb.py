"""Exporta el .blend abierto a .glb (sin cámaras ni luces, sin la colección "Reference").

Uso:  blender --background art/<ruta>.blend --python art/export_glb.py -- <salida.glb>
También se importa desde los scripts de construcción (export(ruta)).
"""
import os
import sys

import bpy


def _en_reference(obj):
	"""True si el objeto vive en una colección llamada Reference (o dentro de una)."""
	padres = {}
	for c in bpy.data.collections:
		for h in c.children:
			padres.setdefault(h, []).append(c)

	def sube(col):
		return col.name == "Reference" or any(sube(p) for p in padres.get(col, []))

	return any(sube(c) for c in obj.users_collection)


def export(ruta):
	os.makedirs(os.path.dirname(os.path.abspath(ruta)), exist_ok=True)
	if bpy.context.object and bpy.context.object.mode != 'OBJECT':
		bpy.ops.object.mode_set(mode='OBJECT')
	bpy.ops.object.select_all(action='DESELECT')
	n = 0
	for o in bpy.context.scene.objects:
		if o.type in {'CAMERA', 'LIGHT'} or _en_reference(o):
			continue
		o.hide_set(False)
		o.select_set(True)
		n += 1
	bpy.ops.export_scene.gltf(
		filepath=ruta, export_format='GLB', use_selection=True,
		export_cameras=False, export_lights=False, export_apply=True,
		export_yup=True, export_texcoords=False, export_image_format='NONE',
	)
	tris = 0
	dg = bpy.context.evaluated_depsgraph_get()
	for o in bpy.context.selected_objects:
		if o.type == 'MESH':
			tris += sum(len(p.vertices) - 2 for p in o.evaluated_get(dg).data.polygons)
	print(f"[export_glb] {ruta}: {n} objetos, {tris} triangulos")
	return tris


if __name__ == "__main__":
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	if not args:
		sys.exit("Uso: blender --background x.blend --python art/export_glb.py -- salida.glb")
	export(args[0])
