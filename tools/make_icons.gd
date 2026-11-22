extends SceneTree
## Draws the hotkey popup's pictures into assets/icons, then import them:
##   godot --headless --path . -s res://tools/make_icons.gd
##   godot --headless --path . --import
## A small software rasterizer, so it needs no window or GPU. Structures use the game's own
## models and textures. Hand weapons are too thin to read at icon size, so they get chunkier ones here.

const Defs = preload("res://scripts/data/defs.gd")
const Geo = preload("res://scripts/view/geo.gd")
const Materials = preload("res://scripts/view/materials.gd")
const Meshes = preload("res://scripts/view/meshes.gd")

const OUT := "res://assets/icons"
const SIZE := 128
const SUPER := 3      # samples per pixel along each side
const MARGIN := 0.04
const SUN := Vector3(-0.45, 0.75, 0.6)

const WOOD := Color(0.56, 0.38, 0.21)
const LEATHER := Color(0.32, 0.2, 0.12)
const BRONZE := Color(0.86, 0.56, 0.24)
const IRON := Color(0.68, 0.72, 0.78)
const CLOTH := Color(0.66, 0.16, 0.12)
const PALE := Color(0.92, 0.88, 0.76)
const GOLD := Color(0.95, 0.76, 0.32)

var mats
var meshes
var flat := {}      # Color -> material
var images := {}    # texture -> Image
var color_buf := PackedColorArray()
var depth_buf := PackedFloat32Array()
var side := SIZE * SUPER


func _initialize() -> void:
	_draw_all.call_deferred()


func _draw_all() -> void:
	mats = Materials.new()
	meshes = Meshes.new(mats)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var done := 0
	for command: String in Defs.HOTKEYS:
		for page: String in Defs.HOTKEYS[command]:
			for slot: String in Defs.HOTKEYS[command][page]["keys"].values():
				_draw_icon(slot.get_slice(":", 0), slot.get_slice(":", 1))
				done += 1
	print("%d icons written to %s" % [done, OUT])
	quit()


func _draw_icon(kind: String, id: String) -> void:
	var mesh: ArrayMesh
	var eye := Vector3(0.62, 0.45, 1.0)   # from the front right, a little above
	var upright := 0.0
	match kind:
		"build":
			mesh = meshes.building(id)
			if Defs.BUILDINGS[id].get("wall", false):
				eye = Vector3(0.35, 0.28, 1.0)
		"upgrade":
			mesh = meshes.building(id, 1)
		"research":
			mesh = _keg()
		"craft":
			if id == "ram":
				mesh = meshes.ram()
				eye = Vector3(1.0, 0.45, 0.7)
			elif id == "cannon":
				mesh = meshes.cannon()
				eye = Vector3(1.0, 0.35, 0.55)
			elif id == "shot":
				mesh = _shot()
			else:
				mesh = _gear(id)
				eye = Vector3(0.12, 0.1, 1.0)
				if not id.ends_with("shield") and not id.ends_with("armor") and id != "bow":
					upright = -PI / 4.0   # long things lie corner to corner
	var img := _render(mesh, eye.normalized(), upright)
	if kind == "upgrade":
		_up_arrow(img)
	var err := img.save_png("%s/%s_%s.png" % [OUT, kind, id])
	if err != OK:
		printerr("Could not save %s %s (%d)" % [kind, id, err])


# --- Icon models -----------------------------------------------------------------

func _paint(g: Geo, col: Color) -> void:
	if not flat.has(col):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		flat[col] = mat
	g.slot(col.to_html(), flat[col])


func _metal(id: String) -> Color:
	if id.begins_with("bronze"):
		return BRONZE
	return IRON if id.begins_with("iron") else WOOD


