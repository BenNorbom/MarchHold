extends "res://scripts/sim/match_base.gd"
## Crews, plans, work and the settlement economy.

const HAUL_WEIGHT := 6.0     # a load is hauled many times, the first walk happens once
const GATHER_RANGE := 260.0
const MAX_SEARCHES_PER_TICK := 12
const SEARCH_RETRY := 2.0    # seconds before looking again when there's nothing to gather

var searches_this_tick := 0
var claims := {}          # resource node id -> gatherers heading to it
var birth_acc := PackedFloat64Array()      # by faction
var breed_acc := {}       # stable id -> progress
var upkeep_t := 0.0


# --- Posts ---------------------------------------------------------------------

func post_of(u: Unit) -> Post:
	return posts.get(u.post) if u.post >= 0 else null


func post_members(p: Post) -> Array:
	var out := []
	for id in p.members:
		var u := unit(id)
		if u and not u.dead and u.post == p.id:
			out.append(u)
	return out


## Everywhere an order can name: places the player named, and posts (the village is just home).
func places_of(faction: int) -> Dictionary:
	var out: Dictionary = fac(faction).places.duplicate()
	for p: Post in posts.values():
		var key := p.name.to_lower()
		# One plain word ("farms", "garrison") has to keep its usual meaning in orders.
		if p.faction == faction and key.contains(" ") and not out.has(key):
			out[key] = {"name": p.name, "pos": p.center}
	return out


func village_post(faction: int) -> Post:
	for p: Post in posts.values():
		if p.faction == faction and p.mandate == "village":
			return p
	return null


func leads_post(u: Unit) -> bool:
	var p := post_of(u)
	return p != null and p.captain == u.id


## Working on something the player (not their captain) told them to do.
func under_direct_order(u: Unit) -> bool:
	var c := crew_of(u)
	return c != null and c.post < 0


## Where someone idles, falls back to, flees to and heals.
func resting_place(u: Unit) -> Vector2:
	var p := post_of(u)
	if p == null:
		return home_pos(u.faction)
	return p.refuge if p.alert == "falling_back" else p.center


func join_post(p: Post, u: Unit) -> void:
	if u.post == p.id:
		return
	leave_post(u)
	var c := crew_of(u)
	if c and c.post >= 0:
		release_member(u)
	u.post = p.id
	p.members.append(u.id)


func leave_post(u: Unit) -> void:
	var p := post_of(u)
	u.post = -1
	if p == null:
		return
	p.members.erase(u.id)
	if u.dead:
		p.lost += 1
	if p.captain != u.id:
		return
	var heir: Unit = null
	for m in post_members(p):
		if not m.child:
			heir = m
			break
	if heir == null:
		posts.erase(p.id)
		if p.faction == 0:
			post(0, "Nobody is left to run the %s." % p.name, "alarm")
		return
	var c := crew_of(heir)
	if c and c.post >= 0:
		release_member(heir)
	p.captain = heir.id
	heir.captain = true
	if p.faction == 0:
		post(0, "Captain %s has %s the %s. %s takes over as captain." % [u.name, "fallen at" if u.dead else "left", p.name, heir.name], "alarm")


## More hands for a job already under way.
func add_to_crew(c: Crew, people: Array) -> void:
	var task: String = c.steps[c.idx]["action"] if c.idx < c.steps.size() else "idle"
	for u: Unit in people:
		_join(c, u)
		_set_task(u, task)
		c.start_size += 1
	_assign_slots(c)


# --- Crews ---------------------------------------------------------------------

func crew_of(u: Unit) -> Crew:
	return crews.get(u.crew) if u.crew >= 0 else null


func make_crew(faction: int, members: Array) -> Crew:
	var c := Crew.new()
	c.id = new_id()
	c.faction = faction
	crews[c.id] = c
	for u in members:
		_join(c, u)
	return c


func _join(c: Crew, u: Unit) -> void:
	if u.crew == c.id:
		return
	leave_crew(u)
	u.crew = c.id
	c.members.append(u.id)
	if c.leader < 0:
		_set_leader(c, u.id)


func _set_leader(c: Crew, id: int) -> void:
	c.leader = id
	var lead := unit(id)
	# Inside a post only the post has a captain. A crew there ends when its work does.
	c.captain = lead != null and lead.captain and lead.post < 0


func leave_crew(u: Unit) -> void:
	var c := crew_of(u)
	if u.in_tower >= 0:
		leave_tower(u)
	u.crew = -1
	_release_claim(u)
	if c == null:
		return
	var lost_captain := c.captain and c.leader == u.id
	c.members.erase(u.id)
	c.start_size = maxi(0, c.start_size - 1)
	if c.leader == u.id:
		_set_leader(c, c.members[0] if not c.members.is_empty() else -1)
	if c.members.is_empty():
		_cancel_sites(c)
		crews.erase(c.id)
	elif lost_captain and not c.captain and c.idx >= c.steps.size():
		dissolve(c)
	else:
		_assign_slots(c)


## Takes someone who died out of their crew. A dead captain is succeeded by the longest-serving member.
func drop_dead(c: Crew, id: int) -> void:
	c.members.erase(id)
	c.lost += 1
	if c.leader != id:
		return
	var had_captain := c.captain
	_set_leader(c, c.members[0] if not c.members.is_empty() else -1)
	var heir := unit(c.leader)
	if not had_captain or heir == null:
		return
	heir.captain = true
	c.captain = true
	if c.faction == 0:
		var fallen := unit(id)
		post(0, "Captain %s has fallen. %s takes over as captain." % [fallen.name if fallen else "", heir.name], "alarm")


func release_member(u: Unit) -> void:
	leave_crew(u)
	if u.task == "tame":
		var horse := unit(u.tgt_unit)
		if horse and horse.driver == u.id:
			horse.driver = -1
	if u.siege >= 0:
		var engine := unit(u.siege)
		if engine:
			engine.crew_ids.erase(u.id)
		u.siege = -1
	u.tgt_unit = -1
	u.enemy_bld = -1
	_set_task(u, "idle")


func dissolve(c: Crew) -> void:
	for id in c.members.duplicate():
		var u := unit(id)
		if u:
			u.crew = -1
			_set_task(u, "idle")
	c.members.clear()
	crews.erase(c.id)


func crew_label(c: Crew) -> String:
	var lead := unit(c.leader)
	var n := c.members.size()
	if lead == null:
		return "a crew"
	var title := "Captain " + lead.name if c.captain else lead.name
	return title if n == 1 else "%s's crew (%d)" % [title, n]


func is_free_adult(u: Unit) -> bool:
	return not u.dead and u.kind == "villager" and not u.child and u.crew < 0 and u.siege < 0 and u.stable < 0 and not leads_post(u)


## Idle adults of a faction, nearest to p first.
func idle_adults(faction: int, p: Vector2) -> Array:
	var out := []
	for u: Unit in units:
		if u.faction == faction and is_free_adult(u):
			out.append(u)
	out.sort_custom(func(a, b): return a.pos.distance_squared_to(p) < b.pos.distance_squared_to(p))
	return out


## When there are no idle adults, pull workers from the largest gathering crews.
func _pull_workers(faction: int, p: Vector2, n: int, exclude: Crew) -> Array:
	var out := []
	var pool := []
	for c: Crew in crews.values():
		if c == exclude or c.faction != faction or c.captain or c.idx >= c.steps.size():
			continue
		var a: String = c.steps[c.idx]["action"]
		if a == "gather" and c.members.size() > 1:
			for id in c.members:
				pool.append(unit(id))
	# Take from wood, stone and ore before food, nearest first.
	pool.sort_custom(func(a, b):
		var fa := _is_food_worker(a)
		var fb := _is_food_worker(b)
		if fa != fb:
			return fb
		return a.pos.distance_squared_to(p) < b.pos.distance_squared_to(p))
	for u in pool:
		if out.size() >= n:
			break
		if u and not u.dead:
			out.append(u)
	return out


## Everyone in the faction's crews who is gathering `subject` ("" = anything), latest joiners first.
## Captains' own loose crews are left alone. Work a captain handed out counts: the order overrides it.
func gatherers_of(faction: int, subject: String) -> Array:
	var out := []
	for c: Crew in crews.values():
		if c.faction != faction or c.captain or c.idx >= c.steps.size():
			continue
		var s: Dictionary = c.steps[c.idx]
		if s["action"] != "gather" or (subject != "" and s["subject"] != subject):
			continue
		for i in range(c.members.size() - 1, -1, -1):
			var u := unit(c.members[i])
			if u and not u.dead and not u.child:
				out.append(u)
	return out


## "Take n people off wood": they stop and are free again. n = 0 means everyone gathering it.
func free_workers(faction: int, subject: String, n: int) -> Array:
	var taken := gatherers_of(faction, subject)
	if n > 0:
		taken = taken.slice(0, n)
	for u: Unit in taken:
		_remember_worker(u)
		release_member(u)
	return taken


## "Put n more people under this captain": free hands first, then people on the named work.
## They join the post, so the captain gives them whatever job is short, within about a second.
func assign_to_post(p: Post, subject: String, n: int) -> int:
	var f := p.faction
	var pool := []
	if subject == "":
		for u in idle_adults(f, p.center):
			if u.post != p.id:
				pool.append(u)
	if n == 0 and subject == "":
		pass      # everyone who is free
	else:
		for u in gatherers_of(f, subject):
			if u.post != p.id and not pool.has(u):
				pool.append(u)
	if n > 0:
		pool = pool.slice(0, n)
	put_in_post(p, pool)
	return pool.size()


## Make these people members of the post, ending whatever they were doing for someone else.
func put_in_post(p: Post, people: Array) -> void:
	for u: Unit in people:
		if u.crew >= 0:
			_remember_worker(u)
			release_member(u)
		join_post(p, u)
	if p.target > 0:
		p.target = maxi(p.target, p.members.size())


func _is_food_worker(u: Unit) -> bool:
	var c := crew_of(u)
	if c == null or c.idx >= c.steps.size():
		return false
	return c.steps[c.idx].get("subject", "") in ["berries", "farm", "hunt"]


func recruit(c: Crew, want: int, p: Vector2) -> int:
	var need := want - c.members.size()
	if need <= 0:
		return 0
	var got := 0
	for u in idle_adults(c.faction, p):
		if got >= need:
			break
		_join(c, u)
		got += 1
	if got < need:
		for u in _pull_workers(c.faction, p, need - got, c):
			_remember_worker(u)
			_join(c, u)
			got += 1
	return got


func start_plan(c: Crew, steps: Array) -> void:
	var lead: String = str(steps[0].get("action", "")) if not steps.is_empty() else ""
	if lead in Defs.MILITARY_ACTIONS:
		_remember_crew_work(c)
	elif lead in Defs.WORK_ACTIONS:
		for id in c.members:
			work_memory.erase(id)
	for id in c.members:
		var u := unit(id)
		if u:
			_release_claim(u)
	_cancel_sites(c)
	c.steps = steps
	c.idx = 0
	c.done = false
	c.lost = 0
	_begin_step(c)


# --- Back to work ---------------------------------------------------------------
# A military order (to arms, attack, fall back...) remembers what each person was doing,
# so "back to work" can put everyone back on it. Memories older than this are ignored,
# so a standing army drafted long ago isn't disbanded by an emergency call-up.
const WORK_MEMORY_TIME := 900.0


