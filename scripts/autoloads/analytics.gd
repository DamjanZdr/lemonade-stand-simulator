extends Node
## Anonymous demo telemetry: a start ping plus ONE end-of-session summary
## per peer (tagged host/client), posted to the project's Discord webhook.
## No personal data — random session id only, no Steam id or username.
## Release builds only; debug/editor sessions log locally instead.
const ENDPOINT := "https://script.google.com/macros/s/AKfycbxtVYc6S93vYoEMQh1Izr5mJxrh8K8TvPHEF2RPDRd2jHH8dExShn7LXhQ-Ew0mgoiL/exec"
const QUEUE_PATH := "user://analytics_pending.json"
const OUTCOMES := [
	"customers_arrived",
	"customers_bought",
	"happy",
	"complaints_fruit",
	"complaints_sugar",
	"complaints_ice",
	"timeouts",
	"too_expensive",
	"wrong_order",
	"scams",
]

var session_id := ""
var _match_id := ""
var _session_start_msec := 0
var _started_utc := ""
var _fps_sum := 0.0
var _fps_samples := 0.0
var _fps_low := 0.0
var _max_players := 1
var _participants := 1
var _clicks: Dictionary = { }
var _start: Dictionary = { }
var _last: Dictionary = { }
var _stand: StandUnit
var _mode := "coop"
var _role := "host"
var _ending := false
var _revision := 0
var _sample_clock := 0.0
var _checkpoint_clock := 0.0
var _members: Dictionary = { }
var _host_stands: Dictionary = { }
var _queue: Dictionary = { }
var _request: HTTPRequest
var _following_redirect := false
var _retry_at := 0
var _retry_seconds := 1
var _hardware: Dictionary = { }


func _ready() -> void:
	# Window-close is handled manually in main.gd so the quit summary
	# gets a bounded window to flush before the process exits.
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_peer_left)
	EventBus.day_phase_changed.connect(_phase_changed)
	if _network_enabled() and FileAccess.file_exists(QUEUE_PATH):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUEUE_PATH))
		if stored is Dictionary:
			_queue = stored


func _network_enabled() -> bool:
	return OS.has_feature("release") and not OS.is_debug_build()


