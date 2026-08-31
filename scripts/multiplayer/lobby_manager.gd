extends Node
## Tracks the pre-game lobby roster (name, chosen stand, ready state) across
## the MainMenu -> Lobby -> Gameworld scene transitions. An autoload so this
## state survives changing scenes (regular scene-local state wouldn't).
##
## The host is authoritative for the roster: any peer requests a change via
## an RPC targeted at peer 1, the host applies it to its own copy and then
## broadcasts the whole updated roster back out to everyone. This keeps the
## logic simple (no per-field conflict resolution needed) at the cost of a
## small amount of redundant data on every change — fine at this scale
## (at most a handful of players).

signal roster_changed()
signal game_starting()
signal late_join_starting(peer_id: int)
signal late_join_denied(reason: String)

## peer_id -> { "name": String, "stand_index": int (-1 = unset, 0/1/...
## corresponds to the Nth stand), "ready": bool, "customization": Dictionary }
var roster: Dictionary = { }

## Set to true when the game has already started. Late joiners go through the
## lobby UI but are auto-assigned a free stand, then spawned when they ready up.
var game_started: bool = false

## The game mode for this lobby (Solo/Coop/Versus). Set by the host when
## creating/loading a save. Determines how many stands are available and
## how players are assigned.
var game_mode: int = GameState.GameMode.SOLO

## Maximum total players across all stands.
const MAX_PLAYERS: int = 4


## Returns the number of stands for the current game mode.
func stand_count() -> int:
	match game_mode:
		GameState.GameMode.SOLO:
			return 1
		GameState.GameMode.COOP:
			return 1
		GameState.GameMode.VERSUS:
			return 2
		_:
			return 1


## Returns the maximum players per stand for the current game mode.
func max_players_per_stand() -> int:
	match game_mode:
		GameState.GameMode.SOLO:
			return 1
		GameState.GameMode.COOP:
			return MAX_PLAYERS
		GameState.GameMode.VERSUS:
			return MAX_PLAYERS / 2 # 2 per stand (2v2)
		_:
			return 1


func _ready() -> void:
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)


func _on_lobby_created(_lobby_id: int) -> void:
	_register(1, _local_display_name())


func _on_server_connected() -> void:
	_wait_then_request_register()


func _wait_then_request_register() -> void:
	var attempts := 0
	while attempts < 100: # up to ~15 seconds
		if multiplayer.get_peers().has(1):
			print("[LobbyManager] Found peer 1, sending register request")
			_request_register.rpc_id(1, _local_display_name())
			return
		attempts += 1
		await get_tree().create_timer(0.15).timeout
	push_warning("[LobbyManager] gave up waiting for peer 1 to register")


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and roster.has(peer_id):
		roster.erase(peer_id)
		_broadcast_roster()


func _local_display_name() -> String:
	var n: String = Steam.getPersonaName()
	return n if n != "" else "Player"


## Reset roster state for a fresh lobby (call before hosting/joining again).
func reset() -> void:
	roster.clear()
	game_started = false
	game_mode = GameState.GameMode.SOLO


## Re-emits the current roster so a newly-loaded scene (e.g. the Lobby)
## can refresh its display even if the roster_changed signal fired
## during the scene transition (before the new scene's _ready connected).
func request_refresh() -> void:
	roster_changed.emit()


