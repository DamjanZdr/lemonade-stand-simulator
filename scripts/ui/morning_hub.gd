extends CanvasLayer
## Morning hub: Analytics, Shop, Upgrades. Compact, animated, lemonade-stand vibe.

const PRODUCT_IMAGES: Dictionary = {
	"lemon": "res://assets/textures/ui/products/lemon.png",
	"raspberry": "res://assets/textures/ui/products/raspberry.png",
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
	"cup_tray": "res://assets/textures/ui/products/cup.png",
	"lemonader": "res://assets/textures/ui/products/press.png",
	"fruitomatic": "res://assets/textures/ui/products/press.png",
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

@onready var panel: PanelContainer = $RootVBox/MainHBox/Panel
@onready var vbox: VBoxContainer = $RootVBox/MainHBox/Panel/VBox
@onready var backdrop: ColorRect = $Backdrop

@onready var _status_lbl: Label = $RootVBox/MainHBox/Panel/VBox/BottomBar/StatusLbl
@onready var _flow_indicator: HBoxContainer = $RootVBox/FlowIndicator
@onready var _stand_name_edit: LineEdit = (
	$RootVBox/MainHBox/RightPanel/RightVBox/StandNameRow/NameEdit
)
@onready var _stand_name_button: Button = (
	$RootVBox/MainHBox/RightPanel/RightVBox/StandNameRow/SaveButton
)
@onready var _wall_color_btn: Button = (
	$RootVBox/MainHBox/RightPanel/RightVBox/WallColorRow/WallColorBtn
)
@onready var _roof_color_btn: Button = (
	$RootVBox/MainHBox/RightPanel/RightVBox/RoofColorRow/RoofColorBtn
)
@onready var _fence_prev: Button = ($RootVBox/MainHBox/RightPanel/RightVBox/FenceRow/FencePrev)
@onready var _fence_next: Button = ($RootVBox/MainHBox/RightPanel/RightVBox/FenceRow/FenceNext)
@onready var _fence_preview: TextureRect = (
	$RootVBox/MainHBox/RightPanel/RightVBox/FenceRow/FencePreview
)
var _wall_swatch: ColorRect = null
var _roof_swatch: ColorRect = null
# The fence texture is a 13-band gradient atlas, 20px per band; the fence
# models ship on band 12 (beige). See neighborhood.gd FENCE_BAND_*.
const FENCE_TEXTURE: Texture2D = preload(
	"res://assets/models/environment/Fences/White1_mailboxmaterialgrid.png"
)
const FENCE_BAND_COUNT: int = 13
const FENCE_DEFAULT_BAND: int = 12
const FENCE_BAND_WIDTH: float = 20.0
const FENCE_TEX_HEIGHT: float = 160.0
var _fence_band: int = FENCE_DEFAULT_BAND

@onready var _cart_list: VBoxContainer = (
	$RootVBox/MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CartScroll/CartList
)
@onready var _cart_total_lbl: Label = (
	$RootVBox/MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CartTotal
)
@onready var _checkout_btn: Button = (
	$RootVBox/MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/CartPC/CartPanel/CheckoutBtn
)

@onready var _right_panel: PanelContainer = $RootVBox/MainHBox/RightPanel
# Cached before _add_scroll_indicator() reparents it under ScrollWrap_* —
# the reference stays valid, the path would not.
@onready var _shop_scroll: ScrollContainer = (
	$RootVBox/MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2
)
@onready var _preview_camera: Camera3D = (
	$RootVBox/MainHBox/RightPanel/RightVBox/PreviewContainer/
		SubViewportContainer/
		PreviewViewport/PreviewCamera
)
@onready var _stats_vbox: VBoxContainer = (
	$RootVBox/MainHBox/RightPanel/RightVBox/StatsScroll/StatsVBox
)

var _active_tab: String = "analytics"
## Demo build: upgrades tab is blocked by a "Not Available in Demo" overlay.
const DEMO_DISABLE_UPGRADES := false
## Matches the main-menu stand-name limit (world_menu.gd NAME_MAX_WEIGHT).
const STAND_NAME_MAX_WEIGHT := 15.0

var _flow_tabs: Array[String] = ["analytics", "shop", "upgrades", "npcs"]
var _demo_upgrades_overlay: Control = null
var _flow_step: int = 0
var _cart: Array[Dictionary] = []
var _closed_overlay: Panel = null
var _bin_amounts: Dictionary = { }
var _equipment_counts: Dictionary = { }

var _ice_spin: SpinBox = null
var _ice_unit: String = "C"

# Bar-based upgrade page columns, keyed by branch id
const UpgradeBarColumnScript := preload("res://scripts/ui/upgrade_bar_column.gd")
var _upgrade_columns: Dictionary = { }

var shop_items: Array[Dictionary] = [
	{ "id": "lemon", "name": "Lemons", "cost": Balancing.SUPPLY_COST_LEMON, "qty": 10 },
	{ "id": "raspberry", "name": "Raspberry", "cost": Balancing.SUPPLY_COST_RASPBERRY, "qty": 10 },
	{
		"id": "strawberry",
		"name": "Strawberry",
		"cost": Balancing.SUPPLY_COST_STRAWBERRY,
		"qty": 10,
	},
	{ "id": "blueberry", "name": "Blueberry", "cost": Balancing.SUPPLY_COST_BLUEBERRY, "qty": 10 },
	{ "id": "peach", "name": "Peach", "cost": Balancing.SUPPLY_COST_PEACH, "qty": 10 },
	{
		"id": "watermelon",
		"name": "Watermelon",
		"cost": Balancing.SUPPLY_COST_WATERMELON,
		"qty": 10,
	},
	{ "id": "sugar", "name": "Sugar", "cost": Balancing.SUPPLY_COST_SUGAR, "qty": 10 },
	{ "id": "ice", "name": "Ice", "cost": Balancing.SUPPLY_COST_ICE, "qty": 10 },
	{
		"id": "water",
		"name": "Water",
		"cost": Balancing.WATER_COST,
		"qty": Balancing.WATER_BOX_FILLINGS,
	},
	{ "id": "cups", "name": "Cups", "cost": Balancing.SUPPLY_COST_CUPS, "qty": 10 },
]

var container_items: Array[Dictionary] = [
	{ "id": "fruit_bin", "name": "Crate", "cost": Balancing.CONTAINER_COST_FRUIT_BIN },
	{ "id": "sugar_bin", "name": "Bowl", "cost": Balancing.CONTAINER_COST_SUGAR_BIN },
	{ "id": "ice_bin", "name": "Bucket", "cost": Balancing.CONTAINER_COST_ICE_BIN },
	{ "id": "pitcher", "name": "Pitcher", "cost": Balancing.CONTAINER_COST_PITCHER },
	{ "id": "press", "name": "Fruit Press", "cost": Balancing.CONTAINER_COST_PRESS },
	{ "id": "workstation", "name": "Table", "cost": Balancing.CONTAINER_COST_WORKSTATION },
	{ "id": "lemonader", "name": "Squeeze-E-Z", "cost": Balancing.CONTAINER_COST_LEMONADER },
	{ "id": "fruitomatic", "name": "Fruit-O-Matic", "cost": Balancing.CONTAINER_COST_FRUITOMATIC },
]


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	_flow_indicator.visible = false
	if _right_panel:
		_right_panel.visible = false

	_checkout_btn.pressed.connect(_checkout_cart)
	_stand_name_button.pressed.connect(_rename_local_stand)
	_stand_name_edit.text_submitted.connect(
		func(_text: String):
			_rename_local_stand(),
	)
	_style_stand_name_controls()
	# Same name limit as the main menu: capitals weigh 1.5, total <= 15.
	_stand_name_edit.text_changed.connect(
		func(new_text: String):
			if _name_weight(new_text) > STAND_NAME_MAX_WEIGHT:
				_stand_name_edit.text = new_text.substr(0, new_text.length() - 1)
				_stand_name_edit.caret_column = _stand_name_edit.text.length(),
	)
	if _wall_color_btn:
		_wall_swatch = _make_swatch_picker(
			_wall_color_btn,
			func(c: Color):
				_set_house_color("wall_color", c),
		)
	if _roof_color_btn:
		_roof_swatch = _make_swatch_picker(
			_roof_color_btn,
			func(c: Color):
				_set_house_color("roof_color", c),
		)
	if _fence_preview:
		var atlas := AtlasTexture.new()
		atlas.atlas = FENCE_TEXTURE
		_fence_preview.texture = atlas
		_update_fence_preview()
	if _fence_prev:
		_fence_prev.pressed.connect(
			func():
				_cycle_fence_gradient(-1),
		)
	if _fence_next:
		_fence_next.pressed.connect(
			func():
				_cycle_fence_gradient(1),
		)

	# NPC collection tab — built at runtime (the editor builder predates
	# it); the click/hover wiring loop below picks it up automatically.
	_build_npcs_tab()

	# The status line floats over the panel's bottom edge instead of
	# holding a layout row — gives that ~35px back to the page lists.
	var bottom_bar := get_node_or_null("RootVBox/MainHBox/Panel/VBox/BottomBar")
	if bottom_bar != null:
		_status_lbl.get_parent().remove_child(_status_lbl)
		panel.add_child(_status_lbl)
		_status_lbl.top_level = true
		_status_lbl.z_index = 10
		_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom_bar.visible = false
		var place_status := func():
			_status_lbl.size = Vector2(panel.size.x - 48.0, 24.0)
			_status_lbl.global_position = (
				panel.global_position + Vector2(24.0, panel.size.y - 40.0)
			)
		place_status.call()
		panel.resized.connect(place_status)

	# Floating "more below" arrows for lists that can overflow.
	for scroll_path in [
		"RootVBox/MainHBox/Panel/VBox/Content/AnalyticsPage/Columns/StatsScroll",
		"RootVBox/MainHBox/Panel/VBox/Content/ShopPage/ShopSplit/ScrollContainer2",
		"RootVBox/MainHBox/Panel/VBox/Content/PricesPage/PriceListScroll",
		"RootVBox/MainHBox/RightPanel/RightVBox/StatsScroll",
	]:
		var sc := get_node_or_null(scroll_path) as ScrollContainer
		if sc != null:
			_add_scroll_indicator(sc)

	# Make tab labels clickable
	for tab in _flow_tabs:
		var step_pc := _flow_indicator.get_node_or_null("StepPC_" + tab) as PanelContainer
		if step_pc:
			# Equal-width tabs — each cell stretches to the same share.
			step_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var step_lbl := step_pc.get_node_or_null("StepLbl_" + tab) as Label
			if step_lbl:
				step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

	var price_slider := ($RootVBox/MainHBox/Panel/VBox/Content/PricesPage/PriceSlider as HSlider)
	if price_slider:
		pass

	EventBus.upgrade_purchased.connect(_on_fruit_research_changed, CONNECT_DEFERRED)
	OnboardingManager.stand_progress_changed.connect(_on_stand_progress_changed, CONNECT_DEFERRED)
	EventBus.price_changed.connect(_on_price_changed)
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.day_time_over.connect(_on_day_time_over)
	_build_closed_overlay()
	# Editor/debug builds (or `--dev` launch flag) skip the demo gate so
	# upgrades stay testable without shipping them in the release demo.
	if _demo_upgrades_blocked():
		_build_demo_upgrades_overlay()
	# Exit button lives at the right end of the tab strip, after
	# Customers — the HUD is hidden while the hub is open, so it stays
	# inside the computer screen. Clicking it exits, same as ESC.
	var exit_btn := Button.new()
	exit_btn.name = "ExitTab"
	exit_btn.text = "X"
	exit_btn.tooltip_text = "Exit computer (ESC)"
	exit_btn.custom_minimum_size = Vector2(64, 56)
	exit_btn.add_theme_font_size_override("font_size", 28)
	exit_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.13, 0.16, 1)
	btn_style.border_color = Color(0.18, 0.20, 0.25, 1)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(8)
	btn_style.content_margin_left = 10.0
	btn_style.content_margin_top = 4.0
	btn_style.content_margin_right = 10.0
	btn_style.content_margin_bottom = 4.0
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.45, 0.15, 0.15, 1)
	var btn_pressed := btn_style.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.3, 0.1, 0.1, 1)
	exit_btn.add_theme_stylebox_override("normal", btn_style)
	exit_btn.add_theme_stylebox_override("hover", btn_hover)
	exit_btn.add_theme_stylebox_override("pressed", btn_pressed)
	exit_btn.pressed.connect(_on_exit_button_pressed)
	_flow_indicator.add_child(exit_btn)

	# Employees tab removed in the demo.
	var emp_tab := _flow_indicator.get_node_or_null("StepPC_employees")
	if emp_tab:
		emp_tab.hide()
	var emp_page := $RootVBox/MainHBox/Panel/VBox/Content.get_node_or_null("EmployeesPage")
	if emp_page:
		emp_page.hide()
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

	# Build the bar-based upgrades page (replaces the old node tree)
	_build_upgrades_page()

	# Fix preview viewport to share the game world
	var preview_viewport := (
		$RootVBox/MainHBox/RightPanel/RightVBox/PreviewContainer/
			SubViewportContainer/PreviewViewport
		as SubViewport
	)
	if preview_viewport:
		preview_viewport.world_3d = get_viewport().world_3d
		preview_viewport.render_target_update_mode = (SubViewport.UPDATE_WHEN_VISIBLE)

	# Dev panel — release builds skip it unless launched with --dev.
	if not _dev_tools_enabled():
		return
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
	var meet_btn := Button.new()
	meet_btn.text = "Meet All NPCs"
	meet_btn.pressed.connect(_on_dev_meet_all_npcs)
	dev_vbox.add_child(meet_btn)


