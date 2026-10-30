class_name Assistant
extends CharacterBody3D
## Hired helper NPC — one per purchased "assistant" upgrade node on the
## owning stand. Spawned by StandUnit at DAY start, removed at EVENING.
##
## Flow: unpaid → player clicks → pays the daily wage → assigns a role:
##   "server"  — takes orders, fills cups from a pitcher, serves them
##               (payment auto-accepts — no change minigame).
##   "brewer"  — builds pitchers from a 6-slot fruit queue (loop/one-shot).
##   "stocker" — restocks low containers from matching supply boxes.
##   "cleaner" — picks up empty boxes + street trash into the trashcan.
##
## Everything is simulated by walk-to-marker + fixed waits — no real
## animations or process states. Host runs the sim; clients interpolate.

signal state_changed

const WAGE := 1.0
const WALK_SPEED := 2.6
const ARRIVE_DIST := 0.9
const ACTION_WAIT := 1.0
const STAND_RADIUS := 30.0
const STREET_RADIUS := 70.0
const LOW_STOCK_RATIO := 0.3
const MAX_STAGED_CUPS := 16
const SYNC_INTERVAL := 0.1
const NET_LERP_SPEED := 12.0
const NET_STALE_MSEC := 8000
const ROLES: Array[String] = ["server", "brewer", "stocker", "cleaner"]

var assigned_stand: StandUnit = null
var stand_name: String = ""
var assistant_index: int = 0
var appearance_seed: int = 0

var wage_paid := false
var role := ""
var brewer_queue: Array = [] # [{fruit: String, qty: int}]
var brewer_loop := true

@onready var _npc = $NPCBody

var _home_pos := Vector3.ZERO
var _steps: Array = []
var _wait_left := 0.0
var _step_wait := 0.0
var _moving := false
var _step_target := Vector3.ZERO
var _step_target_node: Node3D = null
var _step_workstation: Workstation = null
var _step_access_marker: Marker3D = null
var _step_act: Callable = Callable()
var _brewer_idx := 0
var _carried: Node3D = null
var _carried_pitcher: Pitcher = null
var _carried_refund := 0.0
var _held_recipe: Dictionary = { }
var _sync_accum := 0.0
var _last_anim := ""

# Client-side interpolation state.
var _net_target_pos := Vector3.ZERO
var _net_target_rot := Vector3.ZERO
var _has_net_target := false
var _last_net_sync_msec := 0


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _ready() -> void:
	if assigned_stand == null and stand_name != "":
		assigned_stand = OnboardingManager.find_stand(stand_name)
	if assigned_stand == null:
		var stands := get_tree().get_nodes_in_group("stand")
		if not stands.is_empty():
			assigned_stand = stands[0]
	if appearance_seed != 0:
		_npc.appearance_seed = appearance_seed
		_npc.randomize_appearance()
	# Kid proportions + higher voice — skin stays default (randomize
	# doesn't touch skin tones).
	_npc.apply_kid_proportions()
	_npc.voice_pitch += 0.3
	_npc.play_anim("Idle")
	_home_pos = global_position
	if not _is_host():
		_last_net_sync_msec = Time.get_ticks_msec()

# ── Physics ──────────────────────────────────────────────────────────


func _physics_process(delta: float) -> void:
	if not _is_host():
		_client_interpolate(delta)
		return
	_sync_accum += delta
	if _sync_accum >= SYNC_INTERVAL:
		_sync_accum = 0.0
		WorldSync.sync_transform(self, global_position, global_rotation)
	if not wage_paid or role == "":
		return
	if _moving:
		_tick_move(delta)
	elif _wait_left > 0.0:
		_wait_left -= delta
		if _wait_left <= 0.0:
			var act := _step_act
			_step_act = Callable()
			if act.is_valid():
				act.call()
			_advance()
	else:
		_advance()


func _tick_move(delta: float) -> void:
	var target := _step_target
	if _step_target_node != null:
		if not is_instance_valid(_step_target_node):
			_abort_steps()
			return
		target = _step_target_node.global_position
	if is_instance_valid(_step_access_marker):
		target = _step_access_marker.global_position
	var delta2d := target - global_position
	delta2d.y = 0.0
	var dist := delta2d.length()
	var precise_arrival := role == "server" or is_instance_valid(_step_access_marker)
	var arrive_dist := 0.05 if precise_arrival else ARRIVE_DIST
	if dist <= arrive_dist:
		_moving = false
		_wait_left = _step_wait
		if role == "server" and assigned_stand != null:
			var marker := assigned_stand.find_child("ServerSpot", true, false) as Node3D
			global_rotation.y = (
				marker.global_rotation.y
				if marker != null
				else assigned_stand \
						.global_rotation \
						.y
			) + PI
		if is_instance_valid(_step_workstation):
			var center := _step_workstation.global_position
			center.y = global_position.y
			if global_position.distance_squared_to(center) > 0.001:
				look_at(center, Vector3.UP)
		_play("Idle")
		return
	global_position += delta2d.normalized() * minf(WALK_SPEED * delta, dist)
	# Face movement direction.
	var target_basis := Basis.looking_at(delta2d.normalized(), Vector3.UP)
	var q := basis.get_rotation_quaternion().slerp(
		target_basis.get_rotation_quaternion(),
		minf(delta * 8.0, 1.0),
	)
	basis = Basis(q)
	_play("Walk")


