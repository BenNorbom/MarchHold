extends RefCounted
## A rival commander (one per AI settlement): a utility AI with build-order templates. It plays through the
## same validated command interface as the player and only knows what its own
## scouts, buildings and commander have seen.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Planner = preload("res://scripts/ai/planner.gd")

const FOOD_HEADROOM := 75.0   # storage kept beyond what "well fed" needs
const STRATEGIES := ["rush", "boom", "turtle", "cavalry", "cannons"]
# What each difficulty changes. None of them cheat: they see, pay and build like the player.
# think: seconds between decisions. scout: when the first scout leaves. watch/posts: when and how many
# watch posts face the enemy. alarm: how far from home an enemy counts as a raid. react: how big
# a raid (riders count double) calls out the militia. ready: weapons kept in the armory for it,
# plus one per `ready_per` adults. wall: when a palisade goes round the camp (sooner if riders are
# seen). attack/army/gap: how soon, how big, and how often the attacks are.
const LEVELS := [
	{"think": 2.5, "scout": 200.0, "watch": 360.0, "posts": 1, "alarm": 90.0, "react": 4, "ready": 3, "ready_per": 14,
		"wall": INF, "attack": 1.45, "army": 0.7, "gap": 420.0, "recall": 20.0},
	{"think": 1.4, "scout": 110.0, "watch": 220.0, "posts": 1, "alarm": 110.0, "react": 3, "ready": 5, "ready_per": 10,
		"wall": 900.0, "attack": 1.0, "army": 1.0, "gap": 300.0, "recall": 14.0},
	{"think": 0.6, "scout": 60.0, "watch": 130.0, "posts": 2, "alarm": 140.0, "react": 2, "ready": 8, "ready_per": 7,
		"wall": 480.0, "attack": 0.75, "army": 1.35, "gap": 200.0, "recall": 8.0},
]

var m                       # the Match
var fid := 1
var strategy := "boom"
var difficulty := 1         # 0 easy, 1 normal, 2 hard
var passive := false        # tutorial: never attacks on its own
var calm_until := 0.0
var max_pop := 200
var think_t := 0.0
var roles := {}             # role -> crew id
var next_attack := 0.0
var attacks := 0
var last_scout := -999.0
var wall_started := false
var last_alarm := -999.0
var rng := RandomNumberGenerator.new()
var lv: Dictionary = LEVELS[1]
var riders_seen_t := -INF   # when this side last saw enemy riders, or an enemy stable
var raided_t := -INF        # when a raid last reached home
var rearm_t := -INF


func setup(match_ref, opts: Dictionary) -> void:
	m = match_ref
	fid = int(opts.get("faction", 1))
	difficulty = clampi(int(opts.get("difficulty", 1)), 0, LEVELS.size() - 1)
	lv = LEVELS[difficulty]
	strategy = opts.get("strategy", "random")
	rng.seed = int(opts.get("seed", 1)) * 31 + fid
	if strategy == "random" or not strategy in STRATEGIES:
		strategy = STRATEGIES[rng.randi_range(0, STRATEGIES.size() - 1)]
	passive = bool(opts.get("passive", false))
	calm_until = 600.0 if opts.get("calm_start", false) else 0.0
	max_pop = int(opts.get("max_pop", 200))
	next_attack = _first_attack_time()
	if m.factions.size() > 2:
		# Seven rivals thinking on the same tick would be a spike.
		think_t = fid * 0.17


func _first_attack_time() -> float:
	var base: float = {"rush": 230.0, "boom": 840.0, "turtle": 1320.0, "cavalry": 780.0, "cannons": 1560.0}[strategy]
	return base * float(lv["attack"])


func update(dt: float) -> void:
	think_t -= dt
	if think_t > 0.0 or m.over:
		return
	think_t = float(lv["think"])
	var f = m.fac(fid)
	if m.home_of(fid) == null:
		return
	_defend(f)
	_economy(f)
	_construction(f)
	_military(f)
	_scouting(f)


# --- Helpers --------------------------------------------------------------------

func _crew(role: String):
	var id: int = roles.get(role, -1)
	var c = m.crews.get(id)
	if c == null or c.members.is_empty():
		roles.erase(role)
		return null
	return c


func _busy(role: String) -> bool:
	var c = _crew(role)
	return c != null and c.idx < c.steps.size()


