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

var _lap := 0
var _laps_total := 3
var _lap_time := 0.0
var _best := 0.0
var _nitro := 1.0
var _nitro_on := false
var _title_text := "APEX RUSH"


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


func set_title(text: String) -> void:
	_title_text = text


## Lap / timing block driven by game.gd
func set_race(lap: int, total: int, lap_time: float, best: float) -> void:
	_lap = lap
	_laps_total = total
	_lap_time = lap_time
	_best = best


## Nitro charge (0..1) and whether the boost is firing right now.
func set_nitro(charge: float, active: bool) -> void:
	_nitro = charge
	_nitro_on = active


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

	# --- nitro bar
	var nitro_bar := Rect2(Vector2(w - 330.0, h - 126.0), Vector2(250.0, 9.0))
	_panel.draw_rect(nitro_bar, Color(1, 1, 1, 0.12))
	var nf := clampf(_nitro, 0.0, 1.0)
	if nf > 0.01:
		var ncol := Color(0.35, 0.85, 1.0) if _nitro_on else Color(0.25, 0.55, 0.75)
		_panel.draw_rect(Rect2(nitro_bar.position, Vector2(nitro_bar.size.x * nf, nitro_bar.size.y)), ncol)
	_panel.draw_string(_font, Vector2(w - 330.0, h - 132.0), "NOS",
		HORIZONTAL_ALIGNMENT_LEFT, 60.0, 16, Color(0.6, 0.85, 1.0, 0.8))

	# --- session / lap block
	_panel.draw_string(_font, Vector2(28.0, 44.0), _title_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.92))
	var lap_line := "LAP %d / %d      %s" % [_lap, _laps_total, _clock(_lap_time)]
	_panel.draw_string(_font, Vector2(28.0, 78.0), lap_line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ACCENT)
	if _best > 0.0:
		_panel.draw_string(_font, Vector2(28.0, 104.0), "BEST  " + _clock(_best),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.75, 0.85, 1.0, 0.85))

	# --- toast
	if _toast_time > 0.0:
		var a := clampf(_toast_time / maxf(0.001, _toast_duration), 0.0, 1.0)
		_panel.draw_string(_font, Vector2(0.0, 160.0), _toast_text,
			HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 1, 1, a))


func _clock(seconds: float) -> String:
	var t := maxf(0.0, seconds)
	var m := int(t / 60.0)
	var sec := int(t) % 60
	var cs := int((t - floor(t)) * 100.0)
	return "%d:%02d.%02d" % [m, sec, cs]
