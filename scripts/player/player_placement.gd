class_name PlayerPlacement
extends Node
## Handles placement ghost visualization and placement/drop logic for held items.

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if _player == null:
		push_warning("PlayerPlacement: parent is not a Player")


## Local-player placement init: precompute shared box metrics and load the
## workstation scene at runtime (avoiding compile-time preload issues while
## the editor reimports .uid files). Called from Player.configure_local_player.
func configure_local_player() -> void:
	var temp_box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
	temp_box.update_metrics()
	temp_box.free()
	_workstation_scene = load("res://scenes/stand/workstation.tscn") as PackedScene


## Public entry point used by PlayerController._process to refresh the ghost.
func update_ghost() -> void:
	if (
		_ghost_suppressed and _player.camera != null
		and _player.camera.global_basis.get_rotation_quaternion().angle_to(_ghost_suppress_quat)
		> GHOST_SUPPRESS_ANGLE
	):
		_ghost_suppressed = false
	_update_ghost()
	# Green-or-nothing: an invalid placement shows no ghost at all. The
	# red blob read as an error whenever the player aimed at a machine or
	# crate to deposit — a context where they never meant to place. No
	# ghost already means "can't place here", and clicking still prints
	# the reason.
	if _ghost != null and not _ghost_valid:
		_ghost.visible = false
	if _ghost_suppressed and _ghost != null:
		_ghost.visible = false


const HINT_GROUND := "Aim at ground to place"
const HINT_STAND := "Aim at stand or table to place"
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
## Player-controlled rotation applied on top of the auto-facing yaw —
## mouse wheel turns the placement ghost 15 degrees per notch.
var _ghost_yaw_offset: float = 0.0
const GHOST_ROTATE_STEP := PI / 12.0

# --- Cached probe results ---
# When _probe_tabletop_below() finds a valid surface, these store the
# corrected hit point and normal so _update_ghost() can position the
# ghost on the tabletop instead of the side hit point.
var _probe_hit_point: Vector3 = Vector3.ZERO
var _probe_hit_normal: Vector3 = Vector3.UP
var _has_probe_hit: bool = false
var _resolved_ground_surface: Node = null

const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")

const CONTAINER_SCENES: Dictionary = {
	"fruit_bin": preload("res://scenes/objects/fruit_bin.tscn"),
	"sugar_bin": preload("res://scenes/objects/sugar_bin.tscn"),
	"ice_bin": preload("res://scenes/objects/ice_bin.tscn"),
	"cup_stack": CUP_STACK_SCENE,
	"pitcher": preload("res://scenes/objects/pitcher.tscn"),
	"press": preload("res://scenes/objects/press.tscn"),
	"water_dispenser": preload("res://scenes/objects/water_dispenser.tscn"),
	"cup_tray": preload("res://scenes/objects/cup_tray.tscn"),
	"lemonader": preload("res://scenes/objects/lemonader.tscn"),
	"fruitomatic": preload("res://scenes/objects/fruitomatic.tscn"),
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
	"cup_tray": "res://scenes/objects/cup_tray.tscn",
	"lemonader": "res://scenes/objects/lemonader.tscn",
	"fruitomatic": "res://scenes/objects/fruitomatic.tscn",
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
	"pitcher": Vector3.ONE * 0.1008,
	"press": Vector3.ONE * 0.07,
	"water_dispenser": Vector3.ONE * 0.25,
	"workstation": Vector3.ONE,
	"cup_tray": Vector3.ONE,
	"lemonader": Vector3.ONE * 1.3,
	"fruitomatic": Vector3.ONE * 1.3,
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
	"pitcher": Vector3.ONE * 0.0512,
	"press": Vector3.ONE * 0.035,
	"water_dispenser": Vector3.ONE * 0.08,
	"workstation": Vector3.ONE * 0.05,
	"cup_tray": Vector3.ONE * 0.4,
	"lemonader": Vector3.ONE * 0.08,
	"fruitomatic": Vector3.ONE * 0.08,
}


func _get_container_bottom_offset(node: Node, parent_y: float = 0.0) -> float:
	# Calculate how far the collision extends below the node's origin.
	if node == null:
		return 0.0
	if node is Lemonader:
		return node.placement_bottom_offset()
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


func held_pitcher_has_contents() -> bool:
	var recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
	return (
		recipe.get("fruit_count", recipe.get("lemons", 0.0)) > 0.0 or recipe.get("water", 0.0) > 0.0
		or recipe.get("sugar", 0.0) > 0.0 or recipe.get("ice", 0.0) > 0.0
	)


func empty_held_pitcher() -> void:
	## Dumps out whatever's currently in the held pitcher. Keeps the pitcher
	## itself held ΓÇö only clears its contents.
	if not held_pitcher_has_contents():
		EventBus.interaction_hint_changed.emit("Pitcher is already empty!")
		return

	_player.held_item_data["saved_recipe"] = { }
	_player.held_item_data["has_liquid"] = false

	if _player.inventory.get_hand_mesh() is Pitcher:
		var held_pitcher := _player.inventory.get_hand_mesh() as Pitcher
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
	if (
		not _player.ray.is_colliding()
		or not is_stand_or_workstation_surface(_player.ray.get_collider())
	):
		return
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
	var temp_stack := CUP_STACK_SCENE.instantiate() as Node3D
	var bottom_offset := _get_container_bottom_offset(temp_stack) * placement_scale.y
	temp_stack.free()
	var stack_pos := place_point + Vector3(0, -bottom_offset, 0)
	var look_dir := _player.global_position - place_point
	look_dir.y = 0
	var stack_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		stack_rot.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

	var state: Dictionary = {
		"starting_count": 1,
		"max_capacity": 10,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
		"_net_place_fx": true,
	}
	# Ownership follows the stand the item lands on, not the placer.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	var stack := WorldSync.request_spawn(
		"res://scenes/objects/cup_stack.tscn",
		stack_pos,
		stack_rot,
		state,
	) as CupStack
	if stack:
		stack.scale = placement_scale
		WorldSync.play_place_pop(stack)
		stack.add_to_group("container")

	# Deduct one cup from held box
	_player.inventory.update_held_amount(float(qty - 1))
	if qty - 1 <= 0:
		_player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")

	# Remember this brand-new stack as the rapid-fire target so holding the
	# mouse down keeps depositing into it, even before the raycast has had a
	# chance to register its freshly-added (and quite small) collider.
	if stack:
		_player.interaction.set_rapid_fire_cup_target(stack)
		AudioManager.play_sfx(
			_get_place_sfx_key("cup_stack"),
			stack.global_position,
			-1.0,
			0.05,
			0.85,
		)
	suppress_ghost_until_look()
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
	# Cups can only be placed on stand/workstation surfaces, not sidewalks
	# or other generic placement surfaces outside the stand area.
	var on_surface := is_stand_or_workstation_surface(collider)
	var hit_point := _player.ray.get_collision_point()

	# Check if looking at existing cup stack
	var interactable := _player.interaction.get_looked_at_interactable() as Interactable
	if interactable is CupStack and _player.held_item == HeldItem.CUP_EMPTY:
		var stack := interactable as CupStack
		var can_add := stack.current_count < stack.max_capacity and stack.can_player_use(_player)
		_ghost.global_transform = stack.global_transform
		var preview_grid := _ghost.get_node_or_null("ItemGrid") as Node3D
		if preview_grid != null and preview_grid.get_child_count() > 0:
			var preview_cup := preview_grid.get_child(0) as Node3D
			if preview_cup != null:
				var target := stack.get_next_cup_global_transform()
				_ghost.global_position += target.origin - preview_cup.global_position
		_ghost.visible = true
		_ghost_valid = can_add
		_apply_ghost_material(
			_ghost,
			_get_ghost_mat_valid() if can_add else _get_ghost_mat_invalid(),
		)
		return

	# Only show ghost when on valid placement surface
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	# Cross-stand placement restriction: cups can only be placed on surfaces
	# owned by the player's assigned stand.
	if not _is_placement_allowed_on(collider):
		_ghost.visible = false
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	# Cups can't go on the ground — counters and workstation tops only.
	# Applies to empty and filled cups alike.
	var is_ground := is_ground_surface(collider)
	if is_ground:
		_ghost.visible = true
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
		return

	_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

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
	# Use the actual bottom offset computed for the ghost so the stack sits
	# exactly on the surface instead of sinking or floating.
	var bottom_offset: float = _ghost.get_meta("bottom_offset", 0.0)
	var stack_pos := hit_point + Vector3(0, -bottom_offset, 0)
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	var stack_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		stack_rot.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

	var state: Dictionary = {
		"starting_count": 1,
		"max_capacity": 10,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
		"_net_place_fx": true,
	}
	# Ownership follows the stand the item lands on, not the placer.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	var stack := WorldSync.request_spawn(
		"res://scenes/objects/cup_stack.tscn",
		stack_pos,
		stack_rot,
		state,
	) as CupStack
	if stack:
		stack.scale = placement_scale
		WorldSync.play_place_pop(stack)
		stack.add_to_group("container")

	_finish_place()
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
	# Use the actual bottom offset computed for the ghost so the cup sits
	# exactly on the surface instead of sinking or floating.
	var bottom_offset: float = _ghost.get_meta("bottom_offset", 0.0)
	var cup_pos := hit_point + Vector3(0, -bottom_offset, 0)
	# Face the player
	var look_dir := _player.global_position - hit_point
	look_dir.y = 0
	var cup_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		cup_rot.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

	var state: Dictionary = {
		"recipe": recipe,
		"fill_color": recipe.get("color", Color(1.0, 0.9, 0.3, 1.0)),
		"state": Cup.CupState.FILLED,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
		"_net_place_fx": true,
	}
	var cup_scene_path := "res://scenes/objects/cup.tscn"
	var cup := WorldSync.request_spawn(cup_scene_path, cup_pos, cup_rot, state) as Cup
	if cup:
		cup.scale = placement_scale
		WorldSync.play_place_pop(cup)
		cup.add_to_group("container")
		# Ensure collision is active and on the _player.interaction layer
		if cup.physics != null:
			cup.physics.collision_layer = 1
			cup.physics.collision_mask = 1
			for child in cup.physics.get_children():
				if child is CollisionShape3D:
					child.disabled = false

	_finish_place()
	_player.inventory.clear_held()
	AudioManager.play_sfx("taking_cup", cup_pos)
	EventBus.interaction_hint_changed.emit("Filled cup placed!")
	EventBus.container_placed.emit("filled_cup", cup)


