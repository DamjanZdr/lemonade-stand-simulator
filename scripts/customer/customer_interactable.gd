class_name CustomerInteractable
extends Interactable
## Child of the Customer node. Routes interact() calls up to the parent Customer.


func interact(player: Node) -> void:
	var customer := get_parent() as Customer
	if customer:
		customer.try_serve(player)


func get_hint(player: Node) -> String:
	var customer := get_parent() as Customer
	if customer == null:
		return ""
	if customer.state != Customer.CustomerState.WAITING:
		return ""
	var p := player as Player
	if p == null:
		return ""
	if p.held_item == p.HeldItem.CUP_FILLED:
		return "Click: serve lemonade"
	return "Customer waiting…"
