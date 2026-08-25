class_name PlayerPlacement
extends Node
## Handles placement ghost visualization and placement/drop logic for held items.

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if _player == null:
		push_warning("PlayerPlacement: parent is not a Player")


## Local-player placement init: precompute shared box metrics and load the
## workstation scene at runtime (avoiding compile-time preload issues while
## the editor reimports .uid files). Called from Player._configure_local_player.
func _configure_local_player() -> void:
	var temp_box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	temp_box.update_metrics()
	temp_box.free()
	_workstation_scene = load("res://scenes/stand/workstation.tscn") as PackedScene


## Public entry point used by PlayerController._process to refresh the ghost.
func update_ghost() -> void:
	_update_ghost()


const HINT_GROUND := "Aim at ground to place"
const HINT_STAND := "Aim at stand or workstation to place"
# --- Container placement ghost ---
var _ghost: Node3D = null
var _ghost_valid: bool = false
static var _ghost_mat_valid: StandardMaterial3D = null
static var _ghost_mat_invalid: StandardMaterial3D = null
var _last_ghost_mat: StandardMaterial3D = null

# --- Box stack wobble ---
var _stack_target_id: int = -1
var _stack_offset: Vector3 = Vector3.ZERO
var _stack_yaw: float = 0.0

const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")

const CONTAINER_SCENES: Dictionary = {
	"fruit_bin": preload("res://scenes/objects/fruit_bin.tscn"),
	"sugar_bin": preload("res://scenes/objects/sugar_bin.tscn"),
	"ice_bin": preload("res://scenes/objects/ice_bin.tscn"),
	"cup_stack": CUP_STACK_SCENE,
	"pitcher": preload("res://scenes/objects/pitcher.tscn"),
	"press": preload("res://scenes/objects/press.tscn"),
	"water_dispenser": preload("res://scenes/objects/water_dispenser.tscn"),
}

const CONTAINER_SCENE_PATHS: Dictionary = {
	"fruit_bin": "res://scenes/objects/fruit_bin.tscn",
	"sugar_bin": "res://scenes/objects/sugar_bin.tscn",
	"ice_bin": "res://scenes/objects/ice_bin.tscn",
	"cup_stack": "res://scenes/objects/cup_stack.tscn",
	"pitcher": "res://scenes/objects/pitcher.tscn",
	"press": "res://scenes/objects/press.tscn",
	"water_dispenser": "res://scenes/objects/water_dispenser.tscn",
	"workstation": "res://scenes/stand/workstation.tscn",
}

# Workstation scene is loaded at runtime to avoid compile-time preload issues
# while the editor re-imports its new .uid files.
var _workstation_scene: PackedScene = null

# Shared box glb scene for trash and held boxes (loaded on demand).
var _trash_box_scene: PackedScene = null

const CONTAINER_PLACEMENT_SCALE: Dictionary = {
	"fruit_bin": Vector3.ONE * 0.06,
	"sugar_bin": Vector3.ONE * 0.04,
	"ice_bin": Vector3.ONE * 0.03,
	"cup_stack": Vector3.ONE * 0.03, # Smaller cups
	"pitcher": Vector3.ONE * 0.1575,
	"press": Vector3.ONE * 0.10,
	"water_dispenser": Vector3.ONE * 0.25,
	"workstation": Vector3.ONE,
}

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")
const STACK_MAX_OFFSET: float = 0.04
const STACK_MAX_YAW: float = 0.14
const CUP_SCENE: PackedScene = preload("res://scenes/objects/cup.tscn")

const CONTAINER_HAND_SCALE: Dictionary = {
	"fruit_bin": Vector3.ONE * 0.03,
	"sugar_bin": Vector3.ONE * 0.02,
	"ice_bin": Vector3.ONE * 0.015,
	"cup_stack": Vector3.ONE * 0.015,
	"pitcher": Vector3.ONE * 0.08,
	"press": Vector3.ONE * 0.05,
	"water_dispenser": Vector3.ONE * 0.08,
	"workstation": Vector3.ONE * 0.05,
}


func _get_container_bottom_offset(node: Node, parent_y: float = 0.0) -> float:
	# Calculate how far the collision extends below the node's origin.
	if node == null:
		return 0.0
	var node_y := parent_y
	if node is Node3D:
		node_y += (node as Node3D).position.y
	var lowest_y := node_y
	for child in node.get_children():
		if child is CollisionShape3D:
			var col := child as CollisionShape3D
			var shape_pos_y := node_y + col.position.y
			var half_height := 0.0
			if col.shape is BoxShape3D:
				half_height = (col.shape as BoxShape3D).size.y * 0.5
			elif col.shape is CylinderShape3D:
				half_height = (col.shape as CylinderShape3D).height * 0.5
			elif col.shape is SphereShape3D:
				half_height = (col.shape as SphereShape3D).radius
			var bottom := shape_pos_y - half_height
			lowest_y = min(lowest_y, bottom)
		if child is Node3D:
			lowest_y = min(lowest_y, _get_container_bottom_offset(child, node_y))
	return lowest_y


func _get_container_scene(container_type: String) -> PackedScene:
	# Return the PackedScene for a container type, handling workstation specially.
	if container_type == "workstation":
		return _workstation_scene
	return CONTAINER_SCENES.get(container_type) as PackedScene


func _held_pitcher_has_contents() -> bool:
	var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
	return (
		recipe.get("fruit_count", recipe.get("lemons", 0.0)) > 0.0 or recipe.get("water", 0.0) > 0.0
		or recipe.get("sugar", 0.0) > 0.0 or recipe.get("ice", 0.0) > 0.0
	)


func _empty_held_pitcher() -> void:
	## Dumps out whatever's currently in the held pitcher. Keeps the pitcher
	## itself held ΓÇö only clears its contents.
	if not _held_pitcher_has_contents():
		EventBus.interaction_hint_changed.emit("Pitcher is already empty!")
		return

	_player.held_item_data["saved_recipe"] = { }
	_player.held_item_data["has_liquid"] = false

	if _player._held_mesh is Pitcher:
		var held_pitcher := _player._held_mesh as Pitcher
		held_pitcher.fruit_type = ""
		held_pitcher.fruit_count = 0.0
		held_pitcher.water = 0.0
		held_pitcher.sugar = 0.0
		held_pitcher.ice = 0.0
		held_pitcher.cups_poured = 0
		held_pitcher.update_label()
		held_pitcher.update_liquid_color()

	EventBus.interaction_hint_changed.emit("Pitcher emptied!")


func _place_cup_stack_from_box() -> void:
	# Place ONE cup on the surface or add to existing stack.

	# Get quantity from held box
	var qty: int = int(_player.held_item_data.get("amount", 0))
	if qty <= 0:
		return

	# Check if looking at existing stack
	var interactable := _player.interaction.get_looked_at_interactable() as Interactable
	if interactable is CupStack:
		# Add one cup to existing stack
		_player.interaction.set_rapid_fire_cup_target(interactable as CupStack)
		interactable.add_cups(1)
		_player.inventory.update_held_amount(float(qty - 1))
		if qty - 1 <= 0:
			_player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
		EventBus.supply_box_deposited.emit("cups", 1)
		return

	# Check for overlap with existing cup stacks before placing
	if _player.ray.is_colliding():
		var hit_point := _player.ray.get_collision_point()
		for node in get_tree().get_nodes_in_group("container"):
			if node is CupStack:
				var dist := (node as Node3D).global_position.distance_to(hit_point)
				if dist < 0.08: # Smaller threshold for cups
					EventBus.interaction_hint_changed.emit("Too close to existing cup stack!")
					return

	# Place new stack with ONE cup
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack")
	var place_point := _player.ray.get_collision_point()
	var bottom_offset_estimate := 0.5
	var stack_pos := place_point + Vector3(0, -bottom_offset_estimate * placement_scale.y, 0)
	var look_dir := _player.global_position - place_point
	look_dir.y = 0
	var stack_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		stack_rot.y = atan2(look_dir.x, look_dir.z)

	var state: Dictionary = {
		"starting_count": 1,
		"max_capacity": 10,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
	}
	var stack := WorldSync.request_spawn(
		"res://scenes/objects/cup_stack.tscn",
		stack_pos,
		stack_rot,
		state,
	) as CupStack
	if stack:
		stack.scale = placement_scale
		stack.add_to_group("container")

	# Deduct one cup from held box
	_player.inventory.update_held_amount(float(qty - 1))
	if qty - 1 <= 0:
		_player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")

	# Remember this brand-new stack as the rapid-fire target so holding the
	# mouse down keeps depositing into it, even before the raycast has had a
	# chance to register its freshly-added (and quite small) collider.
	_player.interaction.set_rapid_fire_cup_target(stack as CupStack)

	AudioManager.play_sfx(_get_place_sfx_key("cup_stack"), stack.global_position, -1.0, 0.05, 0.85)
	EventBus.container_placed.emit("cup_stack", stack)


