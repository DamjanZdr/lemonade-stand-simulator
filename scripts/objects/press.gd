class_name Press
extends Interactable
## Fruit press: player deposits scoops, then presses to extract juice into a pitcher.
## A pitcher must be snapped to the PitcherSnapPoint before pressing works.

var fruit_type: String = ""
var fruit_count: float = 0.0

var _pressing: bool = false
var _press_progress: float = 0.0
var _press_duration: float = 1.5
var _pressed_so_far: float = 0.0

const SNAP_DISTANCE: float = 1.5
const ANIM_FPS: float = 30.0
const FRAME_PRESS_START: float = 0.0
const FRAME_PRESS_END: float = 10.0
const FRAME_OPEN_END: float = 20.0

var _snapped_pitcher: Pitcher = null

@onready var _mesh: Node3D = $PressMesh
@onready var _juice_mesh: Node3D = $press/JuiceMesh
@onready var _progress_bar: ProgressBar = $ProgressBarViewport/ProgressBar
@onready var _snap_point: Marker3D = $PitcherSnapPoint
@onready var _model: Node3D = $press
@onready var _anim_player: AnimationPlayer = (
		_model.find_child("AnimationPlayer", true) if _model else null
)
var _merged_anim: Animation = null
const MERGED_ANIM_NAME: String = "merged/PressingMerged"
var _juice_drain_tween: Tween = null


func _ready() -> void:
	add_to_group("press")
	if _progress_bar:
		_progress_bar.value = 0.0
	_build_merged_animation()


func _process(delta: float) -> void:
	_update_snap()

	if _pressing:
		_press_progress += delta
		if _progress_bar:
			_progress_bar.value = (_press_progress / _press_duration) * 100.0
		# Incrementally add fruit juice to the pitcher as the press goes down
		if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and fruit_count > 0.0:
			var per_fruit := _press_duration / fruit_count
			var target_pressed := floorf(_press_progress / per_fruit)
			target_pressed = minf(target_pressed, fruit_count)
			if target_pressed > _pressed_so_far:
				var to_add := target_pressed - _pressed_so_far
				var ok := _snapped_pitcher.add_ingredient(fruit_type, to_add)
				if ok:
					_pressed_so_far = target_pressed
				else:
					_finish_press()
					return

		# Animate JuiceMesh during first fruit drip, then keep it visible until done
		if _juice_mesh != null and fruit_count > 0.0:
			var per_fruit := _press_duration / fruit_count
			if _pressed_so_far == 0.0:
				var drip_t := clampf(_press_progress / per_fruit, 0.0, 1.0)
				_juice_mesh.position.y = lerpf(0.7, -3.3, drip_t)
			else:
				_juice_mesh.position.y = -3.3
			_juice_mesh.visible = true

		if _press_progress >= _press_duration:
			_finish_press()
			return
		# Drive the pressing animation segment (frame 0-10)
		_update_press_animation()


func _update_press_animation() -> void:
	if _anim_player == null or _merged_anim == null:
		return
	var press_segment := FRAME_PRESS_END / ANIM_FPS # 10/30 = 0.333s
	var t := (_press_progress / _press_duration) * press_segment
	_anim_player.seek(t, true)


