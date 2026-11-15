class_name TouchControls
extends Control

## On-screen buttons for the Android build. Drawn procedurally (no textures) so the
## project stays asset-free, and multi-touch aware so gas + steering work together.

var _buttons: Array = []      # [{name: String, rect: Rect2, label: String}]
var _owners: Dictionary = {}  # touch index -> button name

var _steer := 0.0
var _throttle := 0.0
var _brake := 0.0
var _hand := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = DisplayServer.is_touchscreen_available()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w < 10.0 or h < 10.0:
		return
	_buttons = [
		{"name": "left", "rect": Rect2(w * 0.03, h * 0.64, w * 0.13, h * 0.28), "label": "<"},
		{"name": "right", "rect": Rect2(w * 0.18, h * 0.64, w * 0.13, h * 0.28), "label": ">"},
		{"name": "gas", "rect": Rect2(w * 0.80, h * 0.60, w * 0.17, h * 0.32), "label": "GAS"},
		{"name": "brake", "rect": Rect2(w * 0.62, h * 0.70, w * 0.16, h * 0.22), "label": "BRK"},
		{"name": "hand", "rect": Rect2(w * 0.62, h * 0.52, w * 0.16, h * 0.14), "label": "HAND"},
	]
	queue_redraw()


# --- read by game.gd ------------------------------------------------------- #
func steer_axis() -> float:
	return clampf(_steer, -1.0, 1.0)


func throttle_axis() -> float:
	return _throttle


func brake_axis() -> float:
	return _brake


func handbrake() -> bool:
	return _hand


# --- input ---------------------------------------------------------------- #
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _owners.has(drag.index):
			var hit := _hit(drag.position)
			if hit != String(_owners[drag.index]):
				_release(drag.index)
				if not hit.is_empty():
					_press(drag.index, drag.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(-1, mb.position)
			else:
				_release(-1)


func _press(index: int, pos: Vector2) -> void:
	var hit := _hit(pos)
	if hit.is_empty():
		return
	_owners[index] = hit
	_refresh()


func _release(index: int) -> void:
	if _owners.erase(index):
		_refresh()


func _hit(pos: Vector2) -> String:
	for b in _buttons:
		var r: Rect2 = b.rect
		if r.has_point(pos):
			return String(b.name)
	return ""


func _refresh() -> void:
	_steer = 0.0
	_throttle = 0.0
	_brake = 0.0
	_hand = false
	for key in _owners.keys():
		match String(_owners[key]):
			"left":
				_steer -= 1.0
			"right":
				_steer += 1.0
			"gas":
				_throttle = 1.0
			"brake":
				_brake = 1.0
			"hand":
				_hand = true
	queue_redraw()


# --- drawing -------------------------------------------------------------- #
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var labels := _owners.values()
	for b in _buttons:
		var r: Rect2 = b.rect
		var pressed := labels.has(String(b.name))
		var fill := Color(1.0, 0.55, 0.15, 0.55) if pressed else Color(1, 1, 1, 0.18)
		draw_rect(r, fill, true)
		draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)
		var fs := int(minf(r.size.y * 0.26, 30.0))
		var baseline := r.position.y + r.size.y * 0.5 + fs * 0.35
		if font != null:
			draw_string(font, Vector2(r.position.x, baseline), String(b.label),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.9))
