class_name AssistantInteractable
extends Interactable
## Child of an Assistant. Clicking opens the pay/task menu.


func interact(_player: Node) -> void:
	var a := get_parent() as Assistant
	if a != null:
		AssistantMenu.open(a)


func set_highlight(on: bool) -> void:
	_clear_highlight_outlines()
	var a := get_parent() as Assistant
	if on and a != null:
		_apply_outline(get_parent(), true)


func get_hint(_player: Node) -> String:
	var a := get_parent() as Assistant
	if a == null:
		return ""
	if not a.wage_paid:
		return "Assistant | LMB: pay ($%.2f/day)" % Assistant.WAGE
	if a.role == "":
		return "Assistant | LMB: assign task"
	return "Assistant | LMB: manage (%s)" % a.role.capitalize()
