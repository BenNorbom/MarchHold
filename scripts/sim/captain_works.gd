extends RefCounted
## What a captain builds, upgrades, researches and makes, inside the mandate.
## Captains spend in order (food, housing, defence, the rest), count sites nobody
## has paid for yet as spent, and stay out of the reserve.

const Defs = preload("res://scripts/data/defs.gd")
const Planner = preload("res://scripts/ai/planner.gd")

enum Rank { FOOD, HOUSING, DEFENCE, REST }

const BUILDERS := 3
const WALL_BUILDERS := 5
const PEOPLE_PER_PROJECT := 15 # one more project at a time for each of these
const MAX_PROJECTS := 4
const RING := 22.0             # garrison palisade
const RING_SIDES := 14
const TELL_AFTER := 120.0      # seconds held up before the captain says so
const SPEARS_KEPT := 6
const EVERY := 2.0             # seconds between looks at what to build
const HAUL := 60.0             # work this far from a drop-off wants a stockpile


## A project is a role in Post.jobs that ends by itself and is never trimmed.
static func is_project(role: String) -> bool:
	return role.begins_with("do:")


static func update(m, p) -> void:
	# Staffing is every second. Building plans can wait, and cost more to work out.
	if m.t - p.works_t < EVERY - 0.05:
		return
	p.works_t = m.t
	_note_what_is_seen(m, p)
	var running := 0
	for role in p.jobs.keys():
		if is_project(role):
			var c = m.crews.get(p.jobs[role])
			if c and c.post == p.id:
				running += 1
			else:
				p.jobs.erase(role)
	var room := mini(MAX_PROJECTS, 1 + p.members.size() / PEOPLE_PER_PROJECT) - running
	if room <= 0 or _resume(m, p):
		return
	var f = m.fac(p.faction)
	var held := committed(m, p.faction)
	var wants := _wants(m, p)
	var top: int = Rank.REST
	if not wants.is_empty():
		top = wants[0]["rank"]
	# Leave what a captain with a more urgent need is saving up for.
	for other in m.posts.values():
		if other.id != p.id and other.faction == p.faction and not other.saving.is_empty() and int(other.saving["rank"]) < top:
			_add_cost(held, other.saving["cost"])
	if wants.is_empty() and not p.ready_told and p.target > 0 and p.members.size() >= p.target:
		p.ready_told = true
		if p.faction == 0:
			m.post(0, "%s: the %s is manned and built. We'll keep it running." % [m.post_label(p), p.name], "done")
	p.saving = {}
	p.blocked = {}
	for want in wants:
		var why := _limit(m, p, want)
		if why != "":
			p.blocked[want["what"]] = why
			continue
		var cost: Dictionary = want["cost"]
		if not _covers(f, cost, held):
			p.blocked[want["what"]] = "the stores can't spare " + Defs.cost_text(cost)
			if p.saving.is_empty():
				p.saving = {"rank": want["rank"], "cost": cost}
			_add_cost(held, cost)
			continue
		if _start(m, p, want):
			p.saving = {}
			p.blocked.erase(want["what"])
			p.blocked_since.erase(want["what"])
			p.blocked_told.erase(want["what"])
			_tell_blocked(m, p, wants)
			return
		p.blocked[want["what"]] = "no good site in the area"
	_tell_blocked(m, p, wants)


## Each thing held up is reported once, with the reason, until it gets going.
static func _tell_blocked(m, p, wants: Array) -> void:
	var still := {}
	for want in wants:
		var what: String = want["what"]
		still[what] = true
		if not p.blocked.has(what) or p.blocked[what] in ["you said not to", "not in the mandate"]:
			continue
		if not p.blocked_since.has(what):
			p.blocked_since[what] = m.t
		elif m.t - float(p.blocked_since[what]) >= TELL_AFTER and not p.blocked_told.has(what):
			p.blocked_told[what] = true
			if p.faction != 0:
				continue
			var verb: String = "make" if want["kind"] == "craft" else want["kind"]
			var thing: String = want["type"]
			match want["kind"]:
				"build":
					thing = "a " + Defs.building_name(thing).to_lower()
				"craft":
					thing = Defs.item_name(thing, 2)
				"upgrade":
					thing = "the " + thing
			var why: String = p.blocked[what]
			for r in want["cost"]:
				if why.begins_with("the stores") and int(m.fac(0).reserve.get(r, 0)) > 0:
					why += ", with the %d %s you told us to keep back" % [int(m.fac(0).reserve[r]), Defs.RESOURCE_NAMES[r]]
			m.post(0, "%s: we can't %s %s: %s." % [m.post_label(p), verb, thing, why], "warn")
	for what in p.blocked_since.keys():
		if not still.has(what):
			p.blocked_since.erase(what)
			p.blocked_told.erase(what)


