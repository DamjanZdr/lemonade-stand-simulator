class_name PedestrianPath
extends Marker3D
## Drop this script on any Marker3D in the world to define a pedestrian route.
## This node is the spawn point (NPCs appear here).
## Drag PedestrianWaypoint nodes into [waypoints] — NPCs walk through them in order and despawn.
## [spawn_weight] lets busier paths spawn more often.

@export var waypoints: Array[PedestrianWaypoint] = []
@export_range(0.1, 10.0, 0.1) var spawn_weight: float = 1.0
## Disable this route whenever a second stand is active (versus mode).
## Some routes run along stand 2's queue line, which only exists in versus.
@export var single_stand_only: bool = false


func _ready() -> void:
	add_to_group("pedestrian_paths")


## Whether this route may spawn pedestrians under the current game mode.
func is_usable() -> bool:
	if waypoints.is_empty():
		return false
	if single_stand_only and LobbyManager.game_mode == GameState.GameMode.VERSUS:
		return false
	return true
