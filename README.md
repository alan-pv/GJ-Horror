# Ajedrez de eliminación

Torneo de ajedrez por eliminación en un salón oscuro, donde cualquiera puede hacer trampa y cualquiera puede acusarte.

- [Documento de diseño](docs/documento-diseno.md)
- [Documento técnico](docs/documento-tecnico.md)

Motor: Godot 4.6+ (GDScript, renderer Compatibility para poder exportar a web).

## Bots / Maia-3

Los bots no "calculan la mejor jugada": muestrean una política de jugadas humanas según su Elo. En la versión web esa política la da **Maia-3 5M**, una red (*Chessformer*) que imita a jugadores humanos y se condiciona con el Elo propio y el del rival como número continuo (0..5000, sin categorías). Se ejecuta en el navegador con `onnxruntime-web` (wasm, 1 hilo, sin COOP/COEP). En el editor y en escritorio se usa `FallbackBrain` (GDScript).

- `src/bots/maia_encoding.gd`: codificación de entrada idéntica a la de maia3 (64 casillas x 12 canales x 8 posiciones, tablero espejado según quién mueve, vocabulario de 4352 jugadas con coronaciones, Elo continuo).
- `src/bots/maia_history.gd`: Maia-3 ve la posición actual y las 7 anteriores (sin ellas pierde ~4 puntos de acierto, ver abajo). Como el cerebro solo recibe el tablero actual y cada bot pide en su turno, reconstruye la jugada intermedia buscando la pareja de jugadas legales que lleva de la posición vista antes a la actual. Si una trampa alteró el tablero y no hay explicación, sigue con lo que tenga (al empezar la partida se rellena con la posición más antigua, igual que maia3).
- `src/bots/maia_brain.gd`: llama a `window.MaiaBridge` vía `JavaScriptBridge`; si el puente no está listo o tarda más de 3 s, usa el respaldo.
- `web/maia_bridge.js`, `web/maia3_5m.onnx` (10,7 MB, pesos fp16 con cálculo fp32) y `web/ort/` (onnxruntime-web 1.20.1 mínimo: `ort.wasm.min.js`, `ort-wasm-simd-threaded.mjs/.wasm`): se copian junto a `index.html` al exportar. **Todo es local, sin CDN**: tras cargar, el juego funciona sin conexión.

**Descarga de la versión web** (sin contar el motor de Godot): ~22,0 MB sin comprimir (modelo 10,7 MB + wasm de onnxruntime 11,2 MB + JS 0,08 MB), ~12,4 MB comprimidos con gzip.

**Regenerar el modelo y los datos** (descarga `maia3-5m.pt` de Hugging Face, `UofTCSSLab/Maia3-5M`):

```
python -m venv .venv && . .venv/bin/activate
pip install torch python-chess onnx onnxruntime onnxscript numpy huggingface_hub
pip install git+https://github.com/CSSLab/maia3          # o: --maia3-repo ruta/al/clon
python tools/export_maia3_onnx.py     # modelo, data/maia3/moves.json y fixture de pruebas
python tools/check_onnx.py            # ONNX vs PyTorch sobre el fixture
node tools/check_bridge.js            # puente JS + onnxruntime incluido vs el fixture
```

El exportador compara además 400 posiciones aleatorias entre PyTorch y el ONNX (acuerdo top-1 99,8 %, diferencia máxima de probabilidad 5e-4) y sustituye `RMSNorm` por operaciones básicas porque `aten::rms_norm` no existe en opset 17.

**Historial: por qué hace falta.** El checkpoint 5M se entrenó con 8 posiciones por entrada. Medido sobre 1504 posiciones de partidas humanas de Lichess (enero de 2013, ambos jugadores de 1000 a 2200, con el Elo real de cada uno), el acierto top-1 es 52,9 % con historial y 48,9 % usando solo la posición actual repetida 8 veces (el modo por defecto del motor UCI oficial). Con historial supera a Maia-2 (52,0 % según el paper); sin él quedaría por debajo.

**Exportar a web** (necesita las plantillas de exportación de Godot 4.6 instaladas):

```
GODOT=/ruta/a/godot tools/build_web.sh
python3 -m http.server -d build/web 8000
```

**Pruebas:** `godot --headless --path . --script res://tests/run_tests.gd -- --filter=maia`.

**Créditos y licencia:** Maia-3 © CSSLab (Universidad de Toronto), código y pesos bajo **AGPL-3.0**: <https://github.com/CSSLab/maia3>, pesos en <https://huggingface.co/UofTCSSLab/Maia3-5M>. Arquitectura y resultados: Monroe, Eilender, Chalmers, Tang y Anderson, *Chessformer: A Unified Architecture for Chess Modeling*, ICLR 2026 (<https://arxiv.org/abs/2605.19091>). Este repositorio incluye derivados de Maia-3 (el modelo ONNX y el port de la codificación), por lo que se distribuye bajo AGPL-3.0 (ver `LICENSE`): **el repositorio se hará público cuando el juego se publique**, y el código fuente debe ofrecerse a quien juegue la versión web. onnxruntime-web © Microsoft, licencia MIT (`web/ort/LICENSE-onnxruntime.txt`).