func _update_single_cup_ghost() -> void:
	# Show ghost preview for single cup placement.
	# Destroy ghost if it's the wrong type for current held item
	if _ghost != null:
		var is_cup_stack_ghost: bool = _ghost.get_node_or_null("ItemGrid") != null
		var should_be_stack: bool = _player.held_item == HeldItem.CUP_EMPTY
		if is_cup_stack_ghost != should_be_stack:
			_destroy_ghost()

	if _ghost == null:
		if _player.held_item == HeldItem.CUP_FILLED:
			_ghost = CUP_SCENE.instantiate()
			var placement_scale: Vector3 = Vector3.ONE * 0.03
			_ghost.scale = placement_scale
			_ghost.state = Cup.CupState.FILLED
			var bottom_offset := _get_container_bottom_offset(_ghost)
			_ghost.set_meta("bottom_offset", bottom_offset * placement_scale.y)
			_disable_scripts(_ghost)
			_disable_physics(_ghost)
			_mark_ghost(_ghost)
			_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			get_tree().current_scene.add_child(_ghost)
		else:
			_ghost = CUP_STACK_SCENE.instantiate()
			var placement_scale: Vector3 = (CONTAINER_PLACEMENT_SCALE.get("cup_stack"))
			_ghost.scale = placement_scale
			var bottom_offset := _get_container_bottom_offset(_ghost)
			_ghost.set_meta("bottom_offset", bottom_offset * placement_scale.y)
			_disable_scripts(_ghost)
			_disable_physics(_ghost)
			_mark_ghost(_ghost)
			# Show only 1 cup in ghost
			_set_single_cup_visibility(_ghost)
			_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			get_tree().current_scene.add_child(_ghost)

	if not _player.ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := _player.ray.get_collider()
	var on_surface := _is_placement_surface(collider)
	var hit_point := _player.ray.get_collision_point()

	# Check if looking at existing cup stack
	var interactable := _player.interaction.get_looked_at_interactable() as Interactable
	if interactable is CupStack and _player.held_item == HeldItem.CUP_EMPTY:
		# For empty cups, hide ghost when looking at stack
		_ghost.visible = false
		_ghost_valid = true
		return

	# Only show ghost when on valid placement surface
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	# Filled cups can't go on ground
	var is_ground := _is_ground_surface(collider)
	if _player.held_item == HeldItem.CUP_FILLED and is_ground:
		_ghost.visible = true
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
		return

	_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)

	var overlapping := _check_ghost_overlap()
	_ghost.visible = true

	var valid := not overlapping
	_ghost_valid = valid
	var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
	_apply_ghost_material(_ghost, mat)


func _place_single_cup(_filled: bool) -> void:
	# Place a single cup on the surface (creates new stack with 1 cup).
	# Check ghost validity before placing
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Cannot place here - too close to another stack!")
		return

	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack")
	var hit_point := _player.ray.get_collision_point()
	var bottom_offset_estimate := 0.5
	var stack_pos := hit_point + Vector3(0, -bottom_offset_estimate * placement_scale.y, 0)
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	var stack_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		stack_rot.y = atan2(look_dir.x, look_dir.z)

	var state: Dictionary = {
		"starting_count": 1,
		"max_capacity": 10,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
	}
	var stack := WorldSync.request_spawn(
		"res://scenes/objects/cup_stack.tscn",
		stack_pos,
		stack_rot,
		state,
	) as CupStack
	if stack:
		stack.scale = placement_scale
		stack.add_to_group("container")

	_destroy_ghost()
	_player.inventory.clear_held()
	AudioManager.play_sfx("taking_cup", stack_pos)
	EventBus.container_placed.emit("cup_stack", stack)


func _place_filled_cup() -> void:
	# Place a filled cup on the surface for customers to take.
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Cannot place here - invalid position!")
		return

	var recipe: Dictionary = _player.held_item_data.get("recipe", { })
	var placement_scale := Vector3.ONE * 0.03
	# Calculate position before spawning
	var hit_point := _player.ray.get_collision_point()
	# Estimate bottom offset (cup physics shape) for placement
	var bottom_offset_estimate := 0.5
	var cup_pos := hit_point + Vector3(0, -bottom_offset_estimate * placement_scale.y, 0)
	# Face the player
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	var cup_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		cup_rot.y = atan2(look_dir.x, look_dir.z)

	var state: Dictionary = {
		"recipe": recipe,
		"fill_color": recipe.get("color", Color(1.0, 0.9, 0.3, 1.0)),
		"state": Cup.CupState.FILLED,
		"_net_groups": ["container"],
	}
	var cup := WorldSync.request_spawn("res://scenes/objects/cup.tscn", cup_pos, cup_rot, state) as Cup
	if cup:
		cup.scale = placement_scale
		cup.add_to_group("container")
		# Ensure collision is active and on the _player.interaction layer
		if cup.physics != null:
			cup.physics.collision_layer = 1
			cup.physics.collision_mask = 1
			for child in cup.physics.get_children():
				if child is CollisionShape3D:
					child.disabled = false

	_destroy_ghost()
	_player.inventory.clear_held()
	AudioManager.play_sfx("taking_cup", cup_pos)
	EventBus.interaction_hint_changed.emit("Filled cup placed!")


func _place_held_supply_box_on(place_pos: Vector3, place_rot: Vector3 = Vector3.ZERO) -> SupplyBox:
	var state: Dictionary = { }
	if _player.held_item_data.get("is_equipment", false):
		state["is_equipment"] = true
		state["equipment_type"] = _player.held_item_data.get("equipment_type", "")
	else:
		state["ingredient_type"] = _player.held_item_data.get("ingredient_type", "lemon")
		state["quantity"] = _player.held_item_data.get("amount", 1.0)
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		place_pos,
		place_rot,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
	AudioManager.play_sfx("box_drop", place_pos)
	_destroy_ghost()
	_player.inventory.clear_held()
	return box


func _regenerate_stack_offset() -> void:
	var angle := randf() * TAU
	var dist := randf() * STACK_MAX_OFFSET
	_stack_offset = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_stack_yaw = randf_range(-STACK_MAX_YAW, STACK_MAX_YAW)


func _get_topmost_box_in_stack(base: SupplyBox) -> SupplyBox:
	if not is_instance_valid(base) or not base.is_inside_tree():
		return base
	var top := base
	var top_y := _get_box_stack_y(base)
	var base_pos := base.global_position
	for node in get_tree().get_nodes_in_group("supply_box"):
		if not is_instance_valid(node) or node == base:
			continue
		var box := node as SupplyBox
		if box == null or not box.is_inside_tree():
			continue
		var dx := absf(box.global_position.x - base_pos.x)
		var dz := absf(box.global_position.z - base_pos.z)
		if dx < SupplyBox.stack_radius and dz < SupplyBox.stack_radius:
			var box_y := _get_box_stack_y(box)
			if box_y > top_y:
				top = box
				top_y = box_y
	return top


func _get_box_stack_y(box: SupplyBox) -> float:
	if box.has_meta("fall_target_y"):
		return box.get_meta("fall_target_y") as float
	if not box.is_inside_tree():
		return 0.0
	return box.global_position.y


