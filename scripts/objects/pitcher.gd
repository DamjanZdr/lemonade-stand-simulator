class_name Pitcher
extends Interactable
## Three-state pitcher: PREPPING → COMPLETE → SERVING → PREPPING
##
## PREPPING: sits on prep table; player scoops ingredients in from bins.
## COMPLETE: has lemon+water ready; can still add sugar/ice until first cup poured.
## SERVING:  placed anywhere; player with empty cup clicks to fill a cup.

enum PitcherState {
	PREPPING,
	COMPLETE,
	SERVING,
}

var state: PitcherState = PitcherState.PREPPING
var fruit_type: String = "" ## e.g., "lemon"; empty when no fruit added yet.
var fruit_count: float = 0.0 ## How many fruits worth of juice in the pitcher.
var water: float = 0.0
var sugar: float = 0.0
var ice: float = 0.0
var cups_poured: int = 0 # Once > 0, can no longer add sugar/ice

# Set by world at startup so pitcher knows where to return after being thrown out.
var prep_position: Vector3 = Vector3.ZERO
var _prep_scale: Vector3 = Vector3.ONE

@onready var _body_mesh: Node3D = $pitcher
@onready var contents_label: Label3D = $ContentsLabel
@onready var physics: StaticBody3D = $Physics
@onready var _lemonade_node: Node3D = $lemonade
@onready var _glass_mesh: MeshInstance3D = $pitcher/Cylinder_001
@onready var _lemonade_eraser: Node3D = $LemonadeFill/LemonadeEraser

var _drop_busy: bool = false # true while a drop animation is playing
var _eraser_tween: Tween = null
var _press_eraser_tween: Tween = null
var _suppress_eraser_updates: bool = false
var _last_liquid_color: Color = Color(0.0, 0.0, 0.0, -1.0)
var _last_eraser_target_y: float = -1000.0

const ERASER_Y_EMPTY: float = 1.752
const ERASER_Y_FULL: float = 5.245
const MAX_FILL_VOLUME: float = 10.0

@export_group("Liquid Colors")
@export var water_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var lemon_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var strawberry_color: Color = Color(1.0, 0.2, 0.4, 1.0)
@export var blueberry_color: Color = Color(0.3, 0.1, 0.6, 1.0)
@export var peach_color: Color = Color(1.0, 0.7, 0.5, 1.0)
@export var watermelon_color: Color = Color(0.9, 0.1, 0.2, 1.0)

# _liquid_material is NOT cached to avoid hot-reload / CSG rebuild resets


func _ready() -> void:
	add_to_group("pitcher")
	add_to_group("container")
	Pickupable.setup_for_container(self, "pitcher")
	prep_position = global_position
	_prep_scale = scale
	EventBus.debug_empty_pitcher.connect(_on_debug_empty_pitcher)
	# Hide the original GLB lemonade cylinders (the CSG fill is used instead).
	for n in ["Cylinder_002", "Cylinder_003"]:
		var orig := _lemonade_node.get_node_or_null(n) as MeshInstance3D
		if orig:
			orig.visible = false
	_fix_glass_transparency()
	_update_eraser_position()
	update_label()
	update_liquid_color()


# Glass uses TRANSPARENCY_ALPHA_DEPTH_PRE_PASS which writes depth before the opaque
# lemonade renders, making it invisible. Switch to plain ALPHA so depth pre-pass is skipped.
func _fix_glass_transparency() -> void:
	if _glass_mesh == null or _glass_mesh.mesh == null:
		return
	var mat := _glass_mesh.mesh.surface_get_material(0)
	if mat is StandardMaterial3D:
		var dup := mat.duplicate() as StandardMaterial3D
		dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mesh.material_override = dup

# --- Queries ---


func get_liquid_volume() -> float:
	return fruit_count + water


func is_fully_empty() -> bool:
	return fruit_count == 0.0 and water == 0.0 and sugar == 0.0 and ice == 0.0

# --- Mutation ---


