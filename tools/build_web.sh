#!/usr/bin/env bash
# Exporta el juego a Web (HTML5) en build/web/ y copia el puente de Maia-3, el modelo y onnxruntime-web (todo local, sin CDN).
# Uso: GODOT=/ruta/a/godot tools/build_web.sh
# Requiere las plantillas de exportacion de Godot 4.7.2 (preset "Web", sin hilos).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
SALIDA="$RAIZ/build/web"
VERSION="4.7.2.stable"

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
  1. Descarga Godot_v4.7.2-stable_export_templates.tpz desde
     https://github.com/godotengine/godot/releases/tag/4.7.2-stable
  2. En el editor: Proyecto > Exportar > Gestionar plantillas > Instalar desde archivo
     (o descomprime el .tpz y copia su carpeta 'templates' a:
      $PLANTILLAS)
Luego vuelve a ejecutar este script.
MSG
	exit 2
fi

for f in web/maia_bridge.js web/maia3_5m.onnx web/ort/ort.wasm.min.js web/ort/ort-wasm-simd-threaded.mjs web/ort/ort-wasm-simd-threaded.wasm; do
	[ -f "$RAIZ/$f" ] || { echo "Falta $f (modelo: tools/export_maia3_onnx.py)" >&2; exit 1; }
done

mkdir -p "$SALIDA"
"$GODOT" --headless --path "$RAIZ" --import
"$GODOT" --headless --path "$RAIZ" --export-release "Web" "$SALIDA/index.html"

cp "$RAIZ/web/maia_bridge.js" "$RAIZ/web/maia3_5m.onnx" "$SALIDA/"
mkdir -p "$SALIDA/ort"
cp "$RAIZ"/web/ort/* "$SALIDA/ort/"
# Los .wasm/.mjs de ort deben servirse con su tipo MIME (python -m http.server y itch.io lo hacen).
echo "Activos de Maia-3: $(du -ch "$SALIDA/maia3_5m.onnx" "$SALIDA/maia_bridge.js" "$SALIDA"/ort/* | tail -1 | cut -f1)"
echo "Listo: $SALIDA  (sirve con: python3 -m http.server -d build/web 8000)"
