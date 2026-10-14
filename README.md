# Ajedrez de eliminación

Torneo de ajedrez por eliminación en un salón oscuro, donde cualquiera puede hacer trampa y cualquiera puede acusarte.

- [Documento de diseño](docs/documento-diseno.md)
- [Documento técnico](docs/documento-tecnico.md)

Motor: Godot 4.6+ (GDScript, renderer Compatibility para poder exportar a web).

## Bots / Maia-2

Los bots no "calculan la mejor jugada": muestrean una política de jugadas humanas según su Elo. En la versión web esa política la da **Maia-2 (blitz)**, una red que imita a jugadores humanos de cada nivel, ejecutada en el navegador con `onnxruntime-web` (wasm, 1 hilo, sin COOP/COEP). En el editor y en escritorio se usa `FallbackBrain` (GDScript).

- `src/bots/maia_encoding.gd`: codificación de entrada idéntica a la de maia2 (tablero espejado si juegan negras, categorías de Elo, vocabulario de 1880 jugadas).
- `src/bots/maia_brain.gd`: llama a `window.MaiaBridge` vía `JavaScriptBridge`; si el puente no está listo o tarda más de 3 s, usa el respaldo.
- `web/maia_bridge.js` y `web/maia2_blitz.onnx` (~43 MB, pesos fp16): se copian junto a `index.html` al exportar.

**Regenerar el modelo y los datos** (descarga los pesos de Maia-2 desde Google Drive a `.maia2_cache/`):

```
pip install maia2 onnx onnxruntime onnxscript
python tools/export_maia2_onnx.py     # modelo, moves.json, elo_buckets.json y fixture de pruebas
python tools/check_onnx.py            # ONNX vs PyTorch sobre el fixture
```

**Exportar a web** (necesita las plantillas de exportación de Godot 4.6 instaladas):

```
GODOT=/ruta/a/godot tools/build_web.sh
python3 -m http.server -d build/web 8000
```

**Pruebas:** `godot --headless --path . --script res://tests/run_tests.gd -- --filter=maia`.

**Licencia:** Maia-2 © CSSLab (Universidad de Toronto), licencia MIT: <https://github.com/CSSLab/maia2>. Conservar este aviso al distribuir el modelo.
