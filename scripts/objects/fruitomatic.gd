class_name FruitOMatic
extends Lemonader
## Multi-fruit mixer. Same pitcher/deposit/pickup behavior as the
## Squeeze-E-Z; the difference is starting a batch — the player picks a
## stocked fruit from a camera-focused menu instead of the machine using
## its single loaded fruit.


func _init() -> void:
	# Per-fruit stores live alongside the inherited state shape; the
	# legacy single-fruit "fruit" key stays empty on this machine.
	machine_state["fruits"] = { }


var _focused_player: Player = null


func _machine_type() -> String:
	return "fruitomatic"


func _machine_name() -> String:
	return "Fruit-O-Matic"


## The full-automation tier: Fruit-O-Matic adds water itself, unlike
## the Squeeze-E-Z which leaves topoff to the player.
func _adds_water() -> bool:
	return true


func deposit(ingredient: String, amount: float) -> float:
	if not WorldSync.is_host() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	if ingredient in GameState.FRUIT_TYPES:
		var fruits: Dictionary = machine_state["fruits"]
		var have := float(fruits.get(ingredient, 0.0))
		var accepted := minf(amount, floorf(Balancing.LEMONADER_CAPACITY - have))
		if accepted <= 0.0:
			return 0.0
		fruits[ingredient] = have + accepted
		publish_state()
		return accepted
	if ingredient not in ["sugar", "ice"]:
		return 0.0
	var stock: Dictionary = machine_state["stock"]
	var applied := minf(amount, floorf(Balancing.LEMONADER_CAPACITY - float(stock[ingredient])))
	if applied <= 0.0:
		return 0.0
	stock[ingredient] = float(stock[ingredient]) + applied
	publish_state()
	return applied


func _stock_have(key: String, fruit: String) -> float:
	if key == "fruit":
		return float(machine_state["fruits"].get(fruit, 0.0))
	return float(machine_state["stock"].get(key, 0.0))


func _stock_consume(key: String, amount: float, fruit: String) -> void:
	if key == "fruit":
		var fruits: Dictionary = machine_state["fruits"]
		var left := float(fruits.get(fruit, 0.0)) - amount
		if left < 0.001:
			fruits.erase(fruit)
		else:
			fruits[fruit] = left
	else:
		machine_state["stock"][key] = float(machine_state["stock"].get(key, 0.0)) - amount


func _resolve_mix(player: Player, action: String) -> String:
	var fruit := action.get_slice(":", 1)
	if fruit not in GameState.FRUIT_TYPES:
		return "Pick a fruit first"
	var recipe := board_recipe(player.assigned_stand, fruit)
	if recipe.is_empty():
		return "Set a %s recipe on the board." % fruit.capitalize()
	return start_batch(recipe, fruit)


func refresh_stock_panels() -> void:
	# One grouped label for sugar + ice, one row of six labels for the
	# per-fruit stores — each panel tracks its own stock amount.
	var stock: Dictionary = machine_state["stock"]
	for kind in ["sugar", "ice"]:
		_update_stock_panel(
			get_node_or_null("StockPanels/SugarIce/" + kind.capitalize()) as Node3D,
			kind,
			float(stock.get(kind, 0.0)),
		)
	var batch_fruit := str(machine_state["batch"].get("fruit_type", ""))
	var fruits: Dictionary = machine_state["fruits"]
	for fruit in GameState.FRUIT_TYPES:
		var amount := float(fruits.get(fruit, 0.0))
		_update_stock_panel(
			get_node_or_null("StockPanels/Fruits/" + str(fruit).capitalize()) as Node3D,
			str(fruit),
			amount,
		)
		var btn := get_node_or_null("StockPanels/Fruits/Start" + str(fruit).capitalize())
		if btn != null:
			if btn.has_method("set_available"):
				btn.set_available(amount > 0.001)
			if btn.has_method("set_engaged"):
				btn.set_engaged(batch_fruit == str(fruit))


func _update_stock_panel(panel: Node3D, icon_name: String, amount: float) -> void:
	if panel == null:
		return
	for child in panel.get_node("Icons").get_children():
		var icon := child as Sprite3D
		if icon != null:
			icon.visible = amount > 0.001 and str(icon.name) == icon_name
			if icon.texture != null:
				var extent := maxi(icon.texture.get_width(), icon.texture.get_height())
				icon.pixel_size = 0.09 / maxf(1.0, float(extent))
	panel.get_node("Empty").visible = amount <= 0.001
	(panel.get_node("Quantity") as Label3D).text = ("%.1f" % maxf(0.0, amount)).trim_suffix(".0")


func show_result(message: String) -> void:
	super.show_result(message)
	if message.begins_with("Missing:"):
		_flash_missing(message.trim_prefix("Missing:").strip_edges())


## Local pre-check used by the START buttons so a doomed batch keeps the
## camera focused — the flashing X and the hint explain what's missing.
## The real request still re-validates on the host.
func predict_mix_problem(player: Player, fruit: String) -> String:
	if fruit not in GameState.FRUIT_TYPES:
		return "Pick a fruit first"
	var recipe := board_recipe(player.assigned_stand, fruit)
	if recipe.is_empty():
		return "Set a %s recipe on the board." % fruit.capitalize()
	return batch_problem(recipe, fruit)


