extends CanvasLayer
## Morning hub: Analytics, Shop, Upgrades. Compact, animated, lemonade-stand vibe.

const PRODUCT_IMAGES: Dictionary = {
	"lemon": "res://assets/textures/ui/products/lemon.png",
	"strawberry": "res://assets/textures/ui/products/strawberry.png",
	"blueberry": "res://assets/textures/ui/products/blueberry.png",
	"peach": "res://assets/textures/ui/products/peach.png",
	"watermelon": "res://assets/textures/ui/products/watermelon.png",
	"sugar": "res://assets/textures/ui/products/sugar.png",
	"ice": "res://assets/textures/ui/products/ice.png",
	"cups": "res://assets/textures/ui/products/cup.png",
	"water": "res://assets/textures/ui/products/water jug.png",
	"fruit_bin": "res://assets/textures/ui/products/crate.png",
	"sugar_bin": "res://assets/textures/ui/products/sugar bin.png",
	"ice_bin": "res://assets/textures/ui/products/ice bucket.png",
	"pitcher": "res://assets/textures/ui/products/pitcher.png",
	"press": "res://assets/textures/ui/products/press.png",
	"workstation": "res://assets/textures/ui/products/table.png",
}

const BRANCH_COLORS: Array[Color] = [
	Color(0.95, 0.25, 0.25),
	Color(0.25, 0.85, 0.25),
	Color(0.25, 0.35, 0.95),
	Color(0.95, 0.85, 0.15),
	Color(0.85, 0.25, 0.85),
	Color(0.15, 0.85, 0.95),
	Color(0.95, 0.55, 0.15),
	Color(0.55, 0.15, 0.95),
	Color(0.65, 0.95, 0.15),
	Color(0.95, 0.45, 0.55),
]

@onready var panel: PanelContainer = $MainHBox/Panel
@onready var vbox: VBoxContainer = $MainHBox/Panel/VBox
@onready var backdrop: ColorRect = $Backdrop

@onready var _status_lbl: Label = $MainHBox/Panel/VBox/BottomBar/StatusLbl
@onready var _flow_indicator: HBoxContainer = $MainHBox/Panel/VBox/FlowIndicator

@onready var _cart_list: VBoxContainer = (
	$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CartScroll/CartList
)
@onready var _cart_total_lbl: Label = (
	$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CartTotal
)
@onready var _checkout_btn: Button = (
	$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CheckoutBtn
)

@onready var _right_panel: PanelContainer = $MainHBox/RightPanel
@onready var _preview_camera: Camera3D = (
	$MainHBox/RightPanel/RightVBox/PreviewContainer/
		AspectRatioContainer/SubViewportContainer/
		PreviewViewport/PreviewCamera
)
@onready var _stats_vbox: VBoxContainer = ($MainHBox/RightPanel/RightVBox/StatsScroll/StatsVBox)

var _active_tab: String = "analytics"
var _flow_tabs: Array[String] = ["analytics", "shop", "upgrades", "employees"]
var _flow_step: int = 0
var _cart: Array[Dictionary] = []
var _preview_angle: float = 0.0
var _bin_amounts: Dictionary = { }
var _equipment_counts: Dictionary = { }

var _ice_spin: SpinBox = null
var _ice_unit: String = "C"

# Upgrade tree pan state
var _tree_pan_offset: Vector2 = Vector2.ZERO
var _tree_dragging: bool = false
var _tree_drag_start: Vector2 = Vector2.ZERO
var _tree_scale: float = 2.5
var _tree_tooltip: PanelContainer = null
var _icon_material: ShaderMaterial = null
var _tree_content: Control = null
var _tree_centered: bool = false
var _tree_laid_out: bool = false
var _tree_layout_pending: bool = false
var _animating_lines: Dictionary = { }
var _animating_children: Dictionary = { }


class CircleNode extends Control:
	var fill_color: Color = Color.WHITE
	var border_color: Color = Color.BLACK
	var border_width: float = 2.0
	var is_square: bool = false
	var _square_style: StyleBoxFlat = null


	func _init() -> void:
		_square_style = StyleBoxFlat.new()
		custom_minimum_size = Vector2(60, 60)
		size = Vector2(60, 60)
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = 0
		size_flags_vertical = 0


	func _draw() -> void:
		var radius: float = minf(size.x, size.y) / 2.0
		var center: Vector2 = size / 2.0
		if is_square:
			_square_style.bg_color = fill_color
			_square_style.border_color = border_color
			_square_style.border_width_bottom = int(border_width)
			var side_width: int = roundi(border_width * 0.7)
			_square_style.border_width_top = side_width
			_square_style.border_width_left = side_width
			_square_style.border_width_right = side_width
			_square_style.corner_radius_top_left = 6
			_square_style.corner_radius_top_right = 6
			_square_style.corner_radius_bottom_left = 6
			_square_style.corner_radius_bottom_right = 6
			_square_style.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		else:
			draw_circle(center, radius, fill_color)
			if border_width > 0.0:
				draw_arc(
					center,
					radius - border_width / 2.0,
					0.0,
					2.0 * PI,
					32,
					border_color,
					border_width,
					true,
				)


var shop_items: Array[Dictionary] = [
	{ "id": "lemon", "name": "Lemons", "cost": 2.0, "qty": 10 },
	{ "id": "strawberry", "name": "Strawberry", "cost": 3.0, "qty": 10 },
	{ "id": "blueberry", "name": "Blueberry", "cost": 3.5, "qty": 10 },
	{ "id": "peach", "name": "Peach", "cost": 4.0, "qty": 10 },
	{ "id": "watermelon", "name": "Watermelon", "cost": 5.0, "qty": 10 },
	{ "id": "sugar", "name": "Sugar", "cost": 1.5, "qty": 10 },
	{ "id": "ice", "name": "Ice", "cost": 1.0, "qty": 10 },
	{
		"id": "water",
		"name": "Water",
		"cost": Balancing.WATER_COST,
		"qty": Balancing.WATER_BOX_FILLINGS,
	},
	{ "id": "cups", "name": "Cups", "cost": 0.5, "qty": 10 },
]

