extends SceneTree
## Battle tests on a small flat field, so they run in seconds:
##   godot --headless --path . -s res://tests/test_battle.gd
## Set MH_TEST=<name> to run a single test.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Match = preload("res://scripts/sim/match.gd")
const Crowd = preload("res://scripts/sim/crowd.gd")
const BattlePose = preload("res://scripts/view/battle_pose.gd")

const C := Vector2(128, 128)
const TOUCH := 0.68               # 85% of two people's radii
const TESTS := ["bodies", "destinations", "arrival", "gate", "corpse", "free_arrows", "archery", "timing", "leash",
	"walls", "walled_camp", "towers", "deep_crew", "commander_attack", "commander_guard", "commander_bow", "matchups", "fairness", "poses"]

var failures := 0
var passes := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := OS.get_environment("MH_TEST")
	var t0 := Time.get_ticks_msec()
	for name in TESTS:
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


# --- Helpers -----------------------------------------------------------------------

func field(seed_in: int = 1):
	var tr = Terrain.new()
	tr.size = 256.0
	tr.height_res = 129
	tr.heights.resize(129 * 129)
	tr.heights.fill(5.0)
	var m = Match.new()
	m.rng.seed = seed_in
	m._init_world(tr, 2)
	m.birth_acc.resize(2)
	for i in 2:
		var f = m.Faction.new()
		f.id = i
		f.start = Vector2(40 + 176 * i, 128)
		f.knowledge.resize(m.kres * m.kres)
		f.knowledge.fill(-1.0)
		for r in Defs.RESOURCES:
			f.stock[r] = 100.0
		f.food_cap = 150
		m.factions.append(f)
	m.rebuild_unit_hash()
	return m


func soldier(m, faction: int, p: Vector2, weapon: String = "wood_spear"):
	var u = m.spawn_unit(faction, "villager", p)
	u.name = "S%d" % u.id
	u.weapon = weapon
	return u


## Stands still and takes it.
func dummy(m, faction: int, p: Vector2, hp: float = 100000.0):
	var u = m.spawn_unit(faction, "commander", p)
	u.task = "player"
	u.weapon = ""
	u.max_hp = hp
	u.hp = hp
	return u


func player(m, p: Vector2, weapon: String = "wood_spear"):
	var u = dummy(m, 0, p)
	u.weapon = weapon
	u.facing = 0.0        # looking along +y
	m.fac(0).commander = u.id
	return u


func crew(m, men: Array, action: String, target: Vector2):
	var c = m.make_crew(men[0].faction, men)
	c.steps = [{"action": action, "subject": "", "count": 0, "amount": 0, "where": ""}]
	c.state = {"target": target}
	c.start_size = men.size()
	for u in men:
		m._set_task(u, action)
	m._assign_slots(c)
	return c


func run(m, seconds: float) -> void:
	for i in roundi(seconds / Defs.TICK):
		m.tick(Defs.TICK)


func wall(m, faction: int, p: Vector2, length: float, rot: float = PI / 2, type: String = "palisade"):
	var b = m.add_building(faction, type, p, rot, true)
	m._unblock(b)
	b.size.x = length
	m._block(b)
	return b


func overlaps(list: Array) -> int:
	var n := 0
	for i in list.size():
		for j in range(i + 1, list.size()):
			if not list[i].dead and not list[j].dead and list[i].pos.distance_to(list[j].pos) < TOUCH:
				n += 1
	return n


func alive(list: Array) -> Array:
	return list.filter(func(u): return not u.dead)


# --- Bodies and movement -----------------------------------------------------------

func test_bodies() -> void:
	var m = field()
	var foe = dummy(m, 1, C)
	var men := []
	for k in 24:
		men.append(soldier(m, 0, C + Vector2((k % 8 - 3.5) * 1.9, -22 - k / 8 * 2)))
	crew(m, men, "attack", C)
	run(m, 14.0)
	check(overlaps(men + [foe]) == 0, "24 on 1: nobody overlaps (%d pairs)" % overlaps(men + [foe]))
	check(foe.hp < foe.max_hp, "the target is being hit")
	var fighting := men.filter(func(u): return u.engaged and u.front).size()
	check(fighting >= 3 and fighting <= Defs.MELEE["spear"]["places"], "a ring fights, the rest wait (%d fighting)" % fighting)

	m = field()
	var same := []
	for k in 30:
		same.append(soldier(m, 0, C, ""))
	run(m, 3.0)
	check(overlaps(same) == 0, "30 on one exact spot spread out (%d pairs)" % overlaps(same))

	m = field()
	var all := []
	for side in 2:
		var line := []
		for k in 100:
			var u = soldier(m, side, C + Vector2((k % 25 - 12) * 1.6, (11 + k / 25 * 1.8) * (1 if side else -1)))
			u.max_hp = 100000.0
			u.hp = u.max_hp
			line.append(u)
		crew(m, line, "attack", C)
		all += line
	run(m, 12.0)
	var pairs := overlaps(all)
	check(pairs <= 8, "100 v 100: no pile-ups (%d overlapping pairs of 19900)" % pairs)
	var buried := all.filter(func(u): return m.solid_for(u.faction, m.cell_of(u.pos))).size()
	check(buried == 0, "100 v 100: nobody pushed into solid ground")


