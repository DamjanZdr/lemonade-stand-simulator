extends Node
## Node-based upgrade tree (Nodebuster-style).
## Each node is a single purchase. The tree layout is defined in a scene file
## (res://scenes/tools/upgrade_tree.tscn) using UpgradeTreeNode instances.
## UpgradeDefinition resources define what each upgrade type does.

const TREE_SCENE_PATH := "res://scenes/tools/upgrade_tree.tscn"

## node_name -> { upgrade_id, cost, position, connections[], is_root }
var tree_nodes: Dictionary = { }
## node_name -> Array[node_name] (adjacency for rendering)
var tree_connections: Dictionary = { }
## node_name -> Vector2 (pixel position from the scene)
var tree_positions: Dictionary = { }
## upgrade_id -> UpgradeDefinition resource
var definitions: Dictionary = { }
## Set of purchased node names
var purchased_nodes: Dictionary = { } # node_name -> true
## Root node name
var root_node_name: String = ""


func _ready() -> void:
	_load_tree()
	_apply_radial_layout()
	# Auto-purchase the lemon unlock node so the first fruit in the
	# recipe branch shows as unlocked by default.
	for node_name in tree_nodes:
		var data: Dictionary = tree_nodes[node_name]
		if data.get("upgrade_id", "") == "lemon_unlock":
			purchased_nodes[node_name] = true
			break
	# Override definitions from UpgradeConfigManager if present.
	var scene: Node = Engine.get_main_loop().current_scene
	var cfg: Node = scene.get_node_or_null("Managers/UpgradeConfigManager")
	if cfg != null and cfg.has_method("get_upgrades"):
		for def in cfg.get_upgrades():
			if def != null:
				definitions[str(def.id)] = def
	_apply_definition_values()
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)


const RECIPE_ORDER: Array[String] = ["lemon", "strawberry", "blueberry", "peach", "watermelon"]


