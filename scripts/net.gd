extends Node
## Autoload "Net": LAN hosting/joining (ENet), UDP server discovery, and car-state sync.

signal server_found(ip: String, host_name: String)
signal remote_state(id: int, pos: Vector3, yaw: float, speed: float)
signal peer_joined(id: int)
signal peer_left(id: int)
signal connected
signal connection_failed

const PORT := 24565
const DISCOVERY_PORT := 24566
const MAGIC := "CARRACERS1"

var online := false
var in_race := false
var player_name := "Player"

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
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


func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)
	# Late joiner: if the race already started, send them straight into it.
	if multiplayer.is_server() and in_race:
		_start_race.rpc_id(id)


@rpc("authority", "call_local", "reliable")
func _start_race() -> void:
	in_race = true
	get_tree().change_scene_to_file("res://scenes/race.tscn")


@rpc("any_peer", "unreliable")
func _state(pos: Vector3, yaw: float, speed: float) -> void:
	remote_state.emit(multiplayer.get_remote_sender_id(), pos, yaw, speed)
