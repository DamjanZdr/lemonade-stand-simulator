extends DirectionalLight3D
## Rotates the sun across the sky based on the in-game workday (6am → 6pm).

var _morning_rot := Vector3(deg_to_rad(-15.0), deg_to_rad(-60.0), 0.0)
var _noon_rot := Vector3(deg_to_rad(-90.0), 0.0, 0.0)
var _evening_rot := Vector3(deg_to_rad(-165.0), deg_to_rad(60.0), 0.0)

var _current_t: float = 0.0


func _ready() -> void:
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_rotation_for_time(0.0)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := clampf(1.0 - (time_left / total_time), 0.0, 1.0)
	_rotation_for_time(t)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_rotation_for_time(0.0)
	elif phase == DayManager.Phase.EVENING:
		_rotation_for_time(1.0)


func _rotation_for_time(t: float) -> void:
	# t = 0 (6am) → morning, t = 0.5 (noon) → overhead, t = 1 (6pm) → evening
	if t < 0.5:
		var local_t := t * 2.0
		rotation = _morning_rot.lerp(_noon_rot, local_t)
	else:
		var local_t := (t - 0.5) * 2.0
		rotation = _noon_rot.lerp(_evening_rot, local_t)
