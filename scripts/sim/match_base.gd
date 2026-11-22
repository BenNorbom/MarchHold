extends RefCounted
## Authoritative match state and shared helpers. Nothing here touches nodes or
## rendering, so the whole simulation runs headless for tests and AI training.

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Blocking = preload("res://scripts/sim/blocking.gd")

const CELL := 2.0                    # path grid cell in metres
const KCELL := 8.0                   # knowledge grid cell in metres
const BUCKET := 16.0
const NODE_BUCKET := 32.0
const STEEP := 38.0
const MAX_PATHS_PER_TICK := 14

enum Anim { IDLE, WALK, RUN, CHOP, HAMMER, DIG, PICK, MELEE, SHOOT, CARRY, RIDE, DEAD, LOAD }


class Unit:
	var id := 0
	var faction := 0
	var kind := "villager"      # villager, commander, horse, deer, cannon, ram
	var name := ""
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var facing := 0.0
	var hp := 50.0
	var max_hp := 50.0
	var child := false
	var born := 0.0
	var female := false
	var crew := -1
	var captain := false
	var task := "idle"
	var phase := ""
	var tgt_node := -1
	var tgt_bld := -1
	var tgt_unit := -1
	var goal := Vector2.ZERO
	var path := PackedVector2Array()
	var path_i := 0
	var path_goal := Vector2(-1, -1)
	var carry_res := ""
	var carry := 0.0
	var weapon := ""
	var shield := ""
	var armor := ""
	var bow := false
	var arrows := 0
	var mounted := false
	var cooldown := 0.0
	var work_t := 0.0
	var anim := 0
	var anim_t := 0.0
	var flee_t := 0.0
	var enemy := -1
	var enemy_bld := -1
	var hit_t := -99.0
	var attacker := -1
	var seen := {}              # scouts: knowledge cell -> time seen
	var sightings := {}         # scouts: intel key -> entry
	var scout_dir := Vector2.ZERO
	var scout_leg := 0
	var siege := -1             # villager: engine it crews. engine: unused
	var crew_ids: Array = []    # engine: crew unit ids
	var ammo := 0               # engine: shot loaded / carried
	var team := false           # engine: horse team attached
	var herd := -1
	var driver := -1            # horse: villager driving it in
	var stable := -1            # horse: stable it lives in
	var gestation := 0.0
	var dead := false
	var dead_t := 0.0
	var charge_start := Vector2.ZERO
	var slot := Vector2.ZERO    # formation offset
	var stuck := 0.0
	var last_pos := Vector2.ZERO
	var reload := 0.0
	var in_tower := -1


class Building:
	var id := 0
	var faction := 0
	var type := ""
	var pos := Vector2.ZERO
	var rot := 0.0
	var size := Vector2(4, 4)
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var progress := 0.0
	var work := 0.0
	var hp := 1.0
	var max_hp := 1.0
	var complete := false
	var paid := false
	var tier := 0
	var upgrading := ""
	var up_work := 0.0
	var up_paid := false
	var research := ""
	var research_t := 0.0
	var node := -1
	var deposit := ""
	var cells := PackedInt32Array()
	var blocking := false
	var dead := false
	var workers := 0
	var alarm_t := -99.0
	var waiting_msg_t := -99.0
	var line := -1


class Crew:
	var id := 0
	var faction := 0
	var members: Array = []
	var leader := -1
	var captain := false
	var steps: Array = []
	var idx := 0
	var state := {}
	var start_size := 0
	var lost := 0
	var done := false
	var loop := false
	var origin := Vector2.ZERO


class Faction:
	var id := 0
	var name := ""
	var commander_name := ""
	var short_name := ""
	var alive := true
	var out_t := -1.0
	var color := Color.WHITE
	var stock := {}
	var gear := {}
	var age := 0
	var researched := {}
	var start := Vector2.ZERO
	var commander := -1
	var food_state := 2
	var knowledge := PackedFloat32Array()
	var visible := PackedByteArray()
	var intel := {}
	var reports: Array = []
	var names_used := {}
	var births := 0
	var deaths := 0
	var kills := 0
	var alarm_t := -99.0
	var attack_msg_t := -99.0
	var is_ai := false
	var mark := Vector2.ZERO
	var has_mark := false
	var pop := 0
	var adults := 0
	var children := 0
	var housing := 0
	var food_cap := 0
	var idle := 0
	var soldiers := 0
	var horses := 0
	var age_t: Array = [0.0, -1.0, -1.0, -1.0, -1.0]
	var hints := {}