var container_items: Array[Dictionary] = [
	{ "id": "fruit_bin", "name": "Fruit Bin", "cost": Balancing.CONTAINER_COST_FRUIT_BIN },
	{ "id": "sugar_bin", "name": "Sugar Bin", "cost": Balancing.CONTAINER_COST_SUGAR_BIN },
	{ "id": "ice_bin", "name": "Ice Plate", "cost": Balancing.CONTAINER_COST_ICE_BIN },
	{ "id": "pitcher", "name": "Pitcher", "cost": Balancing.CONTAINER_COST_PITCHER },
	{ "id": "press", "name": "Fruit Press", "cost": Balancing.CONTAINER_COST_PRESS },
	{ "id": "workstation", "name": "Table", "cost": Balancing.CONTAINER_COST_WORKSTATION },
]


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	if _right_panel:
		_right_panel.visible = false

	_checkout_btn.pressed.connect(_checkout_cart)

	# Make tab labels clickable
	for tab in _flow_tabs:
		var step_pc := _flow_indicator.get_node_or_null("StepPC_" + tab) as PanelContainer
		if step_pc:
			step_pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var t := tab
			step_pc.gui_input.connect(
				func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed:
						if event.button_index == MOUSE_BUTTON_LEFT:
							AudioManager.play_sfx_ui("tab_click")
							_show_tab(t),
			)
			step_pc.mouse_entered.connect(
				func():
					_on_tab_hover(step_pc, t),
			)
			step_pc.mouse_exited.connect(
				func():
					_on_tab_unhover(step_pc, t),
			)

	var price_slider := ($MainHBox/Panel/VBox/Content/PricesPage/PriceSlider as HSlider)
	if price_slider:
		pass

	EventBus.price_changed.connect(_on_price_changed)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.container_placed.connect(
		func(_t, _n):
			_scan_stand_state(),
	)
	EventBus.container_picked_up.connect(
		func(_t, _n):
			_scan_stand_state(),
	)
	EventBus.bin_amount_changed.connect(
		func(_t, _a):
			_scan_stand_state(),
	)
	_show_tab("analytics")

	# Build shop cards with section headers
	_build_shop()

	# Build upgrade skill tree (uses pre-existing UpgradeTree Control from scene)
	var tree_ctrl := ($MainHBox/Panel/VBox/Content/UpgradesPage/UpgradeTree as Control)
	if tree_ctrl:
		_tree_tooltip = tree_ctrl.get_node("Tooltip") as PanelContainer
		_tree_tooltip.z_index = 100
		_tree_tooltip.top_level = false
		tree_ctrl.remove_child(_tree_tooltip)
		self.add_child(_tree_tooltip)

		var content := Control.new()
		content.name = "TreeContent"
		content.mouse_filter = Control.MOUSE_FILTER_PASS
		content.clip_contents = false
		content.z_index = 0
		content.custom_minimum_size = Vector2(4000, 4000)
		content.size = Vector2(4000, 4000)
		tree_ctrl.add_child(content)
		tree_ctrl.move_child(content, 0)
		_tree_content = content

		var root_name := UpgradeManager.root_node_name
		for id in UpgradeManager.tree_positions:
			var node: CircleNode
			if id == root_name:
				node = _create_tree_root_node(root_name)
			else:
				var data := UpgradeManager.get_node_data(id)
				node = _create_tree_node(id, data)
			content.add_child(node)

		# Ensure the tree control itself gets enough space from the VBox
		# and can receive mouse input even before layout runs.
		tree_ctrl.custom_minimum_size = Vector2(300, 200)
		tree_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
		_update_tree_visibility(tree_ctrl)

		tree_ctrl.gui_input.connect(
			func(event: InputEvent):
				if event is InputEventMouseButton:
					if event.button_index == MOUSE_BUTTON_LEFT:
						_tree_dragging = event.pressed
						_tree_drag_start = event.position - _tree_pan_offset
						tree_ctrl.accept_event()
					elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
						var mb_event_up := event as InputEventMouseButton
						var new_scale_up := clampf(_tree_scale * 1.1, 0.5, 1.2)
						var center_up := tree_ctrl.size / 2.0
						var local_up := (
							(mb_event_up.position - center_up - _tree_pan_offset) / _tree_scale
						)
						_tree_pan_offset = (
							mb_event_up.position - center_up - new_scale_up * local_up
						)
						_tree_scale = new_scale_up
						_layout_upgrade_tree(tree_ctrl)
						tree_ctrl.accept_event()
					elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
						var mb_event_down := event as InputEventMouseButton
						var new_scale_down := clampf(_tree_scale / 1.1, 0.5, 1.2)
						var center_down := tree_ctrl.size / 2.0
						var local_down := (
							(mb_event_down.position - center_down - _tree_pan_offset) / _tree_scale
						)
						_tree_pan_offset = (
							mb_event_down.position - center_down - new_scale_down * local_down
						)
						_tree_scale = new_scale_down
						_layout_upgrade_tree(tree_ctrl)
						tree_ctrl.accept_event()
				elif event is InputEventMouseMotion and _tree_dragging:
					_tree_pan_offset = event.position - _tree_drag_start
					_layout_upgrade_tree(tree_ctrl)
					tree_ctrl.accept_event(),
		)

		tree_ctrl.draw.connect(
			func():
				var border_style := StyleBoxFlat.new()
				border_style.bg_color = Color.TRANSPARENT
				border_style.border_color = Color(0.4, 0.35, 0.25, 0.8)
				border_style.border_width_bottom = 2
				border_style.border_width_top = 2
				border_style.border_width_left = 2
				border_style.border_width_right = 2
				border_style.corner_radius_top_left = 6
				border_style.corner_radius_top_right = 6
				border_style.corner_radius_bottom_left = 6
				border_style.corner_radius_bottom_right = 6
				border_style.draw(tree_ctrl.get_canvas_item(), Rect2(Vector2.ZERO, tree_ctrl.size))
				if not _tree_laid_out or _tree_content == null:
					return
				for from_id in UpgradeManager.tree_connections:
					var from_node := _tree_content.get_node_or_null("TreeNode_" + from_id) as CircleNode
					if from_node == null or not from_node.visible:
						continue
					var from_center_local := from_node.position + from_node.size / 2.0
					var from_pos := (
						_tree_content.position + _tree_content.scale * from_center_local
					)
					for to_id in UpgradeManager.tree_connections[from_id]:
						var line_key: String = from_id + "|" + to_id
						var to_node := _tree_content.get_node_or_null("TreeNode_" + to_id) as CircleNode
						if to_node == null:
							continue
						var to_center_local := to_node.position + to_node.size / 2.0
						var to_pos := (
							_tree_content.position + _tree_content.scale * to_center_local
						)
						var to_purchased: bool = (UpgradeManager.is_node_purchased(to_id))
						var to_color := (to_node.fill_color
							if to_purchased
							else to_node.border_color)
						if _animating_lines.has(line_key):
							var progress: float = _animating_lines[line_key]
							var anim_end: Vector2 = (from_pos + progress * (to_pos - from_pos))
							tree_ctrl.draw_line(
								from_pos,
								anim_end,
								to_color,
								12.0 * _tree_scale,
								true,
							)
							continue
						if not to_node.visible:
							continue
						var from_purchased: bool = (
							from_id == UpgradeManager.root_node_name
							or UpgradeManager.is_node_purchased(from_id)
						)
						var line_color := to_color
						var line_width := 6.0 * _tree_scale
						if from_purchased and to_purchased:
							line_width = 7.5 * _tree_scale
						tree_ctrl.draw_line(from_pos, to_pos, line_color, line_width, true),
		)

	# Fix preview viewport to share the game world
	var preview_viewport := (
		$MainHBox/RightPanel/RightVBox/PreviewContainer/
			AspectRatioContainer/SubViewportContainer/PreviewViewport
		as SubViewport
	)
	if preview_viewport:
		preview_viewport.world_3d = get_viewport().world_3d
		preview_viewport.render_target_update_mode = (SubViewport.UPDATE_WHEN_VISIBLE)

	# Dev panel
	var dev_panel := PanelContainer.new()
	dev_panel.name = "DevPanel"
	dev_panel.anchors_preset = Control.PRESET_TOP_RIGHT
	dev_panel.offset_left = -180.0
	dev_panel.offset_right = 0.0
	dev_panel.offset_bottom = 80.0
	var dev_st := StyleBoxFlat.new()
	dev_st.bg_color = Color(0.1, 0.05, 0.05, 0.85)
	dev_st.border_color = Color(0.8, 0.2, 0.2)
	dev_st.border_width_left = 2
	dev_st.border_width_top = 2
	dev_st.border_width_right = 2
	dev_st.border_width_bottom = 2
	dev_st.set_corner_radius_all(8)
	dev_panel.add_theme_stylebox_override("panel", dev_st)
	add_child(dev_panel)
	var dev_vbox := VBoxContainer.new()
	dev_vbox.add_theme_constant_override("separation", 6)
	dev_panel.add_child(dev_vbox)
	var dev_title := Label.new()
	dev_title.text = "DEV"
	dev_title.add_theme_font_size_override("font_size", 14)
	dev_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	dev_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_vbox.add_child(dev_title)
	var reset_btn := Button.new()
	reset_btn.text = "Reset Progress"
	reset_btn.pressed.connect(_on_dev_reset)
	dev_vbox.add_child(reset_btn)
	var end_btn := Button.new()
	end_btn.text = "End Day Early"
	end_btn.pressed.connect(_on_dev_end_day)
	dev_vbox.add_child(end_btn)


func _build_shop() -> void:
	var shop_scroll := ($MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2) as ScrollContainer
	if shop_scroll == null:
		return
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var old_list := shop_scroll.get_node_or_null("ShopList") as VBoxContainer
	if old_list:
		old_list.queue_free()
	var old_grid := shop_scroll.get_node_or_null("ShopGrid") as GridContainer
	if old_grid:
		old_grid.queue_free()
	var shop_vbox := VBoxContainer.new()
	shop_vbox.name = "ShopList"
	shop_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_vbox.add_theme_constant_override("separation", 12)
	shop_scroll.add_child(shop_vbox)
	# Consumables section
	var consumables_header := Label.new()
	consumables_header.text = "Consumables"
	consumables_header.add_theme_font_size_override("font_size", 22)
	consumables_header.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	shop_vbox.add_child(consumables_header)
	var consumables_grid := GridContainer.new()
	consumables_grid.columns = 2
	consumables_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sep in ["h_separation", "v_separation"]:
		consumables_grid.add_theme_constant_override(sep, 10)
	for item in shop_items:
		consumables_grid.add_child(_create_ingredient_card(item))
	shop_vbox.add_child(consumables_grid)
	# Equipment section
	var equipment_header := Label.new()
	equipment_header.text = "Equipment"
	equipment_header.add_theme_font_size_override("font_size", 22)
	equipment_header.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	shop_vbox.add_child(equipment_header)
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sep in ["h_separation", "v_separation"]:
		equipment_grid.add_theme_constant_override(sep, 10)
	for item in container_items:
		equipment_grid.add_child(_create_equipment_card(item))
	shop_vbox.add_child(equipment_grid)


func _show_tree_tooltip(node_id: String, anchor_pos: Vector2) -> void:
	if _tree_tooltip == null:
		return
	_build_upgrade_tooltip(node_id, anchor_pos)
	if _tree_tooltip != null:
		return
	var data := UpgradeManager.get_node_data(node_id)
	var tip_vbox := _tree_tooltip.get_node("TipContent")
	var title := tip_vbox.get_node("TipTitle") as Label
	var price := tip_vbox.get_node("TipPrice") as Label
	var desc := tip_vbox.get_node("TipDesc") as Label
	var effect := tip_vbox.get_node("TipEffect") as Label
	title.text = data.get("name", "???")
	price.text = "$%.0f" % data.get("cost", 0.0)
	price.visible = not data.get("purchased", false)
	desc.text = data.get("description", "")
	var upgrade_id: String = data.get("upgrade_id", "")
	var eff_total: float = UpgradeManager.get_effect_total(upgrade_id)
	if eff_total > 0:
		effect.text = "Current bonus: +%.0f%%" % (eff_total * 100)
		effect.visible = true
	else:
		effect.visible = false
	if data.get("purchased", false):
		title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_tree_tooltip.visible = true
	_tree_tooltip.reset_size()
	_tree_tooltip.position = anchor_pos - Vector2(
		_tree_tooltip.size.x / 2.0,
		_tree_tooltip.size.y + 10.0,
	)


