# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 2

Pedidos del 2026-10-19 que no entran en la tanda de arreglos rápidos. Cada frente es delegable por separado salvo donde se indica la dependencia.

### Frente A — Mano del jugador con cinco dedos y agarre real
Es lo que el jugador ve todo el tiempo: debe ser lo más pulido del juego.
- [ ] Mano de 5 dedos en `player.glb` (Blender): índice, medio, anular y meñique con 3 falanges y pulgar con 3; pesos limpios en los nudillos. Actualizar `tools/check_characters.gd`.
- [ ] Agarres por tipo de pieza (peón por la cabeza, torre/alfil por el cuerpo, caballo, dama y rey por la corona): puntos de contacto definidos por pieza en `PieceFactory` y dedos que se cierran hasta tocar (sin atravesar ni quedar en el aire).
- [ ] Orientación de la muñeca controlada (hoy el IK no la controla): la palma mira a la pieza al acercarse.
- [ ] Pulsar el reloj, tomar la pluma y escribir con la mano nueva; temblor por estrés en los dedos.
- [ ] Capturas de cerca de cada fase (alcanzar, agarrar, trasladar, soltar) antes de entregar.

### Frente B — Poses de espera naturales
- [ ] Mientras espera el turno rival: brazos cruzados sobre la mesa, una mano en la mesa y la otra en la cabeza o el mentón, codos apoyados; varias poses que alternan con transiciones suaves (rival, jugador y mesas de fondo).
- [ ] Hoy `sit_idle/sit_think/sit_nervous` dejan las manos sobre el propio tablero (a z = ±0,30 con la silla a 0,80) y los brazos van por IK en reposo, así que no se ven sus gestos. Reanimar las poses en Blender con las manos fuera del tablero (o acercar las sillas) y que el IK solo entre al mover.
- [ ] Transición de la pose de espera al brazo que va a mover (sin saltos).

### Frente C — Animaciones con el modelo actual
- [ ] Inventario de lo que aún usa visuales del modelo anterior (tos, pieza caída, acusación ajena que se levanta y señala, guardias de la eliminación, banqueta, figura temporal del condenado, etc.).
- [ ] Rehacer cada una con `CharacterFigure` (animaciones nuevas en Blender si hace falta: toser, levantarse y señalar, ser arrastrado). No tienen que ser 1:1 con las antiguas, solo coherentes con la acción.

### Frente D — El rival voltea ante distracciones (espera la elección del usuario)
Hoy `BotController.notice_event` hace voltear con `turn_to_event_chance × intensity`. Se propone una probabilidad por evento; el usuario elige cuáles entran:

| Evento candidato | Probabilidad propuesta |
| --- | --- |
| Disparo de una ejecución en otra mesa | Muy alta |
| Guardias arrastrando a un eliminado | Alta |
| Alguien huye corriendo de su mesa | Alta |
| Grito de "¡Trampa!" en otra mesa (acusación ajena) | Alta |
| Apagón o parpadeo de lámparas | Alta |
| Banqueta o golpe detrás | Alta |
| El árbitro pasa cerca o detrás | Media (de reojo, rápido) |
| Llanto o súplica de un condenado | Media |
| Puerta que se abre o se cierra | Media |
| Lámpara de una mesa que queda a media luz tras una ejecución | Baja |
| Pieza que cae en una mesa vecina | Baja |
| Reloj vecino que pita al caer la bandera | Baja |
| Tos o ruido del propio jugador (requiere la tecla pendiente del humano) | Media |

- [ ] Implementar los eventos elegidos con su probabilidad en `EventDef`/personalidad, con giro de cabeza hacia el origen y regreso natural.

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
| Elo del rival del humano | De 1000 (ronda 1) a 1500 (final); ¿subir el techo a ~1700-1950 (promedio de jugadores con Elo FIDE)? |
| Ritmo | 3 min + 2 s por jugada |
| ¿Más tiempo para blancas? | No |
| Jugadores por torneo | 32 en cuadrícula 4x4 (configurable con `--players`) |
| Título del juego | Pendiente |
| Motor de los bots | Maia-3 5M (AGPL); Maia-2 (MIT) queda en el historial como plan B |