func _advance() -> void:
	_step_workstation = null
	_step_access_marker = null
	if _steps.is_empty():
		_rebuild_steps()
	if _steps.is_empty():
		# Nothing to do — linger at the role's idle spot (servers wait at
		# the stand front so they're already near customers).
		var idle := _idle_spot()
		var idle_dist := 0.05 if role == "server" else ARRIVE_DIST * 2.0
		if global_position.distance_to(idle) > idle_dist:
			_step_target = idle
			_step_target_node = null
			_step_act = Callable()
			_step_wait = 0.5
			_moving = true
		return
	var step: Dictionary = _steps.pop_front()
	_step_target = step.get("target", global_position)
	var target_node = step.get("node", null)
	if not is_instance_valid(target_node) and typeof(target_node) == TYPE_OBJECT:
		_abort_steps()
		return
	_step_target_node = target_node
	_step_act = step.get("act", Callable())
	_step_wait = step.get("wait", ACTION_WAIT)
	if role == "server":
		_step_target = _idle_spot()
		_step_target_node = null
	elif is_instance_valid(_step_target_node):
		for node in get_tree().get_nodes_in_group("container"):
			if (
				node is Workstation and node.is_visible_in_tree()
				and node.supports_item(_step_target_node)
			):
				var marker: Marker3D = (node as Workstation).nearest_access_marker(global_position)
				if marker != null:
					_step_workstation = node
					_step_access_marker = marker
					break
	_moving = true


func _idle_spot() -> Vector3:
	if role == "server" and assigned_stand != null:
		var server_spot := assigned_stand.find_child("ServerSpot", true, false) as Node3D
		if server_spot != null:
			return Vector3(
				server_spot.global_position.x,
				global_position.y,
				server_spot.global_position.z,
			)
		# In front of the counter at ground level — customers queue here.
		var c := _counter_top_center()
		var fwd := assigned_stand.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		return Vector3(c.x, global_position.y, c.z) + fwd * 1.0
	return _home_pos


func _abort_steps() -> void:
	## A step's target node vanished mid-walk (sold, moved, despawned).
	_moving = false
	_wait_left = 0.0
	_step_act = Callable()
	_steps.clear()


func _play(anim: String) -> void:
	if _last_anim == anim:
		return
	_last_anim = anim
	_npc.play_anim(anim)

# ── Client interpolation ──────────────────────────────────────────────


func net_set_target(pos: Vector3, rot: Vector3) -> void:
	_net_target_pos = pos
	_net_target_rot = rot
	_has_net_target = true
	_last_net_sync_msec = Time.get_ticks_msec()


func _client_interpolate(delta: float) -> void:
	if Time.get_ticks_msec() - _last_net_sync_msec > NET_STALE_MSEC:
		queue_free()
		return
	if _has_net_target:
		var t := clampf(NET_LERP_SPEED * delta, 0.0, 1.0)
		global_position = global_position.lerp(_net_target_pos, t)
		var q := basis.get_rotation_quaternion().slerp(Quaternion.from_euler(_net_target_rot), t)
		basis = Basis(q)
		if global_position.distance_to(_net_target_pos) > 0.15:
			_play("Walk")
		else:
			_play("Idle")

# ── Player-facing API (pay / assign) ─────────────────────────────────


func request_pay() -> void:
	if _is_host():
		_host_pay(0)
	else:
		_rpc_pay.rpc_id(1)


func request_assign(new_role: String, queue: Array = [], loop: bool = true) -> void:
	if _is_host():
		_host_assign(new_role, queue, loop)
	else:
		_rpc_assign.rpc_id(1, new_role, queue, loop)


func _peer_owns_stand(peer_id: int) -> bool:
	if multiplayer.get_peers().is_empty():
		return true
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id:
			return p.get("assigned_stand") == assigned_stand
	return false


@rpc("any_peer", "reliable")
func _rpc_pay() -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and not _peer_owns_stand(sender):
		return
	_host_pay(sender)


func _host_pay(_sender: int) -> void:
	if wage_paid or assigned_stand == null:
		return
	if assigned_stand.spend_money(WAGE):
		wage_paid = true
		_sync_ui_state()


@rpc("any_peer", "reliable")
func _rpc_assign(new_role: String, queue: Array, loop: bool) -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and not _peer_owns_stand(sender):
		return
	_host_assign(new_role, queue, loop)