func _build_upgrade_tooltip(node_id: String, anchor_pos: Vector2) -> void:
	var data := UpgradeManager.get_node_data(node_id)
	var tip_vbox := _tree_tooltip.get_node("TipContent") as VBoxContainer
	for child in tip_vbox.get_children():
		tip_vbox.remove_child(child)
		child.queue_free()
	_tree_tooltip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tip_vbox.add_theme_constant_override("separation", -16)

	var title_style := StyleBoxFlat.new()
	title_style.bg_color = _get_node_color(data).lightened(0.12)
	title_style.set_corner_radius_all(6)
	title_style.content_margin_left = 10
	title_style.content_margin_top = 7
	title_style.content_margin_right = 10
	title_style.content_margin_bottom = 7
	var title_panel := PanelContainer.new()
	title_panel.custom_minimum_size = Vector2(205, 0)
	title_panel.z_index = 1
	title_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_panel.add_theme_stylebox_override("panel", title_style)
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	title_panel.add_child(title_vbox)
	var title_lbl := Label.new()
	title_lbl.text = data.get("name", "???")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.max_lines_visible = 2
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.custom_minimum_size = Vector2(0, 56)
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_vbox.add_child(title_lbl)
	tip_vbox.add_child(title_panel)

	var upgrade_id: String = data.get("upgrade_id", "")
	var current_effect: float = UpgradeManager.get_effect_total(upgrade_id)
	var increase: float = data.get("effect", 0.0)
	var is_unlock := upgrade_id.ends_with("_unlock")
	var stat_style := StyleBoxFlat.new()
	stat_style.bg_color = Color(0.16, 0.16, 0.16)
	stat_style.border_color = Color(0.35, 0.35, 0.35)
	stat_style.border_width_left = 2
	stat_style.border_width_top = 2
	stat_style.border_width_right = 2
	stat_style.border_width_bottom = 3
	stat_style.set_corner_radius_all(6)
	stat_style.content_margin_left = 10
	stat_style.content_margin_top = 15
	stat_style.content_margin_right = 10
	stat_style.content_margin_bottom = 12
	var stat_panel := PanelContainer.new()
	stat_panel.custom_minimum_size = Vector2(260, 0)
	stat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_panel.add_theme_stylebox_override("panel", stat_style)
	var stat_box := VBoxContainer.new()
	stat_box.add_theme_constant_override("separation", 0)
	var increase_label := Label.new()
	increase_label.text = (
		upgrade_id.replace("_unlock", "").capitalize()
		if is_unlock
		else "%+.0f%%" % (increase * 100)
	)
	increase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	increase_label.add_theme_font_size_override("font_size", 30)
	increase_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	stat_box.add_child(increase_label)
	var change_label := Label.new()
	change_label.text = "(%+.0f%% → %+.0f%%)" % [
		current_effect * 100,
		(current_effect + increase) * 100,
	]
	change_label.visible = not is_unlock
	change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	change_label.add_theme_font_size_override("font_size", 16)
	change_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	stat_box.add_child(change_label)
	var divider := HSeparator.new()
	stat_box.add_child(divider)
	var price := Label.new()
	price.text = "$%.0f" % data.get("cost", 0.0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 30)
	price.add_theme_color_override(
		"font_color",
		(
			Color(0.35, 0.9, 0.45)
			if UpgradeManager.can_afford_node(node_id)
			else Color(1.0, 0.45, 0.45)
		),
	)
	price.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.05, 0.65))
	price.add_theme_constant_override("shadow_offset_x", 0)
	price.add_theme_constant_override("shadow_offset_y", 1)
	price.visible = not data.get("purchased", false)
	stat_box.add_child(price)
	stat_panel.add_child(stat_box)
	tip_vbox.add_child(stat_panel)

	_tree_tooltip.visible = true
	_tree_tooltip.reset_size()
	var tree_ctrl := _tree_content.get_parent() as Control
	var tip_offset := Vector2(_tree_tooltip.size.x / 2.0, _tree_tooltip.size.y + 10.0)
	if tree_ctrl != null:
		_tree_tooltip.position = tree_ctrl.get_global_transform() * (anchor_pos - tip_offset)
	else:
		_tree_tooltip.position = anchor_pos - tip_offset


func _hide_tree_tooltip() -> void:
	if _tree_tooltip != null:
		_tree_tooltip.visible = false


func _is_tree_node_visible(id: String) -> bool:
	if id == UpgradeManager.root_node_name:
		return true
	if _animating_children.has(id):
		return false
	var data := UpgradeManager.get_node_data(id)
	if data.get("purchased", false):
		return true
	if data.get("can_unlock", false):
		return true
	return false


func _update_tree_visibility(tree_ctrl: Control) -> void:
	if _tree_content == null:
		return
	var root_name := UpgradeManager.root_node_name
	for id in UpgradeManager.tree_positions:
		var node := _tree_content.get_node_or_null("TreeNode_" + id)
		if node == null:
			continue
		node.visible = _is_tree_node_visible(id)
	tree_ctrl.queue_redraw()


func _update_root_counter(circle: CircleNode) -> void:
	var root_name := UpgradeManager.root_node_name
	var purchased := 0
	var total := 0
	for id in UpgradeManager.tree_nodes:
		if id == root_name:
			continue
		total += 1
		if UpgradeManager.is_node_purchased(id):
			purchased += 1
	var sym := circle.get_node_or_null("Symbol") as Label
	if sym != null:
		sym.text = "%d/%d" % [purchased, total]


func _create_tree_root_node(root_name: String) -> CircleNode:
	var circle := CircleNode.new()
	circle.name = "TreeNode_" + root_name
	circle.fill_color = Color(0.88, 0.65, 0.12)
	circle.border_color = Color(0.95, 0.82, 0.25)
	circle.border_width = 0.0
	circle.size = Vector2(70, 70)
	circle.custom_minimum_size = Vector2(70, 70)
	circle.anchor_left = 0
	circle.anchor_top = 0
	circle.anchor_right = 0
	circle.anchor_bottom = 0
	var sym := Label.new()
	sym.name = "Symbol"
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sym.add_theme_font_size_override("font_size", 20)
	sym.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	sym.position = Vector2(0, 0)
	sym.size = Vector2(70, 70)
	sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sym.self_modulate = Color(1, 1, 1, 0.6)
	circle.add_child(sym)
	_update_root_counter(circle)
	var data := UpgradeManager.get_node_data(root_name)
	_style_tree_node(circle, data)
	circle.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("hover")
			_hover_tree_node(circle, true),
	)
	circle.mouse_exited.connect(
		func():
			_hover_tree_node(circle, false),
	)
	return circle


func _hover_tree_node(node: CircleNode, hovered: bool) -> void:
	node.pivot_offset = node.size / 2.0
	var target := Vector2(1.08, 1.08) if hovered else Vector2(1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(node, "scale", target, 0.08)


func _create_tree_node(id: String, data: Dictionary) -> CircleNode:
	var circle := CircleNode.new()
	circle.name = "TreeNode_" + id
	circle.anchor_left = 0
	circle.anchor_top = 0
	circle.anchor_right = 0
	circle.anchor_bottom = 0
	_style_tree_node(circle, data)
	var is_hovered := false
	circle.mouse_entered.connect(
		func():
			is_hovered = true
			AudioManager.play_sfx_ui("hover")
			var top_center_local := (circle.position + Vector2(circle.size.x / 2.0, 0.0))
			var anchor := _tree_content.position + _tree_content.scale * top_center_local
			_show_tree_tooltip(id, anchor)
			_hover_tree_node(circle, true),
	)
	circle.mouse_exited.connect(
		func():
			is_hovered = false
			_hide_tree_tooltip()
			_hover_tree_node(circle, false),
	)
	circle.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					var end_scale := Vector2(1.08, 1.08) if is_hovered else Vector2(1.0, 1.0)
					_buy_tree_upgrade(id, circle, end_scale)
					circle.accept_event(),
	)
	return circle


func _style_tree_node(circle: CircleNode, data: Dictionary) -> void:
	var purchased: bool = data.get("purchased", false)
	var can_buy: bool = data.get("can_buy", false)
	if data.get("is_root", false):
		circle.fill_color = Color(0.18, 0.18, 0.18)
		circle.is_square = false
		circle.border_color = Color(0.7, 0.7, 0.7)
		circle.border_width = 4.0
	elif purchased:
		circle.fill_color = _get_node_color(data).lightened(0.15)
		circle.is_square = false
		circle.border_width = 0.0
	else:
		circle.fill_color = Color(0.18, 0.18, 0.18)
		circle.is_square = true
		circle.border_color = _get_node_color(data).lightened(0.25)
		circle.border_width = 4.0
	var base_size: int = 70
	var node_size: int = base_size
	circle.size_flags_horizontal = 0
	circle.size_flags_vertical = 0
	circle.custom_minimum_size = Vector2(node_size, node_size)
	circle.size = Vector2(node_size, node_size)
	circle.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if (not purchased and can_buy)
		else Control.CURSOR_ARROW
	)
	var icon := _get_node_icon(data)
	var sym := circle.get_node_or_null("Symbol") as Control
	if (
		sym != null
		and ((icon != null and not sym is TextureRect) or (icon == null and not sym is Label))
	):
		sym.queue_free()
		sym = null
	if icon != null:
		if sym == null:
			sym = TextureRect.new()
			sym.name = "Symbol"
			sym.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sym.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sym.position = Vector2(0, 0)
			circle.add_child(sym)
		var tex: TextureRect = sym as TextureRect
		var icon_size: int = mini(int(node_size * 0.7), 40)
		tex.texture = icon
		if _icon_material == null:
			_icon_material = ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = (
				"shader_type canvas_item; void fragment() { " + "vec4 c = texture(TEXTURE, UV); "
				+ "COLOR = vec4(vec3(1.0 - c.rgb), c.a); }"
			)
			_icon_material.shader = sh
		tex.material = _icon_material
		tex.self_modulate = Color(0.75, 0.75, 0.75, 1.0 if purchased else 0.85)
		tex.size = Vector2(icon_size, icon_size)
		tex.position = Vector2((node_size - icon_size) / 2.0, (node_size - icon_size) / 2.0)
	else:
		if sym == null:
			sym = Label.new()
			sym.name = "Symbol"
			sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sym.position = Vector2(0, 0)
			circle.add_child(sym)
		var lbl: Label = sym as Label
		if not data.get("is_root", false):
			lbl.text = _get_node_symbol(data)
		lbl.size = Vector2(node_size, node_size)
		lbl.position = Vector2(0, 0)
		var font_size: int = 16 if data.get("is_root", false) else maxi(node_size / 2, 10)
		var font_color := Color(0.92, 0.90, 0.82)
		if data.get("is_root", false):
			font_color = Color.WHITE
			lbl.self_modulate = Color.WHITE
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", font_color)
	circle.queue_redraw()


