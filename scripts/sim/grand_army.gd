extends RefCounted
## The Grand army start: every side begins as a finished, walled settlement at full
## tech, for fights between maxed-out armies. What each side gets is Defs.GRAND_ARMY.
## It only runs during setup, before the first tick.

const Defs = preload("res://scripts/data/defs.gd")

const WALL_R := 88.0          # inside the 100 m margin camps keep from a small map's edge
const GATES := 4
const PLAZA := 15.0           # open ground round the campfire
const INSIDE := 9.0           # buildings keep this far in from the wall
const OUTSIDE := 170.0        # the furthest anything that didn't fit inside may stand
const LANE := 3.2             # room left between buildings, so a path cell is always free
const NODE_OFFSETS := [7.0, 10.0, 13.0, 16.0, 19.0]


static func apply(m, f) -> void:
	var spec: Dictionary = Defs.GRAND_ARMY
	f.age = Defs.AGES.size() - 1
	for age in f.age_t.size():
		f.age_t[age] = 0.0
	for id in Defs.RESEARCH:
		f.researched[id] = true
	var home: Vector2 = m.home_pos(f.id)
	var front: float = (Vector2(m.map_size, m.map_size) * 0.5 - home).angle()
	_wall(m, f.id, home, front)
	_works(m, f.id, home)
	# Candidates only get worse as the camp fills, so each type carries on where it last found room.
	var spots := _spots(home, front)
	var at := {}
	for type: String in spec["buildings"]:
		for k in int(spec["buildings"][type]):
			_place(m, f.id, type, spots, at)
	for type: String in spec["tiers"]:
		for b in m.buildings_of(f.id, type):
			b.tier = int(spec["tiers"][type])
	_people(m, f, home, int(spec["villagers"]))
	for st in m.buildings_of(f.id, "stable"):
		var n := int(Defs.BUILDINGS["stable"]["horse_cap"])
		for k in n:
			var h = m.spawn_unit(f.id, "horse", st.pos + Vector2.from_angle(k * TAU / n) * 3.0)
			h.stable = st.id
			h.female = k % 2 == 0
	for r in spec["stock"]:
		f.stock[r] = float(spec["stock"][r])
	f.granary = int(spec["stock"]["food"])
	f.food_state = 3
	# They know the ground they live on, so captains can find its deposits.
	for k in m.kcells_in(home, OUTSIDE):
		f.knowledge[k] = 0.0
	m._refresh_counts(f)


## A closed ring with double gates. Steep ground gets wall too, or the ring would have holes.
static func _wall(m, faction: int, home: Vector2, front: float) -> void:
	var n := ceili(TAU * WALL_R / float(Defs.BUILDINGS["stone_wall"]["length"]))
	var thick: float = Defs.BUILDINGS["stone_wall"]["thick"]
	var gates := {}
	for g in GATES:
		var first := roundi(float(g) * n / GATES)
		gates[posmod(first - 1, n)] = true
		gates[first] = true
	var line := -1
	for k in n:
		var a := home + Vector2.from_angle(front + k * TAU / n) * WALL_R
		var b := home + Vector2.from_angle(front + (k + 1) * TAU / n) * WALL_R
		var piece = m.add_building(faction, "stone_gate" if gates.has(k) else "stone_wall", (a + b) * 0.5, (b - a).angle(), false)
		piece.size = Vector2(a.distance_to(b) + 0.4, thick)
		piece.a = a
		piece.b = b
		if line < 0:
			line = piece.id
		piece.line = line
		_finish(m, piece)


## The quarry and a mine on each kind of deposit go wherever the nearest of those lies.
static func _works(m, faction: int, home: Vector2) -> void:
	_by_node(m, faction, "quarry", m.terrain.outcrops, home)
	for dep in Defs.DEPOSITS:
		_by_node(m, faction, "mine", m.terrain.deposits.filter(func(n): return n.sub == dep), home)


