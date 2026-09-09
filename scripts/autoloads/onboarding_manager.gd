extends Node
## Host-authoritative, stand-scoped onboarding and permanent recipe discovery.

signal stand_progress_changed(stand: StandUnit, progress: Dictionary)
signal discovery_announced(stand: StandUnit, title: String, detail: String)

const VERSION := 1
const TRACK_DEMO := "DEMO"
const FRUIT_COMPLAINTS := ["too_strong", "not_enough_fruit", "too_sweet", "not_sweet_enough"]
const ICE_COMPLAINTS := ["too_cold", "not_cold_enough"]
const CLIENT_REPORTED_EVENTS := [
	"equipment_placed",
	"supply_deposited",
	"pitcher_placed",
	"fruit_loaded",
	"fruit_pressed",
	"pitcher_ingredient",
	"pitcher_water_filled",
	"pitcher_prepared",
	"cup_filled",
]
const TASKS: Array[Dictionary] = [
	{
		"id": "demo_order_workstation",
		"text": "Order a {workstation} from your computer.",
		"event": "equipment_ordered",
		"parts": { "workstation": "workstation" },
	},
	{
		"id": "demo_place_workstation",
		"text": "Place the {workstation} inside your stand.",
		"event": "equipment_placed",
		"parts": { "workstation": "workstation" },
	},
	{
		"id": "demo_trash_workstation_box",
		"text": "Throw the {empty workstation box} in the trashcan.",
		"event": "trash_disposed",
		"parts": { "empty workstation box": "empty_box" },
	},
	{
		"id": "demo_order_equipment",
		"text": "Order a {crate}, {press}, {bucket}, {bowl}, and {pitcher}.",
		"event": "equipment_ordered",
		"parts": {
			"crate": "fruit_bin",
			"press": "press",
			"bucket": "ice_bin",
			"bowl": "sugar_bin",
			"pitcher": "pitcher",
		},
	},
	{
		"id": "demo_place_equipment",
		"text": "Place the {crate}, {press}, {bucket}, {bowl}, and {pitcher} on the workstation.",
		"event": "equipment_placed",
		"parts": {
			"crate": "fruit_bin",
			"press": "press",
			"bucket": "ice_bin",
			"bowl": "sugar_bin",
			"pitcher": "pitcher",
		},
		"requires_workstation": true,
	},
	{
		"id": "demo_order_ingredients",
		"text": "Order {a box of lemons}, {a box of sugar}, and {a box of ice}.",
		"event": "supply_ordered",
		"parts": { "a box of lemons": "lemon", "a box of sugar": "sugar", "a box of ice": "ice" },
	},
	{
		"id": "demo_stock_ingredients",
		"text": "Place the {lemons in the crate}, {sugar in the bowl}, and {ice in the bucket}.",
		"event": "supply_deposited",
		"parts": {
			"lemons in the crate": "lemon",
			"sugar in the bowl": "sugar",
			"ice in the bucket": "ice",
		},
	},
	{
		"id": "demo_place_pitcher_press",
		"text": "Place the {pitcher beneath the press}.",
		"event": "pitcher_placed",
		"parts": { "pitcher beneath the press": "press" },
	},
	{
		"id": "demo_load_press",
		"text": "Put {at least one lemon} into the press.",
		"event": "fruit_loaded",
		"parts": { "at least one lemon": "lemon" },
	},
	{
		"id": "demo_squeeze_lemons",
		"text": "{Squeeze the lemons until they are completely dry}.",
		"event": "fruit_pressed",
		"parts": { "Squeeze the lemons until they are completely dry": "lemon" },
	},
	{
		"id": "demo_move_pitcher_to_workstation",
		"text": "Take the {pitcher out of the press and place it on the workstation}.",
		"event": "equipment_placed",
		"parts": { "pitcher out of the press and place it on the workstation": "pitcher" },
		"requires_workstation": true,
	},
	{
		"id": "demo_add_sugar_ice",
		"text": "Add at least one scoop each of {sugar} and {ice} to the pitcher.",
		"event": "pitcher_ingredient",
		"parts": { "sugar": "sugar", "ice": "ice" },
	},
	{
		"id": "demo_place_water_dispenser",
		"text": "Place the {pitcher on the water dispenser}.",
		"event": "pitcher_placed",
		"parts": { "pitcher on the water dispenser": "water_dispenser" },
	},
	{
		"id": "demo_fill_water",
		"text": "{Fill the rest of the pitcher with water}.",
		"event": "pitcher_water_filled",
		"parts": { "Fill the rest of the pitcher with water": "water" },
	},
	{
		"id": "demo_place_pitcher_stand",
		"text": "Place the {finished pitcher on your stand}.",
		"event": "equipment_placed",
		"parts": { "finished pitcher on your stand": "pitcher" },
	},
	{
		"id": "demo_order_place_cups",
		"text": "{Order cups} and {place them on your stand}.",
		"event": "cups",
		"parts": { "Order cups": "ordered", "place them on your stand": "placed" },
	},
	{
		"id": "demo_fill_cup",
		"text": "{Fill at least one cup with lemonade}.",
		"event": "cup_filled",
		"parts": { "Fill at least one cup with lemonade": "cup" },
	},
	{
		"id": "demo_ask_customer",
		"text": "{Ask a customer what they would like}.",
		"event": "customer_asked",
		"parts": { "Ask a customer what they would like": "asked" },
	},
	{
		"id": "demo_serve_customer",
		"text": "{Serve the customer their order}.",
		"event": "customer_served",
		"parts": { "Serve the customer their order": "served" },
	},
	{
		"id": "demo_correct_change",
		"text": "{Give the customer the correct change}.",
		"event": "correct_change",
		"parts": { "Give the customer the correct change": "change" },
	},
	{
		"id": "demo_set_price",
		"text": "{Increase the lemonade price to $1.00}.",
		"event": "price_changed",
		"parts": { "Increase the lemonade price to $1.00": "lemon" },
		"value": 1.0,
	},
	{
		"id": "demo_record_recipe",
		"text": "On the recipe board, record the {lemons} and {sugar} used in your latest pitcher.",
		"event": "recipe_changed",
		"parts": { "lemons": "fruit_count", "sugar": "sugar" },
	},
	{
		"id": "demo_set_ice_ratio",
		"text": "{Set how many degrees the temperature must rise before adding another ice cube}.",
		"event": "ice_changed",
		"parts": {
			"Set how many degrees the temperature must rise before adding another ice cube": "ice"
		},
	},
	{
		"id": "demo_master_lemon",
		"text": "{Use customer feedback to perfect your lemon recipe}.",
		"event": "recipe_discovered",
		"parts": { "Use customer feedback to perfect your lemon recipe": "lemon" },
	},
	{
		"id": "demo_set_perfect_lemon",
		"text": "{Set your perfected lemon recipe on the recipe board}.",
		"event": "perfect_recipe_set",
		"parts": { "Set your perfected lemon recipe on the recipe board": "lemon" },
	},
	{
		"id": "demo_master_ice",
		"text": "{Use customer feedback to perfect your ice setting}.",
		"event": "ice_discovered",
		"parts": { "Use customer feedback to perfect your ice setting": "ice" },
	},
	{
		"id": "demo_set_perfect_ice",
		"text": "{Set your perfected ice ratio on the recipe board}.",
		"event": "perfect_ice_set",
		"parts": { "Set your perfected ice ratio on the recipe board": "ice" },
	},
	{
		"id": "demo_research_second_fruit",
		"text": "{Research and unlock a second fruit}.",
		"event": "fruit_unlocked",
		"parts": { "Research and unlock a second fruit": "fruit" },
	},
	{
		"id": "demo_prepare_second_fruit",
		"text": "{Order}, {prepare}, and {serve} lemonade made with your new fruit.",
		"event": "second_fruit",
		"parts": { "Order": "ordered", "prepare": "prepared", "serve": "served" },
	},
	{
		"id": "demo_master_second_fruit",
		"text": "{Use customer feedback to perfect your new fruit recipe}.",
		"event": "recipe_discovered",
		"parts": { "Use customer feedback to perfect your new fruit recipe": "selected" },
	},
	{
		"id": "demo_set_second_recipe",
		"text": "{Save your perfected new fruit recipe on the recipe board}.",
		"event": "perfect_recipe_set",
		"parts": { "Save your perfected new fruit recipe on the recipe board": "selected" },
	},
]

