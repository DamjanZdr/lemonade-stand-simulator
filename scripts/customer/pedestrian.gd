class_name Pedestrian
extends CharacterBody3D
## A neighbourhood pedestrian that follows a PedestrianPath in order.
## At convertable waypoints it rolls a popularity-based chance to join the queue.
## On success it walks directly to the reserved queue slot (same NPC, visually continuous)
## and signals the spawner when it arrives. After the last waypoint it despawns.
##
## Multiplayer: the host is authoritative for all NPC state. Clients receive
## state-change RPCs (spawn, waypoint advance, queue routing, offer, serve,
## resume, despawn) and simulate walking locally between state changes.
## This avoids syncing positions every frame — clients walk independently
## until the host tells them something changed.

const GRAVITY := 9.8

@export var walk_speed: float = 2.2

signal wants_to_join(pedestrian: Pedestrian)

var _waypoints: Array[PedestrianWaypoint] = []
var _waypoint_idx: int = 0

## Cached waypoint world-positions for client-side simulation (no need to
## reference the actual PedestrianWaypoint nodes on clients).
var _waypoint_positions: Array[Vector3] = []

## When true the pedestrian has diverted to a queue slot and ignores waypoints.
var _routing_to_queue: bool = false
var _queue_target: Vector3 = Vector3.ZERO
var _queue_arrived_cb: Callable = Callable() # called once the pedestrian reaches the slot

@onready var _npc: Node3D = $NPCBody

enum PedestrianState {
	WALKING,
	OFFERED,
	SERVING,
}
var _state: PedestrianState = PedestrianState.WALKING

var _offered_by_player: Node3D = null
var _offer_patience_max: float = 30.0
var _offer_patience: float = 0.0

var _facing_target: Basis = Basis.IDENTITY
var _is_rotating_to_face: bool = false
const _ROTATION_SPEED: float = 10.0

var _resume_waypoint_idx: int = 0
var _feedback_timer: float = 0.0
var _ground_y: float = 0.0
var _ground_snapped: bool = false
var _snap_attempts: int = 0
var _playable_area: Area3D = null
var _playable_snapped: bool = false
var _people_manager: Node = null

var _ui_anchor: Node3D = null
var _ui_layer: CanvasLayer = null
var _ui_label: Label = null
var _ui_panel: Panel = null
var _patience_circle: Sprite3D = null
var _patience_progress: TextureProgressBar = null
var _last_patience_percent: int = -1

const _OFFER_TEXT := "A free lemonade? Sure, I would love that!"


func _ready() -> void:
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 1.5
	_connect_playable_area()
	floor_constant_speed = true
	floor_stop_on_slope = false
	floor_block_on_wall = false
	_npc.randomize_appearance()
	_npc.play_anim("Walk")
	_ui_anchor = Node3D.new()
	_ui_anchor.name = "UIAnchor"
	_ui_anchor.position = Vector3(0, 1.7, 0)
	add_child(_ui_anchor)
	_build_order_bubble()
	_build_patience_circle()
	_hide_order_bubble()
	_patience_circle.visible = false
	add_to_group("pedestrians")
	_ignore_customer_collisions()


func _connect_playable_area() -> void:
	if _playable_area != null:
		return
	if get_tree() == null or get_tree().current_scene == null:
		return
	_playable_area = get_tree().current_scene.find_child("PlayableArea", true, false) as Area3D
	if _playable_area == null:
		return
	_playable_area.monitoring = true
	_playable_area.set_collision_mask_value(5, true)
	_playable_area.body_entered.connect(_on_playable_area_entered)


func _on_playable_area_entered(body: Node3D) -> void:
	if body != self or _playable_snapped:
		return
	_playable_snapped = true
	_ground_snapped = false
	_snap_attempts = 0


## Called by PedestrianSpawner right after instantiation.
## On the host: sets up waypoints and syncs the route to clients.
## On clients: called with empty waypoints; use setup_client() instead.
func setup(waypoints: Array[PedestrianWaypoint], start_index: int = 0) -> void:
	_waypoints = waypoints
	_waypoint_idx = start_index
	# Cache positions (unused on clients now — server-authoritative sync)
	_waypoint_positions.clear()
	for wp in waypoints:
		_waypoint_positions.append(wp.global_position)


