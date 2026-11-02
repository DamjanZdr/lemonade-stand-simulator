extends "res://scripts/multiplayer/world_sync.gd"


func capture_container(node: Node) -> Dictionary:
	return _serialize_container(node)


func reset_client_ids() -> void:
	_net_id_to_node.clear()
	_node_to_net_id.clear()


func apply_container(entry: Dictionary, world: Node) -> void:
	_spawn_container_from_snapshot(entry, world)
