extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd
## Set MH_TEST=<name> to run a single test, MH_DUEL_MIN=<minutes> to change the duel length.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Match = preload("res://scripts/sim/match.gd")
const Rival = preload("res://scripts/ai/rival.gd")
const Parser = preload("res://scripts/orders/parser.gd")
const Schema = preload("res://scripts/orders/schema.gd")
const Hotkeys = preload("res://scripts/game/hotkeys.gd")
const ChatGPTCallback = preload("res://scripts/orders/chatgpt_callback.gd")
const ChatGPTVault = preload("res://scripts/orders/chatgpt_vault.gd")

var failures := 0
var passes := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	var only := OS.get_environment("MH_TEST")
	var tests := ["defs", "validation", "terrain", "map_sizes", "economy", "crews", "selection", "walls", "combat", "research", "shield", "parser", "schema", "chatgpt", "terra_orders", "hotkeys", "removed_buildings", "rings", "settlements", "path_queue", "rivals", "menu", "gathering", "construction", "back_to_work", "duel"]
	var t0 := Time.get_ticks_msec()
	for name in tests:
		if only != "" and only != name:
			continue
		print("--- ", name)
		call("test_" + name)
	print("\n%d passed, %d failed (%.1f s)" % [passes, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: ", msg)


func test_chatgpt() -> void:
	var terra_script := load("res://scripts/orders/terra.gd")
	var valid := "GET /auth/callback?state=test&client_id=example&code=a%2Bb HTTP/1.1"
	check(ChatGPTCallback._parse(valid, "test").get("code") == "a+b", "ChatGPT callback decodes the authorization code")
	check(ChatGPTCallback._parse(valid, "wrong").is_empty(), "ChatGPT callback requires matching state")
	check(ChatGPTCallback._parse("GET /auth/callback?state=test&state=other HTTP/1.1", "test").is_empty(), "ChatGPT callback rejects duplicate state")
	var plan := JSON.stringify({"kind": "reply", "reply": "Stores are full.", "steps": []})
	var delta := "data: " + JSON.stringify({"type": "response.output_text.delta", "delta": plan}) + "\r\n\r\n"
	var completed := "data: {\"type\":\"response.completed\"}\r\n\r\n"
	check(terra_script._read_stream(delta + completed).get("text") == plan, "ChatGPT stream returns completed text")
	check(terra_script._read_stream(delta).is_empty(), "ChatGPT stream discards incomplete output")
	var failure := "data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}"
	check(terra_script._read_stream(delta + failure).get("error", {}).get("code") == "subscription_sharing_usage_limit_exceeded", "ChatGPT stream preserves the failure code")
	check(not Schema.parse_plan(plan).is_empty(), "Terra accepts a well-formed answer")
	var malformed := JSON.stringify({"kind": "plan", "reply": "", "steps": [{"action": "gather",
		"subject": "wood", "where": "", "count": {}, "amount": 10}]})
	check(Schema.parse_plan(malformed).is_empty(), "Terra rejects a malformed model step before simulation")
	if OS.get_name() == "Windows":
		var example := "Windows credential storage test".to_utf8_buffer()
		var protected := ChatGPTVault._crypt(example, "Protect")
		check(not protected.is_empty() and protected != example, "Windows protects the local ChatGPT credential bytes")
		check(ChatGPTVault._crypt(protected, "Unprotect") == example, "Windows decrypts the protected bytes for this user")


func run(m, seconds: float, ais: Array = []) -> void:
	var steps := int(seconds / Defs.TICK)
	for i in steps:
		m.tick(Defs.TICK)
		for ai in ais:
			ai.update(Defs.TICK)
		m.events.clear()
		if m.over:
			break


func new_match(seed_in: int, ai_both: bool = false):
	var m = Match.new()
	m.setup({"seed": seed_in, "ai_both": ai_both})
	return m


# --- Tests ------------------------------------------------------------------------

func test_defs() -> void:
	for id in Defs.BUILDINGS:
		var d: Dictionary = Defs.BUILDINGS[id]
		for r in d["cost"]:
			check(r in Defs.RESOURCES, "%s cost uses unknown resource %s" % [id, r])
		check(d.has("desc"), "%s has a description" % id)
	for id in Defs.ITEMS:
		var it: Dictionary = Defs.ITEMS[id]
		for r in it["cost"]:
			check(r in Defs.RESOURCES, "%s cost uses unknown resource %s" % [id, r])
		check(int(it["batch"]) > 0, "%s batch > 0" % id)
	for a in Defs.ACTIONS:
		check(not Defs.subjects_for(a).is_empty(), "%s has subjects" % a)
	check(not "tin" in Defs.RESOURCES and not "copper" in Defs.RESOURCES, "copper and tin are merged into bronze ore")
	check(not "charcoal" in Defs.RESOURCES, "coal is mined, no charcoal")


func step(a: String, s: String = "", amount: int = 0, where: String = "", count: int = 0) -> Dictionary:
	return {"action": a, "subject": s, "count": count, "amount": amount, "where": where}


func test_validation() -> void:
	check(Defs.validate_steps([step("gather", "wood", 20), step("build", "hut")]) == "", "gather then build is valid")
	check(Defs.validate_steps([]) != "", "empty plan rejected")
	check(Defs.validate_steps([step("gather", "wood"), step("build", "hut")]) != "", "endless gathering must be last")
	check(Defs.validate_steps([step("guard"), step("gather", "wood", 5)]) != "", "guard must be last")
	check(Defs.validate_steps([step("build", "wood")]) != "", "build needs a structure")
	check(Defs.validate_steps([step("craft", "arrows", 32)]) == "", "craft with amount")
	check(Defs.validate_steps([step("build", "hut", 5)]) != "", "build can't take an amount")
	check(Defs.validate_steps([step("scout", "", 0, "east")]) == "", "scout east")
	check(Defs.validate_steps([step("scout", "", 0, "up")]) != "", "unknown direction")
	var nine := []
	for i in 9:
		nine.append(step("build", "hut"))
	check(Defs.validate_steps(nine) != "", "more than eight steps rejected")
	check(Defs.validate_steps([step("teleport")]) != "", "unknown action rejected")


func test_terrain() -> void:
	for id in Defs.MAP_SIZES:
		_check_terrain(id)


func _check_terrain(id: String) -> void:
	var info: Dictionary = Defs.MAP_SIZES[id]
	var margin: float = info["margin"]
	for s in range(1, 13):
		var tr = Terrain.new()
		tr.generate(s * 977, id)
		var a: Vector2 = tr.starts[0]
		var b: Vector2 = tr.starts[1]
		check(a.distance_to(b) >= info["min_start"], "%s seed %d camps %.0f m apart" % [id, s, a.distance_to(b)])
		for p in [a, b]:
			check(tr.in_bounds(p, margin - 1), "%s seed %d camp inside margins" % [id, s])
			var kinds := {}
			for n in tr.nodes:
				var d: float = n.pos.distance_to(p)
				if n.kind == "berry" and d < 90.0:
					kinds["berry"] = true
				if n.kind == "tree" and d < 120.0:
					kinds["tree"] = true
				if n.kind == "deposit" and d < 230.0:
					kinds[n.sub] = true
				if n.kind == "rock" and n.sub == "outcrop" and d < 160.0:
					kinds["outcrop"] = true
			for k in ["berry", "tree", "bronze_ore", "coal", "iron_ore", "outcrop"]:
				check(kinds.has(k), "%s seed %d: %s near camp" % [id, s, k])
			var home_stone = null
			for n in tr.nodes:
				if n.sub == "outcrop" and n.pos.distance_to(p) < 34.0:
					home_stone = n
			check(home_stone != null, "%s seed %d: stone beside camp" % [id, s])
			if home_stone:
				var eye: Vector3 = tr.pos3(p, 1.7)
				check(home_stone.landmark_name() == "Stone", "%s seed %d: home outcrop is named" % [id, s])
				check(tr.clear_line(eye, tr.pos3(home_stone.pos, 4.0)), "%s seed %d: home outcrop in sight of camp" % [id, s])
				check(not tr.clear_line(eye, tr.pos3(home_stone.pos, -3.0)), "%s seed %d: ground blocks a line of sight" % [id, s])
		if s == 1:
			print("  %s: trees %d, nodes %d" % [id, tr.count_nodes("tree"), tr.nodes.size()])


func test_economy() -> void:
	var m = new_match(5)
	var f = m.fac(0)
	check(f.pop == Defs.START_VILLAGERS, "start with six villagers")
	check(f.housing == 8, "campfire houses 8")
	var hut_wood := float(Defs.BUILDINGS["hut"]["cost"]["wood"])
	var r: Dictionary = m.command(0, {"steps": [step("gather", "wood", int(hut_wood) + 30, "", 6)]})
	check(r.get("ok", false), "gather order accepted: %s" % r.get("error", ""))
	run(m, 150.0)
	check(float(f.stock["wood"]) >= hut_wood, "wood gathered for a hut (%.0f of %.0f)" % [float(f.stock["wood"]), hut_wood])
	var home: Vector2 = m.home_pos(0)
	var site := {}
	for k in 24:
		var p: Vector2 = home + Vector2.from_angle(k * 0.7) * (14.0 + k)
		site = m.place_site(0, "hut", p, 0.0)
		if site.get("ok", false):
			break
	check(site.get("ok", false), "hut site placed: %s" % site.get("error", ""))
	var st := step("build", "hut")
	st["sites"] = [site.get("id", -1)]
	r = m.command(0, {"steps": [st]})
	check(r.get("ok", false), "build order accepted: %s" % r.get("error", ""))
	run(m, 60.0)
	check(m.bld(site.get("id", -1)) != null and m.bld(site["id"]).complete, "hut built")
	m._refresh_counts(f)
	check(f.housing == 14, "housing rose to 14 (%d)" % f.housing)
	check(f.pop > Defs.START_VILLAGERS, "births happened while well fed (%d people)" % f.pop)
	var bad: Dictionary = m.place_site(0, "tower", home + Vector2(30, 30), 0.0)
	check(not bad.get("ok", true), "tower locked in the Wood age")
	# Berries feed the village.
	var food_before := float(f.stock["food"])
	r = m.command(0, {"steps": [step("gather", "berries", 0, "", 3)]})
	run(m, 40.0)
	check(float(f.stock["food"]) > food_before - 5.0, "berry pickers keep food up")


func test_crews() -> void:
	var m = new_match(414)
	var adults: Array = m.idle_adults(0, m.home_pos(0))
	var lead = adults[0]
	var worker = adults[1]
	var remaining = adults[2]
	var other = adults[3]
	var crew = m.make_crew(0, [lead, worker, remaining])
	var destination = m.make_crew(0, [other])
	m.command(0, {"crew": crew.id, "steps": [step("promote"), step("gather", "wood")]})
	m.command(0, {"crew": destination.id, "steps": [step("promote"), step("hold")]})
	m.update_crews(0.0)
	check(crew.captain and destination.captain, "promoting each crew gives it a captain")
	var order: Dictionary = m.command(0, {"unit": worker.id, "steps": [step("gather", "berries")]})
	check(order["ok"] and lead.crew == crew.id and worker.crew == crew.id and crew.steps[0]["subject"] == "berries", "addressing a member orders their whole crew")
	var individual := {"unit": worker.id, "individual": true}
	order = m.command(0, individual.merged({"steps": [step("status")]}))
	check(order["ok"] and worker.crew == crew.id and worker.task == "gather", "individual status preserves the worker's assignment")
	order = m.command(0, individual.merged({"steps": [step("hold", "", 0, "marked")]}))
	check(not order["ok"] and worker.crew == crew.id, "invalid individual order preserves crew membership")
	order = m.command(0, individual.merged({"steps": [step("follow", "", 0, "", 3)]}))
	var solo = m.crew_of(worker)
	check(order["ok"] and solo != crew and solo.members == [worker.id] and worker.task == "follow", "individual order takes only that worker, even with a requested count")
	check(crew.members == [lead.id, remaining.id] and remaining.task == "gather", "the original crew continues its work")
	var state: Dictionary = destination.state.duplicate()
	var moved: Dictionary = m.reassign_crew(0, individual, other.id)
	check(moved["ok"] and worker.crew == destination.id and worker.task == "hold" and destination.state == state, "transferred worker takes up the destination crew's active plan")
	check(not m.crews.has(solo.id), "transfer removes the worker's empty former crew")
	check(m.cancel(0, individual) == 1 and worker.crew < 0 and other.task == "hold", "individual cancel releases only the addressed worker")
	order = m.command(0, {"unit": lead.id, "individual": true, "steps": [step("follow")]})
	check(order["ok"] and m.crew_of(lead).captain and not crew.captain and remaining.task == "gather", "a captain keeps their rank when given a solo assignment")
	moved = m.reassign_crew(0, {"crew": crew.id}, other.id)
	check(moved["ok"] and remaining.crew == destination.id and remaining.task == "hold", "whole crews can transfer to another captain")
	var enemy = m.idle_adults(1, m.home_pos(1))[0]
	moved = m.reassign_crew(0, {"crew": destination.id}, enemy.id)
	check(not moved["ok"] and remaining.crew == destination.id, "invalid transfer leaves the original assignment intact")
	var idle_group = m.make_crew(0, [adults[4], adults[5]])
	moved = m.reassign_crew(0, {"unit": adults[4].id, "individual": true}, other.id)
	check(moved["ok"] and adults[5].crew == idle_group.id, "an idle group stays together when one member transfers")
	order = m.command(0, {"unit": remaining.id, "individual": true, "steps": [step("dismiss")]})
	check(order["ok"] and remaining.crew < 0 and other.task == "hold", "individual dismissal leaves the rest of the destination crew on duty")


func test_selection() -> void:
	var m = new_match(77)
	var adults: Array = m.idle_adults(0, m.home_pos(0))
	var a = adults[0]
	var b = adults[1]
	var c = adults[2]
	var d = adults[3]
	var big = m.make_crew(0, [a, b, c])
	m.command(0, {"crew": big.id, "steps": [step("gather", "wood")]})
	var r: Dictionary = m.command(0, {"units": [a.id, d.id], "steps": [step("gather", "stone", 0, "", 5)]})
	var picked = m.crew_of(a)
	check(r["ok"] and picked != null and picked == m.crew_of(d), "selected villagers form one crew")
	check(picked.members.size() == 2 and picked.steps[0]["subject"] == "stone", "the selection crew has exactly the picked people (%d)" % picked.members.size())
	check(m.crew_of(b) == big and big.members.size() == 2 and b.task == "gather", "the rest of the old crew keeps working")
	r = m.command(0, {"units": [a.id, d.id], "steps": [step("gather", "berries")]})
	check(r["ok"] and m.crew_of(a) == picked, "re-ordering the same selection reuses its crew")
	r = m.command(0, {"units": [a.id], "steps": [step("status")]})
	check(r["ok"] and m.crew_of(a) == picked, "status for a selection keeps assignments")
	check(m.cancel(0, {"units": [a.id, d.id]}) == 2 and m.crew_of(a) == null and a.task == "idle", "stopping a selection frees them")
	r = m.command(0, {"units": [], "steps": [step("gather", "wood")]})
	check(not r["ok"], "an empty selection is refused")
	var joined: Dictionary = m.reassign_crew(0, {"units": [a.id, d.id]}, b.id)
	check(joined["ok"] and m.crew_of(a) == big and m.crew_of(d) == big and big.members.size() == 4, "a selection can join another crew")


func test_back_to_work() -> void:
	var m = new_match(91)
	var adults: Array = m.idle_adults(0, m.home_pos(0))
	var woodcutters = [adults[0], adults[1]]
	var miners = [adults[2], adults[3]]
	var idler = adults[4]
	var wood_crew = m.make_crew(0, woodcutters)
	var stone_crew = m.make_crew(0, miners)
	m.command(0, {"crew": wood_crew.id, "steps": [step("gather", "wood")]})
	m.command(0, {"crew": stone_crew.id, "steps": [step("gather", "stone", 40)]})
	run(m, 3.0)
	var r: Dictionary = m.command(0, {"all": true, "steps": [step("guard", "", 0, "home")]})
	check(r["ok"] and woodcutters[0].task != "gather" and miners[0].task != "gather", "to arms pulls everyone off their work")
	check(m.crew_of(idler) != null and m.crew_of(idler).steps[-1]["action"] == "guard", "idle villagers are drafted too")
	r = m.command(0, {"all": true, "steps": [step("resume_work")]})
	check(r["ok"], "back to work succeeds after to arms")
	check(m.crew_of(woodcutters[0]) == wood_crew and wood_crew.steps[0]["subject"] == "wood" and woodcutters[0].task == "gather", "woodcutters go back to wood in the same crew")
	var back_stone = m.crew_of(miners[0])
	check(back_stone != null and back_stone.steps[0]["subject"] == "stone" and miners[1].crew == back_stone.id and miners[0].task == "gather", "miners go back to stone together")
	check(m.crew_of(idler) == null and idler.task == "idle", "people who were idle go back to idle")
	check(m.work_memory.is_empty(), "returning clears the memory")
	r = m.command(0, {"all": true, "steps": [step("resume_work")]})
	check(not r["ok"], "back to work with nothing remembered says so")
	# Calling to arms twice must not overwrite the earlier memory with the guard post.
	m.command(0, {"all": true, "steps": [step("guard", "", 0, "home")]})
	m.command(0, {"all": true, "steps": [step("guard", "", 0, "home")]})
	r = m.command(0, {"all": true, "steps": [step("resume_work")]})
	check(r["ok"] and woodcutters[0].task == "gather", "a second military order keeps the original job")
	# New work given in between wins over the old memory.
	m.command(0, {"all": true, "steps": [step("guard", "", 0, "home")]})
	m.command(0, {"unit": woodcutters[0].id, "steps": [step("gather", "berries")]})
	m.command(0, {"all": true, "steps": [step("resume_work")]})
	check(m.crew_of(woodcutters[0]).steps[0]["subject"] == "berries", "someone given new work keeps it")
	# Addressing one crew restores only that crew.
	m.command(0, {"all": true, "steps": [step("guard", "", 0, "home")]})
	r = m.command(0, {"unit": miners[0].id, "steps": [step("resume_work")]})
	check(r["ok"] and miners[0].task == "gather" and miners[0].crew >= 0 and woodcutters[1].task == "guard", "addressed back to work only returns that crew")
	check(Defs.validate_steps([step("resume_work"), step("gather", "wood")]) != "", "back to work can't be mixed with other steps")


func test_walls() -> void:
	var m = new_match(8)
	var f = m.fac(0)
	f.stock["wood"] = 500.0
	var home: Vector2 = m.home_pos(0)
	var pts := [home + Vector2(-20, 25), home + Vector2(0, 30), home + Vector2(20, 25)]
	var r: Dictionary = m.place_wall(0, "palisade", pts)
	check(r.get("ok", false), "palisade placed post to post: %s" % r.get("error", ""))
	var ids: Array = r.get("ids", [])
	check(ids.size() >= 8, "about 10 pieces for 40 m (%d)" % ids.size())
	var st := step("build", "palisade")
	st["sites"] = ids
	r = m.command(0, {"steps": [st], })
	check(r.get("ok", false), "wall crew assigned")
	run(m, 90.0)
	var done := 0
	for id in ids:
		var b = m.bld(id)
		if b and b.complete:
			done += 1
	check(done == ids.size(), "all palisade pieces built (%d/%d)" % [done, ids.size()])
	var b0 = m.bld(ids[0])
	if b0:
		var c: Vector2i = m.cell_of(b0.pos)
		check(m.solid_for(1, c), "palisade blocks the enemy")


func test_combat() -> void:
	var m = new_match(11)
	var f = m.fac(0)
	f.gear["wood_spear"] = 8
	f.gear["bow"] = 2
	f.gear["arrows"] = 40
	f.stock["wood"] = 200.0
	var home: Vector2 = m.home_pos(0)
	var arm: Dictionary = {}
	for k in 30:
		arm = m.place_site(0, "armory", home + Vector2.from_angle(k * 0.5) * (16.0 + k * 0.5), 0.0)
		if arm.get("ok", false):
			break
	m.bld(arm["id"]).progress = 1.0
	m._complete(m.bld(arm["id"]))
	var r: Dictionary = m.command(0, {"steps": [step("arm", "", 0, "", 6), step("guard", "", 0, "home")]})
	check(r.get("ok", false), "arm and guard accepted: %s" % r.get("error", ""))
	run(m, 30.0)
	var armed := 0
	for u in m.units:
		if u.faction == 0 and u.kind == "villager" and (u.weapon != "" or u.bow):
			armed += 1
	check(armed >= 5, "villagers armed (%d)" % armed)
	# Enemy raiders walk in.
	var raiders := []
	for k in 4:
		var e = m.spawn_unit(1, "villager", home + Vector2(60, 0) + Vector2(k * 1.5, 0))
		e.name = "Raider"
		e.weapon = "wood_spear"
		raiders.append(e)
	var rc = m.make_crew(1, raiders)
	rc.steps = [step("attack", "", 0, "")]
	rc.state = {"target": home}
	rc.idx = 0
	for e in raiders:
		m._set_task(e, "attack")
	run(m, 60.0)
	var alive := 0
	for e in raiders:
		if not e.dead:
			alive += 1
	check(alive <= 1, "the raid was beaten off (%d raiders left)" % alive)
	check(m.fac(1).deaths >= 3 or alive <= 1, "raiders died")
	# Cannon vs a wall piece.
	var m2 = new_match(12)
	var w = m2.add_building(1, "stone_wall", m2.home_pos(1) + Vector2(40, 0), 0.0, true)
	var cn = m2.spawn_unit(0, "cannon", w.pos + Vector2(-90, 0))
	cn.ammo = 8
	var crewmen := []
	for k in 3:
		var cm = m2.spawn_unit(0, "villager", cn.pos + Vector2(-2, k))
		cm.siege = cn.id
		cn.crew_ids.append(cm.id)
		crewmen.append(cm)
	var cc = m2.make_crew(0, crewmen)
	cc.steps = [step("hold")]
	cc.state = {"target": cn.pos}
	for cm in crewmen:
		m2._set_task(cm, "hold")
	run(m2, 70.0)
	check(w.dead or w.hp < w.max_hp * 0.5, "cannon shots break a stone wall (hp %.0f / %.0f)" % [w.hp, w.max_hp])


func test_research() -> void:
	var m = new_match(14)
	var f = m.fac(0)
	f.age = 1
	var entry := {}
	for e in m.research_menu(0):
		if e["id"] == "mounted_archery":
			entry = e
	check(not entry.is_empty() and entry["locked"] != "", "mounted archery is listed but locked without a stable")
	for e in m.build_menu(0):
		check(e["kind"] != "research", "research is not in the build menu")
	var rider = m.spawn_unit(0, "villager", m.home_pos(0))
	rider.bow = true
	rider.arrows = 10
	check(m.can_shoot_bow(rider), "archers shoot on foot")
	rider.mounted = true
	check(not m.can_shoot_bow(rider), "riders can't shoot before the research")
	f.researched["mounted_archery"] = true
	check(m.can_shoot_bow(rider), "riders shoot once mounted archery is known")
	var pr: Dictionary = Parser.parse("research mounted archery")
	check(pr.get("ok", false) and pr["steps"][0]["action"] == "research" and pr["steps"][0]["subject"] == "mounted_archery", "parser reads 'research mounted archery'")
	check("mounted_archery" in Defs.subjects_for("research"), "schema offers mounted_archery")


func test_shield() -> void:
	var m = new_match(13)
	var me = m.commander(0)
	var foe = m.spawn_unit(1, "villager", me.pos + Vector2(0, 1.5))
	foe.weapon = "wood_spear"
	m.units.assign([me, foe]) # no bystanders in the line of fire
	var base: float = m.melee_damage(foe, me)
	m.set_commander(0, me.pos, 0.0, 0, true)
	check(not me.shield_up, "nothing to raise without a shield")
	for id in ["wood_shield", "bronze_shield", "iron_shield"]:
		var d: Dictionary = Defs.ITEMS[id]
		me.shield = id
		m.set_commander(0, me.pos, 0.0, 0, false)
		foe.pos = me.pos + Vector2(0, 1.5)
		check(is_equal_approx(m.melee_damage(foe, me), base * (1.0 - d["block_melee"])), "%s carried keeps its usual protection" % id)
		m.set_commander(0, me.pos, 0.0, 0, true)
		for deg in [0.0, 65.0, -65.0, 75.0, -75.0, 180.0]:
			foe.pos = me.pos + Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg))) * 1.5
			var key := "up_melee" if absf(deg) < 70.0 else "block_melee"
			check(is_equal_approx(m.melee_damage(foe, me), base * (1.0 - d[key])), "%s raised, blow from %d degrees" % [id, deg])
		for side in [1.0, -1.0]:
			for free in [false, true]:
				m.shots.clear()
				me.hp = me.max_hp
				me.prev = me.pos
				var s = m.Shot.new()
				s.kind = "arrow"
				s.faction = 1
				s.shooter = foe.id
				s.dmg = 20.0
				var ground: float = m.terrain.height_at(me.pos.x, me.pos.y)
				s.start = Vector3(me.pos.x, ground + 1.1, me.pos.y + 12.0 * side)
				s.end = Vector3(me.pos.x, ground + 1.1, me.pos.y)
				s.free = free
				if free:
					s.pos = s.end + Vector3(0, 0, 0.8 * side)
					s.vel = Vector3(0, 0, -10.0 * side)
				else:
					s.hits = true
					s.target = me.id
					s.dur = 0.05
				m.rebuild_unit_hash()
				m.shots.append(s)
				m.update_shots(0.1)
				var stopped: float = d["up_arrow"] if side > 0.0 else d["block_arrow"] * (0.7 if free else 1.0)
				check(absf((me.max_hp - me.hp) - 20.0 * (1.0 - stopped)) < 0.01, "%s raised, %s arrow from the %s" % [id, "free" if free else "aimed", "front" if side > 0.0 else "back"])


