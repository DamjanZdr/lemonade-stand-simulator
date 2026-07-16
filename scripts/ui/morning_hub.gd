extends CanvasLayer
## Morning hub: Analytics, Shop, Upgrades. Compact, animated, lemonade-stand vibe.

const ITEM_PREVIEW_WIDGET: PackedScene = preload("res://scenes/ui/item_preview_3d.tscn")
const ITEM_PREVIEW_SCENES: Dictionary = {
	"lemon": preload("res://scenes/ui/shop_previews/lemon_preview.tscn"),
	"strawberry": preload("res://scenes/ui/shop_previews/strawberry_preview.tscn"),
	"blueberry": preload("res://scenes/ui/shop_previews/blueberry_preview.tscn"),
	"peach": preload("res://scenes/ui/shop_previews/peach_preview.tscn"),
	"watermelon": preload("res://scenes/ui/shop_previews/watermelon_preview.tscn"),
	"sugar": preload("res://scenes/ui/shop_previews/sugar_preview.tscn"),
	"ice": preload("res://scenes/ui/shop_previews/ice_preview.tscn"),
	"cups": preload("res://scenes/ui/shop_previews/cups_preview.tscn"),
	"water": preload("res://scenes/ui/shop_previews/water_preview.tscn"),
	"fruit_bin": preload("res://scenes/ui/shop_previews/fruit_bin_preview.tscn"),
	"sugar_bin": preload("res://scenes/ui/shop_previews/sugar_bin_preview.tscn"),
	"ice_bin": preload("res://scenes/ui/shop_previews/ice_bin_preview.tscn"),
	"pitcher": preload("res://scenes/ui/shop_previews/pitcher_preview.tscn"),
	"press": preload("res://scenes/ui/shop_previews/press_preview.tscn"),
}

@onready var panel: PanelContainer = $MainHBox/Panel
@onready var vbox: VBoxContainer = $MainHBox/Panel/VBox
@onready var backdrop: ColorRect = $Backdrop

@onready var _status_lbl: Label = $MainHBox/Panel/VBox/BottomBar/StatusLbl
@onready var _back_btn: Button = $MainHBox/Panel/VBox/FlowIndicator/BackBtn
@onready var _next_btn: Button = $MainHBox/Panel/VBox/FlowIndicator/NextBtn
@onready var _start_btn: Button = (
		$MainHBox/Panel/VBox/Content/ReadyPage/StartDayBtn
)
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
@onready var _stats_vbox: VBoxContainer = (
		$MainHBox/RightPanel/RightVBox/StatsScroll/StatsVBox
)

var _active_tab: String = "analytics"
var _flow_tabs: Array[String] = ["analytics", "upgrades", "shop", "ready"]
var _flow_step: int = 0
var _shop_qty: Dictionary = { }
var _preview_angle: float = 0.0
var _bin_amounts: Dictionary = { }
var _equipment_counts: Dictionary = { }

