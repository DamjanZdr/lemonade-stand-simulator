extends Node3D
## Multiplayer test scene.
##
## Spawns players when peers connect. Host spawns its own player on ready,
## clients request spawn via RPC. MultiplayerSpawner replicates players.

const TEST_PLAYER_SCENE: PackedScene = preload("res://scenes/multiplayer/test_player.tscn")

@onready var players_node: Node = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

var _client_spawn_requested: bool = false


func _ready() -> void:
	# Configure the spawner to auto-replicate children of Players.
	# spawnable_scenes expects resource paths (PackedStringArray), not PackedScene objects.
	spawner.add_spawnable_scene("res://scenes/multiplayer/test_player.tscn")
	spawner.spawn_path = players_node.get_path()

	# Connect networking signals.
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.lobby_created.connect(_on_lobby_created)

	# NOTE: We deliberately do NOT check multiplayer.is_server() here. Before
	# any real peer is created, Godot uses a default OfflineMultiplayerPeer
	# whose unique ID is always 1, so is_server() would trivially return true
	# on every instance — spawning an untracked, unreplicated phantom player.
	# We only spawn once a *real* peer exists (lobby_created for the host,
	# server_connected for clients).


func _on_lobby_created(_lobby_id: int) -> void:
	# We just became the real host (peer ID 1) — spawn our own player now.
	print("[MultiplayerTest] _on_lobby_created fired, my unique_id=", multiplayer.get_unique_id())
	spawn_player(1)


func _on_server_connected() -> void:
	# Client connected to server — request spawn.
	print(
		"[MultiplayerTest] _on_server_connected fired, my unique_id=",
		multiplayer.get_unique_id(),
	)
	_request_spawn.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _request_spawn() -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	print(
		"[MultiplayerTest] _request_spawn RPC received, remote_sender_id=",
		sender_id,
		" my unique_id=",
		multiplayer.get_unique_id(),
	)
	if sender_id != 0:
		spawn_player(sender_id)


func _on_peer_connected(peer_id: int) -> void:
	print(
		"[MultiplayerTest] _on_peer_connected fired for peer ",
		peer_id,
		", is_server=",
		multiplayer.is_server(),
		", my unique_id=",
		multiplayer.get_unique_id(),
	)
	# Server spawns a player for the new peer.
	if multiplayer.is_server():
		spawn_player(peer_id)
	elif peer_id == multiplayer.get_unique_id() and not _client_spawn_requested:
		# Observed SteamMultiplayerPeer quirk: instead of (or in addition to)
		# the standard connected_to_server signal, this fires peer_connected
		# reporting our OWN id once the connection is starting to come up.
		# However the underlying peer connection to the host isn't
		# necessarily usable for RPCs yet at this exact moment, so poll the
		# actual connection status before sending anything.
		_client_spawn_requested = true
		_wait_for_connection_then_spawn()


func _wait_for_connection_then_spawn() -> void:
	# CONNECTION_CONNECTED can be true before SteamMultiplayerPeer's internal
	# handshake (which registers peer ID 1 as a known/addressable peer) has
	# finished — that handshake is retried roughly every 500ms internally.
	# So wait until peer 1 actually shows up in multiplayer.get_peers()
	# before attempting to address an RPC at it.
	var attempts := 0
	while attempts < 100: # up to ~15 seconds
		var peers: PackedInt32Array = multiplayer.get_peers()
		if attempts % 10 == 0:
			print(
				"[MultiplayerTest] Waiting for peer 1 to register... current peers=",
				peers,
				" (attempt ",
				attempts,
				")",
			)
		if peers.has(1):
			print("[MultiplayerTest] Peer 1 registered, requesting spawn (attempt ", attempts, ")")
			_request_spawn.rpc_id(1)
			return
		attempts += 1
		await get_tree().create_timer(0.15).timeout
	print("[MultiplayerTest] Gave up waiting for peer 1 to register")


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		remove_player(peer_id)


func spawn_player(id: int) -> void:
	if players_node.has_node(str(id)):
		return
	var player = TEST_PLAYER_SCENE.instantiate()
	player.name = str(id)
	# Random spawn offset so players don't overlap.
	player.position = Vector3(randf_range(-3, 3), 2.0, randf_range(-3, 3))
	players_node.add_child(player)
	print("[MultiplayerTest] Spawned player for peer ", id)


func remove_player(id: int) -> void:
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()
		print("[MultiplayerTest] Removed player for peer ", id)