static func committed(m, faction: int) -> Dictionary:
	var held := {}
	for b in m.buildings:
		if b.dead or b.faction != faction:
			continue
		if not b.complete and not b.paid:
			_add_cost(held, Defs.BUILDINGS[b.type]["cost"])
		if b.upgrading != "" and not b.up_paid:
			_add_cost(held, Defs.UPGRADES[b.upgrading]["cost"])
	return held


static func _add_cost(held: Dictionary, cost: Dictionary) -> void:
	for r in cost:
		held[r] = float(held.get(r, 0.0)) + float(cost[r])


static func _covers(f, cost: Dictionary, held: Dictionary) -> bool:
	for r in cost:
		if float(f.stock.get(r, 0.0)) - float(held.get(r, 0.0)) - float(f.reserve.get(r, 0.0)) < float(cost[r]):
			return false
	return true


static func _limit(m, p, want: Dictionary) -> String:
	if want["kind"] != "build":
		return ""
	var type: String = want["type"]
	if not may_build(m, p, type):
		return "not in the mandate"
	if p.forbid.has(type):
		return "you said not to"
	return m.unlock_problem(p.faction, type)


# --- What's needed -----------------------------------------------------------

static func _want(rank: int, kind: String, type: String, cost: Dictionary) -> Dictionary:
	return {"rank": rank, "kind": kind, "type": type, "cost": cost, "what": "%s %s" % [kind, type]}


static func _building(rank: int, type: String) -> Dictionary:
	return _want(rank, "build", type, Defs.BUILDINGS[type]["cost"])


## Finished or planned, inside the post's area.
static func count_here(m, p, type: String) -> int:
	var n := 0
	for b in m.buildings_of(p.faction, type, false):
		if b.pos.distance_to(p.center) <= p.radius:
			n += 1
	return n


static func _planned(m, faction: int, key: String) -> int:
	var n := 0
	for b in m.buildings_of(faction, "", false):
		n += int(Defs.BUILDINGS[b.type].get(key, 0))
	return maxi(n, m.fac(faction).granary) if key == "food_cap" else n


static func _can_have(m, p, type: String) -> bool:
	return not p.forbid.has(type) and m.unlock_problem(p.faction, type) == "" and m.can_afford(p.faction, Defs.BUILDINGS[type]["cost"])


## The mandate's own list, and what its strategy calls for.
static func may_build(m, p, type: String) -> bool:
	if type in Defs.MANDATES[p.mandate]["builds"]:
		return true
	return type in Defs.STRATEGY_BUILDS and p.mandate in ["village", "industry"] and (m.post_goal(p) > 0 or p.focus != "")


## How far a post looks for deposits: further while racing for an age.
static func reach(m, p) -> float:
	return maxf(p.radius, Defs.STRATEGY_REACH) if m.post_goal(p) > 0 and p.mandate in ["village", "industry"] else p.radius


static func _wants(m, p) -> Array:
	var out := []
	_strategy(m, p, out)
	match p.mandate:
		"village":
			_village(m, p, out)
		"farming":
			_farming(m, p, out)
		"industry":
			_industry(m, p, out)
		"garrison":
			_garrison(m, p, out)
	return out


