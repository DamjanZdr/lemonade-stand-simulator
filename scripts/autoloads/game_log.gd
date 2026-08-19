extends Node
## Simple file logger + in-memory buffer. Writes to user://game_log.txt so
## we can see output even when running outside the editor. Also keeps a
## rolling buffer of recent log lines and emits a signal so the in-game
## DebugConsolePanel can display them live.

signal log_added(msg: String)

const MAX_BUFFER: int = 200

var _buffer: Array[String] = []


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
	_buffer.append(msg)
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	log_added.emit(msg)


## Public log method for other scripts to use.
func log(msg: String) -> void:
	_write(msg)
	print(msg)


## Get all buffered log lines as a single string.
func get_buffer_text() -> String:
	return "\n".join(_buffer)


## Copy the full buffer to the OS clipboard.
func copy_to_clipboard() -> void:
	DisplayServer.clipboard_set(get_buffer_text())


## Clear the buffer and the log file.
func clear() -> void:
	_buffer.clear()
	var path := "user://game_log.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("")
		file.close()
