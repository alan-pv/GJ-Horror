# ROADMAP

Plan por hitos del prototipo (un humano contra bots, exportado a web) y del lanzamiento. Cada hito se divide en frentes que implementan subagentes en paralelo (ver `CLAUDE.md`). Las casillas marcadas ya están en `main`.

## Hito 1 — Partida 1v1 jugable ✅

- [x] Servidor: tablero físico, reglas completas (perft), reloj de 3 min, las tablas ganan negras.
- [x] Trampas como datos y su validación (empujoncito, deslizar, robar, mover pieza enemiga).
- [x] Acusaciones: ventana desde la última jugada, tres falsas eliminan, pausa del reloj.
- [x] Ayuda para principiantes (bloquea un error grave una vez).
- [x] Bots: política muestreada, Maia-2 Blitz en el navegador y respaldo en GDScript; personalidades.
- [x] Cliente 3D: salón, lámpara, tablero, mano con TwoBoneIK3D, cámara en primera persona, reloj, HUD.

## Hito 2 — Trampas y vigilancia ✅

- **2A. Trampas del jugador y árbitro** (`src/client/cheats/`, `hand_animator.gd`, `src/client/arbiter.gd`)
  - [x] Elegir trampa (teclas 1-4), pieza y destino; abortar a mitad.
  - [x] Animación propia y reconocible de cada trampa, para ambas manos y con la duración que dicta el servidor.
  - [x] Pieza robada escondida en la mano/regazo; evidencia visible (pieza descentrada, pieza que falta).
  - [x] Árbitro que camina a la mesa al acusar y anuncia el veredicto; `pass_behind()` para el evento disuasivo.
- **2B. Bots tramposos** (`src/bots/`)
  - [x] Planificador de trampas: cuándo (el rival no mira, más si va perdiendo) y cuál (la que más ayuda sin dejar posiciones imposibles).
  - [x] Abortar si el rival voltea; provocar distracciones del rival antes de una trampa.

## Hito 3 — Eventos y director de tensión ✅

- **3. Director y eventos** (`src/server/tension_director.gd`, `src/client/events/`, `data/events/`)
  - [x] Director de tensión en el servidor: elige evento, origen y momento; más frecuencia con menos jugadores.
  - [x] Globales: apagón, ruido detrás, acusación ajena, eliminación en otra mesa.
  - [x] Del rival: tirar una pieza y toser (con tiempo de espera, sospechosos en sí mismos).
  - [x] Disuasivo: el árbitro pasa detrás (mientras está cerca, las trampas se ven).
  - [x] Sonido espacial con `AudioStreamPlayer3D` (sonidos sintetizados mientras no haya assets).
  - [x] Los bots voltean ante los eventos.

## Hito 4 — Torneo ✅

- **4. Torneo y salón vivo** (`src/server/tournament/`, `hall.gd`, flujo de `game_root.gd`)
  - [x] Gestor de torneo: rondas sincronizadas, emparejamiento aleatorio, impares (pasa sin jugar), final a dos partidas con colores invertidos y desempate por tiempo sobrante.
  - [x] Partidas de fondo bot contra bot simuladas de forma barata en las otras mesas.
  - [x] Al eliminar a alguien su lámpara se apaga y su figura sale del salón; el salón se oscurece.
  - [x] Advertencias que se arrastran entre partidas; cola automática a un torneo nuevo al ser eliminado.
  - [x] Pantallas entre rondas (quedan N jugadores) y de campeón.

## Integración de los hitos 2-4 (en curso)

- [ ] Corrutinas seguras al recargar la escena entre partidas (árbitro, manos, bots, eventos).
- [ ] El servidor avisa `cheat_aborted` al terminar la partida con una trampa en curso.
- [ ] El torneo informa al director de tensión cuántos quedan; guardias y figuras coherentes al eliminar.
- [ ] Verificar visualmente al árbitro que pasa detrás (disuasivo).
- [ ] Caché de jugadas legales en `MatchServer` (picos de las mesas de fondo).
- [ ] Balance de bots: variedad de trampas (no solo robar), menos eliminaciones por acusaciones falsas, distracciones menos frecuentes.

## Hito 5 — Web y pulido

- [ ] Bots con **Maia-3 5M** (más humano: 55,4 % vs 52,0 %; 11 MB; Elo continuo), 100 % local: onnxruntime-web incluido en el build, sin CDN.
- [ ] Licencia AGPL-3.0 (requisito de Maia-3) y **repo público el día que se publique el juego** en itch.io.
- [ ] Exportación web real (plantillas de Godot 4.6) y prueba de Maia-2 en navegador.
- [ ] Rendimiento: ayuda para principiantes por debajo de 0,1 s, IK lejano con menos frecuencia, medir mesas visibles en una máquina modesta.
- [ ] Audio ambiente (relojes, piezas, murmullos que disminuyen al vaciarse el salón).
- [ ] Tutorial corto (mover, mirar, hacer trampa, acusar).
- [ ] Ajuste de balance con bots: ¿más tiempo para blancas (Armageddon)?, cono de visión, duraciones de trampas.
- [ ] Arte: reemplazar primitivas por modelos (manos, piezas, personajes).

## Lanzamiento — Multijugador

- [ ] Servidor headless de Godot con la API de alto nivel (`@rpc`, `MultiplayerSynchronizer` para mirada y manos).
- [ ] Información oculta: enviar la animación de una trampa solo a quien puede verla.
- [ ] Lista completa de trampas y eventos; modo espectador o cola al ser eliminado.
- [ ] Emparejamiento por rating; ayuda solo en tutorial y liga de principiantes.

## Decisiones abiertas (configurables en `MatchConfig`)

| Decisión | Valor actual |
| --- | --- |
| ¿El reloj se pausa mientras llega el árbitro? | Sí |
| ¿Una acusación correcta borra una advertencia? | No |
| Ventana de acusación | Desde la última jugada del acusador |
| ¿Más tiempo para blancas? | No (3:00 / 3:00) |
| Jugadores por torneo | 16 (configurable con `--players`) |
| Título del juego | Pendiente |
| Motor de los bots | Maia-3 5M (AGPL); Maia-2 (MIT) queda en el historial como plan B |
