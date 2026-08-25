class_name Player
extends CharacterBody3D

@export var move_speed: float = 5.0
const MOUSE_SENSITIVITY: float = 0.002

## Head/neck yaw limit before the body rotates to catch up.
const NECK_YAW_MAX: float = 0.8
## How quickly the body rotates to match the head when the neck hits its limit.
const NECK_YAW_CATCHUP_SPEED: float = 8.0

const HINT_GROUND := "Aim at ground to place"
const HINT_STAND := "Aim at stand or workstation to place"

## Which stand this player is assigned to (set by whatever assigns players
## to stands — the lobby, in real multiplayer). Null in solo/offline play,
## where there's no "your stand vs their stand" concept since only one
## person is playing — see StandUnit.can_be_served_by() for how this is
## used to restrict serving another stand's customers in real multiplayer
## without blocking solo testing of every stand.
var assigned_stand: StandUnit = null

var held_item: int = HeldItem.NONE
var held_item_data: Dictionary = { }
var _held_mesh: Node3D = null

@export var gravity: float = 9.8
@export var sprint_multiplier: float = 1.8
@export var jump_velocity: float = 5.0
@export var rapid_fire_interval: float = 0.35

# Last node hit by a raycast during an interact call; used by interactable
# scripts to know which collider the player actually clicked.
var last_interact_hit: Node = null

# --- Container placement ghost ---
func _held_pitcher_has_contents() -> bool:
	var recipe: Dictionary = held_item_data.get("saved_recipe", { })
	return (
		recipe.get("fruit_count", recipe.get("lemons", 0.0)) > 0.0 or recipe.get("water", 0.0) > 0.0
		or recipe.get("sugar", 0.0) > 0.0 or recipe.get("ice", 0.0) > 0.0
	)


func _empty_held_pitcher() -> void:
	## Dumps out whatever's currently in the held pitcher. Keeps the pitcher
	## itself held — only clears its contents.
	if not _held_pitcher_has_contents():
		EventBus.interaction_hint_changed.emit("Pitcher is already empty!")
		return

	held_item_data["saved_recipe"] = { }
	held_item_data["has_liquid"] = false

	if _held_mesh is Pitcher:
		var held_pitcher := _held_mesh as Pitcher
		held_pitcher.fruit_type = ""
		held_pitcher.fruit_count = 0.0
		held_pitcher.water = 0.0
		held_pitcher.sugar = 0.0
		held_pitcher.ice = 0.0
		held_pitcher.cups_poured = 0
		held_pitcher.update_label()
		held_pitcher.update_liquid_color()

	EventBus.interaction_hint_changed.emit("Pitcher emptied!")


