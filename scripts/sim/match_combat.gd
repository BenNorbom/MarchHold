extends "res://scripts/sim/match_work.gd"
## Combat, projectiles, siege engines, animals, vision, intelligence and alarms.

const WOOD_TYPES := ["hut", "stockpile", "lodge", "farm", "armory", "palisade", "palisade_gate", "watch_post", "stable"]
const STONE_TYPES := ["stone_wall", "stone_gate", "tower"]

var vision_t := 0.0


# --- Fighting -----------------------------------------------------------------

func armed(u: Unit) -> bool:
	return u.weapon != "" or (u.bow and u.arrows > 0) or u.kind == "commander"


func weapon_def(u: Unit) -> Dictionary:
	return Defs.ITEMS[u.weapon] if u.weapon != "" else Defs.FISTS


func describe_person(u: Unit) -> String:
	if u.kind == "commander":
		return "commander"
	if u.kind in ["cannon", "ram"]:
		return u.kind
	if u.mounted:
		return "rider"
	if u.weapon.ends_with("pike"):
		return "pikeman"
	if u.weapon.ends_with("spear"):
		return "spearman"
	if u.weapon.ends_with("sword"):
		return "swordsman"
	if u.weapon == "club":
		return "clubman"
	if u.bow:
		return "archer"
	return "villager"


## Returns true when the unit spent this tick fighting or fleeing.
func combat_update(u: Unit, dt: float, radius: float) -> bool:
	u.cooldown = maxf(0.0, u.cooldown - dt)
	if u.child or u.siege >= 0:
		return _maybe_flee(u, dt, 10.0)
	if u.flee_t > 0.0:
		u.flee_t -= dt
		var home := resting_place(u)
		move_to(u, home + _ring(u, 6.0), dt, 3.0, true)
		return true
	if not armed(u):
		return _maybe_flee(u, dt, 12.0)
	# Badly hurt soldiers fall back to heal.
	if u.kind == "villager" and u.hp < u.max_hp * 0.25 and t - u.hit_t < 4.0:
		u.flee_t = 10.0
		return true
	var foe := unit(u.enemy)
	if foe == null or foe.dead or foe.pos.distance_to(u.pos) > radius + 8.0 or foe.stable >= 0:
		foe = nearest_enemy(u.pos, radius, u.faction)
		u.enemy = foe.id if foe else -1
	if foe == null:
		var b := bld(u.enemy_bld)
		if b and not b.dead:
			_attack_building(u, b, dt)
			return true
		return false
	_fight(u, foe, dt)
	return true


func _maybe_flee(u: Unit, dt: float, r: float) -> bool:
	if u.flee_t > 0.0:
		u.flee_t -= dt
		move_to(u, resting_place(u) + _ring(u, 5.0), dt, 3.0, true)
		return true
	var foe := nearest_enemy(u.pos, r, u.faction, func(o): return armed(o))
	if foe:
		u.flee_t = 6.0
		u.carry = 0.0
		return true
	return false


func _fight(u: Unit, foe: Unit, dt: float) -> void:
	var d := u.pos.distance_to(foe.pos)
	var bow_range := Defs.TOWER_BOW_RANGE if u.in_tower >= 0 else Defs.BOW_RANGE
	if u.bow and u.arrows > 0 and (u.weapon == "" or d > 6.0) and d <= bow_range:
		face(u, foe.pos)
		u.anim = Anim.SHOOT
		if u.cooldown <= 0.0:
			u.cooldown = 2.0
			u.arrows -= 1
			fire_arrow(u, foe, armory_tier(u.faction))
		return
	if u.bow and u.arrows <= 0 and u.weapon == "":
		# Out of arrows: go and refill at the armory.
		var arm := nearest_building(u.faction, u.pos, ["armory"])
		if arm and go_to_building(u, arm, dt, 1.4, true):
			refill_quiver(u, fac(u.faction))
		return
	var w := weapon_def(u)
	var reach: float = w["reach"] + 0.5 + (0.6 if foe.mounted else 0.0) + (1.2 if foe.kind in ["cannon", "ram"] else 0.0)
	if d > reach:
		if u.mounted and u.charge_start == Vector2.ZERO:
			u.charge_start = u.pos
		move_to(u, foe.pos, dt, reach * 0.8, true)
		return
	face(u, foe.pos)
	u.anim = Anim.MELEE
	if u.cooldown <= 0.0:
		u.cooldown = float(w["rate"])
		deal_damage(foe, melee_damage(u, foe), u, "melee")
		sound("clash" if foe.weapon != "" or foe.shield != "" else "hit", foe.pos)