var _pending_saved: Dictionary = { }


func _ready() -> void:
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.day_time_over.connect(_on_day_time_over)
	EventBus.equipment_order_placed.connect(
		func(t: String, sn: String):
			report(find_stand(sn), "equipment_ordered", { "type": t }),
	)
	EventBus.supply_order_placed.connect(
		func(t: String, _q: float, _c: float, sn: String):
			report(find_stand(sn), "supply_ordered", { "type": t }),
	)
	EventBus.trash_disposed.connect(
		func(t: String, _refund: float, sn: String):
			report(find_stand(sn), "trash_disposed", { "type": t }),
	)
	EventBus.container_placed.connect(
		func(t: String, n: Node):
			var data := { "type": t }
			if n is Pitcher:
				data["pitcher_state"] = int((n as Pitcher).state)
				data["snapshot"] = (n as Pitcher).get_recipe_snapshot()
			var stand := stand_for_node(n)
			if stand == null:
				stand = WorldSync.get_local_stand() as StandUnit
			report(stand, "equipment_placed", data),
	)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_initialize_stands")


func find_stand(stand_name: String) -> StandUnit:
	for node in get_tree().get_nodes_in_group("stand"):
		var stand := node as StandUnit
		if (
			stand.name == stand_name
			or (stand.is_legacy_primary and GameState.stand_name == stand_name)
		):
			return stand
	return null


