extends Node
## Manages the day cycle: Morning (shop) → Day (serve) → Evening (summary)

enum Phase {
	MORNING,
	DAY,
	EVENING,
}

var current_phase: Phase = Phase.MORNING

var day_number: int = 1
var day_revenue: float = 0.0
var day_serves: int = 0
var day_happy_serves: int = 0
var day_start_money: float = 0.0
var day_pedestrians: int = 0
var day_customers_arrived: int = 0
var day_customers_bought: int = 0
var day_costs: float = 0.0

var _day_timer: float = 0.0
var _day_duration: float = 180.0 # 3 minutes default

var _day_running: bool = false
var day_time_over: bool = false

# Saved day-cycle state waiting to be restored on the next game start
# (set by SaveManager.apply_save_to_game_state). Empty when the next
# start should begin a fresh day.
var _pending_resume: Dictionary = { }

# Throttle day-timer sync so it isn't sent every frame.
var _last_synced_timer: float = -1.0
var _sync_interval_timer: float = 0.0
const TIMER_SYNC_INTERVAL: float = 0.5
const TIMER_SYNC_THRESHOLD: float = 0.1


func _ready() -> void:
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.customer_served.connect(_on_customer_served)
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.pedestrian_spawned.connect(_on_pedestrian_spawned)


func _process(delta: float) -> void:
	if not _day_running:
		return
	# No multiplayer peer yet — can't determine host/client.
	if not multiplayer.multiplayer_peer:
		return
	# Only the host advances the day timer. Clients receive the time
	# via RPC from the host (see _broadcast_day_timer below).
	if not multiplayer.is_server():
		return
	if not day_time_over:
		_day_timer -= delta
		if _day_timer <= 0.0:
			_day_timer = 0.0
			day_time_over = true
			EventBus.day_time_over.emit()
			# Reliable sync for the final day-over state: the regular timer
			# sync is unreliable_ordered and can be dropped, leaving joiners stuck
			# at ~5:59 with no interactable end-day sign.
			if multiplayer.get_peers().size() > 0:
				_sync_day_over.rpc()
			_day_running = false
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)
	# Throttle timer RPCs: only send when the timer has changed meaningfully,
	# the day-over flag changed, or a minimum interval elapsed.
	var should_sync_timer := false
	if _last_synced_timer < 0.0:
		should_sync_timer = true
	else:
		_sync_interval_timer += delta
		var timer_delta := absf(_last_synced_timer - _day_timer)
		if timer_delta >= TIMER_SYNC_THRESHOLD or _sync_interval_timer >= TIMER_SYNC_INTERVAL:
			should_sync_timer = true
	if should_sync_timer and multiplayer.get_peers().size() > 0:
		_last_synced_timer = _day_timer
		_sync_interval_timer = 0.0
		_sync_day_timer.rpc(_day_timer, _day_duration, day_time_over)


## Reliable final day-over sync for clients. The regular timer sync is
## unreliable_ordered and can drop the single packet that carries is_over=true.
@rpc("authority", "call_local", "reliable")
func _sync_day_over() -> void:
	if multiplayer.is_server():
		return
	# Snap the client timer to zero and emit the final update. The last
	# unreliable _sync_day_timer packet carrying 0.0 may be dropped, which
	# otherwise leaves the HUD clock frozen at ~5:59 even though the day
	# is over.
	_day_timer = 0.0
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)
	if not day_time_over:
		day_time_over = true
		EventBus.day_time_over.emit()


@rpc("authority", "call_local", "unreliable_ordered")
func _sync_day_timer(timer: float, duration: float, is_over: bool) -> void:
	if multiplayer.is_server():
		return
	_day_timer = timer
	_day_duration = duration
	# Emit day_time_over signal when the day ends for clients so the
	# end-day sign becomes interactable on clients too.
	# Never reset day_time_over back to false from a stale unreliable packet
	# after the reliable _sync_day_over has already fired.
	if is_over and not day_time_over:
		day_time_over = true
		EventBus.day_time_over.emit()
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)


## Sync the current day phase and day number to all clients.
## Called whenever the host changes the phase (morning/day/evening).
func _sync_phase_to_clients() -> void:
	if not multiplayer.multiplayer_peer:
		return
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().size() > 0:
		_sync_day_phase.rpc(current_phase, day_number)


