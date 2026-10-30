class_name UpgradeBarColumn
extends VBoxContainer

## One progression branch rendered as a vertical fill bar with threshold
## tick marks and hoverable reward markers alternating left/right of the
## bar. Reads live data from UpgradeManager.get_branch_progress().
## Track, fill and ticks all derive from a single _bar_rect() so they can
## never drift out of alignment.

const BAR_WIDTH := 90.0
const BAR_PAD := 6.0
# Extra headroom above the track so the top-edge goal badge doesn't
# overlap the labels above the bar.
const BAR_TOP_PAD := 38.0
const MARKER_SIZE := 60.0
const MARKER_GAP := 4.0
## The source icons are black-on-transparent; this tints them white so
## they read on the dark badge circles.
const WHITE_ICON_SHADER := """shader_type canvas_item;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(1.0, 1.0, 1.0, a);
}"""
const DARK_ICON_SHADER := """shader_type canvas_item;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(0.05, 0.055, 0.07, a);
}"""
## Liquid fill: wavy surface line, brightened band at the meniscus,
## subtle vertical shading. 'slosh' spikes the wave during fill-ups.
const FILL_SHADER := """shader_type canvas_item;
uniform vec4 fill_color : source_color = vec4(0.3, 0.75, 0.4, 1.0);
uniform vec2 rect_size = vec2(80.0, 400.0);
uniform float slosh = 0.0;
// 1 when the fill reaches the bar's top border — the surface must touch
// it (slosh then only dips downward, like liquid against a lid).
uniform float top_clamp = 0.0;

void fragment() {
	vec2 px = UV * rect_size;
	// Standing wave pinned at both walls — the surface sloshes in the
	// middle and settles to a flat line as 'slosh' decays to 0.
	float amp = 0.3 + slosh * 7.0;
	float wave = sin(UV.x * 3.141593) * sin(TIME * 4.5) * amp
		+ sin(UV.x * 6.283185) * sin(TIME * 3.1) * amp * 0.3;
	// Mid-fill: headroom above the surface so the wave never clips at the
	// rect's edge. At the top border: hug it, dips only.
	float edge = mix(amp + 1.5 + wave, 0.8 + min(wave, 0.0), top_clamp);
	// Everything below the surface line is liquid, above is empty.
	float a = smoothstep(edge - 1.0, edge + 1.0, px.y);
	vec3 col = fill_color.rgb * (0.85 + 0.15 * (1.0 - UV.y));
	COLOR = vec4(col, a);
}"""

var _branch: Dictionary = { }
var _bar_area: Control = null
var _track: Panel = null
var _fill: ColorRect = null
var _ticks: Array[ColorRect] = []
var _markers: Array[PanelContainer] = []
var _tip: PanelContainer = null
var _tip_title: Label = null
var _tip_sub: Label = null
var _action_lbl: Label = null
var _value_lbl: Label = null
var _last_value := 0.0
var _last_level := -1
var _last_max := 0
var _last_next := -1.0
var _stand: StandUnit = null
var _mat_white: ShaderMaterial = null
var _mat_dark: ShaderMaterial = null
var _fill_mat: ShaderMaterial = null
var _fill_color := Color(0.30, 0.75, 0.40)
var _bubbles: CPUParticles2D = null
# What the bar is actually drawing — held at the last-viewed level so
# the fill can pour upward when the player arrives.
var _displayed_value := 0.0
var _slosh := 0.0
var _fill_tween: Tween = null
# Last-viewed fill per "stand|branch" so each bar animates only growth
# the player hasn't watched yet.
static var _seen_fill: Dictionary = { }


func _thresholds() -> Array:
	return _branch.get("thresholds", UpgradeManager.FRUIT_THRESHOLDS)


func _rewards() -> Array:
	return _branch.get("rewards", [])


func _max_value() -> float:
	var t := _thresholds()
	return float(t[t.size() - 1]) if not t.is_empty() else 1.0


func _reward_text(tier: int) -> String:
	var r := _rewards()
	return str(r[tier]) if tier >= 0 and tier < r.size() else ""


