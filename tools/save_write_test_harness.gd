extends "res://scripts/systems/save_manager.gd"

var fail_replace := false
var fail_target := ""


func _ready() -> void:
	pass


func _replace_save_file(source: String, target: String) -> Error:
	if fail_replace and (fail_target == "" or target == fail_target):
		return ERR_CANT_CREATE
	return DirAccess.rename_absolute(source, target)
