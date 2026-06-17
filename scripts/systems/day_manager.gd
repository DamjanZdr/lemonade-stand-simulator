extends Node
## Manages the day cycle: Morning (shop) → Day (serve) → Evening (summary)

enum Phase { MORNING, DAY, EVENING }

var current_phase: Phase = Phase.MORNING

var day_number: int = 1
var day_revenue: float = 0.0
var day_serves: int = 0
var day_happy_serves: int = 0
var day_start_money: float = 0.0

var _day_timer: float = 0.0
var _day_duration: float = 180.0 # 3 minutes default

var _day_running: bool = false


func _ready() -> void:
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.customer_served.connect(_on_customer_served)


func _process(delta: float) -> void:
	if not _day_running:
		return
	_day_timer -= delta
	if _day_timer <= 0.0:
		_end_day()
	EventBus.day_timer_updated.emit(_day_timer, _day_duration)


func start_morning() -> void:
	current_phase = Phase.MORNING
	# Randomize temperature for the day
	var temp := randf_range(Balancing.ICE_MIN_TEMP + 5.0, Balancing.ICE_MAX_TEMP - 5.0)
	GameState.temperature = temp
	EventBus.weather_changed.emit(temp)
	EventBus.day_phase_changed.emit(Phase.MORNING, day_number)


func start_day() -> void:
	current_phase = Phase.DAY
	day_start_money = GameState.money
	day_revenue = 0.0
	day_serves = 0
	day_happy_serves = 0
	_day_timer = _day_duration
	_day_running = true
	EventBus.day_phase_changed.emit(Phase.DAY, day_number)


func _end_day() -> void:
	_day_running = false
	current_phase = Phase.EVENING
	EventBus.day_phase_changed.emit(Phase.EVENING, day_number)


func end_evening() -> void:
	day_number += 1
	start_morning()


func _on_change_finalized(earned: float) -> void:
	if current_phase == Phase.DAY:
		day_revenue += earned


func _on_customer_served(_customer: Node, outcome: String) -> void:
	if current_phase != Phase.DAY:
		return
	day_serves += 1
	if outcome == "happy":
		day_happy_serves += 1
