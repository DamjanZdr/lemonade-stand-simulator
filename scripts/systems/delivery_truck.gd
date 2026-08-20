class_name DeliveryTruck
extends Node3D
## Delivery truck placed in the world. Uses Marker3D children as path waypoints.
## Path: PathStart → PathTurnStart → PathTurnEnd → PathDrop (stop & transfer) → PathEnd
## Move the markers in the editor to control the truck's route.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

const DRIVE_SPEED: float = 48.0
const TURN_SPEED: float = 15.0
const ARC_DURATION: float = 0.8
const ARC_HEIGHT: float = 7.0
const BOX_DELAY: float = 0.12
const STOP_DURATION: float = 1.0

@onready var _grid: DeliveryGrid = $DeliveryGrid

var _target_grid: DeliveryGrid = null
var _state: String = "idle"
var _pending_boxes: Array[SupplyBox] = []
var _engine_player: AudioStreamPlayer3D = null
var _engine_fade_tween: Tween = null
var _boxes_transferred: int = 0
var _post_transfer_timer: float = 0.0
var _sync_timer: float = 0.0
var _last_synced_pos: Vector3 = Vector3.ZERO
const TRUCK_SYNC_INTERVAL: float = 0.1 # 10 updates/sec while driving

# Waypoint markers (read from children)
var _path_start: Marker3D = null
var _path_turn_start: Marker3D = null
var _path_turn_end: Marker3D = null
var _path_drop: Marker3D = null
var _path_end: Marker3D = null

# Driving state
var _waypoints: Array[Vector3] = []
var _current_wp: int = 0
var _scene_y: float = 0.0 # Preserved Y height from scene placement
var _scene_yaw: float = 0.0 # Preserved Y rotation from scene placement
var _turn_start_yaw: float = 0.0 # Yaw at start of turn segment
var _turn_end_yaw: float = 0.0 # Target yaw to face drop point

# Indices for turn segment in _waypoints
const WP_TURN_START: int = 1
const WP_TURN_END: int = 2
const WP_DROP: int = 3


func _ready() -> void:
	visible = false
	_scene_y = global_position.y
	_scene_yaw = global_rotation.y
	_find_route_markers()
	_recolor_truck(Color.WHITE)
	call_deferred("_fix_labels")


func _recolor_truck(color: Color) -> void:
	var truck_model := get_node_or_null("pickup truck2") as Node3D
	if truck_model == null:
		return
	for mesh_instance in _find_all_meshes_list(truck_model):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var mat := mesh_instance.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			if _is_red(mat.albedo_color):
				var new_mat := mat.duplicate() as BaseMaterial3D
				new_mat.albedo_color = color
				mesh_instance.set_surface_override_material(i, new_mat)


func _fix_labels() -> void:
	var truck_model := get_node_or_null("pickup truck2") as Node3D
	if truck_model == null:
		return
	for child in truck_model.get_children():
		if child is Label3D:
			var label := child as Label3D
			label.shaded = true
			label.no_depth_test = false
			# Also force depth test on the internal material
			var mat := label.material_override
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).no_depth_test = false


func _find_route_markers() -> void:
	var world := get_tree().current_scene
	var route := world.find_child("TruckRoute", true, false) as Node3D
	if route == null:
		push_warning("DeliveryTruck: no TruckRoute node found in world")
		return
	_path_start = route.get_node_or_null("PathStart") as Marker3D
	_path_turn_start = route.get_node_or_null("PathTurnStart") as Marker3D
	_path_turn_end = route.get_node_or_null("PathTurnEnd") as Marker3D
	_path_drop = route.get_node_or_null("PathDrop") as Marker3D
	_path_end = route.get_node_or_null("PathEnd") as Marker3D


func _start_engine_sound() -> void:
	_stop_engine_sound()
	var stream := load("res://assets/audio/sfx/car engine.mp3") as AudioStream
	if stream == null:
		return
	# Duplicate so we can enable looping without affecting the shared resource
	var orig_len: float = 0.0
	if stream is AudioStreamMP3:
		stream = (stream as AudioStreamMP3).duplicate()
		(stream as AudioStreamMP3).loop = true
		orig_len = (stream as AudioStreamMP3).get_length()
	_engine_player = AudioStreamPlayer3D.new()
	_engine_player.stream = stream
	_engine_player.unit_size = 12.0
	_engine_player.max_distance = 60.0
	_engine_player.autoplay = true
	_engine_player.volume_db = 3.0
	add_child(_engine_player)
	_engine_player.global_position = global_position
	# Start from the middle of the engine sound and fade in
	if orig_len > 0.0:
		_engine_player.play(orig_len * 0.5)
	_engine_player.volume_db = -20.0
	var tween := create_tween()
	tween.tween_property(_engine_player, "volume_db", 3.0, 0.4)