func add_ingredient(ingredient_type: String, amount: float) -> bool:
	# Can only add ingredients in PREPPING or COMPLETE state
	if state != PitcherState.PREPPING and state != PitcherState.COMPLETE:
		return false

	# Once cups are poured, can no longer add sugar or ice
	if cups_poured > 0 and (ingredient_type == "sugar" or ingredient_type == "ice"):
		return false

	# Determine if this ingredient is a fruit by looking for its IngredientData.
	var is_fruit := _is_ingredient_fruit(ingredient_type)

	match ingredient_type:
		_ when is_fruit:
			# Can only add fruit in PREPPING state (not COMPLETE)
			if state == PitcherState.COMPLETE:
				return false
			if get_liquid_volume() + amount > Balancing.PITCHER_MAX_LIQUID:
				return false
			# Reject mixed fruits in the same pitcher.
			if fruit_type != "" and fruit_type != ingredient_type:
				EventBus.interaction_hint_changed.emit(
					"Cannot mix %s with %s!"
					% [ingredient_type.capitalize(), fruit_type.capitalize()],
				)
				return false
			if fruit_type == "":
				fruit_type = ingredient_type
			fruit_count += amount
			update_liquid_color()
			# Check if we should transition to COMPLETE (has both fruit and water)
			if fruit_count > 0.0 and water > 0.0:
				state = PitcherState.COMPLETE
				EventBus.pitcher_state_changed.emit(int(state))
		"water":
			# Can only add water in PREPPING state (not COMPLETE)
			if state == PitcherState.COMPLETE:
				return false
			if get_liquid_volume() + amount > Balancing.PITCHER_MAX_LIQUID:
				return false
			water += amount
			update_liquid_color()
			# Check if we should transition to COMPLETE
			if fruit_count > 0.0 and water > 0.0:
				state = PitcherState.COMPLETE
				EventBus.pitcher_state_changed.emit(int(state))
		"sugar":
			sugar += amount
		"ice":
			ice += amount
		_:
			return false
	update_label()
	EventBus.pitcher_ingredient_added.emit(ingredient_type, amount)
	_sync_state_to_peers()
	return true


func get_recipe_snapshot() -> Dictionary:
	var color := _get_current_liquid_color()
	return {
		"fruit_type": fruit_type,
		"fruit_count": fruit_count,
		"water": water,
		"sugar": sugar,
		"ice": ice,
		"color": color,
	}


## Sync this pitcher's state to all peers via WorldSync. Only the host
## sends; clients receive and update their local copy + refresh display.
func _sync_state_to_peers() -> void:
	WorldSync.sync_properties(
		self,
		{
			"fruit_type": fruit_type,
			"fruit_count": fruit_count,
			"water": water,
			"sugar": sugar,
			"ice": ice,
			"cups_poured": cups_poured,
			"state": state,
		},
	)
	WorldSync.sync_call(self, "sync_fill_display")
	WorldSync.sync_call(self, "update_label")


func pour_portion() -> Dictionary:
	var snap := get_recipe_snapshot()
	var liquid := get_liquid_volume()
	if liquid <= 0.0:
		return snap
	var portion_ratio := minf(Balancing.PORTION_SIZE / liquid, 1.0)
	fruit_count -= fruit_count * portion_ratio
	water -= water * portion_ratio
	sugar -= sugar * portion_ratio
	ice -= ice * portion_ratio
	cups_poured += 1 # Track that a cup was poured
	# Pouring a cup means the pitcher is now actively serving, wherever it is.
	# Without this, a pitcher poured from while still in the COMPLETE state
	# (i.e. placed but never explicitly marked SERVING) would be treated as
	# "not serving" once drained, causing _clear_and_return() to incorrectly
	# snap it back to its original prep-table position.
	if state != PitcherState.SERVING:
		state = PitcherState.SERVING
		EventBus.pitcher_state_changed.emit(int(state))
	# Flush floating-point dust
	if get_liquid_volume() < 0.05:
		fruit_type = ""
		fruit_count = 0.0
		water = 0.0
		sugar = 0.0
		ice = 0.0
	update_label()
	update_liquid_color()
	AudioManager.play_sfx("fill_up_cup", global_position)
	_sync_state_to_peers()
	return snap