## Lift the cup so the bottom of its merged visual bounds rests on
## surface_y. The GLB pivot is mid-cup, so a raw spawn sinks it halfway
## into the tray/surface.
func _seat_cup_on(cup: Node3D, surface_y: float) -> void:
	var found := false
	var aabb := AABB()
	for n in cup.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var wa := mi.global_transform * mi.get_aabb()
		aabb = wa if not found else aabb.merge(wa)
		found = true
	if found:
		cup.global_position.y += surface_y - aabb.position.y


func _place_cup_on_tray(tray: CupTray) -> void:
	# Snap the held cup (empty or filled) into the tray's first free slot.
	var spot := tray.free_slot_position()
	if spot == Vector3.INF:
		EventBus.interaction_hint_changed.emit("Tray is full!")
		return

	var filled := _player.held_item == HeldItem.CUP_FILLED
	var recipe: Dictionary = _player.held_item_data.get("recipe", { })
	var placement_scale := Vector3.ONE * 0.03
	var look_dir := _player.global_position - spot
	look_dir.y = 0
	var cup_rot := Vector3.ZERO
	if look_dir.length_squared() > 0.001:
		cup_rot.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

	var state: Dictionary = {
		"state": Cup.CupState.FILLED if filled else Cup.CupState.EMPTY,
		"_net_groups": ["container"],
		"_net_scale": placement_scale,
		"_net_place_fx": true,
	}
	if filled:
		state["recipe"] = recipe
		state["fill_color"] = recipe.get("color", Color(1.0, 0.9, 0.3, 1.0))
	var cup := WorldSync.request_spawn("res://scenes/objects/cup.tscn", spot, cup_rot, state) as Cup
	if cup:
		cup.scale = placement_scale
		cup.add_to_group("container")
		if cup.physics != null:
			cup.physics.collision_layer = 1
			cup.physics.collision_mask = 1
			for child in cup.physics.get_children():
				if child is CollisionShape3D:
					child.disabled = false
		# Seat BEFORE the pop — the pop tween resets scale to ~zero,
		# which would shrink the measured AABB and zero out the lift.
		_seat_cup_on(cup, spot.y)
		# The spawn broadcast carried the unseated marker position —
		# push the corrected transform so clients see the same seat.
		WorldSync.sync_move_and_show(cup, cup.global_position, cup.global_rotation, cup.scale, true)
		WorldSync.play_place_pop(cup)

	_finish_place()
	_player.inventory.clear_held()
	AudioManager.play_sfx("taking_cup", spot)
	EventBus.interaction_hint_changed.emit("Cup placed on tray!")
	EventBus.container_placed.emit("filled_cup" if filled else "cup", cup)


func _place_held_supply_box_on(
	place_pos: Vector3,
	place_rot: Vector3 = Vector3.ZERO,
	extra_state: Dictionary = { },
) -> SupplyBox:
	# The ghost is the source of truth for free placement — if a preview is
	# showing red (footprint overlaps a palette, another box, etc.) the
	# click must be rejected, not just recolored.
	if _ghost != null and not _ghost_valid:
		return null
	var state: Dictionary = extra_state.duplicate()
	state["_net_place_fx"] = true
	if _player.held_item_data.get("is_equipment", false):
		state["is_equipment"] = true
		state["equipment_type"] = _player.held_item_data.get("equipment_type", "")
	else:
		state["ingredient_type"] = _player.held_item_data.get("ingredient_type", "lemon")
		state["quantity"] = _player.held_item_data.get("amount", 1.0)
	# Box ownership follows the stand's surface it lands on.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		place_pos,
		place_rot,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
		# Adjust Y so the visual bottom sits on the surface, not the
		# root origin which may be above the visual bottom.
		var y_diff := box.bottom_offset - SupplyBox.DEFAULT_BOTTOM_OFFSET
		box.global_position.y += y_diff
		WorldSync.play_place_pop(box)
	AudioManager.play_sfx("box_drop", place_pos)
	_finish_place()
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
		if dx < base.stack_radius and dz < base.stack_radius:
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


func _get_bottom_box_in_stack(base: SupplyBox) -> SupplyBox:
	if not is_instance_valid(base) or not base.is_inside_tree():
		return base
	var bottom := base
	var bottom_y := _get_box_stack_y(base)
	var base_pos := base.global_position
	for node in get_tree().get_nodes_in_group("supply_box"):
		if not is_instance_valid(node) or node == base:
			continue
		var box := node as SupplyBox
		if box == null or not box.is_inside_tree():
			continue
		var dx := absf(box.global_position.x - base_pos.x)
		var dz := absf(box.global_position.z - base_pos.z)
		if dx < base.stack_radius and dz < base.stack_radius:
			var box_y := _get_box_stack_y(box)
			if box_y < bottom_y:
				bottom = box
				bottom_y = box_y
	return bottom


## A stack is only as placeable as the surface its bottom box rests on.
## Upper boxes carry no stand_owner and their ray hit point sits too high
## for is_ground_surface's 1m probe to reach the palette, so surface checks
## against the hovered box fail for box 3+ of a stack.
func _stack_base_is_placeable(hit_box: SupplyBox) -> bool:
	var bottom := _get_bottom_box_in_stack(hit_box)
	if bottom == null:
		return false
	# Stacks rooted on a delivery grid cell are always valid.
	if bottom.has_meta("delivery_cell_idx"):
		return true
	if _get_placement_owner_stand(bottom) != "":
		return true
	# Probe below the stack base, same mask/reach as is_ground_surface but
	# starting from the bottom box instead of the (much higher) ray hit.
	var from := bottom.global_position + Vector3.UP * 0.25
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5, 8)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider", null)
	while node != null:
		if node.name == "PlacableFloor" or node is DeliveryGrid:
			return true
		node = node.get_parent()
	return false


## Boxes may only rest on the palette floor — the collider itself (or an
## ancestor) must literally be PlacableFloor. Unlike is_ground_surface
## there is no downward probe: props like price boards and dispensers
## must never borrow the floor beneath them and let a box float on their
## side face.
func _is_box_floor_hit(collider: Object) -> bool:
	var node := collider as Node
	while node != null:
		if node.name == "PlacableFloor":
			return true
		node = node.get_parent()
	return false


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


func is_aiming_at_grid() -> bool:
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
	if not is_any_stand_surface(grid):
		return
	var cell_idx := grid.get_closest_cell(hit_point)
	if cell_idx < 0:
		_drop_held_box()
		return
	var slot := grid.reserve_slot(cell_idx)
	var grid_path := str(grid.get_path())
	# Pass delivery grid metas through spawn state so clients also get them.
	var extra_state := { "_net_delivery_cell_idx": cell_idx, "_net_delivery_grid_path": grid_path }
	var box := _place_held_supply_box_on(slot["position"], slot["rotation"], extra_state)
	if box == null:
		# Ghost rejected the placement — undo the reservation so the cell
		# doesn't stay taken forever.
		grid.release_slot_index(cell_idx)
		return
	box.set_meta("delivery_cell_idx", cell_idx)
	box.set_meta("delivery_grid_path", grid.get_path())


func _place_held_supply_box_on_stack(root: SupplyBox) -> void:
	if not _stack_base_is_placeable(root):
		return
	root.update_metrics()
	var top := _get_topmost_box_in_stack(root)
	top.update_metrics()
	if top.get_instance_id() != _stack_target_id:
		_stack_target_id = top.get_instance_id()
		_regenerate_stack_offset()
	var top_y := _get_box_stack_y(top)
	var place_pos := Vector3(top.global_position.x, top_y, top.global_position.z) + Vector3(
		0,
		top.stack_height,
		0,
	) + _stack_offset
	var place_rot := top.global_rotation + Vector3(0, _stack_yaw + _ghost_yaw_offset, 0)
	# Inherit delivery grid metas from the box we're stacking on so the
	# new box also knows which grid slot it belongs to.
	var cell_idx: int = top.get_meta("delivery_cell_idx", -1) as int
	var extra_state: Dictionary = { }
	if cell_idx >= 0:
		var grid := _get_delivery_grid()
		if grid != null:
			grid.reserve_slot(cell_idx)
			extra_state["_net_delivery_cell_idx"] = cell_idx
			extra_state["_net_delivery_grid_path"] = str(grid.get_path())
	var box := _place_held_supply_box_on(place_pos, place_rot, extra_state)
	if box == null:
		if cell_idx >= 0:
			var grid2 := _get_delivery_grid()
			if grid2 != null:
				grid2.release_slot_index(cell_idx)
		return
	if cell_idx >= 0:
		box.set_meta("delivery_cell_idx", cell_idx)
		var grid := _get_delivery_grid()
		if grid != null:
			box.set_meta("delivery_grid_path", grid.get_path())


