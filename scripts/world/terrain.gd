extends RefCounted
## Procedural square map in one of Defs.MAP_SIZES: heightmap, camp positions and resource nodes.
## Pure data, shared by the simulation (headless) and the renderer.

const Defs = preload("res://scripts/data/defs.gd")

const STEP := 2.0                 # metres between height samples
const FOREST_CELL := 8.0          # forest density grid
const RIM_MIN := 80.0             # a narrower rim of hills would be too steep to walk


class RNode:
	var id := 0
	var kind := ""      # tree, rock, berry, deposit, carcass
	var sub := ""       # pine/oak, boulder/outcrop, bush, bronze_ore/coal/iron_ore, deer
	var pos := Vector2.ZERO
	var amount := 0.0   # < 0 means it never runs out
	var scale := 1.0
	var rot := 0.0

	## The name shown in the world and on the map, or "" for unnamed nodes.
	func landmark_name() -> String:
		if kind == "rock" and sub == "outcrop":
			return "Stone outcrop"
		if kind == "deposit":
			var res: String = Defs.RESOURCE_NAMES[sub]
			return res.left(1).to_upper() + res.substr(1)
		return ""


var seed_value := 0
var map_id := ""
var config := {}
var size := 0.0                   # metres per side
var size_scale := 1.0             # side length relative to the largest map
var height_res := 0           # height samples per side
var forest_res := 0
var heights := PackedFloat32Array()
var forest := PackedFloat32Array()
var starts: Array[Vector2] = []
var kit := Vector2.ZERO        # how far each camp's own deposits and deer are
var nodes: Array = []           # Array[RNode]
var herds: Array = []           # {kind, pos, count}
var rng := RandomNumberGenerator.new()


func generate(seed_in: int, map_in: String = Defs.MAP_REFERENCE, settlements: int = 2) -> void:
	var camps := clampi(settlements, 2, Defs.MAX_SETTLEMENTS)
	map_id = Defs.map_for(camps, map_in)
	config = Defs.MAP_SIZES[map_id]
	size = float(config["size"])
	size_scale = size / float(Defs.MAP_SIZES[Defs.MAP_REFERENCE]["size"])
	height_res = int(size / STEP) + 1
	forest_res = int(size / FOREST_CELL)
	seed_value = seed_in
	rng.seed = seed_in
	_heights()
	kit = config["kit"]
	if camps == 2:
		_pick_starts()
	else:
		_pick_ring(camps)
	for s in starts:
		_flatten(s, 34.0, 80.0)
	_forest_map()
	_place_nodes()


# --- Height ---------------------------------------------------------------------

func _heights() -> void:
	var hills := FastNoiseLite.new()
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.seed = seed_value
	hills.frequency = 0.0021
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 5
	hills.fractal_gain = 0.45
	var ridges := FastNoiseLite.new()
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridges.seed = seed_value + 11
	ridges.frequency = 0.0042
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 4
	var mask := FastNoiseLite.new()
	mask.seed = seed_value + 23
	mask.frequency = 0.0016
	var fine := FastNoiseLite.new()
	fine.seed = seed_value + 37
	fine.frequency = 0.02
	fine.fractal_octaves = 3
	heights.resize(height_res * height_res)
	var half := size * 0.5
	var rim := 1.0 - maxf(0.2, RIM_MIN / half)
	for j in height_res:
		var z := j * STEP
		for i in height_res:
			var x := i * STEP
			var h := 22.0 + 15.0 * hills.get_noise_2d(x, z)
			var m := clampf(mask.get_noise_2d(x, z) * 1.6 + 0.1, 0.0, 1.0)
			h += 18.0 * m * maxf(0.0, ridges.get_noise_2d(x, z) + 0.15)
			h += 1.6 * fine.get_noise_2d(x, z)
			var edge := maxf(absf(x - half), absf(z - half)) / half
			h += 34.0 * smoothstep(rim, 1.0, edge)
			heights[j * height_res + i] = h