func _update_snap() -> void:
	## Keep snapped pitcher aligned; clear if lost.
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_snapped_pitcher.global_position = _snap_point.global_position
		return
	_snapped_pitcher = null


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return

	# Deposit fruit scoops into press
	if p.held_item == p.HeldItem.SUPPLY_BOX \
			and p.held_item_data.get("source") == "bin_scoop":
		var itype: String = p.held_item_data.get("ingredient_type", "")
		var amount: float = p.held_item_data.get("amount", 0.0)
		if not _is_fruit(itype):
			EventBus.interaction_hint_changed.emit("Only fruits go in the press!")
			return
		# Cannot mix fruit types
		if fruit_count > 0.0 and fruit_type != itype:
			EventBus.interaction_hint_changed.emit(
				"Cannot mix %s with %s!" % [itype.capitalize(), fruit_type.capitalize()],
			)
			return
		fruit_type = itype
		fruit_count += amount
		p.clear_held()
		EventBus.interaction_hint_changed.emit(
			"%s in press: %.0f" % [fruit_type.capitalize(), fruit_count],
		)
		return

	# Start pressing if fruits inside, hands empty, and a valid pitcher is snapped
	if p.held_item == p.HeldItem.NONE and fruit_count > 0.0 and not _pressing:
		if _snapped_pitcher == null or not is_instance_valid(_snapped_pitcher):
			EventBus.interaction_hint_changed.emit("Snap a pitcher to the press first!")
			return
		if not _can_press_into_pitcher(_snapped_pitcher):
			EventBus.interaction_hint_changed.emit(
				"Pitcher has wrong fruit or already has water!",
			)
			return
		_start_press()
		return

	# Pick up pitcher from press if press is empty
	if p.held_item == p.HeldItem.NONE and fruit_count <= 0.0 \
			and not _pressing and has_snapped_pitcher():
		var pitcher := _snapped_pitcher
		_snapped_pitcher = null
		p.pickup_container(pitcher, "pitcher")
		return

	# Pick up the press container (only if empty, no snapped pitcher, and not pressing)
	if p.held_item == p.HeldItem.NONE and fruit_count <= 0.0 \
			and not _pressing and not has_snapped_pitcher():
		p.pickup_container(self, "press")


func interact_secondary(player: Node) -> void:
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.NONE and not _pressing \
			and fruit_count <= 0.0 and not has_snapped_pitcher():
		p.pickup_container(self, "press")


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""
	if _pressing:
		return "Pressing %s..." % fruit_type.capitalize()
	if p.held_item == p.HeldItem.SUPPLY_BOX \
			and p.held_item_data.get("source") == "bin_scoop":
		var itype: String = p.held_item_data.get("ingredient_type", "")
		if not _is_fruit(itype):
			return "Press only accepts fruits"
		if fruit_count > 0.0 and fruit_type != itype:
			return "Cannot mix fruit types in press"
		return "Click: add %s to press (has %.0f)" % [itype.capitalize(), fruit_count]
	if fruit_count > 0.0:
		if not has_snapped_pitcher():
			return "Snap a pitcher to the press! (%.0f %s ready)" % [
				fruit_count,
				fruit_type.capitalize(),
			]
		if not _can_press_into_pitcher(_snapped_pitcher):
			return "Pitcher incompatible — empty or same-fruit/no-water only"
		return "Click: press %s into pitcher | RMB: pick up" % fruit_type.capitalize()
	if fruit_count <= 0.0 and has_snapped_pitcher():
		return "LMB: pick up pitcher | RMB: pick up pitcher"
	if fruit_count <= 0.0 and not has_snapped_pitcher():
		return "LMB: pick up press | RMB: pick up press"
	return "Press has fruit or pitcher — cannot pick up"


func _is_fruit(ingredient_type: String) -> bool:
	var path := "res://resources/data/" + ingredient_type + ".tres"
	if not ResourceLoader.exists(path):
		return false
	var res := load(path)
	return res is IngredientData


func _get_press_duration() -> float:
	if fruit_type.is_empty() or fruit_count <= 0.0:
		return 1.5
	var path := "res://resources/data/" + fruit_type + ".tres"
	if not ResourceLoader.exists(path):
		return 1.5 * fruit_count
	var data := load(path) as IngredientData
	if data == null:
		return 1.5 * fruit_count
	var duration := data.press_time_per_fruit * fruit_count
	var press_bonus: float = UpgradeManager.get_effect_total("press_speed")
	if press_bonus > 0.0:
		duration *= (1.0 - press_bonus)
	return duration


