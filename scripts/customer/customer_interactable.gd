class_name CustomerInteractable
extends Interactable
## Child of the Customer node. Routes interact() calls up to the parent Customer.

var _ring: MeshInstance3D = null


func _ready() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "_HighlightRing"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = 0.1
	_ring.mesh = mesh
	_ring.material_override = _get_fill_mat()
	_ring.layers = 2
	_ring.visible = false
	var customer := get_parent() as Customer
	if customer != null:
		customer.call_deferred("add_child", _ring)
		_ring.position = Vector3(0, 0.1, 0)


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
	if _ring != null:
		_ring.visible = on
		if on:
			_ring.add_to_group("outline_fill")
		else:
			_ring.remove_from_group("outline_fill")


func get_hint(player: Node) -> String:
	var customer := get_parent() as Customer
	if customer == null or customer.state != Customer.CustomerState.WAITING:
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Click: serve lemonade"
	return ""
