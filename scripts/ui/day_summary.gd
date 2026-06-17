extends CanvasLayer
## Evening transition: fade to black, then auto-advance to next morning.
## Day results are shown on the Morning Hub analytics tab instead.

@onready var panel: PanelContainer = $Panel
@onready var backdrop: ColorRect = $Backdrop


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		_fade_to_black()
	else:
		panel.visible = false
		backdrop.visible = false


func _fade_to_black() -> void:
	backdrop.visible = true
	backdrop.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 1.0)
	tween.tween_callback(
		func():
			DayManager.end_evening()
			tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 0), 0.5)
			tween.tween_callback(func(): backdrop.visible = false)
	)
