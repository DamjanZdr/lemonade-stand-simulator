class_name Pedestrian
extends CharacterBody3D
## A neighbourhood pedestrian that follows a PedestrianPath in order.
## At convertable waypoints it rolls a popularity-based chance to join the queue.
## On success it walks directly to the reserved queue slot (same NPC, visually continuous)
## and signals the spawner when it arrives. After the last waypoint it despawns.

const GRAVITY := 9.8

@export var walk_speed: float = 2.2

signal wants_to_join(pedestrian: Pedestrian)

var _waypoints: Array[PedestrianWaypoint] = []
var _waypoint_idx: int = 0

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

var _ui_anchor: Node3D = null
var _order_label: Label3D = null
var _order_panel: Sprite3D = null
var _patience_circle: Sprite3D = null
var _patience_progress: TextureProgressBar = null

const _OFFER_TEXT := "A free lemonade?\nSure I would love that!"


func _ready() -> void:
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.3
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


## Called by PedestrianSpawner right after instantiation.
func setup(waypoints: Array[PedestrianWaypoint], start_index: int = 0) -> void:
	_waypoints = waypoints
	_waypoint_idx = start_index


## Called by PedestrianSpawner after a slot is reserved.
## The pedestrian stops following waypoints and walks straight to [target].
## [on_arrive] is called once it gets there.
func walk_to_queue(target: Vector3, on_arrive: Callable) -> void:
	_routing_to_queue = true
	_queue_target = target
	_queue_arrived_cb = on_arrive
	_npc.play_anim("Walk")


func update_queue_target(target: Vector3) -> void:
	_queue_target = target


func get_route_continuation() -> Dictionary:
	return {
		"waypoints": _waypoints,
		"next_index": _waypoint_idx + 1,
	}


func _physics_process(delta: float) -> void:
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
				move_and_slide()
				return

			if _waypoints.is_empty() or _waypoint_idx >= _waypoints.size():
				move_and_slide()
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

	move_and_slide()


func _arrive() -> void:
	if _state != PedestrianState.WALKING:
		return
	var wp := _waypoints[_waypoint_idx]

	var convert_chance: float = Balancing.pedestrian_convert_chance(GameState.popularity)
	var marketing_bonus: float = UpgradeManager.get_effect_total("marketing")
	if marketing_bonus > 0.0:
		convert_chance = clampf(convert_chance + marketing_bonus, 0.0, 1.0)
	if wp.convertable and randf() <= convert_chance:
		wants_to_join.emit(self)
		return # spawner will call walk_to_queue() or _resume(); don't advance yet

	_advance_waypoint()


func _advance_waypoint() -> void:
	_waypoint_idx += 1
	if _waypoint_idx >= _waypoints.size():
		queue_free()


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


func _show_order_text(text: String) -> void:
	if _order_label == null:
		return
	_order_label.text = text
	_order_label.visible = true
	if _order_panel:
		_order_panel.visible = false
		await get_tree().process_frame
		_resize_order_panel()


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
	_order_panel = Sprite3D.new()
	_order_panel.name = "OrderPanel"
	_order_panel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_order_panel.double_sided = true
	_order_panel.no_depth_test = true
	_order_panel.shaded = false
	_order_panel.pixel_size = 0.0008
	_order_panel.texture = _create_white_texture()
	_order_panel.modulate = Color(1, 1, 1, 0.95)
	_order_panel.position = Vector3(0, -0.65, -0.01)
	_order_panel.sorting_offset = -1.0
	_order_panel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_ui_anchor.add_child(_order_panel)

	_order_label = Label3D.new()
	_order_label.name = "OrderLabel"
	_order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_order_label.no_depth_test = true
	_order_label.pixel_size = 0.0008
	_order_label.font_size = 80
	_order_label.outline_size = 4
	_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_order_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_order_label.width = 0
	_order_label.sorting_offset = 1.0
	_order_label.modulate = Color(1, 1, 1, 1)
	_order_label.position = Vector3(0, -0.65, 0)
	_order_label.visible = false
	_ui_anchor.add_child(_order_label)
	_ui_anchor.move_child(_order_label, -1)


func _build_patience_circle() -> void:
	var viewport := SubViewport.new()
	viewport.name = "PatienceViewport"
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	_patience_circle.pixel_size = 0.0012
	_patience_circle.position = Vector3(0, 2.2, 0)
	_patience_circle.texture = viewport.get_texture()
	add_child(_patience_circle)


func _resize_order_panel() -> void:
	if _order_panel == null or _order_label == null:
		return
	var font := _order_label.font if _order_label.font else ThemeDB.fallback_font
	var text_px := font.get_multiline_string_size(
		_order_label.text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		int(_order_label.font_size),
	)
	var text_size := text_px * _order_label.pixel_size
	var pad := Vector2(0.05, 0.035)
	var panel_size := text_size + pad
	var panel_px := Vector2i(
		int(panel_size.x / _order_panel.pixel_size),
		int(panel_size.y / _order_panel.pixel_size),
	)
	panel_px.x = maxi(panel_px.x, 32)
	panel_px.y = maxi(panel_px.y, 32)
	var corner_px := clampi(int(mini(panel_px.x, panel_px.y) * 0.15), 8, 32)
	var panel_color := Color(0.20, 0.22, 0.24, 0.88)
	_order_panel.texture = _create_rounded_panel_texture(
		panel_px.x,
		panel_px.y,
		panel_color,
		corner_px,
	)
	_order_panel.scale = Vector3(1, 1, 1)
	_order_panel.visible = true


func _hide_order_bubble() -> void:
	if _order_panel:
		_order_panel.visible = false
	if _order_label:
		_order_label.visible = false


func _refresh_patience_bar(ratio: float) -> void:
	if _patience_progress == null:
		return
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