func _process(delta: float) -> void:
	_pump()
	if session_id == "" or _ending:
		return
	var player := WorldSync.get_local_player()
	if (
		player != null and not EventBus.esc_menu_open and not EventBus.day_transition_active
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		var fps := Engine.get_frames_per_second()
		if fps > 0:
			_fps_sum += fps * delta
			_fps_samples += delta
			if fps < 30:
				_fps_low += delta
	_sample_clock += delta
	_checkpoint_clock += delta
	if _sample_clock >= 1.0:
		_sample_clock = 0.0
		if _match_id == "" and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(1):
			_request_match.rpc_id(1, session_id)
		_capture()
	if _checkpoint_clock >= 60.0 and not _start.is_empty() and _match_id != "":
		_checkpoint_clock = 0.0
		_send(_payload("checkpoint"))


## New run: new id, fresh counters, baseline snapshot, start ping.
func session_begin() -> void:
	if session_id != "":
		return
	session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_session_start_msec = Time.get_ticks_msec()
	_started_utc = Time.get_datetime_string_from_system(true) + "Z"
	_fps_sum = 0.0
	_fps_samples = 0.0
	_fps_low = 0.0
	_max_players = 1
	_participants = 1
	_mode = "versus" if LobbyManager.game_mode == GameState.GameMode.VERSUS else "coop"
	_role = "host" if WorldSync.is_host() else "client"
	_match_id = Crypto.new().generate_random_bytes(16).hex_encode() if _role == "host" else ""
	_ending = false
	_revision = 0
	_sample_clock = 0.0
	_checkpoint_clock = 0.0
	_start = { }
	_last = { }
	_stand = null
	_members.clear()
	_host_stands.clear()
	_hardware = _get_hardware()
	# _clicks intentionally NOT cleared — menu clicks before a run still
	# count toward whatever summary eventually reports.
	if _role == "host":
		_members[multiplayer.get_unique_id()] = session_id
	elif multiplayer.has_multiplayer_peer():
		_request_match.rpc_id(1, session_id)
	_capture()


@rpc("any_peer", "call_remote", "reliable")
func _request_match(participant_session: String) -> void:
	if _role != "host" or session_id == "" or _ending or not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if participant_session.length() != 32 or not LobbyManager.roster.has(peer):
		return
	if not _members.has(peer):
		_participants += 1
	_members[peer] = participant_session
	_max_players = maxi(_max_players, _members.size())
	_broadcast_match()


func _broadcast_match() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_receive_match.rpc(_match_id, _mode, _max_players, _participants)


@rpc("authority", "call_remote", "reliable")
func _receive_match(id: String, mode: String, peak: int, participants: int) -> void:
	if session_id == "" or _ending or _role != "client":
		return
	_match_id = id
	_mode = mode
	_max_players = peak
	_participants = participants
	_capture()


func _peer_left(peer: int) -> void:
	if _role == "host" and session_id != "":
		_members.erase(peer)


func _phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING and session_id != "" and not _ending:
		_capture()
		if not _start.is_empty() and _match_id != "":
			_send(_payload("day_end"))


## Count a button click worth reporting (wishlist / discord / bug report).
func track(event: String) -> void:
	_clicks[event] = int(_clicks.get(event, 0)) + 1


## Session ended without quitting (exit to menu / disconnect). Sends the
## summary then clears the id so a later quit doesn't double-report.
func end_session(reason: String) -> void:
	if session_id == "" or _ending:
		return
	_capture()
	_ending = true
	_send(_payload(reason))
	session_id = ""
	_clicks.clear()


## Bounded send for the quit path — caller awaits then quits.
func send_and_wait(reason: String, timeout := 5.0) -> void:
	# A menu-only visit can still have clicks worth reporting (e.g. they
	# hit wishlist and quit without ever starting a game).
	if session_id != "" and not _ending:
		end_session(reason)
	elif session_id == "" and not _clicks.is_empty():
		session_id = Crypto.new().generate_random_bytes(16).hex_encode()
		_session_start_msec = Time.get_ticks_msec()
		_started_utc = Time.get_datetime_string_from_system(true) + "Z"
		_start = { }
		_last = { }
		_host_stands.clear()
		_match_id = ""
		_mode = "menu"
		_role = "none"
		_max_players = 1
		_participants = 1
		_revision = 0
		_fps_samples = 0.0
		_hardware = _get_hardware()
		_send(_payload(reason))
		session_id = ""
		_clicks.clear()
	var start := Time.get_ticks_msec()
	while not _queue.is_empty() and Time.get_ticks_msec() - start < int(timeout * 1000.0):
		_pump()
		await get_tree().process_frame


func _capture() -> void:
	if WorldSync.get_local_player() == null:
		return
	if not is_instance_valid(_stand):
		_stand = WorldSync.get_local_stand()
	if not is_instance_valid(_stand) or _stand.onboarding_progress.is_empty():
		return
	# GameState is only written on the host — clients must read the synced
	# StandUnit or every stat reports as frozen defaults.
	_last = _snapshot(_stand, _role == "host")
	if _role == "host":
		for node in get_tree().get_nodes_in_group("stand"):
			var stand := node as StandUnit
			if (
				stand == null or stand.process_mode == Node.PROCESS_MODE_DISABLED
				or stand.onboarding_progress.is_empty()
			):
				continue
			var key := str(stand.name)
			var latest := _snapshot(stand, true)
			if not _host_stands.has(key):
				_host_stands[key] = {
					"stand_id": key,
					"start": latest.duplicate(true),
					"milestones": { },
				}
			var record: Dictionary = _host_stands[key]
			record["latest"] = latest
			_update_milestones(record)
	if _start.is_empty() and _match_id != "":
		_start = _last.duplicate(true)
		_send(_payload("session_start"))


func _snapshot(stand: StandUnit, authoritative: bool) -> Dictionary:
	var p: Dictionary = stand.onboarding_progress
	var demo := "in progress"
	if p.get("skipped", false):
		demo = "skipped"
	elif p.get("completed", false) or p.get("current_task_id", "") == "demo_keep_running":
		demo = "completed"
	var result := {
		"stand_id": str(stand.name),
		"day": DayManager.day_number,
		"money": stand.money,
		"cups": stand.total_cups_sold,
		"revenue": stand.total_money_earned_from_sales,
		"spending": stand.total_money_spent,
		"demo": demo,
		"first_cup_filled": bool(p.get("first_cup_filled", false)),
		"discoveries": p.get("discovered_recipes", { }).keys(),
		"ice_discovered": p.get("discovered_ice_ratio", null) != null,
		"perfect_recipes": stand.perfect_recipes_set.keys(),
	}
	if authoritative:
		var outcomes := { }
		var snapshotted := int(stand.last_day_stats.get("day", -1)) == DayManager.day_number
		for key in OUTCOMES:
			outcomes[key] = int(stand.lifetime_stats.get(key, 0))
			if not snapshotted:
				outcomes[key] += int(stand.get("day_" + key))
		result["outcomes"] = outcomes
	return result


func _update_milestones(record: Dictionary) -> void:
	var base: Dictionary = record.start
	var latest: Dictionary = record.latest
	var times: Dictionary = record.milestones
	var elapsed := (Time.get_ticks_msec() - _session_start_msec) / 1000.0
	var reached := {
		"first_cup": not base.first_cup_filled and latest.first_cup_filled,
		"first_sale": latest.cups > base.cups,
		"recipe_discovered": latest.discoveries.size() > base.discoveries.size(),
		"demo_completed": base.demo != "completed" and latest.demo == "completed",
	}
	for key in reached:
		if reached[key] and not times.has(key):
			times[key] = elapsed


func _payload(reason: String) -> Dictionary:
	_revision += 1
	var event := "checkpoint" if reason in ["checkpoint", "day_end"] else "session_end"
	if reason == "session_start":
		event = "session_start"
	return {
		"schema_version": 2,
		"source": "game_v2",
		"revision": _revision,
		"started_utc": _started_utc,
		"observed_utc": Time.get_datetime_string_from_system(true) + "Z",
		"ended_utc": Time.get_datetime_string_from_system(true) + "Z" if event == "session_end" else null,
		"session_id": session_id,
		"match_id": _match_id,
		"event": event,
		"reason": reason,
		"mode": _mode,
		"role": _role,
		"players": _max_players,
		"participants": _participants,
		"build": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"steam_build": Steam.getAppBuildId() if NetworkManager.is_steam_initialized() else 0,
		"minutes": (Time.get_ticks_msec() - _session_start_msec) / 60000.0,
		"start": _start.duplicate(true),
		"end": _last.duplicate(true) if event == "session_end" else null,
		"latest": _last.duplicate(true),
		"stand_reports": _host_stands.values().duplicate(true) if _role == "host" else [],
		"clicks": _clicks.duplicate(true),
		"achievements": AchievementManager.get_unlocked_ids(),
		"avg_fps": _fps_sum / _fps_samples if _fps_samples > 0 else null,
		"low_fps_percent": 100.0 * _fps_low / _fps_samples if _fps_samples > 0 else null,
		"fps_sample_seconds": _fps_samples,
		"hardware": _hardware.duplicate(true),
	}


func _get_hardware() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.CONFIG_PATH)
	return {
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"ram_gb": float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": str(DisplayServer.window_get_size()),
		"renderer": RenderingServer.get_current_rendering_method(),
		"graphics_quality": cfg.get_value(
			"graphics",
			"graphics_quality",
			SettingsManager.DEFAULT_GRAPHICS_QUALITY,
		),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"fps_cap": Engine.max_fps,
	}


