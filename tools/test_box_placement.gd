extends SceneTree

const PITCHER_SERVING_STATE := 2

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	root.get_node("AchievementManager").set_script(load("res://tools/achievement_test_harness.gd"))
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var world_objects := Node3D.new()
	world_objects.name = "WorldObjects"
	world.add_child(world_objects)

	# Stand with a palette floor on the ground collision layer (mask 8).
	var stand_script: Script = load("res://scripts/stand/stand_unit.gd")
	var stand: Node = stand_script.new()
	stand.name = "TestStand"
	stand.is_legacy_primary = false
	for child_name in [
		"DeliveryGrid", "DeliveryMarker", "QueueMarkerActive", "QueueMarker1", "QueueMarker2",
		"PriceBoard", "Thermometer", "WaterDispenser", "Stand",
	]:
		var child := Marker3D.new()
		child.name = child_name
		stand.add_child(child)
	world.add_child(stand)
	var floor_body := StaticBody3D.new()
	floor_body.name = "PlacableFloor"
	floor_body.collision_layer = 8
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10, 0.1, 10)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	stand.add_child(floor_body)

	# Player + placement component (same harness style as test_lemonader).
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.set_script(load("res://tools/local_player_test_actor.gd"))
	player.get_node("PlayerPlacement").set_script(
		load("res://tools/box_placement_test_harness.gd"),
	)
	player.set_multiplayer_authority(1)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(player)
	var placement: Node = player.placement

	# A floating prop collider that merely has floor below it — the old
	# downward-probe logic treated this as "ground".
	var prop := StaticBody3D.new()
	prop.name = "PriceBoardSide"
	prop.collision_layer = 1
	var prop_shape := CollisionShape3D.new()
	var prop_box := BoxShape3D.new()
	prop_box.size = Vector3(0.5, 1.0, 0.1)
	prop_shape.shape = prop_box
	prop.add_child(prop_shape)
	world.add_child(prop)
	prop.global_position = Vector3(3, 0.5, 3)

	await physics_frame
	await physics_frame

	# --- Strict floor hit: only a direct PlacableFloor hit counts ---
	check(placement.is_box_floor_hit(floor_body), "palette body counts as box floor")
	check(placement.is_box_floor_hit(floor_shape), "palette child shape counts as box floor")
	check(not placement.is_box_floor_hit(prop), "prop above palette is not box floor")
	check(not placement.is_box_floor_hit(prop_shape), "prop shape is not box floor")

	# --- Stack base resolution ---
	var box_scene: PackedScene = load("res://scenes/objects/supply_box.tscn")
	var stack: Array = []
	for i in range(4):
		var b: Node = box_scene.instantiate()
		world.add_child(b)
		b.global_position = Vector3(0, 0.25 + i * 0.49, 0)
		stack.append(b)
	await physics_frame
	for b in stack:
		b.update_metrics()

	check(
		placement.get_bottom_box_in_stack(stack[3]) == stack[0],
		"bottom resolves from the top box",
	)
	check(
		placement.get_topmost_box_in_stack(stack[0]) == stack[3],
		"top resolves from the bottom box",
	)
	# The reported bug: aiming at upper boxes must still find a valid base.
	check(placement.stack_base_is_placeable(stack[3]), "stack on palette valid from upper box")
	check(placement.stack_base_is_placeable(stack[1]), "stack on palette valid from lower box")

	# An airborne box (no owner, no floor, no grid) has no placeable base.
	var air: Node = box_scene.instantiate()
	world.add_child(air)
	air.global_position = Vector3(40, 5.0, 40)
	await physics_frame
	check(not placement.stack_base_is_placeable(air), "airborne box has no placeable base")
	# A box rooted on a delivery grid cell is valid even off the palette.
	air.set_meta("delivery_cell_idx", 0)
	check(placement.stack_base_is_placeable(air), "grid-rooted box is placeable")
	air.remove_meta("delivery_cell_idx")

	# A stack whose bottom box knows its stand owner is valid.
	stack[0].set("stand_owner", "TestStand")
	check(placement.stack_base_is_placeable(stack[3]), "owned stack base is placeable")

	# --- Physics overlap: any body the ghost clips must invalidate it ---
	var ray := RayCast3D.new()
	ray.process_mode = Node.PROCESS_MODE_ALWAYS
	ray.collision_mask = 9
	ray.target_position = Vector3(0, -2, 0)
	ray.enabled = true
	player.add_child(ray)
	player.ray = ray
	player.global_position = Vector3(0, 1.5, 5)
	await physics_frame
	check(ray.is_colliding(), "test ray reaches the floor")
	var rival: Node = stand_script.new()
	rival.name = "RivalStand"
	player.assigned_stand = rival
	player.assigned_stand_name = "RivalStand"
	check(placement.is_box_placeable_surface(floor_body), "boxed items allow rival palette floor")
	check(not placement.is_table_floor_surface(floor_body), "unboxed tables reject rival floor")
	player.held_item_data = {
		"is_equipment": true,
		"equipment_type": "pitcher",
		"source": "delivery",
	}
	placement.update_equipment_box_ghost()
	check(placement.ghost != null, "pitcher box has a floor ghost")
	check(placement.ghost_valid, "pitcher box ghost is valid on rival floor")
	if placement.ghost != null:
		check(placement.ghost.get_meta("ghost_type", "") == "box", "floor ghost stays boxed")
	placement.destroy_ghost()
	player.assigned_stand = stand
	player.assigned_stand_name = stand.name
	rival.free()

	var ghost: Node = box_scene.instantiate()
	world.add_child(ghost)
	placement.disable_physics(ghost)
	ghost.add_to_group("ghost")
	placement.ghost = ghost

	# Free spot on the palette: nothing to clip.
	ghost.global_position = Vector3(0, 0.25, 5)
	await physics_frame
	check(not placement.check_ghost_overlap(), "clear floor spot overlaps nothing")

	# Edge of the box clipping the prop body: must invalidate.
	ghost.global_position = Vector3(3, 0.25, 3.2)
	await physics_frame
	check(placement.check_ghost_overlap(), "box edge clipping prop is rejected")

	# Just clear of the prop: valid again.
	ghost.global_position = Vector3(3, 0.25, 4.0)
	await physics_frame
	check(not placement.check_ghost_overlap(), "box beside prop overlaps nothing")

	# Overlapping an existing supply box: rejected (not just props).
	ghost.global_position = Vector3(0, 0.25, 0)
	await physics_frame
	check(placement.check_ghost_overlap(), "box clipping existing box is rejected")

	placement.ghost = null
	ghost.free()

	# --- Items riding on a held container appear in its ghost ---
	var fake_table := Node3D.new()
	world.add_child(fake_table)
	var pitcher_scene: PackedScene = load("res://scenes/objects/pitcher.tscn")
	var item: Node = pitcher_scene.instantiate()
	fake_table.add_child(item)
	item.add_to_group("container")
	item.position = Vector3(0.4, 0.9, -0.2)
	player.held_item_data = { "container_type": "workstation", "source_node": fake_table }
	placement.workstation_scene = load("res://scenes/stand/workstation.tscn")
	placement.create_ghost("workstation")
	check(placement.ghost != null, "container ghost created")
	var item_copy: Node = placement.ghost.get_node_or_null(String(item.name))
	check(item_copy != null, "carried item appears in the ghost")
	check(
		item_copy != null and (item_copy as Node3D).transform.is_equal_approx(item.transform),
		"ghost item keeps its offset for rotation",
	)
	check(
		item_copy != null and not item_copy.is_in_group("container"),
		"ghost item copy is not a real container",
	)
	placement.destroy_ghost()
	item.free()
	fake_table.free()

	var dispenser_scene: PackedScene = load("res://scenes/objects/water_dispenser.tscn")
	var dispenser: Node = dispenser_scene.instantiate()
	world.add_child(dispenser)
	var juice_recipe := {
		"fruit_type": "lemon", "fruit_count": 2.0, "water": 0.0,
		"sugar": 0.0, "ice": 0.0, "cups_poured": 0, "state": 0,
	}
	check(dispenser.can_snap_pitcher_from_recipe(juice_recipe), "lemon juice can snap to dispenser")
	player.held_item = HeldItem.CONTAINER
	player.held_item_data = { "container_type": "pitcher", "saved_recipe": juice_recipe }
	check(
		placement.ensure_snap_ghost(dispenser.get_snap_global_position()),
		"juice snap ghost exists",
	)
	var placed: Node = placement.place_container()
	check(placed != null, "host can place a lemon-only pitcher without emptying it")
	if placed != null:
		check(is_equal_approx(placed.fruit_count, 2.0), "placement retains squeezed fruit")
		check(is_zero_approx(placed.water), "placement retains lemon-only recipe")
		dispenser.snap_pitcher(placed)
		check(
			not dispenser.can_snap_pitcher_from_recipe(juice_recipe),
			"occupied snap rejects another",
		)
		await create_timer(0.6).timeout
		placed.queue_free()
	dispenser.queue_free()
	await process_frame
	await _test_pitcher_batch_roundtrip(world, player, placement, pitcher_scene)
	await _test_pitcher_clicks(
		world, player, placement, dispenser_scene, pitcher_scene, juice_recipe,
	)
	if "--diagnose-stalls" in OS.get_cmdline_user_args():
		var logger := root.get_node("GameLog")
		logger.mark("pitcher_snap_test")
		OS.delay_msec(300)
		await process_frame
		await process_frame
		check("[STALL] frame=" in logger.get_buffer_text(), "stall trace records delayed frames")

	for b in stack:
		b.free()
	air.free()
	prop.free()
	player.free()
	floor_body.free()
	stand.free()
	world.free()
	print("BOX PLACEMENT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _test_pitcher_batch_roundtrip(
	world: Node, player: Node, placement: Node, pitcher_scene: PackedScene,
) -> void:
	var pitcher: Node = pitcher_scene.instantiate()
	pitcher.stand_owner = player.assigned_stand.name
	world.get_node("WorldObjects").add_child(pitcher)
	pitcher.add_ingredient("lemon", 2.0)
	pitcher.add_ingredient("water", 8.0)
	pitcher.add_ingredient("sugar", 4.0)
	pitcher.add_ingredient("ice", 2.0)
	for cup in range(4):
		var recipe: Dictionary = pitcher.pour_portion()
		check(is_equal_approx(recipe.get("fruit_count", 0.0), 2.0), "first cups retain two lemons")
		check(is_equal_approx(recipe.get("sugar", 0.0), 4.0), "first cups retain four sugar")
	pitcher.state = PITCHER_SERVING_STATE
	for cycle in range(3):
		placement.pickup_container(pitcher, "pitcher")
		await process_frame
		var held: Node = player.inventory.get_hand_mesh()
		check(held != null, "part-used pitcher can be picked up")
		if held == null:
			return
		check(
			held.get_contents_string() == "2 lemon 4 sugar 2 ice",
			"held pitcher displays the original batch after pickup",
		)
		check(held.state == PITCHER_SERVING_STATE, "held pitcher retains serving state")
		check(
			is_equal_approx(held.serving_recipe.get("fruit_count", 0.0), 2.0),
			"held pitcher retains the frozen batch recipe",
		)
		check(
			placement.ensure_snap_ghost(Vector3(15 + cycle * 2, 1, 0)),
			"part-used pitcher has a placement ghost",
		)
		pitcher = placement.place_container()
		check(pitcher != null, "part-used pitcher can be placed again")
		if pitcher == null:
			return
		var recipe: Dictionary = pitcher.pour_portion()
		check(is_equal_approx(recipe.get("fruit_count", 0.0), 2.0), "later cups retain two lemons")
		check(is_equal_approx(recipe.get("sugar", 0.0), 4.0), "later cups retain four sugar")
		check(
			is_equal_approx(recipe.get("_initial_volume", 0.0), 10.0),
			"pickup and placement do not restart the batch",
		)
		check(
			is_equal_approx(pitcher.get_liquid_volume(), 5.0 - cycle),
			"pickup and placement preserve actual remaining volume",
		)
	for cup in range(3):
		var recipe: Dictionary = pitcher.pour_portion()
		check(is_equal_approx(recipe.get("fruit_count", 0.0), 2.0), "last cups retain two lemons")
		check(is_equal_approx(recipe.get("sugar", 0.0), 4.0), "last cups retain four sugar")
	check(pitcher.cups_poured == 10, "batch still yields exactly ten cups")
	check(pitcher.is_fully_empty(), "batch drains fully after ten cups")
	check(pitcher.pour_portion().is_empty(), "empty pitcher cannot yield an extra cup")
	pitcher.queue_free()
	await process_frame


