class_name Player
extends CharacterBody3D

enum HeldItem { NONE, CUP_EMPTY, CUP_FILLED, SUPPLY_BOX, CONTAINER }

const MOVE_SPEED: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002

@export var gravity: float = 9.8
@export var sprint_multiplier: float = 1.8
@export var jump_velocity: float = 5.0

var held_item: HeldItem = HeldItem.NONE
var held_item_data: Dictionary = { }
var _held_mesh: Node3D = null
var _last_hint: String = ""
var _hovered: Interactable = null

# --- Rapid-fire bin deposit ---
var _primary_held: bool = false
var _rapid_fire_timer: float = 0.0
@export var rapid_fire_interval: float = 0.35

# --- Container placement ghost ---
var _ghost: Node3D = null
var _ghost_valid: bool = false
static var _ghost_mat_valid: StandardMaterial3D = null
static var _ghost_mat_invalid: StandardMaterial3D = null

const CONTAINER_SCENES: Dictionary = {
	"lemon_bin": preload("res://scenes/objects/lemon_bin.tscn"),
	"sugar_bin": preload("res://scenes/objects/sugar_bin.tscn"),
	"ice_bin": preload("res://scenes/objects/ice_bin.tscn"),
	"cup_stack": preload("res://scenes/objects/cup_stack.tscn"),
	"pitcher": preload("res://scenes/objects/pitcher.tscn"),
	"press": preload("res://scenes/objects/press.tscn"),
}

const CONTAINER_PLACEMENT_SCALE: Dictionary = {
	"lemon_bin": Vector3.ONE * 0.06,
	"sugar_bin": Vector3.ONE * 0.04,
	"ice_bin": Vector3.ONE * 0.03,
	"cup_stack": Vector3.ONE * 0.03, # Smaller cups
	"pitcher": Vector3.ONE * 0.15,
	"press": Vector3.ONE * 0.10,
}

const CONTAINER_HAND_SCALE: Dictionary = {
	"lemon_bin": Vector3.ONE * 0.03,
	"sugar_bin": Vector3.ONE * 0.02,
	"ice_bin": Vector3.ONE * 0.015,
	"cup_stack": Vector3.ONE * 0.015,
	"pitcher": Vector3.ONE * 0.08,
	"press": Vector3.ONE * 0.05,
}


func _get_container_bottom_offset(node: Node) -> float:
	"""Calculate how far the collision extends below the node's origin."""
	var lowest_y := 0.0
	for child in node.get_children():
		if child is CollisionShape3D:
			var col := child as CollisionShape3D
			var shape_pos_y := col.position.y
			var half_height := 0.0
			if col.shape is BoxShape3D:
				half_height = (col.shape as BoxShape3D).size.y * 0.5
			elif col.shape is CylinderShape3D:
				half_height = (col.shape as CylinderShape3D).height * 0.5
			elif col.shape is SphereShape3D:
				half_height = (col.shape as SphereShape3D).radius
			var bottom := shape_pos_y - half_height
			lowest_y = min(lowest_y, bottom)
		lowest_y = min(lowest_y, _get_container_bottom_offset(child))
	return lowest_y


@onready var head: Node3D = $Head
@onready var hand_slot: Node3D = $Head/Camera3D/HandSlot
@onready var ray: RayCast3D = $Head/RayCast3D


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Layer 2 is used by the screen-space outline system for white fill nodes.
	# The main camera must not render them — only the SubViewport OutlineCamera does.
	$Head/Camera3D.cull_mask &= ~2


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, -PI / 2.1, PI / 2.1)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if \
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else \
		Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_primary_held = true
			_rapid_fire_timer = _get_rapid_fire_interval()
			_primary_interact()
		elif not event.pressed:
			_primary_held = false

	if event.is_action_pressed("secondary_interact") and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_secondary_interact()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := MOVE_SPEED * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	velocity.x = direction.x * speed if direction else move_toward(velocity.x, 0, speed)
	velocity.z = direction.z * speed if direction else move_toward(velocity.z, 0, speed)
	move_and_slide()
	_poll_hint()
	_update_ghost()
	_update_rapid_fire(delta)