static func _by_node(m, faction: int, type: String, nodes: Array, home: Vector2) -> void:
	var near := nodes.duplicate()
	near.sort_custom(func(a, b): return a.pos.distance_squared_to(home) < b.pos.distance_squared_to(home))
	for node in near:
		var rot: float = (home - node.pos).angle()
		for out: float in NODE_OFFSETS:
			for k in 24:
				var p: Vector2 = node.pos + Vector2.from_angle(rot + k * TAU / 24.0) * out
				if m.site_problem(faction, type, p, rot) != "" or m._site_node(type, p) != node:
					continue
				var b = m.add_building(faction, type, p, rot, false)
				b.node = node.id
				if type == "mine":
					b.deposit = node.sub
				_finish(m, b)
				return


## Places to try, from the plaza to the wall and only then beyond it, each with its rotation.
static func _spots(home: Vector2, front: float) -> Array:
	var out := []
	var r := PLAZA
	while r <= OUTSIDE:
		if r <= WALL_R - INSIDE or r >= WALL_R + INSIDE:
			var n := ceili(TAU * r / 2.5)
			for k in n:
				var angle := front + k * TAU / n
				out.append([home + Vector2.from_angle(angle) * r, angle + PI * 0.5])
		r += 2.5
	return out


static func _place(m, faction: int, type: String, spots: Array, at: Dictionary) -> void:
	if type == "tower" and _place_tower(m, faction):
		return
	var size: Vector2 = Defs.BUILDINGS[type]["size"]
	var i: int = at.get(type, 0)
	while i < spots.size():
		var p: Vector2 = spots[i][0]
		var rot: float = spots[i][1]
		i += 1
		if not _room(m, faction, type, p, rot, size):
			continue
		_finish(m, m.add_building(faction, type, p, rot, false))
		break
	at[type] = i


## Towers stand just inside the wall, spread round it and clear of the gates.
static func _place_tower(m, faction: int) -> bool:
	var home: Vector2 = m.home_pos(faction)
	var total := int(Defs.GRAND_ARMY["buildings"]["tower"])
	var k: int = m.buildings_of(faction, "tower").size()
	var front: float = (Vector2(m.map_size, m.map_size) * 0.5 - home).angle()
	var size: Vector2 = Defs.BUILDINGS["tower"]["size"]
	for nudge in [0.0, 0.07, -0.07, 0.14, -0.14, 0.22, -0.22]:
		var angle: float = front + (k + 0.5) * TAU / total + nudge
		var p := home + Vector2.from_angle(angle) * (WALL_R - 6.5)
		# The doorway is on local +Z, so this turns it toward the camp.
		var rot := angle + PI * 0.5
		if _room(m, faction, "tower", p, rot, size):
			_finish(m, m.add_building(faction, "tower", p, rot, false))
			return true
	return false


static func _room(m, faction: int, type: String, p: Vector2, rot: float, size: Vector2) -> bool:
	if m.site_problem(faction, type, p, rot) != "":
		return false
	for b in m.buildings_of(faction, "", false):
		if b.pos.distance_squared_to(p) < 900.0 and m._obb_overlap(p, rot, size, b.pos, b.rot, b.size, LANE):
			return false
	return m.nearest_node("rock", p, size.length() * 0.5 + 4.0, func(n): return n.sub == "outcrop") == null


## Complete without the "finished" message that 300 buildings would each post.
static func _finish(m, b) -> void:
	b.complete = true
	b.paid = true
	b.progress = 1.0
	b.hp = b.max_hp
	m._block(b)


static func _people(m, f, home: Vector2, total: int) -> void:
	var have: int = m.units.filter(func(u): return u.faction == f.id and u.kind == "villager").size()
	var k := 0
	while have < total:
		k += 1
		var r := minf(5.0 + sqrt(k) * 1.8, WALL_R - INSIDE)
		var p := home + Vector2.from_angle(k * 2.39996) * r
		if m.solid_for(f.id, m.cell_of(p)):
			if k < 20000:
				continue
			p = m.cell_center(m.nearest_free_cell(f.id, m.cell_of(p)))
		var u = m.spawn_unit(f.id, "villager", p)
		u.name = m.pick_name(f)
		have += 1
