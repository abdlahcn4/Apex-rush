class_name RaceHUD
extends CanvasLayer

## Minimal canvas HUD (speed, gear, rpm, hints). The web build draws its speedo on a
## <canvas>; this uses Control._draw via the panel's "draw" signal.

const ACCENT := Color(1.0, 0.55, 0.15)

var _panel: Control
var _font: Font

var _kmh := 0.0
var _gear := "N"
var _rpm := 900.0
var _drift := 0.0
var _toast_text := ""
var _toast_time := 0.0
var _toast_duration := 1.2


func _ready() -> void:
	layer = 10
	_panel = Control.new()
	_panel.name = "HUDPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.draw.connect(_on_draw)
	_font = ThemeDB.fallback_font


func update_stats(kmh: float, gear: String, rpm: float, drift: float) -> void:
	_kmh = kmh
	_gear = gear
	_rpm = rpm
	_drift = drift
	if _toast_time > 0.0:
		_toast_time -= get_process_delta_time()
	_panel.queue_redraw()


func toast(text: String, secs := 1.2) -> void:
	_toast_text = text
	_toast_time = secs
	_toast_duration = secs


func _on_draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var w := _panel.size.x
	var h := _panel.size.y
	if w < 10.0 or h < 10.0:
		return

	# --- speed
	var spd := str(int(round(_kmh)))
	_panel.draw_string(_font, Vector2(w - 330.0, h - 86.0), spd,
		HORIZONTAL_ALIGNMENT_RIGHT, 250.0, 86, Color(1, 1, 1, 0.96))
	_panel.draw_string(_font, Vector2(w - 330.0, h - 52.0), "KM/H",
		HORIZONTAL_ALIGNMENT_RIGHT, 250.0, 22, ACCENT)

	# --- gear
	_panel.draw_string(_font, Vector2(w - 400.0, h - 86.0), _gear,
		HORIZONTAL_ALIGNMENT_LEFT, 70.0, 56, Color(1.0, 0.78, 0.35))

	# --- rpm bar
	var bar := Rect2(Vector2(w - 330.0, h - 40.0), Vector2(250.0, 8.0))
	_panel.draw_rect(bar, Color(1, 1, 1, 0.14))
	var frac := clampf((_rpm - 900.0) / 7200.0, 0.0, 1.0)
	if frac > 0.01:
		var fill := ACCENT.lerp(Color(1.0, 0.92, 0.25), frac)
		_panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill)

	# --- drift flash
	if _drift > 0.45:
		_panel.draw_string(_font, Vector2(w - 400.0, h - 130.0), "DRIFT",
			HORIZONTAL_ALIGNMENT_RIGHT, 340.0, 30, Color(1.0, 0.35, 0.15, clampf(_drift, 0.0, 1.0)))

	# --- hints
	_panel.draw_string(_font, Vector2(28.0, 42.0), "APEX RUSH - GODOT SLICE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.75))
	_panel.draw_string(_font, Vector2(28.0, 70.0), "W/S or UP/DOWN  throttle - brake    A/D or LEFT/RIGHT  steer",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.45))
	_panel.draw_string(_font, Vector2(28.0, 94.0), "SPACE  handbrake    C  camera    R  reset    ESC  quit",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.45))

	# --- toast
	if _toast_time > 0.0:
		var a := clampf(_toast_time / maxf(0.001, _toast_duration), 0.0, 1.0)
		_panel.draw_string(_font, Vector2(0.0, 160.0), _toast_text,
			HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 1, 1, a))
