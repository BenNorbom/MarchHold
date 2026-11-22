extends "res://scripts/sim/match_combat.gd"
## Public match API: setup, the fixed-step tick, validated commands, the
## commander's actions and read-only queries for menus and Terra.

const Captains = preload("res://scripts/sim/captains.gd")
const START_FOOD := 40.0
const FRESH_MARK := 120.0       # seconds a mark counts as "this"


func setup(opts: Dictionary) -> void:
	options = opts
	var seed_in := int(opts.get("seed", 1))
	rng.seed = seed_in * 7919 + 13
	var tr := Terrain.new()
	tr.generate(seed_in, str(opts.get("map", Defs.MAP_LARGEST)))
	_init_world(tr)
	factions.clear()
	for i in 2:
		var f := Faction.new()
		f.id = i
		f.name = "Your people" if i == 0 else "Rook's people"
		f.commander_name = "Commander" if i == 0 else "Commander Rook"
		f.color = Color(0.16, 0.28, 0.55) if i == 0 else Color(0.62, 0.15, 0.11)
		f.is_ai = i == 1 or bool(opts.get("ai_both", false))
		f.start = tr.starts[i]
		for r in Defs.RESOURCES:
			f.stock[r] = 0.0
		f.knowledge.resize(kres * kres)
		f.knowledge.fill(-1.0)
		f.visible.resize(kres * kres)
		factions.append(f)
	for f: Faction in factions:
		var other: Vector2 = factions[1 - f.id].start
		var rot := atan2((other - f.start).y, (other - f.start).x)
		add_building(f.id, "campfire", f.start, rot, true)
		var cmd := spawn_unit(f.id, "commander", f.start + Vector2.from_angle(rot) * 7.0)
		cmd.name = f.commander_name
		cmd.facing = atan2((other - f.start).x, (other - f.start).y)
		cmd.task = "player" if not f.is_ai else "idle"
		f.commander = cmd.id
		for k in Defs.START_VILLAGERS:
			var u := spawn_unit(f.id, "villager", f.start + Vector2.from_angle(TAU * k / Defs.START_VILLAGERS + 0.4) * rng.randf_range(4.5, 7.0))
			u.name = pick_name(f)
		_refresh_counts(f)
		f.stock["food"] = START_FOOD
	for i in tr.herds.size():
		var h: Dictionary = tr.herds[i]
		herd_pos[i] = h["pos"]
		for k in int(h["count"]):
			var a := spawn_unit(-1, h["kind"], h["pos"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 9.0))
			a.herd = i
			if h["kind"] == "horse":
				a.female = k % 2 == 0
	rebuild_unit_hash()
	update_vision()


func is_player_faction(id: int) -> bool:
	return id == 0 and not fac(0).is_ai


func tick(dt: float = Defs.TICK) -> void:
	if over:
		return
	t += dt
	ticks += 1
	paths_this_tick = 0
	rebuild_unit_hash()
	upkeep_t += dt
	if upkeep_t >= 1.0:
		upkeep(upkeep_t)
		upkeep_t = 0.0
		check_morale()
	update_crews(dt)
	for p: Post in posts.values():
		# Once a second each, staggered so they don't all think on the same tick.
		if (ticks + p.id) % 10 == 0:
			Captains.think(self, p)
	var n := units.size()
	for i in n:
		var u: Unit = units[i]
		if u.dead:
			continue
		u.prev = u.pos
		match u.kind:
			"villager":
				_update_villager(u, dt)
			"commander":
				_update_commander(u, dt)
			"horse", "deer":
				update_animal(u, dt)
			"cannon", "ram":
				update_engine(u, dt)
		_unstick(u, dt)
	update_shots(dt)
	vision_t += dt
	if vision_t >= 0.5:
		vision_t = 0.0
		update_vision()
	if ticks % 50 == 0:
		_cleanup()


func _update_villager(u: Unit, dt: float) -> void:
	if u.task == "scout" and u.scout_leg < 3:
		update_worker(u, dt)
		return
	var c := crew_of(u)
	if combat_update(u, dt, soldier_radius(u, c)):
		return
	update_worker(u, dt)


func _update_commander(u: Unit, dt: float) -> void:
	u.cooldown = maxf(0.0, u.cooldown - dt)
	if u.task == "player":
		return
	# Outnumbered: fall back rather than fight alone.
	if u.flee_t > 0.0:
		u.flee_t -= dt
		move_to(u, u.goal, dt, 2.0, true)
		return
	var foes := 0
	var friends := 0
	var threat := Vector2.ZERO
	for o: Unit in units_near(u.pos, 26.0, -2):
		if o.dead or o.stable >= 0 or not is_person(o) or o.id == u.id:
			continue
		if o.faction == u.faction and armed(o):
			friends += 1
		elif o.faction >= 0 and o.faction != u.faction and armed(o):
			foes += 1
			threat += o.pos
	if foes >= 3 and foes > friends + 1:
		var away := (u.pos - threat / foes).normalized()
		u.goal = (u.pos + away * 45.0).clamp(Vector2(20, 20), Vector2(map_size - 20, map_size - 20))
		u.flee_t = 5.0
		return
	if combat_update(u, dt, 20.0):
		return
	var f := fac(u.faction)
	var home := home_pos(u.faction)
	var arm := nearest_building(u.faction, u.pos, ["armory"])
	if arm and int(t) % 30 == 0 and arm.pos.distance_to(home) < 80.0:
		if not go_to_building(u, arm, dt):
			return
		_equip_best(u, f)
	if u.pos.distance_to(home) > 14.0:
		move_to(u, home + _ring(u, 6.0), dt, 2.0)
	else:
		u.anim = Anim.IDLE