## The rect inside _bar_area that the bar occupies: the bar itself is
## centered under the text labels; markers hang off its right edge.
func _bar_rect() -> Rect2:
	var w := minf(BAR_WIDTH, _bar_area.size.x - 8.0)
	var x := (_bar_area.size.x - w) * 0.5
	return Rect2(x, BAR_TOP_PAD, w, maxf(_bar_area.size.y - BAR_TOP_PAD - BAR_PAD, 8.0))


func setup(branch_def: Dictionary) -> void:
	_branch = branch_def
	# Equal width for every column so bars line up across the page.
	custom_minimum_size = Vector2(140, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var vbox := self
	var ws := Shader.new()
	ws.code = WHITE_ICON_SHADER
	_mat_white = ShaderMaterial.new()
	_mat_white.shader = ws
	var ds := Shader.new()
	ds.code = DARK_ICON_SHADER
	_mat_dark = ShaderMaterial.new()
	_mat_dark.shader = ds
	var name_lbl := Label.new()
	name_lbl.text = str(_branch.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(name_lbl)

	# "What fills this bar" — always visible so players know the action.
	_action_lbl = Label.new()
	_action_lbl.text = str(_branch.get("action", ""))
	_action_lbl.add_theme_font_size_override("font_size", 15)
	_action_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	_action_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_lbl.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(_action_lbl)

	_bar_area = Control.new()
	_bar_area.custom_minimum_size = Vector2(0, 140)
	_bar_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar_area.clip_contents = false
	vbox.add_child(_bar_area)
	_bar_area.resized.connect(_relayout)

	_track = Panel.new()
	var track_st := StyleBoxFlat.new()
	track_st.bg_color = Color(0.05, 0.06, 0.08)
	track_st.border_width_left = 4
	track_st.border_width_top = 4
	track_st.border_width_right = 4
	track_st.border_width_bottom = 4
	track_st.border_color = Color(0.68, 0.71, 0.80)
	track_st.set_corner_radius_all(4)
	_track.add_theme_stylebox_override("panel", track_st)
	_bar_area.add_child(_track)

	_fill_color = _branch.get("color", Color(0.30, 0.75, 0.40))
	_fill = ColorRect.new()
	var fs := Shader.new()
	fs.code = FILL_SHADER
	_fill_mat = ShaderMaterial.new()
	_fill_mat.shader = fs
	_fill_mat.set_shader_parameter("fill_color", _fill_color)
	_fill.material = _fill_mat
	_bar_area.add_child(_fill)

	# Surface spray while the liquid rises — child of the fill so it
	# rides the meniscus; emitting only during a pour, then fades out.
	_bubbles = CPUParticles2D.new()
	_bubbles.emitting = false
	_bubbles.amount = 30
	_bubbles.lifetime = 0.4
	_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_bubbles.emission_rect_extents = Vector2(30.0, 1.0)
	_bubbles.direction = Vector2(0.0, -1.0)
	_bubbles.spread = 30.0
	_bubbles.gravity = Vector2(0.0, 140.0)
	_bubbles.initial_velocity_min = 30.0
	_bubbles.initial_velocity_max = 65.0
	_bubbles.scale_amount_min = 1.5
	_bubbles.scale_amount_max = 3.5
	_bubbles.color = _fill_color.lightened(0.45)
	_fill.add_child(_bubbles)

	# Ticks mark every threshold. They're all created first so every
	# badge is added later and always draws above every tick line —
	# interleaving them let higher ticks paint over lower badges.
	var thresholds := _thresholds()
	for i in range(thresholds.size()):
		var tick := ColorRect.new()
		tick.color = Color(0.55, 0.60, 0.70)
		tick.set_meta("threshold", float(thresholds[i]))
		tick.set_meta("tier", i)
		_bar_area.add_child(tick)
		_ticks.append(tick)

	# Circular badge with the branch icon — or a "?" when the branch
	# has no icon yet (signals an icon needs to be made). Hidden until
	# the first real layout positions it (else they'd pile at 0,0 and
	# visibly slide into place when the page opens).
	for i in range(thresholds.size()):
		var marker := PanelContainer.new()
		marker.visible = false
		marker.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
		var mst := StyleBoxFlat.new()
		mst.bg_color = Color(0.08, 0.09, 0.12)
		mst.set_corner_radius_all(int(MARKER_SIZE / 2.0))
		mst.border_width_left = 4
		mst.border_width_top = 4
		mst.border_width_right = 4
		mst.border_width_bottom = 4
		mst.border_color = Color(0.78, 0.81, 0.88)
		mst.set_content_margin_all(9)
		marker.add_theme_stylebox_override("panel", mst)
		marker.mouse_filter = Control.MOUSE_FILTER_STOP
		marker.set_meta("tier", i)
		var icon_path := str(_branch.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tex := TextureRect.new()
			tex.texture = load(icon_path)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tex.material = _mat_white
			marker.add_child(tex)
			marker.set_meta("icon", tex)
		else:
			var q := Label.new()
			q.text = "?"
			q.add_theme_font_size_override("font_size", 24)
			q.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			marker.add_child(q)
		marker.mouse_entered.connect(_on_marker_hover.bind(marker))
		marker.mouse_exited.connect(_on_marker_unhover.bind(marker))
		marker.gui_input.connect(_on_marker_input.bind(marker))
		_bar_area.add_child(marker)
		_markers.append(marker)

	_value_lbl = Label.new()
	_value_lbl.add_theme_font_size_override("font_size", 16)
	_value_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	_value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# One line: "12 / 18" — the branch title above explains what it is.
	_value_lbl.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(_value_lbl)

	# Hover card for tick markers: reward + the threshold it needs.
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.z_index = 50
	_tip.top_level = true
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_st := StyleBoxFlat.new()
	tip_st.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	tip_st.border_width_left = 1
	tip_st.border_width_top = 1
	tip_st.border_width_right = 1
	tip_st.border_width_bottom = 1
	tip_st.border_color = Color(0.45, 0.50, 0.62)
	tip_st.set_corner_radius_all(6)
	tip_st.set_content_margin_all(8)
	_tip.add_theme_stylebox_override("panel", tip_st)
	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 2)
	_tip.add_child(tip_vbox)
	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 16)
	_tip_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.37))
	_tip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_vbox.add_child(_tip_title)
	_tip_sub = Label.new()
	_tip_sub.add_theme_font_size_override("font_size", 14)
	_tip_sub.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
	_tip_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_vbox.add_child(_tip_sub)
	_bar_area.add_child(_tip)

	tooltip_text = str(_branch.get("description", ""))
	_relayout()


