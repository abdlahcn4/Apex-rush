extends Node3D

## Apex Rush — Godot vertical slice.
## World setup mirroring buildWorldScene() in public/js/game.js: sunset sky, warm sun,
## distant mountains, ground plane, Sunset Ring circuit, one car, chase camera, HUD.

const TRACK_PATH := "res://data/trackdata.json"

var quality := 2

var track: ApexTrack
var player: ApexVehicle
var cam: ChaseCamera
var hud: RaceHUD

var ground: MeshInstance3D
var mountains: MultiMeshInstance3D


func _ready() -> void:
	_load_track()
	_build_environment()
	ground = _build_ground()
	mountains = _build_mountains()
	if track == null or track.N <= 1:
		push_error("Track failed to load - check res://data/trackdata.json")
		return
	track.build(self, quality)
	_spawn_player()
	_setup_camera()
	_setup_hud()
	if hud != null:
		hud.toast("SUNSET RING — FREE DRIVE", 2.0)


# --------------------------------------------------------------------------- #
# setup
# --------------------------------------------------------------------------- #

func _load_track() -> void:
	var text := FileAccess.get_file_as_string(TRACK_PATH)
	if text.is_empty():
		push_error("Cannot read " + TRACK_PATH)
		return
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Malformed track JSON")
		return
	var points: Array = data.get("points", [])
	var radius := float(data.get("checkpointRadius", 26.0))
	track = ApexTrack.new(points, radius)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2c5d9e")
	sky_mat.sky_horizon_color = Color("ffb070")
	sky_mat.sky_curve = 0.15
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = Color("f0a878")
	sky_mat.ground_bottom_color = Color("4a4636")
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("f0a878")
	env.fog_density = 0.00035
	env.fog_sun_scatter = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.78, 0.56)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.rotation_degrees = Vector3(-14.0, 150.0, 0.0)
	add_child(sun)


func _build_ground() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.20)
	mat.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(120.0, 120.0, 1.0)

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.05, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_mountains() -> MultiMeshInstance3D:
	# unit cone (CylinderMesh with a zero top radius, then scaled per instance)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var count := 46

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = count
	for i in range(count):
		var a := (float(i) / float(count)) * TAU + rng.randf() * 0.1
		var dist := 2300.0 + rng.randf() * 900.0
		var hgt := 220.0 + rng.randf() * 520.0
		var rad := 260.0 + rng.randf() * 420.0
		var basis := Basis().scaled(Vector3(rad, hgt, rad))
		var pos := Vector3(cos(a) * dist, hgt * 0.5 - 20.0, sin(a) * dist)
		mm.set_instance_transform(i, Transform3D(basis, pos))

	var mat := MeshKit.solid(Color(0.36, 0.33, 0.47), 1.0)
	var inst := MultiMeshInstance3D.new()
	inst.name = "Mountains"
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _spawn_player() -> void:
	var start: Dictionary = track.point_at(-12.0, 3.4)
	player = ApexVehicle.new("vortex", Color("2ecc40"), quality)
	add_child(player)
	player.reset(float(start.x), float(start.z), atan2(float(start.tx), float(start.tz)))


func _setup_camera() -> void:
	cam = ChaseCamera.new()
	cam.name = "ChaseCamera"
	add_child(cam)
	cam.setup(player)


func _setup_hud() -> void:
	hud = RaceHUD.new()
	hud.name = "HUD"
	add_child(hud)


# --------------------------------------------------------------------------- #
# loop
# --------------------------------------------------------------------------- #

func _physics_process(delta: float) -> void:
	if player == null:
		return
	player.update_physics(delta, _read_input(), track, false)
	player.apply_visual(delta)


func _process(delta: float) -> void:
	if player == null or cam == null:
		return
	cam.update_camera(delta, player)
	if hud != null:
		hud.update_stats(absf(player.vF) * 3.6, player.gear, player.rpm, player.drift)
	# keep world followers centred on the camera
	if ground != null:
		ground.global_position = Vector3(
			roundf(cam.global_position.x / 10.0) * 10.0,
			-0.05,
			roundf(cam.global_position.z / 10.0) * 10.0)
	if mountains != null:
		mountains.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)


func _read_input() -> Dictionary:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0

	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		throttle = 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		brake = 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		steer += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		steer -= 1.0

	var analog := false
	var hand := Input.is_physical_key_pressed(KEY_SPACE)
	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var pad: int = pads[0]
		var axis := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		if absf(axis) > 0.12:
			steer = axis
			analog = true
		var trig := Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)
		if trig > 0.1:
			throttle = maxf(throttle, trig)
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_A):
			throttle = 1.0
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_B):
			brake = 1.0
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_X):
			hand = true

	return {
		"throttle": throttle,
		"brake": brake,
		"steer": clampf(steer, -1.0, 1.0),
		"analog": analog,
		"handbrake": hand,
	}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				_reset_car()
			KEY_C:
				_cycle_camera()


func _reset_car() -> void:
	if player == null or track == null:
		return
	var pr: Dictionary = track.project(player.x, player.z, player.hint)
	var lane := float(ApexTrack.LANES[0])
	for l in ApexTrack.LANES:
		if absf(float(l) - float(pr.lat)) < absf(lane - float(pr.lat)):
			lane = float(l)
	var pt: Dictionary = track.point_at(float(pr.s), lane)
	player.reset(float(pt.x), float(pt.z), atan2(float(pt.tx), float(pt.tz)))
	if cam != null:
		cam.cam_yaw = player.h
	if hud != null:
		hud.toast("CAR RESET", 0.8)


func _cycle_camera() -> void:
	if cam == null:
		return
	var label: String = cam.cycle()
	if hud != null:
		hud.toast(label, 0.9)
