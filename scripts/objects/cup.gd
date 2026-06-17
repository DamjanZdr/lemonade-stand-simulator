class_name Cup
extends Interactable
## A single paper cup. Starts EMPTY; becomes FILLED when the pitcher pours into it.
## Player picks it up and hands it to the customer at the counter.

const CUP_GLB: PackedScene = preload("res://blender/cup.glb")

enum CupState { EMPTY, FILLED }

var state: CupState = CupState.EMPTY
var recipe: Dictionary = {}

@onready var model: Node3D = $Model
@onready var physics: StaticBody3D = $Physics

var _cup_fill_mesh: Node = null


func _ready() -> void:
	_cup_fill_mesh = model.find_child("CupFill", true, false)
	_refresh_fill_visibility()


func fill(recipe_snapshot: Dictionary) -> void:
	state = CupState.FILLED
	recipe = recipe_snapshot
	_refresh_fill_visibility()


func interact(player: Node) -> void:
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return
	match state:
		CupState.EMPTY:
			physics.collision_layer = 0
			model.visible = false
			p.set_held(p.HeldItem.CUP_EMPTY, {}, _make_hand_mesh(false))
			queue_free()
		CupState.FILLED:
			physics.collision_layer = 0
			model.visible = false
			p.set_held(p.HeldItem.CUP_FILLED, { "recipe": recipe }, _make_hand_mesh(true))
			queue_free()


func get_hint(player: Node) -> String:
	var p := player as Player
	if p == null or p.held_item != p.HeldItem.NONE:
		return ""
	return "Click: pick up %s cup" % ("filled" if state == CupState.FILLED else "empty")


func _refresh_fill_visibility() -> void:
	if _cup_fill_mesh:
		_cup_fill_mesh.visible = (state == CupState.FILLED)


static func make_hand_mesh(filled: bool) -> Node3D:
	var inst := CUP_GLB.instantiate() as Node3D
	inst.scale = Vector3.ONE * 0.05
	var fill_node := inst.find_child("CupFill", true, false)
	if fill_node:
		fill_node.visible = filled
	return inst


func _make_hand_mesh(filled: bool) -> Node3D:
	return Cup.make_hand_mesh(filled)
