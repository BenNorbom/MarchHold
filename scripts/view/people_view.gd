extends Node3D
## Nearby villagers use articulated rigs. Distant people, animals and props are batched.

const Rig = preload("res://scripts/view/villager_rig.gd")
const Anim = preload("res://scripts/sim/match_base.gd").Anim
const BattlePose = preload("res://scripts/view/battle_pose.gd")
const TICK: float = preload("res://scripts/data/defs.gd").TICK
const FLINCH := 0.32          # seconds
const FALL := 0.55
const SINK_AT := 14.0         # seconds after death

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
var crowd_meshes: Array[MultiMesh] = []
var horse_mm: MultiMesh
var deer_mm: MultiMesh
var vis := {}           # unit id -> [Vector3 pos, float facing, float phase]
var view_dist := 300.0
var counts := {}
var rigs := {}
var spare_rigs := [[], [], []]
var detail_radius: float
var detail_limit: int
var clock := 0.0
var flinches := {}            # unit id -> [when, direction, strength]
var died := {}                # unit id -> when the body started to fall
var refresh := 0.0


func setup(match_ref, mats, mesh_lib, quality: int) -> void:
	m = match_ref
	detail_radius = [18.0, 26.0, 34.0][quality]
	detail_limit = [4, 12, 20][quality]
	meshes = mesh_lib
	view_dist = [200.0, 300.0, 380.0][quality]
	body_mm = _make(meshes.person(), MAX_PEOPLE, true)
	var crowd_material: ShaderMaterial = mats.get_mat("person").duplicate()
	crowd_material.set_shader_parameter("painted_crowd", true)
	for mesh: ArrayMesh in [preload("res://assets/people/villager_crowd.res"), preload("res://assets/people/farmer_crowd.res"), preload("res://assets/people/child_crowd.res")]:
		crowd_meshes.append(_make(mesh, MAX_PEOPLE, true, crowd_material))
	for name in ITEMS:
		var cap := MAX_PEOPLE if name in ["bundle_wood", "wood_spear", "club", "bow", "axe", "wood_shield"] else 260
		if name in ["crown", "cloak"]:
			cap = 4
		item_mm[name] = _make(meshes.item(name), cap, name != "crown")
	horse_mm = _make(meshes.quadruped(false), MAX_ANIMALS, true)
	deer_mm = _make(meshes.quadruped(true), MAX_ANIMALS, true)


func _make(mesh: Mesh, cap: int, shadows: bool, material: Material = null) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if material:
		mi.material_override = material
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


func _carried_resource(u) -> String:
	if u.dead or u.mounted or u.carry <= 0.0:
		return ""
	if u.anim == Anim.CARRY or (u.phase == "haul" and u.anim in [Anim.IDLE, Anim.WALK]):
		return u.carry_res
	return u.carry_res if u.task == "idle" and u.anim == Anim.IDLE else ""


func _select_rigs(cam: Vector3, hidden: int) -> void:
	var candidates := []
	var center := Vector2(cam.x, cam.z)
	for u in m.units:
		if u.kind != "villager" or u.id == hidden or (u.dead and (u.dead_t < 0 or m.t - u.dead_t > 18)):
			continue
		var distance: float = center.distance_to(u.pos)
		if rigs.has(u.id):
			distance -= 2.0
		if distance < detail_radius:
			candidates.append([distance, u])
	candidates.sort_custom(func(a,b): return a[0] < b[0])
	var wanted := {}
	for i in mini(detail_limit,candidates.size()):
		var u = candidates[i][1]
		wanted[u.id] = u
	for id in rigs.keys():
		var rig: Rig = rigs[id]
		if wanted.has(id) and rig.model_index == Rig.model_for(wanted[id]):
			continue
		rig.hide()
		spare_rigs[rig.model_index].append(rig)
		rigs.erase(id)
	for id in wanted:
		if rigs.has(id):
			continue
		var u = wanted[id]
		var index := Rig.model_for(u)
		var rig: Rig
		if spare_rigs[index].is_empty():
			rig = Rig.new()
			add_child(rig)
			rig.setup(index)
		else:
			rig = spare_rigs[index].pop_back()
		rig.customize(fmod(id * 0.6180339, 1.0), m.fac(u.faction).color)
		rig.show()
		rigs[id] = rig