## What this crew is doing, in a form "back to work" can restart. {} if it isn't working.
func _work_entry(c: Crew) -> Dictionary:
	if c.captain:
		return {}
	if c.steps.is_empty():
		# A fresh crew of idle villagers: going back means going back to idle.
		return {"group": c.id, "steps": [], "loop": false, "t": t}
	if c.idx >= c.steps.size() or not str(c.steps[c.idx].get("action", "")) in Defs.WORK_ACTIONS:
		return {}
	var steps: Array = c.steps.slice(c.idx).duplicate(true)
	var first: Dictionary = steps[0]
	var amount := int(first.get("amount", 0))
	if amount > 0:
		var done := int(c.state.get("made", 0)) if first["action"] == "craft" else int(c.state.get("delivered", 0.0))
		if done >= amount:
			steps.remove_at(0)
		else:
			first["amount"] = amount - done
	for s in steps:
		s["count"] = 0
	return {"group": c.id, "steps": steps, "loop": c.loop, "t": t}


func _remember(u: Unit, entry: Dictionary) -> bool:
	var old = work_memory.get(u.id)
	if old != null and t - float(old["t"]) <= WORK_MEMORY_TIME:
		return false  # keep the earliest memory: that's the real job
	work_memory[u.id] = entry
	return true


## Called as a crew is about to take a military order.
func _remember_crew_work(c: Crew) -> void:
	var entry := _work_entry(c)
	if entry.is_empty():
		return
	var used := false
	for id in c.members:
		var u := unit(id)
		if u and _remember(u, entry):
			used = true
	if used:
		# The unbuilt sites stay on the map for when they return.
		for i in range(c.idx, c.steps.size()):
			c.steps[i]["sites"] = []


## A worker is being pulled out of a working crew to fill another order.
func _remember_worker(u: Unit) -> void:
	var c := crew_of(u)
	if c == null:
		return
	var entry := _work_entry(c)
	if not entry.is_empty():
		_remember(u, entry)


func _crew_is_working(c: Crew) -> bool:
	return c.idx < c.steps.size() and str(c.steps[c.idx].get("action", "")) in Defs.WORK_ACTIONS


## Put people back on the work a military order pulled them off. `only` limits it to those ids.
## Returns how many went back. Anyone who has since been given new work is left alone.
func resume_work(faction: int, only: Array = []) -> int:
	var groups := {}
	for id in work_memory.keys():
		var u := unit(id)
		if u == null or u.dead:
			work_memory.erase(id)
			continue
		if u.faction != faction or (not only.is_empty() and not only.has(id)):
			continue
		var entry: Dictionary = work_memory[id]
		work_memory.erase(id)
		if t - float(entry["t"]) > WORK_MEMORY_TIME or u.child or u.siege >= 0:
			continue
		var cur := crew_of(u)
		if cur != null and (cur.captain or _crew_is_working(cur)):
			continue
		var key: int = entry["group"]
		if not groups.has(key):
			groups[key] = {"entry": entry, "units": []}
		groups[key]["units"].append(u)
	var back := 0
	for g in groups.values():
		var us: Array = g["units"]
		var steps: Array = g["entry"]["steps"].duplicate(true)
		back += us.size()
		# Nobody works with a weapon in hand or on horseback: gear goes back to the armory, horses to the stable.
		# The one exception is a field ram, which is built under arms.
		var carrying := not _keeps_arms(steps) and us.any(func(u): return _needs_stowing(u))
		if steps.is_empty() and not carrying:
			for u in us:
				release_member(u)
			continue
		if carrying:
			steps.push_front({"action": "disarm", "subject": "", "count": 0, "amount": 0, "where": "", "sites": []})
		var crew := crew_of(us[0])
		var same := crew != null and crew.members.size() == us.size()
		if same:
			for u in us:
				if u.crew != crew.id:
					same = false
		if not same:
			for u in us:
				release_member(u)
			crew = make_crew(faction, us)
		crew.loop = bool(g["entry"]["loop"])
		start_plan(crew, steps)
	return back


## Whether the work being returned to is done under arms. Only the job in hand counts:
## a ram that is already finished doesn't let the crew carry weapons to the next job.
func _keeps_arms(steps: Array) -> bool:
	for s: Dictionary in steps:
		if not s["action"] in ["build", "resume"]:
			return false
		for sid in s.get("sites", []):
			var b := bld(sid)
			if b != null and not b.dead and not b.complete:
				return bool(Defs.BUILDINGS.get(b.type, {}).get("keeps_arms", false))
	return false


## The rival drops its unstarted sites. A player's sites wait to be resumed.
func _cancel_sites(c: Crew) -> void:
	if not fac(c.faction).is_ai:
		return
	for s in c.steps:
		for sid in s.get("sites", []):
			var b := bld(sid)
			if b and not b.dead and not b.paid and b.work <= 0.0:
				remove_building(b, "cancelled")


func cancel_plan(c: Crew) -> void:
	_cancel_sites(c)
	c.steps = []
	c.idx = 0
	c.done = true
	for id in c.members:
		var u := unit(id)
		if u:
			_set_task(u, "idle")
	if not c.captain:
		dissolve(c)


func _set_task(u: Unit, task: String) -> void:
	if u.in_tower >= 0:
		leave_tower(u)
	_release_claim(u)
	u.task = task
	u.phase = ""
	u.enemy_bld = -1
	u.tgt_bld = -1
	u.work_t = 0.0
	u.path = PackedVector2Array()
	u.scout_leg = 0


func _release_claim(u: Unit) -> void:
	if u.tgt_node >= 0 and claims.has(u.tgt_node):
		claims[u.tgt_node] = maxi(0, int(claims[u.tgt_node]) - 1)
	u.tgt_node = -1


func _claim(u: Unit, n) -> void:
	_release_claim(u)
	u.tgt_node = n.id
	claims[n.id] = int(claims.get(n.id, 0)) + 1


func crew_center(c: Crew) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in c.members:
		var u := unit(id)
		if u and not u.dead:
			s += u.pos
			n += 1
	return s / n if n > 0 else fac(c.faction).start


## Resolve a step's "where" into a point on the map. null when unknown.
func resolve_where(c: Crew, where: String, default_dist: float = 140.0):
	var f := fac(c.faction)
	match where:
		"", "here":
			if where == "here" or c.state.get("here_default", false):
				var cmd := unit(f.commander)
				if cmd and not cmd.dead:
					return cmd.pos
			return crew_center(c)
		"home":
			return home_pos(c.faction)
		"marked":
			return f.mark if f.has_mark else null
		"enemy":
			return enemy_ground(c.faction)["pos"]
	if where.begins_with(Defs.PLACE):
		var place: Dictionary = places_of(c.faction).get(where.substr(Defs.PLACE.length()), {})
		return place.get("pos")
	var v := Terrain.direction_vector(where)
	var p := home_pos(c.faction) + v * default_dist
	return p.clamp(Vector2(20, 20), Vector2(map_size - 20, map_size - 20))


## Every living rival's camp this faction has seen: [{"faction", "pos", "t"}, ...].
## Only campfires count; the rival AI relies on that. Use known_enemy_ground for orders.
func known_camps(faction: int) -> Array:
	var out := []
	var f := fac(faction)
	for k in f.intel:
		var e: Dictionary = f.intel[k]
		if e.get("kind", "") != "building" or e.get("type", "") != "campfire":
			continue
		var who := int(e.get("faction", -1))
		if who >= 0 and who != faction and factions[who].alive:
			out.append({"faction": who, "pos": e["pos"], "t": e["t"]})
	return out


## The nearest of those camps, or {}.
func known_enemy(faction: int) -> Dictionary:
	var best := {}
	var home := home_pos(faction)
	for camp in known_camps(faction):
		if best.is_empty() or (camp["pos"] as Vector2).distance_squared_to(home) < (best["pos"] as Vector2).distance_squared_to(home):
			best = camp
	return best


func known_enemy_camp(faction: int):
	return known_enemy(faction).get("pos")


## Where to send the player's troops against a rival: the camp if seen, otherwise the
## nearest rival building seen, otherwise the best guess. Returns {"pos", "faction", "sure"}.
func enemy_ground(faction: int) -> Dictionary:
	var camp := known_enemy(faction)
	if not camp.is_empty():
		return {"pos": camp["pos"], "faction": camp["faction"], "sure": true}
	var home := home_pos(faction)
	var best := {}
	for k in fac(faction).intel:
		var e: Dictionary = fac(faction).intel[k]
		if e.get("kind", "") != "building":
			continue
		var who := int(e.get("faction", -1))
		if who < 0 or who == faction or not factions[who].alive:
			continue
		if best.is_empty() or (e["pos"] as Vector2).distance_squared_to(home) < (best["pos"] as Vector2).distance_squared_to(home):
			best = {"pos": e["pos"], "faction": who, "sure": true}
	if not best.is_empty():
		return best
	return {"pos": _enemy_guess(faction), "faction": -1, "sure": false}


func _begin_step(c: Crew) -> void:
	while c.idx < c.steps.size():
		var s: Dictionary = c.steps[c.idx]
		c.state = {"t0": t, "delivered": 0.0, "made": 0, "batch_t": 0.0, "batch_paid": false}
		var want := int(s.get("count", 0))
		if want > 0:
			recruit(c, want, crew_center(c) if not c.members.is_empty() else home_pos(c.faction))
		if c.members.is_empty():
			c.done = true
			return
		c.start_size = c.members.size()
		_remember_sites(c)
		var err := _prepare_step(c, s)
		if err == "":
			for id in c.members:
				var u := unit(id)
				if u:
					_set_task(u, s["action"])
			_assign_slots(c)
			return
		if c.faction == 0:
			post(0, "%s: %s" % [crew_label(c), err], "warn")
		c.idx += 1
	_finish_plan(c)


## So people ordered away can be told to carry on with what they were building.
func _remember_sites(c: Crew) -> void:
	var sites := []
	for s in c.steps:
		sites.append_array(s.get("sites", []))
	if sites.is_empty():
		return
	for id in c.members:
		var u := unit(id)
		if u:
			u.last_sites = sites