func melee_damage(att: Unit, tgt: Unit) -> float:
	var w := weapon_def(att)
	var dmg: float = w["dmg"]
	if tgt.mounted:
		dmg *= float(w.get("vs_mounted", 1.0))
	elif w.has("close"):
		dmg *= float(w["close"])
	if att.mounted:
		if tgt.bow and tgt.weapon == "":
			dmg *= 1.5
		elif tgt.shield == "" and not (tgt.weapon.ends_with("pike") or tgt.weapon.ends_with("spear")):
			dmg *= 1.2
		if w.has("charge") and att.charge_start != Vector2.ZERO and att.charge_start.distance_to(att.pos) > 10.0:
			dmg *= float(w["charge"])
		att.charge_start = Vector2.ZERO
	if att.kind == "commander":
		dmg *= 1.25
	if tgt.kind in ["cannon", "ram"]:
		return dmg * 0.8
	if tgt.shield != "":
		dmg *= 1.0 - float(Defs.ITEMS[tgt.shield]["block_melee"])
	if tgt.armor != "":
		dmg *= 1.0 - float(Defs.ITEMS[tgt.armor]["armor"])
	return dmg


func deal_damage(tgt: Unit, dmg: float, att: Unit, kind: String) -> void:
	if tgt.dead or dmg <= 0.0:
		return
	tgt.hp -= dmg
	tgt.hit_t = t
	if att:
		tgt.attacker = att.id
		if tgt.enemy < 0 and armed(tgt) and att.faction != tgt.faction:
			tgt.enemy = att.id
	emit({"type": "hit", "id": tgt.id, "pos": tgt.pos, "kind": kind})
	if tgt.faction >= 0 and att and att.faction != tgt.faction and is_person(tgt):
		var f := fac(tgt.faction)
		if t - f.attack_msg_t > 25.0 and tgt.kind != "commander":
			f.attack_msg_t = t
			var where := _place_name(tgt.faction, tgt.pos)
			if tgt.faction == 0:
				post(0, "%s is under attack %s!" % [tgt.name, where], "alarm")
				sound("horn", tgt.pos, 0)
			_note_units(f, att.pos, [att], t)
	if tgt.hp <= 0.0:
		if att and att.faction >= 0:
			fac(att.faction).kills += 1
		if tgt.kind == "deer":
			tgt.dead = true
			tgt.dead_t = t
			emit({"type": "death", "id": tgt.id, "kind": "deer", "pos": tgt.pos, "faction": -1})
			add_carcass(tgt.pos, 40.0)
			return
		kill_unit(tgt, kind)


func _place_name(faction: int, p: Vector2) -> String:
	var home := home_pos(faction)
	var d := p.distance_to(home)
	if d < 40.0:
		return "at home"
	return "%d m %s of home" % [int(round(d / 10.0) * 10.0), Terrain.compass_name(p - home)]


func _attack_building(u: Unit, b: Building, dt: float) -> void:
	var reach: float = weapon_def(u)["reach"] + 0.6
	if u.bow and u.weapon == "":
		# Arrows don't hurt buildings; archers hang back.
		u.enemy_bld = -1
		return
	if dist_to_building(u.pos, b) > reach + 0.8:
		move_to(u, approach_point(u, b, reach * 0.6), dt, 0.6, true)
		return
	face(u, b.pos)
	u.anim = Anim.MELEE
	if u.cooldown <= 0.0:
		var w := weapon_def(u)
		u.cooldown = float(w["rate"])
		damage_building(b, float(w["dmg"]) * _material(b.type), u)
		sound("chop" if b.type in WOOD_TYPES else "pick", b.pos)


func _material(type: String) -> float:
	if type in WOOD_TYPES:
		return 0.35
	if type in STONE_TYPES:
		return 0.04
	if type == "campfire":
		return 0.3
	return 0.12


func damage_building(b: Building, dmg: float, att: Unit) -> void:
	if b.dead:
		return
	b.hp -= dmg
	emit({"type": "building_hit", "id": b.id})
	var f := fac(b.faction)
	if att and t - b.alarm_t > 20.0:
		b.alarm_t = t
		if b.faction == 0:
			post(0, "The %s is under attack %s!" % [Defs.building_name(b.type).to_lower(), _place_name(0, b.pos)], "alarm")
			sound("bell", b.pos, 0)
		_note_units(f, att.pos, [att], t)
	if b.hp <= 0.0:
		if b.faction == 0:
			post(0, "The %s was destroyed." % Defs.building_name(b.type).to_lower(), "death")
		elif att and att.faction == 0:
			post(0, "The enemy %s is destroyed." % Defs.building_name(b.type).to_lower(), "done")
		sound("collapse", b.pos)
		remove_building(b, "destroyed")
		_refresh_counts(f)