func stand_for_node(node: Node) -> StandUnit:
	if node == null:
		return null
	var owner_name: String = node.get("stand_owner") if "stand_owner" in node else ""
	if owner_name != "":
		return find_stand(owner_name)
	var current := node
	while current != null:
		if current is StandUnit:
			return current
		current = current.get_parent()
	return null


func _initialize_stands() -> void:
	for node in get_tree().get_nodes_in_group("stand"):
		initialize_stand(node as StandUnit)


func _on_node_added(node: Node) -> void:
	if node is StandUnit:
		call_deferred("initialize_stand", node)


func default_progress() -> Dictionary:
	return {
		"version": VERSION,
		"track_id": TRACK_DEMO,
		"current_task_id": TASKS[0].id,
		"completed_task_ids": [],
		"completed_parts": { },
		"suspended_task_state": { },
		"active_recipe_candidates": { },
		"active_ice_candidate": { },
		"discovered_recipes": { },
		"discovered_ice_ratio": null,
		"selected_demo_fruit": "",
		"ice_degrees_per_scoop": 4.0,
		"latest_pitchers": { },
		"completed": false,
		"started": true,
		"skipped": false,
		"day_end_active": false,
		"revision": 0,
	}


func initialize_stand(stand: StandUnit) -> void:
	if stand == null:
		return
	var key := stand.name
	if _pending_saved.has(key) and WorldSync.is_host():
		stand.onboarding_progress = _normalize(_pending_saved[key])
		_pending_saved.erase(key)
	elif stand.onboarding_progress.is_empty():
		if not WorldSync.is_host():
			return
		stand.onboarding_progress = default_progress()
	stand.ice_degrees_per_scoop = float(stand.onboarding_progress.get(
			"ice_degrees_per_scoop",
			stand.ice_degrees_per_scoop,
		))
	if stand.is_legacy_primary:
		GameState.ice_degrees_per_scoop = stand.ice_degrees_per_scoop
	_advance_satisfied_tasks(stand)
	stand_progress_changed.emit(stand, stand.onboarding_progress.duplicate(true))