## What an age or a focus asks for. It comes before the rest, after food and roofs.
static func _strategy(m, p, out: Array) -> void:
	var f = m.fac(p.faction)
	var aim: int = m.post_goal(p)
	if aim > 0:
		if f.age < 1 and m.buildings_of(p.faction, "quarry", false).is_empty():
			out.append(_building(Rank.DEFENCE, "quarry"))
		if aim >= 2 and f.age >= 1:
			for dep in (["bronze"] if aim < 3 or f.age < 2 else Defs.DEPOSITS):
				_want_mine(m, p, out, dep)
		if aim >= 3 and m.research_problem(p.faction, "iron_mining") == "":
			out.append(_want(Rank.DEFENCE, "research", "iron_mining", Defs.RESEARCH["iron_mining"]["cost"]))
		if aim >= 4 and f.age >= 3:
			if m.buildings_of(p.faction, "university", false).is_empty():
				out.append(_building(Rank.DEFENCE, "university"))
			if m.research_problem(p.faction, "gunpowder") == "":
				out.append(_want(Rank.DEFENCE, "research", "gunpowder", Defs.RESEARCH["gunpowder"]["cost"]))
	if p.focus == "":
		return
	var st: Dictionary = Defs.STRATEGIES[p.focus]
	match p.focus:
		"growth":
			if _planned(m, p.faction, "housing") - f.pop <= maxi(10, f.pop / 3) and _planned(m, p.faction, "housing") < Defs.POP_HARD_CAP:
				out.append(_building(Rank.HOUSING, "hut"))
			if count_here(m, p, "farm") * Planner.FARMERS_PER_FARM < ceili(f.pop * 0.32):
				out.append(_building(Rank.FOOD, "farm"))
		"defence":
			if count_here(m, p, "tower") < 2 and f.age >= 1:
				out.append(_building(Rank.DEFENCE, "tower"))
			if not p.walled and f.age >= 1 and f.pop >= 20:
				out.append(_want(Rank.DEFENCE, "build", "stone_wall", _ring_cost(p, "stone_wall")))
			_keep_spears(m, p, out, maxi(SPEARS_KEPT, f.adults / 3))
	if not st.has("items"):
		return
	# The armories it needs, the research, and horses for cavalry.
	if m.buildings_of(p.faction, "armory", false).is_empty():
		out.append(_building(Rank.DEFENCE, "armory"))
	elif m.buildings_of(p.faction, "armory").all(func(b): return b.queue.size() >= m.QUEUE_MAX / 2) and m.buildings_of(p.faction, "armory", false).size() < 1 + f.pop / 30:
		out.append(_building(Rank.REST, "armory"))
	for research in ["armory_bronze", "armory_iron"]:
		if f.age >= int(Defs.RESEARCH[research]["age"]) and m.research_problem(p.faction, research) == "":
			out.append(_want(Rank.DEFENCE, "research", research, Defs.RESEARCH[research]["cost"]))
	if st.has("horses") and f.age >= 1:
		if m.buildings_of(p.faction, "stable", false).is_empty():
			out.append(_building(Rank.DEFENCE, "stable"))
	var item := focus_item(m, p)
	if item == "":
		return
	var have := stocked(m, p.faction, item)
	var keep: int = p.focus_keep
	if have < keep:
		var want := _want(Rank.DEFENCE, "craft", item, Defs.item_cost(item, maxi(0, m.armory_tier(p.faction))))
		want["count"] = keep - have
		out.append(want)
	elif not p.focus_told and p.faction == 0:
		p.focus_told = true
		m.post(0, "%s: the armory holds %d %s, as you asked. We'll keep it topped up." % [m.post_label(p), have, Defs.item_name(item, have)], "done")


## The best thing the focus can make right now, or "" when it needs an age or research first.
static func focus_item(m, p) -> String:
	for item: String in Defs.STRATEGIES[p.focus].get("items", []):
		if m.craft_problem(p.faction, item) == "" and m.step_problem(p.faction, _step("craft", item)) == "":
			return item
	return ""


## In the armory, and waiting in an armory's queue.
static func stocked(m, faction: int, item: String) -> int:
	var n := int(m.fac(faction).gear.get(item, 0))
	if item in ["ram", "cannon"]:
		for engine in m.units:
			if not engine.dead and engine.kind == item and engine.faction == faction:
				n += 1
	for b in m.buildings_of(faction, "armory"):
		n += b.queue.count(item) * int(Defs.ITEMS[item]["batch"])
	return n


static func _want_mine(m, p, out: Array, dep: String) -> void:
	for b in m.buildings_of(p.faction, "mine", false):
		if b.deposit == dep or (not b.complete and b.node >= 0 and m.terrain.nodes[b.node].sub == dep):
			return
	var mine := _building(Rank.DEFENCE, "mine")
	mine["deposit"] = dep
	mine["what"] = "mine " + dep
	out.append(mine)


