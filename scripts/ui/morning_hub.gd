extends CanvasLayer
## Morning hub: Analytics, Shop, Upgrades. Compact, animated, lemonade-stand vibe.

@onready var panel: PanelContainer = $Panel
@onready var vbox: VBoxContainer = $Panel/VBox
@onready var backdrop: ColorRect = $Backdrop

var _tab_bar: HBoxContainer
var _content: MarginContainer
var _status_lbl: Label
var _start_btn: Button
var _pages: Dictionary = { }
var _active_tab: String = "analytics"
var _shop_qty: Dictionary = { }

const SHOP_ITEMS: Array[Dictionary] = [
	{ "id": "lemon", "name": "Lemons", "cost": 2.0, "qty": 10 },
	{ "id": "strawberry", "name": "Strawberry", "cost": 3.0, "qty": 10 },
	{ "id": "blueberry", "name": "Blueberry", "cost": 3.5, "qty": 10 },
	{ "id": "peach", "name": "Peach", "cost": 4.0, "qty": 10 },
	{ "id": "watermelon", "name": "Watermelon", "cost": 5.0, "qty": 10 },
	{ "id": "sugar", "name": "Sugar", "cost": 1.5, "qty": 10 },
	{ "id": "ice", "name": "Ice", "cost": 1.0, "qty": 10 },
	{ "id": "cups", "name": "Cups", "cost": 0.5, "qty": 10 },
]

const CONTAINER_ITEMS: Array[Dictionary] = [
	{ "id": "lemon_bin", "name": "Lemon Crate", "cost": Balancing.CONTAINER_COST_LEMON_BIN },
	{ "id": "sugar_bin", "name": "Sugar Bin", "cost": Balancing.CONTAINER_COST_SUGAR_BIN },
	{ "id": "ice_bin", "name": "Ice Plate", "cost": Balancing.CONTAINER_COST_ICE_BIN },
	{ "id": "cup_stack", "name": "Cup Stack", "cost": Balancing.CONTAINER_COST_CUP_STACK },
	{ "id": "pitcher", "name": "Pitcher", "cost": Balancing.CONTAINER_COST_PITCHER },
	{ "id": "press", "name": "Fruit Press", "cost": Balancing.CONTAINER_COST_PRESS },
]


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	while vbox.get_child_count() > 0:
		var c := vbox.get_child(0)
		vbox.remove_child(c)
		c.queue_free()
	_build_ui()
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	_show_tab("analytics")


func _detach_current_page() -> void:
	while _content.get_child_count() > 0:
		var c := _content.get_child(0)
		_content.remove_child(c)