func _drop_held_box() -> void:
	var state: Dictionary = { "_net_place_fx": true }
	if _player.held_item_data.get("is_equipment", false):
		state["is_equipment"] = true
		state["equipment_type"] = _player.held_item_data.get("equipment_type", "")
	else:
		state["ingredient_type"] = _player.held_item_data.get("ingredient_type", "lemon")
		state["quantity"] = _player.held_item_data.get("amount", 1.0)
	# Box ownership follows the stand's surface it lands on.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	# Drop exactly where the raycast hits, or 0.8 m ahead if not hitting anything.
	var drop_pos: Vector3
	if _player.ray.is_colliding():
		drop_pos = _player.ray.get_collision_point() + Vector3(
			0,
			SupplyBox.DEFAULT_BOTTOM_OFFSET,
			0,
		)
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
		# Adjust Y so the visual bottom sits on the surface, not the
		# root origin which may be above the visual bottom.
		var y_diff := box.bottom_offset - SupplyBox.DEFAULT_BOTTOM_OFFSET
		box.global_position.y += y_diff
		WorldSync.play_place_pop(box)
	AudioManager.play_sfx("box_drop", drop_pos)
	_finish_place()
	_player.inventory.clear_held()


## Host-side: drop the carried box on nearby clear ground when the player
## is knocked down (thrown trash hit), so stolen goods spill loose before
## the thief can reach their stand. Only runs on the host.
func drop_held_box_on_stun() -> void:
	if not WorldSync.is_host():
		return
	var data: Dictionary = _player.held_item_data
	var state: Dictionary = { }
	match _player.held_item:
		HeldItem.SUPPLY_BOX:
			if data.get("is_equipment", false):
				state["is_equipment"] = true
				state["equipment_type"] = data.get("equipment_type", "")
			else:
				state["ingredient_type"] = data.get("ingredient_type", "lemon")
				state["quantity"] = data.get("amount", 1.0)
			var original_owner: String = data.get("box_stand_owner", "")
			if original_owner != "":
				state["stand_owner"] = original_owner
		HeldItem.TRASH:
			if data.get("trash_type", "") != "empty_box":
				return
			state["is_trash_box"] = true
			state["ingredient_type"] = "trash"
			state["quantity"] = 0.0
			state["trash_value"] = data.get("trash_value", 0.0)
			state["trash_type"] = "empty_box"
		_:
			return
	var drop_pos := _find_stun_drop_position()
	var box := WorldSync.spawn_networked(
		"res://scenes/objects/supply_box.tscn",
		WorldSync.get_world_objects(),
		drop_pos,
		Vector3(0.0, randf() * TAU, 0.0),
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
		var y_diff := box.bottom_offset - SupplyBox.DEFAULT_BOTTOM_OFFSET
		box.global_position.y += y_diff
	AudioManager.play_sfx("box_drop", drop_pos)
	# The owning client clears its real inventory + hand mesh via the RPC;
	# its set_held(NONE) mirrors the cleared state back to the host.
	_player.clear_held_stun()


## Find a clear, flat spot near the player to drop a knocked-loose box.
## Rays down at ring offsets around the player, then shape-tests the box
## footprint so it can't clip into props, walls, or other bodies.
func _find_stun_drop_position() -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	var origin := _player.global_position
	var probe := Vector3(0.85, 0.55, 0.7) # supply box footprint, padded
	var shape := BoxShape3D.new()
	shape.size = probe
	var exclude: Array[RID] = [_player.get_rid()]
	for radius in [1.0, 1.6, 2.2]:
		for i in 8:
			var angle := TAU * float(i) / 8.0 + randf() * 0.4
			var cand: Vector3 = origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var ray_q := PhysicsRayQueryParameters3D.create(
				cand + Vector3.UP * 2.5,
				cand + Vector3.DOWN * 4.5,
			)
			ray_q.exclude = exclude
			var hit := space.intersect_ray(ray_q)
			if hit.is_empty() or hit.normal.y < 0.8:
				continue
			var ground: Vector3 = hit.position
			var shape_q := PhysicsShapeQueryParameters3D.new()
			shape_q.shape = shape
			shape_q.transform = Transform3D(Basis(), ground + Vector3.UP * (probe.y * 0.5 + 0.03))
			shape_q.exclude = exclude
			if space.intersect_shape(shape_q, 1).is_empty():
				return ground + Vector3(0.0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0.0)
	# No clear ring found — drop at the player's feet.
	return origin + Vector3(0.8, 0.3, 0.0) + Vector3(0.0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0.0)


func _drop_trash(place_pos: Vector3 = Vector3.ZERO) -> void:
	var state: Dictionary = {
		"is_trash_box": true,
		"ingredient_type": "trash",
		"quantity": 0.0,
		"trash_value": _player.held_item_data.get("trash_value", 0.0),
		"trash_type": _player.held_item_data.get("trash_type", "empty_box"),
		"_net_place_fx": true,
	}
	var drop_pos: Vector3
	if place_pos != Vector3.ZERO:
		drop_pos = place_pos
	elif _player.ray.is_colliding() and is_box_placeable_surface(_player.ray.get_collider()):
		drop_pos = _player.ray.get_collision_point() + Vector3(
			0,
			SupplyBox.DEFAULT_BOTTOM_OFFSET,
			0,
		)
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
		# Adjust Y so the visual bottom sits on the surface, not the
		# root origin which may be above the visual bottom.
		var y_diff := box.bottom_offset - SupplyBox.DEFAULT_BOTTOM_OFFSET
		box.global_position.y += y_diff
		WorldSync.play_place_pop(box)
	AudioManager.play_sfx("box_drop", drop_pos)
	_finish_place()
	_player.inventory.clear_held()


## Place a held trash box (empty_box) on top of an existing supply box stack.
## Behaves like _place_held_supply_box_on_stack but spawns a trash box.
func _place_held_trash_box_on_stack(root: SupplyBox) -> void:
	root.update_metrics()
	var top := _get_topmost_box_in_stack(root)
	top.update_metrics()
	if top.get_instance_id() != _stack_target_id:
		_stack_target_id = top.get_instance_id()
		_regenerate_stack_offset()
	var top_y := _get_box_stack_y(top)
	var place_pos := Vector3(top.global_position.x, top_y, top.global_position.z) + Vector3(
		0,
		top.stack_height,
		0,
	) + _stack_offset
	var place_rot := top.global_rotation + Vector3(0, _stack_yaw + _ghost_yaw_offset, 0)
	var state: Dictionary = {
		"is_trash_box": true,
		"ingredient_type": "trash",
		"quantity": 0.0,
		"trash_value": _player.held_item_data.get("trash_value", 0.0),
		"trash_type": _player.held_item_data.get("trash_type", "empty_box"),
		"stack_base_id": top.get_instance_id(),
		"_net_place_fx": true,
	}
	# Inherit delivery grid metas from the box we're stacking on.
	if top.has_meta("delivery_grid_path"):
		state["delivery_grid_path"] = top.get_meta("delivery_grid_path")
	if top.has_meta("delivery_cell_idx"):
		state["delivery_cell_idx"] = top.get_meta("delivery_cell_idx")
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		place_pos,
		place_rot,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
		WorldSync.play_place_pop(box)
	AudioManager.play_sfx("box_drop", place_pos)
	_finish_place()
	_player.inventory.clear_held()


## Place a held trash box (empty_box) on a delivery grid cell.
## Mirrors _place_held_supply_box_on_grid but spawns a trash box.
func _place_held_trash_box_on_grid(grid: DeliveryGrid, hit_point: Vector3) -> void:
	if not is_any_stand_surface(grid):
		return
	var cell_idx := grid.get_closest_cell(hit_point)
	if cell_idx < 0:
		_drop_trash()
		return
	var slot := grid.reserve_slot(cell_idx)
	var state: Dictionary = {
		"is_trash_box": true,
		"ingredient_type": "trash",
		"quantity": 0.0,
		"trash_value": _player.held_item_data.get("trash_value", 0.0),
		"trash_type": _player.held_item_data.get("trash_type", "empty_box"),
		"_net_delivery_cell_idx": cell_idx,
		"_net_delivery_grid_path": str(grid.get_path()),
	}
	var box := _place_held_trash_box_at(slot["position"], slot["rotation"], state)
	if box == null:
		return
	box.set_meta("delivery_cell_idx", cell_idx)
	box.set_meta("delivery_grid_path", grid.get_path())


## Spawn a trash box at the given position (shared helper for grid/stack).
func _place_held_trash_box_at(
	place_pos: Vector3,
	place_rot: Vector3,
	state: Dictionary,
) -> SupplyBox:
	state["_net_place_fx"] = true
	var box := WorldSync.request_spawn(
		"res://scenes/objects/supply_box.tscn",
		place_pos,
		place_rot,
		state,
	) as SupplyBox
	if box:
		box.update_metrics()
		var y_diff := box.bottom_offset - SupplyBox.DEFAULT_BOTTOM_OFFSET
		box.global_position.y += y_diff
		WorldSync.play_place_pop(box)
	AudioManager.play_sfx("box_drop", place_pos)
	_finish_place()
	_player.inventory.clear_held()
	return box


func _get_place_sfx_key(container_type: String) -> String:
	match container_type:
		"pitcher", "press", "fruit_bin":
			return container_type
		_:
			return "table"


func _place_equipment_from_box() -> void:
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Can only place on stand or table!")
		return
	var equipment_type: String = _player.held_item_data.get("equipment_type", "")
	var scene_path: String = CONTAINER_SCENE_PATHS.get(equipment_type, "")
	if scene_path == "":
		push_warning("Unknown equipment type: " + equipment_type)
		return
	# Use same position as ghost (already includes collision offset)
	var place_pos := _ghost.global_position
	var place_rot := _ghost.global_rotation
	var on_workstation := is_workstation_surface(_player.ray.get_collider())
	var placement_scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(equipment_type, Vector3.ONE)
	var state: Dictionary = { }
	# Set initial state so _ready() sees it
	state["starting_amount"] = 0.0
	state["starting_count"] = 0
	state["_net_groups"] = ["container"]
	state["_net_scale"] = placement_scale
	state["_net_place_fx"] = true
	# Ownership follows the stand the item lands on, not the placer.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	var instance := WorldSync.request_spawn(scene_path, place_pos, place_rot, state) as Node3D
	if instance:
		instance.scale = placement_scale
		WorldSync.play_place_pop(instance)
		instance.add_to_group("container")
		# Add pitcher to pitcher group for water tap detection
		if instance is Pitcher:
			instance.add_to_group("pitcher")
			instance.set_pitcher_visible(true)
			instance.sync_fill_display()
			instance.call_deferred("update_label")
			EventBus.pitcher_state_changed.emit(int(instance.state))
	_finish_place()
	_player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
	AudioManager.play_sfx(_get_place_sfx_key(equipment_type), place_pos, -1.0, 0.05, 0.85)
	OnboardingManager.report(
		_player.assigned_stand,
		"equipment_placed",
		{ "type": equipment_type, "on_workstation": on_workstation },
	)
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

	# Some containers need their _ready() to run so visual state is correct
	# (fruit grids, pitcher fill level/color, label). We briefly add them to a
	# hidden temp node, let _ready() fire, then detach them.
	var disable_script := true
	if container_type == "fruit_bin" and inst is FruitBin:
		var fbin := inst as FruitBin
		var temp := Node.new()
		temp.name = "FruitBinHandTemp"
		_player.add_child(temp)
		temp.add_child(fbin)
		fbin.update_display()
		# Remove the Pickupable component so the hand mesh doesn't behave
		# like a real placed container once we disable the script.
		var pickupable := fbin.get_node_or_null("Pickupable")
		if pickupable != null:
			pickupable.queue_free()
		temp.remove_child(fbin)
		temp.queue_free()
	elif container_type in ["sugar_bin", "ice_bin"] and inst is IngredientBin:
		var bin := inst as IngredientBin
		var temp := Node.new()
		temp.name = "IngredientBinHandTemp"
		_player.add_child(temp)
		temp.add_child(bin)
		# For ice, the deferred bucket setup may not have run yet — run it now
		# so update_display() shows the correct cube count.
		if container_type == "ice_bin":
			bin.setup_ice_bucket()
		bin.update_display()
		var pickupable := bin.get_node_or_null("Pickupable")
		if pickupable != null:
			pickupable.queue_free()
		temp.remove_child(bin)
		temp.queue_free()
	elif container_type == "pitcher" and inst is Pitcher:
		var pitcher := inst as Pitcher
		# Keep the script AND the live LemonadeFill CSG — the held pitcher
		# must react to refills/emptying, and the press proves a fresh
		# instance entering the tree once bakes cleanly. The old temp-node
		# detach/reattach is what made the CSG flash a white box.
		# Pickupable is queue_free'd (not free()) so Pitcher._ready() can
		# still wrap its can_pickup_callback before the node dies.
		var pickupable := pitcher.get_node_or_null("Pickupable")
		if pickupable != null:
			pickupable.queue_free()
		# Hide for the first frame in the tree — entering mid-frame can
		# render the CSG combiner's child primitives (including the eraser
		# box) for one frame before the combiner bakes, which is the white
		# box flash seen on appliance pitcher take. One frame is
		# imperceptible; the pitcher's own _ready still runs.
		inst.visible = false
		pitcher.ready.connect(
			func() -> void:
				if not is_instance_valid(pitcher):
					return
				# Wait until one full frame has been rendered with the
				# clone in the tree: frame_post_draw guarantees the CSG's
				# deferred bake flushed, so the combiner never shows its
				# raw primitives (the eraser box = white box flash).
				RenderingServer.frame_post_draw.connect(
					func() -> void:
						if is_instance_valid(pitcher):
							pitcher.visible = true,
					Object.CONNECT_ONE_SHOT,
				),
			Object.CONNECT_ONE_SHOT,
		)
		disable_script = false
	elif container_type in ["lemonader", "fruitomatic"] and inst is Lemonader:
		var machine := inst as Lemonader
		var pickupable := machine.get_node_or_null("Pickupable")
		if pickupable != null:
			pickupable.queue_free()
		# Same first-frame guard as the pitcher clone: the slot preview's
		# live LemonadeFill CSG needs one rendered frame to bake or its
		# eraser box flashes white. refresh_display is called explicitly so
		# the carried machine shows its real state (slot pitcher + stock).
		# A timer, not frame_post_draw: guaranteed to fire even if no frame
		# renders (headless), and the ~2-frame wait covers the CSG bake.
		inst.visible = false
		machine.ready.connect(
			func() -> void:
				if not is_instance_valid(machine):
					return
				machine.refresh_display()
				machine.get_tree().create_timer(0.1).timeout.connect(
					func() -> void:
						if is_instance_valid(machine):
							machine.visible = true,
					Object.CONNECT_ONE_SHOT,
				),
			Object.CONNECT_ONE_SHOT,
		)
		# Keep the script alive — _disable_scripts() would set_script(null),
		# which strips refresh_display/configure_model entirely. _process is
		# harmless: machine_state's batch was folded into output, so the
		# clone can never tick, finish, or publish state for a non-world node.
		disable_script = false

	# Apply hand scale for containers (smaller than placed version)
	var hand_scale: Vector3 = CONTAINER_HAND_SCALE.get(container_type, Vector3.ONE * 0.1)
	inst.scale = hand_scale
	# Hand meshes must never block the player's raycast or collide with the world.
	_disable_physics(inst)
	if disable_script:
		_disable_scripts(inst)

	# Disable collision on hand mesh to prevent pushing player
	_disable_hand_collision(inst)

	# Hand-held clones must not be counted as real placed objects
	remove_placement_groups(inst)

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
		"lemonader", "fruitomatic":
			if inst is Lemonader and not saved_recipe.is_empty():
				# saved_recipe carries the machine's machine_state — set it
				# before _ready so refresh_display shows the slot pitcher.
				var state := saved_recipe.duplicate(true)
				# A live batch folded into output keeps the held mesh's
				# visuals honest without letting the clone's _process tick
				# the batch down and publish state for a non-world node.
				if not (state["batch"] as Dictionary).is_empty() \
						and (state["output"] as Dictionary).is_empty():
					state["output"] = state["batch"]
				state["batch"] = { }
				state["remaining"] = 0.0
				(inst as Lemonader).machine_state = state
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
	var old_mesh := _player.inventory.get_hand_mesh()
	if old_mesh and is_instance_valid(old_mesh):
		old_mesh.queue_free()
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
		# Re-attach via inventory so state stays consistent.
		_player.inventory.set_held(_player.held_item, _player.held_item_data, new_mesh)


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
		n.begins_with("ice cube") or n.begins_with("sugar cube") or n.begins_with("lemon")
		or n.begins_with("raspberry") or n.begins_with("strawberry")
		or n.begins_with("blueberry") or n.begins_with("peach") or n.begins_with("watermelon")
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
	# Ghost the items riding on the held thing (bins on a carried table,
	# cups on a tray) — rotating the preview is only useful if you can see
	# where everything sits. Copies keep their transform relative to the
	# source, so they rotate with the ghost automatically.
	var source: Node = _player.held_item_data.get("source_node")
	if source != null and is_instance_valid(source):
		for child in source.get_children():
			if child is Node3D and child.is_in_group("container"):
				var copy := (child as Node3D).duplicate()
				remove_placement_groups(copy)
				_ghost.add_child(copy)
				copy.transform = (child as Node3D).transform
	# Disable all physics on the ghost so it can't collide or be raycast-hit
	_disable_physics(_ghost)
	# Add to ghost group for overlap filtering
	_mark_ghost(_ghost)
	# Remove the LemonadeFill CSG before the ghost enters the tree — the
	# ghost is a fresh instance whose combiner flashes its eraser box for
	# a frame while baking, and ghost material over a liquid prism reads
	# as a white blob. Ghosts only show the container anyway (bin contents
	# are hidden the same way below). find_child (not get_node) so the
	# Squeeze-E-Z ghost's nested PitcherPoint/PitcherPreview/LemonadeFill
	# is caught too.
	var _ghost_fill := _ghost.find_child("LemonadeFill", true, false)
	if _ghost_fill != null:
		_ghost_fill.free()
	_disable_scripts(_ghost)
	get_tree().current_scene.add_child(_ghost)
	_hide_ghost_box_ui(_ghost)
	_hide_ghost_container_contents(_ghost)
	# Apply ghost material AFTER adding to tree so _ready() side effects
	# (e.g. CSG material setup) don't override the transparent ghost material.
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())
	_ghost.visible = false