func _clear_and_return() -> void:
	# Save current state before clearing
	var was_serving := (state == PitcherState.SERVING)
	fruit_type = ""
	fruit_count = 0.0
	water = 0.0
	sugar = 0.0
	ice = 0.0
	cups_poured = 0
	state = PitcherState.PREPPING
	# Only move back to prep position if not in SERVING state (i.e., at prep table)
	if not was_serving:
		global_position = prep_position
	set_pitcher_visible(true)
	update_label()
	EventBus.pitcher_cleared.emit()
	EventBus.pitcher_state_changed.emit(int(state))


func set_pitcher_visible(v: bool) -> void:
	if not is_inside_tree():
		return
	_body_mesh.visible = v
	_lemonade_node.visible = v
	contents_label.visible = v
	physics.collision_layer = 1 if v else 0

# --- Interaction ---


func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	# Only the stand that owns this pitcher can interact with it.
	if not can_player_use(player):
		return

	match state:
		PitcherState.PREPPING, PitcherState.COMPLETE:
			# Deposit scoop from hand (sugar/ice only in COMPLETE state)
			if p.held_item == HeldItem.SUPPLY_BOX \
					and p.held_item_data.get("source") == "bin_scoop":
				if _drop_busy:
					return
				var itype: String = p.held_item_data.get("ingredient_type", "")
				var amount: float = p.held_item_data.get("amount", 0.0)
				if _can_add_ingredient(itype, amount):
					var start_pos := _get_hand_pos(player)
					p.inventory.clear_held()
					_animate_drop(itype, amount, start_pos)
				else:
					EventBus.interaction_hint_changed.emit(
						"Cannot add %s! (State: %s, Cups poured: %d)"
						% [itype, str(state), cups_poured],
					)
				return
			# Fill cup if pitcher has liquid and player holds empty cup
			if p.held_item == HeldItem.CUP_EMPTY and get_liquid_volume() > 0.0:
				var recipe := pour_portion()
				var cup_color: Color = recipe.get("color", Color(0.0, 0.0, 0.0, -1.0))
				p.inventory.set_held(
					HeldItem.CUP_FILLED,
					{ "recipe": recipe },
					_make_filled_cup_mesh(cup_color),
				)
				EventBus.pitcher_cup_filled.emit(recipe)
				if is_fully_empty():
					_clear_and_return()
				return
			# Pick up: always use container system now
			if p.held_item == HeldItem.NONE:
				p.pickup_container(self, "pitcher")
		PitcherState.SERVING:
			if p.held_item == HeldItem.CUP_EMPTY:
				var recipe := pour_portion()
				var cup_color: Color = recipe.get("color", Color(0.0, 0.0, 0.0, -1.0))
				p.inventory.set_held(
					HeldItem.CUP_FILLED,
					{ "recipe": recipe },
					_make_filled_cup_mesh(cup_color),
				)
				EventBus.pitcher_cup_filled.emit(recipe)
				if is_fully_empty():
					_clear_and_return()
				return
			# Pick up: a pitcher that's still serving (not full, cups already
			# poured from it) should still be pick-up-able with an empty hand,
			# same as a fresh one in PREPPING/COMPLETE.
			if p.held_item == HeldItem.NONE:
				p.pickup_container(self, "pitcher")


func try_add_ingredient(ingredient_type: String, amount: float) -> bool:
	## Public entry for press machine / automated addition.
	## Returns true if the drop animation was started.
	if _drop_busy:
		return false
	if not _can_add_ingredient(ingredient_type, amount):
		return false
	_animate_drop(ingredient_type, amount)
	return true