func _get_delivery_grid_from_collider(collider: Node) -> DeliveryGrid:
	var node: Node = collider
	while node != null:
		if node is DeliveryGrid:
			return node as DeliveryGrid
		node = node.get_parent()
	return null


func _get_delivery_grid() -> DeliveryGrid:
	if get_tree() == null:
		return null
	var grid := get_tree().get_first_node_in_group("delivery_grid") as DeliveryGrid
	return grid


func _is_aiming_at_grid() -> bool:
	if not _player.ray.is_colliding():
		return false
	var collider := _player.ray.get_collider()
	var grid := _get_delivery_grid_from_collider(collider)
	if grid == null:
		return false
	# Prefer stacking on a box if the _player.ray is actually hitting a box on the grid.
	var node: Node = collider
	while node != null:
		if node is SupplyBox:
			return false
		node = node.get_parent()
	return true


func _place_held_supply_box_on_grid(grid: DeliveryGrid, hit_point: Vector3) -> void:
	var cell_idx := grid.get_closest_cell(hit_point)
	if cell_idx < 0:
		_drop_held_box()
		return
	var slot := grid.reserve_slot(cell_idx)
	var box := _place_held_supply_box_on(slot["position"], slot["rotation"])
	if box == null:
		return
	box.set_meta("delivery_cell_idx", cell_idx)
	box.set_meta("delivery_grid_path", grid.get_path())


func _place_held_supply_box_on_stack(root: SupplyBox) -> void:
	root.update_metrics()
	var top := _get_topmost_box_in_stack(root)
	if top.get_instance_id() != _stack_target_id:
		_stack_target_id = top.get_instance_id()
		_regenerate_stack_offset()
	var top_y := _get_box_stack_y(top)
	var place_pos := Vector3(top.global_position.x, top_y, top.global_position.z) + Vector3(
		0,
		SupplyBox.stack_height,
		0,
	) + _stack_offset
	var place_rot := top.global_rotation + Vector3(0, _stack_yaw, 0)
	var box := _place_held_supply_box_on(place_pos, place_rot)
	if box == null:
		return
	var cell_idx: int = top.get_meta("delivery_cell_idx", -1) as int
	if cell_idx >= 0:
		var grid := _get_delivery_grid()
		if grid != null:
			grid.reserve_slot(cell_idx)
			box.set_meta("delivery_cell_idx", cell_idx)
			box.set_meta("delivery_grid_path", grid.get_path())


func _drop_held_box() -> void:
	var state: Dictionary = { }
	if _player.held_item_data.get("is_equipment", false):
		state["is_equipment"] = true
		state["equipment_type"] = _player.held_item_data.get("equipment_type", "")
	else:
		state["ingredient_type"] = _player.held_item_data.get("ingredient_type", "lemon")
		state["quantity"] = _player.held_item_data.get("amount", 1.0)
	# Drop exactly where the raycast hits, or 0.8 m ahead if not hitting anything.
	var drop_pos: Vector3
	if _player.ray.is_colliding():
		drop_pos = _player.ray.get_collision_point() + Vector3(0, SupplyBox.bottom_offset, 0)
	else:
		drop_pos = _player.global_position + (-_player.transform.basis.z * 0.8) + Vector3(
			0,
			0.15,
			0,
		)
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		drop_pos,
		Vector3.ZERO,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
	AudioManager.play_sfx("box_drop", drop_pos)
	_destroy_ghost()
	_player.inventory.clear_held()


func _drop_trash(place_pos: Vector3 = Vector3.ZERO) -> void:
	var state: Dictionary = {
		"is_trash_box": true,
		"ingredient_type": "trash",
		"quantity": 0.0,
		"trash_value": _player.held_item_data.get("trash_value", 0.0),
		"trash_type": _player.held_item_data.get("trash_type", "empty_box"),
	}
	var drop_pos: Vector3
	if place_pos != Vector3.ZERO:
		drop_pos = place_pos
	elif _player.ray.is_colliding() and _is_placement_surface(_player.ray.get_collider()):
		drop_pos = _player.ray.get_collision_point() + Vector3(0, SupplyBox.bottom_offset, 0)
	else:
		drop_pos = _player.global_position + (-_player.transform.basis.z * 0.8) + Vector3(
			0,
			0.15,
			0,
		)
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		drop_pos,
		Vector3.ZERO,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
	AudioManager.play_sfx("box_drop", drop_pos)
	_destroy_ghost()
	_player.inventory.clear_held()


func _get_place_sfx_key(container_type: String) -> String:
	match container_type:
		"pitcher", "press", "fruit_bin":
			return container_type
		_:
			return "table"


func _place_equipment_from_box() -> void:
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Can only place on stand or workstation!")
		return
	var equipment_type: String = _player.held_item_data.get("equipment_type", "")
	var scene_path: String = CONTAINER_SCENE_PATHS.get(equipment_type, "")
	if scene_path == "":
		push_warning("Unknown equipment type: " + equipment_type)
		return
	# Use same position as ghost (already includes collision offset)
	var place_pos := _ghost.global_position
	var place_rot := _ghost.global_rotation
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(equipment_type, Vector3.ONE)
	var state: Dictionary = { }
	# Set initial state so _ready() sees it
	state["starting_amount"] = 0.0
	state["starting_count"] = 0
	state["_net_groups"] = ["container"]
	state["_net_scale"] = placement_scale
	var instance := WorldSync.request_spawn(scene_path, place_pos, place_rot, state) as Node3D
	if instance:
		instance.scale = placement_scale
		instance.add_to_group("container")
		# Add pitcher to pitcher group for water tap detection
		if instance is Pitcher:
			instance.add_to_group("pitcher")
			instance.set_pitcher_visible(true)
			instance.sync_fill_display()
			instance.call_deferred("update_label")
			EventBus.pitcher_state_changed.emit(int(instance.state))
	_destroy_ghost()
	_player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
	AudioManager.play_sfx(_get_place_sfx_key(equipment_type), place_pos, -1.0, 0.05, 0.85)
	EventBus.container_placed.emit(equipment_type, instance)


func hold_container(
	container_type: String,
	saved_amount: float = 0.0,
	saved_count: int = 0,
	has_liquid: bool = false,
	saved_recipe: Dictionary = { },
	from_box: bool = false,
) -> void:
	var scene: PackedScene = _get_container_scene(container_type)
	if scene == null:
		push_warning("Unknown container type: " + container_type)
		return

	# Create hand mesh for container first
	var hand_mesh: Node3D = _create_container_hand_mesh(
		container_type,
		has_liquid,
		saved_recipe,
		saved_amount,
		saved_count,
		from_box,
	)

	# Use set_held to properly manage hand mesh (unified system)
	_player.inventory.set_held(
		HeldItem.CONTAINER,
		{
			"container_type": container_type,
			"saved_amount": saved_amount,
			"saved_count": saved_count,
			"has_liquid": has_liquid,
			"saved_recipe": saved_recipe,
			"from_delivery_box": from_box,
		},
		hand_mesh,
	)

	EventBus.held_item_changed.emit(int(_player.held_item), _player.held_item_data)
	_create_ghost(container_type)


func _get_trash_box_scene() -> PackedScene:
	if _trash_box_scene == null:
		_trash_box_scene = load("res://assets/models/props/boxnew.glb") as PackedScene
	return _trash_box_scene


func _create_container_hand_mesh(
	container_type: String,
	_has_liquid: bool,
	saved_recipe: Dictionary,
	saved_amount: float = 0.0,
	saved_count: int = 0,
	from_box: bool = false,
) -> Node3D:
	# Create a hand mesh for the held container.
	if from_box:
		var box_inst: SupplyBox = SUPPLY_BOX_SCENE.instantiate() as SupplyBox
		box_inst.is_hand_mesh = true
		box_inst.quantity = 0.0
		box_inst.scale = Vector3.ONE * (0.05 / 0.3)
		var phys := box_inst.get_node_or_null("Physics") as StaticBody3D
		if phys:
			phys.collision_layer = 0
			phys.collision_mask = 0
		return box_inst

	var scene: PackedScene = _get_container_scene(container_type)
	if scene == null:
		return null

	var inst: Node3D = scene.instantiate() as Node3D

	# Set starting state BEFORE the node enters the tree so its _ready()
	# correctly displays the right item count and formats the label.
	_set_container_starting_state(inst, container_type, saved_amount, saved_count, saved_recipe)

	# Apply hand scale for containers (smaller than placed version)
	var hand_scale: Vector3 = CONTAINER_HAND_SCALE.get(container_type, Vector3.ONE * 0.1)
	inst.scale = hand_scale

	# Disable collision on hand mesh to prevent pushing player
	_disable_hand_collision(inst)

	# Hand-held clones must not be counted as real placed objects
	_remove_placement_groups(inst)

	return inst


