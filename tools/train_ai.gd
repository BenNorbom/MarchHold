extends SceneTree
## Trains the rival by self-play, headless:
##   godot --headless --path . -s res://tools/train_ai.gd -- [options]
##     --suite=rush|duel|all   rush: Rook against a scripted cavalry rusher, like a quick human player.
##                             duel: Rook's openings against each other.
##     --only=spear            run only the rushes whose label contains this
##     --seeds=3               maps per matchup
##     --minutes=20            how long each match may run
##     --difficulty=2          Rook's difficulty
## Each match prints one line; the summary at the end is what a change has to improve.

const Defs = preload("res://scripts/data/defs.gd")
const Match = preload("res://scripts/sim/match.gd")
const Rival = preload("res://scripts/ai/rival.gd")
const Raider = preload("res://tools/raider.gd")

const RUINED_POP := 5   # Rook alive at the end with fewer people than this counts as beaten

var args := {}
var results := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		args[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	_main.call_deferred()


func _main() -> void:
	var suite := str(args.get("suite", "all"))
	var seeds := int(args.get("seeds", "3"))
	var minutes := float(args.get("minutes", "20"))
	var level := int(args.get("difficulty", "2"))
	if suite in ["rush", "all"]:
		var rushes := [
			# Each goes as soon as it has the men, horses and spears; first_wave is only the earliest.
			{"label": "cavalry rush, 8 riders", "riders": 8, "first_wave": 240.0},
			{"label": "cavalry rush, 6 riders", "riders": 6, "first_wave": 240.0},
			{"label": "spear rush, 8 on foot", "riders": 8, "first_wave": 240.0, "foot": true},
		]
		var only := str(args.get("only", ""))
		for rush in rushes:
			if only != "" and not str(rush["label"]).contains(only):
				continue
			for strategy in Rival.STRATEGIES:
				for k in seeds:
					_rush_match(rush, strategy, level, 9100 + k * 37, minutes)
	if suite in ["duel", "all"]:
		var pairs := [["rush", "boom"], ["turtle", "cavalry"], ["cannons", "boom"], ["cavalry", "rush"], ["boom", "turtle"]]
		for pair in pairs:
			for k in seeds:
				_duel(pair, level, 4242 + k * 101, minutes)
	_summary()
	quit()


func _rush_match(rush: Dictionary, strategy: String, level: int, seed_in: int, minutes: float) -> void:
	var m = Match.new()
	m.setup({"seed": seed_in, "ai_both": true})
	var raider = Raider.new()
	raider.setup(m, rush.merged({"faction": 0, "seed": seed_in}))
	var rook = Rival.new()
	rook.setup(m, {"faction": 1, "difficulty": level, "strategy": strategy, "seed": seed_in})
	var t0 := Time.get_ticks_msec()
	_play(m, [raider, rook], minutes)
	var f1 = m.fac(1)
	var f0 = m.fac(0)
	# A village left with a handful of people has lost, even if the clock ran out first.
	var ruined: bool = not m.over and f1.pop < RUINED_POP
	var held: bool = (not m.over and not ruined) or (m.over and m.winner == 1)
	var outcome := "Rook WINS" if m.over and m.winner == 1 else ("ROOK DIES" if m.over else ("ROOK RUINED" if ruined else "Rook holds"))
	var line := "RUSH %-26s vs %-8s seed %d | %s at %5.1f min | Rook pop %d age %s kills %d deaths %d | raider waves %d pop %d deaths %d | %.0f s" % [
		rush["label"], strategy, seed_in, outcome, m.t / 60.0,
		f1.pop, Defs.AGES[f1.age], f1.kills, f1.deaths, raider.waves, f0.pop, f0.deaths, (Time.get_ticks_msec() - t0) / 1000.0]
	print(line)
	results.append({"suite": "rush", "key": rush["label"], "strategy": strategy, "held": held, "won": m.over and m.winner == 1,
		"pop": f1.pop, "age": f1.age, "kd": float(f1.kills) / maxf(1.0, float(f1.deaths))})


func _duel(pair: Array, level: int, seed_in: int, minutes: float) -> void:
	var m = Match.new()
	m.setup({"seed": seed_in, "ai_both": true})
	var ais := []
	for i in 2:
		var ai = Rival.new()
		ai.setup(m, {"faction": i, "difficulty": level, "strategy": pair[i], "seed": seed_in + i})
		ais.append(ai)
	var t0 := Time.get_ticks_msec()
	var peaks := _play(m, ais, minutes)
	var line := "DUEL %-8s vs %-8s seed %d | %s at %5.1f min" % [pair[0], pair[1], seed_in, ("winner " + pair[m.winner]) if m.over else "no winner", m.t / 60.0]
	for f in m.factions:
		line += " | %s pop %d (peak %d) age %s soldiers %d kills %d" % [pair[f.id], f.pop, peaks[f.id], Defs.AGES[f.age], f.soldiers, f.kills]
	print(line + " | %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	results.append({"suite": "duel", "key": "%s-%s" % pair, "over": m.over, "fought": m.fac(0).kills + m.fac(1).kills,
		"ages": [m.fac(0).age, m.fac(1).age], "peaks": peaks})


func _play(m, ais: Array, minutes: float) -> Array:
	var peaks := [0, 0]
	while m.t < minutes * 60.0 and not m.over:
		for i in 50:
			m.tick(Defs.TICK)
			for ai in ais:
				ai.update(Defs.TICK)
			m.events.clear()
			m.messages.clear()
			if m.over:
				break
		for f in m.factions:
			peaks[f.id] = maxi(peaks[f.id], f.pop)
	return peaks


func _summary() -> void:
	var rush := results.filter(func(r): return r["suite"] == "rush")
	if not rush.is_empty():
		var held := rush.filter(func(r): return r["held"]).size()
		var won := rush.filter(func(r): return r["won"]).size()
		var kd := 0.0
		for r in rush:
			kd += r["kd"]
		print("SUMMARY rush: Rook survived %d of %d, won %d, mean kills per loss %.2f" % [held, rush.size(), won, kd / rush.size()])
		for strategy in Rival.STRATEGIES:
			var mine := rush.filter(func(r): return r["strategy"] == strategy)
			print("  %-8s survived %d of %d" % [strategy, mine.filter(func(r): return r["held"]).size(), mine.size()])
	var duels := results.filter(func(r): return r["suite"] == "duel")
	if not duels.is_empty():
		var decided := duels.filter(func(r): return r["over"]).size()
		var fought := duels.filter(func(r): return r["fought"] > 0).size()
		var stone := 0
		var bronze := 0
		for r in duels:
			for a in r["ages"]:
				stone += 1 if a >= 1 else 0
				bronze += 1 if a >= 2 else 0
		print("SUMMARY duel: decided %d of %d, fought %d, Stone age %d of %d sides, Bronze %d" % [decided, duels.size(), fought, stone, duels.size() * 2, bronze])
