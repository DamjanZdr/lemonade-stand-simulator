@tool
class_name UpgradeTreeNode
extends Node2D
## A single node in the upgrade skill tree. Place these in upgrade_tree.tscn.
## Use the inspector buttons to create connected nodes in any direction.
## At runtime, UpgradeManager reads the tree scene to build the graph.

## Which upgrade this node grants when purchased.
@export var upgrade: UpgradeDefinition = null

## Cost to purchase this specific node.
@export var cost: float = 50.0

## Is this the root node? (Only one per tree.)
@export var is_root: bool = false

## Connected nodes in each direction (used for tree traversal and rendering).
@export var connection_up: NodePath = NodePath("")
@export var connection_down: NodePath = NodePath("")
@export var connection_left: NodePath = NodePath("")
@export var connection_right: NodePath = NodePath("")

## Grid spacing for new node creation.
const GRID_SPACING := 80.0

## Editor buttons to create connected nodes.
@export_tool_button("Create Node Above") var _btn_up = _create_above
@export_tool_button("Create Node Below") var _btn_down = _create_below
@export_tool_button("Create Node Left") var _btn_left = _create_left
@export_tool_button("Create Node Right") var _btn_right = _create_right


func _create_above() -> void:
	_create_connected_node(Vector2(0, -GRID_SPACING), "up")


func _create_below() -> void:
	_create_connected_node(Vector2(0, GRID_SPACING), "down")


func _create_left() -> void:
	_create_connected_node(Vector2(-GRID_SPACING, 0), "left")


func _create_right() -> void:
	_create_connected_node(Vector2(GRID_SPACING, 0), "right")


func _create_connected_node(offset: Vector2, direction: String) -> void:
	if not Engine.is_editor_hint():
		return
	var new_node := UpgradeTreeNode.new()
	new_node.name = _generate_node_name()
	new_node.position = position + offset
	get_parent().add_child(new_node)
	new_node.owner = get_tree().edited_scene_root
	# Set the connection on this node
	var path_to_new := get_path_to(new_node)
	match direction:
		"up":
			connection_up = path_to_new
			new_node.connection_down = new_node.get_path_to(self)
		"down":
			connection_down = path_to_new
			new_node.connection_up = new_node.get_path_to(self)
		"left":
			connection_left = path_to_new
			new_node.connection_right = new_node.get_path_to(self)
		"right":
			connection_right = path_to_new
			new_node.connection_left = new_node.get_path_to(self)
	notify_property_list_changed()
	queue_redraw()
	get_parent().queue_redraw() if get_parent() else null


func _generate_node_name() -> String:
	var parent := get_parent()
	if parent == null:
		return "TreeNode_1"
	var count := 0
	for child in parent.get_children():
		if child is UpgradeTreeNode:
			count += 1
	return "TreeNode_%d" % (count + 1)


func get_connections() -> Array[UpgradeTreeNode]:
	var result: Array[UpgradeTreeNode] = []
	for path in [connection_up, connection_down, connection_left, connection_right]:
		if path == NodePath(""):
			continue
		var node := get_node_or_null(path)
		if node is UpgradeTreeNode:
			result.append(node)
	return result


func get_connection_pairs() -> Array[Dictionary]:
	## Returns [{direction, node}] for non-empty connections.
	var result: Array[Dictionary] = []
	var paths := {
		"up": connection_up,
		"down": connection_down,
		"left": connection_left,
		"right": connection_right,
	}
	for dir in paths:
		var path: NodePath = paths[dir]
		if path == NodePath(""):
			continue
		var node := get_node_or_null(path)
		if node is UpgradeTreeNode:
			result.append({ "direction": dir, "node": node })
	return result


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Draw the node circle
	var radius := 16.0
	var color := Color(0.4, 0.4, 0.4)
	if is_root:
		color = Color(0.9, 0.7, 0.2)
		radius = 20.0
	elif upgrade != null:
		match upgrade.category:
			"equipment":
				color = Color(0.3, 0.7, 0.3)
			"customer":
				color = Color(0.7, 0.4, 0.25)
			"recipe":
				color = Color(0.3, 0.5, 0.7)
			"economy":
				color = Color(0.7, 0.6, 0.25)
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color.WHITE, 2.0)
	# Draw label
	var label_text := "ROOT" if is_root else ""
	if not is_root and upgrade != null:
		label_text = upgrade.display_name if upgrade.display_name != "" else str(upgrade.id)
	if label_text != "":
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-label_text.length() * 3.0, 4.0),
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			10,
			Color.WHITE,
		)
	# Draw cost
	if not is_root:
		var cost_str := "$%.0f" % cost
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-cost_str.length() * 3.0, radius + 14.0),
			cost_str,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			9,
			Color(0.9, 0.8, 0.3),
		)
	# Draw connections
	for pair in get_connection_pairs():
		var target: UpgradeTreeNode = pair["node"]
		var target_pos := target.position - position
		draw_line(Vector2.ZERO, target_pos, Color(0.6, 0.5, 0.3), 2.0)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