func _build_merged_animation() -> void:
	if _anim_player == null:
		return
	var lib := _anim_player.get_animation_library("")
	if lib == null:
		return
	var anim_pressing := lib.get_animation("Pressing")
	var anim_cyl := lib.get_animation("Cylinder_011Action")
	if anim_pressing == null or anim_cyl == null:
		return

	# Pick the track with the most keys for each path
	var track_best: Dictionary = { }
	for i in range(anim_pressing.get_track_count()):
		var path: NodePath = anim_pressing.track_get_path(i)
		var count: int = anim_pressing.track_get_key_count(i)
		track_best[path] = [anim_pressing, i, count]
	for i in range(anim_cyl.get_track_count()):
		var path: NodePath = anim_cyl.track_get_path(i)
		var count: int = anim_cyl.track_get_key_count(i)
		if track_best.has(path):
			if count > track_best[path][2]:
				track_best[path] = [anim_cyl, i, count]
		else:
			track_best[path] = [anim_cyl, i, count]

	_merged_anim = Animation.new()
	_merged_anim.resource_name = "PressingMerged"
	_merged_anim.length = anim_pressing.length

	for path in track_best.keys():
		var src: Animation = track_best[path][0]
		var src_idx: int = track_best[path][1]
		var track_type: int = src.track_get_type(src_idx)
		var new_track: int = _merged_anim.add_track(track_type)
		_merged_anim.track_set_path(new_track, path)
		_merged_anim.track_set_interpolation_type(
			new_track,
			src.track_get_interpolation_type(src_idx),
		)
		_merged_anim.track_set_enabled(new_track, true)
		var key_count: int = src.track_get_key_count(src_idx)
		for k in range(key_count):
			var time: float = src.track_get_key_time(src_idx, k)
			var value: Variant = src.track_get_key_value(src_idx, k)
			_merged_anim.track_insert_key(new_track, time, value)

	var merged_lib := AnimationLibrary.new()
	merged_lib.add_animation("PressingMerged", _merged_anim)
	_anim_player.add_animation_library("merged", merged_lib)


func has_snapped_pitcher() -> bool:
	return _snapped_pitcher != null and is_instance_valid(_snapped_pitcher)


func snap_pitcher(pitcher: Pitcher) -> void:
	_snapped_pitcher = pitcher
	if _snap_point != null:
		_snapped_pitcher.global_position = _snap_point.global_position


func can_snap_pitcher(recipe: Dictionary) -> bool:
	if has_snapped_pitcher():
		return false
	var fcount: float = recipe.get("fruit_count", recipe.get("lemons", 0.0))
	var water: float = recipe.get("water", 0.0)
	var sugar: float = recipe.get("sugar", 0.0)
	var ice: float = recipe.get("ice", 0.0)
	if fcount == 0.0 and water == 0.0 and sugar == 0.0 and ice == 0.0:
		return true
	var ftype: String = recipe.get("fruit_type", "")
	if water == 0.0 and ftype == fruit_type:
		return true
	return false


func get_pitcher_snap_hint(recipe: Dictionary) -> String:
	if has_snapped_pitcher():
		return "Press already has a pitcher  |  RMB: Cancel (refund)"
	if not can_snap_pitcher(recipe):
		return "Pitcher incompatible with press  |  RMB: Cancel (refund)"
	return "LMB: Snap pitcher to press  |  RMB: Cancel (refund)"


func get_snap_global_position() -> Vector3:
	if _snap_point == null:
		return global_position
	return _snap_point.global_position


func _can_press_into_pitcher(pitcher: Pitcher) -> bool:
	## Empty pitcher is always valid.
	if pitcher.fruit_count == 0.0 and pitcher.water == 0.0 \
			and pitcher.sugar == 0.0 and pitcher.ice == 0.0:
		return true
	## Otherwise: no water yet, and same fruit type.
	if pitcher.water == 0.0 and pitcher.fruit_type == fruit_type:
		return true
	return false


