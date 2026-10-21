# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 2

Pedidos del 2026-10-19 que no entran en la tanda de arreglos rápidos. Cada frente es delegable por separado salvo donde se indica la dependencia.

El arte (modelado y animación) también lo hacen los agentes con scripts de Blender: el usuario no anima. El código pide **roles** de animación (`<rol>` o `<rol>__<variante>`) con respaldo, para que añadir variantes no exija tocar código.

### Frente A — Mano del jugador: retoques del agarre
Lo que quedó tras la mano de cinco dedos y el agarre por pieza.
- [ ] Oposición pulgar-índice de 80° a 160° según la pieza: el pulgar cierra a lo largo de los dedos y no de lado, así que se ve como garra sobre la cabeza, no como pinza diametral.
- [ ] Con agarres bajos (torre) los dedos que no tocan pueden quedar hasta 5 mm bajo la mesa: falta límite de suelo para ellos.
- [ ] Dama y rey: el pulgar queda alto sobre la corona.
- [ ] Reloj: variante de pulsar con los dedos juntos.
- [ ] Medir el coste de la resolución de dedos en el juego (dos brazos con IK, 16 mesas) en una máquina modesta.

### Frente B — Pulido de animaciones
Un clip por acción, sin variantes (21 en `player.glb`); lo que queda es revisarlo en el juego.
- [ ] Revisar en el juego la silla que sigue al cuerpo (`ChairFollow`) en la acusación y en la eliminación: la prueba no ve solape, pero no hay captura que encuadre la mesa del evento (falta una opción de cámara hacia `--event-table`).
- [ ] Revisar en el juego `sit_cough`, `sit_pick_up` (la mano baja hasta ~10 cm del suelo) y `sit_press_clock` (el preview no dibuja el reloj) con el IK del brazo apagado.
- [ ] Inclinación del torso: el tope quedó en 0,70 rad (con 0,6 había posturas sin alcanzar) y 3 posturas extremas en la esquina lejana no llegan por 3,5-4,5 cm; el vientre puede rozar ~1 cm el canto a máxima inclinación (estimado). Revisar en primera persona.
- [ ] `test_seated_posture_is_upright` casi no comprueba nada (sin fotogramas el esqueleto queda en T-pose): rehacerla como `test_chair_follow`, dentro del árbol.
- [ ] **Agarre de la pluma (trípode):** hoy los dedos quedan cerrados en puño detrás de la pluma. Como se agarra de verdad:
  - la pluma descansa sobre el costado de la última falange del **medio**;
  - la sujetan las **yemas de pulgar e índice**, a 2-3 cm de la punta, una frente a la otra;
  - el cuerpo de la pluma se apoya en la base del índice (entre pulgar e índice) y apunta hacia atrás, por encima del dorso, hacia el hombro, a ~45-55° del papel;
  - anular y meñique se recogen bajo la palma, y el canto de la mano (meñique) se apoya en el papel;
  - la muñeca va recta y los trazos salen de los dedos y de un leve deslizamiento de la mano, no del brazo.
  Hace falta una pose de mano propia para escribir (no `PINCH`), con el medio como apoyo, y revisarla con capturas de cerca, en la mano del jugador y en la del rival.

### Frente E — Escenificación según lo que ve el jugador
- [ ] Calcular qué mesas están en la línea de visión directa del jugador (cono de la cámara en reposo, sin oclusión) y llevar ahí las reacciones más dramáticas (huidas, súplicas, ejecuciones con más preparación); las mesas fuera de cuadro usan reacciones discretas.