func test_destinations() -> void:
	var m = field()
	var a := []
	var b := []
	for k in 8:
		a.append(soldier(m, 0, C + Vector2(k * 1.5 - 20, 20)))
		b.append(soldier(m, 0, C + Vector2(k * 1.5 + 10, 20)))
	var ca = crew(m, a, "guard", C)
	var cb = crew(m, b, "guard", C)
	run(m, 25.0)
	var closest := INF
	for u in a:
		for v in b:
			closest = minf(closest, m.station(u, ca).distance_to(m.station(v, cb)))
	check(closest >= 1.0, "crews with one post get their own spots (%.2f m)" % closest)
	check(overlaps(a + b) == 0, "two crews at one post don't overlap")
	var spots := []
	for id in 200:
		var u = soldier(m, 0, C)
		spots.append(m._ring(u, 6.0))
	var repeats := 0
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if spots[i].distance_to(spots[j]) < 0.05:
				repeats += 1
	check(repeats == 0, "ring spots never repeat (%d)" % repeats)


func test_arrival() -> void:
	var m = field()
	var u = soldier(m, 0, Vector2(60, 128), "")
	u.flee_t = 14.0
	run(m, 9.0)
	var bad := 0
	for i in 40:
		var p: Vector2 = u.pos
		m.tick(Defs.TICK)
		if u.anim != m.Anim.IDLE or u.pos.distance_to(p) > 0.02:
			bad += 1
	check(bad == 0, "someone who has arrived stands still (%d bad ticks)" % bad)
	var men := []
	for k in 20:
		men.append(soldier(m, 0, C + Vector2(k % 5, 20 + k / 5)))
	var c = crew(m, men, "recall", C)
	run(m, 22.0)
	check(not m.crews.has(c.id), "a crowded recall finishes")


func test_gate() -> void:
	var m = field()
	wall(m, 0, C + Vector2(0, -22), 40.0)
	wall(m, 0, C + Vector2(0, 22), 40.0)
	wall(m, 0, C, 5.0, PI / 2, "palisade_gate")
	var out := []
	var back := []
	for k in 12:
		out.append(soldier(m, 0, C + Vector2(-12 - k / 4 * 1.5, k % 4 * 1.5 - 2)))
		back.append(soldier(m, 0, C + Vector2(12 + k / 4 * 1.5, k % 4 * 1.5 - 2)))
	crew(m, out, "guard", C + Vector2(20, 0))
	crew(m, back, "guard", C - Vector2(20, 0))
	run(m, 40.0)
	var through := out.filter(func(u): return u.pos.x > C.x + 4).size() + back.filter(func(u): return u.pos.x < C.x - 4).size()
	check(through == 24, "both ways through one gate without jamming (%d of 24)" % through)


func test_corpse() -> void:
	var m = field()
	var u = soldier(m, 0, C)
	u.prev = C - Vector2(0.5, 0)
	m.kill_unit(u, "melee")
	m.tick(Defs.TICK)
	check(u.prev == u.pos, "a corpse lies still")


# --- Ranged ------------------------------------------------------------------------

