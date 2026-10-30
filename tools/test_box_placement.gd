extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# Stand with a palette floor on the ground collision layer (mask 8).
	var stand: Node = load("res://scripts/stand/stand_unit.gd").new()
	stand.name = "TestStand"
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
	var player: Node = load("res://scripts/player/player.gd").new()
	player.set_multiplayer_authority(1)
	world.add_child(player)
	var placement: Node = load("res://scripts/player/player_placement.gd").new()
	player.add_child(placement)
	player.placement = placement
	placement._player = player

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
	check(placement._is_box_floor_hit(floor_body), "palette body counts as box floor")
	check(placement._is_box_floor_hit(floor_shape), "palette child shape counts as box floor")
	check(not placement._is_box_floor_hit(prop), "prop above palette is not box floor")
	check(not placement._is_box_floor_hit(prop_shape), "prop shape is not box floor")

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
		placement._get_bottom_box_in_stack(stack[3]) == stack[0],
		"bottom resolves from the top box",
	)
	check(
		placement._get_topmost_box_in_stack(stack[0]) == stack[3],
		"top resolves from the bottom box",
	)
	# The reported bug: aiming at upper boxes must still find a valid base.
	check(placement._stack_base_is_placeable(stack[3]), "stack on palette valid from upper box")
	check(placement._stack_base_is_placeable(stack[1]), "stack on palette valid from lower box")

	# An airborne box (no owner, no floor, no grid) has no placeable base.
	var air: Node = box_scene.instantiate()
	world.add_child(air)
	air.global_position = Vector3(40, 5.0, 40)
	await physics_frame
	check(not placement._stack_base_is_placeable(air), "airborne box has no placeable base")
	# A box rooted on a delivery grid cell is valid even off the palette.
	air.set_meta("delivery_cell_idx", 0)
	check(placement._stack_base_is_placeable(air), "grid-rooted box is placeable")
	air.remove_meta("delivery_cell_idx")

	# A stack whose bottom box knows its stand owner is valid.
	stack[0].set("stand_owner", "TestStand")
	check(placement._stack_base_is_placeable(stack[3]), "owned stack base is placeable")

	# --- Physics overlap: any body the ghost clips must invalidate it ---
	var ray := RayCast3D.new()
	ray.collision_mask = 9
	ray.target_position = Vector3(0, -2, 0)
	ray.enabled = true
	player.add_child(ray)
	player.ray = ray
	player.global_position = Vector3(0, 1.5, 5)
	await physics_frame
	check(ray.is_colliding(), "test ray reaches the floor")

	var ghost: Node = box_scene.instantiate()
	world.add_child(ghost)
	placement._disable_physics(ghost)
	ghost.add_to_group("ghost")
	placement._ghost = ghost

	# Free spot on the palette: nothing to clip.
	ghost.global_position = Vector3(0, 0.25, 5)
	await physics_frame
	check(not placement._check_ghost_overlap(), "clear floor spot overlaps nothing")

	# Edge of the box clipping the prop body: must invalidate.
	ghost.global_position = Vector3(3, 0.25, 3.2)
	await physics_frame
	check(placement._check_ghost_overlap(), "box edge clipping prop is rejected")

	# Just clear of the prop: valid again.
	ghost.global_position = Vector3(3, 0.25, 4.0)
	await physics_frame
	check(not placement._check_ghost_overlap(), "box beside prop overlaps nothing")

	# Overlapping an existing supply box: rejected (not just props).
	ghost.global_position = Vector3(0, 0.25, 0)
	await physics_frame
	check(placement._check_ghost_overlap(), "box clipping existing box is rejected")

	placement._ghost = null
	ghost.free()

	# --- Items riding on a held container appear in its ghost ---
	var fake_table := Node3D.new()
	world.add_child(fake_table)
	var item: Node = load("res://scenes/objects/pitcher.tscn").instantiate()
	fake_table.add_child(item)
	item.add_to_group("container")
	item.position = Vector3(0.4, 0.9, -0.2)
	player.held_item_data = { "container_type": "workstation", "source_node": fake_table }
	placement._workstation_scene = load("res://scenes/stand/workstation.tscn")
	placement._create_ghost("workstation")
	check(placement._ghost != null, "container ghost created")
	var item_copy: Node = placement._ghost.get_node_or_null(String(item.name))
	check(item_copy != null, "carried item appears in the ghost")
	check(
		item_copy != null and (item_copy as Node3D).transform.is_equal_approx(item.transform),
		"ghost item keeps its offset for rotation",
	)
	check(
		item_copy != null and not item_copy.is_in_group("container"),
		"ghost item copy is not a real container",
	)
	placement._destroy_ghost()
	item.free()
	fake_table.free()

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
