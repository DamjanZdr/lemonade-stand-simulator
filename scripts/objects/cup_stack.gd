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
var _label_format: String = "%.0f / %.0f"


func _ready() -> void:
	_item_nodes.clear()
	for child in item_grid.get_children():
		_item_nodes.append(child as Node3D)

	_item_origins.clear()
	for node in _item_nodes:
		_item_origins.append(node.position)
		# Hide the CupFill mesh so grid cups always look empty
		var fill := node.find_child("CupFill", true, false)
		if fill:
			fill.visible = false

	if Engine.is_editor_hint():
		for node in _item_nodes:
			node.visible = true
		return

	_label_format = amount_label.text
	current_count = starting_count
	_update_display()
	EventBus.debug_refill_all_bins.connect(_on_debug_refill)


func _update_display() -> void:
	var visible_count := mini(current_count, _item_nodes.size())
	for i in range(_item_nodes.size()):
		_item_nodes[i].visible = i < visible_count
	amount_label.text = _label_format % [current_count, max_capacity]
	
	# Disable collision and remove from container group when empty
	if current_count <= 0:
		if physics != null:
			physics.collision_layer = 0
			physics.collision_mask = 0
		remove_from_group("container")
	else:
		add_to_group("container")
	EventBus.cup_stack_changed.emit(current_count)


func add_cups(qty: int) -> void:
	var old_count := mini(current_count, _item_nodes.size())
	current_count = mini(current_count + qty, max_capacity)
	_update_display()
	var new_count := mini(current_count, _item_nodes.size())
	for i in range(old_count, new_count):
		_drop_item(i)


func _drop_item(index: int) -> void:
	var node := _item_nodes[index]
	node.position.y = _item_origins[index].y + drop_height
	var tween := create_tween()
	tween.tween_property(node, "position:y", _item_origins[index].y, 0.25) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return

	# Deposit ONE cup from box at a time
	if p.held_item == p.HeldItem.SUPPLY_BOX:
		var data := p.held_item_data
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == "cups":
			var space: int = max_capacity - current_count
			if space <= 0:
				return
			# Only add ONE cup at a time
			add_cups(1)
			EventBus.supply_box_deposited.emit("cups", 1.0)
			var remaining: int = int(data.get("amount", 0.0)) - 1
			if remaining > 0:
				p.update_held_amount(float(remaining))
			else:
				p.clear_held()
			return

	# Return an empty cup back to the stack
	if p.held_item == p.HeldItem.CUP_EMPTY:
		add_cups(1)
		p.clear_held()
		return

	# Take a cup OR pick up empty container
	if p.held_item == p.HeldItem.NONE:
		if current_count <= 0:
			# Pick up empty stack
			p.pickup_container(self, "cup_stack")
			return
		current_count -= 1
		_update_display()
		p.set_held(p.HeldItem.CUP_EMPTY, {}, Cup.make_hand_mesh(false))


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""

	if p.held_item == p.HeldItem.SUPPLY_BOX:
		var data := p.held_item_data
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == "cups":
			var space := max_capacity - current_count
			if space <= 0:
				return "Cup stack full! (%d / %d)" % [current_count, max_capacity]
			return "Click: add 1 cup (×%.0f in box)" % data.get("amount", 0.0)
		return ""

	if p.held_item == p.HeldItem.NONE:
		if current_count > 0:
			return "LMB: take a cup  |  RMB: pick up stack  (%d left)" % current_count
		return "LMB: pick up empty stack  |  RMB: pick up"
	if p.held_item == p.HeldItem.CUP_EMPTY:
		return "Click: return cup"
	return ""


func _on_debug_refill() -> void:
	current_count = max_capacity
	_update_display()
