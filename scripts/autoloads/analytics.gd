extends Node
## Anonymous demo telemetry: session rows (start/checkpoint/end) plus
## host-side learning details (tutorial steps, pitcher batches) posted to
## the project's Google Apps Script endpoint and upserted into Sheets.
## No personal data — random session/match ids only, no Steam id or username.
## Release builds only; debug/editor sessions log locally instead.
const ENDPOINT := "https://script.google.com/macros/s/AKfycbxtVYc6S93vYoEMQh1Izr5mJxrh8K8TvPHEF2RPDRd2jHH8dExShn7LXhQ-Ew0mgoiL/exec"
const CHECKPOINT_SECONDS := 30.0
const CHANGE_FLUSH_SECONDS := 5.0
const QUIT_FLUSH_SECONDS := 2.0
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
var _change_clock := 0.0
var _critical_dirty := false
var _members: Dictionary = { }
var _host_stands: Dictionary = { }
var _queue: Dictionary = { }
var _request: HTTPRequest
var _following_redirect := false
var _retry_at := 0
var _retry_seconds := 1
var _hardware: Dictionary = { }
var _tutorial_rows: Dictionary = { }
var _tutorial_current: Dictionary = { }
var _tutorial_attempts: Dictionary = { }
var _activity: Dictionary = { }
var _batch_rows: Dictionary = { }
var _batch_aliases: Dictionary = { }
var _batch_numbers: Dictionary = { }
var _batch_people: Dictionary = { }
var _learning_dirty: Dictionary = { }
var _inflight: Dictionary = { }
var _inline_keys: Array[String] = []


func _ready() -> void:
	# Window-close is handled manually in main.gd so the quit summary
	# gets a bounded window to flush before the process exits.
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_disconnected.connect(_peer_left)
	EventBus.day_phase_changed.connect(_phase_changed)
	OnboardingManager.stand_progress_changed.connect(_tutorial_progress)


func _network_enabled() -> bool:
	return OS.has_feature("release") and not OS.is_debug_build()


func _process(delta: float) -> void:
	_pump()
	if session_id == "" or _ending:
		return
	var player := WorldSync.get_local_player()
	var active := (
		player != null and not EventBus.esc_menu_open
		and not EventBus.day_transition_active and not get_tree().paused
	)
	if _role == "host":
		_activity[multiplayer.get_unique_id()] = {
			"stand": (
				str(player.assigned_stand.name)
				if player != null and is_instance_valid(player.assigned_stand)
				else ""
			),
			"active": active,
			"seen": Time.get_ticks_msec(),
		}
		_tick_tutorials(delta)
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
		if _role == "client" and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(
				1
			):
			_report_activity.rpc_id(1, active)
		if _match_id == "" and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(1):
			_request_match.rpc_id(1, session_id)
		_capture()
	if _critical_dirty:
		_change_clock += delta
	if (
		not _start.is_empty() and _match_id != ""
		and (
			_checkpoint_clock >= CHECKPOINT_SECONDS
			or (_critical_dirty and _change_clock >= CHANGE_FLUSH_SECONDS)
		)
	):
		_checkpoint_clock = 0.0
		_send(_payload("checkpoint"))
		_flush_learning()


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
	_change_clock = 0.0
	_critical_dirty = false
	_start = { }
	_last = { }
	_stand = null
	_members.clear()
	_host_stands.clear()
	_tutorial_rows.clear()
	_tutorial_current.clear()
	_tutorial_attempts.clear()
	_activity.clear()
	_batch_rows.clear()
	_batch_aliases.clear()
	_batch_numbers.clear()
	_batch_people.clear()
	_learning_dirty.clear()
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
		_activity.erase(peer)


func _phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING and session_id != "" and not _ending:
		_capture()
		if not _start.is_empty() and _match_id != "":
			_send(_payload("day_end"))
			_flush_learning()


