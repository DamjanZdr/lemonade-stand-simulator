@tool
class_name CupStack
extends Interactable
## Stacks cups in a grid. Player takes one at a time.
## Works the same way as IngredientBin: items in ItemGrid, drop animation, etc.

@export var starting_count: int = 5
@export var max_capacity: int = 10
@export var drop_height: float = 0.35

var current_count: int = 0

@onready var item_grid: Node3D = $ItemGrid
@onready var amount_label: Label3D = $AmountLabel
@onready var physics: StaticBody3D = $Physics

var _item_nodes: Array[Node3D] = []
var _item_origins: Array[Vector3] = []
# One collider per cup slot (instead of a single resized collider), so the
# clickable area always exactly matches the cups actually present — the same
# effect as if every cup had its own collision shape.
var _slot_colliders: Array[CollisionShape3D] = []
var _label_format: String = "%.0f / %.0f"

# The standalone cup scene defines the correct per-cup collision shape (a cup
# is much taller than the ~0.6 vertical spacing between nested cups in the
# stack, since cups nest deep inside each other). Reuse its shape/offset
# instead of deriving a (much flatter) height from the grid spacing.
const CUP_SCENE: PackedScene = preload("res://scenes/objects/cup.tscn")


func _ready() -> void:
	_item_nodes.clear()
	for child in item_grid.get_children():
		_item_nodes.append(child as Node3D)

	_item_origins.clear()
	for node in _item_nodes:
		_item_origins.append(node.position)
		# Hide the fill mesh so grid cups always look empty
		var fill := node.find_child("Fill", true, false)
		if fill:
			fill.visible = false

	_build_slot_colliders()

	if Engine.is_editor_hint():
		for node in _item_nodes:
			node.visible = true
		return

	_label_format = amount_label.text
	current_count = starting_count
	_update_display()
	EventBus.debug_refill_all_bins.connect(_on_debug_refill)


# Replaces the single template CollisionShape3D (from the scene file) with
# one CollisionShape3D per cup slot, each using the real cup collision shape
# (from cup.tscn) positioned at that slot's cup origin. This is simpler and
# far more robust than trying to derive a shape from grid spacing.
func _build_slot_colliders() -> void:
	_slot_colliders.clear()
	if physics == null or _item_origins.is_empty():
		return

	for child in physics.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var reference := _get_cup_collision_reference()
	var shape: Shape3D = reference.get("shape")
	if shape == null:
		return
	var offset_y: float = reference.get("offset_y", 0.0)

	var grid_y: float = item_grid.position.y
	for i in range(_item_origins.size()):
		var collider := CollisionShape3D.new()
		# Shared shape resource is fine here since no slot ever mutates it.
		collider.shape = shape
		collider.position = Vector3(0.0, grid_y + _item_origins[i].y + offset_y, 0.0)
		physics.add_child(collider)
		_slot_colliders.append(collider)


# Reads the collision shape and its vertical offset from the standalone cup
# scene, so the stack's per-cup hitboxes always match the "real" cup.
func _get_cup_collision_reference() -> Dictionary:
	var result: Dictionary = { }
	var temp := CUP_SCENE.instantiate() as Node3D
	if temp == null:
		return result
	var col := temp.get_node_or_null("Physics/CollisionShape3D") as CollisionShape3D
	if col != null and col.shape != null:
		result["shape"] = col.shape
		result["offset_y"] = col.position.y
	temp.queue_free()
	return result


func _update_display() -> void:
	var visible_count := mini(current_count, _item_nodes.size())
	for i in range(_item_nodes.size()):
		_item_nodes[i].visible = i < visible_count
	amount_label.text = _label_format % [current_count, max_capacity]

	# Enable only the colliders for cups that are actually present.
	for i in range(_slot_colliders.size()):
		_slot_colliders[i].disabled = i >= visible_count

	# Disable collision and remove from container group when empty
	if current_count <= 0:
		if physics != null:
			physics.collision_layer = 0
			physics.collision_mask = 0
		remove_from_group("container")
	else:
		if physics != null:
			physics.collision_layer = 1
			physics.collision_mask = 1
		add_to_group("container")
	EventBus.cup_stack_changed.emit(current_count)


func add_cups(qty: int, from_pos: Vector3 = Vector3.ZERO) -> void:
	var old_count := mini(current_count, _item_nodes.size())
	current_count = mini(current_count + qty, max_capacity)
	_update_display()
	var new_count := mini(current_count, _item_nodes.size())
	for i in range(old_count, new_count):
		_drop_item(i, from_pos)
	WorldSync.sync_property(self, "current_count", current_count)
	WorldSync.sync_call(self, "_update_display")


func _drop_item(index: int, from_pos: Vector3 = Vector3.ZERO) -> void:
	var node := _item_nodes[index]
	var origin := _item_origins[index]
	if from_pos != Vector3.ZERO:
		_animate_throw_arc(node, from_pos, origin)
		return
	node.position.y = origin.y + drop_height
	var tween := create_tween()
	tween.tween_property(node, "position:y", origin.y, 0.25) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return

	# Deposit ONE cup from box at a time
	if p.held_item == HeldItem.SUPPLY_BOX:
		var data := p.held_item_data
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == "cups":
			var space: int = max_capacity - current_count
			if space <= 0:
				return
			# Only add ONE cup at a time
			add_cups(1, _get_hand_pos(p))
			AudioManager.play_sfx("taking_cup", global_position)
			EventBus.supply_box_deposited.emit("cups", 1.0)
			var remaining: int = int(data.get("amount", 0.0)) - 1
			if remaining > 0:
				p.update_held_amount(float(remaining))
			else:
				p.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
			return

	# Return an empty cup back to the stack
	if p.held_item == HeldItem.CUP_EMPTY:
		add_cups(1, _get_hand_pos(p))
		AudioManager.play_sfx("taking_cup", global_position)
		p.clear_held()
		return

	# Take a cup OR pick up empty container
	if p.held_item == HeldItem.NONE:
		if current_count <= 0:
			# Pick up empty stack
			p.pickup_container(self, "cup_stack")
			return
		current_count -= 1
		_update_display()
		AudioManager.play_sfx("taking_cup", global_position)
		p.set_held(HeldItem.CUP_EMPTY, { }, Cup.make_hand_mesh(false))
		WorldSync.sync_property(self, "current_count", current_count)
		WorldSync.sync_call(self, "_update_display")


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""

	if p.held_item == HeldItem.SUPPLY_BOX:
		var data := p.held_item_data
		if data.get("is_trash", false):
			return ""
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == "cups":
			var space := max_capacity - current_count
			if space <= 0:
				return "Cup Stack | full! (%d / %d)" % [current_count, max_capacity]
			return "Cup Stack | LMB: add 1 cup (x%.0f in box)" % data.get("amount", 0.0)
		return ""

	if p.held_item == HeldItem.NONE:
		if current_count > 0:
			return "Cup Stack | LMB: take a cup (%d)  |  RMB: pick up" % current_count
		return "Cup Stack | LMB: pick up"
	if p.held_item == HeldItem.CUP_EMPTY:
		return "Cup Stack | LMB: return cup"
	return ""


func _on_debug_refill() -> void:
	current_count = max_capacity
	_update_display()
