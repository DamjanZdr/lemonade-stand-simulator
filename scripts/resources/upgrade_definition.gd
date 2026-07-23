class_name UpgradeDefinition
extends Resource
## Defines a single upgrade type. Multiple tree nodes can reference the same definition.
## Effects stack additively: total_effect = number_of_purchased_nodes * effect_per_node.

## Unique identifier, e.g., "press_speed", "marketing".
@export var id: StringName = &""

## Display name shown to the player.
@export var display_name: String = ""

## Short description of what this upgrade does.
@export_multiline var description: String = ""

## Optional icon displayed on tree nodes.
@export var icon: Texture2D = null

## Category for coloring/grouping: "equipment", "customer", "recipe", "economy".
@export_enum("equipment", "customer", "recipe", "economy") var category: String = "equipment"

## How much effect each purchased node of this type adds.
@export var effect_per_node: float = 0.1

## Maximum number of nodes of this type that can exist in the tree (0 = unlimited).
@export var max_nodes: int = 0

## Per-node cost. The last value repeats for higher nodes if fewer values are provided than nodes.
@export var costs: Array[float] = []

## Per-node effect. The last value repeats for higher nodes if fewer values are provided than nodes.
@export var effects: Array[float] = []
