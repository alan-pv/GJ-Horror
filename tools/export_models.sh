#!/usr/bin/env bash
# Reexporta TODOS los .blend bajo art/ a assets/models/ reflejando la ruta
# (art/props/x.blend -> assets/models/props/x.glb). Úsalo tras editar un .blend a mano.
# Uso: tools/export_models.sh [filtro]   (filtro opcional: subcadena de la ruta)
set -euo pipefail
cd "$(dirname "$0")/.."
BLENDER="${BLENDER:-blender}"
find art -name '*.blend' | sort | while read -r f; do
	[[ -n "${1:-}" && "$f" != *"$1"* ]] && continue
	rel="${f#art/}"
	out="assets/models/${rel%.blend}.glb"
	"$BLENDER" --background "$f" --python art/export_glb.py -- "$out" 2>&1 | grep -E "export_glb|Error|Traceback" || true
done
