@tool
extends Node
## Holds the customizable roof and wall color palettes used by Neighborhood.


func _enter_tree() -> void:
	add_to_group("color_manager")


## Color used for roofs when the "Color Roofs" toggle is off.
## Set to Color.TRANSPARENT to keep the original roof material.
@export var roof_default_color: Color = Color(0.15, 0.15, 0.17)

## Color used for walls when the "Color Walls" toggle is off.
## Set to Color.TRANSPARENT to keep the original wall material.
@export var wall_default_color: Color = Color.TRANSPARENT


## 5 colors for the roof palette.
@export var roof_colors: Array[Color] = [
	Color(0.5, 0.25, 0.2),
	Color(0.42, 0.42, 0.45),
	Color(0.30, 0.50, 0.30),
	Color(0.15, 0.30, 0.55),
	Color(0.70, 0.70, 0.15),
]

## 5 colors for the wall palette.
@export var wall_colors: Array[Color] = [
	Color(0.95, 0.85, 0.55),
	Color(0.85, 0.55, 0.45),
	Color(0.45, 0.65, 0.85),
	Color(0.55, 0.75, 0.45),
	Color(0.75, 0.55, 0.80),
]

const _DEFAULT_ROOF_COLORS: Array[Color] = [
	Color(0.5, 0.25, 0.2),
	Color(0.42, 0.42, 0.45),
	Color(0.30, 0.50, 0.30),
	Color(0.15, 0.30, 0.55),
	Color(0.70, 0.70, 0.15),
]

const _DEFAULT_WALL_COLORS: Array[Color] = [
	Color(0.95, 0.85, 0.55),
	Color(0.85, 0.55, 0.45),
	Color(0.45, 0.65, 0.85),
	Color(0.55, 0.75, 0.45),
	Color(0.75, 0.55, 0.80),
]

@export_group("Randomize")


func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": "randomize_roofs",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
		{
			"name": "randomize_walls",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
		{
			"name": "randomize_both",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
		{
			"name": "default_roofs",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
		{
			"name": "default_walls",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
		{
			"name": "default_both",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED,
		},
	]


func _set(property: StringName, value: Variant) -> bool:
	if value != true:
		return false
	if property == &"randomize_roofs":
		_notify_randomize("roofs")
		return true
	if property == &"randomize_walls":
		_notify_randomize("walls")
		return true
	if property == &"randomize_both":
		_notify_randomize("both")
		return true
	if property == &"default_roofs":
		_notify_default("roofs")
		return true
	if property == &"default_walls":
		_notify_default("walls")
		return true
	if property == &"default_both":
		_notify_default("both")
		return true
	return false


func _get(property: StringName) -> Variant:
	if (
		property == &"randomize_roofs" or property == &"randomize_walls"
		or property == &"randomize_both" or property == &"default_roofs"
		or property == &"default_walls" or property == &"default_both"
	):
		return false
	return null


func _notify_randomize(target: String) -> void:
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("neighborhood"):
			if node.has_method("randomize_house_colors"):
				node.call("randomize_house_colors", target)


func _notify_default(target: String) -> void:
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("neighborhood"):
			if node.has_method("default_house_colors"):
				node.call("default_house_colors", target)
