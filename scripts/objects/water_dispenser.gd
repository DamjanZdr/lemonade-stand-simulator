class_name WaterDispenser
extends Interactable
## Water dispenser: holds water that fills pitchers. Refilled from shop water boxes.
## Pitcher snaps to Marker3D. Click to fill. Tap handle rotates during fill.

var water_fillings: int = 10
var max_fillings: int = 10

@export var fill_time_per_pitcher: float = 2.0

var _is_filling: bool = false
var _fill_progress: float = 0.0
var _fill_amount: float = 0.0
var _snapped_pitcher: Pitcher = null
var _tap_tween: Tween = null
var _last_display_fillings: float = -1000.0

@onready var _water_eraser: CSGBox3D = $CSGCombiner3D/WaterEraser
@onready var _tap_mesh: MeshInstance3D = $"water dispenser/TapObject"
@onready var _snap_point: Marker3D = $Marker3D

const TAP_Y_CLOSED: float = 110.0
const TAP_Y_OPEN: float = 250.0
const WATER_Y_FULL: float = 3.9
const WATER_Y_EMPTY: float = 0.74


func _ready() -> void:
	add_to_group("water_dispenser")
	add_to_group("container")
	_update_water_visual()


## Host-only: apply a refill and sync to all clients.
func _apply_refill(to_add: int) -> void:
	water_fillings = mini(water_fillings + to_add, max_fillings)
	_update_water_visual()
	WorldSync.sync_property(self, "water_fillings", water_fillings)
	WorldSync.sync_call(self, "_update_water_visual")


## Host-only: apply finishing a fill and sync to all clients.
func _apply_finish_fill() -> void:
	_is_filling = false
	_fill_progress = 0.0
	water_fillings = maxi(water_fillings - 1, 0)
	_update_water_visual()
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_snapped_pitcher.water += _fill_amount
		_snapped_pitcher.update_label()
		_snapped_pitcher.end_press_eraser_animation()
		_snapped_pitcher.update_liquid_color()
		EventBus.pitcher_ingredient_added.emit("water", _fill_amount)
		if _snapped_pitcher.fruit_count > 0.0 and _snapped_pitcher.water > 0.0 \
				and _snapped_pitcher.state == Pitcher.PitcherState.PREPPING:
			_snapped_pitcher.state = Pitcher.PitcherState.COMPLETE
			EventBus.pitcher_state_changed.emit(int(_snapped_pitcher.state))
	# Return tap to closed
	if _tap_mesh:
		if _tap_tween and _tap_tween.is_valid():
			_tap_tween.kill()
		_tap_tween = create_tween()
		_tap_tween.tween_property(_tap_mesh, "rotation_degrees:y", TAP_Y_CLOSED, 0.3)
	WorldSync.sync_property(self, "water_fillings", water_fillings)
	WorldSync.sync_call(self, "_update_water_visual")


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_refill(to_add: int) -> void:
	if not is_multiplayer_authority():
		return
	_apply_refill(to_add)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_start_fill(water_amount: float) -> void:
	if not is_multiplayer_authority():
		return
	_start_fill(water_amount)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_finish_fill() -> void:
	if not is_multiplayer_authority():
		return
	_apply_finish_fill()


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_take_pitcher() -> void:
	if not is_multiplayer_authority():
		return
	# Host doesn't take the pitcher for the client — just clears the snap
	# reference so the host knows it's gone. The client picks it up locally.
	if _snapped_pitcher != null:
		_snapped_pitcher = null
		_is_filling = false
		_fill_progress = 0.0
		_reset_tap()


func _process(delta: float) -> void:
	_update_snap()
	if _is_filling and _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_fill_progress += delta
		var t := _fill_progress / fill_time_per_pitcher
		if t >= 1.0:
			_finish_fill()
		else:
			# Smoothly decrease dispenser water visual as pitcher fills
			var display_fillings := float(water_fillings) - t
			_update_water_visual(display_fillings)


func _update_snap() -> void:
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		if not _snapped_pitcher.global_position.is_equal_approx(_snap_point.global_position):
			_snapped_pitcher.global_position = _snap_point.global_position
		return
	if _snapped_pitcher != null:
		_snapped_pitcher = null
		if _is_filling:
			_is_filling = false
			_fill_progress = 0.0
			_reset_tap()


