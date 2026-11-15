class_name CarHero
extends RefCounted

## Assembles the detailed hero vehicle from the imported Khronos "Car Concept" glTF
## (CC-BY-4.0, 97 authored meshes: body panels, glass, interior, seats, steering wheel,
## rims, brake discs, callipers, lights). Nothing here is generated geometry - the code
## only re-parents authored nodes, re-tints authored materials and attaches lights.
##
## The result keeps the exact contract ApexVehicle expects:
##   {root, body, wheels[{pivot,spin,front}], tail_mat, head_mat, wr, spec, model, lights}
## plus extras the effects layer uses: {exhaust:[Node3D], cockpit:Node3D, paint:Array}

const HERO_PATH := "res://assets/vehicles/carconcept/CarConcept.glb"
const WHEEL_NAMES := ["WheelFrontL", "WheelFrontR", "WheelRearL", "WheelRearR"]

const LAMP_RED := Color(1.0, 0.05, 0.08)
const LAMP_WHITE := Color(1.0, 0.95, 0.86)
const LAMP_AMBER := Color(1.0, 0.52, 0.08)


static func available() -> bool:
	return ResourceLoader.exists(HERO_PATH)


static func build(spec: Dictionary, paint: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var tail_mat := _emissive(LAMP_RED, 1.1)
	var head_mat := _emissive(LAMP_WHITE, 1.0)
	var out := {
		"root": root,
		"body": body,
		"wheels": [],
		"tail_mat": tail_mat,
		"head_mat": head_mat,
		"wr": 0.36,
		"spec": spec,
		"model": "CarConcept",
		"lights": [],
		"exhaust": [],
		"cockpit": null,
		"paint_materials": [],
	}

	var scene := AssetLibrary.scene(HERO_PATH)
	if scene == null:
		push_error("CarHero: CarConcept.glb missing")
		return out
	var model := scene.instantiate() as Node3D
	if model == null:
		push_error("CarHero: CarConcept.glb did not instantiate a Node3D")
		return out

	var spec_body: Dictionary = spec.get("body", {})
	var target_len := float(spec_body.get("L", 4.6))
	var ext := AssetLibrary.bounds(model)
	if ext.size.z < 0.1:
		push_error("CarHero: empty bounds")
		body.add_child(model)
		return out
	var factor := clampf(target_len / ext.size.z, 0.05, 20.0)
	root.scale = Vector3.ONE * factor
	out["scale"] = factor
	out["length"] = ext.size.z * factor
	out["width"] = ext.size.x * factor

	# sit the tyres on y = 0 without touching vehicle.body (which owns the suspension)
	var fix := Node3D.new()
	fix.name = "GroundFix"
	fix.position = Vector3(0.0, -ext.position.y, 0.0)
	body.add_child(fix)
	fix.add_child(model)

	# --- paint, glass, lamps: re-tint the authored materials ----------------- #
	_restyle(model, paint, out, tail_mat, head_mat)

	# --- wheels: authored hubs become steer/roll pivots --------------------- #
	var wheel_radius := 0.0
	for wheel_name in WHEEL_NAMES:
		var node := model.find_child(wheel_name, true, false) as Node3D
		if node == null:
			continue
		var rel := AssetLibrary.relative_to(node, model)
		var centre := rel.origin + Vector3(0.0, -ext.position.y, 0.0)
		var box := _sub_aabb(node)
		var pivot := Node3D.new()
		pivot.name = "Pivot_" + wheel_name
		pivot.position = centre
		root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin_" + wheel_name
		pivot.add_child(spin)
		var holder := node.get_parent()
		if holder != null:
			holder.remove_child(node)
		spin.add_child(node)
		node.transform = Transform3D(rel.basis, Vector3.ZERO)
		# wheels turn the other way in glTF space on the right-hand side
		var front: bool = String(wheel_name).contains("Front")
		out["wheels"].append({"pivot": pivot, "spin": spin, "front": front})
		wheel_radius = maxf(wheel_radius, box.size.y * 0.5)
	out["wr"] = maxf(0.12, wheel_radius * factor)

	# --- exhaust tips and cockpit eye point, derived from the authored bounds #
	var rear_z := ext.position.z
	var half_w := ext.size.x * 0.5
	for sx in [-1.0, 1.0]:
		var tip := Node3D.new()
		tip.name = "Exhaust"
		tip.position = Vector3(float(sx) * half_w * 0.42, ext.position.y + ext.size.y * 0.24,
			rear_z + ext.size.z * 0.03)
		fix.add_child(tip)
		(out["exhaust"] as Array).append(tip)

	var eye_source := model.find_child("InteriorSteeringWheel01", true, false) as Node3D
	if eye_source != null:
		var eye := Node3D.new()
		eye.name = "CockpitEye"
		eye.position = AssetLibrary.relative_to(eye_source, model).origin + Vector3(0.0, 0.12, 0.0)
		fix.add_child(eye)
		out["cockpit"] = eye

	# --- headlight beams ----------------------------------------------------- #
	var front_z := ext.position.z + ext.size.z
	for sx in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.light_color = Color(1.0, 0.95, 0.86)
		beam.light_energy = 3.2
		beam.spot_range = 48.0
		beam.spot_angle = 27.0
		beam.shadow_enabled = false
		beam.visible = false
		beam.position = Vector3(float(sx) * half_w * 0.62, ext.position.y + ext.size.y * 0.5, front_z)
		beam.rotation = Vector3(deg_to_rad(-7.0), PI, 0.0)
		fix.add_child(beam)
		(out["lights"] as Array).append(beam)

	return out


## Walks every surface of the authored car and swaps only the materials that carry a
## meaning we care about: paint, glass, lights, rims, tyres, brakes.
static func _restyle(model: Node3D, paint: Color, out: Dictionary, tail_mat: StandardMaterial3D,
		head_mat: StandardMaterial3D) -> void:
	var seen := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var name_key := src.resource_name
			if seen.has(name_key) and seen[name_key] != null:
				mi.set_surface_override_material(i, seen[name_key])
				continue
			var made: StandardMaterial3D = _restyle_one(name_key, src, paint, tail_mat, head_mat, out)
			if made != null:
				seen[name_key] = made
				mi.set_surface_override_material(i, made)


static func _restyle_one(name_key: String, src: StandardMaterial3D, paint: Color,
		tail_mat: StandardMaterial3D, head_mat: StandardMaterial3D,
		out: Dictionary) -> StandardMaterial3D:
	var key := name_key.to_lower()

	if key.contains("paint"):
		var m := _copy_base(src)
		var shade := paint
		if key.contains("paint 2"):
			shade = paint.darkened(0.16)
		if key.contains("pearl"):
			shade = paint.lightened(0.10)
		elif key.contains("graphite"):
			shade = paint.darkened(0.62)
		m.albedo_color = shade
		m.albedo_texture = null
		# The authored paint ships metallic 1.0 (the glTF default) plus a panel-detail
		# normal map. Fully metallic paint mirrors the HDRI, and the normal map stipples
		# that mirror into coloured noise. Automotive paint is a dielectric tinted base
		# under a clearcoat, so: low metalness, mid roughness, strong clearcoat, no normal
		# perturbation on the panels.
		m.metallic = 0.28
		m.roughness = 0.36
		m.metallic_specular = 0.52
		m.normal_enabled = false
		m.ao_enabled = true
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.16
		m.rim_enabled = false
		(out["paint_materials"] as Array).append(m)
		return m

	if key.contains("glass"):
		var m := _copy_base(src)
		m.albedo_color = Color(0.05, 0.07, 0.09, 0.42)
		m.metallic = 0.0
		m.metallic_specular = 0.6
		m.roughness = 0.03
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.02
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.rim_enabled = true
		m.rim = 0.5
		return m

	if key.contains("brakelight") or key.contains("taillight"):
		return tail_mat
	if key.contains("headlight"):
		return head_mat
	if key.contains("signallight") or key.contains("turnsignal"):
		return _emissive(LAMP_AMBER, 0.55)

	if key.contains("rim"):
		var m := _copy_base(src)
		m.metallic = 0.86
		m.roughness = 0.31
		m.albedo_color = Color(0.26, 0.27, 0.30)
		m.clearcoat_enabled = true
		m.clearcoat = 0.5
		m.clearcoat_roughness = 0.2
		return m
	if key.contains("tire") or key.contains("tyre"):
		var m := _copy_base(src)
		m.metallic = 0.0
		m.roughness = 0.88
		return m
	if key.contains("disc"):
		var m := _copy_base(src)
		m.metallic = 0.72
		m.roughness = 0.58
		return m
	if key.contains("brake"):
		var m := _copy_base(src)
		m.metallic = 0.6
		m.roughness = 0.35
		return m
	if key.contains("mirror"):
		var m := _copy_base(src)
		m.metallic = 0.9
		m.roughness = 0.06
		m.albedo_color = Color(0.78, 0.80, 0.84)
		return m
	if key.contains("dash"):
		# instrument glow is the one authored emissive worth keeping
		var m := _copy_base(src)
		m.roughness = maxf(0.45, src.roughness)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.36, 0.06)
		m.emission_energy_multiplier = 0.55
		return m
	if key.contains("interior") or key.contains("seat") or key.contains("floormat"):
		var m := _copy_base(src)
		m.roughness = maxf(0.55, src.roughness)
		m.metallic = minf(0.2, src.metallic)
		return m
	if key.contains("brake"):
		var m := _copy_base(src)
		m.metallic = 0.35
		m.roughness = 0.42
		return m
	# everything else keeps its authored texture set but loses the stray emissive: the
	# source file marks rims, hardware and badges as emissive with factor 1.0, which
	# blown out into the bloom pass and produced the gold speckle
	return _copy_base(src)


static func _copy_base(src: StandardMaterial3D) -> StandardMaterial3D:
	var m := src.duplicate() as StandardMaterial3D
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# nothing on a car body emits light except the lamps, which are built separately
	m.emission_enabled = false
	m.emission = Color.BLACK
	m.emission_texture = null
	m.emission_energy_multiplier = 0.0
	m.rim_enabled = false
	return m


static func _emissive(glow: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = glow.darkened(0.55)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Combined AABB of a node and its mesh children, in that node's parent space.
static func _sub_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != node.get_parent():
			if walk is Node3D and walk != node:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var box := xf * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	if first:
		return AABB(Vector3.ZERO, Vector3.ONE * 0.5)
	return out
