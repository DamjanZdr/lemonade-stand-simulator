class_name Customer
extends CharacterBody3D
## Runtime-spawned NPC. Walks to queue spot, waits, receives/rejects lemonade, leaves.

enum CustomerState {
	WALKING,
	WAITING,
	RECEIVING,
	REACTING,
	LEAVING,
}

const GRAVITY: float = 9.8

var queue_position: Vector3 = Vector3.ZERO
var queue_slot: int = 0 # 0 = active (faces counter), 1+ = queued (faces front of queue)
var queue_face_dir: Vector3 = Vector3(1, 0, 0) # set by spawner
var counter_face_dir: Vector3 = Vector3(0, 0, 1) # set by spawner
var patience_max: float = Balancing.PATIENCE_BASE
var patience: float = 0.0
var _order_taken: bool = false
var serve_patience_max: float = Balancing.PATIENCE_BASE
var state: CustomerState = CustomerState.WALKING
## Stun timer: when > 0, the customer stops moving (hit by trash).
var _stun_timer: float = 0.0
## Remaining order: fruit_type -> cups still needed. Set by the spawner
## before the customer engages; mutated as the price-check removes items
## and as cups are correctly served.
var order: Dictionary = { }
## Which stand this customer is queued at / buying from. Set by the
## CustomerSpawner that spawned this customer. Used to credit payment to
## the correct stand instead of a single shared pot once there's more than
## one stand in the world.
var stand: StandUnit = null


## Price for a fruit type, from this customer's own stand if known,
## falling back to the global GameState price otherwise (e.g. for
## debug-spawned customers with no stand assigned).
func _get_price(fruit_type: String) -> float:
	if stand:
		return stand.get_price(fruit_type)
	return GameState.get_price(fruit_type)
## True once the one-time price-check reaction has run for this visit.


var _price_checked: bool = false
## True while the price-check's sequence of "too expensive"/"so cheap"
## messages is being shown, to block serving/re-triggering.
var _price_checking: bool = false
## Sum of the price paid for each correctly-matched cup served so far.
var _accumulated_price: float = 0.0
## First quality complaint hit across all correctly-served cups (e.g.
## too_sweet); empty string means everything served was spot-on so far.
var _best_complaint: String = ""
var _outcome: String = ""
var _waiting_for_change: bool = false
var _change_callable: Callable = Callable()
var _change_due_cents: int = 0
var _last_tendered_cents: int = 0
## What the customer handed over (in dollars), shown alongside how much is
## still owed while the player makes change.
var _payment_amount: float = 0.0
var _feedback_text: String = ""
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
var _pending_disengage: bool = false
var _talk_anim_playing: bool = false

@onready var emoji_anchor: Node3D = $EmojiAnchor
@onready var emoji_display: Node = $EmojiAnchor/EmojiDisplay
@onready var order_label: Label3D = $EmojiAnchor/OrderLabel
@onready var _npc: Node3D = $NPCBody

var _ui_layer: CanvasLayer = null
var _ui_label: Label = null
var _ui_panel: Panel = null

var _patience_circle: Sprite3D = null
var _patience_progress: TextureProgressBar = null
var _last_patience_percent: int = -1

var _preserve_appearance: bool = false

## Set by WorldSync spawn state before _ready(). Forwarded to NPCBody
## so all peers see the same hair/clothing/gender.
var appearance_seed: int = 0


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
	var bonus: float = 1.0 + sunroof_bonus
	serve_patience_max = Balancing.PATIENCE_BASE * bonus # Phase 2
	patience_max = Balancing.PATIENCE_BASE * bonus * 0.5 # Phase 1
	patience = patience_max
	EventBus.debug_force_happy_serve.connect(_on_debug_force_happy)
	if not _preserve_appearance:
		if appearance_seed != 0:
			_npc.appearance_seed = appearance_seed
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
	add_to_group("customers")
	_ignore_pedestrian_collisions()
	# Clients don't need collision — positions are synced from host.
	# Disabling collision shapes saves physics processing on clients.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_disable_collision()


func _process(_delta: float) -> void:
	if _ui_label != null and _ui_label.visible:
		_update_bubble_screen_pos()