func _unstick(u: Unit, dt: float) -> void:
	if u.kind == "commander" and u.task == "player":
		return
	var moved := u.pos.distance_to(u.last_pos)
	if u.anim in [Anim.WALK, Anim.RUN, Anim.CARRY, Anim.RIDE] and moved < 0.02:
		u.stuck += dt
		if u.stuck > 2.5:
			u.stuck = 0.0
			u.path = PackedVector2Array()
			u.path_goal = Vector2(-999, -999)
			var c := cell_of(u.pos)
			if solid_for(clampi(u.faction, 0, 1), c):
				u.pos = cell_center(nearest_free_cell(clampi(u.faction, 0, 1), c))
			else:
				u.pos += Vector2.from_angle(rng.randf() * TAU) * 1.5
	else:
		u.stuck = 0.0
	u.last_pos = u.pos


func _cleanup() -> void:
	var keep := []
	for u: Unit in units:
		if u.dead and t - u.dead_t > 25.0:
			unit_by_id.erase(u.id)
			continue
		keep.append(u)
	units = keep
	var kb := []
	for b: Building in buildings:
		if b.dead:
			bld_by_id.erase(b.id)
			continue
		kb.append(b)
	buildings = kb
	if messages.size() > 400:
		messages = messages.slice(messages.size() - 300)


func on_commander_dead(u: Unit) -> void:
	if over:
		return
	over = true
	winner = 1 - u.faction
	end_reason = "%s was killed." % u.name
	emit({"type": "over", "winner": winner})


# --- Orders --------------------------------------------------------------------

## Tech and age checks that earlier steps in the same plan can't fix.
func step_problem(faction: int, s: Dictionary) -> String:
	var f := fac(faction)
	var subj: String = s.get("subject", "")
	var at: String = s.get("where", "")
	if at.begins_with(Defs.PLACE) and not places_of(faction).has(at.substr(Defs.PLACE.length())):
		return "There's no place called %s. Mark it (R), then say 'call this %s'." % [at.substr(Defs.PLACE.length()).capitalize(), at.substr(Defs.PLACE.length()).capitalize()]
	match s["action"]:
		"build":
			return unlock_problem(faction, subj)
		"craft":
			var it: Dictionary = Defs.ITEMS[subj]
			var need_age: int = [0, 2, 3][it["tier"]]
			if it.has("research"):
				need_age = 3
			if f.age < need_age:
				return "%s need the %s age. %s" % [Defs.item_name(subj, 2).capitalize(), Defs.AGES[need_age], Defs.AGE_HOW[need_age]]
			if it.has("research") and not f.researched.has(it["research"]) and f.age < 4:
				return "Cannons need gunpowder. Build a university and research it."
		"smelt":
			if subj == "iron" and f.age < 3:
				return "Iron needs an iron furnace (upgrade the smelter in the Bronze age)."
			if f.age < 1:
				return "Smelting needs the Stone age. %s" % Defs.AGE_HOW[1]
		"upgrade":
			var up := _upgrade_for(faction, subj)
			if up.begins_with("!") and not up.contains("first"):
				return up.substr(1).capitalize()
		"research":
			if f.age < 3:
				return "Research needs the Iron age and a university."
		"gather":
			if subj in Defs.DEPOSITS and f.age < 1:
				return "Mining needs the Stone age. %s" % Defs.AGE_HOW[1]
		"tame", "mount":
			if f.age < 1:
				return "Horses need a stable, which needs the Stone age."
		"man":
			if subj == "cannon" and f.age < 4:
				return "Cannons need gunpowder."
			if subj == "ram" and f.age < 2:
				return "Rams need a bronze armory."
	return ""


## The first step starts right away, so its buildings must already exist.
func first_step_problem(faction: int, s: Dictionary) -> String:
	var subj: String = s.get("subject", "")
	var home := home_pos(faction)
	var why := ""
	match s["action"]:
		"craft":
			why = craft_problem(faction, subj)
		"arm":
			if nearest_building(faction, home, ["armory"]) == null:
				why = "we need an armory first."
			elif subj != "" and int(fac(faction).gear.get(subj, 0)) <= 0:
				why = "there are no %s in the armory. Make some with /c." % Defs.item_name(subj, 2)
		"smelt":
			if buildings_of(faction, "smelter").is_empty():
				why = "we need a smelter first."
			elif subj == "iron" and buildings_of(faction, "smelter").all(func(b): return b.tier < 1):
				why = "the smelter has to be upgraded to an iron furnace first."
		"research":
			if fac(faction).researched.has(subj):
				why = "we already know %s." % Defs.RESEARCH[subj]["name"].to_lower()
			elif not has_building(faction, Defs.RESEARCH[subj]["building"]):
				why = "we need a university first."
		"tame":
			if buildings_of(faction, "stable").is_empty():
				why = "we need a stable to keep horses in."
		"mount":
			if _stable_with_horse(faction, home) == null:
				why = "there are no grown horses in a stable."
		"man":
			if _free_engine(faction, subj, home) == null:
				why = "there's no %s waiting for a crew." % Defs.item_name(subj)
		"upgrade":
			var up := _upgrade_for(faction, subj)
			if up.begins_with("!"):
				why = up.substr(1)
		"build":
			var sites = s.get("sites", [])
			if not sites is Array or not sites.any(func(id):
				var site := bld(id)
				return site != null and not site.dead and not site.complete and site.faction == faction
			):
				why = "there's no site placed for the %s." % Defs.building_name(subj).to_lower()
		"scout", "guard", "hold", "attack":
			var where: String = s.get("where", "")
			var needs_enemy_camp: bool = (where == "enemy" and s["action"] != "scout") or (where == "" and s["action"] == "attack")
			if where == "marked" and not fac(faction).has_mark:
				why = "mark a spot first (look at the ground and press R)."
			elif needs_enemy_camp and known_enemy_camp(faction) == null:
				why = "we don't know where their camp is. Scout first."
		"gather":
			var g: Dictionary = Defs.GATHER[subj]
			if g.has("building") and not g.has("node"):
				var ok := false
				for b in buildings_of(faction, g["building"]):
					if not subj in Defs.DEPOSITS or b.deposit == subj:
						ok = true
				if not ok:
					why = ("we need a mine on a %s deposit first." % Defs.RESOURCE_NAMES[subj]) if subj in Defs.DEPOSITS else ("we need a %s first." % Defs.building_name(g["building"]).to_lower())
	return why.substr(0, 1).to_upper() + why.substr(1) if why != "" else ""


