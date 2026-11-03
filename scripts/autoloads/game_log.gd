extends Node
## Simple file logger + in-memory buffer. Writes to user://game_log.txt so
## we can see output even when running outside the editor. Also keeps a
## rolling buffer of recent log lines and emits a signal so the in-game
## DebugConsolePanel can display them live.

signal log_added(msg: String)

const MAX_BUFFER: int = 200

var _buffer: Array[String] = []
var _last_frame_usec: int = 0
var _last_post_draw_usec: int = 0
var _trace_stalls: bool = false


func _ready() -> void:
	_write("=== GameLog started at %s ===" % str(Time.get_datetime_dict_from_system()))
	_trace_stalls = "--diagnose-stalls" in OS.get_cmdline_user_args()
	set_process(_trace_stalls)
	if _trace_stalls:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		RenderingServer.frame_post_draw.connect(_record_post_draw)
		self.log("[STALL] diagnostics enabled; GPU timings may lag behind the reported frame")


func _record_post_draw() -> void:
	_last_post_draw_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := now - _last_frame_usec if _last_frame_usec > 0 else 0
	_last_frame_usec = now
	if elapsed < 250000:
		return
	var viewport_rid := get_viewport().get_viewport_rid()
	self.log(
		(
			"[STALL] frame=%.1fms process=%.1fms physics=%.1fms "
			+ "render_cpu=%.1fms render_gpu=%.1fms since_post_draw=%.1fms "
			+ "mark=%s mark_age=%dms nodes=%d"
		)
		% [
			elapsed / 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
			RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
			(now - _last_post_draw_usec) / 1000.0 if _last_post_draw_usec > 0 else -1.0,
			_last_mark_label,
			Time.get_ticks_msec() - _last_mark,
			get_tree().get_node_count(),
		]
	)


func _write(msg: String) -> void:
	var path := "user://game_log.txt"
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(msg)
		file.close()
	_buffer.append(msg)
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	log_added.emit(msg)


## Public log method for other scripts to use.
func log(msg: String) -> void:
	_write(msg)
	print(msg)


var _marks: Dictionary = { }
var _last_mark: int = 0
var _last_mark_label: String = ""


## Breadcrumb marker for diagnostics — records the time since the
## previous mark under a rolling label. Silent (no file write) so hot
## paths can call it freely; used by the spike-dump tooling.
func mark(label: String) -> void:
	var now := Time.get_ticks_msec()
	_marks[label] = now
	_last_mark = now
	_last_mark_label = label


## Log how long a measured section took. t0 is a Time.get_ticks_usec()
## snapshot taken by the caller before the work ran.
func time_log(label: String, t0: int) -> void:
	var elapsed_us := Time.get_ticks_usec() - t0
	_write("[time] %s: %.1fms" % [label, elapsed_us / 1000.0])


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
