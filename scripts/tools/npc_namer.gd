extends Node
## Debug tool for video recording: press N to enter NPC naming mode.
## Right-click spawns a random NPC at the looked-at floor position, facing the player.
## Left-click on a spawned NPC opens a name input popup.
## Enter confirms the name and shows it as a floating label above the NPC.
## Escape closes the input popup without naming.
## Regular pedestrian spawning is paused while the mode is active.
## Press N again to exit and clean up all spawned NPCs + labels.

const PEDESTRIAN_SCENE: PackedScene = preload("res://scenes/customer/pedestrian.tscn")
const AMATIC_FONT := preload("res://assets/fonts/AmaticSC-Bold.ttf")

var _active: bool = false
# Each entry: { ped: Pedestrian, panel: Panel, label: Label, named: bool }
var _spawned: Array = []
var _ui_layer: CanvasLayer = null
var _input_popup: PanelContainer = null
var _input_field: LineEdit = null
var _input_center: CenterContainer = null
var _selected_idx: int = -1
var _prev_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _people_was_active: bool = false


func _ready() -> void:
	set_process_input(true)
	set_process(false)


func _input(event: InputEvent) -> void:
	# While the input popup is open, let all key events go to the
	# LineEdit — don't toggle the mode or process any other keys.
	if _input_popup != null:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_input_popup()
			get_viewport().set_input_as_handled()
			return
		# Consume all other key/mouse events so they don't reach the
		# player controller. The LineEdit still gets them because it's
		# a focus-based control, not an _input handler.
		if event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_N:
		_toggle_mode()
		get_viewport().set_input_as_handled()
		return

	if not _active:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_spawn_at_mouse()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_try_select_npc()
			get_viewport().set_input_as_handled()

# ── Mode toggle ───────────────────────────────────────────────────────────────


func _toggle_mode() -> void:
	if _active:
		_exit_mode()
	else:
		_enter_mode()


func _enter_mode() -> void:
	_active = true
	# Pause regular pedestrian spawning. PeopleManager schedules spawns
	# via day_timer_updated → spawn_on_path, bypassing the spawner's
	# _managed flag, so we must pause both. Also stop the spawn timer
	# directly to be thorough.
	var spawner := get_tree().get_first_node_in_group("pedestrian_spawner")
	if spawner:
		if spawner.has_method("set_paused"):
			spawner.set_paused(true)
		if spawner.has_node("_spawn_timer"):
			spawner._spawn_timer.stop()
	var people := get_tree().get_first_node_in_group("people_manager")
	if people:
		_people_was_active = people._active
		people._active = false
	# Create a CanvasLayer for name labels + input popup.
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "NpcNamerLayer"
	_ui_layer.layer = 102
	add_child(_ui_layer)
	# Show the mouse cursor for clicking.
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _exit_mode() -> void:
	_active = false
	EventBus.esc_menu_open = false
	# Resume regular pedestrian spawning.
	var spawner := get_tree().get_first_node_in_group("pedestrian_spawner")
	if spawner:
		if spawner.has_method("set_paused"):
			spawner.set_paused(false)
		# Restart the timer if it's daytime and the spawner is NOT managed
		# by PeopleManager (managed → PeopleManager handles scheduling).
		if (
			spawner.has_node("_spawn_timer") and DayManager
			and DayManager.phase == DayManager.Phase.DAY and not spawner._managed
		):
			spawner._spawn_timer.start()
	var people := get_tree().get_first_node_in_group("people_manager")
	if people:
		people._active = _people_was_active
	# Clean up all spawned NPCs and their labels.
	for entry in _spawned:
		if is_instance_valid(entry.ped):
			entry.ped.queue_free()
		if is_instance_valid(entry.panel):
			entry.panel.queue_free()
	_spawned.clear()
	# Clean up UI.
	_close_input_popup()
	if _ui_layer:
		_ui_layer.queue_free()
		_ui_layer = null
	# Restore mouse mode.
	Input.mouse_mode = _prev_mouse_mode
	set_process(false)

# ── Spawning ──────────────────────────────────────────────────────────────────


func _spawn_at_mouse() -> void:
	var result := _raycast_from_mouse()
	if result.is_empty():
		return
	var pos: Vector3 = result.position
	pos.y = 0.0

	var ped := PEDESTRIAN_SCENE.instantiate() as Pedestrian
	if ped == null:
		return
	# Add to the World node (which has the 3D world), not the Main root.
	var world := get_tree().current_scene.get_node_or_null("World")
	if world:
		world.add_child(ped)
	else:
		get_tree().current_scene.add_child(ped)
	ped.global_position = pos
	# Empty waypoints → pedestrian stands still (physics process returns early).
	ped.setup([], 0)
	ped.velocity = Vector3.ZERO

	# Face the player on the horizontal plane. The NPC model faces +Z by
	# default, so look in the opposite direction (away from the player)
	# to end up facing toward them.
	var player := _get_local_player()
	if player:
		var dir := (pos - player.global_position).normalized()
		dir.y = 0.0
		if dir.length() > 0.001:
			ped.basis = Basis.looking_at(dir, Vector3.UP)

	# Switch from Walk (set in _ready) to Idle. Use call_deferred so
	# it runs after the pedestrian's _ready and any queued animations.
	if ped._npc and is_instance_valid(ped._npc):
		ped._npc.call_deferred("play_anim", "Idle")

	# Remove the PedestrianInteractable so the player's interaction
	# system doesn't highlight or interact with these debug NPCs.
	var inter := ped.get_node_or_null("PedestrianInteractable")
	if inter:
		inter.queue_free()

	_spawned.append(_create_name_label(ped))

