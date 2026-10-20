extends Node
## Anonymous demo telemetry: a start ping plus ONE end-of-session summary
## per peer (tagged host/client), posted to the project's Discord webhook.
## No personal data — random session id only, no Steam id or username.
## Release builds only; debug/editor sessions log locally instead.
const WEBHOOK_URL := (
	"https://discord.com/api/webhooks/1561941448419713124/"
	+ "m2X0NgGua4e4DMLZo2tDwllv-uTXe6Mn3-b2HyGYi-qZ5loCkeKSHSxB8TD1JOE-S2SJ"
)

var session_id := ""
var _session_start_msec := 0
var _start_day := 0
var _start_money := 0.0
var _start_cups := 0
var _fps_sum := 0.0
var _fps_samples := 0
var _fps_low := 0
var _max_players := 1
var _clicks: Dictionary = { }


func _ready() -> void:
	# Window-close is handled manually in main.gd so the quit summary
	# gets a bounded window to flush before the process exits.
	get_tree().auto_accept_quit = false


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		_fps_sum += fps
		_fps_samples += 1
		if fps < 30:
			_fps_low += 1
	if multiplayer.has_multiplayer_peer():
		_max_players = maxi(_max_players, multiplayer.get_peers().size() + 1)


## New run: new id, fresh counters, baseline snapshot, start ping.
func session_begin() -> void:
	session_id = "%x%x" % [Time.get_unix_time_from_system(), randi()]
	_session_start_msec = Time.get_ticks_msec()
	_fps_sum = 0.0
	_fps_samples = 0
	_fps_low = 0
	_max_players = 1
	# _clicks intentionally NOT cleared — menu clicks before a run still
	# count toward whatever summary eventually reports.
	var stand := _local_stand()
	_start_day = DayManager.day_number
	_start_money = stand.money if stand != null else GameState.money
	_start_cups = stand.total_cups_sold if stand != null else GameState.total_cups_sold
	_send("session_start")


## Count a button click worth reporting (wishlist / discord / bug report).
func track(event: String) -> void:
	_clicks[event] = int(_clicks.get(event, 0)) + 1


## Session ended without quitting (exit to menu / disconnect). Sends the
## summary then clears the id so a later quit doesn't double-report.
func end_session(reason: String) -> void:
	if session_id == "":
		return
	_send(reason)
	session_id = ""
	_clicks.clear()


## Bounded send for the quit path — caller awaits then quits.
func send_and_wait(reason: String, timeout := 1.2) -> void:
	if not OS.has_feature("release") or OS.is_debug_build():
		return
	# A menu-only visit can still have clicks worth reporting (e.g. they
	# hit wishlist and quit without ever starting a game).
	if session_id == "" and _clicks.is_empty():
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
	_clicks.clear()


func _local_stand() -> StandUnit:
	var s: StandUnit = WorldSync.get_local_stand()
	return s if s != null and is_instance_valid(s) else null


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
	# GameState is only written on the host — clients must read the synced
	# StandUnit or every stat reports as frozen defaults.
	var money := GameState.money
	var cups := GameState.total_cups_sold
	var happy := GameState.customers_served_happy
	var lost := GameState.customers_lost
	var stand := _local_stand()
	if stand != null:
		money = stand.money
		cups = stand.total_cups_sold
		happy = stand.customers_served_happy
		lost = stand.customers_lost
	var discoveries := ""
	var perfect := "no"
	var last_day := ""
	var demo := "n/a"
	if stand != null:
		var p: Dictionary = stand.onboarding_progress
		var found: Array = p.get("discovered_recipes", { }).keys()
		if p.get("discovered_ice_ratio", null) != null:
			found.append("ice")
		discoveries = ", ".join(found) if not found.is_empty() else "none"
		if not stand.perfect_recipes_set.is_empty():
			perfect = ", ".join(stand.perfect_recipes_set.keys())
		if p.get("skipped", false):
			demo = "skipped"
		elif p.get("completed", false) \
				or p.get("current_task_id", "") == "demo_keep_running":
			demo = "completed"
		else:
			demo = "in progress"
		var l: Dictionary = stand.last_day_stats
		if not l.is_empty():
			last_day = (
				"d%d: %d arrived · %d bought · %d happy · "
				+ "%d timeouts · %d pricey · %d wrong · %d scams · profit $%.0f"
			) % [
				int(l.get("day", 0)),
				int(l.get("customers_arrived", 0)),
				int(l.get("customers_bought", 0)),
				int(l.get("happy", 0)),
				int(l.get("timeouts", 0)),
				int(l.get("too_expensive", 0)),
				int(l.get("wrong_order", 0)),
				int(l.get("scams", 0)),
				float(l.get("profit", 0.0)),
			]
	var mem := OS.get_memory_info()
	var fields: Array = [
		{
			"name": "Session",
			"value": (
				("%s · %.1f min" % [session_id, minutes])
				if session_id != ""
				else "menu only"
			),
			"inline": true,
		},
		{
			"name": "Mode",
			"value": "%s (%s) · %d player(s)" % [mode, role, _max_players],
			"inline": true,
		},
		{ "name": "Demo", "value": demo, "inline": true },
		{
			"name": "Progress",
			"value": "day %d→%d · $%.0f→%.0f · %d→%d cups"
			% [_start_day, DayManager.day_number, _start_money, money, _start_cups, cups],
			"inline": false,
		},
		{ "name": "Served/lost (today)", "value": "%d / %d" % [happy, lost], "inline": true },
		{ "name": "Avg FPS", "value": "%.0f (%.0f%% <30)" % [avg_fps, low_pct], "inline": true },
		{ "name": "Discoveries", "value": discoveries, "inline": true },
		{ "name": "Perfect recipe", "value": perfect, "inline": true },
		{ "name": "Achievements", "value": _achievements(), "inline": true },
		{ "name": "Clicks", "value": _clicks_text(), "inline": true },
		{ "name": "Last day", "value": last_day if last_day != "" else "n/a", "inline": false },
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


func _clicks_text() -> String:
	if _clicks.is_empty():
		return "none"
	var parts: Array[String] = []
	for k in _clicks:
		parts.append("%s ×%d" % [k, int(_clicks[k])])
	return ", ".join(parts)


func _achievements() -> String:
	var ids: Array = AchievementManager.get_unlocked_ids()
	return ", ".join(ids) if not ids.is_empty() else "none"
