class_name PlayerInteraction
extends Node
## Handles first-person raycast, interaction hints, and primary/secondary interact dispatch.

@onready var _player: Player = get_parent() as Player

## Currently highlighted interactable.
var hovered: Interactable = null

var _last_hint: String = ""
var _last_press_holding_fruit: bool = false

# --- Rapid-fire bin deposit ---
var _primary_held: bool = false
var _rapid_fire_timer: float = 0.0
# Cup stacks have a small collider (matching the real cup's size), so a tiny
# bit of mouse drift while holding can make the raycast momentarily miss it
# — especially right after placing the very first cup, when re-aiming is the
# only way it used to "reconnect". Remember the last cup stack we deposited
# into and keep targeting it while held, as long as it's still valid.
var _rapid_fire_cup_target: CupStack = null

# --- Per-frame lookup cache (avoids redundant tree walks) ---
var _frame_press: Press = null
var _frame_dispenser: WaterDispenser = null
var _frame_lookups_done: bool = false


func _ready() -> void:
	if _player == null:
		push_warning("PlayerInteraction: parent is not a Player")


## Tells the interaction module whether the player is in money mode so it can
## clear highlights and hints.
func set_money_mode(active: bool) -> void:
	if active and hovered and is_instance_valid(hovered):
		hovered.set_highlight(false)
		hovered = null
	if active:
		_last_hint = ""
		EventBus.interaction_hint_changed.emit("")


## Called from Player._unhandled_input to track the primary mouse button.
func set_primary_held(held: bool) -> void:
	_primary_held = held
	if held:
		_rapid_fire_timer = _player._get_rapid_fire_interval()
		_rapid_fire_cup_target = null
	else:
		_rapid_fire_cup_target = null


## Reset the per-frame press/dispenser cache at the start of each physics tick.
func update_frame_lookups() -> void:
	_frame_lookups_done = false


