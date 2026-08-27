class_name Workstation
extends Interactable
## A placeable/movable table surface that other equipment can sit on.


func _ready() -> void:
	add_to_group("container")
	Pickupable.setup_for_container(self, "workstation")


func get_hint(_player: Node) -> String:
	return "Table"