func _order(role: String, steps: Array, count: int) -> bool:
	var req := {"steps": steps}
	var c = _crew(role)
	if c:
		req["crew"] = c.id
		if count > 0:
			steps[0]["count"] = count
	else:
		steps[0]["count"] = maxi(count, 1)
	var res: Dictionary = m.command(fid, req)
	if res.get("ok", false):
		# Weapons go straight into an armory's queue, so there may be no crew to remember.
		var made: Array = res.get("crews", [])
		if not made.is_empty():
			roles[role] = made[0]
		return true
	return false


func _step(action: String, subject: String = "", amount: int = 0, where: String = "", count: int = 0) -> Dictionary:
	return {"action": action, "subject": subject, "count": count, "amount": amount, "where": where}


func _size(role: String) -> int:
	var c = _crew(role)
	return c.members.size() if c else 0


func _count(type: String, include_sites: bool = true) -> int:
	var n := 0
	for b in m.buildings:
		if not b.dead and b.faction == fid and b.type == type and (include_sites or b.complete):
			n += 1
	return n


func _home() -> Vector2:
	return m.home_pos(fid)


func _toward_enemy() -> Vector2:
	var e = m.known_enemy_camp(fid)
	if e != null:
		return ((e as Vector2) - _home()).normalized()
	var c := Vector2(m.map_size, m.map_size) * 0.5
	return (c - _home()).normalized()


# --- Economy -------------------------------------------------------------------

func _economy(f) -> void:
	var adults: int = f.adults
	if adults <= 0:
		return
	var food_need := Planner.food_workers(f.pop, f.food_state)
	var wood_need := Planner.wood_workers(adults, f.age)
	var stone_need := 0
	if f.age >= 1 or m.has_building(fid, "quarry"):
		stone_need = Planner.stone_workers(adults, 0.26 if strategy == "turtle" else 0.2, float(f.stock.get("stone", 0)), float(f.stock.get("wood", 0)),
			450.0 if strategy == "turtle" or f.age >= 2 else 250.0)
	elif _count("quarry", true) == 0 and m.t > 150.0 and strategy != "rush":
		stone_need = 1
	# With plenty of food in store, two pickers will do and wood gets every idle hand.
	var food_comfy: bool = f.food_state >= 3 and float(f.stock.get("food", 0)) > minf(f.pop * 4.0, 120.0)
	if food_comfy:
		food_need = mini(food_need, 2)
		_keep_gathering("wood", "wood", maxi(wood_need, _size("wood") + f.idle))
	# Food: berries first, then farms.
	var farms := _count("farm", false)
	var food_src := Planner.food_source(m, fid, _home(), farms)
	_keep_gathering("food", food_src, mini(food_need, farms * 2) if food_src == "farm" else food_need)
	if food_src == "farm" and food_need > farms * 2:
		var extra := "berries" if m.nearest_node("berry", _home(), 160.0) != null else ""
		if extra != "":
			_keep_gathering("food2", extra, food_need - farms * 2)
	if not food_comfy:
		_keep_gathering("wood", "wood", wood_need)
	if stone_need > 0:
		_keep_gathering("stone", "stone", stone_need)
	if f.age >= 1:
		for dep in Defs.DEPOSITS:
			if _has_mine(dep) and (dep != "iron" or f.age >= 3):
				var want := 2 if dep != "iron" else 3
				if strategy in ["cannons", "turtle"] and dep != "bronze":
					want += 1
				_keep_gathering(dep, dep, want)


func _has_mine(dep: String) -> bool:
	for b in m.buildings:
		if not b.dead and b.faction == fid and b.type == "mine" and b.complete and b.deposit == dep:
			return true
	return false


func _keep_gathering(role: String, subject: String, want: int) -> void:
	if want <= 0:
		return
	var c = _crew(role)
	var cur := ""
	if c and c.idx < c.steps.size():
		cur = c.steps[c.idx]["subject"]
	if c == null or cur != subject or c.members.size() < want:
		if m.fac(fid).idle <= 0 and c != null and cur == subject:
			return
		_order(role, [_step("gather", subject)], want)


# --- Construction --------------------------------------------------------------

## The armory comes before anything but the housing that stops births.
func _saving_for_armory() -> bool:
	return _count("armory") == 0 and (strategy == "rush" or m.t > 100.0)