func test_parser() -> void:
	var P = Parser
	var r: Dictionary = P.parse("gather wood")
	check(r.get("ok", false) and r["steps"][0]["action"] == "gather" and r["steps"][0]["subject"] == "wood", "gather wood")
	r = P.parse("gather 30 wood then build a hut")
	check(r.get("ok", false) and r["steps"].size() == 2 and r["steps"][0]["amount"] == 30 and r["steps"][1]["subject"] == "hut", "two-step plan")
	r = P.parse("send two scouts east")
	check(r.get("ok", false) and r["steps"][0]["action"] == "scout" and r["steps"][0]["where"] == "east" and r["steps"][0]["count"] == 2, "send two scouts east")
	r = P.parse("make 32 arrows")
	check(r.get("ok", false) and r["steps"][0]["action"] == "craft" and r["steps"][0]["subject"] == "arrows" and r["steps"][0]["amount"] == 32, "make arrows")
	r = P.parse("follow me")
	check(r.get("ok", false) and r["steps"][0]["action"] == "follow", "follow me")
	r = P.parse("fall back")
	check(r.get("ok", false) and r["steps"][0]["action"] == "recall", "fall back")
	r = P.parse("to arms!")
	check(r.get("ok", false) and r["steps"][0]["action"] == "arm" and r["steps"][-1]["action"] == "guard", "to arms")
	r = P.parse("back to work")
	check(r.get("ok", false) and r["steps"][0]["action"] == "resume_work" and r.get("all", false), "back to work")
	r = P.parse("okay everyone get back to work!")
	check(r.get("ok", false) and r["steps"].size() == 1 and r["steps"][0]["action"] == "resume_work", "get back to work")
	r = P.parse("arm 6 with spears and guard the camp")
	check(r.get("ok", false) and r["steps"][0]["subject"] == "wood_spear" and r["steps"][0]["count"] == 6, "arm with spears")
	r = P.parse("what should we do about the weather in spain")
	check(not r.get("ok", false), "nonsense is not parsed")
	r = P.parse("build a stone wall")
	check(r.get("ok", false) and r["steps"][0]["subject"] == "stone_wall", "stone wall")
	r = P.parse("smelt bronze")
	check(r.get("ok", false) and r["steps"][0]["action"] == "smelt", "smelt bronze")
	var resumes := {"continue construction": "", "continue": "", "resume building": "", "keep building": "", "finish it": "",
		"finish the job": "", "please continue": "", "continue, please": "", "go back to building": "", "get back to work": "",
		"continue building the hut": "hut", "finish the farm": "farm", "keep building the farm": "farm",
		"keep building the stone wall": "stone_wall", "get back to building the stone wall": "stone_wall",
		"continue the construction of the armory": "armory", "continue work on the house": "house", "build it": "",
		"finish the stockpile by the berries": "stockpile", "help with the construction": "", "finish that hunter's lodge": "lodge",
		"send 2 builders to finish the hut": "hut", "everyone continue construction": "", "finish off the watch post": "watch_post",
		"continue where you left off": "", "resume construction on the granary": "granary", "go finish the quarry": "quarry"}
	for text in resumes:
		r = P.parse(text)
		check(r["ok"] and r["steps"][0]["action"] == "resume" and r["steps"][0]["subject"] == resumes[text], "resume: " + text)
	r = P.parse("finish the wall")
	check(r["ok"] and r["steps"][0].get("match") == "wall", "a plain wall can be either material")
	for text in ["continue gathering wood", "finish gathering berries", "keep gathering wood", "gather wood to finish the hut",
			"work the farms", "continue working on the farm", "go home", "go back to camp", "return to base", "build a hut", "build another hut"]:
		r = P.parse(text)
		check(not r["steps"].any(func(s): return s["action"] == "resume" or s.has("match")), "not a resume: " + text)
	r = P.parse("gather 30 wood and finish the hut")
	check(r["ok"] and r["steps"].size() == 2 and r["steps"][1]["action"] == "resume", "gather then resume")
	var places := {"gather wood": "", "gather wood for the camp": "", "bring me wood": "", "get them some wood": "",
		"chop trees here": "here", "pick berries over there": "marked", "gather wood to the north": "north"}
	for text in places:
		r = P.parse(text)
		check(r["ok"] and r["steps"][0]["where"] == places[text], "gather place: " + text)
	r = P.parse("attack their camp")
	check(r.get("ok", false) and r["steps"][0]["action"] == "attack" and r["steps"][0]["where"] == "enemy", "attack their camp")


