class_name TrashManager
extends Node
## Configures the refund value for each type of trash.

@export var trash_values: Dictionary = {
	"apple": 1.0,
	"banana": 1.0,
	"can": 1.0,
	"cigarettes": 1.0,
	"cup": 1.0,
}


func _ready() -> void:
	add_to_group("trash_manager")


func get_value(trash_name: String) -> float:
	return float(trash_values.get(trash_name, 1.0))