## Dev tools are available in editor/debug builds, or in any build
## launched with --dev (works as a Steam launch option).
func _dev_tools_enabled() -> bool:
	return OS.is_debug_build() \
			or OS.get_cmdline_args().has("--dev") \
			or OS.get_cmdline_user_args().has("--dev")


func _build_shop() -> void:
	if _shop_scroll == null:
		return
	var shop_scroll := _shop_scroll
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Detach before freeing: queue_free() leaves the node in the tree until
	# end of frame, so a second _build_shop in the same frame (e.g. a
	# joiner receiving several fruit-unlock syncs at once) would add a
	# new list while the old one still renders — duplicating headers.
	for child in shop_scroll.get_children():
		shop_scroll.remove_child(child)
		child.queue_free()
	var shop_vbox := VBoxContainer.new()
	shop_vbox.name = "ShopList"
	shop_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_vbox.add_theme_constant_override("separation", 12)
	# Right margin keeps the second card column off the scroll edge;
	# matching left margin keeps the list optically centered.
	var shop_margin := MarginContainer.new()
	shop_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_margin.add_theme_constant_override("margin_left", 4)
	shop_margin.add_theme_constant_override("margin_right", 12)
	shop_margin.add_child(shop_vbox)
	shop_scroll.add_child(shop_margin)
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
	# Unlocked consumables first (keeping their listed order), locked
	# fruits last. As fruits are researched they move back up into
	# their original slot after lemon.
	var unlocked_items: Array[Dictionary] = []
	var locked_items: Array[Dictionary] = []
	for item in shop_items:
		if item["id"] in GameState.FRUIT_TYPES and not _is_local_fruit_unlocked(item["id"]):
			locked_items.append(item)
		else:
			unlocked_items.append(item)
	for item in unlocked_items + locked_items:
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


