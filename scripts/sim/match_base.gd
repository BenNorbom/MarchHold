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
const BLD_BUCKET := 32.0
const WILD_HORSE := 1 << 30         # in a bucket's mask, beside one bit per faction
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
	var post := -1              # the captain's post they belong to
	var captain := false
	var task := "idle"
	var phase := ""
	var tgt_node := -1
	var tgt_bld := -1
	var last_sites: Array = [] # building sites this person was last sent to
	var tgt_unit := -1
	var goal := Vector2.ZERO
	var path := PackedVector2Array()
	var path_i := 0
	var path_goal := Vector2(-1, -1)
	var carry_res := ""
	var carry := 0.0
	var weapon := ""
	var shield := ""
	var shield_up := false
	var block_t := -99.0        # when a raised shield last stopped something
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
	var path_queued := false
	var path_turn := -1         # the tick this unit's turn to find a route came up


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
	var sight_cells := PackedInt32Array()      # what it watches, worked out once


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
	var post := -1              # the post whose captain set this job, -1 for a direct order


## A captain's place and purpose. Plain data, so it can be saved.
class Post:
	var id := 0
	var faction := 0
	var name := ""
	var mandate := ""
	var center := Vector2.ZERO
	var radius := 60.0
	var captain := -1
	var target := 0             # people including the captain, 0 for everyone free
	var members: Array = []     # unit ids, longest-serving first
	var jobs := {}              # role -> crew id
	var pickers := 0            # people the bushes nearby have room for
	var pickers_t := -999.0
	var forbid := {}            # structure ids the player said not to build
	var posture := "fall_back"  # hold, or fall back when outnumbered
	var saving := {}            # {rank, cost} of the project waiting on materials
	var blocked := {}           # project -> why it hasn't started
	var walled := false
	var rng := RandomNumberGenerator.new()
	var seen := {}              # resource node ids this post has laid eyes on
	var survey_nodes: Array = []
	var surveying := false
	var rounds := 0
	var works_t := -999.0       # when the captain last looked at what to build
	var alert := ""             # intruder, raid or falling_back
	var alert_t := -999.0       # when the threat was last seen
	var threat := 0             # the most seen at once during this alert
	var threat_at := Vector2.ZERO
	var refuge := Vector2.ZERO
	var lost := 0
	var lost_at_alert := 0
	var blocked_since := {}     # project -> when it was first held up
	var blocked_told := {}
	var ready_told := false


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
	var mark_t := -999.0
	var has_mark := false
	var places := {}            # lower-case name -> {name, pos}
	var reserve := {}           # resource -> what captains must leave. Stores are shared, so it's per side.
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
## Work people were pulled off by a military order: unit id -> {group, steps, loop}. Empty steps = was idle.
var work_memory := {}
var posts := {}
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
# With three or more settlements each has its own share of the routes and its own queue.
var fair_paths := false
var path_queues: Array = []          # faction -> unit ids waiting, longest first
var paths_left := PackedInt32Array()
var path_granted := false
var ulist: Array = []
var uhead := PackedInt32Array()
var unext := PackedInt32Array()
var node_buckets: Array = []
var kind_buckets := {}               # node kind -> bucket -> node ids, or null where there are none
var uside := PackedInt32Array()      # unit bucket -> which sides have someone in it
var bld_buckets := {}                # cell -> buildings centred there, oldest first
var own_blds: Array = []             # faction -> its buildings, oldest first
var own_by_type: Array = []          # faction -> type -> the same


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
	kind_buckets.clear()
	for n in terrain.nodes:
		_bucket_node(n)
	uhead.resize(bucket_n * bucket_n)
	uhead.fill(-1)
	uside.resize(bucket_n * bucket_n)
	uside.fill(0)
	bld_buckets.clear()
	fair_paths = faction_count > 2
	path_queues.clear()
	paths_left.resize(faction_count)
	paths_left.fill(MAX_PATHS_PER_TICK / faction_count)
	own_blds.clear()
	own_by_type.clear()
	for f in faction_count:
		path_queues.append([])
		own_blds.append([])
		own_by_type.append({})


