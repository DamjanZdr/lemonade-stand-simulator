class_name MoneyDenomination
extends Interactable
## A single clickable bill/coin (or coin stack) under the player's camera.
## Clicking it adds its value to the MoneyController's tendered amount.

@export var cents: int = 1

var _controller: MoneyController = null


func _ready() -> void:
	_controller = get_parent() as MoneyController


func interact(_player: Node) -> void:
	if _controller:
		AudioManager.play_sfx("coins" if cents < 100 else "cash", global_position, -1.0, 0.1)
		_controller.add_denomination(cents)


func get_hint(_player: Node) -> String:
	return ""
