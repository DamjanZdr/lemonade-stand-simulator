class_name CounterSlot
extends Interactable
## Invisible slot on the counter. Click while holding sealed pitcher to place it for serving.

@export var is_counter_slot: bool = true  # false = prep slot (not currently used)


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	if p.held_item != p.HeldItem.PITCHER:
		return
	var pitcher: Pitcher = get_tree().get_first_node_in_group("pitcher") as Pitcher
	if pitcher == null:
		return
	if pitcher.get_liquid_volume() <= 0.0:
		EventBus.interaction_hint_changed.emit("Pitcher has no lemonade!")
		return
	pitcher.place_on_counter(global_position)
	p.clear_held()


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""
	if p.held_item == p.HeldItem.PITCHER:
		return "Click: place pitcher on counter"
	return ""