## Items of these slots waiting in the armory.
func _gear_count(f, slots: Array) -> int:
	var n := 0
	for k in f.gear:
		if Defs.ITEMS.has(k) and Defs.ITEMS[k]["slot"] in slots:
			n += int(f.gear[k])
	return n


## Wood held back from construction so the next batch of weapons can be made.
func _weapon_reserve(f) -> float:
	if _count("armory", false) == 0 or m.t < _army_start():
		return 0.0
	if f.soldiers + _gear_count(f, ["weapon", "bow"]) >= _army_want(f):
		return 0.0
	return float(Defs.item_cost(_basic_weapon(), maxi(0, m.armory_tier(fid))).get("wood", 0))


## Wood the next building is waiting for. Once the army has a core of weapons, construction comes first.
func _building_hold(f) -> float:
	if f.soldiers + _gear_count(f, ["weapon", "bow"]) < mini(_army_want(f), 5):
		return 0.0
	var want := _next_building(f)
	return float(Defs.BUILDINGS[want]["cost"].get("wood", 0)) if Defs.BUILDINGS.has(want) else 0.0


func _basic_weapon() -> String:
	return "wood_spear"


## Wood still owed for sites that are placed but not yet paid for. Builders pay when they start,
## so anything bought in the meantime would keep that site waiting.
func _unpaid_wood() -> float:
	var owed := 0.0
	for b in m.buildings:
		if not b.dead and b.faction == fid and not b.complete and not b.paid and not Defs.BUILDINGS[b.type].get("wall", false):
			owed += float(Defs.BUILDINGS[b.type]["cost"].get("wood", 0))
	return owed


## An unfinished structure of ours that no crew is building. Walls are left to their own crews.
func _orphan_site():
	var claimed := {}
	for c in m.crews.values():
		if c.faction == fid and c.idx < c.steps.size() and c.steps[c.idx]["action"] == "build":
			for id in c.state.get("sites", []):
				claimed[id] = true
	for b in m.buildings:
		if not b.dead and b.faction == fid and not b.complete and not claimed.has(b.id) and not Defs.BUILDINGS[b.type].get("wall", false):
			return b
	return null


## Births stop when housing runs out, so a hut is due once the free beds drop low enough.
func _housing_needed(f) -> bool:
	var lookahead: int = 0 if _saving_for_armory() else maxi(3, f.pop / 6)
	return f.housing < 200 and f.pop < max_pop and f.housing - f.pop <= lookahead and not _site_pending(["hut"])


func _construction(f) -> void:
	var slack: int = f.housing - f.pop
	if _housing_needed(f):
		var hrole := "build" if not _busy("build") else ("build2" if not _busy("build2") and f.adults >= 10 else "")
		if hrole != "":
			var reserve := 0.0 if slack <= 0 else _weapon_reserve(f)
			_place_and_build(f, hrole, "hut", reserve, slack <= 0)
			return
	# A site whose builders were killed would otherwise wait forever.
	var orphan = _orphan_site()
	if orphan != null:
		var orole := "build" if not _busy("build") else ("build2" if not _busy("build2") and f.adults >= 10 else "")
		if orole != "":
			var osteps := [_step("build", orphan.type)]
			osteps[0]["sites"] = [orphan.id]
			if _order(orole, osteps, 3 if f.adults > 8 else 2):
				return
	if _busy("build") and (_busy("build2") or f.adults < 16):
		return
	var want := _next_building(f)
	if want == "":
		return
	var role := "build" if not _busy("build") else "build2"
	if want == "palisade_ring" or want == "stone_ring":
		_build_wall(f, role, "palisade" if want == "palisade_ring" else "stone_wall")
		return
	if want.begins_with("upgrade:"):
		var b := want.substr(8)
		var up_id: String = m._upgrade_for(fid, b)
		if Defs.UPGRADES.has(up_id) and m.can_afford(fid, Defs.UPGRADES[up_id]["cost"]):
			_order(role, [_step("upgrade", b)], 3)
		return
	if want.begins_with("research:"):
		# Research needs no villagers: pay and it runs in the building.
		m.start_research(fid, want.substr(9))
		return
	# The armory and the quarry (the way to pikes and the Stone age) don't wait for spears.
	_place_and_build(f, role, want, 0.0 if want in ["armory", "quarry"] else _weapon_reserve(f))


