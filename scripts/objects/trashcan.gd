class_name Trashcan
extends Interactable
## Interactable trashcan. Accepts held items marked as trash and refunds money.

@export var empty_box_refund: float = 1.0

const TRASH_SCENE: PackedScene = preload("res://trash.tscn")


func _ready() -> void:
	add_to_group("trashcan")


func get_hint(player: Node) -> String:
	if not _is_valid_player(player):
		return ""
	if _is_holding_trash(player):
		var refund := _get_refund(player)
		return "LMB: trash for $%.2f" % refund
	return "LMB: Trashcan"


func interact(player: Node) -> void:
	if not _is_valid_player(player):
		return
	if not _is_holding_trash(player):
		return
	var refund := _get_refund(player)
	var trash_type := _get_trash_type(player)
	if refund > 0.0:
		GameState.add_money(refund)
	EventBus.trash_disposed.emit(trash_type, refund)
	_spawn_disposed_trash()
	player.clear_held()


func _spawn_disposed_trash() -> void:
	if TRASH_SCENE == null:
		return
	var trash := TRASH_SCENE.instantiate() as Node3D
	if trash == null:
		return
	if trash is Area3D:
		trash.monitoring = false
		trash.monitorable = false
	get_tree().current_scene.add_child(trash)
	var start := global_position + Vector3.UP * 1.0
	var end := global_position + Vector3.UP * 0.2
	trash.global_position = start
	var tw := create_tween()
	tw.tween_property(trash, "global_position", end, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tw.tween_callback(trash.queue_free)


func _is_valid_player(player: Node) -> bool:
	return player != null and player.has_method("clear_held") and player.has_method("set_held")


func _is_holding_trash(player: Node) -> bool:
	var data: Dictionary = player.get("held_item_data")
	return data.get("is_trash", false)


func _get_refund(player: Node) -> float:
	var data: Dictionary = player.get("held_item_data")
	var base: float = data.get("trash_value", empty_box_refund)
	var bonus: float = 1.0 + UpgradeManager.get_effect_total("trash_rebate")
	return base * bonus


func _get_trash_type(player: Node) -> String:
	var data: Dictionary = player.get("held_item_data")
	if data.get("is_equipment", false):
		return data.get("equipment_type", "equipment")
	var ingredient_type: String = data.get("ingredient_type", "")
	if ingredient_type != "":
		return ingredient_type
	return "trash"
