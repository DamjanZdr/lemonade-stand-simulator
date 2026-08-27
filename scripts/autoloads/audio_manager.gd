extends Node
## Central 3D SFX player. Preloads all sound effects and plays them positionally.
##
## Usage:
##   AudioManager.play_sfx("pick_up_box", global_position)
##   AudioManager.play_sfx("press_fruits", global_position, _press_duration)

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music tracks/"
const _PITCH_VARIATION: float = 0.05
const _UI_PITCH_VARIATION: float = 0.02
## UI sounds (play_sfx_ui) play through a plain, non-positional
## AudioStreamPlayer with no distance falloff, unlike world SFX (play_sfx)
## which get quieter with distance via AudioStreamPlayer3D. Without this
## offset, UI sounds always end up feeling loud relative to world sounds
## even when the underlying files are normalized to the same level.
const UI_VOLUME_DB: float = -8.0

var _streams: Dictionary = { }
var _music_player: AudioStreamPlayer = null
var _music_tracks: Array[String] = []
var _music_index: int = 0

signal music_track_changed(track_name: String)
signal music_progress(current: float, total: float)


func _ready() -> void:
	_ensure_buses()
	_preload_all()
	_preload_music()
	EventBus.change_finalized.connect(_on_change_finalized)
	# Start menu music immediately — it loops and persists across
	# scene transitions since AudioManager is an autoload.
	_play_music("Crinoline Dreams")


func _process(_delta: float) -> void:
	if _music_player and _music_player.playing:
		var stream := _music_player.stream as AudioStreamMP3
		if stream:
			music_progress.emit(_music_player.get_playback_position(), stream.get_length())


## Ensure SFX and Music buses exist (created at runtime so we don't
## need a .bus layout file). Master is always bus 0.
func _ensure_buses() -> void:
	# Master is bus 0 by default.
	# Add SFX bus if missing.
	if AudioServer.get_bus_count() < 2:
		AudioServer.add_bus()
		AudioServer.set_bus_name(1, "SFX")
		AudioServer.set_bus_send(1, "Master")
	# Add Music bus if missing.
	if AudioServer.get_bus_count() < 3:
		AudioServer.add_bus()
		AudioServer.set_bus_name(2, "Music")
		AudioServer.set_bus_send(2, "Master")
	# Default all volumes to 50%.
	AudioServer.set_bus_volume_db(0, linear_to_db(0.5))
	AudioServer.set_bus_volume_db(1, linear_to_db(0.5))
	AudioServer.set_bus_volume_db(2, linear_to_db(0.5))


func _preload_all() -> void:
	var files := {
		"box_drop": "box drop on ground.mp3",
		"fill_up_cup": "fill up cup.mp3",
		"fruit_in_crate": "fruit in crate.mp3",
		"fruit_pickup_from_crate": "fruit pickup from crate.mp3",
		"pick_up_box": "pick up box.mp3",
		"press_fruits": "press fruits.mp3",
		"taking_cup": "taking cup.mp3",
		"water_pour_in_pitcher": "water pour in pitcher.mp3",
		"coins": "coins.mp3",
		"cash": "cash.mp3",
		"transaction_complete": "transaction complete.mp3",
		"swoosh": "swoosh.mp3",
		"stand_transition_swoosh": "stand transition swoosh.mp3",
		"button_hover": "button hover.mp3",
		"hover": "hover.mp3",
		"blip_select": "blipSelect.wav",
		"tab_click": "tab click.mp3",
		"upgrade_bought": "upgradebought.mp3",
		"pitcher": "pitcher.mp3",
		"press": "press placed.mp3",
		"fruit_bin": "fruit bin placed.mp3",
		"table": "table placed.mp3",
		"trash": "trash.mp3",
		"car_engine": "car engine.mp3",
		"car_beep": "car beep.mp3",
		"start_engine": "start engine.mp3",
	}
	for key in files:
		var path: String = SFX_DIR + files[key]
		var stream := load(path) as AudioStream
		if stream:
			_streams[key] = stream
		else:
			push_warning("AudioManager: could not load '%s'" % path)