func _place_and_build(f, role: String, want: String, reserve: float = 0.0, urgent: bool = false) -> void:
	# Don't tie up builders waiting for materials. Housing that is blocking births may jump the queue.
	var cost: Dictionary = Defs.BUILDINGS[want]["cost"]
	var held := 0.0 if urgent else reserve + _unpaid_wood()
	if not m.can_afford(fid, cost) or float(f.stock.get("wood", 0)) < float(cost.get("wood", 0)) + held:
		return
	var p = _find_site(want)
	if p == null:
		return
	var res: Dictionary = m.place_site(fid, want, p[0], p[1])
	if not res.get("ok", false):
		return
	var steps := [_step("build", want)]
	steps[0]["sites"] = [res["id"]]
	if not _order(role, steps, 3 if f.adults > 8 else 2):
		m.remove_site(res["id"])


func _next_building(f) -> String:
	var t: float = m.t
	var pop: int = f.pop
	var housing: int = f.housing
	var rush := strategy == "rush"
	# A drop-off beside the trees saves every woodcutter most of the walk.
	if _count("stockpile") == 0 and t > 45.0 and _tree_stockpile_site() != null:
		return "stockpile"
	if _count("armory") == 0 and (rush or t > 100.0 or float(f.stock.get("wood", 0)) > 70.0):
		return "armory"
	var farms_want := Planner.farms_wanted(pop)
	var farms_due: bool = t > 150.0 or m.nearest_node("berry", _home(), 150.0) == null
	# Two farms come first; the quarry (the way to the Stone age) goes before any more.
	if _count("farm") < mini(farms_want, 2) and farms_due:
		return "farm"
	if _count("quarry") == 0 and t > (230.0 if rush else 170.0):
		return "quarry"
	# Lookouts come after the quarry, so they don't hold back the Stone age.
	var posts_now := _count("watch_post")
	if posts_now < int(lv["posts"]) and t > float(lv["watch"]) + posts_now * 150.0:
		return "watch_post"
	if _count("farm") < farms_want and farms_due:
		return "farm"
	# A ring of palisade turns a raid of riders into a siege, and the militia has time to arm.
	var wall_due: bool = t > float(lv["wall"]) or (difficulty > 0 and t > 240.0 and (m.t - riders_seen_t < 600.0 or m.t - raided_t < 900.0))
	if not wall_started and wall_due and m.has_building(fid, "armory") and pop >= 12 and float(f.stock.get("wood", 0)) >= 260.0 and _ring_radius("palisade") > 0.0:
		return "palisade_ring"
	if f.age < 1:
		if strategy == "turtle" and not wall_started and m.has_building(fid, "armory") and t > 360.0 and pop >= 14 and float(f.stock.get("wood", 0)) >= 150.0:
			return "palisade_ring"
		return ""
	if _count("stockpile") == 0 and t > 240.0:
		return "stockpile"
	if pop > 35 and f.food_cap < pop * Defs.WELL_FED_STOCK + FOOD_HEADROOM and not _site_pending(["stockpile"]):
		return "stockpile"
	if strategy == "cavalry" and _count("stable") == 0:
		return "stable"
	for dep in ["bronze"]:
		if not _mine_site_exists(dep) and t > (330.0 if strategy != "rush" else 420.0) and _find_deposit(dep) != null:
			return "mine"
	if strategy == "turtle" and not wall_started and t > 420.0:
		return "stone_ring"
	if strategy == "turtle" and _count("tower") < 2 and t > 480.0:
		return "tower"
	if f.age >= 2:
		var arm = m.nearest_building(fid, _home(), ["armory"])
		if arm and m.research_problem(fid, "armory_bronze") == "":
			return "research:armory_bronze"
		if _count("stable") == 0:
			return "stable"
		if not _mine_site_exists("iron") and _find_deposit("iron") != null:
			return "mine"
		if m.research_problem(fid, "iron_mining") == "":
			return "research:iron_mining"
	if f.age >= 3:
		var arm2 = m.nearest_building(fid, _home(), ["armory"])
		if arm2 and m.research_problem(fid, "armory_iron") == "":
			return "research:armory_iron"
		if strategy in ["cannons", "turtle", "boom"] and _count("university") == 0:
			return "university"
		if m.research_problem(fid, "gunpowder") == "":
			return "research:gunpowder"
	if _count("farm") < farms_want + 1 and pop > 20:
		return "farm"
	if float(f.stock.get("wood", 0)) > 550.0 and _count("farm") < int(ceil(pop / 3.5)):
		return "farm"
	return ""