func _test_pitcher_clicks(
	world: Node, player: Node, placement: Node, dispenser_scene: PackedScene,
	pitcher_scene: PackedScene, recipe: Dictionary,
) -> void:
	var objects := world.get_node("WorldObjects")
	var press_scene: PackedScene = load("res://scenes/objects/press.tscn")
	for attempt in range(3):
		var target: Node = dispenser_scene.instantiate()
		target.position = Vector3(20 + attempt * 6, 1, 0)
		target.stand_owner = player.assigned_stand.name
		var proxy := StaticBody3D.new()
		proxy.collision_layer = 1
		proxy.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		proxy.add_child(shape)
		target.add_child(proxy)
		world.add_child(target)
		player.global_position = target.global_position + Vector3(0, 0, 2)
		player.ray.target_position = Vector3(0, 0, -4)
		var press: Node = press_scene.instantiate()
		press.position = target.position + Vector3(-3, 0, 0)
		press.stand_owner = player.assigned_stand.name
		world.add_child(press)
		var pitcher: Node = pitcher_scene.instantiate()
		pitcher.stand_owner = player.assigned_stand.name
		objects.add_child(pitcher)
		press.snap_pitcher(pitcher)
		press.fruit_type = "lemon"
		press.fruit_count = 2.0
		press.interact(player)
		for tick in range(80):
			await create_timer(0.1).timeout
			if is_zero_approx(press.fruit_count):
				break
		check(is_equal_approx(pitcher.fruit_count, 2.0), "actual press transfers two lemons")
		press.interact(player)
		check(player.inventory.held_item == HeldItem.CONTAINER, "take pressed pitcher into hand")
		press.queue_free()
		placement.destroy_ghost()
		await physics_frame
		await physics_frame
		player.ray.force_raycast_update()
		player.interaction.update_frame_lookups()
		check(
			player.interaction.get_looked_at_interactable() == target,
			"pitcher click ray reaches the owning dispenser",
		)
		var previous := objects.get_children()
		player.interaction.primary_interact()
		check(player.inventory.held_item == HeldItem.NONE, "dispenser click clears held pitcher")
		check(
			not target.can_snap_pitcher_from_recipe(recipe),
			"dispenser click restores a missing ghost and snaps the juice pitcher",
		)
		for child in objects.get_children():
			if child not in previous and child.has_method("get_liquid_volume"):
				check(is_equal_approx(child.fruit_count, 2.0), "clicked snap preserves lemon juice")
				child.queue_free()
		target.queue_free()
		await process_frame
	await create_timer(0.6).timeout
