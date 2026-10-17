# gdlint: disable=variable-name
extends Control

@export var Multiplayer: bool = false:
	set(value):
		Multiplayer = value
		if is_node_ready():
			%MultiplayerCheck.set_pressed_no_signal(value)


func _ready() -> void:
	%MultiplayerCheck.set_pressed_no_signal(Multiplayer)
	%MultiplayerCheck.toggled.connect(
		func(on: bool) -> void:
			Multiplayer = on,
	)