var _mine_dep := ""


func _mine_site_exists(dep: String) -> bool:
	for b in m.buildings:
		if not b.dead and b.faction == fid and b.type == "mine" and b.deposit == dep:
			return true
	return false


func _find_deposit(dep: String):
	_mine_dep = dep
	return Planner.find_deposit(m, fid, dep, _home(), 330.0, false)


func _site_pending(types: Array) -> bool:
	for b in m.buildings:
		if not b.dead and b.faction == fid and b.type in types and not b.complete:
			return true
	return false


## The first stockpile goes beside the trees the woodcutters are working, on the camp's side of them.
func _tree_stockpile_site():
	return Planner.tree_stockpile_site(m, fid, _home())


func _find_site(type: String):
	if type == "stockpile" and _count("stockpile") == 0:
		var spot = _tree_stockpile_site()
		if spot != null:
			return spot
	return Planner.find_site(m, fid, type, _home(), _toward_enemy(), rng, false, _mine_dep)


## The smallest ring round the camp that no building stands in the way of, or 0.
func _ring_radius(type: String) -> float:
	if ring_r.has(type) and m.t - float(ring_r[type][1]) < 30.0:
		return ring_r[type][0]
	var home := _home()
	var found := 0.0
	var start := 40.0 if type == "palisade" else 50.0
	var r := start
	while r <= 86.0 and found == 0.0:
		var n := ceili(TAU * r / float(Defs.BUILDINGS[type]["length"]))
		var blocked := 0
		for k in n:
			var a: Vector2 = home + Vector2.from_angle(k * TAU / n) * r
			var b: Vector2 = home + Vector2.from_angle((k + 1) * TAU / n) * r
			if m.site_problem(fid, type, (a + b) * 0.5, (b - a).angle(), Vector2(a.distance_to(b), Defs.BUILDINGS[type]["thick"])) != "":
				blocked += 1
				if blocked > 1:
					break
		if blocked <= 1:
			found = r
		r += 4.0
	ring_r[type] = [found, m.t]
	return found


var ring_r := {}


func _build_wall(f, role: String, type: String) -> void:
	wall_started = true
	var home := _home()
	var r := _ring_radius(type)
	if r <= 0.0:
		r = 46.0 if type == "palisade" else 56.0
	var pts := []
	var n := maxi(14, ceili(TAU * r / 16.0))
	var gate_k := int(round(fposmod(atan2(_toward_enemy().y, _toward_enemy().x), TAU) / TAU * n)) % n
	for k in n + 1:
		pts.append(home + Vector2.from_angle(k * TAU / n) * r)
	var res: Dictionary = m.place_wall(fid, type, pts)
	if not res.get("ok", false):
		return
	# Replace the piece facing the enemy with a gate.
	var ids: Array = res["ids"]
	var gate_type := "palisade_gate" if type == "palisade" else "stone_gate"
	var gate_at: Vector2 = home + Vector2.from_angle((gate_k + 0.5) * TAU / n) * r
	var best_id := -1
	var bd := INF
	for id in ids:
		var b = m.bld(id)
		if b and b.pos.distance_to(gate_at) < bd:
			bd = b.pos.distance_to(gate_at)
			best_id = id
	if best_id >= 0:
		var b = m.bld(best_id)
		var gp: Vector2 = b.pos
		var grot: float = b.rot
		m.remove_site(best_id)
		ids.erase(best_id)
		var g: Dictionary = m.place_site(fid, gate_type, gp, grot)
		if g.get("ok", false):
			ids.push_front(g["id"])
	var steps := [_step("build", type)]
	steps[0]["sites"] = ids
	if not _order(role, steps, 5):
		for id in ids:
			m.remove_site(id)
		wall_started = false


# --- Military ------------------------------------------------------------------