func _gear(id: String) -> ArrayMesh:
	var g := Geo.new()
	var metal := _metal(id)
	var up := Vector3.UP
	if id.ends_with("spear"):
		_paint(g, WOOD)
		g.cylinder(up * -1.4, up * 0.8, 0.075, 0.075, 8)
		_paint(g, LEATHER)
		g.cylinder(up * 0.55, up * 0.78, 0.11, 0.11, 8)
		_paint(g, WOOD.lightened(0.45) if id == "wood_spear" else metal)
		g.cone(up * 0.98, up * 1.55, 0.24, 4)
		g.cylinder(up * 0.74, up * 0.98, 0.09, 0.24, 4, false)
	elif id.ends_with("pike"):
		# Longer and thinner than a spear, with langets down the shaft.
		_paint(g, WOOD)
		g.cylinder(up * -2.3, up * 1.3, 0.075, 0.075, 8)
		_paint(g, metal)
		g.cone(up * 1.5, up * 2.5, 0.17, 4)
		g.cylinder(up * 0.7, up * 1.5, 0.11, 0.17, 4, false)
	elif id.ends_with("lance"):
		_paint(g, WOOD)
		g.cylinder(up * -1.5, up * -0.75, 0.11, 0.11, 8)
		g.cylinder(up * -0.75, up * 1.3, 0.22, 0.07, 10)
		_paint(g, metal)
		g.cone(up * -0.85, up * -0.35, 0.48, 12)
		g.cone(up * 1.2, up * 1.75, 0.16, 8)
		_paint(g, CLOTH)
		g.box(Vector3(0.3, 0.8, 0.0), Vector3(0.5, 0.36, 0.03), 1.0, false)
	elif id.ends_with("sword"):
		_paint(g, LEATHER)
		g.cylinder(up * -0.9, up * -0.45, 0.085, 0.085, 8)
		_paint(g, metal)
		g.sphere(up * -0.97, 0.13, 5, 8)
		g.box(up * -0.42, Vector3(0.75, 0.13, 0.15), 1.0, false)
		g.cylinder(up * -0.36, up * 0.95, 0.19, 0.15, 4, false)
		g.cone(up * 0.95, up * 1.35, 0.15, 4)
	elif id.ends_with("shield"):
		var back := Vector3(0, 0, -0.08)
		_paint(g, metal if id != "wood_shield" else LEATHER)
		g.cylinder(back, Vector3.ZERO, 1.0, 1.0, 28)
		_paint(g, WOOD if id == "wood_shield" else metal.darkened(0.3))
		g.cylinder(Vector3.ZERO, Vector3(0, 0, 0.06), 0.84, 0.84, 28)
		if id == "wood_shield":
			_paint(g, WOOD.darkened(0.3))
			for x in [-0.42, 0.0, 0.42]:
				g.box(Vector3(x, 0, 0.07), Vector3(0.035, 1.4, 0.02), 1.0, false)
		_paint(g, IRON if id == "wood_shield" else metal)
		g.sphere(Vector3(0, 0, 0.1), 0.28, 8, 14)
	elif id.ends_with("armor"):
		var squash := Transform3D(Basis.from_scale(Vector3(1, 1, 0.65)), Vector3.ZERO)
		g.xf = squash
		_paint(g, metal)
		g.cylinder(up * -0.8, up * -0.1, 0.6, 0.55, 16)
		g.cylinder(up * -0.1, up * 0.55, 0.55, 0.78, 16)
		g.cylinder(up * 0.55, up * 0.82, 0.78, 0.36, 16)
		for x in [-0.78, 0.78]:
			g.sphere(Vector3(x, 0.5, 0), 0.32, 6, 10)
		_paint(g, LEATHER)
		g.cylinder(up * -0.62, up * -0.42, 0.64, 0.63, 16, false)
		g.cylinder(up * 0.82, up * 0.86, 0.34, 0.3, 16)
		g.xf = Transform3D.IDENTITY
	elif id == "bow":
		var pts: Array[Vector3] = []
		for i in 13:
			var t := -1.0 + i / 6.0
			pts.append(Vector3(0.75 * (1.0 - t * t) - 0.3, t * 1.2, 0))
		_paint(g, WOOD)
		for i in 12:
			g.cylinder(pts[i], pts[i + 1], 0.085, 0.085, 7)
		_paint(g, LEATHER)
		g.cylinder(pts[5], pts[7], 0.12, 0.12, 7)
		_paint(g, PALE)
		g.cylinder(pts[0], pts[12], 0.03, 0.03, 5)
	elif id == "arrows":
		for x in [-0.4, 0.0, 0.4]:
			var at := Vector3(x, 0, 0)
			_paint(g, WOOD)
			g.cylinder(at + up * -1.0, at + up * 0.8, 0.05, 0.05, 6)
			_paint(g, IRON)
			g.cone(at + up * 0.75, at + up * 1.2, 0.17, 4)
			_paint(g, PALE)
			g.box(at + up * -0.8, Vector3(0.26, 0.42, 0.03), 1.0, false)
	else:
		printerr("No picture for %s" % id)
	return g.finish()


