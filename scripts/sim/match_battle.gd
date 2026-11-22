extends "res://scripts/sim/match_work.gd"
## Battle rules that match_combat.gd's fighting is built from: choosing targets,
## spacing, the attack clock, cover and the player's own fighting.
##
## Every blow has a start, an impact and a recovery. The view draws from the same
## clock, so what you see land is what does the damage.

const LOW_COVER := {"campfire": 0.7, "stockpile": 1.3, "farm": 0.5, "tower": 8.0}

const EPS := 0.001                # t is summed, so compare with a little slack
const START_MARGIN := 0.3         # beyond the weapon's stand distance: may begin fighting
const STAY_MARGIN := 0.75         # ... keeps fighting
const HIT_MARGIN := 0.95          # ... a blow still lands; step back further to dodge it
const RECOVER := 0.15             # rooted this long after an impact
const PARRY_WINDOW := 0.3
const PARRY_REARM := 0.35         # lowering the guard briefly doesn't re-open the window
const NOCK := 0.35
const ARROW_FLAT := 0.12          # arc height as a share of the distance
const ARROW_LOB := 0.25

var strikes: Array = []           # units whose blow lands this tick
var pressure := {}                # target id -> how many are after it


# --- What people carry ------------------------------------------------------------


func melee_def(u: Unit) -> Dictionary:
	if u.style_for != u.weapon:
		u.style_for = u.weapon
		u.style = Defs.MELEE[Defs.weapon_family(u.weapon)]
	return u.style


## Centre-to-centre distance to fight at.
func stand_distance(u: Unit, foe: Unit) -> float:
	var stand: float = melee_def(u)["stand"]
	if u.mounted or foe.mounted or foe.kind != "villager":
		stand += maxf(0.0, Crowd.radius(u) + Crowd.radius(foe) - 0.8)
	return stand


func is_hostile(faction: int, o: Unit) -> bool:
	return not o.dead and o.faction >= 0 and o.faction != faction and o.stable < 0 and o.kind != "horse" and o.kind != "deer"


# --- Deciding to fight ------------------------------------------------------------

## Before anyone acts: count who is after whom, and who has a place in the front rank.
func update_engagements() -> void:
	if ticks % 3 != 0:
		return
	pressure.clear()
	var close := {}
	for u: Unit in units:
		if u.dead or u.enemy < 0:
			continue
		var foe := unit(u.enemy)
		if foe == null or foe.dead:
			continue
		pressure[foe.id] = int(pressure.get(foe.id, 0)) + 1
		if u.bow and u.arrows > 0 and u.weapon == "":
			continue
		var d := u.pos.distance_to(foe.pos)
		if d > stand_distance(u, foe) + 2.5:
			u.front = true
			continue
		if not close.has(foe.id):
			close[foe.id] = []
		# Whoever already holds a place keeps it.
		close[foe.id].append([d - (10.0 if u.front and u.engaged else 0.0), u])
	for id in close:
		var ranked: Array = close[id]
		if ranked.size() > 6:          # no weapon has fewer places
			ranked.sort_custom(func(a, b): return a[0] < b[0])
		for i in ranked.size():
			var u: Unit = ranked[i][1]
			u.front = i < int(melee_def(u)["places"])


func _drop_fight(u: Unit) -> void:
	u.enemy = -1
	u.engaged = false
	u.engage_from = Vector2.ZERO
	cancel_swing(u)


## Where this unit may fight, measured from its post and not from where it has got to:
## [centre, limit, limit for whoever just hit it].
func _fight_area(u: Unit, c: Crew, order: String, radius: float) -> Array:
	match order:
		"hold":
			var reach := stand_distance(u, u) + HIT_MARGIN + 1.0
			return [station(u, c), reach, reach]
		"guard":
			return [station(u, c), radius + 4.0, radius * 2.2]
		"follow":
			var lead := unit(fac(u.faction).commander)
			return [lead.pos if lead and not lead.dead else u.pos, radius + 6.0, radius * 2.0]
		"attack":
			return [crew_center_now(c), radius + 14.0, radius * 2.2]
	var from := u.engage_from if u.engage_from != Vector2.ZERO else u.pos
	return [from, radius + 10.0, radius + 28.0]


