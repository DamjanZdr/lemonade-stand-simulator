extends Node
## Manages the customer queue. All organic customers arrive via pedestrian conversion.
## Direct spawning is only used by the debug force-spawn button.

const CUSTOMER_SCENE: PackedScene = preload("res://scenes/customer/customer.tscn")

var _queue_spots: Array[Vector3] = [] # set by main.tscn via set_queue_spots()
var _queue: Array = [] # active Customer nodes occupying each slot
var _queue_face_dir: Vector3 = Vector3(1, 0, 0) # direction queued customers face (toward front)
var _counter_face_dir: Vector3 = Vector3(0, 0, 1) # direction slot-0 customer faces (toward counter)
var _reserved_slots: Dictionary = { } # slot_index -> Pedestrian walking to that slot
var _queue_max_override: int = 0 # 0 = use Balancing.QUEUE_MAX


func _ready() -> void:
	EventBus.customer_left.connect(_on_customer_left)
	EventBus.debug_force_spawn_customer.connect(_on_debug_force_spawn)
	EventBus.debug_set_queue_max.connect(_on_debug_set_queue_max)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	# During morning/evening, clear any remaining queue
	if phase != DayManager.Phase.DAY:
		for c in _queue:
			if c != null and is_instance_valid(c):
				var cust := c as Customer
				if cust != null and cust.state != Customer.CustomerState.LEAVING:
					cust.force_timeout()
		_queue.fill(null)
		_reserved_slots.clear()


func set_queue_spots(spots: Array[Vector3], step: Vector3 = Vector3.ZERO) -> void:
	_queue_spots = spots
	_queue.resize(spots.size())
	_queue.fill(null)
	# Slot 0 (active customer) faces +Z toward the counter.
	# All other slots face +X toward the front of the queue.
	_queue_face_dir = Vector3(1, 0, 0)
	_counter_face_dir = Vector3(0, 0, 1)


func _spawn_at_slot(slot_index: int) -> void:
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	get_parent().add_child(customer)
	customer.global_position = Vector3(0, 0, Balancing.CUSTOMER_SPAWN_Z)
	customer.queue_slot = slot_index
	customer.queue_position = _queue_spots[slot_index]
	_apply_facing(customer)
	_queue[slot_index] = customer


func _get_queue_cap() -> int:
	var base: int = _queue_max_override
	if _queue_max_override <= 0:
		base = mini(Balancing.QUEUE_MAX, _queue_spots.size())
	var bonus: int = int(UpgradeManager.get_effect_total("queue_appeal"))
	return mini(base + bonus, _queue_spots.size())


func _first_free_slot() -> int:
	var cap := _get_queue_cap()
	for i in range(mini(cap, _queue.size())):
		if _reserved_slots.has(i):
			continue
		if _queue[i] == null or not is_instance_valid(_queue[i]):
			return i
	return -1


func _on_customer_left(customer: Node, _outcome: String) -> void:
	for i in range(_queue.size()):
		if _queue[i] == customer:
			_queue[i] = null
			break
	_compact_queue()


func _compact_queue() -> void:
	# Collect customers that are still waiting in line (not being served or leaving).
	# RECEIVING/REACTING stay at slot 0; they're included so the slot stays occupied.
	var packed: Array = []
	for c: Customer in _queue:
		if c != null and is_instance_valid(c):
			var cust := c as Customer
			if cust == null or cust.state != Customer.CustomerState.LEAVING:
				packed.append(c)

	# Build a new queue that respects reserved slots — never move a customer
	# into a slot a pedestrian is currently walking toward.
	var new_queue: Array = []
	new_queue.resize(_queue.size())
	new_queue.fill(null)

	var packed_idx := 0
	for i in range(new_queue.size()):
		if _reserved_slots.has(i):
			continue # leave reserved slots empty
		if packed_idx < packed.size():
			new_queue[i] = packed[packed_idx]
			packed_idx += 1

	for i in range(new_queue.size()):
		_queue[i] = new_queue[i]
		if _queue[i] != null:
			var c := _queue[i] as Customer
			c.queue_slot = i
			if c.queue_position != _queue_spots[i]:
				c.step_forward(_queue_spots[i])


func _on_debug_set_queue_max(max_size: int) -> void:
	_queue_max_override = clamp(max_size, 0, _queue_spots.size())


func _on_debug_force_spawn() -> void:
	_compact_queue() # close any gaps first
	# Bypass the normal queue cap — debug force-spawn fills any free slot up to
	# the total number of queue spots (not limited to Balancing.QUEUE_MAX).
	for i in range(_queue.size()):
		if _reserved_slots.has(i):
			continue
		if _queue[i] == null or not is_instance_valid(_queue[i]):
			_spawn_at_slot(i)
			return


