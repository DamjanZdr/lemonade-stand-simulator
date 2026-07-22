extends Node
## Central config node for all upgrade definitions.
## Add this under Managers in the world scene.
## Tweak effect_per_node, display_name, description, etc. for each upgrade
## from the inspector instead of hunting down individual .tres files.

@export var upgrades: Array[UpgradeDefinition] = []


func get_upgrades() -> Array[UpgradeDefinition]:
	return upgrades
