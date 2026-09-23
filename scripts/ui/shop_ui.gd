extends CanvasLayer
## Morning shop UI: buy ingredients, then start the day.

@onready var panel: PanelContainer = $Panel
@onready var money_label: Label = $Panel/VBox/Header/MoneyLabel
@onready var day_label: Label = $Panel/VBox/Header/DayLabel
@onready var temp_label: Label = $Panel/VBox/Header/TempLabel
@onready var grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var start_btn: Button = $Panel/VBox/StartBtn
@onready var status_label: Label = $Panel/VBox/StatusLabel

var _quantities: Dictionary = { }
var _items: Array[Dictionary] = []

static var shop_items: Array[Dictionary] = [
	{ "id": "lemon", "name": "Lemons", "cost": Balancing.SUPPLY_COST_LEMON, "qty": 10 },
	{
		"id": "strawberry",
		"name": "Strawberry",
		"cost": Balancing.SUPPLY_COST_STRAWBERRY,
		"qty": 10,
	},
	{ "id": "blueberry", "name": "Blueberry", "cost": Balancing.SUPPLY_COST_BLUEBERRY, "qty": 10 },
	{ "id": "peach", "name": "Peach", "cost": Balancing.SUPPLY_COST_PEACH, "qty": 10 },
	{
		"id": "watermelon",
		"name": "Watermelon",
		"cost": Balancing.SUPPLY_COST_WATERMELON,
		"qty": 10,
	},
	{ "id": "sugar", "name": "Sugar", "cost": Balancing.SUPPLY_COST_SUGAR, "qty": 10 },
	{ "id": "ice", "name": "Ice", "cost": Balancing.SUPPLY_COST_ICE, "qty": 10 },
	{ "id": "cups", "name": "Cups", "cost": Balancing.SUPPLY_COST_CUPS, "qty": 10 },
]


func _ready() -> void:
	panel.visible = false
	start_btn.pressed.connect(_on_start_day)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	_build_grid()


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		day_label.text = "Day %d" % day
		var temp := GameState.temperature
		temp_label.text = "Weather: %.0f°C" % temp
		_bind_stand_money()
		_update_money_label()
		_reset_quantities()
		panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("set_hud_visible"):
			hud.set_hud_visible(false)
	else:
		panel.visible = false
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("set_hud_visible"):
			hud.set_hud_visible(true)


func set_auto_show(enabled: bool) -> void:
	if enabled:
		if not EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
			EventBus.day_phase_changed.connect(_on_day_phase_changed)
	else:
		if EventBus.day_phase_changed.is_connected(_on_day_phase_changed):
			EventBus.day_phase_changed.disconnect(_on_day_phase_changed)


## Live money updates come from the local stand's own money_changed signal —
## StandUnit mutations emit that per-stand signal, and on clients _apply_state()
## is the only place stand money changes (EventBus.money_changed only fires for
## the primary stand's GameState bridge).
var _bound_stand: Node = null


func _bind_stand_money() -> void:
	var stand := WorldSync.get_local_stand()
	if stand == _bound_stand:
		return
	if (
		_bound_stand != null and is_instance_valid(_bound_stand)
		and _bound_stand.has_signal("money_changed")
		and _bound_stand.money_changed.is_connected(_on_money_changed)
	):
		_bound_stand.money_changed.disconnect(_on_money_changed)
	_bound_stand = stand
	if _bound_stand != null and _bound_stand.has_signal("money_changed"):
		_bound_stand.money_changed.connect(_on_money_changed)


func _on_money_changed(_amount: float) -> void:
	_bind_stand_money()
	if panel.visible:
		_update_money_label()
		_update_buttons()


func _update_money_label() -> void:
	money_label.text = "Money: $%.2f" % _get_local_money()


## Get the local player's stand money, falling back to GameState.money.
func _get_local_money() -> float:
	var stand := WorldSync.get_local_stand()
	if stand != null and is_instance_valid(stand) and "money" in stand:
		return stand.money
	return GameState.money


func _build_grid() -> void:
	_items = shop_items.duplicate(true)
	for item in _items:
		var id: String = item["id"]
		_quantities[id] = 0
		var is_locked_fruit := (
			id in GameState.FRUIT_TYPES and not UpgradeManager.is_fruit_unlocked(id)
		)

		# Name label
		var name_lbl := Label.new()
		if is_locked_fruit:
			name_lbl.text = "\U0001F512 " + item["name"]
			name_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		else:
			name_lbl.text = item["name"]
		grid.add_child(name_lbl)

		# Cost label
		var cost_lbl := Label.new()
		if is_locked_fruit:
			cost_lbl.text = "Locked"
			cost_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		else:
			cost_lbl.text = "$%.0f / %d" % [item["cost"], item["qty"]]
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(cost_lbl)

		# Quantity spinbox
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 10
		spin.step = 1
		spin.value = 0
		spin.custom_minimum_size = Vector2(80, 0)
		spin.editable = not is_locked_fruit
		spin.value_changed.connect(
			func(v: float):
				_on_qty_changed(id, v),
		)
		spin.name = "Spin_" + id
		grid.add_child(spin)

		# Buy button
		var btn := Button.new()
		btn.text = "Buy"
		btn.name = "Btn_" + id
		btn.disabled = is_locked_fruit
		btn.pressed.connect(
			func():
				_buy_item(id),
		)
		grid.add_child(btn)


func _reset_quantities() -> void:
	for id in _quantities:
		_quantities[id] = 0
	for child in grid.get_children():
		if child is SpinBox:
			child.value = 0
	if status_label:
		status_label.text = ""
	_update_buttons()


func _on_qty_changed(id: String, value: float) -> void:
	_quantities[id] = int(value)
	_update_buttons()


func _update_buttons() -> void:
	for item in _items:
		var id: String = item["id"]
		var is_locked_fruit := (
			id in GameState.FRUIT_TYPES and not UpgradeManager.is_fruit_unlocked(id)
		)
		var qty: int = _quantities.get(id, 0)
		var total: float = qty * item["cost"]
		var btn := grid.get_node_or_null("Btn_" + id) as Button
		if btn:
			btn.disabled = is_locked_fruit or qty <= 0 or _get_local_money() < total


func update_buttons() -> void:
	_update_buttons()


func _buy_item(id: String) -> void:
	var qty: int = _quantities.get(id, 0)
	if qty <= 0:
		return
	for item in _items:
		if item["id"] == id:
			var total: float = qty * item["cost"]
			if not WorldSync.spend_local_money(total):
				return
			# Deliver supply boxes
			var amount_per_box: float = item["qty"]
			var sn := WorldSync.get_local_stand_name()
			for i in range(qty):
				EventBus.supply_order_placed.emit(id, amount_per_box, item["cost"], sn)
			# Trigger the delivery truck to bring the boxes
			EventBus.checkout_completed.emit(sn)
			# Show confirmation
			if status_label:
				status_label.text = "Bought %d %s crate(s)!" % [qty, item["name"]]
			# Reset this item's quantity
			_quantities[id] = 0
			var spin := grid.get_node_or_null("Spin_" + id) as SpinBox
			if spin:
				spin.value = 0
			_update_buttons()
			return


func _on_start_day() -> void:
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DayManager.start_day()