func _flatten(c: Vector2, inner: float, outer: float) -> void:
	var sum := 0.0
	var n := 0
	for a in 16:
		var p := c + Vector2.from_angle(a * TAU / 16.0) * inner * 0.6
		sum += height_at(p.x, p.y)
		n += 1
	sum += height_at(c.x, c.y)
	var target := sum / float(n + 1)
	var r := int(ceil(outer / STEP)) + 1
	var ci := int(round(c.x / STEP))
	var cj := int(round(c.y / STEP))
	for j in range(maxi(0, cj - r), mini(height_res, cj + r + 1)):
		for i in range(maxi(0, ci - r), mini(height_res, ci + r + 1)):
			var d := Vector2(i * STEP, j * STEP).distance_to(c)
			if d > outer:
				continue
			var w := 1.0 - smoothstep(inner, outer, d)
			var k := j * height_res + i
			heights[k] = lerpf(heights[k], target, w)


func _pick_starts() -> void:
	var c := Vector2(size, size) * 0.5
	var lo: float = config["margin"]
	var hi := size - lo
	var min_d: float = config["min_start"]
	var jitter := 40.0 * size_scale
	var best: Array[Vector2] = []
	var best_score := -INF
	for attempt in 80:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var side := Vector2(-dir.y, dir.x)
		var r := rng.randf_range(min_d * 0.5 + 8.0, 430.0 * size_scale)
		var a := c + dir * r + side * rng.randf_range(-jitter, jitter)
		var b := c - dir * r + side * rng.randf_range(-jitter, jitter)
		if a.x < lo or a.x > hi or a.y < lo or a.y > hi or b.x < lo or b.x > hi or b.y < lo or b.y > hi:
			continue
		if a.distance_to(b) < min_d:
			continue
		var score := -(_roughness(a) + _roughness(b)) + rng.randf() * 2.0
		if score > best_score:
			best_score = score
			best = [a, b]
	if best.is_empty():
		best = [Vector2(220, 800) * size_scale, Vector2(800, 220) * size_scale]
	starts = best