func _get_node_icon(data: Dictionary) -> Texture2D:
	var id: String = data.get("upgrade_id", "")
	var cat: String = data.get("category", "")
	var icon_name := ""
	if id == "sunroof":
		icon_name = "patience"
	elif cat == "recipe" or id.ends_with("_unlock"):
		icon_name = "fruitunlock"
	else:
		icon_name = id.replace("_", "")
	var path := "res://assets/textures/ui/upgrades/" + icon_name + ".png"
	if FileAccess.file_exists(path):
		return load(path) as Texture2D
	return null


func _get_node_symbol(data: Dictionary) -> String:
	var name: String = data.get("name", "").to_lower()
	if "press" in name or "speed" in name:
		return "⚙"
	if "sunroof" in name or "sun" in name:
		return "☀"
	if "lemon" in name:
		return "🍋"
	if "strawberry" in name:
		return "🍓"
	if "blueberry" in name:
		return "🫐"
	if "peach" in name:
		return "🍑"
	if "watermelon" in name:
		return "🍉"
	if "negotiation" in name:
		return "�"
	if "nimbleness" in name or "nimb" in name:
		return "👟"
	if "water" in name or "dispenser" in name:
		return "💧"
	var upgrade_id: String = data.get("upgrade_id", "")
	return upgrade_id.left(1).to_upper() if not upgrade_id.is_empty() else "?"


func _get_branch_color(branch_idx: int) -> Color:
	return BRANCH_COLORS[branch_idx % BRANCH_COLORS.size()]


func _get_node_color(data: Dictionary) -> Color:
	if data.get("is_root", false):
		return Color(0.92, 0.90, 0.82)
	var branch_idx: int = data.get("branch_index", 0)
	var hue: float = fposmod(branch_idx * 0.618, 1.0)
	return Color.from_hsv(hue, 0.55, 0.72)


func _layout_upgrade_tree(tree_ctrl: Control) -> void:
	var area := _tree_available_area(tree_ctrl)
	if area.x <= 10 or area.y <= 10:
		if _tree_layout_pending:
			return
		_tree_layout_pending = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_tree_layout_pending = false
		area = _tree_available_area(tree_ctrl)
		if area.x <= 10 or area.y <= 10:
			return
	if _tree_content == null:
		return
	var root_name := UpgradeManager.root_node_name
	var root_pos: Vector2 = UpgradeManager.tree_positions.get(root_name, Vector2.ZERO)
	var half_content: Vector2 = _tree_content.size / 2.0
	for id in UpgradeManager.tree_positions:
		var gp: Vector2 = UpgradeManager.tree_positions[id]
		var node := _tree_content.get_node_or_null("TreeNode_" + id) as CircleNode
		if node == null:
			continue
		var sz: Vector2 = node.size
		var rel: Vector2 = gp - root_pos
		var px: float = half_content.x + rel.x - sz.x / 2.0
		var py: float = half_content.y + rel.y - sz.y / 2.0
		node.position = Vector2(px, py)
		node.scale = Vector2(1.0, 1.0)
		node.anchor_left = 0
		node.anchor_top = 0
		node.anchor_right = 0
		node.anchor_bottom = 0
		node.offset_left = px
		node.offset_top = py
		node.offset_right = px + sz.x
		node.offset_bottom = py + sz.y
	_tree_content.scale = Vector2(_tree_scale, _tree_scale)
	var center: Vector2 = area / 2.0
	var half_scaled: Vector2 = half_content * _tree_scale
	_tree_pan_offset.x = clampf(_tree_pan_offset.x, -center.x, center.x)
	_tree_pan_offset.y = clampf(_tree_pan_offset.y, -center.y, center.y)
	_tree_content.position = center + _tree_pan_offset - half_scaled
	tree_ctrl.custom_minimum_size = area
	tree_ctrl.size = area
	var parent_vbox := tree_ctrl.get_parent() as Container
	if parent_vbox:
		parent_vbox.queue_sort()
	_tree_laid_out = true
	tree_ctrl.queue_redraw()


func _tree_available_area(tree_ctrl: Control) -> Vector2:
	var sz := tree_ctrl.size
	if sz.x > 10 and sz.y > 10:
		return sz
	var parent := tree_ctrl.get_parent() as Control
	if parent != null:
		sz = parent.size
	if sz.x > 10 and sz.y > 10:
		return sz
	if panel != null and panel.size.x > 10 and panel.size.y > 10:
		return panel.size
	return Vector2(640, 480)


func _buy_tree_upgrade(
	id: String,
	node: CircleNode,
	end_scale: Vector2 = Vector2(1.0, 1.0),
) -> void:
	var data := UpgradeManager.get_node_data(id)
	if data.get("purchased", false):
		return
	if not data.get("can_buy", false):
		_status_lbl.text = "Not enough money!"
		_animate_status()
		var tween := create_tween()
		var orig := node.position
		tween.tween_property(node, "position", orig + Vector2(4, 0), 0.05)
		tween.tween_property(node, "position", orig - Vector2(4, 0), 0.05)
		tween.tween_property(node, "position", orig + Vector2(2, 0), 0.05)
		tween.tween_property(node, "position", orig, 0.05)
		return
	# Route upgrade purchases through the host.
	if not WorldSync.is_host():
		_request_purchase.rpc_id(1, "upgrade_node", id, 0.0, 0.0)
		_status_lbl.text = "Upgrade purchased!"
		_animate_status()
		return
	if UpgradeManager.purchase_node(id):
		AudioManager.play_sfx_ui("upgrade_bought")
		_status_lbl.text = "Upgrade purchased!"
		_animate_status()
		var purchased_data: Dictionary = UpgradeManager.tree_nodes.get(id, { })
		var uid: String = purchased_data.get("upgrade_id", "")
		if uid.ends_with("_unlock"):
			var fruit := uid.substr(0, uid.length() - 7)
			if fruit in GameState.FRUIT_TYPES:
				_build_shop()
		var newly_visible: Array[String] = []
		for child_id in UpgradeManager.tree_connections.get(id, []):
			var child_node := _tree_content.get_node_or_null("TreeNode_" + child_id) as CircleNode
			if child_node != null and not child_node.visible:
				newly_visible.append(child_id)
				_animating_lines[id + "|" + child_id] = 0.0
				_animating_children[child_id] = true
		_refresh_upgrades()
		node.pivot_offset = node.size / 2.0
		var tween := create_tween()
		tween.tween_property(node, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(node, "scale", end_scale, 0.3).set_ease(Tween.EASE_OUT).set_trans(
			Tween.TRANS_ELASTIC
		)
		_animate_next_node_unlock(id, newly_visible)


func _animate_next_node_unlock(parent_id: String, newly_visible: Array[String]) -> void:
	if newly_visible.is_empty() or _tree_content == null:
		return
	var tree_ctrl := _tree_content.get_parent() as Control
	if tree_ctrl == null:
		return
	for child_id in newly_visible:
		var child_node := _tree_content.get_node_or_null("TreeNode_" + child_id) as CircleNode
		if child_node == null:
			continue
		var line_key: String = parent_id + "|" + child_id
		var line_tween := create_tween()
		line_tween.tween_method(
			func(p: float):
				_animating_lines[line_key] = p
				tree_ctrl.queue_redraw(),
			0.0,
			1.0,
			0.2,
		)
		line_tween.tween_callback(
			func():
				_animating_lines.erase(line_key)
				_animating_children.erase(child_id)
				_update_tree_visibility(tree_ctrl)
				child_node.pivot_offset = child_node.size / 2.0
				child_node.scale = Vector2(0.05, 0.05)
				var child_tween := create_tween()
				child_tween \
						.tween_property(child_node, "scale", Vector2(1.0, 1.0), 0.5) \
						.set_ease(Tween.EASE_OUT) \
						.set_trans(Tween.TRANS_BOUNCE),
		)


func _refresh_tree_node(id: String, node: CircleNode) -> void:
	var data := UpgradeManager.get_node_data(id)
	_style_tree_node(node, data)


func _process(delta: float) -> void:
	if not _right_panel or not _right_panel.visible:
		return
	var center := Vector3.ZERO
	var h_dist := 8.0
	var height := 4.0
	var base_angle := 0.0
	var root := get_tree().current_scene
	if root:
		var world := root.get_node_or_null("World")
		var search_root := world if world != null else root
		var marker := search_root.get_node_or_null("PreviewCenter") as Marker3D
		if marker:
			center = marker.global_position
		var orbit_cam := search_root.get_node_or_null("PreviewOrbitCamera") as Node3D
		if orbit_cam:
			var off := orbit_cam.global_position - center
			h_dist = Vector2(off.x, off.z).length()
			height = off.y
			base_angle = atan2(off.x, off.z)
	_preview_angle += delta * 0.5
	var angle := base_angle + _preview_angle
	_preview_camera.position = center + Vector3(sin(angle) * h_dist, height, cos(angle) * h_dist)
	_preview_camera.look_at(center, Vector3.UP)


func _create_ingredient_card(item: Dictionary) -> PanelContainer:
	return _create_item_card(item, "Card_", Color(0.10, 0.11, 0.14), Color(0.20, 0.22, 0.27))


func _create_equipment_card(item: Dictionary) -> PanelContainer:
	return _create_item_card(item, "EquipCard_", Color(0.09, 0.10, 0.13), Color(0.18, 0.22, 0.30))


func _create_item_card(
	item: Dictionary,
	name_prefix: String,
	bg: Color,
	border: Color,
) -> PanelContainer:
	var id: String = item["id"]
	var is_locked_fruit: bool = (
		id in GameState.FRUIT_TYPES and not UpgradeManager.is_fruit_unlocked(id)
	)
	var card := PanelContainer.new()
	card.name = name_prefix + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(130, 130)

	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = border
	st.set_corner_radius_all(10)
	st.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", st)

	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	card.add_child(inner)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(96, 96)
	preview_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var preview_st := StyleBoxFlat.new()
	preview_st.bg_color = Color(0.08, 0.09, 0.11)
	preview_st.border_width_left = 1
	preview_st.border_width_top = 1
	preview_st.border_width_right = 1
	preview_st.border_width_bottom = 1
	preview_st.border_color = Color(0.35, 0.38, 0.46)
	preview_st.set_corner_radius_all(8)
	preview_st.set_content_margin_all(4)
	preview_panel.add_theme_stylebox_override("panel", preview_st)
	inner.add_child(preview_panel)

	var preview_holder := Control.new()
	preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(preview_holder)

	# Show product image
	var img_path: String = PRODUCT_IMAGES.get(id, "")
	if img_path != "" and FileAccess.file_exists(img_path):
		var preview := TextureRect.new()
		preview.texture = load(img_path) as Texture2D
		preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(88, 88)
		preview.size_flags_horizontal = Control.SIZE_FILL
		preview.size_flags_vertical = Control.SIZE_FILL
		preview_holder.add_child(preview)

	# Overlay a lock icon on top of the preview for locked items
	if is_locked_fruit:
		if preview_holder.get_child_count() > 0:
			preview_holder.get_child(0).modulate = Color(0.5, 0.5, 0.5, 0.7)
		var lock_overlay := Label.new()
		lock_overlay.text = "LOCKED"
		lock_overlay.add_theme_font_size_override("font_size", 11)
		lock_overlay.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		lock_overlay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lock_overlay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock_overlay.z_index = 10
		preview_panel.add_child(lock_overlay)

	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 4)
	inner.add_child(right_box)

	var name_lbl := Label.new()
	name_lbl.text = item["name"]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override(
		"font_color",
		Color(0.45, 0.45, 0.45) if is_locked_fruit else Color(0.92, 0.90, 0.82),
	)
	right_box.add_child(name_lbl)

	if is_locked_fruit:
		var locked_lbl := Label.new()
		locked_lbl.text = "Locked - research to unlock"
		locked_lbl.add_theme_font_size_override("font_size", 13)
		locked_lbl.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		right_box.add_child(locked_lbl)
	else:
		var pack_qty: int = int(item.get("qty", 1))
		var pack_lbl := Label.new()
		pack_lbl.text = "%d unit%s" % [pack_qty, "" if pack_qty == 1 else "s"]
		pack_lbl.add_theme_font_size_override("font_size", 14)
		pack_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		right_box.add_child(pack_lbl)

		var per_unit: float = item["cost"] / maxi(1, pack_qty)
		var per_unit_lbl := Label.new()
		per_unit_lbl.text = "$%.2f / unit" % per_unit
		per_unit_lbl.add_theme_font_size_override("font_size", 14)
		per_unit_lbl.add_theme_color_override("font_color", Color(0.55, 0.70, 0.85))
		right_box.add_child(per_unit_lbl)

	var bottom_row := HBoxContainer.new()
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_row.alignment = BoxContainer.ALIGNMENT_END
	bottom_row.add_theme_constant_override("separation", 6)
	right_box.add_child(bottom_row)

	if not is_locked_fruit:
		var total_lbl := Label.new()
		total_lbl.text = "$%.2f" % item["cost"]
		total_lbl.add_theme_font_size_override("font_size", 18)
		total_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
		total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_row.add_child(total_lbl)

		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.custom_minimum_size = Vector2(40, 40)
		add_btn.add_theme_font_size_override("font_size", 22)
		_apply_button_style(
			add_btn,
			Color(0.14, 0.15, 0.19),
			Color(0.88, 0.65, 0.12),
			Color(0.18, 0.20, 0.25),
			Color(0.92, 0.88, 0.78),
			24,
			1.15,
		)
		add_btn.pressed.connect(
			func():
				AudioManager.play_sfx_ui("tab_click")
				_add_to_cart(item),
		)
		bottom_row.add_child(add_btn)

	return card