## Checks a step can start and fills crew.state. Returns a problem or "".
func _prepare_step(c: Crew, s: Dictionary) -> String:
	var f := fac(c.faction)
	var a: String = s["action"]
	var subj: String = s.get("subject", "")
	match a:
		"gather":
			var g: Dictionary = Defs.GATHER[subj]
			if g.has("building") and not g.has("node"):
				var types := [g["building"]]
				var have := false
				for b in buildings_of(c.faction, g["building"]):
					if subj in Defs.DEPOSITS and b.deposit != subj:
						continue
					have = true
				if not have:
					if subj in Defs.DEPOSITS:
						return "we need a mine on a %s deposit first." % Defs.RESOURCE_NAMES[subj]
					return "we need a %s first." % Defs.building_name(types[0]).to_lower()
			var where: String = s.get("where", "")
			var p = resolve_where(c, where, 120.0)
			c.state["origin"] = p if p != null else crew_center(c)
			c.state["named_place"] = where != "" and p != null
		"build":
			var sites: Array = s.get("sites", [])
			var live := []
			var finished := false
			for sid in sites:
				var b := bld(sid)
				if b and not b.dead:
					if b.complete:
						finished = true
					else:
						live.append(sid)
			if live.is_empty() and not finished:  # if others finished it, the step is simply done
				return "there's no site placed for the %s." % Defs.building_name(subj).to_lower()
			c.state["sites"] = live
		"upgrade":
			var up_id := _upgrade_for(c.faction, subj)
			if up_id.begins_with("!"):
				return up_id.substr(1)
			var b := nearest_building(c.faction, crew_center(c), [subj])
			c.state["bld"] = b.id
			c.state["up"] = up_id
			if b.upgrading == "":
				b.upgrading = up_id
				b.up_work = 0.0
				b.up_paid = false
		"craft":
			# Nobody works at the armory. The order goes into an armory's queue and the armory makes it.
			var amt := int(s.get("amount", 0))
			var queued_why := queue_craft(c.faction, subj, amt)
			if queued_why != "":
				return queued_why
			var n := amt if amt > 0 else int(Defs.ITEMS[subj]["batch"])
			c.state["want"] = n
			c.state["made"] = n
		"arm":
			var arm := nearest_building(c.faction, crew_center(c), ["armory"])
			if arm == null:
				return "we need an armory first."
			c.state["bld"] = arm.id
			if subj != "" and int(f.gear.get(subj, 0)) <= 0:
				return "there are no %s in the armory. Make some with /c." % Defs.item_name(subj, 2)
		"disarm":
			var arm := nearest_building(c.faction, crew_center(c), ["armory"])
			c.state["bld"] = arm.id if arm != null else -1
		"mount":
			var st := _stable_with_horse(c.faction, crew_center(c))
			if st == null:
				return "there are no horses in a stable."
			c.state["bld"] = st.id
		"man":
			var eng := _free_engine(c.faction, subj, crew_center(c))
			if eng == null:
				return "there's no %s waiting for a crew. Make one at the armory." % Defs.item_name(subj)
			c.state["engine"] = eng.id
		"smelt":
			var sm: Dictionary = Defs.SMELT[subj]
			var best: Building = null
			for b in buildings_of(c.faction, "smelter"):
				if b.tier >= int(sm["tier"]):
					best = b
			if best == null:
				return "we need a smelter first." if sm["tier"] == 0 else "the smelter has to be upgraded to an iron furnace first."
			c.state["bld"] = best.id
		"research":
			# Nobody works on research. The crew only sets it going, and the building does the rest.
			var why := start_research(c.faction, subj)
			if why != "":
				return why
		"tame":
			if buildings_of(c.faction, "stable").is_empty():
				return "we need a stable to keep horses in."
			var p = resolve_where(c, s.get("where", ""), 200.0 * terrain.size_scale)
			c.state["origin"] = p if p != null else home_pos(c.faction)
		"scout":
			var where: String = s.get("where", "")
			var p = null
			if where == "enemy":
				p = known_enemy_camp(c.faction)
				if p == null:
					p = _enemy_guess(c.faction)
			elif where in ["", "here"]:
				p = _enemy_guess(c.faction)
			else:
				p = resolve_where(c, where, 380.0 * terrain.size_scale)
			if p == null:
				return "mark a spot first (look at the ground and press R)."
			c.state["target"] = p
		"guard", "hold":
			var where: String = s.get("where", "")
			var p = crew_center(c) if a == "hold" and where == "" else resolve_where(c, where if where != "" else "here", 120.0)
			if p == null:
				return "mark a spot first (look at the ground and press R)."
			c.state["target"] = p
		"attack":
			var where: String = s.get("where", "")
			var ground := {}
			if where in ["", "enemy"]:
				ground = enemy_ground(c.faction)
			var p = ground["pos"] if not ground.is_empty() else resolve_where(c, where, 380.0 * terrain.size_scale)
			if p == null:
				return "mark a spot first (look at the ground and press R)."
			c.state["target"] = p
			if not ground.is_empty():
				c.state["foe"] = ground["faction"]
				if not ground["sure"] and c.faction == 0:
					post(0, "We haven't seen their camp yet, so we're marching to where it should be. Troops will spot it on the way.")
		"follow":
			if unit(f.commander) == null:
				return "there's no one to follow."
		"recall":
			c.state["target"] = home_pos(c.faction)
		"promote":
			var lead := unit(c.leader)
			if lead and not leads_post(lead):
				# Their own crew now, outside any post.
				for id in c.members:
					var mate := unit(id)
					if mate and not leads_post(mate):
						leave_post(mate)
				lead.captain = true
				c.captain = true
				c.loop = false
				if c.faction == 0:
					post(0, "%s is now a captain. Address their crew by looking at a member." % lead.name, "info")
		"dismiss", "status":
			pass
	return ""


func _upgrade_for(faction: int, building: String) -> String:
	var f := fac(faction)
	if building == "armory":
		return "!armory upgrades are researched now. Type /r."
	var b := nearest_building(faction, home_pos(faction), [building])
	if b == null:
		return "!we need a %s first." % building
	for id in Defs.UPGRADES:
		var up: Dictionary = Defs.UPGRADES[id]
		if up["building"] == building and int(up["from"]) == b.tier:
			if f.age < int(up["age"]):
				return "!that needs the %s age: %s" % [Defs.AGES[up["age"]], Defs.AGE_HOW[up["age"]].to_lower()]
			return id
	return "!the %s is fully upgraded." % building


func craft_problem(faction: int, item: String) -> String:
	var f := fac(faction)
	var it: Dictionary = Defs.ITEMS[item]
	var arm := nearest_building(faction, home_pos(faction), ["armory"])
	if arm == null:
		return "we need an armory first."
	var top := 0
	for b in buildings_of(faction, "armory"):
		top = maxi(top, b.tier)
	if top < int(it["tier"]):
		return "research the %s armory first (/r)." % ["wood", "bronze", "iron"][it["tier"]]
	if it.has("research") and not f.researched.has(it["research"]):
		return "that needs %s research at a university." % it["research"]
	return ""


## What the faction has paid for so far: research that is running, so it can't be started twice.
func is_researching(faction: int, id: String) -> bool:
	for b in own_blds[faction]:
		if not b.dead and b.research == id:
			return true
	return false


func _research_progress(faction: int, id: String) -> float:
	for b in own_blds[faction]:
		if not b.dead and b.research == id:
			return b.research_t / float(Defs.RESEARCH[id]["time"])
	return 0.0


## The research problem in words, or "" when it can start now.
func research_problem(faction: int, id: String) -> String:
	var f := fac(faction)
	var r: Dictionary = Defs.RESEARCH[id]
	if f.researched.has(id):
		return "we already know %s." % r["name"].to_lower()
	if is_researching(faction, id):
		return "%s is already being researched." % r["name"]
	if not has_building(faction, r["building"]):
		return "we need a %s first." % Defs.building_name(r["building"]).to_lower()
	if f.age < int(r["age"]):
		return "that needs the %s age." % Defs.AGES[r["age"]]
	if r.has("requires") and not f.researched.has(r["requires"]):
		return "that needs the %s first." % Defs.RESEARCH[r["requires"]]["name"].to_lower()
	if _free_lab(faction, r["building"]) == null:
		return "the %s is busy with other research." % Defs.building_name(r["building"]).to_lower()
	return ""


func _free_lab(faction: int, type: String) -> Building:
	for b in buildings_of(faction, type):
		if b.research == "":
			return b
	return null


## Most items an armory will hold in its queue. A full queue refuses the order.
const QUEUE_MAX := 12


## Puts items into the queue of the least busy armory that can make them. Nobody works there.
## The armory pays for each item as it starts it, and makes them one at a time.
func queue_craft(faction: int, item: String, amount: int) -> String:
	var why := craft_problem(faction, item)
	if why != "":
		return why
	var it: Dictionary = Defs.ITEMS[item]
	var batch := int(it["batch"])
	var entries := ceili(float(amount if amount > 0 else batch) / float(batch))
	var arm: Building = null
	for b: Building in buildings_of(faction, "armory"):
		if not b.complete or b.tier < int(it["tier"]):
			continue
		if arm == null or b.queue.size() < arm.queue.size():
			arm = b
	if arm == null:
		return "no armory is ready to make %s." % Defs.item_name(item, 2)
	if arm.queue.size() + entries > QUEUE_MAX:
		return "the armory queue is full (%d waiting)." % arm.queue.size()
	for i in entries:
		arm.queue.append(item)
	if faction == 0:
		var made := entries * batch
		post(0, "The armory will make %d %s." % [made, Defs.item_name(item, made)], "info")
	return ""


## Each armory works its queue by itself, one item at a time, paying for each item as it starts.
func _update_armories(dt: float) -> void:
	for b: Building in buildings:
		if b.dead or not b.complete or b.queue.is_empty():
			continue
		var item: String = b.queue[0]
		var it: Dictionary = Defs.ITEMS[item]
		if b.make_t <= 0.0:
			var cost := Defs.item_cost(item, armory_tier(b.faction))
			if not pay(b.faction, cost):
				if b.faction == 0 and t - b.waiting_msg_t > 25.0:
					b.waiting_msg_t = t
					post(0, "The armory is waiting for %s to make %s." % [Defs.cost_text(missing_cost(0, cost)), Defs.item_name(item, 2)], "warn")
				continue
		b.make_t += dt
		if b.make_t < float(it["time"]):
			continue
		b.make_t = 0.0
		b.queue.pop_front()
		_finish_make(b, item)


func _finish_make(b: Building, item: String) -> void:
	var it: Dictionary = Defs.ITEMS[item]
	var n := int(it["batch"])
	sound("anvil" if int(it["tier"]) > 0 else "hammer", b.pos)
	if it["slot"] == "siege":
		var e := spawn_unit(b.faction, item, b.pos + Vector2.from_angle(b.rot + PI * 0.5) * (b.size.y * 0.5 + 3.0))
		e.ammo = 0
		emit({"type": "unit", "id": e.id})
	else:
		var f := fac(b.faction)
		f.gear[item] = int(f.gear.get(item, 0)) + n
	if b.faction == 0 and b.queue.is_empty():
		post(0, "The armory has finished its queue.", "done")


## Pays for the research and sets it going in a free building. It then runs by itself.
func start_research(faction: int, id: String) -> String:
	var why := research_problem(faction, id)
	if why != "":
		return why
	var r: Dictionary = Defs.RESEARCH[id]
	if not pay(faction, r["cost"]):
		return "we need %s for that." % Defs.cost_text(missing_cost(faction, r["cost"]))
	var lab := _free_lab(faction, r["building"])
	lab.research = id
	lab.research_t = 0.0
	if faction == 0:
		post(0, "Researching %s (%d s)." % [r["name"].to_lower(), int(r["time"])], "info")
	return ""


func _update_research(dt: float) -> void:
	for b: Building in buildings:
		if b.dead or b.research == "" or not b.complete:
			continue
		var r: Dictionary = Defs.RESEARCH[b.research]
		b.research_t += dt
		if b.research_t < float(r["time"]):
			continue
		var f := fac(b.faction)
		f.researched[b.research] = true
		b.research = ""
		b.research_t = 0.0
		if r.has("armory_tier"):
			_raise_armories(b.faction, int(r["armory_tier"]))
		if b.faction == 0:
			post(0, "Research complete: %s. %s" % [r["name"], r["desc"]], "done")
		sound("complete", b.pos, b.faction)
		if r.has("opens_age"):
			_open_age(f, int(r["opens_age"]))


## Every armory takes the researched tier at once.
func _raise_armories(faction: int, tier: int) -> void:
	for a in buildings_of(faction, "armory", false):
		if a.tier < tier:
			a.tier = tier
			emit({"type": "building", "id": a.id})


func researched_armory_tier(faction: int) -> int:
	var top := 0
	var f := fac(faction)
	for id in f.researched:
		top = maxi(top, int(Defs.RESEARCH.get(id, {}).get("armory_tier", 0)))
	return top


func armory_tier(faction: int) -> int:
	var top := -1
	for b in buildings_of(faction, "armory"):
		top = maxi(top, b.tier)
	return top