## Called by PedestrianSpawner when a pedestrian wants to join.
## Gathers every pedestrian already walking to a slot plus the new one,
## then greedily reassigns slots front-to-back so the closest pedestrian
## to each slot claims it. Existing pedestrians are rerouted if their
## assignment changes. Returns the slot given to [pedestrian], or -1.
func claim_free_slot(pedestrian: Pedestrian) -> int:
	_compact_queue()

	# Gather in-flight pedestrians
	var in_flight: Array[Pedestrian] = []
	for ped: Pedestrian in _reserved_slots.values():
		if is_instance_valid(ped):
			in_flight.append(ped)

	# Collect slots that are not occupied by actual customers
	var available_slots: Array[int] = []
	var cap := _get_queue_cap()
	for i in range(mini(cap, _queue.size())):
		if _queue[i] != null and is_instance_valid(_queue[i]):
			continue
		available_slots.append(i)

	# No room for another pedestrian?
	if in_flight.size() + 1 > available_slots.size():
		return -1

	# Build the full pool: existing + newcomer
	var all_peds := in_flight.duplicate()
	all_peds.append(pedestrian)
	available_slots.sort()

	# Greedy assignment: for each slot, closest remaining pedestrian wins it
	var assigned: Dictionary = { } # slot_index -> Pedestrian
	var remaining := all_peds.duplicate()
	for slot: int in available_slots:
		if remaining.is_empty():
			break
		var closest: Pedestrian = null
		var best_dist := INF
		for ped: Pedestrian in remaining:
			var d: float = ped.global_position.distance_to(_queue_spots[slot])
			if d < best_dist:
				best_dist = d
				closest = ped
		assigned[slot] = closest
		remaining.erase(closest)

	# Remember old assignments so we can reroute changed pedestrians
	var old_map := _reserved_slots.duplicate()
	_reserved_slots.clear()
	for slot: int in assigned.keys():
		var ped = assigned[slot]
		_reserved_slots[slot] = ped
		# Reroute if this pedestrian was already reserved for a different slot
		var had_old := false
		var old_slot := -1
		for s: int in old_map.keys():
			if old_map[s] == ped:
				had_old = true
				old_slot = s
				break
		if had_old and old_slot != slot:
			ped.update_queue_target(_queue_spots[slot])

	# Return whichever slot the newcomer received
	for slot: int in assigned.keys():
		if assigned[slot] == pedestrian:
			return slot
	return -1


func get_slot_for_pedestrian(pedestrian: Pedestrian) -> int:
	for slot: int in _reserved_slots.keys():
		if _reserved_slots[slot] == pedestrian:
			return slot
	return -1


func _apply_facing(customer: Customer) -> void:
	customer.queue_face_dir = _queue_face_dir
	customer.counter_face_dir = _counter_face_dir


## Returns the world position of a queue slot (used by PedestrianSpawner to route a
## pedestrian to the slot before converting it).
func get_slot_position(slot_index: int) -> Vector3:
	return _queue_spots[slot_index]


## Called by PedestrianSpawner once the pedestrian has physically walked to the slot.
## Clears the reservation and spawns a customer already in WAITING state at the slot.
## If [source_pedestrian] is given, the pedestrian's NPCBody is transferred so the
## visual appearance stays identical.
func spawn_converted(slot_index: int, source_pedestrian: Pedestrian = null) -> void:
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	customer.queue_slot = slot_index
	customer.queue_position = _queue_spots[slot_index]
	_apply_facing(customer)

	if source_pedestrian != null and is_instance_valid(source_pedestrian):
		customer.preserve_appearance()
		var old_npc := customer.get_node_or_null("NPCBody")
		var new_npc := source_pedestrian.get_node_or_null("NPCBody")
		if old_npc != null and new_npc != null:
			source_pedestrian.remove_child(new_npc)
			customer.remove_child(old_npc)
			customer.add_child(new_npc)
			new_npc.owner = customer
			old_npc.queue_free()

	get_parent().add_child(customer)
	if source_pedestrian != null:
		customer.global_position = source_pedestrian.global_position
		customer.basis = source_pedestrian.basis
		customer.state = Customer.CustomerState.WALKING
	else:
		customer.global_position = _queue_spots[slot_index]
		customer.start_waiting()
	_queue[slot_index] = customer
	# Clear reservation only AFTER the slot is occupied in _queue so no other
	# spawn or compact can claim it in between.
	_reserved_slots.erase(slot_index)
