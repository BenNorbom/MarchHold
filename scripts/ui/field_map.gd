extends Control
## The field map: a parchment that only shows ground the commander has seen or
## scouts have reported, with every mark stamped with how long ago it was seen.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")

var m
var base_tex: ImageTexture
var fog_img: Image
var fog_tex: ImageTexture
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(match_ref, map_img: Image) -> void:
	m = match_ref
	base_tex = ImageTexture.create_from_image(map_img)
	fog_img = Image.create(m.kres, m.kres, false, Image.FORMAT_RGBA8)
	fog_tex = ImageTexture.create_from_image(fog_img)
	font = get_theme_default_font()


func refresh() -> void:
	if m == null:
		return
	var f = m.fac(0)
	var now: float = m.t
	var n: int = m.kres
	for j in n:
		for i in n:
			var seen: float = f.knowledge[j * n + i]
			var col: Color
			if seen < 0.0:
				col = Color(0.86, 0.79, 0.62, 1.0)
			else:
				var age := now - seen
				col = Color(0.86, 0.79, 0.62, clampf(age / 600.0, 0.0, 0.45))
			fog_img.set_pixel(i, j, col)
	fog_tex.update(fog_img)
	queue_redraw()


func _rect() -> Rect2:
	var s := minf(size.x, size.y) * 0.86
	return Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))


func _to_screen(r: Rect2, p: Vector2) -> Vector2:
	return r.position + p / m.map_size * r.size


func _ago(t: float) -> String:
	var a := int((m.t - t) / 60.0)
	return "now" if a < 1 else "%dm" % a


func _draw() -> void:
	if m == null:
		return
	var r := _rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(r.grow(18), Color(0.62, 0.52, 0.36))
	draw_rect(r.grow(14), Color(0.86, 0.79, 0.62))
	draw_texture_rect(base_tex, r, false, Color(1, 0.97, 0.9))
	draw_texture_rect(fog_tex, r, false)
	var f = m.fac(0)
	var ink := Color(0.22, 0.15, 0.08)
	var ours: Color = f.color
	# Known terrain features.
	var show_names := bool(Settings.get_val("resource_labels", true))
	for n in m.terrain.nodes:
		var title: String = n.landmark_name()
		if title == "":
			continue
		var k: int = m.kcell(n.pos)
		if f.knowledge[k] < 0.0:
			continue
		var p := _to_screen(r, n.pos)
		var col := Color(0.35, 0.33, 0.3)
		if n.kind == "deposit":
			col = {"bronze_ore": Color(0.2, 0.55, 0.45), "coal": Color(0.08, 0.08, 0.08), "iron_ore": Color(0.6, 0.25, 0.15)}[n.sub]
		draw_circle(p, 4.5, col)
		if show_names:
			draw_string(font, p + Vector2(6, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	# Your buildings.
	for b in m.buildings:
		if b.dead or b.faction != 0:
			continue
		var p := _to_screen(r, b.pos)
		var sz := 3.0 if Defs.BUILDINGS[b.type].get("wall", false) else 5.0
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), ours)
		if b.type == "campfire":
			draw_circle(p, 7, ours)
			draw_string(font, p + Vector2(9, 5), "Home", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
	# What you know about the enemy.
	for key in f.intel:
		var e: Dictionary = f.intel[key]
		var side = m.fac(int(e.get("faction", -1)))
		var theirs: Color = side.color if side else Color(0.6, 0.12, 0.1)
		var p := _to_screen(r, e["pos"])
		match e["kind"]:
			"building":
				if e.get("faction", -1) == 0:
					continue
				var sz := 3.0 if Defs.BUILDINGS[e["type"]].get("wall", false) else 5.0
				draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), theirs)
				if e["type"] == "campfire":
					draw_circle(p, 8, theirs)
					draw_string(font, p + Vector2(10, 5), "%s's camp (%s)" % [m.fac(e["faction"]).short_name, _ago(e["t"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, theirs.darkened(0.45))
			"units":
				if e.get("faction", -1) == 0 or m.t - float(e["t"]) > 300.0:
					continue
				draw_circle(p, 5, theirs)
				draw_string(font, p + Vector2(7, -4), "%d (%s)" % [int(e["total"]), _ago(e["t"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, theirs.darkened(0.45))
			"herd":
				draw_string(font, p - Vector2(6, -4), "≈", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.45, 0.3, 0.1))
				draw_string(font, p + Vector2(8, 4), "horses (%s)" % _ago(e["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.3, 0.1))
	# The mark and you.
	if f.has_mark:
		var mp := _to_screen(r, f.mark)
		draw_line(mp, mp + Vector2(0, -14), Color(0.75, 0.6, 0.1), 2.0)
		draw_rect(Rect2(mp + Vector2(0, -14), Vector2(9, 6)), Color(0.85, 0.7, 0.15))
	var me = m.commander(0)
	if me and not me.dead:
		var p := _to_screen(r, me.pos)
		var fwd := Vector2(sin(me.facing), cos(me.facing))
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([p + fwd * 11, p - fwd * 6 + side * 6, p - fwd * 6 - side * 6]), Color(0.9, 0.75, 0.2))
		draw_polyline(PackedVector2Array([p + fwd * 11, p - fwd * 6 + side * 6, p - fwd * 6 - side * 6, p + fwd * 11]), ink, 1.5)
	# Compass rose and scale.
	var cr := r.position + Vector2(r.size.x - 40, 44)
	draw_line(cr + Vector2(0, -22), cr + Vector2(0, 22), ink, 2.0)
	draw_line(cr + Vector2(-22, 0), cr + Vector2(22, 0), ink, 1.0)
	draw_string(font, cr + Vector2(-6, -26), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	var px100: float = 100.0 / m.map_size * r.size.x
	var sb := r.position + Vector2(24, r.size.y - 26)
	draw_line(sb, sb + Vector2(px100, 0), ink, 3.0)
	draw_string(font, sb + Vector2(0, -6), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	draw_string(font, r.position + Vector2(24, 30), "Field map — only what you and your scouts have seen", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
	draw_string(font, r.position + Vector2(24, r.size.y + 36), "M or Esc to put the map away", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.85, 0.75))
