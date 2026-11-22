extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd
## Set MH_TEST=<name> to run a single test, MH_DUEL_MIN=<minutes> to change the duel length.
## MH_TEST=absence (not in the default run) leaves captains alone for 15 minutes. MH_SEED picks the map.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Match = preload("res://scripts/sim/match.gd")
const Rival = preload("res://scripts/ai/rival.gd")
const Parser = preload("res://scripts/orders/parser.gd")
const Schema = preload("res://scripts/orders/schema.gd")
const Planner = preload("res://scripts/ai/planner.gd")
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
	var tests := ["defs", "validation", "terrain", "map_sizes", "economy", "crews", "selection", "delegation", "posts", "post_orders", "places", "mandate_building", "walls", "combat", "parser", "schema", "chatgpt", "terra_orders", "duel"]
	if only == "absence":
		tests.append(only)
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


func grown_village(m, size: int) -> Array:
	var home: Vector2 = m.home_pos(0)
	while m.idle_adults(0, home).size() < size:
		var u = m.spawn_unit(0, "villager", home + Vector2.from_angle(m.units.size() * 0.7) * 9.0)
		u.name = m.pick_name(m.fac(0))
	m.fac(0).stock["food"] = 140.0
	m._refresh_counts(m.fac(0))
	return m.idle_adults(0, home)


func test_posts() -> void:
	if not "mandate" in Defs.ACTIONS:
		check(false, "captains can be given a mandate")
		return
	var m = new_match(414)
	var home: Vector2 = m.home_pos(0)
	var adults: Array = grown_village(m, 30)
	var steward = adults[0]
	var r: Dictionary = m.command(0, {"unit": steward.id, "individual": true, "steps": [step("mandate", "village")]})
	check(r["ok"], "a village mandate is accepted: %s" % r.get("error", ""))
	if not r["ok"]:
		return
	var village = m.posts[r["post"]]
	check(village.captain == steward.id and steward.captain and village.center.distance_to(home) < 1.0, "the village captain runs the main camp")

	# The steward takes everyone free and gives them work.
	run(m, 8.0)
	check(adults.all(func(u): return u.post == village.id), "the village absorbs every idle adult")
	var jobs := {}
	var idle := 0
	for u in adults:
		var c = m.crew_of(u)
		if c and c.idx < c.steps.size():
			jobs[c.steps[c.idx]["subject"]] = true
		elif u != steward:
			idle += 1
	check(jobs.has("wood") and jobs.has("berries"), "they gather food and wood without being told (%s)" % str(jobs.keys()))
	check(idle <= 3, "almost nobody is left idle (%d)" % idle)
	var child = m.spawn_unit(0, "villager", home + Vector2(5, 0))
	child.child = true
	child.born = m.t - Defs.MATURE_TIME
	run(m, 6.0)
	check(not child.child and child.post == village.id and child.crew >= 0, "someone who grows up gets a job by themselves")

	# A second post far away draws its people from the village.
	var far: Vector2 = home + (Vector2(m.map_size, m.map_size) * 0.5 - home).normalized() * 180.0
	m.set_mark(0, far)
	var warden = adults[1]
	r = m.command(0, {"unit": warden.id, "individual": true, "steps": [step("mandate", "garrison", 0, "marked", 8)]})
	check(r["ok"], "a remote garrison is accepted: %s" % r.get("error", ""))
	if not r["ok"]:
		return
	var garrison = m.posts[r["post"]]
	check(garrison.center.distance_to(far) < 1.0 and garrison.target == 8, "a mandate has a place and a size")
	run(m, 100.0)
	var there: Array = m.post_members(garrison)
	check(there.size() == 8, "the village staffs other posts to their size (%d of 8)" % there.size())
	var arrived: Array = there.filter(func(u): return u.pos.distance_to(far) < garrison.radius)
	check(arrived.size() == there.size(), "they live at their post, not at the campfire (%d of %d there)" % [arrived.size(), there.size()])
	check(m.resting_place(warden).distance_to(far) < 1.0, "idle, fleeing and wounded people make for their post")

	# A direct order always wins, then they go back to their post's work.
	var picked: Array = m.post_members(village).filter(func(u): return u != steward).slice(0, 3)
	var ids: Array = picked.map(func(u): return u.id)
	r = m.command(0, {"units": ids, "steps": [step("hold")]})
	check(r["ok"], "a captain's people still take direct orders")
	run(m, 20.0)
	check(picked.all(func(u): return u.task == "hold"), "captains never undo a direct order")
	m.cancel(0, {"units": ids})
	run(m, 6.0)
	check(picked.all(func(u): return u.task != "hold" and u.crew >= 0), "released people go back to the post's work")

	# Succession keeps the mandate.
	m.kill_unit(warden)
	run(m, 2.0)
	var heir = m.unit(garrison.captain)
	check(m.posts.has(garrison.id) and heir != null and not heir.dead and heir.captain and heir.post == garrison.id, "a fallen captain's post passes to one of its people")
	check(garrison.mandate == "garrison" and garrison.center.distance_to(far) < 1.0, "the successor keeps the mandate")

	# The last bush doesn't get the whole village.
	var bare = new_match(414)
	var camp: Vector2 = bare.home_pos(0)
	var kept := false
	for n in bare.terrain.nodes:
		if n.kind == "berry" and n.pos.distance_to(camp) < 200.0:
			if kept:
				n.amount = 0.0
			kept = true
	var few: Array = grown_village(bare, 30)
	bare.command(0, {"unit": few[0].id, "individual": true, "steps": [step("mandate", "village")]})
	run(bare, 8.0)
	var pickers: int = few.filter(func(u):
		var c = bare.crew_of(u)
		return c != null and c.idx < c.steps.size() and c.steps[c.idx]["subject"] == "berries").size()
	check(pickers <= 4, "pickers are capped by the bushes left (%d on one bush)" % pickers)

	# Nobody is governed without a mandate.
	var untouched = new_match(414)
	grown_village(untouched, 12)
	run(untouched, 8.0)
	check(untouched.crews_of(0).is_empty() and untouched.posts.is_empty(), "without a mandate nobody is ordered about")


