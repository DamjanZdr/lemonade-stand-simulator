@tool
extends EditorScript

## Adds a ColorManager node under the "Managers" node of the currently open scene.


func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("No scene is currently open.")
		return

	var managers := root.get_node_or_null("Managers")
	if managers == null:
		push_error("No 'Managers' node found in the current scene.")
		return

	if managers.has_node("ColorManager"):
		push_warning("ColorManager already exists under Managers.")
		return

	var cm := Node.new()
	cm.name = "ColorManager"
	cm.set_script(preload("res://scripts/managers/color_manager.gd"))
	managers.add_child(cm)
	cm.set_owner(root)

	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()

	print("ColorManager added under Managers.")
