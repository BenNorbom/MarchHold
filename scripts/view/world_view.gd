extends Node3D
## Renders the match: sky, sun, terrain, forests, rocks, buildings, projectiles
## and effects. People and animals are drawn by PeopleView.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const PeopleView = preload("res://scripts/view/people_view.gd")
const BattleFx = preload("res://scripts/view/battle_fx.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

const CHUNK := 32              # terrain cells per chunk side (64 m)
const TREE_CHUNK := 256.0
const GRASS_TILE := 16.0
const WALL_BANNER_EVERY := 3   # wall pieces per banner
const SPLAT_TEXEL := 2.0       # metres per splat map pixel
const LANDMARK_RANGE := 160.0  # names show from this far, unless a hill is in the way
const LANDMARK_CHECK := 0.2    # seconds between checks for hills in the way

var m                           # Match
var mats
var meshes
var quality := 1
var env: WorldEnvironment
var sun: DirectionalLight3D
var splat_img: Image
var splat_tex: ImageTexture
var terrain_mat: ShaderMaterial
var people: PeopleView
var battle_fx: BattleFx
var tick_alpha := 0.0           # how far this frame is between two sim ticks
var node_slots := {}            # resource node id -> [[MultiMesh, index], ...]
var bush_slots := {}            # the same for bush leaves, which outlast their berries
var bld_nodes := {}             # building id -> {"root", "mesh", "body", "tier", "len", "h", "fire"}
var grass_tiles := {}           # Vector2i -> MultiMeshInstance3D
var grass_radius := 32.0
var grass_mat: ShaderMaterial
var arrow_mm: MultiMesh
var ball_mm: MultiMesh
var banner_mats := {}           # faction id -> cloth material
var engine_nodes := {}          # unit id -> MeshInstance3D
var fx_pool: Array = []
var mark_node: Node3D
var ghost: MeshInstance3D
var ghost_line: Array = []
var hidden_unit := -1
var rng := RandomNumberGenerator.new()
var near_lod := 130.0
var cam_pos := Vector3.ZERO
var fires: Array = []
var selected_ids: Array[int] = []
var select_mm: MultiMesh
var landmark_labels: Node3D
var landmark_font: Font
var landmark_wait := 0.0


func setup(match_ref, materials, mesh_lib, q: int) -> void:
	m = match_ref
	mats = materials
	meshes = mesh_lib
	quality = q
	rng.seed = 99
	near_lod = [80.0, 110.0, 160.0][q]
	grass_radius = [20.0, 30.0, 38.0][q]
	_environment()
	_terrain()
	landmark_labels = Node3D.new()
	add_child(landmark_labels)
	landmark_font = UiTheme.font("res://assets/fonts/EBGaramond.ttf", 700)
	_nature()
	_show_landmark_labels()
	Settings.changed.connect(_show_landmark_labels)
	people = PeopleView.new()
	add_child(people)
	people.setup(m, mats, meshes, q)
	battle_fx = BattleFx.new()
	add_child(battle_fx)
	battle_fx.setup(mats, meshes)
	_projectiles()
	for b in m.buildings:
		_sync_building(b)
	ghost = MeshInstance3D.new()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	mark_node = _make_flag()
	mark_node.visible = false
	add_child(mark_node)
	_selection_rings()


## Flat glowing rings drawn under selected villagers.
func _selection_rings() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.62
	ring.rings = 24
	ring.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.35)
	mat.no_depth_test = false
	ring.material = mat
	select_mm = MultiMesh.new()
	select_mm.transform_format = MultiMesh.TRANSFORM_3D
	select_mm.mesh = ring
	select_mm.instance_count = 64
	select_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = select_mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-60, -60, -60), Vector3(m.map_size + 120, 320, m.map_size + 120))
	add_child(mi)


func _update_selection_rings(alpha: float) -> void:
	var n := 0
	for id in selected_ids:
		if n >= select_mm.instance_count:
			break
		var u = m.unit(id)
		if u == null or u.dead:
			continue
		var p: Vector2 = u.prev.lerp(u.pos, alpha)
		select_mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.4, 1)), m.terrain.pos3(p, 0.06)))
		n += 1
	select_mm.visible_instance_count = n


# --- Environment ------------------------------------------------------------------

