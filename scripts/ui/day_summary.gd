extends CanvasLayer
## Evening summary: show day's stats, then go to next morning.

@onready var panel: PanelContainer = $Panel
@onready var day_label: Label = $Panel/VBox/DayLabel
@onready var revenue_label: Label = $Panel/VBox/Stats/RevenueLabel
@onready var serves_label: Label = $Panel/VBox/Stats/ServesLabel
@onready var happy_label: Label = $Panel/VBox/Stats/HappyLabel
@onready var popularity_label: Label = $Panel/VBox/Stats/PopularityLabel
@onready var next_btn: Button = $Panel/VBox/NextBtn


func _ready() -> void:
	panel.visible = false
	next_btn.pressed.connect(_on_next_day)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		_show_summary(day)
	else:
		panel.visible = false


func _show_summary(day: int) -> void:
	day_label.text = "Day %d Complete!" % day
	revenue_label.text = "Revenue: $%.2f" % DayManager.day_revenue
	serves_label.text = "Served: %d customers" % DayManager.day_serves
	happy_label.text = "Happy: %d  |  Unhappy: %d" % [
		DayManager.day_happy_serves,
		DayManager.day_serves - DayManager.day_happy_serves,
	]
	popularity_label.text = "Popularity: %.0f%%" % (GameState.popularity * 100.0)
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_next_day() -> void:
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DayManager.end_evening()
