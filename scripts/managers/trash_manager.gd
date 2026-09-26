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
	EventBus.day_time_over.connect(_on_day_time_over)


func get_value(trash_name: String) -> float:
	return float(trash_values.get(trash_name, 1.0))


func _on_day_time_over() -> void:
	if not WorldSync.is_host():
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var trash_count := tree.get_nodes_in_group("trash_item").size()
	if trash_count <= 0:
		return
	var delta := -Balancing.POPULARITY_TRASH_LEFT_PENALTY * float(trash_count)
	for s in tree.current_scene.find_children("*", "StandUnit", true, false):
		if s.has_method("set_popularity"):
			s.set_popularity(s.popularity + delta)
	GameState.set_popularity(GameState.popularity + delta)
	GameLog.log(
		"[TrashManager] Day ended with %d litter on the street; popularity %d"
		% [trash_count, delta]
	)