## Count a button click worth reporting (wishlist / discord / bug report).
func track(event: String) -> void:
	_clicks[event] = int(_clicks.get(event, 0)) + 1


## Session ended without quitting (exit to menu / disconnect). Sends the
## summary then clears the id so a later quit doesn't double-report.
func end_session(reason: String) -> void:
	if session_id == "" or _ending:
		return
	_capture()
	_close_tutorials()
	_ending = true
	if reason == "quit":
		_cancel_inflight()
	_send(_payload(reason))
	_flush_learning()
	session_id = ""
	_clicks.clear()


## Bounded send for the quit path — caller awaits then quits.
func send_and_wait(reason: String, timeout := QUIT_FLUSH_SECONDS) -> void:
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
			_sync_tutorial(stand)
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


func _learning_enabled() -> bool:
	return session_id != "" and _role == "host" and not _ending and _match_id != ""


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0


@rpc("any_peer", "call_remote", "unreliable")
func _report_activity(active: bool) -> void:
	if not _learning_enabled() or not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _members.has(peer) or get_tree().current_scene == null:
		return
	var player := get_tree().current_scene.get_node_or_null("Players/" + str(peer))
	if player == null or not is_instance_valid(player.assigned_stand):
		return
	_activity[peer] = {
		"stand": str(player.assigned_stand.name),
		"active": active,
		"seen": Time.get_ticks_msec(),
	}


func _tutorial_progress(stand: StandUnit, _progress: Dictionary) -> void:
	if _learning_enabled() and _host_stands.has(str(stand.name)):
		_sync_tutorial(stand)


func _ensure_tutorial(stand: StandUnit, task_id: String) -> Dictionary:
	var key := str(stand.name)
	if _tutorial_current.has(key):
		var current: Dictionary = _tutorial_rows[_tutorial_current[key]]
		if current.task_id == task_id:
			return current
		current["status"] = "interrupted"
		current["elapsed_seconds"] = _elapsed() - float(current.started_seconds)
		_mark_learning("tutorial", current)
	var order := OnboardingManager._task_index(task_id)
	if order < 0 or task_id == "demo_keep_running":
		return { }
	var attempt_key := key + ":" + task_id
	var attempt := int(_tutorial_attempts.get(attempt_key, 0)) + 1
	_tutorial_attempts[attempt_key] = attempt
	var id := key + ":" + task_id + ":" + str(attempt)
	var first_observed := not _tutorial_rows.values().any(
		func(row: Dictionary) -> bool:
			return row.stand_id == key,
	)
	var row := {
		"id": id,
		"stand_id": key,
		"task_id": task_id,
		"step_order": order + 1,
		"name": str(OnboardingManager.TASKS[order].text).replace("{", "").replace("}", ""),
		"status": "active",
		"started_seconds": _elapsed(),
		"completed_seconds": null,
		"elapsed_seconds": 0.0,
		"active_seconds": 0.0,
		"automatic": false,
		"resumed": first_observed
		and not stand.onboarding_progress.get("completed_task_ids", []).is_empty(),
	}
	_tutorial_rows[id] = row
	_tutorial_current[key] = id
	_mark_learning("tutorial", row)
	return row


func _observed_stand(stand: StandUnit) -> bool:
	if _tutorial_current.has(str(stand.name)):
		return true
	for player in get_tree().get_nodes_in_group("player"):
		if _members.has(player.get_multiplayer_authority()) and player.assigned_stand == stand:
			return true
	return _activity.values().any(
		func(entry: Dictionary) -> bool:
			return entry.stand == str(stand.name) and Time.get_ticks_msec() - int(entry.seen) < 3000,
	)