func _physics_process(delta: float) -> void:
	# Server-authoritative: only the host runs customer simulation.
	# Clients interpolate toward synced positions.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_physics_client_interpolate(delta)
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if _is_rotating_to_face:
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(_facing_target.get_rotation_quaternion(), t)
		basis = Basis(q)
		if q.dot(_facing_target.get_rotation_quaternion()) > 0.999:
			basis = _facing_target
			_is_rotating_to_face = false

	# Tick stun timer — stunned customers can't walk.
	if _stun_timer > 0.0:
		_stun_timer = maxf(_stun_timer - delta, 0.0)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

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
				sync_state(CustomerState.WAITING, "Idle")
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
					if _talk_anim_playing:
						_pending_disengage = true
					else:
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
					WorldSync.despawn_networked(self)
			elif _leave_waypoint_idx >= _leave_waypoints.size():
				WorldSync.despawn_networked(self)
			else:
				var target := _leave_waypoints[_leave_waypoint_idx].global_position
				_walk_toward(target, delta)
				if global_position.distance_to(target) < 0.55:
					_leave_waypoint_idx += 1
					if _leave_waypoint_idx >= _leave_waypoints.size():
						WorldSync.despawn_networked(self)

	_apply_motion(delta)


func _apply_motion(delta: float) -> void:
	# Only walking/leaving customers need collision/floor snap. While waiting/receiving/reacting
	# the customer is stationary (velocity = 0), so just translate.
	match state:
		CustomerState.WAITING, CustomerState.RECEIVING, CustomerState.REACTING:
			velocity.y = 0.0
			global_position += velocity * delta
		_:
			move_and_slide()


## Stun the customer for duration seconds (host-authoritative).
## Called when hit by thrown trash.
func stun(duration: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_stun_timer = maxf(_stun_timer, duration)


func _walk_toward(target: Vector3, delta: float) -> void:
	var dir := (target - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * Balancing.CUSTOMER_WALK_SPEED
	velocity.z = dir.z * Balancing.CUSTOMER_WALK_SPEED
	if dir.length_squared() > 0.01:
		var target_basis := Basis.looking_at(dir, Vector3.UP)
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), t)
		basis = Basis(q)


# ── Client-side interpolation (server-authoritative) ─────────────────────────
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_rot: Vector3 = Vector3.ZERO
var _has_net_target: bool = false
const _NET_LERP_SPEED: float = 12.0


func _physics_client_interpolate(delta: float) -> void:
	if _is_rotating_to_face:
		var t := minf(delta * _ROTATION_SPEED, 1.0)
		var q := basis.get_rotation_quaternion().slerp(_facing_target.get_rotation_quaternion(), t)
		basis = Basis(q)
		if q.dot(_facing_target.get_rotation_quaternion()) > 0.999:
			basis = _facing_target
			_is_rotating_to_face = false
	if _has_net_target:
		var t := clampf(_NET_LERP_SPEED * delta, 0.0, 1.0)
		global_position = global_position.lerp(_net_target_pos, t)
		var curr_q := basis.get_rotation_quaternion()
		var target_q := Quaternion.from_euler(_net_target_rot)
		basis = Basis(curr_q.slerp(target_q, t))


func net_set_target(pos: Vector3, rot: Vector3) -> void:
	_net_target_pos = pos
	_net_target_rot = rot
	_has_net_target = true


## Host: sync a state change + animation to clients.
## Called when the host changes the customer's state (WALKING→WAITING, etc.)
func sync_state(new_state: int, anim: String) -> void:
	_sync_state.rpc(new_state, anim)


@rpc("authority", "call_local", "reliable")
func _sync_state(new_state: int, anim: String) -> void:
	if multiplayer.is_server():
		return
	state = new_state as CustomerState
	_npc.play_anim(anim)


## Host: sync the engaged (talking + facing) state to clients.
func sync_engaged(player_pos: Vector3) -> void:
	_sync_engaged.rpc(player_pos)