func _set_container_starting_state(
	inst: Node,
	container_type: String,
	saved_amount: float,
	saved_count: int,
	saved_recipe: Dictionary = { },
) -> void:
	# Set the starting amount/count on a container instance so its own
	# _ready() renders the correct item visibility and label text.
	match container_type:
		"sugar_bin", "ice_bin":
			if "starting_amount" in inst:
				inst.starting_amount = saved_amount
		"fruit_bin":
			if inst is FruitBin:
				var fbin := inst as FruitBin
				var amounts: Dictionary = saved_recipe.get("fruit_amounts", { })
				if not amounts.is_empty():
					fbin.fruit_amounts = amounts.duplicate()
		"cup_stack":
			if "starting_count" in inst:
				inst.starting_count = saved_count
		"pitcher":
			if inst is Pitcher:
				var pitcher := inst as Pitcher
				pitcher.fruit_type = saved_recipe.get("fruit_type", "")
				pitcher.fruit_count = saved_recipe.get(
					"fruit_count",
					saved_recipe.get("lemons", 0.0),
				)
				pitcher.water = saved_recipe.get("water", 0.0)
				pitcher.sugar = saved_recipe.get("sugar", 0.0)
				pitcher.ice = saved_recipe.get("ice", 0.0)
				pitcher.cups_poured = saved_recipe.get("cups_poured", 0)


func _refresh_held_container_mesh() -> void:
	if _player._held_mesh and is_instance_valid(_player._held_mesh):
		_player._held_mesh.queue_free()
		_player._held_mesh = null
	var container_type: String = _player.held_item_data.get("container_type", "")
	var has_liquid: bool = _player.held_item_data.get("has_liquid", false)
	var saved_recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
	var saved_amount: float = _player.held_item_data.get("saved_amount", 0.0)
	var saved_count: int = _player.held_item_data.get("saved_count", 0)
	var new_mesh: Node3D = _create_container_hand_mesh(
		container_type,
		has_liquid,
		saved_recipe,
		saved_amount,
		saved_count,
	)
	if new_mesh:
		_player._held_mesh = new_mesh
		_player.hand_slot.add_child(_player._held_mesh)


func _disable_hand_collision(node: Node) -> void:
	# Recursively disable collision on all physics bodies.
	if node is CollisionObject3D:
		var body: CollisionObject3D = node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_hand_collision(child)


func _hide_ghost_box_ui(node: Node) -> void:
	# Remove labels/icons from box ghosts so only the box is shown.
	if node is Label3D or node is Sprite3D:
		node.visible = false
	for child in node.get_children():
		_hide_ghost_box_ui(child)


func _hide_ghost_container_contents(node: Node) -> void:
	# Hide perishable contents inside bins so the ghost shows only the bin.
	var n := node.name
	if n.begins_with("ItemGrid") or n == "AmountLabel" or n == "price tag":
		node.visible = false
		return
	if (
		n.begins_with("ice cube") or n.begins_with("sugar cube")
		or n.begins_with("lemon") or n.begins_with("strawberry") or n.begins_with("blueberry")
		or n.begins_with("peach") or n.begins_with("watermelon")
	):
		node.visible = false
		return
	if node is MeshInstance3D and n.begins_with("IceCube"):
		node.visible = false
		return
	for child in node.get_children():
		_hide_ghost_container_contents(child)


func _create_ghost(container_type: String) -> void:
	_destroy_ghost()
	var scene: PackedScene = _get_container_scene(container_type)
	if scene == null:
		return
	_ghost = scene.instantiate()
	_ghost.set_meta("ghost_type", "container")
	_ghost.set_meta("container_type", container_type)
	# Apply placement scale so ghost matches final size
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(container_type, Vector3.ONE)
	_ghost.scale = placement_scale
	# Calculate offset based on collision bounds (will be stored in metadata)
	var bottom_offset := _get_container_bottom_offset(_ghost)
	_ghost.set_meta("bottom_offset", bottom_offset * placement_scale.y)
	# Set starting state so the ghost's _ready() shows the correct item
	# count and label, matching what will actually be placed.
	var saved_amount: float = _player.held_item_data.get("saved_amount", 0.0)
	var saved_count: int = _player.held_item_data.get("saved_count", 0)
	_set_container_starting_state(_ghost, container_type, saved_amount, saved_count)
	# Disable all physics on the ghost so it can't collide or be raycast-hit
	_disable_physics(_ghost)
	# Add to ghost group for overlap filtering
	_mark_ghost(_ghost)
	_disable_scripts(_ghost)
	get_tree().current_scene.add_child(_ghost)
	_hide_ghost_box_ui(_ghost)
	_hide_ghost_container_contents(_ghost)
	# Apply ghost material AFTER adding to tree so _ready() side effects
	# (e.g. CSG material setup) don't override the transparent ghost material.
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())
	_ghost.visible = false


func _remove_placement_groups(node: Node) -> void:
	# Hand or ghost meshes must not be counted as real placed objects.
	if not is_instance_valid(node):
		return
	node.remove_from_group("container")
	node.remove_from_group("pitcher")
	node.remove_from_group("press")
	node.remove_from_group("water_dispenser")
	node.remove_from_group("supply_box")


func _mark_ghost(node: Node) -> void:
	node.add_to_group("ghost")
	_remove_placement_groups(node)
	# _ready() may add the node to placement groups after add_child,
	# so remove them again once the tree is done setting up.
	call_deferred("_remove_placement_groups", node)


func _destroy_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_last_ghost_mat = null
	_ghost_valid = false


func _update_cup_box_ghost() -> void:
	# Show ghost preview for cup placement when holding cup box.
	if not _player.ray.is_colliding():
		_destroy_ghost()
		_ghost_valid = false
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()
	var on_surface := _is_placement_surface(collider)

	# If looking at a supply box, stack like other supply boxes.
	var node: Node = collider
	while node != null:
		if node is SupplyBox:
			_update_supply_box_ghost()
			return
		if node is DeliveryGrid:
			_update_grid_ghost(node as DeliveryGrid, hit_point)
			return
		node = node.get_parent()

	# Check if looking at existing cup stack - hide ghost in that case
	var interactable := _player.interaction.get_looked_at_interactable() as Interactable
	if interactable is CupStack:
		_destroy_ghost()
		_ghost_valid = true # Valid to add to existing
		return

	if not on_surface:
		_destroy_ghost()
		_ghost_valid = false
		return

	var is_ground := _is_ground_surface(collider)
	if is_ground:
		# Floor ΓÇö show box ghost but invalid (cup boxes can't go on floor)
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.bottom_offset, 0)
		_ghost.visible = true
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	# Workstation/stand ΓÇö show cup stack ghost
	if _ghost == null or _ghost.get_meta("ghost_type", "") != "cup_stack":
		_destroy_ghost()
		_ghost = CUP_STACK_SCENE.instantiate()
		_ghost.set_meta("ghost_type", "cup_stack")
		var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack")
		_ghost.scale = placement_scale
		var bottom_offset := _get_container_bottom_offset(_ghost)
		_ghost.set_meta("bottom_offset", bottom_offset * placement_scale.y)
		_disable_scripts(_ghost)
		_disable_physics(_ghost)
		_mark_ghost(_ghost)
		_set_single_cup_visibility(_ghost)
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
		get_tree().current_scene.add_child(_ghost)

	_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)

	var overlapping := _check_ghost_overlap()
	_ghost.visible = true

	var valid := on_surface and not overlapping
	if valid != _ghost_valid:
		_ghost_valid = valid
		var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
		_apply_ghost_material(_ghost, mat)


