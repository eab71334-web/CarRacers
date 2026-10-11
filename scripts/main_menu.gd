extends Control
## Main menu built in code: Solo, Host LAN, Join LAN (auto-discovery or manual IP).

var _status: Label
var _start_btn: Button
var _server_list: VBoxContainer
var _ip_edit: LineEdit
var _found := {}


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(520, 0)
	root.position = Vector2(-260, -250)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var title := Label.new()
	title.text = "CarRacers"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	root.add_child(_button("Solo Race", _on_solo))
	root.add_child(_button("Host LAN Game", _on_host))

	_start_btn = _button("Start Race (host)", _on_start)
	_start_btn.visible = false
	root.add_child(_start_btn)

	var row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0, 60)
	row.add_child(_ip_edit)
	row.add_child(_button("Join", func(): _join(_ip_edit.text.strip_edges())))
	root.add_child(row)

	var found_label := Label.new()
	found_label.text = "Games found on your network:"
	root.add_child(found_label)
	_server_list = VBoxContainer.new()
	root.add_child(_server_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)

	Net.server_found.connect(_on_server_found)
	Net.peer_joined.connect(func(id: int): _status.text = "Player %d joined" % id)
	Net.connected.connect(func(): _status.text = "Connected. Waiting for the host to start...")
	Net.connection_failed.connect(func(): _status.text = "Connection failed")
	Net.start_listening()


func _exit_tree() -> void:
	Net.stop_listening()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.pressed.connect(cb)
	return b


func _on_solo() -> void:
	Net.leave()
	Net.start_race_for_all()


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Could not host (error %d)" % err
		return
	_start_btn.visible = true
	_status.text = "Hosting. Your IP: %s\nOthers on the same Wi-Fi will see this game automatically." % ", ".join(Net.local_ips())


func _on_start() -> void:
	Net.start_race_for_all()


func _join(ip: String) -> void:
	if ip == "":
		_status.text = "Enter the host IP"
		return
	var err := Net.join(ip)
	_status.text = "Connecting to %s..." % ip if err == OK else "Could not connect (error %d)" % err


func _on_server_found(ip: String, host_name: String) -> void:
	if _found.has(ip):
		return
	_found[ip] = true
	_server_list.add_child(_button("%s  (%s)" % [host_name, ip], func(): _join(ip)))
