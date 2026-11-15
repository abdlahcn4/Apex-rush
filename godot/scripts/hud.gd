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
	if size.x < 32.0:
		return
	var s := minf(size.x / 1280.0, size.y / 720.0)
	_draw_timing(s)
	_draw_speedo(s, size)
	_draw_nitro(s, size)
	_draw_toast(s, size)


func _draw_timing(s: float) -> void:
	var w := 290.0 * s
	var h := 104.0 * s
	var pos := Vector2(26.0 * s, 24.0 * s)
	_round_rect(Rect2(pos, Vector2(w, h)), 12.0 * s, PANEL, PANEL_EDGE, 2.0 * s)

	_text(pos + Vector2(18.0 * s, 30.0 * s), _title_text, 17.0 * s, Color(1, 1, 1, 0.72))
	var lap_text := "LAP %d / %d" % [_lap, _laps_total]
	_text(pos + Vector2(18.0 * s, 62.0 * s), lap_text, 26.0 * s, INK)
	_text(pos + Vector2(w - 18.0 * s - _width(_clock(_lap_time), 26.0 * s), 62.0 * s),
		_clock(_lap_time), 26.0 * s, ACCENT)
	_text(pos + Vector2(18.0 * s, 88.0 * s), "BEST  " + _clock(_best), 16.0 * s, Color(0.75, 0.8, 0.9, 0.9))


func _draw_speedo(s: float, size: Vector2) -> void:
	var radius := 104.0 * s
	var centre := Vector2(190.0 * s, size.y - 150.0 * s)
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)

	draw_circle(centre, radius + 16.0 * s, PANEL)
	# unlit track
	draw_arc(centre, radius, start, start + sweep, 64, TRACK_BG, 13.0 * s, true)
	# lit arc, colour shifts to red near the top of the range
	var lit_end := start + sweep * _needle
	if _needle > 0.02:
		var col := ACCENT.lerp(ACCENT_HOT, _needle)
		draw_arc(centre, radius, start, lit_end, 64, col, 13.0 * s, true)
	# tick marks
	var ticks := 10
	for i in range(ticks + 1):
		var a := start + sweep * (float(i) / float(ticks))
		var inner := radius - 18.0 * s
		var outer := radius - 10.0 * s
		var p1 := centre + Vector2(cos(a), sin(a)) * inner
		var p2 := centre + Vector2(cos(a), sin(a)) * outer
		draw_line(p1, p2, Color(1, 1, 1, 0.35), 2.0 * s, true)
	# needle
	var na := start + sweep * _needle
	var tip := centre + Vector2(cos(na), sin(na)) * (radius - 6.0 * s)
	draw_line(centre, tip, ACCENT_HOT, 3.0 * s, true)

	var speed_text := str(int(round(_smooth_kmh)))
	var speed_size := 54.0 * s
	var tw := _width(speed_text, speed_size)
	_text(centre + Vector2(-tw * 0.5, 12.0 * s), speed_text, speed_size, INK)
	var unit := "KM/H"
	_text(centre + Vector2(-_width(unit, 16.0 * s) * 0.5, 36.0 * s), unit, 16.0 * s, Color(1, 1, 1, 0.55))

	# gear badge
	var badge := Rect2(centre + Vector2(radius + 18.0 * s, -26.0 * s), Vector2(54.0 * s, 54.0 * s))
	_round_rect(badge, 10.0 * s, Color(0.06, 0.07, 0.1, 0.85), PANEL_EDGE, 2.0 * s)
	var gw := _width(_gear, 30.0 * s)
	_text(badge.position + Vector2((badge.size.x - gw) * 0.5, 36.0 * s), _gear, 30.0 * s, CYAN)

	# rpm strip under the clock: 20 segments, shift light at the end
	var strip_w := 300.0 * s
	var strip_pos := Vector2(centre.x - strip_w * 0.5, size.y - 44.0 * s)
	var seg_gap := 3.0 * s
	var seg_w := (strip_w - seg_gap * 19.0) / 20.0
	var rpm01 := clampf((_smooth_rpm - 800.0) / 6800.0, 0.0, 1.0)
	draw_rect(Rect2(strip_pos, Vector2(strip_w, 12.0 * s)), Color(1, 1, 1, 0.06), true)
	for i in range(20):
		var lit := rpm01 * 20.0 > float(i) + 0.35
		var col := CYAN
		if i >= 16:
			col = ACCENT_HOT
		elif i >= 12:
			col = ACCENT
		if not lit:
			col = Color(1, 1, 1, 0.10)
		draw_rect(Rect2(strip_pos + Vector2(float(i) * (seg_w + seg_gap), 0.0), Vector2(seg_w, 12.0 * s)), col, true)
	if rpm01 > 0.93:
		# shift light flash
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.02)
		draw_rect(Rect2(strip_pos + Vector2(0, -18.0 * s), Vector2(strip_w, 6.0 * s)), Color(1.0, 0.2, 0.1, pulse), true)


func _draw_nitro(s: float, size: Vector2) -> void:
	var w := 210.0 * s
	var h := 18.0 * s
	var pos := Vector2(size.x - w - 34.0 * s, size.y - 60.0 * s)
	_text(pos + Vector2(0.0, -8.0 * s), "NITRO", 15.0 * s, Color(1, 1, 1, 0.6))
	_round_rect(Rect2(pos, Vector2(w, h)), 6.0 * s, Color(1, 1, 1, 0.10), PANEL_EDGE, 1.0 * s)
	var fill := Color(0.25, 0.8, 1.0) if not _nitro_on else Color(0.55, 0.95, 1.0)
	_round_rect(Rect2(pos + Vector2(2.0 * s, 2.0 * s), Vector2((w - 4.0 * s) * _nitro, h - 4.0 * s)), 4.0 * s, fill, Color(0, 0, 0, 0), 0.0)
	if _nitro_on:
		_text(pos + Vector2(w + 10.0 * s, 15.0 * s), "BOOST", 15.0 * s, Color(0.55, 0.95, 1.0))


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