class Shot:
	var kind := "arrow"         # arrow, ball
	var faction := 0
	var shooter := -1
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var t := 0.0
	var dur := 1.0
	var target := -1
	var target_bld := -1
	var hits := false
	var dmg := 0.0
	var free := false           # physically simulated (fired by a commander)
	var dead := false


var terrain: Terrain
var map_size := 0.0
# Cells per side of each grid, set from the map size.
var grid_n := 0                      # pathing
var kres := 0                        # knowledge
var bucket_n := 0                    # unit hash
var node_bucket_n := 0               # resource node hash
var t := 0.0
var ticks := 0
var rng := RandomNumberGenerator.new()
var units: Array = []
var unit_by_id := {}
var buildings: Array = []
var bld_by_id := {}
var crews := {}
var factions: Array = []
var shots: Array = []
var messages: Array = []
var events: Array = []
var next_id := 1
var over := false
var winner := -1
var end_reason := ""
var options := {}
var blocking: Blocking
var terrain_solid := PackedByteArray()
var paths_this_tick := 0
var ulist: Array = []
var uhead := PackedInt32Array()
var unext := PackedInt32Array()
var node_buckets: Array = []


# --- Setup ------------------------------------------------------------------------

func _init_world(tr: Terrain, faction_count: int) -> void:
	terrain = tr
	map_size = tr.size
	grid_n = int(map_size / CELL)
	kres = int(map_size / KCELL)
	bucket_n = int(map_size / BUCKET)
	node_bucket_n = int(map_size / NODE_BUCKET)
	terrain_solid.resize(grid_n * grid_n)
	for j in grid_n:
		for i in grid_n:
			var p := Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)
			var solid := terrain.slope_deg(p.x, p.y) > STEEP or not terrain.in_bounds(p, 3.0)
			terrain_solid[j * grid_n + i] = 1 if solid else 0
	blocking = Blocking.new()
	blocking.setup(grid_n, terrain_solid, faction_count)
	node_buckets.clear()
	node_buckets.resize(node_bucket_n * node_bucket_n)
	for k in node_bucket_n * node_bucket_n:
		node_buckets[k] = PackedInt32Array()
	for n in terrain.nodes:
		_bucket_node(n)
	uhead.resize(bucket_n * bucket_n)
	uhead.fill(-1)


func _bucket_node(n) -> void:
	var bi := clampi(int(n.pos.x / NODE_BUCKET), 0, node_bucket_n - 1)
	var bj := clampi(int(n.pos.y / NODE_BUCKET), 0, node_bucket_n - 1)
	var arr: PackedInt32Array = node_buckets[bj * node_bucket_n + bi]
	arr.append(n.id)
	node_buckets[bj * node_bucket_n + bi] = arr


func new_id() -> int:
	next_id += 1
	return next_id


func fac(id: int) -> Faction:
	return factions[id] if id >= 0 and id < factions.size() else null


func unit(id: int) -> Unit:
	return unit_by_id.get(id)


func bld(id: int) -> Building:
	return bld_by_id.get(id)


func post(faction: int, text: String, kind: String = "info") -> void:
	messages.append({"t": t, "faction": faction, "text": text, "kind": kind})


func emit(ev: Dictionary) -> void:
	if events.size() < 4000:
		events.append(ev)


func sound(name: String, p: Vector2, faction: int = -1) -> void:
	emit({"type": "sound", "name": name, "pos": p, "faction": faction})


func pick_name(f: Faction) -> String:
	for attempt in 12:
		var n: String = Defs.NAMES[rng.randi_range(0, Defs.NAMES.size() - 1)]
		if not f.names_used.has(n):
			f.names_used[n] = 1
			return n
	var base: String = Defs.NAMES[rng.randi_range(0, Defs.NAMES.size() - 1)]
	f.names_used[base] = int(f.names_used.get(base, 1)) + 1
	return "%s %d" % [base, f.names_used[base]]


# --- Entities ------------------------------------------------------------------------