func _register(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	roster[peer_id] = {
		"name": player_name,
		"stand_index": -1,
		"ready": false,
		"customization": { },
	}
	# If the game already started, this is a late joiner. Auto-assign a stand or
	# deny them immediately so they don't take up an in-game slot without one.
	if game_started:
		var free_stand := _first_free_stand()
		if free_stand < 0:
			print("[LobbyManager] Denying late join for peer %d (no free stand)" % peer_id)
			_deny_late_join.rpc_id(peer_id, "Both stands are full. Try again later.")
			# Give the client a moment to show the message before dropping.
			_disconnect_peer_deferred.call_deferred(peer_id)
		else:
			roster[peer_id]["stand_index"] = free_stand
			print("[LobbyManager] Late join peer %d assigned stand %d" % [peer_id, free_stand])
	_broadcast_roster()
	# Sync the game-started flag so the new client knows the lobby is in late-join mode.
	if game_started:
		_sync_game_started.rpc_id(peer_id, game_started)
	# Sync the game mode so the client's lobby UI renders correctly.
	_sync_game_mode.rpc_id(peer_id, game_mode)
	# Sync the host's stand name so the joiner sees the correct stand
	# name in the lobby UI instead of their own save's stand name.
	_sync_stand_name.rpc_id(peer_id, GameState.stand_name)


@rpc("any_peer", "call_local", "reliable")
func _request_register(player_name: String) -> void:
	_register(_sender_id(), player_name)


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## Returns the first unclaimed stand index (0 or 1), or -1 if both are taken.
func _first_free_stand() -> int:
	var used: Array[int] = []
	for id in roster:
		if id == _sender_id():
			continue
		var idx: int = roster[id].get("stand_index", -1)
		if idx >= 0:
			used.append(idx)
	var count := stand_count()
	for i in range(count):
		if not used.has(i):
			return i
	return -1


func _disconnect_peer_deferred(peer_id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if multiplayer.has_multiplayer_peer() and peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _broadcast_roster() -> void:
	print("[LobbyManager] Broadcasting roster: %d players" % roster.size())
	_apply_roster.rpc(roster)


## Marks the game as started on the host and syncs that to all clients.
func mark_game_started() -> void:
	if not multiplayer.is_server():
		return
	game_started = true
	_sync_game_started.rpc(game_started)


@rpc("authority", "call_local", "reliable")
func _sync_game_started(is_started: bool) -> void:
	game_started = is_started


@rpc("authority", "call_local", "reliable")
func _sync_game_mode(mode: int) -> void:
	game_mode = mode
	roster_changed.emit() # trigger lobby UI to re-apply mode layout


## Sync the host's stand name to clients so the lobby UI shows the
## correct stand name for joiners (not their own save's name).
@rpc("authority", "call_local", "reliable")
func _sync_stand_name(stand_name: String) -> void:
	GameState.stand_name = stand_name
	# Refresh the lobby UI if it's visible so the stand header updates.
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _deny_late_join(reason: String) -> void:
	if multiplayer.is_server():
		return
	print("[LobbyManager] Late join denied: %s" % reason)
	late_join_denied.emit(reason)


@rpc("any_peer", "call_local", "reliable")
func _apply_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	print(
		"[LobbyManager] Applied roster: %d players, my id=%d"
		% [roster.size(), multiplayer.get_unique_id()]
	)
	roster_changed.emit()

## --- Local player actions (call these from the lobby UI) ---


func set_my_stand(stand_index: int) -> void:
	_request_set_stand.rpc_id(1, stand_index)


@rpc("any_peer", "call_local", "reliable")
func _request_set_stand(stand_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if roster.has(id):
		roster[id]["stand_index"] = stand_index
		_broadcast_roster()


func set_my_ready(is_ready: bool) -> void:
	_request_set_ready.rpc_id(1, is_ready)


func set_my_customization(data: Dictionary) -> void:
	_request_set_customization.rpc_id(1, data)


@rpc("any_peer", "call_local", "reliable")
func _request_set_customization(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if roster.has(id):
		roster[id]["customization"] = data
		_broadcast_roster()


func get_my_customization() -> Dictionary:
	return get_my_entry().get("customization", { })


@rpc("any_peer", "call_local", "reliable")
func _request_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender_id()
	if roster.has(id):
		roster[id]["ready"] = is_ready
		_broadcast_roster()
		# If the game is already in progress, a late joiner starts the moment
		# they ready up (assuming they have a stand).
		if game_started and is_ready and roster[id].get("stand_index", -1) >= 0:
			late_join_starting.emit(id)

## --- Queries ---


func get_my_entry() -> Dictionary:
	return roster.get(multiplayer.get_unique_id(), { })


func all_ready() -> bool:
	# Only players who have selected a stand count toward the ready check.
	# Players without a stand (stand_index < 0) are ignored — the host can
	# start without them and they won't spawn in.
	var has_stand_players := false
	for id in roster:
		var stand_idx: int = roster[id].get("stand_index", -1)
		if stand_idx < 0:
			continue
		has_stand_players = true
		if not roster[id].get("ready", false):
			return false
	return has_stand_players

## --- Starting the game (host only) ---


func start_game() -> void:
	if not multiplayer.is_server():
		return
	if not all_ready():
		return
	mark_game_started()
	# Host starts its own transition immediately. Clients are notified
	# via notify_clients_start() after the host has finished loading.
	game_starting.emit()


## Called by the host after its local player is ready and world state
## has been pushed. Tells all clients to start their game transition.
func notify_clients_start() -> void:
	if not multiplayer.is_server():
		return
	_notify_clients_start.rpc()


@rpc("authority", "call_local", "reliable")
func _notify_clients_start() -> void:
	# On the host this is a no-op — it already started via start_game().
	if multiplayer.is_server():
		return
	# Don't change scenes — main.tscn is already loaded (the lobby runs
	# inside it). Just emit the signal so main.gd can transition from
	# the lobby phase to the game phase (tween camera to first-person,
	# hide lobby UI, start game systems).
	game_starting.emit()
