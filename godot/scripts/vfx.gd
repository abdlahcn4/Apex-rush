class_name VehicleVFX
extends Node3D

## Effects layer for the hero car. Everything is anchored to authored geometry:
##   - backfire flames fire from the two exhaust tips of the model, never from thin air
##   - nitro flames use the same tips with a blue palette
##   - tyre smoke is anchored to the rear wheel pivots and driven by slip
## CPU particles are used on purpose: GPUParticles3D is not available in the GL
## compatibility renderer that both the phone and the PC build run on.

const POP_COOLDOWN := 0.16
const RPM_POP := 4200.0
const RPM_BACKFIRE := 4600.0

var _exhaust: Array = []
var _rear_wheels: Array = []
var _flame: Array = []
var _nitro: Array = []
var _smoke: Array = []
var _pop_cooldown := 0.0
var _was_gear := ""
var _was_throttle := 0.0
var _nitro_on := false


func setup(model: Dictionary, car_body: Node3D) -> void:
	name = "VFX"
	# the anchors live under the model's GroundFix, so take them from there
	var exhaust_src: Array = model.get("exhaust", [])
	for node in exhaust_src:
		var anchor := node as Node3D
		if anchor == null:
			continue
		_exhaust.append(anchor)
		_flame.append(_make_flame(anchor, false))
		_nitro.append(_make_flame(anchor, true))

	for w in model.get("wheels", []):
		var wheel: Dictionary = w
		if bool(wheel.get("front", false)):
			continue
		var pivot := wheel.get("pivot") as Node3D
		if pivot != null:
			_rear_wheels.append(pivot)
			_smoke.append(_make_smoke(pivot))


func _make_flame(anchor: Node3D, blue: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = not blue
	p.amount = 10 if not blue else 16
	p.lifetime = 0.22 if not blue else 0.2
	p.explosiveness = 0.85 if not blue else 0.2
	p.randomness = 0.6
	p.local_coords = false
	p.direction = Vector3(0.0, 0.0, -1.0)
	p.spread = 16.0
	p.flatness = 0.4
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.25
	p.mesh = _quad(0.16)

	var ramp := Gradient.new()
	if blue:
		ramp.set_color(0, Color(0.55, 0.85, 1.0, 0.95))
		ramp.set_color(1, Color(0.15, 0.35, 1.0, 0.0))
	else:
		ramp.set_color(0, Color(1.0, 0.92, 0.55, 0.95))
		ramp.set_color(1, Color(1.0, 0.28, 0.05, 0.0))
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	p.color_ramp = ramp
	p.scale_amount_curve = curve
	p.material_override = _glow_material(Color(1.0, 1.0, 1.0), blue)
	anchor.add_child(p)
	return p


func _make_smoke(pivot: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.1
	p.explosiveness = 0.1
	p.randomness = 0.5
	p.local_coords = false
	p.direction = Vector3(0.0, 0.35, -0.6)
	p.spread = 35.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.8
	p.mesh = _quad(0.5)

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.87, 0.9, 0.5))
	ramp.set_color(1, Color(0.72, 0.74, 0.8, 0.0))
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.0))
	p.color_ramp = ramp
	p.scale_amount_curve = curve
	p.material_override = _smoke_material()
	pivot.add_child(p)
	return p


func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _glow_material(_tint: Color, blue: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.75, 0.9, 1.0) if blue else Color(1.0, 0.85, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.45, 0.75, 1.0) if blue else Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 2.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m


func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.88, 0.9, 0.94)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func update(v: ApexVehicle, dt: float) -> void:
	if v == null:
		return
	_pop_cooldown = maxf(0.0, _pop_cooldown - dt)

	var gear_changed := v.gear != _was_gear and _was_gear != ""
	var upshift := gear_changed and v.rpm > RPM_POP
	var lifted := _was_throttle > 0.5 and v.throttle < 0.1 and v.rpm > RPM_BACKFIRE

	# exhaust pop: on an upshift under load, and when the throttle is lifted high in the revs
	if (upshift or lifted) and _pop_cooldown <= 0.0:
		_pop_cooldown = POP_COOLDOWN
		for p in _flame:
			var flame := p as CPUParticles3D
			if flame == null:
				continue
			flame.amount = 8 if lifted else 12
			flame.restart()
			flame.emitting = true

	# nitro: blue flames for as long as the bottle is open
	var want_nitro := v.nitro_active
	if want_nitro != _nitro_on:
		_nitro_on = want_nitro
		for p in _nitro:
			var jet := p as CPUParticles3D
			if jet != null:
				jet.emitting = want_nitro

	# tyre smoke: rear wheels only, driven by slip and handbrake
	var slip := clampf(v.drift, 0.0, 1.0)
	if v.hand and absf(v.vF) > 5.0:
		slip = maxf(slip, 0.8)
	var smoking := slip > 0.22 and absf(v.vF) > 4.0
	for p in _smoke:
		var s := p as CPUParticles3D
		if s == null:
			continue
		if s.emitting != smoking:
			s.emitting = smoking
		if smoking:
			s.amount = int(lerpf(8.0, 22.0, slip))

	_was_gear = v.gear
	_was_throttle = v.throttle
