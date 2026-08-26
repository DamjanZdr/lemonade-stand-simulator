class_name Player
extends CharacterBody3D

@export var move_speed: float = 3.0

const HINT_GROUND := "Aim at ground to place"
const HINT_STAND := "Aim at stand or workstation to place"

## Which stand this player is assigned to (set by whatever assigns players
## to stands ΓÇö the lobby, in real multiplayer). Null in solo/offline play,
## where there's no "your stand vs their stand" concept since only one
## person is playing ΓÇö see StandUnit.can_be_served_by() for how this is
## used to restrict serving another stand's customers in real multiplayer
## without blocking solo testing of every stand.
var assigned_stand: StandUnit = null

var held_item: int = HeldItem.NONE
var held_item_data: Dictionary = { }
var _held_mesh: Node3D = null

@export var gravity: float = 9.8
@export var sprint_multiplier: float = 3.5
@export var jump_velocity: float = 5.0
@export var rapid_fire_interval: float = 0.35

# Last node hit by a raycast during an interact call; used by interactable
# scripts to know which collider the player actually clicked.
var last_interact_hit: Node = null

@onready var head: Node3D = $Head
@onready var hand_slot: Node3D = $Head/Camera3D/HandSlot
@onready var ray: RayCast3D = $Head/RayCast3D
@onready var camera: Camera3D = $Head/Camera3D
@onready var visuals: PlayerVisuals = $Visuals
@onready var inventory: PlayerInventory = $PlayerInventory
@onready var interaction = $PlayerInteraction
@onready var placement: PlayerPlacement = $PlayerPlacement
@onready var controller: PlayerController = $PlayerController

var _money_mode: bool = false


func set_money_mode(active: bool) -> void:
	_money_mode = active
	if interaction != null:
		interaction.set_money_mode(active)
	if active:
		EventBus.interaction_hint_changed.emit("")

# ---------------------------------------------------------------------------
#  Controller delegation wrappers
#  Object scripts (blackboard.gd, price_board.gd) call these on the Player
#  node directly. They forward to the PlayerController child that now owns
#  the real implementation.
# ---------------------------------------------------------------------------


func enter_priceboard_focus(focus_transform: Transform3D) -> void:
	controller.enter_priceboard_focus(focus_transform)


func exit_priceboard_focus() -> void:
	controller.exit_priceboard_focus()


func _enter_tree() -> void:
	# Multiplayer authority: nodes spawned via main.gd's per-peer spawning
	# are named after the owning peer's ID, matching the pattern used by
	# the Phase 1 networking test scene. A statically-placed Player (e.g.
	# in an editor preview scene with a non-numeric name) keeps the
	# default authority (peer 1 / host), which is also correct for solo
	# play using the default OfflineMultiplayerPeer.
	if name.is_valid_int():
		set_multiplayer_authority(int(name))
	GameLog.log(
		"[Player] _enter_tree name=%s authority=%d my_id=%d is_auth=%s"
		% [
			name,
			get_multiplayer_authority(),
			multiplayer.get_unique_id(),
			is_multiplayer_authority(),
		]
	)
	_setup_position_replication()


## So other peers can see where a remote player physically is, even
## though only the authoritative peer drives that player's own movement
## input/physics locally.
func _setup_position_replication() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "PositionSync"
	# Explicitly set the synchronizer's authority to match the player's.
	# Without this, the synchronizer may not know which peer is the
	# authority and won't replicate position/rotation to other peers.
	sync.set_multiplayer_authority(get_multiplayer_authority())
	# Set replication config BEFORE adding to tree ΓÇö otherwise the
	# synchronizer tries to start replication with no config and errors.
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath("../:position"))
	config.add_property(NodePath("../:rotation"))
	sync.replication_config = config
	add_child(sync)
	GameLog.log(
		"[Player] PositionSync set up for %s authority=%d"
		% [name, sync.get_multiplayer_authority()]
	)


func _ready() -> void:
	add_to_group("player")
	GameLog.log(
		"[Player] _ready name=%s authority=%d my_id=%d is_auth=%s"
		% [
			name,
			get_multiplayer_authority(),
			multiplayer.get_unique_id(),
			is_multiplayer_authority(),
		]
	)
	_setup_visuals()
	if is_multiplayer_authority():
		_configure_local_player()
	else:
		# This is another peer's player, replicated here so we can see
		# them ΓÇö not ours to control. Skip capturing input/camera/audio,
		# which would otherwise fight with our own local player for them.
		# Log the initial position so we can see if the synchronizer
		# is updating it over time.
		GameLog.log("[Player] Remote player %s initial pos=%s" % [name, str(global_position)])
		# Set up a one-shot timer to check if position is being updated
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(
			func():
				if is_instance_valid(self):
					GameLog.log(
						"[Player] Remote player %s pos after 3s=%s" % [name, str(global_position)]
					),
		)