func poll_hint() -> void:
	var interactable := get_looked_at_interactable()
	if interactable != hovered:
		if hovered and is_instance_valid(hovered):
			hovered.set_highlight(false)
		hovered = interactable
		if hovered:
			hovered.set_highlight(true)
	elif hovered and is_instance_valid(hovered) and hovered is Press:
		# Re-apply highlight only when held-item state changes (not every frame)
		var holding_fruit_now: bool = _player.inventory.held_item == HeldItem.SUPPLY_BOX \
				and _player.inventory.held_item_data.get("source") == "bin_scoop"
		if holding_fruit_now != _last_press_holding_fruit:
			_last_press_holding_fruit = holding_fruit_now
			hovered.set_highlight(true)
	var hint := ""
	# Pedestrians show their own hint (offer / serve) regardless of held item.
	if interactable is PedestrianInteractable:
		hint = interactable.get_hint(_player)
		if hint != _last_hint:
			_last_hint = hint
			EventBus.interaction_hint_changed.emit(hint)
		return
	if _player.inventory.held_item_data.get("is_trash", false):
		if interactable != null and interactable.is_in_group("trashcan"):
			hint = interactable.get_hint(_player)
		elif _player.inventory.held_item_data.get("trash_type", "") == "empty_box":
			hint = "Trash | LMB: place or use trashcan"
		else:
			hint = "Trash | find a trashcan"
		if hint != _last_hint:
			_last_hint = hint
			EventBus.interaction_hint_changed.emit(hint)
		return
	if _player.inventory.held_item == HeldItem.CONTAINER:
		var container_type: String = _player.inventory.held_item_data.get("container_type", "")
		# Check if looking at trashcan for recycling
		if interactable != null and interactable.is_in_group("trashcan"):
			hint = interactable.get_hint(_player)
			if hint != _last_hint:
				_last_hint = hint
				EventBus.interaction_hint_changed.emit(hint)
			return
		# Check if looking at water tap with pitcher
		if interactable is WaterTap:
			if container_type == "pitcher":
				var _recipe: Dictionary = _player.inventory.held_item_data.get("saved_recipe", { })
				if _recipe.get("water", 0.0) > 0.0:
					hint = "Pitcher | already has water"
				else:
					hint = "Pitcher | LMB: fill with water"
			else:
				hint = "%s | LMB: place" % _player.inventory.get_held_item_name()
		else:
			hint = "%s | LMB: place" % _player.inventory.get_held_item_name()
		if container_type == "pitcher":
			var press := _find_looked_at_press()
			if press != null:
				var snap_recipe: Dictionary = _player.inventory.held_item_data.get(
					"saved_recipe",
					{ },
				)
				hint = press.get_pitcher_snap_hint(snap_recipe)
				return
			var dispenser := _find_looked_at_dispenser()
			if dispenser != null:
				hint = dispenser.get_hint(_player)
				return
		if _player.placement._ghost_valid:
			hint = "%s | LMB: place" % _player.inventory.get_held_item_name()
		else:
			if container_type == "workstation":
				hint = _player.HINT_GROUND
			else:
				hint = "%s | %s" % [_player.inventory.get_held_item_name(), _player.HINT_STAND]
		if container_type == "pitcher" and _player._held_pitcher_has_contents():
			hint += "  |  RMB: empty"
	elif _player.inventory.held_item == HeldItem.SUPPLY_BOX \
			and _player.inventory.held_item_data.get("source") == "bin_scoop":
		# Bin scoops can only be deposited into bins/presses/pitchers
		if interactable != null:
			hint = interactable.get_hint(_player)
		else:
			hint = "%s | aim at bin, press, or trash to deposit" % _player \
					.inventory \
					.get_held_item_name()
	elif _player.inventory.held_item == HeldItem.SUPPLY_BOX \
			and _player.inventory.held_item_data.get("ingredient_type") == "cups":
		var _held_name := _player.inventory.get_held_item_name()
		hint = "%s | LMB: place 1 cup" % _held_name
		if _player._is_aiming_at_grid():
			hint = "%s | LMB: place box on grid" % _held_name
		if interactable is SupplyBox:
			hint = "%s | LMB: stack box" % _held_name
		if interactable is CupStack:
			hint = "%s | LMB: add 1 cup" % _held_name
	elif _player.inventory.held_item == HeldItem.SUPPLY_BOX:
		var _hn := _player.inventory.get_held_item_name()
		hint = "%s | LMB: place box" % _hn
		if _player._is_aiming_at_grid():
			hint = "%s | LMB: place on grid" % _hn
		if interactable is SupplyBox:
			hint = "%s | LMB: stack on box" % _hn
	elif _player.inventory.held_item == HeldItem.CUP_EMPTY:
		hint = "Empty Cup | LMB: place cup"
		if interactable is CupStack:
			hint = "Empty Cup | LMB: add to stack"
	elif _player.inventory.held_item == HeldItem.CUP_FILLED:
		hint = "Filled Cup | LMB: place filled cup"
		if _player.ray.is_colliding():
			var hit_node: Node = _player.ray.get_collider() as Node
			var has_customer := _player._find_customer_in_ancestors(hit_node) != null
			var has_ped := _player._find_pedestrian_in_ancestors(hit_node) != null
			if has_customer or has_ped:
				hint = "Filled Cup | LMB: serve lemonade"
	else:
		hint = interactable.get_hint(_player) if interactable else ""
		# Append pickup hint when looking at a pickupable object with empty hands
		if interactable and _player.inventory.held_item == HeldItem.NONE:
			var pickupable := interactable.find_child("Pickupable", false, false)
			if (
				pickupable != null and pickupable.can_pick_up(_player)
				and not hint.contains("pick up")
			):
				hint = hint + "  |  RMB: pick up" if hint != "" else "RMB: pick up"
			elif not hint.contains("pick up"):
				# Also check container-based pickup (workstations, bins, etc.)
				var ctype := _player.placement._get_container_type_for_node(interactable)
				if ctype != "":
					hint = hint + "  |  RMB: pick up" if hint != "" else "RMB: pick up"
	if hint != _last_hint:
		_last_hint = hint
		EventBus.interaction_hint_changed.emit(hint)