func spawn_unit(faction: int, kind: String, p: Vector2) -> Unit:
	var u := Unit.new()
	u.id = new_id()
	u.faction = faction
	u.kind = kind
	u.pos = p
	u.prev = p
	u.last_pos = p
	u.born = t
	u.facing = rng.randf() * TAU
	match kind:
		"villager":
			u.max_hp = Defs.VILLAGER["hp"]
			u.female = rng.randf() < 0.5
		"commander":
			u.max_hp = Defs.COMMANDER["hp"]
			u.weapon = "club"
		"horse":
			u.max_hp = 60.0
			u.female = rng.randf() < 0.5
		"deer":
			u.max_hp = 25.0
		"cannon":
			u.max_hp = Defs.CANNON["hp"]
		"ram":
			u.max_hp = Defs.RAM["hp"]
	u.hp = u.max_hp
	units.append(u)
	unit_by_id[u.id] = u
	return u


func is_person(u: Unit) -> bool:
	return u.kind == "villager" or u.kind == "commander"


func add_building(faction: int, type: String, p: Vector2, rot: float, complete: bool = false) -> Building:
	var d: Dictionary = Defs.BUILDINGS[type]
	var b := Building.new()
	b.id = new_id()
	b.faction = faction
	b.type = type
	b.pos = p
	b.rot = rot
	if d.get("wall", false):
		b.size = Vector2(d["length"], d["thick"])
	else:
		b.size = d["size"]
	b.max_hp = float(d["hp"])
	b.hp = b.max_hp * (1.0 if complete else 0.05)
	if complete:
		b.complete = true
		b.progress = 1.0
		b.paid = true
	buildings.append(b)
	bld_by_id[b.id] = b
	if complete:
		_block(b)
	emit({"type": "building", "id": b.id})
	return b


func remove_building(b: Building, reason: String = "") -> void:
	if b.dead:
		return
	b.dead = true
	_unblock(b)
	emit({"type": "building_gone", "id": b.id, "reason": reason})
	for u: Unit in units:
		if u.tgt_bld == b.id:
			u.tgt_bld = -1
			u.phase = ""
		if u.enemy_bld == b.id:
			u.enemy_bld = -1
		if u.in_tower == b.id:
			u.in_tower = -1


func buildings_of(faction: int, type: String = "", complete_only: bool = true) -> Array:
	var out := []
	for b: Building in buildings:
		if b.dead or b.faction != faction:
			continue
		if type != "" and b.type != type:
			continue
		if complete_only and not b.complete:
			continue
		out.append(b)
	return out


func has_building(faction: int, type: String) -> bool:
	for b: Building in buildings:
		if not b.dead and b.faction == faction and b.type == type and b.complete:
			return true
	return false


func home_of(faction: int) -> Building:
	for b: Building in buildings:
		if not b.dead and b.faction == faction and b.type == "campfire":
			return b
	return null


func home_pos(faction: int) -> Vector2:
	var h := home_of(faction)
	return h.pos if h else fac(faction).start


func nearest_building(faction: int, p: Vector2, types: Array, complete_only: bool = true) -> Building:
	var best: Building = null
	var bd := INF
	for b: Building in buildings:
		if b.dead or b.faction != faction:
			continue
		if complete_only and not b.complete:
			continue
		if not types.is_empty() and not b.type in types:
			continue
		var d := b.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## Nearest place to drop a resource: campfire or stockpile, plus granary / lodge for food.
func nearest_dropoff(faction: int, p: Vector2, res: String) -> Building:
	var types := ["campfire", "stockpile"]
	if res == "food":
		types += ["granary", "lodge"]
	return nearest_building(faction, p, types)


# --- Grid and pathing ----------------------------------------------------------------

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, grid_n - 1), clampi(int(p.y / CELL), 0, grid_n - 1))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func solid_for(faction: int, c: Vector2i) -> bool:
	return blocking.is_solid(faction, c)


