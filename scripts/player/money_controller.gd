class_name MoneyController
extends Node3D

## Manages the 3D money denominations attached to the player's camera.
## Activated when a customer pays (sale_initiated). Releases the mouse
## so the player can click bills and coins to make change.

var _active: bool = false
var _payment_cents: int = 0
var _change_due_cents: int = 0
var _tendered_cents: int = 0

var _camera: Camera3D = null
var _player: Node = null
var _hovered: MoneyDenomination = null

## Local position when fully shown (captured from the scene at startup).
var _rest_position: Vector3 = Vector3.ZERO
## How far below the resting position the tray starts/ends while hidden.
@export var slide_distance: float = 0.6
@export var slide_up_duration: float = 0.3
@export var slide_down_duration: float = 0.25
var _slide_tween: Tween = null


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_warning("MoneyController: parent is not a Camera3D")
		return

	# Draw the money on top of everything (counter, cups, NPCs, etc.) like a
	# classic FPS viewmodel so it never gets clipped by nearby world geometry.
	_disable_depth_test_recursive(self)

	_rest_position = position
	visible = false
	_set_areas_enabled(false)
	EventBus.sale_initiated.connect(_on_sale_initiated)
	EventBus.change_finalized.connect(_on_change_finalized)
	EventBus.customer_left.connect(_on_customer_left)


func _hidden_position() -> Vector3:
	return _rest_position - Vector3(0.0, slide_distance, 0.0)


func _set_areas_enabled(enabled: bool) -> void:
	# Area3D colliders keep colliding even while the node is hidden, which
	# would let the player's normal aim raycast pick up the money by mistake.
	for area in _collect_areas(self):
		area.collision_layer = 1 if enabled else 0


func _collect_areas(node: Node) -> Array[Area3D]:
	var result: Array[Area3D] = []
	if node is Area3D:
		result.append(node as Area3D)
	for child in node.get_children():
		result.append_array(_collect_areas(child))
	return result


func _disable_depth_test_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(i)
				if mat == null:
					mat = mi.mesh.surface_get_material(i)
				if mat == null:
					continue
				var dup := mat.duplicate() as Material
				if dup is BaseMaterial3D:
					(dup as BaseMaterial3D).no_depth_test = true
				dup.render_priority = 100
				mi.set_surface_override_material(i, dup)
	elif node is Label3D:
		# Higher render_priority than the bill/coin meshes above so the
		# denomination text draws on top instead of being hidden behind them.
		var lbl := node as Label3D
		lbl.no_depth_test = true
		lbl.render_priority = 101
	for child in node.get_children():
		_disable_depth_test_recursive(child)


func _on_sale_initiated(payment: float, change_due: float) -> void:
	_payment_cents = roundi(payment * 100.0)
	_change_due_cents = roundi(change_due * 100.0)
	_tendered_cents = 0
	_active = true
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	position = _hidden_position()
	visible = true
	_set_areas_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _player == null:
		_player = WorldSync.get_local_player()
	if _player and _player.has_method("set_money_mode"):
		_player.set_money_mode(true)
	EventBus.change_tendered_updated.emit(_tendered_cents, _change_due_cents)
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_slide_tween.tween_property(self, "position", _rest_position, slide_up_duration)


func _on_change_finalized(_earned: float) -> void:
	_deactivate()


func _on_customer_left(_customer: Node, _outcome: String) -> void:
	if _active:
		_deactivate()


func _deactivate() -> void:
	_active = false
	_set_areas_enabled(false)
	if _hovered and is_instance_valid(_hovered):
		_hovered.set_highlight(false)
	_hovered = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _player and _player.has_method("set_money_mode"):
		_player.set_money_mode(false)

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_slide_tween.tween_property(self, "position", _hidden_position(), slide_down_duration)
	_slide_tween.tween_callback(
		func():
			visible = false,
	)


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_hover()


func _update_hover() -> void:
	var denom := _raycast_denomination(get_viewport().get_mouse_position())
	if denom != _hovered:
		if _hovered and is_instance_valid(_hovered):
			_hovered.set_highlight(false)
		_hovered = denom
		if _hovered:
			_hovered.set_highlight(true)


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var denom := _raycast_denomination(event.position)
		if denom:
			denom.interact(_player)
			get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _raycast_denomination(mouse_pos: Vector2) -> MoneyDenomination:
	if _camera == null:
		return null

	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	var to := from + dir * 10.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := space.intersect_ray(query)
	if result.is_empty():
		return null

	var chain: Node = result.collider
	while chain != null:
		if chain is MoneyDenomination:
			return chain as MoneyDenomination
		chain = chain.get_parent()
	return null


func add_denomination(cents: int) -> void:
	if not _active:
		return
	_tendered_cents += cents
	EventBus.change_tendered_updated.emit(_tendered_cents, _change_due_cents)
	if _tendered_cents >= _change_due_cents:
		# No confirm button anymore — finalize as soon as enough is tendered.
		call_deferred("_give_change")


func _give_change() -> void:
	if not _active:
		return
	var earned := (_payment_cents - _tendered_cents) / 100.0
	EventBus.change_finalized.emit(earned)