func _start_press() -> void:
	_pressing = true
	_press_progress = 0.0
	_pressed_so_far = 0.0
	_press_duration = _get_press_duration()
	if _progress_bar:
		_progress_bar.visible = true
		_progress_bar.value = 0.0
	# Start merged animation at frame 0 and pause so we can drive it manually
	if _anim_player != null and _merged_anim != null:
		_anim_player.play(MERGED_ANIM_NAME)
		_anim_player.pause()
		_anim_player.seek(FRAME_PRESS_START / ANIM_FPS, true)
	if _juice_mesh != null:
		if _juice_drain_tween and _juice_drain_tween.is_valid():
			_juice_drain_tween.kill()
		_juice_mesh.visible = true
		_juice_mesh.position.y = 0.7
		_juice_mesh.scale = Vector3.ONE
	# Animate pitcher eraser from current fill to final fill over press duration
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher) and fruit_count > 0.0:
		var target_vol := _snapped_pitcher.get_liquid_volume() + fruit_count
		_snapped_pitcher.start_press_eraser_animation(target_vol, _press_duration)


func _finish_press() -> void:
	_pressing = false
	_press_progress = 0.0
	if _progress_bar:
		_progress_bar.value = 0.0
		_progress_bar.visible = false
	if _mesh:
		_mesh.position.y = 0.0
	# Drain JuiceMesh from top to bottom instead of snapping off
	if _juice_mesh != null:
		_start_juice_drain()

	# Play the "opening back up" segment (frame 10-20) at normal speed
	if _anim_player != null and _merged_anim != null:
		_anim_player.play(MERGED_ANIM_NAME)
		_anim_player.seek(FRAME_PRESS_END / ANIM_FPS, true)

	# End pitcher eraser animation regardless of whether pitcher moved away
	if _snapped_pitcher != null and is_instance_valid(_snapped_pitcher):
		_snapped_pitcher.end_press_eraser_animation()

	if _snapped_pitcher == null or not is_instance_valid(_snapped_pitcher):
		EventBus.interaction_hint_changed.emit("Pitcher moved away during press!")
		_pressed_so_far = 0.0
		return

	# Add any remaining amount that wasn't added during incremental pressing
	if _pressed_so_far < fruit_count:
		var remaining := fruit_count - _pressed_so_far
		_snapped_pitcher.add_ingredient(fruit_type, remaining)

	EventBus.interaction_hint_changed.emit(
		"Pressed %.0f %s into pitcher!" % [fruit_count, fruit_type.capitalize()],
	)
	fruit_count = 0.0
	fruit_type = ""
	_pressed_so_far = 0.0


func _start_juice_drain() -> void:
	if _juice_drain_tween and _juice_drain_tween.is_valid():
		_juice_drain_tween.kill()

	# Find a MeshInstance3D under JuiceMesh to read the AABB
	var mesh_inst := _juice_mesh as MeshInstance3D
	if mesh_inst == null:
		for child in _juice_mesh.get_children():
			mesh_inst = child as MeshInstance3D
			if mesh_inst != null:
				break

	if mesh_inst == null or mesh_inst.mesh == null:
		# Fallback: hide immediately
		_juice_mesh.visible = false
		_juice_mesh.position.y = 0.7
		_juice_mesh.scale = Vector3.ONE
		return

	var aabb := mesh_inst.mesh.get_aabb()
	var bottom_local := aabb.position.y
	var original_pos_y := _juice_mesh.position.y

	_juice_drain_tween = create_tween()
	_juice_drain_tween.tween_method(
		func(s: float):
			_juice_mesh.scale.y = s
			_juice_mesh.position.y = original_pos_y + bottom_local * (1.0 - s),
		1.0,
		0.0,
		0.35,
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)
	_juice_drain_tween.tween_callback(
		func():
			_juice_mesh.visible = false
			_juice_mesh.scale = Vector3.ONE
			_juice_mesh.position.y = 0.7
	)