# Upgrade tree pan state
var _tree_pan_offset: Vector2 = Vector2.ZERO
var _tree_dragging: bool = false
var _tree_drag_start: Vector2 = Vector2.ZERO
var _tree_scale: float = 2.5
var _tree_tooltip: PanelContainer = null
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


	func _init() -> void:
		custom_minimum_size = Vector2(60, 60)
		size = Vector2(60, 60)
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = 0
		size_flags_vertical = 0


	func _draw() -> void:
		var radius: float = minf(size.x, size.y) / 2.0
		var center: Vector2 = size / 2.0
		draw_circle(center, radius, fill_color)
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
]


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false

	_back_btn.pressed.connect(_on_nav_back)
	_next_btn.pressed.connect(_on_next_pressed)
	_start_btn.pressed.connect(_on_start_day)
	_checkout_btn.pressed.connect(_checkout_cart)

	# Make tab labels clickable
	for tab in _flow_tabs:
		var step_pc := _flow_indicator.get_node_or_null(
			"StepPC_" + tab,
		) as PanelContainer
		if step_pc:
			step_pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var t := tab
			step_pc.gui_input.connect(
				func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed:
						if event.button_index == MOUSE_BUTTON_LEFT:
							_show_tab(t)
			)

	# Category buttons
	var cat_row := $MainHBox/Panel/VBox/Content/ShopPage/CatRow as HBoxContainer
	if cat_row:
		for child in cat_row.get_children():
			if child is Button and child.name.begins_with("Cat_"):
				var cat := child.name.substr(4)
				child.pressed.connect(func(): _show_shop_category(cat))

	var price_slider := (
			$MainHBox/Panel/VBox/Content/ReadyPage/PriceRow/PriceSlider as HSlider
	)
	if price_slider:
		price_slider.min_value = 0.25
		price_slider.max_value = 10.0
		price_slider.step = 0.25
		price_slider.value = GameState.current_price
		price_slider.value_changed.connect(
			func(v: float):
				GameState.current_price = v
				EventBus.price_changed.emit(v)
		)

	EventBus.price_changed.connect(_on_price_changed)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.container_placed.connect(func(_t, _n): _scan_stand_state())
	EventBus.container_picked_up.connect(func(_t, _n): _scan_stand_state())
	EventBus.bin_amount_changed.connect(func(_t, _a): _scan_stand_state())
	_show_tab("analytics")

	# Build shop cards
	var shop_grid := (
			$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2/ShopGrid
	) as GridContainer
	if shop_grid:
		for item in shop_items:
			shop_grid.add_child(_create_ingredient_card(item))
		for item in container_items:
			var card := _create_equipment_card(item)
			card.visible = false
			shop_grid.add_child(card)

	# Build upgrade skill tree (uses pre-existing UpgradeTree Control from scene)
	var tree_ctrl := (
			$MainHBox/Panel/VBox/Content/UpgradesPage/UpgradeTree as Control
	)
	if tree_ctrl:
		_tree_tooltip = tree_ctrl.get_node("Tooltip") as PanelContainer
		_tree_tooltip.z_index = 1

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
						var new_scale_up := clampf(_tree_scale * 1.1, 0.3, 1.5)
						var center_up := tree_ctrl.size / 2.0
						var local_up := (
								(mb_event_up.position - center_up - _tree_pan_offset)
								/ _tree_scale
						)
						_tree_pan_offset = (
								mb_event_up.position - center_up - new_scale_up * local_up
						)
						_tree_scale = new_scale_up
						_layout_upgrade_tree(tree_ctrl)
						tree_ctrl.accept_event()
					elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
						var mb_event_down := event as InputEventMouseButton
						var new_scale_down := clampf(_tree_scale / 1.1, 0.3, 1.5)
						var center_down := tree_ctrl.size / 2.0
						var local_down := (
								(mb_event_down.position - center_down - _tree_pan_offset)
								/ _tree_scale
						)
						_tree_pan_offset = (
								mb_event_down.position
								- center_down
								- new_scale_down * local_down
						)
						_tree_scale = new_scale_down
						_layout_upgrade_tree(tree_ctrl)
						tree_ctrl.accept_event()
				elif event is InputEventMouseMotion and _tree_dragging:
					_tree_pan_offset = event.position - _tree_drag_start
					_layout_upgrade_tree(tree_ctrl)
					tree_ctrl.accept_event()
		)

		tree_ctrl.draw.connect(
			func():
				if not _tree_laid_out or _tree_content == null:
					return
				for from_id in UpgradeManager.tree_connections:
					var from_node := _tree_content.get_node_or_null(
						"TreeNode_" + from_id,
					) as CircleNode
					if from_node == null or not from_node.visible:
						continue
					var from_center_local := from_node.position + from_node.size / 2.0
					var from_pos := (
							_tree_content.position + _tree_content.scale * from_center_local
					)
					for to_id in UpgradeManager.tree_connections[from_id]:
						var line_key: String = from_id + "|" + to_id
						var to_node := _tree_content.get_node_or_null(
							"TreeNode_" + to_id,
						) as CircleNode
						if to_node == null:
							continue
						var to_center_local := to_node.position + to_node.size / 2.0
						var to_pos := (
								_tree_content.position + _tree_content.scale * to_center_local
						)
						if _animating_lines.has(line_key):
							var progress: float = _animating_lines[line_key]
							var anim_end: Vector2 = (
									from_pos + progress * (to_pos - from_pos)
							)
							tree_ctrl.draw_line(
								from_pos,
								anim_end,
								Color(1.0, 0.95, 0.5),
								4.0 * _tree_scale,
								true,
							)
							continue
						if not to_node.visible:
							continue
						var from_purchased: bool = (
								from_id == UpgradeManager.root_node_name
								or UpgradeManager.is_node_purchased(from_id)
						)
						var to_purchased: bool = (
								UpgradeManager.is_node_purchased(to_id)
						)
						var line_color := Color(0.22, 0.24, 0.30)
						var line_width := 2.0 * _tree_scale
						if from_purchased and to_purchased:
							line_color = Color(0.88, 0.72, 0.18)
							line_width = 2.5 * _tree_scale
						elif from_purchased:
							line_color = Color(0.45, 0.38, 0.15)
							line_width = 2.0 * _tree_scale
						tree_ctrl.draw_line(
							from_pos,
							to_pos,
							line_color,
							line_width,
							true,
						)
		)

	_scan_stand_state()

	# Fix preview viewport to share the game world
	var preview_viewport := (
			$MainHBox/RightPanel/RightVBox/PreviewContainer/
			AspectRatioContainer/SubViewportContainer/PreviewViewport as SubViewport
	)
	if preview_viewport:
		preview_viewport.world_3d = get_viewport().world_3d
		preview_viewport.render_target_update_mode = (
				SubViewport.UPDATE_WHEN_VISIBLE
		)

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


