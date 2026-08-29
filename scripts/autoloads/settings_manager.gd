extends Node
## Persists user settings (audio volumes, graphics toggles) across sessions
## using a ConfigFile at user://settings.cfg.

const CONFIG_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_GRAPHICS := "graphics"

const DEFAULT_MASTER_VOLUME := 0.5
const DEFAULT_SFX_VOLUME := 0.5
const DEFAULT_MUSIC_VOLUME := 0.5
const DEFAULT_FULLSCREEN := false
const DEFAULT_VSYNC := true
const DEFAULT_ENHANCED_LIGHTING := true
const DEFAULT_FPS_COUNTER := false

signal settings_loaded()


func _ready() -> void:
	load_settings()


## Load settings from disk and apply them to AudioServer / DisplayServer.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# No config file yet — use defaults (already set by AudioManager).
		settings_loaded.emit()
		return
	# Audio
	var master := cfg.get_value(SECTION_AUDIO, "master", DEFAULT_MASTER_VOLUME) as float
	var sfx := cfg.get_value(SECTION_AUDIO, "sfx", DEFAULT_SFX_VOLUME) as float
	var music := cfg.get_value(SECTION_AUDIO, "music", DEFAULT_MUSIC_VOLUME) as float
	AudioServer.set_bus_volume_db(0, linear_to_db(master))
	if AudioServer.get_bus_count() > 1:
		AudioServer.set_bus_volume_db(1, linear_to_db(sfx))
	if AudioServer.get_bus_count() > 2:
		AudioServer.set_bus_volume_db(2, linear_to_db(music))
	# Graphics
	var fullscreen := cfg.get_value(SECTION_GRAPHICS, "fullscreen", DEFAULT_FULLSCREEN) as bool
	var vsync := cfg.get_value(SECTION_GRAPHICS, "vsync", DEFAULT_VSYNC) as bool
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	settings_loaded.emit()


## Save current settings to disk.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	# Audio
	var master := db_to_linear(AudioServer.get_bus_volume_db(0))
	var sfx := master
	var music := master
	if AudioServer.get_bus_count() > 1:
		sfx = db_to_linear(AudioServer.get_bus_volume_db(1))
	if AudioServer.get_bus_count() > 2:
		music = db_to_linear(AudioServer.get_bus_volume_db(2))
	cfg.set_value(SECTION_AUDIO, "master", master)
	cfg.set_value(SECTION_AUDIO, "sfx", sfx)
	cfg.set_value(SECTION_AUDIO, "music", music)
	# Graphics
	cfg.set_value(
		SECTION_GRAPHICS,
		"fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
	)
	cfg.set_value(
		SECTION_GRAPHICS,
		"vsync",
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
	)
	cfg.save(CONFIG_PATH)


## Save a single graphics toggle value (for enhanced_lighting / fps_counter,
## which are handled by main.gd and not queryable from DisplayServer).
func save_graphics_bool(key: String, value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION_GRAPHICS, key, value)
	cfg.save(CONFIG_PATH)


## Read a graphics bool from the config file (with default).
func get_graphics_bool(key: String, default: bool) -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return default
	return cfg.get_value(SECTION_GRAPHICS, key, default) as bool