func _show_tab(tab_name: String) -> void:
	_active_tab = tab_name
	var content := $MainHBox/Panel/VBox/Content as MarginContainer
	if content:
		for child in content.get_children():
			child.visible = (child.name.to_lower() == tab_name + "page")
			if child.visible:
				child.modulate = Color(1, 1, 1, 0)
				var tween := create_tween()
				tween.tween_property(child, "modulate", Color(1, 1, 1, 1), 0.2)
	if tab_name == "analytics":
		_refresh_analytics()
	elif tab_name == "upgrades":
		_refresh_upgrades()
	elif tab_name == "shop":
		pass
	elif tab_name == "employees":
		_refresh_employees_page()
	_update_flow_indicator()


func _update_flow_indicator() -> void:
	_flow_step = _flow_tabs.find(_active_tab)
	for i in range(_flow_tabs.size()):
		var tab := _flow_tabs[i]
		var step_pc := _flow_indicator.get_node("StepPC_" + tab) as PanelContainer
		if step_pc == null:
			continue
		var step_lbl := step_pc.get_node("StepLbl_" + tab) as Label
		step_pc.visible = true
		if tab == _active_tab:
			var active_st := StyleBoxFlat.new()
			active_st.bg_color = Color(0.88, 0.65, 0.12)
			active_st.set_corner_radius_all(8)
			active_st.set_content_margin_all(8)
			active_st.content_margin_left = 12
			active_st.content_margin_right = 12
			step_pc.add_theme_stylebox_override("panel", active_st)
			if step_lbl:
				step_lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
		else:
			var inactive_st := StyleBoxFlat.new()
			inactive_st.bg_color = Color(0.12, 0.13, 0.17)
			inactive_st.set_corner_radius_all(8)
			inactive_st.set_content_margin_all(8)
			inactive_st.content_margin_left = 12
			inactive_st.content_margin_right = 12
			step_pc.add_theme_stylebox_override("panel", inactive_st)
			if step_lbl:
				step_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _on_tab_hover(step_pc: PanelContainer, tab: String) -> void:
	AudioManager.play_sfx_ui("hover")
	if tab == _active_tab:
		return
	var hover_st := StyleBoxFlat.new()
	hover_st.bg_color = Color(0.18, 0.19, 0.24)
	hover_st.set_corner_radius_all(8)
	hover_st.set_content_margin_all(8)
	hover_st.content_margin_left = 12
	hover_st.content_margin_right = 12
	step_pc.add_theme_stylebox_override("panel", hover_st)


func _on_tab_unhover(step_pc: PanelContainer, tab: String) -> void:
	if tab == _active_tab:
		return
	_update_flow_indicator()


func _refresh_employees_page() -> void:
	var emp_page := $MainHBox/Panel/VBox/Content/EmployeesPage as VBoxContainer
	if emp_page == null:
		return
	for child in emp_page.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Employees"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	emp_page.add_child(title)
	var placeholder := Label.new()
	placeholder.text = "Under Construction"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_font_size_override("font_size", 22)
	placeholder.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	emp_page.add_child(placeholder)


func _build_prices_page() -> void:
	var prices_page := ($MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var container := prices_page.get_node_or_null("PriceListScroll/PriceList") as VBoxContainer
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	for ft in GameState.FRUIT_TYPES:
		if not UpgradeManager.is_fruit_unlocked(ft):
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var name_lbl := Label.new()
		name_lbl.text = ft.capitalize()
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		row.add_child(name_lbl)
		var slider := HSlider.new()
		slider.min_value = Balancing.PRICE_MIN
		slider.max_value = Balancing.PRICE_MAX
		slider.step = 0.05
		slider.value = GameState.get_price(ft)
		slider.custom_minimum_size = Vector2(260, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var val_lbl := Label.new()
		val_lbl.text = "$%.2f" % GameState.get_price(ft)
		val_lbl.custom_minimum_size = Vector2(80, 0)
		val_lbl.add_theme_font_size_override("font_size", 20)
		val_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.28))
		row.add_child(val_lbl)
		var ft_ref := ft
		slider.value_changed.connect(
			func(v: float):
				val_lbl.text = "$%.2f" % v
				# The stand applies the price and updates GameState authoritatively.
				var stand := _get_local_stand()
				if stand and stand.has_method("request_set_price"):
					stand.request_set_price(ft_ref, v)
				else:
					GameState.set_price(ft_ref, v),
		)
		container.add_child(row)