func _process(_delta: float) -> void:
	if not _right_panel or not _right_panel.visible:
		return
	# Static preview: copy the editor-placed PreviewOrbitCamera node for the
	# local stand (suffix "2" for the versus stand). It's a real Camera3D so
	# its editor preview shows exactly what the hub preview will render.
	var root := get_tree().current_scene
	if root == null:
		return
	var world := root.get_node_or_null("World")
	var search_root := world if world != null else root
	var stand := _get_local_stand()
	var suffix := ""
	if stand != null and is_instance_valid(stand) and not stand.get("is_legacy_primary"):
		suffix = "2"
	var cam_marker := (search_root.find_child("PreviewOrbitCamera" + suffix, true, false) as Node3D)
	if cam_marker == null and suffix != "":
		cam_marker = search_root.find_child("PreviewOrbitCamera", true, false) as Node3D
	if cam_marker:
		_preview_camera.global_transform = cam_marker.global_transform
		if cam_marker is Camera3D:
			_preview_camera.fov = (cam_marker as Camera3D).fov


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
	var is_locked_fruit: bool = (id in GameState.FRUIT_TYPES and not _is_local_fruit_unlocked(id))
	var is_locked_machine: bool = not UpgradeManager.is_item_unlocked(id, _get_local_stand())
	var is_locked: bool = is_locked_fruit or is_locked_machine
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

	# Show product image — locked items stay hidden behind a "?" so the
	# player can't see what they'll unlock.
	var img_path: String = PRODUCT_IMAGES.get(id, "")
	if is_locked:
		var q_lbl := Label.new()
		q_lbl.text = "?"
		q_lbl.add_theme_font_size_override("font_size", 56)
		q_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
		q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview_holder.add_child(q_lbl)
	elif img_path != "" and ResourceLoader.exists(img_path):
		var preview := TextureRect.new()
		preview.texture = load(img_path) as Texture2D
		preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(88, 88)
		preview.size_flags_horizontal = Control.SIZE_FILL
		preview.size_flags_vertical = Control.SIZE_FILL
		preview_holder.add_child(preview)

	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 4)
	inner.add_child(right_box)

	var name_lbl := Label.new()
	name_lbl.text = "Unknown Fruit" if is_locked_fruit else item["name"]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override(
		"font_color",
		Color(0.45, 0.45, 0.45) if is_locked else Color(0.92, 0.90, 0.82),
	)
	if is_locked:
		# Locked cards show only the title — center it next to the "?" icon.
		name_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right_box.add_child(name_lbl)

	if not is_locked:
		var pack_qty: int = int(item.get("qty", 1))
		var pack_lbl := Label.new()
		pack_lbl.text = "%d unit%s" % [pack_qty, "" if pack_qty == 1 else "s"]
		pack_lbl.add_theme_font_size_override("font_size", 14)
		pack_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		right_box.add_child(pack_lbl)

		var per_unit: float = _negotiated_cost(item["cost"]) / maxi(1, pack_qty)
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

		var total_lbl := Label.new()
		total_lbl.text = "$%.2f" % _negotiated_cost(item["cost"])
		total_lbl.add_theme_font_size_override("font_size", 18)
		total_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
		total_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_row.add_child(total_lbl)

		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.custom_minimum_size = Vector2(52, 52)
		add_btn.add_theme_font_size_override("font_size", 28)
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


## Deliveries close at 6 PM — day_time_over is synced to clients by
## DayManager, so this check works on every peer.
func _shop_closed() -> bool:
	return DayManager.day_time_over


## "Closed for today" overlay stacked over the shop page. Content is a
## MarginContainer, so every child fills the same rect — the overlay
## covers whichever page is active; we only show it on the shop tab.
func _build_closed_overlay() -> void:
	var content := $RootVBox/MainHBox/Panel/VBox/Content as MarginContainer
	if content == null:
		return
	_closed_overlay = Panel.new()
	_closed_overlay.name = "ClosedOverlay"
	_closed_overlay.visible = false
	# Block clicks from reaching the shop/cart underneath.
	_closed_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.03, 0.88)
	sb.set_corner_radius_all(8)
	_closed_overlay.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "Closed for today\nDeliveries resume tomorrow morning"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_closed_overlay.add_child(lbl)
	content.add_child(_closed_overlay)


func _update_closed_overlay() -> void:
	if _closed_overlay:
		_closed_overlay.visible = _shop_closed() and _active_tab == "shop"


func _on_day_time_over() -> void:
	_update_closed_overlay()


## Weighted character count for stand names (mirrors world_menu.gd).
func _name_weight(s: String) -> float:
	var weight: float = 0.0
	for ch in s:
		weight += 1.5 if ch >= "A" and ch <= "Z" else 1.0
	return weight


func _rename_local_stand() -> void:
	var stand := _get_local_stand()
	var new_name := _stand_name_edit.text.strip_edges()
	if stand == null or new_name.is_empty():
		return
	stand.request_set_stand_name(new_name)
	_animate_status_text("Renamed to %s" % new_name)


func _refresh_stand_name_editor() -> void:
	var stand := _get_local_stand()
	if stand != null and _stand_name_edit != null:
		_stand_name_edit.text = stand.stand_display_name
	# Sync house color swatches to this stand's style, falling back to
	# the house palettes' defaults so the current color is always shown
	# even if it was never customized.
	var custom: Dictionary = LobbyManager.stand_house_styles.get(_local_stand_index(), { })
	var cm := get_tree().get_first_node_in_group("color_manager")
	var wall_default := Color(0.95, 0.85, 0.55)
	var roof_default := Color(0.5, 0.25, 0.2)
	if cm != null:
		var wc: Array = cm.get("wall_colors")
		if not wc.is_empty():
			wall_default = wc[0]
		var rc: Array = cm.get("roof_colors")
		if not rc.is_empty():
			roof_default = rc[0]
	if _wall_swatch != null:
		var wc_val = custom.get("wall_color", null)
		_wall_swatch.color = wc_val if wc_val is Color else wall_default
	if _roof_swatch != null:
		var rc_val = custom.get("roof_color", null)
		_roof_swatch.color = rc_val if rc_val is Color else roof_default
	_fence_band = posmod(int(custom.get("fence_gradient", FENCE_DEFAULT_BAND)), FENCE_BAND_COUNT)
	_update_fence_preview()


## Turn a plain Button into a lobby-style color picker: a flat rounded
## swatch that opens a minimal ColorPicker popup directly above the button.
## Returns the swatch ColorRect so callers can update the shown color.
func _make_swatch_picker(btn: Button, on_color: Callable) -> ColorRect:
	btn.text = ""
	btn.flat = true
	var swatch := ColorRect.new()
	swatch.color = Color(0.5, 0.5, 0.5)
	swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(swatch)

	# Embedded popup: a real PopupPanel/Window is unreliable inside the
	# computer's SubViewport, so use an overlay PanelContainer + a
	# full-screen click-catcher that closes it.
	var picker := ColorPicker.new()
	picker.sampler_visible = false
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.presets_visible = false

	var popup := PanelContainer.new()
	popup.name = "ColorPopup"
	popup.visible = false
	popup.z_index = 50
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Color(0.10, 0.12, 0.16, 0.97)
	pop_style.set_corner_radius_all(8)
	pop_style.set_border_width_all(1)
	pop_style.border_color = Color(1, 1, 1, 0.2)
	popup.add_theme_stylebox_override("panel", pop_style)
	popup.add_child(picker)

	var catcher := Button.new()
	catcher.name = "ColorPopupCatcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.flat = true
	catcher.visible = false
	catcher.z_index = 49
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		catcher.add_theme_stylebox_override(state, empty)
	add_child(catcher)
	add_child(popup)
	catcher.pressed.connect(
		func():
			popup.visible = false
			catcher.visible = false,
	)
	picker.color_changed.connect(
		func(c: Color):
			on_color.call(c)
			swatch.color = c,
	)
	btn.pressed.connect(
		func():
			picker.color = swatch.color
			catcher.visible = true
			popup.visible = true
			# Open to the left of the button, vertically centered on it.
			var pop_size := popup.get_combined_minimum_size()
			var pos := Vector2(
				btn.global_position.x - pop_size.x - 8,
				btn.global_position.y + (btn.size.y - pop_size.y) * 0.5,
			)
			var win_size := get_viewport().get_visible_rect().size
			pos.x = clampf(pos.x, 0.0, win_size.x - pop_size.x)
			pos.y = clampf(pos.y, 0.0, win_size.y - pop_size.y)
			popup.position = pos,
	)
	return swatch


## Brighter styling for the stand-name input + rename button so they
## read as editable controls against the dark panel.
func _style_stand_name_controls() -> void:
	if _stand_name_edit:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.28, 0.30, 0.36, 0.95)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		_stand_name_edit.add_theme_stylebox_override("normal", sb)
		var sb_f := sb.duplicate() as StyleBoxFlat
		sb_f.border_color = Color(1, 0.9, 0.3, 0.9)
		_stand_name_edit.add_theme_stylebox_override("focus", sb_f)
		_stand_name_edit.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		_stand_name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.45))
	if _stand_name_button:
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.30, 0.34, 0.42, 0.95)
			if state == "hover":
				sb.bg_color = Color(0.38, 0.43, 0.52, 1.0)
			if state == "pressed":
				sb.bg_color = Color(0.25, 0.28, 0.34, 1.0)
			sb.set_corner_radius_all(6)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.35)
			sb.content_margin_left = 14
			sb.content_margin_right = 14
			_stand_name_button.add_theme_stylebox_override(state, sb)
		_stand_name_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))


## The stand index this player is assigned to (0 = primary). Peers without
## a roster entry — offline single-player — default to stand 0.
func _local_stand_index() -> int:
	var idx: int = LobbyManager.get_my_entry().get("stand_index", -1)
	return idx if idx >= 0 else 0