func _environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = mats.sky_material()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if quality > 0 else Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = quality > 0
	e.glow_intensity = 0.35
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.2
	e.fog_enabled = true
	e.fog_light_color = Color(0.68, 0.76, 0.86)
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.25
	e.fog_density = 0.0008
	e.fog_aerial_perspective = 0.4
	e.fog_sky_affect = 0.25
	e.fog_height = 30.0
	e.fog_height_density = 0.004
	e.ssao_enabled = quality >= 1
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.3
	e.ssil_enabled = quality >= 2
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = quality >= 2
	e.volumetric_fog_density = 0.006
	e.volumetric_fog_albedo = Color(0.85, 0.88, 0.92)
	e.volumetric_fog_length = 120.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.06
	e.adjustment_contrast = 1.04
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0 + rng.randf_range(-40, 40), 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.25
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [110.0, 180.0, 260.0][quality]
	sun.directional_shadow_blend_splits = quality > 0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if quality < 2 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.72, 0.85, 1.0][quality]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.use_taa = quality >= 2
		vp.mesh_lod_threshold = [2.0, 1.0, 0.75][quality]


# --- Terrain -------------------------------------------------------------------------

func _terrain() -> void:
	var tr: Terrain = m.terrain
	_build_splat()
	terrain_mat = mats.terrain_material(splat_tex)
	terrain_mat.set_shader_parameter("map_size", tr.size)
	# Near: 64 m chunks at full detail. Far: 128 m chunks at half detail (fewer draw calls).
	var n := (tr.height_res - 1) / CHUNK
	for cj in n:
		for ci in n:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(tr, ci, cj, 1, CHUNK)
			mi.material_override = terrain_mat
			mi.visibility_range_end = 280.0
			mi.visibility_range_end_margin = 10.0
			add_child(mi)
	var n2 := (tr.height_res - 1) / (CHUNK * 2)
	for cj in n2:
		for ci in n2:
			var far := MeshInstance3D.new()
			far.mesh = _chunk_mesh(tr, ci, cj, 2, CHUNK * 2)
			far.material_override = terrain_mat
			far.visibility_range_begin = 200.0
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(far)
	# Collision for the commander.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = tr.height_res
	hm.map_depth = tr.height_res
	hm.map_data = tr.heights
	shape.shape = hm
	shape.scale = Vector3(Terrain.STEP, 1.0, Terrain.STEP)
	shape.position = Vector3(m.map_size * 0.5, 0.0, m.map_size * 0.5)
	body.add_child(shape)
	add_child(body)


