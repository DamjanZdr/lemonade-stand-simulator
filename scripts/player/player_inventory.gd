class_name PlayerInventory
extends Node
## Manages the player's held item state and the first-person hand mesh.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")
const TRANSFER_DURATION: float = 0.16

## The currently held item type (from HeldItem autoload).
var held_item: int = HeldItem.NONE

## Per-item data for the held item.
var held_item_data: Dictionary = { }

## The Node3D attached to the camera hand slot.
var _held_mesh: Node3D = null
var _pickup_effect_preplayed: bool = false

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
	var previous_mesh := _held_mesh
	if picking_up and _player != null and _player.is_multiplayer_authority():
		if not _pickup_effect_preplayed:
			_play_source_shrink(data)
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
	_play_source_shrink({ }, source, single_mesh)
	_pickup_effect_preplayed = true


func _play_source_shrink(
	data: Dictionary,
	explicit_source: Node = null,
	single_mesh: bool = false,
) -> void:
	var hit := explicit_source
	if hit == null or not is_instance_valid(hit):
		hit = _player.last_interact_hit as Node
	if hit == null or not is_instance_valid(hit):
		hit = _player.ray.get_collider() as Node
	if hit == null or not is_instance_valid(hit):
		return
	var source := hit
	if not single_mesh:
		while source.get_parent() != null and not source is Interactable:
			source = source.get_parent()
	if not source is Node3D:
		return
	var source_3d := source as Node3D
	var meshes: Array[MeshInstance3D] = []
	if source_3d is MeshInstance3D:
		meshes.append(source_3d as MeshInstance3D)
	for child in source_3d.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.visible and mesh.mesh != null and mesh.name != "_Outline":
			meshes.append(mesh)
	if meshes.is_empty():
		return
	if data.get("source", "") == "bin_scoop" and not single_mesh:
		var hit_pos := _get_transfer_world_position()
		meshes.sort_custom(
			func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
				return a.global_position.distance_squared_to(hit_pos) \
						< b.global_position.distance_squared_to(hit_pos),
		)
		meshes = [meshes[0]]
	var scene := get_tree().current_scene
	if scene == null:
		return
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
