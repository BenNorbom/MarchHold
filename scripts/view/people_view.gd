extends Node3D
## Draws every person and animal with a handful of MultiMeshes. Limbs are
## animated in the vertex shader (shaders/person.gdshader).

const Defs = preload("res://scripts/data/defs.gd")

const MAX_PEOPLE := 560
const MAX_ANIMALS := 260
const ITEMS := ["club", "wood_spear", "bronze_spear", "iron_spear", "bronze_sword", "iron_sword", "bronze_pike", "iron_pike",
	"bronze_lance", "iron_lance", "bow", "axe", "hammer", "pick", "hoe", "basket", "bundle_wood", "bundle_stone",
	"bundle_food", "wood_shield", "bronze_shield", "iron_shield", "bronze_helmet", "iron_helmet", "bronze_armor",
	"iron_armor", "crown", "cloak"]
const AABB_ALL := AABB(Vector3(-60, -60, -60), Vector3(1150, 320, 1150))

var m
var meshes
var body_mm: MultiMesh
var item_mm := {}
var horse_mm: MultiMesh
var deer_mm: MultiMesh
var vis := {}           # unit id -> [Vector3 pos, float facing, float phase]
var view_dist := 300.0
var counts := {}


func setup(match_ref, mats, mesh_lib, quality: int) -> void:
	m = match_ref
	meshes = mesh_lib
	view_dist = [200.0, 300.0, 380.0][quality]
	body_mm = _make(meshes.person(), MAX_PEOPLE, true)
	for name in ITEMS:
		var cap := MAX_PEOPLE if name in ["bundle_wood", "wood_spear", "club", "bow", "axe", "wood_shield"] else 260
		if name in ["crown", "cloak"]:
			cap = 4
		item_mm[name] = _make(meshes.item(name), cap, name != "crown")
	horse_mm = _make(meshes.quadruped(false), MAX_ANIMALS, true)
	deer_mm = _make(meshes.quadruped(true), MAX_ANIMALS, true)


func _make(mesh: Mesh, cap: int, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB_ALL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


func _put(mm: MultiMesh, xf: Transform3D, col: Color, custom: Color) -> void:
	var i: int = counts.get(mm, 0)
	if i >= mm.instance_count:
		return
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, col)
	mm.set_instance_custom_data(i, custom)
	counts[mm] = i + 1


static func anim_rate(anim: int) -> float:
	match anim:
		1, 9:
			return 9.5
		2:
			return 14.0
		3:
			return 4.2
		4:
			return 6.5
		5:
			return 4.8
		6:
			return 2.5
		7:
			return 6.2
		8:
			return 1.5
		10:
			return 11.0
		12:
			return 5.0
	return 1.4


func _tool_for(u) -> String:
	match u.anim:
		3:
			return "axe"
		4:
			return "hammer"
		5:
			var b = m.bld(u.tgt_bld)
			return "hoe" if b and b.type == "farm" else "pick"
		6:
			return "basket"
		12:
			return "hammer"
	return ""