func _chunk_mesh(tr: Terrain, ci: int, cj: int, step: int, chunk: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := chunk / step
	var i0 := ci * chunk
	var j0 := cj * chunk
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var w := cells + 1
	for j in w:
		for i in w:
			var gi := i0 + i * step
			var gj := j0 + j * step
			var x := gi * Terrain.STEP
			var z := gj * Terrain.STEP
			verts.append(Vector3(x, tr.heights[gj * tr.height_res + gi] - (0.06 if step > 1 else 0.0), z))
			norms.append(tr.normal_at(x, z))
			uvs.append(Vector2(x, z) * 0.25)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var idx := PackedInt32Array()
	for j in cells:
		for i in cells:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			idx.append_array([a, b, d, a, d, c])
	# Skirts hide cracks between levels of detail.
	var base := verts.size()
	var edge: Array = []
	for i in w:
		edge.append(i)
	for j in range(1, w):
		edge.append(j * w + cells)
	for i in range(cells - 1, -1, -1):
		edge.append(cells * w + i)
	for j in range(cells - 1, 0, -1):
		edge.append(j * w)
	for k in edge.size():
		var v: Vector3 = verts[edge[k]]
		verts.append(v - Vector3(0, 2.5, 0))
		norms.append(norms[edge[k]])
		uvs.append(uvs[edge[k]])
	for k in edge.size():
		var a2: int = edge[k]
		var b2: int = edge[(k + 1) % edge.size()]
		var a3 := base + k
		var b3 := base + (k + 1) % edge.size()
		idx.append_array([a2, a3, b2, b2, a3, b3])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(mesh, 0)
	st.generate_tangents()
	return st.commit()


func _build_splat() -> void:
	var tr: Terrain = m.terrain
	var s := int(m.map_size / SPLAT_TEXEL)
	splat_img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = tr.seed_value + 5
	noise.frequency = 0.02
	var dry := FastNoiseLite.new()
	dry.seed = tr.seed_value + 9
	dry.frequency = 0.006
	var k: float = m.map_size / s
	for y in s:
		for x in s:
			var px := (x + 0.5) * k
			var pz := (y + 0.5) * k
			var slope := tr.slope_deg(px, pz)
			var hgt := tr.height_at(px, pz)
			var rock := smoothstep(24.0, 38.0, slope) + smoothstep(55.0, 70.0, hgt) * 0.5
			var forest := tr.forest_at(px, pz)
			var dirt := clampf(noise.get_noise_2d(px, pz) * 1.4 - 0.55, 0.0, 1.0) * 0.6
			var dryness := clampf(dry.get_noise_2d(px, pz) * 1.2 + 0.1, 0.0, 1.0) * 0.5
			for st in tr.starts:
				var d: float = Vector2(px, pz).distance_to(st)
				if d < 30.0:
					dirt = maxf(dirt, (1.0 - d / 30.0) * 0.85)
			splat_img.set_pixel(x, y, Color(clampf(rock, 0, 1), dirt, forest * 0.95, dryness))
	# Rocks and deposits scuff the ground.
	for n in tr.nodes:
		if n.kind == "rock" or n.kind == "deposit":
			_paint(n.pos, 3.5 * n.scale + (4.0 if n.sub == "outcrop" or n.kind == "deposit" else 0.0), 0, 0.7)
	splat_tex = ImageTexture.create_from_image(splat_img)


## Paint a channel of the splat map around p (0 rock, 1 dirt, 2 forest, 3 dry).
func _paint(p: Vector2, r: float, channel: int, amount: float) -> void:
	var s := splat_img.get_width()
	var k: float = m.map_size / s
	var c := Vector2i(int(p.x / k), int(p.y / k))
	var rr := int(ceil(r / k))
	for y in range(maxi(0, c.y - rr), mini(s, c.y + rr + 1)):
		for x in range(maxi(0, c.x - rr), mini(s, c.x + rr + 1)):
			var d := Vector2((x + 0.5) * k, (y + 0.5) * k).distance_to(p)
			if d > r:
				continue
			var w := amount * (1.0 - smoothstep(r * 0.5, r, d))
			var col := splat_img.get_pixel(x, y)
			col[channel] = maxf(col[channel], w)
			if channel == 1:
				col.b = col.b * (1.0 - w * 0.8)
			splat_img.set_pixel(x, y, col)


func paint_dirt(p: Vector2, r: float) -> void:
	_paint(p, r, 1, 0.75)
	splat_tex.update(splat_img)


# --- Nature ---------------------------------------------------------------------------

func _nature() -> void:
	var tr: Terrain = m.terrain
	var groups := {}    # key -> Array of [node, transform]
	for n in tr.nodes:
		var key := ""
		var xf := Transform3D()
		var p := tr.pos3(n.pos)
		match n.kind:
			"tree":
				var variant: int = n.id % 3
				var cx := int(n.pos.x / TREE_CHUNK)
				var cz := int(n.pos.y / TREE_CHUNK)
				key = "tree:%s:%d:%d:%d" % [n.sub, variant, cx, cz]
				var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.05))
				xf = Transform3D(tilt * Basis(Vector3.UP, n.rot).scaled(Vector3.ONE * n.scale), p)
			"rock":
				key = "rock:%s:%d" % [n.sub, n.id % 3]
				var sc: float = n.scale * (1.0 if n.sub == "boulder" else 1.0)
				xf = Transform3D(Basis(Vector3.UP, n.rot).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.2), sc)), p - Vector3(0, 0.15, 0))
			"deposit":
				key = "dep:%s" % n.sub
				xf = Transform3D(Basis(Vector3.UP, n.rot), p - Vector3(0, 0.1, 0))
			"berry":
				key = "bush:%d:%d" % [int(n.pos.x / TREE_CHUNK), int(n.pos.y / TREE_CHUNK)]
				xf = Transform3D(Basis(Vector3.UP, n.rot).scaled(Vector3.ONE * n.scale), p - Vector3(0, 0.05, 0))
		if key == "":
			continue
		var title: String = n.landmark_name()
		if title != "":
			var mesh: Mesh = meshes.rock_mesh(n.sub, n.id % 3 if n.kind == "rock" else 0)
			# At least 4 m up, to clear a mine built on the deposit.
			var height := maxf(mesh.get_aabb().end.y * xf.basis.get_scale().y + 0.8, 4.0)
			_add_landmark_label(title, xf.origin + Vector3(0, height, 0))
		if not groups.has(key):
			groups[key] = []
		groups[key].append([n, xf])
	for key in groups:
		var parts: PackedStringArray = key.split(":")
		var list: Array = groups[key]
		match parts[0]:
			"tree":
				for lod in 2:
					var mm := _mm(meshes.tree(parts[1], int(parts[2]), lod), list, node_slots)
					var mi := MultiMeshInstance3D.new()
					mi.multimesh = mm
					# LOD is measured to the middle of the bounds. Fix them now, or
					# hide_node moving a felled tree away would drag that middle along.
					mi.custom_aabb = mm.get_aabb()
					if lod == 0:
						mi.visibility_range_end = near_lod
						mi.visibility_range_end_margin = 12.0
						mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
					else:
						mi.visibility_range_begin = near_lod
						mi.visibility_range_begin_margin = 12.0
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mi)
			"rock":
				var mi2 := MultiMeshInstance3D.new()
				mi2.multimesh = _mm(meshes.rock_mesh(parts[1], int(parts[2])), list, node_slots)
				# No visibility range, as for bushes: each group spans the whole map.
				add_child(mi2)
			"dep":
				var mi3 := MultiMeshInstance3D.new()
				mi3.multimesh = _mm(meshes.rock_mesh(parts[1], 0), list, node_slots)
				add_child(mi3)
			"bush":
				# No visibility range: it's measured to the middle of the whole
				# MultiMesh, not to each bush. The chunks are frustum culled.
				var mi4 := MultiMeshInstance3D.new()
				mi4.multimesh = _mm(meshes.bush(), list, bush_slots)
				add_child(mi4)
				var mi5 := MultiMeshInstance3D.new()
				mi5.multimesh = _mm(meshes.bush_berries(), list, node_slots)
				mi5.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi5)
	grass_mat = mats.get_mat("grass")