func _sync_tutorial(stand: StandUnit) -> void:
	if not _learning_enabled() or not _observed_stand(stand):
		return
	var key := str(stand.name)
	var p: Dictionary = stand.onboarding_progress
	if (
		p.get("skipped", false) or p.get("completed", false)
		or p.get("current_task_id", "") == "demo_keep_running"
	):
		if _tutorial_current.has(key):
			var row: Dictionary = _tutorial_rows[_tutorial_current[key]]
			row["status"] = "skipped" if p.get("skipped", false) else "interrupted"
			row["elapsed_seconds"] = _elapsed() - float(row.started_seconds)
			_mark_learning("tutorial", row)
			_tutorial_current.erase(key)
		return
	_ensure_tutorial(stand, str(p.get("current_task_id", "")))


func tutorial_completed(stand: StandUnit, task_id: String, automatic: bool = false) -> void:
	if not _learning_enabled() or stand == null or not _observed_stand(stand):
		return
	var row := _ensure_tutorial(stand, task_id)
	if row.is_empty():
		return
	row["status"] = "completed"
	row["completed_seconds"] = _elapsed()
	row["elapsed_seconds"] = _elapsed() - float(row.started_seconds)
	row["automatic"] = automatic
	_mark_learning("tutorial", row)
	_tutorial_current.erase(str(stand.name))


func _tick_tutorials(delta: float) -> void:
	for id in _tutorial_current.values():
		var row: Dictionary = _tutorial_rows[id]
		row["elapsed_seconds"] = _elapsed() - float(row.started_seconds)
		_mark_learning("tutorial", row)
		var stand := OnboardingManager.find_stand(row.stand_id)
		if stand == null or stand.onboarding_progress.get("day_end_active", false) or get_tree().paused:
			continue
		var active := _activity.values().any(
			func(entry: Dictionary) -> bool:
				return (
					entry.stand == row.stand_id and entry.active
					and Time.get_ticks_msec() - int(entry.seen) < 3000
				),
		)
		if active:
			row["active_seconds"] = minf(
				float(row.elapsed_seconds),
				float(row.active_seconds) + delta,
			)


func _close_tutorials() -> void:
	for id in _tutorial_current.values():
		var row: Dictionary = _tutorial_rows[id]
		row["status"] = "left_on_step"
		row["elapsed_seconds"] = _elapsed() - float(row.started_seconds)
		_mark_learning("tutorial", row)
	_tutorial_current.clear()


func record_pour(stand: StandUnit, recipe: Dictionary, continued: bool = false) -> void:
	if not _learning_enabled() or stand == null:
		return
	var row := _ensure_batch(stand, recipe, continued)
	recipe["_analytics_batch"] = row.id
	row["cups_poured"] = int(row.cups_poured) + 1
	recipe["_analytics_cup"] = str(row.id) + ":" + str(row.cups_poured)
	_mark_learning("batch", row)


func _ensure_batch(stand: StandUnit, recipe: Dictionary, carried: bool) -> Dictionary:
	var incoming := str(recipe.get("_analytics_batch", ""))
	if _batch_rows.has(incoming):
		return _batch_rows[incoming]
	if _batch_aliases.has(incoming) and incoming != "":
		return _batch_rows[_batch_aliases[incoming]]
	var key := str(stand.name)
	_batch_numbers[key] = int(_batch_numbers.get(key, 0)) + 1
	var fruit := str(recipe.get("fruit_type", "unknown"))
	var fruit_key := key + ":" + fruit
	_batch_numbers[fruit_key] = int(_batch_numbers.get(fruit_key, 0)) + 1
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var row := {
		"id": id,
		"stand_id": key,
		"batch_number": _batch_numbers[key],
		"fruit_batch_number": _batch_numbers[fruit_key],
		"fruit": fruit,
		"fruit_count": float(recipe.get("fruit_count", 0)),
		"water": float(recipe.get("water", 0)),
		"sugar": float(recipe.get("sugar", 0)),
		"ice": float(recipe.get("ice", 0)),
		"started_seconds": _elapsed(),
		"day": DayManager.day_number,
		"carried_in": carried,
		"recipe_known": stand.onboarding_progress.get("discovered_recipes", { }).has(fruit),
		"temperature_min": null,
		"temperature_max": null,
		"cups_poured": 0,
		"paid_cups": 0,
		"sample_cups": 0,
		"paid_people": 0,
		"paid_happy": 0,
		"paid_unhappy": 0,
		"sample_people": 0,
		"sample_happy": 0,
		"sample_unhappy": 0,
		"paid_reasons": { },
		"sample_reasons": { },
		"paid_axes": { },
		"sample_axes": { },
	}
	_batch_rows[id] = row
	_batch_people[id] = { }
	if incoming != "":
		_batch_aliases[incoming] = id
	_mark_learning("batch", row)
	return row


