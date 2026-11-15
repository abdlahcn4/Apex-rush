class_name AudioDirector
extends Node

## Drives every sound from real recorded samples (see ASSETS.md):
##   engine  - Kenney engine loop, pitched by RPM, re-triggered per gear change
##   skid    - Kenney/Wyzowl slide recording, filtered by drift load
##   impacts - Wyzowl impact recordings, pooled so overlaps do not cut each other
##   ui      - Wyzowl interface clicks
## No sample is synthesised at runtime; pitch and level are the only processing.

const ENGINE_DB_IDLE := -20.0
const ENGINE_DB_FULL := -7.0
const SKID_SILENT := -60.0

var engine: AudioStreamPlayer
var skid: AudioStreamPlayer
var ui: AudioStreamPlayer
var shift: AudioStreamPlayer
var countdown: AudioStreamPlayer

var _impacts: Array = []
var _impact_index := 0
var _impact_cooldown := 0.0
var _last_gear := ""
var _muted := false


func _ready() -> void:
	engine = _loop("engine", ENGINE_DB_IDLE, 0.7)
	skid = _loop("skid", SKID_SILENT, 1.35)
	ui = _one_shot("click", -6.0)
	shift = _one_shot("gearshift", -9.0)
	countdown = _one_shot("countdown", -4.0)
	for kind in ["impact_heavy", "impact_medium", "impact_light"]:
		var p := _one_shot(kind, -4.0)
		if p != null:
			_impacts.append(p)


func _loop(kind: String, db: float, pitch: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = kind
	var stream := AssetLibrary.audio(kind)
	if stream == null:
		return p
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var per_frame := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if wav.stereo:
			per_frame *= 2
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.data.size() / per_frame)
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	return p


func _one_shot(kind: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = kind
	var stream := AssetLibrary.audio(kind)
	if stream == null:
		return null
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


## Called every frame from the game loop with the live vehicle state.
func update(v: ApexVehicle, dt: float) -> void:
	if v == null:
		return
	var blend := minf(1.0, dt * 6.0)

	if engine != null:
		var rpm01 := clampf((v.rpm - 800.0) / 6600.0, 0.0, 1.0)
		var target_pitch := lerpf(0.62, 1.9, rpm01)
		if v.nitro_active:
			target_pitch *= 1.07
		engine.pitch_scale = lerpf(engine.pitch_scale, target_pitch, blend)
		var target_db := lerpf(ENGINE_DB_IDLE, ENGINE_DB_FULL, rpm01)
		target_db += 5.0 * clampf(v.throttle, 0.0, 1.0)
		engine.volume_db = lerpf(engine.volume_db, target_db, blend)

	if skid != null:
		var slip := clampf(v.drift, 0.0, 1.0)
		if v.hand and absf(v.vF) > 6.0:
			slip = maxf(slip, 0.75)
		var target_db := SKID_SILENT
		if slip > 0.18:
			target_db = lerpf(-26.0, -10.0, slip)
		skid.volume_db = lerpf(skid.volume_db, target_db, minf(1.0, dt * 8.0))
		skid.pitch_scale = lerpf(1.15, 1.75, slip)

	if v.gear != _last_gear:
		if _last_gear != "" and v.gear != "N" and v.gear != "R" and shift != null:
			shift.pitch_scale = 0.92 + randf() * 0.18
			shift.play()
		_last_gear = v.gear

	if v.impact > 0.9 and _impact_cooldown <= 0.0:
		play_impact(v.impact)
	_impact_cooldown = maxf(0.0, _impact_cooldown - dt)


func play_impact(strength: float) -> void:
	_impact_cooldown = 0.28
	if _impacts.is_empty():
		return
	var p: AudioStreamPlayer = _impacts[_impact_index % _impacts.size()]
	_impact_index += 1
	if p == null:
		return
	p.volume_db = clampf(-16.0 + strength * 2.2, -18.0, 0.0)
	p.pitch_scale = 0.9 + randf() * 0.2
	p.play()


func play_ui() -> void:
	if ui != null:
		ui.play()


func play_countdown() -> void:
	if countdown != null:
		countdown.play()


func is_muted() -> bool:
	return _muted


func set_muted(muted: bool) -> void:
	_muted = muted
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, muted)
