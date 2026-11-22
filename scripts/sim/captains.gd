extends RefCounted
## What a captain decides, about once a second per post: who belongs to it and
## what they work on. No state of its own (that lives in Match.Post) and no model
## calls. Work starts through Match.command, like everyone else's orders.

const Defs = preload("res://scripts/data/defs.gd")
const Planner = preload("res://scripts/ai/planner.gd")
const Works = preload("res://scripts/sim/captain_works.gd")
const Watch = preload("res://scripts/sim/captain_watch.gd")

const STEWARD_KEEPS := 6       # the village never lends itself below this
const BUSH_REACH := 160.0
const PICKERS_PER_BUSH := 3    # as many as can claim one bush
const SLACK := 1               # a job may run this far over before people are moved, so they don't dither


static func think(m, p) -> void:
	p.members = p.members.filter(func(id): return _serving(m, p, id))
	if p.mandate == "village":
		# Everyone free, in no order, so no need for idle_adults' sort by distance.
		for u in m.units:
			if u.post < 0 and u.crew < 0 and u.faction == p.faction and m.is_free_adult(u):
				m.join_post(p, u)
		_staff_other_posts(m, p)
	elif p.members.size() < p.target and m.village_post(p.faction) == null:
		# With no steward, a captain finds their own people.
		for u in m.idle_adults(p.faction, p.center):
			if p.members.size() >= p.target:
				break
			if u.post < 0:
				m.join_post(p, u)
	Watch.update(m, p)
	var mustered := Watch.all_hands(p)
	if mustered:
		_drop_work(m, p)
	else:
		Works.update(m, p)
	var on_project := {}
	for role in p.jobs:
		if Works.is_project(role):
			on_project[p.jobs[role]] = true
	var roster: Array = m.post_members(p)
	var workers := []
	for u in roster:
		if u.id != p.captain and not u.child and u.siege < 0 and not m.under_direct_order(u) and not on_project.has(u.crew):
			workers.append(u)
	_assign(m, p, roster, Watch.jobs(m, p, workers) if mustered else _wanted(m, p, workers))


## In a raid builders and crafters down tools. Paid-for work resumes afterwards.
static func _drop_work(m, p) -> void:
	for role in p.jobs.keys():
		if not Works.is_project(role) and not (role == "arm" and p.alert == "falling_back"):
			continue
		var c = m.crews.get(p.jobs[role])
		if c and c.post == p.id:
			for id in c.members.duplicate():
				var u = m.unit(id)
				if u:
					m.release_member(u)
		p.jobs.erase(role)


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
			# Short of well fed means slower births, so staff food as if hungry.
			var food := Planner.food_workers(f.pop, 3 if f.food_state == 3 else 1)
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
			var stock: Dictionary = m.fac(p.faction).stock
			var smelter = m.nearest_building(p.faction, p.center, ["smelter"])
			if smelter and smelter.pos.distance_to(p.center) <= p.radius:
				var metal := "bronze"
				if smelter.tier >= 1 and float(stock.get("iron_ore", 0)) > 3.0 and float(stock.get("bronze", 0)) > 30.0:
					metal = "iron"
				# The smelter comes before the mines, once it has something to smelt.
				var fed := true
				for r in Defs.SMELT[metal]["inputs"]:
					if float(stock.get(r, 0)) < 2.0:
						fed = false
				if fed:
					var n := mini(2, left)
					_add(jobs, "smelt", "smelt", metal, n)
					left -= n
			# Miners go round the mines in turn, up to three each, so one ore can't take everyone.
			var miners := {}
			var room := {}
			for dep in Defs.DEPOSITS:
				room[dep] = mini(3, _places(m, p, "mine", dep))
			for turn in 3:
				for dep in Defs.DEPOSITS:
					if left > 0 and turn < room[dep]:
						miners[dep] = turn + 1
						left -= 1
			for dep in miners:
				_add(jobs, dep, "gather", dep, miners[dep])
			var diggers := mini(_places(m, p, "quarry"), left)
			_add(jobs, "stone", "gather", "stone", diggers)
			left -= diggers
			_add(jobs, "wood", "gather", "wood", left)
		"garrison", "army":
			var bare := workers.filter(func(u): return u.weapon == "" and not u.bow).size()
			var n := mini(bare, _spare_weapons(m, p))
			if int(m.fac(p.faction).gear.get("arrows", 0)) > 0:
				# Half-empty quivers go back for more.
				n += workers.filter(func(u): return u.bow and u.arrows < Defs.QUIVER / 2).size()
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
		var picking := mini(n - placed, _bush_places(m, p))
		_add(jobs, "berries", "gather", "berries", picking)
		placed += picking
		if placed < n:
			var hunting := mini(n - placed, mini(4, Planner.nearby_deer(m, p.center)))
			_add(jobs, "hunt", "gather", "hunt", hunting)
			placed += hunting
	return placed


static func _bush_places(m, p) -> int:
	if m.t - p.pickers_t >= 5.0:
		p.pickers_t = m.t
		p.pickers = 0
		for node in m._nodes_within(p.center, BUSH_REACH):
			if node.kind == "berry" and node.amount != 0.0:
				p.pickers += PICKERS_PER_BUSH
	return p.pickers


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
static func _assign(m, p, roster: Array, jobs: Array) -> void:
	var wanted := {}
	for job in jobs:
		wanted[job["role"]] = job
	for role in p.jobs.keys():
		var c = m.crews.get(p.jobs[role])
		if c == null or c.post != p.id:
			p.jobs.erase(role)      # finished, or under a direct order now
			continue
		if role == "arm" or Works.is_project(role):
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
	var free: Array = roster.filter(func(u): return u.id != p.captain and m.is_free_adult(u))
	for job in jobs:
		var role: String = job["role"]
		var c = m.crews.get(p.jobs.get(role, -1))
		var at: Vector2 = job.get("at", p.center)
		if c and job.has("at"):
			c.state["target"] = at      # the line moves with the threat
		var need: int = int(job["n"]) - (c.members.size() if c else 0)
		if need <= 0 or free.is_empty():
			continue
		var fit := free
		if role == "defend":
			fit = free.filter(func(u): return m.armed(u))
		elif role in ["arm", "shelter"]:
			# Empty hands first, then half-empty quivers.
			var bare: Array = free.filter(func(u): return u.weapon == "" and not u.bow)
			if role == "arm":
				bare.append_array(free.filter(func(u): return u.bow and u.arrows < Defs.QUIVER / 2))
			fit = bare
		var take: Array = fit.slice(0, need)
		if take.is_empty():
			continue
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
			c.state["target"] = at
		free = free.filter(func(u): return not take.has(u))
