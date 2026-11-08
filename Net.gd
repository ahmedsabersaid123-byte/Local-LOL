extends Node
# Multiplayer (ENet) + lobby state. The host's game is authoritative for the lobby;
# friends find a room by the host's username through backend/server.js.

signal lobby_changed
signal status(msg: String)
signal joined_room
signal left_room

const PORT := 7777
const MAX_PLAYERS := 32

var players := {}     # peer_id -> {name, username, team, look}
var bots := []        # [{name, team, level}]
var mode := "tdm"     # tdm | boss
var boss_level := 1
var match_seed := 0
var in_room := false
var in_match := false
var solo := false
var _join_queue: Array = []
var _join_port := PORT
var _wired := false


func my_info() -> Dictionary:
	var u := Api.user
	return {
		"name": u.get("display_name", "Player"),
		"username": u.get("username", ""),
		"team": 0,
		"look": Api.current_look(),
	}


func _wire() -> void:
	if _wired:
		return
	_wired = true
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return in_room and multiplayer.multiplayer_peer != null and multiplayer.is_server()


# ---------- hosting / joining ----------
func host_game() -> int:
	_wire()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	solo = false
	_reset_lobby()
	players[1] = my_info()
	in_room = true
	lobby_changed.emit()
	joined_room.emit()
	return OK


func host_solo() -> void:
	_wire()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	solo = true
	_reset_lobby()
	players[1] = my_info()
	in_room = true


func join_game(addresses: Array, port: int = PORT) -> void:
	_wire()
	_join_queue = addresses.duplicate()
	_join_port = port
	_try_next_address()


func _try_next_address() -> void:
	if _join_queue.is_empty():
		status.emit("مقدرتش أوصل للغرفة (تأكد من فتح بورت %d عند صاحب الغرفة)" % _join_port)
		multiplayer.multiplayer_peer = null
		return
	var addr: String = _join_queue.pop_front()
	status.emit("بتصل بـ %s ..." % addr)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, _join_port)
	if err != OK:
		_try_next_address()
		return
	multiplayer.multiplayer_peer = peer


func _on_connected() -> void:
	solo = false
	in_room = true
	register_player.rpc_id(1, my_info())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_try_next_address()


func _on_server_disconnected() -> void:
	status.emit("صاحب الغرفة خرج")
	leave()


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		_broadcast()


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_reset_lobby()
	in_room = false
	in_match = false
	solo = false
	left_room.emit()
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != "res://scenes/Menu.tscn":
		get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _reset_lobby() -> void:
	players = {}
	bots = []
	mode = "tdm"
	boss_level = 1


# ---------- lobby sync ----------
@rpc("any_peer", "reliable")
func register_player(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	info["team"] = _smaller_team()
	players[id] = info
	_broadcast()


func _broadcast() -> void:
	if not solo:
		sync_lobby.rpc(players, bots, mode, boss_level)
	lobby_changed.emit()


@rpc("authority", "reliable")
func sync_lobby(p: Dictionary, b: Array, m: String, bl: int) -> void:
	players = p
	bots = b
	mode = m
	boss_level = bl
	if not in_room:
		in_room = true
	lobby_changed.emit()
	joined_room.emit()


func _smaller_team() -> int:
	var c := [0, 0]
	for id in players:
		c[int(players[id].team) % 2] += 1
	for b in bots:
		c[int(b.team) % 2] += 1
	return 0 if c[0] <= c[1] else 1


func team_count(t: int) -> int:
	var n := 0
	for id in players:
		if int(players[id].team) == t:
			n += 1
	for b in bots:
		if int(b.team) == t:
			n += 1
	return n


# ---------- host / player actions ----------
func move_player(id: int, team: int) -> void:
	if multiplayer.is_server():
		if players.has(id):
			players[id].team = team
			_broadcast()
	else:
		request_team.rpc_id(1, team)


@rpc("any_peer", "reliable")
func request_team(team: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and (team == 0 or team == 1):
		players[id].team = team
		_broadcast()


func add_bot(team: int, level: int) -> void:
	if not multiplayer.is_server() or bots.size() >= 24:
		return
	var nm: String = Catalog.BOT_NAMES[bots.size() % Catalog.BOT_NAMES.size()]
	bots.append({"name": "%s [Bot]" % nm, "team": team, "level": clampi(level, 1, Catalog.BOT_LEVELS.size())})
	_broadcast()


func remove_bot(index: int) -> void:
	if multiplayer.is_server() and index >= 0 and index < bots.size():
		bots.remove_at(index)
		_broadcast()


func set_bot_team(index: int, team: int) -> void:
	if multiplayer.is_server() and index >= 0 and index < bots.size():
		bots[index].team = team
		_broadcast()


func set_mode(m: String) -> void:
	if multiplayer.is_server():
		mode = m
		_broadcast()


func set_boss_level(l: int) -> void:
	if multiplayer.is_server():
		boss_level = clampi(l, 1, Catalog.BOSS_LEVELS.size())
		_broadcast()


func start_match() -> void:
	if not multiplayer.is_server():
		return
	if not solo:
		_broadcast()
	begin_match.rpc(randi())


@rpc("authority", "call_local", "reliable")
func begin_match(seed_value: int) -> void:
	match_seed = seed_value
	in_match = true
	get_tree().change_scene_to_file("res://scenes/Match.tscn")
