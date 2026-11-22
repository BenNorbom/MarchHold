extends "res://scripts/sim/match_battle.gd"
## Combat, projectiles, siege engines, animals, vision, intelligence and alarms.

const WOOD_TYPES := ["hut", "stockpile", "farm", "armory", "palisade", "palisade_gate", "watch_post", "stable"]
const STONE_TYPES := ["stone_wall", "stone_gate", "tower"]

const REFUGE_NEAR := 15.0       # this close to the refuge, people falling back turn and fight

var vision_t := 0.0
var armed_filter: Callable = armed      # one Callable, not a new lambda for every villager every tick


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
	if u.bow:
		return "archer"
	return "villager"


## Returns true when the unit spent this tick fighting or fleeing.
func combat_update(u: Unit, dt: float, radius: float) -> bool:
	u.cooldown = maxf(0.0, u.cooldown - dt)
	if t < u.stun_t:
		u.anim = Anim.IDLE
		return true
	var held := post_of(u)
	if held and under_direct_order(u):
		held = null
	if held and held.alert == "falling_back" and u.siege < 0 and u.pos.distance_to(held.refuge) > REFUGE_NEAR:
		# Falling back is a run. Stopping to trade blows is how a retreat gets caught.
		u.enemy = -1
		u.enemy_bld = -1
		move_to(u, held.refuge + _ring(u, 6.0), dt, 2.0, true)
		return true
	if u.child or u.siege >= 0:
		return _maybe_flee(u, dt, 10.0)
	if u.flee_t > 0.0:
		_drop_fight(u)
		u.flee_t -= dt
		var home := resting_place(u)
		move_to(u, home + _ring(u, 6.0), dt, 3.0, true)
		return true
	if not armed(u):
		return _maybe_flee(u, dt, 12.0)
	# Badly hurt soldiers fall back to heal.
	if u.kind == "villager" and u.hp < u.max_hp * 0.25 and t - u.hit_t < 4.0:
		u.flee_t = 10.0
		_drop_fight(u)
		return true
	if _swinging(u):
		return true
	var c := crew_of(u)
	var order: String = c.steps[c.idx]["action"] if c and c.idx < c.steps.size() else ""
	var foe := unit(u.enemy)
	if foe:
		if u.engage_from == Vector2.ZERO:
			u.engage_from = u.pos
		# The leash is checked twice a second, the rest every tick.
		var gone := foe.dead or foe.stable >= 0 or foe.faction == u.faction
		if not gone and (ticks + u.id) % 5 == 0:
			gone = not _may_fight(u, foe, _fight_area(u, c, order, radius), radius)
		if gone:
			foe = null
			u.enemy = -1
			u.scan_t = 0.0
	elif u.enemy >= 0:
		u.enemy = -1
		u.scan_t = 0.0
	if t + EPS >= u.scan_t:
		foe = _pick_target(u, foe, c, order, radius)
		var again := 0.5
		if foe:
			again = (2.2 if u.front else 1.0) if u.engaged else 0.8
		u.scan_t = t + again + float(u.id % 4) * 0.1
	if foe == null:
		u.engaged = false
		u.engage_from = Vector2.ZERO
		var b := bld(u.enemy_bld)
		if b and not b.dead:
			_attack_building(u, b, dt)
			return true
		u.enemy_bld = -1
		return false
	_fight(u, foe, dt, order, c)
	return true


func _maybe_flee(u: Unit, dt: float, r: float) -> bool:
	if u.flee_t > 0.0:
		u.flee_t -= dt
		move_to(u, resting_place(u) + _ring(u, 5.0), dt, 3.0, true)
		return true
	var foe := nearest_enemy(u.pos, r, u.faction, armed_filter)
	if foe:
		u.flee_t = 6.0
		u.carry = 0.0
		return true
	return false


