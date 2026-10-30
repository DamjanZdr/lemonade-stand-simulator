extends CanvasLayer
## Always-visible right panel for balancing tweaks. Never needs to be opened.

@onready var stats_label: Label = $Panel/VBox/StatsLabel
@onready var verdict_label: Label = $Panel/VBox/VerdictLabel

var _refresh_timer: float = 0.0
var _test_payment_cooldown: float = 0.0


func _enter_tree() -> void:
	# Hide as early as possible so the panel never flashes on screen
	visible = false


func _input(event: InputEvent) -> void:
	# Debug tool — dead in release builds (editor/debug runs only).
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1:
			visible = not visible
			get_viewport().set_input_as_handled()


func _ready() -> void:
	visible = false
	$Panel/VBox/BtnMoney.pressed.connect(
		func():
			_debug_action("add_money", { "amount": 1000.0 }),
	)
	$Panel/VBox/BtnRefill.pressed.connect(
		func():
			_debug_action("refill_bins", { }),
	)
	$Panel/VBox/BtnEmpty.pressed.connect(
		func():
			_debug_action("empty_pitcher", { }),
	)
	$Panel/VBox/BtnSpawn.pressed.connect(
		func():
			_debug_action("force_spawn_customer", { }),
	)
	$Panel/VBox/BtnForceHappy.pressed.connect(
		func():
			_debug_action("force_happy_serve", { }),
	)
	$Panel/VBox/BtnTestPayment.pressed.connect(
		func():
			if _test_payment_cooldown > 0.0:
				return
			_test_payment_cooldown = 1.0
			# Mirror customer._customer_payment() so the bill reflects the live price.
			var price := _local_price("lemon")
			var payment: float
			if price <= 1.0:
				payment = 1.0
			elif price <= 5.0:
				payment = 5.0
			else:
				payment = 10.0
			var change_due := roundf((payment - price) * 100.0) / 100.0
			EventBus.sale_initiated.emit(payment, change_due),
	)
	$Panel/VBox/TempSlider.value_changed.connect(
		func(v: float):
			# Weather is world-global, not stand-scoped: apply locally for
			# instant feedback AND through the host so the global value moves.
			EventBus.debug_set_temperature.emit(v)
			_debug_action("set_temperature", { "value": v }),
	)
	$Panel/VBox/TierSlider.value_changed.connect(
		func(v: float):
			_debug_action("set_feedback_tier", { "tier": int(v) }),
	)
	$Panel/VBox/SpawnSlider.value_changed.connect(
		func(v: float):
			EventBus.debug_set_spawn_rate.emit(v),
	)
	$Panel/VBox/QueueMaxSlider.value_changed.connect(
		func(v: float):
			_debug_action("set_queue_max", { "value": int(v) }),
	)
	$Panel/VBox/OutlineWidthSlider.value_changed.connect(
		func(v: float):
			EventBus.debug_set_outline_width.emit(v),
	)
	$Panel/VBox/OutlineColorPicker.color_changed.connect(
		func(c: Color):
			EventBus.debug_set_outline_color.emit(c),
	)

	# Popularity override — added in script to avoid editing the .tscn.
	var vbox := $Panel/VBox
	var pop_label := Label.new()
	pop_label.text = "Popularity:"
	pop_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(pop_label)
	var pop_slider := HSlider.new()
	pop_slider.min_value = 0.0
	pop_slider.max_value = Balancing.MAX_POPULARITY
	pop_slider.step = 1.0
	var stand := _local_stand()
	pop_slider.value = stand.popularity if stand != null else GameState.popularity
	pop_slider.custom_minimum_size = Vector2(0, 12)
	pop_slider.value_changed.connect(
		func(v: float):
			_debug_action("set_popularity", { "value": v }),
	)
	vbox.add_child(pop_slider)

	# Time scale buttons
	var time_label := Label.new()
	time_label.text = "Time Scale:"
	time_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(time_label)
	var time_row := HBoxContainer.new()
	for speed in [1.0, 2.0, 5.0, 10.0]:
		var btn := Button.new()
		btn.text = "x%d" % int(speed)
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(
			func():
				EventBus.debug_set_time_scale.emit(speed),
		)
		time_row.add_child(btn)
	vbox.add_child(time_row)
	EventBus.debug_set_time_scale.connect(
		func(s: float):
			Engine.time_scale = s,
	)

	# House color toggles
	var roofs_cb := CheckBox.new()
	roofs_cb.text = "Color Roofs"
	roofs_cb.button_pressed = GameState.color_roofs
	roofs_cb.toggled.connect(
		func(v: bool):
			GameState.color_roofs = v
			EventBus.debug_set_color_roofs.emit(v),
	)
	vbox.add_child(roofs_cb)

	var walls_cb := CheckBox.new()
	walls_cb.text = "Color Walls"
	walls_cb.button_pressed = GameState.color_walls
	walls_cb.toggled.connect(
		func(v: bool):
			GameState.color_walls = v
			EventBus.debug_set_color_walls.emit(v),
	)
	vbox.add_child(walls_cb)

	# Reset save button
	var reset_btn := Button.new()
	reset_btn.text = "Reset Save"
	reset_btn.add_theme_font_size_override("font_size", 9)
	reset_btn.pressed.connect(
		func():
			EventBus.game_reset.emit()
			# Also reset GameState to defaults
			GameState.money = Balancing.STARTING_MONEY
			GameState.popularity = Balancing.STARTING_POPULARITY
			GameState.temperature = 25.0
			for ft in GameState.FRUIT_TYPES:
				GameState.prices[ft] = 1.50
			GameState.feedback_tier = 0
			GameState.customers_served_happy = 0
			GameState.customers_lost = 0
			DayManager.day_number = 1
			UpgradeManager.reset()
			# Reset containers to default state and position
			var root := get_tree().current_scene
			if root:
				for node in root.get_tree().get_nodes_in_group("supply_box"):
					node.queue_free()
				SaveManager.respawn_default_containers()
			EventBus.money_changed.emit(GameState.money)
			EventBus.popularity_changed.emit(GameState.popularity)
			EventBus.weather_changed.emit(GameState.temperature)
			for ft in GameState.FRUIT_TYPES:
				EventBus.price_changed.emit(ft, GameState.get_price(ft))
			EventBus.feedback_tier_changed.emit(GameState.feedback_tier),
	)
	vbox.add_child(reset_btn)

	# End day early button
	var end_day_btn := Button.new()
	end_day_btn.text = "End Day Early"
	end_day_btn.add_theme_font_size_override("font_size", 9)
	end_day_btn.pressed.connect(
		func():
			# The day is world-global but host-authoritative — route
			# through the debug funnel so clients can trigger it too.
			_debug_action("end_day", { }),
	)
	vbox.add_child(end_day_btn)

	# Upgrade branches — "+1" fills the bar to its next threshold so
	# each click makes exactly one tier claimable.
	vbox.add_child(HSeparator.new())
	var up_label := Label.new()
	up_label.text = "Upgrades (+1 tier):"
	up_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(up_label)
	for branch in UpgradeManager.get_branches():
		var row := HBoxContainer.new()
		var branch_lbl := Label.new()
		branch_lbl.text = str(branch.get("name", branch.get("id", "?")))
		branch_lbl.add_theme_font_size_override("font_size", 8)
		branch_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(branch_lbl)
		var branch_btn := Button.new()
		branch_btn.text = "+1"
		branch_btn.add_theme_font_size_override("font_size", 9)
		var branch_id := str(branch.get("id", ""))
		branch_btn.pressed.connect(
			func():
				var local := WorldSync.get_local_stand() as StandUnit
				if local != null:
					OnboardingManager.report(local, "debug_fill_branch", { "branch": branch_id }),
		)
		row.add_child(branch_btn)
		vbox.add_child(row)

	# NPC roster tools
	vbox.add_child(HSeparator.new())
	var meet_btn := Button.new()
	meet_btn.text = "Meet All NPCs"
	meet_btn.add_theme_font_size_override("font_size", 9)
	meet_btn.pressed.connect(_on_meet_all_npcs)
	vbox.add_child(meet_btn)
	var nine_btn := Button.new()
	nine_btn.text = "Set All NPCs 9/10"
	nine_btn.add_theme_font_size_override("font_size", 9)
	nine_btn.pressed.connect(_on_set_all_nine)
	vbox.add_child(nine_btn)
	var npc_edit := LineEdit.new()
	npc_edit.placeholder_text = "NPC name"
	npc_edit.add_theme_font_size_override("font_size", 9)
	vbox.add_child(npc_edit)
	var npc_btn := Button.new()
	npc_btn.text = "Spawn NPC"
	npc_btn.add_theme_font_size_override("font_size", 9)
	npc_btn.pressed.connect(_on_spawn_named_npc.bind(npc_edit))
	vbox.add_child(npc_btn)

	# The VBox has outgrown the screen height — wrap it in a
	# ScrollContainer so every control stays reachable. Done last so
	# all the $Panel/VBox/... lookups above still resolve.
	var panel := $Panel
	panel.remove_child(vbox)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	scroll.add_child(vbox)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_refresh()