func _poll_hint() -> void:
	var interactable := _get_looked_at_interactable()
	if interactable != _hovered:
		if _hovered and is_instance_valid(_hovered):
			_hovered.set_highlight(false)
		_hovered = interactable
		if _hovered:
			_hovered.set_highlight(true)
	var hint := ""
	if held_item == HeldItem.CONTAINER:
		# Check if looking at water tap with pitcher
		if interactable is WaterTap:
			var container_type: String = held_item_data.get("container_type", "")
			if container_type == "pitcher":
				var _recipe: Dictionary = held_item_data.get("saved_recipe", { })
				if _recipe.get("water", 0.0) > 0.0:
					hint = "Pitcher already has water  |  RMB: Cancel (refund)"
				else:
					hint = "LMB: Fill pitcher with water  |  RMB: Cancel (refund)"
			else:
				hint = "LMB: Place  |  RMB: Cancel (refund)"
		else:
			var container_type: String = held_item_data.get("container_type", "")
			if container_type == "pitcher":
				var press := _find_looked_at_press()
				if press != null:
					var _recipe: Dictionary = held_item_data.get("saved_recipe", { })
					hint = press.get_pitcher_snap_hint(_recipe)
				elif _ghost_valid:
					hint = "LMB: Place  |  RMB: Cancel (refund)"
				else:
					hint = "Aim at stand or workstation to place  |  RMB: Cancel (refund)"
			elif _ghost_valid:
				hint = "LMB: Place  |  RMB: Cancel (refund)"
			else:
				hint = "Aim at stand or workstation to place  |  RMB: Cancel (refund)"
	elif held_item == HeldItem.SUPPLY_BOX \
			and held_item_data.get("ingredient_type") == "cups":
		hint = "LMB: Place 1 cup  |  RMB: Drop box"
		if interactable is CupStack:
			hint = "LMB: Add 1 cup  |  RMB: Drop box"
	elif held_item == HeldItem.CUP_EMPTY:
		hint = "LMB: Place cup  |  RMB: Drop"
		if interactable is CupStack:
			hint = "LMB: Add to stack  |  RMB: Drop"
	elif held_item == HeldItem.CUP_FILLED:
		hint = "LMB: Place filled cup  |  RMB: Drop"
	else:
		hint = interactable.get_hint(self) if interactable else ""
		# Append pickup hint when looking at a placed container with empty hands
		if interactable and held_item == HeldItem.NONE:
			var ctype := _get_container_type_for_node(interactable)
			if ctype != "":
				hint = hint + "  |  RMB: Pick up" if hint != "" else "RMB: Pick up"
	if hint != _last_hint:
		_last_hint = hint
		EventBus.interaction_hint_changed.emit(hint)


func _primary_interact() -> void:
	# Check if looking at an interactable first (even when holding items)
	var interactable := _get_looked_at_interactable()

	# Handle water tap interaction when holding pitcher - fill directly
	if interactable is WaterTap and held_item == HeldItem.CONTAINER:
		var container_type: String = held_item_data.get("container_type", "")
		if container_type == "pitcher":
			var recipe: Dictionary = held_item_data.get("saved_recipe", { })
			var current_water: float = recipe.get("water", 0.0)
			if current_water <= 0.0:
				var current_fruit: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
				var liquid_volume: float = current_fruit + current_water
				var fill: float = Balancing.PITCHER_MAX_LIQUID - liquid_volume
				if fill > 0.0:
					recipe["water"] = current_water + fill
					held_item_data["saved_recipe"] = recipe
					held_item_data["has_liquid"] = true
					EventBus.pitcher_ingredient_added.emit("water", fill)
					# Animate eraser on the held mesh instead of recreating it
					if _held_mesh is Pitcher:
						(_held_mesh as Pitcher).fill_water_slow(fill, 4.0)
				EventBus.interaction_hint_changed.emit("Pitcher filled with water!")
			else:
				EventBus.interaction_hint_changed.emit("Pitcher already has water!")
			return

	if held_item == HeldItem.CONTAINER:
		var container_type: String = held_item_data.get("container_type", "")
		if container_type == "pitcher":
			var press := _find_looked_at_press()
			if press != null:
				var recipe: Dictionary = held_item_data.get("saved_recipe", { })
				if press.can_snap_pitcher(recipe):
					_ghost.global_position = press.get_snap_global_position()
					_ghost_valid = true
					var placed := _try_place_container()
					if placed is Pitcher:
						press.snap_pitcher(placed as Pitcher)
					return
				EventBus.interaction_hint_changed.emit(
					press.get_pitcher_snap_hint(recipe),
				)
				return
		_try_place_container()
		return

	# Handle single empty cup placement or pitcher interaction
	if held_item == HeldItem.CUP_EMPTY:
		# First check if looking at a pitcher to fill cup
		if interactable is Pitcher:
			(interactable as Pitcher).interact(self)
			return
		# Then check for cup stack
		if interactable is CupStack:
			(interactable as CupStack).interact(self)
			return
		# Then check for water tap
		if interactable is WaterTap:
			(interactable as WaterTap).interact(self)
			return
		# Place on surface to start new stack
		if ray.is_colliding() and _is_placement_surface(ray.get_collider()):
			_place_single_cup(false)
			return
		return

	# Handle filled cup - serve to customer or place on surface
	if held_item == HeldItem.CUP_FILLED:
		# First check if looking at a customer to serve (customer is not an Interactable)
		if ray.is_colliding():
			var hit_node: Node = ray.get_collider() as Node
			var customer: Customer = _find_customer_in_ancestors(hit_node)
			if customer != null:
				customer.try_serve(self)
				return
		# Then place on surface
		if ray.is_colliding() and _is_placement_surface(ray.get_collider()):
			_place_filled_cup()
			return
		return

	# Special handling for cup box - place stack on surface or deposit to existing
	if held_item == HeldItem.SUPPLY_BOX \
			and held_item_data.get("source") == "delivery" \
			and held_item_data.get("ingredient_type") == "cups":
		if interactable is CupStack:
			# Deposit to existing stack
			interactable.interact(self)
			return
		# Check if looking at placement surface
		if ray.is_colliding() and _is_placement_surface(ray.get_collider()):
			_place_cup_stack_from_box()
			return
		# Fallback: drop the box
		_drop_held_box()
		return

	# Handle fallback interactables (not caught by specific cases above)
	var fallback_interactable := _get_looked_at_interactable()
	if fallback_interactable:
		fallback_interactable.interact(self)
	elif held_item == HeldItem.SUPPLY_BOX and held_item_data.get("source") == "delivery":
		_drop_held_box()


