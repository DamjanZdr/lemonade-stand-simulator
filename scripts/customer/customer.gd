class_name Customer
extends CharacterBody3D
## Runtime-spawned NPC. Walks to queue spot, waits, receives/rejects lemonade, leaves.

enum CustomerState { WALKING, WAITING, RECEIVING, REACTING, LEAVING }

const GRAVITY: float = 9.8


var queue_position: Vector3 = Vector3.ZERO
var queue_slot: int = 0 # 0 = active (faces counter), 1+ = queued (faces front of queue)
var queue_face_dir: Vector3 = Vector3(1, 0, 0) # set by spawner
var counter_face_dir: Vector3 = Vector3(0, 0, 1) # set by spawner
var patience_max: float = Balancing.PATIENCE_BASE
var patience: float = 0.0
var state: CustomerState = CustomerState.WALKING
var expected_fruit: String = "lemon"
var _outcome: String = ""
var _waiting_for_change: bool = false
var _change_callable: Callable = Callable()
var _fallback_tween: Tween = null
var _facing_target: Basis = Basis.IDENTITY
var _is_rotating_to_face: bool = false
const _ROTATION_SPEED: float = 10.0

var _leave_waypoints: Array[PedestrianWaypoint] = []
var _leave_waypoint_idx: int = 0

const _ENGAGE_LOOK_RANGE: float = 3.5
var _engaged_with_player: bool = false
var _engaged_player: Node3D = null
var _default_facing_target: Basis = Basis.IDENTITY

@onready var emoji_anchor: Node3D = $EmojiAnchor
@onready var emoji_display: Node = $EmojiAnchor/EmojiDisplay
@onready var order_label: Label3D = $EmojiAnchor/OrderLabel
@onready var _npc: Node3D = $NPCBody

var _order_panel: Sprite3D = null

var _patience_circle: Sprite3D = null
var _patience_progress: TextureProgressBar = null

var _preserve_appearance: bool = false


func preserve_appearance() -> void:
	_preserve_appearance = true


func _ready() -> void:
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.3
	floor_constant_speed = true
	floor_stop_on_slope = false
	floor_block_on_wall = false
	var sunroof_bonus: float = UpgradeManager.get_effect_total("sunroof")
	if sunroof_bonus > 0.0:
		patience_max *= (1.0 + sunroof_bonus)
	patience = patience_max
	EventBus.debug_force_happy_serve.connect(_on_debug_force_happy)
	if not _preserve_appearance:
		_npc.randomize_appearance()
	_npc.play_anim("Walk")
	_build_order_bubble()
	_build_patience_circle()
	_refresh_patience_bar(1.0)
	# Hide legacy order/patience nodes if they still exist in the scene.
	for legacy_name in [
		"PatienceBar",
		"PatienceBarBG",
		"EmojiAnchor/OrderLabel",
		"EmojiAnchor/OrderPanel",
	]:
		var node := get_node_or_null(legacy_name)
		if node:
			node.visible = false
	# Ensure both hand-held cash pickups start hidden.
	for cp_name in ["CashPoint/CashPickup", "CashPoint2/CashPickup"]:
		var cp := _npc.get_node_or_null(cp_name) as CashPickup
		if cp:
			cp.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if _is_rotating_to_face:
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(
			_facing_target.get_rotation_quaternion(),
			t,
		)
		basis = Basis(q)
		if q.dot(_facing_target.get_rotation_quaternion()) > 0.999:
			basis = _facing_target
			_is_rotating_to_face = false

	match state:
		CustomerState.WALKING:
			_walk_toward(queue_position, delta)
			if global_position.distance_to(queue_position) < 0.25:
				velocity = Vector3.ZERO
				state = CustomerState.WAITING
				_begin_smooth_facing()
				_npc.play_anim("Idle")
				_default_facing_target = _facing_target
				EventBus.customer_arrived.emit(self)
		CustomerState.WAITING:
			patience -= delta
			var ratio := patience / patience_max
			_refresh_patience_bar(ratio)
			EventBus.customer_patience_changed.emit(self, ratio)
			if _engaged_with_player:
				var should_disengage := not is_instance_valid(_engaged_player)
				if not should_disengage:
					var dist := global_position.distance_to(_engaged_player.global_position)
					should_disengage = dist > _ENGAGE_LOOK_RANGE
				if should_disengage:
					_disengage_player()
				else:
					_facing_target = Basis.looking_at(
						_engaged_player.global_position - global_position,
						Vector3.UP,
					)
					_is_rotating_to_face = true
			if patience <= 0.0:
				_resolve("timeout")
		CustomerState.LEAVING:
			if _leave_waypoints.is_empty():
				_walk_toward(
					Vector3(global_position.x, global_position.y, Balancing.CUSTOMER_DESPAWN_Z),
					delta,
				)
				if global_position.z <= Balancing.CUSTOMER_DESPAWN_Z:
					queue_free()
			elif _leave_waypoint_idx >= _leave_waypoints.size():
				queue_free()
			else:
				var target := _leave_waypoints[_leave_waypoint_idx].global_position
				_walk_toward(target, delta)
				if global_position.distance_to(target) < 0.55:
					_leave_waypoint_idx += 1
					if _leave_waypoint_idx >= _leave_waypoints.size():
						queue_free()

	move_and_slide()


