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
	_infer_stand_owner()
	_build_collider()
	_build_indicator()
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	_update_indicator.call_deferred()


## Map this mailbox to the stand that belongs to its player house.
## Co-op uses player_house / StandUnit; versus also uses player_house2 / StandUnit2.
func _infer_stand_owner() -> void:
	if stand_owner != "":
		return
	var parent_name := str(get_parent().name).to_lower()
	if parent_name == "player_house2":
		stand_owner = "StandUnit2"
	elif parent_name == "player_house":
		stand_owner = "StandUnit"


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
	# World-space (not fixed_size) — the icon shrinks with distance.
	circle.pixel_size = 0.009
	_indicator.add_child(circle)
	var mark := Label3D.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.font = INDICATOR_FONT
	mark.font_size = 96
	mark.modulate = Color(1.0, 1.0, 1.0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The glyph's visual center sits above its baseline/origin, so lower
	# the label so the "!" is centered inside the circle rather than
	# aligned with the top edge.
	mark.position = Vector3(0.0, -0.09, 0.0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.render_priority = 1
	mark.pixel_size = 0.0092
	mark.font_size = 120
	mark.outline_size = 0
	# Lower and nudge right so the "!" stays optically centered in the bigger circle.
	mark.position = Vector3(0.0, -0.13, 0.0)
	mark.offset = Vector2(8.0, 0.0)
	_indicator.add_child(mark)
	add_child(_indicator)
	_indicator.visible = false


## Soft-edged, slightly transparent yellow circle — the "unread mail" bubble.
func _make_circle_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.47
	var edge := size * 0.50
	var yellow := Color(1.0, 0.92, 0.1, 1.0)
	for y in range(size):
		for x in range(size):
			var d := (Vector2(x, y) - center).length()
			if d <= radius:
				img.set_pixel(x, y, yellow)
			elif d <= edge:
				var t := (d - radius) / (edge - radius)
				img.set_pixel(x, y, Color(yellow.r, yellow.g, yellow.b, 1.0 - t))
	return ImageTexture.create_from_image(img)


## True if this mailbox belongs to the local player's assigned stand.
func _is_local_stand_mailbox() -> bool:
	if stand_owner == "":
		return true
	var player := WorldSync.get_local_player()
	if player == null:
		return false
	if not ("assigned_stand" in player):
		return false
	var stand: Node = player.assigned_stand
	if stand != null and is_instance_valid(stand):
		return stand.name == stand_owner
	if "assigned_stand_name" in player:
		return player.assigned_stand_name == stand_owner
	return false


func _has_unread_report() -> bool:
	if _seen:
		return false
	if not _is_local_stand_mailbox():
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
	_indicator.visible = (DayManager.current_phase == DayManager.Phase.DAY and _has_unread_report())


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