func _load_tree() -> void:
	var scene := load(TREE_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("UpgradeManager: Could not load tree scene at %s" % TREE_SCENE_PATH)
		return
	var instance := scene.instantiate()
	var recipe_candidates: Dictionary = { } # upgrade_id -> { node_name, cost, data, pos, conns }
	for child in instance.get_children():
		if not child is UpgradeTreeNode:
			continue
		var node: UpgradeTreeNode = child
		var node_name: String = node.name
		var upgrade_id: String = ""
		var category: String = ""
		if node.upgrade != null:
			upgrade_id = str(node.upgrade.id)
			category = node.upgrade.category
			if not definitions.has(upgrade_id):
				definitions[upgrade_id] = node.upgrade
		var connections: Array[String] = []
		var dir_paths := [
			node.connection_up,
			node.connection_down,
			node.connection_left,
			node.connection_right,
		]
		for path in dir_paths:
			if path == NodePath(""):
				continue
			var target := node.get_node_or_null(path)
			if target != null:
				connections.append(str(target.name))
		var node_data := {
			"upgrade_id": upgrade_id,
			"cost": node.cost,
			"position": node.position,
			"connections": connections,
			"is_root": node.is_root,
			"category": category,
		}
		if node.is_root:
			root_node_name = node_name
			tree_nodes[node_name] = node_data
			tree_positions[node_name] = node.position
			continue
		if category == "recipe":
			var cost: float = node.cost
			if not recipe_candidates.has(upgrade_id) or cost < recipe_candidates[upgrade_id].cost:
				recipe_candidates[upgrade_id] = {
					"node_name": node_name,
					"cost": cost,
					"data": node_data,
					"pos": node.position,
					"conns": connections,
				}
			continue
		tree_nodes[node_name] = node_data
		tree_positions[node_name] = node.position
		if not connections.is_empty():
			tree_connections[node_name] = connections
		if node.is_root:
			root_node_name = node_name
	for upgrade_id in recipe_candidates:
		var c: Dictionary = recipe_candidates[upgrade_id]
		tree_nodes[c["node_name"]] = c["data"]
		tree_positions[c["node_name"]] = c["pos"]
		if not c["conns"].is_empty():
			tree_connections[c["node_name"]] = c["conns"]
	instance.free()


func _apply_radial_layout() -> void:
	## Reorganize the tree into one spoke per upgrade type.
	if root_node_name.is_empty() or tree_nodes.is_empty():
		return
	var root_pos: Vector2 = tree_positions.get(root_node_name, Vector2.ZERO)

	# Group nodes by their upgrade_id.
	var groups: Dictionary = { } # upgrade_id -> Array[node_name]
	for node_name in tree_nodes:
		if node_name == root_node_name:
			continue
		var data: Dictionary = tree_nodes[node_name]
		var upgrade_id: String = data.get("upgrade_id", "")
		if upgrade_id.is_empty():
			continue
		if not groups.has(upgrade_id):
			groups[upgrade_id] = []
		groups[upgrade_id].append(node_name)

	# Collapse the recipe fruit unlocks into one ordered branch.
	var recipe_branch: Array[String] = []
	for fruit in RECIPE_ORDER:
		var recipe_id: String = fruit + "_unlock"
		if not groups.has(recipe_id):
			continue
		var list: Array = groups[recipe_id]
		if not list.is_empty():
			recipe_branch.append(list[0])
		groups.erase(recipe_id)
	if not recipe_branch.is_empty():
		groups["recipe_unlock"] = recipe_branch

	if groups.is_empty():
		return

	# Order each group from the node closest to the root outward.
	# Recipe branch is already ordered and should not be resorted.
	for id in groups:
		if id == "recipe_unlock":
			continue
		var list: Array = groups[id]
		list.sort_custom(
			func(a: String, b: String) -> bool:
				var da: float = tree_positions[a].distance_to(root_pos)
				var db: float = tree_positions[b].distance_to(root_pos)
				return da < db,
		)
		groups[id] = list

	# Assign an even angle to each unique upgrade type.
	var ids: Array = groups.keys()
	ids.sort()
	var angles: Dictionary = { }
	for branch_idx in range(ids.size()):
		angles[ids[branch_idx]] = 2.0 * PI * branch_idx / ids.size()

	# Place nodes along their type spoke with shorter gaps the further out they go.
	var base_spacing: float = 150.0
	tree_connections.clear()
	for branch_idx in range(ids.size()):
		var id: String = ids[branch_idx]
		var angle: float = angles[id]
		var dir := Vector2(cos(angle), sin(angle))
		var list: Array = groups[id]
		var dist: float = 0.0
		for i in range(list.size()):
			var node_name: String = list[i]
			var step: float = base_spacing
			dist += step
			tree_positions[node_name] = root_pos + dir * dist

			var data: Dictionary = tree_nodes[node_name]
			data["spoke_index"] = i
			data["branch_index"] = branch_idx
			var conns: Array[String] = []
			var prev_name: String = root_node_name if i == 0 else list[i - 1]
			conns.append(prev_name)
			data["connections"] = conns

			# Rendering adjacency: root -> 1 -> 2 -> 3 ...
			if i == 0:
				if not tree_connections.has(root_node_name):
					tree_connections[root_node_name] = []
				tree_connections[root_node_name].append(node_name)
			else:
				var prev: String = list[i - 1]
				if not tree_connections.has(prev):
					tree_connections[prev] = []
				tree_connections[prev].append(node_name)


## Check if a node can be purchased (adjacent to a purchased node or root).
func can_unlock(node_name: String) -> bool:
	if node_name == root_node_name:
		return true
	if is_node_purchased(node_name):
		return false
	var data: Dictionary = tree_nodes.get(node_name, { })
	var connections: Array = data.get("connections", [])
	for adj_name in connections:
		if adj_name == root_node_name or is_node_purchased(adj_name):
			return true
	return false


func can_afford_node(node_name: String) -> bool:
	var data: Dictionary = tree_nodes.get(node_name, { })
	var cost: float = data.get("cost", 0.0) * (1.0 - _negotiation_discount())
	return GameState.money >= cost


func is_node_purchased(node_name: String) -> bool:
	return purchased_nodes.has(node_name)


func get_node_data(node_name: String) -> Dictionary:
	var data: Dictionary = tree_nodes.get(node_name, { }).duplicate()
	data["node_name"] = node_name
	data["purchased"] = is_node_purchased(node_name)
	data["can_unlock"] = can_unlock(node_name)
	data["can_buy"] = can_unlock(node_name) and can_afford_node(node_name)
	var upgrade_id: String = data.get("upgrade_id", "")
	if definitions.has(upgrade_id):
		var def: UpgradeDefinition = definitions[upgrade_id]
		data["name"] = def.display_name
		data["description"] = def.description
		data["icon"] = def.icon
		if not data.has("effect"):
			data["effect"] = def.effect_per_node
	else:
		data["name"] = "Root" if data.get("is_root", false) else "???"
		data["description"] = ""
		data["icon"] = null
	return data


func purchase_node(node_name: String) -> bool:
	if not can_unlock(node_name):
		return false
	var data: Dictionary = tree_nodes.get(node_name, { })
	var cost: float = data.get("cost", 0.0) * (1.0 - _negotiation_discount())
	if not GameState.spend_money(cost):
		return false
	purchased_nodes[node_name] = true
	var upgrade_id: String = data.get("upgrade_id", "")
	_apply_effect(upgrade_id)
	EventBus.upgrade_purchased.emit(data.get("id", 0), cost)
	EventBus.game_saved.emit()
	return true


## Get the total stacked effect for an upgrade type (sum across all purchased nodes of that type).
func get_effect_total(upgrade_id: String) -> float:
	var def: UpgradeDefinition = definitions.get(upgrade_id)
	if def == null:
		return 0.0
	var total := 0.0
	for node_name in purchased_nodes:
		var data: Dictionary = tree_nodes.get(node_name, { })
		if data.get("upgrade_id", "") == upgrade_id:
			var effect: float = data.get("effect", def.effect_per_node)
			total += effect
	return total


## Get how many nodes of a given upgrade type are purchased.
func get_purchased_count(upgrade_id: String) -> int:
	var count := 0
	for node_name in purchased_nodes:
		var data: Dictionary = tree_nodes.get(node_name, { })
		if data.get("upgrade_id", "") == upgrade_id:
			count += 1
	return count


## Get total nodes of a given upgrade type in the tree.
func get_total_nodes_for(upgrade_id: String) -> int:
	var count := 0
	for node_name in tree_nodes:
		if tree_nodes[node_name].get("upgrade_id", "") == upgrade_id:
			count += 1
	return count


func get_category_color(category: String) -> Color:
	match category:
		"equipment":
			return Color(0.30, 0.55, 0.30)
		"customer":
			return Color(0.55, 0.35, 0.25)
		"recipe":
			return Color(0.30, 0.45, 0.55)
		"economy":
			return Color(0.55, 0.50, 0.25)
		_:
			return Color(0.50, 0.50, 0.50)


func get_all_node_names() -> Array:
	return tree_nodes.keys()


func get_total_purchased() -> int:
	return purchased_nodes.size()

## --- Compatibility layer for existing code that uses old API ---


func get_level(id: String) -> int:
	return get_purchased_count(id)


func get_cost(id: String) -> float:
	# Return cost of the cheapest unpurchased node of this type
	var cheapest := 999999.0
	for node_name in tree_nodes:
		var data: Dictionary = tree_nodes[node_name]
		if data.get("upgrade_id", "") == id and not is_node_purchased(node_name):
			if can_unlock(node_name):
				cheapest = minf(cheapest, data.get("cost", 0.0))
	if cheapest >= 999999.0:
		return 0.0
	return cheapest * (1.0 - _negotiation_discount())


func is_maxed(id: String) -> bool:
	return get_purchased_count(id) >= get_total_nodes_for(id)


func can_afford(id: String) -> bool:
	return GameState.money >= get_cost(id)


func purchase(id: String) -> bool:
	# Purchase the next available node of this upgrade type
	for node_name in tree_nodes:
		var data: Dictionary = tree_nodes[node_name]
		if data.get("upgrade_id", "") == id and not is_node_purchased(node_name):
			if can_unlock(node_name):
				return purchase_node(node_name)
	return false


func get_categories() -> Array:
	var cats: Dictionary = { }
	for def in definitions.values():
		cats[def.category] = true
	return cats.keys()


func get_upgrades_in_category(category: String) -> Array:
	var result: Array = []
	for id in definitions:
		if definitions[id].category == category:
			result.append(id)
	return result


func get_upgrade_data(id: String) -> Dictionary:
	var def: UpgradeDefinition = definitions.get(id)
	if def == null:
		return { "id": id, "name": "???", "level": 0, "cost": 0.0, "maxed": true }
	return {
		"id": id,
		"name": def.display_name,
		"description": def.description,
		"category": def.category,
		"level": get_purchased_count(id),
		"max_level": get_total_nodes_for(id),
		"cost": get_cost(id),
		"maxed": is_maxed(id),
	}


func _apply_effect(upgrade_id: String) -> void:
	match upgrade_id:
		"psychology":
			GameState.feedback_tier = 2
			EventBus.feedback_tier_changed.emit(2)


func is_fruit_unlocked(fruit: String) -> bool:
	if fruit == "lemon":
		return true
	return get_purchased_count(fruit + "_unlock") > 0


func get_unlocked_fruits() -> Array[String]:
	var result: Array[String] = []
	for ft in GameState.FRUIT_TYPES:
		if is_fruit_unlocked(ft):
			result.append(ft)
	return result


func apply_all_effects() -> void:
	for node_name in purchased_nodes:
		var data: Dictionary = tree_nodes.get(node_name, { })
		_apply_effect(data.get("upgrade_id", ""))


func _apply_definition_values() -> void:
	for node_name in tree_nodes:
		var data: Dictionary = tree_nodes[node_name]
		var upgrade_id: String = data.get("upgrade_id", "")
		var def: UpgradeDefinition = definitions.get(upgrade_id)
		if def == null:
			continue
		var idx: int = data.get("spoke_index", 0)
		if def.costs.size() > 0:
			var cost_idx := mini(idx, def.costs.size() - 1)
			data["cost"] = def.costs[cost_idx]
		if def.effects.size() > 0:
			var effect_idx := mini(idx, def.effects.size() - 1)
			data["effect"] = def.effects[effect_idx]


func _on_upgrade_purchased(_id: int, _cost: float) -> void:
	pass # Legacy signal compatibility


func load_legacy_upgrades(owned_list: Array) -> void:
	# Convert old level-based upgrades to node purchases
	var legacy_map := {
		0: "press_speed",
		1: "nimbleness",
		2: "sunroof",
		3: "larger_crates",
		5: "price_flex",
		6: "psychology",
	}
	for u in owned_list:
		if u is int and legacy_map.has(u):
			purchase(legacy_map[u])


func load_purchased_nodes(node_names: Array) -> void:
	purchased_nodes.clear()
	for n in node_names:
		if tree_nodes.has(str(n)):
			purchased_nodes[str(n)] = true


func get_save_data() -> Array:
	return purchased_nodes.keys()


func reset() -> void:
	purchased_nodes.clear()


func _negotiation_discount() -> float:
	return clampf(get_effect_total("negotiation"), 0.0, 0.9)
