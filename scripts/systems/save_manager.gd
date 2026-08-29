extends Node
## Save/load game progress to user://saves/<slot_name>.json.
## Supports multiple save slots so the host can start New Game (fresh)
## or Load Game (pick a previous save).

const SAVE_DIR: String = "user://saves/"
const LEGACY_SAVE_PATH: String = "user://save.json"
const MAX_SLOTS: int = 20

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
var _default_container_positions: Array = []

## The currently active save slot (set when hosting New Game or Load Game).
## Empty string means no save loaded (fresh start, no auto-saving).
var current_slot: String = ""

## When true, auto-save to current_slot on state changes. Only the host
## should auto-save.
var auto_save_enabled: bool = false


func _ready() -> void:
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_reset.connect(_on_game_reset)
	EventBus.container_placed.connect(
		func(_t, _n):
			save_game(),
	)
	EventBus.container_picked_up.connect(
		func(_t, _n):
			save_game(),
	)
	EventBus.supply_box_spawned.connect(
		func(_b):
			save_game(),
	)
	EventBus.bin_amount_changed.connect(
		func(_t, _a):
			save_game(),
	)
	EventBus.cup_stack_changed.connect(
		func(_c):
			save_game(),
	)
	EventBus.pitcher_state_changed.connect(
		func(_s):
			save_game(),
	)

	# Load the workstation scene at runtime to avoid compile-time preload issues
	# while the editor imports the new scene/script .uid files.
	_workstation_scene = load("res://scenes/stand/workstation.tscn") as PackedScene

	# Migrate legacy save to slot system if needed
	_migrate_legacy_save()


func _get_container_scene(ctype: String) -> PackedScene:
	if ctype == "workstation":
		return _workstation_scene
	return CONTAINER_SCENES.get(ctype) as PackedScene


func _is_known_container_type(ctype: String) -> bool:
	return ctype in CONTAINER_SCENES or ctype == "workstation"


func save_game(force: bool = false) -> void:
	# Only the host auto-saves. Clients receive state via RPCs and
	# should never write save files (they'd be incomplete/out of sync).
	# 'force' bypasses the host check (used when creating a new game
	# from the main menu before networking is set up).
	if not force and not WorldSync.is_host():
		return
	if not auto_save_enabled or current_slot == "":
		return
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := _build_save_dict()
	data["slot_name"] = current_slot
	data["saved_at"] = Time.get_unix_time_from_system()
	var json := JSON.stringify(data)
	var path := _slot_path(current_slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
	else:
		push_error("Failed to save game to %s (error %d)" % [path, FileAccess.get_open_error()])


func load_game() -> Dictionary:
	return load_slot(current_slot)


func load_slot(slot_name: String) -> Dictionary:
	if slot_name == "":
		return { }
	var path := _slot_path(slot_name)
	if not FileAccess.file_exists(path):
		return { }
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { }
	var json := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json)
	if parsed is Dictionary:
		return parsed
	return { }


func has_save() -> bool:
	return current_slot != "" and FileAccess.file_exists(_slot_path(current_slot))


func delete_save() -> void:
	if current_slot != "" and FileAccess.file_exists(_slot_path(current_slot)):
		DirAccess.remove_absolute(_slot_path(current_slot))
		print("Save deleted: ", current_slot)