func _show_tree_tooltip(node_id: String, anchor_pos: Vector2) -> void:
	if _tree_tooltip == null:
		return
	var data := UpgradeManager.get_node_data(node_id)
	var vbox := _tree_tooltip.get_node("TipContent")
	var title := vbox.get_node("TipTitle") as Label
	var price := vbox.get_node("TipPrice") as Label
	var desc := vbox.get_node("TipDesc") as Label
	var effect := vbox.get_node("TipEffect") as Label
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


func _create_tree_root_node(root_name: String) -> CircleNode:
	var circle := CircleNode.new()
	circle.name = "TreeNode_" + root_name
	circle.fill_color = Color(0.88, 0.65, 0.12)
	circle.border_color = Color(0.95, 0.82, 0.25)
	circle.border_width = 2.0
	circle.size = Vector2(55, 55)
	circle.custom_minimum_size = Vector2(55, 55)
	circle.anchor_left = 0
	circle.anchor_top = 0
	circle.anchor_right = 0
	circle.anchor_bottom = 0
	var sym := Label.new()
	sym.name = "Symbol"
	sym.text = "S"
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sym.add_theme_font_size_override("font_size", 28)
	sym.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	sym.position = Vector2(0, 0)
	sym.size = Vector2(55, 55)
	sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.add_child(sym)
	circle.mouse_entered.connect(func(): _hover_tree_node(circle, true))
	circle.mouse_exited.connect(func(): _hover_tree_node(circle, false))
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
			var top_center_local := (
					circle.position + Vector2(circle.size.x / 2.0, 0.0)
			)
			var anchor := _tree_content.position + _tree_content.scale * top_center_local
			_show_tree_tooltip(id, anchor)
			_hover_tree_node(circle, true)
	)
	circle.mouse_exited.connect(
		func():
			is_hovered = false
			_hide_tree_tooltip()
			_hover_tree_node(circle, false)
	)
	circle.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_LEFT:
					var end_scale := Vector2(1.08, 1.08) if is_hovered else Vector2(1.0, 1.0)
					_buy_tree_upgrade(id, circle, end_scale)
					circle.accept_event()
	)
	return circle