## Sync the current day/phase to a specific peer (for late joiners).
## Sends one reliable packet with the full state — phase, day number,
## exact remaining time, and the day-over flag — so the joiner's sun,
## HUD clock, and end-day sign are correct immediately. Without the
## timer the joiner's sun stays at the scene-default morning position
## until the next unreliable _sync_day_timer broadcast — which never
## arrives once the day is over (_day_running is false).
func sync_day_state_to_peer(peer_id: int) -> void:
	if not multiplayer.multiplayer_peer:
		return
	if not multiplayer.is_server():
		return
	_sync_day_state.rpc_id(
		peer_id,
		current_phase,
		day_number,
		_day_timer,
		_day_duration,
		day_time_over,
	)


## Reliable full day-state snapshot for a late joiner. Emits both
## day_phase_changed and day_timer_updated so the sun controller and
## HUD clock snap to the host's exact time of day.
@rpc("authority", "call_local", "reliable")
func _sync_day_state(phase: int, day: int, timer: float, duration: float, is_over: bool) -> void:
	if multiplayer.is_server():
		return
	current_phase = phase as Phase
	day_number = day
	_day_timer = timer
	_day_duration = duration
	# Same flag rules as _sync_day_phase: a non-DAY phase clears the
	# carry-over flag; during DAY the host's authoritative flag wins.
	if phase != Phase.DAY:
		day_time_over = false
	elif is_over and not day_time_over:
		day_time_over = true
		EventBus.day_time_over.emit()
	EventBus.day_phase_changed.emit(current_phase, day_number)
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)


@rpc("authority", "call_local", "reliable")
func _sync_day_phase(phase: int, day: int) -> void:
	if multiplayer.is_server():
		return
	current_phase = phase as Phase
	day_number = day
	# Reset the day-over flag when a new day/night phase begins — the flag
	# is only cleared host-side, so without this a client keeps
	# day_time_over=true into the next day.
	if phase != Phase.DAY:
		day_time_over = false
	EventBus.day_phase_changed.emit(current_phase, day_number)


func start_morning() -> void:
	current_phase = Phase.MORNING
	day_start_money = GameState.money
	day_costs = 0.0
	# Randomize temperature for the day
	var temp := randf_range(Balancing.TEMP_MIN + 5.0, Balancing.TEMP_MAX - 5.0)
	GameState.temperature = temp
	EventBus.weather_changed.emit(temp)
	EventBus.day_phase_changed.emit(Phase.MORNING, day_number)
	_sync_phase_to_clients()


func start_day() -> void:
	current_phase = Phase.DAY
	day_revenue = 0.0
	day_serves = 0
	day_happy_serves = 0
	day_pedestrians = 0
	day_customers_arrived = 0
	day_customers_bought = 0
	_day_timer = _day_duration
	_day_running = true
	day_time_over = false
	EventBus.day_phase_changed.emit(Phase.DAY, day_number)
	_sync_phase_to_clients()


func trigger_end_day() -> void:
	if not day_time_over:
		return
	end_day()


func end_day() -> void:
	_day_running = false
	day_time_over = false
	day_costs = day_start_money - GameState.money + day_revenue
	current_phase = Phase.EVENING
	EventBus.day_phase_changed.emit(Phase.EVENING, day_number)
	_sync_phase_to_clients()


## Stop the day cycle and reset timer state. Called when returning to
## the main menu so the day cycle doesn't keep running (and adjusting
## lighting via _on_day_timer_updated) while the player is in the menu
## or lobby. Without this, the exposure/ambient from the previous
## game's day cycle persists and makes the lobby appear dark.
func stop_day_cycle() -> void:
	_day_running = false
	day_time_over = false
	_day_timer = 0.0
	# Leaving gameplay entirely: drop the phase to MORNING and notify
	# listeners. The world keeps ticking in the menu (WorldSync.is_host()
	# is true with no peer), so without this the phase stays DAY and the
	# pedestrian/customer spawners keep running, stacking NPCs while the
	# player sits in the main menu. The phase change triggers each
	# spawner's clear path, despawning the leftover NPCs.
	if current_phase != Phase.MORNING:
		current_phase = Phase.MORNING
		EventBus.day_phase_changed.emit(current_phase, day_number)