static func clean_steps(steps: Array) -> Array:
	var out := []
	for s in steps:
		if not (s is Dictionary):
			out.append({})
			continue
		out.append({"action": str(s.get("action", "")), "subject": str(s.get("subject", "")),
			"count": int(s.get("count", 0)), "amount": int(s.get("amount", 0)), "where": str(s.get("where", "")),
			"sites": s.get("sites", [])})
	return out


func _default_size(faction: int, s: Dictionary) -> int:
	var f := fac(faction)
	match s["action"]:
		"gather":
			return maxi(1, f.idle)
		"build":
			return 4 if Defs.BUILDINGS.get(s["subject"], {}).get("wall", false) else 3
		"upgrade":
			return 3
		"craft", "smelt":
			return 2
		"research", "scout", "tame", "mount":
			return 1
		"man":
			return int(Defs.ITEMS[s["subject"]]["crew"])
		"arm":
			return maxi(1, f.idle)
	return maxi(1, f.idle)


func _military_pool(faction: int) -> Array:
	var out := []
	for u: Unit in units:
		if u.dead or u.faction != faction or u.kind != "villager" or u.child or u.siege >= 0:
			continue
		if not (u.weapon != "" or u.bow):
			continue
		var c := crew_of(u)
		if c and c.idx < c.steps.size() and c.steps[c.idx]["action"] in ["attack", "guard", "hold", "follow", "scout"]:
			continue
		out.append(u)
	return out


func orderable_unit(faction: int, id: int) -> Unit:
	var u := unit(id)
	if u and not u.dead and u.kind == "villager" and u.faction == faction and not u.child:
		return u
	return null


func _addressed_crew(faction: int, req: Dictionary) -> Crew:
	var c: Crew = crews.get(int(req["crew"])) if req.has("crew") else null
	if not req.has("crew") and req.has("unit"):
		var u := orderable_unit(faction, int(req["unit"]))
		if u:
			c = crew_of(u)
	return c if c and c.faction == faction and not c.members.is_empty() else null


## The person a piece of text opens with, matched on the longest name first.
## A bare first name works while it is unambiguous. prefix also accepts the start of one.
## Returns {unit, rest, error}: rest is the text after the name.
func find_person(faction: int, text: String, prefix: bool = false) -> Dictionary:
	var said := text.strip_edges()
	var low := said.to_lower()
	var living: Array[Unit] = []
	var best: Unit = null
	var taken := 0
	for u: Unit in units:
		if u.dead or u.faction != faction or u.kind != "villager" or u.name == "":
			continue
		living.append(u)
		var n := u.name.to_lower()
		if n.length() > taken and low.begins_with(n) and (low.length() == n.length() or low[n.length()] in " ,:.!?"):
			best = u
			taken = n.length()
	var none := {"unit": null, "rest": said, "error": ""}
	var words := low.split(" ", false)
	if words.is_empty():
		return none
	# A dead "Hal Miller" must not turn into plain Hal.
	if (best == null or not best.name.contains(" ")) and words.size() > 1 and not words[0].right(1) in ",:":
		if words[1].rstrip(",:.!?").capitalize() in Defs.BYNAMES:
			return none
	if best == null:
		var word := words[0].rstrip(",:.!?")
		if word == "":
			return none
		var found := living.filter(func(u): return u.name.to_lower().get_slice(" ", 0) == word)
		if found.is_empty() and prefix:
			found = living.filter(func(u): return u.name.to_lower().begins_with(word))
		if found.size() > 1:
			var leaders := found.filter(func(u): return u.captain)
			if leaders.size() != 1:
				var options: Array[String] = []
				for u in found.slice(0, 4):
					options.append(u.name)
				none["error"] = "Which one: %s?" % ", ".join(options)
				return none
			found = leaders
		if found.is_empty():
			return none
		best = found[0]
		taken = words[0].length()
	return {"unit": best, "rest": said.substr(taken).lstrip(" ,:.!?"), "error": ""}


## Join one villager or their whole crew to an existing crew without restarting its plan.
func reassign_crew(faction: int, req: Dictionary, destination_id: int) -> Dictionary:
	var destination := _addressed_crew(faction, {"unit": destination_id})
	if destination == null:
		return {"ok": false, "error": "Choose a villager who already leads or belongs to a crew."}
	var source := _addressed_crew(faction, req)
	if source == destination:
		return {"ok": false, "error": "Already part of %s." % crew_label(destination)}
	var members := []
	if req.has("units"):
		for id in req["units"]:
			var su := orderable_unit(faction, int(id))
			if su and crew_of(su) != destination:
				members.append(su.id)
	elif not req.get("individual", false) and source:
		members = source.members.duplicate()
	elif req.has("unit") and orderable_unit(faction, int(req["unit"])):
		members.append(int(req["unit"]))
	if members.is_empty():
		return {"ok": false, "error": "Address a villager or crew first."}
	var task: String = destination.steps[destination.idx]["action"] if destination.idx < destination.steps.size() else "idle"
	for id in members:
		var u := orderable_unit(faction, id)
		if u:
			release_member(u)
			_join(destination, u)
			_set_task(u, task)
			destination.start_size += 1
	_assign_slots(destination)
	return {"ok": true, "crew": destination.id}