func _fmt(v: float) -> String:
	var s := "%d" % int(v) if floorf(v) == v else "%.1f" % v
	return str(_branch.get("unit", "")) + s


func _relayout() -> void:
	var r := _bar_rect()
	_track.position = r.position
	_track.size = r.size
	var max_v := _max_value()
	var laid_out := r.size.y > 40.0
	for i in range(_ticks.size()):
		var tick := _ticks[i]
		# The bar's top edge IS the final goal line — no tick drawn there.
		tick.visible = i < _ticks.size() - 1 and laid_out
		var frac := clampf(float(tick.get_meta("threshold")) / max_v, 0.0, 1.0)
		var ty := r.position.y + r.size.y * (1.0 - frac)
		# Inset inside the 4px track border.
		tick.position = Vector2(r.position.x + 4.0, ty - 4.0)
		tick.size = Vector2(r.size.x - 8.0, 8.0)
		var marker := _markers[i]
		marker.size = Vector2(MARKER_SIZE, MARKER_SIZE)
		marker.pivot_offset = marker.size * 0.5
		# Badge sits centered ON the bar at the threshold line.
		var mx := r.position.x + (r.size.x - MARKER_SIZE) * 0.5
		marker.position = Vector2(mx, ty - MARKER_SIZE * 0.5)
		if laid_out:
			marker.visible = true
	_update_fill()


func _update_fill() -> void:
	var r := _bar_rect()
	var frac := clampf(_displayed_value / _max_value(), 0.0, 1.0)
	# Inset inside the 4px track border so the outline stays crisp.
	var inner := Rect2(r.position.x + 4.0, r.position.y + 4.0, r.size.x - 8.0, r.size.y - 8.0)
	_fill.position = Vector2(inner.position.x, inner.position.y + inner.size.y * (1.0 - frac))
	_fill.size = Vector2(inner.size.x, inner.size.y * frac)
	if _fill_mat != null:
		_fill_mat.set_shader_parameter("rect_size", _fill.size)
		_fill_mat.set_shader_parameter("slosh", _slosh)
		# Blend the surface onto the border over the last 10% of the pour.
		_fill_mat.set_shader_parameter("top_clamp", clampf((frac - 0.9) / 0.1, 0.0, 1.0))
	if _bubbles != null:
		_bubbles.position = Vector2(_fill.size.x * 0.5, 2.0)
		_bubbles.emission_rect_extents = Vector2(_fill.size.x * 0.5, 1.0)


