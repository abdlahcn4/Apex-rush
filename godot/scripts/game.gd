extends Node3D

## Apex Rush — Godot build.
## Flow: main menu -> garage / circuit select -> race (countdown, laps, results).
## The world is rebuilt per race so each circuit gets its own theme, sky, surface and
## props. Physics, camera and HUD systems are the ones ported from the Three.js build.

const MAPS_PATH := "res://data/maps.json"
const LAPS_TOTAL := 3
const COUNTDOWN_FROM := 3.2

var quality := 2

var maps: Array = []
var map_def: Dictionary = {}
var car_id := "vortex"
var map_id := "sunset_ring"

var world: Node3D
var track: ApexTrack
var player: ApexVehicle
var cam: ChaseCamera
var hud: RaceHUD
var touch: TouchControls
var audio: AudioDirector
var ui: GameUI

var ground: MeshInstance3D
var mountains: MultiMeshInstance3D

var headlights := false
var racing := false
var paused := false
var countdown := 0.0
var go_flash := 0.0

var lap := 1
var lap_time := 0.0
var best_lap := 0.0
var total_time := 0.0
var last_s := -1.0


func _ready() -> void:
	_load_maps()
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)

	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(_car_list(), _map_list())
	ui.race_requested.connect(_start_race)
	ui.resume_requested.connect(_resume)
	ui.restart_requested.connect(_restart)
	ui.left_race.connect(_leave_race)
	ui.show_main()

	# CI / smoke runs pass `-- --autotest` so the headless build actually drives the
	# world instead of stopping on the menu.
	if "--autotest" in OS.get_cmdline_user_args():
		_start_race(map_id, car_id)
		_report_autotest()


# --------------------------------------------------------------------------- #
# data
# --------------------------------------------------------------------------- #

func _load_maps() -> void:
	var text := FileAccess.get_file_as_string(MAPS_PATH)
	if text.is_empty():
		push_error("Cannot read " + MAPS_PATH)
		return
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Malformed maps JSON")
		return
	maps = data.get("maps", [])
	if maps.is_empty():
		push_error("No circuits in " + MAPS_PATH)


func _car_list() -> Array:
	var out: Array = []
	for id in CarBuilder.ORDER:
		var s := CarBuilder.spec(id)
		out.append({
			"id": id,
			"name": String(s.name),
			"tier": int(s.tier),
			"top": float(s.top),
			"accel": float(s.accel),
			"brake": float(s.brake),
			"handling": float(s.handling),
			"color": String(s.color),
			"model": String(AssetLibrary.CAR_FILES.get(id, "")),
		})
	return out


func _map_list() -> Array:
	var out: Array = []
	for m in maps:
		out.append({
			"id": String(m.get("id", "")),
			"name": String(m.get("name", "")),
			"grade": String(m.get("grade", "Circuit")),
			"blurb": String(m.get("blurb", "")),
		})
	return out


func _find_map(id: String) -> Dictionary:
	for m in maps:
		if String(m.get("id", "")) == id:
			return m
	return maps[0] if not maps.is_empty() else {}


# --------------------------------------------------------------------------- #
# race lifecycle
# --------------------------------------------------------------------------- #

func _start_race(next_map: String, next_car: String) -> void:
	_teardown_world()
	map_id = next_map if not next_map.is_empty() else map_id
	car_id = next_car if not next_car.is_empty() else car_id
	map_def = _find_map(map_id)

	ui.show_loading("LOADING")
	_build_world()

	racing = true
	paused = false
	countdown = COUNTDOWN_FROM
	go_flash = 0.0
	lap = 1
	lap_time = 0.0
	best_lap = 0.0
	total_time = 0.0
	last_s = -1.0
	ui.show_race()
	if hud != null:
		hud.set_title(String(map_def.get("name", "APEX RUSH")).to_upper())
		hud.toast(String(map_def.get("name", "")) + " — GET READY", 1.6)


func _restart() -> void:
	_start_race(map_id, car_id)


func _leave_race() -> void:
	racing = false
	paused = false
	_teardown_world()


func _teardown_world() -> void:
	if world != null:
		world.queue_free()
		world = null
	track = null
	player = null
	cam = null
	hud = null
	touch = null
	ground = null
	mountains = null


func _pause() -> void:
	if not racing or paused:
		return
	paused = true
	ui.show_pause()


func _resume() -> void:
	paused = false
	ui.show_race()