func posts_of(faction: int) -> Array:
	var out := []
	for p: Post in posts.values():
		if p.faction == faction:
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func post_label(p: Post) -> String:
	var lead := unit(p.captain)
	return "Captain %s (%s)" % [lead.name if lead else "", p.name]


func post_status(p: Post) -> String:
	var doing: Array[String] = []
	var working := {}
	var ordered := 0
	for u in post_members(p):
		var c := crew_of(u)
		if c == null or c.idx >= c.steps.size():
			continue
		if c.post != p.id:
			ordered += 1
		else:
			var s: Dictionary = c.steps[c.idx]
			var what: String = s["action"]
			if what == "gather":
				what = Defs.GATHER[s["subject"]]["name"]
			elif what == "smelt":
				what = "smelting"
			working[what] = int(working.get(what, 0)) + 1
	for what in working:
		doing.append("%d %s" % [working[what], what])
	if ordered > 0:
		doing.append("%d on your orders" % ordered)
	var size := str(p.members.size())
	if p.target > 0:
		size += " of %d" % p.target
	return "%s: %s people. %s." % [post_label(p), size, ", ".join(doing) if not doing.is_empty() else "standing by"]


## Who carries out an order given to a captain: as many of their people as it needs.
func _post_detail(p: Post, first: Dictionary) -> Array:
	var pool: Array = post_members(p).filter(func(u): return u.id != p.captain and not u.child and u.siege < 0)
	var a: String = first["action"]
	var want := int(first.get("count", 0))
	if want == 0:
		var soldiers: bool = p.mandate in ["garrison", "army"]
		if a == "recall" or (soldiers and a in ["attack", "follow", "guard", "hold", "arm"]):
			want = pool.size()
		elif a in ["attack", "follow", "guard", "hold"]:
			# A working post sends its fighters, not its farmers.
			var fighters := pool.filter(func(u): return armed(u)).size()
			want = fighters if fighters > 0 else 4
		elif a == "arm":
			want = 4
		elif a == "gather":
			want = 3
		else:
			want = _default_size(p.faction, first)
	# People free or on the captain's jobs go before anyone already on your orders.
	var key := func(u):
		return (0 if u.crew < 0 else (1 if not under_direct_order(u) else 2))
	pool.sort_custom(func(x, y):
		var kx: int = key.call(x)
		var ky: int = key.call(y)
		if kx != ky:
			return kx < ky
		var fighting: bool = a in ["attack", "guard", "hold", "follow"]
		if fighting and armed(x) != armed(y):
			return armed(x)
		return x.id < y.id)
	var out := pool.slice(0, want)
	var lead := unit(p.captain)
	if out.is_empty() and lead and not lead.dead:
		out.append(lead)
	return out


## Stands a post down. Its people are free again.
func close_post(p: Post) -> void:
	for u in post_members(p):
		var c := crew_of(u)
		if c and c.post == p.id:
			release_member(u)
		u.post = -1
	posts.erase(p.id)


## Puts someone in charge of a place and a purpose, or changes the charge they have.
func give_mandate(faction: int, req: Dictionary, s: Dictionary) -> Dictionary:
	var kind: String = s["subject"]
	var d: Dictionary = Defs.MANDATES[kind]
	var people: Array = []
	if req.has("post"):
		var held: Post = posts.get(int(req["post"]))
		if held and held.faction == faction:
			people.append(unit(held.captain))
	elif req.has("units"):
		for id in req["units"]:
			var su := orderable_unit(faction, int(id))
			if su:
				people.append(su)
	elif req.has("unit"):
		var u := orderable_unit(faction, int(req["unit"]))
		if u:
			people.append(u)
			var c := crew_of(u)
			if c and c.post < 0 and c.leader == u.id and not req.get("individual", false):
				for id in c.members:
					if id != u.id:
						people.append(unit(id))
	elif req.has("crew"):
		var c := _addressed_crew(faction, req)
		if c:
			var chosen := orderable_unit(faction, int(req.get("person", c.leader)))
			if chosen == null or not c.members.has(chosen.id):
				chosen = unit(c.leader)
			people.append(chosen)
			# A captain brings their own crew. Anyone else comes alone.
			if c.captain and c.post < 0 and chosen.id == c.leader:
				for id in c.members:
					if id != chosen.id:
						people.append(unit(id))
	elif req.is_empty() or not req.get("all", false):
		var free := idle_adults(faction, home_pos(faction))
		if not free.is_empty():
			people.append(free[0])
	if people.is_empty():
		return {"ok": false, "error": "Say who is in charge: look at someone, or start with their name."}
	var lead: Unit = people[0]
	var at = home_pos(faction)
	var where: String = s["where"]
	if kind != "village":
		if where == "":
			at = lead.pos
		else:
			var here := Crew.new()
			here.faction = faction
			here.members = [lead.id]
			at = resolve_where(here, where, 120.0)
			if at == null:
				return {"ok": false, "error": "Mark a spot first (look at the ground and press R)." if where == "marked" else "We don't know where that is yet."}
	var p: Post = village_post(faction) if kind == "village" else null
	if p == null and leads_post(lead):
		p = post_of(lead)
	if p == null:
		p = Post.new()
		p.id = new_id()
		p.faction = faction
		posts[p.id] = p
	elif p.captain != lead.id and leads_post(lead):
		leave_post(lead)
	for u: Unit in people:
		# Taking charge ends whatever they were doing.
		if u.crew >= 0:
			release_member(u)
		join_post(p, u)
	p.captain = lead.id
	lead.captain = true
	p.mandate = kind
	p.center = at
	p.radius = float(d["radius"])
	var count := int(s.get("count", 0))
	p.target = count if count > 0 else maxi(int(d["size"]), people.size() if kind != "village" else 0)
	var title: String = "village"
	if kind != "village":
		if where.begins_with(Defs.PLACE) and fac(faction).places.has(where.substr(Defs.PLACE.length())):
			title = fac(faction).places[where.substr(Defs.PLACE.length())]["name"]
		else:
			title = "%s %s" % [Terrain.compass_name(p.center - home_pos(faction)), d["name"]]
		var base := title
		var nth := 1
		while posts_of(faction).any(func(o): return o != p and o.name == title):
			nth += 1
			title = "%s %d" % [base, nth]
	p.name = title
	return {"ok": true, "crews": [], "post": p.id}


