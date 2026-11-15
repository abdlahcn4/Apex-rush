class_name GameUI
extends CanvasLayer

## Front end for the game: main menu, garage (car select), map select, loading,
## countdown, pause and results. Pure Control theming — no textures, so it stays
## crisp at any phone resolution and costs nothing to render.

signal race_requested(map_id: String, car_id: String)
signal resume_requested
signal restart_requested
signal left_race

const ACCENT := Color("#ff7a18")
const ACCENT_DIM := Color("#8a4a12")
const INK := Color(0.93, 0.95, 1.0)
const PANEL_BG := Color(0.035, 0.045, 0.075, 0.93)

var cars: Array = []
var maps: Array = []
var selected_car := "vortex"
var selected_map := "sunset_ring"
var in_race := false

var _dim: ColorRect
var _panel: PanelContainer
var _vbox: VBoxContainer
var _title: Label
var _sub: Label
var _countdown: Label
var _toast: Label
var _hint: Label
var _toast_time := 0.0

var _press_pos := Vector2.ZERO
var _press_index := -1
var _touch_seen := false
var _last_activate_ms := -1000
# --- showroom (3D vehicle preview behind the menu and in the garage) ----------- #
var _showroom: SubViewport
var _showroom_container: SubViewportContainer
var _showroom_car: Node3D
var _show_cam: Camera3D
var _showcase_shift := Vector2.ZERO
var _showroom_spin: Node3D
var _paint := Color("#2ecc40")
var paint_color := Color("#2ecc40")
var has_paint := false
var quality := 2
var master_db := 0.0
# row metrics chosen per screen so every row stays inside a 1280x720 viewport
var _row_h := 76.0
var _last_rows := 4
var _row_font := 26
var debug_input_events := 0
var debug_trace := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# The menu is a two-column composition: buttons own the left column, the 3D car owns
	# the right one. A soft scrim sits under the buttons only, so the car is never covered.
	_dim = ColorRect.new()
	_dim.name = "Scrim"
	_dim.color = Color(0.02, 0.03, 0.05, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "MenuPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_width_left = 6
	style.border_color = ACCENT
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.resized.connect(_keep_panel_inside)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(_vbox)

	_build_showroom(root)

	_title = _label("APEX RUSH", 44, ACCENT)
	_sub = _label("", 20, Color(0.72, 0.78, 0.88))
	_vbox.add_child(_title)
	_vbox.add_child(_sub)

	_countdown = _label("", 150, Color(1, 1, 1))
	_countdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown.visible = false
	root.add_child(_countdown)

	_toast = _label("", 26, Color(1, 1, 1))
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 96.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	root.add_child(_toast)

	_hint = _label("", 17, Color(0.75, 0.8, 0.9))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -46.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = "W/S/A/D or arrows   SPACE handbrake   SHIFT nitro   C camera   L lights   M mute   ESC pause"
	root.add_child(_hint)


func _process(delta: float) -> void:
	if _showroom_spin != null and _showroom_container != null and _showroom_container.visible:
		_showroom_spin.rotation.y += delta * 0.45
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false


## A real 3D turntable for the menu and the garage: the shipped car, lit by an HDRI, on a
## SubViewport behind the UI. Costs one extra world, no textures.
func _build_showroom(root: Control) -> void:
	var container := SubViewportContainer.new()
	container.name = "Showroom"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(container)
	_showroom_container = container

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)
	_showroom = vp

	# A neutral photo studio, not a street panorama: coloured foliage in an HDRI is what
	# turned the paint into green and gold noise. Grey gradient + soft boxes only.
	var studio := ProceduralSkyMaterial.new()
	studio.sky_top_color = Color(0.055, 0.062, 0.075)
	studio.sky_horizon_color = Color(0.20, 0.21, 0.235)
	studio.sky_curve = 0.28
	studio.ground_horizon_color = Color(0.11, 0.115, 0.13)
	studio.ground_bottom_color = Color(0.02, 0.022, 0.028)
	studio.ground_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = studio
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.12
	env.glow_bloom = 0.03
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	# three-point rig: warm key, cool fill, hard white kicker along the roofline
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.88)
	key.light_energy = 1.35
	key.rotation_degrees = Vector3(-32.0, 138.0, 0.0)
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.76, 1.0)
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-12.0, -55.0, 0.0)
	vp.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.98, 0.95)
	rim.light_energy = 1.1
	rim.rotation_degrees = Vector3(-58.0, 24.0, 0.0)
	rim.shadow_enabled = false
	vp.add_child(rim)

	var cam := Camera3D.new()
	cam.position = Vector3(4.9, 1.75, 5.9)
	cam.fov = 40.0
	vp.add_child(cam)
	_show_cam = cam
	cam.look_at(Vector3(0.0, 0.62, 0.0), Vector3.UP)

	_showroom_spin = Node3D.new()
	vp.add_child(_showroom_spin)
	_refresh_showroom_car()
	_layout()
	get_viewport().size_changed.connect(_layout)


