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


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.04, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(600.0, 0.0)
	centre.add_child(_panel)

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

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(_vbox)

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
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false


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
	_clear()
	_add_button("RACE", _on_race)
	_add_button("GARAGE  ·  " + _car_name(selected_car), show_garage)
	_add_button("CIRCUIT  ·  " + _map_name(selected_map), show_maps)
	_add_button("QUIT", func() -> void: get_tree().quit())


func show_garage() -> void:
	_set_panel_visible(true)
	_notify_left_race()
	_title.text = "GARAGE"
	_sub.text = "Pick your car — every class handles differently"
	_clear()
	for car in cars:
		var id := String(car.get("id", ""))
		var mark := "▸ " if id == selected_car else "   "
		var text := "%s%s  ·  Tier %d  ·  %d km/h" % [mark, String(car.get("name", id)), int(car.get("tier", 1)), int(round(float(car.get("top", 70.0)) * 3.6))]
		_add_button(text, func() -> void:
			selected_car = id
			show_garage()
		)
	_add_button("◂ BACK", show_main)


func show_maps() -> void:
	_set_panel_visible(true)
	_notify_left_race()
	_title.text = "CIRCUIT"
	_sub.text = "Five locations, each with its own light, surface and skyline"
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
	_title.text = text
	_sub.text = _map_name(selected_map) + "  ·  " + _car_name(selected_car)
	_clear()


func show_race() -> void:
	in_race = true
	_set_panel_visible(false)
	_hint.visible = false
	_countdown.visible = false


func show_pause() -> void:
	_set_panel_visible(true)
	_title.text = "PAUSED"
	_sub.text = _map_name(selected_map) + "  ·  " + _car_name(selected_car)
	_clear()
	_add_button("RESUME", func() -> void: resume_requested.emit())
	_add_button("RESTART", func() -> void: restart_requested.emit())
	_add_button("GARAGE", show_garage)
	_add_button("MAIN MENU", show_main)


func show_results(laps: int, total: float, best: float) -> void:
	_set_panel_visible(true)
	_title.text = "FINISH"
	_sub.text = "%s  ·  %d laps" % [_map_name(selected_map), laps]
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


func _activate_at(pos: Vector2) -> void:
	if _vbox == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_activate_ms < 220:
		return
	for child in _vbox.get_children():
		var b := child as Button
		if b == null or not b.is_visible_in_tree():
			continue
		if b.get_global_rect().has_point(pos):
			_last_activate_ms = now
			_flash(b)
			var audio := get_tree().root.find_child("Audio", true, false)
			if audio is AudioDirector:
				(audio as AudioDirector).play_ui()
			b.pressed.emit()
			return


func _flash(b: Button) -> void:
	b.modulate = Color(1.6, 1.35, 1.05)
	var tween := create_tween()
	tween.tween_property(b, "modulate", Color(1, 1, 1), 0.2)


func _on_race() -> void:
	race_requested.emit(selected_map, selected_car)


func _set_panel_visible(on: bool) -> void:
	_dim.visible = on
	_panel.visible = on


func _clear() -> void:
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


func _add_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560.0, 76.0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 26)
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