func _style_tree_node(circle: CircleNode, data: Dictionary) -> void:
	var purchased: bool = data.get("purchased", false)
	var category: String = data.get("category", "")
	var can_buy: bool = data.get("can_buy", false)
	var spoke_index: int = data.get("spoke_index", 0)
	var cat_color := UpgradeManager.get_category_color(category)
	if purchased:
		circle.fill_color = cat_color.lightened(0.15)
		circle.border_color = Color(0.95, 0.82, 0.25)
	elif can_buy:
		circle.fill_color = cat_color
		circle.border_color = Color(0.95, 0.82, 0.25)
	else:
		circle.fill_color = cat_color.darkened(0.35)
		circle.border_color = Color(0.3, 0.3, 0.3)
	circle.border_width = 2.0
	var base_size: int = 50
	var shrink: int = 3
	var node_size: int = maxi(base_size - spoke_index * shrink, 30)
	circle.size_flags_horizontal = 0
	circle.size_flags_vertical = 0
	circle.custom_minimum_size = Vector2(node_size, node_size)
	circle.size = Vector2(node_size, node_size)
	circle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (
			not purchased and can_buy
	) else Control.CURSOR_ARROW
	var sym := circle.get_node_or_null("Symbol") as Label
	if sym == null:
		sym = Label.new()
		sym.name = "Symbol"
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sym.position = Vector2(0, 0)
		circle.add_child(sym)
	sym.text = _get_node_symbol(data)
	sym.size = Vector2(node_size, node_size)
	var font_size: int = maxi(node_size / 2, 10)
	sym.add_theme_font_size_override("font_size", font_size)
	sym.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	circle.queue_redraw()


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
	if "demand" in name:
		return "📈"
	if "nimbleness" in name or "nimb" in name:
		return "👟"
	if "water" in name or "dispenser" in name:
		return "💧"
	var upgrade_id: String = data.get("upgrade_id", "")
	return upgrade_id.left(1).to_upper() if not upgrade_id.is_empty() else "?"


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
	_tree_content.position = (
			Vector2(area.x / 2.0, area.y / 2.0)
			+ _tree_pan_offset
			- half_content * _tree_scale
	)
	tree_ctrl.custom_minimum_size = area
	tree_ctrl.size = area
	var vbox := tree_ctrl.get_parent() as Container
	if vbox:
		vbox.queue_sort()
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
	if UpgradeManager.purchase_node(id):
		_status_lbl.text = "Upgrade purchased!"
		_animate_status()
		var newly_visible: Array[String] = []
		for child_id in UpgradeManager.tree_connections.get(id, []):
			var child_node := _tree_content.get_node_or_null(
				"TreeNode_" + child_id,
			) as CircleNode
			if child_node != null and not child_node.visible:
				newly_visible.append(child_id)
				_animating_lines[id + "|" + child_id] = 0.0
				_animating_children[child_id] = true
		_refresh_upgrades()
		node.pivot_offset = node.size / 2.0
		var tween := create_tween()
		tween.tween_property(node, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(
			node,
			"scale",
			end_scale,
			0.3,
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		_animate_next_node_unlock(id, newly_visible)


func _animate_next_node_unlock(
		parent_id: String,
		newly_visible: Array[String],
) -> void:
	if newly_visible.is_empty() or _tree_content == null:
		return
	var tree_ctrl := _tree_content.get_parent() as Control
	if tree_ctrl == null:
		return
	for child_id in newly_visible:
		var child_node := _tree_content.get_node_or_null(
			"TreeNode_" + child_id,
		) as CircleNode
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
				child_tween.tween_property(
					child_node,
					"scale",
					Vector2(1.0, 1.0),
					0.5,
				).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
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
	_preview_camera.position = center + Vector3(
		sin(angle) * h_dist,
		height,
		cos(angle) * h_dist,
	)
	_preview_camera.look_at(center, Vector3.UP)


func _create_ingredient_card(item: Dictionary) -> PanelContainer:
	var id: String = item["id"]
	var card := PanelContainer.new()
	card.name = "Card_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.11, 0.14)
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.20, 0.22, 0.27)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", st)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	var preview := ITEM_PREVIEW_WIDGET.instantiate()
	preview.preview_scene = ITEM_PREVIEW_SCENES.get(id, ITEM_PREVIEW_SCENES["cups"])
	preview.custom_minimum_size = Vector2(100, 60)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(preview)

	var name_lbl := Label.new()
	name_lbl.text = item["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	inner.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%.0f for %d" % [item["cost"], item["qty"]]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
	inner.add_child(cost_lbl)

	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qty_row.add_theme_constant_override("separation", 8)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(32, 28)
	_apply_button_style(
		minus,
		Color(0.14, 0.15, 0.19),
		Color(0.25, 0.18, 0.12),
		Color(0.18, 0.19, 0.22),
		Color(0.9, 0.85, 0.75),
		6,
	)
	minus.pressed.connect(func(): _change_qty(id, -1))
	qty_row.add_child(minus)
	var qty_lbl := Label.new()
	qty_lbl.name = "Qty_" + id
	qty_lbl.text = "0"
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.custom_minimum_size = Vector2(28, 0)
	qty_lbl.add_theme_font_size_override("font_size", 15)
	qty_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	qty_row.add_child(qty_lbl)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 28)
	_apply_button_style(
		plus,
		Color(0.14, 0.15, 0.19),
		Color(0.12, 0.25, 0.12),
		Color(0.18, 0.19, 0.22),
		Color(0.9, 0.85, 0.75),
		6,
	)
	plus.pressed.connect(func(): _change_qty(id, 1))
	qty_row.add_child(plus)
	inner.add_child(qty_row)

	var buy_btn := Button.new()
	buy_btn.name = "Buy_" + id
	buy_btn.text = "Add to Cart"
	buy_btn.custom_minimum_size = Vector2(0, 30)
	buy_btn.add_theme_font_size_override("font_size", 12)
	_apply_button_style(
		buy_btn,
		Color(0.14, 0.15, 0.19),
		Color(0.88, 0.65, 0.12),
		Color(0.18, 0.20, 0.25),
		Color(0.92, 0.88, 0.78),
		8,
	)
	buy_btn.pressed.connect(func(): _add_to_cart(item))
	inner.add_child(buy_btn)
	return card


func _create_equipment_card(item: Dictionary) -> PanelContainer:
	var id: String = item["id"]
	var card := PanelContainer.new()
	card.name = "EquipCard_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.10, 0.13)
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.18, 0.22, 0.30)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", st)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	var preview := ITEM_PREVIEW_WIDGET.instantiate()
	preview.preview_scene = ITEM_PREVIEW_SCENES.get(id, ITEM_PREVIEW_SCENES["cups"])
	preview.custom_minimum_size = Vector2(100, 60)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(preview)

	var name_lbl := Label.new()
	name_lbl.text = item["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	inner.add_child(name_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%.0f" % item["cost"]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
	inner.add_child(cost_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Add to Cart"
	buy_btn.custom_minimum_size = Vector2(0, 30)
	buy_btn.add_theme_font_size_override("font_size", 12)
	_apply_button_style(
		buy_btn,
		Color(0.14, 0.15, 0.19),
		Color(0.88, 0.65, 0.12),
		Color(0.18, 0.20, 0.25),
		Color(0.92, 0.88, 0.78),
		8,
	)
	buy_btn.pressed.connect(func(): _add_to_cart(item))
	inner.add_child(buy_btn)
	return card


func _show_tab(tab_name: String) -> void:
	_active_tab = tab_name
	var title_lbl := $MainHBox/Panel/VBox/TabTitle as Label
	if title_lbl:
		title_lbl.text = tab_name.capitalize()
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
		_show_shop_category("consumables")
	elif tab_name == "ready":
		_refresh_ready_page()
	_update_flow_indicator()


func _update_flow_indicator() -> void:
	_flow_step = _flow_tabs.find(_active_tab)
	for i in range(_flow_tabs.size()):
		var tab := _flow_tabs[i]
		var step_pc := _flow_indicator.get_node("StepPC_" + tab) as PanelContainer
		if step_pc == null:
			continue
		var step_lbl := step_pc.get_node("StepLbl_" + tab) as Label
		if tab == _active_tab:
			step_pc.visible = true
			var active_st := StyleBoxFlat.new()
			active_st.bg_color = Color(0.88, 0.65, 0.12)
			active_st.set_corner_radius_all(8)
			active_st.set_content_margin_all(8)
			active_st.content_margin_left = 12
			active_st.content_margin_right = 12
			step_pc.add_theme_stylebox_override("panel", active_st)
			if step_lbl:
				step_lbl.add_theme_color_override(
					"font_color",
					Color(0.05, 0.05, 0.05),
				)
		else:
			step_pc.visible = false
	_back_btn.visible = (_flow_step > 0)
	_next_btn.visible = (_flow_step < _flow_tabs.size() - 1)


func _on_nav_back() -> void:
	var idx := _flow_tabs.find(_active_tab)
	if idx > 0:
		_show_tab(_flow_tabs[idx - 1])


func _on_next_pressed() -> void:
	var idx := _flow_tabs.find(_active_tab)
	if idx < _flow_tabs.size() - 1:
		_show_tab(_flow_tabs[idx + 1])


func _show_shop_category(cat: String) -> void:
	var grid := (
			$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2/ShopGrid
	) as GridContainer
	if grid:
		for child in grid.get_children():
			if child.name.begins_with("Card_"):
				child.visible = (cat == "consumables")
			elif child.name.begins_with("EquipCard_"):
				child.visible = (cat == "equipment")
	var cat_row := $MainHBox/Panel/VBox/Content/ShopPage/CatRow as HBoxContainer
	if cat_row:
		for btn in cat_row.get_children():
			if btn is Button:
				btn.button_pressed = (btn.name == "Cat_" + cat)


func _refresh_ready_page() -> void:
	var ready := (
			$MainHBox/Panel/VBox/Content/ReadyPage as VBoxContainer
	)
	if ready == null:
		return
	var temp_info := ready.get_node_or_null("WeatherRow/TempInfo") as Label
	if temp_info:
		temp_info.text = "Temperature: %.0fC" % GameState.temperature
	var pop_info := ready.get_node_or_null("WeatherRow/PopInfo") as Label
	if pop_info:
		pop_info.text = "Popularity: %.0f%%" % (GameState.popularity * 100.0)
	var start_btn := ready.get_node_or_null("StartDayBtn") as Button
	if start_btn:
		start_btn.text = "Start Day %d" % DayManager.day_number


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
			h.add_theme_font_size_override("font_size", 16)
			h.add_theme_color_override("font_color", Color(0.9, 0.87, 0.78))
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(h)
			var sep := HSeparator.new()
			ybox.add_child(sep)
			var rev := Label.new()
			rev.text = "Revenue: $%.2f" % DayManager.day_revenue
			rev.add_theme_font_size_override("font_size", 15)
			rev.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
			rev.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(rev)
			var s := Label.new()
			s.text = "Served: %d  |  Happy: %d" % [
				DayManager.day_serves,
				DayManager.day_happy_serves,
			]
			s.add_theme_font_size_override("font_size", 13)
			s.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ybox.add_child(s)


func _refresh_upgrades() -> void:
	var upg_page := (
			$MainHBox/Panel/VBox/Content/UpgradesPage as VBoxContainer
	)
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
	_tree_scale = clampf(fit_scale, 0.3, 1.5)


func _change_qty(id: String, delta: int) -> void:
	var new_val := clampi(_shop_qty.get(id, 0) + delta, 0, 10)
	_shop_qty[id] = new_val
	var shop_grid := (
			$MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2/ShopGrid
	) as GridContainer
	if shop_grid:
		var qty_lbl: Label = null
		var card := shop_grid.get_node_or_null("Card_" + id)
		if card:
			qty_lbl = card.get_node_or_null("Inner/Qty_" + id) as Label
		else:
			card = shop_grid.get_node_or_null("EquipCard_" + id)
			if card:
				qty_lbl = card.get_node_or_null("Inner/Qty_" + id) as Label
		if qty_lbl:
			qty_lbl.text = str(new_val)


func _add_to_cart(item: Dictionary) -> void:
	var id: String = item["id"]
	var current: int = _shop_qty.get(id, 0)
	if current < 10:
		_change_qty(id, 1)
		_update_cart_ui()
		_animate_status_text("Added to cart!")


func _remove_from_cart(id: String) -> void:
	var current: int = _shop_qty.get(id, 0)
	if current > 0:
		_change_qty(id, -1)
		_update_cart_ui()
		_animate_status_text("Removed from cart")


func _update_cart_ui() -> void:
	while _cart_list.get_child_count() > 0:
		var c := _cart_list.get_child(0)
		_cart_list.remove_child(c)
		c.queue_free()
	var total := 0.0
	var has_items := false
	var all_items := []
	all_items.append_array(shop_items)
	all_items.append_array(container_items)
	for item in all_items:
		var qty: int = _shop_qty.get(item["id"], 0)
		if qty > 0:
			has_items = true
			total += qty * item["cost"]
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 6)
			var name_lbl := Label.new()
			name_lbl.text = item["name"]
			name_lbl.add_theme_font_size_override("font_size", 14)
			name_lbl.add_theme_color_override(
				"font_color",
				Color(0.92, 0.90, 0.82),
			)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var price_lbl := Label.new()
			price_lbl.text = "$%.2f" % (qty * item["cost"])
			price_lbl.add_theme_font_size_override("font_size", 13)
			price_lbl.add_theme_color_override(
				"font_color",
				Color(0.65, 0.80, 0.45),
			)
			row.add_child(price_lbl)
			var qty_lbl := Label.new()
			qty_lbl.text = "x%d" % qty
			qty_lbl.add_theme_font_size_override("font_size", 14)
			qty_lbl.add_theme_color_override(
				"font_color",
				Color(0.70, 0.88, 1.0),
			)
			qty_lbl.custom_minimum_size = Vector2(30, 0)
			qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(qty_lbl)
			var rem_btn := Button.new()
			rem_btn.text = "X"
			rem_btn.custom_minimum_size = Vector2(32, 30)
			_apply_button_style(
				rem_btn,
				Color(0.14, 0.12, 0.10),
				Color(0.35, 0.15, 0.12),
				Color(0.18, 0.14, 0.12),
				Color(0.95, 0.70, 0.60),
				6,
			)
			rem_btn.pressed.connect(func(): _remove_from_cart(item["id"]))
			row.add_child(rem_btn)
			_cart_list.add_child(row)
	_cart_total_lbl.text = "Total: $%.2f" % total
	_checkout_btn.disabled = not has_items or GameState.money < total
	if not has_items:
		var empty := Label.new()
		empty.text = "Cart is empty"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cart_list.add_child(empty)


func _checkout_cart() -> void:
	for item in shop_items:
		var id: String = item["id"]
		var qty: int = _shop_qty.get(id, 0)
		if qty > 0:
			_buy_ingredient(id)
	for item in container_items:
		var id: String = item["id"]
		var qty: int = _shop_qty.get(id, 0)
		if qty > 0:
			for i in range(qty):
				_buy_container(id, item["cost"])
			_shop_qty[id] = 0
			_change_qty(id, 0)
	_update_cart_ui()


func _animate_status_text(msg: String) -> void:
	_status_lbl.text = msg
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(1.5)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _buy_ingredient(id: String) -> void:
	var qty: int = _shop_qty.get(id, 0)
	if qty <= 0:
		return
	for item in shop_items:
		if item["id"] == id:
			var total: float = qty * item["cost"]
			if not GameState.spend_money(total):
				return
			for i in range(qty):
				EventBus.supply_order_placed.emit(id, item["qty"], item["cost"])
			_status_lbl.text = "Bought %d %s crate(s)!" % [qty, item["name"]]
			_animate_status()
			_shop_qty[id] = 0
			_change_qty(id, 0)
			return


func _buy_container(container_type: String, cost: float) -> void:
	if not GameState.spend_money(cost):
		_status_lbl.text = "Not enough money!"
		_animate_status()
		return
	EventBus.equipment_order_placed.emit(container_type)
	_status_lbl.text = "%s ordered!" % container_type.capitalize().replace("_", " ")
	_animate_status()


func _animate_status() -> void:
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _on_price_changed(value: float) -> void:
	var price_val := (
			$MainHBox/Panel/VBox/Content/ReadyPage/PriceRow/PriceValue as Label
	)
	if price_val:
		price_val.text = "$%.2f" % value


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
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
		var price_slider := (
				$MainHBox/Panel/VBox/Content/ReadyPage/PriceRow/PriceSlider as HSlider
		)
		if price_slider:
			price_slider.value = GameState.current_price
		_show_tab("analytics")
		panel.visible = true
		backdrop.visible = true
		_right_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var tween := create_tween()
		panel.modulate = Color(1, 1, 1, 0)
		backdrop.modulate = Color(1, 1, 1, 0)
		_right_panel.modulate = Color(1, 1, 1, 0)
		tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 0.2)
		tween.parallel().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.3)
		tween.parallel().tween_property(_right_panel, "modulate", Color(1, 1, 1, 1), 0.3)
	else:
		panel.visible = false
		backdrop.visible = false
		_right_panel.visible = false


