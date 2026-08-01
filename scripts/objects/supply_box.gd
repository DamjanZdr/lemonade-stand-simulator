class_name SupplyBox
extends Interactable
## Runtime-spawned by DeliverySystem. Player picks it up and deposits into the matching bin,
## or — for equipment — places it like a container.

@export var ingredient_type: String = "lemon"
@export var quantity: float = 10.0
@export var is_equipment: bool = false
@export var equipment_type: String = ""
@export var is_trash_box: bool = false
@export var trash_value: float = 0.0
@export var trash_type: String = "empty_box"

var is_hand_mesh: bool = false

@onready var physics: StaticBody3D = get_node_or_null("Physics") as StaticBody3D
@onready var label: Label3D = get_node_or_null("Label") as Label3D
@onready var collision_shape: CollisionShape3D = get_node_or_null("Physics/CollisionShape3D") as CollisionShape3D

# Cached icon/label nodes per face for _process
var _face_icons: Array[Sprite3D] = []
var _face_labels: Array[Label3D] = []
const _FACE_NAMES := ["Front", "Back", "Left", "Right", "Top"]
const _FACE_NORMALS: Array[Vector3] = [
	Vector3(0, 0, -1),
	Vector3(0, 0, 1),
	Vector3(-1, 0, 0),
	Vector3(1, 0, 0),
	Vector3(0, 1, 0),
]

static var stack_height: float = 0.324663
static var bottom_offset: float = 0.16
static var stack_radius: float = 0.15
static var box_aabb: AABB = AABB(Vector3(-0.252, -0.16, -0.2), Vector3(0.504, 0.324663, 0.4))

# --- Icon system ---
const INGREDIENT_ICONS: Dictionary = {
	"lemon": "res://Product Images/lemon.png",
	"strawberry": "res://Product Images/strawberry.png",
	"blueberry": "res://Product Images/blueberry.png",
	"peach": "res://Product Images/peach.png",
	"watermelon": "res://Product Images/watermelon.png",
	"sugar": "res://Product Images/sugar.png",
	"ice": "res://Product Images/ice.png",
	"cups": "res://Product Images/cup.png",
	"water": "res://Product Images/water jug.png",
	"fruit_bin": "res://Product Images/crate.png",
	"sugar_bin": "res://Product Images/sugar bin.png",
	"ice_bin": "res://Product Images/ice bucket.png",
	"pitcher": "res://Product Images/pitcher.png",
	"press": "res://Product Images/press.png",
	"workstation": "res://Product Images/table.png",
	"trash": "res://Product Images/trashcan.png",
}
const ICON_SIZE := 128
static var texture_cache: Dictionary = { }


static func pre_render_all() -> void:
	for itype in INGREDIENT_ICONS.keys():
		if not texture_cache.has(itype):
			var path: String = INGREDIENT_ICONS[itype]
			if FileAccess.file_exists(path):
				texture_cache[itype] = load(path) as Texture2D


func _ready() -> void:
	_cache_face_nodes()
	if is_hand_mesh:
		_apply_tint()
		if label:
			label.no_depth_test = false
		var top_icon_node := get_node_or_null("IconSprite_Top") as Sprite3D
		if top_icon_node:
			top_icon_node.no_depth_test = false
			top_icon_node.shaded = false
		if not is_equipment:
			_setup_icon()
		else:
			_setup_equipment_icon()
		set_process(false)
		return
	update_metrics()
	add_to_group("supply_box")
	_apply_tint()
	if is_equipment:
		_setup_equipment_icon()
	else:
		_setup_icon()


func _cache_face_nodes() -> void:
	_face_icons.clear()
	_face_labels.clear()
	for fname in _FACE_NAMES:
		var icon := get_node_or_null("Icons/IconSprite_" + fname) as Sprite3D
		if icon == null:
			icon = get_node_or_null("IconSprite_" + fname) as Sprite3D
		_face_icons.append(icon)
		var lbl := get_node_or_null("Icons/QtyLabel_" + fname) as Label3D
		if lbl == null:
			lbl = get_node_or_null("QtyLabel_" + fname) as Label3D
		_face_labels.append(lbl)


func _process(_delta: float) -> void:
	var has_icon: bool
	if is_equipment:
		has_icon = INGREDIENT_ICONS.has(equipment_type)
	else:
		has_icon = (
			INGREDIENT_ICONS.has(ingredient_type) and (quantity > 0.0 or ingredient_type == "trash")
		)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := (cam.global_position - global_position).normalized()
	for i in range(_FACE_NAMES.size()):
		var world_normal: Vector3 = (global_transform.basis * _FACE_NORMALS[i]).normalized()
		var facing: bool = world_normal.dot(to_cam) > 0.0
		var icon := _face_icons[i]
		if icon != null:
			if has_icon:
				icon.visible = facing
			icon.no_depth_test = false
		var lbl := _face_labels[i]
		if lbl != null:
			if ingredient_type == "trash":
				lbl.visible = false
			else:
				lbl.visible = facing
			lbl.no_depth_test = false


static func _make_icon_texture(itype: String) -> Texture2D:
	if texture_cache.has(itype):
		return texture_cache[itype] as Texture2D
	var path: String = INGREDIENT_ICONS.get(itype, "")
	print(
		"[SupplyBox] _make_icon_texture for '",
		itype,
		"' path='",
		path,
		"' exists=",
		FileAccess.file_exists(path),
	)
	if path != "" and FileAccess.file_exists(path):
		var tex := load(path) as Texture2D
		print("[SupplyBox] loaded texture: ", tex)
		texture_cache[itype] = tex
		return tex
	print("[SupplyBox] FAILED to load icon for '", itype, "'")
	return null