# --- Projectiles ------------------------------------------------------------------

func _height(p: Vector2) -> float:
	return terrain.height_at(p.x, p.y)


func fire_arrow(shooter: Unit, target: Unit, tier: int) -> void:
	var d := shooter.pos.distance_to(target.pos)
	var s := Shot.new()
	s.kind = "arrow"
	s.faction = shooter.faction
	s.shooter = shooter.id
	s.start = Vector3(shooter.pos.x, _height(shooter.pos) + (5.5 if shooter.in_tower >= 0 else 1.5), shooter.pos.y)
	var chance := clampf(1.05 - d / 75.0, 0.3, 0.95)
	if target.kind == "deer":
		chance = 0.85
	s.hits = rng.randf() < chance
	var aim := target.pos + (target.pos - target.prev) * 6.0 * (d / 40.0)
	if not s.hits:
		aim += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 4.0)
	s.end = Vector3(aim.x, _height(aim) + (1.1 if s.hits else 0.0), aim.y)
	s.dur = clampf(d / 38.0, 0.25, 2.0)
	s.target = target.id
	s.dmg = Defs.ARROW_DMG[clampi(tier, 0, 2)]
	shots.append(s)
	sound("bow", shooter.pos)


func fire_ball(e: Unit, aim: Vector2, at_bld: int) -> void:
	var d := e.pos.distance_to(aim)
	var spread := float(Defs.CANNON["scatter"]) * d
	var miss := Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread))
	var p := aim + miss
	var s := Shot.new()
	s.kind = "ball"
	s.faction = e.faction
	s.shooter = e.id
	s.start = Vector3(e.pos.x, _height(e.pos) + 1.0, e.pos.y)
	s.end = Vector3(p.x, _height(p) + 0.5, p.y)
	s.dur = clampf(d / 120.0, 0.35, 1.6)
	s.target_bld = at_bld
	shots.append(s)
	sound("cannon", e.pos)
	emit({"type": "fx", "name": "muzzle", "pos": e.pos, "dir": aim - e.pos})


## Physically simulated shot (the player's bow).
func fire_free_arrow(shooter: Unit, origin: Vector3, vel: Vector3, tier: int) -> void:
	var s := Shot.new()
	s.kind = "arrow"
	s.free = true
	s.faction = shooter.faction
	s.shooter = shooter.id
	s.pos = origin
	s.start = origin
	s.vel = vel
	s.dmg = Defs.ARROW_DMG[clampi(tier, 0, 2)] * 1.2
	shots.append(s)
	sound("bow", shooter.pos)


func update_shots(dt: float) -> void:
	for s: Shot in shots:
		if s.dead:
			continue
		s.t += dt
		if s.free:
			_free_shot(s, dt)
			continue
		var k := clampf(s.t / s.dur, 0.0, 1.0)
		var flat := s.start.lerp(s.end, k)
		var arc := (4.0 * k * (1.0 - k)) * (s.start.distance_to(s.end) * (0.12 if s.kind == "arrow" else 0.05))
		s.pos = flat + Vector3(0, arc, 0)
		if k >= 1.0:
			s.dead = true
			if s.kind == "arrow":
				var tgt := unit(s.target)
				if s.hits and tgt and not tgt.dead:
					var dmg := s.dmg
					if tgt.shield != "":
						dmg *= 1.0 - float(Defs.ITEMS[tgt.shield]["block_arrow"])
					if tgt.armor != "":
						dmg *= 1.0 - float(Defs.ITEMS[tgt.armor]["armor"])
					if tgt.in_tower >= 0:
						dmg *= 0.5
					deal_damage(tgt, dmg, unit(s.shooter), "arrow")
				emit({"type": "fx", "name": "arrow_land", "pos": Vector2(s.end.x, s.end.z), "hit": s.hits})
			else:
				_ball_impact(s)
	shots = shots.filter(func(s): return not s.dead)


func _free_shot(s: Shot, dt: float) -> void:
	var old := s.pos
	s.vel.y -= 9.8 * dt
	s.pos += s.vel * dt
	var p2 := Vector2(s.pos.x, s.pos.z)
	var shooter := unit(s.shooter)
	for u: Unit in units_near(p2, 3.0, -2):
		if u.faction == s.faction or u.id == s.shooter or u.dead or u.stable >= 0:
			continue
		var top := _height(u.pos) + (2.6 if u.mounted else 1.85)
		var seg_closest := Geometry3D.get_closest_point_to_segment(Vector3(u.pos.x, s.pos.y, u.pos.y), old, s.pos)
		var hd := Vector2(seg_closest.x, seg_closest.z).distance_to(u.pos)
		if hd < (0.9 if u.mounted else 0.55) and seg_closest.y > _height(u.pos) and seg_closest.y < top:
			var dmg := s.dmg
			if u.shield != "":
				dmg *= 1.0 - float(Defs.ITEMS[u.shield]["block_arrow"]) * 0.7
			if u.armor != "":
				dmg *= 1.0 - float(Defs.ITEMS[u.armor]["armor"])
			deal_damage(u, dmg, shooter, "arrow")
			s.dead = true
			emit({"type": "fx", "name": "arrow_land", "pos": u.pos, "hit": true})
			return
	if s.pos.y < _height(p2) or s.t > 6.0 or not terrain.in_bounds(p2, 1.0):
		s.dead = true
		emit({"type": "fx", "name": "arrow_land", "pos": p2, "hit": false})


