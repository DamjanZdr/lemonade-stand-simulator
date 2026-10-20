extends Node
## Anonymous demo telemetry: one Discord-webhook POST per session event.
## No personal data — random session id only, no Steam id or username.
## Release builds only; debug/editor sessions log locally instead.
const WEBHOOK_URL := (
	"https://discord.com/api/webhooks/1561941448419713124/"
	+ "m2X0NgGua4e4DMLZo2tDwllv-uTXe6Mn3-b2HyGYi-qZ5loCkeKSHSxB8TD1JOE-S2SJ"
)

var session_id := ""
var _session_start_msec := 0
var _fps_sum := 0.0
var _fps_samples := 0
var _fps_low := 0


func _ready() -> void:
	# Window-close is handled manually in main.gd so the quit summary
	# gets a bounded window to flush before the process exits.
	get_tree().auto_accept_quit = false
	EventBus.day_time_over.connect(
		func() -> void:
			checkpoint("day_end"),
	)


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		_fps_sum += fps
		_fps_samples += 1
		if fps < 30:
			_fps_low += 1


## New run: new id, fresh FPS stats, start ping.
func session_begin() -> void:
	session_id = "%x%x" % [Time.get_unix_time_from_system(), randi()]
	_session_start_msec = Time.get_ticks_msec()
	_fps_sum = 0.0
	_fps_samples = 0
	_fps_low = 0
	_send("session_start")


## Fire-and-forget checkpoint (day end / demo complete).
func checkpoint(reason: String) -> void:
	_send(reason)


## Session ended without quitting (exit to menu / disconnect). Sends the
## summary then clears the id so a later quit doesn't double-report.
func end_session(reason: String) -> void:
	if session_id == "":
		return
	_send(reason)
	session_id = ""


## Bounded send for the quit path — caller awaits then quits.
func send_and_wait(reason: String, timeout := 1.2) -> void:
	if not OS.has_feature("release") or OS.is_debug_build():
		return
	if session_id == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			req.queue_free(),
	)
	req.request(
		WEBHOOK_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(_payload(reason)),
	)
	var start := Time.get_ticks_msec()
	while is_instance_valid(req) \
			and Time.get_ticks_msec() - start < int(timeout * 1000.0):
		await get_tree().process_frame


func _send(reason: String) -> void:
	var body := JSON.stringify(_payload(reason))
	if not OS.has_feature("release") or OS.is_debug_build():
		GameLog.log("[Analytics] %s (not sent in debug build)" % reason)
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(
		func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			req.queue_free(),
	)
	var err := req.request(
		WEBHOOK_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body,
	)
	if err != OK:
		req.queue_free()


func _payload(reason: String) -> Dictionary:
	var minutes := 0.0
	if _session_start_msec > 0:
		minutes = (Time.get_ticks_msec() - _session_start_msec) / 60000.0
	var avg_fps := 0.0
	var low_pct := 0.0
	if _fps_samples > 0:
		avg_fps = _fps_sum / _fps_samples
		low_pct = 100.0 * _fps_low / _fps_samples
	var mode := "solo"
	var role := "host"
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		mode = "coop" if LobbyManager.game_mode == GameState.GameMode.COOP else "versus"
		role = "host" if multiplayer.is_server() else "client"
	var stand: StandUnit = WorldSync.get_local_stand()
	var discoveries := ""
	var perfect := "no"
	if stand != null and is_instance_valid(stand):
		var p: Dictionary = stand.onboarding_progress
		var found: Array = p.get("discovered_recipes", { }).keys()
		if p.get("discovered_ice_ratio", null) != null:
			found.append("ice")
		discoveries = ", ".join(found) if not found.is_empty() else "none"
		if not stand.perfect_recipes_set.is_empty():
			perfect = ", ".join(stand.perfect_recipes_set.keys())
	var mem := OS.get_memory_info()
	var fields: Array = [
		{ "name": "Session", "value": "%s · %.1f min" % [session_id, minutes], "inline": true },
		{ "name": "Mode", "value": "%s (%s)" % [mode, role], "inline": true },
		{ "name": "Day", "value": str(DayManager.day_number), "inline": true },
		{ "name": "Money", "value": "$%.0f" % GameState.money, "inline": true },
		{ "name": "Cups (all-time)", "value": str(GameState.total_cups_sold), "inline": true },
		{
			"name": "Served/lost (today)",
			"value": "%d / %d" % [GameState.customers_served_happy, GameState.customers_lost],
			"inline": true,
		},
		{ "name": "Avg FPS", "value": "%.0f (%.0f%% <30)" % [avg_fps, low_pct], "inline": true },
		{ "name": "Discoveries", "value": discoveries, "inline": true },
		{ "name": "Perfect recipe", "value": perfect, "inline": true },
		{ "name": "Achievements", "value": _achievements(), "inline": true },
		{ "name": "GPU", "value": RenderingServer.get_video_adapter_name(), "inline": false },
		{
			"name": "PC",
			"value": "%s · %s (%d cores) · %.0f GB · %s · %s"
			% [
				OS.get_name(),
				OS.get_processor_name(),
				OS.get_processor_count(),
				float(mem.get("physical", 0)) / 1073741824.0,
				str(DisplayServer.window_get_size()),
				RenderingServer.get_current_rendering_method(),
			],
			"inline": false,
		},
	]
	return {
		"embeds": [{ "title": "Demo session — %s" % reason, "color": 0xF5D547, "fields": fields }],
	}


func _achievements() -> String:
	var ids: Array = AchievementManager.get_unlocked_ids()
	return ", ".join(ids) if not ids.is_empty() else "none"