func test_schema() -> void:
	check("resume" in Schema.plan_schema()["properties"]["steps"]["items"]["properties"]["action"]["enum"], "Terra can resume construction")
	var sc: Dictionary = Schema.plan_schema()
	check(sc["type"] == "object" and sc["additionalProperties"] == false, "strict object")
	var items: Dictionary = sc["properties"]["steps"]["items"]
	check(items["required"].size() == items["properties"].size(), "every step field is required (strict mode)")
	check("gather" in items["properties"]["action"]["enum"], "actions come from the data tables")
	check("university" in items["properties"]["subject"]["enum"], "subjects include buildings")
	var text := JSON.stringify(sc)
	check(text.length() > 200 and JSON.parse_string(text) != null, "schema serializes")
	var steps := [step("gather", "wood", 10)]
	check(not Schema.parse_plan(JSON.stringify({"kind": "plan", "reply": "", "steps": steps})).is_empty(), "Terra accepts an actionable plan")
	check(Schema.parse_plan(JSON.stringify({"kind": "reply", "reply": "", "steps": steps})).is_empty(), "Terra rejects steps attached to advice")
	check(Schema.parse_plan(JSON.stringify({"kind": "plan", "reply": "", "steps": []})).is_empty(), "Terra rejects a plan with no steps")