func _ball_impact(s: Shot) -> void:
	var p := Vector2(s.end.x, s.end.z)
	var e := unit(s.shooter)
	emit({"type": "fx", "name": "impact", "pos": p})
	sound("impact", p)
	for b: Building in buildings:
		if b.dead or b.faction == s.faction or b.pos.distance_to(p) > b.size.length() * 0.5 + 2.0:
			continue
		var local := (p - b.pos).rotated(-b.rot)
		if absf(local.x) <= b.size.x * 0.5 + 1.5 and absf(local.y) <= b.size.y * 0.5 + 1.5:
			damage_building(b, Defs.CANNON["dmg_building"], e)
	for u: Unit in units_near(p, Defs.CANNON["splash"], -2):
		if u.faction == s.faction or u.stable >= 0:
			continue
		var fall := 1.0 - u.pos.distance_to(p) / float(Defs.CANNON["splash"])
		var dmg: float = Defs.CANNON["dmg_unit"] * clampf(fall, 0.2, 1.0)
		if u.armor != "":
			dmg *= 1.0 - float(Defs.ITEMS[u.armor]["armor"]) * 0.5
		deal_damage(u, dmg, e, "ball")


# --- Siege engines ----------------------------------------------------------------

func update_engine(e: Unit, dt: float) -> void:
	e.reload = maxf(0.0, e.reload - dt)
	var crew_units := []
	for id in e.crew_ids.duplicate():
		var m := unit(id)
		if m == null or m.dead or m.siege != e.id:
			e.crew_ids.erase(id)
		else:
			crew_units.append(m)
	var need := int(Defs.ITEMS[e.kind]["crew"])
	if crew_units.is_empty():
		e.anim = Anim.IDLE
		return
	var f := fac(e.faction)
	# Load shot near the armory.
	if e.kind == "cannon" and e.ammo < Defs.SHOT_LOAD:
		var arm := nearest_building(e.faction, e.pos, ["armory"])
		if arm and arm.pos.distance_to(e.pos) < 30.0:
			var take := mini(Defs.SHOT_LOAD - e.ammo, int(f.gear.get("shot", 0)))
			if take > 0:
				e.ammo += take
				f.gear["shot"] = int(f.gear["shot"]) - take
	var c := crew_of(crew_units[0])
	var s: Dictionary = c.steps[c.idx] if c and c.idx < c.steps.size() else {}
	var a: String = s.get("action", "hold")
	var goal: Vector2 = e.pos
	if a == "attack" or a == "guard":
		goal = c.state.get("target", e.pos)
	elif a == "follow":
		var cmd := unit(f.commander)
		if cmd:
			goal = cmd.pos
	elif a == "recall":
		goal = home_pos(e.faction)
	# Pick something to shoot or ram.
	var rng_max: float = Defs.CANNON["range"] if e.kind == "cannon" else 3.0
	var tb := _engine_target_building(e, goal, rng_max)
	var crewed := crew_units.size() >= need
	var speed_scale := 1.0 if crewed else 0.35
	var base_speed: float
	if e.kind == "cannon":
		base_speed = Defs.CANNON["speed_team"] if e.team else Defs.CANNON["speed_hand"]
	else:
		base_speed = Defs.RAM["speed_team"] if e.team else Defs.RAM["speed"]
	if e.kind == "cannon":
		var aim_unit: Unit = null
		if tb == null:
			aim_unit = _cluster_target(e, rng_max)
		var in_range := (tb != null and tb.pos.distance_to(e.pos) <= rng_max) or aim_unit != null
		if in_range and crewed:
			var aim: Vector2 = tb.pos if tb else aim_unit.pos
			face(e, aim)
			e.anim = Anim.LOAD if e.reload > 0.0 else Anim.IDLE
			if e.reload <= 0.0 and e.ammo > 0:
				e.ammo -= 1
				e.reload = Defs.CANNON["reload"]
				fire_ball(e, aim, tb.id if tb else -1)
			elif e.ammo <= 0 and e.faction == 0 and t - e.hit_t > 30.0:
				e.hit_t = t
				post(0, "A cannon is out of shot. Make more at the armory (/c shot).", "warn")
			return
		var stop := 0.0 if a in ["follow", "recall"] else (rng_max * 0.75 if tb else 4.0)
		_engine_move(e, goal, dt, base_speed * speed_scale, stop + 2.0)
	else:
		if tb and tb.pos.distance_to(e.pos) < tb.size.length() * 0.5 + 3.5:
			face(e, tb.pos)
			if e.reload <= 0.0 and crewed:
				e.reload = Defs.RAM["reload"]
				damage_building(tb, Defs.RAM["dmg_building"], e)
				sound("ram", e.pos)
			return
		var dest := tb.pos if tb else goal
		_engine_move(e, dest, dt, base_speed * speed_scale, (tb.size.length() * 0.5 + 2.5) if tb else 4.0)


