extends "res://scripts/player/player_inventory.gd"


func clear_freed_mesh() -> bool:
	_held_mesh = Node3D.new()
	_held_mesh.free()
	clear_held()
	return typeof(_held_mesh) == TYPE_NIL


func hand_animation_stays_invertible() -> bool:
	var model := Node3D.new()
	model.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(model)
	model.scale = Vector3.ONE * 0.03
	_animate_mesh_in(model)
	var valid := model.transform.basis.determinant() != 0.0
	for i in range(30):
		await get_tree().create_timer(0.01).timeout
		valid = valid and model.transform.basis.determinant() != 0.0
	_animate_mesh_out(model)
	for i in range(30):
		await get_tree().create_timer(0.01).timeout
		if is_instance_valid(model):
			valid = valid and model.transform.basis.determinant() != 0.0
	if is_instance_valid(model):
		model.free()
	return valid