func remove_placement_groups(node: Node) -> void:
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
	remove_placement_groups(node)
	# _ready() may add the node to placement groups after add_child,
	# so remove them again once the tree is done setting up.
	call_deferred("remove_placement_groups", node)


func _destroy_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_last_ghost_mat = null
	_ghost_valid = false
	_ghost_yaw_offset = 0.0


## Mouse wheel (called by the controller): rotate the placement preview.
## Only does anything while a valid green ghost is actually showing.
func rotate_ghost(direction: float) -> void:
	if _ghost == null or not _ghost.visible or not _ghost_valid:
		return
	_ghost_yaw_offset = fposmod(_ghost_yaw_offset + direction * GHOST_ROTATE_STEP, TAU)


## After a successful place the held item often turns into something that
## can't go where you're still aiming (e.g. the empty trash box hovering
## over the stack you just put down) — flashing the red invalid ghost that
## same frame reads as "something went wrong". Hide the ghost until the
## camera actually moves. Ghost validity keeps updating under the hood, so
## clicking to place again without moving the mouse still works.
var _ghost_suppressed := false
var _ghost_suppress_quat := Quaternion.IDENTITY

## Camera rotation needed to re-show the ghost after a placement (~0.3 deg).
## Small enough that any deliberate look clears it, large enough that
## sub-pixel mouse drift doesn't.
const GHOST_SUPPRESS_ANGLE := 0.005


