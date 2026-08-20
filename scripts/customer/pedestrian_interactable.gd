class_name PedestrianInteractable
extends Interactable
## Child of a walking Pedestrian. Lets the player click them for a free lemonade offer.


func _ready() -> void:
	pass


func interact(player: Node) -> void:
	var ped := get_parent() as Pedestrian
	if ped == null:
		return
	var p := player as Player
	if p == null:
		return
	# Route through the host via RPC so the host processes the interaction
	# and syncs the state change to all clients
	var peer_id := int(p.name)
	if ped.can_interact():
		ped.request_offer(peer_id)
		return
	if p.held_item == p.HeldItem.CUP_FILLED:
		var recipe: Dictionary = p.held_item_data.get("recipe", { })
		ped.request_serve(peer_id, recipe)


func set_highlight(on: bool) -> void:
	_apply_outline(get_parent(), on)


func get_hint(player: Node) -> String:
	var ped := get_parent() as Pedestrian
	if ped == null or not ped.can_interact():
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Pedestrian | LMB: serve lemonade"
	return "Pedestrian | LMB: offer free lemonade"
