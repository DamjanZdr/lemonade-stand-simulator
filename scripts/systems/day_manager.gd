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


func _ready() -> void:
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.customer_served.connect(_on_customer_served)
	EventBus.customer_arrived.connect(_on_customer_arrived)
	EventBus.pedestrian_spawned.connect(_on_pedestrian_spawned)


func _process(delta: float) -> void:
	if not _day_running:
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
			_day_running = false
			EventBus.day_time_over.emit()
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)
	if multiplayer.get_peers().size() > 0:
		_sync_day_timer.rpc(_day_timer, _day_duration, day_time_over)


@rpc("authority", "call_local", "unreliable_ordered")
func _sync_day_timer(timer: float, duration: float, is_over: bool) -> void:
	if multiplayer.is_server():
		return
	_day_timer = timer
	_day_duration = duration
	day_time_over = is_over
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)


## Sync the current day phase and day number to all clients.
## Called whenever the host changes the phase (morning/day/evening).
func _sync_phase_to_clients() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().size() > 0:
		_sync_day_phase.rpc(current_phase, day_number)


@rpc("authority", "call_local", "reliable")
func _sync_day_phase(phase: int, day: int) -> void:
	if multiplayer.is_server():
		return
	current_phase = phase as Phase
	day_number = day
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
