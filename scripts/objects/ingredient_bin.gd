@tool
class_name IngredientBin
extends Interactable
## Shallow crate that shows individual ingredient items in a 2×5 grid.
## Click (empty hands) → take 1. Click (holding same scoop) → return it.

## Data-driven ingredient config. If set, ingredient_type is derived from this resource.
@export var ingredient_data: IngredientData = null

## Legacy string identifier (kept for backward compat with existing scenes).
## Auto-synced from ingredient_data.id in _ready() if ingredient_data is set.
@export var ingredient_type: String = "lemon"
@export var starting_amount: float = 10.0
@export var max_capacity: float = 10.0
@export var drop_height: float = 0.35

var current_amount: float = 0.0
var _label_format: String = "%.0f / %.0f"

@onready var container_mesh: MeshInstance3D = $Container
@onready var amount_label: Label3D = $AmountLabel
@onready var item_grid: Node3D = $ItemGrid

# Populated from the children of ItemGrid that you place manually in the editor.
var _item_nodes: Array[Node3D] = []
var _item_origins: Array[Vector3] = []

# --- New ice bucket system ---
var _ice_bucket: Node3D = null
var _ice_cubes: Array[MeshInstance3D] = []
var _ice_origins: Array[Vector3] = []
var _cubes_per_scoop: int = 0


func _ready() -> void:
	add_to_group("bin")
	# If an IngredientData resource is assigned, derive the string type from it.
	if ingredient_data != null:
		ingredient_type = ingredient_data.id
	elif ingredient_type == "lemon":
		# Auto-load the default lemon resource for new/modular setups.
		var res := load("res://resources/data/lemon.tres") as IngredientData
		if res != null:
			ingredient_data = res

	# Collect all children of ItemGrid placed manually in the scene.
	_item_nodes.clear()
	for child in item_grid.get_children():
		_item_nodes.append(child as Node3D)

	_item_origins.clear()
	for node in _item_nodes:
		_item_origins.append(node.position)

	if Engine.is_editor_hint():
		# Show all items so you can see them while sizing things in the editor.
		for node in _item_nodes:
			node.visible = true
		return

	# Capture whatever text is set on the label in the editor as the format template.
	_label_format = amount_label.text
	current_amount = starting_amount
	update_display()
	EventBus.debug_refill_all_bins.connect(_on_debug_refill)
	if ingredient_type == "ice":
		_setup_ice_bucket.call_deferred()


func _setup_ice_bucket() -> void:
	_ice_bucket = find_child("ice bucket with ice", false, false)
	if _ice_bucket == null:
		return
	item_grid.visible = false
	_item_nodes.clear()
	_item_origins.clear()
	var temp_cubes: Array[MeshInstance3D] = []
	for child in _ice_bucket.get_children():
		if child is MeshInstance3D and child.name != "Bucket_001":
			temp_cubes.append(child)
	# Sort by global Y ascending (lowest first)
	temp_cubes.sort_custom(
		func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
			return a.global_position.y < b.global_position.y
	)
	for cube in temp_cubes:
		_ice_cubes.append(cube)
		_ice_origins.append(cube.position)
	if _ice_cubes.size() > 0:
		_cubes_per_scoop = maxi(1, roundi(float(_ice_cubes.size()) / max_capacity))
	_sync_ice_display()


func _sync_ice_display(animate_add: bool = false) -> void:
	if _ice_cubes.is_empty():
		return
	var target_visible: int = clampi(
		roundi((current_amount / max_capacity) * float(_ice_cubes.size())),
		0,
		_ice_cubes.size(),
	)
	var prev_visible := 0
	for cube in _ice_cubes:
		if cube.visible:
			prev_visible += 1
	for i in range(_ice_cubes.size()):
		var was_visible := i < prev_visible
		var should_visible := i < target_visible
		_ice_cubes[i].visible = should_visible
		if should_visible and not was_visible and animate_add and _ice_origins.size() > i:
			_ice_cubes[i].position.y = _ice_origins[i].y + drop_height
			var tween := create_tween()
			tween.tween_property(_ice_cubes[i], "position:y", _ice_origins[i].y, 0.25) \
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func update_display() -> void:
	if ingredient_type == "ice" and _ice_bucket != null:
		amount_label.text = _label_format % [current_amount, max_capacity]
		_sync_ice_display()
		return
	var visible_count: int = mini(roundi(current_amount), _item_nodes.size())
	for i in range(_item_nodes.size()):
		_item_nodes[i].visible = i < visible_count
	amount_label.text = _label_format % [current_amount, max_capacity]


func add_amount(qty: float) -> void:
	if ingredient_type == "ice" and _ice_bucket != null:
		current_amount = minf(current_amount + qty, max_capacity)
		_sync_ice_display(true)
		EventBus.bin_amount_changed.emit(ingredient_type, current_amount)
		return
	var old_count := mini(roundi(current_amount), _item_nodes.size())
	current_amount = minf(current_amount + qty, max_capacity)
	update_display()
	var new_count := mini(roundi(current_amount), _item_nodes.size())
	for i in range(old_count, new_count):
		_drop_item(i)
	EventBus.bin_amount_changed.emit(ingredient_type, current_amount)


