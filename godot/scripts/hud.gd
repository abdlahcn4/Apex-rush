class_name RaceHUD
extends CanvasLayer

## Race dashboard. Drawn with Control primitives so it stays crisp at any resolution:
## a circular speedometer with a live needle arc, a segmented RPM strip with a shift
## light, a nitro bar, and a timing block. Everything scales with the viewport.

const ACCENT := Color(1.0, 0.55, 0.15)
const ACCENT_HOT := Color(1.0, 0.26, 0.12)
const CYAN := Color(0.21, 0.83, 1.0)
const INK := Color(0.96, 0.97, 1.0)
const PANEL := Color(0.04, 0.05, 0.08, 0.62)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.10)
const TRACK_BG := Color(1.0, 1.0, 1.0, 0.10)

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
var _max_kmh := 340.0
var _smooth_kmh := 0.0
var _smooth_rpm := 900.0
var _needle := 0.0


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
	var dt := maxf(0.0001, get_process_delta_time())
	_smooth_kmh = lerpf(_smooth_kmh, _kmh, minf(1.0, dt * 8.0))
	_smooth_rpm = lerpf(_smooth_rpm, _rpm, minf(1.0, dt * 10.0))
	_needle = lerpf(_needle, clampf(_smooth_kmh / _max_kmh, 0.0, 1.0), minf(1.0, dt * 10.0))
	_panel.queue_redraw()


func set_title(text: String) -> void:
	_title_text = text


## Lap / timing block driven by game.gd
func set_race(lap: int, total: int, lap_time: float, best: float) -> void:
	_lap = lap
	_laps_total = total
	_lap_time = lap_time
	_best = best


func set_nitro(charge: float, active: bool) -> void:
	_nitro = clampf(charge, 0.0, 1.0)
	_nitro_on = active


func toast(text: String, secs := 1.2) -> void:
	_toast_text = text
	_toast_time = secs
	_toast_duration = secs


# --------------------------------------------------------------------------- #
# drawing
# --------------------------------------------------------------------------- #

func _on_draw() -> void:
	var size := _panel.size
	if size.x < 32.0 or size.y < 32.0:
		return
	# one scale for the whole dashboard, with a floor so a small window stays legible
	var s := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.42, 2.2)
	var radius := clampf(size.y * 0.135, 54.0 * s, 112.0 * s)
	var bottom := size.y - 34.0 * s
	_draw_speedo(s, Vector2(52.0 * s + radius, bottom - radius), radius)
	_draw_tacho(s, Vector2(size.x - 52.0 * s - radius - 26.0 * s, bottom - radius), radius)
	_draw_nitro(s, size, radius)
	_draw_timing(s)
	_draw_toast(s, size)


func _draw_timing(s: float) -> void:
	var w := 296.0 * s
	var h := 104.0 * s
	var pos := Vector2(26.0 * s, 24.0 * s)
	_round_rect(Rect2(pos, Vector2(w, h)), 10.0 * s, PANEL, PANEL_EDGE, 1.5 * s)
	_text(pos + Vector2(18.0 * s, 28.0 * s), _title_text, 15.0 * s, Color(1, 1, 1, 0.66))
	_text(pos + Vector2(18.0 * s, 62.0 * s), "LAP %d / %d" % [_lap, _laps_total], 24.0 * s, INK)
	_text(pos + Vector2(w - 18.0 * s - _width(_clock(_lap_time), 24.0 * s), 62.0 * s),
		_clock(_lap_time), 24.0 * s, ACCENT)
	_text(pos + Vector2(18.0 * s, 88.0 * s), "BEST  " + _clock(_best), 15.0 * s,
		Color(0.78, 0.83, 0.92, 0.9))


## One instrument dial: track, lit sweep, tick marks, needle and a centre readout.
func _dial(centre: Vector2, radius: float, value01: float, col: Color, width: float,
		red_from: float, redline: Color) -> void:
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	_panel.draw_circle(centre, radius + 13.0 * (width / 12.0), PANEL)
	_panel.draw_arc(centre, radius, start, start + sweep, 72, TRACK_BG, width, true)
	if red_from < 1.0:
		_panel.draw_arc(centre, radius, start + sweep * red_from, start + sweep, 24,
			Color(redline.r, redline.g, redline.b, 0.45), width, true)
	if value01 > 0.01:
		_panel.draw_arc(centre, radius, start, start + sweep * value01, 72, col, width, true)
	for i in range(11):
		var a := start + sweep * (float(i) / 10.0)
		var dir := Vector2(cos(a), sin(a))
		var long: bool = int(i) % 5 == 0
		_panel.draw_line(centre + dir * (radius - (16.0 if long else 9.0) * (width / 12.0)),
			centre + dir * (radius - 4.0 * (width / 12.0)),
			Color(1, 1, 1, 0.45 if long else 0.22), (2.2 if long else 1.4) * (width / 12.0), true)
	var na := start + sweep * value01
	_panel.draw_line(centre, centre + Vector2(cos(na), sin(na)) * (radius - 6.0 * (width / 12.0)),
		redline if value01 > red_from else ACCENT_HOT, 3.0 * (width / 12.0), true)
	_panel.draw_circle(centre, 4.5 * (width / 12.0), Color(0.9, 0.92, 0.96))


func _draw_speedo(s: float, centre: Vector2, radius: float) -> void:
	var value := clampf(_smooth_kmh / _max_kmh, 0.0, 1.0)
	_dial(centre, radius, value, ACCENT.lerp(ACCENT_HOT, value), 12.0 * s, 1.2, ACCENT_HOT)
	var text := str(int(round(_smooth_kmh)))
	var px := radius * 0.62
	_text(centre + Vector2(-_width(text, px) * 0.5, px * 0.22), text, px, INK)
	var unit := "KM/H"
	_text(centre + Vector2(-_width(unit, radius * 0.17) * 0.5, radius * 0.38), unit, radius * 0.17,
		Color(1, 1, 1, 0.55))