func _may_fight(u: Unit, o: Unit, area: Array, radius: float) -> bool:
	if not is_hostile(u.faction, o) or (o.id == u.avoid_id and t < u.avoid_t):
		return false
	var d := u.pos.distance_to(o.pos)
	var hit_me := o.id == u.attacker and t - u.hit_t < 4.0
	if d > maxf(radius + 8.0, float(area[2]) if hit_me else 0.0):
		return false
	# An archer needn't leave the post to shoot.
	if u.bow and u.arrows > 0 and u.weapon == "" and d <= bow_range(u):
		return true
	return o.pos.distance_to(area[0]) <= float(area[2] if hit_me else area[1])


func _pick_target(u: Unit, current: Unit, c: Crew, order: String, radius: float) -> Unit:
	var area := _fight_area(u, c, order, radius)
	var shooter := u.bow and u.arrows > 0 and u.weapon == ""
	var places := int(melee_def(u)["places"])
	var best := current
	var best_score := INF
	if current:
		best_score = _target_score(u, current, current, shooter, places)
	# Most fights are decided close by, so only look far when there's nobody near.
	var looks := [radius] if radius <= 10.0 else [10.0, radius]
	var here := u.pos
	for r: float in looks:
		var r2 := r * r
		var lo := Vector2i(clampi(int((here.x - r) / BUCKET), 0, bucket_n - 1), clampi(int((here.y - r) / BUCKET), 0, bucket_n - 1))
		var hi := Vector2i(clampi(int((here.x + r) / BUCKET), 0, bucket_n - 1), clampi(int((here.y + r) / BUCKET), 0, bucket_n - 1))
		for by in range(lo.y, hi.y + 1):
			for bx in range(lo.x, hi.x + 1):
				var i := uhead[by * bucket_n + bx]
				while i != -1:
					var o: Unit = ulist[i]
					i = unext[i]
					if o.faction == u.faction:
						continue
					var d2 := here.distance_squared_to(o.pos)
					if d2 > r2:
						continue
					# No score can be more than 3 better than the distance.
					if best_score < INF:
						var bound := best_score + 3.0
						if bound <= 0.0 or d2 >= bound * bound:
							continue
					if o == current or not _may_fight(u, o, area, radius):
						continue
					var score := _target_score(u, o, current, shooter, places)
					if score < best_score:
						best_score = score
						best = o
		if best:
			break
	if best == null and t - u.hit_t < 4.0:
		var att := unit(u.attacker)
		if att and _may_fight(u, att, area, radius):
			best = att
	if best != current and best:
		if current:
			pressure[current.id] = int(pressure.get(current.id, 1)) - 1
		else:
			u.engage_from = u.pos
		pressure[best.id] = int(pressure.get(best.id, 0)) + 1
		u.engaged = false
		u.front = true
	u.enemy = best.id if best else -1
	return best


func _target_score(u: Unit, o: Unit, current: Unit, shooter: bool, places: int) -> float:
	var score := u.pos.distance_to(o.pos)
	if o == current:
		score -= 1.5
	if o.id == u.attacker and t - u.hit_t < 3.0:
		score -= 3.0
	if not armed(o):
		score += 4.0
	if not shooter:
		var others := int(pressure.get(o.id, 0)) - (1 if o == current else 0)
		score += 1.2 * others + (4.0 if others >= places else 0.0)
	return score


func bow_range(u: Unit) -> float:
	return Defs.TOWER_BOW_RANGE if u.in_tower >= 0 else Defs.BOW_RANGE


## The way to the foe is shut: attack what shuts it, or find someone else.
func _go_through(u: Unit, foe: Unit, wall: Building, holding: bool) -> void:
	u.avoid_id = foe.id
	u.avoid_t = t + 4.0
	u.enemy = -1
	u.engaged = false
	u.scan_t = 0.0
	u.path_wait = 0.0
	u.anim = Anim.IDLE
	if not holding and wall and wall.faction != u.faction and dist_to_building(u.pos, wall) < 30.0:
		# Keep at the piece already being battered.
		var current := bld(u.enemy_bld)
		if current == null or current.dead:
			u.enemy_bld = wall.id