func _secondary_interact() -> void:
	var interactable := _get_looked_at_interactable()
	if interactable:
		# If hands empty and looking at container, pick it up
		if held_item == HeldItem.NONE:
			var ctype := _get_container_type_for_node(interactable)
			if ctype != "":
				pickup_container(interactable, ctype)
				return
		# Otherwise let the interactable handle secondary interact
		interactable.interact_secondary(self)
		return

	# Cancel container placement if holding one and not looking at anything
	if held_item == HeldItem.CONTAINER:
		_cancel_container_placement()
		return

	# Drop supply box
	if held_item == HeldItem.SUPPLY_BOX and held_item_data.get("source") == "delivery":
		_drop_held_box()


func _place_cup_stack_from_box() -> void:
	"""Place ONE cup on the surface or add to existing stack."""
	const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")

	# Get quantity from held box
	var qty: int = int(held_item_data.get("amount", 0))
	if qty <= 0:
		return

	# Check if looking at existing stack
	var interactable := _get_looked_at_interactable()
	if interactable is CupStack:
		# Add one cup to existing stack
		interactable.add_cups(1)
		update_held_amount(float(qty - 1))
		if qty - 1 <= 0:
			clear_held()
		EventBus.supply_box_deposited.emit("cups", 1)
		return

	# Check for overlap with existing cup stacks before placing
	if ray.is_colliding():
		var hit_point := ray.get_collision_point()
		for node in get_tree().get_nodes_in_group("container"):
			if node is CupStack:
				var dist := (node as Node3D).global_position.distance_to(hit_point)
				if dist < 0.08: # Smaller threshold for cups
					EventBus.interaction_hint_changed.emit("Too close to existing cup stack!")
					return

	# Place new stack with ONE cup
	var stack := CUP_STACK_SCENE.instantiate()

	# Apply smaller placement scale
	var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack", Vector3.ONE * 0.03)
	stack.scale = scale

	# Set the count to 1 and max capacity
	stack.starting_count = 1
	stack.max_capacity = 10

	get_tree().current_scene.add_child(stack)
	stack.add_to_group("container")

	# Position on surface with collision offset
	var place_point := ray.get_collision_point()
	var bottom_offset := _get_container_bottom_offset(stack)
	stack.global_position = place_point + Vector3(0, -bottom_offset * scale.y, 0)
	# Face the player
	var look_dir := global_position - place_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		stack.global_rotation.y = atan2(look_dir.x, look_dir.z)

	# Deduct one cup from held box
	update_held_amount(float(qty - 1))
	if qty - 1 <= 0:
		clear_held()

	EventBus.container_placed.emit("cup_stack", stack)


