class_name FruitBin
extends Interactable
## Multi-fruit bin with separate visual grids per fruit type.
## Each fruit type has its own ItemGrid_* child (e.g. ItemGrid_Lemon).
## The user places fruit models inside each grid in the editor.

@export var drop_height: float = 0.35
@export var starting_amount: float = 10.0

## fruit_type -> amount
var fruit_amounts: Dictionary[String, float] = { }

## fruit_type -> {
##   nodes: Array[Node3D],
##   origins: Array[Vector3],
##   capacity: int,
##   starting_amount: float,
##   drop_height: float,
## }
var fruit_grids: Dictionary[String, Dictionary] = { }


func _ready() -> void:
	add_to_group("bin")
	add_to_group("container")
	Pickupable.setup_for_container(self, "fruit_bin")
	# Discover ItemGrid_* children
	for child in get_children():
		var name: String = child.name
		if name.begins_with("ItemGrid_"):
			var fruit_type := name.substr(9).to_lower() # after "ItemGrid_"
			var nodes: Array[Node3D] = []
			var origins: Array[Vector3] = []
			for item in child.get_children():
				nodes.append(item as Node3D)
				origins.append(item.position)
			var grid_capacity: int = nodes.size()
			var grid_starting: float = self.starting_amount
			var grid_drop: float = self.drop_height
			if "capacity" in child:
				var cap = child.get("capacity")
				if cap is int and cap >= 0:
					grid_capacity = cap
			if "starting_amount" in child:
				var sa = child.get("starting_amount")
				if sa is float and sa >= 0.0:
					grid_starting = sa
			if "drop_height" in child:
				var dh = child.get("drop_height")
				if dh is float and dh >= 0.0:
					grid_drop = dh
			fruit_grids[fruit_type] = {
				"nodes": nodes,
				"origins": origins,
				"capacity": grid_capacity,
				"starting_amount": grid_starting,
				"drop_height": grid_drop,
			}
			if not fruit_amounts.has(fruit_type):
				fruit_amounts[fruit_type] = grid_starting

	if Engine.is_editor_hint():
		# Show all items in editor
		for data in fruit_grids.values():
			for node in data["nodes"]:
				node.visible = true
		return

	update_display()
	EventBus.debug_refill_all_bins.connect(_on_debug_refill)


func update_display() -> void:
	for fruit_type in fruit_grids.keys():
		var data: Dictionary = fruit_grids[fruit_type]
		var nodes: Array[Node3D] = data["nodes"]
		var amount: float = fruit_amounts.get(fruit_type, 0.0)
		var cap: int = data["capacity"]
		var visible_count: int = mini(roundi(amount), cap)
		for i in range(nodes.size()):
			nodes[i].visible = i < visible_count


