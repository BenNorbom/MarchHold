extends RefCounted
## Material library: photographic CC0 textures plus procedurally painted
## leaves, needles, grass and noise. Built once per match.

const TEX := "res://assets/textures/%s_%s.jpg"

const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const PERSON_SHADER := preload("res://shaders/person.gdshader")
const ROCK_SHADER := preload("res://shaders/rock.gdshader")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const GHOST_SHADER := preload("res://shaders/ghost.gdshader")
const SKY_SHADER := preload("res://shaders/sky.gdshader")

var mats := {}
var noise: Texture2D
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1234
	noise = make_noise(256, 0.035, 4)


func tex(name: String, map: String) -> Texture2D:
	return load(TEX % [name, map])


func pbr(texname: String, uv_scale: float, tint := Color(1, 1, 1), metal := 0.0, rough := 1.0, ndepth := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BUILDING_SHADER
	m.set_shader_parameter("albedo_tex", tex(texname, "diff"))
	m.set_shader_parameter("normal_tex", tex(texname, "nor"))
	m.set_shader_parameter("arm_tex", tex(texname, "arm"))
	m.set_shader_parameter("uv_scale", uv_scale)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough_mul", rough)
	m.set_shader_parameter("normal_depth", ndepth)
	return m


func get_mat(name: String) -> Material:
	if mats.has(name):
		return mats[name]
	var m: Material
	match name:
		"planks":
			m = pbr("weathered_planks", 0.45)
		"logs":
			m = pbr("wood_trunk_wall", 0.3)
		"roughwood":
			m = pbr("rough_wood", 0.55)
		"darkwood":
			m = pbr("rough_wood", 0.55, Color(0.55, 0.45, 0.38))
		"thatch":
			m = pbr("thatch_roof_angled", 0.32, Color(1.0, 0.95, 0.88))
		"stone":
			m = pbr("castle_wall_slates", 0.28)
		"plaster":
			m = pbr("white_rough_plaster", 0.35, Color(0.92, 0.88, 0.8))
		"soil":
			m = pbr("farm_soil", 0.22)
		"dirt":
			m = pbr("brown_mud_leaves_01", 0.25)
		"metal":
			m = pbr("rough_wood", 0.5, Color(0.32, 0.32, 0.34), 0.85, 0.45)
		"bronze":
			m = pbr("rough_wood", 0.5, Color(0.7, 0.45, 0.22), 0.9, 0.45)
		"ember":
			m = pbr("rock_boulder_dry", 0.5, Color(0.25, 0.2, 0.18))
			m.set_shader_parameter("emission", 2.2)
			m.set_shader_parameter("emission_color", Vector3(1.0, 0.42, 0.12))
		"oak_bark":
			m = pbr("bark_brown_02", 0.6)
		"pine_bark":
			m = pbr("pine_bark", 0.5)
		"oak_leaves":
			m = foliage(make_leaves(false), Color(0.78, 0.86, 0.62), 0.42)
		"pine_needles":
			m = foliage(make_needles(), Color(0.7, 0.8, 0.62), 0.4)
		"bush_leaves":
			m = foliage(make_leaves(false), Color(0.6, 0.72, 0.45), 0.45)
		"crop":
			m = foliage(make_grass(true), Color(1.0, 0.92, 0.62), 0.45)
		"grass":
			m = ShaderMaterial.new()
			m.shader = GRASS_SHADER
			m.set_shader_parameter("blade_tex", make_grass(false))
		"boulder":
			m = rock("rock_boulder_dry", Color(0.95, 0.93, 0.9), 0.32)
		"outcrop":
			m = rock("rock_face", Color(0.9, 0.9, 0.88), 0.12)
		"dep_bronze_ore":
			m = rock("rock_boulder_dry", Color(0.75, 0.68, 0.6), 0.3, Color(0.25, 0.62, 0.48), 0.85, 0.5)
		"dep_coal":
			m = rock("rock_boulder_dry", Color(0.28, 0.27, 0.27), 0.3, Color(0.04, 0.04, 0.05), 0.9, 0.0)
		"dep_iron_ore":
			m = rock("rock_boulder_dry", Color(0.72, 0.55, 0.45), 0.3, Color(0.55, 0.22, 0.12), 0.85, 0.2)
		"person":
			m = ShaderMaterial.new()
			m.shader = PERSON_SHADER
			m.set_shader_parameter("cloth_noise", noise)
		"animal":
			m = ShaderMaterial.new()
			m.shader = PERSON_SHADER
			m.set_shader_parameter("cloth_noise", noise)
			m.set_shader_parameter("is_animal", true)
		"ghost_ok":
			m = ShaderMaterial.new()
			m.shader = GHOST_SHADER
			m.set_shader_parameter("color", Color(0.35, 0.95, 0.45, 0.32))
		"ghost_bad":
			m = ShaderMaterial.new()
			m.shader = GHOST_SHADER
			m.set_shader_parameter("color", Color(1.0, 0.3, 0.25, 0.35))
		"berries":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.55, 0.05, 0.08)
			sm.roughness = 0.35
			m = sm
		"arrow":
			var sm2 := StandardMaterial3D.new()
			sm2.albedo_color = Color(0.45, 0.33, 0.2)
			sm2.roughness = 0.7
			m = sm2
		"ball":
			var sm3 := StandardMaterial3D.new()
			sm3.albedo_color = Color(0.12, 0.12, 0.13)
			sm3.metallic = 0.8
			sm3.roughness = 0.4
			m = sm3
		"flame":
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			fm.vertex_color_use_as_albedo = true
			fm.albedo_texture = make_soft_dot()
			fm.albedo_color = Color(1.0, 0.55, 0.2)
			m = fm
		"smoke":
			var sm4 := StandardMaterial3D.new()
			sm4.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm4.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sm4.vertex_color_use_as_albedo = true
			sm4.albedo_texture = make_soft_dot()
			sm4.albedo_color = Color(0.62, 0.6, 0.58, 0.5)
			sm4.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m = sm4
		_:
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(1, 0, 1)
			m = d
	mats[name] = m
	return m


