class_name Trashcan
extends Interactable
## Interactable trashcan. Accepts held items marked as trash and refunds money.

@export var empty_box_refund: float = 0.25

const _VARIANT_SCENES: Dictionary = {
	"apple": "res://scenes/objects/trash_apple.tscn",
	"banana": "res://scenes/objects/trash_banana.tscn",
	"can": "res://scenes/objects/trash_can.tscn",
	"cigarettes": "res://scenes/objects/trash_cigarettes.tscn",
	"cup": "res://scenes/objects/trash_cup.tscn",
}


func _ready() -> void:
	add_to_group("trashcan")


func get_hint(player: Node) -> String:
	if not _is_valid_player(player):
		return ""
	var p := player as Player
	if p == null:
		return ""
	if p.held_item_data.get("is_trash", false):
		var refund := _get_refund(player)
		return "Trashcan | LMB: trash for $%.2f" % refund
	if p.held_item == HeldItem.CONTAINER:
		var ctype: String = p.held_item_data.get("container_type", "")
		if ctype == "pitcher" and p.held_item_data.get("has_liquid", false):
			return "Trashcan | empty the pitcher first!"
		var cost := _get_container_refund(p.held_item_data)
		return "Trashcan | LMB: recycle for $%.2f" % cost
	if p.held_item == HeldItem.CUP_EMPTY:
		return "Trashcan | LMB: trash cup for $%.2f" % _get_cup_refund()
	if p.held_item == HeldItem.CUP_FILLED:
		return "Trashcan | LMB: dump cup (no refund)"
	if p.held_item == HeldItem.SUPPLY_BOX:
		var box_data: Dictionary = p.held_item_data
		if box_data.get("is_equipment", false):
			var eq_type: String = box_data.get("equipment_type", "")
			var cost := _get_container_cost_for_trash(eq_type) + empty_box_refund
			return "Trashcan | LMB: recycle for $%.2f" % cost
		return "Trashcan | LMB: sell for $%.2f" % _get_supply_box_refund(box_data)
	return "Trashcan"


## Refund for a supply box: flat scrap value plus half the value of any
## contents still inside. Never exceeds what the remaining stock cost,
## so dumping ingredients for cash is always a loss.
func _get_supply_box_refund(box_data: Dictionary) -> float:
	var amount: float = float(box_data.get("amount", 0.0))
	var itype: String = box_data.get("ingredient_type", "")
	var contents := Balancing.CONTENTS_REFUND_RATIO * Balancing.supply_unit_cost(itype) * amount
	# A loose scoop taken from a bin is also held as SUPPLY_BOX
	# (source == "bin_scoop") but carries no box — paying scrap on top
	# made one lemon refund $0.45 against a $0.40 unit cost.
	if box_data.get("source", "") == "bin_scoop":
		return contents
	if amount <= 0.0:
		return empty_box_refund
	return empty_box_refund + contents


## Refund for a held container: 70% of the container cost plus 50% of
## any stock still inside (bins/bowls/buckets). Pitcher contents are
## liquid — those must be emptied before recycling, checked upstream.
func _get_container_refund(data: Dictionary) -> float:
	var ctype: String = data.get("container_type", "")
	var refund := _get_container_cost_for_trash(ctype)
	return refund + Balancing.CONTENTS_REFUND_RATIO * _container_contents_value(data)


## Resale value of whatever stock is left inside a held container.
func _container_contents_value(data: Dictionary) -> float:
	match data.get("container_type", ""):
		"sugar_bin":
			return float(data.get("saved_amount", 0.0)) \
					* Balancing.supply_unit_cost("sugar")
		"ice_bin":
			return float(data.get("saved_amount", 0.0)) \
					* Balancing.supply_unit_cost("ice")
		"cup_stack":
			return float(data.get("saved_count", 0)) \
					* Balancing.supply_unit_cost("cups")
		"fruit_bin":
			var total := 0.0
			var amounts: Dictionary = data.get("saved_recipe", { }).get("fruit_amounts", { })
			for ftype in amounts:
				total += float(amounts[ftype]) * Balancing.supply_unit_cost(ftype)
			return total
	return 0.0


