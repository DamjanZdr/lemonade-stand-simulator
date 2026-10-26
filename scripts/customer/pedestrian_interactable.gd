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
	if p.held_item == HeldItem.CUP_FILLED:
		var recipe: Dictionary = p.held_item_data.get("recipe", { })
		ped.request_serve(peer_id, recipe)


func set_highlight(on: bool) -> void:
	_clear_highlight_outlines()
	if on:
		_apply_outline(get_parent(), true)


func get_hint(player: Node) -> String:
	var ped := get_parent() as Pedestrian
	if ped == null or not ped.can_interact():
		return ""
	# Named roster NPCs introduce themselves through the hint — the
	# bubble itself stays nameless.
	var who: String = ped.npc_display_name()
	var p := player as Player
	if p != null and p.held_item == HeldItem.CUP_FILLED:
		return "%s | LMB: serve lemonade" % who if who != "" \
				else "Pedestrian | LMB: serve lemonade"
	if who != "":
		return "%s | LMB: talk" % who
	return "Pedestrian | LMB: offer free lemonade"