func line_clear(faction: int, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return true
	var steps := int(len / (CELL * 0.5)) + 1
	var last := Vector2i(-1, -1)
	for s in steps + 1:
		var c := cell_of(a + d * (float(s) / steps))
		if c == last:
			continue
		last = c
		if solid_for(faction, c):
			return false
	return true


func nearest_free_cell(faction: int, c: Vector2i, maxr: int = 12) -> Vector2i:
	if not solid_for(faction, c):
		return c
	for r in range(1, maxr + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if not solid_for(faction, q):
					return q
	return c


## Returns waypoints from a to b. Straight line when nothing is in the way.
func find_path(faction: int, a: Vector2, b: Vector2) -> PackedVector2Array:
	var pf := maxi(faction, 0)
	if line_clear(pf, a, b):
		return PackedVector2Array([b])
	if paths_this_tick >= MAX_PATHS_PER_TICK:
		return PackedVector2Array()
	paths_this_tick += 1
	var ca := nearest_free_cell(pf, cell_of(a))
	var cb := nearest_free_cell(pf, cell_of(b), 20)
	var ids: Array[Vector2i] = blocking.route(pf, ca, cb)
	var out := PackedVector2Array()
	if ids.is_empty():
		return PackedVector2Array([b])
	# String-pull: keep a waypoint only when the straight line to the next breaks.
	var anchor := a
	var i := 1
	while i < ids.size():
		var p := cell_center(ids[i])
		if i == ids.size() - 1:
			out.append(p)
			break
		var nxt := cell_center(ids[i + 1])
		if not line_clear(pf, anchor, nxt):
			out.append(p)
			anchor = p
		i += 1
	if out.is_empty() or out[out.size() - 1].distance_to(b) > CELL * 1.5:
		if not solid_for(pf, cell_of(b)):
			out.append(b)
	return out


func _cells_of(b: Building) -> PackedInt32Array:
	var out := PackedInt32Array()
	var half := b.size * 0.5 + Vector2(0.4, 0.4)
	var r := half.length()
	var c0 := cell_of(b.pos - Vector2(r, r))
	var c1 := cell_of(b.pos + Vector2(r, r))
	var ax := Vector2.from_angle(b.rot)
	var az := Vector2(-ax.y, ax.x)
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var d := cell_center(Vector2i(i, j)) - b.pos
			if absf(d.dot(ax)) <= half.x and absf(d.dot(az)) <= half.y:
				out.append(j * grid_n + i)
	return out


func _block(b: Building) -> void:
	if b.blocking or b.dead:
		return
	var d: Dictionary = Defs.BUILDINGS[b.type]
	if d.get("walkable", false):
		return
	b.cells = _cells_of(b)
	b.blocking = true
	blocking.add(b.cells, _gate_owner(b))
	# Anyone standing inside steps out.
	for u: Unit in units:
		if u.dead:
			continue
		var cu := cell_of(u.pos)
		if b.cells.has(cu.y * grid_n + cu.x):
			var f := maxi(u.faction, 0)
			u.pos = cell_center(nearest_free_cell(f, cu))
			u.prev = u.pos
			u.path = PackedVector2Array()


func _unblock(b: Building) -> void:
	if not b.blocking:
		return
	b.blocking = false
	blocking.remove(b.cells, _gate_owner(b))


func _gate_owner(b: Building) -> int:
	return b.faction if Defs.BUILDINGS[b.type].get("gate", false) else Blocking.NOT_A_GATE


# --- Spatial queries ------------------------------------------------------------------

func rebuild_unit_hash() -> void:
	ulist.clear()
	uhead.fill(-1)
	for u: Unit in units:
		if not u.dead:
			ulist.append(u)
	unext.resize(ulist.size())
	for i in ulist.size():
		var p: Vector2 = ulist[i].pos
		var bi := clampi(int(p.x / BUCKET), 0, bucket_n - 1)
		var bj := clampi(int(p.y / BUCKET), 0, bucket_n - 1)
		var k := bj * bucket_n + bi
		unext[i] = uhead[k]
		uhead[k] = i


## Living units within r of p. faction_mode: -2 any, -3 enemies of `of` (people/siege only), or a faction id.
func units_near(p: Vector2, r: float, faction_mode: int = -2, of: int = -1) -> Array:
	var out := []
	var r2 := r * r
	var b0 := Vector2i(clampi(int((p.x - r) / BUCKET), 0, bucket_n - 1), clampi(int((p.y - r) / BUCKET), 0, bucket_n - 1))
	var b1 := Vector2i(clampi(int((p.x + r) / BUCKET), 0, bucket_n - 1), clampi(int((p.y + r) / BUCKET), 0, bucket_n - 1))
	for bj in range(b0.y, b1.y + 1):
		for bi in range(b0.x, b1.x + 1):
			var i := uhead[bj * bucket_n + bi]
			while i != -1:
				var u: Unit = ulist[i]
				i = unext[i]
				if u.dead or u.pos.distance_squared_to(p) > r2:
					continue
				if faction_mode == -3:
					if u.faction < 0 or u.faction == of or u.kind == "horse" or u.kind == "deer":
						continue
				elif faction_mode >= -1 and u.faction != faction_mode:
					continue
				out.append(u)
	return out


func nearest_enemy(p: Vector2, r: float, faction: int, filter: Callable = Callable()) -> Unit:
	var best: Unit = null
	var bd := INF
	for u: Unit in units_near(p, r, -3, faction):
		if u.stable >= 0:
			continue
		if filter.is_valid() and not filter.call(u):
			continue
		var d := u.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = u
	return best


func nearest_node(kind: String, p: Vector2, maxr: float, filter: Callable = Callable()):
	var best = null
	var bd := maxr * maxr
	var ring := int(ceil(maxr / NODE_BUCKET))
	var bc := Vector2i(clampi(int(p.x / NODE_BUCKET), 0, node_bucket_n - 1), clampi(int(p.y / NODE_BUCKET), 0, node_bucket_n - 1))
	for r in ring + 1:
		# Stop early once a ring can't hold anything nearer than the best so far.
		if best != null and (r - 1) * NODE_BUCKET > sqrt(bd):
			break
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var bi := bc.x + dx
				var bj := bc.y + dy
				if bi < 0 or bj < 0 or bi >= node_bucket_n or bj >= node_bucket_n:
					continue
				for nid in node_buckets[bj * node_bucket_n + bi]:
					var n = terrain.nodes[nid]
					if n.kind != kind or n.amount == 0.0:
						continue
					var d: float = n.pos.distance_squared_to(p)
					if d >= bd:
						continue
					if filter.is_valid() and not filter.call(n):
						continue
					bd = d
					best = n
	return best


func add_carcass(p: Vector2, food: float) -> void:
	var n := Terrain.RNode.new()
	n.id = terrain.nodes.size()
	n.kind = "carcass"
	n.sub = "deer"
	n.pos = p
	n.amount = food
	n.rot = rng.randf() * TAU
	terrain.nodes.append(n)
	_bucket_node(n)
	emit({"type": "node_new", "id": n.id})


func take_from_node(n, want: float) -> float:
	if n.amount < 0.0:
		return want
	var got := minf(want, n.amount)
	n.amount -= got
	if n.amount <= 0.001:
		n.amount = 0.0
		emit({"type": "node_gone", "id": n.id})
	return got


# --- Knowledge -----------------------------------------------------------------------

func kcell(p: Vector2) -> int:
	var i := clampi(int(p.x / KCELL), 0, kres - 1)
	var j := clampi(int(p.y / KCELL), 0, kres - 1)
	return j * kres + i


func kcells_in(p: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i0 := clampi(int((p.x - r) / KCELL), 0, kres - 1)
	var i1 := clampi(int((p.x + r) / KCELL), 0, kres - 1)
	var j0 := clampi(int((p.y - r) / KCELL), 0, kres - 1)
	var j1 := clampi(int((p.y + r) / KCELL), 0, kres - 1)
	var r2 := r * r
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var c := Vector2((i + 0.5) * KCELL, (j + 0.5) * KCELL)
			if c.distance_squared_to(p) <= r2:
				out.append(j * kres + i)
	return out


# --- Placement rules ------------------------------------------------------------------

func _corners(p: Vector2, rot: float, size: Vector2) -> Array:
	var ax := Vector2.from_angle(rot) * size.x * 0.5
	var az := Vector2.from_angle(rot + PI * 0.5) * size.y * 0.5
	return [p + ax + az, p + ax - az, p - ax - az, p - ax + az]


func _obb_overlap(p1: Vector2, r1: float, s1: Vector2, p2: Vector2, r2: float, s2: Vector2, pad: float) -> bool:
	var c1 := _corners(p1, r1, s1 + Vector2(pad, pad))
	var c2 := _corners(p2, r2, s2)
	for axis in [Vector2.from_angle(r1), Vector2.from_angle(r1 + PI * 0.5), Vector2.from_angle(r2), Vector2.from_angle(r2 + PI * 0.5)]:
		var mn1 := INF
		var mx1 := -INF
		var mn2 := INF
		var mx2 := -INF
		for c in c1:
			var v: float = c.dot(axis)
			mn1 = minf(mn1, v)
			mx1 = maxf(mx1, v)
		for c in c2:
			var v: float = c.dot(axis)
			mn2 = minf(mn2, v)
			mx2 = maxf(mx2, v)
		if mx1 < mn2 or mx2 < mn1:
			return false
	return true


## Why a structure can't be placed here, or "" when it can.
func site_problem(faction: int, type: String, p: Vector2, rot: float, size_override: Vector2 = Vector2.ZERO) -> String:
	if not Defs.BUILDINGS.has(type):
		return "Unknown structure."
	var d: Dictionary = Defs.BUILDINGS[type]
	var size: Vector2 = size_override if size_override != Vector2.ZERO else (Vector2(d["length"], d["thick"]) if d.get("wall", false) else d["size"])
	if not terrain.in_bounds(p, 12.0):
		return "Too close to the edge of the land."
	var hs: Array[float] = [terrain.height_at(p.x, p.y)]
	for c in _corners(p, rot, size):
		hs.append(terrain.height_at(c.x, c.y))
	var limit := 4.5 if d.get("wall", false) else (4.0 if type == "farm" else 3.0)
	if hs.max() - hs.min() > limit:
		return "The ground here is too steep."
	var is_wall: bool = d.get("wall", false)
	for b: Building in buildings:
		if b.dead or b.pos.distance_to(p) > 40.0:
			continue
		var other_wall: bool = Defs.BUILDINGS[b.type].get("wall", false)
		var pad := 0.0 if (is_wall and (other_wall or b.type == "tower")) or (b.type == "farm" and type == "farm") else 1.0
		if is_wall and other_wall:
			# Wall pieces may meet end to end but not stack on top of each other.
			if b.pos.distance_to(p) < minf(b.size.x, size.x) * 0.45:
				return "There's already a wall here."
			continue
		if _obb_overlap(p, rot, size, b.pos, b.rot, b.size, pad):
			return "Too close to the %s." % Defs.building_name(b.type).to_lower()
	for u: Unit in units:
		if not u.dead and u.kind in ["cannon", "ram"] and u.pos.distance_to(p) < 3.0:
			return "Something is in the way."
	if d.has("near"):
		var want: String = d["near"]
		var nd = _site_node(type, p)
		if nd == null:
			return "Build the quarry next to a rock outcrop." if want == "outcrop" else "Build the mine on a bronze ore, coal or iron ore deposit."
		if type == "mine":
			for b: Building in buildings:
				if not b.dead and b.type == "mine" and b.node == nd.id:
					return "That deposit already has a mine."
	return ""


func _site_node(type: String, p: Vector2):
	var d: Dictionary = Defs.BUILDINGS[type]
	if not d.has("near"):
		return null
	var r: float = d["near_dist"]
	if d["near"] == "outcrop":
		return nearest_node("rock", p, r, func(n): return n.sub == "outcrop")
	return nearest_node("deposit", p, r)


## Why the faction can't build this type yet, or "".
func unlock_problem(faction: int, type: String) -> String:
	var f := fac(faction)
	var d: Dictionary = Defs.BUILDINGS.get(type, {})
	if d.is_empty() or not d.get("buildable", true):
		return "That can't be built."
	if f.age < int(d["age"]):
		return "Needs the %s age: %s" % [Defs.AGES[d["age"]], Defs.AGE_HOW[d["age"]].to_lower()]
	if type == "university" and not has_building(faction, "smelter"):
		return "Needs a smelter."
	return ""


func missing_cost(faction: int, cost: Dictionary) -> Dictionary:
	var f := fac(faction)
	var miss := {}
	for r in cost:
		var have := float(f.stock.get(r, 0.0))
		if have + 0.0001 < float(cost[r]):
			miss[r] = int(ceil(float(cost[r]) - have))
	return miss


func can_afford(faction: int, cost: Dictionary) -> bool:
	return missing_cost(faction, cost).is_empty()


func pay(faction: int, cost: Dictionary) -> bool:
	if not can_afford(faction, cost):
		return false
	var f := fac(faction)
	for r in cost:
		f.stock[r] = float(f.stock.get(r, 0.0)) - float(cost[r])
	return true


func add_stock(faction: int, res: String, amount: float) -> void:
	var f := fac(faction)
	var v := float(f.stock.get(res, 0.0)) + amount
	if res == "food":
		v = minf(v, float(f.food_cap))
	f.stock[res] = v