func _stable_with_horse(faction: int, p: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for u: Unit in units:
		if u.dead or u.kind != "horse" or u.faction != faction or u.stable < 0 or u.child:
			continue
		var st := bld(u.stable)
		if st and not st.dead and st.pos.distance_squared_to(p) < bd:
			bd = st.pos.distance_squared_to(p)
			best = st
	return best


func _free_engine(faction: int, kind: String, p: Vector2) -> Unit:
	var best: Unit = null
	var bd := INF
	var need := int(Defs.ITEMS[kind]["crew"])
	for u: Unit in units:
		if u.dead or u.kind != kind or u.faction != faction:
			continue
		var live := 0
		for id in u.crew_ids:
			var m := unit(id)
			if m and not m.dead:
				live += 1
		if live >= need:
			continue
		var d := u.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = u
	return best


func _enemy_guess(faction: int):
	var e = known_enemy_camp(faction)
	if e != null:
		return e
	var home := home_pos(faction)
	var c := Vector2(map_size, map_size) * 0.5
	if factions.size() > 2:
		return _unexplored_on_ring(faction, home, c)
	# Two camps face each other across the middle of the map.
	return (c * 2.0 - home).clamp(Vector2(40, 40), Vector2(map_size - 40, map_size - 40))


## With several camps, all anyone knows is that they stand on a ring. Go to the nearest
## part of it this faction hasn't seen, or failing that the part seen longest ago.
func _unexplored_on_ring(faction: int, home: Vector2, c: Vector2) -> Vector2:
	var known := fac(faction).knowledge
	var r: float = map_size * 0.5 - float(terrain.config["margin"])
	var from := (home - c).angle()
	var best := c
	var best_seen := INF
	# Outwards from home to either side, starting past the home kit.
	for k in range(2, 13):
		for side in [1.0, -1.0]:
			var p := c + Vector2.from_angle(from + side * k * TAU / 24.0) * r
			if p.distance_to(home) < Defs.RING_SPACING * 0.8:
				continue
			var seen: float = known[kcell(p)]
			if seen < best_seen:
				best_seen = seen
				best = p
	return best


func _advance(c: Crew) -> void:
	c.idx += 1
	_begin_step(c)


func _finish_plan(c: Crew) -> void:
	c.done = true
	if c.loop and not c.steps.is_empty():
		# Returning gear is a one-off at the start of the plan, not part of the loop.
		c.idx = 1 if c.steps.size() > 1 and c.steps[0]["action"] == "disarm" else 0
		c.done = false
		_begin_step(c)
		return
	if c.captain:
		for id in c.members:
			var u := unit(id)
			if u:
				_set_task(u, "idle")
		return
	dissolve(c)


func _assign_slots(c: Crew) -> void:
	var live := []
	for id in c.members:
		var u := unit(id)
		if u and not u.dead:
			live.append(u)
	# Shields and pikes in front, archers at the back.
	live.sort_custom(func(a, b): return _rank(a) < _rank(b))
	var per_row := clampi(int(ceil(sqrt(live.size() * 2.0))), 1, 10)
	for i in live.size():
		var row := i / per_row
		var col := i % per_row
		var n_in_row := mini(per_row, live.size() - row * per_row)
		live[i].slot = Vector2((col - (n_in_row - 1) * 0.5) * 1.9, -row * 2.0)
	c.depth = maxf(0.0, float((live.size() - 1) / per_row) * 2.0)
	c.width = maxf(2.2, (mini(per_row, live.size()) - 1) * 1.9 + 2.2)


func _rank(u: Unit) -> int:
	if u.bow and u.weapon == "":
		return 3
	if u.shield != "" or u.weapon.ends_with("pike"):
		return 0
	return 1


## World position of a formation slot facing from `from` to `to`.
func slot_point(u: Unit, center: Vector2, facing_dir: Vector2) -> Vector2:
	var fwd := facing_dir.normalized() if facing_dir.length() > 0.01 else Vector2(0, -1)
	var right := Vector2(-fwd.y, fwd.x)
	return center + right * u.slot.x + fwd * u.slot.y


## The crew's centre, worked out once a tick.
func crew_center_now(c: Crew) -> Vector2:
	if c.center_t != t:
		c.center_t = t
		c.center = crew_center(c)
	return c.center


func post_facing(faction: int, target: Vector2) -> Vector2:
	var home := home_pos(faction)
	return (target - home) if target.distance_to(home) > 5.0 else Vector2(0, -1)


## Where this unit stands when guarding or holding.
func station(u: Unit, c: Crew) -> Vector2:
	var target: Vector2 = c.state.get("target", u.pos)
	var dir := post_facing(u.faction, target)
	var spot := slot_point(u, lane_center(c, target, dir), dir)
	if solid_for(u.faction, cell_of(spot)):
		spot = cell_center(nearest_free_cell(maxi(u.faction, 0), cell_of(spot)))
	return spot


## Crews sent to the same place line up side by side instead of inside each other.
func lane_center(c: Crew, center: Vector2, facing_dir: Vector2) -> Vector2:
	if t - c.lane_t >= 1.0:
		c.lane_t = t
		c.lane = _lane_offset(c)
	var lane := c.lane
	if lane == 0.0 or facing_dir.length() < 0.01:
		return center
	var fwd := facing_dir.normalized()
	return center + Vector2(-fwd.y, fwd.x) * lane


func _lane_offset(c: Crew) -> float:
	if c.idx >= c.steps.size():
		return 0.0
	var kind := _post_kind(c.steps[c.idx]["action"])
	var target: Vector2 = c.state.get("target", Vector2.ZERO)
	var sharing := []
	for o: Crew in crews.values():
		if o.faction != c.faction or o.members.is_empty() or o.idx >= o.steps.size():
			continue
		if _post_kind(o.steps[o.idx]["action"]) != kind:
			continue
		if kind != "follow" and (o.state.get("target", Vector2.INF) as Vector2).distance_to(target) > 8.0:
			continue
		sharing.append(o)
	if sharing.size() < 2:
		return 0.0
	sharing.sort_custom(func(a, b): return a.id < b.id)
	var right: float = sharing[0].width * 0.5
	var left := -right
	for i in sharing.size():
		var w: float = sharing[i].width
		var at := 0.0
		if i > 0:
			if i % 2 == 1:
				at = right + w * 0.5
				right += w
			else:
				at = left - w * 0.5
				left -= w
		if sharing[i] == c:
			return at
	return 0.0


func _post_kind(action: String) -> String:
	return "guard" if action == "hold" else action


# --- Crew drivers --------------------------------------------------------------

func update_crews(dt: float) -> void:
	for c: Crew in crews.values():
		# Drop the dead.
		for id in c.members.duplicate():
			var u := unit(id)
			if u == null or u.dead:
				drop_dead(c, id)
		if c.members.is_empty():
			crews.erase(c.id)
			continue
		if c.idx >= c.steps.size():
			if not c.captain and c.done:
				dissolve(c)
			continue
		var s: Dictionary = c.steps[c.idx]
		if _step_done(c, s):
			_advance(c)


func _step_done(c: Crew, s: Dictionary) -> bool:
	var f := fac(c.faction)
	match s["action"]:
		"gather":
			var amt := int(s.get("amount", 0))
			return amt > 0 and c.state["delivered"] >= amt
		"build":
			for sid in c.state.get("sites", []):
				var b := bld(sid)
				if b and not b.dead and not b.complete:
					return false
			return true
		"upgrade":
			var b := bld(c.state.get("bld", -1))
			return b == null or b.dead or b.upgrading != c.state["up"]
		"craft":
			return c.state["made"] >= int(c.state["want"]) or c.state.get("stuck", false)
		"smelt":
			var amt := int(s.get("amount", 0))
			return amt > 0 and c.state["delivered"] >= amt
		"research":
			return true     # set going when the step began, and it runs without the crew
		"tame":
			var amt := int(s.get("amount", 0))
			return c.state.get("full", false) or (amt > 0 and c.state["delivered"] >= amt)
		"arm", "disarm", "mount", "man", "scout", "recall":
			for id in c.members:
				var u := unit(id)
				if u and not u.dead and u.phase != "done":
					return false
			return true
		"promote":
			return true
		"dismiss":
			if c.faction == 0:
				post(0, "%s disbanded." % crew_label(c), "info")
			dissolve(c)
			return false
		"status":
			if c.faction == 0:
				post(0, crew_status(c), "info")
			return true
	return false


func crew_status(c: Crew) -> String:
	var lead := unit(c.leader)
	var who := crew_label(c)
	var armed := 0
	for id in c.members:
		var u := unit(id)
		if u and (u.weapon != "" or u.bow):
			armed += 1
	var doing := "standing by"
	if c.idx < c.steps.size():
		doing = Defs.describe_step(c.steps[c.idx])
		if c.steps.size() > 1:
			doing += " (step %d of %d)" % [c.idx + 1, c.steps.size()]
	var hp := ""
	if lead:
		hp = ", %d%% health" % int(100.0 * lead.hp / lead.max_hp)
	return "%s: %s. %d of %d armed%s." % [who, doing, armed, c.members.size(), hp]


# --- Unit work -----------------------------------------------------------------

func unit_speed(u: Unit) -> float:
	var s: float
	if u.kind == "commander":
		s = Defs.COMMANDER["speed"]
	elif u.child:
		s = Defs.CHILD["speed"]
	else:
		s = Defs.VILLAGER["speed"]
	if u.mounted:
		s = Defs.MOUNTED["speed"]
	var slow := 0.0
	if u.shield != "":
		slow += float(Defs.ITEMS[u.shield].get("slow", 0.0))
	if u.armor != "":
		slow += float(Defs.ITEMS[u.armor].get("slow", 0.0))
	if u.carry > 0.0:
		slow += 0.1
	return s * (1.0 - slow)


## Walks toward goal around anyone in the way. True once within `arrive`, or as near
## as the crowd lets it get when `crowd_ok`.
func move_to(u: Unit, goal: Vector2, dt: float, arrive: float = 1.0, run: bool = false, crowd_ok: bool = true) -> bool:
	var d := u.pos.distance_to(goal)
	if d <= arrive:
		u.path = PackedVector2Array()
		return true
	var same_goal := u.path_goal.distance_squared_to(goal) <= 4.0
	if u.path.is_empty() and same_goal and t < u.path_wait and not (fair_paths and u.path_turn == ticks):
		return false
	if u.path.is_empty() or not same_goal:
		u.path = route_for(u, goal)
		u.path_i = 0
		u.path_goal = goal
		u.climbing = false
		if u.path.is_empty():
			u.path_goal = Vector2(-999, -999)
			return false
		var end := u.path[u.path.size() - 1]
		if end.distance_squared_to(goal) <= 1.0:
			u.dead_ends = 0
		elif crowd_ok and not solid_for(u.faction, cell_of(goal)) and not _enemy_works_between(u.faction, end, goal):
			# No way round. People clamber over their own walls and rough ground, never an enemy's walls.
			u.path.append(goal)
			u.climbing = true
	var last := u.path.size() - 1
	var i := mini(u.path_i, last)
	var wp: Vector2 = u.path[i]
	# Corners only need passing near, or two people would fight over the same point.
	while i < last and u.pos.distance_squared_to(wp) < 1.2 and line_clear(u.faction, u.pos, u.path[i + 1]):
		i += 1
		u.path_i = i
		wp = u.path[i]
	var stride := unit_speed(u) * (1.35 if run else 1.0) * dt
	var to := wp - u.pos
	var dist := to.length()
	u.move_t = t
	var next_pos := wp
	if dist > 0.001:
		next_pos = crowd.step(u, to / dist, minf(stride, dist), self)
		var in_way: Unit = crowd.blocker
		if in_way:
			# The route stops short of the goal and somebody is already standing at its end.
			if i == last and dist < 2.0 and wp.distance_squared_to(u.path_goal) > 1.0:
				u.path = PackedVector2Array()
				_dead_end(u)
				return false
			# Somebody is standing on the spot: this is as close as it gets.
			if crowd_ok and i == last and d <= arrive + 1.2 and in_way.pos.distance_squared_to(goal) < d * d and not in_way.anim in [Anim.WALK, Anim.RUN]:
				u.path = PackedVector2Array()
				return true
		if next_pos != u.pos:
			next_pos = _keep_out(u, next_pos)
			var heading := next_pos - u.pos
			if heading.length_squared() > 0.0001:
				u.facing = atan2(heading.x, heading.y)
	u.pos = next_pos
	if u.mounted:
		u.anim = Anim.RIDE
	elif u.carry > 0.0:
		u.anim = Anim.CARRY
	else:
		u.anim = Anim.RUN if run else Anim.WALK
	var left := u.pos.distance_to(goal)
	if u.pos.distance_squared_to(wp) < 0.0025:
		u.path_i = i + 1
		if i == last:
			u.path = PackedVector2Array()
			if left > arrive:
				if solid_for(u.faction, cell_of(goal)) and left <= arrive + CELL * 1.5:
					return true       # the goal is inside something: next to it will do
				if wp.distance_squared_to(u.path_goal) > 1.0:
					_dead_end(u)            # as far as the ground allows
				else:
					u.path_goal = Vector2(-999, -999)
	return left <= arrive


## A step that would end inside something solid slides along it instead.
func _keep_out(u: Unit, p: Vector2) -> Vector2:
	var to_cell := cell_of(p)
	var from_cell := cell_of(u.pos)
	if to_cell == from_cell or not solid_for(u.faction, to_cell) or solid_for(u.faction, from_cell):
		return p
	if u.climbing and u.path_i >= u.path.size() - 1:
		return p
	if not u.path.is_empty() and not line_clear(u.faction, u.pos, u.path[mini(u.path_i, u.path.size() - 1)]):
		# Jostled off the route: what's ahead is now behind a corner.
		u.path = PackedVector2Array()
		u.path_goal = Vector2(-999, -999)
	var by := p - u.pos
	for alt: Vector2 in [Vector2(by.x, 0), Vector2(0, by.y)]:
		if alt == Vector2.ZERO:
			continue
		var q := u.pos + alt
		if not solid_for(u.faction, cell_of(q)):
			return q
	return u.pos


## A search that can't succeed covers the whole map, so wait longer before each retry.
func _dead_end(u: Unit) -> void:
	u.path_wait = t + minf(4.0, 0.5 * pow(2.0, u.dead_ends))
	u.dead_ends = mini(u.dead_ends + 1, 4)


func _enemy_works_between(faction: int, a: Vector2, b: Vector2) -> bool:
	for o: Building in buildings:
		if o.dead or not o.blocking or o.faction == faction or o.faction < 0:
			continue
		var r := o.size.length() * 0.5
		if Geometry2D.get_closest_point_to_segment(o.pos, a, b).distance_squared_to(o.pos) <= r * r:
			return true
	return false


## Distance from p to the edge of a building's footprint.
func dist_to_building(p: Vector2, b: Building) -> float:
	var local := (p - b.pos).rotated(-b.rot)
	var dx := maxf(absf(local.x) - b.size.x * 0.5, 0.0)
	var dy := maxf(absf(local.y) - b.size.y * 0.5, 0.0)
	return sqrt(dx * dx + dy * dy)


## A spot just outside the footprint, spread around the building per unit.
func approach_point(u: Unit, b: Building, pad: float) -> Vector2:
	var dir := Vector2.from_angle(float(u.id) * GOLDEN_ANGLE)
	var local := dir.rotated(-b.rot)
	var sx := (b.size.x * 0.5 + pad) / maxf(absf(local.x), 0.001)
	var sy := (b.size.y * 0.5 + pad) / maxf(absf(local.y), 0.001)
	return b.pos + dir * minf(sx, sy)


func go_to_building(u: Unit, b: Building, dt: float, pad: float = 1.4, run: bool = false) -> bool:
	if dist_to_building(u.pos, b) <= pad + 1.0:
		return true
	var arrived := move_to(u, approach_point(u, b, pad), dt, 0.7, run)
	var d := dist_to_building(u.pos, b)
	return d <= pad + 1.0 or (arrived and d <= pad + 3.0)


func face(u: Unit, p: Vector2) -> void:
	var d := p - u.pos
	if d.length() > 0.01:
		u.facing = atan2(d.x, d.y)


func work_mult(faction: int) -> float:
	return Defs.FOOD_WORK[fac(faction).food_state]


## How many of a faction's people are working on each resource right now (gathering or smelting).
func workers_by_resource(faction: int) -> Dictionary:
	var out := {}
	for u: Unit in units:
		if u.dead or u.faction != faction or u.kind != "villager" or u.task not in ["gather", "smelt"]:
			continue
		var c := crew_of(u)
		if c == null or c.idx >= c.steps.size():
			continue
		var subj: String = c.steps[c.idx].get("subject", "")
		var res := ""
		if u.task == "gather" and Defs.GATHER.has(subj):
			res = Defs.GATHER[subj]["resource"]
		elif u.task == "smelt":
			res = subj
		if res != "":
			out[res] = int(out.get(res, 0)) + 1
	return out


func update_worker(u: Unit, dt: float) -> void:
	var c := crew_of(u)
	if c == null and u.task != "idle":
		_set_task(u, "idle")
	var s: Dictionary = {}
	if c and c.idx < c.steps.size():
		s = c.steps[c.idx]
	match u.task:
		"gather":
			if s.is_empty():
				_set_task(u, "idle")
				return
			_do_gather(u, c, s, dt)
		"build":
			_do_build(u, c, dt)
		"upgrade":
			_do_upgrade(u, c, dt)
		"arm":
			_do_arm(u, c, s, dt)
		"disarm":
			_do_disarm(u, c, dt)
		"mount":
			_do_mount(u, c, dt)
		"man":
			_do_man(u, c, dt)
		"smelt":
			_do_smelt(u, c, s, dt)
		"tame":
			_do_tame(u, c, s, dt)
		"scout":
			_do_scout(u, c, dt)
		"recall":
			var refuge: Vector2 = resting_place(u) if post_of(u) else c.state.get("target", home_pos(u.faction))
			if move_to(u, refuge + _ring(u, 6.0), dt, 2.0):
				u.phase = "done"
				u.anim = Anim.IDLE
		"guard", "hold", "attack", "follow":
			_do_military(u, c, s, dt)
		"idle", "dismiss", "status", "promote", _:
			_do_idle(u, dt)


const GOLDEN_ANGLE := 2.399963


func _ring(u: Unit, r: float) -> Vector2:
	# Never the same spot twice, and a big group fills several rings.
	var spread := float(u.id % 4) * 1.3 if r > 2.0 else 0.0
	return Vector2.from_angle(float(u.id) * GOLDEN_ANGLE) * (r + spread)


func _do_idle(u: Unit, dt: float) -> void:
	if u.carry > 0.0:
		_unload(u, dt)
		return
	var home := resting_place(u)
	if u.siege >= 0:
		return
	var held := post_of(u)
	if held and held.captain == u.id and held.surveying and held.alert == "":
		_walk_rounds(u, held, dt)
		return
	if u.pos.distance_to(home) > 26.0:
		move_to(u, home + _ring(u, 10.0 + float(u.id % 5) * 2.0), dt, 2.0)
		return
	u.anim = Anim.IDLE
	u.work_t += dt
	if u.work_t > 6.0 + float(u.id % 7):
		u.work_t = 0.0
		u.goal = home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(7.0, 20.0)
		u.phase = "stroll"
	if u.phase == "stroll":
		if move_to(u, u.goal, dt, 0.8):
			u.phase = ""


## Carries what's in hand to a drop-off. True once it's in the stores.
func _unload(u: Unit, dt: float) -> bool:
	var dp := nearest_dropoff(u.faction, u.pos, u.carry_res)
	if dp == null or not go_to_building(u, dp, dt):
		return false
	add_stock(u.faction, u.carry_res, u.carry)
	u.carry = 0.0
	return true


## A captain still looking for an outcrop or deposit walks the bounds: an outer lap, then an inner one.
func _walk_rounds(u: Unit, p: Post, dt: float) -> void:
	const STOPS := 16
	var out: float = [0.82, 0.5][(p.rounds / STOPS) % 2]
	var goal := (p.center + Vector2.from_angle(p.rounds * TAU / STOPS) * p.radius * out).clamp(Vector2(20, 20), Vector2(map_size - 20, map_size - 20))
	u.work_t += dt
	# A stop on a cliff or in a lake of trees is skipped after a while.
	if move_to(u, goal, dt, 8.0) or u.work_t > 40.0:
		u.work_t = 0.0
		p.rounds += 1


func _do_gather(u: Unit, c: Crew, s: Dictionary, dt: float) -> void:
	var subj: String = s["subject"]
	var g: Dictionary = Defs.GATHER[subj]
	var res: String = g["resource"]
	if subj == "hunt":
		_do_hunt(u, c, dt)
		return
	# Building-based work (farm, mine, quarry) feeds the stockpile directly.
	if g.has("building") and (not g.has("node") or not buildings_of(u.faction, g["building"]).is_empty()):
		var b := bld(u.tgt_bld)
		if b == null or b.dead:
			b = _work_building(u, g["building"], subj)
			if b == null:
				if not g.has("node"):
					# Every place is taken: free this person for other work.
					if u.faction == 0 and not c.state.get("full_warned", false):
						c.state["full_warned"] = true
						post(0, "Only %d can work each %s; the rest are free for other work." % [int(Defs.BUILDINGS[g["building"]].get("workers", 3)), Defs.building_name(g["building"]).to_lower()], "warn")
					leave_crew(u)
					_set_task(u, "idle")
					return
			else:
				u.tgt_bld = b.id
		if b != null:
			if u.phase != "work":
				if go_to_building(u, b, dt, 0.4 if Defs.BUILDINGS[b.type].get("walkable", false) else 1.4):
					u.phase = "work"
				return
			face(u, b.pos)
			u.anim = Anim.DIG
			var rate: float = g["building_rate"] * Defs.GATHER_SPEED * work_mult(u.faction) * dt
			add_stock(u.faction, res, rate)
			c.state["delivered"] = float(c.state["delivered"]) + rate
			return
	# Node-based work with hauling.
	if u.carry_res != res and u.carry > 0.0:
		u.phase = "haul"
	match u.phase:
		"", "find":
			_release_claim(u)
			if u.carry >= float(g["carry"]):
				u.phase = "haul"  # a fresh order doesn't send a full load back to the tree
				return
			if searches_this_tick >= MAX_SEARCHES_PER_TICK:
				u.anim = Anim.IDLE  # a big crew picks its spots over a few ticks
				return
			var n = _pick_node(u, c, g)
			if n == null:
				if c.faction == 0 and not c.state.get("warned", false):
					post(0, "%s: there's no more %s nearby." % [crew_label(c), g["name"]], "warn")
					c.state["warned"] = true
				if u.carry > 0.0:
					u.phase = "haul"
				else:
					u.anim = Anim.IDLE
				return
			_claim(u, n)
			u.phase = "go"
		"go":
			var n = terrain.nodes[u.tgt_node] if u.tgt_node >= 0 else null
			if n == null or n.amount == 0.0:
				u.phase = "find"
				return
			var reach: float = 1.6 + n.scale * (1.2 if n.kind == "rock" and n.sub == "outcrop" else 0.6)
			if n.kind == "berry":
				reach = 0.2 + n.scale * 1.4  # right up against the leaves
			var stand: Vector2 = n.pos
			var cell := cell_of(n.pos)
			if solid_for(u.faction, cell):
				# Hard against a building: work from the nearest open ground.
				var open := nearest_free_cell(u.faction, cell, 2)
				if open == cell:
					u.phase = "find"
					return
				stand = cell_center(open)
				reach = 0.5
			if move_to(u, stand, dt, reach):
				u.phase = "work"
		"work":
			var n = terrain.nodes[u.tgt_node] if u.tgt_node >= 0 else null
			if n == null or n.amount == 0.0:
				u.phase = "find" if u.carry < float(g["carry"]) * 0.5 else "haul"
				return
			face(u, n.pos)
			u.anim = Anim.CHOP if n.kind == "tree" else (Anim.DIG if n.kind == "rock" else Anim.PICK)
			var got := take_from_node(n, minf(float(g["carry"]) - u.carry, g["rate"] * Defs.GATHER_SPEED * work_mult(u.faction) * dt))
			u.carry_res = res
			u.carry += got
			if u.work_t <= 0.0:
				u.work_t = 1.1
				sound("chop" if n.kind == "tree" else ("pick" if n.kind == "rock" else "rustle"), n.pos)
			u.work_t -= dt
			if u.carry >= float(g["carry"]):
				u.phase = "haul"
				_release_claim(u)
		"haul":
			var dp := nearest_dropoff(u.faction, u.pos, u.carry_res)
			if dp == null:
				u.anim = Anim.IDLE
				return
			if go_to_building(u, dp, dt):
				add_stock(u.faction, u.carry_res, u.carry)
				if u.carry_res == res:
					c.state["delivered"] = float(c.state["delivered"]) + u.carry
				u.carry = 0.0
				u.carry_res = ""
				u.phase = "find"


## The resource to work next. With no place named, the one with the shortest haul to a
## drop-off wins unless it's a long walk away. A named place is always respected.
func _pick_node(u: Unit, c: Crew, g: Dictionary):
	if t < float(c.state.get("none_until", 0.0)):
		return null  # a crewmate just looked and found nothing
	searches_this_tick += 1
	var kind: String = g["node"]
	var limit := 2 if kind == "tree" else 3
	var usable := func(nd) -> bool:
		if int(claims.get(nd.id, 0)) >= limit:
			return false
		var cell := cell_of(nd.pos)
		return not solid_for(u.faction, cell) or nearest_free_cell(u.faction, cell, 2) != cell
	var best = null
	var best_cost := INF
	if not c.state.get("named_place", false):
		for drop: Building in dropoffs(u.faction, g["resource"]):
			var search := GATHER_RANGE
			if best != null:  # no need to look where nothing could beat the best so far
				search = minf(search, (best_cost - drop.pos.distance_to(u.pos)) / (HAUL_WEIGHT - 1.0))
				if search <= 0.0:
					continue
			var n = nearest_node(kind, drop.pos, search, usable)
			if n == null:
				continue
			var cost: float = n.pos.distance_to(drop.pos) * HAUL_WEIGHT + n.pos.distance_to(u.pos)
			if cost < best_cost:
				best_cost = cost
				best = n
	if best == null:
		best = nearest_node(kind, c.state.get("origin", u.pos), GATHER_RANGE, usable)
	if best == null:
		c.state["none_until"] = t + SEARCH_RETRY
	return best


func _work_building(u: Unit, type: String, subj: String) -> Building:
	var best: Building = null
	var bd := INF
	var cap := int(Defs.BUILDINGS[type].get("workers", 3))
	for b in buildings_of(u.faction, type):
		if subj in Defs.DEPOSITS and b.deposit != subj:
			continue
		var n := 0
		for o: Unit in units:
			if not o.dead and o.tgt_bld == b.id and o.faction == u.faction and o.task in ["gather", "smelt"]:
				n += 1
		if n >= cap:
			continue
		var d: float = b.pos.distance_squared_to(u.pos)
		if d < bd:
			bd = d
			best = b
	return best


func _do_hunt(u: Unit, c: Crew, dt: float) -> void:
	var g: Dictionary = Defs.GATHER["hunt"]
	# Hunters range out from the drop-off that was nearest when they set out.
	var base := bld(u.tgt_bld)
	if base == null or base.dead:
		base = nearest_dropoff(u.faction, u.pos, "food")
		if base == null:
			_set_task(u, "idle")
			return
		u.tgt_bld = base.id
	match u.phase:
		"", "find":
			if u.carry >= float(g["carry"]):
				u.phase = "haul"
				return
			var meat = nearest_node("carcass", base.pos, 230.0)
			if meat:
				_claim(u, meat)
				u.phase = "go"
				return
			var deer: Unit = null
			var bd := 230.0 * 230.0
			for o: Unit in units_near(base.pos, 230.0, -1):
				if o.kind == "deer" and o.pos.distance_squared_to(base.pos) < bd:
					bd = o.pos.distance_squared_to(base.pos)
					deer = o
			if deer == null:
				u.anim = Anim.IDLE
				if go_to_building(u, base, dt) and c.faction == 0 and not c.state.get("warned", false):
					post(0, "%s: no deer left near the %s." % [crew_label(c), Defs.building_name(base.type).to_lower()], "warn")
					c.state["warned"] = true
				return
			u.tgt_unit = deer.id
			u.phase = "stalk"
		"stalk":
			var deer := unit(u.tgt_unit)
			if deer == null or deer.dead:
				u.phase = "find"
				return
			if u.pos.distance_to(deer.pos) <= 20.0:
				face(u, deer.pos)
				u.anim = Anim.SHOOT
				u.work_t += dt
				if u.work_t >= 1.5:
					u.work_t = 0.0
					fire_arrow(u, deer, 0)
					u.phase = "find"
			else:
				move_to(u, deer.pos, dt, 18.0)
		"go":
			var n = terrain.nodes[u.tgt_node] if u.tgt_node >= 0 else null
			if n == null or n.amount == 0.0:
				u.phase = "find"
				return
			if move_to(u, n.pos, dt, 1.4):
				u.phase = "work"
		"work":
			var n = terrain.nodes[u.tgt_node] if u.tgt_node >= 0 else null
			if n == null or n.amount == 0.0:
				u.phase = "haul" if u.carry > 0.0 else "find"
				return
			u.anim = Anim.PICK
			u.carry_res = "food"
			u.carry += take_from_node(n, minf(float(g["carry"]) - u.carry, g["rate"] * Defs.GATHER_SPEED * work_mult(u.faction) * dt))
			if u.carry >= float(g["carry"]):
				u.phase = "haul"
				_release_claim(u)
		"haul":
			var dp := nearest_dropoff(u.faction, u.pos, "food")
			if dp == null:
				return
			if go_to_building(u, dp, dt):
				add_stock(u.faction, "food", u.carry)
				c.state["delivered"] = float(c.state["delivered"]) + u.carry
				u.carry = 0.0
				u.phase = "find"


func _do_build(u: Unit, c: Crew, dt: float) -> void:
	var b := bld(u.tgt_bld)
	if b == null or b.dead or b.complete:
		b = null
		var bd := INF
		for sid in c.state.get("sites", []):
			var o := bld(sid)
			if o and not o.dead and not o.complete:
				var d := o.pos.distance_squared_to(u.pos)
				# Spread the crew over long wall lines.
				if Defs.BUILDINGS[o.type].get("wall", false):
					d += float(_builders_on(o)) * 400.0
				if d < bd:
					bd = d
					b = o
		if b == null:
			u.anim = Anim.IDLE
			return
		u.tgt_bld = b.id
		u.phase = "go"
	if u.phase == "unload":
		if _unload(u, dt):
			u.phase = "go"
		return
	if u.phase == "go":
		var reach := b.size.length() * 0.5 + 1.0
		if go_to_building(u, b, dt):
			u.phase = "work"
		return
	face(u, b.pos)
	if not b.paid:
		var cost: Dictionary = Defs.BUILDINGS[b.type]["cost"]
		if not pay(b.faction, cost):
			if u.carry > 0.0 and cost.has(u.carry_res):
				u.phase = "unload"
				return
			u.anim = Anim.IDLE
			if b.faction == 0 and t - b.waiting_msg_t > 25.0:
				b.waiting_msg_t = t
				post(0, "%s is waiting for %s to build the %s." % [crew_label(c), Defs.cost_text(missing_cost(0, cost)), Defs.building_name(b.type).to_lower()], "warn")
			return
		b.paid = true
		_start_construction(b)
	u.anim = Anim.HAMMER
	u.work_t -= dt
	if u.work_t <= 0.0:
		u.work_t = 0.9
		sound("hammer", b.pos)
	var total := float(Defs.BUILDINGS[b.type]["work"])
	var amount := work_mult(u.faction) * dt
	b.work += amount
	b.progress = clampf(b.work / total, 0.0, 1.0)
	b.hp = minf(b.max_hp, b.hp + b.max_hp * amount / total)
	if b.progress >= 1.0:
		_complete(b)


func _builders_on(b: Building) -> int:
	var n := 0
	for o: Unit in units:
		if not o.dead and o.tgt_bld == b.id and o.task == "build":
			n += 1
	return n


func _start_construction(b: Building) -> void:
	# Fell the trees standing on the site; their wood goes to the store.
	var r := b.size.length() * 0.5 + 0.5
	var ax := Vector2.from_angle(b.rot)
	var az := Vector2(-ax.y, ax.x)
	var wood := 0.0
	for n in _nodes_within(b.pos, r + 2.0):
		# Picked-clean bushes still have leaves to clear away.
		if (n.amount == 0.0 and n.kind != "berry") or n.kind == "deposit" or (n.kind == "rock" and n.sub == "outcrop"):
			continue
		var d: Vector2 = n.pos - b.pos
		if absf(d.dot(ax)) <= b.size.x * 0.5 + 0.6 and absf(d.dot(az)) <= b.size.y * 0.5 + 0.6:
			if n.kind == "tree":
				wood += n.amount
			n.amount = 0.0
			emit({"type": "node_gone", "id": n.id, "cleared": true})
	if wood > 0.0:
		add_stock(b.faction, "wood", wood)
	_block(b)
	emit({"type": "building", "id": b.id})


func _nodes_within(p: Vector2, r: float) -> Array:
	var out := []
	var i0 := clampi(int((p.x - r) / NODE_BUCKET), 0, node_bucket_n - 1)
	var i1 := clampi(int((p.x + r) / NODE_BUCKET), 0, node_bucket_n - 1)
	var j0 := clampi(int((p.y - r) / NODE_BUCKET), 0, node_bucket_n - 1)
	var j1 := clampi(int((p.y + r) / NODE_BUCKET), 0, node_bucket_n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			for nid in node_buckets[j * node_bucket_n + i]:
				var n = terrain.nodes[nid]
				if n.pos.distance_to(p) <= r:
					out.append(n)
	return out


func _complete(b: Building) -> void:
	b.complete = true
	b.progress = 1.0
	b.hp = b.max_hp
	if not b.blocking:
		_block(b)
	var d: Dictionary = Defs.BUILDINGS[b.type]
	if b.type == "mine":
		var n = _site_node("mine", b.pos)
		if n:
			b.node = n.id
			b.deposit = n.sub
	if d.has("becomes"):
		# A field-built siege engine: the site is replaced by the engine itself.
		var e := spawn_unit(b.faction, d["becomes"], b.pos)
		e.facing = b.rot
		e.ammo = 0
		remove_building(b, "became")
		emit({"type": "unit", "id": e.id})
		sound("complete", e.pos, b.faction)
		_refresh_counts(fac(b.faction))
		if b.faction == 0:
			post(0, "The %s is finished. It needs a crew: 'man the %s'." % [d["name"].to_lower(), d["becomes"]], "done")
		return
	emit({"type": "building", "id": b.id})
	sound("complete", b.pos, b.faction)
	if b.type == "armory":
		b.tier = maxi(b.tier, researched_armory_tier(b.faction))
	_refresh_counts(fac(b.faction))
	if b.faction == 0 and not d.get("wall", false):
		var extra := ""
		if d.has("housing"):
			extra = " Housing is now %d." % fac(0).housing
		elif b.type == "mine":
			extra = " It sits on %s." % Defs.RESOURCE_NAMES.get(b.deposit, "a deposit")
		post(0, "The %s is finished.%s" % [d["name"].to_lower(), extra], "done")


func _do_upgrade(u: Unit, c: Crew, dt: float) -> void:
	var b := bld(c.state.get("bld", -1))
	if b == null or b.dead or b.upgrading == "":
		u.phase = "done"
		return
	if u.phase != "work":
		if go_to_building(u, b, dt):
			u.phase = "work"
		return
	var up: Dictionary = Defs.UPGRADES[b.upgrading]
	face(u, b.pos)
	if not b.up_paid:
		if not pay(b.faction, up["cost"]):
			u.anim = Anim.IDLE
			if b.faction == 0 and t - b.waiting_msg_t > 25.0:
				b.waiting_msg_t = t
				post(0, "%s is waiting for %s to upgrade the %s." % [crew_label(c), Defs.cost_text(missing_cost(0, up["cost"])), up["building"]], "warn")
			return
		b.up_paid = true
	u.anim = Anim.HAMMER
	u.work_t -= dt
	if u.work_t <= 0.0:
		u.work_t = 0.9
		sound("hammer", b.pos)
	b.up_work += work_mult(u.faction) * dt
	if b.up_work >= float(up["work"]):
		var id := b.upgrading
		b.upgrading = ""
		b.tier = int(up["tier"])
		emit({"type": "building", "id": b.id})
		sound("complete", b.pos, b.faction)
		if b.faction == 0:
			post(0, "The %s is now a %s." % [up["building"], up["name"].to_lower()], "done")
		if up.has("opens_age"):
			_open_age(fac(b.faction), int(up["opens_age"]))
		c.state["up"] = id


func _do_arm(u: Unit, c: Crew, s: Dictionary, dt: float) -> void:
	if u.phase == "done":
		u.anim = Anim.IDLE
		return
	var b := bld(c.state.get("bld", -1))
	if b == null or b.dead:
		u.phase = "done"
		return
	var f := fac(u.faction)
	var subj: String = s["subject"]
	if u.phase == "ride":
		_ride_after_arming(u, c, dt)
		return
	if not go_to_building(u, b, dt):
		return
	if subj == "":
		_equip_best(u, f)
	else:
		_equip(u, f, subj)
	u.phase = "done"
	# A general call to arms puts fit riders on horses, if a stable has any spare.
	if subj == "" and _rides_sensibly(u, f) and _stable_with_horse(u.faction, u.pos) != null:
		u.phase = "ride"
		return
	if u.faction == 0 and u.weapon == "" and not u.bow and not c.state.get("warned", false):
		c.state["warned"] = true
		post(0, "%s: the armory ran out of gear for everyone." % crew_label(c), "warn")


## Spearmen and lancers gain from a horse; pikemen don't, and bowmen need mounted archery first.
func _rides_sensibly(u: Unit, f: Faction) -> bool:
	if u.mounted or u.child or u.kind != "villager":
		return false
	if u.bow:
		return f.researched.has("mounted_archery")
	return u.weapon != "" and not u.weapon.ends_with("pike")


func _ride_after_arming(u: Unit, c: Crew, dt: float) -> void:
	var st := _stable_with_horse(u.faction, u.pos)
	if st == null:
		u.phase = "done"
		return
	if not go_to_building(u, st, dt):
		return
	if _take_horse(u.faction, st):
		u.mounted = true
		u.max_hp += Defs.MOUNTED["hp_bonus"]
		u.hp += Defs.MOUNTED["hp_bonus"]
		_equip_best(u, fac(u.faction))   # a lance beats a spear on horseback
	u.phase = "done"


## Walk to the armory and hand back everything carried, then a rider leads the horse back
## to a stable. With no armory left the gear is put down here; with no stable room the horse
## is let go.
func _do_disarm(u: Unit, c: Crew, dt: float) -> void:
	if u.phase == "done":
		u.anim = Anim.IDLE
		return
	if u.phase != "horse":
		var b := bld(c.state.get("bld", -1))
		if _has_gear(u) and b != null and not b.dead and not go_to_building(u, b, dt):
			return
		_stow_gear(u, fac(u.faction))
		u.phase = "horse"
	if u.mounted:
		var st := _stable_with_room(u.faction, u.pos)
		if st != null and not go_to_building(u, st, dt):
			return
		_dismount(u, st)
	u.phase = "done"


func _has_gear(u: Unit) -> bool:
	return u.weapon != "" or u.shield != "" or u.armor != "" or u.bow or u.arrows > 0


## Anyone with gear or a horse has something to hand back before working.
func _needs_stowing(u: Unit) -> bool:
	return _has_gear(u) or u.mounted


## Get off: the horse goes into the stable `st`, or runs wild if there is none.
func _dismount(u: Unit, st: Building) -> void:
	u.mounted = false
	u.max_hp -= Defs.MOUNTED["hp_bonus"]
	u.hp = minf(u.hp, u.max_hp)
	var h := spawn_unit(u.faction, "horse", st.pos if st != null else u.pos + Vector2(1.5, 0))
	if st != null:
		h.stable = st.id
	else:
		h.faction = -1
		h.herd = -1
		h.goal = u.pos


## Everything a person carries goes back into the faction's stock.
func _stow_gear(u: Unit, f: Faction) -> void:
	for item in [u.weapon, u.shield, u.armor]:
		if item != "":
			f.gear[item] = int(f.gear.get(item, 0)) + 1
	if u.bow:
		f.gear["bow"] = int(f.gear.get("bow", 0)) + 1
	f.gear["arrows"] = int(f.gear.get("arrows", 0)) + u.arrows
	u.weapon = ""
	u.shield = ""
	u.armor = ""
	u.bow = false
	u.arrows = 0
	emit({"type": "unit", "id": u.id})


func _equip(u: Unit, f: Faction, item: String) -> bool:
	if int(f.gear.get(item, 0)) <= 0:
		return false
	var it: Dictionary = Defs.ITEMS[item]
	match it["slot"]:
		"weapon":
			if u.weapon != "":
				f.gear[u.weapon] = int(f.gear.get(u.weapon, 0)) + 1
			u.weapon = item
			if item.ends_with("pike") and u.shield != "":
				f.gear[u.shield] = int(f.gear.get(u.shield, 0)) + 1
				u.shield = ""
		"shield":
			if u.weapon.ends_with("pike"):
				return false
			if u.shield != "":
				f.gear[u.shield] = int(f.gear.get(u.shield, 0)) + 1
			u.shield = item
		"armor":
			if u.armor != "":
				f.gear[u.armor] = int(f.gear.get(u.armor, 0)) + 1
			u.armor = item
		"bow":
			if u.bow:
				return false
			u.bow = true
			refill_quiver(u, f)
		_:
			return false
	f.gear[item] = int(f.gear[item]) - 1
	return true


func refill_quiver(u: Unit, f: Faction) -> void:
	var need := Defs.QUIVER - u.arrows
	var have := int(f.gear.get("arrows", 0))
	var take := mini(need, have)
	if take > 0:
		u.arrows += take
		f.gear["arrows"] = have - take


func _equip_best(u: Unit, f: Faction) -> void:
	var weapons := ["iron_sword", "iron_spear", "bronze_sword", "bronze_spear", "wood_spear"]
	if u.mounted:
		weapons = ["iron_lance", "bronze_lance"] + weapons
	for w in weapons:
		if u.weapon == w:
			break
		if int(f.gear.get(w, 0)) > 0:
			_equip(u, f, w)
			break
	if u.weapon == "" and not u.bow and int(f.gear.get("bow", 0)) > 0:
		_equip(u, f, "bow")
	for sh in ["iron_shield", "bronze_shield", "wood_shield"]:
		if u.shield == sh:
			break
		if int(f.gear.get(sh, 0)) > 0 and _equip(u, f, sh):
			break
	for ar in ["iron_armor", "bronze_armor"]:
		if u.armor == ar:
			break
		if int(f.gear.get(ar, 0)) > 0 and _equip(u, f, ar):
			break
	if u.bow:
		refill_quiver(u, f)


func _do_mount(u: Unit, c: Crew, dt: float) -> void:
	if u.phase == "done" or u.mounted:
		u.phase = "done"
		return
	var st := bld(c.state.get("bld", -1))
	if st == null or st.dead:
		st = _stable_with_horse(u.faction, u.pos)
		if st == null:
			u.phase = "done"
			return
	if not go_to_building(u, st, dt):
		return
	var horse := _take_horse(u.faction, st)
	if horse:
		u.mounted = true
		u.max_hp += Defs.MOUNTED["hp_bonus"]
		u.hp += Defs.MOUNTED["hp_bonus"]
	elif u.faction == 0 and not c.state.get("warned", false):
		c.state["warned"] = true
		post(0, "%s: the stable ran out of horses." % crew_label(c), "warn")
	u.phase = "done"


func _take_horse(faction: int, st: Building) -> Unit:
	for h: Unit in units:
		if not h.dead and h.kind == "horse" and h.faction == faction and h.stable == st.id and not h.child:
			h.dead = true
			h.stable = -1
			emit({"type": "unit_gone", "id": h.id})
			return h
	return null


func _do_man(u: Unit, c: Crew, dt: float) -> void:
	if u.phase == "done":
		return
	var e := unit(c.state.get("engine", -1))
	if e == null or e.dead:
		e = _free_engine(u.faction, c.steps[c.idx]["subject"], u.pos)
		if e == null:
			u.phase = "done"
			return
		c.state["engine"] = e.id
	if not move_to(u, e.pos, dt, 2.5):
		return
	if not u.id in e.crew_ids:
		e.crew_ids.append(u.id)
	u.siege = e.id
	u.phase = "done"
	# A spare horse from the stable pulls the gun.
	if not e.team:
		var st := _stable_with_horse(u.faction, e.pos)
		if st and st.pos.distance_to(e.pos) < 150.0 and _take_horse(u.faction, st):
			e.team = true


func _do_smelt(u: Unit, c: Crew, s: Dictionary, dt: float) -> void:
	var b := bld(c.state.get("bld", -1))
	if b == null or b.dead:
		_set_task(u, "idle")
		return
	u.tgt_bld = b.id
	if u.phase != "work":
		if go_to_building(u, b, dt):
			u.phase = "work"
		return
	face(u, b.pos)
	var metal: String = s["subject"]
	var sm: Dictionary = Defs.SMELT[metal]
	var f := fac(u.faction)
	if not can_afford(u.faction, sm["inputs"]):
		u.anim = Anim.IDLE
		if u.faction == 0 and t - b.waiting_msg_t > 25.0:
			b.waiting_msg_t = t
			post(0, "The smelter is waiting for %s." % Defs.cost_text(missing_cost(0, sm["inputs"])), "warn")
		return
	u.anim = Anim.HAMMER
	u.work_t += work_mult(u.faction) * dt
	if u.work_t >= float(sm["time"]):
		u.work_t = 0.0
		pay(u.faction, sm["inputs"])
		add_stock(u.faction, metal, 1.0)
		c.state["delivered"] = float(c.state["delivered"]) + 1.0
		sound("smelt", b.pos)
		if metal == "bronze" and f.age < 2:
			_open_age(f, 2)


func _do_tame(u: Unit, c: Crew, s: Dictionary, dt: float) -> void:
	match u.phase:
		"", "find":
			var origin: Vector2 = c.state.get("origin", home_pos(u.faction))
			if _stable_with_room(u.faction, u.pos) == null:
				_tame_full(u, c)
				return
			var best: Unit = null
			var bd := 320.0 * 320.0
			for h: Unit in units:
				if h.dead or h.kind != "horse" or h.faction != -1 or h.driver >= 0:
					continue
				var d := h.pos.distance_squared_to(origin)
				if d < bd:
					bd = d
					best = h
			if best == null:
				u.anim = Anim.IDLE
				if u.faction == 0 and not c.state.get("warned", false):
					c.state["warned"] = true
					post(0, "%s: no wild horses found nearby. Try scouting for herds." % crew_label(c), "warn")
				return
			u.tgt_unit = best.id
			best.driver = u.id
			u.phase = "approach"
		"approach":
			var h := unit(u.tgt_unit)
			if h == null or h.dead or h.driver != u.id:
				u.phase = "find"
				return
			if move_to(u, h.pos, dt, 3.5):
				u.phase = "drive"
		"drive":
			var h := unit(u.tgt_unit)
			if h == null or h.dead:
				u.phase = "find"
				return
			var st := _stable_with_room(u.faction, u.pos)
			if st == null:
				h.driver = -1
				_tame_full(u, c)
				return
			if go_to_building(u, st, dt):
				if _stable_count(st) >= int(Defs.BUILDINGS["stable"]["horse_cap"]):
					return   # filled up meanwhile; next tick picks another stable
				h.faction = u.faction
				h.stable = st.id
				h.driver = -1
				h.pos = st.pos + Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2))
				c.state["delivered"] = float(c.state["delivered"]) + 1.0
				if u.faction == 0:
					post(0, "%s brought a wild %s into the stable." % [u.name, "mare" if h.female else "stallion"], "done")
				u.phase = "find"


