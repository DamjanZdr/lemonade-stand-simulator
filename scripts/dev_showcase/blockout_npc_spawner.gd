extends Node3D
## Simple NPC spawner for the dev showcase blockout scene.
## Spawns capsule NPCs at Start1/Start2, walks them to End1/End2.
## 50% chance to "convert" — converted NPCs divert to the queue after 5-15s.
## Click an NPC to stop them and show speech. Give them lemonade for a reaction.

@export var spawn_interval_min: float = 1.0
@export var spawn_interval_max: float = 4.0
@export var convert_chance: float = 0.5
@export var convert_delay_min: float = 5.0
@export var convert_delay_max: float = 15.0
@export var npc_speed: float = 2.0
@export var queue_spacing: float = 1.2

var _spawn_timer: float = 0.0
var _next_spawn: float = 2.0
var _npcs: Array = []
var _queue_positions: Array = []
var _queue_index: int = 0

@onready var _start1: Marker3D = $Start1
@onready var _start2: Marker3D = $Start2
@onready var _end1: Marker3D = $End1
@onready var _end2: Marker3D = $End2
@onready var _queue_start: Marker3D = $QueueStart
@onready var _queue_end: Marker3D = $QueueEnd
@onready var _npc_template: MeshInstance3D = $NPCexample

# --- Lemonade pickup ---
var _held_lemonade: Node3D = null
var _held_lemonade_orig_parent: Node3D = null


func _ready() -> void:
	_build_queue_positions()
	_npc_template.visible = false
	# Add Area3D to each lemonade so raycast can hit them without physics collision
	for child in get_children():
		if child is CSGCylinder3D and child.name.begins_with("Lemonade"):
			_add_lemonade_area(child)


func _add_lemonade_area(lemonade: CSGCylinder3D) -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = lemonade.radius
	cyl.height = lemonade.height
	shape.shape = cyl
	area.add_child(shape)
	lemonade.add_child(area)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click()


func _handle_click() -> void:
	var player := _get_player()
	if player == null:
		return
	var ray := player.get_node_or_null("Head/RayCast3D") as RayCast3D
	if ray == null:
		return
	ray.force_raycast_update()
	var collider := ray.get_collider()
	if collider == null:
		# Not hitting anything — drop lemonade if holding
		if _held_lemonade != null:
			_drop_lemonade(ray.get_collision_point())
		return

	# Walk up the tree to identify what was hit
	var node: Node = collider
	while node != null:
		# Lemonade cylinder? (hit via Area3D child or the CSG itself)
		if node is CSGCylinder3D and node.name.begins_with("Lemonade"):
			if _held_lemonade == null:
				_pickup_lemonade(node)
			return
		# NPC? (check for the meta tag we set on spawn)
		if node.has_meta("npc_data"):
			_handle_npc_click(node)
			return
		node = node.get_parent()

	# Hit something else — drop lemonade on the surface we're looking at
	if _held_lemonade != null:
		_drop_lemonade(ray.get_collision_point())


func _handle_npc_click(npc: MeshInstance3D) -> void:
	var data: Dictionary = npc.get_meta("npc_data")

	if _held_lemonade != null:
		# Give lemonade to NPC - 50/50 reaction
		_consume_lemonade()
		if randf() < 0.5:
			_show_speech(npc, "THAT TASTES LIKE PISS!!!", Color(1, 0.3, 0.3))
		else:
			_show_speech(npc, "THIS TASTES AMAZING!!!", Color(0.3, 1, 0.4))
			_show_money_popup(npc, "+$1")
		data["state"] = "reacting"
		data["react_timer"] = 0.0
		data["stopped"] = false
	else:
		# Toggle stop/start
		if data.get("stopped", false):
			# Resume
			data["state"] = data.get("prev_state", "walking")
			data["stopped"] = false
			_hide_speech(npc)
		else:
			# Stop and show speech
			data["prev_state"] = data["state"]
			data["state"] = "stopped"
			data["stopped"] = true
			_show_speech(npc, "A free lemonade? Don't mind if i do.", Color(0.7, 1, 0.7))


func _show_speech(npc: Node3D, text: String, color: Color) -> void:
	_hide_speech(npc)
	# Use a CanvasLayer + Panel + Label, projected from 3D position (like real NPCs)
	var layer := CanvasLayer.new()
	layer.name = "SpeechBubble"
	layer.layer = 101
	npc.add_child(layer)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var label := Label.new()
	label.name = "Label"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)
	panel.add_child(label)

	# Force layout so we can get the label's required size, then size the panel
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.reset_size()
	var label_size := label.get_minimum_size()
	panel.custom_minimum_size = label_size + Vector2(10, 4)
	panel.size = panel.custom_minimum_size
	label.position = Vector2(5, 2)
	label.size = label_size

	# Store refs for _process to update screen position
	npc.set_meta("speech_layer", layer)
	npc.set_meta("speech_panel", panel)


