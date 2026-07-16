extends Node
## Save/load game progress to user://save.json.

const SAVE_PATH: String = "user://save.json"

const CONTAINER_SCENES: Dictionary = {
	"fruit_bin": preload("res://scenes/objects/fruit_bin.tscn"),
	"sugar_bin": preload("res://scenes/objects/sugar_bin.tscn"),
	"ice_bin": preload("res://scenes/objects/ice_bin.tscn"),
	"pitcher": preload("res://scenes/objects/pitcher.tscn"),
	"press": preload("res://scenes/objects/press.tscn"),
	"water_dispenser": preload("res://scenes/objects/water_dispenser.tscn"),
	"cup_stack": preload("res://scenes/objects/cup_stack.tscn"),
}

# Workstation is loaded at runtime to avoid compile-time preload issues while the
# editor imports the new scene/script .uid files.
var _workstation_scene: PackedScene = null

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

var _pending_container_respawn: Array = []
var _pending_supply_box_respawn: Array = []


func _ready() -> void:
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_reset.connect(_on_game_reset)
	EventBus.container_placed.connect(func(_t, _n): save_game())
	EventBus.container_picked_up.connect(func(_t, _n): save_game())

	# Load the workstation scene at runtime to avoid compile-time preload issues
	# while the editor imports the new scene/script .uid files.
	_workstation_scene = load("res://scenes/stand/workstation.tscn") as PackedScene


func _get_container_scene(ctype: String) -> PackedScene:
	if ctype == "workstation":
		return _workstation_scene
	return CONTAINER_SCENES.get(ctype) as PackedScene


func _is_known_container_type(ctype: String) -> bool:
	return ctype in CONTAINER_SCENES or ctype == "workstation"


func save_game() -> void:
	var data := _build_save_dict()
	var json := JSON.stringify(data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		print("Game saved.")
	else:
		push_error("Failed to save game to %s" % SAVE_PATH)


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return { }
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return { }
	var json := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json)
	if parsed is Dictionary:
		return parsed
	return { }


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("Save deleted.")


func apply_save_to_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	_pending_container_respawn = data.get("placed_containers", [])
	_pending_supply_box_respawn = data.get("supply_boxes", [])
	GameState.money = data.get("money", Balancing.STARTING_MONEY)
	GameState.popularity = data.get("popularity", 0.1)
	GameState.temperature = data.get("temperature", 25.0)
	GameState.current_price = data.get("current_price", 1.5)
	GameState.feedback_tier = data.get("feedback_tier", 0)
	GameState.customers_served_happy = data.get("customers_served_happy", 0)
	GameState.customers_lost = data.get("customers_lost", 0)
	DayManager.day_number = data.get("day_number", 1)

	UpgradeManager.reset()
	var purchased_nodes_data = data.get("purchased_nodes", [])
	if purchased_nodes_data is Array and not purchased_nodes_data.is_empty():
		UpgradeManager.load_purchased_nodes(purchased_nodes_data)
	else:
		# Legacy level-based format
		var upgrade_data = data.get("upgrade_levels", { })
		if upgrade_data is Dictionary and not upgrade_data.is_empty():
			# Convert old levels to node purchases
			for id in upgrade_data:
				var lvl: int = int(upgrade_data[id])
				for i in range(lvl):
					UpgradeManager.purchase(str(id))
		else:
			var owned_upgrades: Array = data.get("owned_upgrades", [])
			UpgradeManager.load_legacy_upgrades(owned_upgrades)
	UpgradeManager.apply_all_effects()

	var _unlocked: Array = data.get("unlocked_fruits", ["lemon"])
	# TODO: wire to fruit unlock system when implemented

	EventBus.money_changed.emit(GameState.money)
	EventBus.popularity_changed.emit(GameState.popularity)
	EventBus.weather_changed.emit(GameState.temperature)
	EventBus.price_changed.emit(GameState.current_price)
	EventBus.feedback_tier_changed.emit(GameState.feedback_tier)


