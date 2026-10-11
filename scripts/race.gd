extends Node3D
## Oval race track built entirely in code, 3 laps, works solo or over LAN.

const CENTER_RADIUS := 70.0
const INNER_RADIUS := 50.0
const OUTER_RADIUS := 90.0
const SEGMENTS := 48
const TOTAL_LAPS := 3
const COLORS := [Color(0.9, 0.28, 0.3), Color(0.25, 0.55, 0.95), Color(0.95, 0.8, 0.2), Color(0.3, 0.8, 0.45), Color(0.7, 0.4, 0.9), Color(1, 0.55, 0.2), Color(0.9, 0.9, 0.9), Color(0.2, 0.9, 0.9)]

var local_car: Car
var remote_cars := {}
var lap := 0
var next_cp := 1
var finished := false
var race_time := 0.0
var _hud_label: Label
var _msg_label: Label


func _ready() -> void:
	_build_world()
	var ids: Array = [Net.my_id()]
	ids.append_array(multiplayer.get_peers())
	ids.sort()
	var slot := ids.find(Net.my_id())
	local_car = _make_car(slot, true)
	add_child(local_car)
	Net.remote_state.connect(_on_remote_state)
	Net.peer_left.connect(_on_peer_left)
	_build_hud()


func _make_car(slot: int, local: bool) -> Car:
	var c := Car.new()
	c.is_local = local
	c.car_color = COLORS[slot % COLORS.size()]
	var lane := 58.0 + float(slot % 4) * 7.0
	var row := float(slot / 4) * 8.0
	c.start_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(lane, 0.3, -row))
	c.transform = c.start_transform
	return c


func _physics_process(delta: float) -> void:
	if not finished:
		race_time += delta
	if local_car != null:
		Net.send_state(local_car.global_position, local_car.rotation.y, local_car.speed)
		_hud_label.text = "Lap %d/%d   %d km/h   %.1fs" % [mini(lap + 1, TOTAL_LAPS), TOTAL_LAPS, int(absf(local_car.speed) * 3.6), race_time]


func _on_remote_state(id: int, pos: Vector3, yaw: float, _speed: float) -> void:
	var c: Car = remote_cars.get(id)
	if c == null:
		c = _make_car(id % COLORS.size(), false)
		c.position = pos
		c.rotation.y = yaw
		remote_cars[id] = c
		add_child(c)
	c.target_pos = pos
	c.target_yaw = yaw


func _on_peer_left(id: int) -> void:
	if remote_cars.has(id):
		remote_cars[id].queue_free()
		remote_cars.erase(id)


func _on_checkpoint(body: Node3D, index: int) -> void:
	if body != local_car or finished:
		return
	if index != next_cp:
		return
	next_cp = (next_cp + 1) % 4
	if index == 0:
		lap += 1
		if lap >= TOTAL_LAPS:
			finished = true
			_msg_label.text = "FINISH!  %.2fs" % race_time


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)

	# Grass floor.
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(400, 1, 400)
	gshape.shape = gbox
	ground.add_child(gshape)
	var gmesh := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(400, 1, 400)
	gmesh.mesh = gm
	gmesh.material_override = _mat(Color(0.25, 0.55, 0.25))
	ground.add_child(gmesh)
	ground.position.y = -0.5
	add_child(ground)

	var road_mat := _mat(Color(0.2, 0.2, 0.22))
	var wall_mat := _mat(Color(0.85, 0.85, 0.85))
	var seg_len := 2.0 * PI * OUTER_RADIUS / SEGMENTS + 1.0
	var road_len := 2.0 * PI * CENTER_RADIUS / SEGMENTS + 1.0
	for i in SEGMENTS:
		var a := TAU * float(i) / SEGMENTS
		var radial := Vector3(cos(a), 0, sin(a))
		var rot := Basis(Vector3.UP, -a)

		var road := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(OUTER_RADIUS - INNER_RADIUS, 0.1, road_len)
		road.mesh = rm
		road.material_override = road_mat
		road.transform = Transform3D(rot, radial * CENTER_RADIUS + Vector3(0, 0.05, 0))
		add_child(road)

		for r in [INNER_RADIUS, OUTER_RADIUS]:
			var wall := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.0, 2.0, seg_len)
			cs.shape = bs
			wall.add_child(cs)
			var wm := MeshInstance3D.new()
			var wbm := BoxMesh.new()
			wbm.size = bs.size
			wm.mesh = wbm
			wm.material_override = wall_mat
			wall.add_child(wm)
			wall.transform = Transform3D(rot, radial * r + Vector3(0, 1.0, 0))
			add_child(wall)

	# Four checkpoints around the loop; checkpoint 0 is the start/finish line.
	for i in 4:
		var a := TAU * float(i) / 4.0
		var radial := Vector3(cos(a), 0, sin(a))
		var area := Area3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(OUTER_RADIUS - INNER_RADIUS, 6.0, 2.0)
		cs.shape = bs
		area.add_child(cs)
		area.transform = Transform3D(Basis(Vector3.UP, -a), radial * CENTER_RADIUS + Vector3(0, 3, 0))
		area.body_entered.connect(_on_checkpoint.bind(i))
		add_child(area)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_hud_label = Label.new()
	_hud_label.position = Vector2(20, 12)
	_hud_label.add_theme_font_size_override("font_size", 28)
	layer.add_child(_hud_label)

	_msg_label = Label.new()
	_msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_label.position = Vector2(-120, 80)
	_msg_label.add_theme_font_size_override("font_size", 48)
	layer.add_child(_msg_label)

	var menu := Button.new()
	menu.text = "Menu"
	menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu.position = Vector2(-120, 12)
	menu.custom_minimum_size = Vector2(100, 50)
	menu.pressed.connect(_back_to_menu)
	layer.add_child(menu)

	# On-screen touch controls (also work with a mouse).
	_touch_button(layer, "<", "steer_left", Vector2(30, -150), Control.PRESET_BOTTOM_LEFT)
	_touch_button(layer, ">", "steer_right", Vector2(190, -150), Control.PRESET_BOTTOM_LEFT)
	_touch_button(layer, "GAS", "accelerate", Vector2(-190, -170), Control.PRESET_BOTTOM_RIGHT)
	_touch_button(layer, "BRAKE", "brake", Vector2(-190, -80), Control.PRESET_BOTTOM_RIGHT)


func _touch_button(layer: CanvasLayer, text: String, action: String, pos: Vector2, preset: int) -> void:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(preset)
	b.position = pos
	b.custom_minimum_size = Vector2(150, 70)
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): Input.action_press(action))
	b.button_up.connect(func(): Input.action_release(action))
	layer.add_child(b)


func _back_to_menu() -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right"]:
		Input.action_release(a)
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