## Store a house color choice on the STAND's style (host-authoritative),
## not on the player. The broadcast triggers _apply_player_house_colors()
## in main.gd on every peer, recoloring the house attached to this stand.
func _set_house_color(key: String, color: Color) -> void:
	var stand_idx := _local_stand_index()
	LobbyManager.set_stand_house_style(stand_idx, key, color)
	# Apply immediately locally too — the roster round-trip may lag a frame,
	# and on clients our own write hasn't landed in stand_house_styles yet.
	var neighborhood := get_tree().get_first_node_in_group("neighborhood")
	if neighborhood != null and neighborhood.has_method("apply_player_house_colors"):
		var style: Dictionary = LobbyManager.stand_house_styles.get(stand_idx, { }).duplicate(true)
		style[key] = color
		var house_name := StringName("player_house" if stand_idx == 0 else "player_house2")
		var wall = style.get("wall_color", Color.TRANSPARENT)
		var roof = style.get("roof_color", Color.TRANSPARENT)
		var fence_band := int(style.get("fence_gradient", -1))
		neighborhood.apply_player_house_colors(
			house_name,
			wall if wall is Color else Color.TRANSPARENT,
			roof if roof is Color else Color.TRANSPARENT,
			fence_band,
		)


func _cycle_fence_gradient(direction: int) -> void:
	AudioManager.play_sfx_ui("tab_click")
	_fence_band = posmod(_fence_band + direction, FENCE_BAND_COUNT)
	_update_fence_preview()
	_set_fence_gradient(_fence_band)


func _update_fence_preview() -> void:
	if _fence_preview == null:
		return
	var atlas := _fence_preview.texture as AtlasTexture
	if atlas == null:
		return
	atlas.region = Rect2(_fence_band * FENCE_BAND_WIDTH, 0.0, FENCE_BAND_WIDTH, FENCE_TEX_HEIGHT)


## Store a fence gradient choice on the stand's style, same broadcast
## path as _set_house_color().
func _set_fence_gradient(band: int) -> void:
	var stand_idx := _local_stand_index()
	LobbyManager.set_stand_house_style(stand_idx, "fence_gradient", band)
	var neighborhood := get_tree().get_first_node_in_group("neighborhood")
	if neighborhood != null and neighborhood.has_method("apply_player_fence_gradient"):
		var house_name := StringName("player_house" if stand_idx == 0 else "player_house2")
		neighborhood.apply_player_fence_gradient(house_name, band)


func _show_tab(tab_name: String) -> void:
	_active_tab = tab_name
	var content := $RootVBox/MainHBox/Panel/VBox/Content as MarginContainer
	if content:
		for child in content.get_children():
			if child == _closed_overlay or child == _demo_upgrades_overlay:
				continue
			child.visible = (child.name.to_lower() == tab_name + "page")
			if child.visible:
				child.modulate = Color(1, 1, 1, 0)
				var tween := create_tween()
				tween.tween_property(child, "modulate", Color(1, 1, 1, 1), 0.2)
	if tab_name == "analytics":
		_refresh_stand_name_editor()
		_refresh_analytics()
	elif tab_name == "upgrades":
		_refresh_upgrades()
		# The player is looking — pour each bar from its last-seen level.
		for branch_id in _upgrade_columns:
			_upgrade_columns[branch_id].on_viewed()
	elif tab_name == "shop":
		# Rebuild so freshly-claimed fruits/machines unlock their cards —
		# lock state is baked into each card at build time.
		_build_shop()
	elif tab_name == "npcs":
		_populate_npc_page()
	if _demo_upgrades_overlay != null:
		_demo_upgrades_overlay.visible = (tab_name == "upgrades")
	# The "Your Stand" panel belongs to the Stats and Shop tabs only.
	if _right_panel:
		_right_panel.visible = tab_name in ["analytics", "shop"]
	_update_flow_indicator()
	_update_closed_overlay()


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


## Builds the NPC collection tab button + page at runtime. The scene was
## authored by the @tool builder before this feature existed, so this
## page lives in code instead of the .tscn.
func _build_npcs_tab() -> void:
	if _flow_indicator == null:
		return
	var step_pc := PanelContainer.new()
	step_pc.name = "StepPC_npcs"
	step_pc.custom_minimum_size = Vector2(160, 56)
	var step_lbl := Label.new()
	step_lbl.name = "StepLbl_npcs"
	step_lbl.text = "Customers"
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step_lbl.add_theme_font_size_override("font_size", 22)
	step_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	step_pc.add_child(step_lbl)
	_flow_indicator.add_child(step_pc)

	var content := $RootVBox/MainHBox/Panel/VBox/Content as MarginContainer
	if content == null:
		return
	var page := VBoxContainer.new()
	page.name = "NpcsPage"
	page.visible = false
	page.add_theme_constant_override("separation", 6)
	content.add_child(page)

	var title := Label.new()
	title.text = "Customers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.92, 0.72, 0.22))
	page.add_child(title)

	# perfected / met / total — sits directly under the title like a
	# second row of it.
	var header := Label.new()
	header.name = "NpcHeader"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	page.add_child(header)

	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.add_theme_font_size_override("normal_font_size", 15)
	desc.add_theme_color_override("default_color", Color(0.60, 0.60, 0.66))
	var tip_parts: Array[String] = []
	for rarity in ["common", "community", "rare", "elite"]:
		var col: Color = NpcRoster.RARITY_NAME_COLORS[rarity]
		tip_parts.append(
			"[color=#%s]%s +%d%%[/color]"
			% [col.to_html(false), rarity, int(NpcRoster.RARITY_TIP_PCT[rarity] * 100.0)],
		)
	desc.text = "[center]Serve a customer 10 perfect cups and they" \
			+ " leave a tip on every sale:  %s[/center]" % " · ".join(tip_parts)
	page.add_child(desc)

	# Four columns: common | community | rare | elite.
	# Scrollbars are hidden — mouse wheel still scrolls, a floating ▼
	# indicator shows when more rows exist below, and nothing overlaps
	# the cards.
	var cols := HBoxContainer.new()
	cols.name = "NpcColumns"
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	page.add_child(cols)
	var col_names := ["common", "community", "rare", "elite"]
	for i in col_names.size():
		var col_name: String = col_names[i]
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll_" + col_name
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		cols.add_child(scroll)
		_add_scroll_indicator(scroll)
		var col := VBoxContainer.new()
		col.name = "Col_" + col_name
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		scroll.add_child(col)
		if i < col_names.size() - 1:
			var sep := VSeparator.new()
			sep.modulate = Color(1, 1, 1, 0.25)
			cols.add_child(sep)


## Wraps a ScrollContainer in a VBox that shows a small "▼" row centered
## just under the list whenever more content exists below the visible
## area. Used where scrollbars are hidden (SCROLL_MODE_SHOW_NEVER).
func _add_scroll_indicator(scroll: ScrollContainer) -> void:
	var parent := scroll.get_parent()
	if parent == null:
		return
	var wrap := VBoxContainer.new()
	wrap.name = "ScrollWrap_" + scroll.name
	wrap.size_flags_horizontal = scroll.size_flags_horizontal
	wrap.size_flags_vertical = scroll.size_flags_vertical
	wrap.size_flags_stretch_ratio = scroll.size_flags_stretch_ratio
	wrap.custom_minimum_size = scroll.custom_minimum_size
	wrap.add_theme_constant_override("separation", 0)
	var idx := scroll.get_index()
	parent.add_child(wrap)
	parent.move_child(wrap, idx)
	scroll.reparent(wrap)
	scroll.custom_minimum_size = Vector2.ZERO

	var arrow := Label.new()
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.visible = false
	wrap.add_child(arrow)

	var bar := scroll.get_v_scroll_bar()
	var update := func(_v := 0.0) -> void:
		if not is_instance_valid(bar) or not is_instance_valid(arrow):
			return
		var scrollable := bar.max_value - bar.page
		arrow.visible = (bar.page > 1.0 and scrollable > 4.0 and bar.value < scrollable - 4.0)
	bar.value_changed.connect(
		func(_v):
			update.call(),
	)
	bar.changed.connect(
		func():
			update.call(),
	)
	# Lists populate/empty after this runs — re-check whenever content
	# changes or the view resizes, not just on scrollbar signals.
	scroll.child_entered_tree.connect(
		func(_c):
			update.call_deferred(),
	)
	scroll.child_exiting_tree.connect(
		func(_c):
			update.call(),
	)
	scroll.resized.connect(
		func():
			update.call(),
	)
	wrap.resized.connect(
		func():
			update.call(),
	)
	# Empty/short lists never trigger scrollbar changes — evaluate once
	# after layout so the arrow doesn't linger on them.
	update.call_deferred()
	update.call()