func _build_save_dict() -> Dictionary:
	return {
		"money": GameState.money,
		"popularity": GameState.popularity,
		"temperature": GameState.temperature,
		"current_price": GameState.current_price,
		"feedback_tier": GameState.feedback_tier,
		"customers_served_happy": GameState.customers_served_happy,
		"customers_lost": GameState.customers_lost,
		"day_number": DayManager.day_number,
		"purchased_nodes": UpgradeManager.get_save_data(),
		"unlocked_fruits": ["lemon"], # TODO: dynamic
		"placed_containers": _scan_placed_containers(),
		"supply_boxes": _scan_supply_boxes(),
		"version": 1,
	}


func _scan_placed_containers() -> Array:
	var result := []
	if get_tree() == null or get_tree().current_scene == null:
		return result
	var player: Node = get_tree().current_scene.get_node_or_null("Player")
	for node in get_tree().get_nodes_in_group("container"):
		# Skip containers currently held by the player
		if player != null and node.is_ancestor_of(player) or _is_child_of_player(node, player):
			continue
		var ctype := _get_container_type(node)
		if ctype == "" or not _is_known_container_type(ctype):
			continue
		var entry := {
			"type": ctype,
			"position": [
				node.global_position.x,
				node.global_position.y,
				node.global_position.z,
			],
			"rotation": [
				node.global_rotation.x,
				node.global_rotation.y,
				node.global_rotation.z,
			],
			"scale": [
				node.scale.x,
				node.scale.y,
				node.scale.z,
			],
		}
		# Capture container contents
		if node is FruitBin:
			entry["fruit_amounts"] = _dict_to_arrays(node.fruit_amounts)
		elif node is IngredientBin:
			entry["current_amount"] = node.current_amount
			entry["ingredient_type"] = node.ingredient_type
		elif node is Pitcher:
			entry["fruit_type"] = node.fruit_type
			entry["fruit_count"] = node.fruit_count
			entry["water"] = node.water
			entry["sugar"] = node.sugar
			entry["ice"] = node.ice
			entry["pitcher_state"] = int(node.state)
			entry["cups_poured"] = node.cups_poured
		elif node is CupStack:
			entry["current_count"] = node.current_count
		result.append(entry)
	return result


func _is_child_of_player(node: Node, player: Node) -> bool:
	if player == null or node == null:
		return false
	var parent := node.get_parent()
	while parent != null:
		if parent == player:
			return true
		parent = parent.get_parent()
	return false


func _dict_to_arrays(dict: Dictionary) -> Array:
	var result := []
	for key in dict:
		result.append([key, dict[key]])
	return result


func _arrays_to_dict(arrays: Array) -> Dictionary:
	var result := { }
	for pair in arrays:
		if pair is Array and pair.size() >= 2:
			result[pair[0]] = pair[1]
	return result


func _scan_supply_boxes() -> Array:
	var result := []
	if get_tree() == null or get_tree().current_scene == null:
		return result
	for node in get_tree().get_nodes_in_group("supply_box"):
		var box := node as SupplyBox
		if box == null:
			continue
		result.append(
			{
				"position": [
					box.global_position.x,
					box.global_position.y,
					box.global_position.z,
				],
				"rotation": [
					box.global_rotation.x,
					box.global_rotation.y,
					box.global_rotation.z,
				],
				"scale": [
					box.scale.x,
					box.scale.y,
					box.scale.z,
				],
				"ingredient_type": box.ingredient_type,
				"quantity": box.quantity,
				"is_equipment": box.is_equipment,
				"equipment_type": box.equipment_type,
			},
		)
	return result


func _get_container_type(node: Node) -> String:
	if node.has_meta("container_type"):
		return node.get_meta("container_type")
	if "container_type" in node:
		return node.container_type
	if node is FruitBin:
		return "fruit_bin"
	if node is IngredientBin:
		var itype: String = node.get("ingredient_type") if "ingredient_type" in node else ""
		match itype:
			"sugar":
				return "sugar_bin"
			"ice":
				return "ice_bin"
			_:
				return "fruit_bin"
	if node is Pitcher:
		return "pitcher"
	if node is Press:
		return "press"
	if node is WaterDispenser:
		return "water_dispenser"
	if node is CupStack:
		return "cup_stack"
	var node_script := node.get_script()
	if node_script != null and node_script.resource_path == "res://scripts/objects/workstation.gd":
		return "workstation"
	var n := node.name.to_lower()
	if n.contains("pitcher"):
		return "pitcher"
	if n.contains("press"):
		return "press"
	return ""