func _build_ui() -> void:
	# Opaque warm background for the whole panel — fully opaque, no see-through
	var panel_st := StyleBoxFlat.new()
	panel_st.bg_color = Color(0.08, 0.06, 0.03)
	panel_st.border_color = Color(0.50, 0.35, 0.18)
	panel_st.border_width_left = 10
	panel_st.border_width_top = 10
	panel_st.border_width_right = 10
	panel_st.border_width_bottom = 10
	panel_st.set_corner_radius_all(24)
	panel.add_theme_stylebox_override("panel", panel_st)
	panel.modulate = Color(1, 1, 1, 1)

	# Header
	var header := HBoxContainer.new()
	header.name = "Header"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var day_lbl := Label.new()
	day_lbl.name = "DayLabel"
	day_lbl.add_theme_font_size_override("font_size", 22)
	day_lbl.text = "Day 1"
	header.add_child(day_lbl)
	var money_lbl := Label.new()
	money_lbl.name = "MoneyLabel"
	money_lbl.add_theme_font_size_override("font_size", 20)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_lbl.text = "Money: $%.2f" % GameState.money
	header.add_child(money_lbl)
	var temp_lbl := Label.new()
	temp_lbl.name = "TempLabel"
	temp_lbl.add_theme_font_size_override("font_size", 16)
	temp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	temp_lbl.text = "25C"
	header.add_child(temp_lbl)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	# Price row
	var price_row := HBoxContainer.new()
	price_row.name = "PriceRow"
	var price_title := Label.new()
	price_title.text = "Cup Price:"
	price_row.add_child(price_title)
	var price_slider := HSlider.new()
	price_slider.name = "PriceSlider"
	price_slider.min_value = Balancing.PRICE_MIN
	price_slider.max_value = Balancing.PRICE_MAX
	price_slider.step = 0.05
	price_slider.value = GameState.current_price
	price_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_slider.value_changed.connect(_on_price_changed)
	price_row.add_child(price_slider)
	var price_val := Label.new()
	price_val.name = "PriceValue"
	price_val.text = "$%.2f" % GameState.current_price
	price_row.add_child(price_val)
	vbox.add_child(price_row)
	vbox.add_child(HSeparator.new())

	# Tabs
	_tab_bar = HBoxContainer.new()
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bar.add_theme_constant_override("separation", 12)
	for tab_name in ["analytics", "shop", "upgrades"]:
		var btn := Button.new()
		btn.name = "Tab_" + tab_name
		btn.text = tab_name.capitalize()
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 20)
		var btn_st := StyleBoxFlat.new()
		btn_st.bg_color = Color(0.25, 0.18, 0.08)
		btn_st.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", btn_st)
		var btn_st_p := StyleBoxFlat.new()
		btn_st_p.bg_color = Color(0.55, 0.40, 0.15)
		btn_st_p.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("pressed", btn_st_p)
		var btn_st_h := StyleBoxFlat.new()
		btn_st_h.bg_color = Color(0.40, 0.28, 0.10)
		btn_st_h.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("hover", btn_st_h)
		btn.pressed.connect(func(): _show_tab(tab_name))
		_tab_bar.add_child(btn)
	vbox.add_child(_tab_bar)
	vbox.add_child(HSeparator.new())

	# Content
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_content.add_theme_constant_override(side, 8)
	vbox.add_child(_content)

	# Status
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_status_lbl)

	# Start Day
	_start_btn = Button.new()
	_start_btn.text = "Open Stand!"
	_start_btn.add_theme_font_size_override("font_size", 26)
	var start_st := StyleBoxFlat.new()
	start_st.bg_color = Color(0.60, 0.45, 0.15)
	start_st.set_corner_radius_all(14)
	_start_btn.add_theme_stylebox_override("normal", start_st)
	var start_st_h := StyleBoxFlat.new()
	start_st_h.bg_color = Color(0.75, 0.58, 0.22)
	start_st_h.set_corner_radius_all(14)
	_start_btn.add_theme_stylebox_override("hover", start_st_h)
	var start_st_p := StyleBoxFlat.new()
	start_st_p.bg_color = Color(0.45, 0.32, 0.08)
	start_st_p.set_corner_radius_all(14)
	_start_btn.add_theme_stylebox_override("pressed", start_st_p)
	_start_btn.pressed.connect(_on_start_day)
	vbox.add_child(_start_btn)

	_build_analytics_page()
	_build_shop_page()
	_build_upgrades_page()


func _build_analytics_page() -> void:
	var page := VBoxContainer.new()
	page.name = "AnalyticsPage"
	page.add_theme_constant_override("separation", 10)

	var today := Label.new()
	today.name = "TodayLabel"
	today.add_theme_font_size_override("font_size", 16)
	page.add_child(today)

	var ybox := VBoxContainer.new()
	ybox.name = "YesterdayBox"
	page.add_child(ybox)

	_pages["analytics"] = page