## Fills the NPCs tab with every roster NPC the local stand has met.
## Rows: rarity-colored name, rarity tag, affinity bar (0–100).
func _populate_npc_page() -> void:
	var page := $RootVBox/MainHBox/Panel/VBox/Content.get_node_or_null("NpcsPage")
	if page == null:
		return
	var header := page.get_node("NpcHeader") as Label
	if header == null:
		return
	var stand := _get_local_stand() as StandUnit
	var collection: Dictionary = (stand.get_npc_collection() if stand != null else { })
	var perfected := 0
	for k in collection:
		if float((collection[k] as Dictionary).get("affinity", 0.0)) >= 10.0:
			perfected += 1
	header.text = "%d / %d / %d" % [perfected, collection.size(), NpcRoster.size()]
	# Refresh live if the collection changes while the tab is open.
	if stand != null and not stand.npc_collection_changed.is_connected(_on_npc_collection_changed):
		stand.npc_collection_changed.connect(_on_npc_collection_changed)

	var col_common := _npc_column("common")
	var col_community := _npc_column("community")
	var col_rare := _npc_column("rare")
	var col_elite := _npc_column("elite")
	if col_common == null or col_community == null or col_rare == null or col_elite == null:
		return
	for col in [col_common, col_community, col_rare, col_elite]:
		for c in col.get_children():
			c.queue_free()

	# Group the whole roster by rarity, alphabetical inside each column.
	# Unmet slots render as dimmed "???" so the tab doubles as a checklist.
	var by_rarity := { "common": [], "community": [], "rare": [], "elite": [] }
	for i in NpcRoster.size():
		var entry := NpcRoster.get_entry(i)
		var rarity := str(entry.get("rarity", "common"))
		if by_rarity.has(rarity):
			by_rarity[rarity].append(i)
	for rarity in by_rarity:
		by_rarity[rarity].sort_custom(
			func(a, b):
				# Met customers float to the top in the order they were
				# first met; unmet slots stay alphabetical below them.
				var ea: Dictionary = collection.get(a, collection.get(str(a), { }))
				var eb: Dictionary = collection.get(b, collection.get(str(b), { }))
				# Met entries sort by discovery order (0 = first met);
				# unmet get -1. Met entries from older saves lack "order"
				# — they keep a large sentinel so they still float to the
				# top, just after the properly-ordered ones.
				var oa: int = ea.get("order", 1000000) if not ea.is_empty() else -1
				var ob: int = eb.get("order", 1000000) if not eb.is_empty() else -1
				if (oa >= 0) != (ob >= 0):
					return oa >= 0
				if oa != ob:
					return oa < ob
				return str(NpcRoster.get_entry(a).get("name", "")) \
						< str(NpcRoster.get_entry(b).get("name", "")),
		)

	_npc_fill_column(col_common, "Common", by_rarity["common"], collection)
	_npc_fill_column(col_community, "Community", by_rarity["community"], collection)
	_npc_fill_column(col_rare, "Rare", by_rarity["rare"], collection)
	_npc_fill_column(col_elite, "Elite", by_rarity["elite"], collection)


func _npc_column(col_name: String) -> VBoxContainer:
	var page := $RootVBox/MainHBox/Panel/VBox/Content.get_node_or_null("NpcsPage")
	if page == null:
		return null
	return page.find_child("Col_" + col_name, true, false) as VBoxContainer


func _npc_fill_column(
	col: VBoxContainer,
	title: String,
	ids: Array,
	collection: Dictionary,
) -> void:
	if ids.is_empty():
		return
	var rarity_key := title.to_lower()
	var met_count := 0
	for raw_id in ids:
		if collection.has(int(raw_id)) or collection.has(str(raw_id)):
			met_count += 1
	var header := Label.new()
	header.text = "%s  ·  %d/%d" % [title, met_count, ids.size()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override(
		"font_color",
		NpcRoster.RARITY_NAME_COLORS.get(rarity_key, Color(0.65, 0.58, 0.48)),
	)
	col.add_child(header)
	for raw_id in ids:
		var id := int(raw_id)
		var entry := NpcRoster.get_entry(id)
		var met := collection.has(id) or collection.has(str(id))
		var cups := 0
		if met:
			cups = int((collection.get(id, collection.get(str(id), { }))).get("affinity", 0.0))
		col.add_child(_make_npc_card(entry, met, cups))


## One NPC collection card: name (or "Unknown") in its rarity color +
## a row of 10 chunk pips that fill yellow per perfect cup served.
func _make_npc_card(entry: Dictionary, met: bool, cups: int) -> PanelContainer:
	var card := PanelContainer.new()
	# Same card chrome as the shop item cards.
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.11, 0.14)
	st.border_color = Color(0.20, 0.22, 0.27)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", st)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var rarity := str(entry.get("rarity", "common"))
	var name_lbl := Label.new()
	var npc_name := str(entry.get("name", ""))
	name_lbl.text = npc_name
	name_lbl.clip_text = true
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Shrink long names so they fit inside the card on a single line.
	var name_size := 18
	if npc_name.length() > 28:
		name_size = 12
	elif npc_name.length() > 20:
		name_size = 15
	name_lbl.add_theme_font_size_override("font_size", name_size)
	name_lbl.add_theme_color_override(
		"font_color",
		(NpcRoster.RARITY_NAME_COLORS.get(rarity, Color.WHITE)
			if met
			else Color(0.45, 0.45, 0.50)),
	)
	vbox.add_child(name_lbl)

	# 10 chunk pips — grey until earned, yellow per perfect cup.
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 3)
	for i in 10:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(15, 15)
		var pip_st := StyleBoxFlat.new()
		pip_st.bg_color = Color(0.88, 0.65, 0.12) if i < cups \
				else Color(0.16, 0.17, 0.21)
		pip_st.set_corner_radius_all(3)
		pip.add_theme_stylebox_override("panel", pip_st)
		pips.add_child(pip)
	vbox.add_child(pips)
	return card


func _on_npc_collection_changed(_collection: Dictionary) -> void:
	if _active_tab == "npcs":
		_populate_npc_page()


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


func _on_tab_unhover(_step_pc: PanelContainer, tab: String) -> void:
	if tab == _active_tab:
		return
	_update_flow_indicator()


## True when the demo should block upgrades — release builds without the
## `--dev` flag. Editor/debug runs and `--dev` launches keep them open.
func _demo_upgrades_blocked() -> bool:
	return (
		DEMO_DISABLE_UPGRADES and not (OS.is_debug_build() or "--dev" in OS.get_cmdline_user_args())
	)


## Demo overlay over the Upgrades page: semi-transparent so the tree stays
## visible, but blocks all mouse interaction and purchasing.
func _build_demo_upgrades_overlay() -> void:
	var content := $RootVBox/MainHBox/Panel/VBox/Content as MarginContainer
	if content == null:
		return
	_demo_upgrades_overlay = Control.new()
	_demo_upgrades_overlay.name = "DemoUpgradesOverlay"
	_demo_upgrades_overlay.visible = false
	_demo_upgrades_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_demo_upgrades_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(_demo_upgrades_overlay)

	var tint := ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.05, 0.05, 0.08, 0.90)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	_demo_upgrades_overlay.add_child(tint)

	var label := Label.new()
	label.text = "Not Available in Demo"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_demo_upgrades_overlay.add_child(label)