func test_terra_orders() -> void:
	var game = load("res://scripts/game/game.gd").new()
	var m = new_match(8)
	game.m = m
	game.hud = game.Hud.new()
	game.add_child(game.hud)
	game.view = game.WorldView.new()
	game.view.ghost = MeshInstance3D.new()
	game.view.add_child(game.view.ghost)
	game.add_child(game.view)
	root.add_child(game)
	var worker = m.idle_adults(0, m.home_pos(0))[0]
	var ctx := {"req": {"unit": worker.id, "individual": true}, "who": worker.name, "text": "We could use a little more timber in the stores."}
	var gather := {"ok": true, "data": {"kind": "plan", "reply": "I'll gather ten wood.", "steps": [step("gather", "wood", 10)]}}
	game.terra_ctx = ctx
	game._on_terra(gather)
	var crew = m.crew_of(worker)
	check(crew != null and worker.task == "gather" and crew.steps[0]["amount"] == 10, "Terra starts the addressed villager's order immediately")
	game.terra_ctx = ctx
	game._on_terra({"ok": true, "data": {"kind": "reply", "reply": "A hut would house five people.", "steps": []}})
	check(worker.task == "gather" and not game.placing, "Terra advice leaves the crew and placement untouched")
	game.terra_ctx = ctx
	check(game._discard_terra_request({}), "an outstanding Terra order can be cancelled")
	game._on_terra({"ok": true, "data": {"kind": "plan", "reply": "", "steps": [step("hold")]}})
	check(worker.task == "gather", "Terra ignores a cancelled order's later response")
	game.terra_ctx = ctx
	game._on_terra({"ok": true, "data": {"kind": "plan", "reply": "Choose a spot for the hut.", "steps": [step("build", "hut")]}})
	check(game.placing and game.place_type == "hut" and worker.task == "gather" and m.buildings_of(0, "hut", false).is_empty(), "Terra opens placement and waits for the player to choose the site")
	var home: Vector2 = m.home_pos(0)
	for i in 12:
		var pos := home + Vector2.from_angle(i * TAU / 12.0) * 24.0
		if m.site_problem(0, "hut", pos, game.place_rot) == "":
			game.place_pos = pos
			game.place_ok = true
			game._place_click()
			break
	var huts: Array = m.buildings_of(0, "hut", false)
	check(not game.placing and worker.task == "build" and huts.size() == 1 and huts[0].pos == game.place_pos, "the chosen site becomes the addressed villager's construction job")
	game.free()