func update_frame(delta: float, alpha: float, cam: Vector3, hidden: int) -> void:
	counts.clear()
	var tr = m.terrain
	var t: float = m.t
	var seen := {}
	var vd2 := view_dist * view_dist
	for u in m.units:
		var person: bool = u.kind == "villager" or u.kind == "commander"
		var animal: bool = u.kind == "horse" or u.kind == "deer"
		if not person and not animal:
			continue
		if u.id == hidden:
			continue
		if u.dead and (u.dead_t < 0.0 or t - u.dead_t > 18.0):
			continue
		var p2: Vector2 = u.prev.lerp(u.pos, alpha)
		var pos := Vector3(p2.x, tr.height_at(p2.x, p2.y), p2.y)
		if pos.distance_squared_to(cam) > vd2:
			continue
		seen[u.id] = true
		var v: Array = vis.get(u.id, [pos, u.facing, randf() * TAU])
		var moved: float = (pos - v[0]).length() / maxf(delta, 0.001)
		v[1] = lerp_angle(v[1], u.facing, minf(1.0, delta * 9.0))
		var anim: int = u.anim
		if u.dead:
			anim = 0
		v[2] = fmod(v[2] + delta * anim_rate(anim) * (clampf(moved / 4.0, 0.4, 1.6) if anim in [1, 2, 9, 10] else 1.0), TAU * 100.0)
		v[0] = pos
		vis[u.id] = v
		var seed := fmod(float(u.id) * 0.6180339, 1.0)
		var basis := Basis(Vector3.UP, v[1])
		if animal:
			var col := _animal_color(u, seed)
			var sc := 0.72 if u.child else 1.0
			var a_anim := 6 if anim == 6 else (2 if anim == 2 else (1 if anim == 1 else 0))
			var xf := Transform3D(basis.scaled(Vector3.ONE * sc), pos)
			if u.dead:
				xf = Transform3D(basis * Basis(Vector3.FORWARD, PI * 0.5), pos + Vector3(0, 0.45, 0))
			_put(horse_mm if u.kind == "horse" else deer_mm, xf, col, Color(a_anim, v[2], 1.0, seed))
			continue
		# People.
		var f = m.fac(u.faction)
		var tunic: Color = f.color.darkened(0.15).lerp(Color(0.36, 0.3, 0.22), 0.08 + 0.22 * fmod(seed * 7.3, 1.0)) if f else Color(0.5, 0.45, 0.35)
		var sc2 := 0.66 if u.child else (1.06 if u.kind == "commander" else 1.0)
		var xf2 := Transform3D(basis.scaled(Vector3.ONE * sc2), pos)
		var custom := Color(anim, v[2], clampf(moved / 4.0, 0.0, 1.5), seed)
		if u.dead:
			xf2 = Transform3D(basis * Basis(Vector3.RIGHT, -PI * 0.5), pos + Vector3(0, 0.15, 0))
			custom = Color(0, 0, 0, seed)
		if u.mounted and not u.dead:
			var horse_anim := 2 if moved > 5.0 else (1 if moved > 0.4 else 0)
			_put(horse_mm, Transform3D(basis, pos), Color(0.32, 0.2, 0.11), Color(horse_anim, v[2], 1.0, seed))
			xf2 = Transform3D(basis.scaled(Vector3.ONE * sc2), pos + Vector3(0, 0.72, 0))
			custom.r = 10
			if anim == 7:
				custom.r = 7
		_put(body_mm, xf2, tunic, custom)
		var tool := _tool_for(u)
		var weapon: String = u.weapon
		if tool != "":
			_put(item_mm[tool], xf2, tunic, custom)
		elif weapon != "":
			_put(item_mm[weapon], xf2, tunic, custom)
		if u.bow and (weapon == "" or anim == 8) and tool == "":
			_put(item_mm["bow"], xf2, tunic, custom)
		elif anim == 8 and not u.bow:
			_put(item_mm["bow"], xf2, tunic, custom)
		if u.shield != "" and anim != 8 and tool == "":
			_put(item_mm[u.shield], xf2, tunic, custom)
		if u.armor != "":
			_put(item_mm[u.armor], xf2, tunic, custom)
			_put(item_mm["bronze_helmet" if u.armor.begins_with("bronze") else "iron_helmet"], xf2, tunic, custom)
		if u.kind == "commander":
			_put(item_mm["crown"], xf2, tunic, custom)
			_put(item_mm["cloak"], xf2, f.color.lightened(0.15) if f else tunic, custom)
		if u.carry > 0.0:
			var bundle := "bundle_wood" if u.carry_res == "wood" else ("bundle_food" if u.carry_res == "food" else "bundle_stone")
			var bcol := Color(0.55, 0.53, 0.5) if u.carry_res == "stone" else (Color(0.2, 0.2, 0.22) if u.carry_res == "coal" else (Color(0.5, 0.36, 0.28) if u.carry_res.ends_with("ore") else tunic))
			_put(item_mm[bundle], xf2, bcol, custom)
	body_mm.visible_instance_count = counts.get(body_mm, 0)
	for name in item_mm:
		var mm: MultiMesh = item_mm[name]
		mm.visible_instance_count = counts.get(mm, 0)
	horse_mm.visible_instance_count = counts.get(horse_mm, 0)
	deer_mm.visible_instance_count = counts.get(deer_mm, 0)
	if Engine.get_process_frames() % 120 == 0:
		for id in vis.keys():
			if not seen.has(id):
				vis.erase(id)


func _animal_color(u, seed: float) -> Color:
	if u.kind == "deer":
		return Color(0.5, 0.33, 0.2).lerp(Color(0.42, 0.3, 0.2), seed)
	var coats := [Color(0.33, 0.2, 0.11), Color(0.45, 0.25, 0.12), Color(0.12, 0.1, 0.09), Color(0.62, 0.6, 0.56), Color(0.52, 0.38, 0.22)]
	return coats[u.id % coats.size()]