## Called by PedestrianSpawner after a slot is reserved.
## The pedestrian stops following waypoints and walks straight to [target].
## [on_arrive] is called once it gets there.
func walk_to_queue(target: Vector3, on_arrive: Callable) -> void:
	_routing_to_queue = true
	_ground_snapped = false
	_snap_attempts = 0
	_queue_target = target
	_queue_arrived_cb = on_arrive
	_npc.play_anim("Walk")
	_sync_walk_to_queue.rpc(target)


## Update queue target position (host only). Syncs to clients.
func update_queue_target(target: Vector3) -> void:
	_queue_target = target
	_sync_queue_target.rpc(target)


func get_route_continuation() -> Dictionary:
	return { "waypoints": _waypoints, "next_index": _waypoint_idx + 1 }


func _process(_delta: float) -> void:
	if _ui_label != null and _ui_label.visible:
		_update_bubble_screen_pos()


func _physics_process(delta: float) -> void:
	# Server-authoritative: only the host runs NPC simulation.
	# Clients receive position+rotation via WorldSync and interpolate.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_physics_client_interpolate(delta)
		return

	if _playable_area == null:
		_connect_playable_area()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if _is_rotating_to_face:
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(_facing_target.get_rotation_quaternion(), t)
		basis = Basis(q)
		if q.dot(_facing_target.get_rotation_quaternion()) > 0.999:
			basis = _facing_target
			_is_rotating_to_face = false

	match _state:
		PedestrianState.WALKING:
			if _routing_to_queue:
				if global_position.distance_to(_queue_target) < 0.35:
					_routing_to_queue = false
					velocity = Vector3.ZERO
					if _queue_arrived_cb.is_valid():
						_queue_arrived_cb.call()
				else:
					_walk_toward(_queue_target, delta)
				_apply_motion(delta)
				return

			if _waypoints.is_empty() or _waypoint_idx >= _waypoints.size():
				_apply_motion(delta)
				return

			var target := _waypoints[_waypoint_idx].global_position
			if global_position.distance_to(target) < 0.55:
				_arrive()
			else:
				_walk_toward(target, delta)

		PedestrianState.OFFERED:
			velocity = Vector3.ZERO
			if is_instance_valid(_offered_by_player):
				_facing_target = Basis.looking_at(
					_offered_by_player.global_position - global_position,
					Vector3.UP,
				)
				_is_rotating_to_face = true
			_offer_patience -= delta
			if _offer_patience <= 0.0:
				_offer_timeout()
			else:
				_refresh_patience_bar(_offer_patience / _offer_patience_max)

		PedestrianState.SERVING:
			velocity = Vector3.ZERO
			_feedback_timer -= delta
			if _feedback_timer <= 0.0:
				_resume_walking()

	_apply_motion(delta)


func _apply_motion(delta: float) -> void:
	if _routing_to_queue:
		move_and_slide()
	elif not _ground_snapped:
		# Snap to the floor before switching to cheap translation.
		move_and_slide()
		_snap_attempts += 1
		if is_on_floor() or _snap_attempts > 20:
			_ground_y = global_position.y
			_ground_snapped = true
	else:
		velocity.y = 0.0
		global_position += velocity * delta
		global_position.y = _ground_y


# ── Client-side interpolation ─────────────────────────────────────────────────
## Server-authoritative approach (like Schedule 1 / FishNet):
## The host runs all NPC logic and periodically syncs position+rotation
## via WorldSync.sync_transform(). Clients interpolate smoothly toward
## the received position. No client-side simulation — just interpolation.
## State changes (offered, serving, resume) use separate RPCs.

## Target position/rotation received from host via WorldSync.
## Client interpolates global_position toward this every frame.
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_rot: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
const _NET_LERP_SPEED: float = 12.0 # How fast to interpolate toward target


func _physics_client_interpolate(delta: float) -> void:
	# Handle facing rotation (e.g. when offered/serving)
	if _is_rotating_to_face:
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(_facing_target.get_rotation_quaternion(), t)
		basis = Basis(q)
		if q.dot(_facing_target.get_rotation_quaternion()) > 0.999:
			basis = _facing_target
			_is_rotating_to_face = false

	# Interpolate position toward the last received target from the host
	if _has_net_target:
		var t := clampf(_NET_LERP_SPEED * delta, 0.0, 1.0)
		global_position = global_position.lerp(_net_target_pos, t)
		# Smoothly rotate toward target rotation
		var curr_q := basis.get_rotation_quaternion()
		var target_q := Quaternion.from_euler(_net_target_rot)
		basis = Basis(curr_q.slerp(target_q, t))

	# When walking, keep the walk animation playing; when stopped, idle
	if _state == PedestrianState.WALKING:
		var dist_to_target := global_position.distance_to(_net_target_pos)
		if dist_to_target > 0.05:
			_npc.play_anim("Walk")
		else:
			_npc.play_anim("Idle")