## The stand this peer's player is assigned to — every stand-scoped
## debug action targets it (versus: the joiner's own stand, not the
## host's primary stand).
func _local_stand() -> StandUnit:
	return WorldSync.get_local_stand() as StandUnit


func _local_price(fruit_type: String) -> float:
	var stand := _local_stand()
	return stand.get_price(fruit_type) if stand != null else GameState.get_price(fruit_type)


## Route a stand-scoped debug action through the OnboardingManager
## report funnel: clients send an RPC to the host, the host validates
## the sender's assigned stand, then StandUnit.apply_debug_action
## mutates authoritative state and pushes it to all peers.
func _debug_action(action: String, params: Dictionary) -> void:
	var stand := _local_stand()
	if stand == null:
		return
	OnboardingManager.report(stand, "debug_action", { "action": action, "params": params })


func _on_meet_all_npcs() -> void:
	var stand := _local_stand()
	if stand != null:
		stand.request_meet_all_npcs()


func _on_set_all_nine() -> void:
	var stand := _local_stand()
	if stand != null:
		stand.request_set_all_npcs_nine()


func _on_spawn_named_npc(edit: LineEdit) -> void:
	var npc_id := NpcRoster.find_id_by_name(edit.text)
	if npc_id < 0:
		edit.text = ""
		edit.placeholder_text = "No match"
		return
	var npc_name := str(NpcRoster.get_entry(npc_id).get("name", ""))
	edit.text = ""
	edit.placeholder_text = "Spawned %s" % npc_name
	_debug_action("spawn_npc", { "npc_id": npc_id })


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_refresh()
	if _test_payment_cooldown > 0.0:
		_test_payment_cooldown -= delta


func _refresh() -> void:
	var stand := _local_stand()
	# Prefer a pitcher owned by the local stand; fall back to any.
	var pitcher: Pitcher = null
	for p in get_tree().get_nodes_in_group("pitcher"):
		var owner := OnboardingManager.stand_for_node(p)
		if owner != null and owner != stand:
			continue
		pitcher = p as Pitcher
		if owner == stand:
			break
	var recipe: Dictionary = pitcher.get_recipe_snapshot() if pitcher else { }
	var verdict := (
		RecipeEvaluator.get_verdict_string(recipe, GameState.temperature)
		if pitcher
		else "No pitcher"
	)

	var money: float = stand.money if stand != null else GameState.money
	var popularity: float = (stand.popularity if stand != null else GameState.popularity)
	var tier: int = (stand.feedback_tier if stand != null else GameState.feedback_tier)
	var price: float = _local_price("lemon")

	stats_label.text = (
		"Money: $%.2f\nPop: %d%%\nTemp: %.0fC\nTier: %d\nPrice: $%.2f (lemon)"
		% [money, int(popularity / 10.0), GameState.temperature, tier, price]
	)
	verdict_label.text = "Recipe: " + verdict