func _update_grid_ghost(grid: DeliveryGrid, hit_point: Vector3) -> void:
	_ensure_box_ghost()
	var cell_idx := grid.get_closest_cell(hit_point)
	var target_id := grid.get_instance_id() + cell_idx
	if target_id != _stack_target_id:
		_stack_target_id = target_id
	_ghost.global_position = grid.get_slot_position(cell_idx)
	_ghost.global_rotation = grid.get_slot_rotation(cell_idx)
	_ghost.visible = true
	_ghost_valid = true
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())


func _update_supply_box_ghost() -> void:
	if _ghost != null and _ghost.get_meta("ghost_type", "") != "box":
		_destroy_ghost()
	if _ghost == null:
		_ghost = SUPPLY_BOX_SCENE.instantiate()
		_ghost.set_meta("ghost_type", "box")
		_disable_scripts(_ghost)
		_disable_physics(_ghost)
		_mark_ghost(_ghost)
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
		_hide_ghost_box_ui(_ghost)
		get_tree().current_scene.add_child(_ghost)

	if not _player.ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		_stack_target_id = -1
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()

	# Check if looking at another SupplyBox ΓÇö stack on top
	var node: Node = collider
	var target_box: SupplyBox = null
	while node != null:
		if node is SupplyBox:
			target_box = _get_topmost_box_in_stack(node as SupplyBox)
			break
		node = node.get_parent()

	if target_box != null and target_box.is_inside_tree():
		target_box.update_metrics()
		var target_id := target_box.get_instance_id()
		if target_id != _stack_target_id:
			_stack_target_id = target_id
			_regenerate_stack_offset()
		var ghost_y := _get_box_stack_y(target_box)
		var stack_base := Vector3(
			target_box.global_position.x,
			ghost_y,
			target_box.global_position.z,
		) + Vector3(0, SupplyBox.stack_height, 0)
		_ghost.global_position = stack_base + _stack_offset
		_ghost.global_rotation = target_box.global_rotation + Vector3(0, _stack_yaw, 0)
		_ghost.visible = true
		_ghost_valid = true
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
		return

	# Check if looking at the delivery grid ΓÇö snap to the nearest cell
	var grid_node: Node = collider
	while grid_node != null:
		if grid_node is DeliveryGrid:
			_update_grid_ghost(grid_node as DeliveryGrid, hit_point)
			return
		grid_node = grid_node.get_parent()

	# Otherwise only show ghost on approved placement surfaces (ground, tables, etc.)
	var on_surface := _is_placement_surface(collider)
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		_stack_target_id = -1
		return

	_stack_target_id = -1
	_ghost.global_position = hit_point + Vector3(0, SupplyBox.bottom_offset, 0)
	_ghost.visible = true
	_ghost_valid = true
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())


func _update_equipment_box_ghost() -> void:
	var equipment_type: String = _player.held_item_data.get("equipment_type", "")
	if equipment_type == "":
		return

	if not _player.ray.is_colliding():
		_destroy_ghost()
		_ghost_valid = false
		_stack_target_id = -1
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()

	# Check if looking at another SupplyBox ΓÇö stack on top (box ghost)
	var node: Node = collider
	while node != null:
		if node is SupplyBox:
			var target_box := _get_topmost_box_in_stack(node as SupplyBox)
			if target_box == null or not target_box.is_inside_tree():
				_ghost.visible = false
				_ghost_valid = false
				_stack_target_id = -1
				return
			target_box.update_metrics()
			var target_id := target_box.get_instance_id()
			if target_id != _stack_target_id:
				_stack_target_id = target_id
				_regenerate_stack_offset()
			_ensure_box_ghost()
			var stack_base := target_box.global_position + Vector3(0, SupplyBox.stack_height, 0)
			_ghost.global_position = stack_base + _stack_offset
			_ghost.global_rotation = target_box.global_rotation + Vector3(0, _stack_yaw, 0)
			_ghost.visible = true
			_ghost_valid = true
			_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			return
		node = node.get_parent()

	# Check if looking at the delivery grid ΓÇö show box ghost on the grid.
	var grid_node: Node = collider
	while grid_node != null:
		if grid_node is DeliveryGrid:
			_update_grid_ghost(grid_node as DeliveryGrid, hit_point)
			return
		grid_node = grid_node.get_parent()

	var on_surface := _is_placement_surface(collider)
	var is_ground := _is_ground_surface(collider)

	# Workstations are tables ΓÇö they can only be placed on the floor.
	if equipment_type == "workstation":
		if not is_ground:
			_destroy_ghost()
			_ghost_valid = false
			_stack_target_id = -1
			return
		_ensure_container_ghost(equipment_type)
		if _ghost == null:
			_ghost_valid = false
			_stack_target_id = -1
			return
		var ws_offset: float = _ghost.get_meta("bottom_offset", 0.0)
		_ghost.global_position = hit_point + Vector3(0, -ws_offset, 0)
		var look_dir := _player.global_position - hit_point
		look_dir.y = 0
		if look_dir.length_squared() > 0.001:
			_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)
		_ghost.visible = true
		_ghost_valid = true
		_stack_target_id = -1
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
		return

	if not on_surface:
		_destroy_ghost()
		_ghost_valid = false
		_stack_target_id = -1
		return

	if is_ground:
		# Floor placement for other equipment ΓÇö just drop the box
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.bottom_offset, 0)
		_ghost.visible = true
		_ghost_valid = true
		_stack_target_id = -1
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
	else:
		# Other equipment on a surface ΓÇö show container ghost
		_ensure_container_ghost(equipment_type)
		if _ghost == null:
			_ghost_valid = false
			_stack_target_id = -1
			return
		var equip_offset: float = _ghost.get_meta("bottom_offset", 0.0)
		_ghost.global_position = hit_point + Vector3(0, -equip_offset, 0)
		var look_dir := _player.global_position - hit_point
		look_dir.y = 0
		if look_dir.length_squared() > 0.001:
			_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)
		_ghost.visible = true
		_ghost_valid = true
		_stack_target_id = -1
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())


func _ensure_box_ghost() -> void:
	if _ghost != null and _ghost.get_meta("ghost_type", "") == "box":
		return
	_destroy_ghost()
	_ghost = SUPPLY_BOX_SCENE.instantiate()
	_ghost.set_meta("ghost_type", "box")
	_disable_scripts(_ghost)
	_disable_physics(_ghost)
	_mark_ghost(_ghost)
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())
	_hide_ghost_box_ui(_ghost)
	get_tree().current_scene.add_child(_ghost)


func _ensure_container_ghost(container_type: String) -> void:
	if _ghost != null and _ghost.get_meta("ghost_type", "") == "container":
		var current_type: String = _ghost.get_meta("container_type", "")
		if current_type == container_type:
			return
	_destroy_ghost()
	var scene: PackedScene = _get_container_scene(container_type)
	if scene == null:
		return
	_ghost = scene.instantiate()
	_ghost.set_meta("ghost_type", "container")
	_ghost.set_meta("container_type", container_type)
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(container_type, Vector3.ONE)
	_ghost.scale = placement_scale
	var bottom_offset := _get_container_bottom_offset(_ghost)
	_ghost.set_meta("bottom_offset", bottom_offset * placement_scale.y)
	_disable_physics(_ghost)
	_mark_ghost(_ghost)
	_disable_scripts(_ghost)
	get_tree().current_scene.add_child(_ghost)
	_hide_ghost_box_ui(_ghost)
	_hide_ghost_container_contents(_ghost)
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())