func report(stand: StandUnit, event_name: String, data: Dictionary = { }) -> void:
	if stand == null or data.get("debug", false):
		return
	if not WorldSync.is_host():
		_request_report.rpc_id(1, stand.name, event_name, data)
		return
	_apply_report(stand, event_name, data)


@rpc("any_peer", "reliable")
func _request_report(stand_name: String, event_name: String, data: Dictionary) -> void:
	if not WorldSync.is_host():
		return
	if not event_name in CLIENT_REPORTED_EVENTS:
		return
	var stand := find_stand(stand_name)
	var sender := multiplayer.get_remote_sender_id()
	var players := get_tree().current_scene.get_node_or_null("Players")
	var player: Player = players.get_node_or_null(str(sender)) as Player if players != null else null
	if stand == null or player == null or player.assigned_stand != stand:
		return
	_apply_report(stand, event_name, data)


func _apply_report(stand: StandUnit, event_name: String, data: Dictionary) -> void:
	initialize_stand(stand)
	if event_name == "pitcher_prepared":
		var snap: Dictionary = data.get("snapshot", { }).duplicate(true)
		var fruit: String = snap.get("fruit_type", "")
		stand.onboarding_progress.latest_pitchers[fruit] = snap
		if fruit == stand.onboarding_progress.selected_demo_fruit:
			_match_task(stand, "second_fruit_prepared", { "fruit_type": fruit })
	if (
		event_name == "supply_ordered"
		and data.get("type", "") == stand.onboarding_progress.selected_demo_fruit
	):
		_match_task(stand, "second_fruit_ordered", { "fruit_type": data.type })
	if event_name == "customer_feedback":
		_evaluate_mastery(stand, data)
	_match_task(stand, event_name, data)


func _match_task(stand: StandUnit, event_name: String, data: Dictionary) -> void:
	var p := stand.onboarding_progress
	if p.completed or p.skipped or p.day_end_active:
		return
	var idx := _task_index(p.current_task_id)
	if idx < 0:
		idx = mini(p.completed_task_ids.size(), TASKS.size() - 1)
		p.current_task_id = TASKS[idx].id
	var task := TASKS[idx]
	var completed_parts: Dictionary = p.completed_parts
	var changed := false
	for part in task.parts:
		if completed_parts.get(part, false):
			continue
		if _part_matches(task, part, event_name, data, p):
			completed_parts[part] = true
			changed = true
	if not changed:
		return
	p.completed_parts = completed_parts
	if completed_parts.size() >= task.parts.size():
		p.completed_task_ids.append(task.id)
		p.completed_parts = { }
		if idx + 1 >= TASKS.size():
			p.completed = true
			p.current_task_id = ""
		else:
			p.current_task_id = TASKS[idx + 1].id
	_advance_satisfied_tasks(stand)
	_touch(stand)


func _advance_satisfied_tasks(stand: StandUnit) -> void:
	var p := stand.onboarding_progress
	while not p.completed:
		var id: String = p.current_task_id
		var satisfied := false
		match id:
			"demo_master_lemon":
				satisfied = p.discovered_recipes.has("lemon")
			"demo_set_perfect_lemon":
				var found: Dictionary = p.discovered_recipes.get("lemon", { })
				satisfied = not found.is_empty() and stand.get_recipe("lemon") == found
			"demo_master_ice":
				satisfied = p.discovered_ice_ratio != null
			"demo_set_perfect_ice":
				satisfied = (
					p.discovered_ice_ratio != null
					and is_equal_approx(stand.ice_degrees_per_scoop, float(p.discovered_ice_ratio))
				)
			"demo_research_second_fruit":
				satisfied = p.selected_demo_fruit != ""
			"demo_master_second_fruit":
				satisfied = p.discovered_recipes.has(p.selected_demo_fruit)
			"demo_set_second_recipe":
				var found: Dictionary = p.discovered_recipes.get(p.selected_demo_fruit, { })
				satisfied = (
					not found.is_empty() and stand.get_recipe(p.selected_demo_fruit) == found
				)
		if not satisfied:
			return
		var idx := _task_index(id)
		if not p.completed_task_ids.has(id):
			p.completed_task_ids.append(id)
		p.completed_parts = { }
		if idx + 1 >= TASKS.size():
			p.completed = true
			p.current_task_id = ""
		else:
			p.current_task_id = TASKS[idx + 1].id


