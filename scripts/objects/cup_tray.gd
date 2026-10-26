class_name CupTray
extends Interactable
## A tray holding filled cups in authored slots. Purchased as equipment
## and placed like any other container. The server assistant fills free
## slots; players pick cups off it like any other placed cup.
## Pickupable only while no cups sit on it.

@onready var _slots: Node3D = $Slots
@onready var physics: StaticBody3D = $Physics


func _ready() -> void:
	add_to_group("container")
	add_to_group("cup_tray")
	var p := Pickupable.setup_for_container(self, "cup_tray")
	p.can_pickup_callback = func(player: Node) -> bool:
		if player == null or player.get("held_item") != HeldItem.NONE:
			return false
		if not can_player_use(player):
			return false
		return _cups_on_tray() == 0


func interact(player: Node) -> void:
	var pickupable := get_node_or_null("Pickupable") as Pickupable
	if pickupable != null:
		pickupable.pick_up(player)


func get_hint(player: Node) -> String:
	if _cups_on_tray() == 0 and can_player_use(player):
		return "Cup Tray | LMB: pick up"
	return "Cup Tray"


## World position of the first free slot, or Vector3.INF when full.
func free_slot_position() -> Vector3:
	for m in _slots.get_children():
		var p: Vector3 = m.global_position
		if not _slot_occupied(p):
			return p
	return Vector3.INF


func has_free_slot() -> bool:
	return free_slot_position() != Vector3.INF


func _cups_on_tray() -> int:
	var c := 0
	for m in _slots.get_children():
		if _slot_occupied(m.global_position):
			c += 1
	return c


func _slot_occupied(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("container"):
		if n is Cup and is_instance_valid(n) \
				and n.global_position.distance_to(p) < 0.12:
			return true
	return false