func primary_interact() -> void:
	# Check if looking at an interactable first (even when holding items)
	var interactable := get_looked_at_interactable()

	# Walking pedestrians take priority: first click starts the offer no matter
	# what the player is holding. Subsequent clicks serve lemonade.
	if interactable is PedestrianInteractable:
		interactable.interact(_player)
		return

	# Unified pickup path: if the interactable has a Pickupable component and
	# we can pick it up, let it handle pickup/held-item setup.
	if _player.inventory.held_item == HeldItem.NONE and interactable != null:
		var pickupable := interactable.find_child("Pickupable", false, false)
		if pickupable != null and pickupable.can_pick_up(_player):
			pickupable.pick_up(_player)
			return

	# Trash items can be disposed of at a trashcan.
	# Empty box trash can also be placed on the ground like supply boxes.
	if _player.inventory.held_item_data.get("is_trash", false):
		var is_box_trash: bool = _player.inventory.held_item_data.get("trash_type", "") == "empty_box"
		if interactable != null and interactable.is_in_group("trashcan"):
			interactable.interact(_player)
			_player.placement._destroy_ghost()
			return
		# Also check ray collider ancestor chain for trashcan group
		if _player.ray.is_colliding():
			var node: Node = _player.ray.get_collider()
			while node != null:
				if node is Interactable and node.is_in_group("trashcan"):
					(node as Interactable).interact(_player)
					_player.placement._destroy_ghost()
					return
				node = node.get_parent()
		if is_box_trash:
			if _player.placement._ghost != null and _player.placement._ghost_valid:
				_player.placement._drop_trash(_player.placement._ghost.global_position)
			elif (
				_player.ray.is_colliding()
				and _player._is_placement_surface(_player.ray.get_collider())
			):
				_player.placement._drop_trash(
					_player.ray.get_collision_point() + Vector3(0, SupplyBox.bottom_offset, 0)
				)
			else:
				_player.placement._drop_trash()
		return

	# Containers can be recycled at a trashcan for 70% refund.
	if _player.inventory.held_item == HeldItem.CONTAINER:
		if interactable != null and interactable.is_in_group("trashcan"):
			interactable.interact(_player)
			return

	# Handle water tap interaction when holding pitcher - fill directly
	var container_type: String = ""
	if interactable is WaterTap and _player.inventory.held_item == HeldItem.CONTAINER:
		container_type = _player.inventory.held_item_data.get("container_type", "")
		if container_type == "pitcher":
			var recipe: Dictionary = _player.inventory.held_item_data.get("saved_recipe", { })
			var current_water: float = recipe.get("water", 0.0)
			if current_water <= 0.0:
				var current_fruit: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
				var liquid_volume: float = current_fruit + current_water
				var fill: float = Balancing.PITCHER_MAX_LIQUID - liquid_volume
				if fill > 0.0:
					recipe["water"] = current_water + fill
					_player.inventory.held_item_data["saved_recipe"] = recipe
					_player.inventory.held_item_data["has_liquid"] = true
					EventBus.pitcher_ingredient_added.emit("water", fill)
					# Animate eraser on the held mesh instead of recreating it
					var hand_mesh := _player.inventory.get_hand_mesh()
					if hand_mesh is Pitcher:
						(hand_mesh as Pitcher).fill_water_slow(fill, 4.0)
				EventBus.interaction_hint_changed.emit("Pitcher filled with water!")
			else:
				EventBus.interaction_hint_changed.emit("Pitcher already has water!")
			return

	if _player.inventory.held_item == HeldItem.CONTAINER:
		container_type = _player.inventory.held_item_data.get("container_type", "")
		if container_type == "pitcher":
			var press := _find_looked_at_press()
			if press != null:
				var snap_recipe: Dictionary = _player.inventory.held_item_data.get(
					"saved_recipe",
					{ },
				)
				if press.can_snap_pitcher(snap_recipe):
					_player.placement._ghost.global_position = press.get_snap_global_position()
					_player.placement._ghost_valid = true
					var placed := _player.placement._try_place_container()
					if placed is Pitcher:
						press.snap_pitcher(placed as Pitcher)
					return
				EventBus.interaction_hint_changed.emit(press.get_pitcher_snap_hint(snap_recipe))
				return
			var dispenser := _find_looked_at_dispenser()
			if dispenser != null:
				var _recipe: Dictionary = _player.inventory.held_item_data.get("saved_recipe", { })
				if dispenser.can_snap_pitcher_from_recipe(_recipe):
					_player.placement._ghost.global_position = dispenser.get_snap_global_position()
					_player.placement._ghost_valid = true
					var placed := _player.placement._try_place_container()
					if placed is Pitcher:
						dispenser.snap_pitcher(placed as Pitcher)
					return
				# Can't snap to dispenser — fall through to normal placement
		var from_box: bool = _player.inventory.held_item_data.get("from_delivery_box", false)
		if from_box and _player.ray.is_colliding():
			var node: Node = _player.ray.get_collider()
			while node != null:
				if node is SupplyBox:
					_player.placement._ghost_valid = true
					var box_pos := (node as SupplyBox).global_position
					var g := _player.placement._ghost
					var offset: float = g.get_meta("bottom_offset", 0.0) if g else 0.0
					_player.placement._ghost.global_position = box_pos + Vector3(
						0,
						0.262 - offset,
						0,
					)
					_player.placement._try_place_container()
					return
				node = node.get_parent()
			# Ground placement for equipment boxes
			if not _player._is_placement_surface(_player.ray.get_collider()):
				_player.placement._ghost_valid = false
				return
		_player.placement._try_place_container()
		return

	# Handle single empty cup placement or pitcher interaction
	if _player.inventory.held_item == HeldItem.CUP_EMPTY:
		# First check if looking at a pitcher to fill cup
		if interactable is Pitcher:
			_player.last_interact_hit = _player.ray.get_collider()
			(interactable as Pitcher).interact(_player)
			_player.last_interact_hit = null
			return
		# Then check for cup stack
		if interactable is CupStack:
			_player.last_interact_hit = _player.ray.get_collider()
			(interactable as CupStack).interact(_player)
			_player.last_interact_hit = null
			return
		# Then check for water tap
		if interactable is WaterTap:
			_player.last_interact_hit = _player.ray.get_collider()
			(interactable as WaterTap).interact(_player)
			_player.last_interact_hit = null
			return
		# Place on surface to start new stack
		if _player.ray.is_colliding() and _player._is_placement_surface(_player.ray.get_collider()):
			_player.placement._place_single_cup(false)
			return
		return

	# Handle filled cup - serve to customer or place on surface
	if _player.inventory.held_item == HeldItem.CUP_FILLED:
		# First check if looking at a customer or pedestrian to serve.
		if _player.ray.is_colliding():
			var hit_node: Node = _player.ray.get_collider() as Node
			var customer: Customer = _player._find_customer_in_ancestors(hit_node)
			if customer != null:
				var peer_id := int(_player.name)
				var recipe_data: Dictionary = _player.inventory.held_item_data.get("recipe", { })
				customer.request_serve(peer_id, recipe_data)
				return
			var ped: Pedestrian = _player._find_pedestrian_in_ancestors(hit_node)
			if ped != null:
				var peer_id := int(_player.name)
				var recipe_data: Dictionary = _player.inventory.held_item_data.get("recipe", { })
				ped.request_serve(peer_id, recipe_data)
				return
		# Then place on surface (only on workstation/stand, not ground)
		if _player.ray.is_colliding():
			var collider := _player.ray.get_collider()
			if _player._is_placement_surface(collider) and not _player._is_ground_surface(collider):
				_player.placement._place_filled_cup()
				return
		return

	# Special handling for cup box - place stack on surface or deposit to existing
	if _player.inventory.held_item == HeldItem.SUPPLY_BOX \
			and _player.inventory.held_item_data.get("source") == "delivery" \
			and _player.inventory.held_item_data.get("ingredient_type") == "cups":
		if _player.ray.is_colliding():
			var node: Node = _player.ray.get_collider()
			while node != null:
				if node is SupplyBox:
					# Stack the cup box on top of the hovered stack
					_player.placement._place_held_supply_box_on_stack(node as SupplyBox)
					return
				if node is DeliveryGrid:
					# Place on the delivery grid
					_player.placement._place_held_supply_box_on_grid(
						node as DeliveryGrid,
						_player.ray.get_collision_point(),
					)
					return
				node = node.get_parent()
		if interactable is CupStack:
			# Deposit to existing stack
			_rapid_fire_cup_target = interactable as CupStack
			_player.last_interact_hit = _player.ray.get_collider()
			interactable.interact(_player)
			_player.last_interact_hit = null
			return
		if _player.ray.is_colliding():
			var collider := _player.ray.get_collider()
			if _player._is_placement_surface(collider):
				if _player._is_ground_surface(collider):
					# Floor — drop the box
					_player.placement._place_held_supply_box_on(
						_player.ray.get_collision_point() + Vector3(0, SupplyBox.bottom_offset, 0),
					)
					return
				# Workstation/stand — place cup stack
				_player.placement._place_cup_stack_from_box()
				return
		# Fallback: drop the box
		_player.placement._drop_held_box()
		return

	# Handle non-cup supply box placement (stack on boxes or place on ground)
	if (
		_player.inventory.held_item == HeldItem.SUPPLY_BOX
		and _player.inventory.held_item_data.get("source") == "delivery"
	) \
			and _player.inventory.held_item_data.get("ingredient_type") != "cups":
		var is_equipment: bool = _player.inventory.held_item_data.get("is_equipment", false)
		if _player.ray.is_colliding():
			var node: Node = _player.ray.get_collider()
			while node != null:
				if node is SupplyBox:
					_player.placement._place_held_supply_box_on_stack(node as SupplyBox)
					return
				if node is DeliveryGrid:
					_player.placement._place_held_supply_box_on_grid(
						node as DeliveryGrid,
						_player.ray.get_collision_point(),
					)
					return
				node = node.get_parent()
			# Check if looking at a matching ingredient bin or water dispenser
			if not is_equipment:
				if interactable is IngredientBin:
					var bin := interactable as IngredientBin
					if bin.ingredient_type == _player.inventory.held_item_data.get(
						"ingredient_type",
						"",
					):
						_player.last_interact_hit = _player.ray.get_collider()
						bin.interact(_player)
						_player.last_interact_hit = null
						return
				if interactable is FruitBin:
					var fbin := interactable as FruitBin
					var itype: String = _player.inventory.held_item_data.get("ingredient_type", "")
					if fbin.fruit_grids.has(itype):
						_player.last_interact_hit = _player.ray.get_collider()
						fbin.interact(_player)
						_player.last_interact_hit = null
						return
				if interactable is WaterDispenser:
					if _player.inventory.held_item_data.get("ingredient_type", "") == "water":
						_player.last_interact_hit = _player.ray.get_collider()
						interactable.interact(_player)
						_player.last_interact_hit = null
						return
			var collider := _player.ray.get_collider()
			var on_surface := _player._is_placement_surface(collider)
			var is_ground := _player._is_ground_surface(collider)
			var equipment_type: String = _player.inventory.held_item_data.get("equipment_type", "")
			if (
				is_equipment
				and (
					on_surface and not is_ground and equipment_type != "workstation"
					or is_ground and equipment_type == "workstation"
				)
			):
				# Place working equipment on workstation (or floor for tables)
				_player.placement._place_equipment_from_box()
				return
			if on_surface and not is_equipment:
				# Place ingredient box on a surface
				_player.placement._place_held_supply_box_on(
					_player.ray.get_collision_point() + Vector3(0, SupplyBox.bottom_offset, 0),
				)
				return
		_player.placement._drop_held_box()
		return

	# Handle fallback interactables (not caught by specific cases above)
	var fallback_interactable := get_looked_at_interactable()
	if fallback_interactable:
		_player.last_interact_hit = _player.ray.get_collider()
		fallback_interactable.interact(_player)
		_player.last_interact_hit = null
	elif (
		_player.inventory.held_item == HeldItem.SUPPLY_BOX
		and _player.inventory.held_item_data.get("source") == "delivery"
	):
		_player.placement._drop_held_box()