# ── Selection + naming ─────────────────────────────────────────────────────────


func _try_select_npc() -> void:
	var result := _raycast_from_mouse()
	if result.is_empty():
		return
	var collider: Object = result.collider
	var ped := _find_pedestrian_in_parents(collider)
	if ped == null:
		return
	for i in range(_spawned.size()):
		if _spawned[i].ped == ped:
			_selected_idx = i
			_show_input_popup(_spawned[i].label.text)
			return


func _show_input_popup(current_name: String = "") -> void:
	# Close any existing popup WITHOUT resetting the selected index
	# (the caller set it just before calling us).
	if _input_center != null:
		_input_center.queue_free()
		_input_center = null
	_input_popup = null
	_input_field = null
	# Freeze player movement while typing.
	EventBus.esc_menu_open = true

	# CenterContainer wraps the popup so it's truly centered on screen.
	_input_center = CenterContainer.new()
	_input_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_input_center)

	_input_popup = PanelContainer.new()
	_input_popup.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.055, 0.94)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.96, 0.83, 0.32)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	_input_popup.add_theme_stylebox_override("panel", sb)
	_input_center.add_child(_input_popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_input_popup.add_child(vbox)

	var title := Label.new()
	title.text = "Enter NPC Name"
	title.add_theme_font_override("font", AMATIC_FONT)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.96, 0.83, 0.32))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_input_field = LineEdit.new()
	_input_field.add_theme_font_override("font", AMATIC_FONT)
	_input_field.add_theme_font_size_override("font_size", 28)
	_input_field.custom_minimum_size = Vector2(320, 44)
	_input_field.text = current_name
	_input_field.placeholder_text = "Name..."
	_input_field.clear_button_enabled = true
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(0, 0, 0, 0.35)
	field_style.border_color = Color(1, 1, 1, 0.7)
	field_style.set_border_width_all(2)
	field_style.set_content_margin_all(8)
	field_style.set_corner_radius_all(4)
	_input_field.add_theme_stylebox_override("normal", field_style)
	var focus_style := field_style.duplicate()
	focus_style.border_color = Color(0.96, 0.83, 0.32, 1.0)
	_input_field.add_theme_stylebox_override("focus", focus_style)
	_input_field.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	_input_field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	_input_field.add_theme_color_override("caret_color", Color(1, 0.95, 0.7, 1.0))
	_input_field.text_submitted.connect(_on_name_submitted)
	vbox.add_child(_input_field)
	_input_field.grab_focus()


func _on_name_submitted(text: String) -> void:
	var name := text.strip_edges()
	if name != "" and _selected_idx >= 0 and _selected_idx < _spawned.size():
		var entry: Dictionary = _spawned[_selected_idx]
		entry.label.text = name
		entry.named = true
		# Replicate the customer order bubble sizing: force the label
		# to recalculate its minimum size, then size the panel around it.
		entry.label.reset_size()
		entry.label.visible = true
		var label_size: Vector2 = entry.label.get_combined_minimum_size()
		var pad := Vector2(8, 4)
		entry.panel.size = label_size + pad * 2
		entry.label.position = pad
		entry.label.size = label_size
	_close_input_popup()


func _close_input_popup() -> void:
	if _input_center != null:
		_input_center.queue_free()
		_input_center = null
	_input_popup = null
	_input_field = null
	_selected_idx = -1
	# Restore player movement.
	if _active:
		EventBus.esc_menu_open = false

# ── Name labels (CanvasLayer-based, same approach as customer order bubbles) ──


func _create_name_label(ped: Pedestrian) -> Dictionary:
	var panel := Panel.new()
	panel.name = "NameLabelPanel"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.96, 0.83, 0.32, 0.9)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", sb)
	_ui_layer.add_child(panel)

	var label := Label.new()
	label.name = "NameLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", AMATIC_FONT)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.visible = false
	panel.add_child(label)

	return { "ped": ped, "panel": panel, "label": label, "named": false }


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for entry in _spawned:
		if not entry.named:
			continue
		if not is_instance_valid(entry.ped):
			entry.panel.visible = false
			continue
		# Position above the NPC's head (same area as order bubbles).
		var world_pos: Vector3 = entry.ped.global_position + Vector3(0, 2.0, 0)
		if cam.is_position_behind(world_pos):
			entry.panel.visible = false
			continue
		var screen_pos := cam.unproject_position(world_pos)
		var dist := cam.global_position.distance_to(world_pos)
		var ui_scale := clampf(4.0 / dist, 0.3, 1.5)
		entry.panel.scale = Vector2(ui_scale, ui_scale)
		var panel_size: Vector2 = entry.panel.size * ui_scale
		entry.panel.position = screen_pos - panel_size * 0.5
		entry.panel.visible = true

# ── Helpers ────────────────────────────────────────────────────────────────────


func _raycast_from_mouse() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return { }
	var mouse_pos := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var to := from + dir * 100.0
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [cam]
	return space.intersect_ray(query)


func _find_pedestrian_in_parents(node: Node) -> Pedestrian:
	var n := node
	while n != null:
		if n is Pedestrian:
			return n as Pedestrian
		n = n.get_parent()
	return null


func _get_local_player() -> Node3D:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	# WorldSync helper if available; otherwise fall back to tree search.
	if tree.current_scene.has_method("get_local_player"):
		return tree.current_scene.get_local_player()
	var p := tree.current_scene.find_child("Player", true, false) as Node3D
	return p
