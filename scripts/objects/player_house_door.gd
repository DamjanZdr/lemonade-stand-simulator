extends Interactable
## Clickable door trigger. Triggers end-of-day when the timer has run out,
## and highlights the configured door mesh on hover.

@export var door_node: NodePath = NodePath("../door")

var _ready_to_end: bool = false


func _ready() -> void:
	EventBus.day_time_over.connect(_on_day_time_over)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func interact(_player: Node) -> void:
	if _ready_to_end:
		DayManager.trigger_end_day()


func get_hint(_player: Node) -> String:
	if _ready_to_end:
		return "Door | LMB: end day"
	return "Door | it's not 6 PM yet"


func set_highlight(on: bool) -> void:
	# Outline the configured door mesh, not this trigger area.
	var door := get_node_or_null(door_node)
	if door != null:
		_apply_outline(door, on)
	else:
		super.set_highlight(on)


func _on_day_time_over() -> void:
	_ready_to_end = true


func _on_day_phase_changed(_phase: int, _day: int) -> void:
	if _phase == DayManager.Phase.MORNING:
		_ready_to_end = false
