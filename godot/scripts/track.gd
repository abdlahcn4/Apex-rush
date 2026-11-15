class_name ApexTrack
extends RefCounted

## Port of CircuitTrack from public/js/track.js.
## Builds a closed centripetal Catmull-Rom ring from trackdata.json, resamples it at
## ~2 m spacing, and extrudes the road / walls / markings along it.

const ROAD_HALF := 11.0
const WALL := 11.5
const LANES := [-6.75, -2.25, 2.25, 6.75]

var samples: Array = []          # {x, z, tx, tz, nx, nz, d}
var length := 0.0
var N := 0
var step := 2.0
var checkpoint_radius := 26.0

var _grid: Dictionary = {}
var _min_x := 0.0
var _max_x := 0.0
var _min_z := 0.0
var _max_z := 0.0


func _init(points: Array, cp_radius: float) -> void:
	checkpoint_radius = cp_radius
	_build(points)


# --------------------------------------------------------------------------- #
# spline
# --------------------------------------------------------------------------- #

static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float, alpha := 0.5) -> Vector2:
	# Barry-Goldman evaluation of a centripetal Catmull-Rom segment (matches
	# THREE.CatmullRomCurve3 with curveType 'centripetal').
	var d1 := p0.distance_to(p1)
	var d2 := p1.distance_to(p2)
	var d3 := p2.distance_to(p3)
	var t0 := 0.0
	var t1 := t0 + pow(maxf(d1, 0.0001), alpha)
	var t2 := t1 + pow(maxf(d2, 0.0001), alpha)
	var t3 := t2 + pow(maxf(d3, 0.0001), alpha)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


