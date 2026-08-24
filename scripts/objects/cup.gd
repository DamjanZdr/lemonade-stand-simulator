class_name Cup
extends Interactable
## A single paper cup. Starts EMPTY; becomes FILLED when the pitcher pours into it.
## Player picks it up and hands it to the customer at the counter.

const CUP_GLB: PackedScene = preload("res://assets/models/props/cup.glb")

enum CupState {
	EMPTY,
	FILLED,
}

var state: CupState = CupState.EMPTY
var recipe: Dictionary = { }
var fill_color: Color = Color(1.0, 0.9, 0.3, 1.0)

@onready var model: Node3D = $Model
@onready var physics: StaticBody3D = $Physics

var _cup_fill_mesh: Node = null


func _ready() -> void:
	_cup_fill_mesh = model.find_child("Fill", true, false)
	_refresh_fill_visibility()


func fill(recipe_snapshot: Dictionary) -> void:
	state = CupState.FILLED
	recipe = recipe_snapshot
	fill_color = recipe_snapshot.get("color", fill_color)
	_refresh_fill_visibility()
	apply_fill_color()


func interact(player: Node) -> void:
	var p := player as Player
	if p == null or p.held_item != HeldItem.NONE:
		return
	match state:
		CupState.EMPTY:
			physics.collision_layer = 0
			model.visible = false
			p.set_held(HeldItem.CUP_EMPTY, { }, _make_hand_mesh(false))
			queue_free()
		CupState.FILLED:
			physics.collision_layer = 0
			model.visible = false
			p.set_held(HeldItem.CUP_FILLED, { "recipe": recipe }, _make_hand_mesh(true))
			queue_free()


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null or p.held_item != HeldItem.NONE:
		return ""
	return "Cup | LMB: pick up %s cup" % ("filled" if state == CupState.FILLED else "empty")


func _refresh_fill_visibility() -> void:
	if _cup_fill_mesh:
		_cup_fill_mesh.visible = (state == CupState.FILLED)


static func make_hand_mesh(filled: bool, color: Color = Color(1.0, 0.9, 0.3, 1.0)) -> Node3D:
	var inst := CUP_GLB.instantiate() as Node3D
	inst.scale = Vector3.ONE * 0.05
	var fill_node := inst.find_child("Fill", true, false)
	if fill_node:
		fill_node.visible = filled
		if filled:
			_apply_fill_color_to_node(fill_node, color)
	return inst


static func _apply_fill_color_to_node(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var base_mat := mi.mesh.surface_get_material(0)
			if base_mat != null:
				var mat := base_mat.duplicate() as StandardMaterial3D
				mat.albedo_color = color
				mi.material_override = mat
				return
	# If the node itself isn't a MeshInstance3D, search its children
	for child in node.get_children(true):
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var base_mat := mi.mesh.surface_get_material(0)
				if base_mat != null:
					var mat := base_mat.duplicate() as StandardMaterial3D
					mat.albedo_color = color
					mi.material_override = mat


func apply_fill_color() -> void:
	if _cup_fill_mesh == null:
		return
	_apply_fill_color_to_node(_cup_fill_mesh, fill_color)


func _make_hand_mesh(filled: bool) -> Node3D:
	return Cup.make_hand_mesh(filled, fill_color)