func _on_money_changed(_amount: float) -> void:
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
			DayManager.start_day()
	)


func _apply_button_style(
		btn: Button,
		bg: Color,
		fg: Color,
		hover: Color,
		text: Color,
		font: int,
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


func _scan_stand_state() -> void:
	_bin_amounts.clear()
	_equipment_counts.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for node in root.get_tree().get_nodes_in_group("container"):
		if node is FruitBin:
			for ftype in node.fruit_amounts:
				_bin_amounts[ftype] = (
						_bin_amounts.get(ftype, 0)
						+ node.fruit_amounts[ftype]
				)
		elif node is IngredientBin:
			var itype: String = node.ingredient_type
			if itype != "":
				_bin_amounts[itype] = (
						_bin_amounts.get(itype, 0.0)
						+ node.current_amount
				)
		elif node is CupStack:
			_bin_amounts["cups"] = (
					_bin_amounts.get("cups", 0)
					+ node.current_count
			)
		elif node is Pitcher:
			if node.fruit_type != "" and node.fruit_count > 0.0:
				var prev: float = _bin_amounts.get(node.fruit_type, 0.0)
				_bin_amounts[node.fruit_type] = prev + node.fruit_count
			_bin_amounts["water"] = (
					_bin_amounts.get("water", 0.0)
					+ node.water
			)
			_bin_amounts["sugar"] = (
					_bin_amounts.get("sugar", 0.0)
					+ node.sugar
			)
			_bin_amounts["ice"] = (
					_bin_amounts.get("ice", 0.0)
					+ node.ice
			)
	for node in root.get_tree().get_nodes_in_group("supply_box"):
		var box := node as SupplyBox
		if box == null or box.is_equipment:
			continue
		var btype: String = box.ingredient_type
		_bin_amounts[btype] = _bin_amounts.get(btype, 0.0) + box.quantity
	for node in root.get_tree().get_nodes_in_group("water_dispenser"):
		var dispenser := node as WaterDispenser
		if dispenser != null:
			_bin_amounts["water"] = (
					_bin_amounts.get("water", 0.0)
					+ dispenser.water_fillings
			)
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
	money_lbl.add_theme_font_size_override("font_size", 13)
	money_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	_stats_vbox.add_child(money_lbl)
	for itype in _bin_amounts:
		var amt: float = _bin_amounts[itype]
		var line := Label.new()
		line.text = "%s: %.0f" % [itype.capitalize(), amt]
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", Color(0.6, 0.75, 0.88))
		_stats_vbox.add_child(line)
	for etype in _equipment_counts:
		var cnt: int = _equipment_counts[etype]
		var line := Label.new()
		line.text = "%s: %d" % [etype.capitalize().replace("_", " "), cnt]
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
		_stats_vbox.add_child(line)


func _on_dev_reset() -> void:
	SaveManager.delete_save()
	GameState.money = Balancing.STARTING_MONEY
	GameState.popularity = 0.1
	GameState.temperature = 25.0
	GameState.current_price = 1.50
	GameState.feedback_tier = 0
	GameState.customers_served_happy = 0
	GameState.customers_lost = 0
	DayManager.day_number = 1
	UpgradeManager.reset()
	var root := get_tree().current_scene
	if root:
		for node in root.get_tree().get_nodes_in_group("container"):
			node.queue_free()
		for node in root.get_tree().get_nodes_in_group("supply_box"):
			node.queue_free()
	EventBus.game_reset.emit()
	EventBus.money_changed.emit(GameState.money)
	EventBus.price_changed.emit(GameState.current_price)
	EventBus.weather_changed.emit(GameState.temperature)
	DayManager._end_day()


func _on_dev_end_day() -> void:
	DayManager._end_day()
