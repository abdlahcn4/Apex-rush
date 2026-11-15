class_name CarBuilder
extends RefCounted

## Port of buildCar() from public/js/cars.js.
## The original extrudes a side-view Shape across the car's width and bolts boxes on
## for lights, wing, mirrors and wheels. Here the silhouette is a polygon extruded by
## MeshKit.extrude_profile, and the trim is primitives.

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
	var b: Dictionary = s.body
	var root := Node3D.new()
	root.name = "Model"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint := _paint(color, quality)
	var glass := _glass()
	var carbon := MeshKit.solid(Color(0.10, 0.11, 0.13), 0.35, 0.6)
	var black := MeshKit.solid(Color(0.05, 0.05, 0.06), 0.55, 0.2)

	var hl := float(b.L) * 0.5
	var w := float(b.W)

	# --- main shell: side silhouette extruded across the width
	var prof := PackedVector2Array([
		Vector2(-hl, 0.30),
		Vector2(hl, 0.30),
		Vector2(hl, float(b.noseY)),
		Vector2(hl - 0.6, float(b.hoodY)),
		Vector2(float(b.cabF), float(b.beltY)),
		Vector2(float(b.roofF), float(b.cabTop) - 0.03),
		Vector2(float(b.roofB), float(b.cabTop)),
		Vector2(float(b.cabB), float(b.beltY) + 0.03),
		Vector2(-hl + 0.2, float(b.tailY)),
		Vector2(-hl, float(b.tailY) - 0.06),
	])
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = MeshKit.extrude_profile(prof, w - 0.24)
	shell.material_override = paint
	body.add_child(shell)

	# --- cabin glass
	var cab := PackedVector2Array([
		Vector2(float(b.cabF) + 0.05, float(b.beltY) - 0.02),
		Vector2(float(b.roofF), float(b.cabTop) - 0.01),
		Vector2(float(b.roofB), float(b.cabTop)),
		Vector2(float(b.cabB) - 0.05, float(b.beltY) + 0.02),
	])
	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	cabin.mesh = MeshKit.extrude_profile(cab, w * 0.78 - 0.2)
	cabin.material_override = glass
	body.add_child(cabin)

	# --- painted roof panel
	var roof_len := maxf(0.3, float(b.roofF) - float(b.roofB))
	_box(body, Vector3(w * 0.72, 0.05, roof_len),
		Vector3(0.0, float(b.cabTop) + 0.085, (float(b.roofF) + float(b.roofB)) * 0.5), paint)

	# --- headlights / mirrors / skirts
	var head_mat := _head_mat()
	for sx in [-1.0, 1.0]:
		var lamp := _box(body, Vector3(0.46, 0.09, 0.22),
			Vector3(sx * w * 0.32, float(b.noseY) - 0.03, hl - 0.01), head_mat)
		lamp.rotation = Vector3(-0.25, 0.0, 0.0)
		_box(body, Vector3(0.12, 0.05, 0.3),
			Vector3(sx * (w * 0.5 + 0.02), float(b.beltY) + 0.12, float(b.cabF) - 0.15), black)
		_box(body, Vector3(0.2, 0.12, 0.08),
			Vector3(sx * (w * 0.5 + 0.10), float(b.beltY) + 0.16, float(b.cabF) - 0.15), paint)
		_box(body, Vector3(0.08, 0.14, float(b.L) * 0.5),
			Vector3(sx * (w * 0.5 + 0.02), 0.37, 0.0), carbon)

	# --- tail lights (kept as a material reference so braking can brighten them)
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.33, 0.0, 0.02)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.06, 0.12)
	tail_mat.emission_energy_multiplier = 0.9
	_box(body, Vector3(w * 0.86, 0.08, 0.06),
		Vector3(0.0, float(b.tailY) - 0.17, -hl - 0.12), tail_mat)
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.4, 0.13, 0.06),
			Vector3(sx * w * 0.34, float(b.tailY) - 0.2, -hl - 0.13), tail_mat)

	# --- grille + diffuser
	_box(body, Vector3(w * 0.62, 0.16, 0.1), Vector3(0.0, 0.42, hl + 0.1), black)
	_box(body, Vector3(w * 0.8, 0.14, 0.2), Vector3(0.0, 0.36, -hl - 0.06), carbon)

	# --- aero
	var wing := int(s.wing)
	if wing == 2:
		var wy := float(b.tailY) + 0.32
		_box(body, Vector3(w * 0.98, 0.05, 0.42), Vector3(0.0, wy, -hl + 0.32), carbon)
		for sx2 in [-1.0, 1.0]:
			_box(body, Vector3(0.05, 0.32, 0.1), Vector3(sx2 * w * 0.28, wy - 0.17, -hl + 0.32), carbon)
	elif wing == 1:
		_box(body, Vector3(w * 0.84, 0.05, 0.22), Vector3(0.0, float(b.tailY) + 0.03, -hl + 0.15), carbon)

	# --- wheels (front = +Z)
	var wr := float(b.wr)
	var wb := float(b.wb)
	var tire_mat := MeshKit.solid(Color(0.08, 0.08, 0.09), 0.92)
	var rim_mat := MeshKit.solid(Color(0.78, 0.80, 0.83), 0.22, 1.0)
	var seg := 24 if quality >= 2 else 12
	var wheels: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.name = "Wheel"
			pivot.position = Vector3(sx * (w * 0.5 - 0.13), wr, sz * wb)

			var spin := Node3D.new()
			pivot.add_child(spin)

			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = wr
			tire_mesh.bottom_radius = wr
			tire_mesh.height = 0.3
			tire_mesh.radial_segments = seg
			var tire := MeshInstance3D.new()
			tire.mesh = tire_mesh
			tire.rotation = Vector3(0.0, 0.0, PI * 0.5)
			tire.material_override = tire_mat
			spin.add_child(tire)

			var rim_mesh := CylinderMesh.new()
			rim_mesh.top_radius = wr * 0.68
			rim_mesh.bottom_radius = wr * 0.68
			rim_mesh.height = 0.31
			rim_mesh.radial_segments = seg
			var rim := MeshInstance3D.new()
			rim.mesh = rim_mesh
			rim.rotation = Vector3(0.0, 0.0, PI * 0.5)
			rim.material_override = rim_mat
			spin.add_child(rim)

			root.add_child(pivot)
			wheels.append({"pivot": pivot, "spin": spin, "front": sz > 0.0})

	return {
		"root": root,
		"body": body,
		"wheels": wheels,
		"tail_mat": tail_mat,
		"wr": wr,
		"spec": s,
	}


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _paint(color: Color, quality: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.55
	m.roughness = 0.30
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if quality >= 2:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.06
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.043, 0.063, 0.094)
	m.metallic = 0.9
	m.roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _head_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.98, 0.94)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.95, 0.86)
	m.emission_energy_multiplier = 1.6
	return m