func test_post_orders() -> void:
	for pair in [["run the village", "village"], ["look after the farms", "farming"], ["take twenty and run a mine here", "industry"],
			["set up a garrison at the mark", "garrison"], ["raise an army", "army"]]:
		var p: Dictionary = Parser.parse(pair[0])
		check(p["ok"] and p["steps"][0]["action"] == "mandate" and p["steps"][0]["subject"] == pair[1], "'%s' is a mandate" % pair[0])
	var mine: Dictionary = Parser.parse("take twenty and run a mine here")
	check(mine["ok"] and mine["steps"][0]["count"] == 20 and mine["steps"][0]["where"] == "here", "a mandate takes a size and a place")
	for phrase in ["run back to camp", "build a farm", "don't run the village", "set up a farm"]:
		check(not Parser.parse(phrase)["steps"].any(func(s): return s["action"] == "mandate"), "'%s' is not a mandate" % phrase)

	var m = new_match(77)
	var adults: Array = grown_village(m, 24)
	var game = chat_game(m)
	var steward = adults[0]
	game._on_chat("%s, run the village" % steward.name)
	var village = m.village_post(0)
	check(village != null and village.captain == steward.id, "'Name, run the village' gives the mandate")
	if village == null:
		game.free()
		return
	run(m, 6.0)
	game.selected.assign([steward.id])
	game.open_chat()
	check(game.addressee.get("post", -1) == village.id, "talking to a captain addresses their post")
	game.hud.close_chat()
	game.selected.clear()
	game.addressee = {}
	game._on_chat("Captain %s, send two scouts east" % steward.name)
	var scouts: Array = m.post_members(village).filter(func(u): return u.task == "scout")
	check(scouts.size() == 2 and steward.task != "scout", "an order to a captain is carried out by that many of their people (%d)" % scouts.size())
	run(m, 3.0)
	check(scouts.all(func(u): return u.task == "scout"), "and the captain leaves them to it")
	var gatherer = null
	for u in m.post_members(village):
		var c = m.crew_of(u)
		if c and c.post == village.id and c.leader != u.id:
			gatherer = u
			break
	check(gatherer != null, "the village has job crews")
	if gatherer:
		game._on_chat("%s, take twenty and run a mine here" % gatherer.name)
		var works: Array = m.posts.values().filter(func(p): return p.mandate == "industry")
		check(works.size() == 1 and works[0].captain == gatherer.id, "the person named takes charge, not their crew's leader")
		check(works.size() == 1 and works[0].members.size() == 1 and works[0].target == 20, "they bring only themselves, and the size sticks")
	game.selected.assign([m.post_members(village)[-1].id])
	game.open_chat()
	game.hud.close_chat()
	game._on_chat("take twelve and set up a garrison here")
	var forts: Array = m.posts.values().filter(func(p): return p.mandate == "garrison")
	check(forts.size() == 1 and forts[0].target == 12, "a size given to a selected person sticks")
	game.selected.clear()
	game.addressee = {}
	game._menu_people()
	check(not game.menu_items.is_empty() and game.menu_items[0].get("post", -1) == village.id, "/p lists captains first")
	var facts: Dictionary = m.brief(0, "your people", -1)
	check(facts.get("posts", []).size() == m.posts.size(), "Terra is told about the posts")
	game.free()


