@tool
class_name PreviewOrbitCamera
extends Marker3D

@export var look_at_preview_center: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_look_at_preview_center()
		look_at_preview_center = false


func _look_at_preview_center() -> void:
	var preview_center := get_node_or_null("../PreviewCenter") as Marker3D
	if preview_center == null:
		push_warning("PreviewOrbitCamera: PreviewCenter not found as sibling node.")
		return
	look_at(preview_center.global_position, Vector3.UP)
	print("PreviewOrbitCamera: Looked at PreviewCenter (%s)" % str(preview_center.global_position))
