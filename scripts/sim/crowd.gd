extends RefCounted
## Bodies: nobody stands inside anybody else. Walkers step around whoever is in the
## way, and whatever overlap is left is relaxed once a tick after everyone has moved.
## Holds no reference to the match, which owns it.

const Anim = preload("res://scripts/sim/match_base.gd").Anim

const CELL := 1.7                 # a little over two riders' radii
const MARGIN := 0.12              # pairs this close may come to overlap while relaxing
const PASSES := 3
const BLOCKED_WAIT := 0.25        # someone boxed in looks again after this long
const MAX_PUSH := 0.4             # metres per pass
const SIDESTEPS := [0.7, 1.4, -0.7, -1.4]

var bodies: Array = []
var rad := PackedFloat32Array()
var side_n := 0                   # cells per side
var head := PackedInt32Array()    # cell -> first index into bodies
var next := PackedInt32Array()
var blocker = null                # who was in the way in the last step() call


static func radius(u) -> float:
	match u.kind:
		"cannon", "ram":
			return 1.0
		"horse":
			return 0.7
		"deer":
			return 0.45
	if u.mounted:
		return 0.75
	return 0.3 if u.child else 0.4


## How readily a body gives way. The player is only ever moved by the player.
static func give(u) -> float:
	if u.kind == "commander" and u.task == "player":
		return 0.0
	if u.in_tower >= 0 or u.kind == "cannon" or u.kind == "ram":
		return 0.05
	match u.anim:
		Anim.MELEE, Anim.SHOOT:
			return 0.3
		Anim.CHOP, Anim.HAMMER, Anim.DIG, Anim.PICK, Anim.LOAD:
			return 0.35
	return 1.0


func index(units: Array, map_size: float) -> void:
	var n := int(map_size / CELL) + 3
	if n != side_n:
		side_n = n
		head.resize(n * n)
	head.fill(-1)
	bodies.clear()
	for u in units:
		if not u.dead and u.stable < 0 and u.in_tower < 0:
			bodies.append(u)
	var size := bodies.size()
	next.resize(size)
	rad.resize(size)
	for i in size:
		var u = bodies[i]
		var p: Vector2 = u.pos
		var k := clampi(int(p.y / CELL), 1, n - 2) * n + clampi(int(p.x / CELL), 1, n - 2)
		next[i] = head[k]
		head[k] = i
		rad[i] = 0.4 if u.kind == "villager" and not u.mounted and not u.child else radius(u)


## Where a walker actually goes when it wants to move `dist` along the unit vector `dir`.
## Returns its own position when every way forward is taken.
func step(u, dir: Vector2, dist: float, m) -> Vector2:
	blocker = null
	var here: Vector2 = u.pos
	var now: float = m.t
	if now < u.boxed_t:
		return here
	var r := radius(u)
	var ghost: bool = now < u.ghost_t     # briefly squeezing past friends to clear a jam
	var near := []
	var cx := clampi(int(here.x / CELL), 1, side_n - 2)
	var cy := clampi(int(here.y / CELL), 1, side_n - 2)
	for y in range(cy - 1, cy + 2):
		var row := y * side_n
		for k in range(row + cx - 1, row + cx + 2):
			var i := head[k]
			while i != -1:
				var rr := (r + rad[i]) * 0.9
				var o = bodies[i]
				i = next[i]
				var gap: float = here.distance_squared_to(o.pos)
				if gap > (rr + dist) * (rr + dist) or o == u or o.dead or (ghost and o.faction == u.faction):
					continue
				near.append([o, rr * rr, gap])
	var straight := here + dir * dist
	if near.is_empty():
		return straight
	blocker = _in_way(straight, near)
	if blocker == null:
		return straight
	if now >= u.dodge_t:
		var off: float = dir.cross(blocker.pos - here)
		if absf(off) > 0.15:
			u.side = -signf(off)
	for angle: float in SIDESTEPS:
		var p := here + dir.rotated(angle * u.side) * dist
		if _in_way(p, near) == null and not m.solid_for(u.faction, m.cell_of(p)):
			u.dodge_t = now + 0.6
			return p
	u.boxed_t = now + BLOCKED_WAIT
	return here