func test_places() -> void:
	var m = new_match(77)
	if not m.has_method("places_of"):
		check(false, "places can be named")
		return
	var adults: Array = grown_village(m, 12)
	var game = chat_game(m)
	var home: Vector2 = m.home_pos(0)
	var hill: Vector2 = home + (Vector2(m.map_size, m.map_size) * 0.5 - home).normalized() * 110.0
	m.set_mark(0, hill)
	game._on_chat("call this East Hill")
	var places: Dictionary = m.places_of(0)
	check(places.has("east hill") and places["east hill"]["pos"].distance_to(hill) < 1.0, "a place just marked gets the name")
	m.t += 200.0
	game._on_chat("call this Home Ford")
	places = m.places_of(0)
	check(places.has("home ford") and places["home ford"]["pos"].distance_to(m.commander(0).pos) < 1.0, "with no fresh mark, 'this' is where you stand")
	for word in ["off", "wood", "Stone Wall", "north", "home", "farms", "attack"]:
		game._on_chat("call this %s" % word)
		check(not m.places_of(0).has(word.to_lower()), "a place can't be called '%s'" % word)
	game._on_chat("%s, hold East Hill" % adults[0].name)
	var c = m.crew_of(adults[0])
	check(c != null and c.steps[c.idx]["action"] == "hold" and c.state["target"].distance_to(hill) < 1.0, "orders can name a place")
	game._on_chat("%s, gather wood at East Hill" % adults[1].name)
	c = m.crew_of(adults[1])
	check(c != null and c.steps[c.idx]["subject"] == "wood" and c.state["origin"].distance_to(hill) < 1.0, "work can happen at a named place")
	game._on_chat("%s, set up a garrison at East Hill" % adults[2].name)
	var held = m.post_of(adults[2])
	check(held != null and held.center.distance_to(hill) < 1.0 and held.name == "East Hill", "a post takes its place's name")
	check(not Parser.parse("hold East Hill")["steps"].any(func(s): return s["where"].begins_with("place:")), "only known places are recognized")
	var r: Dictionary = m.command(0, {"unit": adults[3].id, "steps": [step("hold", "", 0, "place:nowhere")]})
	check(not r["ok"], "an unknown place is refused")
	var facts: Dictionary = m.brief(0, "your people", -1)
	check(facts.get("places", {}).has("place:east hill"), "Terra is told the places")
	var wheres: Array = Schema.plan_schema(facts.get("places", {}).keys())["properties"]["steps"]["items"]["properties"]["where"]["enum"]
	check("place:east hill" in wheres and "marked" in wheres, "Terra may answer with a named place")
	check(Defs.describe_step(step("guard", "", 0, "place:east hill")) == "guard East Hill", "places read as names")
	game.free()


func sites_of(m, type: String) -> Array:
	return m.buildings_of(0, type, false)