static func _ring_cost(p, type: String) -> Dictionary:
	var gate := "stone_gate" if type == "stone_wall" else "palisade_gate"
	var r := RING if p.mandate != "village" else RING * 2.5
	var pieces := ceili(TAU * r / float(Defs.BUILDINGS[type]["length"]))
	var cost := {}
	for res in Defs.BUILDINGS[type]["cost"]:
		cost[res] = int(Defs.BUILDINGS[type]["cost"][res]) * pieces + int(Defs.BUILDINGS[gate]["cost"].get(res, 0))
	return cost


static func _village(m, p, out: Array) -> void:
	var f = m.fac(p.faction)
	var pop: int = f.pop
	var eaters := pop
	for other in m.posts.values():
		if other.faction == p.faction and other.mandate == "farming":
			eaters -= other.members.size() * 4
	var farms := count_here(m, p, "farm")
	if farms < ceili(eaters * 0.15) and (pop >= 14 or farms * Planner.FARMERS_PER_FARM + p.pickers < pop * 0.3):
		out.append(_building(Rank.FOOD, "farm"))
	if _planned(m, p.faction, "food_cap") < pop * Defs.WELL_FED_STOCK * 1.5 + 20.0:
		out.append(_building(Rank.FOOD, "stockpile"))
	elif pop >= 8 and Planner.wood_haul_long(m, p.faction, p.center) and Planner.tree_stockpile_site(m, p.faction, p.center) != null:
		# A drop-off at the tree line roughly triples what the woodcutters bring in.
		var by_trees := _building(Rank.FOOD, "stockpile")
		by_trees["by_trees"] = true
		by_trees["what"] = "build stockpile by the trees"
		out.append(by_trees)
	var housing := _planned(m, p.faction, "housing")
	if housing < Defs.POP_HARD_CAP and housing - pop <= maxi(6, pop / 5):
		out.append(_building(Rank.HOUSING, "hut"))
	if pop >= 16 and m.buildings_of(p.faction, "armory", false).is_empty():
		out.append(_building(Rank.DEFENCE, "armory"))
	if pop >= 24 and count_here(m, p, "watch_post") + count_here(m, p, "tower") == 0:
		out.append(_building(Rank.DEFENCE, "watch_post"))
	if pop >= 14 and m.buildings_of(p.faction, "quarry", false).is_empty():
		out.append(_building(Rank.REST, "quarry"))
	if pop >= 70 and f.age >= 2 and m.buildings_of(p.faction, "stable", false).is_empty():
		out.append(_building(Rank.REST, "stable"))
	# Militia need spears waiting. With an industry captain, that's their job.
	for other in m.posts.values():
		if other.faction == p.faction and other.mandate == "industry":
			return
	_keep_spears(m, p, out, SPEARS_KEPT)


static func _farming(m, p, out: Array) -> void:
	var f = m.fac(p.faction)
	if count_here(m, p, "farm") < ceili((p.target - 1) / float(Planner.FARMERS_PER_FARM)):
		out.append(_building(Rank.FOOD, "farm"))
	if m.village_post(p.faction) == null:
		if _planned(m, p.faction, "food_cap") < f.pop * Defs.WELL_FED_STOCK * 1.5 + 20.0:
			out.append(_building(Rank.FOOD, "stockpile"))
		if _planned(m, p.faction, "housing") - f.pop <= 4:
			out.append(_building(Rank.HOUSING, "hut"))
	if _remote(m, p) and count_here(m, p, "watch_post") == 0:
		out.append(_building(Rank.DEFENCE, "watch_post"))


static func _industry(m, p, out: Array) -> void:
	var f = m.fac(p.faction)
	var dropoff = m.nearest_building(p.faction, p.center, ["campfire", "stockpile"], false)
	if dropoff == null or dropoff.pos.distance_to(p.center) > HAUL:
		out.append(_building(Rank.REST, "stockpile"))
	if _remote(m, p) and count_here(m, p, "watch_post") == 0:
		out.append(_building(Rank.DEFENCE, "watch_post"))
	if f.age < 1 and m.buildings_of(p.faction, "quarry", false).is_empty():
		out.append(_building(Rank.REST, "quarry"))
	if f.age >= 1:
		for dep in Defs.DEPOSITS:
			var node = Planner.find_deposit(m, p.faction, dep, p.center, reach(m, p), true, p.seen)
			if node and not _mine_planned(m, p, node):
				var mine := _building(Rank.REST, "mine")
				mine["deposit"] = dep
				mine["what"] = "mine " + dep
				out.append(mine)
	if m.buildings_of(p.faction, "armory", false).is_empty() and f.pop >= 16:
		out.append(_building(Rank.REST, "armory"))
	if f.age >= 3 and m.buildings_of(p.faction, "university", false).is_empty():
		out.append(_building(Rank.REST, "university"))
	for id in Defs.RESEARCH:
		if m.research_problem(p.faction, id) == "":
			out.append(_want(Rank.REST, "research", id, Defs.RESEARCH[id]["cost"]))
	_keep_spears(m, p, out, SPEARS_KEPT)