func _add_landmark_label(title: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = title
	label.font = landmark_font
	label.font_size = 32
	label.outline_size = 10
	label.modulate = UiTheme.INK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# The same size on screen at any distance, and readable through leaves.
	label.fixed_size = true
	label.pixel_size = 0.0017
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.visibility_range_end = LANDMARK_RANGE
	label.position = at
	landmark_labels.add_child(label)


func _show_landmark_labels() -> void:
	landmark_labels.visible = bool(Settings.get_val("resource_labels", true))


## Labels draw through everything so leaves can't hide them; hills still must.
func _update_landmark_labels(delta: float, cam: Vector3) -> void:
	landmark_wait -= delta
	if landmark_wait > 0.0 or not landmark_labels.visible:
		return
	landmark_wait = LANDMARK_CHECK
	for label: Label3D in landmark_labels.get_children():
		var at := label.position
		label.visible = cam.distance_to(at) < LANDMARK_RANGE and m.terrain.clear_line(cam, at)


func _mm(mesh: Mesh, list: Array, slots = null) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][1])
		if slots != null:
			var id: int = list[i][0].id
			if not slots.has(id):
				slots[id] = []
			slots[id].append([mm, i])
	return mm


func hide_node(id: int, slots: Dictionary = node_slots) -> void:
	for slot in slots.get(id, []):
		var mm: MultiMesh = slot[0]
		mm.set_instance_transform(slot[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -50, 0)))
	slots.erase(id)


# --- Grass ----------------------------------------------------------------------------

func _update_grass(cam: Vector3) -> void:
	var c := Vector2i(int(cam.x / GRASS_TILE), int(cam.z / GRASS_TILE))
	var r := int(ceil(grass_radius / GRASS_TILE))
	var want := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if k.x < 0 or k.y < 0 or k.x * GRASS_TILE >= m.map_size or k.y * GRASS_TILE >= m.map_size:
				continue
			var center := Vector2((k.x + 0.5) * GRASS_TILE, (k.y + 0.5) * GRASS_TILE)
			if center.distance_to(Vector2(cam.x, cam.z)) > grass_radius + GRASS_TILE:
				continue
			want[k] = true
			if not grass_tiles.has(k):
				grass_tiles[k] = _grass_tile(k)
	for k in grass_tiles.keys():
		if not want.has(k):
			grass_tiles[k].queue_free()
			grass_tiles.erase(k)
	grass_mat.set_shader_parameter("player_pos", cam)
	grass_mat.set_shader_parameter("fade_start", grass_radius - 8.0)
	grass_mat.set_shader_parameter("fade_end", grass_radius)