func _gear_plan(f) -> Array:
	var tier: int = m.armory_tier(fid)
	match strategy:
		"rush":
			return ["wood_spear"] if tier == 0 else (["bronze_sword", "bronze_shield"] if tier == 1 else ["iron_sword", "iron_shield"])
		"cavalry":
			if tier >= 1:
				return ["iron_lance" if tier >= 2 else "bronze_lance", "bronze_shield" if tier == 1 else "iron_shield"]
			return ["wood_spear", "bow"]
		"turtle":
			if tier >= 2:
				return ["iron_pike", "iron_sword", "iron_shield", "bow"]
			return ["wood_spear", "bow"]
		"cannons":
			if f.researched.has("gunpowder"):
				return ["cannon", "iron_pike", "iron_shield"]
			if tier >= 2:
				return ["iron_pike", "iron_sword", "iron_shield"]
	if tier >= 2:
		return ["iron_sword", "iron_shield", "iron_armor", "bow"]
	if tier == 1:
		return ["bronze_sword", "bronze_shield", "bronze_pike", "bronze_armor"]
	return ["wood_spear", "wood_shield", "bow"]


func _army_start() -> float:
	return {"rush": 100.0, "boom": 420.0, "turtle": 420.0, "cavalry": 420.0, "cannons": 600.0}[strategy] * [1.3, 1.0, 0.9][difficulty]


## How many soldiers to field now: the target, but never more than a share of the adults.
func _army_want(f) -> int:
	var cap_frac := 0.5 if strategy == "rush" else (0.3 if m.t < _army_start() + 300.0 else 0.42)
	return mini(_army_target(f), int(f.adults * cap_frac))


func _army_target(f) -> int:
	var base: int = {"rush": 7, "boom": 22, "turtle": 26, "cavalry": 12, "cannons": 18}[strategy]
	base = int(base * float(lv["army"]))
	return base + attacks * 4