func _setup_equipment_icon() -> void:
	var has_icon := INGREDIENT_ICONS.has(equipment_type)
	var label_text := "×1"
	for i in range(_FACE_NAMES.size()):
		var fname: String = _FACE_NAMES[i]
		var icon_node := _face_icons[i]
		if icon_node != null:
			if fname == "Top" and not is_hand_mesh:
				icon_node.visible = false
			elif not has_icon:
				icon_node.visible = false
			else:
				icon_node.no_depth_test = false
				icon_node.shaded = false
				if not texture_cache.has(equipment_type):
					texture_cache[equipment_type] = _make_icon_texture(equipment_type)
				if texture_cache.has(equipment_type):
					icon_node.texture = texture_cache[equipment_type] as Texture2D
		var label_node := _face_labels[i]
		if label_node != null:
			label_node.no_depth_test = false
			label_node.text = label_text


func _setup_icon() -> void:
	print(
		"[SupplyBox] _setup_icon called, ingredient_type='",
		ingredient_type,
		"' quantity=",
		quantity,
		" is_hand_mesh=",
		is_hand_mesh,
	)
	var qty_text := "×%.0f" % quantity if ingredient_type != "trash" else ""
	var has_icon := (
		INGREDIENT_ICONS.has(ingredient_type) and (quantity > 0.0 or ingredient_type == "trash")
	)
	print(
		"[SupplyBox] has_icon=",
		has_icon,
		" INGREDIENT_ICONS.has=",
		INGREDIENT_ICONS.has(ingredient_type),
	)
	for i in range(_FACE_NAMES.size()):
		var fname: String = _FACE_NAMES[i]
		var icon_node := _face_icons[i]
		if icon_node != null:
			if fname == "Top" and not is_hand_mesh:
				icon_node.visible = false
			elif not has_icon:
				icon_node.visible = false
			else:
				icon_node.no_depth_test = false
				icon_node.shaded = false
				if not texture_cache.has(ingredient_type):
					texture_cache[ingredient_type] = _make_icon_texture(ingredient_type)
				if texture_cache.has(ingredient_type):
					icon_node.texture = texture_cache[ingredient_type] as Texture2D
		var label_node := _face_labels[i]
		if label_node != null:
			label_node.no_depth_test = false
			label_node.text = qty_text


func interact(player: Node) -> void:
	var p: Player = player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return
	# Hide the box before freeing it so it doesn't flash for a frame.
	visible = false
	physics.collision_layer = 0

	if is_trash_box:
		AudioManager.play_sfx("pick_up_box", global_position)
		p.make_held_trash(trash_value, trash_type, _make_hand_mesh())
		_make_boxes_above_fall()
		queue_free()
		return

	if is_equipment:
		AudioManager.play_sfx("pick_up_box", global_position)
		p.set_held(
			p.HeldItem.SUPPLY_BOX,
			{ "source": "delivery", "is_equipment": true, "equipment_type": equipment_type },
			_make_hand_mesh(),
		)
		_make_boxes_above_fall()
		queue_free()
		return

	AudioManager.play_sfx("pick_up_box", global_position)
	p.set_held(
		p.HeldItem.SUPPLY_BOX,
		{ "ingredient_type": ingredient_type, "amount": quantity, "source": "delivery" },
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
			return a.global_position.y < b.global_position.y,
	)
	for box in above:
		var target_y := box.global_position.y - stack_height
		box.set_meta("fall_target_y", target_y)
		var tween := box.create_tween()
		tween.tween_property(box, "global_position:y", target_y, 0.25) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.finished.connect(
			func():
				box.remove_meta("fall_target_y")
				AudioManager.play_sfx("box_drop", box.global_position),
		)


func interact_secondary(player: Node) -> void:
	interact(player)


func get_hint(player: Node) -> String:
	var p: Player = player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return ""
	if is_trash_box:
		return "Trash Box | LMB: pick up"
	if is_equipment:
		return "Supply Box | LMB: pick up %s box" % equipment_type.capitalize().replace("_", " ")
	if ingredient_type == "cups":
		return "Supply Box | LMB: pick up cup box (x%d cups)" % quantity
	return "Supply Box | LMB: pick up %s box (x%.0f)" % [ingredient_type.capitalize(), quantity]


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
	# Instance the actual supply_box scene so all labels/sprites match the editor
	var scene: PackedScene = load("res://scenes/objects/supply_box.tscn") as PackedScene
	var inst: SupplyBox = scene.instantiate() as SupplyBox
	# Mark as hand mesh BEFORE _ready runs (add_child triggers _ready)
	inst.is_hand_mesh = true
	inst.is_equipment = is_equipment
	inst.ingredient_type = ingredient_type
	inst.quantity = quantity
	inst.equipment_type = equipment_type
	# Scale the whole thing down to hand size
	# World box has 'box' child at scale 0.3, so root at 0.05/0.3 gives box at 0.05
	inst.scale = Vector3.ONE * (0.05 / 0.3)
	# Disable physics
	var phys := inst.get_node_or_null("Physics") as StaticBody3D
	if phys:
		phys.collision_layer = 0
		phys.collision_mask = 0
	return inst
