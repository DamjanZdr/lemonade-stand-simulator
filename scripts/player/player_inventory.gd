class_name PlayerInventory
extends Node
## Manages the player's held item state and the first-person hand mesh.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")
const TRANSFER_DURATION: float = 0.16
const TRANSFER_PARTICLE_COLOR := Color(1.0, 0.9, 0.35, 1.0)
static var _soft_particle_texture: ImageTexture = null
static var _ring_texture: ImageTexture = null
const BOX_PARTICLE_COLOR := Color(0.48, 0.27, 0.12, 1.0)

## The currently held item type (from HeldItem autoload).
var held_item: int = HeldItem.NONE

## Per-item data for the held item.
var held_item_data: Dictionary = { }

## The Node3D attached to the camera hand slot.
var _held_mesh: Node3D = null
var _pickup_effect_preplayed: bool = false
var _preplayed_effect_color: Color = TRANSFER_PARTICLE_COLOR
var _preplayed_effect_position: Vector3 = Vector3.ZERO
var _skip_next_particles: bool = false

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if _player == null:
		push_warning("PlayerInventory: parent is not a Player")


## Returns a user-readable name for the held item, used by the HUD.
## Returns the currently attached hand mesh, or null if empty-handed.
func get_hand_mesh() -> Node3D:
	return _held_mesh


func get_held_item_name() -> String:
	match held_item:
		HeldItem.CUP_EMPTY:
			return "Empty Cup"
		HeldItem.CUP_FILLED:
			return "Filled Cup"
		HeldItem.SUPPLY_BOX:
			var itype: String = held_item_data.get("ingredient_type", "")
			if held_item_data.get("source") == "bin_scoop":
				return itype.capitalize()
			if itype == "cups":
				return "Cup Box"
			if held_item_data.get("is_equipment", false):
				var etype: String = held_item_data.get("equipment_type", "equipment")
				return HeldItem.container_name(etype) + " Box"
			return itype.capitalize() + " Box"
		HeldItem.CONTAINER:
			return HeldItem.container_name(held_item_data.get("container_type", ""))
		HeldItem.TRASH:
			return "Trash"
	return ""


## Attach a held item to the camera hand slot.
func set_held(item_type: int, data: Dictionary, mesh: Node3D = null) -> void:
	var picking_up := held_item == HeldItem.NONE and item_type != HeldItem.NONE
	var previous_item := held_item
	var previous_data := held_item_data
	var previous_mesh := _held_mesh
	var effect_color := _get_main_material_color(mesh if picking_up else previous_mesh)
	var effect_position := _get_transfer_world_position()
	if picking_up and _player != null and _player.is_multiplayer_authority():
		if _pickup_effect_preplayed:
			effect_color = _preplayed_effect_color
			effect_position = _preplayed_effect_position
		else:
			effect_color = _play_source_shrink(data)
	_pickup_effect_preplayed = false
	if previous_mesh and is_instance_valid(previous_mesh):
		_animate_mesh_out(previous_mesh)
		_held_mesh = null
	held_item = item_type
	held_item_data = data
	if _player != null:
		# Clear any stale meshes that may have been left behind by desyncs.
		for child in _player.hand_slot.get_children():
			child.queue_free()
		# Hand meshes are first-person only — other players never see what
		# someone is holding, so a remote player node must never attach one
		# (a host-side set_held on a remote node otherwise leaks a floating
		# mesh near that player's head until something clears it).
		if mesh and _player.is_multiplayer_authority():
			_held_mesh = mesh
			_player.hand_slot.add_child(mesh)
			_player.remove_placement_groups(mesh)
			# Hand meshes must never block the player's own raycast.
			for child in mesh.find_children("*", "CollisionShape3D", true, false):
				(child as CollisionShape3D).disabled = true
			for child in mesh.find_children("*", "StaticBody3D", true, false):
				(child as StaticBody3D).collision_layer = 0
				(child as StaticBody3D).collision_mask = 0
			_apply_hand_offset(item_type, data)
			_animate_mesh_in(mesh)
		elif mesh != null:
			mesh.queue_free()
	if _player != null:
		_player.held_item = held_item
		_player.held_item_data = held_item_data
		_player.held_mesh = _held_mesh
	EventBus.held_item_changed.emit(int(item_type), data)
	_sync_held_to_host(item_type, data)
	if _player != null and _player.is_multiplayer_authority():
		var effect_item := item_type if picking_up else previous_item
		var effect_data := data if picking_up else previous_data
		if _should_play_particles(effect_item, effect_data) and not _skip_next_particles:
			effect_color = _get_effect_color(effect_item, effect_data)
			var is_fruit: bool = effect_data.get("source", "") == "bin_scoop"
			var is_box_placement: bool = not picking_up and not is_fruit
			_play_transfer_particles(
				effect_position,
				effect_color,
				_get_particle_scale(effect_item, effect_data),
				0.5 if is_fruit else (1.5 if is_box_placement else 1.0),
				1.35 if is_box_placement else 1.0,
				0.26 if is_fruit else (0.4 if is_box_placement else 0.3),
				0.45 if is_fruit else 1.0,
			)
	_skip_next_particles = false