### Frente F — Progreso visible en el salón
Depende del Frente B solo para la animación de caminar del jugador.
- [ ] Mesas numeradas: el jugador empieza en una mesa de un extremo (p. ej. la 10) y al ganar sube (5, 3, 2, 1). En el extremo opuesto, un podio con las mesas finales visualmente más ricas (mejor tablero, mantel, lámpara, piezas); las primeras son sencillas.
- [ ] Señal visual del progreso desde el asiento (número de mesa visible, podio al fondo que se acerca).
- [ ] Entre rondas, en lugar de fundido a negro y recarga con el rival ya sentado: animación en primera persona de levantarse y caminar por el salón hasta la siguiente mesa. Hoy `GameRoot` supone la mesa del humano en `Vector3.ZERO` (mesa 9): decidir si se mueve la mesa del humano o se desplaza el salón alrededor de ella.

### Frente H — Diseño: por qué hacer trampa (por discutir)
Problema: si el jugador puede ganar sin trampas, el juego es solo ajedrez. Ideas para que hacer trampa sea necesario o muy tentador; se eligen y se combinan después de hablarlo:
- **Rivales más fuertes que el jugador:** el Elo del rival sube más rápido que el del jugador medio (hoy 1000 → 1500), así que jugar limpio pierde casi siempre a partir de la ronda 2-3.
- **Todos hacen trampa:** los bots tramposos lo hacen cada vez más; si el jugador no acusa ni responde con trampas, va perdiendo material sin ver por qué.
- **Desventaja de salida:** en rondas avanzadas el jugador empieza con material de menos (partida con ventaja para el rival), menos tiempo o siempre con negras; la trampa es la forma de igualar.
- **Reloj:** pensar cuesta tiempo y la trampa no (o cuesta menos); con poco tiempo, mover una pieza a escondidas es más rápido que encontrar la jugada.
- **Objetivo por ronda:** el árbitro o "la casa" exige algo que el ajedrez limpio casi no permite (ganar en N jugadas, capturar la dama antes de la jugada 20); no cumplirlo es la eliminación.
- **Recompensa del riesgo:** las trampas no detectadas dan algo visible (tiempo extra, quitar una advertencia, ventaja en la ronda siguiente) y la tensión crece con cada una.
- **Ventanas de oportunidad:** los eventos (apagón, acusación ajena, árbitro que pasa) son momentos claros para hacer trampa; anunciarlos o hacerlos frecuentes en los momentos críticos de la partida.
- **Narrativa:** el torneo está amañado y los campeones anteriores fueron tramposos; la regla tácita es "que no te vean", no "no hagas trampa".

## Pendiente

- [ ] Las partidas de fondo empiezan desde la posición inicial; podrían arrancar de un medio juego (`Hall.mid_game_fen`) para que los tableros se vean avanzados.
- [ ] Pasillo entre filas de ~1,16 m entre sillas (`HallLayout.SPACING_Z` = 3,2): subirlo si el árbitro pasa justo.

- [ ] El humano no tiene tecla para su evento de distracción (toser).

- [ ] **Repo público el día que se publique el juego** en itch.io (AGPL de Maia-3).
- [ ] Exportación web real (plantillas de Godot) y prueba de Maia-3 en navegador.
- [ ] Rendimiento: IK lejano con menos frecuencia, medir 16 mesas visibles en una máquina modesta.
- [ ] Audio ambiente (relojes, piezas, murmullos que disminuyen al vaciarse el salón).
- [ ] Tutorial corto (mover, mirar, hacer trampa, acusar).
- [ ] Ajuste de balance con bots: ¿más tiempo para blancas (Armageddon)?, cono de visión, duraciones de trampas.

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
| Ventana de acusación | Las 3 últimas jugadas del acusador (`accusation_window_moves`) |
| Elo del rival del humano | De 1000 (ronda 1) a 1500 (final) |
| Ritmo | 3 min + 2 s por jugada |
| ¿Más tiempo para blancas? | No |
| Jugadores por torneo | 32 en cuadrícula 4x4 (configurable con `--players`) |
| Título del juego | Pendiente |
| Motor de los bots | Maia-3 5M (AGPL); Maia-2 (MIT) queda en el historial como plan B |