func _engine_move(e: Unit, goal: Vector2, dt: float, speed: float, arrive: float) -> void:
	if e.pos.distance_to(goal) <= arrive:
		e.anim = Anim.IDLE
		return
	if e.path.is_empty() or e.path_goal.distance_squared_to(goal) > 9.0:
		e.path = find_path(e.faction, e.pos, goal)
		e.path_i = 0
		e.path_goal = goal
		if e.path.is_empty():
			e.path_goal = Vector2(-999, -999)
			return
	var wp: Vector2 = e.path[mini(e.path_i, e.path.size() - 1)]
	var to := wp - e.pos
	var dist := to.length()
	if dist > 0.01:
		e.facing = lerp_angle(e.facing, atan2(to.x, to.y), minf(1.0, dt * 2.0))
	var step := speed * dt
	if dist <= step:
		e.pos = wp
		e.path_i += 1
		if e.path_i >= e.path.size():
			e.path = PackedVector2Array()
	else:
		e.pos += to / dist * step
	e.anim = Anim.WALK


func _engine_target_building(e: Unit, goal: Vector2, rng_max: float) -> Building:
	var best: Building = null
	var bd := INF
	for b: Building in buildings:
		if b.dead or b.faction == e.faction or b.faction < 0:
			continue
		var de := b.pos.distance_to(e.pos)
		var dg := b.pos.distance_to(goal)
		if de > rng_max + 60.0 and dg > 70.0:
			continue
		# Walls and gates first, then towers, then the rest.
		var pri := 0.0 if Defs.BUILDINGS[b.type].get("wall", false) else (20.0 if b.type == "tower" else 45.0)
		var score := de + pri
		if score < bd:
			bd = score
			best = b
	return best


func _cluster_target(e: Unit, rng_max: float) -> Unit:
	var best: Unit = null
	var best_n := 2
	for u: Unit in units_near(e.pos, rng_max, -3, e.faction):
		if u.stable >= 0:
			continue
		var n := units_near(u.pos, 6.0, u.faction).size()
		if n > best_n:
			best_n = n
			best = u
	return best


func _crew_engine(u: Unit, dt: float) -> void:
	var e := unit(u.siege)
	if e == null or e.dead:
		u.siege = -1
		return
	var spot := e.pos + Vector2(sin(e.facing), cos(e.facing)) * -2.2 + Vector2(cos(e.facing), -sin(e.facing)) * (float(e.crew_ids.find(u.id)) - 1.0) * 1.3
	if not move_to(u, spot, dt, 0.6):
		return
	u.facing = e.facing
	u.anim = Anim.LOAD if e.reload > 0.0 and e.kind == "cannon" else Anim.IDLE


# --- Military steps ---------------------------------------------------------------