func get_contents_string() -> String:
	var parts: Array[String] = []
	if fruit_count > 0.0 and fruit_type != "":
		parts.append("%.0f %s" % [fruit_count, fruit_type])
	if sugar > 0.0:
		parts.append("%.0f sugar" % sugar)
	if ice > 0.0:
		parts.append("%.0f ice" % ice)
	if parts.is_empty():
		return "empty"
	return " ".join(parts)


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""
	var contents := ""
	if not get_contents_string() == "empty":
		contents = "[%s]\n" % get_contents_string()
	match state:
		PitcherState.PREPPING, PitcherState.COMPLETE:
			if p.held_item == HeldItem.SUPPLY_BOX \
					and p.held_item_data.get("source") == "bin_scoop":
				return contents + "Pitcher | LMB: add %s" % p.held_item_data.get(
					"ingredient_type",
					"",
				)
			if get_liquid_volume() <= 0.0:
				return "Pitcher | LMB: pick up"
			if p.held_item == HeldItem.CUP_EMPTY:
				return contents + (
					"Pitcher | LMB: fill cup  |  RMB: pick up (%.1f liq)" % get_liquid_volume()
				)
			return contents + "Pitcher | LMB/RMB: pick up"
		PitcherState.SERVING:
			if p.held_item == HeldItem.CUP_EMPTY:
				return contents + (
					"Pitcher | LMB: fill cup  |  RMB: pick up (%.1f liq)" % get_liquid_volume()
				)
			return contents + "Pitcher | LMB/RMB: pick up"
	return ""


func _make_hand_mesh() -> Node3D:
	var container := Node3D.new()
	# Scale to match the world display scale (pitcher is placed at 0.105 in world.tscn)
	container.scale = Vector3.ONE * 0.105
	# Duplicate the existing glass visual; material_override already has transparency fixed.
	# Force visible=true since _set_visible(false) is called before this on pickup.
	var glass_dup := _body_mesh.duplicate() as Node3D
	glass_dup.visible = true
	container.add_child(glass_dup)
	# Add the matching lemonade fill (if any liquid is present)
	var vol := get_liquid_volume()
	if vol > 0.0 and _lemonade_eraser != null:
		var fill_dup := $LemonadeFill.duplicate() as Node3D
		var eraser := fill_dup.get_node_or_null("LemonadeEraser") as Node3D
		if eraser != null:
			var t := clampf(vol / MAX_FILL_VOLUME, 0.0, 1.0)
			eraser.position.y = lerpf(ERASER_Y_EMPTY, ERASER_Y_FULL, t)
		container.add_child(fill_dup)
	return container


func _make_filled_cup_mesh(color: Color = Color(0.0, 0.0, 0.0, -1.0)) -> Node3D:
	# When a color is supplied (e.g. from a pour_portion() recipe snapshot taken
	# before the pitcher was drained), use it instead of the pitcher's current
	# liquid color, which is black once the pitcher has been emptied.
	var use_color := color if color.a >= 0.0 else _get_current_liquid_color()
	return Cup.make_hand_mesh(true, use_color)


func update_label() -> void:
	var status := ""
	match state:
		PitcherState.PREPPING:
			status = "[Prepping]"
		PitcherState.COMPLETE:
			status = "[Complete]"
		PitcherState.SERVING:
			status = "[Serving]"
		_:
			status = ""
	var fruit_label := fruit_type.capitalize() if fruit_type != "" else "Fruit"
	contents_label.text = "%s\n%s: %.1f  Sugar: %.1f  Ice: %.1f\nCups: %d" % [
		status,
		fruit_label,
		fruit_count,
		sugar,
		ice,
		cups_poured,
	]
	_update_eraser_position()


func _update_eraser_position(duration: float = 0.15) -> void:
	if _suppress_eraser_updates:
		return
	var vol := get_liquid_volume()
	var t := clampf(vol / MAX_FILL_VOLUME, 0.0, 1.0)
	var target_y := lerpf(ERASER_Y_EMPTY, ERASER_Y_FULL, t)
	if abs(target_y - _last_eraser_target_y) < 0.05:
		return
	_last_eraser_target_y = target_y
	if _lemonade_eraser != null:
		if _eraser_tween and _eraser_tween.is_valid():
			_eraser_tween.kill()
		_eraser_tween = create_tween()
		_eraser_tween.tween_property(_lemonade_eraser, "position:y", target_y, duration) \
				.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)


