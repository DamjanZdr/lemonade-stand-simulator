class_name PedestrianPath
extends Marker3D
## Drop this script on any Marker3D in the world to define a pedestrian route.
## This node is the spawn point (NPCs appear here).
## Drag PedestrianWaypoint nodes into [waypoints] — NPCs walk through them in order and despawn.
## [spawn_weight] lets busier paths spawn more often.

@export var waypoints: Array[PedestrianWaypoint] = []
@export_range(0.1, 10.0, 0.1) var spawn_weight: float = 1.0


func _ready() -> void:
	add_to_group("pedestrian_paths")