## Two-column composition that survives any aspect ratio: buttons left, car right in
## landscape; car above, buttons below in portrait. Nothing overlaps at any size.
func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 64.0 or vp.y < 64.0 or _panel == null:
		return
	var landscape := vp.x >= vp.y * 1.2
	var margin := clampf(vp.x * 0.035, 12.0, 56.0)
	if landscape:
		var panel_w := clampf(vp.x * 0.40, 330.0, 590.0)
		var panel_h := clampf(vp.y * 0.84, 300.0, 640.0)
		_panel.size = Vector2(panel_w, panel_h)
		_panel.position = Vector2(margin, (vp.y - panel_h) * 0.5)
		_dim.size = Vector2(panel_w + margin * 2.0, vp.y)
		_dim.position = Vector2.ZERO
		_dim.color = Color(0.015, 0.02, 0.035, 0.62)
		_showcase_shift = Vector2(panel_w * 0.55, 0.0)
	else:
		var panel_h := vp.y * 0.58
		_panel.size = Vector2(vp.x - margin * 2.0, panel_h)
		_panel.position = Vector2(margin, vp.y - panel_h - margin * 0.6)
		_dim.size = Vector2(vp.x, panel_h + margin * 2.2)
		_dim.position = Vector2(0.0, vp.y - panel_h - margin * 1.6)
		_dim.color = Color(0.015, 0.02, 0.035, 0.62)
		_showcase_shift = Vector2(0.0, panel_h * 0.62)
	_apply_showcase_framing()
	_fit_rows()
	_keep_panel_inside()


## If the rows need more height than the panel was given, the panel grows; this keeps the
## grown panel inside the window instead of hanging off the bottom edge.
func _keep_panel_inside() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var margin := clampf(vp.x * 0.03, 8.0, 48.0)
	var max_y := maxf(margin, vp.y - _panel.size.y - margin)
	_panel.position.y = clampf(_panel.position.y, margin, max_y)


## Keep the car inside the showcase half by aiming the camera off-centre.
func _apply_showcase_framing() -> void:
	if _show_cam == null:
		return
	var target := Vector3(0.0, 0.62, 0.0) - Vector3(_showcase_shift.x, _showcase_shift.y, 0.0) * 0.009
	_show_cam.look_at(target, Vector3.UP)


## Rows shrink with the panel so every button stays on screen on a phone.
func _fit_rows() -> void:
	if _vbox == null or _panel == null:
		return
	_plan_rows(_last_rows)
	for b in _buttons_in(_vbox):
		b.custom_minimum_size = Vector2(0.0, _row_h)
		b.add_theme_font_size_override("font_size", _row_font)


func _transition_in() -> void:
	if _panel == null:
		return
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD)


