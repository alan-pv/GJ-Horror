# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 2

Pedidos del 2026-10-19 que no entran en la tanda de arreglos rápidos. Cada frente es delegable por separado salvo donde se indica la dependencia.

El arte (modelado y animación) también lo hacen los agentes con scripts de Blender: el usuario no anima. El código pide **roles** de animación (`<rol>` o `<rol>__<variante>`) con respaldo, para que añadir variantes no exija tocar código.

### Frente A — Mano del jugador con cinco dedos y agarre real
Es lo que el jugador ve todo el tiempo: debe ser lo más pulido del juego.
- [ ] Agarres por tipo de pieza (peón por la cabeza, torre/alfil por el cuerpo, caballo, dama y rey por la corona): puntos de contacto definidos por pieza en `PieceFactory` y dedos que se cierran hasta tocar (sin atravesar ni quedar en el aire).
- [ ] Orientación de la muñeca controlada (hoy el IK no la controla): la palma mira a la pieza al acercarse.
- [ ] Pulsar el reloj, tomar la pluma y escribir con la mano nueva; temblor por estrés en los dedos.
- [ ] Capturas de cerca de cada fase (alcanzar, agarrar, trasladar, soltar) antes de entregar.
- [ ] Gestos de trampa continuos: hoy los tramos de `_cmove` paran entre sí (los gestos normales ya son una sola curva).
- [ ] Si la trampa interrumpe la anotación del humano hay ~0,25 s de retraso por dejar la pluma; el rival (que escribe con la otra mano) podría empezarla a la vez.

### Frente B — Pulido de animaciones
- [ ] El puño al máximo de los clips (`curl` ~80) no cierra del todo y entre dedos curvados se ve el canto plano de la palma.
- [ ] La inclinación del IK encorva: `HandRig.LEAN_MAX` = 0,95 rad deja la cabeza a 4-14 cm de la mesa y `TorsoLeanModifier` la reparte solo entre Spine y Chest. Bajar el tope (~0,6), adelantar más la cadera (`SHIFT_MAX`) y repartir parte en la pelvis.
- [ ] Poses de espera también para el cuerpo del jugador en primera persona (hoy solo el rival y las mesas de fondo usan `sit_wait`).
- [ ] Maniquíes sin rasgos: la nariz y las orejas son geometría de `Skin` en `player.glb` y quedan como relieve; hace falta una variante sin rasgos (o separar esa geometría) en `build_player.py`.
- [ ] `dragged`: las manos quedan en puño hacia fuera; los guardias se ven casi negros fuera del cono de luz (ropa más clara o algo de emisión).
- [ ] `sit_move_piece` (1,5 cm) y `sit_beg` (2,4 cm) atraviesan el canto de la mesa; `sit_press_clock` queda 3 cm fuera de alcance en 4 fotogramas.
- [ ] Revisar en el juego la tos (`sit_cough`) y recoger la pieza caída (`sit_pick_up`): funcionan sin errores, pero sin captura revisada.

### Frente E — Escenificación según lo que ve el jugador
- [ ] Calcular qué mesas están en la línea de visión directa del jugador (cono de la cámara en reposo, sin oclusión) y llevar ahí las reacciones más dramáticas (huidas, súplicas, ejecuciones con más preparación); las mesas fuera de cuadro usan reacciones discretas.

### Frente F — Progreso visible en el salón
Depende del Frente B solo para la animación de caminar del jugador.
- [ ] Mesas numeradas: el jugador empieza en una mesa de un extremo (p. ej. la 10) y al ganar sube (5, 3, 2, 1). En el extremo opuesto, un podio con las mesas finales visualmente más ricas (mejor tablero, mantel, lámpara, piezas); las primeras son sencillas.
- [ ] Señal visual del progreso desde el asiento (número de mesa visible, podio al fondo que se acerca).
- [ ] Entre rondas, en lugar de fundido a negro y recarga con el rival ya sentado: animación en primera persona de levantarse y caminar por el salón hasta la siguiente mesa. Hoy `GameRoot` supone la mesa del humano en `Vector3.ZERO` (mesa 9): decidir si se mueve la mesa del humano o se desplaza el salón alrededor de ella.

## Pendiente

- [ ] Las partidas de fondo empiezan desde la posición inicial; podrían arrancar de un medio juego (`Hall.mid_game_fen`) para que los tableros se vean avanzados.
- [ ] Pasillo entre filas de ~1,16 m entre sillas (`HallLayout.SPACING_Z` = 3,2): subirlo si el árbitro pasa justo.

- [ ] El humano no tiene tecla para sus eventos de distracción (toser, tirar una pieza).

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
