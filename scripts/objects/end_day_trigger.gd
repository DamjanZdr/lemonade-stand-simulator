class_name EndDayTrigger
extends Interactable

@onready var _mesh: MeshInstance3D = $Sign/Panel
@onready var _mat: StandardMaterial3D = _mesh.material_override

var _ready_to_end: bool = false


func _ready() -> void:
	EventBus.day_time_over.connect(_on_day_time_over)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_mat.emission_energy_multiplier = 0.0


func interact(_player: Node) -> void:
	if _ready_to_end:
		DayManager.trigger_end_day()


func get_hint(_player: Node) -> String:
	if _ready_to_end:
		return "LMB: End day"
	return "It's not 6 PM yet"


func _on_day_time_over() -> void:
	_ready_to_end = true
	_mat.emission_energy_multiplier = 1.5


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_ready_to_end = false
		_mat.emission_energy_multiplier = 0.0