## Applies local-player-only setup: mouse capture, camera, audio, and physics.
## Called from _ready for the local player, and from main.gd when a late
## joiner's authority is claimed after the spawner replicates the node.
func _configure_local_player() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Layer 2 is used by the screen-space outline system for white fill nodes.
	# The main camera must not render them ΓÇö only the SubViewport OutlineCamera does.
	$Head/Camera3D.cull_mask &= ~2
	$Head/Camera3D.make_current()
	GameLog.log("[Player] Camera made current for local player %s" % name)
	var listener := $Head/Camera3D/AudioListener3D as AudioListener3D
	if listener:
		listener.make_current()

	# Smooth movement over small ledges and slopes (sidewalks, curbs, etc.)
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.3
	floor_constant_speed = true
	floor_stop_on_slope = false
	floor_block_on_wall = false

	# Precompute shared box metrics and load the workstation scene for placement.
	placement._configure_local_player()


## Set up the PlayerVisuals: apply customization from the lobby roster,
## scale the head bone, hide the model for the local player (first-person),
## and start the idle animation.
func _setup_visuals() -> void:
	if visuals == null:
		return
	# Mark as player visual so eye look-at targets other players, not "Player"
	visuals.is_player_visual = true
	# Apply customization from the lobby roster
	var peer_id := int(name)
	var entry: Dictionary = LobbyManager.roster.get(peer_id, { })
	var custom: Dictionary = entry.get("customization", { })
	if not custom.is_empty():
		visuals.apply_customization(custom)
	else:
		# No customization data ΓÇö use a deterministic seed based on peer ID
		# so all peers see the same random appearance for this player
		visuals.appearance_seed = peer_id * 2654435761
		visuals.randomize_appearance()
	# Scale the head bone for cartoony proportions (from customization or default)
	var head_size: float = custom.get("head_size", 1.3)
	visuals.scale_head_bone(head_size)
	# Hide visuals for the local player (first-person camera)
	# Remote players see the full character model
	visuals.visible = not is_multiplayer_authority()
	# Start idle animation
	visuals.play_anim("Idle")
	controller._current_anim = "Idle"

# ---------------------------------------------------------------------------
#  Placement delegation wrappers
#  PlayerInteraction, PlayerInventory, and object scripts (press, pitcher,
#  fruit_bin, etc.) call these on the Player node directly. They forward to
#  the PlayerPlacement child that now owns the real implementation.
# ---------------------------------------------------------------------------


## Rapid-fire interval adjusted by the nimbleness upgrade. Used by
## PlayerInteraction to throttle held-mouse deposits.
func _get_rapid_fire_interval() -> float:
	var nimble_bonus: float = UpgradeManager.get_effect_total("nimbleness")
	if nimble_bonus > 0.0:
		return rapid_fire_interval * (1.0 - nimble_bonus)
	return rapid_fire_interval


func pickup_container(interactable: Interactable, container_type: String) -> void:
	placement.pickup_container(interactable, container_type)


func _remove_placement_groups(node: Node) -> void:
	placement._remove_placement_groups(node)


func _held_pitcher_has_contents() -> bool:
	return placement._held_pitcher_has_contents()


func _empty_held_pitcher() -> void:
	placement._empty_held_pitcher()


func _is_aiming_at_grid() -> bool:
	return placement._is_aiming_at_grid()


func _is_placement_surface(collider: Object) -> bool:
	return placement._is_placement_surface(collider)


func _is_ground_surface(collider: Object) -> bool:
	return placement._is_ground_surface(collider)


func _find_customer_in_ancestors(node: Node) -> Customer:
	return placement._find_customer_in_ancestors(node)


func _find_pedestrian_in_ancestors(node: Node) -> Pedestrian:
	return placement._find_pedestrian_in_ancestors(node)


func _set_visual_visible(node: Node, on: bool) -> void:
	if node is GeometryInstance3D or node is CanvasItem:
		node.visible = on
	for child in node.get_children():
		_set_visual_visible(child, on)
