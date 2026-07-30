class_name CashPickup
extends Interactable
## Spawned when a customer pays. Click to open the cash register and make change.

var payment: float = 0.0
var change_due: float = 0.0
var _register_open: bool = false
## When true, interact() hides this node instead of queue_free().
## Use for the CashPickup placed under the NPC's CashPoint marker.
var hide_on_interact: bool = false

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var physics: Area3D = $Physics
@onready var label: Label3D = $Label


func setup(pay: float, due: float) -> void:
	payment = pay
	change_due = due
	if is_inside_tree():
		label.text = "$%.2f" % payment


func _ready() -> void:
	label.text = "$%.2f" % payment
	visibility_changed.connect(_on_visibility_changed)
	_sync_physics_visibility()


func _on_visibility_changed() -> void:
	_sync_physics_visibility()


func _sync_physics_visibility() -> void:
	if physics:
		physics.monitorable = visible
		physics.monitoring = visible


func interact(_player: Node) -> void:
	if _register_open:
		return
	_register_open = true
	EventBus.sale_initiated.emit(payment, change_due)
	if hide_on_interact:
		visible = false
		_register_open = false
	else:
		queue_free()


func get_hint(_player: Node) -> String:
	return "Cash | LMB: open register  ($%.2f bill)" % payment