func _animate_mesh_in(mesh: Node3D) -> void:
	var target_scale := mesh.scale
	mesh.scale = Vector3.ZERO
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", target_scale * 1.12, TRANSFER_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(mesh, "scale", target_scale, 0.08) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _animate_mesh_out(mesh: Node3D) -> void:
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "scale", mesh.scale * 1.08, 0.05) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mesh, "scale", Vector3.ZERO, TRANSFER_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.finished.connect(mesh.queue_free)


func _get_transfer_world_position() -> Vector3:
	if _player.ray != null and _player.ray.is_colliding():
		return _player.ray.get_collision_point()
	return _player.global_position + Vector3.UP


func play_pickup_source(source: Node, single_mesh: bool = false) -> void:
	if _player == null or not _player.is_multiplayer_authority():
		return
	_preplayed_effect_color = _play_source_shrink({ }, source, single_mesh)
	_preplayed_effect_position = (
		(source as Node3D).global_position if source is Node3D else _get_transfer_world_position()
	)
	_pickup_effect_preplayed = true


func _play_source_shrink(
	data: Dictionary,
	explicit_source: Node = null,
	single_mesh: bool = false,
) -> Color:
	var hit := explicit_source
	if hit == null or not is_instance_valid(hit):
		hit = _player.last_interact_hit as Node
	if hit == null or not is_instance_valid(hit):
		hit = _player.ray.get_collider() as Node
	if hit == null or not is_instance_valid(hit):
		return TRANSFER_PARTICLE_COLOR
	var source := hit
	if not single_mesh:
		while source.get_parent() != null and not source is Interactable:
			source = source.get_parent()
	if not source is Node3D:
		return TRANSFER_PARTICLE_COLOR
	var source_3d := source as Node3D
	var meshes: Array[MeshInstance3D] = []
	if source_3d is MeshInstance3D:
		meshes.append(source_3d as MeshInstance3D)
	for child in source_3d.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.visible and mesh.mesh != null and mesh.name != "_Outline":
			meshes.append(mesh)
	if meshes.is_empty():
		return TRANSFER_PARTICLE_COLOR
	if data.get("source", "") == "bin_scoop" and not single_mesh:
		var hit_pos := _get_transfer_world_position()
		meshes.sort_custom(
			func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
				return a.global_position.distance_squared_to(hit_pos) \
						< b.global_position.distance_squared_to(hit_pos),
		)
		meshes = [meshes[0]]
	var effect_color := _get_main_material_color(meshes[0])
	var scene := get_tree().current_scene
	if scene == null:
		return effect_color
	var afterimage := Node3D.new()
	scene.add_child(afterimage)
	afterimage.global_position = _get_transfer_world_position()
	for source_mesh in meshes:
		var copy := MeshInstance3D.new()
		copy.mesh = source_mesh.mesh
		copy.material_override = source_mesh.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		afterimage.add_child(copy)
		copy.global_transform = source_mesh.global_transform
		if data.get("source", "") != "bin_scoop" and not single_mesh:
			source_mesh.visible = false
	var tween := afterimage.create_tween()
	tween.tween_property(afterimage, "scale", Vector3.ONE * 1.12, 0.04) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(afterimage, "scale", Vector3.ZERO, 0.12) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.finished.connect(afterimage.queue_free)
	return effect_color


func _get_main_material_color(node: Node) -> Color:
	if node == null or not is_instance_valid(node):
		return TRANSFER_PARTICLE_COLOR
	var candidates: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		candidates.append(node as MeshInstance3D)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.visible and mesh.mesh != null and mesh.name != "_Outline":
			candidates.append(mesh)
	for mesh in candidates:
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.material_override
			if material == null:
				material = mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				var color := (material as StandardMaterial3D).albedo_color
				if color.a > 0.05:
					return Color(color.r, color.g, color.b, 1.0)
	return TRANSFER_PARTICLE_COLOR