func _walk_toward(target: Vector3, delta: float) -> void:
	var dir := (target - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * Balancing.CUSTOMER_WALK_SPEED
	velocity.z = dir.z * Balancing.CUSTOMER_WALK_SPEED
	if dir.length_squared() > 0.01:
		var target_basis := Basis.looking_at(dir, Vector3.UP)
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			t,
		)
		basis = Basis(q)


func try_serve(player: Node) -> void:
	## Called when the player (holding CUP_FILLED) clicks this customer.
	if state != CustomerState.WAITING:
		return
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.CUP_FILLED:
		return
	var recipe: Dictionary = p.held_item_data.get("recipe", { })
	p.clear_held()
	state = CustomerState.RECEIVING
	_engaged_with_player = false
	_engaged_player = null
	_hide_order_bubble()
	var wait_ratio := patience / patience_max
	var price := GameState.get_price(expected_fruit)
	var outcome := RecipeEvaluator.evaluate(
		recipe,
		GameState.temperature,
		price,
		wait_ratio,
		expected_fruit,
	)
	_resolve(outcome)


func force_timeout() -> void:
	## Called by DayManager / spawner when day ends.
	_resolve("timeout")


func _resolve(outcome: String) -> void:
	_outcome = outcome
	state = CustomerState.REACTING
	EventBus.customer_served.emit(self, outcome)
	emoji_display.show_emoji(outcome, GameState.feedback_tier)
	if outcome != "timeout":
		# Every served customer pays; wait here until the player processes
		# change at the register before walking away.
		var price := GameState.get_price(expected_fruit)
		var payment := _customer_payment(price)
		var change_due := roundf((payment - price) * 100.0) / 100.0
		var cp_name: String = _npc.get_cash_point_name()
		var cash_point := _npc.get_node_or_null(cp_name) as Marker3D
		var drop_pos := cash_point.global_position if cash_point \
		else _npc.global_position + Vector3(0, 1.0, 0.5)
		_npc.start_payment_pose(drop_pos)
		# Use the pre-placed CashPickup under the gender-specific CashPoint.
		var cp := _npc.get_node_or_null(cp_name + "/CashPickup") as CashPickup
		if cp:
			cp.payment = payment
			cp.change_due = change_due
			cp.hide_on_interact = true
			cp.visible = true
			if cp.label:
				cp.label.text = "$%.2f" % payment
		else:
			# Fallback: spawn cash at the counter the old way.
			EventBus.cash_dropped.emit(drop_pos, payment, change_due)
		_waiting_for_change = true
		_change_callable = func(_e: float): _leave_after_change()
		EventBus.change_finalized.connect(_change_callable, CONNECT_ONE_SHOT)
		# Fallback: give up after 60 s if the player ignores the register.
		_fallback_tween = create_tween()
		_fallback_tween.tween_interval(60.0)
		_fallback_tween.tween_callback(_leave_after_change)
	else:
		var serve_bonus: float = UpgradeManager.get_effect_total("speed_serve")
		var interval: float = 1.8 * (1.0 - serve_bonus)
		var tween := create_tween()
		tween.tween_interval(interval)
		tween.tween_callback(_start_leaving)


func _leave_after_change() -> void:
	if not _waiting_for_change:
		return
	_waiting_for_change = false
	# Clean up: disconnect signal if still connected, kill fallback tween.
	if _change_callable.is_valid() and EventBus.change_finalized.is_connected(_change_callable):
		EventBus.change_finalized.disconnect(_change_callable)
	_change_callable = Callable()
	if _fallback_tween and _fallback_tween.is_valid():
		_fallback_tween.kill()
	_fallback_tween = null
	_start_leaving()


func _start_leaving() -> void:
	state = CustomerState.LEAVING
	_engaged_with_player = false
	_engaged_player = null
	_hide_order_bubble()
	_npc.stop_payment_pose()
	var cp_name: String = _npc.get_cash_point_name()
	var cp := _npc.get_node_or_null(cp_name + "/CashPickup") as CashPickup
	if cp:
		cp.visible = false
	_npc.play_anim("Walk")
	EventBus.customer_left.emit(self, _outcome)


