extends Node
## Controls the real-world duration of an in-game workday.
##
## 9am to 6pm is 9 in-game hours. With the default 20 seconds per hour,
## the day lasts the same 180 real seconds as before, so the feel is preserved
## until you tune it.

@export var seconds_per_hour: float = 20.0
@export var day_start_hour: int = 9
@export var day_end_hour: int = 18


func _ready() -> void:
	_apply_to_day_manager()
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_apply_to_day_manager()


func _apply_to_day_manager() -> void:
	var hours := day_end_hour - day_start_hour
	if hours <= 0:
		push_warning("TimeManager: day_end_hour must be after day_start_hour.")
		return
	var total_seconds := seconds_per_hour * float(hours)
	DayManager.set_day_duration(total_seconds)