func test_free_arrows() -> void:
	for power in [0.0, 0.5, 1.0]:
		var speed := lerpf(22.0, 62.0, power)
		var hit := 0
		for d in range(3, 31):
			var m = field()
			var p = player(m, C)
			var e = dummy(m, 1, C + Vector2(0, d))
			m.rebuild_unit_hash()
			var rise := (1.2 - 1.68 + 4.9 * pow(d / speed, 2)) / float(d)
			m.fire_free_arrow(p, Vector3(C.x, 6.68, C.y), Vector3(0, rise, 1).normalized() * speed, 0)
			run(m, 2.0)
			if e.hp < e.max_hp:
				hit += 1
		check(hit == 28, "aimed arrows hit at every range from 3 to 30 m (power %.1f: %d of 28)" % [power, hit])
	var m2 = field()
	var p2 = player(m2, C)
	var hidden = dummy(m2, 1, C + Vector2(0, 8))
	wall(m2, 1, C + Vector2(0, 5), 10.0, 0.0)
	m2.rebuild_unit_hash()
	m2.fire_free_arrow(p2, Vector3(C.x, 6.68, C.y), Vector3(0, 0, 55), 0)
	run(m2, 1.0)
	check(hidden.hp == hidden.max_hp, "a wall stops your arrow")


func test_archery() -> void:
	for moving in [false, true]:
		var hit := 0
		for k in 100:
			var m = field(k + 1)
			var a = dummy(m, 0, C)
			var e = dummy(m, 1, C + Vector2(0, 25))
			for i in 5:
				if moving:
					e.pos.x += 0.4
				m.tick(Defs.TICK)
			m.fire_arrow(a, e, 0)
			for i in 10:
				if moving:
					e.pos.x += 0.4
				m.tick(Defs.TICK)
			if e.hp < e.max_hp:
				hit += 1
		check(hit >= 58 and hit <= 88, "archers hit at their rated 72%% at 25 m, moving=%s (%d%%)" % [moving, hit])
	var m2 = field()
	var archer = soldier(m2, 0, C, "")
	var sheltered = dummy(m2, 1, C + Vector2(0, 22))
	wall(m2, 1, C + Vector2(0, 20.8), 10.0, 0.0, "stone_wall")
	check(m2.arrow_arc(archer, sheltered) < 0.0, "hugging a stone wall is cover")
	var far_back = dummy(m2, 1, C + Vector2(40, 40))
	check(m2.arrow_arc(archer, far_back) > 0.0, "in the open is not cover")


# --- Rules -------------------------------------------------------------------------

func test_timing() -> void:
	var m = field()
	var a = soldier(m, 0, C)
	var e = dummy(m, 1, C + Vector2(1.2, 0))
	var landed := -1.0
	var early := false
	for i in 30:
		m.tick(Defs.TICK)
		if e.hp < e.max_hp and landed < 0.0:
			landed = m.t
			early = m.t + 0.001 < a.swing_hit
	check(landed > 0.0 and not early, "damage waits for the impact")
	check(landed >= float(Defs.MELEE["spear"]["wind"]), "a blow has a wind-up (%.2f s)" % landed)

	m = field()
	a = soldier(m, 0, C)
	var b = soldier(m, 1, C + Vector2(1.2, 0))
	a.hp = 14.0
	b.hp = 14.0
	a.max_hp = 14.0
	b.max_hp = 14.0
	run(m, 3.0)
	check(a.dead and b.dead, "equal blows land together")

	m = field()
	a = soldier(m, 0, C)
	e = dummy(m, 1, C + Vector2(1.2, 0))
	while a.swing_start < 0.0 and m.t < 2.0:
		m.tick(Defs.TICK)
	e.pos = a.pos + Vector2(float(Defs.ITEMS[a.weapon]["reach"]) + 1.5, 0)
	while m.t < a.swing_hit + 0.15:
		m.tick(Defs.TICK)
	check(e.hp == e.max_hp, "stepping back during the wind-up dodges it")


func test_leash() -> void:
	for order in ["guard", "hold"]:
		var m = field()
		var g = soldier(m, 0, C)
		crew(m, [g], order, C)
		var bait = dummy(m, 1, C + Vector2(6, 0))
		var far := 0.0
		for i in 280:
			bait.pos.x = minf(240.0, bait.pos.x + 0.36)
			m.tick(Defs.TICK)
			far = maxf(far, g.pos.distance_to(C))
		var limit := 36.0 if order == "guard" else 2.5
		check(far <= limit, "%s stays by its post (%.1f m, limit %.1f)" % [order, far, limit])
		run(m, 14.0)
		check(g.pos.distance_to(C) < 2.0, "%s goes back to the post afterwards" % order)