func test_hotkeys() -> void:
	var wanted := {}
	for id in Defs.buildable_ids():
		wanted["build:" + id] = true
	for id in Defs.UPGRADES:
		wanted["upgrade:" + Defs.UPGRADES[id]["building"]] = true
	wanted["research:gunpowder"] = true
	for id in Defs.ITEMS:
		wanted["craft:" + id] = true
	var keyed := {}
	for command in Defs.HOTKEYS:
		for page in Defs.HOTKEYS[command]:
			var keys: Dictionary = Defs.HOTKEYS[command][page]["keys"]
			for key: String in keys:
				var slot: String = keys[key]
				check(key.length() == 1 and key == key.to_lower(), "%s %s %s is one letter" % [command, page, key])
				check(wanted.has(slot), "%s %s %s points at something in the game (%s)" % [command, page, key, slot])
				check(not keyed.has(slot), "%s has only one key" % slot)
				check(ResourceLoader.exists("res://assets/icons/%s.png" % slot.replace(":", "_")), "%s has a picture" % slot)
				keyed[slot] = true
	for slot in wanted:
		check(keyed.has(slot), "%s has a key" % slot)

	var m = new_match(21)
	var f = m.fac(0)
	var read := func(command: String, words: String) -> Dictionary:
		return Hotkeys.read(m, command, words.split(" ", false))
	check(read.call("b", "B H")["entry"]["id"] == "hut", "hotkeys ignore case")
	check(read.call("b", "hut").is_empty() and read.call("c", "bow").is_empty(), "names are left to the name lookup")
	check(read.call("b", "b z")["error"] != "", "an unused key is explained")
	check(read.call("b", "b h 2")["error"] != "", "a structure takes no count")
	check(read.call("b", "v w")["error"].contains("Stone age"), "a locked key says what it needs")
	check(read.call("b", "v a")["error"].contains("armory"), "an upgrade needs its building")
	check(read.call("c", "b w")["error"].contains("armory"), "weapons need an armory")
	m.add_building(0, "armory", m.home_pos(0) + Vector2(20, 0), 0.0, true)
	var two: Dictionary = read.call("c", "b w 2")
	check(two["error"] == "" and two["batches"] == 2 and two["entry"]["id"] == "wood_spear", "/c b w 2 is two batches of spears")
	for bad in ["b w 0", "b w x", "b w 100", "b w 2 2"]:
		check(read.call("c", bad)["error"] != "", "bad batch count refused: " + bad)
	check(Array(Hotkeys.split_keys(PackedStringArray(["bh"]))) == ["b", "h"], "quick keys need no space")
	check(Array(Hotkeys.split_keys(PackedStringArray(["hut"]))) == ["hut"], "quick keys still allow names")

	var game = load("res://scripts/game/game.gd").new()
	game.m = m
	game.hud = game.Hud.new()
	game.add_child(game.hud)
	game.view = game.WorldView.new()
	game.add_child(game.view)
	root.add_child(game)
	game._slash("/b b h")
	check(game.placing and game.place_type == "hut", "/b b h places a hut")
	game.placing = false
	game._slash("/b v w")
	check(not game.placing, "a locked structure can't be placed by key")
	f.age = 1
	game._slash("/build v w")
	check(game.placing and game.place_type == "stone_wall", "/build v w places a stone wall")
	game.placing = false
	game._slash("/b hut")
	check(game.placing and game.place_type == "hut", "names still work")
	game.placing = false
	f.stock["wood"] = 100.0
	game._slash("/c b w 2")
	var made := []
	for c in m.crews_of(0):
		for s in c.steps:
			if s["action"] == "craft":
				made.append([s["subject"], int(s["amount"])])
	check(made == [["wood_spear", 2 * int(Defs.ITEMS["wood_spear"]["batch"])]], "/c b w 2 orders two batches (%s)" % str(made))
	game.free()