static func _garrison(m, p, out: Array) -> void:
	var f = m.fac(p.faction)
	if count_here(m, p, "watch_post") + count_here(m, p, "tower") == 0:
		out.append(_building(Rank.DEFENCE, "watch_post"))
	if not p.walled:
		var pieces := ceili(TAU * RING / float(Defs.BUILDINGS["palisade"]["length"]))
		var cost := {}
		for r in Defs.BUILDINGS["palisade"]["cost"]:
			cost[r] = int(Defs.BUILDINGS["palisade"]["cost"][r]) * pieces + int(Defs.BUILDINGS["palisade_gate"]["cost"].get(r, 0))
		out.append(_want(Rank.DEFENCE, "build", "palisade", cost))
	if m.buildings_of(p.faction, "armory", false).is_empty():
		out.append(_building(Rank.DEFENCE, "armory"))
	if f.age >= 1 and count_here(m, p, "tower") == 0:
		out.append(_building(Rank.DEFENCE, "tower"))
	var bare: int = m.post_members(p).filter(func(u): return not u.child and not m.armed(u)).size()
	if bare > 0:
		_keep_spears(m, p, out, bare)


static func _keep_spears(m, p, out: Array, wanted: int) -> void:
	var tier: int = m.armory_tier(p.faction)
	if tier < 0:
		return
	var gear: Dictionary = m.fac(p.faction).gear
	var spare := stocked(m, p.faction, "wood_spear") - int(gear.get("wood_spear", 0))
	for id in gear:
		if Defs.ITEMS[id]["slot"] == "weapon":
			spare += int(gear[id])
	if spare < wanted:
		var item := "wood_spear"     # the one weapon every armory makes
		var spears := _want(Rank.REST, "craft", item, Defs.item_cost(item, tier))
		spears["count"] = wanted - spare
		out.append(spears)




static func _remote(m, p) -> bool:
	return p.center.distance_to(m.home_pos(p.faction)) > Defs.HOME_GROUND


static func _mine_planned(m, p, node) -> bool:
	for b in m.buildings_of(p.faction, "mine", false):
		if b.node == node.id:
			return true
	return false


# --- Doing it ----------------------------------------------------------------

## Up to n of the post's people for a project: the free first, then off wood and stone.
static func _hands(m, p, n: int) -> Array:
	var busy := {}
	var order := {}
	for role in p.jobs:
		if is_project(role) or role == "arm":
			busy[p.jobs[role]] = true
		elif role == "wood":
			order[p.jobs[role]] = 1
		elif role in ["stone", "guard"]:
			order[p.jobs[role]] = 2
	var pool := []
	for u in m.post_members(p):
		if u.id == p.captain or u.child or u.siege >= 0 or m.under_direct_order(u) or busy.has(u.crew):
			continue
		pool.append(u)
	pool.sort_custom(func(a, b):
		var ra: int = 0 if a.crew < 0 else int(order.get(a.crew, 3))
		var rb: int = 0 if b.crew < 0 else int(order.get(b.crew, 3))
		return ra < rb or (ra == rb and a.id < b.id))
	return pool.slice(0, n)


static func _begin(m, p, role: String, step: Dictionary, people: Array) -> bool:
	if people.is_empty():
		return false
	for u in people:
		m.release_member(u)
	var r: Dictionary = m.command(p.faction, {"units": people.map(func(u): return u.id), "steps": [step]})
	if not r.get("ok", false):
		return false
	var c = m.crews.get(r["crews"][0])
	if c == null:
		return false
	c.post = p.id
	p.jobs[role] = c.id
	return true


static func _step(action: String, subject: String, amount: int = 0) -> Dictionary:
	return {"action": action, "subject": subject, "count": 0, "amount": amount, "where": ""}