func test_walls() -> void:
	var m = field()
	wall(m, 1, C, 30.0)
	var a = soldier(m, 0, C - Vector2(1.5, 0), "iron_pike")
	var b = dummy(m, 1, C + Vector2(1.5, 0))
	crew(m, [a], "hold", a.pos)
	run(m, 5.0)
	check(b.hp == b.max_hp, "no blows through a wall")

	m = field()
	var ring := []
	for k in 4:
		ring.append(wall(m, 1, C + Vector2.from_angle(k * PI / 2) * 5.0, 12.0, k * PI / 2 + PI / 2))
	var inside = dummy(m, 1, C)
	var men := []
	for k in 4:
		men.append(soldier(m, 0, C + Vector2(-16, k * 1.5 - 2), "iron_sword"))
	crew(m, men, "attack", C)
	run(m, 25.0)
	var hurt := ring.filter(func(w): return w.dead or w.hp < w.max_hp).size()
	check(hurt > 0 or inside.hp < inside.max_hp, "an unreachable foe: the wall in the way is attacked")


func ring(m, faction: int, r: float, gate: bool) -> Array:
	var out := []
	var n := int(ceil(TAU * r / 4.0))
	for k in n:
		var a := TAU * (k + 0.5) / n
		var kind := "palisade_gate" if gate and k == 0 else "palisade"
		out.append(wall(m, faction, C + Vector2.from_angle(a) * r, TAU * r / n + 0.5, a + PI / 2, kind))
	return out


func test_walled_camp() -> void:
	for gate in [false, true]:
		var m = field()
		var pieces := ring(m, 1, 46.0, gate)
		var fire = m.add_building(1, "campfire", C, 0.0, true)
		var men := []
		for k in 16:
			men.append(soldier(m, 0, C + Vector2(-70 - k / 8 * 2, k % 8 * 1.9 - 7), "iron_sword"))
		crew(m, men, "attack", C)
		var worst := 0
		for i in 600:
			var t0 := Time.get_ticks_usec()
			m.tick(Defs.TICK)
			worst = maxi(worst, Time.get_ticks_usec() - t0)
		var hurt := pieces.filter(func(w): return w.dead or w.hp < w.max_hp).size()
		check(hurt > 0 or fire.dead or fire.hp < fire.max_hp, "an army breaks into a walled camp (gate=%s)" % gate)
		print("  walled camp, gate=%s: worst tick %.0f ms" % [gate, worst / 1000.0])

	var m2 = field()
	ring(m2, 0, 18.0, false)
	var u = soldier(m2, 0, C, "")
	var c = crew(m2, [u], "guard", C + Vector2(34, 0))
	run(m2, 25.0)
	check(u.pos.distance_to(m2.station(u, c)) < 3.0, "your own wall without a gate doesn't trap your people")


func test_towers() -> void:
	for rot in [0.0, 0.6]:
		var m = field()
		var tw = m.add_building(0, "tower", C, rot, true)
		var men := []
		for k in 4:
			var u = soldier(m, 0, C + Vector2(-16, k * 1.5 - 2), "")
			u.bow = true
			u.arrows = 16
			men.append(u)
		crew(m, men, "guard", C)
		run(m, 20.0)
		var manned := men.filter(func(u): return u.in_tower == tw.id).size()
		check(manned == 3, "three archers man a tower turned %.1f (%d)" % [rot, manned])


func test_deep_crew() -> void:
	var m = field()
	var men := []
	for k in 100:
		men.append(soldier(m, 0, Vector2(50 + (k % 10) * 1.9, 60 + k / 10 * 2)))
	var hut = m.add_building(1, "hut", Vector2(100, 130), 0.0, true)
	crew(m, men, "attack", hut.pos)
	run(m, 50.0)
	check(hut.dead or hut.hp < hut.max_hp, "a 100-strong crew reaches what it attacks")


# --- The player ----------------------------------------------------------------------

func test_commander_attack() -> void:
	var m = field()
	var p = player(m, C)
	var e = dummy(m, 1, C + Vector2(0, 1.4))
	m.rebuild_unit_hash()
	check(m.commander_swing(0, 0.05), "a swing starts at once")
	m.commander_update(0, 0.1)
	check(e.hp == e.max_hp, "your blow waits for the visible impact")
	m.commander_update(0, 0.05 + float(Defs.MELEE["spear"]["quick"]))
	check(e.hp < e.max_hp, "and lands on that frame, between ticks")
	check(not m.commander_swing(0, 0.4), "no second blow inside the swing")
	check(m.commander_swing(0, 0.05 + float(Defs.ITEMS[p.weapon]["rate"]) * Defs.COMMANDER_SWING), "the next blow is ready exactly when the swing ends")

	m = field()
	p = player(m, C, "iron_sword")
	var l = dummy(m, 1, C + Vector2(-0.7, 1.3))
	var r = dummy(m, 1, C + Vector2(0.7, 1.3))
	var behind = dummy(m, 1, C + Vector2(0, -1.3))
	m.rebuild_unit_hash()
	m.commander_swing(0, 0.0)
	m.commander_update(0, 0.2)
	check(l.hp < l.max_hp and r.hp < r.max_hp, "a sword sweeps two")
	check(behind.hp == behind.max_hp, "and nobody behind you")

	m = field()
	p = player(m, C, "iron_pike")
	var far = dummy(m, 1, C + Vector2(0, 4.2))
	m.rebuild_unit_hash()
	m.commander_swing(0, 0.0)
	m.commander_update(0, 0.35)
	check(far.hp < far.max_hp, "a pike reaches 4 m")

	check(m.commander_engaged(0), "with an enemy near, clicks are blows")


