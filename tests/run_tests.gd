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
const ChatGPTCallback = preload("res://scripts/orders/chatgpt_callback.gd")
const ChatGPTVault = preload("res://scripts/orders/chatgpt_vault.gd")


## Stands in for the first-person controller when a test drives the chat.
class FakeCommander:
	var move_enabled := true
	var look_enabled := true


var failures := 0
var passes := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	var only := OS.get_environment("MH_TEST")
	var tests := ["defs", "validation", "terrain", "map_sizes", "economy", "crews", "selection", "delegation", "walls", "combat", "parser", "schema", "chatgpt", "terra_orders", "duel"]
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
		if s == 1:
			print("  %s: trees %d, nodes %d" % [id, tr.count_nodes("tree"), tr.nodes.size()])


func test_economy() -> void:
	var m = new_match(5)
	var f = m.fac(0)
	check(f.pop == Defs.START_VILLAGERS, "start with six villagers")
	check(f.housing == 8, "campfire houses 8")
	var r: Dictionary = m.command(0, {"steps": [step("gather", "wood", 30, "", 6)]})
	check(r.get("ok", false), "gather order accepted: %s" % r.get("error", ""))
	run(m, 70.0)
	check(float(f.stock["wood"]) >= 20.0, "wood gathered (%.0f)" % float(f.stock["wood"]))
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
	check(f.housing == 13, "housing rose to 13 (%d)" % f.housing)
	check(f.pop > Defs.START_VILLAGERS, "births happened while well fed (%d people)" % f.pop)
	var bad: Dictionary = m.place_site(0, "house", home + Vector2(30, 30), 0.0)
	check(not bad.get("ok", true), "house locked in the Wood age")
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


func chat_game(m):
	var game = load("res://scripts/game/game.gd").new()
	game.m = m
	game.cmd = FakeCommander.new()
	game.hud = game.Hud.new()
	game.add_child(game.hud)
	root.add_child(game)
	return game