func _military(f) -> void:
	if not m.has_building(fid, "armory"):
		return
	# Keep the armory busy, but only while the army still needs gear, and never at the cost of housing.
	if not _busy("craft"):
		var plan := _gear_plan(f)
		var item: String = plan[rng.randi_range(0, plan.size() - 1)]
		var weapons := _gear_count(f, ["weapon"]) + _queued(["weapon"])
		var needs_gear: bool = m.t >= _army_start() and (f.soldiers + _gear_count(f, ["weapon", "bow"]) < _army_want(f) or item in ["cannon", "ram"])
		# Always keep weapons for the militia: pikes once riders have been seen and the armory can make them.
		var reserve_short: bool = weapons < _ready_want(f)
		if reserve_short:
			item = _militia_item()
			needs_gear = true
		if m.craft_problem(fid, item) != "":
			item = _basic_weapon()
		var cost := Defs.item_cost(item, maxi(0, m.armory_tier(fid)))
		var hold := float(Defs.BUILDINGS["hut"]["cost"]["wood"]) if _housing_needed(f) else _building_hold(f)
		hold += _unpaid_wood()
		if reserve_short:
			# The militia's weapons come before new buildings; only housing that is stopping births comes first.
			hold = float(Defs.BUILDINGS["hut"]["cost"]["wood"]) if f.pop >= f.housing else 0.0
			# Nor the quarry, unless a raid is on: the Stone age is the way to pikes.
			if f.age == 0 and _count("quarry", false) == 0 and m.t > 230.0 and m.t - raided_t > 60.0:
				hold = maxf(hold, float(Defs.BUILDINGS["quarry"]["cost"]["wood"]))
			# A site already placed waits for its wood: spears mustn't take it first.
			hold = maxf(hold, _unpaid_wood()) if m.t - raided_t > 60.0 else hold
		var can_pay: bool = m.can_afford(fid, cost) and float(f.stock.get("wood", 0)) >= float(cost.get("wood", 0)) + hold
		# A couple waiting at a time: each is paid for as it starts, so a long queue would drain the stores.
		if needs_gear and can_pay and _queued_item(item) < 2 and m.craft_problem(fid, item) == "" and m.step_problem(fid, _step("craft", item)) == "":
			var stock := int(f.gear.get(item, 0))
			if item in ["ram", "cannon"]:
				stock = m.units.filter(func(u): return not u.dead and u.faction == fid and u.kind == item).size()
			if stock < (4 if item in ["ram", "cannon"] else 12):
				# One batch at a time: a second batch would spend wood the economy may need first.
				var batches := 2 if float(cost.get("wood", 0)) <= 10.0 else 1
				_order("craft", [_step("craft", item, int(Defs.ITEMS[item]["batch"]) * batches)], 2 if f.adults > 12 else 1)
	# Horses for cavalry.
	if m.has_building(fid, "stable") and f.horses < 6 and not _busy("tame") and strategy in ["cavalry", "boom", "cannons"]:
		_order("tame", [_step("tame", "horses", 3)], 2)
	# Siege is built and staffed from this settlement's own stores and people.
	for kind in ["ram", "cannon"]:
		if m.craft_problem(fid, kind) != "" or _queued_item(kind) > 0 or not m.can_afford(fid, Defs.ITEMS[kind].cost):
			continue
		if (m.options.get("mode") == "grand_army" or (f.adults >= 16 and f.food_state >= 2 and f.soldiers >= 4)) and not m.units.any(func(u): return not u.dead and u.faction == fid and u.kind == kind):
			m.queue_craft(fid, kind, 1)
	for e in m.units:
		if e.dead or e.faction != fid or not e.kind in ["cannon", "ram"]:
			continue
		var key := "eng%d" % e.id
		if m._open_engine_seats(e) > 0:
			var steps := [_step("man", e.kind), _step("guard", "", 0, "home")]
			var result: Dictionary = m.command(fid, {"engine": e.id, "steps": steps})
			if result.ok and not result.crews.is_empty() and _crew(key) == null:
				roles[key] = result.crews[0]
		if not e.crew_ids.is_empty():
			var operator = m.unit(e.crew_ids[0])
			if operator and operator.crew >= 0:
				roles[key] = operator.crew
	# Grow the army.
	var army = _crew("army")
	var have: int = army.members.size() if army else 0
	var want := _army_want(f)
	var free_gear := 0
	for k in f.gear:
		if Defs.ITEMS.has(k) and Defs.ITEMS[k]["slot"] in ["weapon", "bow"]:
			free_gear += int(f.gear[k])
	var attacking: bool = army != null and army.idx < army.steps.size() and army.steps[army.idx]["action"] == "attack"
	# Only soldiers who hold a weapon count toward an attack; an army still queuing at the armory isn't ready.
	var armed := 0
	if army:
		for id in army.members:
			var s = m.unit(id)
			if s != null and not s.dead and (s.weapon != "" or s.bow):
				armed += 1
	var army_start := _army_start()
	# Never strip the economy: the army is a share of the adults, grown only while fed.
	want = _army_want(f)
	var economy_ok: bool = f.food_state >= 2 and (_size("wood") >= 2 or f.age >= 2)
	# Soldiers who joined before there was a weapon for them go back for one when there is.
	if army and not attacking and armed < have and free_gear > 0 and m.t - rearm_t > 20.0:
		rearm_t = m.t
		_order("army", [_step("arm"), _step("guard", "", 0, "home")], 0)
		return
	if not attacking and f.food_state <= 1 and have > maxi(4, int(f.adults * 0.2)):
		_order("army", [_step("dismiss")], 0)
		return
	if not attacking and have < want and free_gear > 0 and f.adults > 8 and m.t >= army_start and economy_ok:
		var add := mini(want - have, mini(free_gear, maxi(1, f.adults / 3)))
		var steps := [_step("arm"), _step("guard", "", 0, "home")]
		if strategy == "cavalry" and f.horses > 0:
			steps = [_step("mount"), _step("arm"), _step("guard", "", 0, "home")]
		_order("army", steps, have + add)
	# Attack.
	if passive or m.t < calm_until or attacking:
		return
	var camp = m.known_enemy_camp(fid)
	if camp == null:
		return
	# Training showed striking back straight after a raid leaves home open to the next wave, so attacks wait for the army.
	if m.t >= next_attack and armed >= int(want * 0.75) and armed >= 5 and f.food_state >= 2 and m.t - raided_t > 120.0:
		var steps := [_step("attack", "", 0, "enemy")]
		if _order("army", steps, 0):
			attacks += 1
			next_attack = m.t + float(lv["gap"])
			for e in m.units:
				if not e.dead and e.faction == fid and e.kind in ["cannon", "ram"]:
					_order("eng%d" % e.id, [_step("attack", "", 0, "enemy")], 0)


## Items of these slots waiting in the armories' queues.
func _queued(slots: Array) -> int:
	var n := 0
	for b in m.buildings_of(fid, "armory"):
		for item in b.queue:
			if Defs.ITEMS[item]["slot"] in slots:
				n += int(Defs.ITEMS[item]["batch"])
	return n


