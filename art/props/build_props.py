"""Construye TODA la utilería: guarda art/props/*.blend y exporta assets/models/props/*.glb.

    blender --background --python art/props/build_props.py [-- table chair ...]

OJO: regenerar sobrescribe los .blend. Si editaste uno a mano, reexporta con
tools/export_models.sh en vez de regenerar.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambient  # noqa: E402
import furniture  # noqa: E402
import items  # noqa: E402
import pieces  # noqa: E402

TODO = {
	"table": furniture.mesa, "chair": furniture.silla, "board": furniture.tablero,
	"lamp": furniture.lampara, "chess_clock": items.reloj, "scoresheet": items.planilla,
	"pen": items.pluma, "pistol": items.pistola, "pieces": pieces.todas,
	"pillar": ambient.columna, "door": ambient.puerta, "wall_panel": ambient.panel,
	"banner": ambient.estandarte,
}

if __name__ == "__main__":
	pedidos = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(TODO)
	for nombre in pedidos:
		print("[build_props]", nombre, "->", TODO[nombre]())