func test_mandate_building() -> void:
	if not "reserve" in Defs.ACTIONS:
		check(false, "captains build within their mandate")
		return
	# A village captain builds what the village needs, unasked.
	var m = new_match(414)
	var f = m.fac(0)
	var home: Vector2 = m.home_pos(0)
	var adults: Array = grown_village(m, 30)
	f.stock["wood"] = 300.0
	m.command(0, {"unit": adults[0].id, "individual": true, "steps": [step("mandate", "village")]})
	var village = m.village_post(0)
	run(m, 280.0)
	check(not sites_of(m, "farm").is_empty(), "the village captain builds farms")
	check(not sites_of(m, "hut").is_empty() or not sites_of(m, "house").is_empty(), "and housing")
	check(not sites_of(m, "quarry").is_empty(), "and finds the outcrop for a quarry")
	var strays: Array = m.buildings_of(0, "", false).filter(func(b):
		return b.type != "campfire" and (not b.type in Defs.MANDATES["village"]["builds"] or b.pos.distance_to(village.center) > village.radius + 0.1))
	check(strays.is_empty(), "never outside the mandate or the area (%d)" % strays.size())
	var cramped := 0
	var built: Array = m.buildings_of(0, "", false).filter(func(b): return not Defs.BUILDINGS[b.type].get("wall", false))
	for i in built.size():
		for j in range(i + 1, built.size()):
			if m._obb_overlap(built[i].pos, built[i].rot, built[i].size, built[j].pos, built[j].rot, built[j].size, 2.0):
				cramped += 1
	check(cramped == 0, "there is room to walk between what captains build (%d cramped)" % cramped)

	# Reserve and "don't build".
	var kept = new_match(414)
	var hands: Array = grown_village(kept, 30)
	kept.fac(0).stock["wood"] = 100.0
	var r: Dictionary = kept.command(0, {"unit": hands[0].id, "individual": true, "steps": [step("mandate", "village"), step("reserve", "wood", 100), step("forbid", "farm")]})
	check(r["ok"], "a mandate can come with limits: %s" % r.get("error", ""))
	var lowest := INF
	for i in 120:
		run(kept, 1.0)
		lowest = minf(lowest, float(kept.fac(0).stock["wood"]))
	check(lowest >= 100.0, "captains never spend into the reserve (%.0f wood left)" % lowest)
	check(sites_of(kept, "farm").is_empty(), "captains don't build what you forbade")

	# Only ground this side knows.
	var blind = new_match(414)
	var dep = Planner.find_deposit(blind, 0, "bronze_ore", blind.home_pos(0), 330.0, false)
	check(dep != null and Planner.find_deposit(blind, 0, "bronze_ore", blind.home_pos(0), 330.0, true) == null, "unseen deposits don't exist for captains")
	var rng := RandomNumberGenerator.new()
	check(Planner.find_site(blind, 0, "hut", dep.pos, Vector2.RIGHT, rng, true, "", 60.0) == null, "nor does unseen ground")

	# Industry mines what it has seen.
	var works = new_match(414)
	var miners: Array = grown_village(works, 12)
	var wf = works.fac(0)
	wf.age = 1
	wf.stock["wood"] = 200.0
	wf.stock["stone"] = 100.0
	var ore = Planner.find_deposit(works, 0, "bronze_ore", works.home_pos(0), 330.0, false)
	for i in miners.size():
		miners[i].pos = ore.pos + Vector2.from_angle(i * 0.9) * 14.0
	works.set_mark(0, ore.pos + Vector2(12, 0))
	works.command(0, {"unit": miners[0].id, "individual": true, "steps": [step("mandate", "industry", 0, "marked", 10)]})
	run(works, 20.0)
	check(not sites_of(works, "mine").is_empty(), "an industry captain sites the mine")

	# With every mine manned, the smelter still gets its share.
	var forge = new_match(414)
	var smiths: Array = grown_village(forge, 8)
	var ff = forge.fac(0)
	ff.age = 1
	ff.stock["bronze_ore"] = 40.0
	ff.stock["coal"] = 40.0
	var camp_at: Vector2 = forge.home_pos(0)
	for res in Defs.DEPOSITS:
		var node = Planner.find_deposit(forge, 0, res, camp_at, 330.0, false)
		var pit = forge.add_building(0, "mine", node.pos + Vector2(7, 0), 0.0, true)
		pit.node = node.id
		pit.deposit = res
	forge.add_building(0, "smelter", camp_at + Vector2(25, 0), 0.0, true)
	forge.command(0, {"unit": smiths[0].id, "individual": true, "steps": [step("mandate", "industry", 0, "home", 7)]})
	run(forge, 4.0)
	check(smiths.any(func(u): return u.task == "smelt"), "the smelter gets workers while the mines are manned")
	check(forge.posts_of(0)[0].name == "works", "works at home are just 'works' (%s)" % forge.posts_of(0)[0].name)

	# A crowded village builds further out.
	var full = new_match(414)
	var mid: Vector2 = full.home_pos(0)
	for ring in [20.0, 34.0, 48.0, 62.0, 74.0]:
		var count := int(TAU * ring / 15.0)
		for k in count:
			full.add_building(0, "stockpile", mid + Vector2.from_angle(k * TAU / count) * ring, 0.0, true)
	full.fac(0).knowledge.fill(0.0)
	var pick := RandomNumberGenerator.new()
	pick.seed = 5
	check(Planner.find_site(full, 0, "farm", mid, Vector2.RIGHT, pick, true, "", 152.0) != null, "captains build further out once the middle is full")

	# A garrison walls itself in and leaves a way home.
	var fort = new_match(414)
	var guards: Array = grown_village(fort, 14)
	fort.fac(0).stock["wood"] = 500.0
	var base: Vector2 = fort.home_pos(0) + (Vector2(fort.map_size, fort.map_size) * 0.5 - fort.home_pos(0)).normalized() * 80.0
	for i in guards.size():
		guards[i].pos = base + Vector2.from_angle(i * 0.5) * 10.0
	fort.set_mark(0, base)
	fort.command(0, {"unit": guards[0].id, "individual": true, "steps": [step("mandate", "garrison", 0, "marked", 12)]})
	run(fort, 90.0)
	check(not sites_of(fort, "palisade").is_empty() and not sites_of(fort, "palisade_gate").is_empty(), "a garrison raises a palisade with a gate")
	var from: Vector2i = fort.nearest_free_cell(0, fort.cell_of(base))
	var to: Vector2i = fort.nearest_free_cell(0, fort.cell_of(fort.home_pos(0)))
	check(not fort.grids[0].get_id_path(from, to).is_empty(), "and its people can still walk home")

	# Told to build, a captain picks the site.
	var told = new_match(77)
	var crowd: Array = grown_village(told, 16)
	told.command(0, {"unit": crowd[0].id, "individual": true, "steps": [step("mandate", "village")]})
	run(told, 2.0)
	told.fac(0).stock["wood"] = 80.0
	var game = chat_game(told)
	game._on_chat("Captain %s, build a watch post" % crowd[0].name)
	var posted: Array = sites_of(told, "watch_post")
	check(not game.placing and posted.size() == 1, "a build order to a captain skips placement")
	if posted.size() == 1:
		check(crowd.any(func(u): return u.task == "build"), "and their people start on it")
	var refused: Dictionary = told.command(0, {"post": told.village_post(0).id, "steps": [step("build", "university")]})
	check(not refused["ok"], "a captain won't build outside the mandate")
	for pair in [["keep 100 wood back", "reserve"], ["don't build any farms", "forbid"], ["you can build farms again", "allow"], ["stand your ground", "posture"], ["fall back if outnumbered", "posture"]]:
		var p: Dictionary = Parser.parse(pair[0])
		check(p["ok"] and p["steps"][0]["action"] == pair[1], "'%s' sets a limit" % pair[0])
	var both: Dictionary = Parser.parse("run the village. keep us well fed and keep 100 wood back")
	check(both["ok"] and both["steps"].size() == 2 and both["steps"][0]["count"] == 0 and both["steps"][1]["amount"] == 100, "the plan's example order parses")
	game.free()