## Three or more camps stand evenly on a ring, so each has two neighbours equally far away.
func _pick_ring(camps: int) -> void:
	var c := Vector2(size, size) * 0.5
	var r: float = size * 0.5 - float(config["margin"])
	var best: Array[Vector2] = []
	var best_score := -INF
	for attempt in 80:
		var turn := rng.randf() * TAU
		var ring: Array[Vector2] = []
		var worst := 0.0
		var total := 0.0
		for k in camps:
			var p := c + Vector2.from_angle(turn + k * TAU / camps) * r
			var rough := _roughness(p)
			worst = maxf(worst, rough)
			total += rough
			ring.append(p)
		var score := -worst - total / camps + rng.randf() * 2.0
		if score > best_score:
			best_score = score
			best = ring
	# Shuffled, so a faction's number says nothing about where it starts or who its neighbours are.
	for k in range(camps - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var held := best[k]
		best[k] = best[j]
		best[j] = held
	starts = best
	var spacing := 2.0 * r * sin(PI / camps)
	kit = Vector2(minf(kit.x, spacing * 0.28), minf(kit.y, spacing * 0.45))


func _roughness(p: Vector2) -> float:
	var hs: Array[float] = []
	for a in 8:
		var q := p + Vector2.from_angle(a * TAU / 8.0) * 40.0
		hs.append(height_at(q.x, q.y))
	return hs.max() - hs.min()


func height_at(x: float, z: float) -> float:
	var fx := clampf(x / STEP, 0.0, height_res - 1.001)
	var fz := clampf(z / STEP, 0.0, height_res - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var k := j * height_res + i
	var h00 := heights[k]
	var h10 := heights[k + 1]
	var h01 := heights[k + height_res]
	var h11 := heights[k + height_res + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_deg(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


func in_bounds(p: Vector2, margin: float = 4.0) -> bool:
	return p.x >= margin and p.y >= margin and p.x <= size - margin and p.y <= size - margin


func pos3(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)


## North is -Z, east is +X.
static func direction_vector(where: String) -> Vector2:
	match where:
		"north": return Vector2(0, -1)
		"northeast": return Vector2(1, -1).normalized()
		"east": return Vector2(1, 0)
		"southeast": return Vector2(1, 1).normalized()
		"south": return Vector2(0, 1)
		"southwest": return Vector2(-1, 1).normalized()
		"west": return Vector2(-1, 0)
		"northwest": return Vector2(-1, -1).normalized()
	return Vector2.ZERO


static func compass_name(v: Vector2) -> String:
	if v.length() < 0.001:
		return "here"
	var ang := fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)
	var names := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
	return names[int(round(ang / 45.0)) % 8]


# --- Forest and resources -------------------------------------------------------

func _forest_map() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value + 51
	fn.frequency = 0.0065
	fn.fractal_octaves = 3
	forest.resize(forest_res * forest_res)
	for j in forest_res:
		for i in forest_res:
			var p := Vector2((i + 0.5) * FOREST_CELL, (j + 0.5) * FOREST_CELL)
			var d := smoothstep(0.02, 0.32, fn.get_noise_2d(p.x, p.y))
			for s in starts:
				var dist := p.distance_to(s)
				if dist < 45.0:
					d = 0.0
				elif dist < 85.0:
					d *= 0.35
			if slope_deg(p.x, p.y) > 32.0:
				d *= 0.3
			forest[j * forest_res + i] = d


func forest_at(x: float, z: float) -> float:
	var i := clampi(int(x / FOREST_CELL), 0, forest_res - 1)
	var j := clampi(int(z / FOREST_CELL), 0, forest_res - 1)
	return forest[j * forest_res + i]


func _add(kind: String, sub: String, p: Vector2, amount: float, scale: float = 1.0) -> RNode:
	var n := RNode.new()
	n.id = nodes.size()
	n.kind = kind
	n.sub = sub
	n.pos = p
	n.amount = amount
	n.scale = scale
	n.rot = rng.randf() * TAU
	nodes.append(n)
	return n


func _near_start(p: Vector2, r: float) -> bool:
	for s in starts:
		if p.distance_to(s) < r:
			return true
	return false


func _free_spot(center: Vector2, rmin: float, rmax: float, keep_clear: float = 10.0) -> Vector2:
	for attempt in 40:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not in_bounds(p, 30.0):
			continue
		if slope_deg(p.x, p.y) > 24.0:
			continue
		if _too_close_to_nodes(p, keep_clear):
			continue
		return p
	return center + Vector2.from_angle(rng.randf() * TAU) * rmax


func _too_close_to_nodes(p: Vector2, r: float) -> bool:
	for n in nodes:
		if n.kind != "tree" and n.pos.distance_to(p) < r:
			return true
	return false


func _place_nodes() -> void:
	nodes.clear()
	herds.clear()
	var k_size := size_scale
	var k_area := k_size * k_size
	# Camp essentials first, so both sides get the same kit at similar distances.
	for s in starts:
		for c in 3:
			var bp := _free_spot(s, 32.0, 62.0, 14.0)
			for k in 5:
				_add("berry", "bush", bp + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), 80.0, rng.randf_range(0.8, 1.2))
		for c in 2:
			var rp := _free_spot(s, 55.0, 100.0, 16.0)
			for k in 4:
				_add("rock", "boulder", rp + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), 120.0, rng.randf_range(0.8, 1.5))
		var op := _free_spot(s, 95.0, 140.0, 25.0)
		_add("rock", "outcrop", op, -1.0, rng.randf_range(1.0, 1.3))
		var used: Array[Vector2] = []
		for dep in Defs.DEPOSITS:
			var dp := Vector2.ZERO
			for attempt in 20:
				dp = _free_spot(s, kit.x, kit.y, 30.0)
				var ok := true
				for u in used:
					if u.distance_to(dp) < 45.0:
						ok = false
				if ok:
					break
			used.append(dp)
			_add("deposit", dep, dp, -1.0)
		# A grove close to camp, so wood is never far.
		for grove in 2:
			var gp := _free_spot(s, 48.0 + grove * 18.0, 70.0 + grove * 22.0, 5.0)
			for k in 40:
				var tp := gp + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 22.0
				_add("tree", "oak" if rng.randf() < 0.6 else "pine", tp, 40.0, rng.randf_range(0.8, 1.25))
		herds.append({"kind": "deer", "pos": _free_spot(s, kit.x + 10.0, kit.y, 5.0), "count": 5})
	# Contested deposits in the middle band between the camps.
	var duel := starts.size() == 2
	var mid := (starts[0] + starts[1]) * 0.5 if duel else Vector2(size, size) * 0.5
	var contested := 2 if duel else starts.size()
	for dep in Defs.DEPOSITS:
		for k in contested:
			_add("deposit", dep, _free_spot(mid, 40.0 * k_size, 200.0 * k_size, 40.0), -1.0)
	var inset := 120.0 * k_size
	for k in roundi(6 * k_area):
		var p := _free_spot(Vector2(rng.randf_range(inset, size - inset), rng.randf_range(inset, size - inset)), 0.0, 10.0, 30.0)
		if not _near_start(p, 180.0 * k_size):
			_add("rock", "outcrop", p, -1.0, rng.randf_range(1.0, 1.4))
	for k in roundi(45 * k_area):
		var p := Vector2(rng.randf_range(40, size - 40), rng.randf_range(40, size - 40))
		if _near_start(p, 120.0 * k_size):
			continue
		for b in rng.randi_range(2, 5):
			_add("rock", "boulder", p + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7)), 120.0, rng.randf_range(0.7, 1.6))
	for k in roundi(30 * k_area):
		var p := Vector2(rng.randf_range(60, size - 60), rng.randf_range(60, size - 60))
		if _near_start(p, 140.0 * k_size):
			continue
		for b in rng.randi_range(3, 5):
			_add("berry", "bush", p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), 80.0, rng.randf_range(0.8, 1.2))
	# Wild horses roam the middle of the map; deer are everywhere.
	for k in roundi(4 * k_size):
		var p := _free_spot(mid, 60.0 * k_size, 300.0 * k_size, 5.0)
		if _near_start(p, 230.0 * k_size):
			p = mid + Vector2.from_angle(rng.randf() * TAU) * 80.0 * k_size
		herds.append({"kind": "horse", "pos": p, "count": 6})
	for k in roundi(6 * k_area):
		var p := Vector2(rng.randf_range(100, size - 100), rng.randf_range(100, size - 100))
		if not _near_start(p, 160.0 * k_size):
			herds.append({"kind": "deer", "pos": p, "count": 5})
	# Forests.
	var tree_noise := FastNoiseLite.new()
	tree_noise.seed = seed_value + 77
	tree_noise.frequency = 0.01
	var gs := 4.2
	var n := int(size / gs)
	for j in n:
		for i in n:
			var p := Vector2((i + rng.randf()) * gs, (j + rng.randf()) * gs)
			if not in_bounds(p, 6.0):
				continue
			var d := forest_at(p.x, p.y)
			var prob := d * 0.6 + 0.012
			if rng.randf() > prob:
				continue
			if _near_start(p, 30.0):
				continue
			if slope_deg(p.x, p.y) > 34.0:
				continue
			var h := height_at(p.x, p.y)
			var pine := h > 34.0 or tree_noise.get_noise_2d(p.x, p.y) > 0.25
			_add("tree", "pine" if pine else "oak", p, 40.0, rng.randf_range(0.75, 1.3))


func count_nodes(kind: String) -> int:
	var c := 0
	for nd in nodes:
		if nd.kind == kind:
			c += 1
	return c
