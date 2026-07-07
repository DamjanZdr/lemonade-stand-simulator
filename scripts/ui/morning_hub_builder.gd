@tool
extends CanvasLayer
## Run this in the editor to build the Morning Hub UI scene.
## Attach this to the CanvasLayer in morning_hub.tscn, reload the scene,
## and the UI will auto-build in the editor. Then save the scene and
## re-attach morning_hub.gd.

const C_TEXT := Color(0.95, 0.92, 0.86)
const C_TEXT_DIM := Color(0.65, 0.58, 0.48)
const C_ACCENT := Color(0.92, 0.72, 0.22)
const C_ACCENT_DIM := Color(0.55, 0.40, 0.12)
const C_CARD := Color(0.10, 0.08, 0.05)
const C_CARD_LIFT := Color(0.14, 0.11, 0.07)
const C_BORDER := Color(0.40, 0.28, 0.12)
const C_GOLD := Color(0.92, 0.72, 0.22)
const C_ICE := Color(0.70, 0.90, 1.0)

var _built := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_build()


func _build() -> void:
	if _built:
		return
	_built = true

	var root := self

	# Clear existing UI children (keep script etc.)
	for child in root.get_children():
		child.queue_free()

	# -- Backdrop --
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.015, 0.01, 0.75)
	root.add_child(backdrop)
	backdrop.owner = root

	# -- Main Panel --
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -420
	panel.offset_top = -280
	panel.offset_right = 420
	panel.offset_bottom = 280
	root.add_child(panel)
	panel.owner = root

	var panel_st := StyleBoxFlat.new()
	panel_st.bg_color = Color(0.07, 0.05, 0.02)
	panel_st.border_color = C_BORDER
	panel_st.border_width_left = 2
	panel_st.border_width_top = 2
	panel_st.border_width_right = 2
	panel_st.border_width_bottom = 2
	panel_st.set_corner_radius_all(28)
	panel.add_theme_stylebox_override("panel", panel_st)

	# -- Panel VBox --
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	vbox.owner = root

	# Header
	var header := _make_hbox("Header")
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)
	header.owner = root
	var day_lbl := _make_label("DayLabel", "Day 1", 22, C_TEXT)
	header.add_child(day_lbl)
	day_lbl.owner = root
	var money_lbl := _make_label("MoneyLabel", "Money: $0.00", 20, C_TEXT)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(money_lbl)
	money_lbl.owner = root
	var temp_lbl := _make_label("TempLabel", "25C", 16, C_TEXT)
	temp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(temp_lbl)
	temp_lbl.owner = root

	# Price Row
	var price_row := _make_hbox("PriceRow")
	vbox.add_child(price_row)
	price_row.owner = root
	var price_title := _make_label("", "Cup Price:", 14, C_TEXT)
	price_row.add_child(price_title)
	price_title.owner = root
	var price_slider := HSlider.new()
	price_slider.name = "PriceSlider"
	price_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(price_slider)
	price_slider.owner = root
	var price_val := _make_label("PriceValue", "$0.00", 14, C_TEXT)
	price_row.add_child(price_val)
	price_val.owner = root

	# Flow Indicator
	var flow_ind := _make_hbox("FlowIndicator")
	flow_ind.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(flow_ind)
	flow_ind.owner = root
	for tab in ["analytics", "upgrades", "shop"]:
		var step_pc := PanelContainer.new()
		step_pc.name = "StepPC_" + tab
		flow_ind.add_child(step_pc)
		step_pc.owner = root
		var step_lbl := _make_label("StepLbl_" + tab, tab.capitalize(), 13, C_TEXT_DIM)
		step_pc.add_child(step_lbl)
		step_lbl.owner = root

	# Content
	var content := MarginContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		content.add_theme_constant_override(side, 8)
	vbox.add_child(content)
	content.owner = root

	# Nav Row
	var nav_row := _make_hbox("NavRow")
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav_row)
	nav_row.owner = root
	var back_btn := _make_btn("BackBtn", "Back", 14)
	nav_row.add_child(back_btn)
	back_btn.owner = root
	var next_btn := _make_btn("NextBtn", "Next", 14)
	nav_row.add_child(next_btn)
	next_btn.owner = root

	# Start Day Button
	var start_btn := _make_btn("StartDayBtn", "Open Stand!", 22)
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(start_btn)
	start_btn.owner = root

	# Status Label
	var status_lbl := _make_label("StatusLbl", "", 14, C_TEXT)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)
	status_lbl.owner = root

	# -- Analytics Page --
	var analytics_page := VBoxContainer.new()
	analytics_page.name = "AnalyticsPage"
	analytics_page.visible = false
	content.add_child(analytics_page)
	analytics_page.owner = root
	var today_lbl := _make_label("TodayLabel", "Day 1  |  $0.00  |  0% pop  |  25C", 16, C_TEXT)
	analytics_page.add_child(today_lbl)
	today_lbl.owner = root
	var ybox := VBoxContainer.new()
	ybox.name = "YesterdayBox"
	analytics_page.add_child(ybox)
	ybox.owner = root

	# -- Upgrades Page --
	var upgrades_page := VBoxContainer.new()
	upgrades_page.name = "UpgradesPage"
	upgrades_page.visible = false
	content.add_child(upgrades_page)
	upgrades_page.owner = root
	var upg_scroll := ScrollContainer.new()
	upg_scroll.name = "ScrollContainer"
	upg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upgrades_page.add_child(upg_scroll)
	upg_scroll.owner = root
	var upg_list := VBoxContainer.new()
	upg_list.name = "UpgradeList"
	upg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upg_list.add_theme_constant_override("separation", 8)
	upg_scroll.add_child(upg_list)
	upg_list.owner = root

	# -- Shop Page --
	var shop_page := VBoxContainer.new()
	shop_page.name = "ShopPage"
	shop_page.visible = false
	content.add_child(shop_page)
	shop_page.owner = root
	var cat_row := _make_hbox("CatRow")
	cat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_page.add_child(cat_row)
	cat_row.owner = root
	for cat in ["ingredients", "equipment"]:
		var cat_btn := _make_btn("Cat_" + cat, cat.capitalize(), 14)
		cat_row.add_child(cat_btn)
		cat_btn.owner = root

	var shop_split := HBoxContainer.new()
	shop_split.name = "ShopSplit"
	shop_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_page.add_child(shop_split)
	shop_split.owner = root

	var scroll2 := ScrollContainer.new()
	scroll2.name = "ScrollContainer2"
	scroll2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_split.add_child(scroll2)
	scroll2.owner = root
	var shop_grid := GridContainer.new()
	shop_grid.name = "ShopGrid"
	shop_grid.columns = 3
	shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sep in ["h_separation", "v_separation"]:
		shop_grid.add_theme_constant_override(sep, 10)
	scroll2.add_child(shop_grid)
	shop_grid.owner = root

	# Cart
	var cart_pc := PanelContainer.new()
	cart_pc.name = "CartPC"
	cart_pc.custom_minimum_size = Vector2(180, 0)
	shop_split.add_child(cart_pc)
	cart_pc.owner = root
	var cart_panel := VBoxContainer.new()
	cart_panel.name = "CartPanel"
	cart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cart_pc.add_child(cart_panel)
	cart_panel.owner = root
	var cart_title := _make_label("CartTitle", "Cart", 16, C_ACCENT)
	cart_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cart_panel.add_child(cart_title)
	cart_title.owner = root
	var cart_scroll := ScrollContainer.new()
	cart_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cart_panel.add_child(cart_scroll)
	cart_scroll.owner = root
	var cart_list := VBoxContainer.new()
	cart_list.name = "CartList"
	cart_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cart_scroll.add_child(cart_list)
	cart_list.owner = root
	var cart_total := _make_label("CartTotal", "Total: $0.00", 14, C_TEXT)
	cart_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cart_panel.add_child(cart_total)
	cart_total.owner = root
	var checkout_btn := _make_btn("CheckoutBtn", "Checkout", 16)
	cart_panel.add_child(checkout_btn)
	checkout_btn.owner = root

	# -- Right Panel --
	var right_panel := PanelContainer.new()
	right_panel.name = "RightPanel"
	right_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_panel.offset_left = 440
	right_panel.offset_top = -280
	right_panel.offset_right = 700
	right_panel.offset_bottom = 280
	root.add_child(right_panel)
	right_panel.owner = root
	var right_st := StyleBoxFlat.new()
	right_st.bg_color = Color(0.07, 0.05, 0.02)
	right_st.border_color = C_BORDER
	right_st.border_width_left = 2
	right_st.border_width_top = 2
	right_st.border_width_right = 2
	right_st.border_width_bottom = 2
	right_st.set_corner_radius_all(24)
	right_panel.add_theme_stylebox_override("panel", right_st)

	var right_vbox := VBoxContainer.new()
	right_vbox.name = "RightVBox"
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right_vbox)
	right_vbox.owner = root

	# Preview
	var preview_title := _make_label("PreviewTitle", "Stand Preview", 18, C_GOLD)
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(preview_title)
	preview_title.owner = root
	var preview_container := PanelContainer.new()
	preview_container.name = "PreviewContainer"
	preview_container.custom_minimum_size = Vector2(0, 200)
	right_vbox.add_child(preview_container)
	preview_container.owner = root
	var preview_st := StyleBoxFlat.new()
	preview_st.bg_color = C_CARD
	preview_st.border_color = C_BORDER
	preview_st.border_width_left = 1
	preview_st.border_width_top = 1
	preview_st.border_width_right = 1
	preview_st.border_width_bottom = 1
	preview_st.set_corner_radius_all(12)
	preview_container.add_theme_stylebox_override("panel", preview_st)
	var preview_vp := SubViewport.new()
	preview_vp.name = "PreviewViewport"
	preview_vp.size = Vector2i(240, 180)
	preview_container.add_child(preview_vp)
	preview_vp.owner = root
	var preview_cam := Camera3D.new()
	preview_cam.name = "PreviewCamera"
	preview_cam.position = Vector3(8, 4, 8)
	preview_cam.look_at(Vector3.ZERO, Vector3.UP)
	preview_vp.add_child(preview_cam)
	preview_cam.owner = root

	# Stats
	var stats_vbox := VBoxContainer.new()
	stats_vbox.name = "StatsVBox"
	stats_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_vbox.add_theme_constant_override("separation", 8)
	right_vbox.add_child(stats_vbox)
	stats_vbox.owner = root
	var stats_title := _make_label("StatsTitle", "Stand Status", 18, C_GOLD)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_vbox.add_child(stats_title)
	stats_title.owner = root
	var stats_sep := HSeparator.new()
	stats_sep.name = "StatsSep"
	stats_vbox.add_child(stats_sep)
	stats_sep.owner = root

	print("Morning Hub UI built! Save the scene (Ctrl+S), then re-attach morning_hub.gd.")


func _make_hbox(name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = name
	return h


func _make_label(name: String, text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.name = name
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_btn(name: String, text: String, font_size: int) -> Button:
	var btn := Button.new()
	btn.name = name
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.25, 0.18, 0.08)
	st.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", st)
	var st_h := StyleBoxFlat.new()
	st_h.bg_color = Color(0.40, 0.28, 0.10)
	st_h.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("hover", st_h)
	var st_p := StyleBoxFlat.new()
	st_p.bg_color = Color(0.55, 0.40, 0.15)
	st_p.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("pressed", st_p)
	return btn
