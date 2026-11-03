extends "res://scripts/autoloads/achievement_manager.gd"


func _unlock(id: String) -> void:
	_unlocked[id] = true