func _host_assign(new_role: String, queue: Array, loop: bool) -> void:
	if not wage_paid:
		return
	if new_role != "" and new_role not in ROLES:
		return
	role = new_role
	brewer_loop = loop
	brewer_queue.clear()
	for e in queue:
		if e is Dictionary and str(e.get("fruit", "")) != "" and int(e.get("qty", 0)) > 0:
			brewer_queue.append({ "fruit": str(e["fruit"]), "qty": clampi(int(e["qty"]), 1, 9) })
	_brewer_idx = 0
	_abort_steps()
	_sync_ui_state()


func _sync_ui_state() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_ui_state.rpc(wage_paid, role, brewer_queue, brewer_loop)
	else:
		_apply_ui_state(wage_paid, role, brewer_queue, brewer_loop)


@rpc("authority", "call_local", "reliable")
func _rpc_ui_state(paid: bool, r: String, queue: Array, loop: bool) -> void:
	_apply_ui_state(paid, r, queue, loop)


func _apply_ui_state(paid: bool, r: String, queue: Array, loop: bool) -> void:
	wage_paid = paid
	role = r
	brewer_queue = queue.duplicate(true)
	brewer_loop = loop
	state_changed.emit()

# ── Task building ────────────────────────────────────────────────────


func _rebuild_steps() -> void:
	match role:
		"cleaner":
			_build_cleaner_steps()
		"server":
			_build_server_steps()
		"stocker":
			_build_stocker_steps()
		"brewer":
			_build_brewer_steps()


func _stand_objects(group: String, radius: float = STAND_RADIUS) -> Array:
	var out: Array = []
	if assigned_stand == null:
		return out
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D and not n.is_queued_for_deletion() \
				and n.global_position.distance_to(assigned_stand.global_position) < radius:
			if role == "server" and group in ["container", "pitcher", "cup_tray"]:
				if not _on_server_counter(n):
					continue
			out.append(n)
	return out


func _on_server_counter(item: Node3D) -> bool:
	if not is_instance_valid(item) or assigned_stand == null or not item.is_visible_in_tree():
		return false
	if item is Interactable and not item.can_player_use(self):
		return false
	var counter := assigned_stand.find_child("Counter", true, false) as Node3D
	if counter == null:
		return false
	var ancestor := item.get_parent()
	while ancestor != null:
		if ancestor is WaterDispenser or ancestor is Press:
			return false
		ancestor = ancestor.get_parent()
	var bounds := AABB()
	var found := false
	for node in counter.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if not found:
		return false
	var position := item.global_position
	return (
		position.x >= bounds.position.x and position.x <= bounds.end.x
		and position.z >= bounds.position.z and position.z <= bounds.end.z
		and position.y >= bounds.end.y - 0.08 and position.y <= bounds.end.y + 0.3
	)