# --------------------------------------------------------------------------- #
# world construction
# --------------------------------------------------------------------------- #

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	var points: Array = map_def.get("points", [])
	if points.size() < 4:
		push_error("Circuit has too few control points: " + map_id)
		return
	var radius := float(map_def.get("checkpointRadius", 26.0))
	track = ApexTrack.new(points, radius)
	track.theme = _theme()

	_build_environment()
	ground = _build_ground()
	mountains = _build_mountains()
	track.build(world, quality)
	_spawn_player()
	_setup_camera()
	_setup_hud()

	headlights = bool((map_def.get("theme", {}) as Dictionary).get("night", false))
	if headlights and player != null:
		CarBuilder.set_headlights(player.model, true)


func _theme() -> Dictionary:
	var t: Variant = map_def.get("theme", {})
	if typeof(t) == TYPE_DICTIONARY:
		return t as Dictionary
	return {}


func _build_environment() -> void:
	var theme := _theme()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(String(theme.get("sky_top", "#2c5d9e")))
	sky_mat.sky_horizon_color = Color(String(theme.get("sky_horizon", "#ffb070")))
	sky_mat.sky_curve = 0.15
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = Color(String(theme.get("fog", "#f0a878")))
	sky_mat.ground_bottom_color = Color(0.18, 0.17, 0.15)
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var night := bool(theme.get("night", false))
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.25 if night else 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(theme.get("ambient", 1.0))
	env.fog_enabled = true
	env.fog_light_color = Color(String(theme.get("fog", "#f0a878")))
	env.fog_density = float(theme.get("fog_density", 0.00035))
	env.fog_sun_scatter = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.9 if night else 0.35
	env.glow_bloom = 0.12 if night else 0.05
	env.ssao_enabled = false
	env.adjustment_enabled = night
	if night:
		env.adjustment_brightness = 1.08
		env.adjustment_contrast = 1.06

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(String(theme.get("sun", "#ffc78e")))
	sun.light_energy = float(theme.get("sun_energy", 2.0))
	sun.shadow_enabled = not night
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 260.0
	var rot: Array = theme.get("sun_rot", [-14.0, 150.0, 0.0])
	sun.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	world.add_child(sun)


func _build_ground() -> MeshInstance3D:
	var theme := _theme()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.98, 0.9)
	mat.roughness = 1.0
	mat.albedo_texture = AssetLibrary.texture(String(theme.get("ground", "grass")))
	mat.uv1_scale = Vector3(90.0, 90.0, 1.0)

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.05, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi


func _build_mountains() -> MultiMeshInstance3D:
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
	world.add_child(inst)
	return inst


func _spawn_player() -> void:
	var start: Dictionary = track.point_at(-12.0, 3.4)
	var spec := CarBuilder.spec(car_id)
	player = ApexVehicle.new(car_id, Color(String(spec.color)), quality)
	world.add_child(player)
	player.reset(float(start.x), float(start.z), atan2(float(start.tx), float(start.tz)))


func _setup_camera() -> void:
	cam = ChaseCamera.new()
	cam.name = "ChaseCamera"
	world.add_child(cam)
	cam.setup(player)


func _setup_hud() -> void:
	hud = RaceHUD.new()
	hud.name = "HUD"
	world.add_child(hud)
	touch = TouchControls.new()
	touch.name = "TouchControls"
	hud.add_child(touch)
	hud.set_race(lap, LAPS_TOTAL, lap_time, best_lap)


# --------------------------------------------------------------------------- #
# loop
# --------------------------------------------------------------------------- #

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var frozen := (not racing) or paused or countdown > 0.0
	player.update_physics(delta, _read_input(), track, frozen)
	player.apply_visual(delta)