func _update_single_cup_ghost() -> void:
	"""Show ghost preview for single cup placement."""
	# Destroy ghost if it's the wrong type for current held item
	if _ghost != null:
		var is_cup_stack_ghost: bool = _ghost.get_node_or_null("ItemGrid") != null
		var should_be_stack: bool = held_item == HeldItem.CUP_EMPTY
		if is_cup_stack_ghost != should_be_stack:
			_destroy_ghost()

	if _ghost == null:
		if held_item == HeldItem.CUP_FILLED:
			const CUP_SCENE: PackedScene = preload("res://scenes/objects/cup.tscn")
			_ghost = CUP_SCENE.instantiate()
			var scale: Vector3 = Vector3.ONE * 0.03
			_ghost.scale = scale
			_ghost.state = Cup.CupState.FILLED
			var bottom_offset := _get_container_bottom_offset(_ghost)
			_ghost.set_meta("bottom_offset", bottom_offset * scale.y)
			_disable_scripts(_ghost)
			_disable_physics(_ghost)
			_ghost.add_to_group("ghost")
			_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			get_tree().current_scene.add_child(_ghost)
		else:
			const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")
			_ghost = CUP_STACK_SCENE.instantiate()
			var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack", Vector3.ONE * 0.03)
			_ghost.scale = scale
			var bottom_offset := _get_container_bottom_offset(_ghost)
			_ghost.set_meta("bottom_offset", bottom_offset * scale.y)
			_disable_scripts(_ghost)
			_disable_physics(_ghost)
			_ghost.add_to_group("ghost")
			# Show only 1 cup in ghost
			_set_single_cup_visibility(_ghost)
			_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			get_tree().current_scene.add_child(_ghost)

	if not ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := ray.get_collider()
	var on_surface := _is_placement_surface(collider)
	var hit_point := ray.get_collision_point()

	# Check if looking at existing cup stack
	var interactable := _get_looked_at_interactable()
	if interactable is CupStack and held_item == HeldItem.CUP_EMPTY:
		# For empty cups, hide ghost when looking at stack
		_ghost.visible = false
		_ghost_valid = true
		return

	# Only show ghost when on valid placement surface
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		return

	_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
	var look_dir := global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)

	var overlapping := _check_ghost_overlap()
	_ghost.visible = true

	var valid := not overlapping
	if valid != _ghost_valid:
		_ghost_valid = valid
		var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
		_apply_ghost_material(_ghost, mat)


func _place_single_cup(filled: bool) -> void:
	"""Place a single cup on the surface (creates new stack with 1 cup)."""
	# Check ghost validity before placing
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Cannot place here - too close to another stack!")
		return

	const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")
	var stack := CUP_STACK_SCENE.instantiate()

	var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack", Vector3.ONE * 0.03)
	stack.scale = scale
	stack.starting_count = 1
	stack.max_capacity = 10

	get_tree().current_scene.add_child(stack)
	stack.add_to_group("container")

	var hit_point := ray.get_collision_point()
	var bottom_offset := _get_container_bottom_offset(stack)
	stack.global_position = hit_point + Vector3(0, -bottom_offset * scale.y, 0)
	var look_dir := global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		stack.global_rotation.y = atan2(look_dir.x, look_dir.z)

	_destroy_ghost()
	clear_held()
	EventBus.container_placed.emit("cup_stack", stack)


func _place_filled_cup() -> void:
	"""Place a filled cup on the surface for customers to take."""
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Cannot place here - invalid position!")
		return

	const CUP_SCENE: PackedScene = preload("res://scenes/objects/cup.tscn")
	var cup: Cup = CUP_SCENE.instantiate() as Cup
	if cup == null:
		return

	# Apply scale
	var scale := Vector3.ONE * 0.03
	cup.scale = scale

	# Transfer recipe and set state
	var recipe: Dictionary = held_item_data.get("recipe", { })
	cup.recipe = recipe
	cup.state = Cup.CupState.FILLED

	# Add to scene (runs _ready())
	get_tree().current_scene.add_child(cup)
	cup.add_to_group("container")

	# Ensure collision is active and on the interaction layer
	if cup.physics != null:
		cup.physics.collision_layer = 1
		cup.physics.collision_mask = 1
		for child in cup.physics.get_children():
			if child is CollisionShape3D:
				child.disabled = false

	# Position
	var hit_point := ray.get_collision_point()
	var bottom_offset := _get_container_bottom_offset(cup)
	cup.global_position = hit_point + Vector3(0, -bottom_offset * scale.y, 0)

	# Face the player
	var look_dir := global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		cup.global_rotation.y = atan2(look_dir.x, look_dir.z)

	_destroy_ghost()
	clear_held()
	EventBus.interaction_hint_changed.emit("Filled cup placed!")