func _bucket_node(n) -> void:
	var bi := clampi(int(n.pos.x / NODE_BUCKET), 0, node_bucket_n - 1)
	var bj := clampi(int(n.pos.y / NODE_BUCKET), 0, node_bucket_n - 1)
	var arr: PackedInt32Array = node_buckets[bj * node_bucket_n + bi]
	arr.append(n.id)
	node_buckets[bj * node_bucket_n + bi] = arr
	if not kind_buckets.has(n.kind):
		var empty := []
		empty.resize(node_bucket_n * node_bucket_n)
		kind_buckets[n.kind] = empty
	var of_kind: Array = kind_buckets[n.kind]
	if of_kind[bj * node_bucket_n + bi] == null:
		of_kind[bj * node_bucket_n + bi] = []
	of_kind[bj * node_bucket_n + bi].append(n.id)


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
	if not f.names_used.has(base):
		f.names_used[base] = 1
		return base
	# The count survives deaths, so a name never comes back for someone else.
	var nth := int(f.names_used[base]) - 1
	f.names_used[base] = nth + 2
	var full := "%s %s" % [base, Defs.BYNAMES[nth % Defs.BYNAMES.size()]]
	for lap in nth / Defs.BYNAMES.size():
		full += " the Younger"
	return full


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
			u.weapon = "wood_spear"
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
	_index_building(b)
	if complete:
		_block(b)
	emit({"type": "building", "id": b.id})
	return b


func remove_building(b: Building, reason: String = "") -> void:
	if b.dead:
		return
	b.dead = true
	_unindex_building(b)
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


func _bld_bucket(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / BLD_BUCKET)), int(floor(p.y / BLD_BUCKET)))


func _index_building(b: Building) -> void:
	var k := _bld_bucket(b.pos)
	if not bld_buckets.has(k):
		bld_buckets[k] = []
	bld_buckets[k].append(b)
	own_blds[b.faction].append(b)
	var typed: Dictionary = own_by_type[b.faction]
	if not typed.has(b.type):
		typed[b.type] = []
	typed[b.type].append(b)


func _unindex_building(b: Building) -> void:
	var k := _bld_bucket(b.pos)
	if bld_buckets.has(k):
		bld_buckets[k].erase(b)
	own_blds[b.faction].erase(b)
	own_by_type[b.faction].get(b.type, []).erase(b)


