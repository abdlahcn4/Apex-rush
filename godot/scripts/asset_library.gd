class_name AssetLibrary
extends RefCounted

## Central registry for the imported art. Every path below points at a real file
## committed under res://assets — a glTF-binary model, a WebP texture or an audio
## stream. See ASSETS.md at the repository root for the licence of each set.

const CAR_DIR := "res://assets/kenney_car_kit/vehicles/"
const ROAD_DIR := "res://assets/kenney_racing_kit/roads/"
const PROP_DIR := "res://assets/kenney_racing_kit/props/"
const TEX_DIR := "res://assets/textures/"
const AUDIO_DIR := "res://assets/audio/"

## Game car id -> imported model. Chosen so every tier drives a different body.
const CAR_FILES := {
	"vortex": "hatchback-sports.glb",
	"falcon": "sedan-sports.glb",
	"titan": "suv-luxury.glb",
	"nimbus": "sedan.glb",
	"raptor": "race.glb",
	"phantom": "race-future.glb",
}

const ROAD_FILES := {
	"straight": "roadStraight.glb",
	"straight_long": "roadStraightLong.glb",
	"straight_arrow": "roadStraightArrow.glb",
	"corner": "roadCornerLarge.glb",
	"corner_small": "roadCornerSmall.glb",
	"corner_wall": "roadCornerLargeWall.glb",
	"corner_border": "roadCornerLargeBorder.glb",
	"curved": "roadCurved.glb",
	"crossing": "roadCrossing.glb",
	"end": "roadEnd.glb",
	"split": "roadSplit.glb",
	"split_large": "roadSplitLarge.glb",
	"split_round": "roadSplitRound.glb",
	"start": "roadStart.glb",
	"start_positions": "roadStartPositions.glb",
	"bridge": "roadStraightBridge.glb",
	"bridge_mid": "roadStraightBridgeMid.glb",
	"bridge_start": "roadStraightBridgeStart.glb",
	"ramp": "roadRamp.glb",
	"ramp_long": "roadRampLong.glb",
	"side": "roadSide.glb",
	"bump": "roadBump.glb",
	"pit_straight": "roadPitStraight.glb",
	"pit_entry": "roadPitEntry.glb",
}

const PROP_FILES := {
	"barrier": "barrierRed.glb",
	"barrier_white": "barrierWhite.glb",
	"barrier_wall": "barrierWall.glb",
	"fence": "fenceStraight.glb",
	"fence_curved": "fenceCurved.glb",
	"rail": "rail.glb",
	"rail_double": "railDouble.glb",
	"grandstand": "grandStand.glb",
	"grandstand_awning": "grandStandAwning.glb",
	"grandstand_covered": "grandStandCovered.glb",
	"grandstand_round": "grandStandRound.glb",
	"billboard": "billboard.glb",
	"billboard_low": "billboardLow.glb",
	"flag_green": "flagGreen.glb",
	"flag_red": "flagRed.glb",
	"flag_checkers": "flagCheckers.glb",
	"light_post": "lightPostLarge.glb",
	"light_post_modern": "lightPostModern.glb",
	"overhead_lights": "overheadLights.glb",
	"overhead": "overhead.glb",
	"pits_garage": "pitsGarage.glb",
	"pits_office": "pitsOffice.glb",
	"tent": "tent.glb",
	"tent_long": "tentLong.glb",
	"tree_large": "treeLarge.glb",
	"tree_small": "treeSmall.glb",
	"grass": "grass.glb",
	"pylon": "pylon.glb",
	"banner_tower": "bannerTowerRed.glb",
	"ramp": "ramp.glb",
}

const TEXTURES := {
	"asphalt": "asphalt.webp",
	"road": "road.webp",
	"concrete": "concrete.webp",
	"grass": "grass.webp",
	"gravel": "gravel.webp",
	"ground": "ground.webp",
}

const AUDIO := {
	"engine": "kenney_engineCircular_000.ogg",
	"engine_alt": "kenney_engineCircular_001.ogg",
	"engine_low": "kenney_spaceEngineLow_000.ogg",
	"impact_heavy": "impact-heavy-hard.wav",
	"impact_medium": "impact-medium-hard.wav",
	"impact_light": "impact-light-hard.wav",
	"click": "click-button-firm.wav",
	"hover": "click-hover-soft.wav",
}

static var _scenes: Dictionary = {}
static var _textures: Dictionary = {}
static var _streams: Dictionary = {}


# --------------------------------------------------------------------------- #
# lookups
# --------------------------------------------------------------------------- #

static func car(id: String) -> PackedScene:
	var file: String = String(CAR_FILES.get(id, CAR_FILES["vortex"]))
	return scene(CAR_DIR + file)


static func road(kind: String) -> PackedScene:
	var file: String = String(ROAD_FILES.get(kind, ROAD_FILES["straight"]))
	return scene(ROAD_DIR + file)


static func prop(kind: String) -> PackedScene:
	var file: String = String(PROP_FILES.get(kind, PROP_FILES["barrier"]))
	return scene(PROP_DIR + file)


static func texture(kind: String) -> Texture2D:
	var file: String = String(TEXTURES.get(kind, TEXTURES["asphalt"]))
	var path := TEX_DIR + file
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		push_error("AssetLibrary: missing texture " + path)
		return null
	var tex := load(path) as Texture2D
	_textures[path] = tex
	return tex


static func audio(kind: String) -> AudioStream:
	var file: String = String(AUDIO.get(kind, AUDIO["click"]))
	var path := AUDIO_DIR + file
	if _streams.has(path):
		return _streams[path] as AudioStream
	if not ResourceLoader.exists(path):
		push_error("AssetLibrary: missing audio " + path)
		return null
	var stream := load(path) as AudioStream
	_streams[path] = stream
	return stream


static func scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path] as PackedScene
	if not ResourceLoader.exists(path):
		push_error("AssetLibrary: missing model " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("AssetLibrary: not a PackedScene: " + path)
		return null
	_scenes[path] = ps
	return ps


## Instantiate an imported model, or null when the file is absent.
static func instance(path: String) -> Node3D:
	var ps := scene(path)
	if ps == null:
		return null
	var node := ps.instantiate()
	if node is Node3D:
		return node as Node3D
	node.queue_free()
	push_error("AssetLibrary: model root is not Node3D: " + path)
	return null


static func has_model(path: String) -> bool:
	return ResourceLoader.exists(path)