static func _start(m, p, want: Dictionary) -> bool:
	var type: String = want["type"]
	match want["kind"]:
		"research":
			# No villagers needed: it is paid for and runs in the building.
			return m.start_research(p.faction, type) == ""
		"upgrade":
			return _begin(m, p, "do:upgrade %s" % type, _step("upgrade", type), _hands(m, p, BUILDERS))
		"craft":
			return _queue(m, p, type, int(want.get("count", 1)))
	var wall: bool = Defs.BUILDINGS[type].get("wall", false)
	var people := _hands(m, p, WALL_BUILDERS if wall else BUILDERS)
	if people.is_empty():
		return false
	var placed := lay_out(m, p, type, want.get("deposit", ""), want.get("by_trees", false))
	if not placed["ok"]:
		return false
	var step := _step("build", type)
	step["sites"] = placed["ids"]
	if not _begin(m, p, "do:build %d" % placed["ids"][0], step, people):
		for id in placed["ids"]:
			m.remove_site(id)
		return false
	if wall:
		p.walled = true
	return true


## Nobody works at the armory: the order joins its queues, as many as the stores and the queues allow.
static func _queue(m, p, item: String, wanted: int) -> bool:
	var f = m.fac(p.faction)
	var it: Dictionary = Defs.ITEMS[item]
	var cost := Defs.item_cost(item, maxi(0, m.armory_tier(p.faction)))
	var held := committed(m, p.faction)
	var room := 0
	for b in m.buildings_of(p.faction, "armory"):
		if b.tier >= int(it["tier"]):
			room += m.QUEUE_MAX - b.queue.size()
	var n := mini(ceili(float(wanted) / int(it["batch"])), room)
	# Each item is paid for when the armory starts it, so only queue what the stores can cover now.
	for r in cost:
		var spare: float = float(f.stock.get(r, 0.0)) - float(held.get(r, 0.0)) - float(f.reserve.get(r, 0.0))
		n = mini(n, int(spare / maxf(1.0, float(cost[r]))))
	if n <= 0:
		return false
	return m.queue_craft(p.faction, item, n * int(it["batch"]), true) == ""


## Picks and marks out a site in the post's area. Used for the captain's own plans and for "build a ..." orders.
static func lay_out(m, p, type: String, deposit: String = "", by_trees: bool = false) -> Dictionary:
	var d: Dictionary = Defs.BUILDINGS[type]
	if not may_build(m, p, type):
		return {"ok": false, "error": "A %s isn't part of running the %s. Address villagers, or use /b, to place it yourself." % [d["name"].to_lower(), p.name]}
	var why: String = m.unlock_problem(p.faction, type)
	if why != "":
		return {"ok": false, "error": why}
	if d.get("wall", false):
		return _ring(m, p, type)
	var front: Vector2 = p.center - m.home_pos(p.faction)
	if front.length() < 1.0:
		front = Vector2(m.map_size, m.map_size) * 0.5 - p.center
	if by_trees:
		var spot = Planner.tree_stockpile_site(m, p.faction, p.center)
		if spot != null and spot[0].distance_to(p.center) <= p.radius and Planner._leaves_lane(m, p.faction, type, spot[0], spot[1]):
			var r: Dictionary = m.place_site(p.faction, type, spot[0], spot[1])
			if r.get("ok", false):
				return {"ok": true, "ids": [r["id"]]}
	var deposits: Array = [deposit]
	if type == "mine" and deposit == "":
		deposits = Defs.DEPOSITS
	for dep in deposits:
		var spot = Planner.find_site(m, p.faction, type, p.center, front.normalized(), p.rng, true, dep, reach(m, p) if type == "mine" else p.radius, p.seen)
		if spot == null:
			continue
		var r: Dictionary = m.place_site(p.faction, type, spot[0], spot[1])
		if r.get("ok", false):
			return {"ok": true, "ids": [r["id"]]}
	var found_none := "I can't find room for a %s in our area." % d["name"].to_lower()
	if d.has("near"):
		found_none = "I haven't found %s in our area yet." % ("a rock outcrop" if d["near"] == "outcrop" else "a free deposit")
	return {"ok": false, "error": found_none}


