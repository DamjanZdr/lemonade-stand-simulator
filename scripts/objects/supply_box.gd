class_name SupplyBox
extends Interactable
## Runtime-spawned by DeliverySystem. Player picks it up and deposits into the matching bin.

@export var ingredient_type: String = "lemon"
@export var quantity: float = 10.0

@onready var body_mesh: Node3D = $BodyMesh
@onready var physics: StaticBody3D = $Physics
@onready var label: Label3D = $Label


func _ready() -> void:
	_apply_tint()
	label.text = "%s\n×%.0f" % [ingredient_type.capitalize(), quantity]


func interact(player: Node) -> void:
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return
	body_mesh.visible = false
	physics.collision_layer = 0
	p.set_held(p.HeldItem.SUPPLY_BOX, {
		"ingredient_type": ingredient_type,
		"amount": quantity,
		"source": "delivery"
	}, _make_hand_mesh())
	queue_free()


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return ""
	if ingredient_type == "cups":
		return "Click: pick up cup box (LMB on surface=place stack, on stack=add cups)"
	return "Click: pick up %s box" % ingredient_type.capitalize()


func _apply_tint() -> void:
	pass  # GLB uses its own materials


func _tint_for_type(itype: String) -> Color:
	match itype:
		"lemon":  return Color(1.0, 0.95, 0.1)
		"water":  return Color(0.4, 0.7, 1.0)
		"sugar":  return Color(0.98, 0.98, 0.98)
		"ice":    return Color(0.7, 0.9, 1.0)
		"cups":   return Color(0.95, 0.95, 0.95)
	return Color.WHITE


func _make_hand_mesh() -> Node3D:
	# Use box.glb directly - scoop_box.tscn has parse errors
	var scene := load("res://blender/box.glb") as PackedScene
	var inst := scene.instantiate() as Node3D
	inst.scale = Vector3.ONE * 0.05
	var lbl := inst.get_node_or_null("QuantityLabel") as Label3D
	if lbl:
		lbl.text = "%s\n\u00d7%.0f" % [ingredient_type.capitalize(), quantity]
	return inst
