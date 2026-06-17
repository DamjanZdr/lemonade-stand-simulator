extends Node
## Global Label3D style enforcer — single source of truth for all 3D world text.
##
## Change RENDER_FONT_SIZE here → text quality updates game-wide on next run.
## Change ALWAYS_IN_FRONT → depth-test behaviour updates game-wide.
## No per-scene edits ever needed.
##
## How it works:
##   • node_added catches every Label3D as it enters the tree (runtime-spawned too).
##   • A deferred full-tree traversal acts as a safety net for nodes that were
##     already in the tree before this autoload's node_added connection was live.
##     (The main scene is guaranteed to be fully loaded before the first idle frame.)
##
## Size invariant: world_height = font_size × pixel_size.
## The script keeps world_height constant while raising font_size to RENDER_FONT_SIZE.
## Example: font_size=18, pixel_size=0.002 → world_height=0.036 m.
## At RENDER_FONT_SIZE=64: pixel_size = 0.002×18/64 = 0.0005625, same world height.

## Texture pixels per glyph — raise for smoother text, lower to save VRAM.
const RENDER_FONT_SIZE: int = 64

## Set false to let 3D geometry occlude labels (e.g. for debug/hidden labels).
const ALWAYS_IN_FRONT: bool = true


func _ready() -> void:
	# Catch every future Label3D the moment it enters the tree.
	get_tree().node_added.connect(_style_if_label)
	# Deferred pass catches nodes that were already added before this signal
	# connection was live (other autoloads, or main scene loaded synchronously).
	call_deferred("_apply_to_all")


func _apply_to_all() -> void:
	_traverse(get_tree().root)


func _traverse(node: Node) -> void:
	_style_if_label(node)
	for child in node.get_children():
		_traverse(child)


func _style_if_label(node: Node) -> void:
	if not node is Label3D:
		return
	var label := node as Label3D
	# Upgrade resolution while preserving the authored physical world-space size.
	if label.font_size > 0 and label.font_size != RENDER_FONT_SIZE:
		label.pixel_size = label.pixel_size * float(label.font_size) / float(RENDER_FONT_SIZE)
		label.font_size  = RENDER_FONT_SIZE
	# Physical world labels (signs, props) opt out of always-on-top rendering
	# by setting the metadata key 'no_depth_override = true' in the scene.
	if not label.has_meta("no_depth_override"):
		label.no_depth_test = ALWAYS_IN_FRONT
