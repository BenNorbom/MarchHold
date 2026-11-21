extends RefCounted
## A small procedural geometry kit. Collects triangles per material slot and
## builds an ArrayMesh. Winding is fixed up automatically from the normal.

var _st := {}            # slot -> SurfaceTool
var _mats := {}
var _order: Array = []
var _cur: SurfaceTool
var _count := {}
var _cur_name := ""
var limb := 0.0           # written to UV2.x (people and animals)
var region := 0.0         # written to UV2.y
var color := Color(1, 1, 1, 1)
var xf := Transform3D.IDENTITY   # applied to every vertex added
var rng := RandomNumberGenerator.new()


func slot(name: String, mat: Material = null) -> void:
	if not _st.has(name):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[name] = st
		_mats[name] = mat
		_order.append(name)
		_count[name] = 0
	_cur = _st[name]
	_cur_name = name


func _vert(p: Vector3, n: Vector3, uv: Vector2) -> void:
	_cur.set_normal((xf.basis * n).normalized())
	_cur.set_uv(uv)
	_cur.set_uv2(Vector2(limb, region))
	_cur.set_color(color)
	_cur.add_vertex(xf * p)
	_count[_cur_name] += 1


## One triangle; n is the intended outward direction (per vertex normals optional).
func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, na = null, nb = null, nc = null) -> void:
	var face := (b - a).cross(c - a)
	var want: Vector3 = (na + nb + nc) if na != null else face
	var n0: Vector3 = na if na != null else face.normalized()
	var n1: Vector3 = nb if nb != null else n0
	var n2: Vector3 = nc if nc != null else n0
	if face.dot(want) > 0.0:
		# Godot's front faces wind clockwise: emit a, c, b.
		_vert(a, n0, ua)
		_vert(c, n2, uc)
		_vert(b, n1, ub)
	else:
		_vert(a, n0, ua)
		_vert(b, n1, ub)
		_vert(c, n2, uc)


## Quad with corners going around (either direction); n is the outward normal.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
	tri(a, b, c, ua, ub, uc, n, n, n)
	tri(a, c, d, ua, uc, ud, n, n, n)


## Axis-aligned box in local space (before xf), UVs in metres times uvs.
func box(center: Vector3, size: Vector3, uvs: float = 1.0, skip_bottom: bool = true) -> void:
	var h := size * 0.5
	var c := center
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	# +Z / -Z
	quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1),
		Vector2(x0, -y0) * uvs, Vector2(x1, -y0) * uvs, Vector2(x1, -y1) * uvs, Vector2(x0, -y1) * uvs)
	quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(0, 0, -1),
		Vector2(-x1, -y0) * uvs, Vector2(-x0, -y0) * uvs, Vector2(-x0, -y1) * uvs, Vector2(-x1, -y1) * uvs)
	# +X / -X
	quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(1, 0, 0),
		Vector2(-z1, -y0) * uvs, Vector2(-z0, -y0) * uvs, Vector2(-z0, -y1) * uvs, Vector2(-z1, -y1) * uvs)
	quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0),
		Vector2(z0, -y0) * uvs, Vector2(z1, -y0) * uvs, Vector2(z1, -y1) * uvs, Vector2(z0, -y1) * uvs)
	# Top
	quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 1, 0),
		Vector2(x0, z1) * uvs, Vector2(x1, z1) * uvs, Vector2(x1, z0) * uvs, Vector2(x0, z0) * uvs)
	if not skip_bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0),
			Vector2(x0, z0) * uvs, Vector2(x1, z0) * uvs, Vector2(x1, z1) * uvs, Vector2(x0, z1) * uvs)


## A box rotated by `basis` around `center` (used for beams and tilted parts).
func obox(center: Vector3, size: Vector3, basis: Basis, uvs: float = 1.0) -> void:
	var old := xf
	xf = old * Transform3D(basis, center)
	box(Vector3.ZERO, size, uvs, false)
	xf = old


