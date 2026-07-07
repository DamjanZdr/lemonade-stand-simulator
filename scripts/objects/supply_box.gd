class_name SupplyBox
extends Interactable
## Runtime-spawned by DeliverySystem. Player picks it up and deposits into the matching bin,
## or — for equipment — places it like a container.

@export var ingredient_type: String = "lemon"
@export var quantity: float = 10.0
@export var is_equipment: bool = false
@export var equipment_type: String = ""

@onready var body_mesh: Node3D = $BodyMesh
@onready var physics: StaticBody3D = $Physics
@onready var label: Label3D = $Label

const STACK_HEIGHT: float = 0.262
const STACK_RADIUS: float = 0.15


func _ready() -> void:
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
	body_mesh.visible = false
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
		if dx < STACK_RADIUS and dz < STACK_RADIUS and box.global_position.y > my_pos.y:
			above.append(box)
	if above.is_empty():
		return
	# Sort by Y ascending so we animate from bottom to top
	above.sort_custom(
		func(a: SupplyBox, b: SupplyBox) -> bool:
			return a.global_position.y < b.global_position.y
	)
	for box in above:
		var target_y := box.global_position.y - STACK_HEIGHT
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
	# Use box.glb directly - scoop_box.tscn has parse errors
	var scene: PackedScene = load("res://blender/box.glb") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	inst.scale = Vector3.ONE * 0.05
	var lbl: Label3D = inst.get_node_or_null("QuantityLabel") as Label3D
	if lbl:
		if is_equipment:
			lbl.text = equipment_type.capitalize().replace("_", " ") + "\nBox"
		else:
			lbl.text = "%s\n\u00d7%.0f" % [ingredient_type.capitalize(), quantity]
	return inst
