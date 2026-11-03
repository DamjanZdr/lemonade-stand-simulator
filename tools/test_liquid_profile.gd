extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var liquid: Script = load("res://scripts/systems/liquid_fill.gd")
	var pitcher: Node = load("res://scenes/objects/pitcher.tscn").instantiate()
	var mesh: Mesh = pitcher.get_node("LemonadeFill/LemonadeMesh").mesh
	var first: PackedVector2Array = liquid.build_profile(mesh)
	check(not first.is_empty(), "pitcher profile exists")
	var started := Time.get_ticks_usec()
	for i in range(20):
		check(liquid.build_profile(mesh) == first, "repeated profile matches original")
	print("20 repeated pitcher profiles: %.2fms" % ((Time.get_ticks_usec() - started) / 1000.0))
	var changed: PackedVector2Array = liquid.build_profile(mesh)
	changed[0] = Vector2(999, 999)
	check(liquid.build_profile(mesh) == first, "caller cannot mutate cached profile")
	var coarse: PackedVector2Array = liquid.build_profile(mesh, 1.0)
	check(liquid.build_profile(mesh) == first, "different bucket does not replace default profile")
	check(liquid.build_profile(mesh, 1.0) == coarse, "coarse profile is stable")
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	var narrow: PackedVector2Array = liquid.build_profile(cylinder)
	cylinder.top_radius = 2.0
	cylinder.bottom_radius = 2.0
	await process_frame
	var wide: PackedVector2Array = liquid.build_profile(cylinder)
	check(wide != narrow, "mesh edits invalidate cached geometry")
	check(liquid.radius_at(wide, 0.0) > 1.9, "updated radius uses new geometry")
	pitcher.free()
	print("LIQUID PROFILE: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