func _refresh_prices_page() -> void:
	var prices_page := ($MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var temp_info := prices_page.get_node_or_null("WeatherRow/TempInfo") as Label
	if temp_info:
		temp_info.text = "Temperature: %.0fC" % GameState.temperature
	var pop_info := prices_page.get_node_or_null("WeatherRow/PopInfo") as Label
	if pop_info:
		pop_info.text = "Popularity: %.0f%%" % (GameState.popularity * 100.0)


func _add_analytics_row(container: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = label + ":"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66))
	row.add_child(name_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	row.add_child(val_lbl)
	container.add_child(row)


func _refresh_analytics() -> void:
	var today := $MainHBox/Panel/VBox/Content/AnalyticsPage/TodayLabel as Label
	if today:
		today.text = "Day %d  |  $%.2f  |  %.0f%% pop  |  %.0fC" % [
			DayManager.day_number,
			GameState.money,
			GameState.popularity * 100.0,
			GameState.temperature,
		]
	var ybox := $MainHBox/Panel/VBox/Content/AnalyticsPage/YesterdayBox as VBoxContainer
	if ybox:
		while ybox.get_child_count() > 0:
			var c := ybox.get_child(0)
			ybox.remove_child(c)
			c.queue_free()
		if DayManager.day_number > 1:
			var h := Label.new()
			h.text = "Day %d Results" % (DayManager.day_number - 1)
			h.add_theme_font_size_override("font_size", 20)
			h.add_theme_color_override("font_color", Color(0.9, 0.87, 0.78))
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(h)
			var sep := HSeparator.new()
			ybox.add_child(sep)
			var rev := Label.new()
			rev.text = "Revenue: $%.2f" % DayManager.day_revenue
			rev.add_theme_font_size_override("font_size", 18)
			rev.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
			rev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(rev)
			var s := Label.new()
			s.text = "Served: %d  |  Happy: %d" % [
				DayManager.day_serves,
				DayManager.day_happy_serves,
			]
			s.add_theme_font_size_override("font_size", 16)
			s.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(s)

	# Lifetime / all-time analytics
	var a_page := $MainHBox/Panel/VBox/Content/AnalyticsPage as VBoxContainer
	var lifetime := a_page.get_node_or_null("LifetimeBox") as VBoxContainer
	if lifetime == null:
		lifetime = VBoxContainer.new()
		lifetime.name = "LifetimeBox"
		lifetime.size_flags_vertical = 0
		lifetime.add_theme_constant_override("separation", 8)
		a_page.add_child(lifetime)
	while lifetime.get_child_count() > 0:
		var c := lifetime.get_child(0)
		lifetime.remove_child(c)
		c.queue_free()
	var h2 := Label.new()
	h2.text = "All-Time Stats"
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h2.add_theme_font_size_override("font_size", 20)
	h2.add_theme_color_override("font_color", Color(0.9, 0.87, 0.78))
	lifetime.add_child(h2)
	lifetime.add_child(HSeparator.new())
	_add_analytics_row(lifetime, "Customers Served", "%d" % GameState.total_customers_served)
	_add_analytics_row(lifetime, "Cups Sold", "%d" % GameState.total_cups_sold)
	_add_analytics_row(lifetime, "Money Made", "$%.2f" % GameState.total_money_earned)
	_add_analytics_row(lifetime, "Money Spent", "$%.2f" % GameState.total_money_spent)
	var total_profit: float = GameState.total_money_earned - GameState.total_money_spent
	_add_analytics_row(lifetime, "Total Profit", "$%.2f" % total_profit)
	_add_analytics_row(lifetime, "Highest Purchase", "$%.2f" % GameState.highest_purchase)
	_add_analytics_row(lifetime, "Highest Balance", "$%.2f" % GameState.highest_money)


func _refresh_upgrades() -> void:
	var upg_page := ($MainHBox/Panel/VBox/Content/UpgradesPage as VBoxContainer)
	if upg_page == null:
		return
	var tree_ctrl := upg_page.get_node_or_null("UpgradeTree") as Control
	if tree_ctrl == null:
		return
	# Update all tree nodes and visibility
	if _tree_content == null:
		return
	var root_name := UpgradeManager.root_node_name
	for id in UpgradeManager.tree_positions:
		if id == root_name:
			continue
		var node := _tree_content.get_node_or_null("TreeNode_" + id) as CircleNode
		if node == null:
			continue
		_refresh_tree_node(id, node)
	_update_tree_visibility(tree_ctrl)
	var root_node := _tree_content.get_node_or_null("TreeNode_" + root_name) as CircleNode
	if root_node != null:
		_update_root_counter(root_node)
	# Wait until the tree control has its real size before centering.
	var parent_vbox := tree_ctrl.get_parent() as Container
	var attempts := 0
	while (tree_ctrl.size.x <= 10 or tree_ctrl.size.y <= 10) and attempts < 20:
		if parent_vbox:
			parent_vbox.queue_sort()
		await RenderingServer.frame_post_draw
		attempts += 1

	# Force the top-level VBox to relayout so Content gets its proper size.
	var panel_vbox := $MainHBox/Panel/VBox as VBoxContainer
	if panel_vbox:
		panel_vbox.queue_sort()
		await RenderingServer.frame_post_draw

	var area := _tree_available_area(tree_ctrl)

	# Fit the visible tree inside the available area, then center the root.
	if not _tree_centered and area.x > 10 and area.y > 10:
		_fit_tree_scale(tree_ctrl, area)
		var root_gp: Vector2 = UpgradeManager.tree_positions[root_name]
		_tree_pan_offset = -root_gp * _tree_scale
		_tree_centered = true
	_layout_upgrade_tree(tree_ctrl)


func _fit_tree_scale(_tree_ctrl: Control, area: Vector2) -> void:
	if _tree_content == null:
		return
	var root_name := UpgradeManager.root_node_name
	var root_gp: Vector2 = UpgradeManager.tree_positions[root_name]
	var max_extent := Vector2.ZERO
	var max_node_size := Vector2(40, 40)
	for id in UpgradeManager.tree_positions:
		var node := _tree_content.get_node_or_null("TreeNode_" + id)
		if node == null or not node.visible:
			continue
		var gp: Vector2 = UpgradeManager.tree_positions[id]
		max_extent.x = max(max_extent.x, abs(gp.x - root_gp.x))
		max_extent.y = max(max_extent.y, abs(gp.y - root_gp.y))
		max_node_size.x = max(max_node_size.x, node.size.x)
		max_node_size.y = max(max_node_size.y, node.size.y)
	if max_extent.x <= 0.001 or max_extent.y <= 0.001:
		return
	var padding: float = 40.0
	var avail_x: float = maxf(0.0, area.x - max_node_size.x - padding * 2.0)
	var avail_y: float = maxf(0.0, area.y - max_node_size.y - padding * 2.0)
	var scale_x: float = avail_x / (max_extent.x * 2.0)
	var scale_y: float = avail_y / (max_extent.y * 2.0)
	var fit_scale: float = min(scale_x, scale_y)
	_tree_scale = clampf(fit_scale, 0.5, 1.2)


func _add_to_cart(item: Dictionary) -> void:
	_cart.append(item)
	_update_cart_ui()
	_animate_status_text("Added to cart!")


func _remove_cart_entry(index: int) -> void:
	if index >= 0 and index < _cart.size():
		_cart.remove_at(index)
		_update_cart_ui()
		_animate_status_text("Removed from cart")


func _update_cart_ui() -> void:
	while _cart_list.get_child_count() > 0:
		var c := _cart_list.get_child(0)
		_cart_list.remove_child(c)
		c.queue_free()
	var total := 0.0
	var has_items := _cart.size() > 0
	for i in _cart.size():
		var item: Dictionary = _cart[i]
		var idx: int = i
		total += item["cost"]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)
		var name_lbl := Label.new()
		name_lbl.text = item["name"]
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var price_lbl := Label.new()
		price_lbl.text = "$%.2f" % item["cost"]
		price_lbl.add_theme_font_size_override("font_size", 16)
		price_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
		row.add_child(price_lbl)
		var rem_btn := Button.new()
		rem_btn.text = "X"
		rem_btn.custom_minimum_size = Vector2(36, 32)
		rem_btn.add_theme_font_size_override("font_size", 16)
		_apply_button_style(
			rem_btn,
			Color(0.14, 0.12, 0.10),
			Color(0.35, 0.15, 0.12),
			Color(0.18, 0.14, 0.12),
			Color(0.95, 0.70, 0.60),
			18,
		)
		rem_btn.pressed.connect(
			func():
				AudioManager.play_sfx_ui("tab_click")
				_remove_cart_entry(idx),
		)
		row.add_child(rem_btn)
		_cart_list.add_child(row)
	_cart_total_lbl.text = "Total: $%.2f" % total
	_checkout_btn.disabled = not has_items or GameState.money < total
	if not has_items:
		var empty := Label.new()
		empty.text = "Cart is empty"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cart_list.add_child(empty)


func _checkout_cart() -> void:
	AudioManager.play_sfx_ui("coins")
	var counts: Dictionary = { }
	var item_lookup: Dictionary = { }
	for item in _cart:
		var id: String = item["id"]
		counts[id] = counts.get(id, 0) + 1
		item_lookup[id] = item
	_cart.clear()
	for id in counts.keys():
		var item: Dictionary = item_lookup[id]
		var qty: int = counts[id]
		if _is_ingredient(item):
			_buy_ingredient(item, qty)
		else:
			for i in range(qty):
				_buy_container(id, item["cost"])
	_update_cart_ui()
	# Only the host should emit checkout_completed (triggers truck delivery).
	# Clients' purchases are routed to the host via _request_purchase RPC,
	# and the host's delivery system handles the actual delivery.
	var stand_name := WorldSync.get_local_stand_name()
	if WorldSync.is_host():
		EventBus.checkout_completed.emit(stand_name)
	else:
		_request_checkout.rpc_id(1, stand_name)


## RPC sent by clients to tell the host that checkout is complete and
## the truck should drive in to deliver the ordered supplies.
@rpc("any_peer", "reliable")
func _request_checkout(stand_name: String) -> void:
	if not WorldSync.is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	GameLog.log("[MorningHub] Host received checkout from %d (stand=%s)" % [sender_id, stand_name])
	EventBus.checkout_completed.emit(stand_name)


func _is_ingredient(item: Dictionary) -> bool:
	return item in shop_items


func _animate_status_text(msg: String) -> void:
	_status_lbl.text = msg
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(1.5)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _buy_ingredient(item: Dictionary, qty: int = 1) -> void:
	var total: float = qty * item["cost"]
	# Route purchases through the host. Clients send an RPC; the host
	# validates money and emits the signal that triggers delivery.
	if WorldSync.is_host():
		if not GameState.spend_money(total):
			return
		var sn := WorldSync.get_local_stand_name()
		for i in range(qty):
			EventBus.supply_order_placed.emit(item["id"], item["qty"], item["cost"], sn)
	else:
		_request_purchase.rpc_id(
			1,
			"supply",
			item["id"],
			float(qty),
			total,
			WorldSync.get_local_stand_name(),
		)
	_status_lbl.text = "Bought %d %s crate(s)!" % [qty, item["name"]]
	_animate_status()


func _buy_container(container_type: String, cost: float) -> void:
	if WorldSync.is_host():
		if not GameState.spend_money(cost):
			_status_lbl.text = "Not enough money!"
			_animate_status()
			return
		EventBus.equipment_order_placed.emit(container_type, WorldSync.get_local_stand_name())
	else:
		_request_purchase.rpc_id(
			1,
			"equipment",
			container_type,
			0.0,
			cost,
			WorldSync.get_local_stand_name(),
		)
	_status_lbl.text = "%s ordered!" % container_type.capitalize().replace("_", " ")
	_animate_status()


