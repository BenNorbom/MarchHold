extends RefCounted
## A sparring partner for training the rival: it plays the way a quick human does. A village
## captain runs its economy, while it hurries a stable and an armory, tames horses, makes
## spears and sends mounted spearmen at the enemy camp, then keeps sending waves.
## It uses the same command interface as the player.

const Defs = preload("res://scripts/data/defs.gd")
const Planner = preload("res://scripts/ai/planner.gd")

var m
var fid := 0
var riders := 8             # the size of a wave
var first_wave := 480.0     # seconds: the earliest the first wave leaves
var wave_gap := 150.0
var foot := false           # true: rush on foot with spears, no stable
var think_t := 0.0
var next_wave := 0.0
var waves := 0
var rng := RandomNumberGenerator.new()


func setup(match_ref, opts: Dictionary) -> void:
	m = match_ref
	fid = int(opts.get("faction", 0))
	riders = int(opts.get("riders", riders))
	first_wave = float(opts.get("first_wave", first_wave))
	foot = bool(opts.get("foot", false))
	rng.seed = int(opts.get("seed", 1))
	next_wave = first_wave


func step(action: String, subject: String = "", amount: int = 0, where: String = "", count: int = 0) -> Dictionary:
	return {"action": action, "subject": subject, "count": count, "amount": amount, "where": where}


func update(dt: float) -> void:
	think_t -= dt
	if think_t > 0.0 or m.over:
		return
	think_t = 1.0
	var f = m.fac(fid)
	var home: Vector2 = m.home_pos(fid)
	if m.village_post(fid) == null:
		var anyone: Array = m.idle_adults(fid, home)
		if not anyone.is_empty():
			m.command(fid, {"unit": anyone[0].id, "individual": true, "steps": [step("mandate", "village")]})
		return
	_build_first(f, home)
	if not foot and m.has_building(fid, "stable") and f.horses < riders and not _crew_doing("tame"):
		var hands: Array = m.idle_adults(fid, home)
		var p = m.village_post(fid)
		var pick: Array = m.post_members(p).filter(func(u): return u.id != p.captain and not u.child and not m.under_direct_order(u)).slice(0, 2)
		if pick.size() == 2:
			m.command(fid, {"units": pick.map(func(u): return u.id), "steps": [step("tame", "horses", riders)]})
	if m.has_building(fid, "armory") and _spears(f) < riders:
		m.command(fid, {"steps": [step("craft", "wood_spear", riders - _spears(f))]})
	if m.t >= next_wave and _spears(f) >= riders and (foot or f.horses >= riders):
		var p = m.village_post(fid)
		var men: Array = m.post_members(p).filter(func(u): return u.id != p.captain and not u.child and not m.under_direct_order(u)).slice(0, riders)
		if men.size() >= riders:
			var plan := [step("arm", "wood_spear"), step("attack", "", 0, "enemy")]
			if not foot:
				plan.push_front(step("mount"))
			var r: Dictionary = m.command(fid, {"units": men.map(func(u): return u.id), "steps": plan})
			if r.get("ok", false):
				waves += 1
				next_wave = m.t + wave_gap


func _spears(f) -> int:
	var n := int(f.gear.get("wood_spear", 0))
	for b in m.buildings_of(fid, "armory"):
		n += b.queue.count("wood_spear")
	return n


func _crew_doing(action: String) -> bool:
	for c in m.crews_of(fid):
		if c.idx < c.steps.size() and c.steps[c.idx]["action"] == action and c.post < 0:
			return true
	return false


## The quarry for the Stone age, then a stable and an armory, before the captain would.
func _build_first(f, home: Vector2) -> void:
	var order: Array = ["armory"] if foot else ["quarry", "armory", "stable"]
	for type in order:
		if not m.buildings_of(fid, type, false).is_empty():
			continue
		if m.unlock_problem(fid, type) != "" or not m.can_afford(fid, Defs.BUILDINGS[type]["cost"]):
			return
		var toward: Vector2 = (Vector2(m.map_size, m.map_size) * 0.5 - home).normalized()
		var spot = Planner.find_site(m, fid, type, home, toward, rng, false)
		if spot == null:
			return
		var site: Dictionary = m.place_site(fid, type, spot[0], spot[1])
		if not site.get("ok", false):
			return
		var p = m.village_post(fid)
		var hands: Array = m.post_members(p).filter(func(u): return u.id != p.captain and not u.child and not m.under_direct_order(u)).slice(0, 3)
		var build := step("build", type)
		build["sites"] = [site["id"]]
		if hands.is_empty() or not m.command(fid, {"units": hands.map(func(u): return u.id), "steps": [build]}).get("ok", false):
			m.remove_site(site["id"])
		return