## Nearest stable that still has a free stall, so a second stable fills once the first is full.
func _stable_with_room(faction: int, p: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	var cap := int(Defs.BUILDINGS["stable"]["horse_cap"])
	for st: Building in buildings_of(faction, "stable"):
		var d := st.pos.distance_squared_to(p)
		if d < bd and _stable_count(st) < cap:
			bd = d
			best = st
	return best


func _tame_full(u: Unit, c: Crew) -> void:
	if not c.state.get("full", false) and u.faction == 0:
		post(0, "%s: every stable is full. Build another stable to keep more horses." % crew_label(c), "warn")
	c.state["full"] = true
	u.phase = "find"


func _stable_count(st: Building) -> int:
	var n := 0
	for h: Unit in units:
		if not h.dead and h.kind == "horse" and h.stable == st.id:
			n += 1
	return n


func _do_scout(u: Unit, c: Crew, dt: float) -> void:
	var target: Vector2 = c.state["target"]
	var f := fac(u.faction)
	# Seen and chased: turn for home with what we know.
	if u.scout_leg < 2:
		var chaser := nearest_enemy(u.pos, 22.0, u.faction, func(o): return o.weapon != "" or o.mounted)
		if chaser:
			u.scout_leg = 2
	match u.scout_leg:
		0:
			var home := home_pos(u.faction)
			var away := (target - home).normalized()
			var near := target - away * 50.0 + Vector2.from_angle(float(u.id % 7) * 0.9) * 10.0
			if move_to(u, near, dt, 10.0, true) or t < u.path_wait:
				u.scout_leg = 1
				u.scout_dir = Vector2(-away.y, away.x) * (1.0 if u.id % 2 == 0 else -1.0)
		1:
			# Circle around the target at a safe distance.
			var side := (target + u.scout_dir * 75.0 - (target - home_pos(u.faction)).normalized() * 20.0).clamp(Vector2(20, 20), Vector2(map_size - 20, map_size - 20))
			if move_to(u, side, dt, 10.0, true) or t < u.path_wait:
				u.scout_leg = 2
		2:
			var dest := home_pos(u.faction)
			var cmd := unit(f.commander)
			if cmd and not cmd.dead and cmd.pos.distance_to(u.pos) < dest.distance_to(u.pos):
				dest = cmd.pos
			if move_to(u, dest, dt, 9.0, true):
				deliver_report(u, c)
				u.scout_leg = 3
				u.phase = "done"
		_:
			u.phase = "done"
			_do_idle(u, dt)


# --- Economy -------------------------------------------------------------------

func _refresh_counts(f: Faction) -> void:
	var pop := 0
	var adults := 0
	var kids := 0
	var idle := 0
	var soldiers := 0
	for u: Unit in units:
		if u.dead or u.faction != f.id or u.kind != "villager":
			continue
		pop += 1
		if u.child:
			kids += 1
		else:
			adults += 1
			if u.crew < 0 and u.siege < 0 and not leads_post(u):
				idle += 1
		if u.weapon != "" or u.bow:
			soldiers += 1
	var housing := 0
	var food_cap := 0
	for b: Building in buildings:
		if b.dead or b.faction != f.id or not b.complete:
			continue
		var d: Dictionary = Defs.BUILDINGS[b.type]
		housing += int(d.get("housing", 0))
		food_cap += int(d.get("food_cap", 0))
	var horses := 0
	for h: Unit in units:
		if not h.dead and h.kind == "horse" and h.faction == f.id and h.stable >= 0:
			horses += 1
	f.pop = pop
	f.adults = adults
	f.children = kids
	f.idle = idle
	f.soldiers = soldiers
	f.housing = mini(housing, Defs.POP_HARD_CAP)
	f.food_cap = food_cap
	f.horses = horses


func upkeep(dt: float) -> void:
	for f: Faction in factions:
		if not f.alive:
			continue
		_refresh_counts(f)
		var food := float(f.stock.get("food", 0.0))
		food -= (f.adults * Defs.RATION_ADULT + f.children * Defs.RATION_CHILD) * dt
		food = clampf(food, 0.0, float(f.food_cap))
		f.stock["food"] = food
		var old := f.food_state
		if food <= 0.01:
			f.food_state = 0
		elif food < f.pop * Defs.FED_STOCK:
			f.food_state = 1
		elif food < f.pop * Defs.WELL_FED_STOCK:
			f.food_state = 2
		else:
			f.food_state = 3
		if f.food_state != old and f.id == 0:
			var msg: String = ["The village is starving! People will die without food.", "The village is hungry. Work slows down.",
				"The village is fed. Births are slow; well fed is faster.", "The village is well fed. Expect births."][f.food_state]
			post(0, msg, "warn" if f.food_state < 2 else "info")
		if f.food_state == 0:
			for u: Unit in units:
				if not u.dead and u.faction == f.id and u.kind == "villager":
					u.hp -= 0.5 * dt
					if u.hp <= 0.0:
						kill_unit(u, "starved")
		# Births. A fed village grows at FED_BIRTH_RATE, a well fed one at full rate.
		# Progress banks even when housing is full (up to BIRTH_BANK_PER_ADULT per
		# adult), so a freed place or a new hut is filled at once. Hungry or starving
		# villages neither gain nor lose what they have banked.
		if f.food_state >= 2:
			var pace := 1.0 if f.food_state == 3 else Defs.FED_BIRTH_RATE
			birth_acc[f.id] += f.adults * dt / Defs.BIRTH_SECONDS_PER_ADULT * pace
			birth_acc[f.id] = minf(birth_acc[f.id], maxf(1.0, f.adults * Defs.BIRTH_BANK_PER_ADULT))
			# f.pop is only refreshed once a tick, so count the births made here.
			var room := f.housing - f.pop
			var born := 0
			while birth_acc[f.id] >= 1.0 and born < room:
				birth_acc[f.id] -= 1.0
				born += 1
				_birth(f, f.pop + born)
		# Growing up, healing at home.
		for u: Unit in units:
			if u.dead or u.faction != f.id:
				continue
			if u.child and t - u.born >= Defs.MATURE_TIME:
				u.child = false
				if u.kind == "villager":
					var frac := u.hp / u.max_hp
					u.max_hp = Defs.VILLAGER["hp"]
					u.hp = u.max_hp * frac
					if f.id == 0:
						post(0, "%s has grown up and can work." % u.name, "grown")
			if is_person(u) and u.hp < u.max_hp and t - u.hit_t > 8.0 and u.pos.distance_to(resting_place(u)) < 30.0:
				u.hp = minf(u.max_hp, u.hp + 1.0 * dt)
		_breed(f, dt)
		if f.age == 0 and has_building(f.id, "quarry"):
			_open_age(f, 1)


func _birth(f: Faction, people: int) -> void:
	var home := home_pos(f.id)
	var u := spawn_unit(f.id, "villager", home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 7.0))
	u.child = true
	u.max_hp = Defs.CHILD["hp"]
	u.hp = u.max_hp
	u.name = pick_name(f)
	f.births += 1
	emit({"type": "unit", "id": u.id})
	if f.id == 0:
		post(0, "A child is born: %s. (%d people, housing %d)" % [u.name, people, f.housing], "birth")
		sound("birth", home, 0)


