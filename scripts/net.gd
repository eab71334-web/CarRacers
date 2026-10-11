extends Node
## Autoload "Net": LAN hosting/joining (ENet), UDP server discovery, car-state sync,
## and a plain-UDP bridge so console clients (the PS4 build) can join the same race.

signal server_found(ip: String, host_name: String)
signal remote_state(id: int, pos: Vector3, yaw: float, speed: float)
signal peer_joined(id: int)
signal peer_left(id: int)
signal connected
signal connection_failed

const PORT := 24565
const DISCOVERY_PORT := 24566
const BRIDGE_PORT := 24567
const MAGIC := "CARRACERS1"
const BRIDGE_MAGIC := "CR1"
const BRIDGE_TIMEOUT := 5.0

var online := false
var in_race := false
var player_name := "Player"

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0

# Bridge (host only)
var _bridge: PacketPeerUDP
var _bridge_clients := {}   # "ip:port" -> {id, ip, port, last}
var _next_bridge_id := 1000
var _world := {}            # id -> [pos, yaw, speed]
var _snap_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return not online or multiplayer.is_server()


func host() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 7)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_bridge = PacketPeerUDP.new()
	if _bridge.bind(BRIDGE_PORT) != OK:
		_bridge = null
	return OK


func join(ip: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	return OK


func start_listening() -> void:
	if _listen != null:
		return
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null


func stop_listening() -> void:
	if _listen != null:
		_listen.close()
		_listen = null


func leave() -> void:
	if _bcast != null:
		_bcast.close()
		_bcast = null
	if _bridge != null:
		_bridge.close()
		_bridge = null
	_bridge_clients.clear()
	_world.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_race = false


func start_race_for_all() -> void:
	if online and multiplayer.is_server():
		_start_race.rpc()
	else:
		_start_race()


func send_state(pos: Vector3, yaw: float, speed: float) -> void:
	if online and multiplayer.is_server():
		_world[my_id()] = [pos, yaw, speed]
	if online and multiplayer.get_peers().size() > 0:
		_state.rpc(pos, yaw, speed)


func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


func _process(delta: float) -> void:
	if _bcast != null:
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			_bcast.put_packet((MAGIC + "|" + player_name).to_utf8_buffer())
	if _listen != null:
		while _listen.get_available_packet_count() > 0:
			var text := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := text.split("|")
			if parts.size() >= 2 and parts[0] == MAGIC:
				server_found.emit(ip, parts[1])
	if _bridge != null:
		_poll_bridge(delta)


# ---------- plain-UDP bridge for console clients ----------
# Client -> host:  CR1|J|name                      join / keep-alive until assigned
#                  CR1|S|x|y|z|yaw|speed           own car state (~30 Hz)
# Host -> client:  CR1|A|id                        assigned id
#                  CR1|W|id,x,y,z,yaw,speed;...    snapshot of all other cars (~20 Hz)

func _poll_bridge(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while _bridge.get_available_packet_count() > 0:
		var text := _bridge.get_packet().get_string_from_utf8()
		_handle_bridge(_bridge.get_packet_ip(), _bridge.get_packet_port(), text, now)

	# Drop silent clients.
	for key in _bridge_clients.keys():
		var c: Dictionary = _bridge_clients[key]
		if now - c["last"] > BRIDGE_TIMEOUT:
			_world.erase(c["id"])
			_bridge_clients.erase(key)
			peer_left.emit(c["id"])

	_snap_timer -= delta
	if _snap_timer <= 0.0 and not _bridge_clients.is_empty():
		_snap_timer = 0.05
		for key in _bridge_clients:
			var c: Dictionary = _bridge_clients[key]
			var items := PackedStringArray()
			for id in _world:
				if id == c["id"]:
					continue
				var s: Array = _world[id]
				var p: Vector3 = s[0]
				items.append("%d,%.2f,%.2f,%.2f,%.3f,%.2f" % [id, p.x, p.y, p.z, s[1], s[2]])
			_bridge_send(c["ip"], c["port"], "%s|W|%s" % [BRIDGE_MAGIC, ";".join(items)])


func _handle_bridge(ip: String, port: int, text: String, now: float) -> void:
	var p := text.split("|")
	if p.size() < 2 or p[0] != BRIDGE_MAGIC:
		return
	var key := "%s:%d" % [ip, port]
	if p[1] == "J":
		if not _bridge_clients.has(key):
			_bridge_clients[key] = {"id": _next_bridge_id, "ip": ip, "port": port, "last": now}
			_next_bridge_id += 1
		var c: Dictionary = _bridge_clients[key]
		c["last"] = now
		_bridge_send(ip, port, "%s|A|%d" % [BRIDGE_MAGIC, c["id"]])
	elif p[1] == "S" and p.size() >= 7 and _bridge_clients.has(key):
		var c: Dictionary = _bridge_clients[key]
		c["last"] = now
		var pos := Vector3(float(p[2]), float(p[3]), float(p[4]))
		var yaw := float(p[5])
		var spd := float(p[6])
		_world[c["id"]] = [pos, yaw, spd]
		remote_state.emit(c["id"], pos, yaw, spd)
		if multiplayer.get_peers().size() > 0:
			_bridge_state.rpc(c["id"], pos, yaw, spd)


func _bridge_send(ip: String, port: int, text: String) -> void:
	_bridge.set_dest_address(ip, port)
	_bridge.put_packet(text.to_utf8_buffer())


# ---------- ENet callbacks ----------

func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	# Late joiner: if the race already started, send them straight into it.
	if multiplayer.is_server() and in_race:
		_start_race.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	_world.erase(id)
	peer_left.emit(id)


@rpc("authority", "call_local", "reliable")
func _start_race() -> void:
	in_race = true
	get_tree().change_scene_to_file("res://scenes/race.tscn")


@rpc("any_peer", "unreliable")
func _state(pos: Vector3, yaw: float, speed: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		_world[id] = [pos, yaw, speed]
	remote_state.emit(id, pos, yaw, speed)


## Host relays console-client cars to the other ENet players.
@rpc("authority", "unreliable")
func _bridge_state(id: int, pos: Vector3, yaw: float, speed: float) -> void:
	remote_state.emit(id, pos, yaw, speed)