func _item(name: String, rig: Rig, xf: Transform3D, tint: Color, data: Color, pose: Dictionary = {}) -> void:
	if rig:
		xf = rig.item_pose(name)
		data.r = 13.0 # Final rigid prop transform, supplied by the bone pose.
	elif not pose.is_empty():
		xf = xf * BattlePose.prop(pose, name, BattlePose.crowd_hand(pose, not BattlePose.in_left_hand(name)))
		data.r = 13.0 # Likewise, from the fighting pose.
	_put(item_mm[name], xf, tint, data)


func on_hit(ev: Dictionary) -> void:
	var strength := 0.45 if ev["guard"] in ["block", "parry"] else 1.0
	flinches[ev["id"]] = [clock, ev["dir"], strength]


## Rotates the top of a body toward dir, about its feet.
func _tilt(dir: Vector2, angle: float) -> Basis:
	var axis := Vector3.UP.cross(Vector3(dir.x, 0, dir.y))
	if axis.length_squared() < 0.0001:
		return Basis()
	return Basis(axis.normalized(), angle)


func _falling(u, v: Array, t: float) -> Array:
	if not died.has(u.id):
		died[u.id] = clock - maxf(0.0, t - u.dead_t - TICK)
	var since: float = maxf(clock - died[u.id], t - u.dead_t - TICK)
	var k := clampf(since / FALL, 0.0, 1.0)
	var angle := PI * 0.5 * k * k
	if k >= 1.0 and since < FALL + 0.2:
		angle -= 0.09 * sin(PI * (since - FALL) / 0.2)     # settles
	var dir: Vector2 = u.hit_dir
	if dir.length_squared() < 0.01:
		dir = -Vector2(sin(v[1]), cos(v[1]))               # backwards
	var lift := lerpf(0.72 if u.mounted else 0.0, 0.15, k)
	if since > SINK_AT:
		lift -= 0.8 * clampf((since - SINK_AT) / 4.0, 0.0, 1.0)
	return [_tilt(dir, angle), lift, k, dir]


## What a fallen fighter was holding lies beside them.
func _dropped(name: String, pos: Vector3, dir: Vector2, side: float, tint: Color, seed_value: float) -> void:
	var at := pos + Vector3(-dir.y, 0, dir.x) * 0.6 * side + Vector3(dir.x, 0, dir.y) * 0.3
	at.y = m.terrain.height_at(at.x, at.z) + 0.05 + (pos.y - m.terrain.height_at(pos.x, pos.z) - 0.15)
	var flat := Basis(Vector3.UP, atan2(dir.x, dir.y) + 0.5 * side)
	var src: Vector3 = BattlePose.HAND_R
	if name.ends_with("spear") or name.ends_with("pike"):
		flat *= Basis(Vector3.RIGHT, PI * 0.5)
	elif name.ends_with("shield"):
		flat *= Basis(Vector3.BACK, PI * 0.5)
		src = BattlePose.HAND_L + Vector3(0.09, 0.28, 0.12)
	_put(item_mm[name], Transform3D(flat, at - flat * src), tint, Color(13, 0, 0, seed_value))