func record_batch_feedback(
	stand: StandUnit,
	recipe: Dictionary,
	complaints: Array,
	sample: bool,
	person: int,
) -> void:
	if not _learning_enabled() or stand == null:
		return
	var row := _ensure_batch(stand, recipe, true)
	var prefix := "sample" if sample else "paid"
	var people: Dictionary = _batch_people[row.id]
	var person_key := prefix + ":" + str(person)
	if not people.has(person_key):
		people[person_key] = { "reasons": [], "cups": [], "axes": [] }
		row[prefix + "_people"] = int(row[prefix + "_people"]) + 1
		row[prefix + "_happy"] = int(row[prefix + "_happy"]) + 1
	var entry: Dictionary = people[person_key]
	var cup := str(recipe.get("_analytics_cup", ""))
	if cup != "" and entry.cups.has(cup):
		return
	entry.cups.append(cup)
	row[prefix + "_cups"] = int(row[prefix + "_cups"]) + 1
	if entry.reasons.is_empty() and not complaints.is_empty():
		row[prefix + "_happy"] = int(row[prefix + "_happy"]) - 1
		row[prefix + "_unhappy"] = int(row[prefix + "_unhappy"]) + 1
	var reasons: Dictionary = row[prefix + "_reasons"]
	for complaint in complaints:
		if not entry.reasons.has(complaint):
			entry.reasons.append(complaint)
			reasons[complaint] = int(reasons.get(complaint, 0)) + 1
		var axis := ""
		if complaint in ["too_strong", "not_enough_fruit"]:
			axis = "fruit"
		elif complaint in ["too_sweet", "not_sweet_enough"]:
			axis = "sugar"
		elif complaint in ["too_cold", "not_cold_enough"]:
			axis = "ice"
		if axis != "" and not entry.axes.has(axis):
			entry.axes.append(axis)
			var axes: Dictionary = row[prefix + "_axes"]
			axes[axis] = int(axes.get(axis, 0)) + 1
	var temperature := GameState.temperature
	row["temperature_min"] = (
		temperature
		if row.temperature_min == null
		else minf(float(row.temperature_min), temperature)
	)
	row["temperature_max"] = (
		temperature
		if row.temperature_max == null
		else maxf(float(row.temperature_max), temperature)
	)
	_mark_learning("batch", row)


func _mark_learning(kind: String, row: Dictionary) -> void:
	_learning_dirty[kind + ":" + str(row.id)] = { "kind": kind, "record": row }
	if kind == "batch" or row.get("status", "active") != "active":
		if not _critical_dirty:
			_change_clock = 0.0
		_critical_dirty = true


func _learning_message(key: String) -> Dictionary:
	var detail: Dictionary = _learning_dirty[key]
	_revision += 1
	var row: Dictionary = detail.record.duplicate(true)
	row["revision"] = _revision
	return {
		"schema_version": 2,
		"event": "learning",
		"steam_build": Steam.getAppBuildId() if NetworkManager.is_steam_initialized() else 0,
		"session_id": session_id,
		"match_id": _match_id,
		"role": "host",
		"revision": _revision,
		"kind": detail.kind,
		"record": row,
		"queue_key": session_id + "|" + key,
	}


