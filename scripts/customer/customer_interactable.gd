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
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		customer.try_serve(player)
	else:
		customer.show_order_to_player(player)


func set_highlight(on: bool) -> void:
	_apply_outline(get_parent(), on)


func get_hint(player: Node) -> String:
	var customer := get_parent() as Customer
	if customer == null or customer.state != Customer.CustomerState.WAITING:
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Click: serve lemonade"
	return ""
