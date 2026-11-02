extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var sync := root.get_node("WorldSync")
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var actor_script: Script = load("res://tools/local_player_test_actor.gd")
	var remote: Node = scene.instantiate()
	remote.set_script(actor_script)
	remote.set_multiplayer_authority(2)
	remote.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(remote)
	check(sync.get_local_player() == null, "remote-only startup has no local player")
	var local: Node = scene.instantiate()
	local.set_script(actor_script)
	local.set_multiplayer_authority(1)
	local.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(local)
	var stand: Node = load("res://scripts/stand/stand_unit.gd").new()
	stand.name = "StandUnit2"
	local.assigned_stand = stand
	local.assigned_stand_name = "StandUnit2"
	check(sync.get_local_player() == local, "local spawn replaces remote fallback")
	check(sync.get_local_stand_name() == "StandUnit2", "shop resolves joiner's own stand")
	check(sync.get_local_stand() == stand, "local stand lookup resolves the owned stand")
	local.set_multiplayer_authority(2)
	remote.set_multiplayer_authority(1)
	check(sync.get_local_player() == remote, "cached player is revalidated after authority change")
	world.free()
	stand.free()
	print("LOCAL PLAYER IDENTITY: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