func add_amount(fruit_type: String, qty: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	if not fruit_grids.has(fruit_type):
		return
	# Client-side: send a request to the host. Do NOT mutate locally so the
	# host stays the single source of truth and there is no double application.
	if not WorldSync.is_host():
		_rpc_request_add_amount.rpc_id(1, fruit_type, qty, from_pos)
		return
	_apply_add_amount(fruit_type, qty, from_pos)
	_sync_state_to_peers()


func _apply_add_amount(fruit_type: String, qty: float, from_pos: Vector3 = Vector3.ZERO) -> void:
	# One-fruit-type rule: if the bin already contains a different fruit,
	# refuse to add this one until the bin is emptied.
	for ft in fruit_amounts.keys():
		if ft != fruit_type and fruit_amounts[ft] > 0.0:
			return
	var data: Dictionary = fruit_grids[fruit_type]
	var nodes: Array[Node3D] = data["nodes"]
	var cap: int = data["capacity"]
	var old_count := mini(roundi(fruit_amounts.get(fruit_type, 0.0)), cap)
	fruit_amounts[fruit_type] = minf(fruit_amounts.get(fruit_type, 0.0) + qty, cap)
	update_display()
	var new_count := mini(roundi(fruit_amounts[fruit_type]), cap)
	var origins: Array[Vector3] = data["origins"]
	var grid_drop: float = data["drop_height"]
	for i in range(old_count, new_count):
		_drop_item(nodes[i], origins[i], grid_drop, from_pos)
	EventBus.bin_amount_changed.emit(fruit_type, fruit_amounts[fruit_type])


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_add_amount(fruit_type: String, qty: float, from_pos: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	add_amount(fruit_type, qty, from_pos)


func _sync_state_to_peers() -> void:
	WorldSync.sync_property(self, "fruit_amounts", fruit_amounts.duplicate(true))
	WorldSync.sync_call(self, "update_display")


func _drop_item(
	node: Node3D,
	origin: Vector3,
	item_drop_height: float,
	from_pos: Vector3 = Vector3.ZERO,
) -> void:
	if from_pos != Vector3.ZERO:
		var tween := _animate_throw_arc(node, from_pos, origin)
		if tween != null:
			tween.finished.connect(
				func():
					AudioManager.play_sfx("fruit_in_crate", global_position),
			)
		return
	node.position.y = origin.y + item_drop_height
	var tween := create_tween()
	tween.tween_property(node, "position:y", origin.y, 0.25) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.finished.connect(
		func():
			AudioManager.play_sfx("fruit_in_crate", global_position),
	)


func take_amount(fruit_type: String, qty: float) -> float:
	if not fruit_amounts.has(fruit_type):
		return 0.0
	# Client-side: send a request to the host and do not mutate locally.
	if not WorldSync.is_host():
		_rpc_request_take_amount.rpc_id(1, fruit_type, qty)
		return 0.0
	var taken := _apply_take_amount(fruit_type, qty)
	_sync_state_to_peers()
	return taken


func _apply_take_amount(fruit_type: String, qty: float) -> float:
	if not fruit_amounts.has(fruit_type):
		return 0.0
	var taken := minf(qty, fruit_amounts[fruit_type])
	fruit_amounts[fruit_type] -= taken
	update_display()
	EventBus.bin_amount_changed.emit(fruit_type, fruit_amounts[fruit_type])
	return taken


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_take_amount(fruit_type: String, qty: float) -> void:
	if not is_multiplayer_authority():
		return
	take_amount(fruit_type, qty)


func _get_fruit_type_from_hit(hit_node: Node) -> String:
	if hit_node == null:
		return ""
	var chain := hit_node
	while chain != null and chain != self:
		var name: String = chain.name
		if name.begins_with("ItemGrid_"):
			return name.substr(9).to_lower()
		chain = chain.get_parent()
	return ""


func _get_first_available_fruit() -> String:
	for fruit_type in fruit_grids.keys():
		if fruit_amounts.get(fruit_type, 0.0) >= Balancing.GRAB_AMOUNT:
			return fruit_type
	return ""


func get_capacity(fruit_type: String) -> int:
	if not fruit_grids.has(fruit_type):
		return 0
	return fruit_grids[fruit_type]["capacity"]


# Local constants matching Player.HeldItem enum
const HELD_NONE := 0
const HELD_SUPPLY_BOX := 3


func interact(player: Node) -> void:
	# Only the stand that owns this bin can interact with it.
	if not Interactable.can_player_use(player, self):
		return
	var held_item: int = player.get("held_item")
	var data: Dictionary = player.get("held_item_data")

	if held_item == HELD_SUPPLY_BOX:
		# Deposit
		var itype: String = data.get("ingredient_type", "")
		if not fruit_grids.has(itype):
			return
		# Returning a scoop
		if data.get("source") == "bin_scoop":
			var scoop_space: float = get_capacity(itype) - fruit_amounts.get(itype, 0.0)
			if scoop_space <= 0.0:
				return
			add_amount(itype, data.get("amount", Balancing.GRAB_AMOUNT), _get_hand_pos(player))
			player.inventory.clear_held()
			return
		# Depositing from delivery box
		if data.get("source") == "delivery":
			# A box can only be deposited into a bin on the same stand.
			var box_owner: String = data.get("box_stand_owner", "")
			if box_owner != "" and stand_owner != "" and box_owner != stand_owner:
				EventBus.interaction_hint_changed.emit(
					"Can only deposit into your own stand's bins!"
				)
				return
			var to_deposit: float = data.get("amount", 0.0)
			# One-fruit-type rule: refuse if bin has a different fruit.
			for ft in fruit_amounts.keys():
				if ft != itype and fruit_amounts[ft] > 0.0:
					return
			var space: float = get_capacity(itype) - fruit_amounts.get(itype, 0.0)
			if space <= 0.0:
				return
			# Deposit one unit per click so the player sees the bin fill up.
			var deposited: float = minf(Balancing.GRAB_AMOUNT, minf(to_deposit, space))
			add_amount(itype, deposited, _get_hand_pos(player))
			EventBus.supply_box_deposited.emit(itype, deposited)
			var remaining: float = to_deposit - deposited
			if remaining > 0.0:
				player.inventory.update_held_amount(remaining)
			else:
				player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
		return

	# Take
	if held_item == HELD_NONE:
		var hit_node: Node = player.get("last_interact_hit")
		var fruit_type := _get_fruit_type_from_hit(hit_node)
		if fruit_type == "" or fruit_amounts.get(fruit_type, 0.0) < Balancing.GRAB_AMOUNT:
			# Fallback to first available fruit
			fruit_type = _get_first_available_fruit()
		if fruit_type == "":
			# Bin is empty - pick up the container
			player.pickup_container(self, "fruit_bin")
			return
		take_amount(fruit_type, Balancing.GRAB_AMOUNT)
		AudioManager.play_sfx("fruit_pickup_from_crate", global_position)
		player.inventory.set_held(
			HELD_SUPPLY_BOX,
			{
				"ingredient_type": fruit_type,
				"amount": Balancing.GRAB_AMOUNT,
				"source": "bin_scoop",
			},
			_make_hand_mesh(fruit_type),
		)
		EventBus.ingredient_scoop_grabbed.emit(fruit_type, Balancing.GRAB_AMOUNT)


func get_hint(player: Node) -> String:
	if not player.has_node("PlayerInventory"):
		return ""
	var held_item: int = player.get("held_item")
	var data: Dictionary = player.get("held_item_data")

	if held_item == HELD_SUPPLY_BOX:
		if data.get("is_trash", false):
			return ""
		var itype: String = data.get("ingredient_type", "")
		if not fruit_grids.has(itype):
			return "Fruit Bin | no %s grid" % itype.capitalize()
		if data.get("source") == "bin_scoop":
			return "Fruit Bin | LMB: return %s" % itype.capitalize()
		if data.get("source") == "delivery":
			var space: float = get_capacity(itype) - fruit_amounts.get(itype, 0.0)
			if space <= 0.0:
				return "Fruit Bin | %s full!" % itype.capitalize()
			var box_amount: float = data.get("amount", 0.0)
			return "Fruit Bin | LMB: deposit %s (x%.0f in box)" % [itype.capitalize(), box_amount]
		return ""

	if held_item == HELD_NONE:
		var hit_node: Node = player.get("last_interact_hit")
		var fruit_type := _get_fruit_type_from_hit(hit_node)
		if fruit_type != "" and fruit_amounts.get(fruit_type, 0.0) >= Balancing.GRAB_AMOUNT:
			return "Fruit Bin | LMB: take %s (%.0f)  |  RMB: pick up" % [
				fruit_type.capitalize(),
				fruit_amounts[fruit_type],
			]
		# Fallback to first available
		fruit_type = _get_first_available_fruit()
		if fruit_type != "":
			return "Fruit Bin | LMB: take %s (%.0f)  |  RMB: pick up" % [
				fruit_type.capitalize(),
				fruit_amounts[fruit_type],
			]
		return "Fruit Bin | LMB: pick up"
	return ""


func _make_hand_mesh(fruit_type: String) -> Node3D:
	var path := "res://assets/models/props/%s.glb" % fruit_type
	var s := load(path) as PackedScene
	if s:
		var inst := s.instantiate() as Node3D
		inst.scale = Vector3.ONE * 0.075
		return inst
	# Fallback sphere
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.038
	sphere.height = 0.076
	m.mesh = sphere
	return m


func _on_debug_refill() -> void:
	for fruit_type in fruit_grids.keys():
		fruit_amounts[fruit_type] = get_capacity(fruit_type)
	update_display()
	for fruit_type in fruit_grids.keys():
		EventBus.bin_amount_changed.emit(fruit_type, fruit_amounts[fruit_type])