func respawn_placed_containers() -> void:
	call_deferred("_do_respawn")


func _do_respawn() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var root := get_tree().current_scene

	# --- Respawn containers ---
	var cdata: Array = _pending_container_respawn
	_pending_container_respawn = []
	if not cdata.is_empty():
		# Remove existing containers of known types so we don't duplicate
		for node in root.get_tree().get_nodes_in_group("container"):
			var ctype := _get_container_type(node)
			if ctype != "" and _is_known_container_type(ctype):
				node.queue_free()

		for entry in cdata:
			var ctype: String = entry.get("type", "")
			var pos: Array = entry.get("position", [])
			var rot: Array = entry.get("rotation", [])
			var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
			if ctype == "" or pos.size() < 3:
				continue
			var scene: PackedScene = _get_container_scene(ctype)
			if scene == null:
				continue
			var instance := scene.instantiate()
			# Set state BEFORE add_child so _ready() sees correct values
			if instance is CupStack:
				instance.starting_count = entry.get("current_count", instance.starting_count)
			if scl.size() >= 3:
				instance.scale = Vector3(scl[0], scl[1], scl[2])
			root.add_child(instance)
			instance.global_position = Vector3(pos[0], pos[1], pos[2])
			instance.global_rotation = Vector3(
				rot[0] if rot.size() > 0 else 0.0,
				rot[1] if rot.size() > 1 else 0.0,
				rot[2] if rot.size() > 2 else 0.0,
			)
			instance.add_to_group("container")

			# Restore container contents
			if instance is FruitBin:
				var fa: Array = entry.get("fruit_amounts", [])
				instance.fruit_amounts.clear()
				for pair in fa:
					if pair is Array and pair.size() >= 2:
						instance.fruit_amounts[pair[0]] = pair[1]
				instance.update_display()
			elif instance is IngredientBin:
				instance.current_amount = entry.get("current_amount", 0.0)
				var itype: String = entry.get("ingredient_type", "")
				if itype != "":
					instance.ingredient_type = itype
				instance.update_display()
			elif instance is Pitcher:
				instance.fruit_type = entry.get("fruit_type", "")
				instance.fruit_count = entry.get("fruit_count", 0.0)
				instance.water = entry.get("water", 0.0)
				instance.sugar = entry.get("sugar", 0.0)
				instance.ice = entry.get("ice", 0.0)
				instance.cups_poured = entry.get("cups_poured", 0)
				instance.state = entry.get("pitcher_state", 0) as Pitcher.PitcherState
				instance.add_to_group("pitcher")
				instance.set_pitcher_visible(true)
				instance.sync_fill_display()
				instance.update_liquid_color()
				instance.call_deferred("update_label")
				EventBus.pitcher_state_changed.emit(int(instance.state))
			else:
				if "starting_amount" in instance:
					instance.starting_amount = 0.0
				if "starting_count" in instance:
					instance.starting_count = 0

	# --- Respawn supply boxes ---
	var sdata: Array = _pending_supply_box_respawn
	_pending_supply_box_respawn = []
	if not sdata.is_empty():
		for node in root.get_tree().get_nodes_in_group("supply_box"):
			node.queue_free()

		for entry in sdata:
			var pos: Array = entry.get("position", [])
			var rot: Array = entry.get("rotation", [])
			var scl: Array = entry.get("scale", [1.0, 1.0, 1.0])
			if pos.size() < 3:
				continue
			var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
			# Set properties BEFORE add_child so _ready() uses correct values
			box.ingredient_type = entry.get("ingredient_type", "lemon")
			box.quantity = entry.get("quantity", 10.0)
			box.is_equipment = entry.get("is_equipment", false)
			box.equipment_type = entry.get("equipment_type", "")
			root.add_child(box)
			box.global_position = Vector3(pos[0], pos[1], pos[2])
			box.global_rotation = Vector3(
				rot[0] if rot.size() > 0 else 0.0,
				rot[1] if rot.size() > 1 else 0.0,
				rot[2] if rot.size() > 2 else 0.0,
			)
			if scl.size() >= 3:
				box.scale = Vector3(scl[0], scl[1], scl[2])
			box.add_to_group("supply_box")


func _on_game_saved() -> void:
	save_game()


func _on_game_reset() -> void:
	delete_save()