## RPC sent by clients to the host to request a purchase from the
## morning hub (computer screen). The host validates money and emits
## the appropriate EventBus signal. stand_name identifies which stand's
## delivery system should handle the order.
@rpc("any_peer", "reliable")
func _request_purchase(
	category: String,
	item_id: String,
	qty: float,
	cost: float,
	stand_name: String = "",
) -> void:
	if not WorldSync.is_host():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	GameLog.log(
		"[MorningHub] Host received purchase from %d: %s/%s (stand=%s)"
		% [sender_id, category, item_id, stand_name]
	)
	match category:
		"supply":
			if not GameState.spend_money(cost):
				return
			# Find the item to get its per-box quantity
			var per_box: float = qty
			for item in shop_items:
				if item.get("id", "") == item_id:
					per_box = item.get("qty", qty)
					break
			for i in range(int(qty)):
				EventBus.supply_order_placed.emit(item_id, per_box, cost / qty, stand_name)
		"equipment":
			if not GameState.spend_money(cost):
				return
			EventBus.equipment_order_placed.emit(item_id, stand_name)
		"upgrade_node":
			UpgradeManager.purchase_node(item_id)
			GameLog.log(
				"[MorningHub] Host purchased upgrade node %s for peer %d" % [item_id, sender_id]
			)


func _animate_status() -> void:
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _on_price_changed(fruit_type: String, new_price: float) -> void:
	var prices_page := ($MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var container := prices_page.get_node_or_null("PriceListScroll/PriceList") as VBoxContainer
	if container == null:
		return
	for row in container.get_children():
		var slider := row.get_child(1) as HSlider
		var val_lbl := row.get_child(2) as Label
		if slider and val_lbl and slider.value != new_price:
			slider.set_value_no_signal(new_price)
			val_lbl.text = "$%.2f" % new_price


## Find the local player's StandUnit so we can send price/recipe
## changes to the host via RPC. Returns null in single-player.
func _get_local_stand() -> Node:
	var root := get_tree().current_scene
	if root == null:
		return null
	# Find the local player first, then use their assigned_stand.
	for p in root.find_children("*", "Player", true, false):
		if p.is_multiplayer_authority():
			var stand: Node = p.get("assigned_stand")
			if stand != null and is_instance_valid(stand):
				return stand
	# Fallback: return the first StandUnit (single-player or unassigned).
	for s in root.find_children("*", "StandUnit", true, false):
		return s
	return null


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_update_morning_data(day)
	else:
		_hide_morning_hub()


func _update_morning_data(day: int) -> void:
	# Reset pan/centering so the tree re-centers each morning
	# (the hub may persist across days).
	_tree_centered = false
	_tree_pan_offset = Vector2.ZERO
	_tree_laid_out = false
	var day_lbl := $MainHBox/Panel/VBox/Header/DayLabel as Label
	if day_lbl:
		day_lbl.text = "Day %d" % day
	var temp_lbl := $MainHBox/Panel/VBox/Header/TempLabel as Label
	if temp_lbl:
		temp_lbl.text = "%.0fC" % GameState.temperature
	var money_lbl := $MainHBox/Panel/VBox/Header/MoneyLabel as Label
	if money_lbl:
		money_lbl.text = "Money: $%.2f" % GameState.money
	var price_slider := ($MainHBox/Panel/VBox/Content/PricesPage/PriceSlider as HSlider)
	if price_slider:
		pass
	_show_tab("analytics")


func _show_morning_hub() -> void:
	_update_morning_data(DayManager.day_number)
	# Set the active stand for research so upgrades are per-stand.
	var stand := _get_local_stand()
	if stand:
		UpgradeManager.set_active_stand(stand.name)
	panel.visible = true
	backdrop.visible = true
	if _right_panel:
		_right_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false)
	var tween := create_tween()
	panel.modulate = Color(1, 1, 1, 0)
	backdrop.modulate = Color(1, 1, 1, 0)
	if _right_panel:
		_right_panel.modulate = Color(1, 1, 1, 0)
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.parallel().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.3)
	if _right_panel:
		tween.parallel().tween_property(_right_panel, "modulate", Color(1, 1, 1, 1), 0.3)


func _hide_morning_hub() -> void:
	# Reset modulate so the next fade-in starts from fully opaque.
	panel.modulate = Color(1, 1, 1, 1)
	backdrop.modulate = Color(1, 1, 1, 1)
	if _right_panel:
		_right_panel.modulate = Color(1, 1, 1, 1)
	panel.visible = false
	backdrop.visible = false
	if _right_panel:
		_right_panel.visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)


func _on_money_changed(_amount: float) -> void:
	_hide_tree_tooltip()
	if not panel.visible:
		return
	var money_lbl := $MainHBox/Panel/VBox/Header/MoneyLabel as Label
	if money_lbl:
		money_lbl.text = "Money: $%.2f" % GameState.money
	if _active_tab == "shop":
		_update_cart_ui()
	elif _active_tab == "upgrades":
		_refresh_upgrades()