func _drop_held_box() -> void:
	const BOX_SCENE = preload("res://scenes/objects/supply_box.tscn")
	var box: SupplyBox = BOX_SCENE.instantiate()
	box.ingredient_type = held_item_data.get("ingredient_type", "lemon")
	box.quantity = held_item_data.get("amount", 1.0)
	# Drop exactly where the raycast hits, or 0.8 m ahead if not hitting anything.
	var drop_pos: Vector3
	if ray.is_colliding():
		drop_pos = ray.get_collision_point() + Vector3(0, 0.13, 0)
	else:
		drop_pos = global_position + (-transform.basis.z * 0.8) + Vector3(0, 0.15, 0)
	get_parent().add_child(box)
	box.global_position = drop_pos
	clear_held()


func _update_rapid_fire(delta: float) -> void:
	if not _primary_held:
		return
	if held_item != HeldItem.SUPPLY_BOX:
		return
	if held_item_data.get("source") != "delivery":
		return

	_rapid_fire_timer -= delta
	if _rapid_fire_timer > 0.0:
		return

	var interactable := _get_looked_at_interactable()

	# Handle cup stack deposits
	var cup_stack := interactable as CupStack
	if cup_stack != null:
		if held_item_data.get("ingredient_type", "") != "cups":
			return
		if cup_stack.current_count >= cup_stack.max_capacity:
			return
		var amount: float = held_item_data.get("amount", 0.0)
		if amount <= 0.0:
			return
		_rapid_fire_timer = _get_rapid_fire_interval()
		cup_stack.interact(self)
		return

	# Handle ingredient bin deposits
	var bin := interactable as IngredientBin
	if bin == null:
		return
	if bin.ingredient_type != held_item_data.get("ingredient_type", ""):
		return
	if bin.current_amount >= bin.max_capacity:
		return
	var amount: float = held_item_data.get("amount", 0.0)
	if amount <= 0.0:
		return

	_rapid_fire_timer = _get_rapid_fire_interval()
	bin.interact(self)


func _get_rapid_fire_interval() -> float:
	var nimble_bonus: float = UpgradeManager.get_effect_total("nimbleness")
	if nimble_bonus > 0.0:
		return rapid_fire_interval * (1.0 - nimble_bonus)
	return rapid_fire_interval


func _get_looked_at_interactable() -> Interactable:
	if not ray.is_colliding():
		return null
	var node: Node = ray.get_collider()
	# Walk up max 4 levels to find an Interactable ancestor
	for i in range(4):
		if node == null:
			break
		if node is Interactable:
			return node as Interactable
		node = node.get_parent()
	return null


func _find_looked_at_press() -> Press:
	# Standard interactable lookup
	var interactable := _get_looked_at_interactable()
	if interactable is Press:
		return interactable as Press
	# Fallback: walk up from direct collider (deeper search)
	if ray.is_colliding():
		var node := ray.get_collider()
		for i in range(6):
			if node == null:
				break
			if node is Press:
				return node as Press
			node = node.get_parent()
	return null


func set_held(item_type: HeldItem, data: Dictionary, mesh: Node3D = null) -> void:
	if _held_mesh and is_instance_valid(_held_mesh):
		_held_mesh.queue_free()
		_held_mesh = null
	held_item = item_type
	held_item_data = data
	if mesh:
		_held_mesh = mesh
		hand_slot.add_child(mesh)
		_apply_hand_offset(item_type, data)
	EventBus.held_item_changed.emit(int(item_type), data)


func _apply_hand_offset(item_type: HeldItem, data: Dictionary) -> void:
	if _held_mesh == null:
		return
	var offset := Vector3.ZERO
	match item_type:
		HeldItem.SUPPLY_BOX:
			offset = Vector3(0.1, 0.1, 0.0)
		HeldItem.CONTAINER:
			var ctype: String = data.get("container_type", "")
			if ctype in ["lemon_bin", "sugar_bin", "ice_bin"]:
				offset = Vector3(0.05, 0.05, 0.0)
	_held_mesh.position = offset


func update_held_amount(new_amount: float) -> void:
	held_item_data["amount"] = new_amount
	if _held_mesh:
		var lbl := _held_mesh.get_node_or_null("QuantityLabel") as Label3D
		if lbl:
			lbl.text = "×%.0f" % new_amount
	EventBus.held_item_changed.emit(int(held_item), held_item_data)