## Orders accept {"unit": id} (their crew), {"unit": id, "individual": true},
## {"units": [ids]} (an exact selection), {"crew": id}, {"all": true}, or an empty
## address for free villagers, plus steps.
func command(faction: int, req: Dictionary) -> Dictionary:
	var steps := clean_steps(req.get("steps", []))
	var err := Defs.validate_steps(steps)
	if err != "":
		return {"ok": false, "error": err}
	for s in steps:
		var e2 := step_problem(faction, s)
		if e2 != "":
			return {"ok": false, "error": e2}
	var e3 := first_step_problem(faction, steps[0])
	if e3 != "":
		return {"ok": false, "error": e3}
	if steps[0]["action"] == "mandate":
		return give_mandate(faction, req, steps[0])
	var targets := []
	var first: Dictionary = steps[0]
	if req.get("all", false):
		for c: Crew in crews.values():
			if c.faction == faction:
				targets.append(c)
		var idle := idle_adults(faction, home_pos(faction))
		if not idle.is_empty():
			targets.append(make_crew(faction, idle))
	elif req.has("post"):
		var p: Post = posts.get(int(req["post"]))
		if p == null or p.faction != faction:
			return {"ok": false, "error": "That post has been stood down."}
		if steps.size() == 1 and first["action"] in ["status", "dismiss"]:
			if first["action"] == "status":
				post(faction, post_status(p), "info")
			else:
				post(faction, "The %s is stood down." % p.name, "info")
				close_post(p)
			return {"ok": true, "crews": []}
		var detail := _post_detail(p, first)
		if detail.is_empty():
			return {"ok": false, "error": "%s has nobody to send." % post_label(p)}
		for s in steps:
			s["count"] = 0      # their own people, not whoever is nearest
		for u in detail:
			release_member(u)
		targets.append(make_crew(faction, detail))
	elif req.has("crew"):
		var c := _addressed_crew(faction, req)
		if c == null:
			return {"ok": false, "error": "That crew is no longer available."}
		targets.append(c)
	elif req.has("units"):
		# An exact selection of villagers: they work together as one crew, at the size picked.
		var picked: Array[Unit] = []
		for id in req["units"]:
			var su := orderable_unit(faction, int(id))
			if su and not picked.has(su):
				picked.append(su)
		if picked.is_empty():
			return {"ok": false, "error": "Nobody selected can take orders."}
		if steps.size() == 1 and first["action"] in ["status", "dismiss"]:
			for su in picked:
				if first["action"] == "dismiss":
					release_member(su)
				else:
					var sc := crew_of(su)
					var doing := Defs.describe_step(sc.steps[sc.idx]) if sc and sc.idx < sc.steps.size() else "standing by"
					post(faction, "%s: %s. %d%% health." % [su.name, doing, int(100.0 * su.hp / su.max_hp)], "info")
			return {"ok": true, "crews": []}
		for s in steps:
			s["count"] = 0
		var same := crew_of(picked[0])
		for su in picked:
			if crew_of(su) != same:
				same = null
				break
		if same and same.members.size() == picked.size():
			targets.append(same)
		else:
			for su in picked:
				release_member(su)
			targets.append(make_crew(faction, picked))
	elif req.has("unit"):
		var u := unit(int(req["unit"]))
		if u == null or u.dead or u.faction != faction or u.kind != "villager":
			return {"ok": false, "error": "That person can't take orders."}
		if u.child:
			return {"ok": false, "error": "%s is a child and can't work yet." % u.name}
		var c := crew_of(u)
		if req.get("individual", false):
			if steps.size() == 1 and first["action"] == "status":
				var doing := "standing by"
				if c and c.idx < c.steps.size():
					doing = Defs.describe_step(c.steps[c.idx])
				post(faction, "%s: %s. %d%% health." % [u.name, doing, int(100.0 * u.hp / u.max_hp)], "info")
				return {"ok": true, "crews": []}
			if steps.size() == 1 and first["action"] == "dismiss":
				release_member(u)
				return {"ok": true, "crews": []}
			for s in steps:
				s["count"] = 0
			if c and c.members.size() > 1:
				release_member(u)
				c = null
		if c == null:
			c = make_crew(faction, [u])
		targets.append(c)
	else:
		var c := make_crew(faction, [])
		var want := int(first.get("count", 0))
		var origin := home_pos(faction)
		if first["action"] in ["attack", "guard", "hold", "follow"] and want == 0:
			for u in _military_pool(faction):
				_join(c, u)
		if c.members.is_empty():
			recruit(c, want if want > 0 else _default_size(faction, first), origin)
		if c.members.is_empty():
			crews.erase(c.id)
			return {"ok": false, "error": "Nobody is free. Look at someone (or use @Name) to give them new work, or say @all."}
		targets.append(c)
	var ids := []
	for c in targets:
		if c.members.is_empty():
			continue
		c.post = -1         # a direct order overrides the captain's
		start_plan(c, steps.duplicate(true))
		ids.append(c.id)
	if ids.is_empty():
		return {"ok": false, "error": "Nobody could take that order."}
	return {"ok": true, "crews": ids}