## Tapered cylinder from a to b with smooth sides.
func cylinder(a: Vector3, b: Vector3, r0: float, r1: float, sides: int = 8, cap_top: bool = true, uvs: float = 1.0, wobble: float = 0.0) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 0.0001:
		return
	var dir := axis / len
	var ref := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var u := dir.cross(ref).normalized()
	var v := dir.cross(u).normalized()
	var circ := TAU * maxf(r0, r1)
	var ring0: Array = []
	var ring1: Array = []
	for i in sides + 1:
		var ang := TAU * i / sides
		var off := (u * cos(ang) + v * sin(ang))
		var w0 := 1.0 + (rng.randf_range(-wobble, wobble) if wobble > 0.0 and i < sides else 0.0)
		ring0.append([a + off * r0 * w0, off])
		ring1.append([b + off * r1 * w0, off])
	if wobble > 0.0:
		ring0[sides] = ring0[0]
		ring1[sides] = ring1[0]
	var slope := (r0 - r1) / len
	for i in sides:
		var p0: Vector3 = ring0[i][0]
		var p1: Vector3 = ring0[i + 1][0]
		var q0: Vector3 = ring1[i][0]
		var q1: Vector3 = ring1[i + 1][0]
		var n0: Vector3 = (ring0[i][1] + dir * slope).normalized()
		var n1: Vector3 = (ring0[i + 1][1] + dir * slope).normalized()
		var u0 := float(i) / sides * circ * uvs
		var u1 := float(i + 1) / sides * circ * uvs
		tri(p0, p1, q1, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, -len * uvs), n0, n1, n1)
		tri(p0, q1, q0, Vector2(u0, 0), Vector2(u1, -len * uvs), Vector2(u0, -len * uvs), n0, n1, n0)
	if cap_top and r1 > 0.001:
		for i in sides:
			tri(b, ring1[i][0], ring1[i + 1][0], Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0), dir, dir, dir)


func cone(a: Vector3, b: Vector3, r: float, sides: int = 8, uvs: float = 1.0) -> void:
	cylinder(a, b, r, 0.0, sides, false, uvs)


## Squashable sphere with optional surface noise (for rocks and bushes).
func sphere(center: Vector3, radius: float, rings: int = 6, segs: int = 10, squash := Vector3.ONE, noise: float = 0.0, uvs: float = 1.0) -> void:
	var pts: Array = []
	var noise_seed := rng.randf() * 100.0
	for r in rings + 1:
		var lat := PI * r / rings
		var row: Array = []
		for s in segs + 1:
			var lon := TAU * (s % segs) / segs
			var dir := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
			var k := 1.0
			if noise > 0.0 and r > 0 and r < rings:
				k += noise * (sin(dir.x * 5.1 + noise_seed) * cos(dir.z * 4.3 + noise_seed * 0.7) + sin(dir.y * 6.7 + noise_seed * 1.3) * 0.5)
			row.append(center + dir * radius * k * squash)
		pts.append(row)
	for r in rings:
		for s in segs:
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s + 1]
			var c: Vector3 = pts[r + 1][s + 1]
			var d: Vector3 = pts[r + 1][s]
			var na := (a - center).normalized()
			var nb := (b - center).normalized()
			var nc := (c - center).normalized()
			var nd := (d - center).normalized()
			var uva := Vector2(float(s) / segs, float(r) / rings) * radius * 4.0 * uvs
			var uvb := Vector2(float(s + 1) / segs, float(r) / rings) * radius * 4.0 * uvs
			var uvc := Vector2(float(s + 1) / segs, float(r + 1) / rings) * radius * 4.0 * uvs
			var uvd := Vector2(float(s) / segs, float(r + 1) / rings) * radius * 4.0 * uvs
			if r > 0:
				tri(a, b, c, uva, uvb, uvc, na, nb, nc)
			if r < rings - 1:
				tri(a, c, d, uva, uvc, uvd, na, nc, nd)


