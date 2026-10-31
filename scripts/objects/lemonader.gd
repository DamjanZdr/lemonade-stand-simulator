class_name Lemonader
extends Interactable

var machine_state: Dictionary = {
	"fruit": "",
	"stock": { "fruit": 0.0, "sugar": 0.0, "ice": 0.0 },
	"recipe": { "fruit_count": 2.0, "water": 8.0, "sugar": 4.0, "ice": 1.0 },
	"pitcher": false,
	"batch": { },
	"remaining": 0.0,
	"output": { },
}
var _hopper_meshes: Dictionary = { }
var _hopper_tweens: Dictionary = { }
var _hopper_active: Dictionary = { }
var _deposit_visuals: Node3D
var _mix_sound_played := false
var _slot_showing_pitcher := false
var _preview_shrinking := false
var _slot_display_ready := false


func _ready() -> void:
	add_to_group("container")
	configure_model()
	refresh_display.call_deferred()
	# RMB picks up the machine itself (pitcher in the slot rides along as
	# part of the scene). Clicking the slot pitcher still hits the preview's
	# own interactable, which routes here via _appliance_host(). Built via
	# load() — a Pickupable class_name reference would close a compile cycle
	# (Lemonader → Pickupable → Player → PlayerPlacement → Lemonader).
	var pickupable_script := load("res://scripts/components/pickupable.gd") as Script
	if pickupable_script != null:
		pickupable_script.call("setup_for_container", self, _machine_type())


## Container/save/held-item id. FruitOMatic overrides so pickup, ghost,
## save, and shop wiring see a different machine type through the same code.
func _machine_type() -> String:
	return "lemonader"


## Player-facing label used in interaction hints.
func _machine_name() -> String:
	return "Squeeze-E-Z"


## Squeeze-E-Z only squeezes — it outputs concentrate (fruit + sugar +
## ice dissolved) and the pitcher still needs a manual water topoff,
## same as hand-pressed juice. FruitOMatic overrides to full water.
func _adds_water() -> bool:
	return false


func placement_bottom_offset() -> float:
	var collision := get_node("Physics/CollisionShape3D") as CollisionShape3D
	var body := collision.get_parent() as Node3D
	var bounds := collision.shape.get_debug_mesh().get_aabb()
	return (body.transform * collision.transform * bounds).position.y


func configure_model() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var kind := str(mesh.name).to_lower()
		if kind in ["sugar", "fruit", "ice"] and mesh.mesh is ArrayMesh:
			if mesh.mesh.get_blend_shape_count() > 0:
				_hopper_meshes[kind] = mesh
				mesh.set_blend_shape_value(0, 0.0)
	_deposit_visuals = Node3D.new()
	_deposit_visuals.name = "DepositVisuals"
	_deposit_visuals.add_to_group("ghost")
	add_child(_deposit_visuals)
	var bottom := get_node_or_null("PitcherPosition") as Node3D
	var point := get_node_or_null("PitcherPoint") as Node3D
	var preview := get_node_or_null("PitcherPoint/PitcherPreview") as Pitcher
	if preview != null:
		preview.set_meta("lemonader_host", self)
		preview.set_process(false)
		preview.set_physics_process(false)
		for group in preview.get_groups():
			preview.remove_from_group(group)
		var pickupable := preview.get_node_or_null("Pickupable")
		if pickupable != null:
			pickupable.free()
		var phys := preview.get_node_or_null("Physics") as StaticBody3D
		if phys != null:
			phys.collision_layer = 0
			phys.collision_mask = 0
		# Keep the preview's live LemonadeFill CSG — like the press's
		# snapped pitcher it stays in the tree permanently, so its combiner
		# bakes once at scene load and the real eraser drives fill level.
	if bottom != null and point != null and preview != null:
		point.global_position = bottom.global_position
		var bounds := visual_bounds(preview)
		preview.global_position.y += bottom.global_position.y - bounds.position.y