func _process(delta: float) -> void:
	if countdown > 0.0 and racing and not paused:
		countdown -= delta
		var shown := int(ceil(countdown))
		if countdown <= 0.0:
			ui.set_countdown("GO")
			go_flash = 0.8
			if audio != null:
				audio.play_countdown()
		else:
			ui.set_countdown(str(shown))
			if int(ceil(countdown + delta)) != shown and audio != null:
				audio.play_countdown()
	if go_flash > 0.0:
		go_flash -= delta
		if go_flash <= 0.0:
			ui.set_countdown("")

	if player == null or cam == null:
		return
	cam.update_camera(delta, player)
	if audio != null:
		audio.update(player, delta)
	if hud != null:
		hud.update_stats(absf(player.vF) * 3.6, player.gear, player.rpm, player.drift)
		hud.set_nitro(player.nitro_charge, player.nitro_active)

	if racing and not paused and countdown <= 0.0 and track != null:
		lap_time += delta
		total_time += delta
		if hud != null:
			hud.set_race(lap, LAPS_TOTAL, lap_time, best_lap)
		_track_progress()

	if ground != null:
		ground.global_position = Vector3(
			roundf(cam.global_position.x / 10.0) * 10.0,
			-0.05,
			roundf(cam.global_position.z / 10.0) * 10.0)
	if mountains != null:
		mountains.global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)


## Start-line crossing detection: the arc-length coordinate wraps from the end of the
## lap back to zero when the car passes the timing line.
func _track_progress() -> void:
	var pr: Dictionary = track.project(player.x, player.z, player.hint)
	var s := float(pr.s)
	if last_s >= 0.0 and last_s > track.length * 0.75 and s < track.length * 0.25:
		if best_lap <= 0.0 or lap_time < best_lap:
			best_lap = lap_time
		lap += 1
		lap_time = 0.0
		if lap > LAPS_TOTAL:
			_finish()
		elif hud != null:
			hud.toast("LAP %d" % lap, 1.2)
			if audio != null:
				audio.play_countdown()
	last_s = s


func _finish() -> void:
	racing = false
	if hud != null:
		hud.toast("FINISH", 2.0)
	ui.show_results(LAPS_TOTAL, total_time, best_lap)


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
	var nitro := Input.is_physical_key_pressed(KEY_SHIFT)
	if touch != null and touch.visible:
		steer += touch.steer_axis()
		throttle = maxf(throttle, touch.throttle_axis())
		brake = maxf(brake, touch.brake_axis())
		hand = hand or touch.handbrake()
		nitro = nitro or touch.nitro()
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
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_Y):
			nitro = true

	return {
		"throttle": throttle,
		"brake": brake,
		"steer": clampf(steer, -1.0, 1.0),
		"analog": analog,
		"handbrake": hand,
		"nitro": nitro,
	}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.physical_keycode:
			KEY_ESCAPE:
				if racing:
					if paused:
						_resume()
					else:
						_pause()
				else:
					ui.show_main()
			KEY_P:
				if paused:
					_resume()
				else:
					_pause()
			KEY_R:
				_reset_car()
			KEY_C:
				_cycle_camera()
			KEY_L:
				_toggle_lights()
			KEY_M:
				_toggle_mute()


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


func _toggle_lights() -> void:
	headlights = not headlights
	if player != null:
		CarBuilder.set_headlights(player.model, headlights)
	if hud != null:
		hud.toast("HEADLIGHTS " + ("ON" if headlights else "OFF"), 0.7)


func _toggle_mute() -> void:
	if audio == null:
		return
	audio.set_muted(not audio.is_muted())
	if hud != null:
		hud.toast("SOUND " + ("OFF" if audio.is_muted() else "ON"), 0.7)


func _cycle_camera() -> void:
	if cam == null:
		return
	var label: String = cam.cycle()
	if hud != null:
		hud.toast(label, 0.9)


## Diagnostic dump for CI: proves what the engine actually assembled, so a build is not
## accepted on trust. Printed only under `-- --autotest`.
func _report_autotest() -> void:
	if player == null or track == null:
		print("[autotest] FAILED: no player/track")
		return
	var model: Dictionary = player.model
	print("[autotest] circuit=%s samples=%d length=%.1fm" % [String(map_def.get("name", "?")), track.N, track.length])
	print("[autotest] car=%s model=%s scale=%.3f length=%.2fm width=%.2fm wheel_radius=%.3fm wheels=%d lights=%d" % [
		car_id,
		String(model.get("model", "?")),
		float(model.get("scale", 0.0)),
		float(model.get("length", 0.0)),
		float(model.get("width", 0.0)),
		float(model.get("wr", 0.0)),
		(model.get("wheels", []) as Array).size(),
		(model.get("lights", []) as Array).size(),
	])
	print("[autotest] props: %d nodes under world, audio engine=%s skid=%s" % [
		world.get_child_count() if world != null else 0,
		str(audio != null and audio.engine != null and audio.engine.stream != null),
		str(audio != null and audio.skid != null and audio.skid.stream != null),
	])
