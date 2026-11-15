class_name ApexVehicle
extends Node3D

## Port of Vehicle from public/js/vehicle.js — the same arcade drift model, in 2D
## (x, z) plus a heading, with no physics engine involved. Forward = (sin h, cos h),
## which matches Godot's +Z forward and rotation.y = h.

const WALL := 11.5
const CAR_HALF_W := 1.0
const GEAR_TOPS := [0.17, 0.32, 0.47, 0.62, 0.79, 1.0]

var id := "vortex"
var spec: Dictionary = {}
var stats: Dictionary = {}
var model: Dictionary = {}

# planar state
var x := 0.0
var z := 0.0
var h := 0.0
var vx := 0.0
var vz := 0.0

# controls
var steer := 0.0
var throttle := 0.0
var brake_in := 0.0
var hand := false

# derived
var speed := 0.0
var vF := 0.0
var vR := 0.0
var drift := 0.0
var impact := 0.0
var last_accel := 0.0

# presentation
var rpm := 900.0
var gear := "N"
var pitch := 0.0
var roll := 0.0
var pv := 0.0
var rv := 0.0
var wheel_rot := 0.0

# nitro (boost) state, surfaced to the HUD and the audio director
var nitro_charge := 1.0
var nitro_active := false

var hint := -1


func _init(car_id: String = "vortex", color: Color = Color("2ecc40"), quality := 2) -> void:
	id = car_id
	spec = CarBuilder.spec(car_id)
	stats = CarBuilder.stats(car_id, {})
	model = CarBuilder.build(car_id, color, quality)
	add_child(model.root)
	name = "PlayerCar"


func reset(nx: float, nz: float, nh: float) -> void:
	x = nx
	z = nz
	h = nh
	vx = 0.0
	vz = 0.0
	steer = 0.0
	drift = 0.0
	hint = -1
	nitro_active = false
	rpm = 900.0
	gear = "N"
	vF = 0.0
	vR = 0.0
	apply_visual(0.0)


func forward() -> Vector2:
	return Vector2(sin(h), cos(h))