func _part_matches(
	task: Dictionary,
	part: String,
	event_name: String,
	data: Dictionary,
	p: Dictionary,
) -> bool:
	var expected: String = task.parts[part]
	if task.event == "cups":
		return (
			(event_name == "supply_ordered" and expected == "ordered" and data.get("type") == "cups")
			or (
				event_name == "equipment_placed" and expected == "placed"
				and data.get("type") == "cup_stack"
			)
		)
	if task.event == "second_fruit":
		return (
			data.get("fruit_type", "") == p.selected_demo_fruit
			and event_name == "second_fruit_" + expected
		)
	if event_name != task.event:
		return false
	if task.get("requires_workstation", false) and not data.get("on_workstation", false):
		return false
	if task.id == "demo_place_pitcher_stand":
		var snapshot: Dictionary = data.get("snapshot", { })
		return (
			data.get("type") == "pitcher" and snapshot.get("fruit_count", 0.0) > 0.0
			and snapshot.get("water", 0.0) > 0.0
		)
	if task.id == "demo_set_price":
		return data.get("fruit_type") == "lemon" and is_equal_approx(data.get("value", 0.0), 1.0)
	if task.id == "demo_record_recipe":
		var latest: Dictionary = p.latest_pitchers.get("lemon", { })
		return (
			data.get("fruit_type") == "lemon"
			and is_equal_approx(data.get("recipe", { }).get(expected, -1.0), latest.get(
					expected,
					-2.0,
				))
		)
	if task.id in ["demo_master_second_fruit", "demo_set_second_recipe"]:
		return data.get("fruit_type") == p.selected_demo_fruit
	return data.get("type", data.get("fruit_type", data.get("part", ""))) == expected


func _evaluate_mastery(stand: StandUnit, data: Dictionary) -> void:
	if not data.get("eligible", false):
		return
	var snap: Dictionary = data.get("snapshot", { }).duplicate(true)
	var fruit: String = snap.get("fruit_type", "")
	if fruit == "" or data.get("requested_fruit", fruit) != fruit:
		return
	var p := stand.onboarding_progress
	var complaints: Array = data.get("complaints", []).duplicate()
	if not p.discovered_recipes.has(fruit):
		var candidate := {
			"fruit_count": snap.get("fruit_count", 0.0),
			"sugar": snap.get("sugar", 0.0),
		}
		var state: Dictionary = p.active_recipe_candidates.get(fruit, { })
		state = _advance_candidate(
			state,
			candidate,
			complaints.any(
				func(c):
					return c in FRUIT_COMPLAINTS,
			),
			_fruit_is_perfect(fruit, candidate),
		)
		p.active_recipe_candidates[fruit] = state
		if state.streak >= 5 and state.perfect:
			p.discovered_recipes[fruit] = candidate
			p.active_recipe_candidates.erase(fruit)
			discovery_announced.emit(
				stand,
				"Perfect %s Recipe Found" % fruit.capitalize(),
				"%g %s · %g scoops of sugar" % [candidate.fruit_count, fruit, candidate.sugar],
			)
			_match_task(stand, "recipe_discovered", { "fruit_type": fruit })
			if stand.get_recipe(fruit) == candidate:
				_match_task(stand, "perfect_recipe_set", { "fruit_type": fruit })
	if p.discovered_ice_ratio == null:
		var ratio := float(data.get("ice_ratio", stand.ice_degrees_per_scoop))
		var state: Dictionary = _advance_candidate(
			p.active_ice_candidate,
			{ "ratio": ratio },
			complaints.any(
				func(c):
					return c in ICE_COMPLAINTS,
			),
			is_equal_approx(ratio, Balancing.PERFECT_ICE_DEGREES_PER_SCOOP),
		)
		p.active_ice_candidate = state
		if state.streak >= 5 and state.perfect:
			p.discovered_ice_ratio = ratio
			p.active_ice_candidate = { }
			discovery_announced.emit(
				stand,
				"Perfect Ice Ratio Found",
				"1 cube every %g degrees" % ratio,
			)
			_match_task(stand, "ice_discovered", { "type": "ice" })
			if is_equal_approx(stand.ice_degrees_per_scoop, ratio):
				_match_task(stand, "perfect_ice_set", { "type": "ice" })
	_touch(stand)


