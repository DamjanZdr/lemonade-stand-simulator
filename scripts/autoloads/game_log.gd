extends Node
## Simple file logger. Writes to user://game_log.txt so we can see output
## even when running outside the editor (e.g. from the project list).
## All print() calls across the codebase also get mirrored to this file.

func _ready() -> void:
	_write("=== GameLog started at %s ===" % str(Time.get_datetime_dict_from_system()))

func _write(msg: String) -> void:
	var path := "user://game_log.txt"
	var file := FileAccess.open(path, FileAccess.READ)
	var existing := ""
	if file:
		existing = file.get_as_text()
		file.close()
	file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(existing + msg + "\n")
		file.close()

## Public log method for other scripts to use.
func log(msg: String) -> void:
	_write(msg)
	print(msg)
