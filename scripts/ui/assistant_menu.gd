class_name AssistantMenu
extends CanvasLayer
## Popup shown when clicking an Assistant NPC. Unpaid assistants get a
## Pay/Cancel prompt; paid ones get role buttons (Server / Brewer /
## Stocker / Cleaner). Brewer opens a 6-slot fruit-queue editor with a
## loop toggle.

const ROLE_LABELS := {
	"server": "Server",
	"brewer": "Brewer",
	"stocker": "Stocker",
	"cleaner": "Cleaner",
}
const QUEUE_SLOTS := 6
const BG := Color(0.10, 0.11, 0.14)
const BORDER := Color(0.20, 0.22, 0.27)

var _assistant: Assistant = null
var _panel: PanelContainer = null
var _queue_edit: Array = [] # working copy of brewer slots
var _loop_edit := true
var _queue_seeded := false
var _mode := "" # "pay" | "roles" | "brewer"


static func open(assistant: Assistant) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or assistant == null:
		return
	var m := AssistantMenu.new()
	m._assistant = assistant
	tree.current_scene.add_child(m)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m._rebuild()


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 40
	if _assistant != null:
		if not _assistant.state_changed.is_connected(_rebuild):
			_assistant.state_changed.connect(_rebuild)
		if _assistant.assigned_stand != null \
				and not _assistant.assigned_stand.money_changed.is_connected(_on_money):
			_assistant.assigned_stand.money_changed.connect(_on_money)


func _on_money(_v: float) -> void:
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_panel = null


func _rebuild() -> void:
	if not is_instance_valid(_assistant):
		queue_free()
		return
	_clear()
	# CenterContainer wrapper keeps the panel truly centered regardless of
	# how tall the contents get.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "Assistant"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	vb.add_child(HSeparator.new())
	if not _assistant.wage_paid:
		_mode = "pay"
		_build_pay_view(vb)
	elif _mode == "" or _mode == "pay":
		_mode = "roles"
		_build_role_view(vb)
	elif _mode == "brewer":
		_build_role_view(vb)
		_build_brewer_editor(vb)
	else:
		_build_role_view(vb)
	vb.add_child(HSeparator.new())
	var close := _make_button("Close")
	close.pressed.connect(queue_free)
	vb.add_child(close)


func _build_pay_view(vb: VBoxContainer) -> void:
	var info := Label.new()
	info.text = "Daily wage: $%.2f — pay to start work." % Assistant.WAGE
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var pay := _make_button("Pay $%.2f" % Assistant.WAGE)
	pay.custom_minimum_size = Vector2(140, 36)
	pay.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	var stand := _assistant.assigned_stand
	pay.disabled = stand == null or stand.money < Assistant.WAGE
	pay.pressed.connect(
		func():
			_assistant.request_pay(),
	)
	row.add_child(pay)
	var cancel := _make_button("Cancel")
	cancel.custom_minimum_size = Vector2(140, 36)
	cancel.pressed.connect(queue_free)
	row.add_child(cancel)


func _build_role_view(vb: VBoxContainer) -> void:
	var status := Label.new()
	status.text = ("Current task: %s" % ROLE_LABELS.get(_assistant.role, "none"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vb.add_child(status)
	for r in Assistant.ROLES:
		var is_current := _assistant.role == r
		var label: String = ROLE_LABELS.get(r, r)
		if is_current:
			label += "  ✓"
		var b := _make_button(label)
		b.custom_minimum_size = Vector2(0, 34)
		if is_current:
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		var role := r
		b.pressed.connect(
			func():
				if role == "brewer":
					_mode = "brewer"
					_queue_seeded = false
					_rebuild()
				else:
					_assistant.request_assign(role),
		)
		vb.add_child(b)


func _build_brewer_editor(vb: VBoxContainer) -> void:
	# Seed the working copy once per editor entry — rebuilds triggered by
	# money/state changes or +/− presses must not wipe in-progress edits.
	if not _queue_seeded:
		_queue_seeded = true
		_queue_edit.clear()
		for i in QUEUE_SLOTS:
			if i < _assistant.brewer_queue.size():
				var e: Dictionary = _assistant.brewer_queue[i]
				_queue_edit.append(
					{ "fruit": str(e.get("fruit", "")), "qty": int(e.get("qty", 1)) }
				)
			else:
				_queue_edit.append({ "fruit": "", "qty": 1 })
		_loop_edit = _assistant.brewer_loop

	var sep := HSeparator.new()
	vb.add_child(sep)
	var hdr := Label.new()
	hdr.text = "Brew queue — click a slot to change its fruit:"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hdr)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for i in QUEUE_SLOTS:
		grid.add_child(_make_slot_cell(i))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var loop := Button.new()
	loop.text = "↻"
	loop.tooltip_text = "Loop queue"
	loop.toggle_mode = true
	loop.button_pressed = _loop_edit
	loop.focus_mode = Control.FOCUS_NONE
	loop.custom_minimum_size = Vector2(52, 52)
	loop.add_theme_font_size_override("font_size", 28)
	if _loop_edit:
		loop.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	loop.toggled.connect(
		func(on: bool):
			_loop_edit = on
			loop.add_theme_color_override(
				"font_color",
				Color(0.45, 0.95, 0.55) if on else Color(1, 1, 1),
			),
	)
	row.add_child(loop)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	vb.add_child(btns)
	var apply := _make_button("Start brewing")
	apply.custom_minimum_size = Vector2(140, 36)
	apply.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	apply.pressed.connect(
		func():
			var queue: Array = []
			for e in _queue_edit:
				if e["fruit"] != "":
					queue.append({ "fruit": e["fruit"], "qty": 1 })
			_assistant.request_assign("brewer", queue, _loop_edit),
	)
	btns.add_child(apply)
	var back := _make_button("Back")
	back.custom_minimum_size = Vector2(100, 36)
	back.pressed.connect(
		func():
			_mode = "roles"
			_rebuild(),
	)
	btns.add_child(back)


func _make_slot_cell(idx: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 96)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_slot_cell(b, idx)
	b.pressed.connect(
		func():
			_cycle_fruit(idx)
			_update_slot_cell(b, idx),
	)
	return b


func _update_slot_cell(b: Button, idx: int) -> void:
	var f: String = _queue_edit[idx]["fruit"]
	if f == "":
		b.icon = null
		b.text = "+"
		b.tooltip_text = "Empty — click to set a fruit"
	else:
		b.text = ""
		b.icon = _fruit_icon(f)
		b.tooltip_text = f.capitalize()


func _fruit_icon(fruit: String) -> Texture2D:
	var p := "res://assets/textures/ui/products/%s.png" % fruit
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null


func _cycle_fruit(idx: int) -> void:
	var fruits: Array = [""]
	for ft in GameState.FRUIT_TYPES:
		if UpgradeManager.is_fruit_unlocked(ft):
			fruits.append(ft)
	var cur: String = _queue_edit[idx]["fruit"]
	var next: String = fruits[(fruits.find(cur) + 1) % fruits.size()]
	_queue_edit[idx]["fruit"] = next


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return b
