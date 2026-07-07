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
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)


func _load_tree() -> void:
	var scene := load(TREE_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("UpgradeManager: Could not load tree scene at %s" % TREE_SCENE_PATH)
		return
	var instance := scene.instantiate()
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
		tree_nodes[node_name] = {
			"upgrade_id": upgrade_id,
			"cost": node.cost,
			"position": node.position,
			"connections": connections,
			"is_root": node.is_root,
			"category": category,
		}
		tree_positions[node_name] = node.position
		if not connections.is_empty():
			tree_connections[node_name] = connections
		if node.is_root:
			root_node_name = node_name
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
	if groups.is_empty():
		return

	# Order each group from the node closest to the root outward.
	for id in groups:
		var list: Array = groups[id]
		list.sort_custom(
			func(a: String, b: String) -> bool:
				var da: float = tree_positions[a].distance_to(root_pos)
				var db: float = tree_positions[b].distance_to(root_pos)
				return da < db
		)
		groups[id] = list

	# Assign an even angle to each unique upgrade type.
	var ids: Array = groups.keys()
	ids.sort()
	var angles: Dictionary = { }
	for i in range(ids.size()):
		angles[ids[i]] = 2.0 * PI * i / ids.size()

	# Place nodes along their type spoke with shorter gaps the further out they go.
	var base_spacing: float = 120.0
	var spacing_shrink: float = 15.0
	var min_spacing: float = 50.0
	tree_connections.clear()
	for id in ids:
		var angle: float = angles[id]
		var dir := Vector2(cos(angle), sin(angle))
		var list: Array = groups[id]
		var dist: float = 0.0
		for i in range(list.size()):
			var node_name: String = list[i]
			var step: float = maxf(base_spacing - i * spacing_shrink, min_spacing)
			dist += step
			tree_positions[node_name] = root_pos + dir * dist

			var data: Dictionary = tree_nodes[node_name]
			data["spoke_index"] = i
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
	return GameState.money >= data.get("cost", 0.0)


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
	else:
		data["name"] = "Root" if data.get("is_root", false) else "???"
		data["description"] = ""
		data["icon"] = null
	return data


func purchase_node(node_name: String) -> bool:
	if not can_unlock(node_name):
		return false
	var data: Dictionary = tree_nodes.get(node_name, { })
	var cost: float = data.get("cost", 0.0)
	if not GameState.spend_money(cost):
		return false
	purchased_nodes[node_name] = true
	var upgrade_id: String = data.get("upgrade_id", "")
	_apply_effect(upgrade_id)
	EventBus.game_saved.emit()
	return true


## Get the total stacked effect for an upgrade type (sum across all purchased nodes of that type).
func get_effect_total(upgrade_id: String) -> float:
	var def: UpgradeDefinition = definitions.get(upgrade_id)
	if def == null:
		return 0.0
	var count := 0
	for node_name in purchased_nodes:
		var data: Dictionary = tree_nodes.get(node_name, { })
		if data.get("upgrade_id", "") == upgrade_id:
			count += 1
	return count * def.effect_per_node


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
	return cheapest if cheapest < 999999.0 else 0.0


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


func apply_all_effects() -> void:
	for node_name in purchased_nodes:
		var data: Dictionary = tree_nodes.get(node_name, { })
		_apply_effect(data.get("upgrade_id", ""))


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