## Serialisable snapshot of the day cycle for SaveManager.
func get_save_state() -> Dictionary:
	return {
		"day_number": day_number,
		"phase": int(current_phase),
		"day_timer": _day_timer,
		"day_duration": _day_duration,
		"day_time_over": day_time_over,
		"day_revenue": day_revenue,
		"day_serves": day_serves,
		"day_happy_serves": day_happy_serves,
		"day_start_money": day_start_money,
		"day_pedestrians": day_pedestrians,
		"day_customers_arrived": day_customers_arrived,
		"day_customers_bought": day_customers_bought,
		"day_costs": day_costs,
	}


## Stash saved day-cycle state so the next game start resumes where the
## save left off instead of restarting at 9 AM. day_number is applied
## immediately because the "Day X" transition reads it before the world
## is ready for resume_from_save().
func store_pending_resume(data: Dictionary) -> void:
	_pending_resume = data.duplicate()
	day_number = int(data.get("day_number", day_number))


func clear_pending_resume() -> void:
	_pending_resume = { }


func has_pending_resume() -> bool:
	return not _pending_resume.is_empty()


## Restore the day cycle captured by get_save_state(). Emits the same
## signals a normal phase change would so the HUD clock, shop overlay,
## end-day sign, day summary, and spawners all re-arm for the restored
## phase.
func resume_from_save() -> void:
	var data := _pending_resume
	_pending_resume = { }
	current_phase = int(data.get("phase", Phase.DAY)) as Phase
	if current_phase == Phase.MORNING:
		# MORNING is a transient prep phase with no resumable progress —
		# this also covers new-game saves, whose default day_state is
		# MORNING. Start the day exactly as a fresh game would.
		start_morning()
		start_day()
		return
	day_revenue = float(data.get("day_revenue", 0.0))
	day_serves = int(data.get("day_serves", 0))
	day_happy_serves = int(data.get("day_happy_serves", 0))
	day_start_money = float(data.get("day_start_money", GameState.money))
	day_pedestrians = int(data.get("day_pedestrians", 0))
	day_customers_arrived = int(data.get("day_customers_arrived", 0))
	day_customers_bought = int(data.get("day_customers_bought", 0))
	day_costs = float(data.get("day_costs", 0.0))
	day_time_over = bool(data.get("day_time_over", false))
	_day_duration = float(data.get("day_duration", _day_duration))
	_day_timer = clampf(float(data.get("day_timer", _day_duration)), 0.0, _day_duration)
	# The clock only runs while DAY is in progress and 6 PM hasn't hit.
	_day_running = current_phase == Phase.DAY and not day_time_over
	# Force the next _process tick to push the timer to clients
	# immediately instead of waiting for the threshold.
	_last_synced_timer = -1.0
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)
	EventBus.day_phase_changed.emit(current_phase, day_number)
	_sync_phase_to_clients()
	if day_time_over:
		EventBus.day_time_over.emit()
		if multiplayer.multiplayer_peer and multiplayer.get_peers().size() > 0:
			_sync_day_over.rpc()


## Reset the whole day cycle to a fresh Day 1 morning. Called when a new
## game starts so a previous session's phase/timer/stats can't leak into
## the new save's day_state.
func reset_cycle() -> void:
	stop_day_cycle()
	_pending_resume = { }
	current_phase = Phase.MORNING
	day_number = 1
	day_revenue = 0.0
	day_serves = 0
	day_happy_serves = 0
	day_start_money = 0.0
	day_pedestrians = 0
	day_customers_arrived = 0
	day_customers_bought = 0
	day_costs = 0.0


func end_evening() -> void:
	day_number += 1
	start_morning()


func set_day_duration(duration: float) -> void:
	_day_duration = maxf(0.0, duration)


func get_day_duration() -> float:
	return _day_duration


func _on_change_finalized(earned: float) -> void:
	if current_phase == Phase.DAY:
		day_revenue += earned


func _on_customer_served(_customer: Node, outcome: String) -> void:
	if current_phase != Phase.DAY:
		return
	day_serves += 1
	if outcome == "happy":
		day_happy_serves += 1
	if outcome != "timeout":
		day_customers_bought += 1


func _on_customer_arrived(_customer: Node) -> void:
	if current_phase == Phase.DAY:
		day_customers_arrived += 1


func _on_pedestrian_spawned(_pedestrian: Node) -> void:
	if current_phase == Phase.DAY:
		day_pedestrians += 1