func _on_start_day() -> void:
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.parallel().tween_property(backdrop, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.parallel().tween_property(_right_panel, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(
		func():
			panel.visible = false
			backdrop.visible = false
			_right_panel.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			DayManager.start_day(),
	)


func _apply_button_style(
	btn: Button,
	bg: Color,
	fg: Color,
	hover: Color,
	text: Color,
	font: int,
	hover_pitch: float = 1.0,
) -> void:
	btn.add_theme_font_size_override("font_size", font)
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", st)
	var st_h := StyleBoxFlat.new()
	st_h.bg_color = hover
	st_h.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("hover", st_h)
	var st_p := StyleBoxFlat.new()
	st_p.bg_color = fg
	st_p.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("pressed", st_p)
	btn.add_theme_color_override("font_color", text)
	btn.add_theme_color_override("font_hover_color", text)
	btn.add_theme_color_override("font_pressed_color", text)
	btn.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("hover", hover_pitch),
	)


func _scan_stand_state() -> void:
	_bin_amounts.clear()
	_equipment_counts.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for node in root.get_tree().get_nodes_in_group("container"):
		if node is FruitBin:
			for ftype in node.fruit_amounts:
				_bin_amounts[ftype] = (_bin_amounts.get(ftype, 0) + node.fruit_amounts[ftype])
		elif node is IngredientBin:
			var itype: String = node.ingredient_type
			if itype != "":
				_bin_amounts[itype] = (_bin_amounts.get(itype, 0.0) + node.current_amount)
		elif node is CupStack:
			_bin_amounts["cups"] = (_bin_amounts.get("cups", 0) + node.current_count)
		elif node is Pitcher:
			if node.fruit_type != "" and node.fruit_count > 0.0:
				var prev: float = _bin_amounts.get(node.fruit_type, 0.0)
				_bin_amounts[node.fruit_type] = prev + node.fruit_count
			_bin_amounts["water"] = (_bin_amounts.get("water", 0.0) + node.water)
			_bin_amounts["sugar"] = (_bin_amounts.get("sugar", 0.0) + node.sugar)
			_bin_amounts["ice"] = (_bin_amounts.get("ice", 0.0) + node.ice)
	for node in root.get_tree().get_nodes_in_group("supply_box"):
		var box := node as SupplyBox
		if box == null or box.is_equipment:
			continue
		var btype: String = box.ingredient_type
		_bin_amounts[btype] = _bin_amounts.get(btype, 0.0) + box.quantity
	for node in root.get_tree().get_nodes_in_group("water_dispenser"):
		var dispenser := node as WaterDispenser
		if dispenser != null:
			_bin_amounts["water"] = (_bin_amounts.get("water", 0.0) + dispenser.water_fillings)
	for node in root.get_tree().get_nodes_in_group("container"):
		var ctype: String = ""
		if node.has_meta("container_type"):
			ctype = node.get_meta("container_type")
		elif "container_type" in node:
			ctype = node.container_type
		elif node.name.to_lower().contains("bin"):
			ctype = node.name.replace("Bin", "").to_snake_case() + "_bin"
		elif node.name.to_lower().contains("pitcher"):
			ctype = "pitcher"
		elif node.name.to_lower().contains("press"):
			ctype = "press"
		if ctype != "":
			_equipment_counts[ctype] = _equipment_counts.get(ctype, 0) + 1
	_refresh_stats()


func _refresh_stats() -> void:
	while _stats_vbox.get_child_count() > 0:
		var c := _stats_vbox.get_child(0)
		_stats_vbox.remove_child(c)
		c.queue_free()
	var money_lbl := Label.new()
	money_lbl.text = "Money: $%.2f" % GameState.money
	money_lbl.add_theme_font_size_override("font_size", 16)
	money_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	_stats_vbox.add_child(money_lbl)
	for itype in _bin_amounts:
		var amt: float = _bin_amounts[itype]
		var line := Label.new()
		line.text = "%s: %.0f" % [itype.capitalize(), amt]
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color", Color(0.6, 0.75, 0.88))
		_stats_vbox.add_child(line)
	for etype in _equipment_counts:
		var cnt: int = _equipment_counts[etype]
		var line := Label.new()
		line.text = "%s: %d" % [etype.capitalize().replace("_", " "), cnt]
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
		_stats_vbox.add_child(line)


func _on_dev_reset() -> void:
	SaveManager.delete_save()
	GameState.money = Balancing.STARTING_MONEY
	GameState.popularity = 0.1
	GameState.temperature = 25.0
	for ft in GameState.FRUIT_TYPES:
		GameState.prices[ft] = 1.50
	GameState.feedback_tier = 0
	GameState.customers_served_happy = 0
	GameState.customers_lost = 0
	DayManager.day_number = 1
	UpgradeManager.reset()
	var root := get_tree().current_scene
	if root:
		# Respawn scene-placed containers with default state
		SaveManager.respawn_default_containers()
	EventBus.game_reset.emit()
	EventBus.money_changed.emit(GameState.money)
	EventBus.price_changed.emit("lemon", GameState.get_price("lemon"))
	EventBus.weather_changed.emit(GameState.temperature)


func _build_recipes_page() -> void:
	var recipes_page := $MainHBox/Panel/VBox/Content/RecipesPage as VBoxContainer
	if recipes_page == null:
		return
	for child in recipes_page.get_children():
		child.queue_free()
	_ice_spin = null
	var title := Label.new()
	title.text = "Recipe Book"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25, 1))
	recipes_page.add_child(title)

	var grid := GridContainer.new()
	grid.name = "RecipesGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipes_page.add_child(grid)

	var fruit_colors: Dictionary = {
		"lemon": Color(0.95, 0.85, 0.15, 1),
		"strawberry": Color(0.92, 0.25, 0.35, 1),
		"blueberry": Color(0.35, 0.55, 0.95, 1),
		"peach": Color(0.95, 0.65, 0.45, 1),
		"watermelon": Color(0.35, 0.75, 0.45, 1),
	}

	var ice_accent := Color(0.55, 0.70, 0.85, 1)
	var ice_card := _make_recipe_card("Ice", ice_accent)
	grid.add_child(ice_card)
	var ice_box := ice_card.get_node("Body/Inner") as VBoxContainer

	var ice_lbl := Label.new()
	ice_lbl.text = "Degrees per scoop"
	ice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ice_lbl.add_theme_font_size_override("font_size", 16)
	ice_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	ice_box.add_child(ice_lbl)

	var ice_spin := SpinBox.new()
	ice_spin.name = "IceSpin"
	ice_spin.min_value = 0.5
	ice_spin.max_value = 10.0
	ice_spin.step = 0.1
	ice_spin.value = GameState.ice_degrees_per_scoop
	ice_spin.custom_minimum_size = Vector2(120, 40)
	ice_box.add_child(ice_spin)
	_ice_spin = ice_spin
	_style_spinbox(ice_spin, ice_accent)

	var unit_row := HBoxContainer.new()
	unit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	unit_row.add_theme_constant_override("separation", 10)
	ice_box.add_child(unit_row)
	var c_btn := Button.new()
	c_btn.text = "C"
	c_btn.toggle_mode = true
	c_btn.button_pressed = true
	var f_btn := Button.new()
	f_btn.text = "F"
	f_btn.toggle_mode = true
	unit_row.add_child(c_btn)
	unit_row.add_child(f_btn)
	_style_unit_button(c_btn, ice_accent)
	_style_unit_button(f_btn, ice_accent)

	var _update_ice_display := func():
		var c_val: float = GameState.ice_degrees_per_scoop
		var display: float = c_val * (1.8 if _ice_unit == "F" else 1.0)
		if _ice_unit == "F":
			ice_spin.min_value = 0.9
			ice_spin.max_value = 18.0
		else:
			ice_spin.min_value = 0.5
			ice_spin.max_value = 10.0
		ice_spin.value = display

	ice_spin.value_changed.connect(
		func(v: float):
			var c_val: float = v if _ice_unit == "C" else v / 1.8
			GameState.ice_degrees_per_scoop = c_val
			_update_ice_display.call(),
	)
	c_btn.pressed.connect(
		func():
			_ice_unit = "C"
			c_btn.button_pressed = true
			f_btn.button_pressed = false
			_update_ice_display.call(),
	)
	f_btn.pressed.connect(
		func():
			_ice_unit = "F"
			f_btn.button_pressed = true
			c_btn.button_pressed = false
			_update_ice_display.call(),
	)
	_update_ice_display.call()

	for ft in GameState.FRUIT_TYPES:
		var locked := not UpgradeManager.is_fruit_unlocked(ft)
		var accent: Color = fruit_colors.get(ft, Color(0.92, 0.78, 0.25, 1))
		if locked:
			accent = Color(0.40, 0.40, 0.40, 1)
		var card := _make_recipe_card(ft, accent, locked)
		grid.add_child(card)
		var card_box := card.get_node("Body/Inner") as VBoxContainer

		if locked:
			var lock_lbl := Label.new()
			lock_lbl.text = "???"
			lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock_lbl.add_theme_font_size_override("font_size", 18)
			card_box.add_child(lock_lbl)
			continue

		var recipe := GameState.get_recipe(ft)

		var fruit_row := _make_spin_row("Fruit", 1, 10, 1, recipe.get("fruit_count", 1.0))
		card_box.add_child(fruit_row)
		var fruit_spin := fruit_row.get_node("SpinBox") as SpinBox
		_style_spinbox(fruit_spin, accent)
		fruit_spin.value_changed.connect(
			func(v: float):
				var r := GameState.get_recipe(ft).duplicate()
				r["fruit_count"] = v
				# The stand applies the recipe and updates GameState authoritatively.
				var stand := _get_local_stand()
				if stand and stand.has_method("request_set_recipe"):
					stand.request_set_recipe(ft, r)
				else:
					GameState.set_recipe(ft, r),
		)

		var sugar_row := _make_spin_row("Sugar", 0, 10, 0.1, recipe.get("sugar", 0.0))
		card_box.add_child(sugar_row)
		var sugar_spin := sugar_row.get_node("SpinBox") as SpinBox
		_style_spinbox(sugar_spin, accent)
		sugar_spin.value_changed.connect(
			func(v: float):
				var r := GameState.get_recipe(ft).duplicate()
				r["sugar"] = v
				# The stand applies the recipe and updates GameState authoritatively.
				var stand := _get_local_stand()
				if stand and stand.has_method("request_set_recipe"):
					stand.request_set_recipe(ft, r)
				else:
					GameState.set_recipe(ft, r),
		)


func _make_recipe_card(title_text: String, accent: Color, locked: bool = false) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.name = "RecipeCard_" + title_text.to_lower()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 0)

	var top_bar := ColorRect.new()
	top_bar.custom_minimum_size = Vector2(0, 4)
	top_bar.color = accent
	card.add_child(top_bar)

	var body := PanelContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_st := StyleBoxFlat.new()
	body_st.bg_color = Color(0.08, 0.09, 0.11, 1)
	body_st.border_color = Color(0.18, 0.19, 0.23, 1)
	body_st.border_width_left = 1
	body_st.border_width_top = 0
	body_st.border_width_right = 1
	body_st.border_width_bottom = 1
	body_st.corner_radius_bottom_left = 12
	body_st.corner_radius_bottom_right = 12
	body_st.content_margin_left = 14
	body_st.content_margin_top = 10
	body_st.content_margin_right = 14
	body_st.content_margin_bottom = 14
	body.add_theme_stylebox_override("panel", body_st)
	card.add_child(body)

	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 12)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(inner)

	if not locked:
		var title_lbl := Label.new()
		title_lbl.text = title_text.capitalize()
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_size_override("font_size", 22)
		title_lbl.add_theme_color_override("font_color", accent)
		inner.add_child(title_lbl)

	return card


func _make_spin_row(
	label_text: String,
	min_v: float,
	max_v: float,
	step_v: float,
	start_v: float,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.76, 0.80, 1))
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.name = "SpinBox"
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = start_v
	spin.custom_minimum_size = Vector2(90, 36)
	row.add_child(spin)
	return row


func _style_spinbox(spin: SpinBox, accent: Color) -> void:
	spin.add_theme_font_size_override("font_size", 18)
	var le := spin.get_line_edit() as LineEdit
	if le == null:
		return
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_size_override("font_size", 18)
	le.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.13, 0.16, 1)
	st.border_color = accent
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.set_corner_radius_all(8)
	st.content_margin_left = 6
	st.content_margin_top = 4
	st.content_margin_right = 6
	st.content_margin_bottom = 4
	le.add_theme_stylebox_override("normal", st)
	var focus_st := StyleBoxFlat.new()
	focus_st.bg_color = Color(0.16, 0.17, 0.21, 1)
	focus_st.border_color = Color(0.95, 0.85, 0.45, 1)
	focus_st.border_width_left = 1
	focus_st.border_width_top = 1
	focus_st.border_width_right = 1
	focus_st.border_width_bottom = 1
	focus_st.set_corner_radius_all(8)
	le.add_theme_stylebox_override("focus", focus_st)


func _style_unit_button(btn: Button, accent: Color) -> void:
	btn.custom_minimum_size = Vector2(44, 32)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.05, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var normal_st := StyleBoxFlat.new()
	normal_st.bg_color = Color(0.12, 0.13, 0.16, 1)
	normal_st.border_color = Color(0.35, 0.37, 0.44, 1)
	normal_st.border_width_left = 1
	normal_st.border_width_top = 1
	normal_st.border_width_right = 1
	normal_st.border_width_bottom = 1
	normal_st.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal_st)
	var pressed_st := StyleBoxFlat.new()
	pressed_st.bg_color = accent
	pressed_st.border_color = accent
	pressed_st.border_width_left = 1
	pressed_st.border_width_top = 1
	pressed_st.border_width_right = 1
	pressed_st.border_width_bottom = 1
	pressed_st.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", pressed_st)
	var hover_st := StyleBoxFlat.new()
	hover_st.bg_color = Color(0.18, 0.19, 0.23, 1)
	hover_st.border_color = accent
	hover_st.border_width_left = 1
	hover_st.border_width_top = 1
	hover_st.border_width_right = 1
	hover_st.border_width_bottom = 1
	hover_st.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover_st)
	btn.mouse_entered.connect(
		func():
			AudioManager.play_sfx_ui("hover"),
	)


func _refresh_recipes_page() -> void:
	if _ice_spin != null:
		var display: float = GameState.ice_degrees_per_scoop * (1.8 if _ice_unit == "F" else 1.0)
		_ice_spin.value = display


func _on_dev_end_day() -> void:
	DayManager.end_day()