func suppress_ghost_until_look() -> void:
	_ghost_suppressed = true
	if _player.camera != null:
		_ghost_suppress_quat = _player.camera.global_basis.get_rotation_quaternion()


## Shared tail for successful placements: mark the ghost suppressed and
## destroy the current preview.
func _finish_place() -> void:
	suppress_ghost_until_look()
	_destroy_ghost()


## Destroys the placement ghost. The ghost is parented to the world
## root, not the player — freeing the player does NOT remove it, so it
## must be cleared explicitly when the session ends or it lingers into
## the next game.
func clear_placement_ghost() -> void:
	_destroy_ghost()


## Ensures a container ghost exists at the given snap position and marks
## it valid, so _try_place_container() can run immediately. The ghost is
## created at pickup but can be destroyed mid-hold (aiming at a trashcan
## destroys it); clicking to snap in that window used to crash on a null
## ghost.
func ensure_snap_ghost(snap_pos: Vector3) -> bool:
	var container_type: String = _player.held_item_data.get("container_type", "")
	if container_type == "":
		return false
	if _ghost == null or _ghost.get_meta("container_type", "") != container_type:
		_create_ghost(container_type)
	if _ghost == null:
		return false
	_ghost.global_position = snap_pos
	_ghost.visible = true
	_ghost_valid = true
	return true


func _update_cup_box_ghost() -> void:
	# Show ghost preview for cup placement when holding cup box.
	if not _player.ray.is_colliding():
		_destroy_ghost()
		_ghost_valid = false
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()
	var on_surface := is_placement_surface(collider)

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

	var is_owned_counter := is_stand_or_workstation_surface(collider)
	var is_box_surface := is_box_placeable_surface(collider)
	if not on_surface or (not is_owned_counter and not is_box_surface):
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
		_ghost.visible = true
		_ghost_valid = false
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	var is_ground := is_ground_surface(collider)
	if is_ground:
		# Cup boxes can be placed on any stand's floor/palette as unopened boxes.
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
		_ghost.visible = true
		_ghost_valid = is_box_surface and not _check_ghost_overlap()
		_apply_ghost_material(
			_ghost,
			_get_ghost_mat_valid() if _ghost_valid else _get_ghost_mat_invalid(),
		)
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
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

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
	var hit_box: SupplyBox = null
	var target_box: SupplyBox = null
	while node != null:
		if node is SupplyBox:
			hit_box = node as SupplyBox
			target_box = _get_topmost_box_in_stack(hit_box)
			break
		node = node.get_parent()

	if target_box != null and target_box.is_inside_tree():
		# Validate the stack's base — the click path checks the same, so
		# ghost and placement stay consistent. The hovered box itself may
		# be several boxes up with no owner or floor beneath its hit point.
		if not _stack_base_is_placeable(hit_box):
			_ghost.visible = false
			_ghost_valid = false
			return
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
		) + Vector3(0, target_box.stack_height, 0)
		_ghost.global_position = stack_base + _stack_offset
		_ghost.global_rotation = target_box.global_rotation + Vector3(
			0,
			_stack_yaw + _ghost_yaw_offset,
			0,
		)
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

	# Ingredient boxes stay as box previews and turn green over the matching
	# destination container, where clicking will deposit their contents.
	var interactable := _player.interaction.get_looked_at_interactable() as Interactable
	var ingredient_type: String = _player.held_item_data.get("ingredient_type", "")
	var matches_container := (
		interactable is IngredientBin
		and (interactable as IngredientBin).ingredient_type == ingredient_type
		or interactable is FruitBin and (interactable as FruitBin).fruit_grids.has(ingredient_type)
		or interactable is WaterDispenser and ingredient_type == "water"
	)
	if matches_container:
		_destroy_ghost()
		_ghost_valid = true
		_stack_target_id = -1
		return

	# Supply crates (and trash boxes) can remain boxed on the palette
	# floor only — the ray must hit PlacableFloor directly, not a prop
	# (price board, dispenser, bin) that merely has floor below it.
	if not _is_box_floor_hit(collider) or not is_box_placeable_surface(collider):
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
		_ghost.visible = true
		_ghost_valid = false
		_stack_target_id = -1
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	_stack_target_id = -1
	_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
	_ghost.global_rotation = Vector3(0, _ghost_yaw_offset, 0)
	_ghost.visible = true
	_ghost_valid = not _check_ghost_overlap()
	_apply_ghost_material(
		_ghost,
		_get_ghost_mat_valid() if _ghost_valid else _get_ghost_mat_invalid(),
	)


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
	# Reset probe cache; is_placement_surface may populate it.
	_has_probe_hit = false

	# Check if looking at another SupplyBox ΓÇö stack on top (box ghost)
	var node: Node = collider
	while node != null:
		if node is SupplyBox:
			var hit_box := node as SupplyBox
			var target_box := _get_topmost_box_in_stack(hit_box)
			if (
				target_box == null or not target_box.is_inside_tree()
				or not _stack_base_is_placeable(hit_box)
			):
				if _ghost != null:
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
			var stack_base := target_box.global_position + Vector3(0, target_box.stack_height, 0)
			_ghost.global_position = stack_base + _stack_offset
			_ghost.global_rotation = target_box.global_rotation + Vector3(
				0,
				_stack_yaw + _ghost_yaw_offset,
				0,
			)
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

	var on_surface := is_placement_surface(collider)
	# If the probe found a corrected tabletop hit point, use it instead
	# of the original side-hit point for ghost positioning.
	if _has_probe_hit:
		hit_point = _probe_hit_point

	# Cross-stand placement restriction: equipment (and its box) can be
	# placed on any stand's ground/palette, but only on the player's own
	# stand/table/workstation. Delivery grids and supply box stacks are
	# handled above and return early.
	if not is_box_placeable_surface(collider):
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
		_ghost.visible = true
		_ghost_valid = false
		_stack_target_id = -1
		_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
		return

	# Workstations are tables ΓÇö they can only be placed on the floor.
	if equipment_type == "workstation":
		if not is_table_floor_surface(collider):
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
			_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset
		_ghost.visible = true
		_ghost_valid = not _check_ghost_overlap()
		_stack_target_id = -1
		_apply_ghost_material(
			_ghost,
			_get_ghost_mat_valid() if _ghost_valid else _get_ghost_mat_invalid(),
		)
		return

	# Only floor-standing equipment (workstation, water dispenser, Fruit-O-Matic)
	# may be placed directly on the ground/floor. Other equipment must go on a
	# table/workstation.
	if equipment_type in ["workstation", "water_dispenser", "fruitomatic"] \
			and _is_box_floor_hit(collider):
		_ensure_box_ghost()
		_ghost.global_position = hit_point + Vector3(0, SupplyBox.DEFAULT_BOTTOM_OFFSET, 0)
		_ghost.visible = true
		_ghost_valid = not _check_ghost_overlap()
		_stack_target_id = -1
		_apply_ghost_material(
			_ghost,
			_get_ghost_mat_valid() if _ghost_valid else _get_ghost_mat_invalid(),
		)
		return

	# Trays belong on the stand counter as well as tables — most equipment
	# is workstation-only. Exclude the stand's own ground/palette so the
	# tray doesn't ghost on the floor.
	var surface_ok := is_workstation_surface(collider)
	if equipment_type == "cup_tray":
		surface_ok = is_stand_or_workstation_surface(collider) \
				and not is_ground_surface(collider)
	if not on_surface or not surface_ok:
		_destroy_ghost()
		_ghost_valid = false
		_stack_target_id = -1
		return

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
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset
	_ghost.visible = true
	_ghost_valid = not _check_ghost_overlap()
	_stack_target_id = -1
	_apply_ghost_material(
		_ghost,
		_get_ghost_mat_valid() if _ghost_valid else _get_ghost_mat_invalid(),
	)


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
	var trashcan := _player.interaction.get_looked_at_interactable() as Trashcan
	var can_trash_held: bool = (
		_player.held_item_data.get("is_trash", false) or _player.held_item == HeldItem.CONTAINER
		or (
			_player.held_item == HeldItem.SUPPLY_BOX
			and _player.held_item_data.get("source", "") == "delivery"
		)
	)
	if trashcan != null and can_trash_held:
		_destroy_ghost()
		return
	# Bin scoops don't have a placement ghost
	if _player.held_item == HeldItem.SUPPLY_BOX \
			and _player.held_item_data.get("source") == "bin_scoop":
		if _ghost != null:
			_destroy_ghost()
		return
	# Handle cup box ghost preview
	if _player.held_item == HeldItem.SUPPLY_BOX \
			and _player.held_item_data.get("ingredient_type") == "cups":
		_update_cup_box_ghost()
		return
	# Handle single cup ghost preview
	if _player.held_item in [HeldItem.CUP_EMPTY, HeldItem.CUP_FILLED]:
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
	if _player.held_item != HeldItem.CONTAINER:
		# Non-container placement paths (machine attach, emptying, trashing)
		# clear the held item without destroying this ghost — don't leave a
		# stale translucent ghost floating at its last position.
		if _ghost != null:
			_destroy_ghost()
		return

	var container_type: String = _player.held_item_data.get("container_type", "")
	# The ghost is created once at pickup but can be destroyed mid-hold
	# (e.g. aiming at a trashcan above destroys it). Recreate it here so
	# the press/dispenser snap previews — and the click-time snap in
	# primary_interact — always have a live ghost.
	if _ghost == null or _ghost.get_meta("container_type", "") != container_type:
		_create_ghost(container_type)
	if _ghost == null:
		return

	# Pitcher snapping to press
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
			# Can't snap — fall through to the machine check / normal placement below
		var machine: Node = _player.interaction.find_looked_at_lemonader()
		if machine != null:
			var _machine_recipe: Dictionary = _player.held_item_data.get("saved_recipe", { })
			# Only show the ghost when the slot can actually take this
			# pitcher — an always-visible pale translucent blob sitting on
			# the machine reads as a glitch, not a hint.
			if machine.can_attach_pitcher(_machine_recipe):
				_ghost.global_position = machine.get_pitcher_snap_global_position()
				_ghost.visible = true
				_ghost_valid = true
				_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			else:
				_ghost.visible = false
				_ghost_valid = false
			return

	if not _player.ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := _player.ray.get_collider()
	var hit_point := _player.ray.get_collision_point()
	var _hit_normal := _player.ray.get_collision_normal()
	var from_box: bool = _player.held_item_data.get("from_delivery_box", false)
	# Reset probe cache; is_placement_surface may populate it if the
	# ray hit a side and a tabletop probe was needed.
	_has_probe_hit = false

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

	var on_surface := is_placement_surface(collider)
	var is_ground := is_ground_surface(collider)
	# If the probe found a corrected tabletop hit point, use it instead
	# of the original side-hit point for ghost positioning.
	if _has_probe_hit:
		hit_point = _probe_hit_point
		_hit_normal = _probe_hit_normal

	# Workstations and water dispensers are floor-standing equipment and can only
	# be placed on the ground. Other containers need an existing stand or
	# workstation surface.
	if container_type == "workstation":
		if not is_table_floor_surface(collider):
			_ghost.visible = false
			_ghost_valid = false
			return
	elif container_type == "water_dispenser":
		if not is_ground or not is_owned_stand_surface(collider):
			_ghost.visible = false
			_ghost_valid = false
			return
	elif not on_surface or not is_stand_or_workstation_surface(collider):
		_ghost.visible = false
		_ghost_valid = false
		return

	# Cross-stand placement restriction: don't allow placing containers on
	# another stand's workstation/surface. Applies to ground too (each stand
	# has its own PlacableFloor area). Use the shared helper so PlacableFloor
	# under a StandUnit is also checked, not just Interactables with stand_owner.
	if not _is_placement_allowed_on(collider):
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
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z) + _ghost_yaw_offset

	# Check for overlap with existing containers
	var overlapping := _check_ghost_overlap()
	# Deployed containers (picked up from workstation) can't go on ground,
	# except floor-standing workstations or water dispensers.
	var deployed: bool = _player.held_item_data.get("deployed", false)
	var valid := (
		not overlapping
		and (
			not (deployed and is_ground) or container_type == "workstation"
			or container_type == "water_dispenser"
			or container_type == "lemonader" or container_type == "fruitomatic"
		)
	)

	_ghost_valid = valid
	var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
	_apply_ghost_material(_ghost, mat)