func _seen_key() -> String:
	return "%s|%s" % [_stand.name if _stand != null else "_", str(_branch.get("id", ""))]


## Called by the hub when the player actually opens this page — pours
## the bar from the last-seen level up to the real one.
func on_viewed() -> void:
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	if _last_value > _displayed_value + 0.01:
		_seen_fill[_seen_key()] = _last_value
		_slosh = 1.0
		if _bubbles != null:
			_bubbles.emitting = true
		_fill_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_fill_tween.tween_method(_set_displayed_value, _displayed_value, _last_value, 2.0)
		_fill_tween.parallel().tween_property(self, "_slosh", 0.0, 2.6)
		# Stop spawning before the surface arrives — nothing should
		# still be popping out once the liquid is settled.
		get_tree().create_timer(1.6).timeout.connect(_stop_bubbles)
	else:
		_displayed_value = _last_value
		_update_fill()
		_render_state()


func _set_displayed_value(v: float) -> void:
	_displayed_value = v
	_update_fill()
	_render_state()


func _stop_bubbles() -> void:
	if _bubbles != null:
		_bubbles.emitting = false


func refresh(stand: StandUnit) -> void:
	if _branch.is_empty():
		return
	var p := UpgradeManager.get_branch_progress(str(_branch["id"]), stand)
	if p.is_empty():
		return
	_stand = stand
	_last_value = float(p.get("value", 0.0))
	_last_level = int(p.get("level", 0))
	_last_max = int(p.get("max_level", 0))
	_last_next = float(p.get("next_threshold", -1.0))

	# Fruit bar: the action names the fruit currently being mastered.
	if _branch.get("kind") == "fruit" and _last_level < _last_max:
		var target := str(p.get("target_fruit", "")).capitalize()
		if target != "":
			_action_lbl.text = "Serve perfect %s recipe" % target

	# Hold the liquid at the last level the player saw — on_viewed()
	# pours it up. Regressions (stand switch/reset) snap immediately.
	var key := _seen_key()
	var shown := float(_seen_fill.get(key, 0.0))
	if _last_value < shown:
		shown = _last_value
		_seen_fill[key] = shown
	if not (_fill_tween != null and _fill_tween.is_valid()):
		_displayed_value = shown
		_update_fill()
	_render_state()


## Draws ticks, badges and labels from _displayed_value so threshold
## lines light up as the liquid pours past them.
func _render_state() -> void:
	var thresholds := _thresholds()
	for tick in _ticks:
		var tick_tier := int(tick.get_meta("tier"))
		if tick_tier < _last_level:
			# Claimed — near-black, matching the claimed badge icon.
			tick.color = Color(0.09, 0.10, 0.12)
		elif _displayed_value >= float(tick.get_meta("threshold")):
			tick.color = _fill_color.lightened(0.25)
		else:
			tick.color = Color(0.78, 0.81, 0.88)
	for marker in _markers:
		var tier := int(marker.get_meta("tier"))
		var st := marker.get_theme_stylebox("panel") as StyleBoxFlat
		if st == null:
			continue
		var claimable := (
			tier == _last_level and _last_level < thresholds.size()
			and _displayed_value >= float(thresholds[tier])
		)
		if tier < _last_level:
			# Claimed — white circle, black outline, near-black icon.
			st.bg_color = Color(0.92, 0.92, 0.95)
			st.border_color = Color(0.0, 0.0, 0.0)
			_set_icon_mat(marker, _mat_dark)
			_stop_pulse(marker)
			marker.mouse_default_cursor_shape = Control.CURSOR_ARROW
		elif claimable:
			# Reached but not claimed — pulsing gold, click to claim.
			st.bg_color = Color(0.08, 0.09, 0.12)
			st.border_color = Color(1.0, 0.85, 0.30)
			_set_icon_mat(marker, _mat_white)
			marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			if not marker.get_meta("pulsing", false):
				_start_pulse(marker)
		else:
			st.bg_color = Color(0.08, 0.09, 0.12)
			st.border_color = (
				_fill_color.lightened(0.35)
				if tier == _last_level
				else Color(0.78, 0.81, 0.88)
			)
			_set_icon_mat(marker, _mat_white)
			_stop_pulse(marker)
			marker.mouse_default_cursor_shape = Control.CURSOR_ARROW

	if _last_level >= _last_max:
		_value_lbl.text = "MAX"
	elif _last_next >= 0.0:
		_value_lbl.text = "%s / %s" % [_fmt(minf(_displayed_value, _last_next)), _fmt(_last_next)]
	else:
		_value_lbl.text = _fmt(_displayed_value)


