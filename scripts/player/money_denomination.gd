class_name MoneyDenomination
extends Interactable
## A single clickable bill/coin (or coin stack) under the player's camera.
## Clicking it adds its value to the MoneyController's tendered amount.

@export var cents: int = 1

var _controller: MoneyController = null
var _base_scale: Vector3
var _base_pos: Vector3
var _fx_tween: Tween
var _hovered: bool = false


func _ready() -> void:
	_controller = get_parent() as MoneyController
	_base_scale = scale
	_base_pos = position


func interact(_player: Node) -> void:
	if _controller:
		AudioManager.play_sfx("coins" if cents < 100 else "cash", global_position, -1.0, 0.1)
		_controller.add_denomination(cents)
		_play_click_fx()


func get_hint(_player: Node) -> String:
	return ""


func set_highlight(on: bool) -> void:
	super(on)
	_hovered = on
	_play_hover_fx(on)


## Hover pop: subtle grow and a small lift off the tray — kept small so
## enlarged bills don't swallow the coins sitting on top of them.
func _play_hover_fx(on: bool) -> void:
	if _fx_tween and _fx_tween.is_running():
		_fx_tween.kill()
	_fx_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var target_scale := _base_scale * (1.08 if on else 1.0)
	var target_pos := _base_pos + Vector3(0, 0.008 if on else 0.0, 0)
	_fx_tween.set_parallel(true)
	_fx_tween.tween_property(self, "scale", target_scale, 0.12)
	_fx_tween.tween_property(self, "position", target_pos, 0.12)


## Click squash: quick dip then spring back to whichever scale applies.
func _play_click_fx() -> void:
	if _fx_tween and _fx_tween.is_running():
		_fx_tween.kill()
	var rest_scale := _base_scale * (1.08 if _hovered else 1.0)
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "scale", _base_scale * 0.92, 0.06) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "scale", rest_scale, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