@rpc("authority", "call_local", "reliable")
func _sync_engaged(player_pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	_npc.play_anim("Talk")
	_facing_target = Basis.looking_at(player_pos - global_position, Vector3.UP)
	_is_rotating_to_face = true


## Client → host: request to show order to this customer.
## The host processes it and syncs the state change back to all clients.
func request_show_order(peer_id: int) -> void:
	if multiplayer.is_server():
		var player := _find_player_by_peer(peer_id)
		if player != null:
			show_order_to_player(player)
	else:
		_request_show_order.rpc_id(1, peer_id)


@rpc("any_peer", "reliable")
func _request_show_order(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := _find_player_by_peer(peer_id)
	if player != null:
		show_order_to_player(player)


## Client → host: request to serve a filled cup to this customer.
func request_serve(peer_id: int, recipe: Dictionary) -> void:
	if multiplayer.is_server():
		var player := _find_player_by_peer(peer_id)
		if player != null:
			player.held_item_data["recipe"] = recipe
			try_serve(player)
	else:
		_request_serve.rpc_id(1, peer_id, recipe)


@rpc("any_peer", "reliable")
func _request_serve(peer_id: int, recipe: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var player := _find_player_by_peer(peer_id)
	if player != null:
		player.held_item_data["recipe"] = recipe
		try_serve(player)


## Find a player node by peer ID. Players are named by peer ID under Players/.
func _find_player_by_peer(peer_id: int) -> Node:
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null(str(peer_id))


func try_serve(player: Node) -> void:
	## Called when the player (holding CUP_FILLED) clicks this customer.
	if state != CustomerState.WAITING:
		return
	if patience <= 0.0:
		return
	var p := player as Player
	if p == null or p.held_item != HeldItem.CUP_FILLED:
		return
	if stand != null and not stand.can_be_served_by(p):
		# Real multiplayer only: this customer belongs to a different
		# stand than the one this player is assigned to. Silently ignore
		# — solo/offline play is unaffected (can_be_served_by always
		# returns true there).
		return

	if not _price_checked:
		# They haven't reacted to the prices yet — do that first instead of
		# accepting a cup blind.
		if not _order_taken:
			_order_taken = true
			patience_max = serve_patience_max
			patience = patience_max
			_refresh_patience_bar(1.0)
		_run_price_check_and_show_order()
		return
	if _price_checking or order.is_empty():
		return

	var recipe: Dictionary = p.held_item_data.get("recipe", { })
	var fruit_type: String = recipe.get("fruit_type", "")

	if not order.has(fruit_type) or order[fruit_type] <= 0:
		# Wrong item: doesn't count toward the order, and the cup is wasted.
		p.inventory.clear_held()
		_reject_wrong_item(fruit_type)
		return

	p.inventory.clear_held()
	var result := RecipeEvaluator.evaluate_detailed(recipe, GameState.temperature, fruit_type)
	if _best_complaint == "" and not result.complaints.is_empty():
		_best_complaint = result.complaints[0]
	_accumulated_price += _get_price(fruit_type)
	order[fruit_type] -= 1
	if order[fruit_type] <= 0:
		order.erase(fruit_type)

	if not order.is_empty():
		# Still waiting on more cups — stay put and refresh what's left.
		_show_order()
		return

	var outcome := "happy" if _best_complaint == "" else _best_complaint
	_engaged_with_player = false
	_engaged_player = null
	_hide_order_bubble()
	_resolve(outcome)


func force_timeout() -> void:
	## Called by DayManager / spawner when day ends.
	_resolve("timeout")


func _resolve(outcome: String) -> void:
	_outcome = outcome
	state = CustomerState.REACTING
	_npc.play_anim("Talk")
	sync_state(CustomerState.REACTING, "Talk")
	# Explicitly route popularity/stats to whichever stand this customer
	# actually belongs to (see the money routing note below for why
	# GameState no longer listens to this signal globally).
	if stand != null and not stand.is_legacy_primary:
		stand.request_customer_served(outcome)
	else:
		GameState.on_customer_served(self, outcome)
	EventBus.customer_served.emit(self, outcome)
	_feedback_text = _feedback_for_outcome(outcome)
	# Only pay for cups actually received — a customer who never got a single
	# correctly-ordered cup (timeout, or everything priced them out) pays
	# nothing.
	if outcome != "timeout" and _accumulated_price > 0.0:
		# The money controller on the player's camera handles change-making.
		var price := _accumulated_price
		var payment := _customer_payment(price)
		var change_due := roundf((payment - price) * 100.0) / 100.0
		_npc.start_payment_pose(_npc.global_position + Vector3(0, 1.0, 0.5))
		_payment_amount = payment
		_change_due_cents = roundi(change_due * 100.0)
		_last_tendered_cents = 0
		EventBus.change_tendered_updated.connect(_on_change_tendered)
		EventBus.sale_initiated.emit(payment, change_due)
		_waiting_for_change = true
		_change_callable = func(earned: float):
			# Explicitly route the money to whichever stand this sale was
			# actually for. GameState no longer listens to change_finalized
			# globally (that would credit every stand's sale into the same
			# pot) — this is now the single place a sale's money is
			# credited, one way or the other.
			if stand != null and not stand.is_legacy_primary:
				stand.request_add_money(earned)
			else:
				GameState.add_money(earned)
			_leave_after_change()
		EventBus.change_finalized.connect(_change_callable, CONNECT_ONE_SHOT)
		# Fallback: give up after 60 s if the player ignores the money.
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
	# Clean up: disconnect signals if still connected, kill fallback tween.
	if _change_callable.is_valid() and EventBus.change_finalized.is_connected(_change_callable):
		EventBus.change_finalized.disconnect(_change_callable)
	_change_callable = Callable()
	if EventBus.change_tendered_updated.is_connected(_on_change_tendered):
		EventBus.change_tendered_updated.disconnect(_on_change_tendered)
	if _fallback_tween and _fallback_tween.is_valid():
		_fallback_tween.kill()
	_fallback_tween = null
	# Only linger with feedback if the player actually completed the change.
	if _last_tendered_cents >= _change_due_cents and _change_due_cents >= 0:
		_show_feedback_then_leave()
	else:
		_start_leaving()


func _start_leaving() -> void:
	state = CustomerState.LEAVING
	_engaged_with_player = false
	_engaged_player = null
	_hide_order_bubble()
	_npc.stop_payment_pose()
	_npc.play_anim("Walk")
	EventBus.customer_left.emit(self, _outcome)
	sync_state(CustomerState.LEAVING, "Walk")


static func _customer_payment(price: float) -> float:
	## Customer pays 10%-100% more than the price, made up of a combination
	## of real denominations (like handing over a mix of bills/coins) so any
	## markup amount in that range is achievable — not just whichever single
	## bill happens to be closest, which for low prices (e.g. a $1 item,
	## with no denomination between $1 and $5) used to collapse to "pays
	## exactly the price, no change owed" far too often.
	const DENOMS: Array[int] = [1000, 500, 100, 50, 10, 5] # largest first
	var price_cents := roundi(price * 100.0)
	var min_cents := price_cents + int(float(price_cents) * 0.1)
	var max_cents := price_cents + int(float(price_cents) * 1.0)
	if max_cents <= min_cents:
		max_cents = min_cents + DENOMS[-1]
	var target := randi_range(min_cents, max_cents)
	# Greedily build the payment up to (not exceeding) the target out of
	# real denominations, largest first — same idea as making change.
	var best := 0
	for d in DENOMS:
		while best + d <= target:
			best += d
	# Ensure payment covers the price (rare edge case: very cheap items
	# where even the smallest denomination overshoots the 10%-100% target).
	# Pick the smallest single denomination that's still >= price_cents —
	# DENOMS is largest-first, so scan it in reverse (ascending) order.
	if best < price_cents:
		var ascending := DENOMS.duplicate()
		ascending.reverse()
		for d in ascending:
			if d >= price_cents:
				best = d
				break
	return float(best) / 100.0


func _on_change_tendered(tendered_cents: int, _due_cents: int) -> void:
	_last_tendered_cents = tendered_cents
	var remaining := _change_due_cents - tendered_cents
	if remaining > 0:
		_set_order_text(
			"I gave you $%.2f. You still owe me $%.2f" % [_payment_amount, remaining / 100.0]
		)
	else:
		_set_order_text("Thank you!")


func _show_feedback_then_leave() -> void:
	_npc.stop_payment_pose()
	# Hide the hand-held cash pickup on the NPC if it's still visible.
	for cp_name: String in ["CashPoint/CashPickup", "CashPoint2/CashPickup"]:
		var cp := _npc.get_node_or_null(cp_name) as CashPickup
		if cp:
			cp.visible = false
	if _feedback_text != "":
		_npc.play_anim("Talk")
		_set_order_text(_feedback_text)
		await get_tree().create_timer(3.0).timeout
	_start_leaving() # switches to the Walk animation itself


func _feedback_for_outcome(outcome: String) -> String:
	match outcome:
		"happy":
			return "Delicious!"
		"too_strong":
			return "Too strong."
		"not_enough_fruit":
			return "Not enough fruit."
		"too_sweet":
			return "Too sweet."
		"not_sweet_enough":
			return "Not sweet enough."
		"too_cold":
			return "Too cold."
		"not_cold_enough":
			return "Not cold enough."
		"too_expensive":
			return "Too expensive."
		"wrong_order":
			return "That's not what I ordered."
		_:
			return ""


func _on_debug_force_happy() -> void:
	if state != CustomerState.WAITING:
		return
	# Simulate paying for whatever's left in the order, skipping the price
	# check/serving flow entirely — this is a debug shortcut.
	for fruit_type: String in order.keys():
		_accumulated_price += _get_price(fruit_type) * order[fruit_type]
	order.clear()
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
	if stand != null and not stand.can_be_served_by(player):
		return
	var was_already_engaged := _engaged_with_player
	_engaged_with_player = true
	_engaged_player = player
	if not _price_checked:
		_run_price_check_and_show_order()
	elif not _price_checking:
		_show_order()
	if not was_already_engaged:
		_npc.play_anim("Talk")
		_talk_anim_playing = true
		# Connect to animation finished to know when Talk ends
		if not _npc.anim_player.is_connected("animation_finished", _on_talk_finished):
			_npc.anim_player.connect("animation_finished", _on_talk_finished)
	_facing_target = Basis.looking_at(player.global_position - global_position, Vector3.UP)
	_is_rotating_to_face = true
	# Sync Talk animation + facing to clients
	sync_engaged(player.global_position)
	# Reset patience for phase 2: waiting to be served
	if not _order_taken:
		_order_taken = true
		patience_max = serve_patience_max
		patience = patience_max
		_refresh_patience_bar(1.0)


func _disengage_player() -> void:
	_engaged_with_player = false
	_engaged_player = null
	_pending_disengage = false
	_npc.play_anim("Idle")
	_facing_target = _default_facing_target
	_is_rotating_to_face = true


func _on_talk_finished(anim_name: String) -> void:
	if anim_name == "Talk":
		_talk_anim_playing = false
		if _pending_disengage:
			_disengage_player()


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
	var percent := int(ratio * 100.0)
	if percent == _last_patience_percent:
		return
	_last_patience_percent = percent
	_patience_progress.value = ratio * _patience_progress.max_value


## Host: sync patience ratio to clients so they see the meter deplete.
func sync_patience(ratio: float) -> void:
	_sync_patience.rpc(ratio)


@rpc("authority", "call_local", "reliable")
func _sync_patience(ratio: float) -> void:
	if multiplayer.is_server():
		return
	if _patience_progress != null:
		_patience_progress.value = ratio * _patience_progress.max_value
	_last_patience_percent = int(ratio * 100.0)


func _set_order_text(text: String) -> void:
	if _ui_label == null:
		return
	_ui_label.text = text
	_ui_label.visible = true
	if _ui_panel:
		# Resize synchronously rather than deferring: _process() runs
		# _update_bubble_screen_pos() every frame while the label is visible,
		# and it forces the panel visible again using whatever size it has
		# *right now* — deferring the resize left a 1-frame window where that
		# happened with the stale (pre-update) size, which also contributed
		# to the panel/text looking misaligned right after the text changed.
		_resize_order_panel()


func _update_bubble_screen_pos() -> void:
	if _ui_panel == null or emoji_anchor == null:
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


func _show_order() -> void:
	if order.is_empty():
		_set_order_text("")
		sync_show_order("")
		return
	var parts: Array[String] = []
	for fruit_type: String in order.keys():
		var qty: int = order[fruit_type]
		parts.append("%d %s" % [qty, fruit_type.capitalize()])
	var text := ", ".join(parts)
	_set_order_text(text)
	sync_show_order(text)


## Host: sync the order bubble text to clients so they see it too.
func sync_show_order(text: String) -> void:
	_sync_show_order.rpc(text)


@rpc("authority", "call_local", "reliable")
func _sync_show_order(text: String) -> void:
	if multiplayer.is_server():
		return
	if text == "":
		# Hide directly — do NOT call _hide_order_bubble() because that
		# would call sync_show_order("") again → infinite recursion
		if _ui_panel:
			_ui_panel.visible = false
		if _ui_label:
			_ui_label.visible = false
	else:
		_set_order_text(text)


func _run_price_check_and_show_order() -> void:
	## Runs once per visit, before the order is ever shown. Each fruit type
	## in the order is compared against its "ideal" base price; the further
	## the current price is from that, the higher the chance the customer
	## reacts (dropping that fruit if it's too expensive, or just commenting
	## if it's a steal). Reacted-to fruits are shown one at a time for 3s.
	if _price_checked:
		if not _price_checking:
			_show_order()
		return
	_price_checked = true
	_price_checking = true

	var messages: Array[String] = []
	for fruit_type: String in order.keys().duplicate():
		var price := _get_price(fruit_type)
		var base := RecipeEvaluator.get_base_price(fruit_type)
		if base <= 0.0:
			continue
		var deviation := (price - base) / base
		if deviation > 0.0:
			if randf() < clampf(deviation, 0.0, 1.0):
				messages.append("The %s is too expensive!" % fruit_type.capitalize())
				order.erase(fruit_type)
		elif deviation < 0.0:
			if randf() < clampf(-deviation, 0.0, 1.0):
				messages.append("Wow, %s is so cheap!" % fruit_type.capitalize())

	for msg: String in messages:
		if not is_inside_tree():
			return
		_npc.play_anim("Talk")
		_set_order_text(msg)
		await get_tree().create_timer(3.0).timeout

	_price_checking = false
	if not is_inside_tree():
		return
	if order.is_empty():
		_resolve("too_expensive") # will switch to the Walk animation itself
		return
	_npc.play_anim("Idle")
	_show_order()


func _reject_wrong_item(fruit_type: String) -> void:
	## Serving something the customer didn't ask for: doesn't count toward
	## the order, doesn't cost them anything either — just a brief callout,
	## then back to waiting on whatever's still left.
	state = CustomerState.RECEIVING
	var label := fruit_type.capitalize() if fruit_type != "" else "that"
	_npc.play_anim("Talk")
	sync_state(CustomerState.RECEIVING, "Talk")
	_set_order_text("I didn't ask for %s!" % label)
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	state = CustomerState.WAITING
	_npc.play_anim("Idle")
	sync_state(CustomerState.WAITING, "Idle")
	_show_order()


func _resize_order_panel() -> void:
	if _ui_panel == null or _ui_label == null:
		return
	var label_size := _ui_label.get_combined_minimum_size()
	var pad := Vector2(8, 4)
	_ui_panel.size = label_size + pad * 2
	_ui_label.position = pad
	# The label's own size never got updated here, so as the text got shorter
	# (e.g. an item removed from the order) it kept centering within its old,
	# stale bounds instead of the new (smaller) panel — causing the text to
	# drift out of alignment with the panel around it.
	_ui_label.size = label_size
	_ui_panel.visible = true


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


func _hide_order_bubble() -> void:
	if _ui_panel:
		_ui_panel.visible = false
	if _ui_label:
		_ui_label.visible = false
	sync_show_order("")


func _build_order_bubble() -> void:
	# Hide the scene's Label3D — we use a CanvasLayer-based label instead
	# so the text renders above the outline overlay (CanvasLayer layer=100).
	order_label.visible = false

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


func _ignore_pedestrian_collisions() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var other := node as CollisionObject3D
		if other == null or not is_instance_valid(other):
			continue
		PhysicsServer3D.body_add_collision_exception(get_rid(), other.get_rid())
		PhysicsServer3D.body_add_collision_exception(other.get_rid(), get_rid())


## Disables physics collision on clients while keeping collision shapes
## enabled for raycast interaction (highlighting, talking to NPCs).
## Called on clients since NPC positions are synced from the host.
func _disable_collision() -> void:
	# Remove from all collision layers/masks so the body doesn't
	# physically collide with anything, but keep the shape enabled
	# so raycasts can still hit it for interaction.
	collision_layer = 0
	collision_mask = 0


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


static var _ui_tonemap_shader: Shader


static func get_ui_tonemap_shader() -> Shader:
	if _ui_tonemap_shader == null:
		_ui_tonemap_shader = Shader.new()
		_ui_tonemap_shader.code = (
			"shader_type spatial;\n" + "render_mode unshaded, cull_disabled;\n"
			+ "uniform sampler2D tex;\n" + "uniform float boost = 1.0;\n"
			+ "void fragment() {\n" + "\tvec4 c = texture(tex, UV);\n"
			+ "\tALBEDO = c.rgb * boost;\n" + "\tALPHA = c.a;\n" + "}\n"
		)
	return _ui_tonemap_shader


func _apply_ui_tonemap_comp(sprite: Sprite3D, exposure: float = 1.0) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = get_ui_tonemap_shader()
	mat.set_shader_parameter("tex", sprite.texture)
	mat.set_shader_parameter("boost", 1.0 / exposure)
	sprite.material_override = mat