func _build_prices_page() -> void:
	var prices_page := ($RootVBox/MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var container := prices_page.find_child("PriceList", true, false) as VBoxContainer
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	for ft in GameState.FRUIT_TYPES:
		if not _is_local_fruit_unlocked(ft):
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
	var prices_page := ($RootVBox/MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var temp_info := prices_page.get_node_or_null("WeatherRow/TempInfo") as Label
	if temp_info:
		temp_info.text = "Temperature: %.0fC  |  1 ice per full 10C / 18F" % GameState.temperature
	var pop_info := prices_page.get_node_or_null("WeatherRow/PopInfo") as Label
	if pop_info:
		pop_info.text = "Popularity: %.0f%%" % (GameState.popularity / 10.0)


## Populate the Stand tab's left column with all-time stats, mirroring the
## daily mail report's layout (People / Money sections).
## Populate the Stats tab: two columns — People (left) and Money (right).
func _refresh_analytics() -> void:
	var cols_node := get_node_or_null("RootVBox/MainHBox/Panel/VBox/Content/AnalyticsPage/Columns")
	var people_col := (
		cols_node.find_child("PeopleCol", true, false) as VBoxContainer
		if cols_node != null
		else null
	)
	var money_col := (
		cols_node.find_child("MoneyCol", true, false) as VBoxContainer
		if cols_node != null
		else null
	)
	if people_col == null or money_col == null:
		return
	for col: VBoxContainer in [people_col, money_col]:
		while col.get_child_count() > 0:
			var c := col.get_child(0)
			col.remove_child(c)
			c.queue_free()

	var stand := _get_local_stand()
	var stats: Dictionary = stand.lifetime_stats if stand else { }
	var days: int = int(stats.get("days_completed", 0))

	_add_stat_section(people_col, "People")
	if days == 0:
		var none := Label.new()
		none.text = "Finish your first day to see stats."
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
		people_col.add_child(none)
	else:
		_add_stat_row(people_col, "Total Pedestrians", "%d" % int(stats.get("pedestrians", 0)))
		_add_stat_row(people_col, "Came to Buy", "%d" % int(stats.get("customers_arrived", 0)))
		_add_stat_row(people_col, "Bought", "%d" % int(stats.get("customers_bought", 0)))
		_add_stat_row(people_col, "Happy", "%d" % int(stats.get("happy", 0)), Color(0.4, 0.85, 0.4))
		var soft_red := Color(0.9, 0.55, 0.55)
		_add_stat_row(
			people_col,
			"Fruit Complaints",
			"%d" % int(stats.get("complaints_fruit", 0)),
			soft_red,
		)
		_add_stat_row(
			people_col,
			"Sugar Complaints",
			"%d" % int(stats.get("complaints_sugar", 0)),
			soft_red,
		)
		_add_stat_row(
			people_col,
			"Ice Complaints",
			"%d" % int(stats.get("complaints_ice", 0)),
			soft_red,
		)
		_add_stat_row(
			people_col,
			"Patience Ran Out",
			"%d" % int(stats.get("timeouts", 0)),
			soft_red,
		)
		_add_stat_row(
			people_col,
			"Too Expensive",
			"%d" % int(stats.get("too_expensive", 0)),
			soft_red,
		)
		_add_stat_row(people_col, "Wrong Order", "%d" % int(stats.get("wrong_order", 0)), soft_red)
		_add_stat_row(people_col, "Scammed", "%d" % int(stats.get("scams", 0)), soft_red)

	_add_stat_section(money_col, "Money")
	if days > 0:
		_add_stat_row(
			money_col,
			"Income",
			"$%.2f" % float(stats.get("income", 0.0)),
			Color(0.4, 0.85, 0.4),
		)
		_add_stat_row(money_col, "Sales", "$%.2f" % float(stats.get("sales", 0.0)))
		_add_stat_row(money_col, "Recycling", "$%.2f" % float(stats.get("recycling", 0.0)))
		_add_stat_row(money_col, "Trash", "$%.2f" % float(stats.get("trash", 0.0)))
		_add_stat_row(
			money_col,
			"Costs",
			"-$%.2f" % float(stats.get("costs", 0.0)),
			Color(0.9, 0.45, 0.45),
		)
		var profit := float(stats.get("profit", 0.0))
		_add_stat_row(
			money_col,
			"Profit",
			"%s$%.2f" % ["+" if profit >= 0.0 else "-", absf(profit)],
			Color(0.4, 0.85, 0.4) if profit >= 0.0 else Color(0.9, 0.3, 0.3),
		)
		var highest_money: float = stand.highest_money if stand else GameState.highest_money
		# Primary-stand sales are routed to GameState, so its highest_purchase
		# lives there; other stands track their own.
		var highest_purchase: float = GameState.highest_purchase
		if stand != null and not stand.is_legacy_primary:
			highest_purchase = stand.highest_purchase
		_add_stat_row(money_col, "Highest Balance", "$%.2f" % highest_money)
		_add_stat_row(money_col, "Highest Purchase", "$%.2f" % highest_purchase)


func _add_stat_section(parent: VBoxContainer, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	parent.add_child(lbl)


func _add_stat_row(
	parent: VBoxContainer,
	label: String,
	value: String,
	color: Color = Color(0.75, 0.72, 0.66),
) -> void:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66))
	row.add_child(name_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 22)
	val_lbl.add_theme_color_override("font_color", color)
	row.add_child(val_lbl)
	parent.add_child(row)


func _refresh_upgrades() -> void:
	var stand := _get_local_stand() as StandUnit
	for branch_id in _upgrade_columns:
		_upgrade_columns[branch_id].refresh(stand)


func _build_upgrades_page() -> void:
	var tree_ctrl := ($RootVBox/MainHBox/Panel/VBox/Content/UpgradesPage/UpgradeTree as Control)
	if tree_ctrl == null:
		return
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 14)
	tree_ctrl.add_child(hbox)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var branches := UpgradeManager.get_branches()
	for i in range(branches.size()):
		if i > 0:
			# Full-height divider between columns.
			var sep := VSeparator.new()
			sep.modulate = Color(1, 1, 1, 0.25)
			hbox.add_child(sep)
		var col := UpgradeBarColumnScript.new()
		col.setup(branches[i])
		hbox.add_child(col)
		_upgrade_columns[str(branches[i]["id"])] = col
	_refresh_upgrades()


func _add_to_cart(item: Dictionary) -> void:
	_cart.append(item)
	_update_cart_ui()
	_animate_status_text("Added to cart!")


## Negotiation discount for the local player's stand — applied to every
## shop price shown or charged through this hub.
func _negotiated_cost(base: float) -> float:
	var neg := clampf(UpgradeManager.get_effect_total("negotiation"), 0.0, 0.9)
	return base * (1.0 - neg)


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
		total += _negotiated_cost(item["cost"])
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
		price_lbl.text = "$%.2f" % _negotiated_cost(item["cost"])
		price_lbl.add_theme_font_size_override("font_size", 16)
		price_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.45))
		row.add_child(price_lbl)
		var rem_btn := Button.new()
		rem_btn.text = "X"
		rem_btn.custom_minimum_size = Vector2(44, 40)
		rem_btn.add_theme_font_size_override("font_size", 20)
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
	_checkout_btn.disabled = not has_items or _get_local_money() < total
	if not has_items:
		var empty := Label.new()
		empty.text = "Cart is empty"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cart_list.add_child(empty)


func _checkout_cart() -> void:
	if _shop_closed():
		_status_lbl.text = "Shop is closed for today"
		_animate_status(true)
		return
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
				_buy_container(id, _negotiated_cost(item["cost"]))
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
	# Deliveries close at 6 PM — drop late checkouts so a client can't
	# trigger the truck after closing.
	if DayManager.day_time_over:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	GameLog.log("[MorningHub] Host received checkout from %d (stand=%s)" % [sender_id, stand_name])
	EventBus.checkout_completed.emit(stand_name)


func _is_ingredient(item: Dictionary) -> bool:
	return item in shop_items


func _animate_status_text(msg: String, error := false) -> void:
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override(
		"font_color",
		Color(0.95, 0.4, 0.35) if error else Color(0.4, 0.85, 0.4),
	)
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(1.5)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _on_fruit_research_changed(_id: int, _cost: float) -> void:
	if visible:
		_build_shop()
		_refresh_upgrades()


func _on_stand_progress_changed(_stand: StandUnit, _progress: Dictionary) -> void:
	if visible:
		_refresh_upgrades()
		# Claims land here too — keep the shop's lock state fresh while
		# it's the tab being viewed.
		if _active_tab == "shop":
			_build_shop()