func _update_water_visual(display_fillings: float = -1.0) -> void:
	if _water_eraser == null:
		return
	if display_fillings >= 0.0 and abs(display_fillings - _last_display_fillings) < 0.05:
		return
	_last_display_fillings = display_fillings
	var t: float
	if display_fillings >= 0.0:
		t = display_fillings / float(max_fillings)
	else:
		t = float(water_fillings) / float(max_fillings)
	var target_y := lerpf(WATER_Y_EMPTY, WATER_Y_FULL, t)
	_water_eraser.position.y = target_y


func _reset_tap() -> void:
	if _tap_tween and _tap_tween.is_valid():
		_tap_tween.kill()
	if _tap_mesh:
		_tap_mesh.rotation_degrees.y = TAP_Y_CLOSED


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return

	# Refill dispenser from water supply box
	if p.held_item == HeldItem.SUPPLY_BOX:
		var itype: String = p.held_item_data.get("ingredient_type", "")
		if itype == "water":
			if water_fillings >= max_fillings:
				EventBus.interaction_hint_changed.emit("Dispenser is full!")
				return
			var qty: float = p.held_item_data.get("amount", 0.0)
			if qty <= 0.0:
				return
			var space: int = max_fillings - water_fillings
			if space <= 0:
				return
			var start_pos := _get_hand_pos(player)
			var to_add: int = 1
			var remaining: float = qty - float(to_add)
			if remaining > 0.0:
				p.inventory.update_held_amount(remaining)
			else:
				p.inventory.make_held_trash(Balancing.TRASH_REFUND_EMPTY_BOX, "empty_box")
			_animate_water_drop(start_pos, to_add)
			# Route through host for authoritative state.
			if not WorldSync.is_host():
				_rpc_request_refill.rpc_id(1, to_add)
			else:
				_apply_refill(to_add)
			return

	# Place pitcher on dispenser — handled by player script ghost placement
	if p.held_item == HeldItem.CONTAINER:
		return

	# Empty hands interactions
	if p.held_item == HeldItem.NONE:
		# Start filling if pitcher snapped, has space, and we have water
		if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and not _is_filling:
			var space := Balancing.PITCHER_MAX_LIQUID - _snapped_pitcher.get_liquid_volume()
			if space > 0.0:
				if water_fillings <= 0:
					EventBus.interaction_hint_changed.emit(
						"Dispenser empty! Buy water boxes from the shop.",
					)
					return
				# Route through host for authoritative state.
				if not WorldSync.is_host():
					_rpc_request_start_fill.rpc_id(1, space)
				else:
					_start_fill(space)
				return
			# Pitcher full — pick it up
			var pitcher := _snapped_pitcher
			_snapped_pitcher = null
			if not WorldSync.is_host():
				_rpc_request_take_pitcher.rpc_id(1)
			p.pickup_container(pitcher, "pitcher")
			return

		# The dispenser itself is a fixed appliance — it can't be picked up
		# or moved, only pitchers snapped to it can be taken.