func _grass_tile(k: Vector2i) -> MultiMeshInstance3D:
	var tr: Terrain = m.terrain
	var r := RandomNumberGenerator.new()
	r.seed = k.x * 7919 + k.y * 104729
	var xfs: Array = []
	var density: int = [320, 720, 1000][quality]
	var s := splat_img.get_width()
	var kk: float = m.map_size / s
	for i in density:
		var p := Vector2((k.x + r.randf()) * GRASS_TILE, (k.y + r.randf()) * GRASS_TILE)
		var sp := splat_img.get_pixel(clampi(int(p.x / kk), 0, s - 1), clampi(int(p.y / kk), 0, s - 1))
		if sp.r > 0.3 or sp.g > 0.45 or r.randf() < sp.b * 0.8:
			continue
		var sc := r.randf_range(0.6, 1.15)
		xfs.append([Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sc, sc * r.randf_range(0.8, 1.4), sc)), tr.pos3(p) - Vector3(0, 0.03, 0)), sp.a])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = meshes.grass_clump()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i][0])
		mm.set_instance_custom_data(i, Color(clampf(xfs[i][1] + r.randf_range(-0.2, 0.3), 0, 1), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- Buildings ----------------------------------------------------------------------

func _sync_building(b) -> void:
	if b.dead:
		_remove_building(b.id)
		return
	var d: Dictionary = Defs.BUILDINGS[b.type]
	var is_wall: bool = d.get("wall", false)
	var length: float = snappedf(b.size.x, 0.5) if is_wall else 4.0
	var info: Dictionary = bld_nodes.get(b.id, {})
	if info.is_empty() or info["tier"] != b.tier:
		_remove_building(b.id)
		var root := Node3D.new()
		var tr: Terrain = m.terrain
		var base_y := _base_height(b)
		root.position = Vector3(b.pos.x, base_y, b.pos.y)
		root.rotation.y = -b.rot
		var mi := MeshInstance3D.new()
		var mesh: ArrayMesh = meshes.building(b.type, b.tier, length)
		mi.mesh = mesh
		if is_wall:
			mi.scale = Vector3(b.size.x / length, 1, 1)
		root.add_child(mi)
		add_child(root)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var h: float = meshes.building_height(b.type, b.tier, length)
		var col_h := h if not d.get("walkable", false) else 0.2
		box.size = Vector3(b.size.x, col_h, b.size.y)
		cs.shape = box
		cs.position = Vector3(0, col_h * 0.5, 0)
		body.add_child(cs)
		root.add_child(body)
		if d.get("walkable", false):
			body.collision_layer = 0
		info = {"root": root, "mesh": mi, "body": body, "tier": b.tier, "h": h, "fire": null, "complete": false}
		bld_nodes[b.id] = info
		_paint_for(b)
		if b.type == "campfire" or (b.type == "smelter") or (b.type == "armory" and b.tier >= 1):
			info["fire"] = _make_fire(root, b)
	var mi2: MeshInstance3D = info["mesh"]
	var level: float = 999.0 if b.complete else (-0.2 + (float(info["h"]) + 0.4) * b.progress if b.paid else -0.25)
	mi2.set_instance_shader_parameter("build_level", level)
	mi2.set_instance_shader_parameter("damage", clampf(1.0 - b.hp / b.max_hp, 0.0, 1.0) * 0.6 if b.complete else 0.0)
	var body2: StaticBody3D = info["body"]
	body2.collision_layer = 1 if (b.blocking or b.complete) and not Defs.BUILDINGS[b.type].get("walkable", false) else 0
	# Your own gates let you through.
	if Defs.BUILDINGS[b.type].get("gate", false) and b.faction == 0:
		body2.collision_layer = 0
	if b.complete and not info["complete"]:
		info["complete"] = true
		# Walls carry one every few pieces, gates always.
		if not is_wall or d.get("gate", false) or b.line < 0 or (b.id - b.line) % WALL_BANNER_EVERY == 0:
			_add_banner(info["root"], b.faction, meshes.banner_spot(b.type, b.size))
		paint_dirt(b.pos, b.size.length() * 0.5 + 2.5)


func _add_banner(parent: Node3D, faction: int, spot: Array) -> void:
	var f = m.fac(faction)
	if f == null or spot.is_empty():
		return
	if not banner_mats.has(faction):
		banner_mats[faction] = mats.banner(f.color)
	var height: float = spot[1]
	var pole := MeshInstance3D.new()
	pole.name = "Banner"
	pole.mesh = meshes.banner_pole(height)
	pole.position = spot[0]
	var cloth := MeshInstance3D.new()
	cloth.mesh = meshes.banner_cloth()
	cloth.material_override = banner_mats[faction]
	cloth.position.y = height - 0.05
	cloth.scale = Vector3.ONE * float(spot[2])
	# The shader turns the cloth about the pole, so it can be culled only by the whole circle it sweeps.
	cloth.custom_aabb = AABB(Vector3(-1.8, -1.3, -1.8), Vector3(3.6, 1.6, 3.6))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # it would turn toward the sun in the shadow pass
	pole.add_child(cloth)
	parent.add_child(pole)


func _base_height(b) -> float:
	var tr: Terrain = m.terrain
	var lo := INF
	var ax: Vector2 = Vector2.from_angle(b.rot) * b.size.x * 0.5
	var az: Vector2 = Vector2.from_angle(b.rot + PI * 0.5) * b.size.y * 0.5
	for p in [b.pos, b.pos + ax + az, b.pos + ax - az, b.pos - ax + az, b.pos - ax - az]:
		lo = minf(lo, tr.height_at(p.x, p.y))
	var mid := tr.height_at(b.pos.x, b.pos.y)
	return lerpf(lo, mid, 0.35)


func _paint_for(b) -> void:
	if b.type == "farm" or Defs.BUILDINGS[b.type].get("wall", false):
		return
	_paint(b.pos, b.size.length() * 0.5 + 1.5, 1, 0.6)
	splat_tex.update(splat_img)


func _remove_building(id: int) -> void:
	var info: Dictionary = bld_nodes.get(id, {})
	if info.is_empty():
		return
	info["root"].queue_free()
	bld_nodes.erase(id)


func _make_fire(root: Node3D, b) -> Node3D:
	var n := Node3D.new()
	var offset := Vector3.ZERO
	if b.type == "smelter":
		offset = Vector3(0, 0.8, 1.5)
	elif b.type == "armory":
		offset = Vector3(b.size.x * 0.5 + 0.9, 1.1, 0)
	n.position = offset
	root.add_child(n)
	var flames := GPUParticles3D.new()
	flames.amount = 24 if b.type == "campfire" else 10
	flames.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 if b.type == "campfire" else 0.2
	pm.gravity = Vector3(0, 2.2, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	grad.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	flames.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.8)
	quad.material = mats.get_mat("flame")
	flames.draw_pass_1 = quad
	flames.position = Vector3(0, 0.25, 0)
	n.add_child(flames)
	var smoke := GPUParticles3D.new()
	smoke.amount = 16
	smoke.lifetime = 5.0
	var sm := ParticleProcessMaterial.new()
	sm.gravity = Vector3(0.4, 1.0, 0.2)
	sm.initial_velocity_min = 0.3
	sm.initial_velocity_max = 0.6
	sm.scale_min = 1.0
	sm.scale_max = 2.6
	var sg := Gradient.new()
	sg.set_color(0, Color(0.45, 0.43, 0.42, 0.35))
	sg.set_color(1, Color(0.7, 0.7, 0.72, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sm.color_ramp = sgt
	smoke.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(1.6, 1.6)
	sq.material = mats.get_mat("smoke")
	smoke.draw_pass_1 = sq
	smoke.position = Vector3(0, 1.2 if b.type == "campfire" else 3.5, 0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 2.2 if b.type == "campfire" else 1.3
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0.8, 0)
	n.add_child(light)
	fires.append(light)
	return n


# --- Projectiles and effects ----------------------------------------------------------

func _projectiles() -> void:
	arrow_mm = MultiMesh.new()
	arrow_mm.transform_format = MultiMesh.TRANSFORM_3D
	arrow_mm.mesh = meshes.arrow()
	arrow_mm.instance_count = 400
	arrow_mm.visible_instance_count = 0
	var ai := MultiMeshInstance3D.new()
	ai.multimesh = arrow_mm
	ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ai.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(m.map_size + 276, 400, m.map_size + 276))
	add_child(ai)
	ball_mm = MultiMesh.new()
	ball_mm.transform_format = MultiMesh.TRANSFORM_3D
	ball_mm.mesh = meshes.ball()
	ball_mm.instance_count = 40
	ball_mm.visible_instance_count = 0
	var bi := MultiMeshInstance3D.new()
	bi.multimesh = ball_mm
	bi.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(m.map_size + 276, 400, m.map_size + 276))
	add_child(bi)
	for i in 12:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 28
		p.lifetime = 2.5
		p.explosiveness = 0.9
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 70.0
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 4.0
		pm.gravity = Vector3(0, 0.3, 0)
		pm.damping_min = 1.5
		pm.damping_max = 2.5
		pm.scale_min = 1.0
		pm.scale_max = 2.4
		var g := Gradient.new()
		g.set_color(0, Color(0.75, 0.72, 0.68, 0.6))
		g.set_color(1, Color(0.8, 0.78, 0.75, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.5, 1.5)
		q.material = mats.get_mat("smoke")
		p.draw_pass_1 = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		fx_pool.append(p)


func puff(p: Vector3, big: bool) -> void:
	for fx in fx_pool:
		if not fx.emitting:
			fx.global_position = p
			fx.amount_ratio = 1.0 if big else 0.35
			fx.restart()
			fx.emitting = true
			return


func _update_shots() -> void:
	var alpha := tick_alpha
	var na := 0
	var nb := 0
	for s in m.shots:
		if s.t == 0.0:
			continue      # loosed since the last tick
		var at: Vector3 = s.prev.lerp(s.pos, alpha)
		if s.kind == "arrow":
			if na >= arrow_mm.instance_count:
				continue
			var dir: Vector3
			if s.free:
				dir = s.vel
			else:
				var k := clampf((s.t - Defs.TICK * (1.0 - alpha)) / s.dur, 0.0, 1.0)
				dir = (s.end - s.start) + Vector3(0, (4.0 - 8.0 * k) * s.start.distance_to(s.end) * s.arc, 0)
			if dir.length() < 0.01:
				dir = Vector3.FORWARD
			arrow_mm.set_instance_transform(na, Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.RIGHT), at))
			na += 1
		else:
			if nb >= ball_mm.instance_count:
				continue
			ball_mm.set_instance_transform(nb, Transform3D(Basis(), at))
			nb += 1
	arrow_mm.visible_instance_count = na
	ball_mm.visible_instance_count = nb


func _update_engines(alpha: float) -> void:
	var seen := {}
	for u in m.units:
		if u.dead or not u.kind in ["cannon", "ram"]:
			continue
		seen[u.id] = true
		var mi: MeshInstance3D = engine_nodes.get(u.id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = meshes.cannon() if u.kind == "cannon" else meshes.ram()
			add_child(mi)
			_add_banner(mi, u.faction, meshes.banner_spot(u.kind))
			engine_nodes[u.id] = mi
		var p: Vector2 = u.prev.lerp(u.pos, alpha)
		var tr: Terrain = m.terrain
		mi.global_transform = Transform3D(Basis(Vector3.UP, u.facing), tr.pos3(p))
	for id in engine_nodes.keys():
		if not seen.has(id):
			engine_nodes[id].queue_free()
			engine_nodes.erase(id)


func _make_flag() -> Node3D:
	var n := Node3D.new()
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 3.0
	pole.mesh = cm
	pole.position = Vector3(0, 1.5, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.35, 0.25, 0.15)
	pole.material_override = pm
	n.add_child(pole)
	var cloth := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 0.6)
	cloth.mesh = qm
	cloth.position = Vector3(0.5, 2.65, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.85, 0.75, 0.2)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.emission_enabled = true
	cmat.emission = Color(0.4, 0.3, 0.05)
	cloth.material_override = cmat
	n.add_child(cloth)
	return n


# --- Placement ghost --------------------------------------------------------------------

func show_ghost(type: String, p: Vector2, rot: float, ok: bool) -> void:
	var tr: Terrain = m.terrain
	ghost.mesh = meshes.ghost(type, ok)
	ghost.global_transform = Transform3D(Basis(Vector3.UP, -rot), tr.pos3(p))
	ghost.visible = true


func show_wall_ghosts(type: String, pieces: Array) -> void:
	# pieces: [[mid, rot, length, ok], ...]
	while ghost_line.size() < pieces.size():
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		ghost_line.append(mi)
	var tr: Terrain = m.terrain
	for i in ghost_line.size():
		var mi: MeshInstance3D = ghost_line[i]
		if i >= pieces.size():
			mi.visible = false
			continue
		var pc: Array = pieces[i]
		mi.mesh = meshes.ghost(type, pc[3])
		mi.global_transform = Transform3D(Basis(Vector3.UP, -float(pc[1])).scaled(Vector3(float(pc[2]) / 4.0, 1, 1)), tr.pos3(pc[0]))
		mi.visible = true


func hide_ghost() -> void:
	ghost.visible = false
	for mi in ghost_line:
		mi.visible = false


# --- Frame update -----------------------------------------------------------------------

func handle_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"building", "building_hit":
				var b = m.bld(ev["id"])
				if b:
					_sync_building(b)
			"building_gone":
				var info: Dictionary = bld_nodes.get(ev["id"], {})
				if not info.is_empty():
					puff(info["root"].global_position + Vector3(0, 1.5, 0), true)
				_remove_building(ev["id"])
			"node_gone":
				hide_node(ev["id"])
				if ev.get("cleared", false):
					hide_node(ev["id"], bush_slots)
			"node_new":
				var n = m.terrain.nodes[ev["id"]]
				if n.kind == "carcass":
					var mi := MeshInstance3D.new()
					mi.mesh = meshes.carcass()
					mi.position = m.terrain.pos3(n.pos)
					mi.rotation.y = n.rot
					add_child(mi)
					node_slots[n.id] = []
					carcasses[n.id] = mi
			"hit":
				people.on_hit(ev)
				battle_fx.hit(ev, m.terrain.pos3(ev["pos"]))
			"death":
				if ev["kind"] != "deer":
					battle_fx.fallen(m.terrain.pos3(ev["pos"]))
			"fx":
				var p: Vector2 = ev["pos"]
				if ev["name"] == "arrow_land":
					battle_fx.arrow_landed(ev["at"], ev["dir"], ev["hit"])
				elif ev["name"] == "muzzle":
					puff(m.terrain.pos3(p, 1.2), true)
				elif ev["name"] == "impact":
					puff(m.terrain.pos3(p, 0.3), true)


var carcasses := {}


func update_frame(delta: float, alpha: float, cam: Vector3) -> void:
	tick_alpha = alpha
	cam_pos = cam
	_update_grass(cam)
	_update_landmark_labels(delta, cam)
	_update_shots()
	_update_engines(alpha)
	people.update_frame(delta, alpha, cam, hidden_unit)
	battle_fx.update_frame(delta, cam)
	_update_selection_rings(alpha)
	for id in carcasses.keys():
		var n = m.terrain.nodes[id]
		if n.amount <= 0.0:
			carcasses[id].queue_free()
			carcasses.erase(id)
	# Fire flicker.
	var t := Time.get_ticks_msec() * 0.001
	for i in fires.size():
		var l: OmniLight3D = fires[i]
		if is_instance_valid(l):
			l.light_energy = 1.8 + 0.4 * sin(t * 11.0 + i) + 0.25 * sin(t * 23.0 + i * 2.0)
	var f = m.fac(0)
	mark_node.visible = f.has_mark
	if f.has_mark:
		mark_node.global_position = m.terrain.pos3(f.mark)
	# Keep building damage and construction up to date for buildings in work.
	for b in m.buildings:
		if not b.complete and not b.dead and b.paid:
			_sync_building(b)


func ground_hit(from: Vector3, dir: Vector3, max_d: float = 120.0):
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_d)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit["position"]