func start_press_eraser_animation(target_vol: float, duration: float) -> void:
	_suppress_eraser_updates = true
	if _press_eraser_tween and _press_eraser_tween.is_valid():
		_press_eraser_tween.kill()
	var t := clampf(target_vol / MAX_FILL_VOLUME, 0.0, 1.0)
	var target_y := lerpf(ERASER_Y_EMPTY, ERASER_Y_FULL, t)
	if _lemonade_eraser != null:
		_press_eraser_tween = create_tween()
		_press_eraser_tween.tween_property(_lemonade_eraser, "position:y", target_y, duration) \
				.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)


func end_press_eraser_animation() -> void:
	_suppress_eraser_updates = false
	if _press_eraser_tween and _press_eraser_tween.is_valid():
		_press_eraser_tween.kill()
	_update_eraser_position()


func fill_water_slow(amount: float, duration: float = 2.0) -> void:
	var start_color := _get_current_liquid_color()
	water += amount
	var end_color := _get_current_liquid_color()
	_update_eraser_position(duration)
	update_label()
	var tween := create_tween()
	tween.tween_method(
		func(c: Color):
			_apply_liquid_color(c),
		start_color,
		end_color,
		duration,
	)
	if fruit_count > 0.0 and water > 0.0 and state == PitcherState.PREPPING:
		state = PitcherState.COMPLETE
		EventBus.pitcher_state_changed.emit(int(state))


func tween_color_for_water_addition(water_amount: float, duration: float) -> void:
	var start_color := _get_current_liquid_color()
	var original_water := water
	water = original_water + water_amount
	var end_color := _get_current_liquid_color()
	water = original_water
	var tween := create_tween()
	tween.tween_method(
		func(c: Color):
			_apply_liquid_color(c),
		start_color,
		end_color,
		duration,
	)


func _can_add_ingredient(ingredient_type: String, amount: float) -> bool:
	# Can only add ingredients in PREPPING or COMPLETE state
	if state != PitcherState.PREPPING and state != PitcherState.COMPLETE:
		return false

	# Once cups are poured, can no longer add sugar or ice
	if cups_poured > 0 and (ingredient_type == "sugar" or ingredient_type == "ice"):
		return false

	var is_fruit := _is_ingredient_fruit(ingredient_type)
	match ingredient_type:
		_ when is_fruit:
			if state == PitcherState.COMPLETE:
				return false
			if fruit_type != "" and fruit_type != ingredient_type:
				return false
			return get_liquid_volume() + amount <= Balancing.PITCHER_MAX_LIQUID
		"water":
			if state == PitcherState.COMPLETE:
				return false
			return get_liquid_volume() + amount <= Balancing.PITCHER_MAX_LIQUID
		"sugar", "ice":
			return true
		_:
			return false


## Checks if an ingredient string corresponds to a known fruit IngredientData resource.
func _is_ingredient_fruit(ingredient_type: String) -> bool:
	if ingredient_type == "":
		return false
	# Check if a .tres file exists for this ingredient type.
	var path := "res://resources/data/" + ingredient_type + ".tres"
	if not ResourceLoader.exists(path):
		return false
	var res := load(path)
	return res is IngredientData


