extends CanvasLayer
## Morning shop UI: buy ingredients, set price, then start the day.

@onready var panel: PanelContainer = $Panel
@onready var money_label: Label = $Panel/VBox/Header/MoneyLabel
@onready var day_label: Label = $Panel/VBox/Header/DayLabel
@onready var temp_label: Label = $Panel/VBox/Header/TempLabel
@onready var price_slider: HSlider = $Panel/VBox/PriceRow/PriceSlider
@onready var price_value: Label = $Panel/VBox/PriceRow/PriceValue
@onready var grid: GridContainer = $Panel/VBox/Scroll/Grid
@onready var start_btn: Button = $Panel/VBox/StartBtn
@onready var status_label: Label = $Panel/VBox/StatusLabel

var _quantities: Dictionary = { }
var _items: Array[Dictionary] = []

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


func _ready() -> void:
	panel.visible = false
	price_slider.min_value = Balancing.PRICE_MIN
	price_slider.max_value = Balancing.PRICE_MAX
	price_slider.step = 0.05
	price_slider.value = GameState.current_price
	price_value.text = "$%.2f" % GameState.current_price
	price_slider.value_changed.connect(_on_price_changed)
	start_btn.pressed.connect(_on_start_day)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	_build_grid()


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		day_label.text = "Day %d" % day
		var temp := GameState.temperature
		temp_label.text = "Weather: %.0f°C" % temp
		_update_money_label()
		_reset_quantities()
		panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		panel.visible = false


func _on_money_changed(_amount: float) -> void:
	if panel.visible:
		_update_money_label()
		_update_buttons()


func _update_money_label() -> void:
	money_label.text = "Money: $%.2f" % GameState.money


func _on_price_changed(value: float) -> void:
	price_value.text = "$%.2f" % value
	EventBus.price_changed.emit(value)


func _build_grid() -> void:
	_items = SHOP_ITEMS.duplicate(true)
	for item in _items:
		var id: String = item["id"]
		_quantities[id] = 0

		# Name label
		var name_lbl := Label.new()
		name_lbl.text = item["name"]
		grid.add_child(name_lbl)

		# Cost label
		var cost_lbl := Label.new()
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
		spin.value_changed.connect(func(v: float): _on_qty_changed(id, v))
		spin.name = "Spin_" + id
		grid.add_child(spin)

		# Buy button
		var btn := Button.new()
		btn.text = "Buy"
		btn.name = "Btn_" + id
		btn.pressed.connect(func(): _buy_item(id))
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
		var qty: int = _quantities.get(id, 0)
		var total: float = qty * item["cost"]
		var btn := grid.get_node_or_null("Btn_" + id) as Button
		if btn:
			btn.disabled = qty <= 0 or GameState.money < total


func _buy_item(id: String) -> void:
	var qty: int = _quantities.get(id, 0)
	if qty <= 0:
		return
	for item in _items:
		if item["id"] == id:
			var total: float = qty * item["cost"]
			if not GameState.spend_money(total):
				return
			# Deliver supply boxes
			var amount_per_box: float = item["qty"]
			for i in range(qty):
				EventBus.supply_order_placed.emit(id, amount_per_box, item["cost"])
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