## An established village of 30, three mandates, then no orders for 15 minutes with the commander 400 m away.
func test_absence() -> void:
	var seed_in := int(OS.get_environment("MH_SEED")) if OS.get_environment("MH_SEED") != "" else 4242
	var minutes := float(OS.get_environment("MH_MINUTES")) if OS.get_environment("MH_MINUTES") != "" else 15.0
	var m = new_match(seed_in)
	var f = m.fac(0)
	var home: Vector2 = m.home_pos(0)
	var adults: Array = grown_village(m, 30)
	# What a village of 30 already has: roofs and some timber.
	var huts := 0
	for k in 300:
		if huts >= 6:
			break
		var p: Vector2 = home + Vector2.from_angle(k * 2.4) * (14.0 + k * 0.12)
		if Planner._leaves_lane(m, 0, "hut", p, 0.0) and m.site_problem(0, "hut", p, 0.0) == "":
			m.add_building(0, "hut", p, 0.0, true)
			huts += 1
	f.stock["wood"] = 150.0
	m._refresh_counts(f)
	m.command(0, {"unit": adults[0].id, "individual": true, "steps": [step("mandate", "village")]})
	m.command(0, {"unit": adults[1].id, "individual": true, "steps": [step("mandate", "industry", 0, "home", 7)]})
	var toward: Vector2 = (Vector2(m.map_size, m.map_size) * 0.5 - home).normalized()
	var front := home + toward * 120.0
	m.set_mark(0, front)
	m.command(0, {"unit": adults[2].id, "individual": true, "steps": [step("mandate", "garrison", 0, "marked", 6)]})
	var garrison = m.post_of(adults[2])
	var away := Vector2.ZERO
	for k in 16:
		var p: Vector2 = home + Vector2.from_angle(toward.angle() + PI * 0.5 + k * TAU / 16.0) * 400.0
		if m.terrain.in_bounds(p, 30.0) and p.distance_to(m.home_pos(1)) > 120.0:
			away = p
			break
	check(away != Vector2.ZERO, "there's somewhere 400 m away to stand")

	var idle_since := {}
	var where := {}
	var idle_share := 0.0
	var samples := 0
	var starved := 0
	var stranded := 0
	var peak: int = f.pop
	var next_report := 60.0
	while m.t < minutes * 60.0 and not m.over:
		m.set_commander(0, away, 0.0, 0)
		run(m, 2.0)
		m.messages.clear()
		peak = maxi(peak, f.pop)
		if f.food_state == 0:
			starved += 1
		var standing := 0
		var grown := 0
		var causes := {}
		for u in m.units:
			if u.dead or u.faction != 0 or u.kind != "villager" or u.child or m.leads_post(u):
				continue
			grown += 1
			# Idle also means on a job but standing still with nothing to do.
			var c = m.crew_of(u)
			var waiting: bool = c == null or (u.task in ["gather", "build", "craft", "smelt", "upgrade"] and u.anim == 0 and u.pos.distance_to(where.get(u.id, Vector2.ZERO)) < 0.1)
			where[u.id] = u.pos
			if not waiting:
				idle_since.erase(u.id)
				continue
			if not idle_since.has(u.id):
				idle_since[u.id] = m.t
			if m.t - float(idle_since[u.id]) > 30.0:
				standing += 1
				var why: String = u.task if c == null or c.idx >= c.steps.size() else "%s %s" % [c.steps[c.idx]["action"], c.steps[c.idx]["subject"]]
				causes[why] = int(causes.get(why, 0)) + 1
		if m.t > 30.0:
			idle_share += float(standing) / maxi(1, grown)
			samples += 1
		if m.t >= next_report:
			next_report += 60.0
			var built := {}
			for b in m.buildings_of(0):
				built[b.type] = int(built.get(b.type, 0)) + 1
			print("  %4.1f min | pop %d/%d age %d | food %d/%d (%s) wood %d stone %d | idle %d %s | %s" % [m.t / 60.0, f.pop, f.housing, f.age,
				int(f.stock["food"]), f.food_cap, Defs.FOOD_STATES[f.food_state], int(f.stock["wood"]), int(f.stock["stone"]), standing, str(causes), str(built)])
			for p in m.posts_of(0):
				print("      %s %s" % [m.post_status(p), str(p.blocked)])
	var idle_avg := idle_share / maxi(1, samples)
	print("  seed %d: peak %d, idle over 30 s %.1f%%, starving samples %d, deaths %d" % [seed_in, peak, idle_avg * 100.0, starved, f.deaths])
	check(peak >= 100, "population reaches 100 (%d)" % peak)
	check(idle_avg < 0.10, "under 10%% idle for over 30 s (%.1f%%)" % (idle_avg * 100.0))
	check(starved == 0, "nobody starves")
	var kept: Array = m.post_members(garrison).filter(func(u): return not m.under_direct_order(u) and u.task in ["guard", "idle"] and not u.child)
	stranded = kept.filter(func(u): return u.pos.distance_to(garrison.center) > garrison.radius).size()
	check(m.posts.has(garrison.id) and garrison.members.size() >= garrison.target and stranded <= 1, "the remote post is still staffed at its post (%d, %d away)" % [garrison.members.size(), stranded])


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
