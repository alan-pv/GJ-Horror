#!/usr/bin/env bash
# Exporta el juego a Web (HTML5) en build/web/ y copia el puente de Maia-2 y el modelo.
# Uso: GODOT=/ruta/a/godot tools/build_web.sh
# Requiere las plantillas de exportacion de Godot 4.6 (preset "Web", sin hilos).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
SALIDA="$RAIZ/build/web"
VERSION="4.6.stable"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "No encuentro Godot. Define GODOT=/ruta/al/ejecutable" >&2
	exit 1
fi

# Busca las plantillas de exportacion web (release o debug, sin hilos).
PLANTILLAS="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION"
if [ ! -f "$PLANTILLAS/web_nothreads_release.zip" ] && [ ! -f "$PLANTILLAS/web_nothreads_debug.zip" ]; then
	cat >&2 <<MSG
Faltan las plantillas de exportacion de Godot $VERSION (~1 GB).
Instalalas asi:
  1. Descarga Godot_v${VERSION%%.*}.6-stable_export_templates.tpz desde
     https://godotengine.org/download/archive/4.6-stable/
  2. En el editor: Proyecto > Exportar > Gestionar plantillas > Instalar desde archivo
     (o descomprime el .tpz y copia su carpeta 'templates' a:
      $PLANTILLAS)
Luego vuelve a ejecutar este script.
MSG
	exit 2
fi

for f in web/maia_bridge.js web/maia2_blitz.onnx; do
	[ -f "$RAIZ/$f" ] || { echo "Falta $f (ver tools/export_maia2_onnx.py)" >&2; exit 1; }
done

mkdir -p "$SALIDA"
"$GODOT" --headless --path "$RAIZ" --import
"$GODOT" --headless --path "$RAIZ" --export-release "Web" "$SALIDA/index.html"

cp "$RAIZ/web/maia_bridge.js" "$RAIZ/web/maia2_blitz.onnx" "$SALIDA/"
echo "Listo: $SALIDA  (sirve con: python3 -m http.server -d build/web 8000)"