func _buy_ingredient(item: Dictionary, qty: int = 1) -> void:
	if item["id"] in GameState.FRUIT_TYPES and not _is_local_fruit_unlocked(item["id"]):
		return
	if _shop_closed():
		_status_lbl.text = "Shop is closed for today"
		_animate_status(true)
		return
	var total: float = qty * _negotiated_cost(item["cost"])
	# Route purchases through the host. Clients send an RPC; the host
	# validates money and emits the signal that triggers delivery.
	if WorldSync.is_host():
		if not WorldSync.spend_local_money(total, "supplies"):
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
	if _shop_closed():
		_status_lbl.text = "Shop is closed for today"
		_animate_status(true)
		return
	if not UpgradeManager.is_item_unlocked(container_type, _get_local_stand()):
		_status_lbl.text = "Locked — check the Upgrades page"
		_animate_status(true)
		return
	if WorldSync.is_host():
		if not WorldSync.spend_local_money(cost):
			_status_lbl.text = "Not enough money!"
			_animate_status(true)
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
	_status_lbl.text = "%s ordered!" % HeldItem.container_name(container_type)
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
	# Host-side validation: the shop closes at 6 PM. Reject any purchase
	# request that arrives after closing, even if the client's UI was open.
	if DayManager.day_time_over:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	GameLog.log(
		"[MorningHub] Host received purchase from %d: %s/%s (stand=%s)"
		% [sender_id, category, item_id, stand_name]
	)
	# Find the requesting player's stand by name and spend from it
	var stand := _find_stand_by_name(stand_name)
	if stand == null:
		return
	var authorized := false
	for player in get_tree().get_nodes_in_group("player"):
		if (
			player.get_multiplayer_authority() == sender_id
			and player.get("assigned_stand") == stand
		):
			authorized = true
			break
	if not authorized:
		return
	match category:
		"supply":
			if qty < 1.0 or qty != floorf(qty) or qty > 100.0:
				return
			if item_id in GameState.FRUIT_TYPES and not stand.is_fruit_unlocked(item_id):
				return
			# Find the item to get its per-box quantity
			var supply: Dictionary = { }
			for item in shop_items:
				if item.get("id", "") == item_id:
					supply = item
					break
			if supply.is_empty():
				return
			var box_cost: float = supply["cost"]
			var neg := clampf(
				UpgradeManager.get_effect_total_for_stand("negotiation", stand_name),
				0.0,
				0.9,
			)
			box_cost *= 1.0 - neg
			if not _spend_from_stand(stand, box_cost * qty, "supplies"):
				return
			for i in range(int(qty)):
				EventBus.supply_order_placed.emit(item_id, supply["qty"], box_cost, stand_name)
		"equipment":
			if not UpgradeManager.is_item_unlocked(item_id, stand):
				return
			var catalog_cost := -1.0
			for item in container_items:
				if item["id"] == item_id:
					catalog_cost = float(item["cost"])
					break
			var neg := clampf(
				UpgradeManager.get_effect_total_for_stand("negotiation", stand_name),
				0.0,
				0.9,
			)
			var expected := catalog_cost * (1.0 - neg)
			if catalog_cost < 0.0 or not is_equal_approx(cost, expected):
				return
			if not _spend_from_stand(stand, expected):
				return
			EventBus.equipment_order_placed.emit(item_id, stand_name)


func _find_stand_by_name(stand_name: String) -> Node:
	if stand_name == "":
		return WorldSync.get_local_stand()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	for s in tree.current_scene.find_children("*", "StandUnit", true, false):
		if s.name == stand_name:
			return s
	return null


func _spend_from_stand(stand: Node, amount: float, category: String = "") -> bool:
	if stand != null and stand.has_method("spend_money"):
		return stand.spend_money(amount, category)
	return GameState.spend_money(amount)


func _animate_status(error := false) -> void:
	_status_lbl.add_theme_color_override(
		"font_color",
		Color(0.95, 0.4, 0.35) if error else Color(0.4, 0.85, 0.4),
	)
	var tween := create_tween()
	_status_lbl.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(_status_lbl, "modulate", Color(1, 1, 1, 0), 0.5)


func _on_price_changed(_fruit_type: String, new_price: float) -> void:
	var prices_page := ($RootVBox/MainHBox/Panel/VBox/Content/PricesPage as VBoxContainer)
	if prices_page == null:
		return
	var container := prices_page.find_child("PriceList", true, false) as VBoxContainer
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
	# Find the local player first, then use their assigned_stand. Skip the
	# authority check when no multiplayer peer exists — is_multiplayer_authority
	# would call get_unique_id() and error out during shutdown/menu teardown.
	if multiplayer.has_multiplayer_peer():
		for p in root.find_children("*", "Player", true, false):
			if p.is_multiplayer_authority():
				var stand: Node = p.get("assigned_stand")
				if stand != null and is_instance_valid(stand):
					return stand
	# Fallback: return the first StandUnit (single-player or unassigned).
	for s in root.find_children("*", "StandUnit", true, false):
		return s
	return null


## Get the local player's stand money, falling back to GameState.money.
func _get_local_money() -> float:
	var stand := _get_local_stand()
	if stand != null and is_instance_valid(stand) and "money" in stand:
		return stand.money
	return GameState.money


## Use the local stand's unlock set so a remote stand's research does not
## leak into this player's shop/recipe/price pages.
func _is_local_fruit_unlocked(fruit: String) -> bool:
	var stand := _get_local_stand()
	if stand != null and is_instance_valid(stand) and stand.has_method("is_fruit_unlocked"):
		return stand.is_fruit_unlocked(fruit)
	return UpgradeManager.is_fruit_unlocked(fruit)


func _on_day_phase_changed(phase: int, day: int) -> void:
	if phase == DayManager.Phase.MORNING:
		_update_morning_data(day)
	else:
		_hide_morning_hub()


func _update_morning_data(day: int) -> void:
	var day_lbl := get_node_or_null("RootVBox/MainHBox/Panel/VBox/Header/DayLabel") as Label
	if day_lbl:
		day_lbl.text = "Day %d" % day
	var temp_lbl := get_node_or_null("RootVBox/MainHBox/Panel/VBox/Header/TempLabel") as Label
	if temp_lbl:
		temp_lbl.text = "%.0fC" % GameState.temperature
	var money_lbl := get_node_or_null("RootVBox/MainHBox/Panel/VBox/Header/MoneyLabel") as Label
	if money_lbl:
		money_lbl.text = "Money: $%.2f" % _get_local_money()
	var price_slider := ($RootVBox/MainHBox/Panel/VBox/Content/PricesPage/PriceSlider as HSlider)
	if price_slider:
		pass


func _show_morning_hub() -> void:
	_update_morning_data(DayManager.day_number)
	_scan_stand_state()
	# Set the active stand for research so upgrades are per-stand.
	var stand := _get_local_stand()
	if stand:
		UpgradeManager.set_active_stand(stand.name)
	_bind_stand_money()
	# Re-evaluate cart affordability against current stand money — the
	# checkout button could be stale if money changed while the hub was
	# closed (_on_money_changed early-returns when the panel is hidden).
	_update_cart_ui()
	# Restore the last-used tab instead of always defaulting to analytics.
	if not _flow_tabs.has(_active_tab):
		_active_tab = "analytics"
	_show_tab(_active_tab)
	panel.visible = true
	backdrop.visible = true
	_flow_indicator.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(false)
	var tween := create_tween()
	panel.modulate = Color(1, 1, 1, 0)
	backdrop.modulate = Color(1, 1, 1, 0)
	_flow_indicator.modulate = Color(1, 1, 1, 0)
	if _right_panel:
		_right_panel.modulate = Color(1, 1, 1, 0)
	tween.tween_property(backdrop, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.parallel().tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.3)
	tween.parallel().tween_property(_flow_indicator, "modulate", Color(1, 1, 1, 1), 0.3)
	if _right_panel:
		tween.parallel().tween_property(_right_panel, "modulate", Color(1, 1, 1, 1), 0.3)


## The bottom-screen X button exits the computer view, same as ESC.
## The hub is a child of the computer's ScreenUI SubViewport, so the
## owning Computer node is two parents up.
func _on_exit_button_pressed() -> void:
	var computer := get_parent()
	while computer != null and not computer is Computer:
		computer = computer.get_parent()
	if computer != null:
		(computer as Computer).close_view()


## keep_on_screen: leave the hub drawn on the monitor (the SubViewport
## holds whatever was last rendered — the screen looks "left on").
## HUD is always restored either way.
func _hide_morning_hub(keep_on_screen := false) -> void:
	# Reset modulate so the next fade-in starts from fully opaque.
	panel.modulate = Color(1, 1, 1, 1)
	backdrop.modulate = Color(1, 1, 1, 1)
	_flow_indicator.modulate = Color(1, 1, 1, 1)
	if _right_panel:
		_right_panel.modulate = Color(1, 1, 1, 1)
	if not keep_on_screen:
		panel.visible = false
		backdrop.visible = false
		_flow_indicator.visible = false
		if _right_panel:
			_right_panel.visible = false
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(true)