func _advance_candidate(
	old: Dictionary,
	value: Dictionary,
	complained: bool,
	perfect: bool,
) -> Dictionary:
	var same: bool = old.get("value", { }) == value
	var silent: int = int(old.get("silent", 0)) if same else 0
	return {
		"value": value,
		"streak": (0 if complained else (int(old.get("streak", 0)) + 1 if same else 1)),
		"silent": (0 if complained else silent + 1),
		"perfect": perfect,
	}


func _fruit_is_perfect(fruit: String, candidate: Dictionary) -> bool:
	var res := load("res://resources/data/%s.tres" % fruit) as IngredientData
	return (
		res != null and is_equal_approx(candidate.fruit_count, float(res.ideal_fruit_count))
		and is_equal_approx(candidate.sugar, res.get_ideal_sugar_for(candidate.fruit_count))
	)


func notify_recipe_changed(stand: StandUnit, fruit: String, recipe: Dictionary) -> void:
	report(stand, "recipe_changed", { "fruit_type": fruit, "recipe": recipe })
	var discovered: Dictionary = stand.onboarding_progress.get("discovered_recipes", { }).get(
		fruit,
		{ },
	)
	if not discovered.is_empty() and recipe == discovered:
		report(stand, "perfect_recipe_set", { "fruit_type": fruit })


func notify_ice_changed(stand: StandUnit, value: float) -> void:
	if stand != null and WorldSync.is_host():
		initialize_stand(stand)
		stand.onboarding_progress["ice_degrees_per_scoop"] = value
	report(stand, "ice_changed", { "type": "ice", "value": value })
	var discovered = stand.onboarding_progress.get("discovered_ice_ratio")
	if discovered != null and is_equal_approx(value, float(discovered)):
		report(stand, "perfect_ice_set", { "type": "ice" })


func enforce_guaranteed_feedback(
	stand: StandUnit,
	snapshot: Dictionary,
	result: EvaluationResult,
) -> void:
	if stand == null or not WorldSync.is_host():
		return
	initialize_stand(stand)
	var p := stand.onboarding_progress
	var fruit: String = snapshot.get("fruit_type", "")
	if fruit != "" and not p.discovered_recipes.has(fruit):
		var candidate := {
			"fruit_count": snapshot.get("fruit_count", 0.0),
			"sugar": snapshot.get("sugar", 0.0),
		}
		var state: Dictionary = p.active_recipe_candidates.get(fruit, { })
		if (
			state.get("value", { }) == candidate and not _fruit_is_perfect(fruit, candidate)
			and int(state.get("silent", 0)) >= 3 and not result.complaints.any(
				func(c):
					return c in FRUIT_COMPLAINTS,
			)
		):
			var res := load("res://resources/data/%s.tres" % fruit) as IngredientData
			if (
				res != null
				and not is_equal_approx(candidate.fruit_count, float(res.ideal_fruit_count))
			):
				result.complaints.push_front(
					"too_strong" if candidate.fruit_count > res.ideal_fruit_count else "not_enough_fruit"
				)
			elif res != null:
				var ideal_sugar := res.get_ideal_sugar_for(candidate.fruit_count)
				result.complaints.push_front(
					"too_sweet" if candidate.sugar > ideal_sugar else "not_sweet_enough"
				)
	if p.discovered_ice_ratio == null:
		var ice_state: Dictionary = p.active_ice_candidate
		var ratio := stand.ice_degrees_per_scoop
		if (
			ice_state.get("value", { }) == { "ratio": ratio }
			and not is_equal_approx(ratio, Balancing.PERFECT_ICE_DEGREES_PER_SCOOP)
			and int(ice_state.get("silent", 0)) >= 3 and not result.complaints.any(
				func(c):
					return c in ICE_COMPLAINTS,
			)
		):
			result.complaints.append(
				("too_cold"
					if ratio < Balancing.PERFECT_ICE_DEGREES_PER_SCOOP
					else "not_cold_enough")
			)


