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
var _outcome: String = ""
var _waiting_for_change: bool = false
var _change_callable: Callable = Callable()
var _fallback_tween: Tween = null
var _facing_target: Basis = Basis.IDENTITY
var _is_rotating_to_face: bool = false
const _ROTATION_SPEED: float = 10.0

@onready var patience_bar: MeshInstance3D = $PatienceBar
@onready var patience_bar_bg: MeshInstance3D = $PatienceBarBG
@onready var emoji_anchor: Node3D = $EmojiAnchor
@onready var emoji_display: Node = $EmojiAnchor/EmojiDisplay
@onready var _npc: Node3D = $NPCBody

var _preserve_appearance: bool = false


func preserve_appearance() -> void:
	_preserve_appearance = true


func _ready() -> void:
	floor_snap_length = 0.2
	var sunroof_bonus: float = UpgradeManager.get_effect_total("sunroof")
	if sunroof_bonus > 0.0:
		patience_max *= (1.0 + sunroof_bonus)
	patience = patience_max
	EventBus.debug_force_happy_serve.connect(_on_debug_force_happy)
	if not _preserve_appearance:
		_npc.randomize_appearance()
	_npc.play_anim("Walk")
	_refresh_patience_bar(1.0)
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
				EventBus.customer_arrived.emit(self)
		CustomerState.WAITING:
			patience -= delta
			var ratio := patience / patience_max
			_refresh_patience_bar(ratio)
			EventBus.customer_patience_changed.emit(self, ratio)
			if patience <= 0.0:
				_resolve("timeout")
		CustomerState.LEAVING:
			_walk_toward(
				Vector3(
					global_position.x,
					global_position.y,
					Balancing.CUSTOMER_DESPAWN_Z,
				),
				delta,
			)
			if global_position.z <= Balancing.CUSTOMER_DESPAWN_Z:
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
	var wait_ratio := patience / patience_max
	## Currently all customers order lemon; multi-fruit shop not yet implemented.
	var expected_fruit := "lemon"
	var outcome := RecipeEvaluator.evaluate(
		recipe,
		GameState.temperature,
		GameState.current_price,
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
		var payment := _customer_payment(GameState.current_price)
		var change_due := roundf((payment - GameState.current_price) * 100.0) / 100.0
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
	_npc.play_anim("Idle")
	EventBus.customer_arrived.emit(self)


func _begin_smooth_facing() -> void:
	## Slot 0 is the active customer — they face the counter.
	## All others face toward the front of the queue.
	if queue_slot == 0:
		_facing_target = Basis.looking_at(counter_face_dir, Vector3.UP)
	else:
		_facing_target = Basis.looking_at(queue_face_dir, Vector3.UP)
	_is_rotating_to_face = true


func _refresh_patience_bar(ratio: float) -> void:
	patience_bar.scale.x = maxf(ratio, 0.001)
	var mat := patience_bar.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		patience_bar.material_override = mat
	mat.albedo_color = Color(1.0 - ratio, ratio, 0.0, 1)
