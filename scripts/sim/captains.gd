extends RefCounted
## What a captain decides, about once a second per post: who belongs to it and
## what they work on. No state of its own (that lives in Match.Post) and no model
## calls. Work starts through Match.command, like everyone else's orders.

const Defs = preload("res://scripts/data/defs.gd")
const Planner = preload("res://scripts/ai/planner.gd")

const STEWARD_KEEPS := 6       # the village never lends itself below this
const SLACK := 1               # a job may run this far over before people are moved, so they don't dither


static func think(m, p) -> void:
	p.members = p.members.filter(func(id): return _serving(m, p, id))
	if p.mandate == "village":
		for u in m.idle_adults(p.faction, p.center):
			if u.post < 0:
				m.join_post(p, u)
		_staff_other_posts(m, p)
	elif m.village_post(p.faction) == null:
		# With no steward, a captain finds their own people.
		for u in m.idle_adults(p.faction, p.center):
			if p.members.size() >= p.target:
				break
			if u.post < 0:
				m.join_post(p, u)
	var workers := []
	for u in m.post_members(p):
		if u.id != p.captain and not u.child and u.siege < 0 and not m.under_direct_order(u):
			workers.append(u)
	_assign(m, p, _wanted(m, p, workers))


static func _serving(m, p, id: int) -> bool:
	var u = m.unit(id)
	return u != null and not u.dead and u.post == p.id


static func _staff_other_posts(m, village) -> void:
	for other in m.posts.values():
		if other.faction != village.faction or other.id == village.id:
			continue
		var short: int = mini(other.target - other.members.size(), village.members.size() - STEWARD_KEEPS)
		if short <= 0:
			continue
		var lend: Array = m.post_members(village).filter(func(u):
			return u.id != village.captain and not u.child and u.siege < 0 and not m.under_direct_order(u))
		lend.sort_custom(func(a, b):
			if (a.crew < 0) != (b.crew < 0):
				return a.crew < 0
			var da: float = a.pos.distance_squared_to(other.center)
			var db: float = b.pos.distance_squared_to(other.center)
			return da < db or (da == db and a.id < b.id))
		for u in lend.slice(0, short):
			m.join_post(other, u)


# --- Jobs ---------------------------------------------------------------------

## The post's jobs, most important first, as {role, step, n}.
static func _wanted(m, p, workers: Array) -> Array:
	var jobs := []
	var left := workers.size()
	match p.mandate:
		"village":
			var f = m.fac(p.faction)
			var food := Planner.food_workers(f.pop, f.food_state)
			for other in m.posts.values():
				if other.faction == p.faction and other.mandate == "farming":
					food -= other.members.size() - 1
			left -= _food_jobs(m, p, jobs, mini(food, left))
			if f.age >= 1 or m.has_building(p.faction, "quarry"):
				var stone := mini(Planner.stone_workers(f.adults), left)
				_add(jobs, "stone", "gather", "stone", stone)
				left -= stone
			_add(jobs, "wood", "gather", "wood", left)
		"farming":
			left -= _food_jobs(m, p, jobs, left)
			_add(jobs, "wood", "gather", "wood", left)
		"industry":
			for dep in Defs.DEPOSITS:
				var n := mini(_places(m, p, "mine", dep), mini(3, left))
				_add(jobs, dep, "gather", dep, n)
				left -= n
			var smelter = m.nearest_building(p.faction, p.center, ["smelter"])
			if smelter and smelter.pos.distance_to(p.center) <= p.radius:
				var stock: Dictionary = m.fac(p.faction).stock
				var metal := "bronze"
				if smelter.tier >= 1 and float(stock.get("iron_ore", 0)) > 3.0 and float(stock.get("bronze", 0)) > 30.0:
					metal = "iron"
				var n := mini(2, left)
				_add(jobs, "smelt", "smelt", metal, n)
				left -= n
			var diggers := mini(_places(m, p, "quarry"), left)
			_add(jobs, "stone", "gather", "stone", diggers)
			left -= diggers
			_add(jobs, "wood", "gather", "wood", left)
		"garrison", "army":
			var bare := workers.filter(func(u): return u.weapon == "" and not u.bow).size()
			var n := mini(bare, _spare_weapons(m, p))
			if m.has_building(p.faction, "armory"):
				_add(jobs, "arm", "arm", "", n)
				left -= n
			_add(jobs, "guard", "guard", "", left)
	return jobs


static func _add(jobs: Array, role: String, action: String, subject: String, n: int) -> void:
	if n > 0:
		jobs.append({"role": role, "n": n,
			"step": {"action": action, "subject": subject, "count": 0, "amount": 0, "where": ""}})


## Puts up to n people on food and returns how many found a place.
static func _food_jobs(m, p, jobs: Array, n: int) -> int:
	if n <= 0:
		return 0
	var placed := mini(n, _places(m, p, "farm"))
	_add(jobs, "farm", "gather", "farm", placed)
	if placed < n:
		var rest := n - placed
		if m.nearest_node("berry", p.center, 160.0) != null:
			_add(jobs, "berries", "gather", "berries", rest)
			placed += rest
		elif m.has_building(p.faction, "lodge"):
			_add(jobs, "hunt", "gather", "hunt", rest)
			placed += rest
	return placed


## Working places this post can fill at its own buildings of a type.
static func _places(m, p, type: String, deposit: String = "") -> int:
	var n := 0
	for b in m.buildings_of(p.faction, type):
		if b.pos.distance_to(p.center) <= p.radius and (deposit == "" or b.deposit == deposit):
			n += int(Defs.BUILDINGS[type]["workers"])
	return n


static func _spare_weapons(m, p) -> int:
	var n := 0
	var gear: Dictionary = m.fac(p.faction).gear
	for id in gear:
		if Defs.ITEMS[id]["slot"] in ["weapon", "bow"]:
			n += int(gear[id])
	return n


## Moves as few people as possible to match the wanted jobs.
static func _assign(m, p, jobs: Array) -> void:
	var wanted := {}
	for job in jobs:
		wanted[job["role"]] = job
	for role in p.jobs.keys():
		var c = m.crews.get(p.jobs[role])
		if c == null or c.post != p.id:
			p.jobs.erase(role)      # finished, or under a direct order now
			continue
		if role == "arm":
			continue
		var keep := 0
		if wanted.has(role) and c.idx < c.steps.size() and c.steps[c.idx]["subject"] == wanted[role]["step"]["subject"]:
			keep = int(wanted[role]["n"])
			if c.members.size() <= keep + SLACK:
				continue
		for id in c.members.slice(keep):
			var u = m.unit(id)
			if u:
				m.release_member(u)
		if keep == 0:
			p.jobs.erase(role)
	var free: Array = m.post_members(p).filter(func(u): return u.id != p.captain and m.is_free_adult(u))
	for job in jobs:
		if free.is_empty():
			break
		var role: String = job["role"]
		var c = m.crews.get(p.jobs.get(role, -1))
		var need: int = int(job["n"]) - (c.members.size() if c else 0)
		if need <= 0:
			continue
		var take := free.slice(0, need)
		if c:
			m.add_to_crew(c, take)
		else:
			var r: Dictionary = m.command(p.faction, {"units": take.map(func(u): return u.id), "steps": [job["step"].duplicate()]})
			if not r.get("ok", false):
				continue
			c = m.crews.get(r["crews"][0])
			if c == null:
				continue
			c.post = p.id
			p.jobs[role] = c.id
			# "here" would be wherever the commander stands. A post works around its own center.
			c.state["origin"] = p.center
			c.state["target"] = p.center
		free = free.slice(take.size())