func _try_place_container() -> Node3D:
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Can only place on stand or table!")
		return null

	var container_type: String = _player.held_item_data.get("container_type", "")
	# Move the existing instance instead of creating a new one, so
	# attached items (workstation items / tray cups / slot pitcher) follow.
	if (
			container_type == "workstation" or container_type == "cup_tray" \
				or container_type == "lemonader"
		or container_type == "fruitomatic"
	):
		var source_node: Node3D = _player.held_item_data.get("source_node") as Node3D
		if source_node != null and is_instance_valid(source_node):
			# Workstation was hidden (not removed from tree) when picked up,
			# so just move it and show it again.
			source_node.global_transform = _ghost.global_transform
			_enable_physics(source_node)
			source_node.visible = true
			if source_node is Lemonader:
				# _enable_physics force-enables the slot preview's collider;
				# refresh re-syncs it so an empty slot can't swallow clicks
				# meant for the machine body.
				(source_node as Lemonader).refresh_display()
			# The pickup shrink effect hides each MeshInstance3D individually;
			# visible=true on the root does not restore them.
			if source_node.has_meta(&"_pickup_hidden_meshes"):
				for hidden_mesh in source_node.get_meta(&"_pickup_hidden_meshes"):
					if is_instance_valid(hidden_mesh):
						hidden_mesh.visible = true
				source_node.remove_meta(&"_pickup_hidden_meshes")
			# Clear the interaction hover state so poll_hint() re-applies
			# highlights on the next frame. After moving the workstation,
			# the bin on it may still be referenced by `hovered` but its
			# outline meshes were removed when the workstation was hidden.
			# Without this, poll_hint() sees interactable == hovered and
			# skips set_highlight(true), leaving the bin without an outline.
			if _player.interaction != null:
				_player.interaction.clear_hover()
			# Ownership follows the stand the workstation lands on.
			var stand_name := _get_placement_stand_name()
			if stand_name != "":
				source_node.set("stand_owner", stand_name)
				WorldSync.sync_property(source_node, "stand_owner", stand_name)
			# _enable_physics already called above re-enables collision
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
			# Pop after sync_move_and_show captured the real scale — the
			# broadcast must not see the tween's shrunken start value.
			WorldSync.play_place_pop(source_node)
			EventBus.container_placed.emit(container_type, source_node)
			AudioManager.play_sfx("table", source_node.global_position, -1.0, 0.05, 0.85)
			_destroy_ghost()
			_player.inventory.clear_held()
			var placed_ref := source_node
			get_tree().create_timer(0.7).timeout.connect(
				func():
					GameLog.log(
						(
							"[WS-PLACE] placer state after 0.7s: "
							+ "node=%s valid=%s visible=%s pos=%s scale=%s"
						)
						% [
							placed_ref.name,
							is_instance_valid(placed_ref),
							placed_ref.visible if is_instance_valid(placed_ref) else "?",
							placed_ref.global_position if is_instance_valid(placed_ref) else "?",
							placed_ref.scale if is_instance_valid(placed_ref) else "?",
						]
					),
			)
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
		"_net_place_fx": true,
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
	# Ownership follows the stand the item lands on, not the placer.
	var stand_name := _get_placement_stand_name()
	if stand_name != "":
		state["stand_owner"] = stand_name
	var instance := WorldSync.request_spawn(scene_path, place_pos, place_rot, state) as Node3D
	if instance == null:
		if not WorldSync.is_host():
			var placed_recipe: Dictionary = _player \
					.held_item_data \
					.get("saved_recipe", { }) \
					.duplicate(true)
			var report_stand := _player.assigned_stand
			if report_stand == null:
				report_stand = OnboardingManager.find_stand(stand_name)
			OnboardingManager.report(
				report_stand,
				"equipment_placed",
				{
					"type": container_type,
					"snapshot": placed_recipe,
					"on_workstation": is_workstation_surface(_player.ray.get_collider()),
				},
			)
		_destroy_ghost()
		_player.inventory.clear_held()
		return null
	instance.scale = placement_scale
	WorldSync.play_place_pop(instance)
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
			WorldSync.sync_property(
				instance,
				"fruit_amounts",
				instance.fruit_amounts.duplicate(true),
			)
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
		instance.serving_recipe = recipe.get("serving_recipe", { }).duplicate(true)
		var restored_state: int = recipe.get("state", int(Pitcher.PitcherState.PREPPING))
		instance.state = restored_state
		EventBus.pitcher_state_changed.emit(restored_state)
		instance.update_label()
		instance.update_liquid_color()
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

	_finish_place()
	var container_type_str: String = _player.held_item_data.get("container_type", "")
	var placed_recipe: Dictionary = _player.held_item_data.get("saved_recipe", { }).duplicate(true)
	var on_workstation := is_workstation_surface(_player.ray.get_collider())
	OnboardingManager.report(
		_player.assigned_stand,
		"equipment_placed",
		{ "type": container_type_str, "snapshot": placed_recipe, "on_workstation": on_workstation },
	)
	_player.inventory.clear_held()
	EventBus.container_placed.emit(container_type_str, instance)
	AudioManager.play_sfx(_get_place_sfx_key(container_type_str), place_pos, -1.0, 0.05, 0.85)
	return instance


