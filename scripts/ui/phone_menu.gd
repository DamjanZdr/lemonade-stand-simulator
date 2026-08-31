extends CanvasLayer
## Phone menu: supply ordering. Toggle with Tab.

var _visible_panel: bool = false

@onready var panel: PanelContainer = $Panel
@onready var order_buttons: VBoxContainer = $Panel/VBox/Orders


func _ready() -> void:
	panel.visible = false
	_build_order_buttons()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"): # Tab key — toggle before UI focus moves
		if DayManager.current_phase != DayManager.Phase.DAY:
			EventBus.interaction_hint_changed.emit(
				"Shop closed — use the morning supply menu before the day starts",
			)
			get_viewport().set_input_as_handled()
			return
		_visible_panel = !_visible_panel
		panel.visible = _visible_panel
		# Set the active stand for research so upgrades are per-stand.
		if _visible_panel:
			var sn := WorldSync.get_local_stand_name()
			if sn != "":
				UpgradeManager.set_active_stand(sn)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _visible_panel \
				else Input.MOUSE_MODE_CAPTURED
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("set_hud_visible"):
			hud.set_hud_visible(not _visible_panel)
		get_viewport().set_input_as_handled()


func _build_order_buttons() -> void:
	# --- Supplies ---
	var supply_header := Label.new()
	supply_header.text = "── Supplies ──"
	supply_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_buttons.add_child(supply_header)
	var types := ["lemon", "water", "sugar", "ice", "cups"]
	for itype in types:
		var btn := Button.new()
		var qty := _get_delivery_quantity()
		var cost := _get_delivery_cost(qty)
		btn.text = "Order %s  ($%.0f)" % [itype.capitalize(), cost]
		btn.pressed.connect(
			func():
				_order(itype),
		)
		order_buttons.add_child(btn)

	# --- Containers ---
	var sep1 := HSeparator.new()
	order_buttons.add_child(sep1)
	var container_header := Label.new()
	container_header.text = "── Equipment ──"
	container_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_buttons.add_child(container_header)
	var containers := [
		["fruit_bin", "Fruit Bin", Balancing.CONTAINER_COST_FRUIT_BIN],
		["sugar_bin", "Sugar Bin", Balancing.CONTAINER_COST_SUGAR_BIN],
		["ice_bin", "Ice Plate", Balancing.CONTAINER_COST_ICE_BIN],
		["pitcher", "Pitcher", Balancing.CONTAINER_COST_PITCHER],
		["press", "Fruit Press", Balancing.CONTAINER_COST_PRESS],
		["workstation", "Table", Balancing.CONTAINER_COST_WORKSTATION],
	]
	var negotiation: float = clampf(UpgradeManager.get_effect_total("negotiation"), 0.0, 0.9)
	for entry in containers:
		var ctype: String = entry[0]
		var label: String = entry[1]
		var cost: float = entry[2] * (1.0 - negotiation)
		var btn := Button.new()
		btn.text = "Buy %s  ($%.0f)" % [label, cost]
		btn.pressed.connect(
			func():
				_buy_container(ctype, cost),
		)
		order_buttons.add_child(btn)

	# --- Upgrades ---
	var sep2 := HSeparator.new()
	order_buttons.add_child(sep2)
	var upgrade_header := Label.new()
	upgrade_header.text = "── Upgrades ──"
	upgrade_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_buttons.add_child(upgrade_header)
	for cat in UpgradeManager.get_categories():
		var cat_label := Label.new()
		cat_label.text = "  " + cat.capitalize()
		cat_label.add_theme_font_size_override("font_size", 14)
		order_buttons.add_child(cat_label)
		for id in UpgradeManager.get_upgrades_in_category(cat):
			var data := UpgradeManager.get_upgrade_data(id)
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var name_lbl := Label.new()
			name_lbl.text = "%s  (Lv %d/%d)" % [
				data.get("name", "???"),
				data.get("level", 0),
				data.get("max_level", 1),
			]
			name_lbl.add_theme_font_size_override("font_size", 14)
			info.add_child(name_lbl)

			var desc := Label.new()
			desc.text = data.get("description", "")
			desc.add_theme_font_size_override("font_size", 11)
			desc.modulate = Color(0.8, 0.8, 0.8)
			info.add_child(desc)
			row.add_child(info)

			var btn := Button.new()
			var maxed: bool = data.get("maxed", false)
			if maxed:
				btn.text = "Maxed"
				btn.disabled = true
			else:
				var cost: float = data.get("cost", 0.0)
				btn.text = "$%.0f" % cost
				btn.disabled = not UpgradeManager.can_afford(id)
				btn.pressed.connect(
					func():
						_buy_upgrade(id, btn, name_lbl),
				)
			row.add_child(btn)
			order_buttons.add_child(row)


func _get_delivery_quantity() -> float:
	var bonus: float = UpgradeManager.get_effect_total("larger_crates")
	return Balancing.DELIVERY_QUANTITY + bonus