func test_delegation() -> void:
	var m = new_match(77)
	var adults: Array = m.idle_adults(0, m.home_pos(0))
	var captain = adults[0]
	var second = adults[1]
	var crew = m.make_crew(0, [captain, second, adults[2]])
	m.command(0, {"crew": crew.id, "steps": [step("promote"), step("gather", "wood")]})
	m.update_crews(0.0)
	var game = chat_game(m)

	# Selecting a captain means talking to their crew.
	game.selected.assign([captain.id])
	game.open_chat()
	check(game.addressee.get("crew", -1) == crew.id, "a selected captain is addressed with their crew")
	game._cycle_chat_address(false)
	check(game.addressee.get("unit", -1) == captain.id and game.addressee.get("individual", false), "Tab still reaches the captain alone")
	game.hud.close_chat()
	game.selected.clear()
	game.addressee = {}

	# A title addresses the captain; it doesn't promote anyone.
	game._on_chat("Captain %s, hold here" % captain.name)
	check(captain.crew == crew.id and crew.steps[crew.idx]["action"] == "hold", "'Captain Name, hold here' orders that captain's crew")
	var titled: Dictionary = Parser.parse("Captain Hal, take ten spearmen and hold the ford")
	check(not titled["ok"], "an order the parser can't represent is left to Terra")
	check(not titled["steps"].any(func(s): return s["action"] == "promote"), "a captain's title is not a promotion")
	for phrase in ["promote", "make Hal a captain", "you are captain now", "become captain"]:
		var p: Dictionary = Parser.parse(phrase)
		check(p["ok"] and p["steps"][0]["action"] == "promote", "'%s' still promotes" % phrase)
	check(not Parser.parse("hold the ford")["ok"], "an unknown place is not read as 'here'")
	check(Parser.parse("hold the line")["ok"] and Parser.parse("guard the camp")["ok"], "known phrases still parse locally")
	check(Parser.parse("fall back")["all"], "fall back with nobody addressed means everyone")
	for phrase in ["send a scout east then come back", "gather 30 wood then come home", "bring the horses back to camp"]:
		check(not Parser.parse(phrase)["all"], "'%s' isn't an order to everyone" % phrase)
	for phrase in ["don't fall back", "never retreat", "do not retreat"]:
		var p: Dictionary = Parser.parse(phrase)
		check(not p["steps"].any(func(s): return s["action"] == "recall"), "'%s' doesn't recall anyone" % phrase)
	for phrase in ["hold them off", "hold until the enemy comes", "stay there"]:
		check(Parser.parse(phrase)["steps"][0]["where"] == "", "'%s' holds the crew's own ground" % phrase)

	# Succession.
	m.kill_unit(captain)
	check(crew.leader == second.id and crew.captain and second.captain, "the longest-serving member succeeds a dead captain")
	check(m.messages.any(func(msg): return msg["kind"] == "alarm" and msg["text"].contains(second.name)), "you are told who took over")

	# Names stay unique and speakable past the end of the list.
	var people := []
	var names := {}
	for i in 260:
		var u = m.spawn_unit(0, "villager", m.home_pos(0))
		u.name = m.pick_name(m.fac(0))
		names[u.name] = true
		people.append(u)
	check(names.size() == people.size(), "260 people have 260 names")
	check(not people.any(func(u): return u.name.right(1).is_valid_int()), "nobody is called 'Hal 2'")
	check(not names.has("Rook"), "none of your people share the rival commander's name")
	var surnamed: Array = people.filter(func(u): return u.name.contains(" "))
	if not surnamed.is_empty():
		var target = surnamed[0]
		game._on_chat("@%s gather wood" % target.name)
		check(target.task == "gather", "@ reaches '%s', not their namesake" % target.name)

	var twins := []
	for byname in ["Reed", "Moss"]:
		var u = m.spawn_unit(0, "villager", m.home_pos(0))
		u.name = "Zed " + byname
		twins.append(u)
	for phrase in ["Zed, gather stone", "tell zed to gather stone"]:
		game._on_chat(phrase)
		var answer: String = game.hud.log_lines[-1]["node"].get_parsed_text()
		check(answer.contains("Which one") and twins.all(func(u): return u.task == "idle"), "'%s' asks which Zed" % phrase)

	# Alarms survive a busy log.
	game.hud.log_line("Alarm at the watch post!", "alarm")
	var alarm: RichTextLabel = game.hud.log_lines[-1]["node"]
	for i in 45:
		game.hud.log_line("Routine %d" % i, "birth")
	check(is_instance_valid(alarm) and not alarm.is_queued_for_deletion() and alarm.visible, "routine lines never push an alarm out")
	check(game.has_method("_show_messages"), "routine messages are rolled up")
	if game.has_method("_show_messages"):
		m.messages.clear()
		for i in 20:
			m.post(0, "A child is born: %d." % i, "birth")
			m.t += 1.0
			game._show_messages()
		var shown: Array = game.hud.log_lines.filter(func(e): return e["node"].get_parsed_text().begins_with("A child is born"))
		check(shown.size() == 1, "twenty births in twenty seconds make one line (%d)" % shown.size())
		m.t += 31.0
		game._show_messages()
		check(game.hud.log_lines[-1]["node"].get_parsed_text().contains("19"), "the rest arrive as one summary")
	game.free()


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
		check(m.grids[1].is_point_solid(c), "palisade blocks the enemy")


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
		e.weapon = "club"
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
	r = P.parse("arm 6 with spears and guard the camp")
	check(r.get("ok", false) and r["steps"][0]["subject"] == "wood_spear" and r["steps"][0]["count"] == 6, "arm with spears")
	r = P.parse("what should we do about the weather in spain")
	check(not r.get("ok", false), "nonsense is not parsed")
	r = P.parse("build a stone wall")
	check(r.get("ok", false) and r["steps"][0]["subject"] == "stone_wall", "stone wall")
	r = P.parse("smelt bronze")
	check(r.get("ok", false) and r["steps"][0]["action"] == "smelt", "smelt bronze")
	r = P.parse("attack their camp")
	check(r.get("ok", false) and r["steps"][0]["action"] == "attack" and r["steps"][0]["where"] == "enemy", "attack their camp")


func test_schema() -> void:
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
		check(not m.grids[0].get_id_path(a, b).is_empty(), "%s camps can reach each other" % id)


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
