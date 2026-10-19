# Créditos de audio (SFX)

Todos los archivos de esta carpeta están **sintetizados con `tools/gen_sfx.py`** (numpy, semilla fija; sin material de terceros). Sin atribución obligatoria; uso y redistribución libres (equivalente a CC0).

Regenerar: `python3 tools/gen_sfx.py` (los `.import` no se tocan).

Archivos: clock_tick, clock_tock, clock_press, piece_place_1..3, pen_write_loop, footstep_1..6, gunshot, gun_cock, body_slump_table, body_fall_floor, chair_scrape, sob_loop, panic_breath_loop, whimper, ear_ring, heartbeat_loop, room_tone_loop.

## Loops
Los `*_loop.wav` tienen `edit/loop_mode=1` (Forward) en su `.import`. Si se reimportan desde cero: Importar > Loop Mode = Forward. Están construidos de forma periódica (filtrado circular y modulaciones de periodo entero), así que empalman sin salto.