func foliage(t: Texture2D, tint: Color, cut: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("leaf_tex", t)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("alpha_cut", cut)
	return m


func rock(texname: String, tint: Color, scale: float, vein := Color(1, 1, 1), vein_amt := 0.0, vein_metal := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("albedo_tex", tex(texname, "diff"))
	m.set_shader_parameter("normal_tex", tex(texname, "nor"))
	m.set_shader_parameter("arm_tex", tex(texname, "arm"))
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("vein_color", Vector3(vein.r, vein.g, vein.b))
	m.set_shader_parameter("vein_amount", vein_amt)
	m.set_shader_parameter("vein_metal", vein_metal)
	return m


func terrain_material(splat: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("splat", splat)
	m.set_shader_parameter("noise_tex", noise)
	for pair in [["grass", "leafy_grass"], ["forest", "forrest_ground_01"], ["dirt", "brown_mud_leaves_01"], ["rock", "rock_face"]]:
		m.set_shader_parameter(pair[0] + "_alb", tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_nrm", tex(pair[1], "nor"))
		m.set_shader_parameter(pair[0] + "_arm", tex(pair[1], "arm"))
	return m


func sky_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	m.set_shader_parameter("cloud_noise", make_noise(256, 0.02, 5, true))
	return m


# --- Procedural textures ---------------------------------------------------------

func make_noise(size: int, freq: float, octaves: int, seamless: bool = true) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = seamless
	t.noise = n
	t.generate_mipmaps = true
	t.normalize = true
	return t


func make_soft_dot() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## Clusters of leaves (oak) or needles (pine) on a transparent card.
func make_leaves(needles: bool) -> Texture2D:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.18, 0.26, 0.1, 0.0))
	var count := 340 if needles else 150
	for i in count:
		# Keep the cluster roughly round so card edges never show.
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * s * 0.42
		var cx := s * 0.5 + cos(ang) * r
		var cy := s * 0.5 + sin(ang) * r
		var g := rng.randf_range(0.55, 1.0)
		var col := Color(0.22 * g, 0.36 * g + 0.05, 0.12 * g, 1.0) if not needles else Color(0.14 * g, 0.26 * g + 0.04, 0.13 * g, 1.0)
		if not needles and rng.randf() < 0.15:
			col = col.lerp(Color(0.45, 0.48, 0.18), 0.4)
		var length := rng.randf_range(10.0, 18.0) if not needles else rng.randf_range(12.0, 22.0)
		var width := rng.randf_range(5.0, 8.5) if not needles else 1.3
		var rot := rng.randf() * TAU if not needles else ang + rng.randf_range(-0.6, 0.6)
		_ellipse(img, Vector2(cx, cy), length, width, rot, col)
	return _foliage_tex(img)


func _ellipse(img: Image, c: Vector2, length: float, width: float, rot: float, col: Color) -> void:
	var s := img.get_width()
	var ax := Vector2.from_angle(rot)
	var ay := Vector2(-ax.y, ax.x)
	var r := int(length) + 1
	for y in range(maxi(0, int(c.y) - r), mini(s, int(c.y) + r + 1)):
		for x in range(maxi(0, int(c.x) - r), mini(s, int(c.x) + r + 1)):
			var d := Vector2(x, y) - c
			var u := d.dot(ax) / (length * 0.5)
			var v := d.dot(ay) / (width * 0.5)
			var e := u * u + v * v
			if e <= 1.0:
				# Lighter along the midrib, darker toward the edge.
				var shade := 1.0 - 0.35 * absf(v) + 0.1 * (1.0 - absf(u))
				img.set_pixel(x, y, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))


## A pine branch: a twig running up the card with needles on both sides.
func make_needles() -> Texture2D:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.18, 0.1, 0.0))
	for y in range(6, h - 2):
		var x := int(w * 0.5 + sin(y * 0.03) * 3.0)
		for dx in range(-1, 2):
			img.set_pixel(clampi(x + dx, 0, w - 1), y, Color(0.3, 0.2, 0.12, 1.0))
	for i in 900:
		var y := rng.randf_range(8.0, h - 4.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var k := y / h
		var length := rng.randf_range(16.0, 34.0) * (0.45 + 0.55 * k)
		var ang := rng.randf_range(0.5, 1.15)
		var dir := Vector2(side * sin(ang), -cos(ang))
		var start := Vector2(w * 0.5 + sin(y * 0.03) * 3.0, y)
		var g := rng.randf_range(0.6, 1.0)
		var col := Color(0.12 * g, 0.24 * g + 0.04, 0.12 * g, 1.0)
		var steps := int(length)
		for s2 in steps:
			var p := start + dir * s2
			for o in [Vector2.ZERO, Vector2(1, 0)]:
				var q: Vector2 = p + o
				if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h:
					img.set_pixel(int(q.x), int(q.y), col)
	return _foliage_tex(img)


## Mipmaps whose alpha is boosted per level, so foliage keeps its coverage at a distance.
func _foliage_tex(img: Image) -> Texture2D:
	img.generate_mipmaps()
	var data := img.get_data()
	var levels := img.get_mipmap_count()
	for level in range(1, levels + 1):
		var start := img.get_mipmap_offset(level)
		var end := img.get_mipmap_offset(level + 1) if level < levels else data.size()
		var boost := 1.0 + 0.55 * level
		var i := start + 3
		while i < end:
			data[i] = mini(255, int(data[i] * boost))
			i += 4
	var out := Image.create_from_data(img.get_width(), img.get_height(), true, img.get_format(), data)
	return ImageTexture.create_from_image(out)


## Grass blades (or wheat stalks with heads).
func make_grass(wheat: bool) -> Texture2D:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.15, 0.0))
	var blades := 44 if not wheat else 18
	for i in blades:
		var x0 := rng.randf_range(10.0, w - 10.0)
		var lean := rng.randf_range(-22.0, 22.0)
		var top := rng.randf_range(h * 0.05, h * 0.45)
		var width := rng.randf_range(1.0, 2.0) if not wheat else rng.randf_range(1.4, 2.8)
		var g := rng.randf_range(0.6, 1.0)
		var col := Color(0.85 * g, 0.95 * g, 0.7 * g) if not wheat else Color(0.75 * g, 0.62 * g, 0.3 * g)
		var y := float(h - 1)
		while y > top:
			var k := (h - y) / (h - top)
			var x := x0 + lean * k * k
			var half := width * (1.0 - k * 0.85)
			for xx in range(int(x - half), int(x + half) + 1):
				if xx >= 0 and xx < w:
					var shade := 0.7 + 0.3 * k
					img.set_pixel(xx, int(y), Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
			y -= 1.0
		if wheat:
			var hx := x0 + lean
			for j in 26:
				var yy := int(top) + j
				for xx in range(int(hx - 3), int(hx + 4)):
					if xx >= 0 and xx < w and yy < h:
						img.set_pixel(xx, yy, Color(0.85, 0.72, 0.38, 1.0))
	return _foliage_tex(img)