func secondary_interact() -> void:
	# Holding a pitcher: RMB always empties it, regardless of what's being
	# looked at.
	if (
		_player.inventory.held_item == HeldItem.CONTAINER
		and _player.inventory.held_item_data.get("container_type", "") == "pitcher"
	):
		_player._empty_held_pitcher()
		return

	var interactable := get_looked_at_interactable()
	if interactable:
		# If hands empty and looking at container, pick it up
		if _player.inventory.held_item == HeldItem.NONE:
			# Press with snapped pitcher: pick up the pitcher, not the press
			if interactable is Press and (interactable as Press).has_snapped_pitcher():
				(interactable as Press).interact(_player)
				return
			var ctype := _player.placement._get_container_type_for_node(interactable)
			if ctype != "":
				_player.pickup_container(interactable, ctype)
				return
		# Otherwise let the interactable handle secondary interact
		interactable.interact_secondary(_player)
		return

	# Drop supply box or empty box trash
	if (
		_player.inventory.held_item == HeldItem.SUPPLY_BOX
		and _player.inventory.held_item_data.get("source") == "delivery"
	):
		_player.placement._drop_held_box()
	elif _player.inventory.held_item == HeldItem.TRASH \
			and _player.inventory.held_item_data.get("trash_type", "") == "empty_box":
		_player.placement._drop_trash()