func visual_bounds(node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if not str(child.name).ends_with("_Outline"):
			meshes.append(child as MeshInstance3D)
	var bounds := AABB()
	var found := false
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	return bounds


func animate_deposit(ingredient: String, amount: float, origin: Vector3) -> void:
	if not origin.is_finite() or not is_finite(amount) or amount <= 0.0:
		return
	var kind := "fruit" if ingredient in GameState.FRUIT_TYPES else ingredient
	if kind not in ["sugar", "fruit", "ice"]:
		return
	var marker := get_node_or_null(kind.capitalize() + "Drop") as Node3D
	if marker == null or not is_instance_valid(_deposit_visuals):
		return
	_hopper_active[kind] = int(_hopper_active.get(kind, 0)) + 1
	set_hopper_open(kind, 1.0)
	var count := clampi(ceili(amount), 1, 20)
	for index in range(count):
		var visual := make_deposit_visual(ingredient)
		visual.visible = false
		var target := _deposit_visuals.to_local(marker.global_position)
		var flight := _animate_throw_arc(
			visual,
			origin,
			target,
			0.35,
			0.12 + index * 0.055,
			index == 0,
		)
		if flight != null:
			flight.finished.connect(visual.queue_free)
			if index == 0:
				flight.finished.connect(_play_deposit_sfx.bind(kind, marker.global_position))
	var closing := create_tween()
	closing.tween_interval(0.12 + (count - 1) * 0.055 + 0.39)
	closing.finished.connect(finish_hopper_load.bind(kind))


func set_hopper_open(kind: String, value: float) -> void:
	var mesh := _hopper_meshes.get(kind) as MeshInstance3D
	if not is_instance_valid(mesh):
		return
	var previous := _hopper_tweens.get(kind) as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	_hopper_tweens[kind] = tween
	tween \
			.tween_method(
		func(weight: float):
			mesh.set_blend_shape_value(0, weight),
		mesh.get_blend_shape_value(0),
		value,
		0.12,
	) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)


func _play_deposit_sfx(kind: String, pos: Vector3) -> void:
	if kind == "ice":
		AudioManager.play_sfx("ice_cubes", pos)
	elif kind == "sugar":
		AudioManager.play_sfx("fruit_in_crate", pos, -1.0, 0.05, 1.3, -4.0)
	else:
		AudioManager.play_sfx("fruit_in_crate", pos)


func finish_hopper_load(kind: String) -> void:
	_hopper_active[kind] = maxi(0, int(_hopper_active.get(kind, 0)) - 1)
	if int(_hopper_active[kind]) == 0:
		set_hopper_open(kind, 0.0)


func make_deposit_visual(ingredient: String) -> Node3D:
	var asset := ingredient
	if ingredient == "sugar":
		asset = "sugar cube"
	elif ingredient == "ice":
		asset = "ice cube"
	var path := "res://assets/models/props/" + asset + ".glb"
	var wrapper := Node3D.new()
	_deposit_visuals.add_child(wrapper)
	if ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		wrapper.add_child(model)
		var bounds := visual_bounds(model)
		var size := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if size > 0.0:
			model.scale *= (0.06 if ingredient in GameState.FRUIT_TYPES else 0.035) / size
		bounds = visual_bounds(model)
		model.global_position += wrapper.global_position - bounds.get_center()
		for child in model.find_children("*", "CollisionObject3D", true, false):
			child.collision_layer = 0
			child.collision_mask = 0
	else:
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.035
		mesh.mesh = cube
		wrapper.add_child(mesh)
	return wrapper


func _process(delta: float) -> void:
	if not WorldSync.is_host() or machine_state["batch"].is_empty():
		return
	machine_state["remaining"] = maxf(0.0, float(machine_state["remaining"]) - delta)
	if float(machine_state["remaining"]) <= 0.0:
		finish_batch()


func deposit(ingredient: String, amount: float) -> float:
	if not WorldSync.is_host() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var key := ingredient
	if ingredient in GameState.FRUIT_TYPES:
		if machine_state["fruit"] != "" and machine_state["fruit"] != ingredient:
			return 0.0
		key = "fruit"
	elif ingredient not in ["sugar", "ice"]:
		return 0.0
	var stock: Dictionary = machine_state["stock"]
	var accepted := minf(amount, floorf(Balancing.LEMONADER_CAPACITY - float(stock[key])))
	if accepted <= 0.0:
		return 0.0
	stock[key] = float(stock[key]) + accepted
	if key == "fruit":
		machine_state["fruit"] = ingredient
	publish_state()
	return accepted


