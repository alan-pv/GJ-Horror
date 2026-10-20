# CLAUDE.md

Juego de Godot 4.6 (GDScript): torneo de ajedrez por eliminación con trampas y acusaciones. **Lo implementado** (arquitectura y todas las mecánicas) está en `docs/arquitectura.md`; **lo pendiente**, en `ROADMAP.md`. Diseño original en `docs/documento-diseno.md` y técnico en `docs/documento-tecnico.md`. Léelos antes de cambiar comportamiento de juego.

### ROADMAP y arquitectura (regla)
- `ROADMAP.md` contiene **solo** lo pendiente. Al terminar una mecánica, en el **mismo commit**: se describe (o se actualiza) en `docs/arquitectura.md` y se **borra** del ROADMAP. No se dejan casillas marcadas.
- Los pedidos nuevos entran primero al ROADMAP, agrupados en frentes delegables.
- Si una mecánica cambia, se corrige su descripción en `docs/arquitectura.md`; ese documento siempre refleja `main`.

## Forma de trabajo

### Roles
- **Opus (sesión principal, líder):** identifica el alcance de cada pedido, cierra las dudas con el usuario, divide el trabajo y delega. No implementa en paralelo con sus agentes: revisa, verifica y hace los commits.
- **Sonnet (subagentes):** implementan. Se lanzan con `model: "sonnet"` y **en paralelo** (varios `Agent` en el mismo mensaje, en segundo plano) siempre que las partes sean independientes.

### Cómo delegar
1. Definir el alcance y las interfaces entre partes **antes** de lanzar los agentes (firmas, señales, rutas de archivos), para que puedan trabajar sin esperarse.
2. Asignar a cada agente un conjunto de archivos **disjunto**; indicar explícitamente qué carpetas no debe tocar.
3. Cada prompt debe ser autosuficiente: contexto, archivos a leer, API existente, entregables, cómo verificar y qué reportar.
4. Los agentes **no hacen commit ni push**. El líder revisa el diff, corre las pruebas y hace commit de cada parte por separado.
5. Si una parte depende de otra, lanzar primero la base o acordar la interfaz y lanzar ambas.

### Git
- Rama por defecto: `main`. Commits pequeños, uno por parte lógica, para facilitar la depuración.
- Autor de los commits: `alan-pv <alanpomaresv@gmail.com>`. **Sin** líneas `Co-Authored-By` ni otras atribuciones a Claude.
- Mensajes de commit en español: título breve y viñetas con lo importante.
- No hacer commit con pruebas en rojo.

### Idioma y estilo
- Comentarios, docstrings (`##`), documentación y mensajes de commit en **español**.
- **Todo lo que ve u oye el jugador** (menús, HUD, frases, motivos de fin de partida) en **inglés**.
- GDScript tipado, tabulaciones, `class_name` en scripts reutilizables, densidad de comentarios moderada.
- Arte: low-poly hecho en Blender con scripts sin interfaz. `art/` guarda los `.blend` (editables a mano) y los scripts que los generan; `assets/models/` los `.glb` exportados que usa Godot. Si se edita un `.blend` a mano, se reexporta, no se regenera.

## Arquitectura (reglas que no se rompen)
- **El servidor manda.** Todo lo que decide el resultado vive en `src/server/` (`MatchServer`). Cliente y bots solo envían intenciones (`submit_move`, `set_gaze`, `start_cheat`, `abort_cheat`, `accuse`) y dibujan lo que el servidor confirma por señales. Aunque hoy corre todo en un proceso, no se cruza esa frontera.
- **Tablero físico:** `BoardState` es lo que hay sobre la mesa, no lo que resultaría de jugadas legales. Los reyes se mueven con trampas como cualquier pieza, pero el rey rival nunca va a la pila; las trampas nunca dejan en jaque al tramposo ni al bando que no mueve.
- **Bots = mismas entradas que un humano.** Los cerebros devuelven una política (`{uci: probabilidad}`) que el bot muestrea; Maia-3 5M en web (licencia AGPL: el repo se hace público al publicar el juego), `FallbackBrain` en editor/escritorio.
- **Web es el objetivo:** renderer Compatibility (sin niebla volumétrica, sin procesos externos). Nada que dependa de `OS.execute`.
- Las decisiones de diseño abiertas van como opciones en `MatchConfig`, no fijas en el código.

## Estructura
- `src/server/` reglas, reloj, trampas (`cheats/`), acusaciones, ayuda para principiantes.
- `src/bots/` cerebros (`chess_brain`, `fallback_brain`, `maia_*`) y `bot_controller`.
- `src/client/`, `src/world/` vista 3D, mano con IK, escena principal.
- `data/` recursos `.tres` (trampas, personalidades) y datos de Maia.
- `web/` (ignorado por Godot) puente JS y modelo ONNX; `tools/` scripts de exportación.
- `tests/` pruebas propias (`extends TestCase`).

## Comandos
```
godot --headless --path . --import                                   # tras crear scripts con class_name
godot --headless --path . --script res://tests/run_tests.gd          # todas las pruebas
godot --headless --path . --script res://tests/run_tests.gd -- --filter=cheats
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3   # ver la escena sin pantalla
GODOT=/ruta/a/godot tools/build_web.sh                               # exportar a web
```
En la máquina de Alan, `godot` no está en el PATH: es `"/home/alanpv/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"` (4.7.2); no hay Xvfb, las capturas usan la pantalla real (`DISPLAY=:0`). Blender 5.2 sí está en el PATH: `blender --background --python art/<...>.py`.
En la nube no hay Godot instalado: descargar `Godot_v4.6-stable_linux.x86_64.zip` de los releases de GitHub al scratchpad.

Toda funcionalidad nueva de lógica lleva pruebas; los cambios visuales se verifican con capturas (Xvfb) antes de entregar.
