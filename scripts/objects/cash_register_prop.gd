class_name CashRegisterProp
extends Interactable
## Physical 3D cash register sitting on the back counter.
## Label3D nodes on the register body display live payment info.
## Denomination items (DenominationItem children) are separate Interactables.
## Click the register body itself to confirm and give change.

var is_active: bool = false
var _payment_cents: int = 0
var _change_due_cents: int = 0
var _tendered_cents: int = 0

@onready var _calc_lbl:   Label3D = $CalcLabel
@onready var _action_lbl: Label3D = $ActionLabel
@onready var _denominations: Node3D = $Denominations
@onready var _shelf: Node3D = $MoneyShelf
@onready var _body: Node3D = $BodyMesh  # The main register body to slide

var _register_rest_pos: Vector3 = Vector3.ZERO
var _register_slide_pos: Vector3 = Vector3(0, 0, -0.4)  # Slide 0.4 units backward on Z


func _ready() -> void:
	EventBus.sale_initiated.connect(_on_sale_initiated)
	EventBus.change_finalized.connect(_on_change_finalized)
	# Hide all interactive elements at startup
	_denominations.visible = false
	_calc_lbl.visible = false
	_action_lbl.visible = false
	is_active = false
	# Store register rest position (we move the whole register, shelf moves with it)
	_register_rest_pos = position


# --- Interactable overrides ---

func interact(_player: Node) -> void:
	if not is_active or _tendered_cents < _change_due_cents:
		return
	_give_change()


func get_hint(_player: Node) -> String:
	if not is_active:
		return "Click the bill on the counter to open register"
	var gap := _change_due_cents - _tendered_cents
	if gap > 0:
		return "Need $%.2f more change" % (gap / 100.0)
	if _tendered_cents > _change_due_cents:
		return "Click register: Give Change  (overpaying $%.2f)" % \
				((_tendered_cents - _change_due_cents) / 100.0)
	return "Click register: Give Change ✓"


func set_highlight(on: bool) -> void:
	# Only highlight when active (during sale)
	if not is_active:
		_apply_outline($BodyMesh, false)
		return
	# Highlight only the register body, not denomination children.
	_apply_outline($BodyMesh, on)


# --- Called by DenominationItem children ---

func add_denomination(cents: int) -> void:
	if not is_active:
		return
	_tendered_cents += cents
	_refresh()


# --- Internal ---

func _on_sale_initiated(payment: float, change_due: float) -> void:
	_payment_cents    = roundi(payment    * 100.0)
	_change_due_cents = roundi(change_due * 100.0)
	_tendered_cents   = 0
	_set_active(true)
	_refresh()
	_slide_register_out()


func _on_change_finalized(_earned: float) -> void:
	_slide_register_back()


func _slide_register_out() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", _register_rest_pos + _register_slide_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _slide_register_back() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", _register_rest_pos, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _give_change() -> void:
	var earned := (_payment_cents - _tendered_cents) / 100.0
	EventBus.change_finalized.emit(earned)
	_set_active(false)


func _set_active(on: bool) -> void:
	is_active = on
	_denominations.visible = on
	_calc_lbl.visible = on
	_action_lbl.visible = on


func _refresh() -> void:
	var paid   := _payment_cents / 100.0
	var price  := (_payment_cents - _change_due_cents) / 100.0
	var change := _change_due_cents / 100.0
	_calc_lbl.text = "$%.2f - $%.2f =\n$%.2f" % [paid, price, change]

	var gap := _change_due_cents - _tendered_cents
	if gap > 0:
		_action_lbl.text = "$%.2f more" % (gap / 100.0)
	elif _tendered_cents > _change_due_cents:
		_action_lbl.text = "⚠ Over $%.2f" % ((_tendered_cents - _change_due_cents) / 100.0)
	else:
		_action_lbl.text = "✓ Click to confirm"
