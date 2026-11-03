extends "res://scripts/systems/save_manager.gd"

var restore_calls := 0


func _ready() -> void:
	pass


func _do_respawn() -> void:
	restore_calls += 1
