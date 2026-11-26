extends Node
## Release walkthrough. Uses fresh match state, construction sites and player orders.
## Run tests/play_match.tscn with -- standard or grand_army.
## Pass game rivals to drive the release UI and the rival strategy in an isolated QA profile.
const Match = preload("res://scripts/sim/match.gd")
const Parser = preload("res://scripts/orders/parser.gd")
const Planner = preload("res://scripts/ai/planner.gd")
const Defs = preload("res://scripts/data/defs.gd")
var m = Match.new()
var game
var live_rivals := false
var rival_engines := {}
var home: Vector2
var workers := []
var failed := false


func _ready() -> void:
	walkthrough.call_deferred()


func order(ids: Array, text: String) -> bool:
	if game:
		game.addressee = {} if ids.is_empty() else {"units": ids}
		game.last_order_result = {}
		game._on_chat(text)
		return game.last_order_result.get("ok", false) or fail("chat order rejected: " + text + " " + str(game.last_order_result))
	var plan: Dictionary = Parser.parse(text)
	if not plan.ok:
		return fail("Parser rejected " + text)
	var request := {"steps": m.resolve_steps(0, plan.steps)}
	if not ids.is_empty():
		request["units"] = ids
	var result: Dictionary = m.command(0, request)
	if not result.ok:
		return fail(text + ": " + str(result.error))
	return true


func fail(reason: String) -> bool:
	failed = true
	printerr("FAIL at %.1fs: %s" % [m.t, reason])
	return false


func until(condition: Callable, seconds: int, action: String) -> bool:
	for i in int(seconds / Defs.TICK):
		if condition.call():
			return true
		if m.over:
			break
		if i > 0 and i % 1200 == 0 and action.begins_with("cannon"):
			var gun = m.units.filter(func(u): return u.faction == 0 and u.kind == "cannon")[0]
			print("Cannon at ", gun.pos, ", ", gun.crew_ids.size(), " operators, target distance ", roundi(gun.pos.distance_to(m.commander(1).pos)))
		m.tick(Defs.TICK)
		if live_rivals:
			game.run_rivals(Defs.TICK)
			if m.options.mode == "grand_army" and m.ticks % 20 == 0 and rival_engines.size() < 2:
				for engine in m.units:
					if engine.faction == 1 and engine.kind in ["ram", "cannon"] and engine.crew_ids.size() == Defs.ITEMS[engine.kind].crew:
						rival_engines[engine.kind] = true
		m.events.clear()
	return condition.call() or fail("%s; stores %s" % [action, m.fac(0).stock])


func afford(cost: Dictionary) -> bool:
	for resource in cost:
		if m.fac(0).stock[resource] >= cost[resource]:
			continue
		if resource != "food" and not order(workers, "gather " + resource):
			return false
		if not until(func(): return m.fac(0).stock[resource] >= cost[resource], 3600, "earn " + resource):
			return false
	return true


func pick(command: String, slot: String) -> bool:
	var ev := InputEventKey.new()
	ev.keycode = {"b": KEY_B, "c": KEY_C, "r": KEY_R}[command]
	ev.pressed = true
	game._unhandled_input(ev)
	if not game.hud.chat_open or not game.hud.picker.visible:
		return fail("missing %s grid (chat %s, menu %s, ready %s, %d ms since start)" % [command, game.hud.chat_open, game.hud.menu_open, game.ready_done, Time.get_ticks_msec() - game.start_ms])
	if command != "b" and not game.addressee.is_empty():
		return fail(command + " unexpectedly needed a villager")
	var key = Defs.HOTKEYS[command][command]["keys"].find_key(slot)
	game.last_order_result = {}
	game._on_picker_key(key)
	if command == "b":
		return game.placing or fail("grid did not start placement")
	return game.last_order_result.get("ok", false) or fail("grid rejected " + slot)


func build(kind: String, deposit: String = ""):
	if not afford(Defs.BUILDINGS[kind].cost):
		return null
	var site = Planner.find_site(m, 0, kind, home, Vector2.RIGHT, m.rng, false, deposit)
	if not site:
		fail("no site for " + kind)
		return null
	var b
	if game:
		game.selected.assign(workers)
		if not pick("b", "build:" + kind):
			return null
		game.place_pos = site[0]
		game.place_rot = site[1]
		game.place_ok = true
		game._place_click()
		if not game.last_order_result.get("ok", false):
			fail("placing " + kind + " with selected builders")
			return null
		b = m.buildings_of(0, kind, false).back()
	else:
		var result: Dictionary = m.place_site(0, kind, site[0], site[1])
		if not result.ok:
			fail(result.error)
			return null
		b = m.bld(result.id)
		var crew: Dictionary = m.command(0, {"units": workers, "steps": [{"action": "build", "subject": kind, "sites": [b.id]}]})
		if not crew.ok:
			fail("selected builders rejected " + kind)
			return null
	if not until(func(): return b.complete, 450, "build " + kind):
		fail("construction failed for " + kind)
		return null
	print("Built ", kind, " ", deposit, " at ", int(m.t), "s")
	return b


