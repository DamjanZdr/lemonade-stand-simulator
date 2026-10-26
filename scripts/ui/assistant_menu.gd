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
	m._rebuild()


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
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "Assistant"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
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
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var pay := _make_button("Pay $%.2f" % Assistant.WAGE)
	var stand := _assistant.assigned_stand
	pay.disabled = stand == null or stand.money < Assistant.WAGE
	pay.pressed.connect(
		func():
			_assistant.request_pay(),
	)
	row.add_child(pay)
	var cancel := _make_button("Cancel")
	cancel.pressed.connect(queue_free)
	row.add_child(cancel)


func _build_role_view(vb: VBoxContainer) -> void:
	var status := Label.new()
	status.text = ("Task: %s" % ROLE_LABELS.get(_assistant.role, "none"))
	vb.add_child(status)
	for r in Assistant.ROLES:
		var label: String = ROLE_LABELS.get(r, r)
		if _assistant.role == r:
			label += "  (current)"
		var b := _make_button(label)
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
	hdr.text = "Brew queue — set each slot's fruit + amount:"
	hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hdr)
	for i in QUEUE_SLOTS:
		vb.add_child(_make_slot_row(i))
	var loop := CheckButton.new()
	loop.text = "Loop queue"
	loop.button_pressed = _loop_edit
	loop.toggled.connect(
		func(on: bool):
			_loop_edit = on,
	)
	vb.add_child(loop)
	var apply := _make_button("Start brewing")
	apply.pressed.connect(
		func():
			var queue: Array = []
			for e in _queue_edit:
				if e["fruit"] != "" and int(e["qty"]) > 0:
					queue.append({ "fruit": e["fruit"], "qty": int(e["qty"]) })
			_assistant.request_assign("brewer", queue, _loop_edit),
	)
	vb.add_child(apply)
	var back := _make_button("Back")
	back.pressed.connect(
		func():
			_mode = "roles"
			_rebuild(),
	)
	vb.add_child(back)


func _make_slot_row(idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var num := Label.new()
	num.text = "%d." % (idx + 1)
	num.custom_minimum_size = Vector2(18, 0)
	row.add_child(num)
	var fruit_btn := _make_button(_slot_label(idx))
	fruit_btn.custom_minimum_size = Vector2(120, 0)
	fruit_btn.pressed.connect(
		func():
			_cycle_fruit(idx)
			fruit_btn.text = _slot_label(idx),
	)
	row.add_child(fruit_btn)
	var minus := _make_button("-")
	minus.pressed.connect(
		func():
			_queue_edit[idx]["qty"] = maxi(1, int(_queue_edit[idx]["qty"]) - 1)
			_rebuild(),
	)
	row.add_child(minus)
	var qty := Label.new()
	qty.text = str(_queue_edit[idx]["qty"])
	qty.custom_minimum_size = Vector2(20, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(qty)
	var plus := _make_button("+")
	plus.pressed.connect(
		func():
			_queue_edit[idx]["qty"] = mini(9, int(_queue_edit[idx]["qty"]) + 1)
			_rebuild(),
	)
	row.add_child(plus)
	return row


func _slot_label(idx: int) -> String:
	var f: String = _queue_edit[idx]["fruit"]
	return f.capitalize() if f != "" else "—"


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
