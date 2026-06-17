extends CanvasLayer
## Cash register UI.
## Opens when the player clicks the customer's payment bill on the counter.
## Player clicks denomination buttons to accumulate change; confirms with Give Change.
## Money earned = customer payment − change tendered (overpaying is the player's loss).

# Denomination values in cents to avoid floating-point accumulation errors.
const DENOM_CENTS: Array[int] = [1, 5, 10, 50, 100, 500]

var _payment_cents: int = 0
var _change_due_cents: int = 0
var _tendered_cents: int = 0

@onready var _panel:          PanelContainer = $Panel
@onready var _paid_lbl:       Label = $Panel/Margin/VBox/PaidLabel
@onready var _due_lbl:        Label = $Panel/Margin/VBox/DueLabel
@onready var _tendered_lbl:   Label = $Panel/Margin/VBox/TenderedLabel
@onready var _denom_row:      HBoxContainer = $Panel/Margin/VBox/DenomRow
@onready var _clear_btn:      Button = $Panel/Margin/VBox/BtnRow/ClearBtn
@onready var _give_btn:       Button = $Panel/Margin/VBox/BtnRow/GiveBtn
@onready var _status_lbl:     Label = $Panel/Margin/VBox/StatusLabel


func _ready() -> void:
	EventBus.sale_initiated.connect(_on_sale_initiated)
	_clear_btn.pressed.connect(_on_clear_pressed)
	_give_btn.pressed.connect(_on_give_pressed)

	# Wire each denomination button in the order they appear in DenomRow.
	var btns := _denom_row.get_children()
	for i in btns.size():
		var btn := btns[i] as Button
		var cents := DENOM_CENTS[i]
		btn.pressed.connect(func(): _add_cents(cents))


func _on_sale_initiated(payment: float, change_due: float) -> void:
	_payment_cents     = roundi(payment    * 100.0)
	_change_due_cents  = roundi(change_due * 100.0)
	_tendered_cents    = 0
	_refresh()
	_panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _add_cents(cents: int) -> void:
	_tendered_cents += cents
	_refresh()


func _on_clear_pressed() -> void:
	_tendered_cents = 0
	_refresh()


func _on_give_pressed() -> void:
	var earned_cents := _payment_cents - _tendered_cents
	EventBus.change_finalized.emit(earned_cents / 100.0)
	_panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	_paid_lbl.text     = "Customer paid:   $%.2f" % (_payment_cents     / 100.0)
	_due_lbl.text      = "Change due:      $%.2f" % (_change_due_cents  / 100.0)
	_tendered_lbl.text = "Tendered:        $%.2f" % (_tendered_cents     / 100.0)

	_give_btn.disabled = _tendered_cents < _change_due_cents

	if _tendered_cents > _change_due_cents:
		var over_cents := _tendered_cents - _change_due_cents
		_status_lbl.text = "⚠  Overpaying by $%.2f — your loss!" % (over_cents / 100.0)
	else:
		_status_lbl.text = ""
