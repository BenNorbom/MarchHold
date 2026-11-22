extends RefCounted
## A captain's judgement under threat, from what the post itself can see:
## shelter civilians, arm militia in proportion, fight inside the post, hold or
## fall back by posture, then stand down. Never attacks.

const Defs = preload("res://scripts/data/defs.gd")
const Planner = preload("res://scripts/ai/planner.gd")

const LOOKOUT := 25.0          # how far past the post's edge counts as a threat to it
const WATCHED := 90.0          # a wide post still only defends this far from its center
const RAID := 3                # fewer than this is a job for whoever is armed already
const OUTNUMBERED := 2.0
const ARMORY_NEAR := 90.0      # militia only arm at an armory this close
const QUIET := 45.0            # seconds unseen before standing down
const QUIET_AWAY := 90.0       # longer after falling back, when the post can't see
const ENGINE_WEIGHT := 3


static func update(m, p) -> void:
	var foes := sighted(m, p)
	var weight := 0
	var at := Vector2.ZERO
	for o in foes:
		weight += ENGINE_WEIGHT if o.kind in ["cannon", "ram"] else 1
		at += o.pos
	if foes.is_empty():
		if p.alert == "":
			return
		if m.t - p.alert_t >= (QUIET_AWAY if p.alert == "falling_back" else QUIET):
			_stand_down(m, p)
		return
	p.alert_t = m.t
	p.threat_at = at / foes.size()
	var was: String = p.alert
	if was == "":
		p.threat = 0
		p.lost_at_alert = p.lost
	p.threat = maxi(p.threat, weight)
	if was == "falling_back":
		return
	var now := "raid" if p.threat >= RAID else "intruder"
	if now == "raid" and p.posture == "fall_back" and _has_refuge(m, p) and weight >= OUTNUMBERED * maxi(1, strength(m, p)):
		now = "falling_back"
		p.refuge = refuge(m, p)
	p.alert = now
	if now in ["raid", "falling_back"] and not was in ["raid", "falling_back"]:
		var doing := "We're falling back." if now == "falling_back" else ("We're holding." if p.posture == "hold" else "We're standing to.")
		_report(m, p, "sighted %s to the %s. %s" % [m._estimate(foes), m.Terrain.compass_name(p.threat_at - p.center), doing], "alarm")
		if p.faction == 0:
			m.sound("horn", p.center, 0)
	elif now == "falling_back" and was != "falling_back":
		_report(m, p, "there are too many of them. We're falling back.", "alarm")


## Armed enemies near the post that one of its people or buildings can see.
static func sighted(m, p) -> Array:
	var reach: float = minf(p.radius, WATCHED) + LOOKOUT
	var around: Vector2 = p.center
	var out := []
	var near: Array = m.units_near(around, reach, -3, p.faction)
	if p.alert == "falling_back":
		# On the way out they still see who follows them.
		var lead = m.unit(p.captain)
		if lead:
			near.append_array(m.units_near(lead.pos, Defs.VILLAGER["sight"], -3, p.faction))
	for o in near:
		if o.stable >= 0 or out.has(o) or not (m.armed(o) or o.kind in ["cannon", "ram"]):
			continue
		if _in_sight(m, p, o.pos):
			out.append(o)
	return out


static func _in_sight(m, p, at: Vector2) -> bool:
	for u in m.units_near(at, Defs.VILLAGER["sight"], p.faction):
		if u.post == p.id:
			return true
	for b in m.buildings:
		if b.dead or not b.complete or b.faction != p.faction or b.pos.distance_to(p.center) > p.radius:
			continue
		if b.pos.distance_to(at) <= float(Defs.BUILDINGS[b.type].get("sight", 18.0)):
			return true
	return false


static func _defenders(m, p) -> Array:
	return m.post_members(p).filter(func(u): return not u.child and u.siege < 0 and not m.under_direct_order(u))


## Who could fight: those armed, and those who could arm here in time.
static func strength(m, p) -> int:
	var people := _defenders(m, p)
	var ready := people.filter(func(u): return m.armed(u)).size()
	return ready + mini(people.size() - ready, _militia_gear(m, p))


static func _militia_gear(m, p) -> int:
	var armory = m.nearest_building(p.faction, p.center, ["armory"])
	if armory == null or armory.pos.distance_to(p.center) > ARMORY_NEAR:
		return 0
	var n := 0
	var gear: Dictionary = m.fac(p.faction).gear
	for id in gear:
		if Defs.ITEMS[id]["slot"] in ["weapon", "bow"]:
			n += int(gear[id])
	return n


static func refuge(m, p) -> Vector2:
	var village = m.village_post(p.faction)
	return village.center if village and village.id != p.id else m.home_pos(p.faction)


static func _has_refuge(m, p) -> bool:
	return p.mandate != "village" and p.center.distance_to(refuge(m, p)) > Defs.HOME_GROUND


## Whether the alert takes everyone off their usual work.
static func all_hands(p) -> bool:
	return p.alert in ["raid", "falling_back"]


## The jobs while there's a raid, in the form captains.gd hands out.
static func jobs(m, p, workers: Array) -> Array:
	var out := []
	if p.alert == "falling_back":
		out.append(_job("retreat", "hold", workers.size(), p.refuge))
		return out
	var fighters := workers.filter(func(u): return m.armed(u)).size()
	var bare := workers.size() - fighters
	var call_up := mini(mini(bare, _militia_gear(m, p)), Planner.militia_wanted(workers.size(), fighters, p.threat))
	# The cap is on everyone armed, or call-ups stack while the first lot are still arming.
	call_up = maxi(0, mini(call_up, p.threat * 2 + 2 - fighters))
	if call_up > 0:
		out.append(_job("arm", "arm", call_up, p.center))
	if fighters > 0:
		var reach := minf(p.radius, WATCHED)
		var toward: Vector2 = p.threat_at - p.center
		# Stand between the threat and the people, not out where it was seen.
		var line: Vector2 = p.center + toward.limit_length(minf(toward.length() * 0.6, reach * 0.5))
		out.append(_job("defend", "guard", fighters, line))
	if bare - call_up > 0:
		out.append(_job("shelter", "hold", bare - call_up, p.center))
	return out


static func _job(role: String, action: String, n: int, at: Vector2) -> Dictionary:
	return {"role": role, "n": n, "at": at,
		"step": {"action": action, "subject": "", "count": 0, "amount": 0, "where": ""}}


static func _stand_down(m, p) -> void:
	var had: String = p.alert
	p.alert = ""
	p.threat = 0
	if had == "intruder":
		return
	var lost: int = p.lost - p.lost_at_alert
	var text := "it's quiet now. We're %s" % ("going back to our post" if had == "falling_back" else "back to work")
	_report(m, p, text + (". We lost %d." % lost if lost > 0 else "."), "report")


static func _report(m, p, text: String, kind: String) -> void:
	if p.faction == 0:
		m.post(0, "%s: %s" % [m.post_label(p), text], kind)
