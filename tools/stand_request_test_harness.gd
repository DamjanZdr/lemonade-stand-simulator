extends "res://scripts/multiplayer/world_sync.gd"


func register_object(obj: Node) -> int:
	return _assign_net_id(obj)


func send_property(obj: Node, net_id: int, value: bool) -> void:
	_rpc_request_property.rpc_id(
		1, str(obj.get_parent().get_path()), str(obj.name), net_id, "visible", value,
	)


func send_call(obj: Node, net_id: int) -> void:
	_rpc_request_call.rpc_id(1, str(obj.get_parent().get_path()), str(obj.name), net_id, "hide", [])


func send_action(net_id: int, action: String, args: Array) -> void:
	_rpc_request_container_action.rpc_id(1, net_id, action, args)


func send_despawn(obj: Node, net_id: int) -> void:
	_rpc_request_despawn.rpc_id(1, str(obj.get_parent().get_path()), str(obj.name), net_id, false)