func _update_ghost() -> void:
	# Bin scoops don't have a placement ghost
	if _player.held_item == HeldItem.SUPPLY_BOX and _player.held_item_data.get("source") == "bin_scoop":
		if _ghost != null:
			_destroy_ghost()
		return
	# Handle cup box ghost preview
	if _player.held_item == HeldItem.SUPPLY_BOX and _player.held_item_data.get("ingredient_type") == "cups":
		_update_cup_box_ghost()
		return
	# Handle single cup ghost preview
	if _player.held_item == HeldItem.CUP_EMPTY or _player.held_item == HeldItem.CUP_FILLED:
		_update_single_cup_ghost()
		return
	# Handle equipment box ΓÇö show container ghost on workstation, box ghost on floor/boxes
	if _player.held_item == HeldItem.SUPPLY_BOX and _player.held_item_data.get(
			"is_equipment",
			false,
		):
		_update_equipment_box_ghost()
		return
	# Handle trash box ghost preview (only for empty box trash)
	if _player.held_item == HeldItem.TRASH \
			and _player.held_item_data.get("trash_type", "") == "empty_box":
		_update_supply_box_ghost()
		return
	if _player.held_item == HeldItem.TRASH:
		_destroy_ghost()
		return
	# Handle generic supply box ghost (non-cup ingredient boxes or any supply box)
	if _player.held_item == HeldItem.SUPPLY_BOX:
		_update_supply_box_ghost()
		return
	if _player.held_item != HeldItem.CONTAINER or _ghost == null:
		return

	# Pitcher snapping to press
	var container_type: String = _player.held_item_data.get("container_type", "")
	if container_type == "pitcher":
		var press := _player.interaction.find_looked_at_press() as Press
		if press != null:
			var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
			_ghost.global_position = press.get_snap_global_position()
			_ghost.visible = true
			if press.can_snap_pitcher(recipe):
				_ghost_valid = true
				_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			else:
				_ghost_valid = false
				_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
			return
		var dispenser := _player.interaction.find_looked_at_dispenser() as WaterDispenser
		if dispenser != null:
			var _recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
			if _ghost == null or _ghost.get_meta("container_type", "") != "pitcher":
				_create_ghost("pitcher")
			if _ghost != null and dispenser.can_snap_pitcher_from_recipe(_recipe):
				_ghost.global_position = dispenser.get_snap_global_position()
				_ghost.visible = true
				_ghost_valid = true
				_apply_ghost_material(_ghost, _get_ghost_mat_valid())
				return
			# Can't snap ΓÇö fall through to normal placement below

	if not _player.ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()
	var _hit_normal := _player.ray.get_collision_normal()
	var from_box: bool = _player.held_item_data.get("from_delivery_box", false)

	# When holding an equipment box, allow stacking on other boxes
	if from_box:
		var node: Node = collider
		while node != null:
			if node is SupplyBox:
				var box := node as SupplyBox
				var box_offset: float = _ghost.get_meta("bottom_offset", 0.0)
				_ghost.global_position = box.global_position + Vector3(0, 0.262 - box_offset, 0)
				_ghost.visible = true
				_ghost_valid = true
				_apply_ghost_material(_ghost, _get_ghost_mat_valid())
				return
			node = node.get_parent()

	# Containers cannot be placed on the delivery grid ΓÇö only boxes can.
	var grid_node: Node = collider
	while grid_node != null:
		if grid_node is DeliveryGrid:
			_ghost.visible = false
			_ghost_valid = false
			return
		grid_node = grid_node.get_parent()

	var on_surface := _is_placement_surface(collider)
	var is_ground := _is_ground_surface(collider)

	# Workstations and water dispensers are floor-standing equipment and can only
	# be placed on the ground. Other containers need an existing stand or
	# workstation surface.
	if container_type == "workstation" or container_type == "water_dispenser":
		if not is_ground:
			_ghost.visible = false
			_ghost_valid = false
			return
	elif not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		return

	_ghost.visible = true
	# Apply collision-based offset so ghost sits on surface
	var offset: float = _ghost.get_meta("bottom_offset", 0.0)
	_ghost.global_position = hit_point + Vector3(0, -offset, 0)
	# Keep ghost upright, face the player
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)

	# Check for overlap with existing containers
	var overlapping := _check_ghost_overlap()
	# Deployed containers (picked up from workstation) can't go on ground,
	# except for workstations and water dispensers, which are floor-standing.
	var deployed: bool = _player.held_item_data.get("deployed", false)
	var valid := (
		not overlapping
		and (
			not (deployed and is_ground) or container_type == "workstation"
			or container_type == "water_dispenser"
		)
	)

	_ghost_valid = valid
	var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
	_apply_ghost_material(_ghost, mat)


func _try_place_container() -> Node3D:
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Can only place on stand or workstation!")
		return null

	var container_type: String = _player.held_item_data.get("container_type", "")
	# Move the existing workstation instead of creating a new one, so attached items follow.
	if container_type == "workstation":
		var source_node: Node3D = _player.held_item_data.get("source_node") as Node3D
		if source_node != null and is_instance_valid(source_node):
			var source_parent: Node = _player.held_item_data.get("source_parent") as Node
			if source_parent != null and is_instance_valid(source_parent):
				source_parent.add_child(source_node)
			else:
				get_tree().current_scene.add_child(source_node)
			source_node.global_transform = _ghost.global_transform
			_enable_physics(source_node)
			# Sync the move + show to clients in a single RPC so the
			# position and visibility are set atomically. This is more
			# reliable than separate move + show RPCs.
			WorldSync.sync_move_and_show(
				source_node,
				source_node.global_position,
				source_node.global_rotation,
				source_node.scale,
				true,
			)
			EventBus.container_placed.emit(container_type, source_node)
			AudioManager.play_sfx("table", source_node.global_position, -1.0, 0.05, 0.85)
			_destroy_ghost()
			_player.inventory.clear_held()
			return source_node
		return null

	var scene_path: String = CONTAINER_SCENE_PATHS.get(container_type, "")
	if scene_path == "":
		return null

	# Restore saved contents (or empty if none)
	var saved_amount: float = _player.held_item_data.get("saved_amount", 0.0)
	var saved_count: int = _player.held_item_data.get("saved_count", 0)
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(container_type, Vector3.ONE)
	var state: Dictionary = {
		"starting_amount": saved_amount,
		"starting_count": saved_count,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
	}
	# Include fruit bin amounts in spawn state so the host (and all
	# clients) receive them. The host applies them after _ready().
	if container_type == "fruit_bin":
		var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
		var amounts: Dictionary = recipe.get("fruit_amounts", { })
		if not amounts.is_empty():
			state["_net_fruit_amounts"] = amounts.duplicate()
	# Include pitcher recipe in spawn state for the same reason.
	if container_type == "pitcher":
		var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
		if not recipe.is_empty():
			state["_net_pitcher_recipe"] = recipe.duplicate()
	var place_pos := _ghost.global_position
	var place_rot := _ghost.global_rotation
	var instance := WorldSync.request_spawn(scene_path, place_pos, place_rot, state) as Node3D
	if instance == null:
		_destroy_ghost()
		_player.inventory.clear_held()
		return null
	instance.scale = placement_scale
	instance.add_to_group("container")
	# Add pitcher to pitcher group for water tap detection
	if instance is Pitcher:
		instance.add_to_group("pitcher")

	# Restore fruit bin amounts after _ready() has run (host only ΓÇö
	# clients receive them via the _net_fruit_amounts spawn state key)
	if container_type == "fruit_bin" and instance is FruitBin:
		var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
		var amounts: Dictionary = recipe.get("fruit_amounts", { })
		if not amounts.is_empty():
			instance.fruit_amounts = amounts.duplicate()
			instance.update_display()
			# Broadcast to clients so they see the restored amounts
			WorldSync.sync_property(instance, "fruit_amounts", instance.fruit_amounts.duplicate(
					true
				))
			WorldSync.sync_call(instance, "update_display")

	# Restore pitcher recipe (always ΓÇö water may have been added while holding)
	if container_type == "pitcher" and instance is Pitcher:
		var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
		instance.fruit_type = recipe.get("fruit_type", "")
		instance.fruit_count = recipe.get("fruit_count", recipe.get("lemons", 0.0))
		instance.sugar = recipe.get("sugar", 0.0)
		instance.ice = recipe.get("ice", 0.0)
		instance.water = recipe.get("water", 0.0)
		instance.cups_poured = recipe.get("cups_poured", 0)
		# Determine state based on contents and cups poured
		if instance.cups_poured > 0:
			# Already serving cups -> SERVING
			instance.state = Pitcher.PitcherState.SERVING
		elif instance.fruit_count > 0.0 and instance.water > 0.0:
			# Has both fruit and water, ready to serve but no cups yet -> COMPLETE
			instance.state = Pitcher.PitcherState.COMPLETE
		else:
			# Missing either fruit or water -> PREPPING
			instance.state = Pitcher.PitcherState.PREPPING
		instance.set_pitcher_visible(true)
		instance.sync_fill_display()
		instance.call_deferred("update_label")
		EventBus.pitcher_state_changed.emit(int(instance.state))

	_destroy_ghost()
	var container_type_str: String = _player.held_item_data.get("container_type", "")
	_player.inventory.clear_held()
	EventBus.container_placed.emit(container_type_str, instance)
	AudioManager.play_sfx(_get_place_sfx_key(container_type_str), place_pos, -1.0, 0.05, 0.85)
	return instance