func request_skip(stand: StandUnit) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if stand == null:
		return
	stand.onboarding_progress.skipped = true
	_touch(stand)


func _on_day_time_over() -> void:
	_set_day_end_active(true)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		_set_day_end_active(true)
	elif phase == DayManager.Phase.MORNING:
		_set_day_end_active(false)


func _set_day_end_active(active: bool) -> void:
	if not WorldSync.is_host():
		return
	for node in get_tree().get_nodes_in_group("stand"):
		var stand := node as StandUnit
		initialize_stand(stand)
		var p := stand.onboarding_progress
		if active and not p.day_end_active:
			p.suspended_task_state = {
				"task": p.current_task_id,
				"parts": p.completed_parts.duplicate(true),
			}
			p.day_end_active = true
			_touch(stand)
		elif not active and p.day_end_active:
			p.current_task_id = p.suspended_task_state.get("task", p.current_task_id)
			p.completed_parts = p.suspended_task_state.get("parts", { })
			p.suspended_task_state = { }
			p.day_end_active = false
			_advance_satisfied_tasks(stand)
			_touch(stand)


func serialize() -> Dictionary:
	var stands := { }
	for node in get_tree().get_nodes_in_group("stand"):
		var stand := node as StandUnit
		stands[stand.name] = stand.onboarding_progress.duplicate(true)
	return { "version": VERSION, "stands": stands }


func reset() -> void:
	_pending_saved.clear()
	for node in get_tree().get_nodes_in_group("stand"):
		var stand := node as StandUnit
		if stand != null:
			stand.onboarding_progress = default_progress()
			stand.ice_degrees_per_scoop = 4.0
			stand_progress_changed.emit(stand, stand.onboarding_progress.duplicate(true))


func deserialize(data: Dictionary) -> void:
	_pending_saved = data.get("stands", { }).duplicate(true)
	call_deferred("_initialize_stands")


func get_task(progress: Dictionary) -> Dictionary:
	if progress.get("day_end_active", false):
		return {
			"id": "day_end",
			"text": "{It's late, end the day}.",
			"parts": { "It's late, end the day": "day" },
		}
	var idx := _task_index(progress.get("current_task_id", ""))
	return TASKS[idx] if idx >= 0 else { }


func _task_index(id: String) -> int:
	for i in TASKS.size():
		if TASKS[i].id == id:
			return i
	return -1


func _normalize(raw: Dictionary) -> Dictionary:
	var p := default_progress()
	for key in raw:
		p[key] = raw[key]
	if _task_index(p.current_task_id) < 0 and not p.completed:
		var idx := mini(p.completed_task_ids.size(), TASKS.size() - 1)
		p.current_task_id = TASKS[idx].id
	return p


func _touch(stand: StandUnit) -> void:
	stand.onboarding_progress.revision = int(stand.onboarding_progress.get("revision", 0)) + 1
	stand_progress_changed.emit(stand, stand.onboarding_progress.duplicate(true))
	stand.push_state()
	SaveManager.save_game()
