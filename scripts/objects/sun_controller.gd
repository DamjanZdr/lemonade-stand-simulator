extends DirectionalLight3D
## Rotates the sun and adjusts its energy across the workday.

## Start of day sun rotation in degrees (x, y, z).
@export var start_rotation_deg: Vector3 = Vector3(-54.0, -172.0, 158.0)
## End of day sun rotation in degrees (x, y, z).
@export var end_rotation_deg: Vector3 = Vector3(-70.0, 42.0, -42.0)

## Light energy at the start of the day.
@export var energy_start: float = 1.1
## Peak light energy at midday.
@export var energy_mid: float = 1.05
## Light energy at the end of the day.
@export var energy_end: float = 0.2

var _current_t: float = 0.0
var _transition_tween: Tween = null


func _ready() -> void:
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_update_for_time(0.0)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := clampf(1.0 - (time_left / total_time), 0.0, 1.0)
	_update_for_time(t)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_tween_to_time(0.0, 0.6)
	elif phase == DayManager.Phase.EVENING:
		_update_for_time(1.0)


## Smoothly tweens the sun to the target time over the given duration.
func _tween_to_time(target_t: float, duration: float) -> void:
	if _transition_tween:
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween \
			.tween_method(
		func(t: float) -> void:
			_update_for_time(t),
		_current_t,
		target_t,
		duration,
	) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)


func _update_for_time(t: float) -> void:
	_current_t = t
	# t = 0 (start of day) → start rotation/energy
	# t = 0.5 (midday) → peak energy
	# t = 1 (end of day) → end rotation/energy
	var start_euler := Vector3(
		deg_to_rad(start_rotation_deg.x),
		deg_to_rad(start_rotation_deg.y),
		deg_to_rad(start_rotation_deg.z),
	)
	var end_euler := Vector3(
		deg_to_rad(end_rotation_deg.x),
		deg_to_rad(end_rotation_deg.y),
		deg_to_rad(end_rotation_deg.z),
	)
	var start_rot := Quaternion.from_euler(start_euler)
	var end_rot := Quaternion.from_euler(end_euler)
	rotation = start_rot.slerp(end_rot, t).get_euler()

	var target_energy: float
	if t < 0.5:
		target_energy = lerpf(energy_start, energy_mid, t * 2.0)
	else:
		target_energy = lerpf(energy_mid, energy_end, (t - 0.5) * 2.0)
	light_energy = target_energy