## A ring of wall around the post, with the gate on the side facing home.
static func _ring(m, p, type: String) -> Dictionary:
	var stone := type.begins_with("stone")
	var gate := "stone_gate" if stone else "palisade_gate"
	var wall := "stone_wall" if stone else "palisade"
	if type in ["stone_gate", "palisade_gate"]:
		return {"ok": false, "error": "Gates come with the wall. Say 'build a %s'." % Defs.building_name(wall).to_lower()}
	var r := RING if p.mandate != "village" else RING * 2.5
	var toward: Vector2 = m.home_pos(p.faction) - p.center
	if toward.length() < 1.0:
		toward = Vector2(m.map_size, m.map_size) * 0.5 - p.center
	var first := toward.angle() - TAU / RING_SIDES * 0.5
	var pts := []
	for k in RING_SIDES + 1:
		pts.append(p.center + Vector2.from_angle(first + k * TAU / RING_SIDES) * r)
	var placed: Dictionary = m.place_wall(p.faction, wall, pts)
	if not placed.get("ok", false):
		return placed
	var ids: Array = placed["ids"]
	var by_gate: Array = ids.duplicate()
	var mid: Vector2 = p.center + toward.normalized() * r
	by_gate.sort_custom(func(a, b): return m.bld(a).pos.distance_squared_to(mid) < m.bld(b).pos.distance_squared_to(mid))
	for id in by_gate:
		var piece = m.bld(id)
		var at: Vector2 = piece.pos
		var rot: float = piece.rot
		var size: Vector2 = piece.size
		m.remove_site(id)
		ids.erase(id)
		var g: Dictionary = m.place_site(p.faction, gate, at, rot)
		if g.get("ok", false):
			m.bld(g["id"]).size = size
			# The gate goes up first, so there is always a way through.
			ids.push_front(g["id"])
			return {"ok": true, "ids": ids}
	for id in ids:
		m.remove_site(id)
	return {"ok": false, "error": "There's no room for a gate, so no wall."}


## Paid-for work in the area that nobody is on gets its builders back.
static func _resume(m, p) -> bool:
	var builds: Array = Defs.MANDATES[p.mandate]["builds"].duplicate()
	if may_build(m, p, "mine"):
		builds.append_array(Defs.STRATEGY_BUILDS)
	var manned := {}
	var upgrading := {}
	for c in m.crews.values():
		if c.faction != p.faction:
			continue
		for i in range(c.idx, c.steps.size()):
			var s: Dictionary = c.steps[i]
			for id in s.get("sites", []):
				manned[id] = true
			if s["action"] == "upgrade":
				upgrading[s["subject"]] = true
	var orphans := []
	for b in m.buildings_of(p.faction, "", false):
		if b.pos.distance_to(p.center) > reach(m, p) or not b.type in builds:
			continue
		if not b.complete:
			if b.paid and not manned.has(b.id):
				orphans.append(b)
		elif b.upgrading != "" and not upgrading.has(b.type) and p.mandate == "industry":
			return _begin(m, p, "do:upgrade " + b.type, _step("upgrade", b.type), _hands(m, p, BUILDERS))
	if orphans.is_empty():
		return false
	var step := _step("build", orphans[0].type)
	step["sites"] = []
	for b in orphans:
		if b.type == orphans[0].type:
			step["sites"].append(b.id)
	return _begin(m, p, "do:build %d" % orphans[0].id, step, _hands(m, p, BUILDERS))


# --- Looking round ----------------------------------------------------------

## A captain remembers outcrops and deposits their side has laid eyes on.
static func _note_what_is_seen(m, p) -> void:
	if not p.mandate in ["village", "industry"]:
		return
	var looking: float = reach(m, p)
	if p.survey_nodes.is_empty() or float(p.get_meta("surveyed", p.radius)) != looking:
		p.set_meta("surveyed", looking)
		p.survey_nodes = []
		for node in m._nodes_within(p.center, looking):
			if node.kind == "deposit" or (node.kind == "rock" and node.sub == "outcrop"):
				p.survey_nodes.append(node.id)
	var unseen := false
	for id in p.survey_nodes:
		if p.seen.has(id):
			continue
		var at: Vector2 = m.terrain.nodes[id].pos
		if Planner.known(m, p.faction, at) or Planner.post_can_see(m, p, at):
			p.seen[id] = true
		elif p.mandate == "industry" or m.post_goal(p) >= 2 or (m.terrain.nodes[id].kind == "rock" and m.buildings_of(p.faction, "quarry", false).is_empty()):
			unseen = true
	p.surveying = unseen