func delete_slot(slot_name: String) -> void:
	var path := _slot_path(slot_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("Save deleted: ", slot_name)


## Returns info about all save slots for the Load Game UI.
## Each entry: { "slot": String, "stand_name": String, "day": int,
##               "money": float, "saved_at": float (unix timestamp) }
## Only shows saves created by the local Steam user (so joiners don't
## see the host's stands in their saves list). If Steam ID is 0 (not
## initialized yet), shows all saves to avoid hiding everything.
func list_saves() -> Array:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return []
	var my_steam_id: int = NetworkManager.steam_id
	var saves: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var slot_name := file_name.get_basename()
			var data := load_slot(slot_name)
			if not data.is_empty():
				# Filter by creator Steam ID so joiners don't see the
				# host's saves. Only filter when we have a valid Steam ID
				# AND the save has a valid creator ID. This prevents
				# hiding all saves when Steam isn't initialized yet.
				var creator_id: int = int(data.get("creator_steam_id", 0))
				if my_steam_id != 0 and creator_id != 0 and creator_id != my_steam_id:
					file_name = dir.get_next()
					continue
				saves.append(
					{
						"slot": slot_name,
						"stand_name": data.get("stand_name", slot_name),
						"game_mode": data.get("game_mode", GameState.GameMode.SOLO)
						as GameState.GameMode,
						"day": data.get("day_number", 1),
						"money": data.get("money", 0.0),
						"saved_at": data.get("saved_at", 0.0),
					}
				)
		file_name = dir.get_next()
	dir.list_dir_end()
	# Sort by most recently saved first
	saves.sort_custom(
		func(a, b):
			return a.get("saved_at", 0.0) > b.get("saved_at", 0.0),
	)
	return saves


## Start a new game with a fresh save slot. The stand_name becomes both
## the save file name and the text on the stand sign in-game.
## game_mode determines the lobby layout (solo/coop/versus).
func start_new_game(stand_name: String = "", game_mode: int = GameState.GameMode.SOLO) -> void:
	if stand_name == "":
		stand_name = "Lemonade Stand"
	# Use the stand name as the slot (file) name.
	current_slot = stand_name
	auto_save_enabled = true
	# Store the stand name and mode so they're available when loaded.
	GameState.stand_name = stand_name
	GameState.game_mode = game_mode as GameState.GameMode
	# Reset GameState to defaults
	GameState.money = Balancing.STARTING_MONEY
	GameState.popularity = 0.1
	GameState.temperature = 25.0
	GameState._init_default_prices()
	GameState._init_default_recipes()
	GameState.feedback_tier = 0
	GameState.highest_money = GameState.money
	GameState.customers_served_happy = 0
	GameState.customers_lost = 0
	GameState.total_customers_served = 0
	GameState.total_cups_sold = 0
	GameState.total_money_earned = 0.0
	GameState.total_money_spent = 0.0
	GameState.highest_purchase = 0.0
	DayManager.day_number = 1
	UpgradeManager.reset()
	UpgradeManager.set_active_stand(stand_name)
	# Save immediately to create the slot (force: not a host yet)
	save_game(true)


## Load an existing save slot and set it as the current slot.
func load_existing_game(slot_name: String) -> void:
	current_slot = slot_name
	auto_save_enabled = true
	var data := load_slot(slot_name)
	if not data.is_empty():
		apply_save_to_game_state(data)


## Stop saving and clear the current slot (e.g. when leaving the game).
func clear_current_slot() -> void:
	current_slot = ""
	auto_save_enabled = false


func _slot_path(slot_name: String) -> String:
	return SAVE_DIR + slot_name + ".json"


func _migrate_legacy_save() -> void:
	# If the old single-save file exists and the new saves dir doesn't,
	# migrate it to a slot called "Legacy Save".
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var target := _slot_path("Legacy Save")
	if FileAccess.file_exists(target):
		return # Already migrated
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := file.get_as_text()
	file.close()
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out:
		out.store_string(json)
		out.close()
		print("[SaveManager] Migrated legacy save to slot 'Legacy Save'")


func apply_save_to_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	_pending_container_respawn = data.get("placed_containers", [])
	_pending_supply_box_respawn = data.get("supply_boxes", [])
	GameState.stand_name = data.get("stand_name", current_slot)
	GameState.game_mode = data.get("game_mode", GameState.GameMode.SOLO) as GameState.GameMode
	GameState.money = data.get("money", Balancing.STARTING_MONEY)
	GameState.popularity = data.get("popularity", 0.1)
	GameState.temperature = data.get("temperature", 25.0)
	var saved_prices = data.get("prices", { })
	if saved_prices is Dictionary and not saved_prices.is_empty():
		for ft in GameState.FRUIT_TYPES:
			GameState.prices[ft] = saved_prices.get(ft, 1.5)
	else:
		var legacy_price: float = data.get("current_price", 1.5)
		for ft in GameState.FRUIT_TYPES:
			GameState.prices[ft] = legacy_price
	var saved_recipes = data.get("recipes", { })
	if saved_recipes is Dictionary and not saved_recipes.is_empty():
		GameState.recipes = saved_recipes.duplicate(true)
	else:
		GameState.recipes.clear()
		for ft in GameState.FRUIT_TYPES:
			GameState.recipes[ft] = GameState.get_recipe(ft)
	GameState.ice_degrees_per_scoop = data.get("ice_degrees_per_scoop", 4.0)
	GameState.feedback_tier = data.get("feedback_tier", 0)
	GameState.customers_served_happy = data.get("customers_served_happy", 0)
	GameState.customers_lost = data.get("customers_lost", 0)
	GameState.total_customers_served = data.get("total_customers_served", 0)
	GameState.total_cups_sold = data.get("total_cups_sold", 0)
	GameState.total_money_earned = data.get("total_money_earned", 0.0)
	GameState.total_money_spent = data.get("total_money_spent", 0.0)
	GameState.highest_purchase = data.get("highest_purchase", 0.0)
	GameState.highest_money = data.get("highest_money", GameState.money)
	DayManager.day_number = data.get("day_number", 1)

	UpgradeManager.reset()
	var stand_name_for_research: String = data.get("stand_name", GameState.stand_name)
	var purchased_nodes_data = data.get("purchased_nodes", [])
	if purchased_nodes_data is Array and not purchased_nodes_data.is_empty():
		if stand_name_for_research != "":
			UpgradeManager.set_purchased_for_stand(stand_name_for_research, purchased_nodes_data)
			UpgradeManager.set_active_stand(stand_name_for_research)
		else:
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
	for ft in GameState.FRUIT_TYPES:
		EventBus.price_changed.emit(ft, GameState.get_price(ft))
		EventBus.recipe_changed.emit(ft, GameState.get_recipe(ft))
	EventBus.feedback_tier_changed.emit(GameState.feedback_tier)


func _build_save_dict() -> Dictionary:
	return {
		"stand_name": GameState.stand_name,
		"game_mode": GameState.game_mode,
		"creator_steam_id": NetworkManager.steam_id,
		"money": GameState.money,
		"popularity": GameState.popularity,
		"temperature": GameState.temperature,
		"prices": GameState.prices.duplicate(),
		"recipes": GameState.recipes.duplicate(true),
		"ice_degrees_per_scoop": GameState.ice_degrees_per_scoop,
		"feedback_tier": GameState.feedback_tier,
		"customers_served_happy": GameState.customers_served_happy,
		"customers_lost": GameState.customers_lost,
		"total_customers_served": GameState.total_customers_served,
		"total_cups_sold": GameState.total_cups_sold,
		"total_money_earned": GameState.total_money_earned,
		"total_money_spent": GameState.total_money_spent,
		"highest_purchase": GameState.highest_purchase,
		"highest_money": GameState.highest_money,
		"day_number": DayManager.day_number,
		"purchased_nodes": UpgradeManager.get_save_data_for_stand(GameState.stand_name),
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
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		# Skip placement-preview ghosts and held items
		if node.is_in_group("ghost"):
			continue
		# Skip containers currently held by the player
		if player != null and node.is_ancestor_of(player) or _is_child_of_player(node, player):
			continue
		var ctype := _get_container_type(node)
		if ctype == "" or not _is_known_container_type(ctype):
			continue
		var entry := {
			"type": ctype,
			"position": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rotation": [node.global_rotation.x, node.global_rotation.y, node.global_rotation.z],
			"scale": [node.scale.x, node.scale.y, node.scale.z],
			"stand_owner": node.get("stand_owner") if "stand_owner" in node else "",
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
		elif node is Press:
			entry["fruit_type"] = node.fruit_type
			entry["fruit_count"] = node.fruit_count
		elif node is WaterDispenser:
			entry["water_fillings"] = node.water_fillings
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
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.is_in_group("ghost"):
			continue
		var box := node as SupplyBox
		if box == null:
			continue
		result.append(
			{
				"position": [box.global_position.x, box.global_position.y, box.global_position.z],
				"rotation": [box.global_rotation.x, box.global_rotation.y, box.global_rotation.z],
				"scale": [box.scale.x, box.scale.y, box.scale.z],
				"ingredient_type": box.ingredient_type,
				"quantity": box.quantity,
				"is_equipment": box.is_equipment,
				"equipment_type": box.equipment_type,
				"stand_owner": box.stand_owner,
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
	var node_script: Script = node.get_script() as Script
	if node_script != null and node_script.resource_path == "res://scripts/objects/workstation.gd":
		return "workstation"
	var n := node.name.to_lower()
	if n.contains("pitcher"):
		return "pitcher"
	if n.contains("press"):
		return "press"
	return ""


func respawn_placed_containers() -> void:
	# Only the host respawns saved containers. Clients will receive them
	# via WorldSync replication.
	if not WorldSync.is_host():
		return
	call_deferred("_do_respawn")


func capture_default_containers() -> void:
	_default_container_positions = []
	if get_tree() == null or get_tree().current_scene == null:
		return
	for node in get_tree().get_nodes_in_group("container"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.is_in_group("ghost"):
			continue
		var ctype := _get_container_type(node)
		if ctype == "" or not _is_known_container_type(ctype):
			continue
		var entry := {
			"type": ctype,
			"position": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rotation": [node.global_rotation.x, node.global_rotation.y, node.global_rotation.z],
			"scale": [node.scale.x, node.scale.y, node.scale.z],
			"stand_owner": node.get("stand_owner") if "stand_owner" in node else "",
		}
		if node is WaterDispenser:
			entry["water_fillings"] = (node as WaterDispenser).max_fillings
		elif node is CupStack:
			entry["current_count"] = (node as CupStack).starting_count
		elif node is Press:
			entry["fruit_type"] = ""
			entry["fruit_count"] = 0.0
		_default_container_positions.append(entry)


func respawn_default_containers() -> void:
	_pending_container_respawn = _default_container_positions.duplicate(true)
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
			if instance is WaterDispenser:
				instance.water_fillings = entry.get("water_fillings", instance.water_fillings)
			if instance is Press:
				instance.fruit_type = entry.get("fruit_type", "")
				instance.fruit_count = entry.get("fruit_count", 0.0)
			# Restore stand ownership.
			if "stand_owner" in instance:
				instance.stand_owner = entry.get("stand_owner", "")
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

		# Link pitchers to presses/water dispensers based on proximity to snap points
		for container in root.get_tree().get_nodes_in_group("container"):
			var snap_pos: Vector3 = Vector3.ZERO
			if container is Press:
				snap_pos = (container as Press).get_snap_global_position()
			elif container is WaterDispenser:
				snap_pos = (container as WaterDispenser).get_snap_global_position()
			else:
				continue
			for pitcher in root.get_tree().get_nodes_in_group("pitcher"):
				if not (pitcher is Pitcher):
					continue
				if pitcher.global_position.is_equal_approx(snap_pos):
					if container is Press:
						(container as Press).snap_pitcher(pitcher as Pitcher)
					elif container is WaterDispenser:
						(container as WaterDispenser).snap_pitcher(pitcher as Pitcher)
					break

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
			if not WorldSync.is_host():
				continue
			var box: SupplyBox = SUPPLY_BOX_SCENE.instantiate()
			# Set properties BEFORE add_child so _ready() uses correct values
			box.ingredient_type = entry.get("ingredient_type", "lemon")
			box.quantity = entry.get("quantity", 10.0)
			box.is_equipment = entry.get("is_equipment", false)
			box.equipment_type = entry.get("equipment_type", "")
			box.stand_owner = entry.get("stand_owner", "")
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
	_clear_street_trash()


func _clear_street_trash() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("trash_item"):
		if is_instance_valid(node):
			node.queue_free()