func _build_shop_page() -> void:
	var page := VBoxContainer.new()
	page.name = "ShopPage"

	var cat_row := HBoxContainer.new()
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for cat in ["ingredients", "equipment"]:
		var btn := Button.new()
		btn.name = "Cat_" + cat
		btn.text = cat.capitalize()
		btn.toggle_mode = true
		btn.pressed.connect(func(): _show_shop_category(cat))
		cat_row.add_child(btn)
	page.add_child(cat_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.name = "ShopGrid"
	grid.columns = 3
	for sep in ["h_separation", "v_separation"]:
		grid.add_theme_constant_override(sep, 10)
	scroll.add_child(grid)
	page.add_child(scroll)

	for item in SHOP_ITEMS:
		grid.add_child(_create_ingredient_card(item))
	for item in CONTAINER_ITEMS:
		var card := _create_equipment_card(item)
		card.name = "Equip_" + item["id"]
		card.visible = false
		grid.add_child(card)

	_pages["shop"] = page
	_show_shop_category("ingredients")


func _create_ingredient_card(item: Dictionary) -> PanelContainer:
	var id: String = item["id"]
	var card := PanelContainer.new()
	card.name = "Card_" + id
	card.custom_minimum_size = Vector2(140, 160)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.15, 0.12, 0.08)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(inner)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(60, 60)
	icon.color = _color_for_item(id)
	inner.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = item["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%.0f for %d" % [item["cost"], item["qty"]]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.modulate = Color(0.8, 0.9, 0.6)
	inner.add_child(cost_lbl)

	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var minus := Button.new()
	minus.text = "-"
	minus.pressed.connect(func(): _change_qty(id, -1))
	qty_row.add_child(minus)
	var qty_lbl := Label.new()
	qty_lbl.name = "Qty_" + id
	qty_lbl.text = "0"
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.custom_minimum_size = Vector2(30, 0)
	qty_row.add_child(qty_lbl)
	var plus := Button.new()
	plus.text = "+"
	plus.pressed.connect(func(): _change_qty(id, 1))
	qty_row.add_child(plus)
	inner.add_child(qty_row)

	var buy_btn := Button.new()
	buy_btn.name = "Buy_" + id
	buy_btn.text = "Buy"
	buy_btn.pressed.connect(func(): _buy_ingredient(id))
	inner.add_child(buy_btn)
	return card


func _create_equipment_card(item: Dictionary) -> PanelContainer:
	var id: String = item["id"]
	var card := PanelContainer.new()
	card.name = "EquipCard_" + id
	card.custom_minimum_size = Vector2(140, 160)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.12, 0.15)
	st.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", st)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(inner)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(60, 60)
	icon.color = Color(0.5, 0.5, 0.6)
	inner.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = item["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%.0f" % item["cost"]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.modulate = Color(0.8, 0.9, 0.6)
	inner.add_child(cost_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.pressed.connect(func(): _buy_container(id, item["cost"]))
	inner.add_child(buy_btn)
	return card


func _color_for_item(id: String) -> Color:
	match id:
		"lemon":
			return Color(1.0, 0.9, 0.2)
		"strawberry":
			return Color(1.0, 0.3, 0.3)
		"blueberry":
			return Color(0.3, 0.4, 0.9)
		"peach":
			return Color(1.0, 0.7, 0.5)
		"watermelon":
			return Color(0.3, 0.8, 0.3)
		"sugar":
			return Color(1.0, 1.0, 1.0)
		"ice":
			return Color(0.7, 0.9, 1.0)
		"cups":
			return Color(0.9, 0.8, 0.7)
		_:
			return Color(0.5, 0.5, 0.5)


func _build_upgrades_page() -> void:
	var page := VBoxContainer.new()
	page.name = "UpgradesPage"

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.name = "UpgradeList"
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	page.add_child(scroll)

	for cat in UpgradeManager.get_categories():
		var cat_lbl := Label.new()
		cat_lbl.text = "  " + cat.capitalize()
		cat_lbl.add_theme_font_size_override("font_size", 16)
		list.add_child(cat_lbl)
		for id in UpgradeManager.get_upgrades_in_category(cat):
			var data := UpgradeManager.get_upgrade_data(id)
			list.add_child(_create_upgrade_row(id, data))

	_pages["upgrades"] = page


func _create_upgrade_row(id: String, data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = "%s  (Lv %d/%d)" % [
		data.get("name", "???"),
		data.get("level", 0),
		data.get("max_level", 1),
	]
	info.add_child(name_lbl)

	var desc := Label.new()
	desc.text = data.get("description", "")
	desc.modulate = Color(0.8, 0.8, 0.8)
	info.add_child(desc)
	row.add_child(info)

	var btn := Button.new()
	btn.name = "UpgBtn_" + id
	var maxed: bool = data.get("maxed", false)
	if maxed:
		btn.text = "Maxed"
		btn.disabled = true
	else:
		btn.text = "$%.0f" % data.get("cost", 0.0)
		btn.disabled = not UpgradeManager.can_afford(id)
		btn.pressed.connect(func(): _buy_upgrade(id, btn))
	row.add_child(btn)
	return row


func _show_tab(tab_name: String) -> void:
	_active_tab = tab_name
	for child in _tab_bar.get_children():
		if child is Button:
			child.button_pressed = (child.name == "Tab_" + tab_name)
	_detach_current_page()
	var page: Control = _pages.get(tab_name)
	if page:
		_content.add_child(page)
		page.modulate = Color(1, 1, 1, 0)
		var tween := create_tween()
		tween.tween_property(page, "modulate", Color(1, 1, 1, 1), 0.2)
	if tab_name == "analytics":
		_refresh_analytics()
	elif tab_name == "upgrades":
		_refresh_upgrades()


func _show_shop_category(cat: String) -> void:
	var page: VBoxContainer = _pages.get("shop")
	if page == null:
		return
	var grid := page.get_node("ShopGrid") as GridContainer
	if grid == null:
		return
	for child in grid.get_children():
		if child.name.begins_with("Card_"):
			child.visible = (cat == "ingredients")
		elif child.name.begins_with("EquipCard_"):
			child.visible = (cat == "equipment")
	var cat_row := page.get_child(0) as HBoxContainer
	if cat_row:
		for btn in cat_row.get_children():
			if btn is Button:
				btn.button_pressed = (btn.name == "Cat_" + cat)


func _refresh_analytics() -> void:
	var page := _pages["analytics"] as VBoxContainer
	if page == null:
		return
	var today := page.get_node("TodayLabel") as Label
	if today:
		today.text = "Day %d  |  $%.2f  |  %.0f%% pop  |  %.0fC" % [
			DayManager.day_number,
			GameState.money,
			GameState.popularity * 100.0,
			GameState.temperature,
		]
	var ybox := page.get_node("YesterdayBox") as VBoxContainer
	while ybox.get_child_count() > 0:
		var c := ybox.get_child(0)
		ybox.remove_child(c)
		c.queue_free()
	if DayManager.day_number > 1:
		var h := Label.new()
		h.text = "Yesterday (Day %d)" % (DayManager.day_number - 1)
		h.add_theme_font_size_override("font_size", 14)
		ybox.add_child(h)
		var rev := Label.new()
		rev.text = "Revenue: $%.2f" % DayManager.day_revenue
		ybox.add_child(rev)
		var s := Label.new()
		s.text = "Served: %d  |  Happy: %d" % [DayManager.day_serves, DayManager.day_happy_serves]
		ybox.add_child(s)


func _refresh_upgrades() -> void:
	var page := _pages["upgrades"] as VBoxContainer
	if page == null:
		return
	var list := page.find_child("UpgradeList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		if child is HBoxContainer:
			var btn := child.get_child(child.get_child_count() - 1) as Button
			if btn and btn.name.begins_with("UpgBtn_"):
				var id := btn.name.substr(7)
				var data := UpgradeManager.get_upgrade_data(id)
				var maxed: bool = data.get("maxed", false)
				if maxed:
					btn.text = "Maxed"
					btn.disabled = true
				else:
					btn.text = "$%.0f" % data.get("cost", 0.0)
					btn.disabled = not UpgradeManager.can_afford(id)


func _change_qty(id: String, delta: int) -> void:
	var new_val := clampi(_shop_qty.get(id, 0) + delta, 0, 10)
	_shop_qty[id] = new_val
	var page := _pages["shop"] as VBoxContainer
	if page:
		var qty_lbl := page.get_node("ShopGrid/Card_" + id + "/Inner/Qty_" + id) as Label
		if qty_lbl:
			qty_lbl.text = str(new_val)
		var buy_btn := page.get_node("ShopGrid/Card_" + id + "/Inner/Buy_" + id) as Button
		if buy_btn:
			for item in SHOP_ITEMS:
				if item["id"] == id:
					buy_btn.disabled = new_val <= 0 or GameState.money < (new_val * item["cost"])
					break


func _buy_ingredient(id: String) -> void:
	var qty: int = _shop_qty.get(id, 0)
	if qty <= 0:
		return
	for item in SHOP_ITEMS:
		if item["id"] == id:
			var total: float = qty * item["cost"]
			if not GameState.spend_money(total):
				return
			for i in range(qty):
				EventBus.supply_order_placed.emit(id, item["qty"], item["cost"])
			_status_lbl.text = "Bought %d %s crate(s)!" % [qty, item["name"]]
			_animate_status()
			_shop_qty[id] = 0
			_change_qty(id, 0)
			return


func _buy_container(container_type: String, cost: float) -> void:
	if not GameState.spend_money(cost):
		_status_lbl.text = "Not enough money!"
		_animate_status()
		return
	EventBus.interaction_hint_changed.emit("Equipment delivered!")
	var container_scenes := {
		"lemon_bin": preload("res://scenes/objects/lemon_bin.tscn"),
		"sugar_bin": preload("res://scenes/objects/sugar_bin.tscn"),
		"ice_bin": preload("res://scenes/objects/ice_bin.tscn"),
		"cup_stack": preload("res://scenes/objects/cup_stack.tscn"),
		"pitcher": preload("res://scenes/objects/pitcher.tscn"),
		"press": preload("res://scenes/objects/press.tscn"),
	}
	var placement_scales := {
		"lemon_bin": Vector3.ONE * 0.06,
		"sugar_bin": Vector3.ONE * 0.04,
		"ice_bin": Vector3.ONE * 0.03,
		"cup_stack": Vector3.ONE * 0.05,
		"pitcher": Vector3.ONE * 0.15,
		"press": Vector3.ONE * 0.10,
	}
	var scene: PackedScene = container_scenes.get(container_type)
	if scene == null:
		return
	var instance := scene.instantiate()
	instance.scale = placement_scales.get(container_type, Vector3.ONE)
	if "starting_amount" in instance:
		instance.starting_amount = 0.0
	if "starting_count" in instance:
		instance.starting_count = 0
	get_tree().current_scene.add_child(instance)
	instance.add_to_group("container")
	var delivery: Node = get_tree().current_scene.find_child("DeliverySystem", true, false)
	var drop_pos := Vector3(5.0, 0.5, 5.0)
	if delivery and "delivery_zone" in delivery:
		drop_pos = delivery.delivery_zone
	var drop_start := drop_pos + Vector3(0, Balancing.DELIVERY_DROP_HEIGHT, 0)
	instance.global_position = drop_start
	var tween := instance.create_tween()
	tween.tween_property(instance, "global_position", drop_pos, 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	EventBus.container_placed.emit(container_type, instance)
	_status_lbl.text = "%s delivered!" % container_type.capitalize().replace("_", " ")
	_animate_status()


func _buy_upgrade(id: String, _btn: Button) -> void:
	if UpgradeManager.purchase(id):
		_status_lbl.text = "Upgrade purchased!"
		_animate_status()
		_refresh_upgrades()
	else:
		_status_lbl.text = "Not enough money!"
		_animate_status()


func _animate_status() -> void:
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _on_price_changed(value: float) -> void:
	var price_val := vbox.get_node("PriceValue") as Label
	if price_val:
		price_val.text = "$%.2f" % value
	EventBus.price_changed.emit(value)


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		var day_lbl := vbox.get_node("Header/DayLabel") as Label
		if day_lbl:
			day_lbl.text = "Day %d" % day
		var temp_lbl := vbox.get_node("Header/TempLabel") as Label
		if temp_lbl:
			temp_lbl.text = "%.0fC" % GameState.temperature
		var money_lbl := vbox.get_node("Header/MoneyLabel") as Label
		if money_lbl:
			money_lbl.text = "Money: $%.2f" % GameState.money
		var price_slider := vbox.get_node("PriceRow/PriceSlider") as HSlider
		if price_slider:
			price_slider.value = GameState.current_price
		_show_tab("analytics")
		panel.visible = true
		backdrop.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var tween := create_tween()
		panel.modulate = Color(1, 1, 1, 0)
		backdrop.modulate = Color(1, 1, 1, 0)
		tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 0.2)
		tween.parallel().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.3)
	else:
		panel.visible = false
		backdrop.visible = false


func _on_money_changed(_amount: float) -> void:
	if not panel.visible:
		return
	var money_lbl := vbox.get_node("MoneyLabel") as Label
	if money_lbl:
		money_lbl.text = "Money: $%.2f" % GameState.money
	if _active_tab == "shop":
		for item in SHOP_ITEMS:
			var qty: int = _shop_qty.get(item["id"], 0)
			var shop_page := _pages["shop"] as VBoxContainer
			var path := "ShopGrid/Card_%s/Inner/Buy_%s" % [item["id"], item["id"]]
			var buy_btn := shop_page.get_node(path) as Button
			if buy_btn:
				buy_btn.disabled = qty <= 0 or GameState.money < (qty * item["cost"])
	elif _active_tab == "upgrades":
		_refresh_upgrades()


func _on_start_day() -> void:
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.parallel().tween_property(backdrop, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(
		func():
			panel.visible = false
			backdrop.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			DayManager.start_day()
	)