func test_commander_guard() -> void:
	var m = field()
	var p = player(m, C)
	var a = soldier(m, 1, C + Vector2(0, 1.2))
	m.t = 5.0
	m.commander_block(0, true, 4.9)
	var guard: String = m.deal_damage(p, 10.0, a, "melee")
	check(guard == "parry" and p.hp == p.max_hp, "a guard raised as the blow lands parries")
	check(a.stun_t > m.t + 0.8, "and staggers the attacker")
	m.t = 6.0
	var hp: float = p.hp
	guard = m.deal_damage(p, 10.0, a, "melee")
	check(guard == "block" and is_equal_approx(hp - p.hp, 10.0 * Defs.BLOCK_KEEP["weapon"]), "a held guard blocks most of it")
	check(p.stamina < 1.0, "blocking costs stamina")
	p.shield = "wood_shield"
	hp = p.hp
	var shield: Dictionary = Defs.ITEMS[p.shield]
	m.deal_damage(p, 10.0 * (1.0 - shield["block_melee"]), a, "melee")
	check(is_equal_approx(hp - p.hp, 10.0 * (1.0 - shield["up_melee"])), "a shield blocks nearly all")
	var back = soldier(m, 1, C + Vector2(0, -1.2))
	hp = p.hp
	m.deal_damage(p, 10.0, back, "melee")
	check(is_equal_approx(hp - p.hp, 10.0), "no block from behind")
	p.stamina = 0.0
	hp = p.hp
	m.deal_damage(p, 10.0, a, "melee")
	check(is_equal_approx(hp - p.hp, 10.0), "a tired guard breaks")
	m.commander_block(0, false, 7.0)
	m.commander_block(0, true, 7.1)
	p.stamina = 1.0
	m.t = 7.2
	check(m.deal_damage(p, 10.0, a, "melee") == "block", "flickering the guard doesn't parry")
	m.commander_swing(0, 8.0)
	check(not p.blocking, "attacking lowers the guard")


func test_commander_bow() -> void:
	var m = field()
	var p = player(m, C, "")
	p.bow = true
	p.arrows = 5
	var o := Vector3(C.x, 6.68, C.y)
	check(m.commander_shoot(0, o, Vector3.BACK, 1.0, 1.0), "the bow looses")
	check(not m.commander_shoot(0, o, Vector3.BACK, 1.0, 1.1), "nocking takes a moment")
	check(m.commander_shoot(0, o, Vector3.BACK, 0.0, 1.5), "then it looses again")
	check(m.shots[1].dmg < m.shots[0].dmg * 0.6, "a snap shot hurts less than a full draw")


# --- Balance -------------------------------------------------------------------------

## +1 when side 0 wins, -1 when side 1 does. count: how many on each side.
func battle(a: Dictionary, b: Dictionary, seed_in: int, count: int = 8, gap: float = 9.0) -> int:
	var m = field(seed_in)
	var sides := [[], []]
	var order := range(count * 2)
	for k in order:
		# Alternate who comes first in the update order.
		var side: int = (k + seed_in) % 2
		var kit: Dictionary = b if side else a
		var i: int = sides[side].size()
		var jitter := Vector2(m.rng.randf_range(-0.5, 0.5), m.rng.randf_range(-0.5, 0.5))
		var u = soldier(m, side, C + Vector2((i % 8 - 3.5) * 1.8, (gap + i / 8 * 2.0) * (1 if side else -1)) + jitter, kit.get("weapon", ""))
		u.shield = kit.get("shield", "")
		u.armor = kit.get("armor", "")
		if kit.get("bow", false):
			u.bow = true
			u.arrows = 16
		if kit.get("horse", false):
			u.mounted = true
			u.max_hp += Defs.MOUNTED["hp_bonus"]
			u.hp = u.max_hp
		sides[side].append(u)
	crew(m, sides[0], "attack", C)
	crew(m, sides[1], "attack", C)
	for i in 900:
		m.tick(Defs.TICK)
		if i % 5 == 0 and (alive(sides[0]).is_empty() or alive(sides[1]).is_empty()):
			break
	var strength := [0.0, 0.0]
	for s in 2:
		for u in alive(sides[s]):
			strength[s] += 1.0 + u.hp / u.max_hp
	return int(signf(strength[0] - strength[1]))


