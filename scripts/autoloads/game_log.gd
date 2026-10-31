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
var _root_vp: RID
var _pre_draw_us: int = 0
var _post_draw_us: int = 0
# Physics tick counter sampled at post_draw — how many catch-up ticks ran
# inside the post-draw→next-process window (physics_max_steps_per_frame).
var _phys_at_post_draw: int = -1
# idle_frame fires before _process callbacks — bgap = post_draw→idle =
# present/vsync + OS events + physics + lead-in (the true mystery window).
var _idle_us: int = 0
# End of this autoload's _process — xgap = process_end→pre_draw covers
# deferred-queue/queue_free flush + RenderingServer.sync + trailing nodes.
var _proc_end_us: int = 0
# physics_frame fires at the top of SceneTree::process — pgap = post_draw→
# physics_frame = present/swap + OS event dispatch only.
var _phys_frame_us: int = 0


func mark(label: String) -> void:
	_marks.append([Engine.get_process_frames(), label])
	if _marks.size() > 8:
		_marks.pop_front()


func time_log(label: String, start_usec: int) -> void:
	var dt := Time.get_ticks_usec() - start_usec
	if float(dt) > HOT_PATH_US:
		self.log("[SPIKE] %s took %.1fms" % [label, float(dt) / 1000.0])


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
	# Per-frame render timing so spike dumps can separate RenderingServer
	# submission (rcpu) from actual GPU time (rgpu) and compositor waits.
	_root_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_root_vp, true)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_draw_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(
		func() -> void:
			_post_draw_us = Time.get_ticks_usec()
			_phys_at_post_draw = Engine.get_physics_frames()
	)
	get_tree().process_frame.connect(func() -> void: _idle_us = Time.get_ticks_usec())
	get_tree().physics_frame.connect(func() -> void: _phys_frame_us = Time.get_ticks_usec())
	if OS.get_environment("LEMON_AUTOPLAY") == "1":
		_autoplay_ready()


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
			# Engine-level attribution: if proc+physics ≪ frame, the time went
			# to render submission/GPU-sync (pipeline compile, texture upload)
			# or physics flush — not GDScript.
			var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			var nav_ms := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
			var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			var rcpu := RenderingServer.viewport_get_measured_render_time_cpu(_root_vp) / 1000.0
			var rgpu := RenderingServer.viewport_get_measured_render_time_gpu(_root_vp) / 1000.0
			# rblock = last completed draw-block duration (pre_draw→post_draw);
			# adraw = time since post_draw — the present/vsync/OS tail.
			var rblock := float(_post_draw_us - _pre_draw_us) / 1000.0
			var adraw := float(now - _post_draw_us) / 1000.0 if _post_draw_us > 0 else -1.0
			# pticks = physics ticks executed inside the adraw window —
			# a catch-up spiral would show many ticks per stalled frame.
			var pticks := Engine.get_physics_frames() - _phys_at_post_draw if _phys_at_post_draw >= 0 else -1
			var bgap := float(_idle_us - _post_draw_us) / 1000.0 if _idle_us > _post_draw_us else -1.0
			var xgap := float(_pre_draw_us - _proc_end_us) / 1000.0 if _pre_draw_us > _proc_end_us else -1.0
			var pgap := float(_phys_frame_us - _post_draw_us) / 1000.0 if _phys_frame_us > _post_draw_us else -1.0
			self.log(
				"[SPIKE] frame %.0fms proc=%.0f phys=%.0f nav=%.0f rcpu=%.0f rgpu=%.0f rblock=%.0f adraw=%.0f bgap=%.0f xgap=%.0f pgap=%.0f pticks=%.0f draw=%.0f nodes=%.0f marks=%s"
				% [
					frame_ms, proc_ms, phys_ms, nav_ms, rcpu, rgpu,
					rblock, adraw, bgap, xgap, pgap, pticks, draws, nodes, ", ".join(recent),
				]
			)
	_last_frame_usec = now
	_proc_end_us = Time.get_ticks_usec()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _file:
		_file.flush()
		_file.close()
		_file = null


## Autoplay harness: drives the same action paths as manual play so the
## spike signature can be reproduced unattended (LEMON_AUTOPLAY=1).
var _auto_tick: int = 0
var _auto_spawned: Array[Node] = []


func _autoplay_ready() -> void:
	_write("[AUTOPLAY] armed — starting a session then spawn/despawn cycling")
	var start_timer := Timer.new()
	start_timer.wait_time = 4.0
	start_timer.one_shot = true
	start_timer.timeout.connect(func() -> void:
		_write("[AUTOPLAY] load_existing_game + host_game")
		SaveManager.load_existing_game("AUTO")
		NetworkManager.host_game()
		var go := Timer.new()
		go.wait_time = 6.0
		go.one_shot = true
		go.timeout.connect(func() -> void:
			_write("[AUTOPLAY] start_game")
			LobbyManager.start_game()
		)
		go.autostart = true
		add_child(go)
	)
	start_timer.autostart = true
	add_child(start_timer)
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.timeout.connect(_autoplay_step)
	timer.autostart = true
	add_child(timer)


func _autoplay_step() -> void:
	var player := WorldSync.get_local_player() if WorldSync.has_method("get_local_player") else null
	if player == null:
		return
	var parent: Node = player.get_parent()
	var base: Vector3 = player.global_position + Vector3(1.5, 0.05, 0)
	var rot := Vector3.ZERO
	_auto_tick += 1
	mark("auto:cycle%d" % (_auto_tick % 4))
	match _auto_tick % 4:
		0:
			var n := WorldSync.spawn_networked("res://scenes/stand/workstation.tscn", parent, base, rot)
			if n: _auto_spawned.append(n)
		1:
			var n := WorldSync.spawn_networked("res://scenes/objects/cup_stack.tscn", parent, base, rot)
			if n: _auto_spawned.append(n)
		2:
			var n := WorldSync.spawn_networked("res://scenes/objects/pitcher.tscn", parent, base, rot)
			if n: _auto_spawned.append(n)
		3:
			if not _auto_spawned.is_empty():
				var n: Node = _auto_spawned.pop_back()
				if is_instance_valid(n):
					WorldSync.despawn_networked(n)


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
	# stdout goes through a pipe under Steam — dozens of prints per action
	# add per-call syscall overhead (and can stall if the reader drains
	# slowly). File logging already captures everything; only echo to the
	# console in debug builds.
	if OS.is_debug_build():
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