func research(tech: String) -> bool:
	return afford(Defs.RESEARCH[tech].cost) and (pick("r", "research:" + tech) if game else order([], "research " + tech.replace("_", " "))) and until(func(): return m.fac(0).researched.has(tech), 160, tech)


func found_town() -> bool:
	var adults: Array = m.idle_adults(0, home).map(func(u): return u.id)
	workers = adults.slice(2)
	if not order(adults.slice(0, 2), "pick berries") or not build("farm") or not order(adults.slice(0, 2), "work the farms"):
		return false
	if not build("farm") or not build("hut"):
		return false
	if not until(func(): return m.idle_adults(0, home).filter(func(u): return not u.id in adults).size() >= 2, 900, "grow two more farmers"):
		return false
	var farmers: Array = m.idle_adults(0, home).filter(func(u): return not u.id in adults).slice(0, 2)
	if not order(farmers.map(func(u): return u.id), "work the farms"):
		return false
	if not build("quarry") or not build("armory") or not build("mine", "bronze"):
		return false
	if not afford({"bronze": 1}) or not research("armory_bronze") or not research("iron_mining"):
		return false
	if not build("mine", "iron") or not research("armory_iron") or not build("university"):
		return false
	return research("gunpowder")


func walkthrough() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "grand_army" if "grand_army" in args else "standard"
	if "game" in args:
		var settings = get_tree().root.get_node("Settings")
		if not OS.get_user_data_dir().get_file().begins_with("MarchHold-QA"):
			fail("Use a separate MarchHold-QA custom user directory for the exported match")
			get_tree().quit(1)
			return
		settings.data["terra_provider"] = settings.TERRA_OFF
		settings.data["intro_seen"] = true
		live_rivals = "rivals" in args
		var app = load("res://scripts/main.gd").new()
		app._register_inputs()
		app.free()
		game = load("res://scripts/game/game.gd").new()
		get_tree().root.add_child(game)
		game.start({"mode": mode, "seed": 414, "map": "small", "opponents": 1, "difficulty": 0, "strategy": "turtle", "calm_start": true})
		game.set_process(false)
		while Time.get_ticks_msec() - game.start_ms < 650:
			await get_tree().process_frame
		m = game.m
		if game.terra.available():
			fail("Terra must be off")
			get_tree().quit(1)
			return
	else:
		m.setup({"mode": mode, "seed": 414, "map": "small", "settlements": 2})
	home = m.home_pos(0)
	if mode == "standard" and not found_town():
		get_tree().quit(1)
		return
	for item in ["wood_shield", "bronze_sword", "ram", "cannon"]:
		if not afford(Defs.ITEMS[item].cost):
			get_tree().quit(1)
			return
		var bought := false
		if game and item == "bronze_sword":
			bought = order([], "/c bronze sword 1")
		elif game:
			bought = pick("c", "craft:" + item)
		else:
			bought = order([], "make one " + Defs.ITEMS[item].name)
		if not bought:
			get_tree().quit(1)
			return
	if not until(func(): return m.armory_overview(0).cannon.stock == 1 and m.armory_overview(0).ram.stock == 1, 230, "finish purchases"):
		get_tree().quit(1)
		return
	var foe = m.commander(1)
	var target = m.nearest_building(1, home, ["stone_gate" if mode == "grand_army" else "campfire"])
	m.set_mark(0, target.pos)
	if not order([], "man the ram, then attack the marked gate"):
		get_tree().quit(1)
		return
	if not until(func(): return target.dead or (mode == "standard" and target.hp < target.max_hp), 900, "ram reaches and breaches defenses"):
		var ram = m.units.filter(func(u): return u.faction == 0 and u.kind == "ram")[0]
		printerr("ram ", ram.pos, " crew ", ram.crew_ids, " target ", target.pos, " path ", ram.path)
		get_tree().quit(1)
		return
	m.set_mark(0, foe.pos, foe.id)
	if not order([], "man the cannon, then fire at the mark"):
		get_tree().quit(1)
		return
	if not until(func(): return m.over, 1300, "cannon engages opposing commander"):
		var gun = m.units.filter(func(u): return u.faction == 0 and u.kind == "cannon")[0]
		printerr("cannon ", gun.pos, " crew ", gun.crew_ids, " foe ", foe.pos)
		get_tree().quit(1)
		return
	if game:
		if mode == "grand_army" and live_rivals and rival_engines.size() != 2:
			fail("opposing settlement did not crew both engines: " + str(rival_engines))
			get_tree().quit(1)
			return
		game._process(0.0)
		if not game.over_shown:
			fail("the victory screen did not open")
			get_tree().quit(1)
			return
		print("Victory screen opened. Terra off. Rival strategy running: ", live_rivals)
	print("%s reached the end screen condition at %.1fs. Winner %d. %s" % [mode, m.t, m.winner, m.end_reason])
	get_tree().quit(0 if m.winner == 0 else 1)
