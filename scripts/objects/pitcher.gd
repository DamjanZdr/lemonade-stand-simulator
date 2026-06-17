class_name Pitcher
extends Interactable
## Three-state pitcher: PREPPING → COMPLETE → SERVING → PREPPING
##
## PREPPING: sits on prep table; player scoops ingredients in from bins.
## COMPLETE: has lemon+water ready; can still add sugar/ice until first cup poured.
## SERVING:  placed anywhere; player with empty cup clicks to fill a cup.

enum PitcherState { PREPPING, COMPLETE, SERVING }

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

var _fill_stages: Array[Node3D] = []
var _drop_busy: bool = false # true while a drop animation is playing
var _eraser_tween: Tween = null
var _press_eraser_tween: Tween = null
var _suppress_eraser_updates: bool = false

const ERASER_Y_EMPTY: float = 1.752
const ERASER_Y_FULL: float = 5.245
const MAX_FILL_VOLUME: float = 10.0

const _FILL_PATHS: Array = [
	"res://blender/lemonade 0.glb",
	"res://blender/lemonade 1.glb",
	"res://blender/lemonade 2.glb",
	"res://blender/lemonade 3.glb",
	"res://blender/lemonade 4.glb",
	"res://blender/lemonade 5.glb",
	"res://blender/lemonade 6.glb",
	"res://blender/lemonade 7.glb",
	"res://blender/lemonade 8.glb",
	"res://blender/lemonade10.glb",
]


func _ready() -> void:
	add_to_group("pitcher")
	prep_position = global_position
	_prep_scale = scale
	EventBus.debug_empty_pitcher.connect(_on_debug_empty_pitcher)
	# Hide the original GLB lemonade cylinder.
	var orig := $lemonade/Cylinder_002 as MeshInstance3D
	if orig:
		orig.visible = false
	# Load each fill-stage model, add as child of $lemonade, start hidden.
	for path in _FILL_PATHS:
		var scene := load(path) as PackedScene
		if scene:
			var inst := scene.instantiate() as Node3D
			inst.visible = false
			inst.scale = Vector3.ONE
			_lemonade_node.add_child(inst)
			_fill_stages.append(inst)
	_fix_glass_transparency()
	_update_eraser_position()
	_update_label()


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
					"Cannot mix %s with %s!" % [
						ingredient_type.capitalize(),
						fruit_type.capitalize(),
					],
				)
				return false
			if fruit_type == "":
				fruit_type = ingredient_type
			fruit_count += amount
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
	_update_label()
	EventBus.pitcher_ingredient_added.emit(ingredient_type, amount)
	return true


func get_recipe_snapshot() -> Dictionary:
	return {
		"fruit_type": fruit_type,
		"fruit_count": fruit_count,
		"water": water,
		"sugar": sugar,
		"ice": ice,
	}


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
	# Flush floating-point dust
	if get_liquid_volume() < 0.05:
		fruit_type = ""
		fruit_count = 0.0
		water = 0.0
		sugar = 0.0
		ice = 0.0
	_update_label()
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
		scale = _prep_scale
	set_pitcher_visible(true)
	_update_label()
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

	match state:
		PitcherState.PREPPING, PitcherState.COMPLETE:
			# Deposit scoop from hand (sugar/ice only in COMPLETE state)
			if p.held_item == p.HeldItem.SUPPLY_BOX \
					and p.held_item_data.get("source") == "bin_scoop":
				if _drop_busy:
					return
				var itype: String = p.held_item_data.get("ingredient_type", "")
				var amount: float = p.held_item_data.get("amount", 0.0)
				if _can_add_ingredient(itype, amount):
					p.clear_held()
					_animate_drop(itype, amount)
				else:
					EventBus.interaction_hint_changed.emit(
						"Cannot add %s! (State: %s, Cups poured: %d)" % [
							itype,
							str(state),
							cups_poured,
						],
					)
				return
			# Fill cup if pitcher has liquid and player holds empty cup
			if p.held_item == p.HeldItem.CUP_EMPTY and get_liquid_volume() > 0.0:
				var recipe := pour_portion()
				p.set_held(p.HeldItem.CUP_FILLED, { "recipe": recipe }, _make_filled_cup_mesh())
				EventBus.pitcher_cup_filled.emit(recipe)
				if is_fully_empty():
					_clear_and_return()
				return
			# Pick up: always use container system now
			if p.held_item == p.HeldItem.NONE:
				p.pickup_container(self, "pitcher")
		PitcherState.SERVING:
			if p.held_item == p.HeldItem.CUP_EMPTY:
				var recipe := pour_portion()
				p.set_held(p.HeldItem.CUP_FILLED, { "recipe": recipe }, _make_filled_cup_mesh())
				EventBus.pitcher_cup_filled.emit(recipe)
				if is_fully_empty():
					_clear_and_return()


