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

## peer_id -> { "name": String, "stand_index": int (-1 = unset, 0/1/...
## corresponds to the Nth stand), "ready": bool, "customization": Dictionary }
var roster: Dictionary = { }


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
	print("[LobbyManager] Registered peer %d as '%s'" % [peer_id, player_name])
	_broadcast_roster()


@rpc("any_peer", "call_local", "reliable")
func _request_register(player_name: String) -> void:
	_register(_sender_id(), player_name)


func _sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _broadcast_roster() -> void:
	print("[LobbyManager] Broadcasting roster: %d players" % roster.size())
	_apply_roster.rpc(roster)


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
	_do_start_game.rpc()


@rpc("authority", "call_local", "reliable")
func _do_start_game() -> void:
	# Don't change scenes — main.tscn is already loaded (the lobby runs
	# inside it). Just emit the signal so main.gd can transition from
	# the lobby phase to the game phase (tween camera to first-person,
	# hide lobby UI, start game systems).
	game_starting.emit()
