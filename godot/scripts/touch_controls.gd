class_name TouchControls
extends Control

## On-screen driving controls for the phone build: steering pads, throttle, brake,
## handbrake, nitro, plus camera / reset / pause actions. Multi-touch aware, so you can
## hold throttle and steer at the same time. Drawn with Control primitives so it needs
## no textures and stays crisp at any resolution.

signal pause_pressed
signal camera_pressed
signal reset_pressed

const ACTION_BUTTONS := ["pause", "camera", "reset"]

var _buttons: Array = []      # [{name: String, rect: Rect2, label: String}]
var _owners: Dictionary = {}  # pointer index -> button name

var _steer := 0.0
var _throttle := 0.0
var _brake := 0.0
var _hand := false
var _nitro := false

var _active := false
var _saw_touch := false


func _ready() -> void:
	# On a phone the emulated mouse copy of a touch can arrive first; ignore it from the
	# very beginning so a finger is never duplicated as a stuck mouse press.
	_saw_touch = OS.has_feature("mobile") or OS.has_feature("android")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	set_active(_is_mobile())


static func is_mobile() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("android")


func _is_mobile() -> bool:
	return is_mobile()


## Which pad sits under a point, if any. Used so a finger that is steering does not also
## rotate the camera.
func hit_name(pos: Vector2) -> String:
	return _hit(pos)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	# An inactive layer must not eat taps meant for the menu behind it.
	# never take part in GUI picking; tap handling is done in _input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on and _buttons.is_empty():
		_layout()
	if not on:
		_owners.clear()
		_refresh()


# --- read by game.gd ------------------------------------------------------- #
func steer_axis() -> float:
	return clampf(_steer, -1.0, 1.0)


func throttle_axis() -> float:
	return _throttle


func brake_axis() -> float:
	return _brake


func handbrake() -> bool:
	return _hand


func nitro() -> bool:
	return _nitro


# --- layout --------------------------------------------------------------- #
func _layout() -> void:
	# On the first frames (and in headless runs) the Control can still be 0x0, so fall
	# back to the viewport: the pads are anchored full-rect, so the two agree.
	var basis := size
	if basis.x < 10.0 or basis.y < 10.0:
		basis = get_viewport_rect().size
	var w := basis.x
	var h := basis.y
	if w < 10.0 or h < 10.0:
		return
	_buttons = [
		# steering
		{"name": "left", "rect": Rect2(w * 0.02, h * 0.58, w * 0.15, h * 0.34), "label": "<"},
		{"name": "right", "rect": Rect2(w * 0.18, h * 0.58, w * 0.15, h * 0.34), "label": ">"},
		# pedals
		{"name": "gas", "rect": Rect2(w * 0.80, h * 0.56, w * 0.18, h * 0.38), "label": "GAS"},
		{"name": "brake", "rect": Rect2(w * 0.62, h * 0.68, w * 0.16, h * 0.26), "label": "BRK"},
		{"name": "hand", "rect": Rect2(w * 0.62, h * 0.50, w * 0.16, h * 0.15), "label": "HAND"},
		{"name": "nitro", "rect": Rect2(w * 0.80, h * 0.40, w * 0.18, h * 0.14), "label": "NOS"},
		# actions along the top edge, out of the way of driving
		{"name": "pause", "rect": Rect2(w * 0.925, h * 0.03, w * 0.06, h * 0.11), "label": "II"},
		{"name": "camera", "rect": Rect2(w * 0.855, h * 0.03, w * 0.06, h * 0.11), "label": "CAM"},
		{"name": "reset", "rect": Rect2(w * 0.785, h * 0.03, w * 0.06, h * 0.11), "label": "RST"},
	]
	queue_redraw()


# --- input ---------------------------------------------------------------- #
## Raw input instead of Control._gui_input: a finger is delivered to Node._input on every
## platform, so the driving pads cannot be lost to GUI picking or canvas-layer ordering.
func _input(event: InputEvent) -> void:
	# Hidden pads must not eat taps aimed at the pause menu or the results screen.
	if not _active:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_saw_touch = true
			# Drop any press the emulated mouse registered before this touch arrived,
			# otherwise the matching release would free the finger but not the puppet.
			if _owners.erase(-1):
				_refresh()
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_saw_touch = true
		if _owners.has(drag.index):
			var hit := _hit(drag.position)
			if hit != String(_owners[drag.index]):
				_release(drag.index)
				if not hit.is_empty():
					_press(drag.index, drag.position)
	elif event is InputEventMouseButton:
		# On a phone the touch stream already handled this; the emulated mouse event
		# that Android also sends would register every tap twice.
		if _saw_touch or OS.has_feature("mobile"):
			return
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
	if ACTION_BUTTONS.has(hit):
		match hit:
			"pause":
				pause_pressed.emit()
			"camera":
				camera_pressed.emit()
			"reset":
				reset_pressed.emit()
		return
	_owners[index] = hit
	_refresh()


func _release(index: int) -> void:
	if _owners.erase(index):
		_refresh()


func _hit(pos: Vector2) -> String:
	for b in _buttons:
		var r: Rect2 = b.rect
		# generous touch slop, especially for the small action buttons
		var pad := 10.0 if ACTION_BUTTONS.has(String(b.name)) else 0.0
		if r.grow(pad).has_point(pos):
			return String(b.name)
	return ""


func _refresh() -> void:
	_steer = 0.0
	_throttle = 0.0
	_brake = 0.0
	_hand = false
	_nitro = false
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
			"nitro":
				_nitro = true
	queue_redraw()


# --- drawing -------------------------------------------------------------- #
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var labels := _owners.values()
	for b in _buttons:
		var r: Rect2 = b.rect
		var name := String(b.name)
		var pressed := labels.has(name)
		var action := ACTION_BUTTONS.has(name)
		var fill := Color(1, 1, 1, 0.14)
		if pressed:
			fill = Color(1.0, 0.55, 0.15, 0.6)
		elif action:
			fill = Color(0.08, 0.10, 0.16, 0.55)
		draw_rect(r, fill, true)
		draw_rect(r, Color(1, 1, 1, 0.32), false, 2.0)
		var fs := int(minf(r.size.y * 0.30, 30.0))
		if action:
			fs = int(minf(r.size.x * 0.30, 20.0))
		var baseline := r.position.y + r.size.y * 0.5 + float(fs) * 0.35
		if font != null:
			draw_string(font, Vector2(r.position.x, baseline), String(b.label),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.92))
