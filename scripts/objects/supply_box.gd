class_name SupplyBox
extends Interactable
## Runtime-spawned by DeliverySystem. Player picks it up and deposits into the matching bin,
## or — for equipment — places it like a container.

@export var ingredient_type: String = "lemon"
@export var quantity: float = 10.0
@export var is_equipment: bool = false
@export var equipment_type: String = ""

@onready var physics: StaticBody3D = $Physics
@onready var label: Label3D = $Label
@onready var collision_shape: CollisionShape3D = $Physics/CollisionShape3D

static var stack_height: float = 0.324663
static var bottom_offset: float = 0.16
static var stack_radius: float = 0.15
static var box_aabb: AABB = AABB(Vector3(-0.252, -0.16, -0.2), Vector3(0.504, 0.324663, 0.4))


func _ready() -> void:
	update_metrics()
	add_to_group("supply_box")
	_apply_tint()
	if is_equipment:
		label.text = equipment_type.capitalize().replace("_", " ") + "\nBox"
	else:
		label.text = "%s\n×%.0f" % [ingredient_type.capitalize(), quantity]


func interact(player: Node) -> void:
	var p: Player = player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return
	# Hide the box before freeing it so it doesn't flash for a frame.
	visible = false
	physics.collision_layer = 0

	if is_equipment:
		p.set_held(
			p.HeldItem.SUPPLY_BOX,
			{
				"source": "delivery",
				"is_equipment": true,
				"equipment_type": equipment_type,
			},
			_make_hand_mesh(),
		)
		_make_boxes_above_fall()
		queue_free()
		return

	p.set_held(
		p.HeldItem.SUPPLY_BOX,
		{
			"ingredient_type": ingredient_type,
			"amount": quantity,
			"source": "delivery",
		},
		_make_hand_mesh(),
	)
	_make_boxes_above_fall()
	queue_free()


func _make_boxes_above_fall() -> void:
	var my_pos := global_position
	var above: Array[SupplyBox] = []
	for node in get_tree().get_nodes_in_group("supply_box"):
		if node == self or not is_instance_valid(node):
			continue
		var box := node as SupplyBox
		if box == null:
			continue
		var dx := absf(box.global_position.x - my_pos.x)
		var dz := absf(box.global_position.z - my_pos.z)
		if dx < stack_radius and dz < stack_radius and box.global_position.y > my_pos.y:
			above.append(box)
	if above.is_empty():
		return
	# Sort by Y ascending so we animate from bottom to top
	above.sort_custom(
		func(a: SupplyBox, b: SupplyBox) -> bool:
			return a.global_position.y < b.global_position.y
	)
	for box in above:
		var target_y := box.global_position.y - stack_height
		var tween := box.create_tween()
		tween.tween_property(box, "global_position:y", target_y, 0.25) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func interact_secondary(player: Node) -> void:
	interact(player)


func get_hint(player: Node) -> String:
	var p: Player = player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return ""
	if is_equipment:
		return "Click: pick up %s box" % equipment_type.capitalize().replace("_", " ")
	if ingredient_type == "cups":
		return "Click: pick up cup box (x%d cups)" % quantity
	return "Click: pick up %s box (x%.0f)" % [ingredient_type.capitalize(), quantity]


func _apply_tint() -> void:
	pass # GLB uses its own materials


func update_metrics() -> void:
	var box_node := find_child("box", true, false) as Node3D
	if box_node == null:
		push_warning("SupplyBox: no 'box' child found for metrics")
		return

	var aabb_local := AABB()
	var first := true
	for mi in _collect_mesh_instances(box_node):
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var mesh_aabb: AABB = mi.mesh.get_aabb()
		var rel_xf := _get_relative_transform(mi, box_node)
		var min_c := Vector3(INF, INF, INF)
		var max_c := Vector3(-INF, -INF, -INF)
		for i in range(8):
			var corner := rel_xf * mesh_aabb.get_endpoint(i)
			min_c = min_c.min(corner)
			max_c = max_c.max(corner)
		var local_aabb := AABB(min_c, max_c - min_c)
		if first:
			aabb_local = local_aabb
			first = false
		else:
			aabb_local = aabb_local.merge(local_aabb)

	if first:
		return

	var min_c := Vector3(INF, INF, INF)
	var max_c := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var corner := box_node.transform * aabb_local.get_endpoint(i)
		min_c = min_c.min(corner)
		max_c = max_c.max(corner)
	box_aabb = AABB(min_c, max_c - min_c)
	bottom_offset = -box_aabb.position.y
	stack_height = box_aabb.size.y
	stack_radius = maxf(0.15, max(box_aabb.size.x, box_aabb.size.z) * 0.25)

	var collision_shape_node := get_node_or_null("Physics/CollisionShape3D") as CollisionShape3D
	if collision_shape_node != null and collision_shape_node.shape is BoxShape3D:
		var box_shape: BoxShape3D = collision_shape_node.shape as BoxShape3D
		box_shape.size = box_aabb.size
		collision_shape_node.position.y = box_aabb.position.y + box_aabb.size.y * 0.5


static func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children(true):
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		else:
			result.append_array(_collect_mesh_instances(child))
	return result


static func _get_relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != ancestor:
		xf = current.transform * xf
		current = current.get_parent() as Node3D
	return xf


func _tint_for_type(itype: String) -> Color:
	match itype:
		"lemon":
			return Color(1.0, 0.95, 0.1)
		"water":
			return Color(0.4, 0.7, 1.0)
		"sugar":
			return Color(0.98, 0.98, 0.98)
		"ice":
			return Color(0.7, 0.9, 1.0)
		"cups":
			return Color(0.95, 0.95, 0.95)
	return Color.WHITE


func _make_hand_mesh() -> Node3D:
	# Use boxnew.glb directly - scoop_box.tscn has parse errors
	var scene: PackedScene = load("res://blender/boxnew.glb") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	inst.scale = Vector3.ONE * 0.05
	var lbl: Label3D = inst.get_node_or_null("QuantityLabel") as Label3D
	if lbl:
		if is_equipment:
			lbl.text = equipment_type.capitalize().replace("_", " ") + "\nBox"
		else:
			lbl.text = "%s\n\u00d7%.0f" % [ingredient_type.capitalize(), quantity]
	return inst