func _in_way(p: Vector2, near: Array):
	for e in near:
		var d: float = p.distance_squared_to(e[0].pos)
		if d < e[1] and d < e[2]:
			return e[0]
	return null


## Push overlapping bodies apart. The result doesn't depend on update order.
func separate(units: Array, m) -> void:
	index(units, m.map_size)
	var n := bodies.size()
	var pos := PackedVector2Array()
	pos.resize(n)
	for i in n:
		pos[i] = bodies[i].pos
	var pa := PackedInt32Array()
	var pb := PackedInt32Array()
	var overlap := false
	for i in n:
		var p := pos[i]
		var ri := rad[i] + MARGIN
		var cx := clampi(int(p.x / CELL), 1, side_n - 2)
		var cy := clampi(int(p.y / CELL), 1, side_n - 2)
		for y in range(cy - 1, cy + 2):
			var row := y * side_n
			for k in range(row + cx - 1, row + cx + 2):
				var j := head[k]
				# Chains run from high index to low, so the rest are all lower.
				while j > i:
					var reach := ri + rad[j]
					var d2 := p.distance_squared_to(pos[j])
					if d2 < reach * reach:
						pa.append(i)
						pb.append(j)
						if d2 < (reach - MARGIN) * (reach - MARGIN):
							overlap = true
					j = next[j]
	if not overlap:
		return
	var yielding := PackedFloat32Array()
	yielding.resize(n)
	yielding.fill(-1.0)
	for list: PackedInt32Array in [pa, pb]:
		for i in list:
			if yielding[i] < 0.0:
				yielding[i] = give(bodies[i])
	var push := PackedVector2Array()
	var count := PackedInt32Array()
	push.resize(n)
	count.resize(n)
	var moved := PackedByteArray()
	moved.resize(n)
	for pass_i in PASSES:
		push.fill(Vector2.ZERO)
		count.fill(0)
		var any := false
		for k in pa.size():
			var i := pa[k]
			var j := pb[k]
			var d := pos[j] - pos[i]
			var rr := rad[i] + rad[j]
			var d2 := d.length_squared()
			if d2 >= rr * rr:
				continue
			var total := yielding[i] + yielding[j]
			if total <= 0.0:
				continue
			var l := sqrt(d2)
			# An exact overlap splits along a direction both ids agree on.
			var away := d / l if l > 0.001 else Vector2.from_angle((bodies[i].id * 31 + bodies[j].id) * 2.39996)
			var fix := away * (rr - l) / total
			push[i] -= fix * yielding[i]
			push[j] += fix * yielding[j]
			count[i] += 1
			count[j] += 1
			any = true
		if not any:
			break
		for i in n:
			if count[i] == 0:
				continue
			# Several neighbours push at once: share it out so a crowd doesn't explode.
			var shove := (push[i] / maxf(1.0, count[i] * 0.4)).limit_length(MAX_PUSH)
			if shove == Vector2.ZERO:
				continue
			pos[i] = _slide(bodies[i].faction, pos[i], shove, m)
			moved[i] = 1
	for i in n:
		if moved[i] == 1:
			bodies[i].pos = pos[i]


func _slide(faction: int, from: Vector2, by: Vector2, m) -> Vector2:
	var to := from + by
	var ct: Vector2i = m.cell_of(to)
	if not m.solid_for(faction, ct) or m.solid_for(faction, m.cell_of(from)):
		return to
	for alt in [from + Vector2(by.x, 0), from + Vector2(0, by.y)]:
		if not m.solid_for(faction, m.cell_of(alt)):
			return alt
	return from
