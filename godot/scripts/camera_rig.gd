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

# --- player-controlled orbit ------------------------------------------------ #
## Dragging turns the camera all the way around the car (a full 360 deg), which is what
## the chase cam was missing. While you keep driving forwards it eases back behind the
## car after a couple of seconds, so a quick look never leaves you driving blind.
var orbit_yaw := 0.0
var orbit_pitch := 0.0

const ORBIT_SENS := 0.0075
const ORBIT_PITCH_MIN := -0.30
const ORBIT_PITCH_MAX := 0.85
const ORBIT_RETURN_DELAY := 2.5

# --- smoothing -------------------------------------------------------------- #
## Everything the camera chases is filtered, because the raw car state carries the
## suspension and tyre physics at 60 Hz: feeding that straight into a look_at is what made
## the camera vibrate at speed.
var _car := Vector2.ZERO
var _speed := 0.0
var _dist := 6.3
var _height := 2.25
var _look_point := Vector3.ZERO
var _look_ready := false
var _orbit_idle := 99.0


func _ready() -> void:
	near = 0.1
	far = 6000.0
	fov = base_fov
	current = true


func orbit(relative: Vector2) -> void:
	orbit_yaw = wrapf(orbit_yaw - relative.x * ORBIT_SENS, -PI, PI)
	orbit_pitch = clampf(orbit_pitch + relative.y * ORBIT_SENS, ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
	_orbit_idle = 0.0


func reset_orbit() -> void:
	orbit_yaw = 0.0
	orbit_pitch = 0.0


func setup(v: ApexVehicle) -> void:
	target = v
	cam_yaw = v.h
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	_car = Vector2(v.x, v.z)
	_look_ready = false
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
	_speed = lerpf(_speed, kmh, minf(1.0, dt * 1.8))
	_car = _car.lerp(Vector2(v.x, v.z), minf(1.0, dt * 22.0))
	_orbit_idle += dt

	# let go of the drag and start driving: drift back behind the car
	if _orbit_idle > ORBIT_RETURN_DELAY and kmh > 4.0:
		var back := minf(1.0, dt * 1.4)
		orbit_yaw = lerpf(orbit_yaw, 0.0, back)
		orbit_pitch = lerpf(orbit_pitch, 0.0, back * 0.7)

	var want_yaw := v.h + orbit_yaw
	var dyaw := want_yaw - cam_yaw
	dyaw = atan2(sin(dyaw), cos(dyaw))
	var rate := 30.0 if mode == 2 else (16.0 if _orbit_idle < ORBIT_RETURN_DELAY else 5.0)
	cam_yaw += dyaw * minf(1.0, dt * rate)

	var car_x := _car.x
	var car_z := _car.y

	if mode == 2:
		var f2 := Vector2(sin(cam_yaw), cos(cam_yaw))
		var zf := cab_f + 0.35
		var eye := Vector3(car_x + f2.x * zf, belt_y + 0.42 + orbit_pitch * 0.5, car_z + f2.y * zf)
		global_position = global_position.lerp(eye, minf(1.0, dt * 26.0))
		var look := Vector3(car_x + f2.x * 30.0, belt_y + 0.1 + orbit_pitch * 8.0, car_z + f2.y * 30.0)
		_look(look)
	else:
		var far_mode := mode == 1
		var want_dist := (9.5 if far_mode else 6.3) * cam_dist + _speed * 0.0045
		var want_h := (3.4 if far_mode else 2.25) * cam_height + orbit_pitch * 4.5
		_dist = lerpf(_dist, want_dist, minf(1.0, dt * 3.0))
		_height = lerpf(_height, maxf(1.2, want_h), minf(1.0, dt * 4.0))

		var fy := Vector2(sin(cam_yaw), cos(cam_yaw))
		var target_pos := Vector3(car_x - fy.x * _dist, _height, car_z - fy.y * _dist)
		var k := (1.0 - exp(-dt * 11.0)) if dt > 0.0 else 1.0
		global_position = global_position.lerp(target_pos, k)

		var want_look := Vector3(car_x + fy.x * 4.0, 1.1 + orbit_pitch * 2.4, car_z + fy.y * 4.0)
		if not _look_ready:
			_look_point = want_look
			_look_ready = true
		_look_point = _look_point.lerp(want_look, minf(1.0, dt * 14.0))
		_look(_look_point)

	# speed-sensitive FOV, driven by the filtered speed so it cannot pulse
	var target_fov := base_fov
	if motion:
		target_fov += minf(14.0, maxf(0.0, _speed - 60.0) * 0.055)
	if absf(fov - target_fov) > 0.05:
		fov = lerpf(fov, target_fov, minf(1.0, dt * 4.0))


func _look(at: Vector3) -> void:
	if global_position.distance_to(at) < 0.05:
		return
	look_at(at, Vector3.UP)
