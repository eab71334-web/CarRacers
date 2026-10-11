extends SceneTree
## Headless LAN test (run two or more instances on one machine).
## godot --headless --path . -s tests/lan_test.gd -- host <seconds> <enet_peers_to_wait_for>
## godot --headless --path . -s tests/lan_test.gd -- client <seconds>

var role := "host"
var secs := 8.0
var wait_for := 1
var t := 0.0
var joined := 0
var started := false
var reported := false
var net: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	secs = float(args[1])
	if args.size() > 2:
		wait_for = int(args[2])


func _setup() -> void:
	net = root.get_node("Net")
	if role == "host":
		print("[host] hosting: ", net.host())
		net.peer_joined.connect(func(id: int):
			joined += 1
			print("[host] peer joined ", id))
	else:
		print("[client] joining: ", net.join("127.0.0.1"))
		net.connected.connect(func(): print("[client] connected, id=", net.my_id()))
		net.connection_failed.connect(func(): print("[client] connection FAILED"))


func _process(delta: float) -> bool:
	if net == null:
		_setup()   # autoloads are not in the tree yet during _initialize
	t += delta
	if role == "host" and not started and joined >= wait_for and t > 1.0:
		started = true
		print("[host] starting race")
		net.start_race_for_all()
	var scene := current_scene
	if scene != null and scene.has_method("_back_to_menu"):
		Input.action_press("accelerate")
	if t >= secs and not reported:
		reported = true
		_report()
	if t >= secs + 3.0:
		quit()   # linger after reporting so the other instances still see this one when they report
	return false


func _report() -> void:
	var scene := current_scene
	if scene == null or not scene.has_method("_back_to_menu"):
		print("[%s] RESULT: race scene never loaded (scene=%s)" % [role, scene])
		return
	var ids: Array = scene.remote_cars.keys()
	ids.sort()
	var p: Vector3 = scene.local_car.global_position
	print("[%s] RESULT: my_id=%d remote_cars=%s local_pos=(%.1f, %.1f, %.1f) speed=%.1f" % [role, net.my_id(), str(ids), p.x, p.y, p.z, scene.local_car.speed])