func _refresh_showroom_car() -> void:
	if _showroom_spin == null:
		return
	for child in _showroom_spin.get_children():
		child.queue_free()
	var spec := CarBuilder.spec(selected_car)
	var hero := CarHero.build(spec, _paint)
	var node := hero.get("root") as Node3D
	if node == null:
		return
	# centre the car in frame and stand it on the floor
	var length := float(hero.get("length", 4.6))
	node.position = Vector3(0.0, 0.0, -length * 0.1)
	_showroom_spin.add_child(node)
	_showroom_car = node


func _set_paint(color: Color) -> void:
	_paint = color
	paint_color = color
	has_paint = true
	if _showroom_car != null:
		for n in _showroom_car.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for i in range(mi.mesh.get_surface_count()):
				var std := mi.get_surface_override_material(i) as StandardMaterial3D
				if std != null and std.resource_name.to_lower().contains("paint"):
					std.albedo_color = color
	show_garage()


## Settings: master volume, graphics preset, fullscreen. Stored in user://settings.cfg.
func show_settings() -> void:
	_set_panel_visible(true)
	set_showroom_visible(true)
	_notify_left_race()
	_title.text = "SETTINGS"
	_sub.text = "Sound, graphics and display"
	_plan_rows(4)
	_clear()
	_add_button("MASTER VOLUME  ·  %d%%" % int(round(_volume_pct())), _cycle_volume)
	_add_button("GRAPHICS  ·  " + _quality_name(), _cycle_quality)
	if not OS.has_feature("mobile"):
		_add_button("FULLSCREEN  ·  " + ("ON" if _is_fullscreen() else "OFF"), _toggle_fullscreen)
	_add_button("◂ BACK", show_main)


func _volume_pct() -> float:
	if master_db <= -59.0:
		return 0.0
	return clampf((master_db + 60.0) / 60.0, 0.0, 1.0) * 100.0


func _quality_name() -> String:
	match quality:
		0: return "LOW"
		1: return "MEDIUM"
		_: return "HIGH"


func _cycle_volume() -> void:
	var pct := [0.0, 25.0, 50.0, 75.0, 100.0]
	var idx := 0
	var cur := _volume_pct()
	var best := 999.0
	for i in range(pct.size()):
		var d := absf(float(pct[i]) - cur)
		if d < best:
			best = d
			idx = i
	idx = (idx + 1) % pct.size()
	var target: float = pct[idx]
	master_db = -60.0 if target <= 0.0 else lerpf(-60.0, 0.0, target / 100.0)
	_apply_audio()
	_save_settings()
	show_settings()


func _cycle_quality() -> void:
	quality = (quality + 1) % 3
	_apply_quality()
	_save_settings()
	show_settings()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_save_settings()
	show_settings()


func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, master_db)


func _apply_quality() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_db", master_db)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "fullscreen", _is_fullscreen())
	cfg.set_value("car", "paint", paint_color)
	cfg.set_value("car", "has_paint", has_paint)
	cfg.save("user://settings.cfg")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		_apply_quality()
		_apply_audio()
		_refresh_showroom_car()
		return
	master_db = float(cfg.get_value("audio", "master_db", 0.0))
	quality = int(cfg.get_value("video", "quality", 2))
	has_paint = bool(cfg.get_value("car", "has_paint", false))
	paint_color = cfg.get_value("car", "paint", paint_color)
	_paint = paint_color
	_apply_quality()
	_apply_audio()
	_refresh_showroom_car()


func set_showroom_visible(on: bool) -> void:
	if _showroom_container != null:
		_showroom_container.visible = on


func setup(car_list: Array, map_list: Array) -> void:
	cars = car_list
	maps = map_list
	if not cars.is_empty():
		selected_car = String(cars[0].get("id", "vortex"))
	if not maps.is_empty():
		selected_map = String(maps[0].get("id", "sunset_ring"))


# --------------------------------------------------------------------------- #
# screens
# --------------------------------------------------------------------------- #

