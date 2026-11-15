class_name CarBuilder
extends RefCounted

## Builds the player car from an imported glTF model (Kenney Car Kit, CC0).
## The bodywork, glass, spoilers and wheels are all authored geometry that ships in
## res://assets — nothing here is generated from primitives.
##
## The public contract is unchanged from the procedural version so ApexVehicle keeps
## working as-is:  {root, body, wheels[{pivot, spin, front}], tail_mat, wr, spec}
##
## Assembly steps per car:
##   1. instance the glTF and measure it,
##   2. uniformly scale it so its length matches the physics spec,
##   3. drop it so the tyre contact patch sits on y = 0,
##   4. lift each authored wheel mesh out into a pivot(steer) -> spin(roll) rig,
##   5. bolt emissive lamp lenses + headlight spots onto the authored shell.

const LAMP_RED := Color(1.0, 0.06, 0.10)
const LAMP_WHITE := Color(1.0, 0.97, 0.90)

const SPECS := {
	"vortex": {
		"name": "Vortex GT", "top": 70.0, "accel": 12.0, "brake": 26.0, "handling": 1.0,
		"color": "#2ecc40", "tier": 1, "wing": 1,
		"body": {"L": 4.5, "W": 2.0, "wb": 1.35, "wr": 0.36, "noseY": 0.52, "hoodY": 0.74,
			"beltY": 0.86, "tailY": 0.96, "cabF": 0.75, "roofF": -0.05, "roofB": -0.85,
			"cabB": -1.55, "cabTop": 1.18},
	},
	"falcon": {
		"name": "Falcon RS", "top": 75.0, "accel": 13.0, "brake": 28.0, "handling": 1.06,
		"color": "#e63946", "tier": 2, "wing": 2,
		"body": {"L": 4.55, "W": 1.95, "wb": 1.38, "wr": 0.36, "noseY": 0.56, "hoodY": 0.8,
			"beltY": 0.9, "tailY": 1.0, "cabF": 0.6, "roofF": -0.15, "roofB": -1.0,
			"cabB": -1.65, "cabTop": 1.3},
	},
	"titan": {
		"name": "Titan V8", "top": 79.0, "accel": 14.5, "brake": 25.0, "handling": 0.94,
		"color": "#f4a261", "tier": 2, "wing": 1,
		"body": {"L": 4.8, "W": 2.02, "wb": 1.45, "wr": 0.38, "noseY": 0.72, "hoodY": 0.92,
			"beltY": 0.96, "tailY": 0.97, "cabF": 0.3, "roofF": -0.3, "roofB": -1.15,
			"cabB": -1.65, "cabTop": 1.36},
	},
	"nimbus": {
		"name": "Nimbus E-GT", "top": 81.0, "accel": 17.0, "brake": 29.0, "handling": 1.08,
		"color": "#f1faee", "tier": 3, "wing": 0,
		"body": {"L": 4.7, "W": 1.98, "wb": 1.42, "wr": 0.37, "noseY": 0.56, "hoodY": 0.78,
			"beltY": 0.88, "tailY": 0.98, "cabF": 0.9, "roofF": 0.0, "roofB": -1.2,
			"cabB": -2.0, "cabTop": 1.3},
	},
	"raptor": {
		"name": "Raptor X", "top": 88.0, "accel": 17.5, "brake": 31.0, "handling": 1.12,
		"color": "#ffbe0b", "tier": 4, "wing": 2,
		"body": {"L": 4.6, "W": 2.05, "wb": 1.38, "wr": 0.36, "noseY": 0.42, "hoodY": 0.66,
			"beltY": 0.8, "tailY": 0.92, "cabF": 0.85, "roofF": 0.15, "roofB": -0.6,
			"cabB": -1.4, "cabTop": 1.1},
	},
	"phantom": {
		"name": "Phantom LM", "top": 95.0, "accel": 19.0, "brake": 34.0, "handling": 1.18,
		"color": "#7b2ff7", "tier": 5, "wing": 2,
		"body": {"L": 4.9, "W": 2.05, "wb": 1.5, "wr": 0.36, "noseY": 0.38, "hoodY": 0.6,
			"beltY": 0.78, "tailY": 0.96, "cabF": 0.7, "roofF": 0.1, "roofB": -0.5,
			"cabB": -1.0, "cabTop": 1.08},
	},
}

const ORDER := ["vortex", "falcon", "titan", "nimbus", "raptor", "phantom"]


static func spec(id: String) -> Dictionary:
	return SPECS.get(id, SPECS["vortex"])


## Port of carStats(): upgrade levels scale top speed, accel, braking and handling.
static func stats(id: String, upgrades: Dictionary = {}) -> Dictionary:
	var s := spec(id)
	var e := float(upgrades.get("engine", 0))
	var br := float(upgrades.get("brakes", 0))
	var hd := float(upgrades.get("handling", 0))
	return {
		"top": float(s.top) * (1.0 + 0.035 * e),
		"accel": float(s.accel) * (1.0 + 0.07 * e),
		"brake": float(s.brake) * (1.0 + 0.1 * br),
		"handling": float(s.handling) * (1.0 + 0.045 * hd),
	}


