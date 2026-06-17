extends CanvasLayer
## Always-visible HUD: money, hint bar, popularity.

@onready var money_label: Label = $VBox/MoneyLabel
@onready var hint_label: Label = $HintLabel
@onready var popularity_label: Label = $VBox/PopLabel
@onready var time_label: Label = $TimeLabel


func _ready() -> void:
	EventBus.money_changed.connect(_on_money)
	EventBus.interaction_hint_changed.connect(_on_hint)
	EventBus.popularity_changed.connect(_on_popularity)
	EventBus.day_timer_updated.connect(_on_day_timer_updated)
	_on_money(GameState.money)
	_on_popularity(GameState.popularity)


func _on_money(value: float) -> void:
	money_label.text = "$%.2f" % value


func _on_hint(hint: String) -> void:
	hint_label.text = hint


func _on_popularity(value: float) -> void:
	popularity_label.text = "Pop: %d%%" % int(value * 100)


func _on_day_timer_updated(time_left: float, total_time: float) -> void:
	if total_time <= 0.0:
		return
	var t := clampf(1.0 - (time_left / total_time), 0.0, 1.0)
	# Map 0→1 to 6:00 → 18:00 (12-hour workday)
	var total_minutes: float = 6.0 * 60.0 + t * 12.0 * 60.0
	var hour: int = int(total_minutes / 60.0)
	var minute: int = int(total_minutes) % 60
	var ampm := "AM" if hour < 12 else "PM"
	var display_hour: int = hour if hour <= 12 else hour - 12
	if display_hour == 0:
		display_hour = 12
	time_label.text = "%d:%02d %s" % [display_hour, minute, ampm]