## A double-sided card (for leaves, needles, grass, crops). n bends the normal outward.
func card(center: Vector3, right: Vector3, up: Vector3, n: Vector3, uv0 := Vector2(0, 0), uv1 := Vector2(1, 1)) -> void:
	var a := center - right * 0.5
	var b := center + right * 0.5
	var c := center + right * 0.5 + up
	var d := center - right * 0.5 + up
	tri(a, b, c, Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv1.y), Vector2(uv1.x, uv0.y), n, n, n)
	tri(a, c, d, Vector2(uv0.x, uv1.y), Vector2(uv1.x, uv0.y), Vector2(uv0.x, uv0.y), n, n, n)


## Gable roof: ridge along local X, from height y0 (eaves) to y1 (ridge).
func gable(center: Vector3, length: float, width: float, y0: float, y1: float, overhang: float = 0.4, uvs: float = 1.0) -> void:
	var hl := length * 0.5 + overhang
	var hw := width * 0.5 + overhang
	var cx := center.x
	var cz := center.z
	var r0 := Vector3(cx - hl, y1, cz)
	var r1 := Vector3(cx + hl, y1, cz)
	var e0 := Vector3(cx - hl, y0, cz + hw)
	var e1 := Vector3(cx + hl, y0, cz + hw)
	var f0 := Vector3(cx - hl, y0, cz - hw)
	var f1 := Vector3(cx + hl, y0, cz - hw)
	var slope_len := Vector2(hw, y1 - y0).length()
	var n1 := Vector3(0, hw, y1 - y0).normalized()
	var n2 := Vector3(0, hw, -(y1 - y0)).normalized()
	quad(e0, e1, r1, r0, n1, Vector2(0, slope_len) * uvs, Vector2(hl * 2, slope_len) * uvs, Vector2(hl * 2, 0) * uvs, Vector2(0, 0))
	quad(f1, f0, r0, r1, n2, Vector2(0, slope_len) * uvs, Vector2(hl * 2, slope_len) * uvs, Vector2(hl * 2, 0) * uvs, Vector2(0, 0))
	# Underside so the roof isn't see-through from below.
	quad(e0, r0, r1, e1, -n1, Vector2.ZERO, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	quad(f1, r1, r0, f0, -n2, Vector2.ZERO, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))


## Triangular gable end walls (the ends of a gable roof), using the current slot.
func gable_ends(center: Vector3, length: float, width: float, y0: float, y1: float, uvs: float = 1.0) -> void:
	var hl := length * 0.5
	var hw := width * 0.5
	for sgn in [-1.0, 1.0]:
		var x: float = center.x + hl * sgn
		var a := Vector3(x, y0, center.z - hw)
		var b := Vector3(x, y0, center.z + hw)
		var c := Vector3(x, y1, center.z)
		tri(a, b, c, Vector2(-hw, 0) * uvs, Vector2(hw, 0) * uvs, Vector2(0, -(y1 - y0)) * uvs, Vector3(sgn, 0, 0), Vector3(sgn, 0, 0), Vector3(sgn, 0, 0))


## Hip-free pyramid roof (for round huts and towers).
func pyramid(center: Vector3, radius: float, y0: float, y1: float, sides: int = 8, uvs: float = 1.0) -> void:
	var top := Vector3(center.x, y1, center.z)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(center.x + cos(a0) * radius, y0, center.z + sin(a0) * radius)
		var p1 := Vector3(center.x + cos(a1) * radius, y0, center.z + sin(a1) * radius)
		var mid := (p0 + p1) * 0.5 - center
		var n := Vector3(mid.x, radius * radius / maxf(0.01, y1 - y0) * 0.5, mid.z).normalized()
		var sl := Vector2(radius, y1 - y0).length()
		tri(p0, p1, top, Vector2(0, sl) * uvs, Vector2(TAU * radius / sides, sl) * uvs, Vector2(TAU * radius / sides * 0.5, 0), n, n, n)


func finish() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for name in _order:
		if int(_count[name]) < 3:
			continue
		var st: SurfaceTool = _st[name]
		st.generate_tangents()
		st.commit(mesh)
		var idx := mesh.get_surface_count() - 1
		if _mats[name] != null:
			mesh.surface_set_material(idx, _mats[name])
	return mesh