func _should_play_particles(item_type: int, data: Dictionary) -> bool:
	if item_type == HeldItem.SUPPLY_BOX:
		if data.get("source", "") == "bin_scoop":
			return Press.FRUIT_COLORS.has(data.get("ingredient_type", ""))
		return true
	if item_type == HeldItem.TRASH:
		return data.get("trash_type", "") == "empty_box"
	return false


func _get_effect_color(item_type: int, data: Dictionary) -> Color:
	if item_type == HeldItem.SUPPLY_BOX and data.get("source", "") == "bin_scoop":
		return Press.FRUIT_COLORS.get(data.get("ingredient_type", ""), TRANSFER_PARTICLE_COLOR)
	return BOX_PARTICLE_COLOR


func _get_particle_scale(item_type: int, data: Dictionary) -> float:
	if item_type == HeldItem.SUPPLY_BOX:
		return 0.25 if data.get("source", "") == "bin_scoop" else 2.5
	if item_type == HeldItem.TRASH and data.get("trash_type", "") == "empty_box":
		return 2.5
	return 0.25


func play_fruit_particles(
	fruit_type: String,
	world_position: Vector3,
	suppress_inventory_particles: bool = false,
) -> void:
	if not Press.FRUIT_COLORS.has(fruit_type):
		return
	_play_transfer_particles(
		world_position,
		Press.FRUIT_COLORS[fruit_type],
		0.25,
		0.5,
		1.0,
		0.26,
		0.45,
	)
	_skip_next_particles = suppress_inventory_particles


func _play_transfer_particles(
	world_position: Vector3,
	effect_color: Color,
	effect_scale: float,
	amount_multiplier: float = 1.0,
	size_multiplier: float = 1.0,
	particle_lifetime: float = 0.5,
	movement_multiplier: float = 1.0,
) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var particles := CPUParticles3D.new()
	var base_amount := 64 if effect_scale > 1.5 else (32 if effect_scale < 0.5 else 48)
	particles.amount = maxi(1, roundi(float(base_amount) * amount_multiplier))
	particles.lifetime = particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.14, 0.025, 0.14) * effect_scale
	particles.direction = Vector3.UP
	particles.spread = 18.0
	particles.initial_velocity_min = 0.08 * movement_multiplier
	particles.initial_velocity_max = 0.18 * movement_multiplier
	particles.radial_accel_min = 0.75 * movement_multiplier
	particles.radial_accel_max = 1.15 * movement_multiplier
	particles.gravity = Vector3(0.0, -0.2, 0.0)
	particles.scale_amount_min = 0.9
	particles.scale_amount_max = 1.25
	particles.hue_variation_min = -0.025
	particles.hue_variation_max = 0.025
	particles.color = effect_color
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.7))
	scale_curve.add_point(Vector2(0.12, 1.1))
	scale_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = scale_curve
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.35, 0.72, 1.0])
	fade.colors = PackedColorArray(
		[Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)],
	)
	particles.color_ramp = fade
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = (Vector2.ONE * 0.1 * clampf(effect_scale, 0.7, 2.0) * size_multiplier)
	var visual_material := StandardMaterial3D.new()
	visual_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	visual_material.vertex_color_use_as_albedo = true
	visual_material.albedo_texture = _get_soft_particle_texture()
	particle_mesh.material = visual_material
	particles.mesh = particle_mesh
	scene.add_child(particles)
	particles.global_position = world_position
	particles.emitting = true
	_play_transfer_ring(scene, world_position, effect_color, effect_scale)
	var cleanup := scene.get_tree().create_timer(particle_lifetime + 0.2)
	cleanup.timeout.connect(particles.queue_free)


func _get_soft_particle_texture() -> ImageTexture:
	if _soft_particle_texture != null:
		return _soft_particle_texture
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / 32.0
			var distance := uv.distance_to(Vector2(0.5, 0.5)) * 2.0
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 1.6)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	_soft_particle_texture = ImageTexture.create_from_image(image)
	return _soft_particle_texture


func _get_ring_texture() -> ImageTexture:
	if _ring_texture != null:
		return _ring_texture
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / 64.0
			var distance := uv.distance_to(Vector2(0.5, 0.5)) * 2.0
			var alpha := 1.0 - smoothstep(0.055, 0.14, absf(distance - 0.72))
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	_ring_texture = ImageTexture.create_from_image(image)
	return _ring_texture


