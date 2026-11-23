extends RefCounted
## Judgement shared by the rival and by captains: how many people each job needs,
## where things can go, and how big a threat is. It decides and never acts.
## Callers still go through Match.command and Match.place_site.

const Defs = preload("res://scripts/data/defs.gd")

const FARMERS_PER_FARM := 2


# --- Staffing -----------------------------------------------------------------

static func food_workers(pop: int, food_state: int) -> int:
	var hungry := food_state <= 1
	return int(ceil(pop * (0.36 if hungry else 0.24))) + (2 if hungry else 1)


static func wood_workers(adults: int, age: int) -> int:
	return int(ceil(adults * (0.5 if age == 0 else 0.32)))


## People on stone, fewer while stone piles up beyond what is wanted and wood runs short.
static func stone_workers(adults: int, share: float = 0.12, stone: float = 0.0, wood: float = INF, wanted: float = 250.0) -> int:
	var n := int(ceil(adults * share))
	if stone >= wanted and stone > wood * 2.0:
		return mini(n, 1)
	if stone >= wanted * 0.6:
		return int(ceil(n * 0.5))
	return n


static func farms_wanted(pop: int) -> int:
	return int(ceil(pop * 0.24 / float(FARMERS_PER_FARM)))


static func food_source(m, _faction: int, center: Vector2, farms: int) -> String:
	if farms > 0:
		return "farm"
	if m.nearest_node("berry", center, 150.0) == null and nearby_deer(m, center) > 0:
		return "hunt"
	return "berries"


static func nearby_deer(m, center: Vector2) -> int:
	return m.units_near(center, 115.0, -1).filter(func(u): return u.kind == "deer").size()


# --- Sites --------------------------------------------------------------------

const LANE := 5.0               # added to a footprint, so people can walk between buildings


## Ground the faction has mapped.
static func known(m, faction: int, p: Vector2) -> bool:
	var f = m.fac(faction)
	var k: int = m.kcell(p)
	return f.knowledge[k] >= 0.0


static func _leaves_lane(m, faction: int, type: String, p: Vector2, rot: float) -> bool:
	var size: Vector2 = Defs.BUILDINGS[type]["size"]
	for b in m.buildings_of(faction, "", false):
		if b.pos.distance_to(p) < 40.0 and m._obb_overlap(p, rot, size, b.pos, b.rot, b.size, LANE):
			return false
	return true


## The nearest deposit without a mine. known_only leaves out ground this side hasn't seen.
static func find_deposit(m, faction: int, dep: String, center: Vector2, reach: float, known_only: bool, seen: Dictionary = {}):
	var best = null
	var bd := reach
	for n in m.terrain.deposits:
		if n.sub != dep:
			continue
		var d: float = n.pos.distance_to(center)
		if d >= bd or (known_only and not seen.has(n.id) and not known(m, faction, n.pos)):
			continue
		var taken := false
		for b in m.buildings:
			if not b.dead and b.type == "mine" and b.node == n.id:
				taken = true
				break
		if not taken:
			bd = d
			best = n
	return best


static func find_outcrop(m, faction: int, center: Vector2, reach: float, known_only: bool, seen: Dictionary = {}):
	var best = null
	var bd := reach
	for n in m.terrain.outcrops:
		var d: float = n.pos.distance_to(center)
		if d < bd and (not known_only or seen.has(n.id) or known(m, faction, n.pos)):
			bd = d
			best = n
	return best