func _queued_item(item: String) -> int:
	var n := 0
	for b in m.buildings_of(fid, "armory"):
		n += b.queue.count(item)
	return n


## Weapons kept in the armory for the militia.
func _ready_want(f) -> int:
	# Early on every bit of wood builds the village: a few spears, more once riders are known or the village can spare them.
	var early: bool = m.t < 300.0 and m.t - riders_seen_t > 900.0 and m.t - raided_t > 900.0
	if early:
		return 3
	# Once raided, keep more in hand: raiders come back.
	return int(lv["ready"]) + f.adults / int(lv["ready_per"]) + (4 if m.t - raided_t < 900.0 else 0)


## Pikes against riders once the armory makes them, otherwise spears, which hit riders twice as hard too.
func _militia_item() -> String:
	if m.t - riders_seen_t < 900.0:
		for pike in ["iron_pike", "bronze_pike"]:
			if m.craft_problem(fid, pike) == "":
				return pike
	return _basic_weapon()


## Enemies seen near home in the last few seconds: {total, riders}. Also notes riders and stables seen anywhere.
func _threat_near(radius: float) -> Dictionary:
	var out := {"total": 0, "riders": 0}
	var home := _home()
	var intel: Dictionary = m.fac(fid).intel
	for key in intel:
		var e: Dictionary = intel[key]
		var kind: String = e.get("kind", "")
		if kind == "building" and e.get("type", "") == "stable" and int(e.get("faction", -1)) != fid:
			riders_seen_t = maxf(riders_seen_t, float(e["t"]))
		if kind != "units":
			continue
		var riders := int(e.get("counts", {}).get("rider", 0))
		if riders > 0:
			riders_seen_t = maxf(riders_seen_t, float(e["t"]))
		if m.t - float(e["t"]) < 6.0 and (e["pos"] as Vector2).distance_to(home) < radius:
			# Several lookouts each note the same band, so the biggest sighting is the estimate.
			out["total"] = maxi(out["total"], int(e["total"]))
			out["riders"] = maxi(out["riders"], riders)
	return out


func _defend(f) -> void:
	# React to enemies seen near home in the last few seconds.
	var seen := _threat_near(float(lv["alarm"]))
	var weight: int = seen["total"] + seen["riders"]
	if weight == 0:
		# Once it's quiet the militia hand their weapons back and go back to work.
		if _crew("militia") != null and m.t - last_alarm > 40.0:
			if not _order("militia", [_step("resume_work")], 0):
				_order("militia", [_step("dismiss")], 0)
			roles.erase("militia")
		return
	if weight >= int(lv["react"]):
		raided_t = m.t
	if m.t - last_alarm < float(lv["recall"]):
		return
	last_alarm = m.t
	var army = _crew("army")
	if army and not (army.idx < army.steps.size() and army.steps[army.idx]["action"] == "attack"):
		_order("army", [_step("guard", "", 0, "home")], 0)
	# Militia: arm villagers only for a real raid, not a lone scout. Against riders, pikes first.
	var guards: int = army.members.size() if army else 0
	if weight >= int(lv["react"]) and guards < weight + 2:
		var with := ""
		if seen["riders"] > 0:
			for pike in ["iron_pike", "bronze_pike", "wood_spear"]:
				if int(f.gear.get(pike, 0)) > 0:
					with = pike
					break
		# Never more than there are weapons for: unarmed villagers sent into a fight only die.
		var have := _size("militia")
		var spare := int(f.gear.get(with, 0)) if with != "" else _gear_count(f, ["weapon", "bow"])
		var more := mini(Planner.militia_wanted(f.adults, guards + have, weight), spare)
		if more > 0:
			_order("militia", [_step("arm", with), _step("guard", "", 0, "home")], have + more)


func _scouting(f) -> void:
	var first: float = lv["scout"]
	if strategy == "rush":
		first *= 0.7
	if m.t < first:
		return
	var known = m.known_enemy_camp(fid)
	var gap := 260.0 if known != null else 140.0
	if _busy("scout") or m.t - last_scout < gap:
		return
	last_scout = m.t
	var steps := [_step("scout", "", 0, "enemy")]
	if f.horses > 0:
		steps = [_step("mount"), _step("scout", "", 0, "enemy")]
	_order("scout", steps, 1)
