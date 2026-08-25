class_name Trashcan
extends Interactable
## Interactable trashcan. Accepts held items marked as trash and refunds money.

@export var empty_box_refund: float = 1.0

const TRASH_SCENE: PackedScene = preload("res://scenes/objects/trash.tscn")


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
		var cost := _get_container_cost_for_trash(ctype)
		return "Trashcan | LMB: recycle for $%.2f" % cost
	return "Trashcan | LMB: pick up"


func interact(player: Node) -> void:
	if not _is_valid_player(player):
		print("[Trashcan] _is_valid_player failed")
		return
	var p := player as Player
	if p == null:
		print("[Trashcan] player cast failed")
		return
	print(
		"[Trashcan] interact called, held_item=%d, is_trash=%s, trash_type=%s"
		% [p.held_item, p.held_item_data.get("is_trash", false), p.held_item_data.get(
				"trash_type",
				"",
			)]
	)
	if p.held_item_data.get("is_trash", false):
		var refund := _get_refund(player)
		var trash_type := _get_trash_type(player)
		# Route through host so money and trash disposal sync correctly
		if WorldSync.is_host():
			_apply_trash_disposal(trash_type, refund)
		else:
			_request_trash_disposal.rpc_id(1, trash_type, refund)
		AudioManager.play_sfx("trash", global_position)
		player.inventory.clear_held()
		return
	if p.held_item == HeldItem.CONTAINER:
		var ctype: String = p.held_item_data.get("container_type", "")
		var refund := _get_container_cost_for_trash(ctype)
		if WorldSync.is_host():
			_apply_trash_disposal(ctype, refund)
		else:
			_request_trash_disposal.rpc_id(1, ctype, refund)
		AudioManager.play_sfx("trash", global_position)
		player.inventory.clear_held()
		return


## Host-side: apply money refund and spawn trash visual.
func _apply_trash_disposal(trash_type: String, refund: float) -> void:
	if not WorldSync.is_host():
		return
	if refund > 0.0:
		GameState.add_money(refund)
	EventBus.trash_disposed.emit(trash_type, refund)
	_spawn_disposed_trash(trash_type)


## Client -> Host RPC to request trash disposal.
@rpc("any_peer", "reliable")
func _request_trash_disposal(trash_type: String, refund: float) -> void:
	if not WorldSync.is_host():
		return
	_apply_trash_disposal(trash_type, refund)


func _spawn_disposed_trash(trash_type: String = "") -> void:
	if TRASH_SCENE == null:
		return
	if not WorldSync.is_host():
		return
	var start := global_position + Vector3.UP * 1.0
	var end := global_position + Vector3.UP * 0.2
	var state: Dictionary = { }
	if trash_type != "":
		state["trash_type"] = trash_type
	var trash := WorldSync.spawn_networked(
		"res://scenes/objects/trash.tscn",
		get_tree().current_scene,
		start,
		Vector3.ZERO,
		state,
	) as Node3D
	if trash == null:
		return
	if trash is Area3D:
		trash.monitoring = false
		trash.monitorable = false
	if trash_type != "" and trash.has_method("show_variant"):
		trash.show_variant(trash_type)
	var tw := create_tween()
	tw.tween_property(trash, "global_position", end, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tw.tween_callback(WorldSync.request_despawn.bind(trash))


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