## Where a structure can go around center, as [position, rotation], or null.
## front is the side watch posts and towers face. radius keeps it inside a captain's area.
## known_only is how captains look: known ground, plus resources in seen, with lanes left between buildings.
static func find_site(m, faction: int, type: String, center: Vector2, front: Vector2, rng: RandomNumberGenerator,
		known_only: bool, deposit: String = "", radius: float = INF, seen: Dictionary = {}):
	var facing := atan2(front.y, front.x)
	if type in ["mine", "quarry"]:
		var node
		var off := 7.0
		if type == "mine":
			node = find_deposit(m, faction, deposit, center, minf(330.0, radius), known_only, seen)
		else:
			off = 10.0
			node = find_outcrop(m, faction, center, minf(400.0, radius), known_only, seen)
		if node == null:
			return null
		var start_angle: float = (center - node.pos).angle() if type == "quarry" else 0.0
		for k in 16:
			var p: Vector2 = node.pos + Vector2.from_angle(start_angle + k * TAU / 16.0) * off
			if p.distance_to(center) > radius or (known_only and not _leaves_lane(m, faction, type, p, facing)):
				continue
			if m.site_problem(faction, type, p, facing) == "":
				return [p, facing]
		return null
	var r0 := 12.0
	var r1 := 42.0
	match type:
		"hut":
			r1 += maxi(0, m.buildings_of(faction, "hut", false).size() - 8) * 1.5
		"farm":
			r0 = 26.0
			r1 = 70.0
		"watch_post", "tower":
			r0 = 45.0
			r1 = 70.0
		"stockpile":
			r0 = 30.0
			r1 = 60.0
		"university", "stable", "smelter":
			r0 = 22.0
			r1 = 60.0
	r1 = minf(r1, radius)
	r0 = minf(r0, r1 * 0.75)
	for attempt in 60:
		var ang := rng.randf() * TAU
		if type in ["watch_post", "tower"]:
			ang = facing + rng.randf_range(-0.7, 0.7)
		var out := r1
		if known_only and attempt >= 20:
			# The middle is full, so look further out, as far as the area goes.
			out = minf(radius, r1 * (1.5 if attempt < 40 else 2.2))
		var p := center + Vector2.from_angle(ang) * rng.randf_range(r0, out)
		if known_only and not known(m, faction, p):
			continue
		var rot := ang + PI * 0.5
		var clearance: float = 7.0 + (Defs.BUILDINGS[type]["size"] as Vector2).length() * 0.5
		if m.nearest_node("rock", p, clearance, func(n): return n.sub == "outcrop") != null:
			continue
		if m.site_problem(faction, type, p, rot) == "" and (not known_only or _leaves_lane(m, faction, type, p, rot)):
			return [p, rot]
	return null


## The woodcutters' trees near center: the middle of the nearest few, or null.
static func tree_line(m, center: Vector2):
	var picked := {}
	var sum := Vector2.ZERO
	for i in 6:
		var n = m.nearest_node("tree", center, 110.0, func(nd): return not picked.has(nd.id))
		if n == null:
			break
		picked[n.id] = true
		sum += n.pos
	return null if picked.is_empty() else sum / picked.size()


## A drop-off beside those trees, on the camp's side of them: [position, rotation], or null.
## Woodcutters walking 50 m to the campfire cut about a third as much as ones with a stockpile at hand.
static func tree_stockpile_site(m, faction: int, center: Vector2):
	var trees = tree_line(m, center)
	if trees == null:
		return null
	var toward: Vector2 = (center - trees).normalized()
	for r in [5.0, 8.0, 11.0, 14.0]:
		for k in 12:
			var p: Vector2 = trees + toward.rotated(k * TAU / 12.0) * r
			if m.site_problem(faction, "stockpile", p, 0.0) == "":
				return [p, 0.0]
	return null


## Whether the trees near center are a long walk from every drop-off.
static func wood_haul_long(m, faction: int, center: Vector2) -> bool:
	var trees = tree_line(m, center)
	if trees == null:
		return false
	var drop = m.nearest_building(faction, trees, ["campfire", "stockpile"], false)
	return drop == null or drop.pos.distance_to(trees) > 25.0


# --- Defence ------------------------------------------------------------------

static func post_can_see(m, p, at: Vector2) -> bool:
	for u in m.units_near(at, Defs.VILLAGER["sight"], p.faction):
		if u.post == p.id:
			return true
	for b in m.buildings:
		if b.dead or not b.complete or b.faction != p.faction or b.pos.distance_to(p.center) > p.radius:
			continue
		if b.pos.distance_to(at) <= float(Defs.BUILDINGS[b.type].get("sight", 18.0)):
			return true
	return false


## Enemies this side saw within radius of center in the last few seconds.
static func threat(m, faction: int, center: Vector2, radius: float) -> int:
	var seen := 0
	var intel: Dictionary = m.fac(faction).intel
	for key in intel:
		var e: Dictionary = intel[key]
		if e.get("kind", "") == "units" and m.t - float(e["t"]) < 6.0 and (e["pos"] as Vector2).distance_to(center) < radius:
			seen += int(e["total"])
	return seen


## How many to arm. A lone scout isn't a raid.
static func militia_wanted(adults: int, guards: int, seen: int) -> int:
	if seen < 3 or guards >= seen + 2:
		return 0
	return maxi(0, mini(adults - guards, seen * 2 + 2))