## Resale value of one clean, empty cup.
func _get_cup_refund() -> float:
	return Balancing.CONTENTS_REFUND_RATIO * Balancing.supply_unit_cost("cups")


func interact(player: Node) -> void:
	if not _is_valid_player(player):
		return
	var p := player as Player
	if p == null:
		return
	if p.held_item_data.get("is_trash", false):
		var refund := _get_refund(player)
		var trash_type := _get_trash_type(player)
		var stand_name := _get_player_stand_name(p)
		# Route through host so money and trash disposal sync correctly
		if WorldSync.is_host():
			apply_trash_disposal(trash_type, refund, stand_name)
		else:
			_request_trash_disposal.rpc_id(1, trash_type, refund, stand_name)
		_finish_held_disposal(p)
		return
	if p.held_item == HeldItem.CONTAINER:
		var ctype: String = p.held_item_data.get("container_type", "")
		if ctype == "pitcher" and p.held_item_data.get("has_liquid", false):
			EventBus.interaction_hint_changed.emit("Empty the pitcher first!")
			return
		var refund := _get_container_refund(p.held_item_data)
		var stand_name := _get_player_stand_name(p)
		if WorldSync.is_host():
			apply_trash_disposal(ctype, refund, stand_name)
		else:
			_request_trash_disposal.rpc_id(1, ctype, refund, stand_name)
		_finish_held_disposal(p)
		return
	if p.held_item == HeldItem.CUP_EMPTY:
		var refund := _get_cup_refund()
		var stand_name := _get_player_stand_name(p)
		if WorldSync.is_host():
			apply_trash_disposal("cup", refund, stand_name)
		else:
			_request_trash_disposal.rpc_id(1, "cup", refund, stand_name)
		_finish_held_disposal(p)
		return
	if p.held_item == HeldItem.CUP_FILLED:
		var stand_name := _get_player_stand_name(p)
		if WorldSync.is_host():
			apply_trash_disposal("cup", 0.0, stand_name)
		else:
			_request_trash_disposal.rpc_id(1, "cup", 0.0, stand_name)
		_finish_held_disposal(p)
		return
	if p.held_item == HeldItem.SUPPLY_BOX:
		# Unopened equipment/ingredient boxes can be sold directly.
		var box_data: Dictionary = p.held_item_data
		var stand_name := _get_player_stand_name(p)
		if box_data.get("is_equipment", false):
			var eq_type: String = box_data.get("equipment_type", "")
			var refund := _get_container_cost_for_trash(eq_type) + empty_box_refund
			if WorldSync.is_host():
				apply_trash_disposal(eq_type, refund, stand_name)
			else:
				_request_trash_disposal.rpc_id(1, eq_type, refund, stand_name)
		else:
			var trash_type: String = box_data.get("ingredient_type", "empty_box")
			var refund := _get_supply_box_refund(box_data)
			if WorldSync.is_host():
				apply_trash_disposal(trash_type, refund, stand_name)
			else:
				_request_trash_disposal.rpc_id(1, trash_type, refund, stand_name)
		_finish_held_disposal(p)
		return


func _finish_held_disposal(player: Player) -> void:
	var mesh := player.inventory.release_hand_mesh()
	player.inventory.clear_held()
	AudioManager.play_sfx("trash", global_position)
	if mesh == null or not is_instance_valid(mesh):
		return
	var start_transform := mesh.global_transform
	mesh.reparent(get_tree().current_scene)
	mesh.global_transform = start_transform
	var start_pos := mesh.global_position
	var target := global_position + Vector3.UP * 0.65
	# Arc apex: midpoint between start and target, raised to form a parabola.
	var mid := (start_pos + target) * 0.5 + Vector3.UP * 1.2
	var tween := create_tween()
	tween.set_parallel(true)
	# Fly along a quadratic bezier arc (start -> mid -> target).
	tween.tween_method(_bezier_pos.bind(start_pos, mid, target, mesh), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN_OUT
	)
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tween.tween_property(mesh, "rotation", mesh.rotation + Vector3(0.8, 1.6, 0.4), 0.45)
	tween.chain().tween_callback(mesh.queue_free)


