extends Node
## Steam multiplayer initialization, lobby management, and peer connection.
##
## Autoload singleton that handles:
## - Steam API initialization (app ID 480 for testing)
## - Lobby creation (host) and joining (client)
## - SteamMultiplayerPeer setup for P2P connections
## - Connection state tracking and signals

signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal connection_failed(reason: String)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_connected()
signal server_disconnected()
signal lobby_list_received(lobbies: Array)

## The Steam app ID. 480 = Valve's Spacewar (test app).
const STEAM_APP_ID: int = 480

var steam_id: int = 0
var lobby_id: int = 0
var is_host: bool = false
var connected: bool = false

var _steam_initialized: bool = false


func _ready() -> void:
	_initialize_steam()
	_connect_signals()


func _initialize_steam() -> void:
	var response: Dictionary = Steam.steamInitEx(STEAM_APP_ID, true)
	print("[NetworkManager] Steam init response: ", response)
	var status: int = response.get("status", 1)
	if status != 0:
		push_warning(
			"[NetworkManager] Steam init failed (status=%d): %s"
			% [status, response.get("verbal", "")]
		)
		# Retry on next frame — Steam client may not be fully ready.
		call_deferred("_retry_steam_init")
		return
	_steam_initialized = true
	steam_id = Steam.getSteamID()
	print("[NetworkManager] Steam ID: ", steam_id)
	print("[NetworkManager] Persona: ", Steam.getPersonaName())


## Retry Steam initialization after a short delay. The Steam client
## may not be fully ready when the game first starts.
func _retry_steam_init() -> void:
	if _steam_initialized:
		return
	# Wait a bit before retrying to give Steam time to initialize.
	await get_tree().create_timer(1.0).timeout
	var response: Dictionary = Steam.steamInitEx(STEAM_APP_ID, true)
	print("[NetworkManager] Steam retry init response: ", response)
	var status: int = response.get("status", 1)
	if status == 0:
		_steam_initialized = true
		steam_id = Steam.getSteamID()
		print("[NetworkManager] Steam ID: ", steam_id)
		print("[NetworkManager] Persona: ", Steam.getPersonaName())
	else:
		push_warning("[NetworkManager] Steam retry failed (status=%d)" % status)


func _connect_signals() -> void:
	# Steam lobby signals
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	# Multiplayer peer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Public API ---


## Create a lobby and start hosting.
func host_game() -> void:
	if not _steam_initialized:
		push_warning("[NetworkManager] Cannot host: Steam not initialized")
		connection_failed.emit(
			"Steam is not initialized. Please restart the game with Steam running."
		)
		return
	is_host = true
	print("[NetworkManager] Creating lobby...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)


## Join a lobby by its ID.
func join_game(target_lobby_id: int) -> void:
	if not _steam_initialized:
		push_warning("[NetworkManager] Cannot join: Steam not initialized")
		connection_failed.emit(
			"Steam is not initialized. Please restart the game with Steam running."
		)
		return
	if connected:
		print("[NetworkManager] Already connected, ignoring join request")
		return
	is_host = false
	print("[NetworkManager] Joining lobby: ", target_lobby_id)
	Steam.joinLobby(target_lobby_id)


## Invite a friend via Steam overlay.
func invite_friend() -> void:
	if lobby_id == 0:
		print("[NetworkManager] No lobby to invite to")
		return
	Steam.activateGameOverlayInviteDialog(lobby_id)


## Search for lobbies created by this game. Filters by the "game" lobby
## data key so we only show Lemonade Stand lobbies, not random SpaceWar
## test lobbies. Results come back via lobby_list_received signal.
func search_lobbies() -> void:
	print("[NetworkManager] Searching for lobbies...")
	Steam.addRequestLobbyListStringFilter("game", "lemonade_stand", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListResultCountFilter(20)
	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	print("[NetworkManager] Found %d lobbies" % lobbies.size())
	var results: Array = []
	for lobby_id in lobbies:
		var name: String = Steam.getLobbyData(lobby_id, "name")
		var host_name: String = Steam.getLobbyData(lobby_id, "host_name")
		var member_count: int = Steam.getNumLobbyMembers(lobby_id)
		results.append(
			{ "id": lobby_id, "name": name, "host_name": host_name, "member_count": member_count }
		)
	lobby_list_received.emit(results)


## Disconnect and clean up.
func leave_game() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	connected = false
	multiplayer.multiplayer_peer = null
	print("[NetworkManager] Left game")

# --- Steam callbacks ---


func _on_lobby_created(connect: int, this_lobby_id: int) -> void:
	if connect != 1:
		print("[NetworkManager] Lobby creation failed: ", connect)
		connection_failed.emit("Lobby creation failed (code: %d)" % connect)
		return
	lobby_id = this_lobby_id
	print("[NetworkManager] Lobby created: ", lobby_id)
	Steam.setLobbyData(lobby_id, "name", "Lemonade Stand - " + Steam.getPersonaName())
	Steam.setLobbyData(lobby_id, "host", str(steam_id))
	Steam.setLobbyData(lobby_id, "host_name", Steam.getPersonaName())
	Steam.setLobbyData(lobby_id, "game", "lemonade_stand")
	# Create host peer
	var peer = SteamMultiplayerPeer.new()
	peer.create_host(0)
	peer.server_relay = true
	multiplayer.set_multiplayer_peer(peer)
	connected = true
	lobby_created.emit(lobby_id)


func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("[NetworkManager] Lobby join failed: ", response)
		connection_failed.emit("Lobby join failed (code: %d)" % response)
		return
	lobby_id = this_lobby_id
	print("[NetworkManager] Lobby joined: ", lobby_id)
	# Note: we can't rely on comparing Steam IDs here, since testing with two
	# instances under the SAME Steam account gives them identical IDs. Use
	# is_host (set explicitly by which button the user pressed) instead.
	# Guard against duplicate peer creation if this callback fires more than once.
	if not is_host and not connected:
		var owner_id = Steam.getLobbyOwner(this_lobby_id)
		# Create client peer and connect to host
		var peer = SteamMultiplayerPeer.new()
		peer.create_client(owner_id, 0)
		peer.server_relay = true
		multiplayer.set_multiplayer_peer(peer)
	lobby_joined.emit(lobby_id)


func _on_join_requested(this_lobby_id: int, _friend_id: int) -> void:
	print("[NetworkManager] Join requested for lobby: ", this_lobby_id)
	join_game(this_lobby_id)

# --- Multiplayer callbacks ---


func _on_peer_connected(peer_id: int) -> void:
	print(
		"[NetworkManager] Peer connected: ",
		peer_id,
		" | my unique_id=",
		multiplayer.get_unique_id(),
		" is_server=",
		multiplayer.is_server(),
	)
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", peer_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] Connected to server")
	connected = true
	server_connected.emit()


func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed")
	connected = false
	connection_failed.emit("Failed to connect to server")


func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected")
	connected = false
	server_disconnected.emit()