func _fight(u: Unit, foe: Unit, dt: float, order: String, c: Crew) -> void:
	var d := u.pos.distance_to(foe.pos)
	if can_shoot_bow(u) and u.arrows > 0 and (u.weapon == "" or d > 6.0) and d <= bow_range(u):
		u.engaged = false
		face(u, foe.pos)
		u.anim = Anim.SHOOT
		if u.cooldown <= 0.0:
			if arrow_arc(u, foe) < 0.0:
				# Behind cover: look for someone else.
				u.cooldown = 0.5
				u.avoid_id = foe.id
				u.avoid_t = t + 3.0
				u.anim = Anim.IDLE
				return
			u.cooldown = 2.0
			u.shot_t = t
			u.arrows -= 1
			fire_arrow(u, foe, armory_tier(u.faction))
		return
	var holding := order == "hold"
	if not holding and u.bow and u.arrows <= 0 and u.weapon == "":
		# Out of arrows: go and refill at the armory.
		var arm := nearest_building(u.faction, u.pos, ["armory"])
		if arm:
			if go_to_building(u, arm, dt, 1.4, true):
				refill_quiver(u, fac(u.faction))
			return
	var stand := stand_distance(u, foe)
	if d <= stand + (STAY_MARGIN if u.engaged else START_MARGIN):
		face(u, foe.pos)
		u.engaged = true
		u.anim = Anim.MELEE
		if u.front and u.cooldown <= 0.0:
			var wall := melee_cover(u, foe)
			if wall:
				_go_through(u, foe, wall, holding)
			else:
				_begin_swing(u, foe.id, -1)
		return
	u.engaged = false
	if not u.front:
		# Second rank: stay ready until a place opens.
		var wait := stand + 1.0
		if d <= wait + 0.6:
			face(u, foe.pos)
			u.anim = Anim.MELEE
			return
		stand = wait
	if holding and c and u.pos.distance_to(station(u, c)) > 1.5:
		face(u, foe.pos)
		u.anim = Anim.MELEE
		return
	if u.mounted and d > 6.0 and u.charge_start == Vector2.ZERO:
		u.charge_start = u.pos
	if order == "attack" and (ticks + u.id) % 5 == 0 and not line_clear(u.faction, u.pos, foe.pos):
		# Storming a camp: batter the wall in the way instead of hunting for a way round.
		var across := wall_between(u.faction, u.pos, foe.pos)
		if across:
			_go_through(u, foe, across, holding)
			return
	if move_to(u, foe.pos, dt, stand, true, false):
		face(u, foe.pos)
		u.anim = Anim.MELEE
	elif t < u.path_wait:
		_go_through(u, foe, melee_cover(u, foe), holding)


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
		# A pike set against a charge takes the weight out of it.
		var braced := tgt.weapon.ends_with("pike") and _faces(tgt, att.pos)
		if w.has("charge") and not braced and att.charge_start != Vector2.ZERO and att.charge_start.distance_to(att.pos) > 10.0:
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