func _stop_engine_sound() -> void:
	if _engine_fade_tween:
		_engine_fade_tween.kill()
		_engine_fade_tween = null
	if _engine_player:
		_engine_player.queue_free()
		_engine_player = null


func _fade_engine_out(duration: float = 1.0) -> void:
	if _engine_player == null:
		return
	if _engine_fade_tween:
		_engine_fade_tween.kill()
	_engine_fade_tween = create_tween()
	_engine_fade_tween.tween_property(_engine_player, "volume_db", -40.0, duration)
	_engine_fade_tween.tween_callback(_stop_engine_sound)


func _play_beep() -> void:
	var stream := load("res://assets/audio/sfx/car beep.mp3") as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.unit_size = 12.0
	player.max_distance = 60.0
	player.pitch_scale = 1.4
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _play_start_engine() -> void:
	var stream := load("res://assets/audio/sfx/start engine.mp3") as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.unit_size = 12.0
	player.max_distance = 60.0
	player.volume_db = 3.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func set_target_grid(grid: DeliveryGrid) -> void:
	_target_grid = grid


## Called by DeliverySystem after all boxes are queued.
## Rearranges boxes in reverse vertical order (first-ordered on top), then drives in.
func start_delivery() -> void:
	if _state != "idle":
		return
	if _target_grid == null:
		return
	if _pending_boxes.is_empty():
		return

	# Rearrange boxes on the truck grid in reverse order so first-ordered is on top
	_rearrange_boxes_reverse()

	# Sort pending boxes by Y descending (top of stack first) for transfer order
	_pending_boxes.sort_custom(
		func(a: SupplyBox, b: SupplyBox) -> bool:
			return a.global_position.y > b.global_position.y,
	)

	# Build waypoint list for approach: start → turn_start → turn_end → drop
	_waypoints.clear()
	if _path_start:
		_waypoints.append(_path_start.global_position)
	if _path_turn_start:
		_waypoints.append(_path_turn_start.global_position)
	if _path_turn_end:
		_waypoints.append(_path_turn_end.global_position)
	if _path_drop:
		_waypoints.append(_path_drop.global_position)

	if _waypoints.size() < 2:
		push_warning("DeliveryTruck: not enough path waypoints defined")
		return

	# Snap to start position, preserving scene Y height
	global_position = Vector3(_waypoints[0].x, _scene_y, _waypoints[0].z)
	# Face the direction of the first waypoint, offset 90° to the right
	var to_first := _waypoints[1] - global_position
	to_first.y = 0.0
	if to_first.length() > 0.01:
		global_rotation.y = atan2(-to_first.x, -to_first.z) + PI / 2.0
	visible = true
	_current_wp = 1
	_state = "driving_in"
	_start_engine_sound()


func _process(delta: float) -> void:
	# Keep engine sound at truck position
	if _engine_player and is_instance_valid(_engine_player):
		_engine_player.global_position = global_position
	# Only the host drives the truck animation; clients receive position
	# updates via WorldSync.
	if not WorldSync.is_host():
		return
	match _state:
		"idle":
			return
		"driving_in":
			_drive_to_waypoint(delta)
		"stopped":
			_post_transfer_timer -= delta
			if _post_transfer_timer <= 0.0:
				_begin_transfer()
		"transferring":
			pass
		"driving_out":
			_drive_out(delta)
	# Sync truck position to clients while moving (event-driven, throttled)
	if _state != "idle":
		_sync_timer += delta
		if _sync_timer >= TRUCK_SYNC_INTERVAL:
			_sync_timer = 0.0
			if global_position.distance_to(_last_synced_pos) > 0.1:
				_last_synced_pos = global_position
				WorldSync.sync_property(self, "global_position", global_position)
				WorldSync.sync_property(self, "global_rotation", global_rotation)


