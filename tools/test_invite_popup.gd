extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Control.new()
	root.add_child(world)
	current_scene = world
	var anchor := Control.new()
	anchor.name = "InviteAnchor"
	anchor.position = Vector2(1100, 150)
	world.add_child(anchor)
	var popup: CanvasLayer = load("res://scripts/ui/invite_popup.gd").new()
	world.add_child(popup)
	await popup.show_invite(1, "Test friend")
	var panel := popup.get_child(0) as Control
	var landing_x := anchor.position.x - panel.size.x
	check(panel.position.x > landing_x, "invite starts right of landing position")
	await create_timer(0.4).timeout
	check(is_equal_approx(panel.position.x, landing_x), "invite slides left to landing position")
	check(
		is_equal_approx(panel.get_global_rect().end.x, anchor.position.x),
		"invite right edge lands at anchor and content extends left",
	)
	check(is_equal_approx(panel.position.y, anchor.position.y), "invite keeps anchor height")
	check(panel.get_global_rect().end.x <= 1280, "invite stays within the screen")
	await popup.hide_popup()
	check(not popup.visible, "invite hides after rightward slide")
	world.free()
	print("INVITE POPUP: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