func _breed(f: Faction, dt: float) -> void:
	for st in buildings_of(f.id, "stable"):
		var mares := 0
		var stallions := 0
		var n := 0
		for h: Unit in units:
			if h.dead or h.kind != "horse" or h.stable != st.id:
				continue
			n += 1
			if h.child:
				if t - h.born >= Defs.MATURE_TIME:
					h.child = false
				continue
			if h.female:
				mares += 1
			else:
				stallions += 1
		if mares > 0 and stallions > 0 and n < int(Defs.BUILDINGS["stable"]["horse_cap"]):
			breed_acc[st.id] = float(breed_acc.get(st.id, 0.0)) + dt * minf(mares, stallions) / 60.0
			if breed_acc[st.id] >= 1.0:
				breed_acc[st.id] = 0.0
				var foal := spawn_unit(f.id, "horse", st.pos + Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2)))
				foal.child = true
				foal.born = t
				foal.stable = st.id
				foal.faction = f.id
				emit({"type": "unit", "id": foal.id})
				if f.id == 0:
					post(0, "A foal was born in the stable.", "info")


func _open_age(f: Faction, age: int) -> void:
	if f.age >= age:
		return
	f.age = age
	f.age_t[age] = t
	if f.id == 0:
		post(0, "The %s age has begun! Type /b and /c to see what's new." % Defs.AGES[age], "age")
		sound("age", home_pos(0), 0)
	else:
		emit({"type": "rival_age", "faction": f.id, "age": age})


