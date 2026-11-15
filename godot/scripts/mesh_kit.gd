class_name MeshKit
extends RefCounted

## Small procedural-mesh helpers shared by the car builder and the track builder.
## Everything here replaces the Three.js ExtrudeGeometry / BufferGeometry work in
## public/js/track.js and public/js/cars.js.


## Extrudes a closed 2D profile along the X axis.
## profile points are (u, v) where u maps to +Z and v maps to +Y,
## so a side-view silhouette drawn in (z, y) comes out as a car body.
## Caps are built with Geometry2D.triangulate_polygon, side walls are quads
## with explicit outward normals (sign of the polygon area decides the direction).
static func extrude_profile(profile: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	if n < 3:
		return ArrayMesh.new()

	var hw := depth * 0.5
	var area := 0.0
	for i in range(n):
		var a := profile[i]
		var b := profile[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area >= 0.0 else -1.0

	# --- side walls
	for i in range(n):
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var d := b - a
		if d.length_squared() < 0.0000001:
			continue
		var n2 := Vector2(d.y, -d.x).normalized() * sgn
		var nrm := Vector3(0.0, n2.y, n2.x).normalized()
		var p0 := Vector3(-hw, a.y, a.x)
		var p1 := Vector3(hw, a.y, a.x)
		var p2 := Vector3(hw, b.y, b.x)
		var p3 := Vector3(-hw, b.y, b.x)
		_tri(st, p0, p1, p2, nrm)
		_tri(st, p0, p2, p3, nrm)

	# --- caps
	var idx := Geometry2D.triangulate_polygon(profile)
	if idx.size() >= 3:
		var k := 0
		while k + 2 < idx.size():
			var pa := profile[idx[k]]
			var pb := profile[idx[k + 1]]
			var pc := profile[idx[k + 2]]
			_tri(st, Vector3(hw, pa.y, pa.x), Vector3(hw, pb.y, pb.x), Vector3(hw, pc.y, pc.x), Vector3(1, 0, 0))
			_tri(st, Vector3(-hw, pa.y, pa.x), Vector3(-hw, pb.y, pb.x), Vector3(-hw, pc.y, pc.x), Vector3(-1, 0, 0))
			k += 3

	return st.commit()


## One flat-shaded triangle with a fixed normal.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


## Unlit-ish standard material helper (used for car trim, trees, buildings).
static func solid(color: Color, roughness := 0.8, metallic := 0.0, cull_off := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
