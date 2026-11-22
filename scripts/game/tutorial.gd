extends RefCounted
## "The Founding": a guided match against a passive rival. Terra, as steward,
## gives one goal at a time and waits until it is done.

const Defs = preload("res://scripts/data/defs.gd")

const STEPS := [
	["Find your people", "Walk up to one of your villagers by the campfire (WASD to move, mouse to look).",
		"Welcome, commander. I'm Terra, your steward. Your six villagers are waiting by the fire. Walk over to one of them."],
	["Your first order", "Look at a villager, press [b]Enter[/b], and type [b]gather wood[/b].",
		"People do what you tell them. Look at someone, press Enter and type 'gather wood'."],
	["A roof", "Type [b]/b b h[/b] (or press B, B, H) to build a [b]hut[/b]. It needs {hut}, so let them chop first.",
		"Only 8 people fit around a campfire. A hut houses 6 more. Type /b b h: b for basic structures, h for hut. Then click the ground to place it."],
	["Well fed", "Feed the village: say [b]pick berries[/b], then build a [b]farm[/b] ([b]/b b f[/b]). Wait for a birth.",
		"Children are born only when the village is well fed and there is room. Berries are quick; a farm feeds people for good."],
	["The armory", "Build an [b]armory[/b] ([b]/b b a[/b]), make spears ([b]/c b w[/b]), then say [b]arm 4 with spears[/b].",
		"Every soldier is a villager. The armory makes weapons; arming people takes them off work, so choose wisely."],
	["Eyes and ears", "Send a scout: [b]send a scout[/b]. When the scout returns, read the report with [b]/s[/b].",
		"You only know what you see. Scouts go out, look, and report back when they return. If they die, what they saw dies with them."],
	["Raiders!", "Raiders are coming. Build a [b]palisade[/b] ([b]/b b p[/b], click posts, Enter) and call [b]to arms[/b]. Survive.",
		"Your scout spotted raiders heading our way! A palisade slows them, and 'to arms' sends everyone to grab weapons and guard home."],
	["A captain", "Look at a villager and say [b]promote[/b]. Then give them two steps, e.g. [b]gather 30 wood then build a hut[/b].",
		"Press Tab in a crew's chat to give one member a new job, or say 'join @Name' to move them to another crew. Chain steps with 'then'."],
	["Stone", "Build a [b]quarry[/b] ([b]/b b q[/b]) next to a big rock outcrop, then start a [b]stone wall[/b] ([b]/b v w[/b]).",
		"A quarry opens the Stone age: towers, stone walls, stables and mines. Walls take a lot of stone and labor."],
	["The crown", "Find Rook's camp and kill [b]Commander Rook[/b] (he wears a crown). Take soldiers: [b]attack their camp[/b].",
		"Rook's camp is weak. Gather your soldiers, follow your scout's report, and end this. Say 'follow me' to bring a crew along."],
]

var g
var step := 0
var acc := 0.0
var flags := {}
var step_t := 0.0
var raid: Array = []
var raid_due := -1.0
var raid_spawned := false
var births0 := 0


func setup(game) -> void:
	g = game


func begin() -> void:
	step = 0
	_show()


func _show() -> void:
	var s: Array = STEPS[step]
	var task: String = s[1].replace("{hut}", Defs.cost_text(Defs.BUILDINGS["hut"]["cost"]))
	g.hud.set_objective("[color=#ffd870][b]The Founding[/b][/color]  ·  step %d of %d\n[b]%s[/b]\n%s" % [step + 1, STEPS.size(), s[0], task])
	g.hud.log_line(s[2], "terra", "Terra")
	step_t = 0.0
	births0 = g.m.fac(0).births
	if step == 6:
		raid_due = g.m.t + 70.0


func on_command(steps: Array, _r: Dictionary) -> void:
	if steps.size() >= 2:
		flags["multi"] = true
	for s in steps:
		if s["action"] == "gather" and s["subject"] == "wood":
			flags["wood"] = true
		if s["action"] == "scout":
			flags["scout"] = true


func tick(dt: float) -> void:
	acc += dt
	step_t += dt
	if acc < 0.5:
		return
	acc = 0.0
	if step == 6:
		_raid_logic()
	if step < STEPS.size() and _done():
		g.hud.log_line("Well done.", "done")
		Sfx.play("complete", null, -8.0)
		step += 1
		if step >= STEPS.size():
			g.hud.set_objective("")
			return
		_show()


func _done() -> bool:
	var m = g.m
	var f = m.fac(0)
	match step:
		0:
			var me = m.commander(0)
			for u in m.units:
				if u.faction == 0 and u.kind == "villager" and not u.dead and u.pos.distance_to(me.pos) < 4.5:
					return step_t > 2.0
			return false
		1:
			return flags.get("wood", false)
		2:
			return m.has_building(0, "hut")
		3:
			return m.has_building(0, "farm") and f.births > births0 - 1 and f.births >= 1 and f.food_state >= 2
		4:
			return m.has_building(0, "armory") and f.soldiers >= 3
		5:
			return not f.reports.is_empty()
		6:
			if not raid_spawned:
				return false
			for u in raid:
				if not u.dead:
					return false
			return true
		7:
			var captain := false
			for c in m.crews_of(0):
				if c.captain:
					captain = true
			return captain and flags.get("multi", false)
		8:
			for b in m.buildings:
				if not b.dead and b.faction == 0 and b.type == "stone_wall":
					return f.age >= 1
			return false
		9:
			return m.over and m.winner == 0
	return false


func _raid_logic() -> void:
	var m = g.m
	if raid_spawned or m.t < raid_due:
		return
	raid_spawned = true
	var home: Vector2 = m.home_pos(0)
	var away: Vector2 = (m.home_pos(1) - home).normalized()
	var start := home + away * 150.0
	for k in 4:
		var e = m.spawn_unit(1, "villager", start + Vector2(k * 1.6, (k % 2) * 1.5))
		e.name = "Raider"
		e.weapon = "wood_spear"
		raid.append(e)
	var c = m.make_crew(1, raid)
	m.set_mark(1, home)
	m.start_plan(c, [{"action": "attack", "subject": "", "count": 0, "amount": 0, "where": "marked", "sites": []}])
	g.hud.log_line("Raiders are coming from the %s!" % m.terrain.compass_name(away), "alarm")
	Sfx.play("horn", null, -4.0)
