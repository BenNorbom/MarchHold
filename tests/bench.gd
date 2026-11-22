extends SceneTree
## Headless performance benchmark and determinism fingerprint for the simulation:
##   godot --headless --path . -s res://tests/bench.gd -- [options]
##     --settlements=2,4,8   settlement counts to run
##     --pop=50,200          people per settlement
##     --scenario=economy,war,walled,idle
##     --seconds=10          simulated seconds measured (after a short warm-up)
##     --repeat=1            runs of each case; the median run is printed
##     --fingerprint=120     instead: hash a seeded AI-vs-AI match after N seconds.
##                           Changes that are pure optimisations must not move it.

const Defs = preload("res://scripts/data/defs.gd")
const Match = preload("res://scripts/sim/match.gd")
const Rival = preload("res://scripts/ai/rival.gd")

const SEED := 4242
const WARMUP_TICKS := 20


## A match that times its subsystems. Whatever is left of a tick is per-unit work.
class TimedMatch extends "res://scripts/sim/match.gd":
	var spent := {}
	var path_calls := 0

	func _add(key: String, since: int) -> void:
		spent[key] = int(spent.get(key, 0)) + Time.get_ticks_usec() - since

	func rebuild_unit_hash() -> void:
		var since := Time.get_ticks_usec()
		super()
		_add("hash", since)

	func upkeep(dt: float) -> void:
		var since := Time.get_ticks_usec()
		super(dt)
		_add("upkeep", since)

	func update_crews(dt: float) -> void:
		var since := Time.get_ticks_usec()
		super(dt)
		_add("crews", since)

	func update_vision() -> void:
		var since := Time.get_ticks_usec()
		super()
		_add("vision", since)

	func update_shots(dt: float) -> void:
		var since := Time.get_ticks_usec()
		super(dt)
		_add("shots", since)

	func find_path(faction: int, a: Vector2, b: Vector2) -> PackedVector2Array:
		var since := Time.get_ticks_usec()
		var out := super(faction, a, b)
		_add("paths", since)
		path_calls += 1
		return out


var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	_main.call_deferred()


func _main() -> void:
	if args.has("fingerprint"):
		_fingerprint(float(args["fingerprint"]))
	else:
		for n in str(args.get("settlements", "2")).split(","):
			for pop in str(args.get("pop", "50,200")).split(","):
				for scenario in str(args.get("scenario", "economy,war")).split(","):
					_case(int(n), int(pop), scenario)
	quit()


func _map_for(settlements: int) -> String:
	for id in Defs.MAP_SIZES:
		if settlements <= int(Defs.MAP_SIZES[id].get("settlements", 2)) and int(Defs.MAP_SIZES[id]["size"]) >= 768:
			return id
	return Defs.MAP_REFERENCE


func _case(settlements: int, pop: int, scenario: String) -> void:
	var runs := []
	for k in maxi(1, int(args.get("repeat", "1"))):
		var r := _measure(settlements, pop, scenario)
		if r.is_empty():
			print("SKIP n=%d: this build can't set up that many settlements" % settlements)
			return
		runs.append(r)
	runs.sort_custom(func(a, b): return a["avg"] < b["avg"])
	var mid: Dictionary = runs[runs.size() / 2]
	print("BENCH n=%d pop=%d %-7s avg=%6.2f p50=%6.2f p99=%6.2f max=%6.2f ms | %s | paths/tick=%.1f setup=%d ms mem=%d MB" % [
		settlements, pop, scenario, mid["avg"], mid["p50"], mid["p99"], mid["max"], mid["parts"], mid["paths"],
		mid["setup"], OS.get_static_memory_usage() / 1048576])


