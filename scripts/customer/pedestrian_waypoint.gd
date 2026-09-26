class_name PedestrianWaypoint
extends Marker3D
## A single point on a pedestrian path.
## Add this as a node type directly ("Add Child Node → PedestrianWaypoint"),
## position it in the world, then drag it into a PedestrianPath's waypoints list.
##
## If [convertable] is ticked, a pedestrian arriving here will roll [convert_chance].
## In multiplayer/versus the probability is driven by the [target_stand]'s
## popularity; if left empty, the nearest StandUnit is resolved at runtime.

## Whether this waypoint gives the pedestrian a chance to become a customer.
@export var convertable: bool = false

## Which stand's popularity controls conversion at this point. Empty = nearest.
@export var target_stand: NodePath = ^""

var _resolved_stand: StandUnit = null


## Resolves the StandUnit this waypoint converts for. If [target_stand] is set,
## that node is used; otherwise the nearest StandUnit is cached.
func get_target_stand() -> StandUnit:
	if _resolved_stand != null and is_instance_valid(_resolved_stand):
		return _resolved_stand
	if not target_stand.is_empty():
		_resolved_stand = get_node_or_null(target_stand) as StandUnit
		if _resolved_stand != null:
			return _resolved_stand
	var best: StandUnit = null
	var best_dist := INF
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("stand"):
		var s := n as StandUnit
		if s == null or not s.is_inside_tree():
			continue
		var d := global_position.distance_squared_to(s.global_position)
		if d < best_dist:
			best_dist = d
			best = s
	_resolved_stand = best
	return best