func _cancel_container_placement() -> void:
	var container_type: String = _player.held_item_data.get("container_type", "")
	var cost := _get_container_cost(container_type)
	# Restore the moved workstation and its attached items to where they were.
	var source_node: Node3D = _player.held_item_data.get("source_node") as Node3D
	if source_node != null and is_instance_valid(source_node):
		var original: Transform3D = (_player.held_item_data.get(
				"source_original_transform",
				source_node.global_transform,
			) as Transform3D)
		var source_parent: Node = _player.held_item_data.get("source_parent") as Node
		if source_node.get_parent() == null:
			if source_parent != null and is_instance_valid(source_parent):
				source_parent.add_child(source_node)
			else:
				get_tree().current_scene.add_child(source_node)
		source_node.global_transform = original
		_enable_physics(source_node)
		# Sync the restore + show to clients in a single RPC
		WorldSync.sync_move_and_show(
			source_node,
			source_node.global_position,
			source_node.global_rotation,
			source_node.scale,
			true,
		)
	_destroy_ghost()
	var refund_value := cost * 0.7
	_player.inventory.make_held_trash(refund_value, container_type)
	EventBus.interaction_hint_changed.emit("Recycled ΓÇö take to trashcan for $%.2f" % refund_value)


func pickup_container(interactable: Interactable, container_type: String) -> void:
	# Workstations are tables ΓÇö keep the original instance so items on top move with it.
	if container_type == "workstation":
		_attach_items_to_workstation(interactable)
		_disable_physics(interactable)
		var source_parent := interactable.get_parent()
		_player.held_item_data["source_parent"] = source_parent
		_player.held_item_data["source_original_transform"] = interactable.global_transform
		# Remember which items got attached so we can sync the attachment
		# to all other peers (host + clients). Without this, only the local
		# player has the items parented to the table.
		var attached_items: Array[Dictionary] = []
		for child in interactable.get_children():
			if child.is_in_group("container"):
				attached_items.append({ "name": child.name, "net_id": WorldSync.get_net_id(child) })
		_player.held_item_data["workstation_attached_items"] = attached_items
		if not attached_items.is_empty():
			WorldSync.sync_workstation_items(interactable.name, attached_items)
		var pickup_pos := interactable.global_position
		source_parent.remove_child(interactable)
		# Hide the workstation on clients (it's "in the player's hands" now)
		WorldSync.sync_hide_object(interactable)
		EventBus.container_picked_up.emit(container_type, interactable)
		AudioManager.play_sfx("table", pickup_pos)
		hold_container(container_type, 0.0, 0, false, { })
		_player.held_item_data["source_node"] = interactable
		_player.held_item_data["deployed"] = true
		return

	# Save container state before picking up
	var saved_amount := 0.0
	var saved_count := 0
	var has_liquid := false
	var saved_recipe := { }
	if "current_amount" in interactable:
		saved_amount = interactable.current_amount
	elif "current_count" in interactable:
		saved_count = interactable.current_count
	# Save pitcher state (always save recipe, even if empty, so water tap can fill it)
	if interactable is Pitcher:
		var pitcher := interactable as Pitcher
		has_liquid = pitcher.get_liquid_volume() > 0.0
		saved_recipe = {
			"fruit_type": pitcher.fruit_type,
			"fruit_count": pitcher.fruit_count,
			"sugar": pitcher.sugar,
			"ice": pitcher.ice,
			"water": pitcher.water,
			"cups_poured": pitcher.cups_poured,
		}
	# Save fruit bin multi-fruit amounts
	if interactable is FruitBin:
		var fbin := interactable as FruitBin
		saved_recipe = { "fruit_amounts": fbin.fruit_amounts.duplicate() }

	EventBus.container_picked_up.emit(container_type, interactable)
	var pickup_key: String = container_type
	if pickup_key == "workstation":
		pickup_key = "table"
	AudioManager.play_sfx(pickup_key, interactable.global_position)
	# Despawn the container on all peers via WorldSync (host authority).
	# This ensures the container is removed for everyone, not just the
	# player who picked it up. Do this BEFORE removing the local copy so
	# WorldSync can still read its original parent path/name.
	WorldSync.request_despawn(interactable)
	# Remove the local container immediately so it can't be interacted with
	# or duplicated while waiting for the host's despawn RPC. Workstations
	# keep their original instance (for attached items); everything else
	# is recreated on placement.
	if container_type != "workstation":
		var ip := interactable.get_parent()
		if ip != null:
			ip.remove_child(interactable)
			interactable.queue_free()
	hold_container(container_type, saved_amount, saved_count, has_liquid, saved_recipe)
	# Mark as deployed (was already placed on a workstation) so it can't go on the floor
	_player.held_item_data["deployed"] = true


func _find_customer_in_ancestors(node: Node) -> Customer:
	var current := node
	while current != null:
		if current is Customer:
			return current as Customer
		current = current.get_parent()
	return null


func _find_pedestrian_in_ancestors(node: Node) -> Pedestrian:
	var current := node
	while current != null:
		if current is Pedestrian:
			return current as Pedestrian
		current = current.get_parent()
	return null


func _get_container_type_for_node(node: Node) -> String:
	if node is IngredientBin:
		var bin := node as IngredientBin
		match bin.ingredient_type:
			"lemon":
				return "fruit_bin"
			"sugar":
				return "sugar_bin"
			"ice":
				return "ice_bin"
	if node is CupStack:
		return "cup_stack"
	if node is Pitcher:
		return "pitcher"
	if node is Press:
		return "press"
	if node is FruitBin:
		return "fruit_bin"
	# WaterDispenser is a fixed appliance ΓÇö it cannot be picked up
	var node_script: Script = node.get_script() as Script
	if node_script != null and node_script.resource_path == "res://scripts/objects/workstation.gd":
		return "workstation"
	return ""


func _is_placement_surface(collider: Object) -> bool:
	if collider == null:
		return false
	if not _player.ray.is_colliding():
		return false
	var normal := _player.ray.get_collision_normal()
	if normal.y <= 0.7:
		return false
	var node := collider as Node
	if node == null:
		return false
	# Check the collider itself and up to 2 parents for placement_surface group
	for i in range(3):
		if node.is_in_group("placement_surface"):
			return true
		node = node.get_parent()
		if node == null:
			break
	return false


