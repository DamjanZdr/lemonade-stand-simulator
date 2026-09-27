extends Control
## Promo slideshow widget (Discord / Wishlist). Anchors itself above the
## bottom-right music player. Used by the main menu and the ESC pause menu.

const PROMO_DISCORD_PATH := "res://assets/textures/ui/discord invite.png"
const PROMO_WISHLIST_PATH := "res://assets/textures/ui/wishlist invite.png"
const PROMO_ROUNDED_SHADER := preload("res://shaders/promo_rounded.gdshader")
const FONT_GRANDSTANDER := preload("res://assets/fonts/Grandstander-clean.ttf")
const PROMO_DISCORD_URL := "https://discord.com/invite/h8GZZd8Fnb"
const PROMO_WISHLIST_URL := (
	"https://store.steampowered.com/app/5000810/When_Life_Gives_You_Lemons/"
	+ "?utm_source=demo&utm_medium=menu&utm_campaign=nextfest"
)

# Same width as the music player; height preserves the 1232x706 image ratio.
const WIDGET_W: float = 280.0
const WIDGET_H: float = 160.0
const MUSIC_WIDGET_H: float = 88.0

var _slides: Array[Control] = []
var _labels: Array[String] = ["Join the Discord", "Wishlist on Steam"]
var _urls: Array[String] = [PROMO_DISCORD_URL, PROMO_WISHLIST_URL]
var _dots: Array[Button] = []
var _hover: ColorRect = null
var _click_btn: Button = null
var _timer: Timer = null
var _index: int = 0
var _tween: Tween = null


func _ready() -> void:
	_build()


