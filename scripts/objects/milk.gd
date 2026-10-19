class_name Milk
extends Interactable
## Easter egg: click the rooftop milk carton and it pops away.
## Awards ACH_HE_WAS_HERE to the clicking peer — achievements are
## per-Steam-account, matching AchievementManager's design.

var _popped: bool = false


func interact(_player: Node) -> void:
	if _popped:
		return
	# Runs on the clicking peer — unlocks for their own Steam account.
	AchievementManager.unlock(AchievementManager.ACH_HE_WAS_HERE)
	if multiplayer.has_multiplayer_peer():
		_pop.rpc()
	else:
		_pop()


func get_hint(_player: Node) -> String:
	return ""


@rpc("any_peer", "call_local", "reliable")
func _pop() -> void:
	if _popped:
		return
	_popped = true
	AudioManager.play_sfx("task_done", global_position)
	# Punch out briefly, then shrink to nothing — the "pop" disappearing act.
	var tween := create_tween()
	tween.tween_property(self, "scale", scale * 1.15, 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3(0.001, 0.001, 0.001), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(
		func():
			visible = false
			var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
			if cs:
				cs.disabled = true,
	)