func cancel(faction: int, req: Dictionary) -> int:
	var n := 0
	if req.get("all", false):
		for c: Crew in crews.values():
			if c.faction == faction:
				cancel_plan(c)
				n += 1
	elif req.has("post"):
		var p: Post = posts.get(int(req["post"]))
		if p and p.faction == faction:
			for u in post_members(p):
				if under_direct_order(u):
					release_member(u)
					n += 1
	elif req.has("units"):
		for id in req["units"]:
			var su := orderable_unit(faction, int(id))
			if su and (crew_of(su) or su.siege >= 0):
				release_member(su)
				n += 1
	elif req.get("individual", false):
		var u := orderable_unit(faction, int(req.get("unit", -1)))
		if u and (crew_of(u) or u.siege >= 0):
			release_member(u)
			n = 1
	else:
		var c := _addressed_crew(faction, req)
		if c:
			cancel_plan(c)
			n = 1
	return n


func place_site(faction: int, type: String, p: Vector2, rot: float) -> Dictionary:
	var why := unlock_problem(faction, type)
	if why == "":
		why = site_problem(faction, type, p, rot)
	if why != "":
		return {"ok": false, "error": why}
	var b := add_building(faction, type, p, rot, false)
	var n = _site_node(type, p)
	if n:
		b.node = n.id
		if type == "mine":
			b.deposit = n.sub
	return {"ok": true, "id": b.id}


## Walls go post to post: each stretch between posts becomes 4 m pieces.
func place_wall(faction: int, type: String, points: Array) -> Dictionary:
	var why := unlock_problem(faction, type)
	if why != "":
		return {"ok": false, "error": why}
	var d: Dictionary = Defs.BUILDINGS[type]
	var ids := []
	var skipped := 0
	var last_err := ""
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var len := a.distance_to(b)
		if len < 1.0:
			continue
		var n := maxi(1, int(ceil(len / float(d["length"]))))
		var piece := len / n
		var rot := atan2((b - a).y, (b - a).x)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var mid := (p0 + p1) * 0.5
			var size := Vector2(piece + 0.15, d["thick"])
			var err := site_problem(faction, type, mid, rot, size)
			if err != "":
				skipped += 1
				last_err = err
				continue
			var w := add_building(faction, type, mid, rot, false)
			w.size = size
			w.a = p0
			w.b = p1
			var line_id: int = ids[0] if not ids.is_empty() else w.id
			w.line = line_id
			ids.append(w.id)
	if ids.is_empty():
		return {"ok": false, "error": last_err if last_err != "" else "Mark at least two posts."}
	return {"ok": true, "ids": ids, "skipped": skipped, "error": last_err}


func remove_site(id: int) -> void:
	var b := bld(id)
	if b and not b.paid:
		remove_building(b, "cancelled")


func set_mark(faction: int, p: Vector2) -> void:
	var f := fac(faction)
	f.mark = p
	f.mark_t = t
	f.has_mark = true


## "Call this East Hill": the spot just marked, or else where the commander stands.
func name_place(faction: int, title: String) -> Dictionary:
	var f := fac(faction)
	var p := f.mark
	if not f.has_mark or t - f.mark_t > FRESH_MARK:
		var me := commander(faction)
		if me == null:
			return {"ok": false, "error": "Mark a spot first (look at the ground and press R)."}
		p = me.pos
	f.places[title.to_lower()] = {"name": title, "pos": p}
	return {"ok": true}


# --- The commander -----------------------------------------------------------------

func set_commander(faction: int, p: Vector2, facing: float, anim: int) -> void:
	var u := unit(fac(faction).commander)
	if u == null or u.dead:
		return
	u.pos = p
	u.facing = facing
	u.anim = anim


func commander(faction: int) -> Unit:
	return unit(fac(faction).commander)


## A melee blow in front of the commander. Returns what was hit ("" for nothing).
func commander_strike(faction: int) -> String:
	var u := commander(faction)
	if u == null or u.dead or u.cooldown > 0.0:
		return ""
	var w := weapon_def(u)
	u.cooldown = float(w["rate"]) * 0.8
	var fwd := Vector2(sin(u.facing), cos(u.facing))
	var reach: float = w["reach"] + 0.8
	var best: Unit = null
	var bd := INF
	for o: Unit in units_near(u.pos, reach + 1.5, -2):
		if o.faction == faction or o.stable >= 0 or o.dead or o.id == u.id:
			continue
		var to := o.pos - u.pos
		var d := to.length()
		if d > reach + (0.6 if o.mounted else 0.0):
			continue
		if d > 0.3 and fwd.dot(to / d) < 0.55:
			continue
		if d < bd:
			bd = d
			best = o
	if best:
		deal_damage(best, melee_damage(u, best), u, "melee")
		sound("clash" if best.weapon != "" or best.shield != "" else "hit", best.pos)
		return best.name if best.name != "" else best.kind
	for b: Building in buildings:
		if b.dead or b.faction == faction:
			continue
		var local := (u.pos + fwd * reach * 0.7 - b.pos).rotated(-b.rot)
		if absf(local.x) <= b.size.x * 0.5 + 0.8 and absf(local.y) <= b.size.y * 0.5 + 0.8:
			damage_building(b, float(w["dmg"]) * _material(b.type), u)
			sound("chop", b.pos)
			return Defs.building_name(b.type)
	sound("swing", u.pos)
	return ""