## Called by WorldSync when a transform sync arrives. Sets the
## interpolation target instead of snapping position directly.
func _net_set_target(pos: Vector3, rot: Vector3) -> void:
	_net_target_pos = pos
	_net_target_rot = rot
	_has_net_target = true


# ── Multiplayer RPCs (host → clients) ────────────────────────────────────────
## Host: advance to next waypoint. Clients don't need this — they follow
## the host's position via WorldSync.sync_transform() interpolation.
func _advance_waypoint() -> void:
	_waypoint_idx += 1
	if _waypoint_idx >= _waypoints.size():
		queue_free()
		return


## Host: NPC was offered a free lemonade and stopped. Synced to clients.
func sync_offered(player_pos: Vector3) -> void:
	_sync_offered.rpc(player_pos)


## Host: NPC was served and is now in serving state. Synced to clients.
func sync_serving() -> void:
	_sync_serving.rpc()


## Host: NPC resumed walking (after offer timeout or serving done). Synced.
func sync_resume(waypoint_idx: int) -> void:
	_sync_resume.rpc(waypoint_idx)


@rpc("authority", "call_local", "reliable")
func _sync_walk_to_queue(target: Vector3) -> void:
	if multiplayer.is_server():
		return
	_routing_to_queue = true
	_ground_snapped = false
	_snap_attempts = 0
	_queue_target = target
	_npc.play_anim("Walk")


@rpc("authority", "call_local", "reliable")
func _sync_queue_target(target: Vector3) -> void:
	if multiplayer.is_server():
		return
	_queue_target = target


@rpc("authority", "call_local", "reliable")
func _sync_offered(player_pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	_state = PedestrianState.OFFERED
	velocity = Vector3.ZERO
	_facing_target = Basis.looking_at(player_pos - global_position, Vector3.UP)
	_is_rotating_to_face = true
	_show_order_text(_OFFER_TEXT)
	if _patience_circle:
		_patience_circle.visible = true
		_refresh_patience_bar(1.0)
	_npc.play_anim("Talk")


@rpc("authority", "call_local", "reliable")
func _sync_serving() -> void:
	if multiplayer.is_server():
		return
	_state = PedestrianState.SERVING
	velocity = Vector3.ZERO
	_hide_order_bubble()
	if _patience_circle:
		_patience_circle.visible = false
	_npc.play_anim("Talk")


@rpc("authority", "call_local", "reliable")
func _sync_resume(waypoint_idx: int) -> void:
	if multiplayer.is_server():
		return
	_state = PedestrianState.WALKING
	_is_rotating_to_face = false
	_waypoint_idx = waypoint_idx
	_hide_order_bubble()
	if _patience_circle:
		_patience_circle.visible = false
	_npc.play_anim("Walk")


func _ensure_people_manager() -> bool:
	if _people_manager != null and is_instance_valid(_people_manager):
		return true
	if get_tree() == null or get_tree().current_scene == null:
		return false
	_people_manager = get_tree().current_scene.find_child("PeopleManager", true, false)
	return _people_manager != null


func _get_convert_chance() -> float:
	if _ensure_people_manager():
		return _people_manager.call("get_pedestrian_convert_chance", GameState.popularity)
	return Balancing.pedestrian_convert_chance(GameState.popularity)


func _arrive() -> void:
	if _waypoint_idx == 2:
		_npc.resume_anim("Walk")
	if _waypoint_idx == 5:
		_npc.pause_anim()
	if _state != PedestrianState.WALKING:
		return
	var wp := _waypoints[_waypoint_idx]

	var convert_chance: float = _get_convert_chance()
	var marketing_bonus: float = UpgradeManager.get_effect_total("marketing")
	if marketing_bonus > 0.0:
		convert_chance = clampf(convert_chance + marketing_bonus, 0.0, 1.0)
	if wp.convertable and randf() <= convert_chance:
		wants_to_join.emit(self)
		return # spawner will call walk_to_queue() or _resume(); don't advance yet

	_advance_waypoint()


func _walk_toward(target: Vector3, delta: float) -> void:
	var dir := (target - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * walk_speed
	velocity.z = dir.z * walk_speed
	if dir.length_squared() > 0.01:
		var target_basis := Basis.looking_at(dir, Vector3.UP)
		var t := minf(delta * 10.0, 1.0)
		var q := basis.get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), t)
		basis = Basis(q)