func _cancel_container_placement() -> void:
	var container_type: String = _player.held_item_data.get("container_type", "")
	var cost := _get_container_cost(container_type)
	# Restore the workstation to its original position and show it again.
	var source_node: Node3D = _player.held_item_data.get("source_node") as Node3D
	if source_node != null and is_instance_valid(source_node):
		var original: Transform3D = (
			_player.held_item_data.get("source_original_transform", source_node.global_transform)
			as Transform3D
		)
		source_node.global_transform = original
		_enable_physics(source_node)
		source_node.visible = true
		# _enable_physics already called above re-enables collision
		# Sync the restore + show to clients in a single RPC
		WorldSync.sync_move_and_show(
			source_node,
			source_node.global_position,
			source_node.global_rotation,
			source_node.scale,
			true,
		)
	_finish_place()
	var refund_value := cost * 0.7
	_player.inventory.make_held_trash(refund_value, container_type)
	EventBus.interaction_hint_changed.emit("Recycled ΓÇö take to trashcan for $%.2f" % refund_value)


func pickup_container(interactable: Interactable, container_type: String) -> void:
	if container_type in ["lemonader", "fruitomatic"]:
		# No copied-mesh afterimage for the machine — it's the same copy
		# path that produced the white-box flash, and a giant translucent
		# machine silhouette reads as a glitch anyway.
		_player.inventory.suppress_next_pickup_effect()
	else:
		_player.inventory.play_pickup_source(interactable)
	# Workstations, loaded cup trays, and the Squeeze-E-Z keep the original
	# instance so items/cups/the slot pitcher move with it (the preview is
	# a scene child, so machine_state and the pitcher ride along for free).
	if (
			container_type == "workstation" or container_type == "cup_tray" \
				or container_type == "lemonader"
		or container_type == "fruitomatic"
	):
		if container_type == "workstation":
			_attach_items_to_workstation(interactable)
		elif container_type == "cup_tray":
			_attach_cups_to_tray(interactable)
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
			WorldSync.sync_workstation_items(interactable, attached_items)
		var pickup_pos := interactable.global_position
		# Don't remove the workstation from the tree — just hide it locally
		# so items stay attached and the tree structure matches other peers.
		# The sync_hide_object call below hides it on all other clients too.
		interactable.visible = false
		# _disable_physics already called above
		WorldSync.sync_hide_object(interactable)
		EventBus.container_picked_up.emit(container_type, interactable)
		AudioManager.play_sfx("table", pickup_pos)
		var saved_state := { }
		if container_type in ["lemonader", "fruitomatic"] and interactable is Lemonader:
			# The hand mesh shows the machine's real state (slot pitcher,
			# batch, stock); the hidden original keeps processing.
			saved_state = (interactable as Lemonader).machine_state.duplicate(true)
		hold_container(container_type, 0.0, 0, false, saved_state)
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
			"serving_recipe": pitcher.serving_recipe.duplicate(true),
			"state": pitcher.state,
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


func find_customer_in_ancestors(node: Node) -> Customer:
	var current := node
	while current != null:
		if current is Customer:
			return current as Customer
		current = current.get_parent()
	return null


func find_pedestrian_in_ancestors(node: Node) -> Pedestrian:
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


func _get_placement_owner_stand(collider: Node) -> String:
	# Walk up the collider hierarchy to find the StandUnit or Interactable
	# that owns this surface. Returns "" if unowned/standalone.
	if collider == null:
		return ""
	var node := collider
	while node != null:
		if node is StandUnit:
			return node.name
		if "stand_owner" in node and node.stand_owner is String and node.stand_owner != "":
			return node.stand_owner
		# The floor under a stand is named PlacableFloor and is a child of the StandUnit.
		if node.name == "PlacableFloor" and node.get_parent() is StandUnit:
			return node.get_parent().name
		node = node.get_parent()
	return ""


func _get_assigned_stand_name() -> String:
	if _player.assigned_stand != null and is_instance_valid(_player.assigned_stand):
		return _player.assigned_stand.name
	return _player.assigned_stand_name


## Ownership follows the stand the item physically sits on ("the unit owns
## everything under it"), not the player who placed it. Resolves the stand
## from the surface the item is being placed on, falling back to the
## player's assigned stand when the surface is unowned.
func _get_placement_stand_name() -> String:
	var surface_owner := ""
	if _player.ray != null and _player.ray.is_colliding():
		var collider := _player.ray.get_collider()
		surface_owner = _get_placement_owner_stand(collider)
		if surface_owner == "" and is_ground_surface(collider):
			surface_owner = _get_placement_owner_stand(_resolved_ground_surface)
	if surface_owner != "":
		return surface_owner
	return _get_assigned_stand_name()


func _is_placement_allowed_on(collider: Node) -> bool:
	# Ownership check: is the local player allowed to place on this surface?
	# This only checks stand ownership, not whether the collider is a valid
	# placement surface. In solo/offline (no peers) allow all valid surfaces.
	# In multiplayer, a surface with an owner requires the player to be assigned
	# to that same stand. Use together with is_placement_surface().
	if collider == null:
		return false
	var mp := _player.get("multiplayer") as MultiplayerAPI
	if mp == null or mp.multiplayer_peer == null:
		return true
	# No get_peers().is_empty() bypass — a lone host must still respect
	# stand ownership (e.g. rival left mid-game).
	var surface_owner := _get_placement_owner_stand(collider)
	if surface_owner == "" and is_ground_surface(collider):
		surface_owner = _get_placement_owner_stand(_resolved_ground_surface)
	if surface_owner == "":
		return false
	var assigned_name := _get_assigned_stand_name()
	if assigned_name == "":
		return false
	return surface_owner == assigned_name


func is_owned_stand_surface(collider: Node) -> bool:
	if collider == null:
		return false
	var surface_owner := _get_placement_owner_stand(collider)
	if surface_owner == "" and is_ground_surface(collider):
		surface_owner = _get_placement_owner_stand(_resolved_ground_surface)
	if surface_owner == "":
		return false
	var assigned_name := _get_assigned_stand_name()
	if assigned_name == "":
		return not _player.multiplayer.has_multiplayer_peer()
	return surface_owner == assigned_name


## Like is_owned_stand_surface, but also accepts ANY stand's ground/palette
## (PlacableFloor). Used for supply/equipment/trash boxes, which can be
## placed on other stands' ground but not on their tables/workstations.
func is_box_placeable_surface(collider: Node) -> bool:
	if collider == null:
		return false
	# Table/workstation surfaces still require own-stand ownership.
	if is_table_floor_surface(collider) or is_workstation_surface(collider):
		return is_owned_stand_surface(collider)
	# Ground/palette: allow on any stand (own or another player's).
	if is_ground_surface(collider):
		var surface_owner := _get_placement_owner_stand(_resolved_ground_surface)
		return surface_owner != ""
	# Any other placement surface under a StandUnit: own-stand only.
	return is_owned_stand_surface(collider)


## Like is_owned_stand_surface, but accepts ANY stand's surface (not just
## the local player's). Used for box-on-box stacking and delivery grid
## placement, which are allowed across stands.
func is_any_stand_surface(collider: Node) -> bool:
	if collider == null:
		return false
	var surface_owner := _get_placement_owner_stand(collider)
	if surface_owner == "" and is_ground_surface(collider):
		surface_owner = _get_placement_owner_stand(_resolved_ground_surface)
	return surface_owner != ""


func is_table_floor_surface(collider: Node) -> bool:
	if collider == null or _player.ray.get_collision_normal().y <= 0.7:
		return false
	var node := collider
	while node != null:
		if node.name == "PlacableFloor":
			return is_owned_stand_surface(collider)
		node = node.get_parent()
	return false


func is_workstation_surface(collider: Node) -> bool:
	var node := collider
	while node != null:
		var script := node.get_script() as Script
		if script != null and script.resource_path == "res://scripts/objects/workstation.gd":
			return true
		node = node.get_parent()
	return false


func is_stand_or_workstation_surface(collider: Node) -> bool:
	if collider == null or not is_placement_surface(collider):
		return false
	var node := collider
	while node != null:
		if node is StandUnit or node is Workstation:
			return is_owned_stand_surface(collider)
		node = node.get_parent()
	return false


