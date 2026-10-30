extends Node
## Simple file logger + in-memory buffer. Writes to user://game_log.txt so
## we can see output even when running outside the editor. Also keeps a
## rolling buffer of recent log lines and emits a signal so the in-game
## DebugConsolePanel can display them live.

signal log_added(msg: String)

const MAX_BUFFER: int = 200

var _buffer: Array[String] = []
var _file: FileAccess = null
var _flush_timer: float = 0.0


func _ready() -> void:
	# Keep the file open for the session — open/seek/close per log line
	# made every interaction pay several disk syscalls (visible hitches
	# in multiplayer, where each action logs on every peer).
	_file = FileAccess.open("user://game_log.txt", FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open("user://game_log.txt", FileAccess.WRITE)
	if _file:
		_file.seek_end()
	_write("=== GameLog started at %s ===" % str(Time.get_datetime_dict_from_system()))


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer >= 2.0:
		_flush_timer = 0.0
		if _file:
			_file.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _file:
		_file.flush()
		_file.close()
		_file = null


func _write(msg: String) -> void:
	if _file:
		_file.store_line(msg)
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