func _build() -> void:
	var margin := 12.0
	var music_h := MUSIC_WIDGET_H + margin * 2.0
	name = "PromoWidget"
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(WIDGET_W + margin)
	offset_top = -(WIDGET_H + music_h + margin)
	offset_right = -margin
	offset_bottom = -(music_h + margin)
	custom_minimum_size = Vector2(WIDGET_W, WIDGET_H)

	var clip_frame := Control.new()
	clip_frame.name = "ClipFrame"
	clip_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_frame.clip_contents = true
	add_child(clip_frame)

	var textures: Array[Texture2D] = [
		load(PROMO_DISCORD_PATH) as Texture2D,
		load(PROMO_WISHLIST_PATH) as Texture2D,
	]
	var panel_color := Color(0.15, 0.22, 0.32, 0.92)
	for i in range(textures.size()):
		var slide := Control.new()
		slide.name = "SlideContainer%d" % i
		slide.set_anchors_preset(Control.PRESET_FULL_RECT)
		var start_offset := 0.0 if i == 0 else WIDGET_W
		slide.offset_left = start_offset
		slide.offset_right = start_offset
		slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_frame.add_child(slide)
		_slides.append(slide)

		var tr := TextureRect.new()
		tr.name = "Image%d" % i
		tr.texture = textures[i]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rounded_mat := ShaderMaterial.new()
		rounded_mat.shader = PROMO_ROUNDED_SHADER
		rounded_mat.set_shader_parameter("size_pixels", Vector2(WIDGET_W, WIDGET_H))
		rounded_mat.set_shader_parameter("corner_radius", 8.0)
		tr.material = rounded_mat
		slide.add_child(tr)

		var panel := Panel.new()
		panel.name = "Panel%d" % i
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		panel.offset_top = -32.0
		panel.offset_bottom = 0.0
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = panel_color
		panel_style.set_border_width_all(0)
		panel_style.corner_radius_top_left = 0
		panel_style.corner_radius_top_right = 0
		panel_style.corner_radius_bottom_left = 8
		panel_style.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", panel_style)
		slide.add_child(panel)

		var label := Label.new()
		label.name = "Label%d" % i
		label.text = _labels[i].to_upper()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 8.0
		label.offset_right = -8.0
		label.offset_top = 3.0
		label.offset_bottom = 3.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT_GRANDSTANDER)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)

	# Hover overlay (rounded to match the image).
	var hover := ColorRect.new()
	hover.name = "Hover"
	hover.set_anchors_preset(Control.PRESET_FULL_RECT)
	hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hover_mat := ShaderMaterial.new()
	hover_mat.shader = PROMO_ROUNDED_SHADER
	hover_mat.set_shader_parameter("size_pixels", Vector2(WIDGET_W, WIDGET_H))
	hover_mat.set_shader_parameter("corner_radius", 8.0)
	hover_mat.set_shader_parameter("is_overlay", true)
	hover_mat.set_shader_parameter("overlay_alpha", 0.0)
	hover.material = hover_mat
	hover.color = Color.TRANSPARENT
	clip_frame.add_child(hover)
	_hover = hover

	# Invisible click target over the whole widget.
	var btn := Button.new()
	btn.name = "Click"
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	var style := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0))
	clip_frame.add_child(btn)
	_click_btn = btn
	btn.mouse_entered.connect(
		func():
			var tw := create_tween()
			tw.tween_property(_hover.material, "shader_parameter/overlay_alpha", 0.12, 0.15),
	)
	btn.mouse_exited.connect(
		func():
			var tw := create_tween()
			tw.tween_property(_hover.material, "shader_parameter/overlay_alpha", 0.0, 0.15),
	)
	btn.pressed.connect(_on_clicked)

	# Slide indicator dots (below the widget, not on the panel).
	var dots_row := HBoxContainer.new()
	dots_row.name = "DotsRow"
	dots_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dots_row.anchor_top = 1.0
	dots_row.anchor_bottom = 1.0
	dots_row.offset_left = -(WIDGET_W / 2.0 + 24.0)
	dots_row.offset_top = 12.0
	dots_row.offset_right = -(WIDGET_W / 2.0 - 24.0)
	dots_row.offset_bottom = 26.0
	dots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dots_row.add_theme_constant_override("separation", 10)
	add_child(dots_row)
	for i in range(_slides.size()):
		var dot := Button.new()
		dot.name = "Dot%d" % i
		dot.flat = true
		dot.custom_minimum_size = Vector2(10, 10)
		dot.mouse_filter = Control.MOUSE_FILTER_STOP
		var dot_style := StyleBoxFlat.new()
		dot_style.set_corner_radius_all(5)
		dot_style.content_margin_left = 0
		dot_style.content_margin_right = 0
		dot_style.content_margin_top = 0
		dot_style.content_margin_bottom = 0
		var is_active := i == _index
		dot_style.bg_color = Color(1, 1, 1, 1.0 if is_active else 0.35)
		dot.add_theme_stylebox_override("normal", dot_style)
		var hover_style := StyleBoxFlat.new()
		hover_style.set_corner_radius_all(5)
		hover_style.content_margin_left = 0
		hover_style.content_margin_right = 0
		hover_style.content_margin_top = 0
		hover_style.content_margin_bottom = 0
		hover_style.bg_color = Color(1, 1, 1, 1.0)
		dot.add_theme_stylebox_override("hover", hover_style)
		dots_row.add_child(dot)
		_dots.append(dot)
		dot.mouse_entered.connect(
			func():
				if _timer != null:
					_timer.paused = true,
		)
		dot.mouse_exited.connect(
			func():
				if _timer != null:
					_timer.paused = false,
		)
		dot.pressed.connect(
			func():
				_show_slide(i),
		)

	# Timer to auto-advance slides.
	_timer = Timer.new()
	_timer.name = "PromoTimer"
	_timer.wait_time = 6.0
	_timer.autostart = true
	_timer.timeout.connect(_advance_slide)
	add_child(_timer)


func _on_clicked() -> void:
	var url := _urls[_index]
	if url != "":
		OS.shell_open(url)


func _show_slide(index: int) -> void:
	if index == _index or _slides.is_empty():
		return
	var duration := 0.4
	var cur := _slides[_index]
	var nxt := _slides[index]

	nxt.offset_left = WIDGET_W
	nxt.offset_right = WIDGET_W

	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var tw := _tween
	tw.tween_property(cur, "offset_left", -WIDGET_W, duration)
	tw.tween_property(cur, "offset_right", -WIDGET_W, duration)
	tw.tween_property(nxt, "offset_left", 0.0, duration)
	tw.tween_property(nxt, "offset_right", 0.0, duration)
	tw.chain().tween_callback(
		func():
			cur.offset_left = WIDGET_W
			cur.offset_right = WIDGET_W,
	)

	_index = index
	for i in range(_dots.size()):
		var dot := _dots[i]
		var normal := dot.get_theme_stylebox("normal") as StyleBoxFlat
		normal.bg_color = Color(1, 1, 1, 1.0 if i == _index else 0.35)
		dot.add_theme_stylebox_override("normal", normal)


func _advance_slide() -> void:
	var next := (_index + 1) % _slides.size()
	_show_slide(next)
