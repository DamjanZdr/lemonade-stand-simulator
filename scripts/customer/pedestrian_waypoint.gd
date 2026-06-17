class_name PedestrianWaypoint
extends Marker3D
## A single point on a pedestrian path.
## Add this as a node type directly ("Add Child Node → PedestrianWaypoint"),
## position it in the world, then drag it into a PedestrianPath's waypoints list.
##
## If [convertable] is ticked, a pedestrian arriving here will roll [convert_chance].
## On success they join the lemonade queue; on failure they continue along the path.

## Whether this waypoint gives the pedestrian a chance to become a customer.
## The actual probability is driven by GameState.popularity — see Balancing.pedestrian_convert_chance().
@export var convertable: bool = false