func interact_secondary(player: Node) -> void:
	# Only throw out if player clicks with empty hands
	var p := player as Player
	if p != null and p.held_item == p.HeldItem.NONE:
		_clear_and_return()


func try_add_ingredient(ingredient_type: String, amount: float) -> bool:
	## Public entry for press machine / automated addition.
	## Returns true if the drop animation was started.
	if _drop_busy:
		return false
	if not _can_add_ingredient(ingredient_type, amount):
		return false
	_animate_drop(ingredient_type, amount)
	return true


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null:
		return ""
	match state:
		PitcherState.PREPPING, PitcherState.COMPLETE:
			if p.held_item == p.HeldItem.SUPPLY_BOX \
					and p.held_item_data.get("source") == "bin_scoop":
				return "Click: add %s to pitcher" % p.held_item_data.get("ingredient_type", "")
			if get_liquid_volume() <= 0.0:
				return "LMB: pick up pitcher  |  RMB: pick up pitcher"
			# Has liquid, can fill cups or pick up
			if p.held_item == p.HeldItem.CUP_EMPTY:
				return "LMB: fill cup (%.1f liq)  |  RMB: pick up pitcher" % get_liquid_volume()
			return "LMB: pick up pitcher  |  RMB: throw out"
		PitcherState.SERVING:
			if p.held_item == p.HeldItem.CUP_EMPTY:
				return "LMB: fill cup (%.1f liq)  |  RMB: pick up pitcher" % get_liquid_volume()
			return "LMB: pick up pitcher  |  RMB: throw out"
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


func _make_filled_cup_mesh() -> Node3D:
	return Cup.make_hand_mesh(true)


func _update_label() -> void:
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
	contents_label.text = "%s\n%s: %.1f  Water: %.1f\nSugar: %.1f  Ice: %.1f\nCups: %d" % [
		status,
		fruit_label,
		fruit_count,
		water,
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
	water += amount
	_update_eraser_position(duration)
	_update_label()
	if fruit_count > 0.0 and water > 0.0 and state == PitcherState.PREPPING:
		state = PitcherState.COMPLETE
		EventBus.pitcher_state_changed.emit(int(state))


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


func _animate_drop(ingredient_type: String, amount: float) -> void:
	_drop_busy = true
	var drop_mesh := _make_drop_mesh(ingredient_type)
	add_child(drop_mesh)
	# Position above the pitcher opening in local space.
	# Pitcher local top is ~Y 3.6; start a bit higher so it visually falls in.
	drop_mesh.position = Vector3(0.0, 5.0, 0.0)
	var target_y := 2.0 # roughly the liquid surface level in local space
	var tween := create_tween()
	tween.tween_property(drop_mesh, "position:y", target_y, 0.3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(
		func():
			drop_mesh.queue_free()
			add_ingredient(ingredient_type, amount)
			_drop_busy = false
	)


func _make_drop_mesh(ingredient_type: String) -> Node3D:
	match ingredient_type:
		"lemon":
			var s := load("res://blender/lemon.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.35
				return inst
		"sugar":
			var s := load("res://blender/sugar cube.glb") as PackedScene
			if s:
				var inst := s.instantiate() as Node3D
				inst.scale = Vector3.ONE * 0.12
				return inst
		"ice":
			var s := load("res://blender/ice cube.glb") as PackedScene
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


func _on_debug_empty_pitcher() -> void:
	_clear_and_return()
