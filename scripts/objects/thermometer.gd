extends Node3D
## Maps live weather temperature to a 3D thermometer visual.

const MIN_TEMP_C: float = 10.0
const MAX_TEMP_C: float = 40.0

const ERASER_Y_EMPTY: float = 0.170
const ERASER_Y_FULL: float = 5.8

@onready var eraser: CSGBox3D = $CSGCombiner3D/CSGBox3D
@onready var _label_c: Label3D = $LabelC
@onready var _label_f: Label3D = $LabelF


func _ready() -> void:
	_update_display(GameState.temperature)
	EventBus.weather_changed.connect(_on_weather_changed)


func _on_weather_changed(temp: float) -> void:
	_update_display(temp)


func _update_display(temp_c: float) -> void:
	var t := clampf((temp_c - MIN_TEMP_C) / (MAX_TEMP_C - MIN_TEMP_C), 0.0, 1.0)
	var target_y := lerpf(ERASER_Y_EMPTY, ERASER_Y_FULL, t)
	if eraser != null:
		eraser.position.y = target_y

	var temp_f := temp_c * 9.0 / 5.0 + 32.0
	if _label_c != null:
		_label_c.text = "%.0f°C" % temp_c
	if _label_f != null:
		_label_f.text = "%.0f°F" % temp_f