func _do_military(u: Unit, c: Crew, s: Dictionary, dt: float) -> void:
	if u.siege >= 0:
		_crew_engine(u, dt)
		return
	var f := fac(u.faction)
	var a: String = s["action"]
	var target: Vector2 = c.state.get("target", u.pos)
	match a:
		"follow":
			var cmd := unit(f.commander)
			if cmd == null or cmd.dead:
				_do_idle(u, dt)
				return
			var dir := Vector2(sin(cmd.facing), cos(cmd.facing))
			var spot := slot_point(u, cmd.pos - dir * 5.0, dir)
			if u.pos.distance_to(spot) > 1.5:
				move_to(u, spot, dt, 1.0, u.pos.distance_to(spot) > 10.0)
			else:
				u.anim = Anim.IDLE
				u.facing = cmd.facing
		"guard", "hold":
			var home := home_pos(u.faction)
			var dir := (target - home) if target.distance_to(home) > 5.0 else Vector2(0, -1)
			var spot := slot_point(u, target, dir)
			if u.bow:
				var tw := nearest_building(u.faction, spot, ["tower"])
				if tw and tw.pos.distance_to(spot) < 12.0:
					spot = tw.pos + _ring(u, 1.2)
			if u.pos.distance_to(spot) > 1.2:
				move_to(u, spot, dt, 0.8)
			else:
				u.anim = Anim.IDLE
				face(u, spot + dir * 10.0)
			var tw2 := nearest_building(u.faction, u.pos, ["tower"])
			u.in_tower = tw2.id if (tw2 and u.bow and tw2.pos.distance_to(u.pos) < 3.5) else -1
		"attack":
			var center := crew_center(c)
			var dir := target - center
			if center.distance_to(target) < 30.0:
				if u.enemy_bld < 0:
					var b := _nearest_enemy_building(u.faction, target, 70.0)
					if b:
						u.enemy_bld = b.id
					else:
						u.anim = Anim.IDLE
				return
			var lead := target + (center - target).normalized() * maxf(0.0, center.distance_to(target) - 25.0)
			var spot := slot_point(u, center + dir.normalized() * 8.0, dir)
			if center.distance_to(target) < 60.0:
				spot = slot_point(u, lead, dir)
			move_to(u, spot, dt, 1.0)


func _nearest_enemy_building(faction: int, p: Vector2, r: float) -> Building:
	var best: Building = null
	var bd := r * r
	for b: Building in buildings:
		if b.dead or b.faction == faction or b.faction < 0:
			continue
		var d := b.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


func check_morale() -> void:
	for c: Crew in crews.values():
		if c.idx >= c.steps.size():
			continue
		var a: String = c.steps[c.idx]["action"]
		if a != "attack" or c.start_size < 4:
			continue
		if c.lost * 2 >= c.start_size and c.members.size() > 0:
			if c.faction == 0:
				post(0, "%s lost half its people and is falling back!" % crew_label(c), "alarm")
			c.steps = [{"action": "recall", "subject": "", "count": 0, "amount": 0, "where": "home"}]
			c.idx = 0
			c.lost = 0
			_begin_step(c)


func soldier_radius(u: Unit, c: Crew) -> float:
	if c == null or c.idx >= c.steps.size():
		return 14.0 if armed(u) else 0.0
	match c.steps[c.idx]["action"]:
		"attack":
			return 28.0
		"guard":
			return 30.0
		"follow":
			return 18.0
		"hold":
			return weapon_def(u)["reach"] + 8.0 if not u.bow else Defs.BOW_RANGE
		"scout":
			return 0.0
	return 12.0


# --- Animals ------------------------------------------------------------------------

func update_animal(a: Unit, dt: float) -> void:
	if a.kind == "horse" and a.driver >= 0:
		var dr := unit(a.driver)
		if dr == null or dr.dead or dr.tgt_unit != a.id:
			a.driver = -1
		else:
			var behind := dr.pos - Vector2(sin(dr.facing), cos(dr.facing)) * 3.0
			_animal_move(a, behind, dt, dr.pos.distance_to(a.pos) > 6.0)
			return
	if a.stable >= 0:
		var st := bld(a.stable)
		if st == null or st.dead:
			a.stable = -1
			a.faction = -1
			return
		if a.pos.distance_to(st.pos) > st.size.length() * 0.6 or a.phase == "":
			a.goal = st.pos + Vector2(rng.randf_range(-st.size.x, st.size.x), rng.randf_range(-st.size.y, st.size.y)) * 0.45
			a.phase = "graze"
		if a.phase == "graze" and _animal_move(a, a.goal, dt, false):
			a.phase = "rest"
			a.work_t = rng.randf_range(4.0, 12.0)
		if a.phase == "rest":
			a.anim = Anim.PICK
			a.work_t -= dt
			if a.work_t <= 0.0:
				a.phase = ""
		return
	# Wild animals: flee from people, otherwise graze near the herd.
	var flee_r := 18.0 if a.kind == "deer" else 12.0
	var threat: Unit = null
	for o: Unit in units_near(a.pos, flee_r, -2):
		if is_person(o) and o.faction >= 0:
			threat = o
			break
	if threat:
		var away := (a.pos - threat.pos).normalized()
		a.goal = a.pos + away * 25.0
		a.phase = "flee"
	if a.phase == "flee":
		if _animal_move(a, a.goal, dt, true):
			a.phase = ""
		return
	if a.phase == "" or a.phase == "rest" and a.work_t <= 0.0:
		var center: Vector2 = a.goal if a.herd < 0 else herd_center(a.herd)
		a.goal = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 14.0)
		a.phase = "graze"
	if a.phase == "graze":
		if _animal_move(a, a.goal, dt, false):
			a.phase = "rest"
			a.work_t = rng.randf_range(3.0, 10.0)
	elif a.phase == "rest":
		a.anim = Anim.PICK
		a.work_t -= dt


