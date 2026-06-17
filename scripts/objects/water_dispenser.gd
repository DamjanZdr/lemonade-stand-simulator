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

@onready var _water_eraser: CSGBox3D = $CSGCombiner3D/WaterEraser
@onready var _tap_mesh: MeshInstance3D = $water dispenser/TapObject
@onready var _snap_point: Marker3D = $Marker3D

const TAP_Y_CLOSED: float = 110.0
const TAP_Y_OPEN: float = 250.0
const WATER_Y_FULL: float = 3.9
const WATER_Y_EMPTY: float = 0.74


func _ready() -> void:
	add_to_group("water_dispenser")
	_update_water_visual()


func _process(delta: float) -> void:
	_update_snap()
	if _is_filling and _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_fill_progress += delta
		var t := _fill_progress / fill_time_per_pitcher
		if t >= 1.0:
			_finish_fill()
		else:
			# Animate tap handle during fill
			if _tap_mesh:
				_tap_mesh.rotation_degrees.y = lerpf(TAP_Y_CLOSED, TAP_Y_OPEN, t)


func _update_snap() -> void:
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_snapped_pitcher.global_position = _snap_point.global_position
		return
	if _snapped_pitcher != null:
		_snapped_pitcher = null
		if _is_filling:
			_is_filling = false
			_fill_progress = 0.0
			_reset_tap()


func _update_water_visual() -> void:
	if _water_eraser:
		var t := float(water_fillings) / float(max_fillings)
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
	if p.held_item == p.HeldItem.SUPPLY_BOX:
		var itype: String = p.held_item_data.get("ingredient_type", "")
		if itype == "water":
			if water_fillings >= max_fillings:
				EventBus.interaction_hint_changed.emit("Dispenser is full!")
				return
			var qty: float = p.held_item_data.get("amount", 0.0)
			if qty <= 0.0:
				return
			var space: int = max_fillings - water_fillings
			var to_add: int = int(minf(qty, float(space)))
			water_fillings += to_add
			_update_water_visual()
			EventBus.supply_box_deposited.emit("water", float(to_add))
			var remaining: float = qty - float(to_add)
			if remaining > 0.0:
				p.update_held_amount(remaining)
				EventBus.interaction_hint_changed.emit(
					"Dispenser: %d/%d (box has %.0f left)" % [water_fillings, max_fillings, remaining],
				)
			else:
				p.clear_held()
				EventBus.interaction_hint_changed.emit(
					"Dispenser refilled! (%d/%d)" % [water_fillings, max_fillings],
				)
			return

	# Place pitcher on dispenser — handled by player script ghost placement
	if p.held_item == p.HeldItem.CONTAINER:
		return

	# Empty hands interactions
	if p.held_item == p.HeldItem.NONE:
		# Start filling if pitcher snapped, has space, and we have water
		if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and not _is_filling:
			var space := Balancing.PITCHER_MAX_LIQUID - _snapped_pitcher.get_liquid_volume()
			if space > 0.0:
				if water_fillings <= 0:
					EventBus.interaction_hint_changed.emit(
						"Dispenser empty! Buy water boxes from the shop.",
					)
					return
				_start_fill(space)
				return
			# Pitcher full — pick it up
			var pitcher := _snapped_pitcher
			_snapped_pitcher = null
			p.pickup_container(pitcher, "pitcher")
			return

		# Pick up dispenser
		if _snapped_pitcher == null:
			p.pickup_container(self, "water_dispenser")


func interact_secondary(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	# Take pitcher from dispenser
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and not _is_filling:
		var pitcher := _snapped_pitcher
		_snapped_pitcher = null
		p.pickup_container(pitcher, "pitcher")
		return
	# Pick up dispenser
	if p.held_item == p.HeldItem.NONE and _snapped_pitcher == null:
		p.pickup_container(self, "water_dispenser")


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return "Water Dispenser"

	if p.held_item == p.HeldItem.SUPPLY_BOX:
		var itype: String = p.held_item_data.get("ingredient_type", "")
		if itype == "water":
			if water_fillings >= max_fillings:
				return "Dispenser is full!"
			return "LMB: refill dispenser (%d/%d)" % [water_fillings, max_fillings]
		return "Only water boxes refill the dispenser"

	if p.held_item == p.HeldItem.CONTAINER:
		var ctype: String = p.held_item_data.get("container_type", "")
		if ctype == "pitcher":
			if _snapped_pitcher != null:
				return "Dispenser already has a pitcher"
			var recipe: Dictionary = p.held_item_data.get("saved_recipe", { })
			if recipe.get("water", 0.0) > 0.0:
				return "Pitcher already has water"
			var liquid: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
			if liquid >= Balancing.PITCHER_MAX_LIQUID:
				return "Pitcher is full"
			return "LMB: Place pitcher on dispenser"
		return "Only pitchers can snap here"

	if _is_filling:
		return "Filling pitcher with water..."

	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		var space := Balancing.PITCHER_MAX_LIQUID - _snapped_pitcher.get_liquid_volume()
		if space > 0.0:
			if water_fillings > 0:
				return "LMB: Fill pitcher  |  RMB: Take pitcher"
			return "Dispenser empty — buy water  |  RMB: Take pitcher"
		return "LMB: Take pitcher  |  RMB: Take pitcher"

	return "LMB: Pick up dispenser  |  RMB: Pick up dispenser"


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


func _finish_fill() -> void:
	_is_filling = false
	_fill_progress = 0.0
	water_fillings -= 1
	_update_water_visual()

	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_snapped_pitcher.water += _fill_amount
		# Trigger label/eraser refresh — _update_label is conventionally private
		# but called across classes for state sync in this codebase
		_snapped_pitcher._update_label()
		_snapped_pitcher.end_press_eraser_animation()
		EventBus.pitcher_ingredient_added.emit("water", _fill_amount)
		# Transition to COMPLETE if both fruit and water present
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