## inp: {throttle, brake, steer, analog, handbrake}
func update_physics(dt: float, inp: Dictionary, track, frozen := false) -> void:
	var top := float(stats.top)
	var accel_rate := float(stats.accel)
	var brake_rate := float(stats.brake)
	var handling := float(stats.handling)

	var fx := sin(h)
	var fz := cos(h)
	var vf := vx * fx + vz * fz
	var spd := absf(vf)

	# --- steering smoothing (speed sensitive)
	var target_steer := 0.0 if frozen else float(inp.steer)
	var rate := 10.0 if bool(inp.analog) else (6.0 if is_zero_approx(target_steer) else 3.2)
	steer += clampf(target_steer - steer, -rate * dt, rate * dt)
	throttle = 0.0 if frozen else float(inp.throttle)
	brake_in = 0.0 if frozen else float(inp.brake)
	hand = (not frozen) and bool(inp.handbrake)

	# --- nitro: burns charge while held, trickles back when released
	nitro_active = (not frozen) and bool(inp.get("nitro", false)) and throttle > 0.0 and nitro_charge > 0.02
	if nitro_active:
		top *= 1.12
		accel_rate *= 1.55
		nitro_charge = maxf(0.0, nitro_charge - dt * 0.30)
	else:
		nitro_charge = minf(1.0, nitro_charge + dt * 0.06)

	# --- yaw
	var dir := 1.0 if vf >= 0.0 else -1.0
	var turn := handling * 2.15 / (1.0 + spd / 40.0) * minf(1.0, spd / 7.0)
	var yaw := -steer * turn * dir
	if hand and spd > 8.0:
		yaw *= 1.45
	if drift > 0.25:
		yaw *= 1.15
	h += yaw * dt

	# --- rebuild local velocity in the new heading (this is what makes it drift)
	var nfx := sin(h)
	var nfz := cos(h)
	var nrx := -nfz
	var nrz := nfx
	vf = vx * nfx + vz * nfz
	var vr := vx * nrx + vz * nrz

	# --- longitudinal
	var acc := 0.0
	if throttle > 0.0:
		if vf < -0.5:
			acc += brake_rate * throttle
		else:
			var f := maxf(0.0, 1.0 - pow(maxf(0.0, vf) / top, 2.2))
			acc += accel_rate * throttle * (0.35 + 0.65 * f) * (1.0 if vf < top else 0.0)
	if brake_in > 0.0:
		if vf > 0.5:
			acc -= brake_rate * brake_in
		elif vf > -14.0:
			acc -= 7.0 * brake_in
	if hand:
		acc -= signf(vf) * 7.0
	# drag + rolling resistance
	acc -= vf * absf(vf) * 0.0008 + signf(vf) * (0.3 if throttle > 0.0 else 1.6)

	var prev_vf := vf
	vf += acc * dt
	if throttle == 0.0 and brake_in == 0.0 and absf(vf) < 0.3:
		vf = 0.0
	if signf(prev_vf) != signf(vf) and absf(prev_vf) > 0.0001 and brake_in == 0.0 and throttle == 0.0:
		vf = 0.0

	# --- lateral grip
	var grip := 7.5 * handling
	if hand:
		grip = 1.1
	elif absf(vr) > 5.0:
		grip *= 0.55
	vr *= exp(-grip * dt)
	drift = minf(1.0, absf(vr) / maxf(6.0, absf(vf) * 0.5))

	vx = nfx * vf + nrx * vr
	vz = nfz * vf + nrz * vr
	x += vx * dt
	z += vz * dt
	vF = vf
	vR = vr
	speed = sqrt(vx * vx + vz * vz)
	last_accel = acc

	# --- walls
	impact = 0.0
	if track != null:
		var p: Dictionary = track.project(x, z, hint)
		hint = int(p.i)
		var lat := float(p.lat)
		var lim := WALL - CAR_HALF_W
		if absf(lat) > lim:
			var nx: float = p.nx
			var nz: float = p.nz
			var tx: float = p.tx
			var tz: float = p.tz
			var side := signf(lat)
			var pen := absf(lat) - lim
			x -= nx * side * pen
			z -= nz * side * pen
			var vn := (vx * nx + vz * nz) * side
			if vn > 0.0:
				vx -= nx * side * vn * 1.35
				vz -= nz * side * vn * 1.35
				impact = vn
			vx *= 0.992
			vz *= 0.992
			# nudge the heading along the wall so the car does not stick
			var th := atan2(tx, tz)
			if vx * tx + vz * tz < 0.0:
				th += PI
			var d := th - h
			d = atan2(sin(d), cos(d))
			h += d * minf(1.0, dt * 2.5)

	# --- gears / rpm
	var kmh := absf(vf) * 3.6
	if vf < -0.5:
		gear = "R"
		rpm = 1500.0 + absf(vf) * 220.0
	elif kmh < 1.0 and throttle == 0.0:
		gear = "N"
		rpm += (900.0 - rpm) * minf(1.0, dt * 5.0)
	else:
		var frac := maxf(0.0, vf) / top
		var g := 5
		for i in range(GEAR_TOPS.size()):
			if frac < float(GEAR_TOPS[i]):
				g = i
				break
		var lo := 0.0 if g == 0 else float(GEAR_TOPS[g - 1])
		var hi := float(GEAR_TOPS[g])
		var r := 0.0 if hi <= lo else (frac - lo) / (hi - lo)
		gear = str(g + 1)
		var rpm_target := 1300.0 + r * 6200.0 + (900.0 if drift > 0.4 else 0.0)
		rpm += (rpm_target - rpm) * minf(1.0, dt * 10.0)
	if throttle == 0.0 and rpm > 1100.0:
		rpm -= dt * 800.0


## Push the planar state into the scene graph: wheels, steering, suspension, brake lights.
func apply_visual(dt: float) -> void:
	position = Vector3(x, 0.0, z)
	rotation = Vector3(0.0, h, 0.0)

	var wr := maxf(0.1, float(model.wr))
	wheel_rot += (vF / wr) * dt
	for w in model.wheels:
		var spin_node: Node3D = w.spin
		spin_node.rotation = Vector3(wheel_rot, 0.0, 0.0)
		if bool(w.front):
			var pivot_node: Node3D = w.pivot
			pivot_node.rotation = Vector3(0.0, -steer * 0.5, 0.0)

	# suspension spring
	var pt := clampf(-last_accel * 0.0028, -0.05, 0.05)
	var lat := -steer * minf(1.0, absf(vF) / 30.0) * 6.0 - vR * 0.3
	var rt := clampf(lat * 0.008, -0.06, 0.06)
	if dt > 0.0:
		pv += ((pt - pitch) * 90.0 - pv * 11.0) * dt
		rv += ((rt - roll) * 90.0 - rv * 11.0) * dt
		pitch += pv * dt
		roll += rv * dt
	var body_node: Node3D = model.body
	body_node.rotation = Vector3(pitch, 0.0, roll)
	body_node.position = Vector3(0.0, sin(Time.get_ticks_msec() * 0.02 + x) * 0.004 * minf(1.0, absf(vF) / 20.0), 0.0)

	var tail: StandardMaterial3D = model.tail_mat
	tail.emission_energy_multiplier = 3.2 if brake_in > 0.0 else 0.9