## Quadratic bezier helper for the trash arc animation. `t` goes 0 -> 1,
## `a`/`b`/`c` are start/mid/end, `mesh` is the node to move.
func _bezier_pos(t: float, a: Vector3, b: Vector3, c: Vector3, mesh: Node3D) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	var u := 1.0 - t
	mesh.global_position = u * u * a + 2.0 * u * t * b + t * t * c


## Host-side: apply money refund. The disposable visual was removed — the
## held-item arc into the can is the only animation now.
## Public so ThrownTrash can call it when trash lands in the can.
func apply_trash_disposal(trash_type: String, refund: float, stand_name: String = "") -> void:
	if not WorldSync.is_host():
		return
	if refund > 0.0:
		_add_money_to_stand(refund, stand_name)
	EventBus.trash_disposed.emit(trash_type, refund, stand_name)


## Client -> Host RPC to request trash disposal.
@rpc("any_peer", "reliable")
func _request_trash_disposal(trash_type: String, refund: float, stand_name: String = "") -> void:
	if not WorldSync.is_host():
		return
	apply_trash_disposal(trash_type, refund, stand_name)


## Credit the refund to the correct stand. Falls back to GameState
## (legacy primary stand) if no stand is specified.
func _add_money_to_stand(refund: float, stand_name: String) -> void:
	if stand_name != "":
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.current_scene != null:
			for s in tree.current_scene.find_children("*", "StandUnit", true, false):
				if s.name == stand_name and s.has_method("add_money"):
					s.add_money(refund)
					return
	GameState.add_money(refund)


## Get the player's assigned stand name for per-stand money routing.
func _get_player_stand_name(p: Player) -> String:
	if p.assigned_stand != null and is_instance_valid(p.assigned_stand):
		return p.assigned_stand.name
	return ""


func _is_valid_player(player: Node) -> bool:
	return player != null and player.has_node("PlayerInventory")


func _is_holding_trash(player: Node) -> bool:
	var data: Dictionary = player.get("held_item_data")
	return data.get("is_trash", false)


func _get_refund(player: Node) -> float:
	var data: Dictionary = player.get("held_item_data")
	var base: float = data.get("trash_value", empty_box_refund)
	var bonus: float = 1.0 + UpgradeManager.get_effect_total("trash_rebate")
	return base * bonus


func _get_container_cost_for_trash(container_type: String) -> float:
	var cost: float = 0.0
	match container_type:
		"fruit_bin":
			cost = Balancing.CONTAINER_COST_FRUIT_BIN
		"sugar_bin":
			cost = Balancing.CONTAINER_COST_SUGAR_BIN
		"ice_bin":
			cost = Balancing.CONTAINER_COST_ICE_BIN
		"cup_stack":
			cost = Balancing.CONTAINER_COST_CUP_STACK
		"pitcher":
			cost = Balancing.CONTAINER_COST_PITCHER
		"press":
			cost = Balancing.CONTAINER_COST_PRESS
		"water_dispenser":
			cost = Balancing.CONTAINER_COST_WATER_DISPENSER
		"workstation":
			cost = Balancing.CONTAINER_COST_WORKSTATION
	return cost * 0.7


func _get_trash_type(player: Node) -> String:
	var data: Dictionary = player.get("held_item_data")
	if data.get("is_equipment", false):
		return data.get("equipment_type", "equipment")
	var ingredient_type: String = data.get("ingredient_type", "")
	if ingredient_type != "":
		return ingredient_type
	var trash_type: String = data.get("trash_type", "")
	if trash_type != "":
		return trash_type
	return "trash"