func _send(payload: Dictionary) -> void:
	if not _network_enabled():
		GameLog.log("[Analytics] %s (not sent in debug build)" % payload.event)
		return
	_queue[payload.session_id] = payload.duplicate(true)
	_save_queue()
	_pump()


func _save_queue() -> void:
	var file := FileAccess.open(QUEUE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		GameLog.log("[Analytics] could not persist pending reports")
		return
	file.store_string(JSON.stringify(_queue))
	file.close()
	var err := DirAccess.rename_absolute(QUEUE_PATH + ".tmp", QUEUE_PATH)
	if err != OK:
		GameLog.log("[Analytics] queue replacement failed: %d" % err)


func _pump() -> void:
	if (
		not _network_enabled() or is_instance_valid(_request)
		or _queue.is_empty() or Time.get_ticks_msec() < _retry_at
	):
		return
	var key: String = str(_queue.keys()[0])
	var payload: Dictionary = _queue[key]
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	_request.max_redirects = 0
	_following_redirect = false
	add_child(_request)
	_request.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			_response_received(key, int(payload.revision), result, code, headers, body),
	)
	var err := _request.request(
		ENDPOINT,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload),
	)
	if err != OK:
		_finish_request(key, int(payload.revision), false)


func _response_received(
	key: String,
	revision: int,
	result: int,
	code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if code in [301, 302, 303] and not _following_redirect:
		for header in headers:
			if not header.to_lower().begins_with("location:"):
				continue
			var location := header.substr(9).strip_edges()
			if location.begins_with("https://script.googleusercontent.com/"):
				_following_redirect = true
				if _request.request(location, [], HTTPClient.METHOD_GET) == OK:
					return
		_finish_request(key, revision, false)
		return
	var response: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		response = JSON.parse_string(body.get_string_from_utf8())
	var ok: bool = response is Dictionary and response.get("ok", false)
	_finish_request(key, revision, ok)


func _finish_request(key: String, revision: int, ok: bool) -> void:
	if ok:
		if _queue.has(key) and int(_queue[key].revision) == revision:
			_queue.erase(key)
		_retry_seconds = 1
		_save_queue()
	else:
		GameLog.log("[Analytics] submission failed; saved for retry")
		_retry_at = Time.get_ticks_msec() + _retry_seconds * 1000
		_retry_seconds = mini(_retry_seconds * 2, 60)
	_request.queue_free()
	_request = null
