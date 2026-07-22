extends CanvasLayer
## Evening transition: fade to black, show day summary, then advance on button press.

@onready var panel: PanelContainer = $Panel
@onready var backdrop: ColorRect = $Backdrop
@onready var day_label: Label = $Panel/VBox/DayLabel
@onready var revenue_label: Label = $Panel/VBox/Stats/RevenueLabel
@onready var pedestrians_label: Label = $Panel/VBox/Stats/PedestriansLabel
@onready var arrived_label: Label = $Panel/VBox/Stats/ArrivedLabel
@onready var bought_label: Label = $Panel/VBox/Stats/BoughtLabel
@onready var costs_label: Label = $Panel/VBox/Stats/CostsLabel
@onready var profit_label: Label = $Panel/VBox/Stats/ProfitLabel
@onready var next_btn: Button = $Panel/VBox/NextBtn

var _advancing: bool = false


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	next_btn.pressed.connect(_on_next_day)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		_fade_to_black()
	else:
		_advancing = false
		panel.visible = false
		backdrop.visible = false


func _fade_to_black() -> void:
	backdrop.visible = true
	backdrop.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 1.0)
	tween.tween_callback(_show_summary)


func _show_summary() -> void:
	day_label.text = "Day %d Complete!" % DayManager.day_number
	revenue_label.text = "Revenue: $%.2f" % DayManager.day_revenue
	pedestrians_label.text = "Pedestrians: %d" % DayManager.day_pedestrians
	arrived_label.text = "Came to buy: %d" % DayManager.day_customers_arrived
	bought_label.text = "Bought: %d" % DayManager.day_customers_bought
	costs_label.text = "Costs: $%.2f" % DayManager.day_costs
	var profit: float = DayManager.day_revenue - DayManager.day_costs
	profit_label.text = "Profit: $%.2f" % profit
	if profit < 0:
		profit_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	else:
		profit_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.3)


func _on_next_day() -> void:
	if _advancing:
		return
	_advancing = true
	DayManager.end_evening()
	DayManager.start_day()
	panel.visible = false
	var tween := create_tween()
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.tween_callback(func(): backdrop.visible = false)
