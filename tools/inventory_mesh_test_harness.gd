extends "res://scripts/player/player_inventory.gd"


func clear_freed_mesh() -> bool:
	_held_mesh = Node3D.new()
	_held_mesh.free()
	clear_held()
	return typeof(_held_mesh) == TYPE_NIL