## Blinks the red X on each stock panel named by a "Missing: ..." result —
## two brighter-red pulses so the player sees which ingredients are short
## (fruit, sugar, or ice).
func _flash_missing(list: String) -> void:
	for part in list.split(","):
		var ingredient := part.strip_edges().get_slice(" ", 1)
		var panel: Node3D = null
		if ingredient in GameState.FRUIT_TYPES:
			panel = get_node_or_null("StockPanels/Fruits/" + ingredient.capitalize()) as Node3D
		elif ingredient in ["sugar", "ice"]:
			panel = get_node_or_null("StockPanels/SugarIce/" + ingredient.capitalize()) as Node3D
		if panel == null:
			continue
		var x := panel.get_node_or_null("Empty") as Label3D
		if x == null:
			continue
		x.visible = true
		var dim := x.modulate
		var tween := create_tween()
		for i in range(2):
			tween.tween_property(x, "modulate", Color(1, 0.65, 0.65), 0.08)
			tween.tween_property(x, "modulate", dim, 0.16)
		tween.finished.connect(refresh_stock_panels)


func get_hint(player: Node) -> String:
	if not can_player_use(player):
		return "Other stand's Fruit-O-Matic"
	if not machine_state["batch"].is_empty():
		return (
			"Fruit-O-Matic | mixing... %.0fs left | RMB: pick up"
			% float(machine_state["remaining"])
		)
	var output: Dictionary = machine_state["output"]
	var inserted := bool(machine_state["pitcher"])
	var p := player as Player
	var held := HeldItem.NONE if p == null else p.held_item
	match held:
		HeldItem.NONE:
			if not output.is_empty():
				return "Fruit-O-Matic | LMB: take pitcher%s | RMB: pick up machine" \
						% _get_output_hint()
			if inserted:
				if (machine_state["fruits"] as Dictionary).is_empty():
					return "Fruit-O-Matic | load fruit first"
				return "Fruit-O-Matic | LMB: choose fruit & mix | RMB: pick up machine"
			return "Fruit-O-Matic | LMB/RMB: pick up | insert an empty pitcher to mix"
		HeldItem.CONTAINER:
			if p.held_item_data.get("container_type") != "pitcher":
				return "Fruit-O-Matic"
			if can_attach_pitcher(p.held_item_data.get("saved_recipe", { })):
				return "Fruit-O-Matic | LMB: insert pitcher"
			if inserted:
				return "Fruit-O-Matic | output slot occupied"
			return "Fruit-O-Matic | pitcher must be empty"
		HeldItem.SUPPLY_BOX:
			var itype := str(p.held_item_data.get("ingredient_type", ""))
			if itype == "":
				return "Fruit-O-Matic"
			if itype not in GameState.FRUIT_TYPES and itype not in ["sugar", "ice"]:
				return "Fruit-O-Matic | only accepts fruit, sugar, ice"
			return "Fruit-O-Matic | LMB: load %s" % itype.capitalize()
	return "Fruit-O-Matic"


func interact(player: Node) -> void:
	var p := player as Player
	if p == null or not can_player_use(p):
		return
	if p.held_item == HeldItem.NONE:
		if not machine_state["output"].is_empty():
			request_action(p, "take")
		elif not machine_state["pitcher"]:
			p.pickup_container(self, _machine_type())
		else:
			# Unlike the EZ there is no single loaded fruit — pull the camera
			# to the machine so the player can click a fruit's START button.
			open_fruit_select(p)
	elif p.held_item == HeldItem.SUPPLY_BOX:
		request_action(p, "deposit")
	elif p.held_item == HeldItem.CONTAINER and p.held_item_data.get("container_type") == "pitcher":
		request_action(p, "attach")


## LMB on an inserted empty pitcher: camera pulls to the machine (and
## adopts the FocusCamera's fov) so the player can aim at a fruit's 3D
## START button. The button click sends "mix:<fruit>" to the host like
## any other machine action; Esc backs out.
func open_fruit_select(player: Player) -> void:
	if _focused_player != null:
		return
	var cam := get_node_or_null("FocusCamera") as Camera3D
	if cam == null:
		return
	# Keep the HUD up — START button results (missing ingredients, no
	# recipe set) are reported in the bottom hint bar while focused.
	player.enter_priceboard_focus(cam.global_transform, cam.fov, false)
	_focused_player = player


func close_fruit_select() -> void:
	if _focused_player != null:
		_focused_player.exit_priceboard_focus()
		_focused_player = null


func _unhandled_input(event: InputEvent) -> void:
	if _focused_player == null:
		return
	if event.is_action_pressed("ui_cancel"):
		close_fruit_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary_interact"):
		# Priceboard mode frees the cursor — pick the world interactable
		# under the mouse and let it handle the click (START buttons route
		# "mix:<fruit>" back through request_action).
		var target := _pick_interactable_at_mouse()
		if target != null:
			target.interact(_focused_player)
		get_viewport().set_input_as_handled()


func _pick_interactable_at_mouse() -> Interactable:
	if _focused_player == null or _focused_player.camera == null:
		return null
	var cam := _focused_player.camera
	var mouse := get_viewport().get_mouse_position()
	# The START buttons sit behind the machine's big body collider from the
	# focus angle, so a physics ray hits the body first and never reaches
	# them. Pick them in screen space instead — nearest projected button
	# within a generous radius wins, which also makes the small buttons
	# comfortably clickable.
	var best: Interactable = null
	var best_dist := 32.0
	var fruits_node := get_node_or_null("StockPanels/Fruits")
	if fruits_node != null:
		for fruit in GameState.FRUIT_TYPES:
			var btn := fruits_node.get_node_or_null("Start" + str(fruit).capitalize()) as Node3D
			if btn == null or cam.is_position_behind(btn.global_position):
				continue
			var dist := cam.unproject_position(btn.global_position).distance_to(mouse)
			if dist < best_dist:
				best_dist = dist
				best = btn as Interactable
	if best != null:
		return best
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 8.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_focused_player.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit["collider"]
	while node != null:
		if node is Interactable:
			return node as Interactable
		node = node.get_parent()
	return null


func _exit_tree() -> void:
	close_fruit_select()