func _on_change_finalized(_earned: float) -> void:
	var player := WorldSync.get_local_player()
	var pos: Vector3 = (player as Node3D).global_position if player else Vector3.ZERO
	play_sfx("transaction_complete", pos, -1.0, 0.1)


## Preload music tracks from the music directory.
func _preload_music() -> void:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("AudioManager: could not open music dir '%s'" % MUSIC_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".mp3"):
			var key := file_name.get_basename()
			var path := MUSIC_DIR + file_name
			var stream := load(path) as AudioStreamMP3
			if stream:
				stream.loop = true
				_streams["music_" + key] = stream
				_music_tracks.append(key)
		file_name = dir.get_next()
	dir.list_dir_end()
	_music_tracks.sort()


## Play a music track on the Music bus. Loops indefinitely.
## Since AudioManager is an autoload, this persists across scene changes.
func _play_music(track_name: String) -> void:
	var key := "music_" + track_name
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		push_warning("AudioManager: music track '%s' not found" % track_name)
		return
	if _music_player and _music_player.playing:
		if _music_player.stream == stream:
			return # Already playing this track.
		_music_player.stop()
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = "Music"
		add_child(_music_player)
	_music_player.stream = stream
	_music_player.play()
	var idx := _music_tracks.find(track_name)
	if idx >= 0:
		_music_index = idx
	music_track_changed.emit(track_name)


## Get the current track name.
func get_current_track() -> String:
	if _music_tracks.is_empty():
		return ""
	return _music_tracks[_music_index]


## Cycle to the next music track. Returns the new track name.
func next_track() -> String:
	if _music_tracks.is_empty():
		return ""
	_music_index = (_music_index + 1) % _music_tracks.size()
	var track := _music_tracks[_music_index]
	_play_music(track)
	return track


## Cycle to the previous music track. Returns the new track name.
func prev_track() -> String:
	if _music_tracks.is_empty():
		return ""
	_music_index = (_music_index - 1 + _music_tracks.size()) % _music_tracks.size()
	var track := _music_tracks[_music_index]
	_play_music(track)
	return track


## Get all available music track names.
func get_track_list() -> Array[String]:
	return _music_tracks.duplicate()


func play_sfx(
	key: String,
	pos: Vector3 = Vector3.ZERO,
	duration_match: float = -1.0,
	pitch_variation: float = _PITCH_VARIATION,
	base_pitch: float = 1.0,
) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return

	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.unit_size = 5.0
	player.max_distance = 50.0

	# Pitch variation so each play sounds slightly different
	var pitch := randf_range(base_pitch - pitch_variation, base_pitch + pitch_variation)
	player.pitch_scale = pitch

	player.finished.connect(player.queue_free)
	scene.add_child(player)
	player.global_position = pos

	# Duration matching: play the last `duration_match` seconds of the sound
	# with a short fade-in, instead of pitch-shifting.
	if duration_match > 0.0 and stream is AudioStreamMP3:
		var orig_len: float = (stream as AudioStreamMP3).get_length()
		if orig_len > duration_match:
			var seek_pos := orig_len - duration_match
			player.play(seek_pos)
			# Fade in over 0.3s
			player.volume_db = -40.0
			var tween := scene.create_tween()
			tween.tween_property(player, "volume_db", 0.0, 0.3)
			return

	player.play()


func play_sfx_ui(
	key: String,
	base_pitch: float = 1.0,
	pitch_variation: float = _UI_PITCH_VARIATION,
	seek_offset: float = 0.0,
	fade_in: float = 0.0,
) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = UI_VOLUME_DB
	player.pitch_scale = randf_range(base_pitch - pitch_variation, base_pitch + pitch_variation)
	player.finished.connect(player.queue_free)
	add_child(player)
	if seek_offset > 0.0 and stream is AudioStreamMP3:
		player.play(seek_offset)
	else:
		player.play()
	if fade_in > 0.0:
		var start_vol := player.volume_db
		player.volume_db = -40.0
		var tween := create_tween()
		tween.tween_property(player, "volume_db", start_vol, fade_in)