func _shot() -> ArrayMesh:
	var g := Geo.new()
	_paint(g, Color(0.36, 0.37, 0.41))
	for p in [Vector3(-0.5, 0, 0.29), Vector3(0.5, 0, 0.29), Vector3(0, 0, -0.58), Vector3(0, 0.82, 0)]:
		g.sphere(p, 0.5, 12, 18)
	return g.finish()


func _keg() -> ArrayMesh:
	var g := Geo.new()
	var up := Vector3.UP
	_paint(g, WOOD)
	g.cylinder(up * -0.8, Vector3.ZERO, 0.58, 0.74, 16, false)
	g.cylinder(Vector3.ZERO, up * 0.8, 0.74, 0.58, 16)
	_paint(g, IRON.darkened(0.3))
	for y in [-0.6, -0.1, 0.5]:
		var r: float = 0.78 - absf(y) * 0.2
		g.cylinder(up * y, up * (y + 0.13), r, r, 16, false)
	_paint(g, PALE)
	g.cylinder(up * 0.8, Vector3(0.25, 1.2, 0), 0.045, 0.045, 6)
	_paint(g, GOLD)
	g.cone(Vector3(0.25, 1.18, 0), Vector3(0.3, 1.5, 0), 0.16, 5)
	return g.finish()


# --- Rendering -------------------------------------------------------------------

func _render(mesh: ArrayMesh, eye: Vector3, roll: float) -> Image:
	var right := Vector3.UP.cross(eye).normalized()
	var view := Basis(right, eye.cross(right), eye).transposed()
	view = Basis(Vector3.BACK, roll) * view
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var p := view * v
			lo = lo.min(Vector2(p.x, p.y))
			hi = hi.max(Vector2(p.x, p.y))
	var span := maxf(hi.x - lo.x, hi.y - lo.y)
	var scale := side * (1.0 - MARGIN * 2.0) / span
	var mid := (lo + hi) * 0.5

	color_buf.resize(side * side)
	color_buf.fill(Color(0, 0, 0, 0))
	depth_buf.resize(side * side)
	depth_buf.fill(-INF)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		var look := _surface_look(mesh.surface_get_material(s))
		for i in range(0, index.size() - 2, 3):
			var pts: Array[Vector3] = []
			var light := PackedFloat32Array()
			var uv := PackedVector2Array()
			for k in 3:
				var j := index[i + k]
				var p := view * verts[j]
				pts.append(Vector3((p.x - mid.x) * scale + side * 0.5, side * 0.5 - (p.y - mid.y) * scale, p.z))
				var n := normals[j]
				if n.dot(eye) < -0.2:
					n = -n   # cards and open undersides are lit from the side you see
				light.append(0.5 + 0.2 * n.y + 0.95 * maxf(0.0, n.dot(SUN.normalized())))
				uv.append(uvs[j] * float(look["uv_scale"]))
			_triangle(pts, light, uv, look)
	var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for y in side:
		for x in side:
			img.set_pixel(x, y, color_buf[y * side + x])
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return img


