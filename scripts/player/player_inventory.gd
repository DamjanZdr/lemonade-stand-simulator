class_name PlayerInventory
extends Node
## Manages the player's held item state and the first-person hand mesh.

const SUPPLY_BOX_SCENE: PackedScene = preload("res://scenes/objects/supply_box.tscn")

## The currently held item type (from HeldItem autoload).
var held_item: int = HeldItem.NONE

## Per-item data for the held item.
var held_item_data: Dictionary = { }

## The Node3D attached to the camera hand slot.
var _held_mesh: Node3D = null

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	if _player == null:
		push_warning("PlayerInventory: parent is not a Player")


## Returns a user-readable name for the held item, used by the HUD.
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
				return etype.capitalize().replace("_", " ") + " Box"
			return itype.capitalize() + " Box"
		HeldItem.CONTAINER:
			return held_item_data.get("container_type", "").capitalize().replace("_", " ")
		HeldItem.TRASH:
			return "Trash"
	return ""


## Attach a held item to the camera hand slot.
func set_held(item_type: int, data: Dictionary, mesh: Node3D = null) -> void:
	if _held_mesh and is_instance_valid(_held_mesh):
		_held_mesh.queue_free()
		_held_mesh = null
	held_item = item_type
	held_item_data = data
	if mesh and _player != null:
		_held_mesh = mesh
		_player.hand_slot.add_child(mesh)
		_player._remove_placement_groups(mesh)
		_apply_hand_offset(item_type, data)
	if _player != null:
		_player.held_item = held_item
		_player.held_item_data = held_item_data
		_player._held_mesh = _held_mesh
	EventBus.held_item_changed.emit(int(item_type), data)


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
		_player._held_mesh = _held_mesh


func clear_held() -> void:
	set_held(HeldItem.NONE, { })


func make_held_trash(
	refund: float,
	trash_type: String = "empty_box",
	hand_mesh: Node3D = null,
) -> void:
	var data := { "amount": 0.0, "is_trash": true, "trash_value": refund, "trash_type": trash_type }
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