func _animate_drop(
	ingredient_type: String,
	amount: float,
	from_pos: Vector3 = Vector3.ZERO,
) -> void:
	_drop_busy = true
	var drop_mesh := _make_drop_mesh(ingredient_type)
	add_child(drop_mesh)
	if from_pos != Vector3.ZERO:
		var target_local := Vector3(0.0, 2.0, 0.0)
		var tween := _animate_throw_arc(drop_mesh, from_pos, target_local)
		if tween:
			tween.finished.connect(
				func():
					drop_mesh.queue_free()
					add_ingredient(ingredient_type, amount)
					_drop_busy = false,
			)
			return
	# Fallback: simple vertical drop from above
	drop_mesh.position = Vector3(0.0, 5.0, 0.0)
	var target_y := 2.0
	var tween := create_tween()
	tween.tween_property(drop_mesh, "position:y", target_y, 0.3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(
		func():
			drop_mesh.queue_free()
			add_ingredient(ingredient_type, amount)
			_drop_busy = false,
	)


func _make_drop_mesh(ingredient_type: String) -> Node3D:
	match ingredient_type:
		"lemon":
			var s := load("res://assets/models/props/lemon.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.35
				return inst
		"sugar":
			var s := load("res://assets/models/props/sugar cube.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.12
				return inst
		"ice":
			var s := load("res://assets/models/props/ice cube.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.15
				return inst
	# Fallback
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	m.mesh = sphere
	return m


func sync_fill_display() -> void:
	## Set fill display directly to current volume without animating.
	## Call this after placing a pitcher so it doesn't replay 0→N.
	var vol := get_liquid_volume()
	var t := clampf(vol / MAX_FILL_VOLUME, 0.0, 1.0)
	var target_y := lerpf(ERASER_Y_EMPTY, ERASER_Y_FULL, t)
	if _lemonade_eraser != null:
		_lemonade_eraser.position.y = target_y
	update_liquid_color()


func update_liquid_color() -> void:
	var total := get_liquid_volume()
	var blended: Color
	if total <= 0.0:
		if fruit_type != "":
			blended = _get_fruit_color(fruit_type)
		else:
			blended = Color(1.0, 0.9, 0.3, 1.0)
	else:
		blended = _get_current_liquid_color()
	_apply_liquid_color(blended)


func _get_current_liquid_color() -> Color:
	var total := get_liquid_volume()
	if total <= 0.0:
		return Color(0, 0, 0, 1)
	# Pure fruit color when fruit is present; water color only when water alone
	if fruit_type != "" and fruit_count > 0.0:
		return _get_fruit_color(fruit_type)
	return water_color


func _get_fruit_color(ftype: String) -> Color:
	match ftype:
		"lemon":
			return lemon_color
		"strawberry":
			return strawberry_color
		"blueberry":
			return blueberry_color
		"peach":
			return peach_color
		"watermelon":
			return watermelon_color
		_:
			return lemon_color


func _apply_liquid_color(color: Color) -> void:
	if color == _last_liquid_color:
		return
	_last_liquid_color = color
	var mesh := $LemonadeFill/LemonadeMesh as CSGMesh3D
	if mesh == null or mesh.mesh == null:
		return
	var base_mat: Material = mesh.mesh.surface_get_material(0)
	var mat: StandardMaterial3D
	if base_mat != null:
		mat = base_mat.duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
	mat.albedo_color = color
	# CSGCombiner3D ignores .material during rebuild; must set surface material on mesh itself
	var dup_mesh := mesh.mesh.duplicate() as ArrayMesh
	dup_mesh.surface_set_material(0, mat)
	mesh.mesh = dup_mesh

	# The CSG subtractive eraser defines the material of the exposed top surface.
	# Update its material so the liquid level shows the correct color.
	var eraser := $LemonadeFill/LemonadeEraser as CSGBox3D
	if eraser != null:
		var eraser_mat: Material = eraser.material
		if eraser_mat != null:
			var dup := eraser_mat.duplicate() as StandardMaterial3D
			dup.albedo_color = color
			eraser.material = dup
		else:
			var new_mat := StandardMaterial3D.new()
			new_mat.albedo_color = color
			eraser.material = new_mat
		# Nudge eraser to force CSGCombiner3D to rebuild with new materials
		eraser.position.y += 0.0001
		eraser.position.y -= 0.0001


func _on_debug_empty_pitcher() -> void:
	_clear_and_return()
