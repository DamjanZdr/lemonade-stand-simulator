class_name CupTray
extends Interactable
## A tray holding cups in authored slots. Purchased as equipment and
## placed like any other container. The server assistant fills free
## slots; players pick cups off it like any other placed cup.
## Empty tray: LMB or RMB picks it up. Loaded tray: only RMB picks it
## up, and the cups ride along (workstation-style carry).

@onready var _slots: Node3D = $Slots
@onready var physics: StaticBody3D = $Physics

## Cups sit closer than this to a slot marker to count as occupying it.
## Must stay below the inter-slot spacing (~0.075m) or adjacent slots
## always read as occupied.
const SLOT_RADIUS := 0.05


func _ready() -> void:
	add_to_group("container")
	add_to_group("cup_tray")
	var p := Pickupable.setup_for_container(self, "cup_tray")


func interact(player: Node) -> void:
	# LMB only grabs an empty tray — with cups on it, the click belongs
	# to the cups; RMB carries the whole loaded tray.
	if _cups_on_tray() > 0:
		EventBus.interaction_hint_changed.emit("RMB to pick up tray with cups")
		return
	var pickupable := get_node_or_null("Pickupable") as Pickupable
	if pickupable != null and pickupable.can_pick_up(player):
		pickupable.pick_up(player)


func get_hint(player: Node) -> String:
	if can_player_use(player):
		if _cups_on_tray() == 0:
			return "Cup Tray | LMB: pick up"
		return "Cup Tray | RMB: pick up with cups"
	return "Cup Tray"


func has_cups() -> bool:
	return _cups_on_tray() > 0


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
				and n.global_position.distance_to(p) < SLOT_RADIUS:
			return true
	return false