## The spot outside the footprint nearest the attacker, so nobody walks round a wall to hit it.
func _nearest_edge(u: Unit, b: Building, pad: float) -> Vector2:
	var local := (u.pos - b.pos).rotated(-b.rot)
	var half := b.size * 0.5
	var edge := local.clamp(-half, half)
	var out := local - edge
	if out.length() < 0.01:
		out = Vector2(0, 1)
	var along := out.normalized().orthogonal() * (float(u.id % 5) - 2.0) * 0.3
	return b.pos + (edge + out.normalized() * pad + along).rotated(b.rot)


# --- Blows ------------------------------------------------------------------------

func _begin_swing(u: Unit, target: int, building: int) -> void:
	var rate: float = weapon_def(u)["rate"]
	u.cooldown = rate
	u.swing_tgt = target
	u.swing_bld = building
	u.swing_start = t
	u.swing_hit = t + float(melee_def(u)["wind"])
	u.swing_end = t + rate
	u.swing_live = true


func cancel_swing(u: Unit) -> void:
	if u.swing_live:
		u.swing_live = false
		u.swing_end = minf(u.swing_end, t)


func _swinging(u: Unit) -> bool:
	if u.swing_live:
		u.anim = Anim.MELEE
		var tgt := unit(u.swing_tgt)
		if tgt and not tgt.dead:
			face(u, tgt.pos)
		if t + EPS >= u.swing_hit:
			u.swing_live = false
			strikes.append(u)
		return true
	if u.swing_start >= 0.0 and t + EPS < u.swing_hit + RECOVER and t < u.swing_end:
		u.anim = Anim.MELEE
		return true
	return false


## All of a tick's blows land together, so whoever updates first gains nothing.
func resolve_strikes() -> void:
	var landed := []
	for u: Unit in strikes:
		if u.dead:
			continue
		var b := bld(u.swing_bld)
		if b:
			if not b.dead:
				landed.append([u, null, b])
			continue
		var tgt := unit(u.swing_tgt)
		if tgt and is_hostile(u.faction, tgt) and u.pos.distance_to(tgt.pos) <= stand_distance(u, tgt) + HIT_MARGIN and melee_cover(u, tgt) == null:
			landed.append([u, tgt, null])
	strikes.clear()
	for hit in landed:
		var u: Unit = hit[0]
		if hit[1]:
			_land_blow(u, hit[1], 1.0)
		else:
			_hit_building(u, hit[2])


func _faces(u: Unit, p: Vector2) -> bool:
	var to := p - u.pos
	return to.length() < 0.01 or Vector2(sin(u.facing), cos(u.facing)).dot(to.normalized()) > 0.25


func _stagger(u: Unit, seconds: float) -> void:
	if u.kind in ["cannon", "ram"] or (u.kind == "commander" and u.task == "player"):
		return
	cancel_swing(u)
	strikes.erase(u)
	u.stun_t = maxf(u.stun_t, t + seconds)


func _knock(u: Unit, by: Vector2) -> void:
	if u.dead or u.kind in ["cannon", "ram"]:
		return
	var p := u.pos + by
	if not solid_for(u.faction, cell_of(p)):
		u.pos = p


# --- The player's own fighting ----------------------------------------------------
# `now` is the player's clock, up to one tick ahead of t, so blows land on the frame
# their animation connects.

func commander_swing(faction: int, now: float) -> bool:
	var u := unit(fac(faction).commander)
	if u == null or u.dead or now + EPS < u.swing_end:
		return false
	var rate: float = weapon_def(u)["rate"]
	if u.blocking:
		u.blocking = false
		u.guard_down_t = now
	u.swing_tgt = -1
	u.swing_bld = -1
	u.swing_start = now
	u.swing_hit = now + float(melee_def(u)["quick"])
	u.swing_end = now + rate * Defs.COMMANDER_SWING
	u.swing_live = true
	sound("swing", u.pos)
	return true


func commander_update(faction: int, now: float) -> void:
	var u := unit(fac(faction).commander)
	if u == null or u.dead or not u.swing_live or now + EPS < u.swing_hit:
		return
	u.swing_live = false
	var found := commander_targets(u)
	for i in found.size():
		var tgt: Unit = found[i]
		var away := (tgt.pos - u.pos).normalized()
		_land_blow(u, tgt, 1.0 if i == 0 else Defs.CLEAVE_SHARE)
		if not tgt.dead:
			_knock(tgt, away * 0.3)
			if u.weapon == "club":
				_stagger(tgt, Defs.CLUB_STAGGER)
	if found.is_empty():
		var b := _commander_building(u)
		if b:
			_hit_building(u, b)