func _drive_to_waypoint(delta: float) -> void:
	if _current_wp >= _waypoints.size():
		# Reached the drop point
		_state = "stopped"
		_post_transfer_timer = STOP_DURATION
		_play_skew_effect()
		# Fast fade engine out, then beep
		_fade_engine_out(0.15)
		get_tree().create_timer(0.25).timeout.connect(_play_beep)
		return

	var target_pos := _waypoints[_current_wp]
	# Keep scene Y height, drive on XZ plane
	target_pos.y = _scene_y
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.15:
		# If we just arrived at turn_start, capture yaw for turn interpolation
		if _current_wp == WP_TURN_START and _path_drop:
			_turn_start_yaw = global_rotation.y
			var to_drop := _path_drop.global_position - global_position
			to_drop.y = 0.0
			_turn_end_yaw = atan2(-to_drop.x, -to_drop.z)
		_current_wp += 1
		return

	var step := minf(DRIVE_SPEED * delta, dist)
	global_position += to_target.normalized() * step

	# Rotation logic depends on which segment we're on
	if _current_wp == WP_TURN_END and _path_drop:
		# During turn segment: interpolate from turn_start_yaw to turn_end_yaw
		var turn_from := _waypoints[WP_TURN_START]
		turn_from.y = _scene_y
		var turn_to := _waypoints[WP_TURN_END]
		turn_to.y = _scene_y
		var total_dist := (turn_to - turn_from).length()
		var traveled := (global_position - turn_from).length()
		var t := clampf(traveled / total_dist, 0.0, 1.0) if total_dist > 0.0 else 1.0
		var yaw_diff_turn := angle_difference(_turn_start_yaw, _turn_end_yaw)
		global_rotation.y = _turn_start_yaw + yaw_diff_turn * t
	else:
		# All other segments: smoothly rotate to face direction of travel
		var target_yaw := atan2(-to_target.x, -to_target.z)
		var current_yaw := global_rotation.y
		var yaw_diff := angle_difference(current_yaw, target_yaw)
		global_rotation.y = current_yaw + yaw_diff * minf(1.0, TURN_SPEED * delta)


func _drive_out(delta: float) -> void:
	# Exit directly to PathEnd, keeping current heading (forward)
	if _path_end == null:
		visible = false
		_state = "idle"
		_stop_engine_sound()
		return

	var target_pos := _path_end.global_position
	target_pos.y = _scene_y
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.5:
		visible = false
		_state = "idle"
		_fade_engine_out(0.15)
		return

	var step := minf(DRIVE_SPEED * delta, dist)
	global_position += to_target.normalized() * step

	# Smoothly rotate to face exit direction
	var target_yaw := atan2(-to_target.x, -to_target.z)
	var current_yaw := global_rotation.y
	var yaw_diff := angle_difference(current_yaw, target_yaw)
	global_rotation.y = current_yaw + yaw_diff * minf(1.0, TURN_SPEED * delta)


func _begin_transfer() -> void:
	if _pending_boxes.is_empty():
		_drive_away()
		return

	_state = "transferring"
	_boxes_transferred = 0

	# Transfer boxes one at a time with a delay between each
	for i in range(_pending_boxes.size()):
		var delay := i * BOX_DELAY
		get_tree().create_timer(delay).timeout.connect(_transfer_next_box.bind(i))


func _transfer_next_box(index: int) -> void:
	if index >= _pending_boxes.size():
		return
	if _state != "transferring":
		return

	var box := _pending_boxes[index]
	if box == null or not is_instance_valid(box):
		_boxes_transferred += 1
		_check_transfer_complete()
		return

	# Get the cell index this box was on in the truck grid
	var truck_cell_idx: int = box.get_meta("truck_cell_idx", -1)

	# Remove from truck grid (reparent to world so it's independent of the truck)
	var world := get_tree().current_scene
	var box_global_pos := box.global_position
	var box_global_rot := box.global_rotation
	_grid.remove_child(box)
	world.add_child(box)
	box.global_position = box_global_pos
	box.global_rotation = box_global_rot

	# Target position on the player's delivery grid at the same cell
	var target_pos := _target_grid.global_position
	var target_rot := Vector3.ZERO
	if truck_cell_idx >= 0:
		target_pos = _target_grid.get_slot_position(truck_cell_idx)
		target_rot = _target_grid.get_slot_rotation(truck_cell_idx)
		_target_grid.reserve_slot(truck_cell_idx)
		box.set_meta("delivery_cell_idx", truck_cell_idx)
		box.tree_exited.connect(_target_grid.release_slot_index.bind(truck_cell_idx))

	# Arc animation: parabolic path from truck to delivery grid
	_animate_arc(box, target_pos, target_rot)
	# Play swoosh sound for this box
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_sfx("swoosh", box_global_pos, -1.0, 0.0, 1.0)

	_boxes_transferred += 1
	_check_transfer_complete()


func _check_transfer_complete() -> void:
	if _boxes_transferred >= _pending_boxes.size():
		# Wait for the last box's arc to finish, then drive away
		var last_arc_time := ARC_DURATION + 0.3
		get_tree().create_timer(last_arc_time).timeout.connect(_drive_away)


