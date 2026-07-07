extends Node
## Abstract inventory: computes total owned items across all placed bins,
## pitchers, cup stacks, and unopened supply boxes.
## This is a read-only view of the physical world state.

func get_inventory() -> Dictionary:
	## Returns a dictionary of item_type -> total_count across the entire stand.
	var result := {
		"lemon": 0,
		"strawberry": 0,
		"blueberry": 0,
		"peach": 0,
		"watermelon": 0,
		"sugar": 0.0,
		"ice": 0.0,
		"water": 0.0,
		"cups": 0,
	}
	if get_tree() == null or get_tree().current_scene == null:
		return result

	# Scan all placed containers
	for node in get_tree().get_nodes_in_group("container"):
		if node is FruitBin:
			for ftype in node.fruit_amounts:
				result[ftype] = result.get(ftype, 0) + node.fruit_amounts[ftype]
		elif node is IngredientBin:
			var itype: String = node.ingredient_type
			if itype in result:
				result[itype] = result.get(itype, 0.0) + node.current_amount
		elif node is CupStack:
			result["cups"] = result.get("cups", 0) + node.current_count
		elif node is Pitcher:
			if node.fruit_type != "" and node.fruit_count > 0.0:
				result[node.fruit_type] = result.get(node.fruit_type, 0) + node.fruit_count
			result["water"] = result.get("water", 0.0) + node.water
			result["sugar"] = result.get("sugar", 0.0) + node.sugar
			result["ice"] = result.get("ice", 0.0) + node.ice

	# Scan unopened supply boxes
	for node in get_tree().get_nodes_in_group("supply_box"):
		var box := node as SupplyBox
		if box == null:
			continue
		if box.is_equipment:
			continue
		var btype: String = box.ingredient_type
		if btype in result:
			result[btype] = result.get(btype, 0.0) + box.quantity
		else:
			result[btype] = result.get(btype, 0.0) + box.quantity

	# Scan water dispensers
	for node in get_tree().get_nodes_in_group("water_dispenser"):
		var dispenser := node as WaterDispenser
		if dispenser != null:
			result["water"] = result.get("water", 0.0) + dispenser.water_fillings

	return result


func get_inventory_string() -> String:
	var inv := get_inventory()
	var lines: Array[String] = []
	for key in inv:
		var val: float = inv[key]
		if val > 0.0:
			lines.append("%s: %.0f" % [key.capitalize(), val])
	if lines.is_empty():
		return "Nothing on the stand"
	return "\n".join(lines)
