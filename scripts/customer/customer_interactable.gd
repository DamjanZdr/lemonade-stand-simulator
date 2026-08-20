class_name CustomerInteractable
extends Interactable
## Child of the Customer node. Routes interact() calls up to the parent Customer.


func _ready() -> void:
	pass


func interact(player: Node) -> void:
	var customer := get_parent() as Customer
	if customer == null:
		return
	var p := player as Player
	if p == null:
		return
	# Route through the host via RPC so the host processes the interaction
	# and syncs the state change to all clients
	var peer_id := int(p.name)
	if p.held_item == p.HeldItem.CUP_FILLED:
		var recipe: Dictionary = p.held_item_data.get("recipe", { })
		customer.request_serve(peer_id, recipe)
	else:
		customer.request_show_order(peer_id)


func set_highlight(on: bool) -> void:
	_apply_outline(get_parent(), on)


func get_hint(player: Node) -> String:
	var customer := get_parent() as Customer
	if customer == null or customer.state != Customer.CustomerState.WAITING:
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Customer | LMB: serve lemonade"
	return ""