func _is_ground_surface(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	for i in range(3):
		var lower: String = node.name.to_lower()
		if "ground" in lower or "floor" in lower or "sidewalk" in lower:
			return true
		node = node.get_parent()
		if node == null:
			break
	return false


func _get_container_cost(container_type: String) -> float:
	match container_type:
		"fruit_bin":
			return Balancing.CONTAINER_COST_FRUIT_BIN
		"sugar_bin":
			return Balancing.CONTAINER_COST_SUGAR_BIN
		"ice_bin":
			return Balancing.CONTAINER_COST_ICE_BIN
		"cup_stack":
			return Balancing.CONTAINER_COST_CUP_STACK
		"pitcher":
			return Balancing.CONTAINER_COST_PITCHER
		"press":
			return Balancing.CONTAINER_COST_PRESS
		"water_dispenser":
			return Balancing.CONTAINER_COST_WATER_DISPENSER
		"workstation":
			return Balancing.CONTAINER_COST_WORKSTATION
	return 0.0


func _set_single_cup_visibility(node: Node) -> void:
	# Show only the first cup in a cup stack (for ghost preview).
	var item_grid := node.get_node_or_null("ItemGrid")
	if item_grid == null:
		return
	# Hide all cups except Cup1
	for i in range(2, 11): # Cup2 through Cup10
		var cup := item_grid.get_node_or_null("Cup%d" % i)
		if cup:
			cup.visible = false


func _get_ghost_mat_valid() -> StandardMaterial3D:
	if _ghost_mat_valid == null:
		_ghost_mat_valid = StandardMaterial3D.new()
		_ghost_mat_valid.albedo_color = Color(0.2, 1.0, 0.3, 0.35)
		_ghost_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat_valid.no_depth_test = true
	return _ghost_mat_valid


func _get_ghost_mat_invalid() -> StandardMaterial3D:
	if _ghost_mat_invalid == null:
		_ghost_mat_invalid = StandardMaterial3D.new()
		_ghost_mat_invalid.albedo_color = Color(1.0, 0.2, 0.2, 0.35)
		_ghost_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_mat_invalid.no_depth_test = true
	return _ghost_mat_invalid


func _check_ghost_overlap() -> bool:
	# Check if ghost overlaps with any existing placed containers using actual collision shapes.
	if _ghost == null:
		return false

	# Get ghost's collision shape and _player.transform
	var ghost_shape := _get_collision_shape(_ghost)
	if ghost_shape == null:
		return false
	var ghost_transform := _ghost.global_transform
	var ghost_bounds_radius := _get_shape_radius(ghost_shape) * maxf(
		ghost_transform.basis.get_scale().x,
		ghost_transform.basis.get_scale().z,
	)
	var ghost_origin := ghost_transform.origin
	var max_check_dist := ghost_bounds_radius + 2.0

	# Check against all placed containers
	for node in get_tree().get_nodes_in_group("container"):
		if node == _ghost:
			continue
		if node.is_in_group("ghost"):
			continue # Skip other ghosts
		if not (node is Node3D):
			continue

		var other_node := node as Node3D
		var other_origin := other_node.global_position
		if ghost_origin.distance_to(other_origin) > max_check_dist:
			continue

		# Get this container's collision shape
		var other_shape := _get_collision_shape(node)
		if other_shape == null:
			continue

		var other_transform := (node as Node3D).global_transform

		# Check intersection based on shape type
		if ghost_shape is BoxShape3D and other_shape is BoxShape3D:
			if _boxes_intersect(ghost_shape, ghost_transform, other_shape, other_transform):
				return true
		elif ghost_shape is CylinderShape3D and other_shape is CylinderShape3D:
			if _cylinders_intersect(ghost_shape, ghost_transform, other_shape, other_transform):
				return true
		else:
			# Fallback to sphere approximation using shape extents
			var ghost_radius := _get_shape_radius(ghost_shape) * maxf(
				ghost_transform.basis.get_scale().x,
				ghost_transform.basis.get_scale().z,
			)
			var other_radius := _get_shape_radius(other_shape) * maxf(
				other_transform.basis.get_scale().x,
				other_transform.basis.get_scale().z,
			)
			var dist := ghost_transform.origin.distance_to(other_transform.origin)
			if dist < (ghost_radius + other_radius):
				return true

	return false


func _get_collision_shape(node: Node) -> Shape3D:
	if node.has_meta("cached_collision_shape"):
		return node.get_meta("cached_collision_shape")
	var found := _find_collision_shape(node)
	if found != null:
		node.set_meta("cached_collision_shape", found)
	return found


func _find_collision_shape(node: Node) -> Shape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape
		var found := _find_collision_shape(child)
		if found != null:
			return found
	return null


func _get_shape_radius(shape: Shape3D) -> float:
	# Get approximate radius for a shape.
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return maxf(size.x, size.z) * 0.5
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	return 0.5


func _boxes_intersect(
	a: BoxShape3D,
	a_transform: Transform3D,
	b: BoxShape3D,
	b_transform: Transform3D,
) -> bool:
	# Check if two oriented boxes intersect using AABB approximation.
	# Simple AABB check in world space
	var a_pos := a_transform.origin
	var a_scale := a_transform.basis.get_scale()
	var a_size := Vector3(a.size.x * a_scale.x, a.size.y * a_scale.y, a.size.z * a_scale.z)

	var b_pos := b_transform.origin
	var b_scale := b_transform.basis.get_scale()
	var b_size := Vector3(b.size.x * b_scale.x, b.size.y * b_scale.y, b.size.z * b_scale.z)

	# Check X, Y, Z overlap with small buffer
	var buffer := 0.02
	if absf(a_pos.x - b_pos.x) > (a_size.x + b_size.x) * 0.5 + buffer:
		return false
	if absf(a_pos.y - b_pos.y) > (a_size.y + b_size.y) * 0.5 + buffer:
		return false
	if absf(a_pos.z - b_pos.z) > (a_size.z + b_size.z) * 0.5 + buffer:
		return false
	return true


func _cylinders_intersect(
	a: CylinderShape3D,
	a_transform: Transform3D,
	b: CylinderShape3D,
	b_transform: Transform3D,
) -> bool:
	# Check if two cylinders intersect (horizontal distance check).
	var a_pos := a_transform.origin
	var b_pos := b_transform.origin
	var a_scale := a_transform.basis.get_scale()
	var b_scale := b_transform.basis.get_scale()
	var a_radius := a.radius * maxf(a_scale.x, a_scale.z)
	var b_radius := b.radius * maxf(b_scale.x, b_scale.z)
	var buffer := 0.02

	# Horizontal distance
	var dx := a_pos.x - b_pos.x
	var dz := a_pos.z - b_pos.z
	var dist := sqrt(dx * dx + dz * dz)

	if dist > a_radius + b_radius + buffer:
		return false

	# Vertical overlap check
	var a_height := a.height * a_scale.y
	var b_height := b.height * b_scale.y
	if absf(a_pos.y - b_pos.y) > (a_height + b_height) * 0.5 + buffer:
		return false

	return true


func _apply_ghost_material(node: Node, mat: StandardMaterial3D) -> void:
	if mat == _last_ghost_mat:
		return
	_last_ghost_mat = mat
	_do_apply_ghost_material(node, mat)


func _do_apply_ghost_material(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	elif node is CSGShape3D:
		(node as CSGShape3D).material_override = mat
	for child in node.get_children():
		_do_apply_ghost_material(child, mat)


func _disable_scripts(node: Node) -> void:
	node.set_script(null)
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_scripts(child)


func _disable_physics(node: Node) -> void:
	if node is StaticBody3D:
		(node as StaticBody3D).collision_layer = 0
		(node as StaticBody3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_disable_physics(child)


func _enable_physics(node: Node) -> void:
	if node is StaticBody3D:
		(node as StaticBody3D).collision_layer = 1
		(node as StaticBody3D).collision_mask = 1
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = false
	for child in node.get_children():
		_enable_physics(child)


func _attach_items_to_workstation(workstation: Node) -> void:
	var table_pos := (workstation as Node3D).global_position
	for item in get_tree().get_nodes_in_group("container"):
		if not is_instance_valid(item):
			continue
		if item == workstation or workstation.is_ancestor_of(item):
			continue
		if not item is Node3D:
			continue
		# Only attach items that are direct children of the world root
		# or WorldObjects ΓÇö not items already parented to another
		# workstation or the player.
		var parent := (item as Node).get_parent()
		if parent == null:
			continue
		if parent != get_tree().current_scene and parent.name != "WorldObjects":
			continue
		var pos := (item as Node3D).global_position
		if pos.y < table_pos.y + 0.8 or pos.y > table_pos.y + 1.5:
			continue
		if absf(pos.x - table_pos.x) > 1.0 or absf(pos.z - table_pos.z) > 1.0:
			continue
		(item as Node3D).reparent(workstation, true)