## Returns how it was defended: "parry", "block", "shield", "armor" or "".
func deal_damage(tgt: Unit, dmg: float, att: Unit, kind: String, from: Vector2 = Vector2.INF, shield_scale: float = 1.0) -> String:
	if tgt.dead or dmg <= 0.0:
		return ""
	var origin := from
	if origin == Vector2.INF:
		origin = att.pos if att else tgt.pos
	var guard := ""
	if tgt.blocking and _faces(tgt, origin):
		if kind == "melee" and t - tgt.guard_up_t <= PARRY_WINDOW:
			guard = "parry"
			dmg = 0.0
			if att:
				_stagger(att, Defs.PARRY_STAGGER)
		elif kind == "melee" or (kind == "arrow" and tgt.shield != ""):
			if tgt.stamina > 0.05:
				guard = "block"
				tgt.stamina = maxf(0.0, tgt.stamina - Defs.BLOCK_STAMINA - dmg * 0.005)
				var kept: float
				if tgt.shield != "":
					var shield: Dictionary = Defs.ITEMS[tgt.shield]
					var carried: float = float(shield["block_" + kind]) * shield_scale
					kept = (1.0 - float(shield["up_" + kind])) / (1.0 - carried)
				else:
					kept = Defs.BLOCK_KEEP["weapon" if tgt.weapon != "" else "bare"]
				dmg *= kept
	if guard == "":
		if tgt.shield != "" and kind != "ball":
			guard = "shield"
		elif tgt.armor != "":
			guard = "armor"
	tgt.hp -= dmg
	tgt.hit_t = t
	tgt.hit_dir = (tgt.pos - origin).normalized()
	if att:
		tgt.attacker = att.id
		if tgt.enemy < 0 and armed(tgt) and att.faction != tgt.faction:
			tgt.enemy = att.id
	emit({"type": "hit", "id": tgt.id, "att": att.id if att else -1, "pos": tgt.pos, "from": origin, "dir": tgt.hit_dir,
		"kind": kind, "guard": guard, "dmg": dmg, "killed": tgt.hp <= 0.0})
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
			tgt.prev = tgt.pos
			emit({"type": "death", "id": tgt.id, "kind": "deer", "pos": tgt.pos, "faction": -1})
			add_carcass(tgt.pos, 40.0)
			return guard
		kill_unit(tgt, kind)
	return guard


func _place_name(faction: int, p: Vector2) -> String:
	var home := home_pos(faction)
	var d := p.distance_to(home)
	if d < 40.0:
		return "at home"
	return "%d m %s of home" % [int(round(d / 10.0) * 10.0), Terrain.compass_name(p - home)]


func _attack_building(u: Unit, b: Building, dt: float) -> void:
	if u.bow and u.weapon == "":
		# Arrows don't hurt buildings; archers hang back.
		u.enemy_bld = -1
		u.anim = Anim.IDLE
		return
	var reach := maxf(float(melee_def(u)["stand"]) + 0.6, 2.0)
	var d := dist_to_building(u.pos, b)
	if d > reach:
		var arrived := move_to(u, _nearest_edge(u, b, 1.2), dt, 0.6, true)
		if not arrived or d > reach + 2.5:
			if t < u.path_wait:
				var across := wall_between(u.faction, u.pos, b.pos)
				if across and across != b:
					u.enemy_bld = across.id
			return
	face(u, b.pos)
	u.anim = Anim.MELEE
	if u.cooldown <= 0.0:
		_begin_swing(u, -1, b.id)


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
	emit({"type": "building_hit", "id": b.id, "att": att.id if att else -1})
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


func _land_blow(u: Unit, tgt: Unit, share: float) -> void:
	if tgt.dead:
		return
	var metal := tgt.weapon != "" or tgt.shield != ""
	var guard := deal_damage(tgt, melee_damage(u, tgt) * share, u, "melee")
	if guard in ["parry", "block"]:
		sound("clash", tgt.pos)
	else:
		sound("clash" if metal else "hit", tgt.pos)


func _hit_building(u: Unit, b: Building) -> void:
	damage_building(b, float(weapon_def(u)["dmg"]) * _material(b.type), u)
	sound("chop" if b.type in WOOD_TYPES else "pick", b.pos)


# --- Projectiles ------------------------------------------------------------------

func _height(p: Vector2) -> float:
	return terrain.height_at(p.x, p.y)