func batch_problem(recipe: Dictionary, fruit: String = "") -> String:
	if fruit == "":
		fruit = str(machine_state["fruit"])
	if not machine_state["batch"].is_empty():
		return "Already mixing"
	if not machine_state["pitcher"]:
		return "Place an empty pitcher first"
	if not machine_state["output"].is_empty():
		return "Take the finished pitcher first"
	if fruit == "":
		return "Load fruit first"
	for key in ["fruit_count", "water", "sugar", "ice"]:
		if typeof(recipe.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			return "Invalid recipe"
		var value := float(recipe.get(key, -1.0))
		if not is_finite(value) or value < 0.0 or value > Balancing.LEMONADER_CAPACITY:
			return "Invalid recipe"
	var fruit_count := float(recipe["fruit_count"])
	var water := float(recipe["water"])
	if fruit_count <= 0.0 or not is_equal_approx(fruit_count, floorf(fruit_count)):
		return "Use a whole positive fruit count"
	if water <= 0.0 or fruit_count + water > Balancing.PITCHER_MAX_LIQUID:
		return "Fruit + water must fit in a pitcher (max 10)"
	var missing: Array[String] = []
	for key in ["fruit", "sugar", "ice"]:
		var need := float(recipe["fruit_count" if key == "fruit" else key])
		var deficit := need - _stock_have(key, fruit)
		if deficit > 0.001:
			var label: String = fruit if key == "fruit" else key
			missing.append("%.1f %s" % [deficit, label])
	return "Missing: " + ", ".join(missing) if not missing.is_empty() else ""


## Stock lookup split out so FruitOMatic can keep per-fruit stores while
## sharing every other batch rule.
func _stock_have(key: String, _fruit: String) -> float:
	return float(machine_state["stock"].get(key, 0.0))


func _stock_consume(key: String, amount: float, _fruit: String) -> void:
	machine_state["stock"][key] = float(machine_state["stock"].get(key, 0.0)) - amount


func board_recipe(stand: StandUnit, fruit: String = "") -> Dictionary:
	if stand == null:
		return { }
	if fruit == "":
		fruit = str(machine_state["fruit"])
	var configured := stand.get_recipe(fruit)
	for key in ["fruit_count", "sugar"]:
		if typeof(configured.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			return { }
	var fruit_count := float(configured["fruit_count"])
	var sugar := float(configured["sugar"])
	if not is_finite(fruit_count) or not is_finite(sugar) or fruit_count <= 0.0 or sugar < 0.0:
		return { }
	# Ice is always the temperature-perfect amount — same formula the recipe
	# evaluator uses, not the stand's display ratio.
	var ice := maxf(1.0, floorf(GameState.temperature / 10.0))
	var mgr: Node = RecipeEvaluator._get_manager()
	if mgr != null:
		ice = mgr.get_ideal_ice(GameState.temperature)
	return {
		"fruit_count": fruit_count,
		"water": Balancing.PITCHER_MAX_LIQUID - fruit_count,
		"sugar": sugar,
		"ice": ice,
	}


## What a "mix" request resolves to. The Squeeze-E-Z fires the board
## recipe for its loaded fruit; FruitOMatic parses "mix:<fruit>" instead.
func _resolve_mix(player: Player, _action: String) -> String:
	return start_from_board(player.assigned_stand)


func start_from_board(stand: StandUnit) -> String:
	if not machine_state["batch"].is_empty():
		return "Already mixing"
	if not machine_state["pitcher"]:
		return "Place an empty pitcher first"
	if not machine_state["output"].is_empty():
		return "Take the finished pitcher first"
	var recipe := board_recipe(stand)
	if recipe.is_empty():
		return "Please set a recipe on the board."
	return start_batch(recipe)


func start_batch(recipe: Dictionary, fruit: String = "") -> String:
	if fruit == "":
		fruit = str(machine_state["fruit"])
	if not WorldSync.is_host():
		return "Waiting for host"
	var problem := batch_problem(recipe, fruit)
	if problem != "":
		return problem
	machine_state["recipe"] = recipe.duplicate(true)
	var batch := recipe.duplicate(true)
	batch["fruit_type"] = fruit
	for key in ["fruit", "sugar", "ice"]:
		_stock_consume(key, float(recipe["fruit_count" if key == "fruit" else key]), fruit)
	machine_state["batch"] = batch
	machine_state["remaining"] = Balancing.LEMONADER_MIX_SECONDS \
			/ (1.0 + UpgradeManager.get_effect_total_for_node("press_speed", self))
	publish_state()
	return "Mixing..."


func finish_batch() -> void:
	if not WorldSync.is_host() or machine_state["batch"].is_empty():
		return
	OnboardingManager.report(
		OnboardingManager.stand_for_node(self),
		"pitcher_made",
		{ "snapshot": machine_state["batch"].duplicate(true), "machine": _machine_type() },
	)
	var result: Dictionary = machine_state["batch"].duplicate(true)
	if not _adds_water():
		# Concentrate only — volume is the fruit amount; water is the
		# player's job at the dispenser before the cups are serveable.
		result["water"] = 0.0
	result["cups_poured"] = 0
	result["serving_recipe"] = { }
	machine_state["output"] = result
	machine_state["batch"] = { }
	machine_state["remaining"] = 0.0
	if float(machine_state["stock"]["fruit"]) < 0.001:
		machine_state["fruit"] = ""
	publish_state()


func publish_state() -> void:
	refresh_display()
	if is_inside_tree():
		WorldSync.sync_property(self, "machine_state", machine_state.duplicate(true))
		WorldSync.sync_call(self, "refresh_display")


func refresh_display() -> void:
	if not is_node_ready():
		return
	refresh_stock_panels()
	var pitcher := $PitcherPoint/PitcherPreview as Pitcher
	var inserted := bool(machine_state["pitcher"])
	# set_pitcher_visible hides the glass body and manages the collider;
	# hide the LemonadeFill CSG too when the slot is empty — its combiner
	# recompute is deferred, so a cleared fill could otherwise linger a
	# frame after the pitcher is taken.
	pitcher.visible = true
	if not inserted and _preview_shrinking:
		# The take-shrink tween owns the preview visuals until it finishes;
		# the callback restores scale and hides it via refresh_display().
		pass
	else:
		pitcher.set_pitcher_visible(inserted)
		var fill_node := pitcher.get_node_or_null("LemonadeFill") as Node3D
		if fill_node != null:
			fill_node.visible = inserted
	if inserted != _slot_showing_pitcher:
		var first := not _slot_display_ready
		_slot_display_ready = true
		_slot_showing_pitcher = inserted
		if not first:
			# Same feedback as placing/picking up a pitcher on a table.
			if inserted:
				WorldSync.play_place_pop(pitcher)
				AudioManager.play_sfx("pitcher", global_position, -1.0, 0.05, 0.85)
			else:
				AudioManager.play_sfx("pitcher", global_position)
	var batch: Dictionary = machine_state["batch"]
	if not batch.is_empty():
		# Mixing in progress: show the batch contents rising gradually.
		if not _mix_sound_played:
			_mix_sound_played = true
			AudioManager.play_sfx(
				"press_fruits",
				global_position,
				float(machine_state["remaining"]),
			)
		# For Squeeze-E-Z the batch recipe still carries the water the
		# stand recipe calls for, but the machine never adds it — show
		# the liquid rising to the concentrate level (fruit only), or the
		# preview visually fills to the top and only corrects on take.
		var preview_batch := batch
		if not _adds_water():
			preview_batch = batch.duplicate()
			preview_batch["water"] = 0.0
		_apply_preview_contents(pitcher, preview_batch)
		pitcher.cups_poured = 0
		pitcher.state = Pitcher.PitcherState.COMPLETE
		pitcher.update_liquid_color()
		pitcher.start_press_eraser_animation(
			pitcher.get_liquid_volume(),
			maxf(0.1, float(machine_state["remaining"])),
		)
		return
	_mix_sound_played = false
	var contents: Dictionary = machine_state["output"]
	_apply_preview_contents(pitcher, contents)
	pitcher.cups_poured = 0
	# A concentrate pitcher (no water yet) is still PREPPING — it only
	# completes once the dispenser tops it off.
	pitcher.state = (
		Pitcher.PitcherState.COMPLETE
		if not contents.is_empty() and float(contents.get("water", 0.0)) > 0.0
		else Pitcher \
				.PitcherState \
				.PREPPING
	)
	# While the take-shrink runs, leave the fill visuals untouched so the
	# liquid doesn't drain mid-pop; the callback refreshes once hidden.
	# End the mix animation only AFTER applying output contents —
	# otherwise _update_eraser_position tweens toward the stale batch
	# volume (full) and overrides the sync below.
	if not _preview_shrinking:
		pitcher.end_press_eraser_animation()
		pitcher.sync_fill_display()


## Pop-down feedback for taking the slot pitcher: shrink the real preview
## node (no copied meshes — those could render wrong for a frame), then
## hide it. refresh_display() skips its own hide while _preview_shrinking
## so the tween isn't stomped; the callback hides + restores via refresh.
func _shrink_preview_then_hide() -> void:
	var preview := get_node_or_null("PitcherPoint/PitcherPreview") as Pitcher
	if preview == null or _preview_shrinking:
		return
	_preview_shrinking = true
	if preview.physics != null:
		preview.physics.collision_layer = 0
	var base_scale := preview.scale
	var tw := create_tween()
	tw.tween_property(preview, "scale", base_scale * 1.1, 0.05) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 0.001, not ZERO — a zero-scale transform is a singular basis and
	# spams Jolt warnings.
	tw.tween_property(preview, "scale", base_scale * 0.001, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(
		func() -> void:
			_preview_shrinking = false
			if is_instance_valid(preview):
				preview.scale = base_scale
				refresh_display(),
	)


func _apply_preview_contents(pitcher: Pitcher, contents: Dictionary) -> void:
	pitcher.fruit_type = str(contents.get("fruit_type", ""))
	for key in ["fruit_count", "water", "sugar", "ice"]:
		pitcher.set(key, float(contents.get(key, 0.0)))


func refresh_stock_panels() -> void:
	for kind in ["sugar", "fruit", "ice"]:
		var panel := get_node_or_null("StockPanels/" + str(kind).capitalize()) as Node3D
		if panel == null:
			continue
		var amount := maxf(0.0, float(machine_state["stock"].get(kind, 0.0)))
		var selected: String = str(machine_state["fruit"]) if kind == "fruit" else str(kind)
		var stocked := amount > 0.001 and selected != ""
		for child in panel.get_node("Icons").get_children():
			var icon := child as Sprite3D
			if icon == null:
				continue
			icon.visible = stocked and str(icon.name) == selected
			if icon.texture != null:
				var extent := maxi(icon.texture.get_width(), icon.texture.get_height())
				icon.pixel_size = 0.09 / maxf(1.0, float(extent))
		var empty := panel.get_node("Empty") as Label3D
		empty.visible = not stocked
		var quantity := panel.get_node("Quantity") as Label3D
		quantity.text = ("%.1f" % amount).trim_suffix(".0")


func _get_output_hint() -> String:
	var pitcher := get_node_or_null("PitcherPoint/PitcherPreview") as Pitcher
	if pitcher == null or machine_state["output"].is_empty():
		return ""
	var text := " (pitcher: %s, %.1f liq)" % [
		pitcher.get_contents_string(),
		pitcher.get_liquid_volume(),
	]
	if float(machine_state["output"].get("water", 0.0)) <= 0.0:
		text += " — needs water"
	return text


func get_hint(player: Node) -> String:
	if not can_player_use(player):
		return "Other stand's Squeeze-E-Z"
	if not machine_state["batch"].is_empty():
		return (
			"Squeeze-E-Z | mixing... %.0fs left | RMB: pick up" % float(machine_state["remaining"])
		)
	var output: Dictionary = machine_state["output"]
	var inserted := bool(machine_state["pitcher"])
	var p := player as Player
	var held := HeldItem.NONE if p == null else p.held_item
	match held:
		HeldItem.NONE:
			if not output.is_empty():
				return "Squeeze-E-Z | LMB: take pitcher%s | RMB: pick up machine" \
						% _get_output_hint()
			if inserted:
				var recipe := (board_recipe(p.assigned_stand) if p != null else { })
				if recipe.is_empty():
					return "Squeeze-E-Z | set a recipe on the board first"
				var problem := batch_problem(recipe)
				if problem != "":
					return "Squeeze-E-Z | %s" % problem
				return "Squeeze-E-Z | LMB: make lemonade | RMB: pick up machine"
			return "Squeeze-E-Z | LMB/RMB: pick up | insert an empty pitcher to mix"
		HeldItem.CONTAINER:
			if p.held_item_data.get("container_type") != "pitcher":
				return "Squeeze-E-Z"
			if can_attach_pitcher(p.held_item_data.get("saved_recipe", { })):
				return "Squeeze-E-Z | LMB: insert pitcher"
			if inserted:
				return "Squeeze-E-Z | output slot occupied"
			return "Squeeze-E-Z | pitcher must be empty"
		HeldItem.SUPPLY_BOX:
			var itype := str(p.held_item_data.get("ingredient_type", ""))
			if itype == "":
				return "Squeeze-E-Z"
			if itype in GameState.FRUIT_TYPES:
				var loaded := str(machine_state["fruit"])
				if loaded != "" and loaded != itype:
					return "Squeeze-E-Z | already has %s" % loaded.capitalize()
			elif itype not in ["sugar", "ice"]:
				return "Squeeze-E-Z | only accepts fruit, sugar, ice"
			return "Squeeze-E-Z | LMB: load %s" % itype.capitalize()
	return "Squeeze-E-Z"


## Placement-ghost support (duck-typed by PlayerPlacement to avoid a
## script dependency cycle): true while an empty pitcher can be inserted.
func can_attach_pitcher(recipe: Dictionary) -> bool:
	if machine_state["pitcher"]:
		return false
	for key in ["fruit_count", "water", "sugar", "ice"]:
		if float(recipe.get(key, 0.0)) > 0.0:
			return false
	return true


## World-space position where an inserted pitcher renders — the ghost
## preview snaps there, matching where the real preview sits.
func get_pitcher_snap_global_position() -> Vector3:
	var preview := get_node_or_null("PitcherPoint/PitcherPreview") as Node3D
	if preview != null:
		return preview.global_position
	return global_position


func interact(player: Node) -> void:
	var p := player as Player
	if p == null or not can_player_use(p):
		return
	if p.held_item == HeldItem.NONE:
		if not machine_state["output"].is_empty():
			request_action(p, "take")
		elif not machine_state["pitcher"]:
			# Empty machine — LMB picks it up like any other container.
			p.pickup_container(self, _machine_type())
		else:
			request_action(p, "mix")
	elif p.held_item == HeldItem.SUPPLY_BOX:
		request_action(p, "deposit")
	elif p.held_item == HeldItem.CONTAINER and p.held_item_data.get("container_type") == "pitcher":
		request_action(p, "attach")


func interact_secondary(player: Node) -> void:
	# RMB always picks up the whole machine — the slot pitcher is a child
	# of this node and travels with it, like items on a workstation.
	var p := player as Player
	if p != null and p.held_item == HeldItem.NONE and can_player_use(p):
		p.pickup_container(self, _machine_type())


func request_action(player: Player, action: String) -> void:
	if player.held_item_data.get("pickup_pending", false):
		return
	player.held_item_data["pickup_pending"] = true
	var origin := _get_hand_pos(player)
	if WorldSync.is_host():
		execute_action(player, action, origin)
	else:
		_request_action.rpc_id(1, action, origin)


@rpc("any_peer", "reliable")
func _request_action(action: String, origin: Vector3) -> void:
	if not WorldSync.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and node.get_multiplayer_authority() == sender:
			execute_action(node, action, origin)
			return


func execute_action(player: Player, action: String, origin: Vector3 = Vector3.INF) -> void:
	if not WorldSync.is_host():
		return
	if not origin.is_finite() or origin.distance_to(player.global_position) > 2.5:
		origin = _get_hand_pos(player)
	var message := ""
	var applied := 0.0
	var output: Dictionary = { }
	var success := false
	if not can_player_use(player) or player.global_position.distance_to(global_position) > 4.0:
		message = "Machine out of reach or belongs to another stand"
	elif action == "deposit" and player.held_item == HeldItem.SUPPLY_BOX:
		var data: Dictionary = player.held_item_data
		var ingredient := str(data.get("ingredient_type", ""))
		var owner := str(data.get("box_stand_owner", ""))
		if owner != "" and stand_owner != "" and owner != stand_owner:
			message = "Use supplies from your own stand"
		elif (
			ingredient in GameState.FRUIT_TYPES
			and (
				player.assigned_stand == null
				or not player.assigned_stand.is_fruit_unlocked(ingredient)
			)
		):
			message = "Fruit is locked"
		else:
			# One click deposits one unit, matching the ingredient bins —
			# a loose scoop dumps its whole scoop, a delivery box pays out
			# GRAB_AMOUNT per click (held click repeats via rapid fire).
			var requested := float(data.get("amount", 0.0))
			if str(data.get("source", "")) == "delivery":
				requested = minf(Balancing.GRAB_AMOUNT, requested)
			applied = deposit(ingredient, requested)
			success = applied > 0.0
			message = "Loaded %.0f" % applied if success else "Full or different fruit loaded"
			if success:
				animate_deposit(ingredient, applied, origin)
				WorldSync.sync_call(self, "animate_deposit", [ingredient, applied, origin])
				EventBus.supply_box_deposited.emit(ingredient, applied)
	elif action == "attach" and player.held_item == HeldItem.CONTAINER:
		var saved: Dictionary = player.held_item_data.get("saved_recipe", { })
		var empty := true
		for key in ["fruit_count", "water", "sugar", "ice"]:
			empty = empty and float(saved.get(key, 0.0)) <= 0.0
		if player.held_item_data.get("container_type") == "pitcher" and empty and not machine_state[
				"pitcher"
			]:
			machine_state["pitcher"] = true
			success = true
		else:
			message = "Needs an empty pitcher and a free output slot"
	elif action == "take" and player.held_item == HeldItem.NONE:
		if machine_state["pitcher"] and machine_state["batch"].is_empty():
			output = machine_state["output"].duplicate(true)
			machine_state["pitcher"] = false
			machine_state["output"] = { }
			success = true
		else:
			message = "No pitcher available — wait until mixing finishes"
	elif ((action == "mix" or action.begins_with("mix:")) and player.held_item == HeldItem.NONE):
		message = _resolve_mix(player, action)
	else:
		message = "Interaction no longer available"
	if success:
		settle_inventory(player, action, applied, output)
	publish_state()
	var peer := player.get_multiplayer_authority()
	if peer == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
		show_result(message)
	else:
		_action_result.rpc_id(peer, action, success, applied, output, message)


func settle_inventory(player: Player, action: String, applied: float, output: Dictionary) -> void:
	player.held_item_data.erase("pickup_pending")
	if action == "attach":
		player.inventory.clear_held()
	elif action == "take":
		# Shrink the real slot preview itself — no copied afterimage (the
		# copy path spawned mid-frame meshes that could flash white).
		# Suppress set_held's own source-shrink so nothing plays twice.
		player.inventory.suppress_next_pickup_effect()
		_shrink_preview_then_hide()
		GameLog.log("[DIAG] take output=%s" % str(output))
		player.placement.hold_container("pitcher", 0.0, 0, not output.is_empty(), output)
	elif action == "deposit":
		var remaining := maxf(0.0, float(player.held_item_data.get("amount", 0.0)) - applied)
		if remaining > 0.0:
			player.inventory.update_held_amount(remaining)
		elif player.held_item_data.get("source", "") == "delivery":
			player.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
		else:
			player.inventory.clear_held()


@rpc("authority", "reliable")
func _action_result(
	action: String,
	success: bool,
	applied: float,
	output: Dictionary,
	message: String,
) -> void:
	var player := WorldSync.get_local_player() as Player
	if player != null:
		player.held_item_data.erase("pickup_pending")
		if success:
			settle_inventory(player, action, applied, output)
	show_result(message)


func show_result(message: String) -> void:
	var player := WorldSync.get_local_player()
	if player != null:
		player.held_item_data.erase("pickup_pending")
	if message != "":
		# Results go to the on-screen hint tooltip — no floating Label3D
		# above the machine.
		EventBus.interaction_hint_changed.emit(message)
