class_name DenominationItem
extends Interactable
## A physical coin or bill sitting on the counter next to the cash register.
## Clicking it adds this denomination's value to the current tendered amount.

@export var cents: int = 1


func interact(_player: Node) -> void:
	var reg := _find_register()
	if reg:
		reg.add_denomination(cents)


func get_hint(_player: Node) -> String:
	var reg := _find_register()
	if reg == null or not reg.is_active:
		return ""
	return "Add %s" % _label()


func set_highlight(on: bool) -> void:
	# Only highlight this item's own mesh, not siblings.
	_apply_outline($Mesh, on)


func _find_register() -> CashRegisterProp:
	# Denominations [Node3D] → CashRegisterProp
	var parent := get_parent()
	if parent and parent.get_parent() is CashRegisterProp:
		return parent.get_parent() as CashRegisterProp
	return null


func _label() -> String:
	return "¢%d" % cents if cents < 100 else "$%d" % (cents / 100)
