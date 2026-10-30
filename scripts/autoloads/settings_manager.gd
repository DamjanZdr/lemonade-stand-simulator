extends Node
## Persists user settings (audio volumes, graphics toggles) across sessions
## using a ConfigFile at user://settings.cfg.

const CONFIG_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_GRAPHICS := "graphics"
const SECTION_GAMEPLAY := "gameplay"
const SECTION_CONTROLS := "controls"

## Actions the player can remap from the Controls settings tab.
const REMAPPABLE_ACTIONS: Array[String] = [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"sprint",
	"jump",
	"crouch",
	"primary_interact",
	"secondary_interact",
]

const DEFAULT_MASTER_VOLUME := 0.5
const DEFAULT_SFX_VOLUME := 0.5
const DEFAULT_MUSIC_VOLUME := 0.5
const DEFAULT_FULLSCREEN := true
const DEFAULT_VSYNC := false
const DEFAULT_ENHANCED_LIGHTING := true
const DEFAULT_FPS_COUNTER := false
const DEFAULT_AUTOSAVE_MINUTES := 5.0
const DEFAULT_GRAPHICS_QUALITY := "high"
const DEFAULT_FPS_CAP := 120
const FPS_CAP_OPTIONS: Array[int] = [60, 120, 240, 0] # 0 = uncapped
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
		"grass_view_distance": 80.0,
		"house_lod_distance": 200.0,
		"lighting_level": 3,
		"ssao": true,
		"ssil": true,
		"glow": true,
	},
	"high": {
		"shadow_size": 2048,
		"soft_shadow": 2,
		"msaa": 2,
		"fxaa": true,
		"grass_multiplier": 0.6,
		"grass_draw_mult": 1.1,
		"grass_max_blades": 4000,
		"grass_view_distance": 66.7,
		"house_lod_distance": 140.0,
		"lighting_level": 2,
		"ssao": true,
		"ssil": false,
		"glow": true,
	},
	"medium": {
		"shadow_size": 2048,
		"soft_shadow": 1,
		"msaa": 0,
		"fxaa": true,
		"grass_multiplier": 0.3,
		"grass_draw_mult": 0.8,
		"grass_max_blades": 1800,
		"grass_view_distance": 53.3,
		"house_lod_distance": 90.0,
		"lighting_level": 1,
		"ssao": false,
		"ssil": false,
		"glow": true,
	},
	"low": {
		"shadow_size": 1024,
		"soft_shadow": 0,
		"msaa": 0,
		"fxaa": false,
		"grass_multiplier": 0.12,
		"grass_draw_mult": 0.5,
		"grass_max_blades": 700,
		"grass_view_distance": 40.0,
		"house_lod_distance": 55.0,
		"lighting_level": 0,
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
	# Always launch fullscreen. The Settings fullscreen toggle still works
	# for the current session, but every launch starts fullscreen.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# FPS cap defaults on (saves power on high-refresh machines) even
	# before a config exists — a saved value overrides it below.
	Engine.max_fps = DEFAULT_FPS_CAP
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
	var vsync := cfg.get_value(SECTION_GRAPHICS, "vsync", DEFAULT_VSYNC) as bool
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
	var cap := cfg.get_value(SECTION_GRAPHICS, "fps_cap", DEFAULT_FPS_CAP) as int
	if cap > 0 and cap not in FPS_CAP_OPTIONS:
		cap = DEFAULT_FPS_CAP
	Engine.max_fps = cap
	# Keybinds
	apply_saved_keybinds()
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
	# Tell grass scatterers to regenerate with the new density multiplier,
	# baked grass patches to thin out, and houses to re-evaluate their
	# LOD swap distance.
	if tree != null:
		tree.call_group("grass_scatterer", "regenerate")
		tree.call_group("neighborhood", "apply_grass_quality")
		tree.call_group(
			"neighborhood",
			"apply_house_lod_distance",
			float(preset.get("house_lod_distance", 200.0)),
		)
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
	cfg.set_value(SECTION_GRAPHICS, "fps_cap", get_fps_cap())
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


func get_fps_cap() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return DEFAULT_FPS_CAP
	var cap := cfg.get_value(SECTION_GRAPHICS, "fps_cap", DEFAULT_FPS_CAP) as int
	return cap if cap in FPS_CAP_OPTIONS else DEFAULT_FPS_CAP


func set_fps_cap(cap: int) -> void:
	if cap not in FPS_CAP_OPTIONS:
		cap = DEFAULT_FPS_CAP
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION_GRAPHICS, "fps_cap", cap)
	cfg.save(CONFIG_PATH)
	Engine.max_fps = cap


func get_grass_density_multiplier() -> float:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_multiplier


func get_grass_draw_multiplier() -> float:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_draw_mult


func get_grass_max_blades() -> int:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_max_blades


## Draw radius for baked grass patches — Epic keeps the authored 80m,
## Low halves it, tiers interpolate.
func get_grass_view_distance() -> float:
	return GRAPHICS_PRESETS[get_graphics_quality()].grass_view_distance


## Enhanced-lighting tier for the current preset: 0=off (Low), 1=light
## (Medium), 2=reduced (High), 3=full (Epic). The user's manual toggle
## floors it at 0 — on Low it's forced off regardless.
func get_lighting_level() -> int:
	if not get_graphics_bool("enhanced_lighting", DEFAULT_ENHANCED_LIGHTING):
		return 0
	return int(GRAPHICS_PRESETS[get_graphics_quality()].lighting_level)


## Distance at which full house meshes swap to the cheap LOD shell.
func get_house_lod_distance() -> float:
	return float(GRAPHICS_PRESETS[get_graphics_quality()].get("house_lod_distance", 200.0))


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

# === KEYBINDS ===
# Saved as "key:<physical_keycode>" or "mouse:<button_index>" per action.


## Rebind an action to a single input event. Any other remappable action
## holding the same binding loses it — two actions never share one key.
func rebind_action(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for other in REMAPPABLE_ACTIONS:
		if other == action or not InputMap.has_action(other):
			continue
		for ev in InputMap.action_get_events(other):
			if _events_equal(ev, event):
				InputMap.action_erase_event(other, ev)
				var cfg := ConfigFile.new()
				cfg.load(CONFIG_PATH)
				cfg.erase_section_key(SECTION_CONTROLS, other)
				cfg.save(CONFIG_PATH)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION_CONTROLS, action, _serialize_input_event(event))
	cfg.save(CONFIG_PATH)


## Re-apply persisted keybinds over the project.godot defaults.
func apply_saved_keybinds() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for action in REMAPPABLE_ACTIONS:
		var saved: String = str(cfg.get_value(SECTION_CONTROLS, action, ""))
		if saved == "":
			continue
		var event := _deserialize_input_event(saved)
		if event == null:
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## First bound event for an action, or null when unbound.
func get_action_binding(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


func _events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return ((a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (
			(a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
		)
	return false


func _serialize_input_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key:%d" % (event as InputEventKey).physical_keycode
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


func _deserialize_input_event(data: String) -> InputEvent:
	var parts := data.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var e := InputEventKey.new()
		e.physical_keycode = parts[1].to_int() as Key
		return e
	if parts[0] == "mouse":
		var e := InputEventMouseButton.new()
		e.button_index = parts[1].to_int() as MouseButton
		return e
	return null
