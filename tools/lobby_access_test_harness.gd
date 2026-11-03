extends "res://scripts/multiplayer/lobby_manager.gd"

var test_sender := 3


func _ready() -> void:
	pass


func _sender_id() -> int:
	return test_sender


func _broadcast_roster() -> void:
	pass


func free_stand() -> int:
	return _first_free_stand()


func choose_stand(index: int) -> void:
	_request_set_stand(index)