func _drop_item(index: int) -> void:
	var node := _item_nodes[index]
	node.position.y = _item_origins[index].y + drop_height
	var tween := create_tween()
	tween.tween_property(node, "position:y", _item_origins[index].y, 0.25) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func take_amount(qty: float) -> float:
	var taken := minf(qty, current_amount)
	current_amount -= taken
	if ingredient_type == "ice" and _ice_bucket != null:
		_sync_ice_display()
	else:
		update_display()
	EventBus.bin_amount_changed.emit(ingredient_type, current_amount)
	return taken

# Local constants matching Player.HeldItem enum (breaks circular dependency)
const HELD_NONE := 0
const HELD_CUP_EMPTY := 1
const HELD_CUP_FILLED := 2
const HELD_SUPPLY_BOX := 3
const HELD_CONTAINER := 4


func interact(player: Node) -> void:
	# Duck-type: verify this is a player by checking for required methods/properties
	if not player.has_method("clear_held"):
		return
	var held_item: int = player.get("held_item")
	var data: Dictionary = player.get("held_item_data")

	if held_item == HELD_SUPPLY_BOX:
		# Return: player holds a scoop of this same ingredient → put it back
		if data.get("source") == "bin_scoop" \
				and data.get("ingredient_type", "") == ingredient_type:
			add_amount(data.get("amount", Balancing.GRAB_AMOUNT))
			player.clear_held()
			return
		# Deposit delivery box — 1 unit per click so the player sees the bin fill up.
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == ingredient_type:
			var to_deposit: float = data.get("amount", 0.0)
			var space: float = max_capacity - current_amount
			if space <= 0.0:
				return # hint already says "Bin full"
			var deposited: float = minf(Balancing.GRAB_AMOUNT, minf(to_deposit, space))
			add_amount(deposited)
			EventBus.supply_box_deposited.emit(ingredient_type, deposited)
			var remaining: float = to_deposit - deposited
			if remaining > 0.0:
				player.update_held_amount(remaining)
			else:
				player.clear_held()
		return

	# Take one unit OR pick up empty container
	if held_item == HELD_NONE:
		# If empty, left-click picks up the container itself
		if current_amount <= 0.0:
			player.pickup_container(self, _get_container_type())
			return
		# Otherwise take a scoop
		take_amount(Balancing.GRAB_AMOUNT)
		player.set_held(
			HELD_SUPPLY_BOX,
			{
				"ingredient_type": ingredient_type,
				"amount": Balancing.GRAB_AMOUNT,
				"source": "bin_scoop",
			},
			_make_hand_mesh(),
		)
		EventBus.ingredient_scoop_grabbed.emit(ingredient_type, Balancing.GRAB_AMOUNT)


func _get_container_type() -> String:
	match ingredient_type:
		"lemon":
			return "fruit_bin"
		"sugar":
			return "sugar_bin"
		"ice":
			return "ice_bin"
	return ""


func get_hint(player: Node) -> String:
	if not player.has_method("clear_held"):
		return ""
	var held_item: int = player.get("held_item")
	var data: Dictionary = player.get("held_item_data")

	if held_item == HELD_SUPPLY_BOX:
		if data.get("source") == "bin_scoop" \
				and data.get("ingredient_type", "") == ingredient_type:
			return "Click: return %s to bin" % ingredient_type.capitalize()
		if data.get("source") == "delivery" \
				and data.get("ingredient_type", "") == ingredient_type:
			var space := max_capacity - current_amount
			if space <= 0.0:
				return "Bin full! (%.0f / %.0f)" % [current_amount, max_capacity]
			return "Click: deposit %s (×%.0f in box)" % [
				ingredient_type.capitalize(),
				data.get("amount", 0.0),
			]
		return ""

	if held_item == HELD_NONE:
		if current_amount >= Balancing.GRAB_AMOUNT:
			return "LMB: take %s  |  RMB: pick up bin  (%.0f left)" % [
				ingredient_type.capitalize(),
				current_amount,
			]
		return "LMB: pick up empty " + ingredient_type.capitalize() + " bin  |  RMB: pick up"
	return ""


func _make_hand_mesh() -> Node3D:
	match ingredient_type:
		"lemon":
			var s := load("res://blender/lemon.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.075
				return inst
		"sugar":
			var s := load("res://blender/sugar cube.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.028
				return inst
		"ice":
			var s := load("res://scenes/objects/ice_scoop.tscn") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.05
				return inst
	# Fallback sphere for unknown types
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.038
	sphere.height = 0.076
	m.mesh = sphere
	return m


func _on_debug_refill() -> void:
	current_amount = max_capacity
	update_display()
	EventBus.bin_amount_changed.emit(ingredient_type, current_amount)