func _set_icon_mat(marker: PanelContainer, mat: Material) -> void:
	var icon := marker.get_meta("icon", null) as TextureRect
	if icon != null:
		icon.material = mat
		return
	# "?" fallback badge: tint the label instead of a shader material.
	var q := marker.get_child(0) as Label
	if q != null:
		q.add_theme_color_override(
			"font_color",
			Color(0.09, 0.10, 0.12) if mat == _mat_dark else Color(0.85, 0.85, 0.88),
		)


func _kill_marker_tween(marker: PanelContainer) -> void:
	var tw: Variant = marker.get_meta("tween", null)
	if tw is Tween and tw.is_valid():
		tw.kill()
	marker.set_meta("tween", null)


func _start_pulse(marker: PanelContainer) -> void:
	marker.set_meta("pulsing", true)
	marker.pivot_offset = marker.size * 0.5
	var tw := marker.create_tween().set_loops()
	tw.tween_property(marker, "scale", Vector2(1.14, 1.14), 0.5)
	tw.tween_property(marker, "scale", Vector2.ONE, 0.5)
	marker.set_meta("tween", tw)


func _stop_pulse(marker: PanelContainer) -> void:
	if marker.get_meta("pulsing", false):
		marker.set_meta("pulsing", false)
		_kill_marker_tween(marker)
		marker.scale = Vector2.ONE


func _is_claimable_tier(tier: int) -> bool:
	var thresholds := _thresholds()
	return (
		_stand != null and tier == _last_level and _last_level < thresholds.size()
		and _displayed_value >= float(thresholds[tier])
	)


func _on_marker_input(event: InputEvent, marker: PanelContainer) -> void:
	if not (
		event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	):
		return
	var tier := int(marker.get_meta("tier"))
	if not _is_claimable_tier(tier):
		return
	AudioManager.play_sfx_ui("coins")
	_stop_pulse(marker)
	OnboardingManager.report(_stand, "claim_upgrade", { "branch": str(_branch.get("id", "")) })


func _on_marker_hover(marker: PanelContainer) -> void:
	AudioManager.play_sfx_ui("hover")
	_kill_marker_tween(marker)
	marker.pivot_offset = marker.size * 0.5
	var pop := marker.create_tween()
	pop.tween_property(marker, "scale", Vector2(1.2, 1.2), 0.12)
	marker.set_meta("tween", pop)
	var tier := int(marker.get_meta("tier"))
	_tip_title.text = _reward_text(tier)
	var thresholds := _thresholds()
	_tip_sub.text = "%s/%s" % [_fmt(_last_value), _fmt(float(thresholds[tier]))]
	_tip.reset_size()
	# top_level canvas item: nothing clips it, so position in global
	# coords centered above the badge (flips below if there's no room).
	var mg := marker.get_global_rect()
	var vx := mg.get_center().x - _tip.size.x * 0.5
	vx = clampf(vx, 8.0, get_viewport_rect().size.x - _tip.size.x - 8.0)
	var vy := mg.position.y - _tip.size.y - 6.0
	if vy < 8.0:
		vy = mg.position.y + mg.size.y + 6.0
	_tip.global_position = Vector2(vx, vy)
	_tip.visible = true


func _on_marker_unhover(marker: PanelContainer) -> void:
	_tip.visible = false
	_kill_marker_tween(marker)
	var shrink := marker.create_tween()
	shrink.tween_property(marker, "scale", Vector2.ONE, 0.12)
	marker.set_meta("tween", shrink)
	if _is_claimable_tier(int(marker.get_meta("tier"))):
		shrink.tween_callback(
			func():
				_start_pulse(marker),
		)