func clear_held() -> void:
	set_held(HeldItem.NONE, { })

# ==========================================================================
#  CONTAINER PLACEMENT SYSTEM
# ==========================================================================


func hold_container(container_type: String, saved_amount: float = 0.0, saved_count: int = 0, has_liquid: bool = false, saved_recipe: Dictionary = { }) -> void:
	var scene: PackedScene = CONTAINER_SCENES.get(container_type)
	if scene == null:
		push_warning("Unknown container type: " + container_type)
		return

	# Create hand mesh for container first
	var hand_mesh: Node3D = _create_container_hand_mesh(container_type, has_liquid, saved_recipe, saved_amount, saved_count)

	# Use set_held to properly manage hand mesh (unified system)
	set_held(
		HeldItem.CONTAINER,
		{
			"container_type": container_type,
			"saved_amount": saved_amount,
			"saved_count": saved_count,
			"has_liquid": has_liquid,
			"saved_recipe": saved_recipe,
		},
		hand_mesh,
	)

	EventBus.held_item_changed.emit(int(held_item), held_item_data)
	_create_ghost(container_type)


func _create_container_hand_mesh(
		container_type: String,
		_has_liquid: bool,
		saved_recipe: Dictionary,
		saved_amount: float = 0.0,
		saved_count: int = 0,
) -> Node3D:
	"""Create a hand mesh for the held container."""
	var scene: PackedScene = CONTAINER_SCENES.get(container_type)
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

	return inst


func _set_container_starting_state(inst: Node, container_type: String, saved_amount: float, saved_count: int, saved_recipe: Dictionary = { }) -> void:
	"""Set the starting amount/count on a container instance so its own
	_ready() renders the correct item visibility and label text."""
	match container_type:
		"lemon_bin", "sugar_bin", "ice_bin":
			if "starting_amount" in inst:
				inst.starting_amount = saved_amount
		"cup_stack":
			if "starting_count" in inst:
				inst.starting_count = saved_count
		"pitcher":
			if inst is Pitcher:
				var pitcher := inst as Pitcher
				pitcher.fruit_type = saved_recipe.get("fruit_type", "")
				pitcher.fruit_count = saved_recipe.get("fruit_count", saved_recipe.get("lemons", 0.0))
				pitcher.water = saved_recipe.get("water", 0.0)
				pitcher.sugar = saved_recipe.get("sugar", 0.0)
				pitcher.ice = saved_recipe.get("ice", 0.0)
				pitcher.cups_poured = saved_recipe.get("cups_poured", 0)


func _refresh_held_container_mesh() -> void:
	if _held_mesh and is_instance_valid(_held_mesh):
		_held_mesh.queue_free()
		_held_mesh = null
	var container_type: String = held_item_data.get("container_type", "")
	var has_liquid: bool = held_item_data.get("has_liquid", false)
	var saved_recipe: Dictionary = held_item_data.get("saved_recipe", { })
	var saved_amount: float = held_item_data.get("saved_amount", 0.0)
	var saved_count: int = held_item_data.get("saved_count", 0)
	var new_mesh: Node3D = _create_container_hand_mesh(
		container_type,
		has_liquid,
		saved_recipe,
		saved_amount,
		saved_count,
	)
	if new_mesh:
		_held_mesh = new_mesh
		hand_slot.add_child(_held_mesh)


func _disable_hand_collision(node: Node) -> void:
	"""Recursively disable collision on all physics bodies."""
	if node is CollisionObject3D:
		var body: CollisionObject3D = node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_hand_collision(child)


func _create_ghost(container_type: String) -> void:
	_destroy_ghost()
	var scene: PackedScene = CONTAINER_SCENES.get(container_type)
	if scene == null:
		return
	_ghost = scene.instantiate()
	# Apply placement scale so ghost matches final size
	var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(container_type, Vector3.ONE)
	_ghost.scale = scale
	# Calculate offset based on collision bounds (will be stored in metadata)
	var bottom_offset := _get_container_bottom_offset(_ghost)
	_ghost.set_meta("bottom_offset", bottom_offset * scale.y)
	# Set starting state so the ghost's _ready() shows the correct item
	# count and label, matching what will actually be placed.
	var saved_amount: float = held_item_data.get("saved_amount", 0.0)
	var saved_count: int = held_item_data.get("saved_count", 0)
	_set_container_starting_state(_ghost, container_type, saved_amount, saved_count)
	# Disable all physics on the ghost so it can't collide or be raycast-hit
	_disable_physics(_ghost)
	# Add to ghost group for overlap filtering
	_ghost.add_to_group("ghost")
	# Make it semi-transparent
	_apply_ghost_material(_ghost, _get_ghost_mat_valid())
	get_tree().current_scene.add_child(_ghost)
	_ghost.visible = false