func fire_arrow(shooter: Unit, target: Unit, tier: int) -> void:
	var d := shooter.pos.distance_to(target.pos)
	var s := Shot.new()
	s.kind = "arrow"
	s.faction = shooter.faction
	s.shooter = shooter.id
	s.start = _muzzle(shooter)
	s.pos = s.start
	s.prev = s.start
	var arc := arrow_arc(shooter, target)
	s.arc = arc if arc >= 0.0 else ARROW_FLAT
	var chance := clampf(1.05 - d / 75.0, 0.3, 0.95)
	if target.kind == "deer":
		chance = 0.85
	s.hits = rng.randf() < chance
	s.dur = clampf(d / 38.0, 0.25, 2.0) * (1.2 if s.arc > ARROW_FLAT else 1.0)
	# It lands on a whole tick, so lead by that.
	var flight := ceilf(s.dur / Defs.TICK) * Defs.TICK
	var aim := target.pos + target.vel.limit_length(14.0) * flight
	if not s.hits:
		aim += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, 4.0)
	s.end = Vector3(aim.x, _height(aim) + (1.1 if s.hits else 0.0), aim.y)
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
	s.pos = s.start
	s.prev = s.start
	s.arc = 0.05
	s.end = Vector3(p.x, _height(p) + 0.5, p.y)
	s.dur = clampf(d / 120.0, 0.35, 1.6)
	s.target_bld = at_bld
	shots.append(s)
	sound("cannon", e.pos)
	emit({"type": "fx", "name": "muzzle", "pos": e.pos, "dir": aim - e.pos})


## Physically simulated shot (the player's bow).
func fire_free_arrow(shooter: Unit, origin: Vector3, vel: Vector3, tier: int, strength: float = 1.0) -> void:
	var s := Shot.new()
	s.kind = "arrow"
	s.free = true
	s.faction = shooter.faction
	s.shooter = shooter.id
	s.pos = origin
	s.prev = origin
	s.start = origin
	s.vel = vel
	s.dmg = Defs.ARROW_DMG[clampi(tier, 0, 2)] * 1.2 * strength
	shots.append(s)
	sound("bow", shooter.pos)


func update_shots(dt: float) -> void:
	# A spent shot stays for one tick, so the view can fly it all the way in.
	shots = shots.filter(func(s): return not s.dead)
	for s: Shot in shots:
		s.t += dt
		s.prev = s.pos
		if s.free:
			_free_shot(s, dt)
			continue
		var k := clampf(s.t / s.dur, 0.0, 1.0)
		s.pos = s.start.lerp(s.end, k) + Vector3(0, 4.0 * k * (1.0 - k) * s.start.distance_to(s.end) * s.arc, 0)
		if k >= 1.0:
			s.dead = true
			if s.kind == "arrow":
				_arrow_lands(s)
			else:
				_ball_impact(s)


func _arrow_lands(s: Shot) -> void:
	var tgt := unit(s.target)
	var p := Vector2(s.end.x, s.end.z)
	var hit := false
	if s.hits and tgt and not tgt.dead:
		# It has to still be there. Game doesn't dodge.
		var room := Crowd.radius(tgt) + 0.9
		hit = tgt.kind == "deer" or tgt.pos.distance_to(p) <= room
	if hit:
		var dmg := s.dmg
		if tgt.shield != "":
			dmg *= 1.0 - float(Defs.ITEMS[tgt.shield]["block_arrow"])
		if tgt.armor != "":
			dmg *= 1.0 - float(Defs.ITEMS[tgt.armor]["armor"])
		if tgt.in_tower >= 0:
			dmg *= 0.5
		deal_damage(tgt, dmg, unit(s.shooter), "arrow", Vector2(s.start.x, s.start.z))
	var at := Vector3(s.end.x, _height(p), s.end.z)
	var drop := (s.end - s.start) - Vector3(0, 4.0 * s.start.distance_to(s.end) * s.arc, 0)
	emit({"type": "fx", "name": "arrow_land", "pos": p, "at": at, "dir": drop, "hit": hit})