func show_main() -> void:
	_set_panel_visible(true)
	_notify_left_race()
	_hint.visible = true
	_title.text = "APEX RUSH"
	_sub.text = "Real cars. Real circuits. Real sound."
	set_showroom_visible(true)
	_plan_rows(5)
	_clear()
	_add_button("RACE", _on_race)
	_add_button("GARAGE  ·  " + _car_name(selected_car), show_garage)
	_add_button("CIRCUIT  ·  " + _map_name(selected_map), show_maps)
	_add_button("SETTINGS", show_settings)
	_add_button("QUIT", func() -> void: get_tree().quit())


func show_garage() -> void:
	_set_panel_visible(true)
	_notify_left_race()
	_title.text = "GARAGE"
	_sub.text = "Pick your car — every class handles differently"
	set_showroom_visible(true)
	_plan_rows(cars.size() + 2)
	_clear()
	_add_paint_row()
	for car in cars:
		var id := String(car.get("id", ""))
		var mark := "▸ " if id == selected_car else "   "
		var text := "%s%s  ·  Tier %d  ·  %d km/h" % [mark, String(car.get("name", id)), int(car.get("tier", 1)), int(round(float(car.get("top", 70.0)) * 3.6))]
		_add_button(text, func() -> void:
			selected_car = id
			show_garage()
		)
	_add_button("◂ BACK", show_main)


