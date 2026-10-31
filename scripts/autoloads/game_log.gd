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

## --- Frame-spike diagnostics (temporary) ---
## mark() stamps the current action; when a frame exceeds SPIKE_FRAME_MS
## we log the frame cost plus the recent marks so the log shows WHAT the
## player was doing when the hitch happened.
const SPIKE_FRAME_MS := 30.0
const HOT_PATH_US := 3000.0

var _marks: Array = []
var _last_frame_usec: int = 0


func mark(label: String) -> void:
	_marks.append([Engine.get_process_frames(), label])
	if _marks.size() > 8:
		_marks.pop_front()


func time_log(label: String, start_usec: int) -> void:
	var dt := Time.get_ticks_usec() - start_usec
	if float(dt) > HOT_PATH_US:
		log("[SPIKE] %s took %.1fms" % [label, float(dt) / 1000.0])


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
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		var frame_ms := float(now - _last_frame_usec) / 1000.0
		if frame_ms > SPIKE_FRAME_MS:
			var recent: Array[String] = []
			for m in _marks:
				recent.append(str(m[1]))
			log("[SPIKE] frame %.0fms marks=%s" % [frame_ms, ", ".join(recent)])
	_last_frame_usec = now


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