func _draw_tacho(s: float, centre: Vector2, radius: float) -> void:
	var redline_rpm := 6800.0
	var max_rpm := 8000.0
	var value := clampf(_smooth_rpm / max_rpm, 0.0, 1.0)
	var in_red := _smooth_rpm >= redline_rpm
	var needle_col := ACCENT_HOT if in_red else CYAN
	_dial(centre, radius, value, needle_col, 12.0 * s, redline_rpm / max_rpm, ACCENT_HOT)
	# rpm readout and gear under it
	var rpm_text := str(int(round(_smooth_rpm / 100.0) * 100))
	var px := radius * 0.42
	_text(centre + Vector2(-_width(rpm_text, px) * 0.5, px * 0.1), rpm_text, px, INK)
	var unit := "RPM"
	_text(centre + Vector2(-_width(unit, radius * 0.15) * 0.5, radius * 0.26), unit, radius * 0.15,
		Color(1, 1, 1, 0.5))
	var badge := Rect2(centre + Vector2(-radius * 0.26, radius * 0.4), Vector2(radius * 0.52, radius * 0.4))
	_round_rect(badge, 6.0 * s, Color(0.06, 0.07, 0.1, 0.9), PANEL_EDGE, 1.5 * s)
	var gp := radius * 0.3
	_text(badge.position + Vector2((badge.size.x - _width(_gear, gp)) * 0.5, badge.size.y * 0.78),
		_gear, gp, needle_col)
	# shift light bar above the dial
	var bar_w := radius * 1.5
	var bar_pos := centre + Vector2(-bar_w * 0.5, -radius - 26.0 * s)
	var fill := clampf((_smooth_rpm - 7600.0) / 400.0, 0.0, 1.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.018)
	_round_rect(Rect2(bar_pos, Vector2(bar_w, 7.0 * s)), 3.0 * s, Color(1, 1, 1, 0.08), PANEL_EDGE, 0.0)
	if fill > 0.0:
		_round_rect(Rect2(bar_pos, Vector2(bar_w * fill, 7.0 * s)), 3.0 * s,
			Color(1.0, 0.24, 0.10, pulse), Color(0, 0, 0, 0), 0.0)


func _draw_nitro(s: float, size: Vector2, radius: float) -> void:
	var segments := 10
	var bar_w := 14.0 * s
	var bar_h := radius * 1.5
	var pos := Vector2(size.x - 30.0 * s, size.y - 34.0 * s - bar_h)
	var gap := 3.0 * s
	var seg_h := (bar_h - gap * float(segments - 1)) / float(segments)
	var lit := int(round(_nitro * float(segments)))
	for i in range(segments):
		var y := pos.y + bar_h - float(i + 1) * seg_h - float(i) * gap
		var on: bool = int(i) < lit
		var col := Color(0.25, 0.85, 1.0)
		if _nitro_on:
			col = Color(0.65, 0.98, 1.0)
		if not on:
			col = Color(1, 1, 1, 0.10)
		_round_rect(Rect2(Vector2(pos.x, y), Vector2(bar_w, seg_h)), 2.0 * s, col, Color(0, 0, 0, 0), 0.0)
	if _nitro_on:
		var label := "BOOST"
		_text(pos + Vector2(-bar_w - _width(label, 12.0 * s) - 6.0 * s, bar_h * 0.5), label,
			12.0 * s, Color(0.6, 0.98, 1.0))


func _draw_toast(s: float, size: Vector2) -> void:
	if _toast_time <= 0.0 or _toast_text.is_empty():
		return
	var alpha := clampf(_toast_time / maxf(0.001, _toast_duration), 0.0, 1.0)
	var text_size := 30.0 * s
	var w := _width(_toast_text, text_size) + 60.0 * s
	var box := Rect2(Vector2(size.x * 0.5 - w * 0.5, 92.0 * s), Vector2(w, 52.0 * s))
	_round_rect(box, 10.0 * s, Color(0.03, 0.04, 0.06, 0.55 * alpha), Color(1, 1, 1, 0.08 * alpha), 1.5 * s)
	_text(box.position + Vector2(30.0 * s, 34.0 * s), _toast_text, text_size, Color(1, 1, 1, alpha))


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

func _text(pos: Vector2, text: String, px: float, color: Color) -> void:
	_panel.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(max(8.0, px)), color)


func _width(text: String, px: float) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(max(8.0, px))).x


func _round_rect(rect: Rect2, radius: float, fill: Color, edge: Color, edge_w: float) -> void:
	_panel.draw_rect(rect, fill, true)
	if edge_w > 0.0 and edge.a > 0.0:
		_panel.draw_rect(rect, edge, false, edge_w)
	if radius > 0.0:
		# soften the corners with four small arcs so the panels do not look like boxes
		for corner in [Vector2(rect.position.x + radius, rect.position.y + radius),
				Vector2(rect.end.x - radius, rect.position.y + radius),
				Vector2(rect.position.x + radius, rect.end.y - radius),
				Vector2(rect.end.x - radius, rect.end.y - radius)]:
			_panel.draw_circle(corner, radius * 0.0, fill)


func _clock(seconds: float) -> String:
	if seconds <= 0.0:
		return "0:00.00"
	var m := int(seconds) / 60
	var rest := seconds - float(m * 60)
	return "%d:%05.2f" % [m, rest]