func update_rapid_fire(delta: float) -> void:
	if not _primary_held:
		return
	if _player.inventory.held_item != HeldItem.SUPPLY_BOX:
		return
	if _player.inventory.held_item_data.get("is_trash", false):
		return
	if _player.inventory.held_item_data.get("source") != "delivery":
		return

	_rapid_fire_timer -= delta
	if _rapid_fire_timer > 0.0:
		return

	var interactable := get_looked_at_interactable()

	# Handle cup stack deposits
	var cup_stack := interactable as CupStack
	if cup_stack != null:
		_rapid_fire_cup_target = cup_stack
	elif _player.inventory.held_item_data.get("ingredient_type", "") == "cups" \
			and is_instance_valid(_rapid_fire_cup_target):
		# Raycast momentarily missed the (small) cup stack collider; keep
		# depositing into the last one we hit rather than stalling out.
		cup_stack = _rapid_fire_cup_target
	if cup_stack != null:
		if _player.inventory.held_item_data.get("ingredient_type", "") != "cups":
			return
		if cup_stack.current_count >= cup_stack.max_capacity:
			return
		var amount: float = _player.inventory.held_item_data.get("amount", 0.0)
		if amount <= 0.0:
			return
		_rapid_fire_timer = _player._get_rapid_fire_interval()
		_player.last_interact_hit = _player.ray.get_collider()
		cup_stack.interact(_player)
		_player.last_interact_hit = null
		return

	# Handle water dispenser refill
	var dispenser := interactable as WaterDispenser
	if dispenser != null:
		if _player.inventory.held_item_data.get("ingredient_type", "") != "water":
			return
		if dispenser.water_fillings >= dispenser.max_fillings:
			return
		var amount: float = _player.inventory.held_item_data.get("amount", 0.0)
		if amount <= 0.0:
			return
		_rapid_fire_timer = _player._get_rapid_fire_interval()
		_player.last_interact_hit = _player.ray.get_collider()
		dispenser.interact(_player)
		_player.last_interact_hit = null
		return

	# Handle ingredient bin deposits
	var bin := interactable as IngredientBin
	if bin != null:
		if bin.ingredient_type == _player.inventory.held_item_data.get("ingredient_type", ""):
			if bin.current_amount < bin.max_capacity:
				var amount: float = _player.inventory.held_item_data.get("amount", 0.0)
				if amount > 0.0:
					_rapid_fire_timer = _player._get_rapid_fire_interval()
					_player.last_interact_hit = _player.ray.get_collider()
					bin.interact(_player)
					_player.last_interact_hit = null
		return
	var fbin := interactable as FruitBin
	if fbin != null:
		var itype: String = _player.inventory.held_item_data.get("ingredient_type", "")
		if fbin.fruit_grids.has(itype):
			var amt: float = _player.inventory.held_item_data.get("amount", 0.0)
			if amt > 0.0 and fbin.fruit_amounts.get(itype, 0.0) < fbin.get_capacity(itype):
				_rapid_fire_timer = _player._get_rapid_fire_interval()
				_player.last_interact_hit = _player.ray.get_collider()
				fbin.interact(_player)
				_player.last_interact_hit = null
		return