func _play_transfer_ring(
	scene: Node,
	world_position: Vector3,
	effect_color: Color,
	effect_scale: float,
) -> void:
	var ring := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var ring_material := StandardMaterial3D.new()
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_material.albedo_color = effect_color
	ring_material.albedo_texture = _get_ring_texture()
	mesh.material = ring_material
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	ring.global_position = world_position + Vector3.UP * 0.015
	ring.global_rotation.x = -PI * 0.5
	var start_size := 0.06 * clampf(effect_scale, 0.6, 1.8)
	var end_size := 0.32 * clampf(effect_scale, 0.6, 1.8)
	ring.scale = Vector3.ONE * start_size
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * end_size, 0.22) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ring, "transparency", 1.0, 0.22) \
			.set_ease(Tween.EASE_IN)
	tween.finished.connect(ring.queue_free)


## Mirror this player's held state to the host so the remote-player copy's
## hand slot shows/clears the same item (e.g. the filled cup the host gave
## this player must disappear from its hand when the cup is dropped).
func _sync_held_to_host(item_type: int, data: Dictionary) -> void:
	if _player == null or not _player.is_multiplayer_authority():
		return
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	WorldSync.request_held_item_sync(item_type, data)


func _apply_hand_offset(item_type: int, data: Dictionary) -> void:
	if _held_mesh == null:
		return
	var offset := Vector3.ZERO
	match item_type:
		HeldItem.SUPPLY_BOX:
			offset = Vector3(0.1, 0.1, 0.0)
		HeldItem.CONTAINER:
			var ctype: String = data.get("container_type", "")
			if ctype in ["fruit_bin", "sugar_bin", "ice_bin"]:
				offset = Vector3(0.05, 0.05, 0.0)
		HeldItem.TRASH:
			offset = Vector3(0.1, 0.1, 0.0)
	_held_mesh.position = offset


func update_held_amount(new_amount: float) -> void:
	held_item_data["amount"] = new_amount
	if _held_mesh:
		var mesh_inst := _held_mesh as SupplyBox
		if mesh_inst and mesh_inst.is_hand_mesh:
			mesh_inst.quantity = new_amount
		var qty_text := "×%.0f" % new_amount
		for fname in ["Front", "Back", "Left", "Right", "Top"]:
			var lbl := _held_mesh.get_node_or_null("Icons/QtyLabel_" + fname) as Label3D
			if lbl == null:
				lbl = _held_mesh.get_node_or_null("QtyLabel_" + fname) as Label3D
			if lbl:
				lbl.text = qty_text
	EventBus.held_item_changed.emit(int(held_item), held_item_data)
	if _player != null:
		_player.held_item_data = held_item_data
		_player.held_mesh = _held_mesh


func release_hand_mesh() -> Node3D:
	var mesh := _held_mesh
	_held_mesh = null
	if _player != null:
		_player.held_mesh = null
	return mesh


func clear_held() -> void:
	set_held(HeldItem.NONE, { })


func make_held_trash(
	refund: float,
	trash_type: String = "empty_box",
	hand_mesh: Node3D = null,
	stand_name: String = "",
) -> void:
	if stand_name == "" and _player != null:
		var stand: Node = _player.get("assigned_stand")
		if stand != null and is_instance_valid(stand):
			stand_name = stand.name
	var data := {
		"amount": 0.0,
		"is_trash": true,
		"trash_value": refund,
		"trash_type": trash_type,
		"stand_name": stand_name,
	}
	if hand_mesh == null:
		var box_inst: SupplyBox = SUPPLY_BOX_SCENE.instantiate() as SupplyBox
		box_inst.is_hand_mesh = true
		box_inst.quantity = 0.0
		box_inst.ingredient_type = "trash"
		box_inst.scale = Vector3.ONE * (0.05 / 0.3)
		var phys := box_inst.get_node_or_null("Physics") as StaticBody3D
		if phys:
			phys.collision_layer = 0
			phys.collision_mask = 0
		hand_mesh = box_inst
	set_held(HeldItem.TRASH, data, hand_mesh)


func _process(_delta: float) -> void:
	# Safety net: if the inventory thinks the hand is empty but a mesh is still
	# attached, something leaked (often from a desynced pickup). Clean it up so
	# other players don't see a phantom held item.
	# Only run for the player we actually control; remote players' meshes are
	# replicated by the multiplayer spawner, and the owning peer must clear them.
	if _player == null or not _player.is_multiplayer_authority():
		return
	if held_item != HeldItem.NONE or _held_mesh != null:
		return
	var slot := _player.hand_slot
	if slot == null:
		return
	for child in slot.get_children():
		child.queue_free()
