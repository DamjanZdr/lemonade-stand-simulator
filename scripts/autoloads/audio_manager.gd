extends Node
## Central 3D SFX player. Preloads all sound effects and plays them positionally.
##
## Usage:
##   AudioManager.play_sfx("pick_up_box", global_position)
##   AudioManager.play_sfx("press_fruits", global_position, _press_duration)

const SFX_DIR := "res://audio/sounds/"
const _PITCH_VARIATION: float = 0.05
const _UI_PITCH_VARIATION: float = 0.02
## UI sounds (play_sfx_ui) play through a plain, non-positional
## AudioStreamPlayer with no distance falloff, unlike world SFX (play_sfx)
## which get quieter with distance via AudioStreamPlayer3D. Without this
## offset, UI sounds always end up feeling loud relative to world sounds
## even when the underlying files are normalized to the same level.
const UI_VOLUME_DB: float = -8.0

var _streams: Dictionary = { }


func _ready() -> void:
	_preload_all()
	EventBus.change_finalized.connect(_on_change_finalized)


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
		"button_hover": "button hover.mp3",
		"hover": "hover.mp3",
		"tab_click": "tab click.mp3",
		"upgrade_bought": "upgradebought.mp3",
		"pitcher": "pitcher.mp3",
		"press": "press placed.mp3",
		"fruit_bin": "fruit bin placed.mp3",
		"table": "table placed.mp3",
		"trash": "trash.mp3",
	}
	for key in files:
		var path: String = SFX_DIR + files[key]
		var stream := load(path) as AudioStream
		if stream:
			_streams[key] = stream
		else:
			push_warning("AudioManager: could not load '%s'" % path)


func _on_change_finalized(_earned: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var pos: Vector3 = (player as Node3D).global_position if player else Vector3.ZERO
	play_sfx("transaction_complete", pos, -1.0, 0.1)


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
) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = UI_VOLUME_DB
	player.pitch_scale = randf_range(base_pitch - pitch_variation, base_pitch + pitch_variation)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
