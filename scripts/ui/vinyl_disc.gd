extends Control
## Draws a small vinyl disc that spins while music is playing.
## Click is handled by the parent MusicPlayer widget.

var _angle: float = 0.0
var _spinning: bool = false
const _SPIN_SPEED: float = 120.0 # degrees per second
const _DISC_RADIUS: float = 18.0
const _LABEL_RADIUS: float = 6.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _spinning:
		_angle += _SPIN_SPEED * delta
		queue_redraw()


func set_spinning(spin: bool) -> void:
	_spinning = spin
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	# Outer disc — dark with subtle gradient rings.
	draw_circle(center, _DISC_RADIUS, Color(0.08, 0.08, 0.08, 0.9))
	# Grooves — concentric circles.
	for i in range(1, 5):
		var r := _DISC_RADIUS - i * 3.0
		if r > _LABEL_RADIUS:
			draw_arc(center, r, 0, TAU, 32, Color(1, 1, 1, 0.06), 0.5)
	# Center label — golden.
	draw_circle(center, _LABEL_RADIUS, Color(1, 0.85, 0.4, 0.8))
	# Spindle hole.
	draw_circle(center, 1.5, Color(0, 0, 0, 1))
	# Reflection mark — a small line that rotates to show spin.
	if _spinning:
		var rad := deg_to_rad(_angle)
		var mark_end := center + Vector2(cos(rad), sin(rad)) * (_DISC_RADIUS - 2.0)
		draw_line(center + Vector2(cos(rad), sin(rad)) * _LABEL_RADIUS, mark_end,
				Color(1, 1, 1, 0.25), 1.0)
