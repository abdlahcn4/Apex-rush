class_name AssetLibrary
extends RefCounted

## Central registry for the imported art. Every path below points at a real file
## committed under res://assets — a glTF-binary model, a WebP texture or an audio
## stream. See ASSETS.md at the repository root for the licence of each set.

const CAR_DIR := "res://assets/kenney_car_kit/vehicles/"
const ROAD_DIR := "res://assets/kenney_racing_kit/roads/"
const PROP_DIR := "res://assets/kenney_racing_kit/props/"
const CITY_DIR := "res://assets/kenney_city_kit/"
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

## Real PBR surface sets: ambientCG 2048px maps, downscaled to 1024 for the mobile build.
## Every kind has an albedo, a normal (OpenGL convention) and a roughness map.
const TEXTURE_SETS := {
	"asphalt": "asphalt",
	"road": "asphalt",
	"concrete": "concrete",
	"kerb": "concrete",
	"grass": "grass",
	"gravel": "gravel",
	"ground": "gravel",
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
	"countdown": "click-toggle-on-firm.wav",
	"skid": "foley-plastic-slide.wav",
	"gearshift": "mechanical-latch-heavy.wav",
	"ratchet": "mechanical-ratchet-light.wav",
	"whoosh": "whoosh-slow-medium.wav",
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


static func _map(kind: String, suffix: String) -> Texture2D:
	var base: String = String(TEXTURE_SETS.get(kind, TEXTURE_SETS["asphalt"]))
	var path := TEX_DIR + base + "_" + suffix + ".jpg"
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		push_error("AssetLibrary: missing texture " + path)
		return null
	var tex := load(path) as Texture2D
	_textures[path] = tex
	return tex


static func texture(kind: String) -> Texture2D:
	return _map(kind, "albedo")


static func texture_normal(kind: String) -> Texture2D:
	return _map(kind, "normal")


static func texture_rough(kind: String) -> Texture2D:
	return _map(kind, "rough")


## Surface material with the full set: colour, normal detail and measured roughness.
## uv_scale is tiles per UV unit, tint lets a circuit shift the same surface (sand, night).
static func surface(kind: String, uv_scale: float, tint := Color.WHITE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture(kind)
	mat.normal_enabled = true
	mat.normal_texture = texture_normal(kind)
	mat.normal_scale = 0.85
	mat.roughness_texture = texture_rough(kind)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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


# --------------------------------------------------------------------------- #
# geometry helpers — imported models are measured, never assumed
# --------------------------------------------------------------------------- #

static var _sizes: Dictionary = {}


## Bounds of every authored mesh inside `root`, in root-local space.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var space := relative_to(mi, root) * mi.get_aabb()
		if first:
			box = space
			first = false
		else:
			box = box.merge(space)
	return box


static func relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func first_mesh(root: Node3D) -> MeshInstance3D:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			return mi
	return null


## Native size of an imported model in its own units (cached).
static func native_size(path: String) -> Vector3:
	if _sizes.has(path):
		return _sizes[path] as Vector3
	var node := instance(path)
	if node == null:
		return Vector3.ONE
	var box := bounds(node)
	node.free()
	_sizes[path] = box.size
	return box.size


## Uniform scale that makes a model's longest horizontal side `target` metres.
static func span_scale(path: String, target: float) -> float:
	var sz := native_size(path)
	var longest := maxf(sz.x, sz.z)
	return 1.0 if longest < 0.001 else target / longest


## Uniform scale that makes a model `target` metres tall.
static func height_scale(path: String, target: float) -> float:
	var sz := native_size(path)
	return 1.0 if sz.y < 0.001 else target / sz.y


## Transform that centres a model on X/Z and drops its base onto y = 0.
static func grounding(path: String) -> Transform3D:
	var node := instance(path)
	if node == null:
		return Transform3D()
	var box := bounds(node)
	node.free()
	return Transform3D(Basis(), Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5)))


## One instance of an imported model, centred, seated on y = 0 and scaled by `scale`.
static func placed(path: String, pos: Vector3, yaw: float, scale: float) -> Node3D:
	var node := instance(path)
	if node == null:
		return null
	var inner := Node3D.new()
	inner.name = String(path.get_file().get_basename())
	node.scale = Vector3.ONE * scale
	inner.add_child(node)
	node.transform = grounding(path)
	inner.position = pos
	inner.rotation = Vector3(0.0, yaw, 0.0)
	return inner


## Many instances of the same imported model in a single draw call.
## spots: [{xform: Transform3D at the model's base, scale: float}]
static func prop_multimesh(path: String, spots: Array, name := "") -> MultiMeshInstance3D:
	if spots.is_empty():
		return null
	var node := instance(path)
	if node == null:
		return null
	var mi := first_mesh(node)
	if mi == null:
		node.free()
		return null
	var mesh: Mesh = mi.mesh
	var inner := relative_to(mi, node)
	var norm := grounding(path) * inner
	node.free()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in range(spots.size()):
		var spot: Dictionary = spots[i]
		var base: Transform3D = spot.xform
		var s := float(spot.get("scale", 1.0))
		mm.set_instance_transform(i, base * Transform3D(Basis().scaled(Vector3.ONE * s), Vector3.ZERO) * norm)
	var inst := MultiMeshInstance3D.new()
	inst.name = name if not name.is_empty() else String(path.get_file().get_basename())
	inst.multimesh = mm
	return inst