static func build(id: String, color: Color, quality := 2) -> Dictionary:
	var s := spec(id)
	# The detailed CC-BY Khronos car is the shipped vehicle; the Kenney kit path below
	# stays as a fallback so the game still builds if that asset is ever missing.
	if CarHero.available():
		return CarHero.build(s, color)
	var b: Dictionary = s.body
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var tail_mat := _lamp_mat(LAMP_RED)
	var head_mat := _lamp_mat(LAMP_WHITE)
	var wheels: Array = []
	var out := {
		"root": root,
		"body": body,
		"wheels": wheels,
		"tail_mat": tail_mat,
		"head_mat": head_mat,
		"wr": float(b.wr),
		"spec": s,
		"model": "",
		"lights": [],
	}

	var model := AssetLibrary.instance(AssetLibrary.CAR_DIR + String(AssetLibrary.CAR_FILES.get(id, "hatchback-sports.glb")))
	if model == null:
		push_error("CarBuilder: could not instance imported car for id " + id)
		return out
	out["model"] = model.name

	# --- measure the authored model, then scale it to the physics spec length
	var ext := AssetLibrary.bounds(model)
	if ext.size.z < 0.05 or ext.size.y < 0.05:
		push_error("CarBuilder: empty bounds for car model " + id)
		root.add_child(model)
		return out
	var factor := clampf(float(b.L) / ext.size.z, 0.2, 8.0)
	root.scale = Vector3.ONE * factor
	out["scale"] = factor
	out["length"] = ext.size.z * factor
	out["width"] = ext.size.x * factor

	# --- sit the tyres on the road (vehicle.gd owns `body.position`, so the
	#     offset lives on an inner node it never touches)
	var fix := Node3D.new()
	fix.name = "GroundFix"
	fix.position = Vector3(0.0, -ext.position.y, 0.0)
	body.add_child(fix)
	fix.add_child(model)

	# --- wheels: authored meshes -> pivot(steer) / spin(roll)
	var wheel_radius := 0.0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		if not mi.name.to_lower().begins_with("wheel"):
			continue
		var rel := AssetLibrary.relative_to(mi, model)
		var box := mi.get_aabb()
		var centre: Vector3 = rel * box.get_center()
		var pivot := Node3D.new()
		pivot.name = "WheelPivot"
		pivot.position = centre + Vector3(0.0, -ext.position.y, 0.0)
		root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "WheelSpin"
		pivot.add_child(spin)
		mi.owner = null
		var holder := mi.get_parent()
		if holder != null and mi.get_parent() == holder:
			holder.remove_child(mi)
		spin.add_child(mi)
		mi.transform = Transform3D(Basis(), -box.get_center())
		wheels.append({"pivot": pivot, "spin": spin, "front": centre.z > 0.0})
		wheel_radius = maxf(wheel_radius, box.size.y * 0.5)
	out["wr"] = maxf(0.1, wheel_radius * factor)

	_polish(model)

	# --- lamps: thin emissive lenses sitting on the authored rear/front faces
	var rear_z := ext.position.z
	var front_z := ext.position.z + ext.size.z
	var lamp_w := minf(ext.size.x * 0.30, 0.42)
	var lamp_h := minf(ext.size.y * 0.09, 0.11)
	for sx in [-1.0, 1.0]:
		var tail := _lens(lamp_w, lamp_h, tail_mat)
		tail.position = Vector3(float(sx) * ext.size.x * 0.28, ext.position.y + ext.size.y * 0.55, rear_z - 0.01)
		tail.rotation = Vector3(0.0, PI, 0.0)
		fix.add_child(tail)

		var head := _lens(lamp_w, lamp_h, head_mat)
		head.position = Vector3(float(sx) * ext.size.x * 0.28, ext.position.y + ext.size.y * 0.60, front_z + 0.01)
		fix.add_child(head)

		var beam := SpotLight3D.new()
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.light_energy = 3.0
		beam.spot_range = 42.0
		beam.spot_angle = 26.0
		beam.shadow_enabled = false
		beam.visible = false
		beam.position = Vector3(float(sx) * ext.size.x * 0.28, ext.position.y + ext.size.y * 0.5, front_z)
		beam.rotation = Vector3(deg_to_rad(-8.0), PI, 0.0)
		fix.add_child(beam)
		(out["lights"] as Array).append(beam)

	return out


## Repaint a car that is already built (garage paint picker, race restart).
static func set_paint(model: Dictionary, color: Color) -> void:
	if not model.has("paint_materials"):
		return
	var list: Array = model.paint_materials
	for i in range(list.size()):
		var m := list[i] as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color = color.darkened(0.22) if i % 2 == 1 else color


## Toggle the imported car's headlights (used at night / in the tunnel).
static func set_headlights(model: Dictionary, on: bool) -> void:
	if not model.has("lights"):
		return
	for n in model.lights:
		var l := n as SpotLight3D
		if l != null:
			l.visible = on


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

static func _lens(w: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The kit models ship with flat matte materials, which read as painted plastic under any
## light. Giving the authored surfaces a metallic sheen turns them into car paint without
## touching the geometry or the authored colour map. Wheels are skipped: tyres stay matte.
static func _polish(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.name.to_lower().begins_with("wheel"):
			continue
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(i)
			var base := src as StandardMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as StandardMaterial3D
			m.metallic = 0.5
			m.metallic_specular = 0.62
			m.roughness = 0.34
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mi.set_surface_override_material(i, m)


static func _lamp_mat(glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = glow.darkened(0.75)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 0.9
	m.roughness = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