func _measure(settlements: int, pop: int, scenario: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var m := TimedMatch.new()
	m.setup({"seed": SEED, "map": _map_for(settlements), "settlements": settlements, "ai_both": true})
	if m.factions.size() != settlements:
		return {}
	_stage(m, pop, scenario)
	var setup_ms := Time.get_ticks_msec() - t0
	for i in WARMUP_TICKS:
		_step(m)
	m.spent.clear()
	m.path_calls = 0
	var n := maxi(1, int(float(args.get("seconds", "10")) / Defs.TICK))
	var times: Array[float] = []
	var total := 0.0
	for i in n:
		var ms := _step(m)
		times.append(ms)
		total += ms
	times.sort()
	var parts: Array[String] = []
	var other := total
	for key in ["hash", "upkeep", "crews", "vision", "shots", "paths"]:
		var ms: float = int(m.spent.get(key, 0)) / 1000.0
		other -= ms
		parts.append("%s %.2f" % [key, ms / n])
	parts.append("units %.2f" % (other / n))
	return {"avg": total / n, "p50": times[n / 2], "p99": times[mini(n - 1, int(n * 0.99))], "max": times[n - 1],
		"parts": ", ".join(parts), "paths": float(m.path_calls) / n, "setup": setup_ms}


func _step(m) -> float:
	# Hold food steady so a case measures a fixed number of people.
	for f in m.factions:
		f.stock["food"] = f.pop * Defs.FED_STOCK * 1.5
		f.food_cap = maxi(f.food_cap, f.pop * 3)
	var since := Time.get_ticks_usec()
	m.tick(Defs.TICK)
	var ms := (Time.get_ticks_usec() - since) / 1000.0
	m.events.clear()
	m.messages.clear()
	return ms


## A grown settlement for everyone, then the work the scenario calls for.
func _stage(m, pop: int, scenario: String) -> void:
	var n: int = m.factions.size()
	var center := Vector2(m.map_size, m.map_size) * 0.5
	for f in m.factions:
		var home: Vector2 = m.home_pos(f.id)
		var plan := ["armory", "stockpile", "stockpile", "stockpile", "watch_post"]
		for k in pop / 12:
			plan.append("hut")
		var k := 0
		for type in plan:
			while k < 400:
				k += 1
				var p := home + Vector2.from_angle(k * 2.39996) * (12.0 + sqrt(k) * 4.0)
				if m.site_problem(f.id, type, p, 0.0) == "":
					m.add_building(f.id, type, p, 0.0, true)
					break
		if scenario == "walled":
			for i in 88:
				var a := i * TAU / 88.0
				var gate: bool = i == 0
				m.add_building(f.id, "stone_gate" if gate else "stone_wall", home + Vector2.from_angle(a) * 56.0, a + PI * 0.5, true)
		var men: Array = m.idle_adults(f.id, home)
		while men.size() < pop:
			var i := men.size()
			var u = m.spawn_unit(f.id, "villager", home + Vector2.from_angle(i * 2.39996) * (4.0 + sqrt(i) * 1.6))
			u.name = "B%d" % i
			men.append(u)
		m.rebuild_unit_hash()
		m._refresh_counts(f)
		match scenario:
			"economy":
				_order(m, f.id, men.slice(0, int(pop * 0.4)), "gather", "wood")
				_order(m, f.id, men.slice(int(pop * 0.4), int(pop * 0.65)), "gather", "berries")
				_order(m, f.id, men.slice(int(pop * 0.65), int(pop * 0.8)), "gather", "stone")
				var guards: Array = men.slice(int(pop * 0.8), int(pop * 0.9))
				for u in guards:
					u.weapon = "wood_spear"
				_order(m, f.id, guards, "guard", "", "home")
			"war", "walled":
				var army: Array = men.slice(0, pop / 2)
				for i in army.size():
					army[i].weapon = "wood_spear"
					army[i].bow = i % 4 == 0
					army[i].arrows = Defs.QUIVER if army[i].bow else 0
				var foe: Vector2 = m.fac((f.id + 1) % n).start
				if scenario == "war":
					# Everyone's army meets in the middle.
					var muster: Vector2 = center + (home - center).normalized() * 28.0
					for i in army.size():
						army[i].pos = muster + Vector2.from_angle(i * 2.39996) * sqrt(i) * 1.5
						army[i].prev = army[i].pos
					foe = center
				m.set_mark(f.id, foe)
				_order(m, f.id, army, "attack", "", "marked")
				_order(m, f.id, men.slice(pop / 2), "gather", "wood")
	m.rebuild_unit_hash()


func _order(m, faction: int, men: Array, action: String, subject: String = "", where: String = "") -> void:
	if men.is_empty():
		return
	var c = m.make_crew(faction, men)
	var r: Dictionary = m.command(faction, {"crew": c.id, "steps": [{"action": action, "subject": subject, "where": where}]})
	if not r.get("ok", false):
		printerr("bench order failed (%s %s): %s" % [action, subject, r.get("error", "")])


func _fingerprint(seconds: float) -> void:
	for map_id in ["small", "large"]:
		var m := Match.new()
		m.setup({"seed": SEED, "map": map_id, "ai_both": true})
		var ais := []
		for i in 2:
			var ai := Rival.new()
			ai.setup(m, {"faction": i, "difficulty": 2, "strategy": ["rush", "boom"][i], "seed": 99 + i})
			ais.append(ai)
		var t0 := Time.get_ticks_msec()
		for i in int(seconds / Defs.TICK):
			m.tick(Defs.TICK)
			for ai in ais:
				ai.update(Defs.TICK)
			m.events.clear()
			if m.over:
				break
		var state := []
		for u in m.units:
			state.append([u.id, u.faction, u.pos, u.hp, u.task, u.carry, u.weapon, u.dead])
		for b in m.buildings:
			state.append([b.id, b.faction, b.type, b.pos, b.hp, b.progress, b.dead])
		for f in m.factions:
			state.append([f.id, f.stock, f.gear, f.age, f.kills, f.births])
		print("FINGERPRINT map=%s seconds=%d hash=%d units=%d buildings=%d wall=%d ms" % [
			map_id, int(seconds), hash(var_to_str(state)), m.units.size(), m.buildings.size(), Time.get_ticks_msec() - t0])