func _destroy_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_valid = false


func _update_cup_box_ghost() -> void:
	"""Show ghost preview for cup placement when holding cup box."""
	# Create ghost if not exists
	if _ghost == null:
		const CUP_STACK_SCENE: PackedScene = preload("res://scenes/objects/cup_stack.tscn")
		_ghost = CUP_STACK_SCENE.instantiate()
		var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get("cup_stack", Vector3.ONE * 0.03)
		_ghost.scale = scale
		var bottom_offset := _get_container_bottom_offset(_ghost)
		_ghost.set_meta("bottom_offset", bottom_offset * scale.y)
		_disable_scripts(_ghost)
		_disable_physics(_ghost)
		_ghost.add_to_group("ghost")
		# Show only 1 cup in ghost
		_set_single_cup_visibility(_ghost)
		_apply_ghost_material(_ghost, _get_ghost_mat_valid())
		get_tree().current_scene.add_child(_ghost)

	if not ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := ray.get_collider()
	var on_surface := _is_placement_surface(collider)
	var hit_point := ray.get_collision_point()

	# Check if looking at existing cup stack - hide ghost in that case
	var interactable := _get_looked_at_interactable()
	if interactable is CupStack:
		_ghost.visible = false
		_ghost_valid = true # Valid to add to existing
		return

	# Only show ghost when on valid placement surface
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		return

	# Use collision-based overlap check
	_ghost.global_position = hit_point + Vector3(0, -_ghost.get_meta("bottom_offset", 0.0), 0)
	var look_dir := global_position - hit_point
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


func _update_ghost() -> void:
	# Handle cup box ghost preview
	if held_item == HeldItem.SUPPLY_BOX and held_item_data.get("ingredient_type") == "cups":
		_update_cup_box_ghost()
		return
	# Handle single cup ghost preview
	if held_item == HeldItem.CUP_EMPTY or held_item == HeldItem.CUP_FILLED:
		_update_single_cup_ghost()
		return
	if held_item != HeldItem.CONTAINER or _ghost == null:
		return

	# Pitcher snapping to press
	var container_type: String = held_item_data.get("container_type", "")
	if container_type == "pitcher":
		var press := _find_looked_at_press()
		if press != null:
			var recipe: Dictionary = held_item_data.get("saved_recipe", { })
			_ghost.global_position = press.get_snap_global_position()
			_ghost.visible = true
			if press.can_snap_pitcher(recipe):
				_ghost_valid = true
				_apply_ghost_material(_ghost, _get_ghost_mat_valid())
			else:
				_ghost_valid = false
				_apply_ghost_material(_ghost, _get_ghost_mat_invalid())
			return

	if not ray.is_colliding():
		_ghost.visible = false
		_ghost_valid = false
		return

	var collider := ray.get_collider()
	var on_surface := _is_placement_surface(collider)
	var hit_point := ray.get_collision_point()
	var hit_normal := ray.get_collision_normal()

	# Only show ghost when on valid placement surface
	if not on_surface:
		_ghost.visible = false
		_ghost_valid = false
		return

	_ghost.visible = true
	# Apply collision-based offset so ghost sits on surface
	var offset: float = _ghost.get_meta("bottom_offset", 0.0)
	_ghost.global_position = hit_point + Vector3(0, -offset, 0)
	# Keep ghost upright, face the player
	var look_dir := global_position - hit_point
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		_ghost.global_rotation.y = atan2(look_dir.x, look_dir.z)

	# Check for overlap with existing containers
	var overlapping := _check_ghost_overlap()
	var valid := not overlapping

	if valid != _ghost_valid:
		_ghost_valid = valid
		var mat := _get_ghost_mat_valid() if valid else _get_ghost_mat_invalid()
		_apply_ghost_material(_ghost, mat)


