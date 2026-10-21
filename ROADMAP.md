# ROADMAP

Solo lo **pendiente**. Lo implementado se describe en [`docs/arquitectura.md`](docs/arquitectura.md) y se borra de aquí en el mismo commit que lo termina (ver `CLAUDE.md`). Cada hito se divide en frentes que implementan subagentes en paralelo.

## Ronda de pulido 2

Pedidos del 2026-10-19 que no entran en la tanda de arreglos rápidos. Cada frente es delegable por separado salvo donde se indica la dependencia.

El arte (modelado y animación) también lo hacen los agentes con scripts de Blender: el usuario no anima. El código pide **roles** de animación (`<rol>` o `<rol>__<variante>`) con respaldo, para que añadir variantes no exija tocar código.

### Frente B — Pulido de animaciones
Un clip por acción, sin variantes (14 en `player.glb`); las escenas de muchas partes se eliminan o simplifican, no se pulen.
- [ ] Inclinación del torso: el tope quedó en 0,70 rad (con 0,6 había posturas sin alcanzar) y 3 posturas extremas en la esquina lejana no llegan por 3,5-4,5 cm; el vientre puede rozar ~1 cm el canto a máxima inclinación (estimado). Revisar en primera persona.
- [ ] **Agarre de la pluma (trípode), lo que falta:** ya están la pinza de pulgar e índice a 2,5 cm de la punta, el medio como apoyo y la pluma a ~50° hacia el hombro (ver `docs/arquitectura.md` 4.14). Pero anular y meñique quedan semiestirados sobre la hoja en vez de recogidos bajo la palma (recogidos atravesarían el papel 1-2 cm con la mano actual: hay que tocar la malla o el esqueleto en `art/`) y la pluma parece salir entre índice y medio. Falta una captura de la pose estable de escritura en el juego, en la mano del jugador y en la del rival.

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

## Ronda de pulido 4

Pedidos del 2026-10-21.

### Por pensar
- [ ] Es aburrido esperar a que terminen todas las mesas para seguir jugando. Buscar alternativas (sin decidir aún).

## Pendiente

- [ ] Corte de la recarga entre rondas (`RoundWalk`): al sentarse se nota un salto de luz (la lámpara de la escena nueva es más brillante y tiene sombras) y el reloj y las planillas de la mesa destino, horneados en su malla, cambian de sitio y se encienden. Comparar con `--walk-end-shot` / `--walk-start-shot`.
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