func _rearrange_boxes_reverse() -> void:
	# Remove all boxes from the truck grid, reset stacks, then re-add in reverse order
	# so that the first-ordered box ends up on top of the stack.
	var boxes_to_restack: Array[SupplyBox] = []
	for child in _grid.get_children():
		if child is SupplyBox:
			boxes_to_restack.append(child as SupplyBox)

	# Sort by Y descending (top first) — these are in normal order (first at bottom)
	boxes_to_restack.sort_custom(
		func(a: SupplyBox, b: SupplyBox) -> bool:
			return a.global_position.y > b.global_position.y,
	)

	# Detach all boxes and reset the grid
	for box in boxes_to_restack:
		_grid.remove_child(box)
	_grid.reset_stacks()

	# Re-add in reverse purchase order: last-ordered first (bottom), first-ordered last (top)
	# boxes_to_restack is sorted top-first = first-ordered first, so we add in reverse
	for i in range(boxes_to_restack.size() - 1, -1, -1):
		var box := boxes_to_restack[i]
		_grid.add_child(box)
		var slot := _grid.reserve_next_slot()
		box.global_position = slot.get("position", _grid.global_position)
		box.global_rotation = slot.get("rotation", Vector3.ZERO)
		var cell_idx: int = slot.get("index", -1)
		if cell_idx >= 0:
			box.set_meta("truck_cell_idx", cell_idx)


func _drive_away() -> void:
	_pending_boxes.clear()
	_current_wp = 0
	# Play start engine sound, then start looping engine and drive off
	_play_start_engine()
	# Stay in current state (transferring) until engine restarts
	get_tree().create_timer(1.0).timeout.connect(_on_engine_restart_done)


func _on_engine_restart_done() -> void:
	_start_engine_sound()
	_state = "driving_out"


func _play_skew_effect() -> void:
	# Cartoony brake: animate the blend shape on pickup truck2.
	var truck_model := get_node_or_null("pickup truck2") as Node3D
	if truck_model == null:
		return

	# Find the MeshInstance3D with a blend shape inside the GLB
	var mi := _find_mesh_with_blend_shape(truck_model)
	if mi == null:
		return

	var blend_idx: int = _find_blend_shape_index(mi)
	if blend_idx < 0:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)

	# Phase 1: skew to max (0.08s)
	tween \
			.tween_method(
		func(v: float) -> void:
			mi.set_blend_shape_value(blend_idx, v),
		0.0,
		1.0,
		0.08,
	) \
			.set_ease(Tween.EASE_OUT)

	# Phase 2: overshoot back slightly (0.1s)
	tween \
			.tween_method(
		func(v: float) -> void:
			mi.set_blend_shape_value(blend_idx, v),
		1.0,
		-0.15,
		0.1,
	) \
			.set_ease(Tween.EASE_OUT)

	# Phase 3: settle back to 0 (0.08s)
	tween \
			.tween_method(
		func(v: float) -> void:
			mi.set_blend_shape_value(blend_idx, v),
		-0.15,
		0.0,
		0.08,
	) \
			.set_ease(Tween.EASE_IN_OUT)


func _find_mesh_with_blend_shape(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
			return mi
	for child in node.get_children():
		var result := _find_mesh_with_blend_shape(child)
		if result != null:
			return result
	return null


func _find_all_meshes_list(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_find_all_meshes_list(child))
	return result


func _is_red(c: Color) -> bool:
	return c.r > 0.35 and c.r > c.g * 1.3 and c.r > c.b * 1.3


func _find_blend_shape_index(mi: MeshInstance3D) -> int:
	var count: int = mi.mesh.get_blend_shape_count()
	for i in count:
		var shape_name: String = mi.mesh.get_blend_shape_name(i)
		if shape_name.to_lower().contains("key") or shape_name.to_lower().contains("skew"):
			return i
	if count > 0:
		return 0
	return -1


func _animate_arc(box: SupplyBox, target_pos: Vector3, target_rot: Vector3) -> void:
	var start_pos := box.global_position

	# Cubic bezier with two control points for a more drastic arc:
	# shoots up sharply, peaks, then dives down sharply.
	var cp1 := start_pos + Vector3(0, ARC_HEIGHT * 1.5, 0)
	var cp2 := target_pos + Vector3(0, ARC_HEIGHT * 1.5, 0)

	var tween := box.create_tween()
	tween.set_parallel(true)

	# Position: cubic bezier start -> cp1 -> cp2 -> target
	tween \
			.tween_method(
		func(t: float):
			var p := start_pos * (1.0 - t) ** 3 \
					+ cp1 * 3.0 * ((1.0 - t) ** 2) * t \
					+ cp2 * 3.0 * (1.0 - t) * (t ** 2) \
					+ target_pos * (t ** 3)
			box.global_position = p,
		0.0,
		1.0,
		ARC_DURATION,
	) \
			.set_trans(Tween.TRANS_LINEAR)

	# Rotation: smoothly rotate to target
	tween.tween_property(box, "global_rotation", target_rot, ARC_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	tween.finished.connect(
		func():
			AudioManager.play_sfx("box_drop", box.global_position),
	)


## Called by DeliverySystem to queue a box for truck delivery.
func queue_box(box: SupplyBox, cell_idx: int) -> void:
	_pending_boxes.append(box)
	box.set_meta("truck_cell_idx", cell_idx)
