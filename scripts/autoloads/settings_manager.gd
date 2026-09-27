extends Node
## Persists user settings (audio volumes, graphics toggles) across sessions
## using a ConfigFile at user://settings.cfg.

const CONFIG_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_GRAPHICS := "graphics"
const SECTION_GAMEPLAY := "gameplay"

const DEFAULT_MASTER_VOLUME := 0.5
const DEFAULT_SFX_VOLUME := 0.5
const DEFAULT_MUSIC_VOLUME := 0.5
const DEFAULT_FULLSCREEN := false
const DEFAULT_VSYNC := false
const DEFAULT_ENHANCED_LIGHTING := true
const DEFAULT_FPS_COUNTER := false
const DEFAULT_AUTOSAVE_MINUTES := 5.0
const DEFAULT_GRAPHICS_QUALITY := "high"
const AUTOSAVE_MIN_MINUTES := 2.0
const AUTOSAVE_MAX_MINUTES := 15.0
const DEFAULT_MOUSE_SENSITIVITY := 1.0
const MOUSE_SENSITIVITY_MIN := 0.5
const MOUSE_SENSITIVITY_MAX := 2.0
const DEFAULT_FOV := 90.0
const FOV_MIN := 75.0
const FOV_MAX := 105.0

const GRAPHICS_PRESETS := {
	"epic": {
		"shadow_size": 4096,
		"soft_shadow": 3,
		"msaa": 2,
		"fxaa": false,
		"grass_multiplier": 2.0,
		"grass_draw_mult": 1.6,
		"grass_max_blades": 8000,
		"ssao": true,
		"ssil": true,
		"glow": true,
	},
	"high": {
		"shadow_size": 2048,
		"soft_shadow": 2,
		"msaa": 2,
		"fxaa": true,
		"grass_multiplier": 1.0,
		"grass_draw_mult": 1.3,
		"grass_max_blades": 6000,
		"ssao": true,
		"ssil": false,
		"glow": true,
	},
	"medium": {
		"shadow_size": 2048,
		"soft_shadow": 1,
		"msaa": 0,
		"fxaa": true,
		"grass_multiplier": 0.7,
		"grass_draw_mult": 1.0,
		"grass_max_blades": 4000,
		"ssao": false,
		"ssil": false,
		"glow": true,
	},
	"low": {
		"shadow_size": 1024,
		"soft_shadow": 0,
		"msaa": 0,
		"fxaa": false,
		"grass_multiplier": 0.5,
		"grass_draw_mult": 0.7,
		"grass_max_blades": 2500,
		"ssao": false,
		"ssil": false,
		"glow": false,
	},
}

signal settings_loaded()
signal gameplay_changed()
signal graphics_quality_applied()

var _mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var _fov := DEFAULT_FOV


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
	var quality := cfg.get_value(SECTION_GRAPHICS, "graphics_quality", DEFAULT_GRAPHICS_QUALITY) as String
	apply_graphics_quality(quality)
	# Gameplay
	_mouse_sensitivity = clampf(
		cfg.get_value(SECTION_GAMEPLAY, "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY) as float,
		MOUSE_SENSITIVITY_MIN,
		MOUSE_SENSITIVITY_MAX,
	)
	_fov = clampf(cfg.get_value(SECTION_GAMEPLAY, "fov", DEFAULT_FOV) as float, FOV_MIN, FOV_MAX)
	# Remove any hard FPS cap so the game can run above the monitor refresh
	# rate when VSync is off. The default is unlimited, but force it here
	# in case project settings or an old config changed it.
	Engine.max_fps = 0
	settings_loaded.emit()


func apply_graphics_quality(quality: String) -> void:
	var preset: Dictionary = GRAPHICS_PRESETS.get(
		quality,
		GRAPHICS_PRESETS[DEFAULT_GRAPHICS_QUALITY],
	)
	# Directional shadow map size / soft shadow filter are read from
	# ProjectSettings when the shadow atlas is allocated.
	ProjectSettings.set_setting(
		"rendering/lights_and_shadows/directional_shadow/size",
		preset["shadow_size"],
	)
	ProjectSettings.set_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
		preset["soft_shadow"],
	)
	# MSAA / FXAA live on the root viewport.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var vp := tree.root
		vp.msaa_3d = preset["msaa"] as Viewport.MSAA
		if preset["fxaa"]:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		else:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		var env := vp.world_3d.environment if vp.world_3d != null else null
		if env != null:
			env.ssao_enabled = preset["ssao"]
			env.ssil_enabled = preset["ssil"]
			env.glow_enabled = preset["glow"]
	# Tell grass scatterers to regenerate with the new density multiplier.
	if tree != null:
		tree.call_group("grass_scatterer", "regenerate")
	graphics_quality_applied.emit()


## Save current settings to disk.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	# Load existing keys first so other sections (e.g. gameplay) survive.
	cfg.load(CONFIG_PATH)
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
	cfg.set_value(SECTION_GRAPHICS, "graphics_quality", get_graphics_quality())
	cfg.save(CONFIG_PATH)


func get_graphics_quality() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return DEFAULT_GRAPHICS_QUALITY
	var q := cfg.get_value(SECTION_GRAPHICS, "graphics_quality", DEFAULT_GRAPHICS_QUALITY) as String
	if not GRAPHICS_PRESETS.has(q):
		return DEFAULT_GRAPHICS_QUALITY
	return q


func set_graphics_quality(quality: String) -> void:
	if not GRAPHICS_PRESETS.has(quality):
		quality = DEFAULT_GRAPHICS_QUALITY
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION_GRAPHICS, "graphics_quality", quality)
	cfg.save(CONFIG_PATH)
	apply_graphics_quality(quality)


func get_grass_density_multiplier() -> float:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_multiplier


func get_grass_draw_multiplier() -> float:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_draw_mult


func get_grass_max_blades() -> int:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_max_blades


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


## Autosave interval in minutes (2-15, default 5).
func get_autosave_minutes() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return DEFAULT_AUTOSAVE_MINUTES
	var v := cfg.get_value(SECTION_GAMEPLAY, "autosave_minutes", DEFAULT_AUTOSAVE_MINUTES) as float
	return clampf(v, AUTOSAVE_MIN_MINUTES, AUTOSAVE_MAX_MINUTES)


func set_autosave_minutes(minutes: float) -> void:
	_set_gameplay_value(
		"autosave_minutes",
		clampf(minutes, AUTOSAVE_MIN_MINUTES, AUTOSAVE_MAX_MINUTES),
	)


## Mouse sensitivity multiplier (0.5-2.0, default 1.0).
func get_mouse_sensitivity() -> float:
	return _mouse_sensitivity


func set_mouse_sensitivity(value: float, persist := true) -> void:
	_mouse_sensitivity = clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	if persist:
		_set_gameplay_value("mouse_sensitivity", _mouse_sensitivity)
	gameplay_changed.emit()


## First-person camera field of view (75-105, default 90).
func get_fov() -> float:
	return _fov


func set_fov(value: float, persist := true) -> void:
	_fov = clampf(value, FOV_MIN, FOV_MAX)
	if persist:
		_set_gameplay_value("fov", _fov)
	gameplay_changed.emit()


func _set_gameplay_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION_GAMEPLAY, key, value)
	cfg.save(CONFIG_PATH)