## Who the commander's blow would hit right now, best first. A sword takes two.
func commander_targets(u: Unit) -> Array:
	var fam := melee_def(u)
	var reach: float = float(weapon_def(u)["reach"]) + 0.6 + (0.5 if u.mounted else 0.0)
	var arc: float = fam["arc"]
	var fwd := Vector2(sin(u.facing), cos(u.facing))
	var scored := []
	for o: Unit in units_near(u.pos, reach + 1.5, -2):
		if o.id == u.id or o.faction == u.faction or o.stable >= 0:
			continue
		var to := o.pos - u.pos
		var d := to.length()
		var r := Crowd.radius(o)
		if d > reach + r - 0.4:
			continue
		var ahead := fwd.dot(to)
		var angle := absf(fwd.angle_to(to)) if d > 0.05 else 0.0
		# In the arc, under the crosshair, or right on top of you.
		if angle > arc and not (ahead > 0.0 and (absf(fwd.cross(to)) < r + 0.2 or d < 1.0)):
			continue
		scored.append([angle + d * 0.12 + (2.0 if o.faction < 0 else 0.0), o])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var most := int(fam.get("cleave", 1))
	var out := []
	for e in scored:
		if melee_cover(u, e[1]) == null:
			out.append(e[1])
			if out.size() >= most:
				break
	return out


func _commander_building(u: Unit) -> Building:
	var reach: float = float(weapon_def(u)["reach"]) + 0.8
	var hit := first_building(u.pos, u.pos + Vector2(sin(u.facing), cos(u.facing)) * reach)
	if hit.is_empty() or hit[0].faction == u.faction:
		return null
	return hit[0]


func commander_block(faction: int, on: bool, now: float) -> void:
	var u := unit(fac(faction).commander)
	if u == null or u.dead:
		return
	if u.swing_live:
		on = false
	if on == u.blocking:
		return
	u.blocking = on
	if on:
		u.guard_up_t = now if now - u.guard_down_t >= PARRY_REARM else -99.0
	else:
		u.guard_down_t = now


## True when a click should fight and not pick a villager.
func commander_engaged(faction: int) -> bool:
	var u := unit(fac(faction).commander)
	if u == null or u.dead:
		return false
	if t - u.hit_t < 3.0:
		return true
	for o: Unit in units_near(u.pos, 8.0, -3, faction):
		if is_hostile(faction, o):
			return true
	return false


func commander_aims_at_foe(faction: int) -> bool:
	var u := unit(fac(faction).commander)
	if u == null or u.dead:
		return false
	var fwd := Vector2(sin(u.facing), cos(u.facing))
	for o: Unit in units_near(u.pos, Defs.BOW_RANGE, -3, faction):
		if is_hostile(faction, o) and absf(fwd.angle_to(o.pos - u.pos)) < 0.22:
			return true
	return false


# --- Cover ------------------------------------------------------------------------

## The enemy wall across the line from `from` to `to`, or null.
func wall_between(faction: int, from: Vector2, to: Vector2) -> Building:
	var out: Building = null
	var best := 2.0
	var mid := (from + to) * 0.5
	var half := from.distance_to(to) * 0.5
	for b: Building in buildings:
		if b.dead or not b.blocking or b.faction == faction or b.faction < 0:
			continue
		var r := half + b.size.length() * 0.5
		if b.pos.distance_squared_to(mid) > r * r or not Defs.BUILDINGS[b.type].get("wall", false):
			continue
		var k := footprint_entry(b, from, to)
		if k >= 0.0 and k < best:
			best = k
			out = b
	return out


## The wall an attacking crew has come up against, looked for once a second.
func wall_ahead(c: Crew, center: Vector2, target: Vector2) -> Building:
	if t - c.wall_t >= 1.0:
		c.wall_t = t
		var hit := wall_between(c.faction, center, target)
		var near := hit != null and dist_to_building(center, hit) < 30.0 + c.depth
		c.wall = hit.id if near else -1
	var b := bld(c.wall)
	return b if b and not b.dead else null


