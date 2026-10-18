class_name DenominationItem
extends Interactable
## A physical coin or bill sitting on the counter next to the cash register.
## Clicking it adds this denomination's value to the current tendered amount.

@export var cents: int = 1

var _base_scale: Vector3
var _base_pos: Vector3
var _fx_tween: Tween
var _hovered: bool = false


func _ready() -> void:
	_base_scale = scale
	_base_pos = position


func interact(_player: Node) -> void:
	var reg := _find_register()
	if reg:
		AudioManager.play_sfx("coins" if cents < 100 else "cash", global_position, -1.0, 0.1)
		reg.add_denomination(cents)
		_play_click_fx()


func get_hint(_player: Node) -> String:
	var reg := _find_register()
	if reg == null or not reg.is_active:
		return ""
	return "Cash | LMB: add %s" % _label()


func set_highlight(on: bool) -> void:
	_clear_highlight_outlines()
	_hovered = on
	# Only highlight this item's own mesh, not siblings.
	if on:
		_apply_outline($Mesh, true)
	_play_hover_fx(on)


## Hover pop: grow slightly and lift off the counter.
func _play_hover_fx(on: bool) -> void:
	if _fx_tween and _fx_tween.is_running():
		_fx_tween.kill()
	_fx_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var target_scale := _base_scale * (1.1 if on else 1.0)
	var target_pos := _base_pos + Vector3(0, 0.01 if on else 0.0, 0)
	_fx_tween.set_parallel(true)
	_fx_tween.tween_property(self, "scale", target_scale, 0.12)
	_fx_tween.tween_property(self, "position", target_pos, 0.12)


## Click squash: quick dip then spring back to whichever scale applies.
func _play_click_fx() -> void:
	if _fx_tween and _fx_tween.is_running():
		_fx_tween.kill()
	var rest_scale := _base_scale * (1.1 if _hovered else 1.0)
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "scale", _base_scale * 0.9, 0.06) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "scale", rest_scale, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _find_register() -> CashRegisterProp:
	# Denominations [Node3D] → CashRegisterProp
	var parent := get_parent()
	if parent and parent.get_parent() is CashRegisterProp:
		return parent.get_parent() as CashRegisterProp
	return null


func _label() -> String:
	return "¢%d" % cents if cents < 100 else "$%d" % (cents / 100)