func get_looked_at_interactable() -> Interactable:
	if not _player.ray.is_colliding():
		return null
	var node: Node = _player.ray.get_collider()
	if node == null:
		return null
	var chain := node
	while chain != null:
		if chain is Interactable:
			return chain as Interactable
		chain = chain.get_parent()
	return null


## Public wrapper for placement code that needs the currently looked-at press.
func find_looked_at_press() -> Press:
	return _find_looked_at_press()


## Public wrapper for placement code that needs the currently looked-at dispenser.
func find_looked_at_dispenser() -> WaterDispenser:
	return _find_looked_at_dispenser()


## The rapid-fire cup target is read/written by both interaction and placement.
func get_rapid_fire_cup_target() -> CupStack:
	return _rapid_fire_cup_target


func set_rapid_fire_cup_target(target: CupStack) -> void:
	_rapid_fire_cup_target = target


func _find_looked_at_press() -> Press:
	if _frame_lookups_done:
		return _frame_press
	_frame_lookups_done = true
	_frame_press = null
	_frame_dispenser = null
	# Standard interactable lookup
	var interactable := get_looked_at_interactable()
	if interactable is Press:
		_frame_press = interactable as Press
		return _frame_press
	if interactable is WaterDispenser:
		_frame_dispenser = interactable as WaterDispenser
	# Fallback: walk up from direct collider (deeper search)
	if _player.ray.is_colliding():
		var node := _player.ray.get_collider()
		for i in range(6):
			if node == null:
				break
			if node is Press and _frame_press == null:
				_frame_press = node as Press
			if node is WaterDispenser and _frame_dispenser == null:
				_frame_dispenser = node as WaterDispenser
			if _frame_press != null and _frame_dispenser != null:
				break
			node = node.get_parent()
	return _frame_press


func _find_looked_at_dispenser() -> WaterDispenser:
	if _frame_lookups_done:
		return _frame_dispenser
	_frame_lookups_done = true
	_frame_press = null
	_frame_dispenser = null
	var interactable := get_looked_at_interactable()
	if interactable is Press:
		_frame_press = interactable as Press
	if interactable is WaterDispenser:
		_frame_dispenser = interactable as WaterDispenser
	if _player.ray.is_colliding():
		var node := _player.ray.get_collider()
		for i in range(6):
			if node == null:
				break
			if node is Press and _frame_press == null:
				_frame_press = node as Press
			if node is WaterDispenser and _frame_dispenser == null:
				_frame_dispenser = node as WaterDispenser
			if _frame_press != null and _frame_dispenser != null:
				break
			node = node.get_parent()
	return _frame_dispenser