func commander_shoot(faction: int, origin: Vector3, dir: Vector3, power: float) -> bool:
	var u := commander(faction)
	if u == null or u.dead or not u.bow or u.arrows <= 0:
		return false
	u.arrows -= 1
	fire_free_arrow(u, origin, dir.normalized() * lerpf(22.0, 62.0, clampf(power, 0.0, 1.0)), armory_tier(faction))
	return true


## Take the best gear from a nearby armory. Returns a summary or a reason.
func commander_take_gear(faction: int) -> String:
	var u := commander(faction)
	if u == null:
		return ""
	var arm := nearest_building(faction, u.pos, ["armory"])
	if arm == null or arm.pos.distance_to(u.pos) > arm.size.length() * 0.5 + 4.0:
		return "Stand next to your armory to take gear."
	var f := fac(faction)
	var before := [u.weapon, u.shield, u.armor, u.bow, u.arrows]
	_equip_best(u, f)
	if not u.bow and int(f.gear.get("bow", 0)) > 0:
		u.bow = true
		f.gear["bow"] = int(f.gear["bow"]) - 1
	if u.bow:
		refill_quiver(u, f)
	if [u.weapon, u.shield, u.armor, u.bow, u.arrows] == before:
		return "Nothing better in the armory. Make gear with /c."
	var parts: Array[String] = []
	parts.append(Defs.item_name(u.weapon) if u.weapon != "" else "bare hands")
	if u.shield != "":
		parts.append(Defs.item_name(u.shield))
	if u.armor != "":
		parts.append(Defs.item_name(u.armor))
	if u.bow:
		parts.append("bow with %d arrows" % u.arrows)
	return "You take " + ", ".join(parts) + "."


func commander_mount(faction: int) -> String:
	var u := commander(faction)
	if u == null:
		return ""
	var st := nearest_building(faction, u.pos, ["stable"])
	var near := st != null and st.pos.distance_to(u.pos) < st.size.length() * 0.5 + 5.0
	if u.mounted:
		if not near:
			u.mounted = false
			u.max_hp -= Defs.MOUNTED["hp_bonus"]
			u.hp = minf(u.hp, u.max_hp)
			var h := spawn_unit(faction, "horse", u.pos + Vector2(1.5, 0))
			h.faction = -1
			h.herd = -1
			h.goal = u.pos
			return "You dismount. The horse wanders off."
		u.mounted = false
		u.max_hp -= Defs.MOUNTED["hp_bonus"]
		u.hp = minf(u.hp, u.max_hp)
		var h2 := spawn_unit(faction, "horse", st.pos)
		h2.stable = st.id
		return "You leave the horse in the stable."
	if not near:
		return "Stand next to your stable to take a horse."
	var horse := _take_horse(faction, st)
	if horse == null:
		return "The stable has no grown horses."
	u.mounted = true
	u.max_hp += Defs.MOUNTED["hp_bonus"]
	u.hp += Defs.MOUNTED["hp_bonus"]
	return "You mount up. Press F by the stable to leave the horse."


## Turns generic subjects from the local parser ("spears", "food") into ids.
func resolve_steps(faction: int, steps: Array) -> Array:
	var tier := maxi(0, armory_tier(faction))
	var f := fac(faction)
	var tiers := {
		"spear": ["wood_spear", "bronze_spear", "iron_spear"], "sword": ["bronze_sword", "bronze_sword", "iron_sword"],
		"shield": ["wood_shield", "bronze_shield", "iron_shield"], "armor": ["bronze_armor", "bronze_armor", "iron_armor"],
		"pike": ["bronze_pike", "bronze_pike", "iron_pike"], "lance": ["bronze_lance", "bronze_lance", "iron_lance"],
	}
	var out := []
	for s in steps:
		var st: Dictionary = s.duplicate()
		var gen: String = st.get("generic", "")
		st.erase("generic")
		if gen != "":
			var base := gen.get_slice("_", 1) if gen.contains("_") else gen
			if tiers.has(base):
				var list: Array = tiers[base]
				if st["action"] == "arm":
					var pick := ""
					for k in range(2, -1, -1):
						if int(f.gear.get(list[k], 0)) > 0:
							pick = list[k]
							break
					st["subject"] = pick if pick != "" else list[tier]
				else:
					st["subject"] = list[tier]
			elif gen == "food":
				var farm_room := false
				for b in buildings_of(faction, "farm"):
					farm_room = true
				if farm_room:
					st["subject"] = "farm"
				elif nearest_node("berry", home_pos(faction), 200.0) != null:
					st["subject"] = "berries"
				elif has_building(faction, "lodge"):
					st["subject"] = "hunt"
				else:
					st["subject"] = "berries"
		out.append(st)
	return out


# --- Queries ------------------------------------------------------------------------

func food_state_name(faction: int) -> String:
	return Defs.FOOD_STATES[fac(faction).food_state]