func cover_height(b: Building) -> float:
	var d: Dictionary = Defs.BUILDINGS[b.type]
	return float(d["height"]) if d.has("height") else float(LOW_COVER.get(b.type, 3.5))


## Where a segment enters a building's footprint (0..1), or -1.
func footprint_entry(b: Building, from: Vector2, to: Vector2) -> float:
	var a := (from - b.pos).rotated(-b.rot)
	var d := (to - from).rotated(-b.rot)
	var half := b.size * 0.5
	if absf(a.x) < half.x and absf(a.y) < half.y:
		return -1.0                   # standing in it, as a tower archer does
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if absf(d[axis]) < 0.0001:
			if absf(a[axis]) > half[axis]:
				return -1.0
			continue
		var k0 := (-half[axis] - a[axis]) / d[axis]
		var k1 := (half[axis] - a[axis]) / d[axis]
		enter = maxf(enter, minf(k0, k1))
		leave = minf(leave, maxf(k0, k1))
		if enter > leave:
			return -1.0
	return enter


## The first solid building on the segment as [building, fraction], or [].
func first_building(from: Vector2, to: Vector2) -> Array:
	var out := []
	var best := 2.0
	var mid := (from + to) * 0.5
	var half := from.distance_to(to) * 0.5
	for b: Building in buildings:
		if b.dead or not b.blocking:
			continue
		var r := half + b.size.length() * 0.5
		if b.pos.distance_squared_to(mid) > r * r:
			continue
		var k := footprint_entry(b, from, to)
		if k >= 0.0 and k < best:
			best = k
			out = [b, k]
	return out


## The building between two fighters, or null.
func melee_cover(u: Unit, foe: Unit) -> Building:
	# The path grid rules out nearly every pair cheaply.
	if line_clear(u.faction, u.pos, foe.pos) and line_clear(foe.faction, u.pos, foe.pos):
		return null
	var hit := first_building(u.pos, foe.pos)
	if hit.is_empty() or cover_height(hit[0]) < 1.0:
		return null
	return hit[0]


# --- Projectiles ------------------------------------------------------------------


func _muzzle(shooter: Unit) -> Vector3:
	var lift := 5.5 if shooter.in_tower >= 0 else (2.2 if shooter.mounted else 1.5)
	return Vector3(shooter.pos.x, _height(shooter.pos) + lift, shooter.pos.y)


## The flattest arc that clears what's in between, or -1 when the target is in cover.
func arrow_arc(shooter: Unit, target: Unit) -> float:
	var from := _muzzle(shooter)
	var to := Vector3(target.pos.x, _height(target.pos) + 1.1, target.pos.y)
	var span := from.distance_to(to)
	var in_path := []
	var mid := (shooter.pos + target.pos) * 0.5
	var half := shooter.pos.distance_to(target.pos) * 0.5
	for b: Building in buildings:
		if b.dead or not b.blocking:
			continue
		var r := half + b.size.length() * 0.5
		if b.pos.distance_squared_to(mid) > r * r:
			continue
		# Your own wall has loopholes for whoever stands at it.
		if b.faction == shooter.faction and dist_to_building(shooter.pos, b) < 6.0:
			continue
		var k := footprint_entry(b, shooter.pos, target.pos)
		if k >= 0.0:
			in_path.append([from.lerp(to, k).y, 4.0 * k * (1.0 - k) * span, _height(b.pos) + cover_height(b)])
	for arc: float in [ARROW_FLAT, ARROW_LOB]:
		var clear := true
		for e in in_path:
			if float(e[0]) + float(e[1]) * arc < float(e[2]):
				clear = false
				break
		if clear:
			return arc
	return -1.0


# Implemented by the combat layer (match_combat.gd).
func armed(_u: Unit) -> bool:
	return false


func weapon_def(_u: Unit) -> Dictionary:
	return Defs.FISTS


func _height(_p: Vector2) -> float:
	return 0.0


func _land_blow(_u: Unit, _tgt: Unit, _share: float) -> void:
	pass


func _hit_building(_u: Unit, _b: Building) -> void:
	pass