func _nearest(nodes: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in nodes:
		var d := global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _queue_step(target: Node3D, wait: float, act: Callable) -> void:
	if target == null:
		return
	_steps.append({ "node": target, "wait": wait, "act": act })

# ── Cleaner ──────────────────────────────────────────────────────────


func _cleaner_targets() -> Array:
	var out: Array = []
	for n in _stand_objects("supply_box"):
		if n.is_trash_box or n.quantity <= 0.0:
			out.append(n)
	for n in get_tree().get_nodes_in_group("thrown_trash"):
		if is_instance_valid(n) and assigned_stand != null \
				and n.global_position.distance_to(assigned_stand.global_position) < STREET_RADIUS:
			out.append(n)
	return out


func _build_cleaner_steps() -> void:
	var item := _nearest(_cleaner_targets()) as Node3D
	if item == null:
		return
	# Prefer the topmost target of the same pile — taking a supporting box
	# from under a stack leaves the rest hovering.
	var best_y := item.global_position.y
	for n in _cleaner_targets():
		var flat := Vector2(
			n.global_position.x - item.global_position.x,
			n.global_position.z - item.global_position.z,
		)
		if flat.length() < 1.2 and n.global_position.y > best_y:
			item = n
			best_y = n.global_position.y
	var can := _nearest(_stand_objects("trashcan")) as Node3D
	if can == null:
		return
	_queue_step(
		item,
		0.8,
		func():
			_pick_up_item(item),
	)
	_queue_step(
		can,
		0.8,
		func():
			_dispose_carried(can),
	)


func _pick_up_item(item: Node3D) -> void:
	if not is_instance_valid(item):
		return
	# Despawn on pick-up, not on drop-off — leaving a hidden supporting box
	# in place kept stacked boxes floating until the trash can was reached.
	_carried_refund = 0.0
	if item is SupplyBox:
		_carried_refund = item.trash_value
	elif "refund" in item:
		_carried_refund = item.refund
	elif item is ThrownTrash and item.has_method("get_refund"):
		_carried_refund = item.get_refund()
	_carried = item
	WorldSync.despawn_networked(item)


func _dispose_carried(can: Node3D) -> void:
	if _carried == null:
		return
	_carried = null
	if can != null and can.has_method("apply_trash_disposal"):
		can.apply_trash_disposal("trash", _carried_refund, assigned_stand.name)
	_carried_refund = 0.0

# ── Server ───────────────────────────────────────────────────────────


func _waiting_customers() -> Array:
	var out: Array = []
	for c in get_tree().get_nodes_in_group("customers"):
		if c is Customer and c.stand == assigned_stand \
				and c.state == Customer.CustomerState.WAITING:
			out.append(c)
	return out


func _find_pitcher_with(fruit_type: String) -> Pitcher:
	for n in _stand_objects("pitcher"):
		if n is Pitcher and n.get_liquid_volume() > 0.0 \
				and n.fruit_type == fruit_type:
			return n
	return null


func _nearest_cup_stack() -> CupStack:
	var best: CupStack = null
	var best_d := INF
	for n in _stand_objects("container"):
		if n is CupStack and n.current_count > 0:
			var d := global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	return best


func _build_server_steps() -> void:
	if not _held_recipe.is_empty():
		var tray := _find_tray()
		var spot := tray.free_slot_position() if tray != null else Vector3.INF
		if spot == Vector3.INF:
			spot = _find_free_counter_spot()
		if spot != Vector3.INF:
			_place_held_cup(spot)
		return
	var cust := _nearest(_waiting_customers()) as Customer
	if cust != null:
		_build_customer_serve_steps(cust)
		return
	# No customers — stock the counter with filled cups so orders can be
	# served instantly when someone arrives.
	var staged := 0
	for n in _stand_objects("container"):
		if n is Cup and n.state == Cup.CupState.FILLED:
			staged += 1
	if staged >= MAX_STAGED_CUPS:
		return
	var spot := Vector3.INF
	var tray := _find_tray()
	if tray != null and tray.has_free_slot():
		spot = tray.free_slot_position()
	if spot == Vector3.INF:
		# No tray (or it's full) — free-scan the counter top for an open
		# spot, same overlap-probing the player's ghost preview uses.
		spot = _find_free_counter_spot()
	if spot == Vector3.INF:
		return
	var stack := _nearest_cup_stack()
	var pitcher := _first_pitcher_with_liquid()
	if stack == null or pitcher == null:
		return
	_queue_step(
		stack,
		0.6,
		func():
			_take_cup(stack),
	)
	_queue_step(
		pitcher,
		0.8,
		func():
			_fill_cup(pitcher),
	)
	_steps.append(
		{
			"target": spot,
			"wait": 0.6,
			"act": func():
				_place_held_cup(spot),
		}
	)


## Approach position for talking to / serving a customer: a point a short
## distance toward the stand, so the assistant stops in front of the queue
## instead of clipping through the stand to reach the customer's exact spot.
func _approach_point(n: Node3D) -> Vector3:
	var to := n.global_position
	var dir := to - _idle_spot()
	dir.y = 0.0
	if dir.length() < 0.01:
		return to
	return to - dir.normalized() * 0.85


## Route to a customer in two legs — via the counter-front idle spot first,
## then to the approach point — so the path goes around the stand rather
## than through it.
func _queue_customer_step(cust: Customer, wait: float, act: Callable) -> void:
	_steps.append({ "target": _idle_spot(), "wait": 0.1, "act": Callable() })
	_steps.append({ "target": _approach_point(cust), "wait": wait, "act": act })


func _build_customer_serve_steps(cust: Customer) -> void:
	if not cust.order_ready():
		# Go take the order first — show_order_to_player only needs a Node3D
		# position for facing; can_be_served_by passes via assigned_stand.
		_queue_customer_step(
			cust,
			0.8,
			func():
				cust.show_order_to_player(self),
		)
		return
	# Prefer an already-filled cup sitting on the counter.
	for ft in cust.order.keys():
		var cup := _find_filled_cup(ft)
		if cup != null:
			_queue_step(
				cup,
				0.5,
				func():
					_grab_filled_cup(cup),
			)
			_queue_customer_step(
				cust,
				1.2,
				func():
					_serve_customer(cust),
			)
			return
	# Otherwise pour a fresh one from a matching pitcher.
	var stack := _nearest_cup_stack()
	for ft in cust.order.keys():
		var pitcher := _find_pitcher_with(ft)
		if pitcher != null and stack != null:
			_queue_step(
				stack,
				0.6,
				func():
					_take_cup(stack),
			)
			_queue_step(
				pitcher,
				0.8,
				func():
					_fill_cup(pitcher),
			)
			_queue_customer_step(
				cust,
				1.2,
				func():
					_serve_customer(cust),
			)
			return


func _find_filled_cup(fruit: String) -> Cup:
	for n in _stand_objects("container"):
		if n is Cup and n.state == Cup.CupState.FILLED \
				and str(n.recipe.get("fruit_type", "")) == fruit:
			return n
	return null


## Probe the stand's counter top on a small grid and return the first
## position where a cup-sized shape doesn't overlap anything, or
## Vector3.INF when the counter is full/absent. Mirrors the player's
## ghost overlap check: a shape query against world colliders, with the
## counter's own colliders excluded so the surface itself doesn't count.
func _find_free_counter_spot(footprint: float = 0.04, height: float = 0.05) -> Vector3:
	if assigned_stand == null:
		return Vector3.INF
	var counter := assigned_stand.find_child("Counter", true, false)
	if counter == null:
		return Vector3.INF
	var aabb := AABB()
	var found := false
	for c in counter.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var wa := mi.global_transform * mi.get_aabb()
		aabb = wa if not found else aabb.merge(wa)
		found = true
	if not found:
		return Vector3.INF
	var top_y := aabb.end.y
	var shape := CylinderShape3D.new()
	shape.radius = footprint
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var exclude_rids: Array[RID] = []
	if counter is CollisionObject3D:
		exclude_rids.append((counter as CollisionObject3D).get_rid())
	for c in counter.find_children("*", "CollisionObject3D", true, false):
		exclude_rids.append((c as CollisionObject3D).get_rid())
	query.exclude = exclude_rids
	var space := get_world_3d().direct_space_state
	var center := aabb.get_center()
	var max_radius := Vector2(aabb.size.x, aabb.size.z).length() * 0.5
	var rings := ceili(max_radius / 0.08)
	for ring in range(rings + 1):
		var radius := ring * 0.08
		var samples := maxi(1, ceili(TAU * radius / 0.08))
		for sample in range(samples):
			var angle := TAU * sample / samples
			var candidate := Vector3(
				center.x + cos(angle) * radius,
				top_y,
				center.z + sin(angle) * radius,
			)
			var surface_y := INF
			var supported := true
			for point in range(17):
				var offset := Vector3.ZERO
				if point > 0:
					var perimeter_angle := TAU * (point - 1) / 16.0
					offset = Vector3(cos(perimeter_angle), 0, sin(perimeter_angle)) * footprint
				var origin := candidate + offset
				var ray := PhysicsRayQueryParameters3D.create(
					origin + Vector3.UP * 0.1,
					origin + Vector3.DOWN * aabb.size.y,
					1,
				)
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or not exclude_rids.has(hit.get("rid")):
					supported = false
					break
				var normal: Vector3 = hit["normal"]
				var position: Vector3 = hit["position"]
				if normal.y < 0.99 or (surface_y != INF and absf(position.y - surface_y) > 0.002):
					supported = false
					break
				surface_y = position.y
			if not supported:
				continue
			candidate.y = surface_y
			if _cup_spot_occupied(candidate):
				continue
			query.transform = Transform3D(Basis(), candidate + Vector3.UP * (height * 0.5 + 0.005))
			if space.intersect_shape(query, 1).is_empty():
				return candidate
	return Vector3.INF


func _find_tray() -> CupTray:
	for n in _stand_objects("cup_tray"):
		if n is CupTray:
			return n
	return null


func _first_pitcher_with_liquid() -> Pitcher:
	for n in _stand_objects("pitcher"):
		if n is Pitcher and n.get_liquid_volume() > 0.0:
			return n
	return null


func _counter_top_center() -> Vector3:
	if assigned_stand == null:
		return global_position
	var counter := assigned_stand.find_child("Counter", true, false)
	if counter == null:
		return assigned_stand.to_global(Vector3(0.0, 1.0, 1.0))
	# Real counter-top height comes from the visual mesh AABB — guessing an
	# offset floated the cups above the surface.
	var aabb := AABB()
	var found := false
	for c in counter.find_children("", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var wa := mi.global_transform * mi.get_aabb()
		aabb = wa if not found else aabb.merge(wa)
		found = true
	if not found:
		return Vector3(
			counter.global_position.x,
			counter.global_position.y + 0.55,
			counter.global_position.z,
		)
	return Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)


func _grab_filled_cup(cup: Cup) -> void:
	if not is_instance_valid(cup) or cup.state != Cup.CupState.FILLED:
		return
	if role == "server" and not _on_server_counter(cup):
		_abort_steps()
		return
	_held_recipe = cup.recipe.duplicate(true)
	WorldSync.despawn_networked(cup)


func _cup_spot_occupied(spot: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("container"):
		if not node is Cup or not is_instance_valid(node):
			continue
		var offset: Vector3 = node.global_position - spot
		if absf(offset.y) < 0.2 and Vector2(offset.x, offset.z).length() < 0.075:
			return true
	return false


func _place_held_cup(spot: Vector3) -> void:
	if _held_recipe.is_empty():
		return
	if _cup_spot_occupied(spot):
		var tray := _find_tray()
		spot = tray.free_slot_position() if tray != null else Vector3.INF
		if spot == Vector3.INF or _cup_spot_occupied(spot):
			spot = _find_free_counter_spot()
		if spot == Vector3.INF:
			return
	var cup := WorldSync.spawn_networked(
		"res://scenes/objects/cup.tscn",
		get_parent(),
		spot,
		Vector3.ZERO,
		{
			"recipe": _held_recipe.duplicate(true),
			"fill_color": _held_recipe.get("color", Color(1.0, 0.9, 0.3)),
			"state": Cup.CupState.FILLED,
			"_net_groups": ["container"],
			"_net_scale": Vector3.ONE * 0.03,
		},
	) as Cup
	if cup != null:
		cup.add_to_group("container")
		if cup.physics != null:
			cup.physics.collision_layer = 1
			cup.physics.collision_mask = 1
		_seat_cup_on(cup, spot.y)
		# The spawn broadcast carried the unseated marker position —
		# push the corrected transform so clients see the same seat.
		WorldSync.sync_move_and_show(cup, cup.global_position, cup.global_rotation, cup.scale, true)
	_held_recipe = { }


## Lift the cup so the bottom of its merged visual bounds rests on
## surface_y. The GLB pivot is mid-cup, so a raw spawn sinks it halfway
## into the tray/surface.
static func _seat_cup_on(cup: Node3D, surface_y: float) -> void:
	var found := false
	var aabb := AABB()
	for n in cup.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var wa := mi.global_transform * mi.get_aabb()
		aabb = wa if not found else aabb.merge(wa)
		found = true
	if found:
		cup.global_position.y += surface_y - aabb.position.y


func _take_cup(stack: CupStack) -> void:
	if not is_instance_valid(stack) or stack.current_count <= 0:
		return
	if role == "server" and not _on_server_counter(stack):
		_abort_steps()
		return
	stack.current_count -= 1
	stack._update_display()
	WorldSync.sync_property(stack, "current_count", stack.current_count)
	WorldSync.sync_call(stack, "_update_display")


func _fill_cup(pitcher: Pitcher) -> void:
	if not is_instance_valid(pitcher) or pitcher.get_liquid_volume() <= 0.0:
		return
	if role == "server" and not _on_server_counter(pitcher):
		_abort_steps()
		return
	_held_recipe = pitcher.pour_portion()
	# Player pours reset the drained pitcher via _fill_cup_for_player;
	# mirror that so assistant-emptied pitchers return to PREPPING and
	# can go back to the press instead of staying locked as SERVING.
	if pitcher.is_fully_empty():
		pitcher._clear_and_return()


func _serve_customer(cust: Customer) -> void:
	if not is_instance_valid(cust) or _held_recipe.is_empty():
		return
	cust.try_serve_assistant(_held_recipe)
	_held_recipe = { }

# ── Stocker ──────────────────────────────────────────────────────────


func _find_box(ingredient_type: String) -> SupplyBox:
	for n in _stand_objects("supply_box"):
		if (
			n is SupplyBox and not n.is_trash_box \
					and n.ingredient_type == ingredient_type
			and n.quantity > 0.0
		):
			return n
	return null


func _build_stocker_steps() -> void:
	for n in _stand_objects("container"):
		var itype := ""
		if n is IngredientBin \
				and n.current_amount < n.max_capacity * LOW_STOCK_RATIO:
			itype = n.ingredient_type
		elif n is FruitBin:
			for ft in GameState.FRUIT_TYPES:
				var cap: float = n._get_capacity(ft)
				if n.fruit_amounts.get(ft, 0.0) < cap * LOW_STOCK_RATIO:
					itype = ft
					break
		elif n is CupStack and n.current_count < n.max_capacity * LOW_STOCK_RATIO:
			itype = "cups"
		if itype == "":
			continue
		var box := _find_box(itype)
		if box == null:
			continue
		var qty := minf(2.0, box.quantity)
		_steps.append(
			{
				"node": box,
				"wait": ACTION_WAIT,
				"act": func():
					_take_from_box(box, qty),
			}
		)
		_steps.append(
			{
				"node": n,
				"wait": ACTION_WAIT,
				"act": func():
					_deposit_to(n, itype, qty),
			}
		)
		return


func _take_from_box(box: SupplyBox, qty: float) -> void:
	if not is_instance_valid(box):
		return
	box.quantity = maxf(0.0, box.quantity - qty)
	box.update_metrics()
	WorldSync.sync_property(box, "quantity", box.quantity)
	WorldSync.sync_call(box, "update_metrics")


func _deposit_to(container: Node3D, itype: String, qty: float) -> void:
	if not is_instance_valid(container):
		return
	if container is IngredientBin:
		container.apply_add_amount(qty)
	elif container is FruitBin:
		container.add_amount(itype, qty)
	elif container is CupStack:
		container.add_cups(int(qty))

# ── Brewer ───────────────────────────────────────────────────────────


func _find_empty_pitcher() -> Pitcher:
	for n in _stand_objects("pitcher"):
		if n is Pitcher and n.is_fully_empty() and n.cups_poured == 0:
			return n
	return null


func _find_free_press() -> Press:
	for n in _stand_objects("container"):
		if n is Press and not n.has_snapped_pitcher() and not n._pressing \
				and n.fruit_count <= 0.0:
			return n
	return null


func _find_fruit_bin(fruit_type: String) -> FruitBin:
	for n in _stand_objects("container"):
		if n is FruitBin and n.fruit_amounts.get(fruit_type, 0.0) >= 1.0:
			return n
	return null


func _find_ingredient_bin(itype: String) -> IngredientBin:
	for n in _stand_objects("container"):
		if n is IngredientBin and n.ingredient_type == itype and n.current_amount > 0.0:
			return n
	return null


func _find_water_source() -> Node3D:
	# Stand-owned fixtures first (dispenser is a StandUnit child; the tap
	# is a scene fixture and may live outside the container group).
	for node in _stand_objects("container"):
		if node is WaterDispenser and node.is_available_for_brewing():
			return node
	if assigned_stand != null:
		for n in assigned_stand.find_children("", "WaterTap", true, false):
			return n
		for n in assigned_stand.find_children("", "WaterDispenser", true, false):
			return n
	for n in _stand_objects("container"):
		if n is WaterTap or n is WaterDispenser:
			return n
	return null


func _brewer_recipe(fruit: String) -> Dictionary:
	var r: Dictionary = { }
	if assigned_stand != null:
		r = assigned_stand.recipes.get(fruit, { })
	return r


func _build_brewer_steps() -> void:
	if brewer_queue.is_empty():
		return
	if _brewer_idx >= brewer_queue.size():
		if brewer_loop:
			_brewer_idx = 0
		else:
			return # One-shot finished — idle until reassigned.
	var entry: Dictionary = brewer_queue[_brewer_idx]
	var fruit: String = entry["fruit"]
	var qty: int = entry["qty"]
	var pitcher := _find_empty_pitcher()
	var press := _find_free_press()
	if pitcher == null or press == null:
		return # No empty pitcher or free press — poll again shortly.
	var recipe := _brewer_recipe(fruit)
	var ice_amt: float = recipe.get("ice", 0.0)
	var sugar_amt: float = recipe.get("sugar", 0.0)
	var ice_bin := _find_ingredient_bin("ice") if ice_amt > 0.0 else null
	var sugar_bin := _find_ingredient_bin("sugar") if sugar_amt > 0.0 else null
	var water_src := _find_water_source()
	if water_src == null:
		return

	_queue_step(
		pitcher,
		ACTION_WAIT,
		func():
			_carry_pitcher(pitcher),
	)
	_queue_step(
		press,
		ACTION_WAIT,
		func():
			_place_pitcher_on_press(press),
	)
	# Load each fruit into the press: walk bin → press per scoop.
	for i in qty:
		var bin := _find_fruit_bin(fruit)
		if bin != null:
			_queue_step(
				bin,
				0.8,
				func():
					_take_fruit(bin, fruit),
			)
		_queue_step(
			press,
			0.6,
			func():
				_load_press_fruit(press, fruit),
		)
	# Press it — the press drains into the snapped pitcher itself. The
	# duration is known up front (press_time_per_fruit * qty) so the wait
	# step can be sized before _start_press runs.
	var press_dur := 1.5 * qty
	var data_path := "res://resources/data/" + fruit + ".tres"
	if ResourceLoader.exists(data_path):
		var data := load(data_path) as IngredientData
		if data != null:
			press_dur = data.press_time_per_fruit * qty
	_queue_step(
		press,
		0.5,
		func():
			press._start_press(),
	)
	_steps.append({ "node": press, "wait": press_dur + 1.5, "act": Callable() })
	_queue_step(
		press,
		0.2,
		func():
			_release_brewer_pitcher(press, pitcher),
	)
	_queue_step(
		water_src,
		0.5,
		func():
			if water_src is WaterDispenser:
				var dispenser := water_src as WaterDispenser
				if not dispenser.can_snap_pitcher(pitcher) or dispenser.water_fillings <= 0:
					_abort_steps()
					return
				pitcher.set_pitcher_visible(true)
				dispenser.snap_pitcher(pitcher, assigned_stand)
				dispenser.start_fill(Balancing.PITCHER_MAX_LIQUID - pitcher.get_liquid_volume())
			else:
				_fill_water(pitcher, fruit),
	)
	_queue_step(
		water_src,
		water_src.fill_time_per_pitcher + 0.5 if water_src is WaterDispenser else 2.0,
		func():
			if water_src is WaterDispenser:
				_release_brewer_pitcher(water_src, pitcher),
	)
	if sugar_bin != null:
		_queue_step(
			sugar_bin,
			0.8,
			func():
				_add_scoop(sugar_bin, pitcher, "sugar", sugar_amt),
		)
	if ice_bin != null:
		_queue_step(
			ice_bin,
			0.8,
			func():
				_add_scoop(ice_bin, pitcher, "ice", ice_amt),
		)
	_steps.append(
		{
			"target": _counter_top_center(),
			"wait": ACTION_WAIT,
			"act": func():
				_deliver_pitcher(press, pitcher),
		}
	)
	_steps.append(
		{
			"target": _home_pos,
			"wait": 0.4,
			"act": func():
				_advance_brewer(),
		}
	)


func _carry_pitcher(p: Pitcher) -> void:
	if not is_instance_valid(p):
		return
	_carried_pitcher = p
	p.set_pitcher_visible(false)


func _place_pitcher_on_press(press: Press) -> void:
	var p := _carried_pitcher
	_carried_pitcher = null
	if p == null or not is_instance_valid(p) or press == null or not is_instance_valid(press):
		return
	p.set_pitcher_visible(true)
	p.global_position = press.get_snap_global_position()
	press.snap_pitcher(p, assigned_stand)
	press.sync_snapped_pitcher()


func _take_fruit(bin: FruitBin, fruit: String) -> void:
	if is_instance_valid(bin):
		bin.take_amount(fruit, 1.0)


func _load_press_fruit(press: Press, fruit: String) -> void:
	if not is_instance_valid(press):
		return
	press.fruit_type = fruit
	press.fruit_count += 1.0
	WorldSync.sync_property(press, "fruit_type", press.fruit_type)
	WorldSync.sync_property(press, "fruit_count", press.fruit_count)


func _fill_water(pitcher: Pitcher, fruit: String) -> void:
	if not is_instance_valid(pitcher):
		return
	var recipe := _brewer_recipe(fruit)
	var want: float = recipe.get(
		"water",
		Balancing.PITCHER_MAX_LIQUID - pitcher.get_liquid_volume(),
	)
	pitcher.water = minf(pitcher.water + want, Balancing.PITCHER_MAX_LIQUID - pitcher.fruit_count)
	pitcher.update_liquid_color()
	if pitcher.fruit_count > 0.0 and pitcher.water > 0.0 \
			and pitcher.state == Pitcher.PitcherState.PREPPING:
		pitcher.state = Pitcher.PitcherState.COMPLETE
		EventBus.pitcher_state_changed.emit(int(pitcher.state))
	pitcher._sync_state_to_peers()


func _add_scoop(bin: IngredientBin, pitcher: Pitcher, itype: String, amt: float) -> void:
	if not is_instance_valid(pitcher):
		return
	var got := 0.0
	if is_instance_valid(bin):
		got = bin.apply_take_amount(amt)
		bin.sync_state_to_peers()
	if itype == "sugar":
		pitcher.sugar += got
	else:
		pitcher.ice += got
	pitcher._sync_state_to_peers()


func _release_brewer_pitcher(appliance: Node3D, pitcher: Pitcher) -> void:
	if not is_instance_valid(appliance) or not is_instance_valid(pitcher):
		_abort_steps()
		return
	if appliance.get("_snapped_pitcher") != pitcher:
		_abort_steps()
		return
	appliance.set("_snapped_pitcher", null)
	appliance.set("_pending_snap_pitcher_net_id", -1)
	WorldSync.sync_property(appliance, "_pending_snap_pitcher_net_id", -1)
	pitcher.locked_by_dispenser = false
	WorldSync.sync_property(pitcher, "locked_by_dispenser", false)
	_carry_pitcher(pitcher)


func _deliver_pitcher(press: Press, pitcher: Pitcher) -> void:
	if not is_instance_valid(pitcher):
		return
	var spot := _find_free_counter_spot(0.16, 0.35)
	if spot == Vector3.INF:
		_steps.push_front(
			{
				"target": _idle_spot(),
				"wait": 1.0,
				"act": func():
					_deliver_pitcher(press, pitcher),
			}
		)
		return
	pitcher.global_position = spot
	_seat_cup_on(pitcher, spot.y)
	_carried_pitcher = null
	pitcher.prep_position = pitcher.global_position
	pitcher.set_pitcher_visible(true)
	pitcher._sync_state_to_peers()
	WorldSync.sync_transform(pitcher, pitcher.global_position, pitcher.global_rotation)


func _advance_brewer() -> void:
	_brewer_idx += 1
