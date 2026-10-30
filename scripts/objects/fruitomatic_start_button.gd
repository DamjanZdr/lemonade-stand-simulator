extends Interactable
## World-space START button under a fruit stock label on the Fruit-O-Matic.
## Clicking asks the machine to begin a batch with this fruit — the same
## host action the on-screen fruit picker sends.

@export var fruit := ""

@onready var _label: Label3D = get_node_or_null("Label3D")
@onready var _button_mesh: MeshInstance3D = get_node_or_null("ButtonMesh")
var _engaged := false
var _rest_pos := Vector3.ZERO


func _ready() -> void:
	_rest_pos = position


func _machine() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("request_action") and node.has_method("can_attach_pitcher"):
			return node
		node = node.get_parent()
	return null


func can_player_use(player: Node) -> bool:
	var machine := _machine()
	return machine == null or machine.can_player_use(player)


func interact(player: Node) -> void:
	var machine := _machine()
	if machine == null:
		return
	# If the batch can't start, keep the camera on the machine — the
	# flashing X and the hint need to be seen, not raced past.
	if machine.has_method("predict_mix_problem") and player is Player:
		var problem: String = machine.predict_mix_problem(player, fruit)
		if problem != "":
			machine.show_result(problem)
			return
	machine.request_action(player, "mix:" + fruit)
	# A batch actually starting ends the focused camera view — send it
	# back to the player's head.
	if machine.has_method("close_fruit_select"):
		machine.close_fruit_select()


## Held sunk into the panel while the machine mixes this fruit's batch;
## clicks back out when the batch finishes. Driven from
## FruitOMatic.refresh_stock_panels so it follows replicated state too.
func set_engaged(engaged: bool) -> void:
	if _engaged == engaged:
		return
	_engaged = engaged
	# Sink along the button's own normal — the buttons are tilted to match
	# the sloped machine face, so -z in parent space isn't the press axis.
	var sink := basis.z.normalized() * 0.006
	var tween := create_tween()
	if engaged:
		tween.tween_property(self, "position", _rest_pos - sink, 0.1)
	else:
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position", _rest_pos, 0.25)


func get_hint(player: Node) -> String:
	if not can_player_use(player):
		return "Other stand's Fruit-O-Matic"
	return "Start %s" % fruit.capitalize()


## Dimmed when nothing is stocked — click still works, the machine's own
## message explains what's missing. Uses a darker tint, not alpha: the
## label renders alpha-scissored, so a translucent modulate would cut the
## glyph interior and leave only a ghost outline.
func set_available(available: bool) -> void:
	if _label != null:
		_label.modulate = Color(1, 1, 1) if available else Color(0.4, 0.4, 0.4)