func test_removed_buildings() -> void:
	for id in ["lodge", "granary", "house"]:
		check(not Defs.BUILDINGS.has(id) and not id in Defs.all_subjects(), "%s is gone from the game and Terra's schema" % id)
	for order in ["build a house", "build a granary", "build a hunter's lodge", "build a hunting lodge"]:
		check(not Parser.parse(order)["ok"], "'%s' isn't taken for another order" % order)
	check(Parser.parse("build a storehouse")["steps"][0]["subject"] == "stockpile", "a storehouse is still a stockpile")

	var m = new_match(33)
	var home: Vector2 = m.home_pos(0)
	for k in 3:
		m.spawn_unit(-1, "deer", home + Vector2(30 + k * 2, 0)).goal = home + Vector2(30, 0)
	var r: Dictionary = m.command(0, {"steps": [step("gather", "hunt", 0, "", 3)]})
	check(r.get("ok", false), "hunting needs no building: %s" % r.get("error", ""))
	if r.get("ok", false):
		run(m, 120.0)
		var crew = m.crews.get(r["crews"][0])
		check(crew != null and float(crew.state.get("delivered", 0.0)) > 0.0, "hunters bring meat to the nearest drop-off")

	var full = new_match(4242, true)
	var ai = Rival.new()
	ai.setup(full, {"faction": 1, "difficulty": 1, "strategy": "boom", "seed": 5})
	var f = full.fac(1)
	f.age = 1
	for type in ["hut", "stockpile"]:
		for i in 70:
			full._refresh_counts(f)
			if (type == "hut" and f.housing >= Defs.POP_HARD_CAP) or (type == "stockpile" and f.food_cap >= Defs.POP_HARD_CAP * Defs.WELL_FED_STOCK):
				break
			var at = ai._find_site(type)
			if at != null:
				full.add_building(1, type, at[0], at[1], true)
	full._refresh_counts(f)
	check(f.housing == Defs.POP_HARD_CAP, "the rival has room for huts to house 200 (%d)" % f.housing)
	check(f.food_cap >= Defs.POP_HARD_CAP * Defs.WELL_FED_STOCK, "the rival has room to store food for 200 (%d)" % f.food_cap)


func open_site(m, type: String, near: Vector2, from: float = 6.0) -> Vector2:
	for r in 40:
		for k in 24:
			var p: Vector2 = near + Vector2.from_angle(k * TAU / 24.0) * (from + r)
			if m.site_problem(0, type, p, 0.0) == "":
				return p
	check(false, "found room for a %s" % type)
	return near


func test_gathering() -> void:
	for kind in ["berry", "tree"]:
		var subject := "berries" if kind == "berry" else "wood"
		var m = new_match(977)
		var home: Vector2 = m.home_pos(0)
		var far = null
		for n in m.terrain.nodes:
			var d: float = n.pos.distance_to(home)
			if n.kind == kind and d < 100.0 and (far == null or d > far.pos.distance_to(home)):
				far = n
		var workers: Array = m.idle_adults(0, home).slice(0, 4)
		var req := {"units": workers.map(func(u): return u.id), "steps": [step("gather", subject)]}
		m.command(0, req)
		run(m, 2.0)
		var store := open_site(m, "stockpile", far.pos)
		var pile = m.add_building(0, "stockpile", store, 0.0, true)
		# Those already at work move over once they next choose where to go.
		run(m, 90.0)
		for u in workers:
			check(u.tgt_node < 0 or m.terrain.nodes[u.tgt_node].pos.distance_to(store) < m.terrain.nodes[u.tgt_node].pos.distance_to(home),
				"%s gatherers move to the ones by a new stockpile" % kind)
		req["steps"] = [step("gather", subject, 0, "home")]
		m.command(0, req)
		run(m, 0.2)
		var w = workers[0]
		check(w.tgt_node >= 0 and m.terrain.nodes[w.tgt_node].pos.distance_to(home) < m.terrain.nodes[w.tgt_node].pos.distance_to(store), "a named place overrides the shortest %s haul" % kind)
		m.remove_building(pile)
		req["steps"] = [step("gather", subject)]
		m.command(0, req)
		run(m, 0.2)
		check(w.tgt_node >= 0 and m.terrain.nodes[w.tgt_node].pos.distance_to(home) < far.pos.distance_to(home), "losing the stockpile sends %s gatherers back toward camp" % kind)
	# The rival repeats orders every second or so. A full load must still reach the store.
	var rm = new_match(977)
	var hauler = rm.idle_adults(0, rm.home_pos(0))[0]
	var again := {"units": [hauler.id], "steps": [step("gather", "wood")]}
	for second in 90:
		rm.command(0, again)
		run(rm, 1.0)
	check(float(rm.fac(0).stock["wood"]) >= 5.0, "repeated orders don't stop a full load being delivered")
	# A bush touching a stockpile sits in blocked ground and must still be pickable.
	for offset in [Vector2(3.2, 0), Vector2(0, -3.2), Vector2(3.2, 3.2), Vector2(-3.2, 0.5)]:
		var m = new_match(31)
		var home: Vector2 = m.home_pos(0)
		var p := open_site(m, "stockpile", home, 16.0)
		m.add_building(0, "stockpile", p, 0.0, true)
		var bush = Terrain.RNode.new()
		bush.id = m.terrain.nodes.size()
		bush.kind = "berry"
		bush.pos = p + offset
		bush.amount = 80.0
		m.terrain.nodes.append(bush)
		m._bucket_node(bush)
		m.command(0, {"units": [m.idle_adults(0, home)[0].id], "steps": [step("gather", "berries")]})
		run(m, 30.0)
		check(bush.amount < 70.0, "a bush against a stockpile at %s gets picked (%.0f left)" % [offset, bush.amount])


func new_game(m):
	var game = load("res://scripts/game/game.gd").new()
	game.m = m
	game.hud = game.Hud.new()
	game.add_child(game.hud)
	game.cmd = game.Commander.new()
	game.terra = game.Terra.new()
	game.add_child(game.terra)
	game.view = game.WorldView.new()
	game.view.ghost = MeshInstance3D.new()
	game.view.add_child(game.view.ghost)
	game.add_child(game.view)
	root.add_child(game)
	return game


