@tool
extends EditorScript
## Run this from the Script Editor (File > Run) while npc.tscn is open
## and the Skeleton3D bone poses are set to the payment pose.

func _run() -> void:
	var editor := EditorInterface.get_selection()
	var selected := editor.get_selected_nodes()
	if selected.is_empty():
		print("Select a Skeleton3D node first!")
		return
	
	var skel := selected[0] as Skeleton3D
	if skel == null:
		print("Selected node is not a Skeleton3D!")
		return
	
	print("// Paste this into npc_appearance.gd start_payment_pose():")
	for bone_name in ["UpperArm.R", "Forearm.R", "Hand.R"]:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			print("// Bone not found: ", bone_name)
			continue
		var pose: Quaternion = skel.get_bone_pose_rotation(idx)
		print('skel.set_bone_pose_rotation(skel.find_bone("%s"), Quaternion(%f, %f, %f, %f))' % [bone_name, pose.x, pose.y, pose.z, pose.w])