func _get_delivery_cost(qty: float) -> float:
	var bulk: float = UpgradeManager.get_effect_total("bulk_buy")
	var haggle: float = UpgradeManager.get_effect_total("negotiation")
	var discount: float = clampf(bulk + haggle, 0.0, 0.9)
	return Balancing.DELIVERY_COST_PER_UNIT * qty * (1.0 - discount)


func _order(itype: String) -> void:
	var qty := _get_delivery_quantity()
	var cost := _get_delivery_cost(qty)
	# Route purchases through the host. The host spends the money and
	# emits the supply_order_placed signal locally, which triggers the
	# delivery system. Clients send an RPC to the host instead.
	var sn := WorldSync.get_local_stand_name()
	if WorldSync.is_host():
		if not WorldSync.spend_local_money(cost):
			EventBus.interaction_hint_changed.emit("Not enough money!")
			return
		EventBus.supply_order_placed.emit(itype, qty, cost, sn)
		EventBus.checkout_completed.emit(sn)
	else:
		_request_purchase.rpc_id(1, "supply", itype, qty, cost, sn)


func _buy_container(container_type: String, cost: float) -> void:
	var sn := WorldSync.get_local_stand_name()
	if WorldSync.is_host():
		if not WorldSync.spend_local_money(cost):
			EventBus.interaction_hint_changed.emit("Not enough money!")
			return
		EventBus.equipment_order_placed.emit(container_type, sn)
	else:
		_request_purchase.rpc_id(1, "equipment", container_type, 0.0, cost, sn)


func _buy_upgrade(id: String, btn: Button, name_lbl: Label) -> void:
	if WorldSync.is_host():
		# Ensure the host's own stand is active before purchasing.
		var sn := WorldSync.get_local_stand_name()
		print("[PhoneMenu] _buy_upgrade: id=%s stand_name=%s" % [id, sn])
		if sn != "":
			UpgradeManager.set_active_stand(sn)
		if UpgradeManager.purchase(id):
			EventBus.interaction_hint_changed.emit("Upgrade purchased!")
			var data := UpgradeManager.get_upgrade_data(id)
			name_lbl.text = "%s  (Lv %d/%d)" % [
				data.get("name", "???"),
				data.get("level", 0),
				data.get("max_level", 1),
			]
			if data.get("maxed", false):
				btn.text = "Maxed"
				btn.disabled = true
			else:
				btn.text = "$%.0f" % data.get("cost", 0.0)
				btn.disabled = not UpgradeManager.can_afford(id)
			# Notify all clients so joiners update their upgrade UI.
			_sync_upgrade_purchased.rpc(id, sn)
		else:
			EventBus.interaction_hint_changed.emit("Not enough money!")
	else:
		var sn2 := WorldSync.get_local_stand_name()
		_request_purchase.rpc_id(1, "upgrade", id, 0.0, 0.0, sn2)


## RPC sent by clients to the host to request a purchase.
## The host validates money and emits the appropriate EventBus signal.
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
		"[PhoneMenu] Host received purchase request from %d: %s/%s (stand=%s)"
		% [sender_id, category, item_id, stand_name]
	)
	# Find the requesting player's stand by name and spend from it
	var stand := _find_stand_by_name(stand_name)
	match category:
		"supply":
			if not _spend_from_stand(stand, cost):
				return
			EventBus.supply_order_placed.emit(item_id, qty, cost, stand_name)
			EventBus.checkout_completed.emit(stand_name)
		"equipment":
			if not _spend_from_stand(stand, cost):
				return
			EventBus.equipment_order_placed.emit(item_id, stand_name)
		"upgrade":
			# Set the buyer's stand active so the purchase is recorded
			# against their stand and money is spent from their stand.
			if stand_name != "":
				UpgradeManager.set_active_stand(stand_name)
			if UpgradeManager.purchase(item_id):
				GameLog.log(
					"[PhoneMenu] Host purchased upgrade %s for peer %d (stand=%s)"
					% [item_id, sender_id, stand_name]
				)
				# Notify all clients so joiners update their upgrade UI.
				_sync_upgrade_purchased.rpc(item_id, stand_name)


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


func _spend_from_stand(stand: Node, amount: float) -> bool:
	if stand != null and stand.has_method("spend_money"):
		return stand.spend_money(amount)
	return GameState.spend_money(amount)


## Sync upgrade purchases to all clients so joiners update their UI.
## The host calls this after a successful upgrade purchase.
@rpc("authority", "call_local", "reliable")
func _sync_upgrade_purchased(upgrade_id: String, stand_name: String) -> void:
	# Only apply to clients whose stand matches (or all if stand_name is empty).
	var local_sn := WorldSync.get_local_stand_name()
	if stand_name != "" and local_sn != stand_name:
		return
	# Set the active stand and apply the purchase locally on clients.
	UpgradeManager.set_active_stand(stand_name)
	# Re-apply effects so fruit unlocks and other effects take effect.
	UpgradeManager.apply_all_effects()
	# Refresh the upgrade UI if it's open.
	EventBus.upgrade_purchased.emit(0, 0.0)