func test_construction() -> void:
	var m = new_match(8)
	var game = new_game(m)
	var home: Vector2 = m.home_pos(0)
	var people: Array = m.idle_adults(0, home)
	var a = people[0]
	var b = people[1]
	var c = people[2]
	var say := func(u, text: String):
		game.addressee = {"unit": u.id, "individual": true} if u else {}
		game.address_label = u.name if u else "your people"
		game._on_chat(text)
	var start := func(u, type: String, ids: Array):
		var s := step("build", type)
		s["sites"] = ids
		check(m.command(0, {"units": [u.id], "steps": [s]})["ok"], "%s started" % type)

	var hut = m.bld(m.place_site(0, "hut", open_site(m, "hut", home, 16.0), 0.0)["id"])
	start.call(a, "hut", [hut.id])
	run(m, 1.0)
	for away in ["follow me", "cancel"]:
		say.call(a, away)
		check(not hut.dead and a.task != "build", "'%s' takes builders off without losing the unpaid site" % away)
		for text in ["continue construction", "continue", "finish the hut", "build the hut"]:
			say.call(a, away)
			say.call(a, text)
			check(a.task == "build" and not game.placing and hut.id in m.crew_of(a).state["sites"], "'%s' after '%s' returns to the same site" % [text, away])

	var posts := [home + Vector2(-12, 22), home + Vector2(12, 22)]
	var wall: Array = m.place_wall(0, "palisade", posts)["ids"]
	start.call(b, "palisade", wall)
	m.fac(0).stock["wood"] = 4.0
	run(m, 14.0)
	say.call(b, "follow me")
	check(wall.all(func(id): return m.bld(id) != null and not m.bld(id).dead), "the whole wall line survives its builder leaving")
	say.call(b, "finish the wall")
	var sites: Array = m.crew_of(b).state["sites"]
	check(not game.placing and not sites.is_empty() and sites.all(func(id): return id in wall), "'finish the wall' resumes that line")
	say.call(b, "continue construction")
	check(m.crew_of(b).state["sites"].all(func(id): return id in wall), "people resume their own job before someone else's")

	say.call(c, "help build the hut")
	check(c.task == "build" and hut.id in m.crew_of(c).state["sites"], "another villager can join a site")
	say.call(c, "build a hut")
	check(game.placing, "'build a hut' still starts a new one")
	game._cancel_place()
	check(not hut.dead, "cancelling placement leaves the old site alone")

	game.terra_ctx = {"req": {"unit": a.id, "individual": true}, "who": a.name, "text": "could you carry on with that hut you began", "site": -1}
	game._on_terra({"ok": true, "data": {"kind": "plan", "reply": "", "steps": [step("build", "hut")]}})
	check(not game.placing and a.task == "build", "Terra answering build to a continue order doesn't ask for a site")
	var facts: Array = m.brief(0, "", -1)["unfinished"]
	check(facts.size() == 2, "Terra is told about both unfinished jobs (%d)" % facts.size())

	m.fac(0).stock["wood"] = 500.0
	run(m, 100.0)
	check(hut.complete and wall.all(func(id): return m.bld(id).complete), "resumed construction finishes")
	say.call(a, "continue construction")
	check(not game.placing, "with nothing unfinished, continue doesn't open placement")

	# Sent off to fetch wood and then told to continue: the wood in hand pays for the site.
	var short = m.bld(m.place_site(0, "hut", open_site(m, "hut", home, 16.0), 0.0)["id"])
	m.fac(0).stock["wood"] = float(Defs.BUILDINGS["hut"]["cost"]["wood"]) - 5.0
	c.carry = 5.0
	c.carry_res = "wood"
	say.call(c, "continue construction")
	run(m, 100.0)
	check(short.complete, "builders unload the wood their site is waiting for")
	var spare = m.bld(m.place_site(0, "stockpile", open_site(m, "stockpile", home, 16.0), 0.0)["id"])
	game.chat_site = spare.id
	say.call(null, "cancel")
	check(spare.dead, "an unstarted site in view can still be cleared")
	var rival_site = m.add_building(1, "hut", m.home_pos(1) + Vector2(20, 0), 0.0)
	var theirs = m.idle_adults(1, m.home_pos(1))[0]
	var st := step("build", "hut")
	st["sites"] = [rival_site.id]
	m.command(1, {"units": [theirs.id], "steps": [st]})
	m.cancel(1, {"units": [theirs.id]})
	check(rival_site.dead, "the rival still drops its unstarted sites")
	game.cmd.free()
	game.free()


func test_map_sizes() -> void:
	for id in Defs.MAP_SIZES:
		var m = Match.new()
		m.setup({"seed": 4242, "map": id})
		var size: float = Defs.MAP_SIZES[id]["size"]
		var far := Vector2(size - 1, size - 1)
		check(m.map_size == size, "%s match is %d m across" % [id, size])
		check(m.fac(0).knowledge.size() == m.kres * m.kres and m.kcell(far) == m.kres * m.kres - 1, "%s knowledge covers the map" % id)
		check(m.cell_of(far) == Vector2i(m.grid_n - 1, m.grid_n - 1), "%s path grid covers the map" % id)
		var a: Vector2i = m.nearest_free_cell(0, m.cell_of(m.home_pos(0)))
		var b: Vector2i = m.nearest_free_cell(0, m.cell_of(m.home_pos(1)))
		check(not m.blocking.grid.get_id_path(a, b).is_empty(), "%s camps can reach each other" % id)


func test_rings() -> void:
	var seeds := int(OS.get_environment("MH_MAP_SEEDS")) if OS.get_environment("MH_MAP_SEEDS") != "" else 1
	for count in range(3, Defs.MAX_SETTLEMENTS + 1):
		var id: String = Defs.map_for(count, "small")
		for s in seeds:
			var tr = Terrain.new()
			tr.generate((s + 1) * 977, id, count)
			var label := "%d camps on %s, seed %d" % [count, id, s + 1]
			check(tr.starts.size() == count, label + ": every camp placed")
			var closest := INF
			for a in count:
				check(tr.in_bounds(tr.starts[a], float(tr.config["margin"]) - 1.0), label + ": camp inside margins")
				for b in range(a + 1, count):
					closest = minf(closest, tr.starts[a].distance_to(tr.starts[b]))
			check(closest >= Defs.RING_SPACING, "%s: neighbours %.0f m apart" % [label, closest])
			check(tr.kit.y < closest * 0.5, label + ": each kit is on its own camp's side")
			for p in tr.starts:
				var kinds := {}
				for n in tr.nodes:
					if n.kind == "tree":
						continue
					var d: float = n.pos.distance_to(p)
					if n.kind == "berry" and d < 90.0:
						kinds["berry"] = true
					elif n.kind == "deposit" and d < 230.0:
						kinds[n.sub] = true
					elif n.kind == "rock" and n.sub == "outcrop" and d < 160.0:
						kinds["outcrop"] = true
				for k in ["berry", "bronze_ore", "coal", "iron_ore", "outcrop"]:
					check(kinds.has(k), "%s: %s near camp" % [label, k])


func test_settlements() -> void:
	var m = Match.new()
	m.setup({"seed": 4242, "map": "small", "settlements": 8})
	check(m.factions.size() == 8 and m.terrain.map_id == "huge", "eight settlements move up to the Huge map")
	var names := {}
	for f in m.factions:
		names[f.commander_name] = true
		check(m.commander(f.id) != null and m.home_of(f.id) != null, "faction %d has a commander and a camp" % f.id)
	check(names.size() == 8, "every commander has their own name")
	var from: Vector2i = m.nearest_free_cell(0, m.cell_of(m.home_pos(0)))
	for id in range(1, 8):
		var to: Vector2i = m.nearest_free_cell(id, m.cell_of(m.home_pos(id)))
		var route: Array = m.blocking.route(0, from, to)
		check(not route.is_empty() and route[-1] == to, "camp %d can be reached" % id)
	# Gates open for their owner alone, for every faction.
	for owner_id in 8:
		var gate = m.add_building(owner_id, "palisade_gate", m.home_pos(owner_id) + Vector2(22, 0), 0.0, true)
		var cell := Vector2i(gate.cells[0] % m.grid_n, gate.cells[0] / m.grid_n)
		for who in 8:
			check(m.solid_for(who, cell) == (who != owner_id), "faction %d at faction %d's gate" % [who, owner_id])
		m.remove_building(gate)
		check(not m.solid_for((owner_id + 1) % 8, cell), "faction %d's gate clears when removed" % owner_id)
	var last = m.fac(7)
	m.add_building(7, "hut", m.home_pos(7) + Vector2(0, 20), 0.0, true)
	last.food_cap = 150
	last.stock["food"] = 100.0
	for i in 70:
		m.upkeep(1.0)
	check(last.births > 0, "the eighth settlement has births")
	# Sightings keep rivals apart.
	var spot: Vector2 = m.home_pos(0) + Vector2(30, 0)
	m.spawn_unit(2, "villager", spot)
	m.spawn_unit(5, "villager", spot + Vector2(2, 0))
	m.rebuild_unit_hash()
	m._sight(m.fac(0), spot, 10.0, null)
	var sides := {}
	for e in m.fac(0).intel.values():
		if e["kind"] == "units":
			sides[e["faction"]] = int(e["total"])
	check(sides.size() == 2 and sides.get(2) == 1 and sides.get(5) == 1, "a mixed group is reported by side (%s)" % str(sides))
	check(m.known_camps(0).is_empty(), "no rival camp is known before it has been seen")
	# An army whose target falls comes home, still together.
	var camp = m.home_of(3)
	m.fac(0).intel["b%d" % camp.id] = {"kind": "building", "type": "campfire", "pos": camp.pos, "faction": 3, "t": 0.0}
	var army = m.make_crew(0, m.idle_adults(0, m.home_pos(0)).slice(0, 3))
	var order: Dictionary = m.command(0, {"crew": army.id, "steps": [step("attack", "", 0, "enemy")]})
	check(order.get("ok", false) and army.state.get("foe", -1) == 3, "attacking their camp remembers whose it is")
	m.kill_unit(m.commander(3))
	check(not m.over and not m.fac(3).alive and m.living().size() == 7, "one fallen rival doesn't end the match")
	check(m.buildings_of(3, "", false).is_empty() and m.units.all(func(u): return u.dead or u.faction != 3), "the fallen settlement breaks up")
	check(army.members.size() == 3 and army.steps[0]["action"] == "guard", "the army comes home when its target falls")
	check(m.known_camps(0).is_empty(), "a fallen rival's camp is no longer a target")
	run(m, 1.0)
	check(not m.over, "the match goes on after an elimination")
	for id in [1, 2, 4, 5, 6, 7]:
		m.kill_unit(m.commander(id))
	check(m.over and m.winner == 0, "the last commander standing wins")
	var lost = Match.new()
	lost.setup({"seed": 7, "map": "medium", "settlements": 3})
	lost.kill_unit(lost.commander(0))
	check(lost.over and lost.winner != 0, "the player's death ends the match")