func _build(points: Array) -> void:
	var ctrl: Array = []
	for p in points:
		ctrl.append(Vector2(float(p[0]), float(p[1])))
	var n := ctrl.size()
	if n < 4:
		push_error("ApexTrack: need at least 4 control points")
		return

	# dense sampling of every segment
	var per_seg := 32
	var dense: Array = []
	for i in range(n):
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in range(per_seg):
			dense.append(_catmull_rom(p0, p1, p2, p3, float(k) / float(per_seg)))

	# close the loop so the resampler can span the final segment
	dense.append(dense[0])

	# cumulative arc length
	var cum: Array = [0.0]
	var acc := 0.0
	for i in range(1, dense.size()):
		var a: Vector2 = dense[i - 1]
		var b: Vector2 = dense[i]
		acc += a.distance_to(b)
		cum.append(acc)
	length = acc
	if length <= 1.0:
		push_error("ApexTrack: degenerate spline")
		return

	N = maxi(32, int(round(length / 2.0)))
	step = length / float(N)

	# uniform arc-length resample (three.js getSpacedPoints)
	var pts: Array = []
	var j := 0
	for i in range(N):
		var target := float(i) * step
		while j < dense.size() - 2 and float(cum[j + 1]) < target:
			j += 1
		var seg_len := float(cum[j + 1]) - float(cum[j])
		var t := 0.0 if seg_len <= 0.00001 else (target - float(cum[j])) / seg_len
		pts.append((dense[j] as Vector2).lerp(dense[j + 1] as Vector2, clampf(t, 0.0, 1.0)))

	# tangents + lateral normals
	samples.clear()
	_min_x = 1e18
	_max_x = -1e18
	_min_z = 1e18
	_max_z = -1e18
	for i in range(N):
		var p: Vector2 = pts[i]
		var nxt: Vector2 = pts[(i + 1) % N]
		var prv: Vector2 = pts[(i - 1 + N) % N]
		var tvec := nxt - prv
		if tvec.length_squared() < 0.0000001:
			tvec = Vector2(0.0, 1.0)
		tvec = tvec.normalized()
		samples.append({
			"x": p.x, "z": p.y,
			"tx": tvec.x, "tz": tvec.y,
			"nx": -tvec.y, "nz": tvec.x,
			"d": float(i) * step,
		})
		_min_x = minf(_min_x, p.x)
		_max_x = maxf(_max_x, p.x)
		_min_z = minf(_min_z, p.y)
		_max_z = maxf(_max_z, p.y)

	# spatial hash for scenery rejection
	_grid.clear()
	for i in range(N):
		var s: Dictionary = samples[i]
		var key := Vector2i(int(floor(float(s.x) / 40.0)), int(floor(float(s.z) / 40.0)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


# --------------------------------------------------------------------------- #
# queries
# --------------------------------------------------------------------------- #

func sample_at(i: int) -> Dictionary:
	return samples[((i % N) + N) % N]


## Projects a world position onto the ring. hint = previous sample index.
func project(x: float, z: float, hint: int = -1) -> Dictionary:
	var bi := 0
	var bd := INF
	if hint < 0:
		var i := 0
		while i < N:
			var s: Dictionary = samples[i]
			var dx := float(s.x) - x
			var dz := float(s.z) - z
			var d := dx * dx + dz * dz
			if d < bd:
				bd = d
				bi = i
			i += 3
		hint = bi

	bd = INF
	for k in range(-30, 31):
		var idx := (hint + k) % N
		if idx < 0:
			idx += N
		var s2: Dictionary = samples[idx]
		var dx2 := float(s2.x) - x
		var dz2 := float(s2.z) - z
		var d2 := dx2 * dx2 + dz2 * dz2
		if d2 < bd:
			bd = d2
			bi = idx

	var s3: Dictionary = samples[bi]
	var dx3 := x - float(s3.x)
	var dz3 := z - float(s3.z)
	var lat := dx3 * float(s3.nx) + dz3 * float(s3.nz)
	var sd := float(s3.d) + dx3 * float(s3.tx) + dz3 * float(s3.tz)
	if sd < 0.0:
		sd += length
	if sd >= length:
		sd -= length
	return {
		"i": bi, "s": sd, "lat": lat,
		"tx": float(s3.tx), "tz": float(s3.tz),
		"nx": float(s3.nx), "nz": float(s3.nz),
		"x": float(s3.x), "z": float(s3.z),
	}


## Position + tangent at distance sd along the ring, offset lat metres sideways.
func point_at(sd: float, lat: float = 0.0) -> Dictionary:
	if N <= 1 or length <= 0.0:
		return {"x": 0.0, "z": 0.0, "tx": 0.0, "tz": 1.0}
	var s0 := fposmod(sd, length)
	var f := s0 / step
	var i := int(floor(f))
	var t := f - floor(f)
	var a: Dictionary = sample_at(i)
	var b: Dictionary = sample_at(i + 1)
	var x := lerpf(float(a.x), float(b.x), t)
	var z := lerpf(float(a.z), float(b.z), t)
	var tx := lerpf(float(a.tx), float(b.tx), t)
	var tz := lerpf(float(a.tz), float(b.tz), t)
	var l := sqrt(tx * tx + tz * tz)
	if l > 0.0001:
		tx /= l
		tz /= l
	return {"x": x - tz * lat, "z": z + tx * lat, "tx": tx, "tz": tz}


func dist_to_road(x: float, z: float) -> float:
	var cx := int(floor(x / 40.0))
	var cz := int(floor(z / 40.0))
	var best := 1e18
	for a in range(-2, 3):
		for b in range(-2, 3):
			var key := Vector2i(cx + a, cz + b)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var s: Dictionary = samples[i]
				var dx := float(s.x) - x
				var dz := float(s.z) - z
				var d := dx * dx + dz * dz
				if d < best:
					best = d
	return sqrt(best)


# --------------------------------------------------------------------------- #
# meshes
# --------------------------------------------------------------------------- #

## Extrudes a cross-section [[lateral, height], ...] along every sample.
## Normals are derived from the cross-section winding, so no culling surprises.
func ribbon(cross: Array, mat: Material, uv_scale := 8.0, flat_up := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := samples.size()
	var m := cross.size()
	if n < 2 or m < 2:
		return MeshInstance3D.new()

	var area := 0.0
	for j in range(m):
		var a: Vector2 = cross[j]
		var b: Vector2 = cross[(j + 1) % m]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area >= 0.0 else -1.0

	var edge_n: Array = []
	var edge_u: Array = [0.0]
	var uacc := 0.0
	for j in range(m - 1):
		var c0: Vector2 = cross[j]
		var c1: Vector2 = cross[j + 1]
		var d2 := c1 - c0
		uacc += d2.length()
		edge_u.append(uacc)
		if flat_up:
			edge_n.append(Vector2(0.0, 1.0))
		else:
			edge_n.append(Vector2(d2.y, -d2.x).normalized() * sgn)

	for i in range(n + 1):
		var s: Dictionary = samples[i % n]
		var s2: Dictionary = samples[(i + 1) % n]
		var v0 := float(s.d) / uv_scale
		var v1 := (float(s.d) + step) / uv_scale
		for j in range(m - 1):
			var c0: Vector2 = cross[j]
			var c1: Vector2 = cross[j + 1]
			var n2: Vector2 = edge_n[j]
			var nrm := Vector3(n2.x * float(s.nx), n2.y, n2.x * float(s.nz)).normalized()
			var p00 := Vector3(float(s.x) + float(s.nx) * c0.x, c0.y, float(s.z) + float(s.nz) * c0.x)
			var p01 := Vector3(float(s.x) + float(s.nx) * c1.x, c1.y, float(s.z) + float(s.nz) * c1.x)
			var p10 := Vector3(float(s2.x) + float(s2.nx) * c0.x, c0.y, float(s2.z) + float(s2.nz) * c0.x)
			var p11 := Vector3(float(s2.x) + float(s2.nx) * c1.x, c1.y, float(s2.z) + float(s2.nz) * c1.x)
			var u0 := float(edge_u[j]) / uv_scale
			var u1 := float(edge_u[j + 1]) / uv_scale
			_quad(st, p00, p10, p11, p01, nrm, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0))

	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_normal(n)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_normal(n)
	st.set_uv(uv3)
	st.add_vertex(p3)


func build(parent: Node3D, quality: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Track"
	parent.add_child(root)

	# --- asphalt
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.28, 0.28, 0.31)
	road_mat.roughness = 0.95
	road_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise
	road_mat.albedo_texture = noise_tex
	road_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)

	var road := ribbon([Vector2(-ROAD_HALF, 0.02), Vector2(ROAD_HALF, 0.02)], road_mat, 8.0, true)
	road.name = "Road"
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(road)

	# --- solid edge lines
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.9, 0.9, 0.88)
	line_mat.roughness = 0.7
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.25, 0.25, 0.24)
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for side in [-1.0, 1.0]:
		var a := 9.0 * side
		var b := 9.35 * side
		var cross: Array = [Vector2(minf(a, b), 0.035), Vector2(maxf(a, b), 0.035)]
		var line := ribbon(cross, line_mat, 8.0, true)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(line)

	# --- dashed lane separators
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.18, 0.02, 3.0)
	var dash_count := 0
	var dash_step := maxi(1, int(round(12.0 / step)))
	for lat in [-4.5, 0.0, 4.5]:
		dash_count += int(ceil(float(N) / float(dash_step)))
	var dash_mm := MultiMesh.new()
	dash_mm.transform_format = MultiMesh.TRANSFORM_3D
	dash_mm.mesh = dash_mesh
	dash_mm.instance_count = maxi(1, dash_count)
	var di := 0
	for lat in [-4.5, 0.0, 4.5]:
		var i := 0
		while i < N and di < dash_mm.instance_count:
			var s: Dictionary = samples[i]
			var basis := Basis(Vector3.UP, atan2(float(s.tx), float(s.tz)))
			var pos := Vector3(float(s.x) + float(s.nx) * float(lat), 0.04, float(s.z) + float(s.nz) * float(lat))
			dash_mm.set_instance_transform(di, Transform3D(basis, pos))
			di += 1
			i += dash_step
	var dash_inst := MultiMeshInstance3D.new()
	dash_inst.multimesh = dash_mm
	dash_inst.material_override = line_mat
	dash_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dash_inst.name = "LaneDashes"
	root.add_child(dash_inst)

	# --- walls
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.55, 0.56, 0.58)
	wall_mat.roughness = 0.9
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var a := side * WALL
		var b := side * (WALL + 0.55)
		var cross: Array = [
			Vector2(b, 0.0),
			Vector2(b, 1.0),
			Vector2(a, 0.95),
			Vector2(a, 0.0),
		]
		var wall := ribbon(cross, wall_mat, 8.0)
		wall.name = "Wall"
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wall)

	_build_scenery(root, quality)
	_build_start_gantry(root)

	return root