## Living buildings centred within r of p that aren't this faction's, oldest first.
func foreign_buildings_near(faction: int, p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	var k0 := _bld_bucket(p - Vector2(r, r))
	var k1 := _bld_bucket(p + Vector2(r, r))
	for j in range(k0.y, k1.y + 1):
		for i in range(k0.x, k1.x + 1):
			var list = bld_buckets.get(Vector2i(i, j))
			if list == null:
				continue
			for b: Building in list:
				if b.faction != faction and b.pos.distance_squared_to(p) <= r2:
					out.append(b)
	if out.size() > 1:
		out.sort_custom(func(a, b): return a.id < b.id)
	return out


func buildings_of(faction: int, type: String = "", complete_only: bool = true) -> Array:
	var list: Array = own_blds[faction] if type == "" else own_by_type[faction].get(type, [])
	var out := []
	for b: Building in list:
		if b.complete or not complete_only:
			out.append(b)
	return out


func has_building(faction: int, type: String) -> bool:
	for b: Building in own_by_type[faction].get(type, []):
		if b.complete:
			return true
	return false


func home_of(faction: int) -> Building:
	var fires: Array = own_by_type[faction].get("campfire", [])
	return fires[0] if not fires.is_empty() else null


func home_pos(faction: int) -> Vector2:
	var h := home_of(faction)
	return h.pos if h else fac(faction).start


func nearest_building(faction: int, p: Vector2, types: Array, complete_only: bool = true) -> Building:
	if faction < 0:
		return null
	var one := types.size() == 1
	var list: Array = own_by_type[faction].get(types[0], []) if one else own_blds[faction]
	var best: Building = null
	var bd := INF
	for b: Building in list:
		if complete_only and not b.complete:
			continue
		if not one and not types.is_empty() and not b.type in types:
			continue
		var d := b.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## Nearest place to drop a resource: campfire or stockpile.
func nearest_dropoff(faction: int, p: Vector2, _res: String) -> Building:
	return nearest_building(faction, p, ["campfire", "stockpile"])


func dropoffs(faction: int, _res: String) -> Array:
	return buildings_of(faction).filter(func(b): return b.type in ["campfire", "stockpile"])


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
	# solid_for and cell_of written out, as this runs for every metre of every route.
	var grid: AStarGrid2D = blocking.grid
	var gates: Dictionary = blocking.open_gates[maxi(faction, 0)]
	var top := grid_n - 1
	var steps := int(len / (CELL * 0.5)) + 1
	var last := Vector2i(-1, -1)
	for s in steps + 1:
		var p := a + d * (float(s) / steps)
		var c := Vector2i(clampi(int(p.x / CELL), 0, top), clampi(int(p.y / CELL), 0, top))
		if c == last:
			continue
		last = c
		if grid.is_point_solid(c) and not gates.has(c):
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
	if fair_paths:
		if not path_granted:
			if paths_left[pf] <= 0:
				return PackedVector2Array()
			paths_left[pf] -= 1
	elif paths_this_tick >= MAX_PATHS_PER_TICK:
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


## Deals out the tick's routes: an equal share for each living settlement, the remainder
## taking turns, and within a settlement whoever has waited longest goes first.
func share_paths() -> void:
	var alive := []
	for f: Faction in factions:
		paths_left[f.id] = 0
		if f.alive:
			alive.append(f.id)
		else:
			path_queues[f.id].clear()
	var n := alive.size()
	if n == 0:
		return
	for i in n:
		var id: int = alive[i]
		var share := MAX_PATHS_PER_TICK / n + (1 if (i + ticks) % n < MAX_PATHS_PER_TICK % n else 0)
		var queue: Array = path_queues[id]
		while share > 0 and not queue.is_empty():
			var u := unit(queue.pop_front())
			if u == null:
				continue
			u.path_queued = false
			if u.dead:
				continue
			u.path_turn = ticks
			share -= 1
		paths_left[id] = share


## A route for a unit, or nothing while it waits its turn.
func route_for(u: Unit, goal: Vector2) -> PackedVector2Array:
	if not fair_paths:
		return find_path(u.faction, u.pos, goal)
	if u.path_queued:
		return PackedVector2Array()
	path_granted = u.path_turn == ticks
	u.path_turn = -1
	var out := find_path(u.faction, u.pos, goal)
	path_granted = false
	if out.is_empty() and u.faction >= 0:
		u.path_queued = true
		path_queues[u.faction].append(u.id)
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
	uside.fill(0)
	for u: Unit in units:
		if not u.dead:
			ulist.append(u)
	unext.resize(ulist.size())
	for i in ulist.size():
		var u: Unit = ulist[i]
		var p: Vector2 = u.pos
		var bi := clampi(int(p.x / BUCKET), 0, bucket_n - 1)
		var bj := clampi(int(p.y / BUCKET), 0, bucket_n - 1)
		var k := bj * bucket_n + bi
		unext[i] = uhead[k]
		uhead[k] = i
		if u.kind == "horse":
			if u.faction < 0:
				uside[k] |= WILD_HORSE
		elif u.faction >= 0:
			uside[k] |= 1 << u.faction


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


## A quick look at the buckets: false means none of those sides is within r of p.
func sides_near(p: Vector2, r: float, sides: int) -> bool:
	var last := bucket_n - 1
	var i0 := clampi(int((p.x - r) / BUCKET), 0, last)
	var i1 := clampi(int((p.x + r) / BUCKET), 0, last)
	for bj in range(clampi(int((p.y - r) / BUCKET), 0, last), clampi(int((p.y + r) / BUCKET), 0, last) + 1):
		var row := bj * bucket_n
		for k in range(row + i0, row + i1 + 1):
			if uside[k] & sides:
				return true
	return false


## The bits of every faction but this one.
func rivals_mask(faction: int) -> int:
	var all := (1 << factions.size()) - 1
	return all if faction < 0 else all & ~(1 << faction)


func nearest_enemy(p: Vector2, r: float, faction: int, filter: Callable = Callable()) -> Unit:
	var rivals := rivals_mask(faction)
	if not sides_near(p, r, rivals):
		return null
	var best: Unit = null
	var bd := INF
	var r2 := r * r
	var filtered := filter.is_valid()
	var last := bucket_n - 1
	var i0 := clampi(int((p.x - r) / BUCKET), 0, last)
	var i1 := clampi(int((p.x + r) / BUCKET), 0, last)
	for bj in range(clampi(int((p.y - r) / BUCKET), 0, last), clampi(int((p.y + r) / BUCKET), 0, last) + 1):
		var row := bj * bucket_n
		for k in range(row + i0, row + i1 + 1):
			if uside[k] & rivals == 0:
				continue
			var i := uhead[k]
			while i != -1:
				var u: Unit = ulist[i]
				i = unext[i]
				if u.faction == faction or u.faction < 0 or u.dead or u.stable >= 0:
					continue
				var d := u.pos.distance_squared_to(p)
				if d > r2 or d >= bd or u.kind == "horse" or u.kind == "deer":
					continue
				if filtered and not filter.call(u):
					continue
				bd = d
				best = u
	return best


func nearest_node(kind: String, p: Vector2, maxr: float, filter: Callable = Callable()):
	var best = null
	if not kind_buckets.has(kind):
		return null
	var of_kind: Array = kind_buckets[kind]
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
				var ids = of_kind[bj * node_bucket_n + bi]
				if ids == null:
					continue
				for nid in ids:
					var n = terrain.nodes[nid]
					if n.amount == 0.0:
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