func update_frame(delta: float, alpha: float, cam: Vector3, hidden: int) -> void:
	counts.clear()
	refresh -= delta
	if refresh <= 0.0:
		_select_rigs(cam, hidden)
		refresh = 0.2
	var tr = m.terrain
	var t: float = m.t
	var now := t + alpha * TICK
	clock += delta
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
		v[1] = lerp_angle(v[1], u.facing, minf(1.0, delta * (16.0 if u.anim in [Anim.MELEE, Anim.SHOOT] else 9.0)))
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
		var lean_by := Basis()        # falling or flinching, about the feet
		var fall := []
		if u.dead:
			fall = _falling(u, v, t)
			lean_by = fall[0]
			xf2 = Transform3D(lean_by * basis.scaled(Vector3.ONE * sc2), pos + Vector3(0, fall[1], 0))
			custom = Color(0, 0, 0, seed)
		elif flinches.has(u.id):
			var fl: Array = flinches[u.id]
			var age: float = (clock - fl[0]) / FLINCH
			if age >= 1.0:
				flinches.erase(u.id)
			else:
				lean_by = _tilt(fl[1], 0.24 * float(fl[2]) * (1.0 - age) * (1.0 - age) * minf(1.0, 0.4 + age * 6.0))
				xf2.basis = lean_by * xf2.basis
		if u.mounted and not u.dead:
			var horse_anim := 2 if moved > 5.0 else (1 if moved > 0.4 else 0)
			_put(horse_mm, Transform3D(basis, pos), Color(0.32, 0.2, 0.11), Color(horse_anim, v[2], 1.0, seed))
			xf2 = Transform3D(lean_by * basis.scaled(Vector3.ONE * sc2), pos + Vector3(0, 0.72, 0))
			custom.r = 10
			if anim == 7:
				custom.r = 7
		var cargo := _carried_resource(u)
		var rig: Rig = rigs.get(u.id)
		var rig_anim := int(custom.r)
		var pose := {}
		if cargo == "":
			pose = BattlePose.sample(u, now)
			if not pose.is_empty():
				custom = BattlePose.encode(pose, seed)
		if rig:
			rig.battle = pose
			var size := 0.90 if u.child else (0.96 + seed * 0.08)
			rig.transform = Transform3D(xf2.basis.orthonormalized().scaled(Vector3(1.04-seed*0.08,1,1)*size),xf2.origin)
			rig.pose(rig_anim,v[2],moved,cargo,delta,rig.to_local(cam),u.dead)
			cargo = rig.cargo
		else:
			if cargo != "":
				custom.r = 14 if cargo == "wood" else (15 if cargo == "food" else 9)
			if u.kind == "villager":
				var crowd_tint := Color.WHITE.lerp(tunic, 0.16)
				_put(crowd_meshes[Rig.model_for(u)], xf2, crowd_tint, custom)
			else:
				_put(body_mm, xf2, tunic, custom)
		var tool := _tool_for(u) if not u.dead and cargo == "" else ""
		var weapon: String = u.weapon
		# Dropped once the body is most of the way down.
		var held: bool = fall.is_empty() or fall[2] < 0.6
		if not held:
			if weapon != "":
				_dropped(weapon, xf2.origin, fall[3], 1.0, tunic, seed)
			if u.shield != "":
				_dropped(u.shield, xf2.origin, fall[3], -1.0, tunic, seed)
		elif tool != "":
			_item(tool, rig, xf2, tunic, custom)
		elif weapon != "" and cargo == "" and anim != Anim.SHOOT:
			_item(weapon, rig, xf2, tunic, custom, pose)
		if held and cargo == "":
			if (u.bow and (weapon == "" or anim == 8) and tool == "") or (anim == 8 and not u.bow):
				_item("bow", rig, xf2, tunic, custom, pose)
			if u.shield != "" and anim != 8 and tool == "":
				_item(u.shield, rig, xf2, tunic, custom, pose)
		if u.armor != "":
			_item(u.armor, rig, xf2, tunic, custom)
			_item("bronze_helmet" if u.armor.begins_with("bronze") else "iron_helmet", rig, xf2, tunic, custom)
		if u.kind == "commander":
			_item("crown", rig, xf2, tunic, custom)
			_item("cloak", rig, xf2, f.color.lightened(0.15) if f else tunic, custom)
		if cargo != "":
			var bundle := "bundle_wood" if cargo == "wood" else ("bundle_food" if cargo == "food" else "bundle_stone")
			var bcol := Color(0.55, 0.53, 0.5) if cargo == "stone" else (Color(0.2, 0.2, 0.22) if cargo == "coal" else (Color(0.5, 0.36, 0.28) if cargo.ends_with("ore") else tunic))
			_item(bundle, rig, xf2, bcol, custom)
	for mm in crowd_meshes:
		mm.visible_instance_count = counts.get(mm, 0)
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
		for id in died.keys():
			if m.unit(id) == null:
				died.erase(id)
		for id in flinches.keys():
			if clock - float(flinches[id][0]) >= FLINCH:
				flinches.erase(id)


func _animal_color(u, seed: float) -> Color:
	if u.kind == "deer":
		return Color(0.5, 0.33, 0.2).lerp(Color(0.42, 0.3, 0.2), seed)
	var coats := [Color(0.33, 0.2, 0.11), Color(0.45, 0.25, 0.12), Color(0.12, 0.1, 0.09), Color(0.62, 0.6, 0.56), Color(0.52, 0.38, 0.22)]
	return coats[u.id % coats.size()]