func interact_secondary(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	# Take pitcher from dispenser
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and not _is_filling:
		var pitcher := _snapped_pitcher
		_snapped_pitcher = null
		if not WorldSync.is_host():
			_rpc_request_take_pitcher.rpc_id(1)
		p.pickup_container(pitcher, "pitcher")
		return
	# The dispenser itself is fixed in place — no pickup on RMB either.


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return "Water Dispenser"

	if p.held_item == HeldItem.SUPPLY_BOX:
		if p.held_item_data.get("is_trash", false):
			return ""
		var itype: String = p.held_item_data.get("ingredient_type", "")
		if itype == "water":
			if water_fillings >= max_fillings:
				return "Water Dispenser | full!"
			return "Water Dispenser | LMB: refill (%d/%d)" % [water_fillings, max_fillings]
		return "Water Dispenser | only water boxes refill"

	if p.held_item == HeldItem.CONTAINER:
		var ctype: String = p.held_item_data.get("container_type", "")
		if ctype == "pitcher":
			if _snapped_pitcher != null:
				return "Water Dispenser | already has a pitcher"
			var recipe: Dictionary = p.held_item_data.get("saved_recipe", { })
			if recipe.get("water", 0.0) > 0.0:
				return "Water Dispenser | pitcher already has water"
			var liquid: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
			if liquid >= Balancing.PITCHER_MAX_LIQUID:
				return "Water Dispenser | pitcher is full"
			return "Water Dispenser | LMB: place pitcher"
		return "Water Dispenser | only pitchers can snap here"

	if _is_filling:
		return "Water Dispenser | filling pitcher..."

	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		var space := Balancing.PITCHER_MAX_LIQUID - _snapped_pitcher.get_liquid_volume()
		if space > 0.0:
			if water_fillings > 0:
				return "Water Dispenser | LMB: fill pitcher"
			return "Water Dispenser | RMB: take pitcher (empty)"
		return "Water Dispenser | LMB: take pitcher"

	return "Water Dispenser | fixed in place"


func snap_pitcher(pitcher: Pitcher) -> void:
	_snapped_pitcher = pitcher
	if _snap_point != null:
		_snapped_pitcher.global_position = _snap_point.global_position


func can_snap_pitcher(pitcher: Pitcher) -> bool:
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		return false
	if pitcher.water > 0.0:
		return false
	var liquid := pitcher.get_liquid_volume()
	if liquid >= Balancing.PITCHER_MAX_LIQUID:
		return false
	return true


func can_snap_pitcher_from_recipe(recipe: Dictionary) -> bool:
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		return false
	if recipe.get("water", 0.0) > 0.0:
		return false
	var liquid: float = recipe.get("fruit_count", recipe.get("lemons", 0.0)) + recipe.get(
		"water",
		0.0,
	)
	if liquid >= Balancing.PITCHER_MAX_LIQUID:
		return false
	return true


func get_snap_global_position() -> Vector3:
	if _snap_point == null:
		return global_position
	return _snap_point.global_position


func _start_fill(water_amount: float) -> void:
	if _snapped_pitcher == null or water_fillings <= 0:
		return
	_is_filling = true
	_fill_progress = 0.0
	_fill_amount = water_amount
	AudioManager.play_sfx("water_pour_in_pitcher", global_position, fill_time_per_pitcher)
	# Animate tap to open
	if _tap_mesh:
		if _tap_tween and _tap_tween.is_valid():
			_tap_tween.kill()
		_tap_tween = create_tween()
		_tap_tween.tween_property(_tap_mesh, "rotation_degrees:y", TAP_Y_OPEN, 0.3)
	# Animate pitcher eraser from current to full
	var current_vol := _snapped_pitcher.get_liquid_volume()
	var target_vol := current_vol + water_amount
	_snapped_pitcher.start_press_eraser_animation(target_vol, fill_time_per_pitcher)
	_snapped_pitcher.tween_color_for_water_addition(water_amount, fill_time_per_pitcher)
	# Water visual will animate smoothly in _process from current level down by 1


func _finish_fill() -> void:
	# Route through host for authoritative state.
	if not WorldSync.is_host():
		_rpc_request_finish_fill.rpc_id(1)
		# Still update local visual state for the client
		_is_filling = false
		_fill_progress = 0.0
		return
	_apply_finish_fill()


func _animate_water_drop(start_pos: Vector3, to_add: int) -> void:
	var drop_mesh := _make_water_drop_mesh()
	add_child(drop_mesh)
	var target_local := Vector3.ZERO
	if _water_eraser:
		target_local = to_local(_water_eraser.global_position)
	var tween := _animate_throw_arc(drop_mesh, start_pos, target_local)
	if tween:
		tween.finished.connect(
			func():
				drop_mesh.queue_free()
				var prev_fillings := water_fillings
				water_fillings += to_add
				var start_y := lerpf(
					WATER_Y_EMPTY,
					WATER_Y_FULL,
					float(prev_fillings) / float(max_fillings),
				)
				var end_y := lerpf(
					WATER_Y_EMPTY,
					WATER_Y_FULL,
					float(water_fillings) / float(max_fillings),
				)
				_water_eraser.position.y = start_y
				var wt := create_tween()
				wt.tween_property(_water_eraser, "position:y", end_y, 0.35) \
						.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				EventBus.supply_box_deposited.emit("water", float(to_add))
				EventBus.interaction_hint_changed.emit(
					"Dispenser: %d/%d" % [water_fillings, max_fillings],
				),
		)
	else:
		drop_mesh.queue_free()
		water_fillings += to_add
		_update_water_visual()
		EventBus.supply_box_deposited.emit("water", float(to_add))


func _make_water_drop_mesh() -> Node3D:
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.8
	sphere.material = mat
	m.mesh = sphere
	return m