func _try_place_container() -> Node3D:
	if not _ghost_valid or _ghost == null:
		EventBus.interaction_hint_changed.emit("Can only place on stand or workstation!")
		return null

	var container_type: String = held_item_data.get("container_type", "")
	var scene: PackedScene = CONTAINER_SCENES.get(container_type)
	if scene == null:
		return null

	var instance := scene.instantiate()
	# Apply placement scale
	var scale: Vector3 = CONTAINER_PLACEMENT_SCALE.get(container_type, Vector3.ONE)
	instance.scale = scale
	# Restore saved contents (or empty if none)
	var saved_amount: float = held_item_data.get("saved_amount", 0.0)
	var saved_count: int = held_item_data.get("saved_count", 0)
	if "starting_amount" in instance:
		instance.starting_amount = saved_amount
	if "starting_count" in instance:
		instance.starting_count = saved_count
	get_tree().current_scene.add_child(instance)
	# Use same position as ghost (already includes collision offset)
	instance.global_position = _ghost.global_position
	instance.global_rotation = _ghost.global_rotation
	# Add to container group for overlap detection
	instance.add_to_group("container")
	# Add pitcher to pitcher group for water tap detection
	if instance is Pitcher:
		instance.add_to_group("pitcher")

	# Restore pitcher recipe (always — water may have been added while holding)
	if container_type == "pitcher" and instance is Pitcher:
		var recipe: Dictionary = held_item_data.get("saved_recipe", { })
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
		instance.call_deferred("_update_label")
		EventBus.pitcher_state_changed.emit(int(instance.state))

	_destroy_ghost()
	var container_type_str: String = held_item_data.get("container_type", "")
	clear_held()
	EventBus.container_placed.emit(container_type_str, instance)
	return instance


func _cancel_container_placement() -> void:
	var container_type: String = held_item_data.get("container_type", "")
	var cost := _get_container_cost(container_type)
	GameState.add_money(cost)
	_destroy_ghost()
	clear_held()
	EventBus.interaction_hint_changed.emit("Placement cancelled — $%.0f refunded" % cost)


func pickup_container(interactable: Interactable, container_type: String) -> void:
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

	EventBus.container_picked_up.emit(container_type, interactable)
	interactable.queue_free()
	hold_container(container_type, saved_amount, saved_count, has_liquid, saved_recipe)


func _find_customer_in_ancestors(node: Node) -> Customer:
	var current := node
	while current != null:
		if current is Customer:
			return current as Customer
		current = current.get_parent()
	return null


func _get_container_type_for_node(node: Node) -> String:
	if node is IngredientBin:
		var bin := node as IngredientBin
		match bin.ingredient_type:
			"lemon":
				return "lemon_bin"
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
	return ""


func _is_placement_surface(collider: Object) -> bool:
	if collider == null:
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


func _get_container_cost(container_type: String) -> float:
	match container_type:
		"lemon_bin":
			return Balancing.CONTAINER_COST_LEMON_BIN
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
	return 0.0


func _set_single_cup_visibility(node: Node) -> void:
	"""Show only the first cup in a cup stack (for ghost preview)."""
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
	"""Check if ghost overlaps with any existing placed containers using actual collision shapes."""
	if _ghost == null:
		return false

	# Get ghost's collision shape and transform
	var ghost_shape := _get_collision_shape(_ghost)
	if ghost_shape == null:
		return false
	var ghost_transform := _ghost.global_transform

	# Check against all placed containers
	for node in get_tree().get_nodes_in_group("container"):
		if node == _ghost:
			continue
		if node.is_in_group("ghost"):
			continue # Skip other ghosts
		if not (node is Node3D):
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
			var ghost_radius := _get_shape_radius(ghost_shape) * maxf(ghost_transform.basis.get_scale().x, ghost_transform.basis.get_scale().z)
			var other_radius := _get_shape_radius(other_shape) * maxf(other_transform.basis.get_scale().x, other_transform.basis.get_scale().z)
			var dist := ghost_transform.origin.distance_to(other_transform.origin)
			if dist < (ghost_radius + other_radius):
				return true

	return false


func _get_collision_shape(node: Node) -> Shape3D:
	"""Find the first CollisionShape3D in the node hierarchy and return its shape."""
	for child in node.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape
		var found := _get_collision_shape(child)
		if found != null:
			return found
	return null


func _get_shape_radius(shape: Shape3D) -> float:
	"""Get approximate radius for a shape."""
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return maxf(size.x, size.z) * 0.5
	elif shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	elif shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	return 0.5


func _boxes_intersect(a: BoxShape3D, a_transform: Transform3D, b: BoxShape3D, b_transform: Transform3D) -> bool:
	"""Check if two oriented boxes intersect using AABB approximation."""
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


func _cylinders_intersect(a: CylinderShape3D, a_transform: Transform3D, b: CylinderShape3D, b_transform: Transform3D) -> bool:
	"""Check if two cylinders intersect (horizontal distance check)."""
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
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_ghost_material(child, mat)


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