func can_interact() -> bool:
	return _state == PedestrianState.WALKING


func offer_free_lemonade(player: Node) -> void:
	if _state != PedestrianState.WALKING or _routing_to_queue:
		return
	_state = PedestrianState.OFFERED
	_offered_by_player = player as Node3D
	_resume_waypoint_idx = _waypoint_idx
	velocity = Vector3.ZERO
	_offer_patience = _offer_patience_max
	_show_order_text(_OFFER_TEXT)
	if _patience_circle:
		_patience_circle.visible = true
		_refresh_patience_bar(1.0)
	_npc.play_anim("Talk")
	if _offered_by_player:
		_facing_target = Basis.looking_at(
			_offered_by_player.global_position - global_position,
			Vector3.UP,
		)
		_is_rotating_to_face = true
	# Sync to clients
	sync_offered(_offered_by_player.global_position if _offered_by_player else global_position)


func try_serve(player: Node) -> void:
	if _state != PedestrianState.OFFERED:
		return
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.CUP_FILLED:
		return
	var recipe: Dictionary = p.held_item_data.get("recipe", { })
	p.clear_held()
	_state = PedestrianState.SERVING
	_offered_by_player = null
	_hide_order_bubble()
	if _patience_circle:
		_patience_circle.visible = false

	var result := RecipeEvaluator.evaluate_detailed(recipe, GameState.temperature, "")
	var feedback := _feedback_text(result)
	_show_order_text(feedback)
	_npc.play_anim("Talk")
	_feedback_timer = 2.5
	# Sync to clients
	sync_serving()


func _offer_timeout() -> void:
	_hide_order_bubble()
	if _patience_circle:
		_patience_circle.visible = false
	_resume_walking()


func _resume_walking() -> void:
	_state = PedestrianState.WALKING
	_offered_by_player = null
	_offer_patience = 0.0
	_is_rotating_to_face = false
	_waypoint_idx = _resume_waypoint_idx
	_hide_order_bubble()
	if _patience_circle:
		_patience_circle.visible = false
	_npc.play_anim("Walk")
	# Sync to clients
	sync_resume(_waypoint_idx)


func _show_order_text(text: String) -> void:
	if _ui_label == null:
		return
	_ui_label.text = text
	_ui_label.visible = true
	if _ui_panel:
		_ui_panel.visible = false
		call_deferred("_resize_order_panel")


func _update_bubble_screen_pos() -> void:
	if _ui_panel == null or _ui_anchor == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Position the order bubble at chest height.
	var bubble_pos := global_position + Vector3(0, 1.1, 0)
	if cam.is_position_behind(bubble_pos):
		_ui_panel.visible = false
		return
	_ui_panel.visible = true
	var screen_pos := cam.unproject_position(bubble_pos)
	# Scale the screen-space bubble with distance so it doesn't look
	# huge when the NPC is far away.
	var dist := cam.global_position.distance_to(bubble_pos)
	var ui_scale := clampf(4.0 / dist, 0.25, 1.3)
	_ui_panel.scale = Vector2(ui_scale, ui_scale)
	var panel_size := _ui_panel.size * ui_scale
	_ui_panel.position = screen_pos - panel_size * 0.5


func _feedback_text(result: EvaluationResult) -> String:
	if result.complaints.is_empty():
		return "Mmm, perfect!\nThanks!"
	var parts: Array[String] = []
	for c: String in result.complaints:
		parts.append(_complaint_word(c))
	return "Hmm, %s." % ", ".join(parts)


func _complaint_word(complaint: String) -> String:
	match complaint:
		"too_strong":
			return "too strong"
		"not_enough_fruit":
			return "not enough fruit"
		"too_sweet":
			return "too sweet"
		"not_sweet_enough":
			return "not sweet enough"
		"too_cold":
			return "too cold"
		"not_cold_enough":
			return "not cold enough"
		_:
			return complaint


