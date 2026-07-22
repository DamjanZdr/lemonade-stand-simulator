class_name PedestrianInteractable
extends Interactable
## Child of a walking Pedestrian. Lets the player click them for a free lemonade offer.


func interact(player: Node) -> void:
	var ped := get_parent() as Pedestrian
	if ped == null:
		return
	# First click always starts the offer, regardless of what the player is holding.
	if ped.can_interact():
		ped.offer_free_lemonade(player)
		return
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		ped.try_serve(player)


func set_highlight(on: bool) -> void:
	var ped := get_parent() as Pedestrian
	if ped != null:
		_apply_outline(ped, on)


func get_hint(player: Node) -> String:
	var ped := get_parent() as Pedestrian
	if ped == null or not ped.can_interact():
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Click: serve lemonade"
	return "Click: offer free lemonade"
