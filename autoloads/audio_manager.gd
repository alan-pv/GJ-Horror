extends Node

## Pool of players for firing sound effects from any scene, the background
## music, and the one place that knows how loud anything is.
##
## Volume lives on the audio buses rather than on each player, so a slider moved
## in the middle of a sound is heard immediately and nothing has to be told
## about it. What the player chose is written to disk here and read back at
## boot, long before any settings screen exists.
##
## Nothing above this file ever has to call it. Music is a convention rather
## than configuration: drop a file where MUSIC_PATHS says and it plays, in every
## scene, for the whole run. Reusing all of this in another project is copying
## this file and the bus layout beside it, and dropping in a music.ogg.


const POOL_SIZE := 8

## Every effect plays here, so one slider covers all of them.
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

## The first one of these that exists is the background music. No scene asks for
## it and no inspector field points at it: a project that has one gets music,
## and a project that does not, does not.
const MUSIC_PATHS := [
	"res://assets/audio/music.ogg",
	"res://assets/audio/music.mp3",
	"res://assets/audio/music.wav",
]

## Long enough that the track arrives rather than starts.
const MUSIC_FADE := 1.5

const SETTINGS_PATH := "user://audio.cfg"
const SETTINGS_SECTION := "audio"

## Below this a bus is silent rather than very quiet: linear_to_db(0) is -inf,
## which is not a number a slider or a config file should ever carry.
const SILENCE_DB := -80.0

const SFX_CLICK := "res://assets/audio/ui/click.wav"
const SFX_HOVER := "res://assets/audio/ui/hover.wav"

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path: String = ""
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = _bus_or_master(SFX_BUS)
		add_child(player)
		_players.append(player)

	_music = AudioStreamPlayer.new()
	_music.bus = _bus_or_master(MUSIC_BUS)
	# Music is the one sound that should carry on over a pause menu.
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	play_music(find_music())


## A project that has not made the bus yet still gets sound, on Master.
func _bus_or_master(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) != -1 else "Master"


func play_sfx(path: String, pitch_variation: float = 0.08) -> void:
	var stream := _get_stream(path)
	if stream == null:
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(0, pitch_variation)
	player.play()


# ---------------------------------------------------------------------------
# Music
#
# One track, started at boot and never stopped. Volume is the Music bus, so the
# settings panel already controls it and nothing here reads a slider.
# ---------------------------------------------------------------------------

func find_music() -> String:
	for path in MUSIC_PATHS:
		if ResourceLoader.exists(path):
			return path
	return ""


func play_music(path: String, fade: float = MUSIC_FADE) -> void:
	if path.is_empty() or _music == null:
		return
	if path == _music_path and _music.playing:
		return
	var stream := _get_stream(path)
	if stream == null:
		return

	_loop_forever(stream)
	_music_path = path
	_music.stream = stream
	_music.volume_db = SILENCE_DB
	_music.play()
	_fade_music_to(0.0, fade)


func stop_music(fade: float = MUSIC_FADE) -> void:
	if _music == null or not _music.playing:
		return
	_music_path = ""
	_fade_music_to(SILENCE_DB, fade)
	await _music_tween.finished
	_music.stop()


func is_music_playing() -> bool:
	return _music != null and _music.playing


## The import flag on the file is not to be trusted — it defaults to off, and a
## project that forgets it gets one silent minute and then nothing. Whether the
## stream can loop by itself is asked here instead, and if it cannot, the player
## simply starts it again when it ends.
func _loop_forever(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.set("loop", true)
	elif not _music.finished.is_connected(_on_music_finished):
		_music.finished.connect(_on_music_finished)


func _on_music_finished() -> void:
	if not _music_path.is_empty():
		_music.play()


func _fade_music_to(volume_db: float, seconds: float) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", volume_db, maxf(seconds, 0.01))


# ---------------------------------------------------------------------------
# Volume
#
# Everything outside works in 0..1, because that is what a slider is. Decibels
# stay in here, where the conversion happens once.
# ---------------------------------------------------------------------------

func bus_volume(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func set_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var linear := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, SILENCE_DB if linear <= 0.0 else linear_to_db(linear))


func is_bus_muted(bus_name: String) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	return index != -1 and AudioServer.is_bus_mute(index)


func set_bus_muted(bus_name: String, value: bool) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, value)


## Every bus there is, in mixer order. A settings screen can build itself from
## this instead of being told the names of a particular game's buses.
func bus_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	return names


# ---------------------------------------------------------------------------
# Remembering it
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var file := ConfigFile.new()
	for bus_name in bus_names():
		file.set_value(SETTINGS_SECTION, "%s_volume" % bus_name, bus_volume(bus_name))
		file.set_value(SETTINGS_SECTION, "%s_muted" % bus_name, is_bus_muted(bus_name))
	var error := file.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not write %s (error %d)." % [SETTINGS_PATH, error])


## A missing file is the normal first run, not a problem: the buses keep the
## levels the layout was saved with.
##
## Only keys the file actually holds are applied. A bus added to the project
## after somebody already saved their settings — a Music bus in a game that
## shipped without one — would otherwise be dragged to full volume by a file
## that has never heard of it, instead of keeping the level it was mixed at.
func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_PATH) != OK:
		return
	for bus_name in bus_names():
		var volume_key := "%s_volume" % bus_name
		var mute_key := "%s_muted" % bus_name
		if file.has_section_key(SETTINGS_SECTION, volume_key):
			set_bus_volume(bus_name, float(file.get_value(SETTINGS_SECTION, volume_key, 1.0)))
		if file.has_section_key(SETTINGS_SECTION, mute_key):
			set_bus_muted(bus_name, bool(file.get_value(SETTINGS_SECTION, mute_key, false)))


func _get_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var stream := load(path) as AudioStream
	_cache[path] = stream
	return stream


func _get_free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0] if not _players.is_empty() else null