func test_path_queue() -> void:
	var m = Match.new()
	m.setup({"seed": 4242, "settlements": 4, "map": "medium"})
	var askers := []
	for f in m.factions:
		var home: Vector2 = m.home_pos(f.id)
		# A wall between everyone and where they're going, so each needs a real route.
		for i in 7:
			m.add_building(f.id, "stone_wall", home + Vector2(30, (i - 3) * 4.0), PI * 0.5, true)
		for k in 6:
			askers.append(m.spawn_unit(f.id, "villager", home + Vector2(22, k - 3)))
	var served := {}
	var order: Array = []
	for tick in 12:
		m.ticks += 1
		m.paths_this_tick = 0
		m.share_paths()
		for u in askers:
			if served.has(u.id):
				continue
			if not m.route_for(u, m.home_pos(u.faction) + Vector2(40, 0)).is_empty():
				served[u.id] = tick
				order.append(u)
		check(m.paths_this_tick <= m.MAX_PATHS_PER_TICK, "no more routes than the budget in tick %d" % tick)
		if tick == 0:
			var got := [0, 0, 0, 0]
			for u in order:
				got[u.faction] += 1
			check(got.min() >= 1 and got.max() - got.min() <= 1, "every settlement gets an equal share at once (%s)" % str(got))
	check(served.size() == askers.size(), "everyone waiting gets a route (%d of %d)" % [served.size(), askers.size()])
	var last := {}
	var in_order := true
	for u in order:
		if last.get(u.faction, -1) > u.id:
			in_order = false
		last[u.faction] = u.id
	check(in_order, "whoever waited longest goes first")


func test_rivals() -> void:
	var m = Match.new()
	m.setup({"seed": 4242, "settlements": 4, "map": "medium"})
	var target: Vector2 = m._enemy_guess(0)
	check(target.distance_to(m.home_pos(0)) >= Defs.RING_SPACING * 0.8, "scouts look away from home")
	for k in m.kcells_in(target, 30.0):
		m.fac(0).knowledge[k] = 5.0
	check(m._enemy_guess(0).distance_to(target) > 30.0, "scouts move on to ground nobody has seen")
	var ais := []
	for id in range(1, 4):
		var ai = Rival.new()
		ai.setup(m, {"faction": id, "difficulty": 2, "seed": 4242})
		ais.append(ai)
	run(m, 45.0, ais)
	for id in range(1, 4):
		check(not m.crews_of(id).is_empty(), "rival %d put its people to work" % id)
		check(m.fac(id).pop >= Defs.START_VILLAGERS, "rival %d kept its people" % id)
	check(m.crews_of(0).is_empty(), "no AI gives the player's people orders")


func test_menu() -> void:
	var menu = load("res://scripts/ui/main_menu.gd").new()
	root.add_child(menu)
	for k in range(1, Defs.MAX_SETTLEMENTS):
		menu.map_pick.select(0)
		menu.opponents.select(k - 1)
		menu._fit_map()
		var id: String = menu.map_pick.get_selected_metadata()
		check(id == Defs.map_for(k + 1, "small"), "%d opponents move the map up to %s" % [k, id])
		check(not menu.map_pick.is_item_disabled(menu.map_pick.selected), "%d opponents leave the picked map enabled" % k)
	menu.free()


func test_duel() -> void:
	var minutes := float(OS.get_environment("MH_DUEL_MIN")) if OS.get_environment("MH_DUEL_MIN") != "" else 24.0
	var strategies := [["rush", "boom"], ["turtle", "cavalry"], ["cannons", "boom"]]
	var pick: int = int(OS.get_environment("MH_DUEL_PAIR")) if OS.get_environment("MH_DUEL_PAIR") != "" else 0
	var pair: Array = strategies[pick % strategies.size()]
	var m = new_match(4242 + pick, true)
	var ais := []
	for i in 2:
		var ai = Rival.new()
		ai.setup(m, {"faction": i, "difficulty": 1, "strategy": pair[i], "seed": 99 + i})
		ais.append(ai)
	var t0 := Time.get_ticks_msec()
	var report_every := 120.0
	var next_report := report_every
	var peak := [0, 0]
	while m.t < minutes * 60.0 and not m.over:
		run(m, 10.0, ais)
		for f in m.factions:
			peak[f.id] = maxi(peak[f.id], f.pop)
		if m.t >= next_report:
			next_report += report_every
			var line := "  %5.1f min" % (m.t / 60.0)
			for f in m.factions:
				line += " | %s: pop %d, age %s, wood %d, food %d (%s), soldiers %d, kills %d, bld %d" % [ais[f.id].strategy, f.pop,
					Defs.AGES[f.age], int(f.stock["wood"]), int(f.stock["food"]), Defs.FOOD_STATES[f.food_state], f.soldiers, f.kills, m.buildings_of(f.id).size()]
			print(line)
			if OS.get_environment("MH_DUEL_DEBUG") != "":
				for ai in ais:
					var rl := "    %s roles:" % ai.strategy
					for role in ai.roles:
						var c = m.crews.get(ai.roles[role])
						if c:
							rl += " %s=%d:%s" % [role, c.members.size(), (Defs.describe_step(c.steps[c.idx]) if c.idx < c.steps.size() else "idle")]
					rl += " | camp known: %s, idle %d" % [str(m.known_enemy_camp(ai.fid) != null), m.fac(ai.fid).idle]
					print(rl)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("  simulated %.1f min in %.1f s; winner: %s" % [m.t / 60.0, secs, str(m.winner) if m.over else "none yet"])
	for f in m.factions:
		check(peak[f.id] > 15, "%s grew past 15 people (peak %d)" % [ais[f.id].strategy, peak[f.id]])
		check(m.buildings_of(f.id).size() >= 6, "%s built at least 6 structures" % ais[f.id].strategy)
		check(f.age >= 1, "%s reached the Stone age" % ais[f.id].strategy)
	var fought := m.fac(0).kills + m.fac(1).kills
	check(fought > 0 or m.over, "the rivals fought (%d kills)" % fought)