## Live money updates come from the local stand's own money_changed signal.
## StandUnit mutations emit that per-stand signal, and on clients
## _apply_state() is the only place stand money changes — EventBus.
## money_changed only fires for the primary stand's GameState bridge,
## so relying on it alone leaves the PC display stale.
var _bound_stand: Node = null


func _bind_stand_money() -> void:
	var stand := _get_local_stand()
	if stand == _bound_stand:
		return
	if (
		_bound_stand != null and is_instance_valid(_bound_stand)
		and _bound_stand.has_signal("money_changed")
		and _bound_stand.money_changed.is_connected(_on_money_changed)
	):
		_bound_stand.money_changed.disconnect(_on_money_changed)
	_bound_stand = stand
	if _bound_stand != null and _bound_stand.has_signal("money_changed"):
		_bound_stand.money_changed.connect(_on_money_changed)


func _on_money_changed(_amount: float) -> void:
	_bind_stand_money()
	if not panel.visible:
		return
	var money_lbl := get_node_or_null("RootVBox/MainHBox/Panel/VBox/Header/MoneyLabel") as Label
	if money_lbl:
		money_lbl.text = "Money: $%.2f" % _get_local_money()
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


## Resolves which stand owns a node: its `stand_owner` if set, otherwise the
## nearest ancestor StandUnit. "" = unassigned/usable by anyone.
func _node_stand_name(node: Node) -> String:
	if node is Interactable and node.stand_owner != "":
		return node.stand_owner
	var n := node
	while n != null:
		if n is StandUnit:
			return n.name
		n = n.get_parent()
	return ""


func _scan_stand_state() -> void:
	_bin_amounts.clear()
	_equipment_counts.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	var stand := _get_local_stand()
	var stand_name: String = stand.name if stand != null else ""
	var belongs := func(node: Node) -> bool:
		var owner := _node_stand_name(node)
		return owner == "" or owner == stand_name
	for node in root.get_tree().get_nodes_in_group("container"):
		if not belongs.call(node) or not node.visible or node.is_in_group("ghost"):
			continue
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
			# Pitcher contents are mixed product, not raw stock — only fruit
			# counts here. Water comes from dispensers below so the number
			# reflects the dispenser's actual remaining fillings.
			if node.fruit_type != "" and node.fruit_count > 0.0:
				var prev: float = _bin_amounts.get(node.fruit_type, 0.0)
				_bin_amounts[node.fruit_type] = prev + node.fruit_count
	for node in root.get_tree().get_nodes_in_group("supply_box"):
		var box := node as SupplyBox
		if box == null or not belongs.call(box) or not box.visible:
			continue
		if box.is_equipment:
			var etype: String = box.equipment_type
			if etype != "":
				_equipment_counts[etype] = _equipment_counts.get(etype, 0) + 1
			continue
		var btype: String = box.ingredient_type
		_bin_amounts[btype] = _bin_amounts.get(btype, 0.0) + box.quantity
	for node in root.get_tree().get_nodes_in_group("water_dispenser"):
		var dispenser := node as WaterDispenser
		if dispenser != null and belongs.call(dispenser):
			_bin_amounts["water"] = (_bin_amounts.get("water", 0.0) + dispenser.water_fillings)
	for node in root.get_tree().get_nodes_in_group("container"):
		if not belongs.call(node) or not node.visible or node.is_in_group("ghost"):
			continue
		var ctype := SaveManager.get_container_type(node)
		if ctype != "" and ctype != "cup":
			_equipment_counts[ctype] = _equipment_counts.get(ctype, 0) + 1
	_refresh_stats()


func _refresh_stats() -> void:
	while _stats_vbox.get_child_count() > 0:
		var c := _stats_vbox.get_child(0)
		_stats_vbox.remove_child(c)
		c.queue_free()
	# Header row: Day left, Money centered, Temp right.
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_vbox.add_child(header)

	var day_lbl := Label.new()
	day_lbl.text = "Day: %d" % DayManager.day_number
	day_lbl.add_theme_font_size_override("font_size", 24)
	day_lbl.add_theme_color_override("font_color", Color(0.9, 0.87, 0.78))
	header.add_child(day_lbl)

	var money_lbl := Label.new()
	money_lbl.text = "$%.2f" % _get_local_money()
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_lbl.add_theme_font_size_override("font_size", 24)
	money_lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	header.add_child(money_lbl)

	var temp_c: float = GameState.temperature
	var temp_lbl := Label.new()
	temp_lbl.text = "%.0fC / %.0fF" % [temp_c, temp_c * 9.0 / 5.0 + 32.0]
	temp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	temp_lbl.add_theme_font_size_override("font_size", 24)
	temp_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	header.add_child(temp_lbl)

	var sep := HSeparator.new()
	_stats_vbox.add_child(sep)

	# Two columns: Equipment left, Consumables right.
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 8)
	_stats_vbox.add_child(cols)

	var equip_col := VBoxContainer.new()
	equip_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_col.add_theme_constant_override("separation", 2)
	cols.add_child(equip_col)
	var equip_hdr := Label.new()
	equip_hdr.text = "Equipment"
	equip_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_hdr.add_theme_font_size_override("font_size", 14)
	equip_hdr.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	equip_col.add_child(equip_hdr)
	if _equipment_counts.is_empty():
		equip_col.add_child(_stats_row("(none)", "", Color(0.5, 0.5, 0.48)))
	for etype in _equipment_counts:
		var cnt: int = _equipment_counts[etype]
		equip_col.add_child(
			_stats_row(_equipment_display_name(etype), "x%d" % cnt, Color(0.6, 0.58, 0.52))
		)

	var vsep := VSeparator.new()
	cols.add_child(vsep)

	var cons_col := VBoxContainer.new()
	cons_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cons_col.add_theme_constant_override("separation", 2)
	cols.add_child(cons_col)
	var cons_hdr := Label.new()
	cons_hdr.text = "Consumables"
	cons_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cons_hdr.add_theme_font_size_override("font_size", 14)
	cons_hdr.add_theme_color_override("font_color", Color(0.92, 0.78, 0.25))
	cons_col.add_child(cons_hdr)
	var shown_any := false
	for itype in _bin_amounts:
		var amt: float = _bin_amounts[itype]
		if amt <= 0.0:
			continue
		shown_any = true
		cons_col.add_child(_stats_row(itype.capitalize(), "%.0f" % amt, Color(0.6, 0.75, 0.88)))
	if not shown_any:
		cons_col.add_child(_stats_row("(none)", "", Color(0.5, 0.5, 0.48)))


## Row with the label left and the value right-aligned, so all values
## line up vertically down the column.
func _stats_row(label_text: String, value_text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", color)
	row.add_child(name_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value_text
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", color)
	row.add_child(val_lbl)
	return row


## Nicer equipment names: move trailing digits to the end so
## "ice_2_bin" reads "Ice Bin 2" instead of "Ice 2 Bin".
func _equipment_display_name(ctype: String) -> String:
	var digits := ""
	var base := ""
	for i in ctype.length():
		if ctype[i].is_valid_int():
			digits += ctype[i]
		else:
			base += ctype[i]
	while base.contains("__"):
		base = base.replace("__", "_")
	base = base.strip_edges().trim_prefix("_").trim_suffix("_")
	var name := HeldItem.container_name(base)
	return "%s %s" % [name, digits] if digits != "" else name


func _on_dev_reset() -> void:
	SaveManager.delete_save()
	GameState.money = Balancing.STARTING_MONEY
	GameState.popularity = Balancing.STARTING_POPULARITY
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
	var recipes_page := $RootVBox/MainHBox/Panel/VBox/Content/RecipesPage as VBoxContainer
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
		"raspberry": Color(0.92, 0.15, 0.40, 1),
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
		var stand := _get_local_stand()
		var c_val: float = (
			stand.ice_degrees_per_scoop if stand != null else GameState.ice_degrees_per_scoop
		)
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
			var stand := _get_local_stand()
			if stand != null:
				stand.request_set_ice_degrees(c_val)
			else:
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
		var locked := not _is_local_fruit_unlocked(ft)
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
	btn.custom_minimum_size = Vector2(52, 40)
	btn.add_theme_font_size_override("font_size", 18)
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


func _on_dev_meet_all_npcs() -> void:
	var stand := _get_local_stand() as StandUnit
	if stand != null:
		stand.request_meet_all_npcs()