func wins(a: Dictionary, b: Dictionary, n: int, count: int = 8, gap: float = 9.0) -> int:
	var won := 0
	for k in n:
		if battle(a, b, k + 1, count, gap) > 0:
			won += 1
	return won


func test_matchups() -> void:
	var pike := {"weapon": "bronze_pike"}
	var lancer := {"weapon": "bronze_lance", "horse": true}
	var sword := {"weapon": "bronze_sword", "shield": "bronze_shield"}
	var archer := {"bow": true}
	var infantry := {"weapon": "wood_spear"}
	var cases := [
		["pikes beat cavalry", pike, lancer, 9.0],
		["cavalry beats archers", lancer, archer, 14.0],
		["sword and shield beats pikes", sword, pike, 9.0],
		["archers beat unshielded infantry", archer, infantry, 22.0],
		["shields blunt archers", sword, archer, 13.0],
	]
	for c in cases:
		var won := wins(c[1], c[2], 12, 8, c[3])
		print("  %s: %d of 12" % [c[0], won])
		check(won >= 8, "%s (%d of 12)" % [c[0], won])


func test_fairness() -> void:
	var tally := 0
	var n := 60
	for k in n:
		tally += battle({"weapon": "wood_spear"}, {"weapon": "wood_spear"}, k + 1, 8)
	var share := 0.5 + 0.5 * float(tally) / n
	print("  side 0 share %.2f over %d mirrored fights" % [share, n])
	# Two standard deviations over 60 fair fights is about 0.13.
	check(absf(share - 0.5) <= 0.14, "mirrored fights favour neither side (%.2f)" % share)


# --- Poses ---------------------------------------------------------------------------

func test_poses() -> void:
	var m = field()
	var tips := {"bronze_sword": 0.89, "wood_spear": 1.75, "bronze_pike": 3.95}
	for weapon in tips:
		var u = soldier(m, 0, C, weapon)
		u.swing_start = 0.0
		u.swing_hit = 0.4
		u.swing_end = 1.2
		var p: Dictionary = BattlePose.sample(u, 0.4)
		check(not p.is_empty(), "%s has an impact pose" % weapon)
		var xf: Transform3D = BattlePose.prop(p, weapon, BattlePose.crowd_hand(p, true))
		var upright: bool = weapon.ends_with("spear") or weapon.ends_with("pike")
		var point: Vector3 = BattlePose.HAND_R + (Vector3(0, tips[weapon], 0.05) if upright else Vector3(0, 0.02, tips[weapon]))
		var tip: Vector3 = xf * point
		var stand: float = Defs.MELEE[Defs.weapon_family(weapon)]["stand"]
		check(tip.z > stand - 0.55 and tip.z < stand + 0.95, "%s visibly reaches its target at impact (tip %.2f m, target %.1f m)" % [weapon, tip.z, stand])
		check(tip.y > 0.5 and tip.y < 1.9, "%s lands on the body (%.2f m up)" % [weapon, tip.y])
		var code: Color = BattlePose.encode(p, 0.5)
		var bits := roundi(code.r) - BattlePose.CODE
		check(absf(((bits >> 1) & 15) * 0.05 - 0.2 - p["lean"]) < 0.03 and absf(((bits >> 5) & 31) * 0.05 - 0.8 - p["twist"]) < 0.03, "%s pose survives packing" % weapon)
		check(code.r < 2048.0, "packed pose fits a half float exactly")
	var rider = soldier(m, 0, C, "bronze_lance")
	rider.mounted = true
	rider.anim = m.Anim.MELEE
	var rp: Dictionary = BattlePose.sample(rider, 1.0)
	check(rp["ride"] and (roundi(BattlePose.encode(rp, 0.1).r) - BattlePose.CODE) & 1 == 1, "riders keep riding legs while fighting")