static func _customer_payment(price: float) -> float:
	## Customer pays with smallest bill that covers the price.
	if price <= 1.0:
		return 1.0
	if price <= 5.0:
		return 5.0
	return 10.0


func _on_debug_force_happy() -> void:
	if state == CustomerState.WAITING:
		_resolve("happy")


func step_forward(new_pos: Vector3) -> void:
	## Called by the spawner when a closer queue slot opens up.
	_is_rotating_to_face = false # cancel any in-progress facing rotation
	if state == CustomerState.WALKING:
		queue_position = new_pos # redirect mid-walk to the closer spot
	elif state == CustomerState.WAITING:
		queue_position = new_pos
		state = CustomerState.WALKING
		_npc.play_anim("Walk")


## Called by CustomerSpawner when spawning a pedestrian-converted customer.
## Skips the walk-in phase — customer is already at the slot position.
func start_waiting() -> void:
	state = CustomerState.WAITING
	_begin_smooth_facing()
	_default_facing_target = _facing_target
	_npc.play_anim("Idle")
	EventBus.customer_arrived.emit(self)


func show_order_to_player(player: Node) -> void:
	## Called when the player clicks this customer with empty hands.
	if state != CustomerState.WAITING:
		return
	var was_already_engaged := _engaged_with_player
	_engaged_with_player = true
	_engaged_player = player
	_show_order()
	if not was_already_engaged:
		_npc.play_anim("Talk")
	_facing_target = Basis.looking_at(
		player.global_position - global_position,
		Vector3.UP,
	)
	_is_rotating_to_face = true


func _disengage_player() -> void:
	_engaged_with_player = false
	_engaged_player = null
	_npc.play_anim("Idle")
	_facing_target = _default_facing_target
	_is_rotating_to_face = true


func set_route_continuation(waypoints: Array[PedestrianWaypoint], next_index: int) -> void:
	_leave_waypoints = waypoints
	_leave_waypoint_idx = next_index


func _begin_smooth_facing() -> void:
	## Slot 0 is the active customer — they face the counter.
	## All others face toward the front of the queue.
	if queue_slot == 0:
		_facing_target = Basis.looking_at(counter_face_dir, Vector3.UP)
	else:
		_facing_target = Basis.looking_at(queue_face_dir, Vector3.UP)
	_is_rotating_to_face = true


func _refresh_patience_bar(ratio: float) -> void:
	if _patience_progress == null:
		return
	_patience_progress.value = ratio * _patience_progress.max_value


func _show_order() -> void:
	order_label.text = "One cup %s" % expected_fruit.capitalize()
	order_label.visible = true
	if _order_panel:
		_order_panel.visible = false
		call_deferred("_resize_order_panel")


func _resize_order_panel() -> void:
	if _order_panel == null or not is_instance_valid(order_label):
		return
	var aabb_size := order_label.get_aabb().size
	var font := order_label.font if order_label.font else ThemeDB.fallback_font
	var text_height := font.get_height(order_label.font_size) * order_label.pixel_size
	var pad := Vector2(0.05, 0.035)
	var panel_size := Vector2(
		aabb_size.x + pad.x,
		text_height + pad.y
	)
	var panel_px := Vector2i(
		int(panel_size.x / _order_panel.pixel_size),
		int(panel_size.y / _order_panel.pixel_size)
	)
	panel_px.x = maxi(panel_px.x, 32)
	panel_px.y = maxi(panel_px.y, 32)
	var corner_px := clampi(int(mini(panel_px.x, panel_px.y) * 0.15), 8, 32)
	var panel_color := Color(0.20, 0.22, 0.24, 0.88)
	_order_panel.texture = _create_rounded_panel_texture(
		panel_px.x, panel_px.y, panel_color, corner_px
	)
	_order_panel.scale = Vector3(1, 1, 1)
	_order_panel.visible = true


func _create_rounded_panel_texture(
	width: int, height: int, color: Color, corner: int
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


func _hide_order_bubble() -> void:
	if _order_panel:
		_order_panel.visible = false
	if order_label:
		order_label.visible = false


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
	emoji_anchor.add_child(_order_panel)
	emoji_anchor.move_child(order_label, -1)

	order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	order_label.no_depth_test = true
	order_label.pixel_size = 0.0008
	order_label.font_size = 80
	order_label.outline_size = 8
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	order_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	order_label.width = 0
	order_label.sorting_offset = 1.0
	order_label.modulate = Color(1, 1, 1, 1)
	order_label.outline_size = 4
	order_label.position = Vector3(0, -0.65, 0)
	order_label.visible = false


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


func _create_white_texture(size: int = 4) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _create_ring_texture(size: int = 128, inner_ratio: float = 0.65) -> ImageTexture:
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
