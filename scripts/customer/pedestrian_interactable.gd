class_name PedestrianInteractable
extends Interactable
## Child of a walking Pedestrian. Lets the player click them for a free lemonade offer.

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
	var ped := get_parent() as Pedestrian
	if ped != null:
		ped.call_deferred("add_child", _ring)
		_ring.position = Vector3(0, 0.1, 0)


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
	if _ring != null:
		_ring.visible = on
		if on:
			_ring.add_to_group("outline_fill")
		else:
			_ring.remove_from_group("outline_fill")


func get_hint(player: Node) -> String:
	var ped := get_parent() as Pedestrian
	if ped == null or not ped.can_interact():
		return ""
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.CUP_FILLED:
		return "Click: serve lemonade"
	return "Click: offer free lemonade"