## The person or animal closest to the view ray, if any.
func pick_unit(from: Vector3, dir: Vector3, max_d: float = 40.0, faction: int = -99) -> int:
	var best := -1
	var best_score := INF
	for u in m.units:
		if u.dead or u.id == hidden_unit or u.stable >= 0:
			continue
		if faction != -99 and u.faction != faction:
			continue
		var p: Vector3 = m.terrain.pos3(u.pos, 1.2 if not u.mounted else 1.9)
		var to := p - from
		var along := to.dot(dir)
		if along < 0.5 or along > max_d:
			continue
		var off := (to - dir * along).length()
		var tol := 0.55 + along * 0.02
		if off > tol:
			continue
		var score := off / tol + along * 0.01
		if score < best_score:
			best_score = score
			best = u.id
	return best


## A hillshaded picture of the map, used for the field map.
func map_image(size: int = 512) -> Image:
	var tr: Terrain = m.terrain
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var k: float = m.map_size / size
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	for y in size:
		for x in size:
			var px := (x + 0.5) * k
			var pz := (y + 0.5) * k
			var n := tr.normal_at(px, pz)
			var shade := clampf(n.dot(light) * 0.9 + 0.25, 0.25, 1.15)
			var base := Color(0.82, 0.74, 0.56)
			var fo := tr.forest_at(px, pz)
			base = base.lerp(Color(0.48, 0.52, 0.34), fo * 0.8)
			var h := tr.height_at(px, pz)
			base = base.lerp(Color(0.7, 0.66, 0.6), smoothstep(45.0, 70.0, h) * 0.6)
			img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade))
	return img