func _inline_learning() -> Array:
	var records := []
	if _role != "host":
		return records
	var keys := _learning_dirty.keys()
	keys.sort_custom(
		func(a: String, b: String) -> bool:
			var first: Dictionary = _learning_dirty[a]
			var second: Dictionary = _learning_dirty[b]
			var first_priority := (
				0
				if first.record.get("status", "") == "left_on_step"
				else (1 if first.kind == "batch" else 2)
			)
			var second_priority := (
				0
				if second.record.get("status", "") == "left_on_step"
				else (1 if second.kind == "batch" else 2)
			)
			return first_priority < second_priority,
	)
	for key in keys:
		var message := _learning_message(key)
		records.append({ "kind": message.kind, "record": message.record })
		if _network_enabled():
			_queue[message.queue_key] = message
		_learning_dirty.erase(key)
		if records.size() >= 10:
			break
	return records


func _flush_learning() -> void:
	if _role != "host":
		return
	for key in _learning_dirty:
		_send(_learning_message(key))
	_learning_dirty.clear()
	_critical_dirty = false
	_change_clock = 0.0


func _payload(reason: String) -> Dictionary:
	_revision += 1
	var event := "checkpoint" if reason in ["checkpoint", "day_end"] else "session_end"
	if reason == "session_start":
		event = "session_start"
	var records := _inline_learning()
	return {
		"schema_version": 2,
		"learning_schema": 1,
		"source": "game_v2",
		"records": records,
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


func _cancel_inflight() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
		_request = null
	_inflight.clear()
	_retry_at = 0


func _send(payload: Dictionary) -> void:
	if not _network_enabled():
		GameLog.log("[Analytics] %s (not sent in debug build)" % payload.event)
		return
	_queue[str(payload.get("queue_key", payload.session_id))] = payload.duplicate(true)
	_pump()


func _prepare_message() -> Dictionary:
	var key: String = str(_queue.keys()[0])
	for candidate in _queue:
		if _queue[candidate].get("event", "") != "learning":
			key = str(candidate)
			break
	var payload: Dictionary = _queue[key].duplicate(true)
	_inflight = { key: int(payload.revision) }
	_inline_keys.clear()
	for detail in payload.get("records", []):
		var detail_key := str(payload.session_id) + "|" + str(detail.kind) + ":" + str(
			detail.record.id
		)
		if _queue.has(detail_key):
			_inflight[detail_key] = int(detail.record.revision)
			_inline_keys.append(detail_key)
	if payload.get("event", "") == "learning":
		payload["records"] = []
		_inflight.clear()
		for candidate in _queue:
			var detail: Dictionary = _queue[candidate]
			if detail.get("event", "") != "learning" or detail.match_id != payload.match_id:
				continue
			payload.records.append({ "kind": detail.kind, "record": detail.record })
			_inflight[candidate] = int(detail.revision)
			if payload.records.size() >= 10:
				break
		payload.erase("record")
	return { "key": key, "payload": payload }


func _pump() -> void:
	if (
		not _network_enabled() or is_instance_valid(_request)
		or _queue.is_empty() or Time.get_ticks_msec() < _retry_at
	):
		return
	var message := _prepare_message()
	var key: String = message.key
	var payload: Dictionary = message.payload
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.timeout = 10.0
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
	if ok and not response.get("records_accepted", false):
		for detail_key in _inline_keys:
			_inflight.erase(detail_key)
	_finish_request(key, revision, ok)


func _finish_request(key: String, revision: int, ok: bool) -> void:
	if ok:
		if _inflight.is_empty():
			_inflight[key] = revision
		for sent_key in _inflight:
			if _queue.has(sent_key) and int(_queue[sent_key].revision) == int(_inflight[sent_key]):
				_queue.erase(sent_key)
		_retry_seconds = 1
	else:
		GameLog.log("[Analytics] submission failed; will retry during this launch")
		_retry_at = Time.get_ticks_msec() + _retry_seconds * 1000
		_retry_seconds = mini(_retry_seconds * 2, 60)
	_inflight.clear()
	_request.queue_free()
	_request = null