var herd_pos := {}


func herd_center(h: int) -> Vector2:
	return herd_pos.get(h, Vector2(map_size, map_size) * 0.5)


func _animal_move(a: Unit, goal: Vector2, dt: float, run: bool) -> bool:
	var to := goal - a.pos
	var d := to.length()
	if d < 0.6:
		a.anim = Anim.IDLE
		return true
	var sp := (9.0 if run else 1.6) * (0.8 if a.child else 1.0)
	if a.kind == "deer" and run:
		sp = 9.5
	var nxt := a.pos + to / d * minf(d, sp * dt)
	if solid_for(-1, cell_of(nxt)):
		a.phase = ""
		a.anim = Anim.IDLE
		return true
	a.pos = nxt
	a.facing = lerp_angle(a.facing, atan2(to.x, to.y), minf(1.0, dt * 6.0))
	a.anim = Anim.RUN if run else Anim.WALK
	return false


# --- Vision, knowledge and intelligence -------------------------------------------

func update_vision() -> void:
	for f: Faction in factions:
		f.visible.fill(0)
	for u: Unit in units:
		if u.dead or u.faction < 0 or u.stable >= 0:
			continue
		if not (is_person(u) or u.kind in ["cannon", "ram"]):
			continue
		var f: Faction = factions[u.faction]
		var r: float = Defs.VILLAGER["sight"]
		var scouting := u.task == "scout" and u.scout_leg < 3
		if u.kind == "commander":
			r = Defs.COMMANDER["sight"]
		elif scouting:
			r = Defs.SCOUT_SIGHT * (1.15 if u.mounted else 1.0)
		var cells := kcells_in(u.pos, r)
		for k in cells:
			f.visible[k] = 1
		if u.kind == "commander":
			for k in cells:
				f.knowledge[k] = t
			_sight(f, u.pos, r, null)
		elif scouting:
			for k in cells:
				u.seen[k] = t
			_sight(f, u.pos, r, u)
	for b: Building in buildings:
		if b.dead or not b.complete:
			continue
		var d: Dictionary = Defs.BUILDINGS[b.type]
		var r := float(d.get("sight", 18.0))
		var f: Faction = factions[b.faction]
		var cells := kcells_in(b.pos, r)
		for k in cells:
			f.visible[k] = 1
			f.knowledge[k] = t
		var seen := _sight(f, b.pos, r, null)
		if d.get("alarm", false) or b.type == "campfire":
			if seen.size() > 0 and t - b.alarm_t > 30.0:
				b.alarm_t = t
				var people := 0
				for o in seen:
					if is_person(o):
						people += 1
				if people > 0 or seen.size() > 0:
					if b.faction == 0:
						var what := Defs.building_name(b.type).to_lower()
						post(0, "Alarm at the %s %s: %s!" % [what, _place_name(0, b.pos), _estimate(seen)], "alarm")
						sound("bell", b.pos, 0)
					emit({"type": "alarm", "faction": b.faction, "pos": b.pos})


## Records what is visible from p. Scouts keep it to themselves until they report.
func _sight(f: Faction, p: Vector2, r: float, scout) -> Array:
	var foes := []
	for o: Unit in units_near(p, r, -2):
		if o.faction == f.id:
			continue
		if o.faction < 0:
			if o.kind == "horse" and o.stable < 0:
				var key := "herd%d" % o.herd
				var e := {"kind": "herd", "pos": o.pos, "t": t}
				if scout:
					scout.sightings[key] = e
				else:
					f.intel[key] = e
			continue
		if o.stable >= 0:
			continue
		foes.append(o)
	if not foes.is_empty():
		var entry := _group_entry(foes)
		var key := "army%d" % kcell(p)
		if scout:
			scout.sightings[key] = entry
		else:
			f.intel[key] = entry
	for b: Building in buildings:
		if b.dead or b.faction == f.id or b.pos.distance_squared_to(p) > r * r:
			continue
		var e := {"kind": "building", "type": b.type, "pos": b.pos, "faction": b.faction, "t": t, "complete": b.complete, "id": b.id}
		if scout:
			scout.sightings["b%d" % b.id] = e
		else:
			f.intel["b%d" % b.id] = e
	if scout:
		for n in _nodes_within(p, r):
			if n.kind == "deposit":
				scout.sightings["d%d" % n.id] = {"kind": "deposit", "type": n.sub, "pos": n.pos, "t": t}
	return foes


