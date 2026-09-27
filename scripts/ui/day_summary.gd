extends CanvasLayer
## Day-end flow + mailbox report.
##
## When the day ends (EVENING phase) the screen fades to black, the host
## advances the day cycle, and a "Day X" card sits on black for a beat
## before fading back in on the new day. The stats panel is no longer an
## evening screen — it is the mailbox report, opened via show_report()
## when the player clicks their mailbox.

const TITLE_FONT: Font = preload("res://assets/fonts/AmaticSC-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/Grandstander-clean.ttf")

@onready var panel: PanelContainer = $Panel
@onready var backdrop: ColorRect = $Backdrop
@onready var day_label: Label = $Panel/VBox/DayLabel
@onready var stats_vbox: VBoxContainer = $Panel/VBox/Stats
@onready var next_btn: Button = $Panel/VBox/NextBtn

var _transitioning: bool = false
var _day_card_shown: bool = false
var _transition_day: int = 0
var _day_card: Label = null


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	add_to_group("day_summary")
	next_btn.text = "Close"
	next_btn.pressed.connect(_on_close)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_make_day_card()


func _make_day_card() -> void:
	_day_card = Label.new()
	_day_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_card.add_theme_font_override("font", TITLE_FONT)
	_day_card.add_theme_font_size_override("font_size", 160)
	_day_card.add_theme_color_override("font_color", Color(1.0, 0.98, 0.88))
	_day_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_card.modulate = Color(1, 1, 1, 0)
	_day_card.visible = false
	add_child(_day_card)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		_start_evening_transition()
	elif _transitioning:
		# First non-EVENING phase after the fade = the new day arrived.
		# A menu return emits MORNING without advancing the day — treat
		# that as an abort instead of showing the Day X card.
		if _day_card_shown:
			return
		if DayManager.day_number > _transition_day:
			_show_day_card()
		else:
			_end_transition()
	else:
		panel.visible = false
		backdrop.visible = false


func _start_evening_transition() -> void:
	_transitioning = true
	_day_card_shown = false
	_transition_day = DayManager.day_number
	panel.visible = false
	_day_card.visible = false
	_day_card.modulate = Color(1, 1, 1, 0)
	backdrop.visible = true
	backdrop.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 0.8)
	tween.tween_callback(_advance_to_next_day)


func _advance_to_next_day() -> void:
	# Quitting to menu mid-fade sets MORNING — don't advance the day.
	if DayManager.current_phase != DayManager.Phase.EVENING:
		return
	# Host moves the cycle forward; clients follow via the phase sync RPC.
	if multiplayer.is_server():
		DayManager.end_evening()
		DayManager.start_day()


func _show_day_card() -> void:
	_day_card_shown = true
	_day_card.text = "Day %d" % DayManager.day_number
	_day_card.visible = true
	var tween := create_tween()
	tween.tween_property(_day_card, "modulate", Color(1, 1, 1, 1), 0.4)
	tween.tween_interval(1.6)
	tween.tween_property(_day_card, "modulate", Color(1, 1, 1, 0), 0.6)
	tween.parallel().tween_property(backdrop, "modulate", Color(1, 1, 1, 0), 0.6)
	tween.tween_callback(_end_transition)


func _end_transition() -> void:
	_day_card.visible = false
	backdrop.visible = false
	_transitioning = false
	_day_card_shown = false

## --- Mailbox report ---


## Opens the previous-day stats panel. Called by the mailbox interactable.
func show_report() -> void:
	if _transitioning:
		return
	_populate_report()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false)
	backdrop.visible = true
	backdrop.modulate = Color(1, 1, 1, 0.75)
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.25)


func _on_close() -> void:
	panel.visible = false
	if not _transitioning:
		backdrop.visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _populate_report() -> void:
	for child in stats_vbox.get_children():
		child.queue_free()
	var entries: Array[Dictionary] = []
	for stand in get_tree().get_nodes_in_group("stand"):
		if stand.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var stats: Dictionary = stand.get("last_day_stats")
		if stats is Dictionary and not stats.is_empty():
			entries.append({ "stand": stand, "stats": stats })
	if entries.is_empty():
		day_label.text = "Mailbox"
		var empty_label := _make_label("No mail today.", 22)
		stats_vbox.add_child(empty_label)
		return
	# Local player's stand first so the left column is always "you".
	var local := WorldSync.get_local_stand()
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a["stand"] == local and b["stand"] != local,
	)
	day_label.text = "Day %d Report" % int(entries[0]["stats"].get("day", DayManager.day_number))
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 40)
	for entry in entries:
		var is_local: bool = entry["stand"] == local and entries.size() > 1
		columns.add_child(_build_stand_column(entry["stats"], is_local))
	stats_vbox.add_child(columns)


func _build_stand_column(stats: Dictionary, is_local: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	var title := str(stats.get("stand_name", "Stand"))
	if is_local:
		title += " (You)"
	var title_label := _make_label(title, 24)
	title_label.add_theme_font_override("font", TITLE_FONT)
	col.add_child(title_label)
	var lines: Array[String] = [
		"Revenue: $%.2f" % float(stats.get("revenue", 0.0)),
		"Came to buy: %d" % int(stats.get("customers_arrived", 0)),
		"Bought: %d" % int(stats.get("customers_bought", 0)),
		"Costs: $%.2f" % float(stats.get("costs", 0.0)),
	]
	for line in lines:
		col.add_child(_make_label(line, 18))
	var profit := float(stats.get("profit", 0.0))
	var profit_label := _make_label("Profit: $%.2f" % profit, 20)
	profit_label.add_theme_color_override(
		"font_color",
		Color(0.4, 0.85, 0.4) if profit >= 0.0 else Color(0.9, 0.3, 0.3),
	)
	col.add_child(profit_label)
	var pop := int(stats.get("popularity", 0))
	var delta := int(stats.get("popularity_delta", 0))
	var pop_text := "Popularity: %d" % pop
	if delta != 0:
		pop_text += " (%+d)" % delta
	var pop_label := _make_label(pop_text, 18)
	pop_label.add_theme_color_override(
		"font_color",
		Color(0.85, 0.5, 0.95) if delta >= 0 else Color(0.9, 0.3, 0.3),
	)
	col.add_child(pop_label)
	return col


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", size)
	return label