## Paint picker: the swatches restyle the live 3D preview and the race car.
func _add_paint_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := _label("PAINT", 16, Color(0.66, 0.72, 0.82))
	label.custom_minimum_size = Vector2(70.0, 0.0)
	row.add_child(label)
	var palette: Array[Color] = [Color("#2ecc40"), Color("#e63946"), Color("#ffbe0b"),
			Color("#7b2ff7"), Color("#f1faee"), Color("#111318"), Color("#ff7a18"), Color("#35d3ff")]
	for c in palette:
		var swatch := Button.new()
		var style := StyleBoxFlat.new()
		style.bg_color = c
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", style)
		swatch.add_theme_stylebox_override("pressed", style)
		swatch.custom_minimum_size = Vector2(38.0, 26.0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = c
		swatch.pressed.connect(func() -> void: _set_paint(col))
		row.add_child(swatch)
	_vbox.add_child(row)


func show_maps() -> void:
	_set_panel_visible(true)
	_notify_left_race()
	_title.text = "CIRCUIT"
	_sub.text = "Five locations, each with its own light, surface and skyline"
	_plan_rows(maps.size() + 1)
	_clear()
	for m in maps:
		var id := String(m.get("id", ""))
		var mark := "▸ " if id == selected_map else "   "
		var text := "%s%s  ·  %s" % [mark, String(m.get("name", id)), String(m.get("grade", "Circuit"))]
		_add_button(text, func() -> void:
			selected_map = id
			show_maps()
		)
	_add_button("◂ BACK", show_main)


func show_loading(text := "LOADING") -> void:
	_set_panel_visible(true)
	set_showroom_visible(false)
	_title.text = text
	_sub.text = _map_name(selected_map) + "  ·  " + _car_name(selected_car)
	_clear()


func show_race() -> void:
	in_race = true
	_set_panel_visible(false)
	set_showroom_visible(false)
	_hint.visible = false
	_countdown.visible = false


func show_pause() -> void:
	_set_panel_visible(true)
	_title.text = "PAUSED"
	_sub.text = _map_name(selected_map) + "  ·  " + _car_name(selected_car)
	_plan_rows(4)
	_clear()
	_add_button("RESUME", func() -> void: resume_requested.emit())
	_add_button("RESTART", func() -> void: restart_requested.emit())
	_add_button("GARAGE", show_garage)
	_add_button("MAIN MENU", show_main)


func show_results(laps: int, total: float, best: float) -> void:
	_set_panel_visible(true)
	_title.text = "FINISH"
	_sub.text = "%s  ·  %d laps" % [_map_name(selected_map), laps]
	_plan_rows(3)
	_clear()
	_add_stat("TOTAL TIME", _clock(total))
	_add_stat("BEST LAP", _clock(best))
	_add_stat("CAR", _car_name(selected_car))
	_add_button("RACE AGAIN", func() -> void: restart_requested.emit())
	_add_button("CHANGE CIRCUIT", show_maps)
	_add_button("MAIN MENU", show_main)


func set_countdown(text: String) -> void:
	_countdown.text = text
	_countdown.visible = not text.is_empty()


func toast(text: String, seconds := 1.6) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_time = seconds


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

func _notify_left_race() -> void:
	if in_race:
		in_race = false
		left_race.emit()


## The menu is driven from here rather than from Control._gui_input: a finger tap is
## delivered to Node._input on every platform, so this cannot be broken by touch-to-mouse
## emulation, canvas-layer ordering or an invisible full-screen Control on top.
func _input(event: InputEvent) -> void:
	if _panel == null or not _panel.visible:
		return
	debug_input_events += 1
	if debug_trace:
		var kind := "?"
		var where := Vector2.ZERO
		var down := false
		if event is InputEventScreenTouch:
			kind = "touch"
			where = (event as InputEventScreenTouch).position
			down = (event as InputEventScreenTouch).pressed
		elif event is InputEventMouseButton:
			kind = "mouse"
			where = (event as InputEventMouseButton).position
			down = (event as InputEventMouseButton).pressed
		print("[tap] %s pos=%s down=%s press_index=%d touch_seen=%s" % [
			kind, str(where), str(down), _press_index, str(_touch_seen),
		])
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		return
	if event is InputEventScreenTouch:
		_touch_seen = true
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press_pos = touch.position
			_press_index = touch.index
			return
		if _press_index >= 0 and touch.index != _press_index:
			return
		if _press_index >= 0 and touch.position.distance_to(_press_pos) > 90.0:
			_press_index = -1
			return  # a drag, not a tap
		_press_index = -1
		_activate_at(touch.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if _touch_seen:
			return  # the emulated copy of a touch we already handled
		if mb.pressed:
			_press_pos = mb.position
			_press_index = -2
			return
		if _press_index == -2:
			_press_index = -1
			_activate_at(mb.position)


## Raw input can reach here in window space or in viewport space depending on the
## platform layer, and the two differ by the stretch ratio (a 2400x1080 phone against a
## 1280x720 viewport is ~1.9x; CI's headless window is 20x). Rather than assume one, the
## tap is tested against every plausible interpretation of the same point.
func _candidates(pos: Vector2) -> Array:
	var out: Array = [pos]
	var vp := get_viewport()
	if vp == null:
		return out
	# The canonical conversion from platform (screen) coordinates into viewport
	# coordinates. This is the transform Godot itself uses to place a finger.
	var screen := vp.get_screen_transform()
	if not screen.is_equal_approx(Transform2D.IDENTITY):
		var p1 := screen.affine_inverse() * pos
		if not out.has(p1):
			out.append(p1)
	var final := vp.get_final_transform()
	if not final.is_equal_approx(Transform2D.IDENTITY):
		var p2 := final.affine_inverse() * pos
		if not out.has(p2):
			out.append(p2)
	return out


## Every button on the current screen, including the ones nested in rows such as the
## garage paint swatches.
func _buttons_in(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		elif child is Container:
			out.append_array(_buttons_in(child))
	return out


func _activate_at(pos: Vector2) -> void:
	if _vbox == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_activate_ms < 220:
		return
	for point in _candidates(pos):
		for b in _buttons_in(_vbox):
			if b == null or not b.is_visible_in_tree():
				continue
			# a little slop so a slightly-off conversion still lands on a finger target
			if b.get_global_rect().grow(14.0).has_point(point):
				if debug_trace:
					print("[tap] hit '%s' with %s (from %s)" % [b.text, str(point), str(pos)])
				_last_activate_ms = now
				_flash(b)
				var audio := get_tree().root.find_child("Audio", true, false)
				if audio is AudioDirector:
					(audio as AudioDirector).play_ui()
				b.pressed.emit()
				return
	if debug_trace:
		print("[tap] nothing hit for %s -> %s" % [str(pos), str(_candidates(pos))])


func _flash(b: Button) -> void:
	b.modulate = Color(1.6, 1.35, 1.05)
	var tween := create_tween()
	tween.tween_property(b, "modulate", Color(1, 1, 1), 0.2)


func _on_race() -> void:
	race_requested.emit(selected_map, selected_car)


func _set_panel_visible(on: bool) -> void:
	_dim.visible = on
	_panel.visible = on


## Picks a row height that keeps the whole list on screen. With a fixed 76 px row the
## garage (6 cars + BACK) overflowed a 720 px tall viewport and its last rows could not be
## tapped on a phone.
func _plan_rows(count: int) -> void:
	const SEPARATION := 12.0
	_last_rows = maxi(1, count)
	# Sized from the viewport, never from the panel's current height: reading the panel
	# while the panel is growing to fit its rows feeds back and inflates both.
	var vp := get_viewport().get_visible_rect().size
	var panel_h := clampf(vp.y * 0.84, 300.0, 640.0)
	var available := maxf(150.0, panel_h - 215.0)
	var h := 76.0
	if count > 0:
		h = (available - SEPARATION * float(count - 1)) / float(count)
	_row_h = clampf(h, 30.0, 76.0)
	_row_font = int(clampf(_row_h * 0.36, 13.0, 26.0))


func _clear() -> void:
	_transition_in()
	for child in _vbox.get_children():
		if child == _title or child == _sub:
			continue
		child.queue_free()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _add_stat(key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var k := _label(key, 20, Color(0.66, 0.72, 0.82))
	k.custom_minimum_size = Vector2(240.0, 0.0)
	var v := _label(value, 22, INK)
	row.add_child(k)
	row.add_child(v)
	_vbox.add_child(row)


func _set_hovered(b: Button, on: bool) -> void:
	if b == null:
		return
	var state := "hover" if on else "normal"
	b.add_theme_stylebox_override("normal", b.get_theme_stylebox(state))
	b.add_theme_color_override("font_color", Color(1, 1, 1) if on else INK)


## Hover state for the mouse: the buttons ignore native input (taps are hit-tested in
## _input), so the hover look is applied here instead of from the theme engine.
func _update_hover(pos: Vector2) -> void:
	if _vbox == null or not _panel.visible:
		return
	for b in _buttons_in(_vbox):
		if b == null:
			continue
		_set_hovered(b, b.is_visible_in_tree() and b.get_global_rect().has_point(pos))


func _add_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, _row_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _row_font)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", ACCENT)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.12, 0.17, 0.96)
	normal.border_width_left = 3
	normal.border_color = ACCENT_DIM
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.17, 0.20, 0.27, 0.98)
	hover.border_color = ACCENT

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(action)
	# Hit-testing is done in _input below, so the menu works from a raw finger tap on
	# any device without relying on the engine's mouse-emulation pipeline.
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(b)
	return b


func _car_name(id: String) -> String:
	for c in cars:
		if String(c.get("id", "")) == id:
			return String(c.get("name", id))
	return id


func _map_name(id: String) -> String:
	for m in maps:
		if String(m.get("id", "")) == id:
			return String(m.get("name", id))
	return id


func _clock(seconds: float) -> String:
	var t := maxf(0.0, seconds)
	var m := int(t / 60.0)
	var s := int(t) % 60
	var cs := int((t - floor(t)) * 100.0)
	return "%d:%02d.%02d" % [m, s, cs]