func kill_unit(u: Unit, why: String = "") -> void:
	if u.dead:
		return
	u.dead = true
	u.dead_t = t
	u.anim = Anim.DEAD
	u.prev = u.pos            # the body lies still between ticks
	u.swing_live = false
	u.blocking = false
	var line := crew_of(u)
	if line:
		_assign_slots(line)   # close the gap; the dead get no slot
	var tower := bld(u.in_tower)
	if tower:
		_release_tower_post(u, tower)
	_release_claim(u)
	var f := fac(u.faction)
	if u.kind == "villager" and f:
		f.deaths += 1
	if u.carry > 0.0:
		u.carry = 0.0
	if u.kind in ["cannon", "ram"]:
		for id in u.crew_ids:
			var m := unit(id)
			if m:
				m.siege = -1
	if u.siege >= 0:
		var e := unit(u.siege)
		if e:
			e.crew_ids.erase(u.id)
	if u.kind == "horse" and u.driver >= 0:
		u.driver = -1
	if u.crew >= 0:
		var c := crew_of(u)
		if c:
			drop_dead(c, u.id)
		u.crew = -1
	leave_post(u)
	emit({"type": "death", "id": u.id, "kind": u.kind, "pos": u.pos, "faction": u.faction})
	if u.faction == 0 and u.kind == "villager":
		var text := "%s %s." % [u.name, "starved" if why == "starved" else "was killed"]
		post(0, text, "death")
	if u.kind == "commander":
		on_commander_dead(u)


func on_commander_dead(_u: Unit) -> void:
	pass


# Implemented by the combat layer (match_combat.gd).
func fire_arrow(_shooter: Unit, _target: Unit, _tier: int) -> void:
	pass


func deliver_report(_scout: Unit, _c: Crew) -> void:
	pass


func _do_military(_u: Unit, _c: Crew, _s: Dictionary, _dt: float) -> void:
	pass
