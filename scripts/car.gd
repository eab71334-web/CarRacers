extends CharacterBody3D
class_name Car
## Arcade car. The local car is driven by input; remote cars just follow network state.

const MAX_SPEED := 38.0
const ACCEL := 18.0
const BRAKE := 30.0
const FRICTION := 8.0
const STEER_SPEED := 2.2
const GRAVITY := 30.0

var is_local := true
var speed := 0.0
var car_color := Color(0.9, 0.28, 0.3)
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var start_transform := Transform3D.IDENTITY


func _ready() -> void:
	_build_visual()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.8, 3.6)
	shape.shape = box
	shape.position.y = 0.6
	add_child(shape)
	if is_local:
		var cam := Camera3D.new()
		cam.position = Vector3(0, 3.4, 7.5)
		cam.rotation_degrees = Vector3(-14, 0, 0)
		add_child(cam)
		cam.current = true
	else:
		target_pos = global_position
		target_yaw = rotation.y


func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = car_color
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 3.6)
	body.mesh = bm
	body.material_override = mat
	body.position.y = 0.6
	add_child(body)

	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.4, 0.5, 1.6)
	glass.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.6, 0.77, 1.0)
	glass.material_override = gmat
	glass.position = Vector3(0, 1.1, 0.2)
	add_child(glass)

	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.07, 0.07, 0.07)
	for x in [-1.0, 1.0]:
		for z in [-1.2, 1.2]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.4
			cm.bottom_radius = 0.4
			cm.height = 0.3
			w.mesh = cm
			w.material_override = wmat
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(x, 0.4, z)
			add_child(w)


func reset_to_start() -> void:
	global_transform = start_transform
	velocity = Vector3.ZERO
	speed = 0.0


func _physics_process(delta: float) -> void:
	if not is_local:
		global_position = global_position.lerp(target_pos, 0.3)
		rotation.y = lerp_angle(rotation.y, target_yaw, 0.3)
		return

	var throttle := Input.get_axis("brake", "accelerate")
	var steer := Input.get_axis("steer_right", "steer_left")

	if throttle > 0.0:
		speed = move_toward(speed, MAX_SPEED, ACCEL * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, -MAX_SPEED * 0.3, BRAKE * delta)
	else:
		speed = move_toward(speed, 0.0, FRICTION * delta)

	rotation.y += steer * STEER_SPEED * delta * clampf(speed / 10.0, -1.0, 1.0)

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Hitting a wall slows the car down.
	var real := get_real_velocity()
	speed = lerpf(speed, real.dot(fwd), 0.5)

	if global_position.y < -10.0:
		reset_to_start()