func _surface_look(mat: Material) -> Dictionary:
	var look := {"tint": Color.WHITE, "uv_scale": 1.0, "img": null, "cut": 0.0, "saturation": 1.0}
	if mat is StandardMaterial3D:
		look["tint"] = mat.albedo_color.srgb_to_linear()
	elif mat is ShaderMaterial:
		var tint = mat.get_shader_parameter("tint")
		if tint is Vector3:
			look["tint"] = Color(tint.x, tint.y, tint.z)
		elif tint is Color:
			look["tint"] = tint
		var uv_scale = mat.get_shader_parameter("uv_scale")
		if uv_scale != null:
			look["uv_scale"] = uv_scale
		var saturation = mat.get_shader_parameter("saturation")
		if saturation != null:
			look["saturation"] = saturation
		for param in ["albedo_tex", "leaf_tex", "blade_tex"]:
			var tex = mat.get_shader_parameter(param)
			if tex is Texture2D:
				look["img"] = _image(tex)
				if param != "albedo_tex" or tex.resource_path == "":
					look["cut"] = 0.4
				break
	return look


## The source picture: an imported texture has no pixels without a renderer.
func _image(tex: Texture2D) -> Image:
	if not images.has(tex):
		var img: Image
		if tex.resource_path != "":
			img = Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
		else:
			img = tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.resize(256, 256)
			images[tex] = img
		else:
			images[tex] = null
	return images[tex]


func _triangle(p: Array[Vector3], light: PackedFloat32Array, uv: PackedVector2Array, look: Dictionary) -> void:
	var a := p[0]
	var b := p[1]
	var c := p[2]
	var area := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(area) < 0.0001:
		return
	var img: Image = look["img"]
	var tint: Color = look["tint"]
	var cut: float = look["cut"]
	var saturation: float = look["saturation"]
	for y in range(maxi(0, int(minf(a.y, minf(b.y, c.y)))), mini(side, ceili(maxf(a.y, maxf(b.y, c.y))) + 1)):
		for x in range(maxi(0, int(minf(a.x, minf(b.x, c.x)))), mini(side, ceili(maxf(a.x, maxf(b.x, c.x))) + 1)):
			var px := x + 0.5 - c.x
			var py := y + 0.5 - c.y
			var u := ((b.y - c.y) * px + (c.x - b.x) * py) / area
			var v := ((c.y - a.y) * px + (a.x - c.x) * py) / area
			var w := 1.0 - u - v
			if u < 0.0 or v < 0.0 or w < 0.0:
				continue
			var z := u * a.z + v * b.z + w * c.z
			var at := y * side + x
			if z <= depth_buf[at]:
				continue
			var col := Color.WHITE
			if img != null:
				var st := uv[0] * u + uv[1] * v + uv[2] * w
				col = img.get_pixel(posmod(floori(st.x * 256.0), 256), posmod(floori(st.y * 256.0), 256))
				if col.a < cut:
					continue
				col = col.srgb_to_linear()
				if saturation < 1.0:
					var grey := col.get_luminance()
					col = Color(grey, grey, grey).lerp(col, saturation)
			var lit := u * light[0] + v * light[1] + w * light[2]
			depth_buf[at] = z
			# Brighter than the world, since the popup behind is nearly black.
			col = Color(col.r * tint.r * lit * 1.5, col.g * tint.g * lit * 1.5, col.b * tint.b * lit * 1.5).linear_to_srgb()
			color_buf[at] = Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 1.0)


func _up_arrow(img: Image) -> void:
	var mid := SIZE - 24
	var top := SIZE - 54
	for y in range(top - 2, top + 50):
		var head := y < top + 24
		var half := (y - top) * 0.85 if head else 8.0
		for x in range(mid - 23, mid + 24):
			var off := absf(x - mid)
			if off <= half and y < top + 45:
				img.set_pixel(x, y, GOLD)
			elif off <= half + 2.5 and y < top + 48:
				img.set_pixel(x, y, Color(0.1, 0.07, 0.04))
