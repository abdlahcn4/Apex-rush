class_name ChaseCamera
extends Camera3D

## Port of updateCamera() / cycleCamera() from public/js/game.js.
## 0 = chase, 1 = far chase, 2 = first person. Heading is followed with a lag so the
## car can rotate a little under the camera while drifting.

var target: ApexVehicle
var mode := 0
var cam_yaw := 0.0
var cam_dist := 1.0
var cam_height := 1.0
var base_fov := 68.0
var motion := true

var belt_y := 0.86
var cab_f := 0.75


func _ready() -> void:
	near = 0.1
	far = 6000.0
	fov = base_fov
	current = true


func setup(v: ApexVehicle) -> void:
	target = v
	cam_yaw = v.h
	var b: Dictionary = v.spec.body
	belt_y = float(b.beltY)
	cab_f = float(b.cabF)
	var f := Vector2(sin(v.h), cos(v.h))
	global_position = Vector3(v.x - f.x * 7.0, 3.0, v.z - f.y * 7.0)
	look_at(Vector3(v.x, 1.0, v.z), Vector3.UP)


func cycle() -> String:
	mode = (mode + 1) % 3
	return ["CHASE CAM", "FAR CHASE CAM", "FIRST PERSON"][mode]


func update_camera(dt: float, v: ApexVehicle) -> void:
	if v == null:
		return
	var kmh := absf(v.vF) * 3.6

	var dyaw := v.h - cam_yaw
	dyaw = atan2(sin(dyaw), cos(dyaw))
	cam_yaw += dyaw * minf(1.0, dt * (30.0 if mode == 2 else 5.0))

	if mode == 2:
		var f2 := Vector2(sin(v.h), cos(v.h))
		var zf := cab_f + 0.35
		global_position = Vector3(v.x + f2.x * zf, belt_y + 0.42, v.z + f2.y * zf)
		_look(Vector3(v.x + f2.x * 30.0, belt_y + 0.1, v.z + f2.y * 30.0))
	else:
		var far_mode := mode == 1
		var dist := (9.5 if far_mode else 6.3) * cam_dist + kmh * 0.004
		var hgt := (3.4 if far_mode else 2.25) * cam_height
		var fy := Vector2(sin(cam_yaw), cos(cam_yaw))
		var tx := v.x - fy.x * dist
		var tz := v.z - fy.y * dist
		var k := (1.0 - exp(-dt * 14.0)) if dt > 0.0 else 1.0
		var p := global_position
		p.x += (tx - p.x) * k
		p.z += (tz - p.z) * k
		p.y += (hgt - p.y) * k
		global_position = p
		_look(Vector3(v.x + fy.x * 4.0, 1.1 * maxf(0.8, cam_height * 0.8), v.z + fy.y * 4.0))

	# speed-sensitive FOV, same curve as the web build
	var target_fov := base_fov
	if motion:
		target_fov += minf(14.0, maxf(0.0, kmh - 60.0) * 0.055)
	if absf(fov - target_fov) > 0.05:
		fov = lerpf(fov, target_fov, minf(1.0, dt * 4.0))


func _look(at: Vector3) -> void:
	if global_position.distance_to(at) < 0.05:
		return
	look_at(at, Vector3.UP)