func _group_entry(foes: Array) -> Dictionary:
	var counts := {}
	var center := Vector2.ZERO
	var fac_id := -1
	for o in foes:
		var k := describe_person(o)
		counts[k] = int(counts.get(k, 0)) + 1
		center += o.pos
		fac_id = o.faction
	return {"kind": "units", "pos": center / foes.size(), "counts": counts, "total": foes.size(), "t": t, "faction": fac_id}


func _note_units(f: Faction, p: Vector2, foes: Array, when: float) -> void:
	if f == null or foes.is_empty():
		return
	var e := _group_entry(foes)
	e["t"] = when
	f.intel["army%d" % kcell(p)] = e


static func approx(n: int) -> String:
	if n <= 3:
		return str(n)
	if n < 10:
		return "about %d" % n
	return "about %d" % (int(round(n / 5.0)) * 5)


func _estimate(foes: Array) -> String:
	var e := _group_entry(foes)
	return counts_text(e["counts"])


static func counts_text(counts: Dictionary) -> String:
	var parts: Array[String] = []
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in keys:
		var n := int(counts[k])
		var word: String = k
		if n != 1:
			word = {"commander": "commanders", "cannon": "cannons", "ram": "rams", "rider": "riders", "pikeman": "pikemen",
				"spearman": "spearmen", "swordsman": "swordsmen", "clubman": "clubmen", "archer": "archers", "villager": "villagers"}.get(k, k + "s")
		if k == "commander":
			parts.append("their crowned commander")
		else:
			parts.append("%s %s" % [approx(n), word])
	return ", ".join(parts)


func deliver_report(u: Unit, c: Crew) -> void:
	var f := fac(u.faction)
	for k in u.seen:
		if float(u.seen[k]) > f.knowledge[k]:
			f.knowledge[k] = u.seen[k]
	var oldest := t
	var camp = null
	var enemy_buildings := {}
	var walls := 0
	var armies := []
	var deposits := {}
	var herds := 0
	for key in u.sightings:
		var e: Dictionary = u.sightings[key]
		var prev: Dictionary = f.intel.get(key, {})
		if prev.is_empty() or float(prev.get("t", -1.0)) <= float(e["t"]):
			f.intel[key] = e
		oldest = minf(oldest, float(e["t"]))
		match e["kind"]:
			"building":
				if e["type"] == "campfire":
					camp = e["pos"]
				elif Defs.BUILDINGS[e["type"]].get("wall", false):
					walls += 1
				else:
					enemy_buildings[e["type"]] = int(enemy_buildings.get(e["type"], 0)) + 1
			"units":
				armies.append(e)
			"deposit":
				deposits[e["type"]] = true
			"herd":
				herds += 1
	var where := Terrain.compass_name(c.state.get("target", u.pos) - home_pos(u.faction))
	var ago := int((t - oldest) / 60.0)
	var when := "just now" if ago < 1 else ("%d minute%s ago" % [ago, "" if ago == 1 else "s"])
	var parts: Array[String] = []
	if camp != null:
		var d := int(round((camp as Vector2).distance_to(home_pos(u.faction)) / 10.0) * 10.0)
		parts.append("their camp is about %d m %s" % [d, Terrain.compass_name((camp as Vector2) - home_pos(u.faction))])
	var total_men := 0
	var counts := {}
	for e in armies:
		for k in e["counts"]:
			counts[k] = int(counts.get(k, 0)) + int(e["counts"][k])
			total_men += int(e["counts"][k])
	if total_men > 0:
		parts.append("I saw " + counts_text(counts))
	if not enemy_buildings.is_empty():
		var bl: Array[String] = []
		for k in enemy_buildings:
			bl.append("%s %s" % [approx(enemy_buildings[k]), Defs.building_name(k).to_lower() + ("s" if enemy_buildings[k] > 1 else "")])
		parts.append("buildings: " + ", ".join(bl))
	if camp != null:
		parts.append("walls: %s" % ("none" if walls == 0 else ("%d sections" % walls)))
	if herds > 0:
		parts.append("wild horses graze out there")
	if not deposits.is_empty():
		var dl: Array[String] = []
		for k in deposits:
			dl.append(Defs.RESOURCE_NAMES[k])
		parts.append("deposits of " + ", ".join(dl))
	var text: String
	if parts.is_empty():
		text = "%s is back from the %s. Nothing to report." % [u.name, where]
	else:
		text = "%s is back from the %s. %s: %s." % [u.name, where, when.capitalize(), "; ".join(parts)]
	f.reports.push_front({"t": t, "by": u.name, "text": text, "dir": where})
	if u.faction == 0:
		post(0, text, "report")
		sound("report", u.pos, 0)
	u.seen = {}
	u.sightings = {}