func is_placement_surface(collider: Object) -> bool:
	if collider == null:
		return false
	if not _player.ray.is_colliding():
		return false
	var node := collider as Node
	if node == null:
		return false
	# Check the collider itself and up to 2 parents for placement_surface group
	var is_placement_node := false
	for i in range(3):
		if node.is_in_group("placement_surface"):
			is_placement_node = true
			break
		node = node.get_parent()
		if node == null:
			break
	# If the collider is a placement_surface but the ray hit a side
	# (normal too horizontal), do a downward probe from the hit point
	# to check if there's a valid top surface below. This allows
	# placing on tables from any angle, not just from above.
	var normal := _player.ray.get_collision_normal()
	if normal.y <= 0.7:
		if is_placement_node:
			return _probe_tabletop_below(collider as Node)
		return false
	if is_placement_node:
		return true
	# Fallback: resolve only the PlacableFloor directly below this hit point.
	return is_ground_surface(collider)


## Probe downward from the ray hit point to find a valid tabletop
## surface. This allows placement on tables even when the player's
## forward ray hits the side of the table.
## Returns true and caches the corrected hit point/normal if a valid
## tabletop is found. Uses the same collision mask as the player's
## RayCast3D so the probe sees what the visual ray sees.
func _probe_tabletop_below(original_collider: Node = null) -> bool:
	_has_probe_hit = false
	var hit_point := _player.ray.get_collision_point()
	var from := hit_point + Vector3.UP * 0.5
	var to := hit_point + Vector3.DOWN * 2.0
	var space := _player.get_world_3d().direct_space_state
	# Use the same collision mask as the player's RayCast3D (mask 9 =
	# layers 1 and 4) so the probe agrees with the visual ray.
	var mask := _player.ray.collision_mask
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [_player.get_rid()]
	var hits := space.intersect_ray(query)
	if hits.is_empty():
		return false
	var n: Node = hits.get("collider", null)
	if n == null:
		return false
	# The probe must hit the same object (or a descendant) we originally
	# hit on the side. This prevents the tabletop probe from snapping to
	# the floor when aiming at the edge of a table or stand.
	if original_collider != null and n != original_collider:
		if not original_collider.is_ancestor_of(n):
			return false
	var normal: Vector3 = hits.get("normal", Vector3.ZERO)
	if normal.y <= 0.7:
		return false
	var pos: Vector3 = hits.get("position", hit_point)
	for i in range(3):
		if n.is_in_group("placement_surface"):
			_probe_hit_point = pos
			_probe_hit_normal = normal
			_has_probe_hit = true
			return true
		n = n.get_parent()
		if n == null:
			break
	return false


func is_ground_surface(collider: Object) -> bool:
	_resolved_ground_surface = null
	var node := collider as Node
	var hit_non_ground_surface := false
	while node != null:
		if node.name == "PlacableFloor":
			_resolved_ground_surface = node
			return true
		if node.is_in_group("placement_surface"):
			hit_non_ground_surface = true
		node = node.get_parent()
	if hit_non_ground_surface:
		return false
	if not _player.ray.is_colliding():
		return false
	var hit_point := _player.ray.get_collision_point()
	var query := PhysicsRayQueryParameters3D.create(
		hit_point + Vector3.UP * 0.25,
		hit_point + Vector3.DOWN * 1.0,
		8,
	)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	node = hit.get("collider", null)
	while node != null:
		if node.name == "PlacableFloor":
			_resolved_ground_surface = node
			return true
		node = node.get_parent()
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
		"lemonader":
			return Balancing.CONTAINER_COST_LEMONADER
		"fruitomatic":
			return Balancing.CONTAINER_COST_FRUITOMATIC
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
	# Real physics overlap: run the ghost's own collision shapes (they
	# already carry its current transform) through intersect_shape against
	# the world, so ANY body the ghost would clip — prop, machine, bin,
	# box, wall — counts, not just container/supply_box group members.
	if _ghost == null:
		return false
	var ghost_shapes: Array[CollisionShape3D] = []
	_collect_ghost_shapes(_ghost, ghost_shapes)
	if ghost_shapes.is_empty():
		return false

	var support: Node = _player.ray.get_collider() if _player.ray.is_colliding() else null
	var exclude: Array[RID] = [_player.get_rid()]
	if support is CollisionObject3D:
		exclude.append((support as CollisionObject3D).get_rid())

	var space := _player.get_world_3d().direct_space_state
	for shape_node in ghost_shapes:
		if shape_node.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = shape_node.global_transform
		# Lift slightly: resting flush on the support surface is not a clip.
		query.transform.origin.y += 0.03
		query.collision_mask = _player.ray.collision_mask
		query.exclude = exclude
		for hit in space.intersect_shape(query, 8):
			var body := hit.get("collider") as Node
			if body == null or not body is Node3D:
				continue
			if body.is_in_group("ghost"):
				continue
			# Bodies inside the ghost preview itself can never count.
			if _is_ancestor_of_node(_ghost, body):
				continue
			# A body that is an ancestor of the support we rest on
			# (e.g. the stand that owns the counter) is the surface.
			if _is_ancestor_of_node(body, support):
				continue
			# Hidden originals carried by a player keep their physics off,
			# but guard against any enabled-but-hidden stragglers.
			if not (body as Node3D).is_visible_in_tree():
				continue
			return true

	# Delivery palettes are static meshes, not containers — reject the
	# placement only when the ghost actually sits over the palette's
	# footprint (its center inside the XZ bounds), not merely touching the
	# edge of the palette's bounding box. Boxes carried away from a
	# delivery land right next to the palette, and an edge-touching AABB
	# check made the ghost stay red across the whole surrounding area.
	var ghost_aabb := AABB()
	var aabb_found := false
	for shape_node in ghost_shapes:
		var a := _shape_world_aabb(shape_node.shape, shape_node.global_transform)
		if not aabb_found:
			ghost_aabb = a
			aabb_found = true
		else:
			ghost_aabb = ghost_aabb.merge(a)
	var ghost_origin := _ghost.global_transform.origin
	for grid in get_tree().get_nodes_in_group("delivery_grid"):
		var palette := grid.get_node_or_null("palette")
		if palette == null:
			continue
		var pal_aabb := _node_world_aabb(palette)
		if pal_aabb.size == Vector3.ZERO:
			continue
		if not ghost_aabb.intersects(pal_aabb):
			continue
		var center_xz := Vector2(ghost_origin.x, ghost_origin.z)
		var min_xz := Vector2(pal_aabb.position.x, pal_aabb.position.z)
		var max_xz := min_xz + Vector2(pal_aabb.size.x, pal_aabb.size.z)
		var inside := (
			center_xz.x > min_xz.x - 0.1 and center_xz.x < max_xz.x + 0.1
			and center_xz.y > min_xz.y - 0.1 and center_xz.y < max_xz.y + 0.1
		)
		if inside:
			return true

	return false


## World-space AABB of a collision shape at the given transform.
## Used for ghost-vs-palette checks where the palette has no CollisionShape3D.
func _shape_world_aabb(shape: Shape3D, t: Transform3D) -> AABB:
	var s: Vector3 = t.basis.get_scale()
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size * s
		return AABB(t.origin - size * 0.5, size)
	var r := _get_shape_radius(shape) * maxf(s.x, s.z)
	var h := r * 2.0
	if shape is CylinderShape3D:
		h = (shape as CylinderShape3D).height * s.y
	return AABB(t.origin - Vector3(r, h * 0.5, r), Vector3(r * 2, h, r * 2))


## Combined world-space AABB of every MeshInstance3D under a node
## (e.g. the delivery-grid palette model, which is just a mesh).
func _node_world_aabb(node: Node) -> AABB:
	var result := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, true):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		if not found:
			result = a
			found = true
		else:
			result = result.merge(a)
	return result


func _is_ancestor_of_node(ancestor: Node, node: Node) -> bool:
	while node != null:
		if node == ancestor:
			return true
		node = node.get_parent()
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


## Every CollisionShape3D inside the ghost — the old overlap check only
## used the first one, so multi-shape ghosts (table top + legs) clipped
## through anything the first shape didn't cover.
func _collect_ghost_shapes(node: Node, out: Array[CollisionShape3D]) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			out.append(child)
		_collect_ghost_shapes(child, out)


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
		# Tables belong to the container group too — skip other
		# workstations so an adjacent table isn't swallowed as an item.
		if item is Workstation:
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


func _attach_cups_to_tray(tray: Node) -> void:
	var tray_pos := (tray as Node3D).global_position
	for item in get_tree().get_nodes_in_group("container"):
		if not item is Cup or not is_instance_valid(item):
			continue
		if tray.is_ancestor_of(item):
			continue
		# Only attach cups that are direct children of the world root —
		# not cups already parented to another carried item.
		var parent := (item as Node).get_parent()
		if parent == null:
			continue
		if parent != get_tree().current_scene and parent.name != "WorldObjects":
			continue
		var pos := (item as Node3D).global_position
		if pos.y < tray_pos.y - 0.05 or pos.y > tray_pos.y + 0.3:
			continue
		if absf(pos.x - tray_pos.x) > 0.35 or absf(pos.z - tray_pos.z) > 0.35:
			continue
		(item as Node3D).reparent(tray, true)
