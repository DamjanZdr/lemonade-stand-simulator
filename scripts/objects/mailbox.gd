extends Interactable
## Player-house mailbox. Every morning a "!" bubble appears above it while
## the previous day's report is unread. Interacting opens the day-report
## panel (DaySummary.show_report()).
##
## The report data lives on each StandUnit's last_day_stats (synced from
## the host), so opening the mail is a purely local UI action — no RPC.
## Only the two player-house mailboxes carry this script; the decorative
## mailboxes under NonPlayableArea stay plain GLB instances.

const INDICATOR_FONT: Font = preload("res://assets/fonts/Grandstander-clean.ttf")

var _indicator: Node3D = null
var _seen: bool = true # starts read — day 1 has no report


func _ready() -> void:
	_build_collider()
	_build_indicator()
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_update_indicator.call_deferred()


## The mailbox GLB has no physics body, so give it a simple box for the
## interaction raycast to hit (and so it blocks nothing weirdly).
func _build_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "MailboxBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Node scale is 0.6 — local sizes map to ~60% in world space.
	box.size = Vector3(1.0, 2.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_indicator() -> void:
	_indicator = Node3D.new()
	_indicator.name = "MailIndicator"
	_indicator.position = Vector3(0.0, 2.4, 0.0)
	var circle := Sprite3D.new()
	circle.name = "Circle"
	circle.texture = _make_circle_texture(128)
	circle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	circle.no_depth_test = true
	circle.fixed_size = true
	circle.pixel_size = 0.0035
	_indicator.add_child(circle)
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.font = INDICATOR_FONT
	mark.font_size = 96
	mark.modulate = Color(0.15, 0.08, 0.02)
	mark.outline_size = 0
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = true
	mark.pixel_size = 0.0035
	_indicator.add_child(mark)
	add_child(_indicator)
	_indicator.visible = false


## Soft-edged yellow circle with a dark rim — the "unread mail" bubble.
func _make_circle_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var outer := size * 0.48
	var inner := size * 0.40
	for y in range(size):
		for x in range(size):
			var d := (Vector2(x, y) - center).length()
			if d <= inner:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.25, 1.0))
			elif d <= outer:
				img.set_pixel(x, y, Color(0.15, 0.08, 0.02, 1.0))
	return ImageTexture.create_from_image(img)


func _has_unread_report() -> bool:
	if _seen:
		return false
	for stand in get_tree().get_nodes_in_group("stand"):
		if stand.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var stats: Variant = stand.get("last_day_stats")
		if stats is Dictionary and not stats.is_empty():
			return true
	return false


func _update_indicator() -> void:
	if _indicator == null:
		return
	_indicator.visible = (
		DayManager.current_phase == DayManager.Phase.DAY
		and _has_unread_report()
	)


func _on_day_phase_changed(phase: int, _day: int) -> void:
	if phase == DayManager.Phase.EVENING:
		# A new report was just captured — mark it unread for the morning.
		_seen = false
	_update_indicator()


func interact(_player: Node) -> void:
	_seen = true
	_update_indicator()
	var report := get_tree().get_first_node_in_group("day_summary")
	if report != null and report.has_method("show_report"):
		AudioManager.play_sfx_ui("tab_click")
		report.show_report()


func get_hint(_player: Node) -> String:
	if _has_unread_report():
		return "Mailbox | LMB: read daily report"
	return "Mailbox | LMB: check mail"
