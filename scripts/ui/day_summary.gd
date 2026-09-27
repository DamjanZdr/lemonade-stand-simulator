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
@onready var day_label: Label = $Panel/Margin/VBox/Header/DayLabel
@onready var sub_label: Label = $Panel/Margin/VBox/SubLabel
@onready var stats_hbox: HBoxContainer = $Panel/Margin/VBox/Stats
@onready var close_btn: Button = $Panel/Margin/VBox/Header/CloseBtn

var _transitioning: bool = false
var _day_card_shown: bool = false
var _transition_day: int = 0
var _day_card: Label = null


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	add_to_group("day_summary")
	day_label.add_theme_font_override("font", TITLE_FONT)
	day_label.add_theme_font_size_override("font_size", 44)
	sub_label.add_theme_font_override("font", BODY_FONT)
	sub_label.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_font_override("font", BODY_FONT)
	close_btn.pressed.connect(_on_close)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_make_day_card()


func _exit_tree() -> void:
	# Static flag lives on the EventBus autoload — make sure it never
	# leaks across scene reloads (e.g. quitting to menu mid-transition).
	EventBus.day_transition_active = false


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
	EventBus.day_transition_active = true
	_clear_local_hover()
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
	EventBus.day_transition_active = false


## Drops the local player's world hover immediately so no outline shows
## through the report/black screen before the next poll clears it.
func _clear_local_hover() -> void:
	var player := WorldSync.get_local_player()
	if player == null:
		return
	var interaction: Node = player.get("interaction")
	if interaction != null and interaction.has_method("clear_hover"):
		interaction.clear_hover()

## --- Mailbox report ---


## Opens the previous-day stats panel. Called by the mailbox interactable.
func show_report() -> void:
	if _transitioning:
		return
	_clear_local_hover()
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


## True while the mailbox report panel is open (main.gd checks this so
## ESC closes the report instead of toggling the pause menu).
func is_report_open() -> bool:
	return panel.visible and not _transitioning


func close_report() -> void:
	_on_close()


func _on_close() -> void:
	panel.visible = false
	if not _transitioning:
		backdrop.visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _populate_report() -> void:
	for child in stats_hbox.get_children():
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
		sub_label.text = ""
		stats_hbox.add_child(_make_label("No mail today.", 22))
		return
	# Local player's stand first so the left column is always "you".
	var local := WorldSync.get_local_stand()
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a["stand"] == local and b["stand"] != local,
	)
	var first_stats: Dictionary = entries[0]["stats"]
	day_label.text = "Day %d Report" % int(first_stats.get("day", DayManager.day_number))
	sub_label.text = ""
	for i in entries.size():
		if i > 0:
			var vsep := VSeparator.new()
			stats_hbox.add_child(vsep)
		var is_local: bool = entries[i]["stand"] == local and entries.size() > 1
		stats_hbox.add_child(_build_stand_column(entries[i]["stats"], is_local))


func _build_stand_column(stats: Dictionary, is_local: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(280, 0)
	col.add_theme_constant_override("separation", 5)
	var title := str(stats.get("stand_name", "Stand"))
	if is_local:
		title += " (You)"
	var title_label := _make_label(title, 34)
	title_label.add_theme_font_override("font", TITLE_FONT)
	col.add_child(title_label)
	col.add_child(HSeparator.new())

	var soft_red := Color(0.9, 0.55, 0.55)
	var dim := Color(0.55, 0.55, 0.55)

	# --- People ---
	col.add_child(_make_section("People"))
	col.add_child(_make_row("Total Pedestrians", str(int(stats.get("pedestrians", 0)))))
	col.add_child(_make_row("Customers", str(int(stats.get("customers_arrived", 0)))))
	var happy := int(stats.get("happy", 0))
	col.add_child(_make_row("Happy", str(happy), Color(0.4, 0.85, 0.4) if happy > 0 else dim, true))
	col.add_child(
		_make_row("Fruit complaints", str(int(stats.get("complaints_fruit", 0))), soft_red, true)
	)
	col.add_child(
		_make_row("Sugar complaints", str(int(stats.get("complaints_sugar", 0))), soft_red, true)
	)
	col.add_child(
		_make_row("Ice complaints", str(int(stats.get("complaints_ice", 0))), soft_red, true)
	)
	col.add_child(_make_row("Patience ran out", str(int(stats.get("timeouts", 0))), soft_red, true))
	col.add_child(
		_make_row("Too expensive", str(int(stats.get("too_expensive", 0))), soft_red, true)
	)
	col.add_child(_make_row("Wrong order", str(int(stats.get("wrong_order", 0))), soft_red, true))
	col.add_child(_make_row("Scammed", str(int(stats.get("scams", 0))), soft_red, true))
	var delta := int(stats.get("popularity_delta", 0))
	var pop_text := "%+d" % delta if delta != 0 else "0"
	var pop_color := (
		Color(0.85, 0.5, 0.95)
		if delta > 0
		else Color(0.9, 0.3, 0.3)
		if delta < 0
		else dim
	)
	col.add_child(_make_row("Popularity", pop_text, pop_color))

	# --- Money ---
	col.add_child(_make_gap(8))
	col.add_child(_make_section("Money"))
	var sales := float(stats.get("sales", stats.get("revenue", 0.0)))
	var recycling := float(stats.get("recycling", 0.0))
	var trash := float(stats.get("trash", 0.0))
	var income := float(stats.get("income", sales + recycling + trash))
	var costs := float(stats.get("costs", 0.0))
	var profit := float(stats.get("profit", income - costs))
	col.add_child(_make_row("Income", "$%.2f" % income, Color(0.4, 0.85, 0.4)))
	col.add_child(_make_row("Sales", "$%.2f" % sales, dim, true))
	col.add_child(_make_row("Recycling", "$%.2f" % recycling, dim, true))
	col.add_child(_make_row("Trash", "$%.2f" % trash, dim, true))
	col.add_child(_make_row("Costs", "-$%.2f" % costs, Color(0.9, 0.45, 0.45)))
	col.add_child(HSeparator.new())
	col.add_child(
		_make_row(
			"Profit",
			"%s$%.2f" % ["+" if profit >= 0.0 else "-", absf(profit)],
			Color(0.4, 0.85, 0.4) if profit >= 0.0 else Color(0.9, 0.3, 0.3),
			false,
			24,
		)
	)
	return col


func _make_section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	return label


## One "label ..... value" stat row; `indent` for Income sub-rows.
func _make_row(
	label_text: String,
	value: String,
	value_color: Color = Color(1, 1, 1),
	indent: bool = false,
	size: int = 18,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = ("     " if indent else "") + label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", BODY_FONT)
	name_label.add_theme_font_size_override("font_size", size)
	if indent:
		name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", BODY_FONT)
	value_label.add_theme_font_size_override("font_size", size)
	value_label.add_theme_color_override("font_color", value_color)
	row.add_child(value_label)
	return row


func _make_gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", size)
	return label
