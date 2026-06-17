class_name WaterTap
extends Interactable
## Fixed faucet on the prep table.
## Click when pitcher is nearby on workstation
## to fill it with water.

## Maximum distance to fill pitcher (covers entire workstation area)
@export var fill_range: float = 4.0


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return

	# If player is holding a pitcher, let the player script handle it directly
	if p.held_item == p.HeldItem.CONTAINER and p.held_item_data.get("container_type") == "pitcher":
		return

	# Find nearest placed pitcher
	var pitcher: Pitcher = _find_nearby_pitcher()

	if pitcher == null:
		EventBus.interaction_hint_changed.emit("No pitcher nearby to fill!")
		return
	if pitcher.water > 0.0:
		EventBus.interaction_hint_changed.emit("Pitcher is already filled with water!")
		return
	# Fill with water (adds water and transitions to COMPLETE if lemons present)
	var fill := Balancing.PITCHER_MAX_LIQUID - pitcher.get_liquid_volume()
	if fill > 0.0:
		pitcher.fill_water_slow(fill, 4.0)
		EventBus.pitcher_ingredient_added.emit("water", fill)


func _find_nearby_pitcher() -> Pitcher:
	var nearest: Pitcher = null
	var nearest_dist := fill_range
	for node in get_tree().get_nodes_in_group("pitcher"):
		var pitcher := node as Pitcher
		if pitcher == null:
			continue
		# Only fill pitchers that don't have water yet
		if pitcher.water > 0.0:
			continue
		# Can fill in PREPPING or COMPLETE state (has lemons but needs water)
		if pitcher.state != Pitcher.PitcherState.PREPPING \
				and pitcher.state != Pitcher.PitcherState.COMPLETE:
			continue
		var dist := global_position.distance_to(pitcher.global_position)
		if dist < nearest_dist:
			nearest = pitcher
			nearest_dist = dist
	return nearest


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return "Water Tap"

	# Check if player is holding a pitcher — hint handled by player script
	if p.held_item == p.HeldItem.CONTAINER and p.held_item_data.get("container_type") == "pitcher":
		var recipe: Dictionary = p.held_item_data.get("saved_recipe", { })
		if recipe.get("water", 0.0) > 0.0:
			return "Pitcher already filled"
		return "Click: fill pitcher with water"

	var pitcher := _find_nearby_pitcher()
	if pitcher == null:
		return "Water Tap (place pitcher nearby)"
	if pitcher.water > 0.0:
		return "Pitcher already filled"
	return "Click: fill pitcher with water"