func _free_shot(s: Shot, dt: float) -> void:
	var from := s.pos
	s.vel.y -= 9.8 * dt
	var to := from + s.vel * dt
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var flat := b - a
	var len2 := flat.length_squared()
	var first := 2.0
	var victim: Unit = null
	# Test the whole of this tick's flight, not just where it ends.
	for u: Unit in units_near((a + b) * 0.5, sqrt(len2) * 0.5 + 2.0, -2):
		if u.faction == s.faction or u.id == s.shooter or u.stable >= 0:
			continue
		var near := clampf((u.pos - a).dot(flat) / len2, 0.0, 1.0) if len2 > 0.0001 else 0.0
		var side := (a + flat * near).distance_squared_to(u.pos)
		var r := Crowd.radius(u) + 0.15
		if side > r * r:
			continue
		var entry := maxf(0.0, near - sqrt(r * r - side) / maxf(sqrt(len2), 0.01))
		if entry >= first:
			continue
		var ground := _height(u.pos)
		var top := 1.85
		if u.mounted:
			top = 2.6
		elif u.child:
			top = 1.3
		elif u.kind != "villager" and u.kind != "commander":
			top = 1.6
		for k: float in [entry, near]:
			var y := lerpf(from.y, to.y, k)
			if y > ground - 0.1 and y < ground + top:
				first = entry
				victim = u
				break
	var stopped := 2.0
	var wall := first_building(a, b)
	if not wall.is_empty():
		var k: float = wall[1]
		if lerpf(from.y, to.y, k) < _height((wall[0] as Building).pos) + cover_height(wall[0]):
			stopped = k
	var samples := maxi(1, int(ceil(sqrt(len2) / 1.5)))
	for i in range(1, samples + 1):
		var k := float(i) / samples
		if k >= stopped:
			break
		var p := from.lerp(to, k)
		if p.y < _height(Vector2(p.x, p.z)):
			stopped = k
			break
	if victim and first < stopped:
		s.pos = from.lerp(to, first)
		var dmg := s.dmg
		if victim.shield != "":
			dmg *= 1.0 - float(Defs.ITEMS[victim.shield]["block_arrow"]) * 0.7
		if victim.armor != "":
			dmg *= 1.0 - float(Defs.ITEMS[victim.armor]["armor"])
		deal_damage(victim, dmg, unit(s.shooter), "arrow", Vector2(s.start.x, s.start.z), 0.7)
		s.dead = true
		sound("arrow_land", victim.pos)
		emit({"type": "fx", "name": "arrow_land", "pos": victim.pos, "at": s.pos, "dir": s.vel, "hit": true})
		return
	if stopped <= 1.0:
		s.pos = from.lerp(to, stopped)
		s.dead = true
		var p2 := Vector2(s.pos.x, s.pos.z)
		sound("arrow_land", p2)
		emit({"type": "fx", "name": "arrow_land", "pos": p2, "at": s.pos, "dir": s.vel, "hit": false})
		return
	s.pos = to
	if s.t > 6.0 or not terrain.in_bounds(b, 1.0):
		s.dead = true


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
		deal_damage(u, dmg, e, "ball", p)


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
	var same_goal := e.path_goal.distance_squared_to(goal) <= 9.0
	if e.path.is_empty() and same_goal and t < e.path_wait and not (fair_paths and e.path_turn == ticks):
		e.anim = Anim.IDLE
		return
	if e.path.is_empty() or not same_goal:
		e.path = route_for(e, goal)
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
			if wp.distance_squared_to(e.path_goal) > 1.0:
				_dead_end(e)
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
			var spot := slot_point(u, lane_center(c, cmd.pos - dir * 5.0, dir), dir)
			var arrived := u.pos.distance_to(spot) <= 1.5
			if not arrived:
				arrived = move_to(u, spot, dt, 1.0, u.pos.distance_to(spot) > 10.0)
			if arrived:
				u.anim = Anim.IDLE
				u.facing = cmd.facing
		"guard", "hold":
			var dir := post_facing(u.faction, target)
			var spot := station(u, c)
			if u.bow:
				var tw := nearest_building(u.faction, spot, ["tower"])
				if tw and tw.pos.distance_to(spot) < 12.0:
					spot = tw.pos + _ring(u, 1.2)
			var at_post := u.pos.distance_to(spot) <= 1.2
			if not at_post:
				at_post = move_to(u, spot, dt, 0.8)
			if at_post:
				u.anim = Anim.IDLE
				face(u, spot + dir * 10.0)
			var tw2 := nearest_building(u.faction, u.pos, ["tower"])
			u.in_tower = tw2.id if (tw2 and u.bow and dist_to_building(u.pos, tw2) < 2.2) else -1
		"attack":
			var center := crew_center_now(c)
			var dir := target - center
			var in_way := wall_ahead(c, center, target)
			# A deep or offset crew's centre never gets as close as its front does.
			if in_way or center.distance_to(target) < 30.0 + c.depth + absf(c.lane):
				if u.bow and u.weapon == "":
					u.anim = Anim.IDLE
					face(u, target)
					return
				if u.enemy_bld < 0:
					var b := in_way
					if in_way:
						# Each takes the piece on their own line, so the breach is a wide one.
						var mine := wall_between(u.faction, u.pos, target)
						if mine and mine.pos.distance_to(in_way.pos) < 14.0:
							b = mine
					else:
						b = _nearest_enemy_building(u.faction, target, 70.0)
					if b:
						u.enemy_bld = b.id
					else:
						u.anim = Anim.IDLE
				return
			var lead := target + (center - target).normalized() * maxf(0.0, center.distance_to(target) - 25.0)
			# Slots run back from the front rank, so aim the front ahead by half the depth:
			# otherwise a deep crew's centre, and then the crew, creeps backwards.
			var spot := slot_point(u, center + dir.normalized() * (8.0 + c.depth * 0.5), dir)
			if center.distance_to(target) < 60.0:
				spot = slot_point(u, lane_center(c, lead, dir), dir)
			if move_to(u, spot, dt, 1.0):
				u.anim = Anim.IDLE


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
	if sides_near(a.pos, flee_r, rivals_mask(-1)):
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
	for u: Unit in units:
		if u.dead or u.faction < 0 or u.stable >= 0:
			continue
		# Only commanders and scouts learn from what they see; buildings are below.
		var scouting := u.task == "scout" and u.scout_leg < 3
		var leader := u.kind == "commander"
		if not (leader or (scouting and u.kind == "villager")):
			continue
		var f: Faction = factions[u.faction]
		var r: float = 0.0
		if leader:
			r = Defs.COMMANDER["sight"]
		elif scouting:
			r = Defs.SCOUT_SIGHT * (1.15 if u.mounted else 1.0)
		var cells := kcells_in(u.pos, r)
		if leader:
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
		if b.sight_cells.is_empty():
			b.sight_cells = kcells_in(b.pos, r)
		var cells := b.sight_cells
		for k in cells:
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
	var around: Array = units_near(p, r, -2) if sides_near(p, r, rivals_mask(f.id) | WILD_HORSE) else []
	for o: Unit in around:
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
		var sides := {}
		for o in foes:
			if not sides.has(o.faction):
				sides[o.faction] = []
			sides[o.faction].append(o)
		for side in sides:
			var entry := _group_entry(sides[side])
			var key := _army_key(side, p)
			if scout:
				scout.sightings[key] = entry
			else:
				f.intel[key] = entry
	for b: Building in foreign_buildings_near(f.id, p, r):
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
	f.intel[_army_key(e["faction"], p)] = e


func _army_key(faction: int, p: Vector2) -> String:
	return "army%d:%d" % [faction, kcell(p)]


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
				"spearman": "spearmen", "swordsman": "swordsmen", "archer": "archers", "villager": "villagers"}.get(k, k + "s")
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
	var camps := {}
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
					camps[e["faction"]] = e["pos"]
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
	for who in camps:
		var away: Vector2 = camps[who] - home_pos(u.faction)
		var d := int(round(away.length() / 10.0) * 10.0)
		var whose := "their" if factions.size() == 2 else "%s's" % factions[who].short_name
		parts.append("%s camp is about %d m %s" % [whose, d, Terrain.compass_name(away)])
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
	if not camps.is_empty():
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