func _hide_speech(npc: Node3D) -> void:
	if npc.has_meta("speech_panel"):
		npc.remove_meta("speech_panel")
	if npc.has_meta("speech_layer"):
		npc.remove_meta("speech_layer")
	var layer := npc.get_node_or_null("SpeechBubble")
	if layer:
		layer.queue_free()


func _show_money_popup(npc: Node3D, text: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "MoneyPopup"
	layer.layer = 102
	npc.add_child(layer)

	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(label)

	# Store for animation
	npc.set_meta("money_popup", layer)
	npc.set_meta("money_popup_label", label)
	npc.set_meta("money_popup_timer", 0.0)
	npc.set_meta("money_popup_y_offset", 0.0)


func _update_money_popup(npc: Node3D, delta: float) -> void:
	if not npc.has_meta("money_popup"):
		return
	var label: Label = npc.get_meta("money_popup_label", null)
	if label == null or not is_instance_valid(label):
		return
	var timer: float = npc.get_meta("money_popup_timer", 0.0) + delta
	npc.set_meta("money_popup_timer", timer)

	# Animate over 2 seconds: rise up and fade out
	var duration := 2.0
	var t := clampf(timer / duration, 0.0, 1.0)
	var y_offset: float = t * 60.0 # rise 60px
	var alpha := 1.0 - t

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world_pos := npc.global_position + Vector3(0, 0.5, 0)
	if cam.is_position_behind(world_pos):
		label.visible = false
		return
	label.visible = true
	var screen_pos := cam.unproject_position(world_pos)
	label.position = screen_pos - label.get_minimum_size() * 0.5 + Vector2(0, -y_offset)
	label.modulate = Color(1, 1, 1, alpha)

	if t >= 1.0:
		var layer := npc.get_node_or_null("MoneyPopup")
		if layer:
			layer.queue_free()
		npc.remove_meta("money_popup")
		npc.remove_meta("money_popup_label")
		npc.remove_meta("money_popup_timer")
		npc.remove_meta("money_popup_y_offset")


func _update_speech_pos(npc: Node3D) -> void:
	var panel: Panel = npc.get_meta("speech_panel", null)
	if panel == null or not is_instance_valid(panel):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Position at chest height
	var bubble_pos := npc.global_position + Vector3(0, 0.3, 0)
	if cam.is_position_behind(bubble_pos):
		panel.visible = false
		return
	panel.visible = true
	var screen_pos := cam.unproject_position(bubble_pos)
	var dist := cam.global_position.distance_to(bubble_pos)
	var ui_scale := clampf(3.0 / dist, 0.1, 1.0)
	panel.scale = Vector2(ui_scale, ui_scale)
	var panel_size := panel.size * ui_scale
	panel.position = screen_pos - panel_size * 0.5


func _get_player() -> Node:
	for child in get_children():
		if child is CharacterBody3D and child.name == "Player":
			return child
	return null


func _pickup_lemonade(lemonade: Node3D) -> void:
	var player := _get_player()
	if player == null:
		return
	var hand_slot := player.get_node_or_null("Head/Camera3D/HandSlot")
	if hand_slot == null:
		return
	_held_lemonade_orig_parent = lemonade.get_parent()
	_held_lemonade = lemonade
	_held_lemonade_orig_parent.remove_child(lemonade)
	hand_slot.add_child(lemonade)
	lemonade.position = Vector3.ZERO
	lemonade.scale = Vector3.ONE * 2.0
	# Disable the pickup area while held
	var area := lemonade.get_node_or_null("PickupArea")
	if area:
		area.monitorable = false
		area.set_deferred("monitoring", false)


func _drop_lemonade(drop_pos: Vector3) -> void:
	if _held_lemonade == null:
		return
	var player := _get_player()
	if player == null:
		return
	var hand_slot := player.get_node_or_null("Head/Camera3D/HandSlot")
	if hand_slot:
		hand_slot.remove_child(_held_lemonade)
	_held_lemonade_orig_parent.add_child(_held_lemonade)
	# Place lemonade so its bottom rests on the surface
	var cyl_height: float = 0.15
	_held_lemonade.global_position = drop_pos + Vector3(0, cyl_height * 0.5, 0)
	_held_lemonade.scale = Vector3.ONE
	# Re-enable the pickup area
	var area := _held_lemonade.get_node_or_null("PickupArea")
	if area:
		area.monitorable = true
		area.set_deferred("monitoring", true)
	_held_lemonade = null


func _consume_lemonade() -> void:
	if _held_lemonade == null:
		return
	var hand_slot := _held_lemonade.get_parent()
	if hand_slot:
		hand_slot.remove_child(_held_lemonade)
	_held_lemonade.queue_free()
	_held_lemonade = null


func _build_queue_positions() -> void:
	_queue_positions.clear()
	var start_pos := _queue_start.global_position
	var end_pos := _queue_end.global_position
	var dir := (end_pos - start_pos).normalized()
	var total_len := start_pos.distance_to(end_pos)
	var pos := start_pos
	while start_pos.distance_to(pos) <= total_len + 0.01:
		_queue_positions.append(pos)
		pos += dir * queue_spacing


func _process(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer >= _next_spawn:
		_spawn_timer = 0.0
		_next_spawn = randf_range(spawn_interval_min, spawn_interval_max)
		_spawn_npc()

	_update_npcs(delta)


func _spawn_npc() -> void:
	var use_start1: bool = randf() < 0.5
	var start_marker := _start1 if use_start1 else _start2
	var end_marker := _end1 if use_start1 else _end2

	# Duplicate the NPCexample template
	var npc: MeshInstance3D = _npc_template.duplicate()
	npc.visible = true
	var stand_y: float = _npc_template.position.y

	# Add a collision body so the raycast can hit the NPC
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.6
	shape.shape = capsule
	body.add_child(shape)
	npc.add_child(body)

	var converted: bool = randf() < convert_chance
	var convert_delay: float = randf_range(convert_delay_min, convert_delay_max)

	var data := {
		"node": npc,
		"end_pos": end_marker.global_position + Vector3(0, stand_y, 0),
		"converted": converted,
		"convert_delay": convert_delay,
		"elapsed": 0.0,
		"state": "walking",
		"queue_pos": Vector3.ZERO,
		"stopped": false,
	}

	# Store data ref on the node so click handler can find it
	npc.set_meta("npc_data", data)

	if converted:
		if _queue_index < _queue_positions.size():
			data["queue_pos"] = _queue_positions[_queue_index] + Vector3(0, stand_y, 0)
			_queue_index += 1
		else:
			data["converted"] = false

	add_child(npc)
	npc.global_position = start_marker.global_position + Vector3(0, stand_y, 0)
	_npcs.append(data)


func _update_npcs(delta: float) -> void:
	var to_remove := []
	for data in _npcs:
		var npc: Node3D = data["node"]
		if not is_instance_valid(npc):
			to_remove.append(data)
			continue

		data["elapsed"] += delta

		# Update speech bubble screen position if active
		if npc.has_meta("speech_panel"):
			_update_speech_pos(npc)
		# Update money popup animation if active
		if npc.has_meta("money_popup"):
			_update_money_popup(npc, delta)

		match data["state"]:
			"stopped":
				pass # Don't move

			"reacting":
				data["react_timer"] = data.get("react_timer", 0.0) + delta
				if data["react_timer"] >= 3.0:
					_hide_speech(npc)
					data["state"] = "walking"

			"walking":
				var target: Vector3 = data["end_pos"]
				if data["converted"] and data["elapsed"] >= data["convert_delay"]:
					data["state"] = "to_queue"
					target = data["queue_pos"]
				_move_toward(npc, target, delta)

				if npc.global_position.distance_to(data["end_pos"]) < 0.3:
					data["state"] = "done"

			"to_queue":
				_move_toward(npc, data["queue_pos"], delta)
				if npc.global_position.distance_to(data["queue_pos"]) < 0.1:
					data["state"] = "queuing"

			"queuing":
				pass

			"done":
				_hide_speech(npc)
				to_remove.append(data)

	for data in to_remove:
		if is_instance_valid(data["node"]):
			var npc: Node3D = data["node"]
			_hide_speech(npc)
			# Also clean up any money popup
			var money_layer := npc.get_node_or_null("MoneyPopup")
			if money_layer:
				money_layer.visible = false
				money_layer.queue_free()
			npc.queue_free()
		_npcs.erase(data)

	_rebuild_queue_indices()


func _move_toward(npc: Node3D, target: Vector3, delta: float) -> void:
	var dir := (target - npc.global_position)
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.01:
		return
	dir = dir.normalized()
	var step := npc_speed * delta
	if step >= dist:
		npc.global_position = target
	else:
		npc.global_position += dir * step
	if dir.length_squared() > 0.001:
		npc.rotation.y = atan2(dir.x, dir.z)


func _rebuild_queue_indices() -> void:
	var used: int = 0
	for data in _npcs:
		if data.get("converted", false) and data["state"] != "done":
			used += 1
	_queue_index = used