func build_menu(faction: int) -> Array:
	var out := []
	for id in Defs.buildable_ids():
		var d: Dictionary = Defs.BUILDINGS[id]
		out.append({"kind": "build", "id": id, "name": d["name"], "cost": d["cost"], "desc": d["desc"],
			"locked": unlock_problem(faction, id), "missing": missing_cost(faction, d["cost"])})
	for id in Defs.UPGRADES:
		var up: Dictionary = Defs.UPGRADES[id]
		var b := nearest_building(faction, home_pos(faction), [up["building"]])
		if b == null or b.tier != int(up["from"]):
			continue
		var lock := ""
		if fac(faction).age < int(up["age"]):
			lock = "Needs the %s age: %s" % [Defs.AGES[up["age"]], Defs.AGE_HOW[up["age"]].to_lower()]
		if b.upgrading != "":
			lock = "Already being upgraded."
		out.append({"kind": "upgrade", "id": up["building"], "name": up["name"] + " (upgrade)", "cost": up["cost"],
			"desc": up["desc"], "locked": lock, "missing": missing_cost(faction, up["cost"])})
	for id in Defs.RESEARCH:
		var r: Dictionary = Defs.RESEARCH[id]
		if fac(faction).researched.has(id):
			continue
		var lock := ""
		if not has_building(faction, r["building"]):
			lock = "Needs a %s." % Defs.building_name(r["building"]).to_lower()
		out.append({"kind": "research", "id": id, "name": "Research " + r["name"].to_lower(), "cost": r["cost"],
			"desc": r["desc"], "locked": lock, "missing": missing_cost(faction, r["cost"])})
	return out


func craft_menu(faction: int) -> Array:
	var out := []
	var tier := armory_tier(faction)
	for id in Defs.ITEMS:
		var it: Dictionary = Defs.ITEMS[id]
		var cost := Defs.item_cost(id, maxi(tier, 0))
		var lock := craft_problem(faction, id)
		if tier >= 0 and int(it["tier"]) > tier + 1:
			continue
		out.append({"kind": "craft", "id": id, "name": "%d %s" % [it["batch"], Defs.item_name(id, int(it["batch"]))],
			"cost": cost, "locked": lock, "missing": missing_cost(faction, cost), "stock": int(fac(faction).gear.get(id, 0))})
	return out


func crews_of(faction: int) -> Array:
	var out := []
	for c: Crew in crews.values():
		if c.faction == faction and not c.members.is_empty():
			out.append(c)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func next_age_text(faction: int) -> String:
	var f := fac(faction)
	if f.age >= Defs.AGES.size() - 1:
		return "You've reached the Gunpowder age."
	return "Next: %s age. %s" % [Defs.AGES[f.age + 1], Defs.AGE_HOW[f.age + 1]]


## The facts Terra may use. Only what this faction knows, never hidden truth.
func brief(faction: int, addressed: String, crew_id: int, individual: bool = false, selected: int = 0) -> Dictionary:
	var f := fac(faction)
	var can_build := []
	var locked := []
	for e in build_menu(faction):
		var row := {"id": e["id"], "kind": e["kind"], "cost": e["cost"]}
		if e["locked"] == "":
			can_build.append(row)
		else:
			row["needs"] = e["locked"]
			locked.append(row)
	var can_craft := []
	for e in craft_menu(faction):
		var row := {"id": e["id"], "batch": Defs.ITEMS[e["id"]]["batch"], "cost": e["cost"], "in_armory": e["stock"]}
		if e["locked"] == "":
			can_craft.append(row)
		else:
			row["needs"] = e["locked"]
			locked.append(row)
	var crew_rows := []
	for c in crews_of(faction):
		if c.post < 0:      # a post's own jobs are summed up in its status
			crew_rows.append(crew_status(c))
	var post_rows := []
	for p in posts_of(faction):
		post_rows.append(post_status(p))
	var known := {}
	var camp = known_enemy_camp(faction)
	if camp != null:
		var d := int((camp as Vector2).distance_to(home_pos(faction)))
		known["enemy_camp"] = "%d m %s of home" % [d, Terrain.compass_name((camp as Vector2) - home_pos(faction))]
	else:
		known["enemy_camp"] = "unknown (send a scout)"
	var reports := []
	for r in f.reports.slice(0, 3):
		reports.append("%s (%d s ago)" % [r["text"], int(t - float(r["t"]))])
	known["latest_reports"] = reports
	var stock := {}
	for r in f.stock:
		stock[r] = int(f.stock[r])
	var gear := {}
	for g in f.gear:
		if int(f.gear[g]) > 0:
			gear[g] = int(f.gear[g])
	var named := {}
	var places := places_of(faction)
	for key: String in places:
		var away: Vector2 = places[key]["pos"] - home_pos(faction)
		named[Defs.PLACE + key] = "%s, %d m %s of home" % [places[key]["name"], int(away.length()), Terrain.compass_name(away)]
	var addressed_info := {"who": addressed, "individual": individual}
	if selected > 0:
		addressed_info["selected"] = selected
	if crew_id >= 0 and crews.has(crew_id):
		addressed_info["crew"] = crew_status(crews[crew_id])
	return {
		"time": "%d:%02d" % [int(t) / 60, int(t) % 60],
		"age": Defs.AGES[f.age],
		"next_age": next_age_text(faction),
		"stock": stock,
		"armory_stock": gear,
		"population": {"people": f.pop, "adults": f.adults, "children": f.children, "housing": f.housing,
			"idle_adults": f.idle, "armed": f.soldiers, "horses_in_stables": f.horses},
		"food": {"state": Defs.FOOD_STATES[f.food_state], "stored": int(f.stock.get("food", 0)), "storage": f.food_cap,
			"well_fed_needs": int(ceil(f.pop * Defs.WELL_FED_STOCK))},
		"addressed": addressed_info,
		"posts": post_rows,
		"places": named,
		"crews": crew_rows,
		"can_build": can_build,
		"can_craft": can_craft,
		"locked": locked,
		"known_map": known,
		"marked_spot": f.has_mark,
	}