func _build_order_bubble() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "OrderBubbleLayer"
	_ui_layer.layer = 101
	add_child(_ui_layer)

	_ui_panel = Panel.new()
	_ui_panel.name = "OrderPanel"
	_ui_panel.visible = false
	_ui_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	_ui_panel.add_theme_stylebox_override("panel", sb)
	_ui_layer.add_child(_ui_panel)

	_ui_label = Label.new()
	_ui_label.name = "OrderLabel"
	_ui_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_label.add_theme_font_size_override("font_size", 12)
	_ui_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_ui_label.add_theme_constant_override("outline_size", 2)
	_ui_label.visible = false
	_ui_panel.add_child(_ui_label)


func _build_patience_circle() -> void:
	var viewport := SubViewport.new()
	viewport.name = "PatienceViewport"
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.disable_3d = true
	viewport.size = Vector2i(128, 128)
	add_child(viewport)

	var tex := _create_ring_texture(128, 0.15)

	_patience_progress = TextureProgressBar.new()
	_patience_progress.name = "PatienceProgress"
	_patience_progress.size = Vector2(128, 128)
	_patience_progress.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_patience_progress.nine_patch_stretch = false
	_patience_progress.texture_progress = tex
	_patience_progress.tint_progress = Color.WHITE
	_patience_progress.max_value = 1000.0
	_patience_progress.value = 1000.0
	_patience_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(_patience_progress)

	_patience_circle = Sprite3D.new()
	_patience_circle.name = "PatienceCircle"
	_patience_circle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_patience_circle.double_sided = true
	_patience_circle.no_depth_test = true
	_patience_circle.shaded = false
	_patience_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_patience_circle.pixel_size = 0.0012
	_patience_circle.position = Vector3(0, 2.2, 0)
	_patience_circle.texture = viewport.get_texture()
	add_child(_patience_circle)
	_apply_ui_tonemap_comp(_patience_circle)
	if not Engine.is_editor_hint():
		EventBus.exposure_changed.connect(
			func(exposure: float):
				_apply_ui_tonemap_comp(_patience_circle, exposure),
		)


func _apply_ui_tonemap_comp(sprite: Sprite3D, exposure: float = 1.0) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = Customer.get_ui_tonemap_shader()
	mat.set_shader_parameter("tex", sprite.texture)
	mat.set_shader_parameter("boost", 1.0 / exposure)
	sprite.material_override = mat


func _resize_order_panel() -> void:
	if _ui_panel == null or _ui_label == null:
		return
	var label_size := _ui_label.get_combined_minimum_size()
	var pad := Vector2(8, 4)
	_ui_panel.size = label_size + pad * 2
	_ui_label.position = pad
	_ui_panel.visible = true


func _hide_order_bubble() -> void:
	if _ui_panel:
		_ui_panel.visible = false
	if _ui_label:
		_ui_label.visible = false


func _refresh_patience_bar(ratio: float) -> void:
	if _patience_progress == null:
		return
	var percent := int(ratio * 100.0)
	if percent == _last_patience_percent:
		return
	_last_patience_percent = percent
	_patience_progress.value = ratio * _patience_progress.max_value


func _ignore_customer_collisions() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("customers"):
		var other := node as CollisionObject3D
		if other == null or other == self or not is_instance_valid(other):
			continue
		PhysicsServer3D.body_add_collision_exception(get_rid(), other.get_rid())
		PhysicsServer3D.body_add_collision_exception(other.get_rid(), get_rid())


func _create_white_texture(size: int = 4) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _create_ring_texture(size: int = 128, inner_ratio: float = 0.15) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var center := int(size / 2.0)
	var outer := int(size / 2.0)
	var inner := int(outer * inner_ratio)
	var outer_sq := outer * outer
	var inner_sq := inner * inner
	for x in range(size):
		var dx := x - center
		var dx_sq := dx * dx
		for y in range(size):
			var d_sq := dx_sq + (y - center) * (y - center)
			if d_sq <= outer_sq and d_sq >= inner_sq:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _create_rounded_panel_texture(
	width: int,
	height: int,
	color: Color,
	corner: int,
) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := clampi(corner, 0, int(mini(width, height) / 2.0))
	for x in range(width):
		var nx := clampi(x, r, width - r - 1)
		var dx := x - nx
		var dx_sq := dx * dx
		for y in range(height):
			var ny := clampi(y, r, height - r - 1)
			var dy := y - ny
			if dx_sq + dy * dy <= r * r:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