func _build_scenery(root: Node3D, quality: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# --- trees
	var tree_counts := [120, 400, 800, 1600]
	var want: int = tree_counts[clampi(quality, 0, 3)]
	var spots: Array = []
	var guard := 0
	while spots.size() < want and guard < want * 12:
		guard += 1
		var x := _min_x - 450.0 + rng.randf() * (_max_x - _min_x + 900.0)
		var z := _min_z - 450.0 + rng.randf() * (_max_z - _min_z + 900.0)
		var d := dist_to_road(x, z)
		if d < 19.0:
			continue
		if d > 120.0 and rng.randf() < 0.55:
			continue
		spots.append({"x": x, "z": z, "s": 0.8 + rng.randf() * 0.9, "r": rng.randf()})

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.25
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 2.4
	trunk_mesh.radial_segments = 5

	# cones = cylinders with a zero top radius (ConeMesh only exposes `radius`)
	var leaf_low := CylinderMesh.new()
	leaf_low.top_radius = 0.0
	leaf_low.bottom_radius = 2.4
	leaf_low.height = 5.5
	leaf_low.radial_segments = 7

	var leaf_high := CylinderMesh.new()
	leaf_high.top_radius = 0.0
	leaf_high.bottom_radius = 1.6
	leaf_high.height = 4.0
	leaf_high.radial_segments = 7

	var trunk_xf: Array = []
	var low_xf: Array = []
	var high_xf: Array = []
	var leaf_cols: Array = []
	for p in spots:
		var s := float(p.s)
		var sy := s * (0.9 + float(p.r) * 0.4)
		var yaw := float(p.r) * TAU
		var basis := Basis(Vector3.UP, yaw) * Basis().scaled(Vector3(s, sy, s))
		var base := Vector3(float(p.x), 0.0, float(p.z))
		trunk_xf.append(Transform3D(basis, base + Vector3(0.0, 1.2 * sy, 0.0)))
		low_xf.append(Transform3D(basis, base + Vector3(0.0, 2.75 * sy, 0.0)))
		high_xf.append(Transform3D(basis, base + Vector3(0.0, 6.2 * sy, 0.0)))
		var h := 0.24 + rng.randf() * 0.10
		leaf_cols.append(Color.from_hsv(h, 0.45 + rng.randf() * 0.2, 0.13 + rng.randf() * 0.10))

	var trunk_mat := MeshKit.solid(Color(0.20, 0.15, 0.11), 0.95)
	# per-instance colours are multiplied by the albedo, so keep it white
	var leaf_mat := MeshKit.solid(Color(1, 1, 1), 0.9)
	leaf_mat.vertex_color_use_as_albedo = true

	root.add_child(_multimesh(trunk_mesh, trunk_mat, trunk_xf))
	root.add_child(_multimesh(leaf_low, leaf_mat, low_xf, leaf_cols))
	root.add_child(_multimesh(leaf_high, leaf_mat, high_xf, leaf_cols))

	# --- buildings
	var centers := [Vector2(300, 300), Vector2(-260, 120), Vector2(760, -200), Vector2(250, -800), Vector2(900, 700)]
	var per_cluster := [10, 18, 26, 34]
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	var box_xf: Array = []
	var box_cols: Array = []
	for c in centers:
		for k in range(int(per_cluster[clampi(quality, 0, 3)])):
			var x := float(c.x) + (rng.randf() - 0.5) * 320.0
			var z := float(c.y) + (rng.randf() - 0.5) * 320.0
			if dist_to_road(x, z) < 45.0:
				continue
			var w := 14.0 + rng.randf() * 22.0
			var hgt := 12.0 + rng.randf() * (90.0 if rng.randf() < 0.2 else 35.0)
			var d := 14.0 + rng.randf() * 22.0
			var basis := Basis(Vector3.UP, floor(rng.randf() * 4.0) * 0.4) * Basis().scaled(Vector3(w, hgt, d))
			box_xf.append(Transform3D(basis, Vector3(x, hgt * 0.5, z)))
			box_cols.append(Color.from_hsv(0.08 + float(box_xf.size() % 7) * 0.02, 0.15, 0.45 + float(box_xf.size() % 3) * 0.10))
	var box_mat := MeshKit.solid(Color(1, 1, 1), 0.85)
	box_mat.vertex_color_use_as_albedo = true
	root.add_child(_multimesh(box_mesh, box_mat, box_xf, box_cols))


func _multimesh(mesh: Mesh, mat: Material, xforms: Array, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() == xforms.size() and colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return inst


func _build_start_gantry(root: Node3D) -> void:
	var s: Dictionary = samples[0]
	var yaw := atan2(float(s.tx), float(s.tz))
	var base := Vector3(float(s.x), 0.0, float(s.z))

	# start line
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.93, 0.93, 0.93)
	line_mat.roughness = 0.6
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(ROAD_HALF * 1.8, 0.02, 1.6)
	var line := MeshInstance3D.new()
	line.mesh = line_mesh
	line.material_override = line_mat
	line.transform = Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0.0, 0.045, 0.0))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)

	# gantry
	var steel := MeshKit.solid(Color(0.16, 0.17, 0.19), 0.5, 0.6)
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.8, 8.0, 0.8)
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(WALL * 2.0 + 3.2, 1.6, 0.5)
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		pillar.mesh = pillar_mesh
		pillar.material_override = steel
		var off := Vector3(float(s.nx), 0.0, float(s.nz)) * (side * (WALL + 1.2))
		pillar.transform = Transform3D(Basis(Vector3.UP, yaw), base + off + Vector3(0.0, 4.0, 0.0))
		root.add_child(pillar)
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = steel
	beam.transform = Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0.0, 7.6, 0.0))
	root.add_child(beam)
