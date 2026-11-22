extends RefCounted
## Procedural models for everything in the world. Meshes are cached.
## Buildings are built at their footprint size with local +X along the length.

const Geo = preload("res://scripts/view/geo.gd")
const Defs = preload("res://scripts/data/defs.gd")

# [centre, radius] of each clump of a berry bush
const BUSH_LOBES := [
	[Vector3(0, 0.95, 0), 0.8],
	[Vector3(0.75, 0.6, 0.1), 0.65],
	[Vector3(0.1, 0.65, 0.8), 0.65],
	[Vector3(-0.75, 0.65, 0.2), 0.65],
	[Vector3(-0.3, 0.55, -0.75), 0.65],
	[Vector3(0.5, 0.6, -0.65), 0.6],
]

var mats                         # Materials library
var cache := {}
var heights := {}                # mesh key -> height (for the construction clip)


func _init(materials) -> void:
	mats = materials


func _g(seed_in: int = 1) -> Geo:
	var g := Geo.new()
	g.rng.seed = seed_in
	return g


func m(name: String) -> Material:
	return mats.get_mat(name)


# --- Buildings -------------------------------------------------------------------

func building(type: String, tier: int = 0, length: float = 4.0) -> ArrayMesh:
	var key := "%s:%d:%.1f" % [type, tier, length if Defs.BUILDINGS[type].get("wall", false) else 0.0]
	if cache.has(key):
		return cache[key]
	var g := _g(hash(key))
	var d: Dictionary = Defs.BUILDINGS[type]
	var size: Vector2 = d.get("size", Vector2(length, d.get("thick", 1.0)))
	var h := 3.0
	match type:
		"campfire":
			h = _campfire(g)
		"hut":
			h = _hut(g)
		"stockpile":
			h = _stockpile(g, size)
		"lodge":
			h = _lodge(g, size)
		"farm":
			h = _farm(g, size)
		"armory":
			h = _armory(g, size, tier)
		"palisade":
			h = _palisade(g, length)
		"palisade_gate":
			h = _palisade_gate(g, length)
		"watch_post":
			h = _watch_post(g)
		"quarry":
			h = _quarry(g, size)
		"stone_wall":
			h = _stone_wall(g, length)
		"stone_gate":
			h = _stone_gate(g, length)
		"tower":
			h = _tower(g)
		"house":
			h = _house(g, size)
		"granary":
			h = _granary(g, size)
		"stable":
			h = _stable(g, size)
		"mine":
			h = _mine(g, size)
		"smelter":
			h = _smelter(g, size, tier)
		"university":
			h = _university(g, size)
	var mesh := g.finish()
	cache[key] = mesh
	heights[key] = h
	return mesh


func building_height(type: String, tier: int = 0, length: float = 4.0) -> float:
	var key := "%s:%d:%.1f" % [type, tier, length if Defs.BUILDINGS[type].get("wall", false) else 0.0]
	if not heights.has(key):
		building(type, tier, length)
	return heights[key]


func _foundation(g: Geo, size: Vector2, h: float = 0.35, mat: String = "stone") -> void:
	g.slot(mat, m(mat))
	g.box(Vector3(0, h * 0.5 - 0.15, 0), Vector3(size.x, h + 0.3, size.y), 1.0)


func _posts(g: Geo, size: Vector2, h: float, r: float = 0.12, inset: float = 0.1) -> void:
	g.slot("roughwood", m("roughwood"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.cylinder(Vector3(sx * (size.x * 0.5 - inset), 0, sz * (size.y * 0.5 - inset)), Vector3(sx * (size.x * 0.5 - inset), h, sz * (size.y * 0.5 - inset)), r, r * 0.9, 6, true, 1.0, 0.08)


func _door(g: Geo, x: float, z: float, w: float, h: float, facing_z: bool = true) -> void:
	g.slot("darkwood", m("darkwood"))
	if facing_z:
		g.box(Vector3(x, h * 0.5, z), Vector3(w, h, 0.12), 1.0)
	else:
		g.box(Vector3(x, h * 0.5, z), Vector3(0.12, h, w), 1.0)


func _campfire(g: Geo) -> float:
	g.slot("stone", m("stone"))
	for i in 10:
		var a := TAU * i / 10.0
		g.sphere(Vector3(cos(a) * 0.85, 0.08, sin(a) * 0.85), 0.2, 3, 6, Vector3(1.2, 0.7, 1.0), 0.15)
	g.slot("ember", m("ember"))
	g.sphere(Vector3(0, 0.02, 0), 0.55, 3, 8, Vector3(1, 0.25, 1), 0.2)
	g.slot("logs", m("roughwood"))
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		g.cylinder(Vector3(cos(a) * 0.65, 0.05, sin(a) * 0.65), Vector3(cos(a) * 0.08, 0.55, sin(a) * 0.08), 0.07, 0.05, 6)
	# Seats and a small store of goods.
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		var c := Vector3(cos(a) * 2.4, 0.22, sin(a) * 2.4)
		var dir := Vector3(-sin(a), 0, cos(a))
		g.cylinder(c - dir * 0.8, c + dir * 0.8, 0.22, 0.22, 7, true, 1.0, 0.05)
	g.slot("planks", m("planks"))
	g.box(Vector3(2.2, 0.35, -1.9), Vector3(0.7, 0.7, 0.7), 1.0)
	g.box(Vector3(2.5, 0.25, -1.1), Vector3(0.5, 0.5, 0.5), 1.0)
	g.slot("thatch", m("thatch"))
	g.sphere(Vector3(-2.3, 0.3, -2.0), 0.4, 3, 6, Vector3(1, 0.8, 1), 0.1)
	return 1.2


func _hut(g: Geo) -> float:
	g.slot("plaster", m("plaster"))
	var r := 2.1
	g.cylinder(Vector3(0, -0.2, 0), Vector3(0, 1.9, 0), r, r * 0.97, 12, false, 1.0, 0.03)
	g.slot("thatch", m("thatch"))
	g.cylinder(Vector3(0, 1.7, 0), Vector3(0, 2.0, 0), r + 0.6, r + 0.45, 12, false)
	g.pyramid(Vector3.ZERO, r + 0.6, 1.7, 4.4, 12, 1.0)
	g.pyramid(Vector3.ZERO, r + 0.45, 2.0, 4.35, 12, 1.0)
	_door(g, 0, r - 0.05, 0.8, 1.55)
	g.slot("roughwood", m("roughwood"))
	g.cylinder(Vector3(-0.5, 0, r), Vector3(-0.5, 1.7, r), 0.06, 0.05, 5)
	g.cylinder(Vector3(0.5, 0, r), Vector3(0.5, 1.7, r), 0.06, 0.05, 5)
	return 4.4


func _stockpile(g: Geo, size: Vector2) -> float:
	g.slot("planks", m("planks"))
	g.box(Vector3(0, 0.08, 0), Vector3(size.x, 0.16, size.y), 1.0)
	_posts(g, size * 0.9, 2.4, 0.1)
	g.slot("planks", m("planks"))
	g.obox(Vector3(0, 2.5, 0), Vector3(size.x * 0.98, 0.08, size.y * 0.98), Basis(Vector3.RIGHT, 0.12), 1.0)
	g.slot("logs", m("roughwood"))
	for i in 4:
		for j in 3 - i % 2:
			g.cylinder(Vector3(-1.6, 0.35 + i * 0.32, -1.3 + j * 0.4 + (i % 2) * 0.2), Vector3(0.4, 0.35 + i * 0.32, -1.3 + j * 0.4 + (i % 2) * 0.2), 0.16, 0.16, 7)
	g.slot("stone", m("stone"))
	for i in 6:
		g.box(Vector3(1.2 + (i % 2) * 0.55, 0.35 + (i / 2) * 0.4, 0.9), Vector3(0.5, 0.38, 0.6), 1.0)
	g.slot("darkwood", m("darkwood"))
	g.box(Vector3(-1.2, 0.45, 1.3), Vector3(0.8, 0.6, 0.6), 1.0)
	return 2.7


func _cabin(g: Geo, size: Vector2, wall_h: float, roof_h: float, wall: String = "logs", roof: String = "thatch") -> void:
	_foundation(g, size, 0.3)
	g.slot(wall, m(wall))
	g.box(Vector3(0, 0.3 + wall_h * 0.5, 0), Vector3(size.x - 0.2, wall_h, size.y - 0.2), 1.0)
	g.gable_ends(Vector3(0, 0, 0), size.x - 0.2, size.y - 0.2, 0.3 + wall_h, 0.3 + wall_h + roof_h, 1.0)
	g.slot(roof, m(roof))
	g.gable(Vector3(0, 0, 0), size.x - 0.2, size.y - 0.2, 0.3 + wall_h - 0.15, 0.3 + wall_h + roof_h, 0.55, 1.0)
	g.slot("roughwood", m("roughwood"))
	g.cylinder(Vector3(-size.x * 0.5 - 0.5, 0.3 + wall_h + roof_h + 0.05, 0), Vector3(size.x * 0.5 + 0.5, 0.3 + wall_h + roof_h + 0.05, 0), 0.12, 0.12, 6)


func _lodge(g: Geo, size: Vector2) -> float:
	_cabin(g, size, 2.2, 2.0)
	_door(g, 0.8, size.y * 0.5 - 0.05, 0.9, 1.8)
	# Drying rack with hides.
	g.slot("roughwood", m("roughwood"))
	g.cylinder(Vector3(-2.0, 0, size.y * 0.5 + 1.3), Vector3(-2.0, 1.8, size.y * 0.5 + 1.3), 0.06, 0.05, 5)
	g.cylinder(Vector3(-0.6, 0, size.y * 0.5 + 1.3), Vector3(-0.6, 1.8, size.y * 0.5 + 1.3), 0.06, 0.05, 5)
	g.cylinder(Vector3(-2.1, 1.7, size.y * 0.5 + 1.3), Vector3(-0.5, 1.7, size.y * 0.5 + 1.3), 0.05, 0.05, 5)
	g.slot("darkwood", m("darkwood"))
	g.box(Vector3(-1.3, 1.25, size.y * 0.5 + 1.3), Vector3(1.0, 0.85, 0.04), 1.0)
	return 4.6


func _farm(g: Geo, size: Vector2) -> float:
	g.slot("soil", m("soil"))
	g.box(Vector3(0, 0.03, 0), Vector3(size.x, 0.2, size.y), 1.0)
	g.slot("crop", m("crop"))
	var rows := 11
	for r in rows:
		var z := -size.y * 0.42 + size.y * 0.84 * r / (rows - 1)
		var n := 9
		for k in n:
			var x := -size.x * 0.42 + size.x * 0.84 * k / (n - 1) + g.rng.randf_range(-0.3, 0.3)
			var hgt := g.rng.randf_range(0.7, 1.0)
			g.color = Color(g.rng.randf_range(0.6, 1.0), 0.6, 0, 1)
			g.card(Vector3(x, 0.1, z), Vector3(1.3, 0, 0).rotated(Vector3.UP, g.rng.randf_range(-0.4, 0.4)), Vector3(0, hgt, 0), Vector3.UP)
			g.card(Vector3(x, 0.1, z), Vector3(0, 0, 1.0).rotated(Vector3.UP, g.rng.randf_range(-0.4, 0.4)), Vector3(0, hgt, 0), Vector3.UP)
	g.color = Color(1, 1, 1, 1)
	g.slot("roughwood", m("roughwood"))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for i in 8:
		var k := float(i) / 7.0
		for p in [Vector3(-hx + k * size.x, 0, -hz), Vector3(-hx + k * size.x, 0, hz), Vector3(-hx, 0, -hz + k * size.y), Vector3(hx, 0, -hz + k * size.y)]:
			g.cylinder(p, p + Vector3(0, 0.9, 0), 0.05, 0.04, 5)
	for z in [-hz, hz]:
		g.cylinder(Vector3(-hx, 0.75, z), Vector3(hx, 0.75, z), 0.035, 0.035, 4)
	for x in [-hx, hx]:
		g.cylinder(Vector3(x, 0.75, -hz), Vector3(x, 0.75, hz), 0.035, 0.035, 4)
	return 1.2


func _armory(g: Geo, size: Vector2, tier: int) -> float:
	var wall := "planks" if tier == 0 else ("logs" if tier == 1 else "stone")
	_cabin(g, size, 2.6, 2.3, wall, "thatch" if tier < 2 else "darkwood")
	_door(g, 0, size.y * 0.5 - 0.05, 1.4, 2.1)
	# Weapon rack outside.
	g.slot("roughwood", m("roughwood"))
	g.cylinder(Vector3(-2.5, 0, size.y * 0.5 + 0.6), Vector3(-2.5, 1.3, size.y * 0.5 + 0.6), 0.05, 0.05, 5)
	g.cylinder(Vector3(-1.2, 0, size.y * 0.5 + 0.6), Vector3(-1.2, 1.3, size.y * 0.5 + 0.6), 0.05, 0.05, 5)
	g.cylinder(Vector3(-2.6, 1.2, size.y * 0.5 + 0.6), Vector3(-1.1, 1.2, size.y * 0.5 + 0.6), 0.04, 0.04, 4)
	for i in 5:
		var x := -2.4 + i * 0.28
		g.cylinder(Vector3(x, 0.05, size.y * 0.5 + 0.75), Vector3(x + 0.05, 2.1, size.y * 0.5 + 0.5), 0.02, 0.015, 4)
	if tier >= 1:
		# Forge with a stone chimney.
		g.slot("stone", m("stone"))
		g.box(Vector3(size.x * 0.5 + 0.8, 0.5, 0), Vector3(1.6, 1.0, 1.8), 1.0)
		g.box(Vector3(size.x * 0.5 + 0.4, 3.5, 0), Vector3(0.9, 5.5 + tier, 0.9), 1.0)
		g.slot("ember", m("ember"))
		g.box(Vector3(size.x * 0.5 + 0.9, 1.02, 0), Vector3(0.9, 0.08, 1.0), 1.0)
		g.slot("metal", m("metal"))
		g.box(Vector3(size.x * 0.5 + 0.9, 0.45, 1.6), Vector3(0.6, 0.35, 0.3), 1.0)
		g.box(Vector3(size.x * 0.5 + 0.9, 0.2, 1.6), Vector3(0.25, 0.4, 0.25), 1.0)
	return 5.2 + (tier * 1.0)


func _palisade(g: Geo, length: float) -> float:
	g.slot("logs", m("roughwood"))
	var n := maxi(3, int(round(length / 0.36)))
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		var hgt := 3.0 + g.rng.randf_range(-0.15, 0.2)
		var r := g.rng.randf_range(0.16, 0.2)
		g.cylinder(Vector3(x, -0.3, 0), Vector3(x, hgt, 0), r, r * 0.92, 6, false, 1.0, 0.06)
		g.cone(Vector3(x, hgt, 0), Vector3(x, hgt + 0.45, 0), r * 0.92, 6)
	g.cylinder(Vector3(-length * 0.5, 1.9, -0.22), Vector3(length * 0.5, 1.9, -0.22), 0.09, 0.09, 5)
	g.cylinder(Vector3(-length * 0.5, 0.9, -0.22), Vector3(length * 0.5, 0.9, -0.22), 0.09, 0.09, 5)
	return 3.5


func _palisade_gate(g: Geo, length: float) -> float:
	g.slot("logs", m("roughwood"))
	for sx in [-1.0, 1.0]:
		g.cylinder(Vector3(sx * length * 0.5, -0.3, 0), Vector3(sx * length * 0.5, 4.2, 0), 0.26, 0.24, 7)
	g.cylinder(Vector3(-length * 0.5 - 0.3, 3.9, 0), Vector3(length * 0.5 + 0.3, 3.9, 0), 0.18, 0.18, 6)
	g.slot("planks", m("planks"))
	g.box(Vector3(-length * 0.25 + 0.05, 1.45, 0), Vector3(length * 0.5 - 0.3, 2.9, 0.16), 1.0)
	g.box(Vector3(length * 0.25 - 0.05, 1.45, 0), Vector3(length * 0.5 - 0.3, 2.9, 0.16), 1.0)
	g.slot("metal", m("metal"))
	for y in [0.6, 2.3]:
		g.box(Vector3(0, y, 0.1), Vector3(length - 0.5, 0.1, 0.04), 1.0)
	return 4.3


func _watch_post(g: Geo) -> float:
	g.slot("logs", m("roughwood"))
	var r := 1.25
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.cylinder(Vector3(sx * r, 0, sz * r), Vector3(sx * r * 0.8, 6.2, sz * r * 0.8), 0.14, 0.11, 6)
	for y in [2.0, 4.0]:
		g.cylinder(Vector3(-r, y, -r), Vector3(r, y, r), 0.06, 0.06, 4)
		g.cylinder(Vector3(r, y, -r), Vector3(-r, y, r), 0.06, 0.06, 4)
	g.slot("planks", m("planks"))
	g.box(Vector3(0, 5.0, 0), Vector3(2.4, 0.15, 2.4), 1.0)
	for side in 4:
		var a := side * PI * 0.5
		g.obox(Vector3(cos(a) * 1.15, 5.55, sin(a) * 1.15), Vector3(0.06, 0.9, 2.3), Basis(Vector3.UP, -a), 1.0)
	g.slot("thatch", m("thatch"))
	g.pyramid(Vector3.ZERO, 1.8, 6.2, 7.6, 4, 1.0)
	g.slot("roughwood", m("roughwood"))
	g.cylinder(Vector3(0.6, 0, 1.9), Vector3(0.6, 5.0, 1.2), 0.05, 0.05, 4)
	g.cylinder(Vector3(-0.1, 0, 1.9), Vector3(-0.1, 5.0, 1.2), 0.05, 0.05, 4)
	return 7.6


func _quarry(g: Geo, size: Vector2) -> float:
	g.slot("stone", m("stone"))
	for i in 9:
		var x := -2.2 + (i % 3) * 1.1
		var z := 1.4 + (i / 3) * 0.0
		g.box(Vector3(x, 0.3 + (i / 3) * 0.55, z), Vector3(1.0, 0.5, 0.8), 1.0)
	g.slot("boulder", m("boulder"))
	for i in 5:
		g.sphere(Vector3(g.rng.randf_range(-2.5, 2.5), 0.1, g.rng.randf_range(-2.8, -1.0)), g.rng.randf_range(0.3, 0.6), 3, 6, Vector3(1, 0.6, 1), 0.25)
	# A timber crane.
	g.slot("logs", m("roughwood"))
	g.cylinder(Vector3(1.8, 0, -0.5), Vector3(1.8, 5.5, -0.5), 0.15, 0.12, 6)
	g.cylinder(Vector3(1.8, 5.2, -0.5), Vector3(-1.5, 4.0, -1.2), 0.1, 0.08, 5)
	g.cylinder(Vector3(1.0, 0, 0.6), Vector3(1.8, 3.0, -0.5), 0.08, 0.08, 5)
	g.cylinder(Vector3(2.6, 0, 0.6), Vector3(1.8, 3.0, -0.5), 0.08, 0.08, 5)
	return 5.5


func _stone_wall(g: Geo, length: float) -> float:
	g.slot("stone", m("stone"))
	var t := 2.0
	g.box(Vector3(0, 1.85, 0), Vector3(length + 0.05, 4.3, t), 1.0)
	g.box(Vector3(0, 0.15, 0), Vector3(length + 0.15, 0.6, t + 0.35), 1.0)
	var merlons := maxi(2, int(round(length / 1.3)))
	for i in merlons:
		var x := -length * 0.5 + (i + 0.5) * length / merlons
		g.box(Vector3(x, 4.35, t * 0.5 - 0.25), Vector3(length / merlons * 0.55, 0.75, 0.5), 1.0)
		g.box(Vector3(x, 4.2, -t * 0.5 + 0.2), Vector3(length / merlons * 0.9, 0.45, 0.4), 1.0)
	return 4.75


func _stone_gate(g: Geo, length: float) -> float:
	g.slot("stone", m("stone"))
	var t := 2.2
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * (length * 0.5 - 0.35), 2.6, 0), Vector3(0.9, 5.2, t + 0.4), 1.0)
	g.box(Vector3(0, 4.55, 0), Vector3(length, 1.3, t), 1.0)
	for i in 4:
		var x := -length * 0.5 + (i + 0.5) * length / 4.0
		g.box(Vector3(x, 5.5, t * 0.5 - 0.2), Vector3(0.55, 0.7, 0.45), 1.0)
	g.slot("darkwood", m("darkwood"))
	g.box(Vector3(0, 1.95, 0.0), Vector3(length - 1.5, 3.9, 0.22), 1.0)
	g.slot("metal", m("metal"))
	for y in [0.8, 2.0, 3.2]:
		g.box(Vector3(0, y, 0.13), Vector3(length - 1.6, 0.12, 0.04), 1.0)
	return 5.9


func _tower(g: Geo) -> float:
	g.slot("stone", m("stone"))
	g.cylinder(Vector3(0, -0.3, 0), Vector3(0, 9.0, 0), 2.45, 2.2, 14, false, 1.0, 0.0)
	g.cylinder(Vector3(0, 9.0, 0), Vector3(0, 9.6, 0), 2.55, 2.55, 14, true, 1.0)
	for i in 8:
		var a := TAU * i / 8.0
		g.obox(Vector3(cos(a) * 2.3, 10.05, sin(a) * 2.3), Vector3(0.7, 0.9, 0.5), Basis(Vector3.UP, -a + PI * 0.5), 1.0)
	_door(g, 0, 2.2, 1.0, 2.0)
	g.slot("darkwood", m("darkwood"))
	for y in [4.0, 6.5]:
		g.box(Vector3(0, y, 2.25), Vector3(0.25, 0.7, 0.12), 1.0)
	return 10.5


func _house(g: Geo, size: Vector2) -> float:
	_foundation(g, size, 0.3)
	g.slot("stone", m("stone"))
	g.box(Vector3(0, 0.3 + 1.2, 0), Vector3(size.x - 0.2, 2.4, size.y - 0.2), 1.0)
	g.slot("plaster", m("plaster"))
	g.box(Vector3(0, 2.7 + 1.0, 0), Vector3(size.x - 0.1, 2.0, size.y - 0.1), 1.0)
	g.gable_ends(Vector3.ZERO, size.x - 0.1, size.y - 0.1, 4.7, 7.0, 1.0)
	# Timber framing.
	g.slot("darkwood", m("darkwood"))
	for i in 5:
		var x := -size.x * 0.5 + 0.1 + i * (size.x - 0.2) / 4.0
		for z in [size.y * 0.5 - 0.02, -size.y * 0.5 + 0.02]:
			g.box(Vector3(x, 3.7, z), Vector3(0.18, 2.0, 0.06), 1.0)
	for z in [size.y * 0.5 - 0.02, -size.y * 0.5 + 0.02]:
		g.box(Vector3(0, 2.75, z), Vector3(size.x - 0.1, 0.18, 0.06), 1.0)
		g.box(Vector3(0, 4.65, z), Vector3(size.x - 0.1, 0.18, 0.06), 1.0)
	g.slot("thatch", m("thatch"))
	g.gable(Vector3.ZERO, size.x - 0.1, size.y - 0.1, 4.55, 7.0, 0.6, 1.0)
	g.slot("stone", m("stone"))
	g.box(Vector3(size.x * 0.3, 6.6, -0.8), Vector3(0.7, 2.2, 0.7), 1.0)
	_door(g, -0.8, size.y * 0.5 - 0.02, 1.0, 2.0)
	g.slot("darkwood", m("darkwood"))
	for x in [1.0, 2.3]:
		g.box(Vector3(x, 1.5, size.y * 0.5), Vector3(0.6, 0.6, 0.06), 1.0)
	return 7.8


func _granary(g: Geo, size: Vector2) -> float:
	g.slot("stone", m("stone"))
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.cylinder(Vector3(sx * (size.x * 0.5 - 0.5), 0, sz * (size.y * 0.5 - 0.5)), Vector3(sx * (size.x * 0.5 - 0.5), 0.8, sz * (size.y * 0.5 - 0.5)), 0.3, 0.2, 6)
	g.slot("planks", m("planks"))
	g.box(Vector3(0, 0.9, 0), Vector3(size.x, 0.2, size.y), 1.0)
	g.box(Vector3(0, 2.4, 0), Vector3(size.x - 0.4, 2.8, size.y - 0.4), 1.0)
	g.gable_ends(Vector3.ZERO, size.x - 0.4, size.y - 0.4, 3.8, 6.2, 1.0)
	g.slot("thatch", m("thatch"))
	g.gable(Vector3.ZERO, size.x - 0.4, size.y - 0.4, 3.7, 6.2, 0.6, 1.0)
	_door(g, 0, size.y * 0.5 - 0.15, 1.2, 1.9)
	g.slot("darkwood", m("darkwood"))
	g.obox(Vector3(0, 0.45, size.y * 0.5 + 0.7), Vector3(1.0, 0.08, 1.6), Basis(Vector3.RIGHT, -0.55), 1.0)
	return 6.4


func _stable(g: Geo, size: Vector2) -> float:
	g.slot("planks", m("planks"))
	g.box(Vector3(0, 1.4, -size.y * 0.5 + 0.2), Vector3(size.x, 2.8, 0.25), 1.0)
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * (size.x * 0.5 - 0.12), 1.4, -size.y * 0.15), Vector3(0.25, 2.8, size.y * 0.7), 1.0)
	# Stall dividers.
	for i in 4:
		var x := -size.x * 0.5 + (i + 1) * size.x / 5.0
		g.box(Vector3(x, 0.7, -size.y * 0.2), Vector3(0.1, 1.4, size.y * 0.55), 1.0)
	g.slot("logs", m("roughwood"))
	for i in 6:
		var x := -size.x * 0.5 + 0.2 + i * (size.x - 0.4) / 5.0
		g.cylinder(Vector3(x, 0, size.y * 0.2), Vector3(x, 3.0, size.y * 0.2), 0.12, 0.1, 6)
	g.slot("thatch", m("thatch"))
	g.obox(Vector3(0, 3.35, -size.y * 0.15), Vector3(size.x + 0.8, 0.25, size.y * 0.85), Basis(Vector3.RIGHT, 0.22), 1.0)
	# Paddock fence in front.
	g.slot("roughwood", m("roughwood"))
	for i in 7:
		var x := -size.x * 0.5 + i * size.x / 6.0
		g.cylinder(Vector3(x, 0, size.y * 0.5), Vector3(x, 1.1, size.y * 0.5), 0.05, 0.05, 5)
	g.cylinder(Vector3(-size.x * 0.5, 0.95, size.y * 0.5), Vector3(size.x * 0.5, 0.95, size.y * 0.5), 0.04, 0.04, 4)
	g.cylinder(Vector3(-size.x * 0.5, 0.5, size.y * 0.5), Vector3(size.x * 0.5, 0.5, size.y * 0.5), 0.04, 0.04, 4)
	g.slot("thatch", m("thatch"))
	g.sphere(Vector3(-size.x * 0.35, 0.4, -size.y * 0.25), 0.55, 3, 6, Vector3(1.2, 0.8, 1), 0.15)
	return 3.8


func _mine(g: Geo, size: Vector2) -> float:
	g.slot("outcrop", m("outcrop"))
	g.sphere(Vector3(0, -0.4, -0.6), 3.2, 5, 10, Vector3(1.0, 0.75, 0.8), 0.18, 0.5)
	g.slot("darkwood", m("darkwood"))
	g.box(Vector3(0, 1.0, 1.95), Vector3(1.7, 2.0, 0.3), 1.0)
	g.slot("logs", m("roughwood"))
	for sx in [-1.0, 1.0]:
		g.cylinder(Vector3(sx * 1.05, 0, 2.2), Vector3(sx * 1.0, 2.4, 2.2), 0.16, 0.14, 6)
	g.cylinder(Vector3(-1.4, 2.35, 2.2), Vector3(1.4, 2.35, 2.2), 0.16, 0.16, 6)
	g.slot("planks", m("planks"))
	g.box(Vector3(2.1, 0.45, 2.6), Vector3(1.0, 0.6, 0.7), 1.0)
	g.slot("metal", m("metal"))
	for sx in [-1.0, 1.0]:
		g.cylinder(Vector3(2.1 + sx * 0.4, 0.15, 2.25), Vector3(2.1 + sx * 0.4, 0.15, 2.95), 0.16, 0.16, 8)
	return 3.2


func _smelter(g: Geo, size: Vector2, tier: int) -> float:
	_foundation(g, size, 0.25)
	g.slot("stone", m("stone"))
	var top := 3.6 if tier == 0 else 5.0
	g.cylinder(Vector3(0, 0.2, 0), Vector3(0, top, 0), 1.6, 0.9, 10, true, 1.0, 0.02)
	g.cylinder(Vector3(0, top, 0), Vector3(0, top + 2.5 + tier, 0), 0.55, 0.45, 8, false, 1.0)
	g.slot("ember", m("ember"))
	g.box(Vector3(0, 0.75, 1.45), Vector3(0.8, 0.7, 0.2), 1.0)
	g.slot("logs", m("roughwood"))
	_posts(g, Vector2(5.4, 5.4), 3.0, 0.1)
	g.slot("thatch", m("thatch"))
	g.obox(Vector3(-1.8, 3.1, 0), Vector3(2.0, 0.2, 5.6), Basis(Vector3.FORWARD, -0.25), 1.0)
	if tier >= 1:
		g.slot("darkwood", m("darkwood"))
		g.box(Vector3(2.0, 0.7, 0.2), Vector3(1.1, 0.5, 1.6), 1.0)
		g.slot("metal", m("metal"))
		g.cylinder(Vector3(1.5, 0.7, 0.2), Vector3(0.9, 0.7, 0.2), 0.1, 0.08, 6)
	return top + 2.5 + tier


func _university(g: Geo, size: Vector2) -> float:
	_foundation(g, size, 0.5)
	g.slot("stone", m("stone"))
	g.box(Vector3(0, 0.5 + 3.0, 0), Vector3(size.x - 0.3, 6.0, size.y - 0.3), 1.0)
	g.gable_ends(Vector3.ZERO, size.x - 0.3, size.y - 0.3, 6.5, 10.5, 1.0)
	g.slot("darkwood", m("darkwood"))
	g.gable(Vector3.ZERO, size.x - 0.3, size.y - 0.3, 6.4, 10.5, 0.5, 1.0)
	# Tall windows.
	for i in 5:
		var x := -size.x * 0.4 + i * size.x * 0.2
		g.box(Vector3(x, 3.6, size.y * 0.5 - 0.1), Vector3(0.7, 2.6, 0.1), 1.0)
		g.box(Vector3(x, 3.6, -size.y * 0.5 + 0.1), Vector3(0.7, 2.6, 0.1), 1.0)
	# Bell tower.
	g.slot("stone", m("stone"))
	g.box(Vector3(size.x * 0.5 - 1.4, 6.5, size.y * 0.5 - 1.4), Vector3(2.4, 13.0, 2.4), 1.0)
	g.slot("darkwood", m("darkwood"))
	g.pyramid(Vector3(size.x * 0.5 - 1.4, 0, size.y * 0.5 - 1.4), 1.9, 13.0, 16.5, 4, 1.0)
	_door(g, 0, size.y * 0.5 - 0.1, 1.8, 3.0)
	return 16.5


# --- Ghost (placement preview) ------------------------------------------------------

func ghost(type: String, ok: bool, length: float = 4.0) -> ArrayMesh:
	var src := building(type, 0, length)
	var key := "ghost:%s:%s:%.1f" % [type, str(ok), length]
	if cache.has(key):
		return cache[key]
	var mesh := src.duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, m("ghost_ok" if ok else "ghost_bad"))
	cache[key] = mesh
	return mesh


# --- Nature -------------------------------------------------------------------------

func tree(species: String, variant: int, lod: int) -> ArrayMesh:
	var key := "tree:%s:%d:%d" % [species, variant, lod]
	if cache.has(key):
		return cache[key]
	var g := _g(variant * 101 + (7 if species == "pine" else 3))
	if species == "pine":
		_pine(g, lod)
	else:
		_oak(g, lod)
	var mesh := g.finish()
	cache[key] = mesh
	return mesh


func _oak(g: Geo, lod: int) -> void:
	var hgt := g.rng.randf_range(11.0, 15.0)
	var trunk_top := hgt * 0.42
	g.slot("bark", m("oak_bark"))
	g.cylinder(Vector3(0, -0.4, 0), Vector3(g.rng.randf_range(-0.3, 0.3), trunk_top, g.rng.randf_range(-0.3, 0.3)), 0.42, 0.28, 9 if lod == 0 else 5, false, 0.6, 0.08 if lod == 0 else 0.0)
	var crown := Vector3(0, hgt * 0.64, 0)
	var rad := Vector3(g.rng.randf_range(4.0, 5.5), hgt * 0.3, g.rng.randf_range(4.0, 5.5))
	var tips: Array = []
	var branches := 6 if lod == 0 else 3
	for i in branches:
		var a := TAU * i / branches + g.rng.randf_range(-0.3, 0.3)
		var tip := crown + Vector3(cos(a) * rad.x * 0.65, g.rng.randf_range(-0.4, 0.9) * rad.y, sin(a) * rad.z * 0.65)
		tips.append(tip)
		g.cylinder(Vector3(0, trunk_top - 0.5, 0), tip, 0.2, 0.05, 6 if lod == 0 else 4, false, 0.6)
	g.slot("leaves", m("oak_leaves"))
	var cards := 110 if lod == 0 else 18
	var size := 2.6 if lod == 0 else 5.2
	for i in cards:
		var dir := Vector3(g.rng.randf_range(-1, 1), g.rng.randf_range(-0.8, 1), g.rng.randf_range(-1, 1)).normalized()
		var k := pow(g.rng.randf(), 0.4)
		var p := crown + dir * rad * k
		if i % 3 == 0 and not tips.is_empty():
			p = tips[i % tips.size()] + dir * size * 0.6
		var right := dir.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = Vector3.RIGHT
		right = right.rotated(dir, g.rng.randf() * TAU)
		var up := dir.cross(right).normalized()
		g.color = Color(clampf(k * 0.8 + dir.y * 0.25 + 0.1, 0.0, 1.0), 1.0, 0, 1)
		var s := size * g.rng.randf_range(0.8, 1.2)
		g.card(p - up * s * 0.5, right * s, up * s, (p - crown).normalized())
	g.color = Color(1, 1, 1, 1)


func _pine(g: Geo, lod: int) -> void:
	var hgt := g.rng.randf_range(15.0, 21.0)
	g.slot("bark", m("pine_bark"))
	g.cylinder(Vector3(0, -0.4, 0), Vector3(0, hgt, 0), 0.38, 0.06, 8 if lod == 0 else 5, false, 0.5, 0.05 if lod == 0 else 0.0)
	g.slot("leaves", m("pine_needles"))
	# Needle cards spread over a cone, pointing outward and slightly down.
	var cards := 190 if lod == 0 else 26
	var base := hgt * 0.24
	var radius := g.rng.randf_range(3.0, 3.8)
	for i in cards:
		var k := pow(g.rng.randf(), 0.75)
		var y := base + (hgt - base) * k
		var r := radius * pow(1.0 - k, 0.95) + 0.25
		var a := g.rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var depth := g.rng.randf_range(0.55, 1.0)
		var p := Vector3(0, y, 0) + out * r * depth
		var size := (1.4 + 1.4 * (1.0 - k)) * (1.0 if lod == 0 else 2.3)
		var dirv := (out + Vector3(0, -0.45, 0)).normalized()
		g.color = Color(clampf(depth * 0.7 + k * 0.4, 0.0, 1.0), 0.8, 0, 1)
		g.card(p - dirv * size * 0.35, tangent * size * 0.8, dirv * size, (out + Vector3(0, 0.5, 0)).normalized())
	g.card(Vector3(0, hgt - 1.8, 0), Vector3(1.0, 0, 0), Vector3(0, 2.2, 0), Vector3.UP)
	g.card(Vector3(0, hgt - 1.8, 0), Vector3(0, 0, 1.0), Vector3(0, 2.2, 0), Vector3.UP)
	g.color = Color(1, 1, 1, 1)


func rock_mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "rock:%s:%d" % [kind, variant]
	if cache.has(key):
		return cache[key]
	var g := _g(variant * 13 + hash(kind))
	match kind:
		"boulder":
			g.slot("rock", m("boulder"))
			g.sphere(Vector3(0, 0.15, 0), 0.9, 5, 9, Vector3(1.0, 0.72, 0.85), 0.22, 1.0)
		"outcrop":
			g.slot("rock", m("outcrop"))
			for i in 6:
				var r := g.rng.randf_range(1.6, 3.4)
				g.sphere(Vector3(g.rng.randf_range(-3, 3), r * 0.25 - 0.4, g.rng.randf_range(-3, 3)), r, 5, 9, Vector3(1.0, g.rng.randf_range(0.6, 1.1), 0.9), 0.2, 0.6)
		_:
			# Deposits: bronze_ore, coal, iron_ore
			g.slot("rock", m("dep_" + kind))
			for i in 5:
				var r := g.rng.randf_range(0.8, 1.7)
				g.sphere(Vector3(g.rng.randf_range(-2.2, 2.2), r * 0.2 - 0.25, g.rng.randf_range(-2.2, 2.2)), r, 4, 8, Vector3(1.0, 0.7, 0.9), 0.25, 1.0)
			for i in 10:
				g.sphere(Vector3(g.rng.randf_range(-3.5, 3.5), 0.05, g.rng.randf_range(-3.5, 3.5)), g.rng.randf_range(0.15, 0.35), 3, 5, Vector3(1, 0.7, 1), 0.3, 1.0)
	var mesh := g.finish()
	cache[key] = mesh
	return mesh


## Leaves of a berry bush, about 3 m across and head high at scale 1.
func bush() -> ArrayMesh:
	if cache.has("bush"):
		return cache["bush"]
	var g := _g(55)
	g.slot("leaves", m("bush_leaves"))
	for lobe in BUSH_LOBES:
		var c: Vector3 = lobe[0]
		var r: float = lobe[1]
		for i in 40:
			var dir := _bush_dir(g)
			var depth := g.rng.randf_range(0.6, 1.0)
			var p := c + dir * r * depth
			# Tilt each card so the crown doesn't look like scales.
			var facing := (dir + _bush_dir(g) * 0.5).normalized()
			var right := facing.cross(Vector3.UP).normalized()
			if right.length() < 0.1:
				right = Vector3.RIGHT
			right = right.rotated(facing, g.rng.randf() * TAU)
			var up := facing.cross(right).normalized()
			var s := g.rng.randf_range(0.6, 0.85)
			g.color = Color(clampf(depth - 0.35 + dir.y * 0.35, 0.0, 1.0), 1.0, 0, 1)
			g.card(p - up * s * 0.5, right * s, up * s, dir)
	g.color = Color(1, 1, 1, 1)
	var mesh := g.finish()
	cache["bush"] = mesh
	return mesh


## The fruit is its own mesh, so a picked-clean bush keeps its leaves.
func bush_berries() -> ArrayMesh:
	if cache.has("bush_berries"):
		return cache["bush_berries"]
	var g := _g(56)
	g.slot("berries", m("bush_berries"))
	for lobe in BUSH_LOBES:
		var c: Vector3 = lobe[0]
		var r: float = lobe[1]
		for bunch in 6:
			var p := c + _bush_dir(g) * r * 1.12
			if p.y < 0.2:
				continue
			for i in 4:
				var off := Vector3(g.rng.randf_range(-1, 1), g.rng.randf_range(-1, 1), g.rng.randf_range(-1, 1)) * 0.075
				g.sphere(p + off, g.rng.randf_range(0.045, 0.065), 3, 5)
	var mesh := g.finish()
	cache["bush_berries"] = mesh
	return mesh


func _bush_dir(g: Geo) -> Vector3:
	var y := g.rng.randf_range(-0.35, 1.0)
	var flat := Vector2.from_angle(g.rng.randf() * TAU) * sqrt(1.0 - y * y)
	return Vector3(flat.x, y, flat.y)


func carcass() -> ArrayMesh:
	if cache.has("carcass"):
		return cache["carcass"]
	var g := _g(9)
	g.slot("a", m("berries"))
	g.sphere(Vector3(0, 0.25, 0), 0.45, 3, 6, Vector3(1.6, 0.5, 0.8), 0.1)
	var mesh := g.finish()
	cache["carcass"] = mesh
	return mesh


func grass_clump() -> ArrayMesh:
	if cache.has("grass"):
		return cache["grass"]
	var g := _g(77)
	g.slot("grass", m("grass"))
	for i in 3:
		var a := PI * i / 3.0
		var right := Vector3(cos(a), 0, sin(a)) * 0.34
		g.card(Vector3.ZERO, right, Vector3(0, 0.3, 0), Vector3.UP)
	var mesh := g.finish()
	cache["grass"] = mesh
	return mesh


# --- People ---------------------------------------------------------------------------

func _p(g: Geo, limb: int, region: int) -> void:
	g.limb = limb
	g.region = region


func person() -> ArrayMesh:
	if cache.has("person"):
		return cache["person"]
	var g := _g(1)
	g.slot("p", m("person"))
	# Legs (trousers) and boots.
	for side in [1.0, -1.0]:
		var limb := 4 if side > 0 else 5
		_p(g, limb, 2)
		g.cylinder(Vector3(0.1 * side, 0.95, 0), Vector3(0.1 * side, 0.12, 0.01), 0.085, 0.058, 7, false)
		_p(g, limb, 3)
		g.box(Vector3(0.1 * side, 0.07, 0.05), Vector3(0.12, 0.14, 0.27), 1.0, false)
	# Tunic skirt and torso.
	_p(g, 0, 1)
	g.cylinder(Vector3(0, 0.66, 0), Vector3(0, 1.02, 0), 0.25, 0.2, 9, false)
	var old := g.xf
	g.xf = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.72)), Vector3.ZERO)
	g.cylinder(Vector3(0, 0.98, 0), Vector3(0, 1.47, 0), 0.2, 0.23, 9, true)
	g.xf = old
	_p(g, 0, 3)
	g.cylinder(Vector3(0, 0.96, 0), Vector3(0, 1.03, 0), 0.215, 0.215, 9, false)
	_p(g, 0, 0)
	g.cylinder(Vector3(0, 1.46, 0), Vector3(0, 1.55, 0.0), 0.055, 0.05, 6, false)
	# Head and hair.
	_p(g, 1, 0)
	g.sphere(Vector3(0, 1.65, 0.015), 0.115, 5, 8, Vector3(0.88, 1.08, 0.98))
	g.box(Vector3(0, 1.635, 0.115), Vector3(0.03, 0.05, 0.04), 1.0, false)
	_p(g, 1, 4)
	g.sphere(Vector3(0, 1.69, -0.012), 0.118, 4, 8, Vector3(0.93, 0.85, 1.0))
	# Arms: sleeves, forearms, hands.
	for side in [1.0, -1.0]:
		var limb := 2 if side > 0 else 3
		_p(g, limb, 1)
		g.cylinder(Vector3(0.21 * side, 1.43, 0), Vector3(0.23 * side, 1.1, 0.02), 0.07, 0.058, 7, false)
		_p(g, limb, 0)
		g.cylinder(Vector3(0.23 * side, 1.1, 0.02), Vector3(0.24 * side, 0.82, 0.05), 0.05, 0.04, 6, false)
		g.sphere(Vector3(0.24 * side, 0.77, 0.06), 0.05, 3, 6)
	var mesh := g.finish()
	cache["person"] = mesh
	return mesh


## Items held or worn by people. Right-hand items use limb 3, left-hand limb 2.
func item(name: String) -> ArrayMesh:
	var key := "item:" + name
	if cache.has(key):
		return cache[key]
	var g := _g(hash(name))
	g.slot("p", m("person"))
	var hand_r := Vector3(-0.24, 0.77, 0.07)
	var hand_l := Vector3(0.24, 0.77, 0.07)
	match name:
		"wood_spear", "bronze_spear", "iron_spear":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, -0.6, 0), hand_r + Vector3(0, 1.45, 0.05), 0.022, 0.022, 5)
			_p(g, 3, 5 if name == "wood_spear" else (7 if name == "bronze_spear" else 6))
			g.cone(hand_r + Vector3(0, 1.45, 0.05), hand_r + Vector3(0, 1.75, 0.06), 0.04, 4)
		"bronze_sword", "iron_sword":
			_p(g, 3, 3)
			g.cylinder(hand_r + Vector3(0, 0, -0.08), hand_r + Vector3(0, 0, 0.08), 0.025, 0.025, 5)
			_p(g, 3, 7 if name == "bronze_sword" else 6)
			g.box(hand_r + Vector3(0, 0, 0.1), Vector3(0.2, 0.03, 0.03), 1.0, false)
			g.box(hand_r + Vector3(0, 0, 0.5), Vector3(0.05, 0.012, 0.78), 1.0, false)
		"bronze_pike", "iron_pike":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, -0.7, 0), hand_r + Vector3(0, 3.6, 0.05), 0.024, 0.02, 5)
			_p(g, 3, 7 if name == "bronze_pike" else 6)
			g.cone(hand_r + Vector3(0, 3.6, 0.05), hand_r + Vector3(0, 3.95, 0.05), 0.04, 4)
		"bronze_lance", "iron_lance":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, -0.2, -0.9), hand_r + Vector3(0, 0.35, 2.3), 0.05, 0.025, 6)
			_p(g, 3, 7 if name == "bronze_lance" else 6)
			g.cone(hand_r + Vector3(0, 0.35, 2.3), hand_r + Vector3(0, 0.4, 2.65), 0.035, 4)
		"bow":
			_p(g, 2, 5)
			var c := hand_l + Vector3(0.0, 0.05, 0.05)
			for i in 6:
				var a0 := -0.9 + 1.8 * i / 6.0
				var a1 := -0.9 + 1.8 * (i + 1) / 6.0
				g.cylinder(c + Vector3(0, sin(a0) * 0.75, cos(a0) * 0.2 - 0.2), c + Vector3(0, sin(a1) * 0.75, cos(a1) * 0.2 - 0.2), 0.02, 0.02, 4, false)
		"axe":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, 0, -0.1), hand_r + Vector3(0, 0.05, 0.7), 0.022, 0.022, 5)
			_p(g, 3, 6)
			g.box(hand_r + Vector3(0, 0.12, 0.66), Vector3(0.03, 0.2, 0.14), 1.0, false)
		"hammer":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, 0, -0.05), hand_r + Vector3(0, 0.02, 0.42), 0.02, 0.02, 5)
			_p(g, 3, 6)
			g.box(hand_r + Vector3(0, 0.0, 0.45), Vector3(0.06, 0.07, 0.16), 1.0, false)
		"pick":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, 0, -0.1), hand_r + Vector3(0, 0.03, 0.75), 0.022, 0.022, 5)
			_p(g, 3, 6)
			g.box(hand_r + Vector3(0, 0.0, 0.75), Vector3(0.04, 0.5, 0.04), 1.0, false)
		"hoe":
			_p(g, 3, 5)
			g.cylinder(hand_r + Vector3(0, -0.2, -0.1), hand_r + Vector3(0, 0.3, 1.1), 0.02, 0.02, 5)
			_p(g, 3, 6)
			g.box(hand_r + Vector3(0, 0.22, 1.12), Vector3(0.18, 0.15, 0.03), 1.0, false)
		"basket", "bundle_food":
			var held := name == "basket"
			_p(g, 3 if held else 0, 5)
			_basket(g, hand_r if held else Vector3(-0.30,0.91,0.12), not held)
		"bundle_wood":
			var center := Vector3(-0.215,1.42,0.01)
			for offset in [Vector3(-0.055,0,0),Vector3(0.046,0.012,0.03),Vector3(-0.006,0.088,-0.04)]:
				_p(g, 0, 12)
				var start: Vector3 = center + offset - Vector3(0, 0, 0.36)
				var end: Vector3 = center + offset + Vector3(0,0,0.33)
				g.cylinder(start, end, 0.061, 0.054, 10, false)
				_p(g, 0, 10)
				g.cylinder(end - Vector3.BACK * 0.001, end, 0.054, 0.054, 10)
				g.cylinder(start + Vector3.BACK * 0.001, start, 0.061, 0.061, 10)
			_p(g,0,3)
			for z in [-0.18,0.16]:
				for i in 12:
					var a := TAU*i/12
					var b := TAU*(i+1)/12
					g.cylinder(center+Vector3(0.113*cos(a),0.037+0.10*sin(a),z),center+Vector3(0.113*cos(b),0.037+0.10*sin(b),z),0.009,0.009,5)
		"bundle_stone":
			_p(g, 0, 9)
			g.sphere(Vector3(0,1.03,0.27),0.175,5,9,Vector3(1.10,0.67,0.86),0.16)
		"wood_shield", "bronze_shield", "iron_shield":
			_p(g, 2, 5 if name == "wood_shield" else (7 if name == "bronze_shield" else 6))
			var c2 := hand_l + Vector3(0.09, 0.28, 0.12)
			g.cylinder(c2, c2 + Vector3(0.06, 0, 0.02), 0.36, 0.36, 12, true)
			_p(g, 2, 6 if name == "wood_shield" else 3)
			g.sphere(c2 + Vector3(0.07, 0, 0.02), 0.07, 3, 6, Vector3(0.6, 1, 1))
		"bronze_helmet", "iron_helmet":
			_p(g, 1, 7 if name == "bronze_helmet" else 6)
			g.sphere(Vector3(0, 1.7, 0.0), 0.135, 4, 8, Vector3(1.0, 0.9, 1.05))
			g.box(Vector3(0, 1.62, 0.125), Vector3(0.03, 0.12, 0.02), 1.0, false)
		"bronze_armor", "iron_armor":
			_p(g, 0, 7 if name == "bronze_armor" else 6)
			var old := g.xf
			g.xf = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3.ZERO)
			g.cylinder(Vector3(0, 1.0, 0), Vector3(0, 1.44, 0), 0.215, 0.245, 9, true)
			g.xf = old
		"crown":
			_p(g, 1, 8)
			g.cylinder(Vector3(0, 1.73, -0.01), Vector3(0, 1.8, -0.01), 0.118, 0.122, 10, false)
			for i in 6:
				var a := TAU * i / 6.0
				var p := Vector3(cos(a) * 0.115, 1.8, sin(a) * 0.115 - 0.01)
				g.cone(p, p + Vector3(0, 0.09, 0), 0.03, 4)
		"cloak":
			_p(g, 0, 9)
			g.quad(Vector3(-0.24, 1.44, -0.16), Vector3(0.24, 1.44, -0.16), Vector3(0.3, 0.55, -0.3), Vector3(-0.3, 0.55, -0.3), Vector3(0, 0, -1))
			g.quad(Vector3(-0.24, 1.44, -0.15), Vector3(-0.3, 0.55, -0.29), Vector3(0.3, 0.55, -0.29), Vector3(0.24, 1.44, -0.15), Vector3(0, 0, 1))
	var mesh := g.finish()
	cache[key] = mesh
	return mesh


func _basket(g: Geo, grip: Vector3, filled: bool) -> void:
	var lip := grip - Vector3(0,0.16,0)
	g.cylinder(lip-Vector3.UP*0.18,lip,0.11,0.155,14)
	for i in 14:
		var a := TAU*i/14
		var b := TAU*(i+1)/14
		for h in [0.0,0.045,0.09,0.135]:
			var radius: float = 0.157 - h*0.25
			g.cylinder(lip+Vector3(cos(a)*radius,-h,sin(a)*radius),lip+Vector3(cos(b)*radius,-h,sin(b)*radius),0.006,0.006,5)
	for i in 10:
		var a := PI*i/10
		var b := PI*(i+1)/10
		g.cylinder(lip+Vector3(cos(a)*0.15,sin(a)*0.16,0),lip+Vector3(cos(b)*0.15,sin(b)*0.16,0),0.012,0.012,7)
	if filled:
		g.region = 11
		for i in 8:
			var a := TAU*i/8
			g.sphere(lip+Vector3(cos(a)*0.084,0.005,sin(a)*0.084),0.041,4,7,Vector3(1,0.84,1))


func quadruped(deer: bool) -> ArrayMesh:
	var key := "deer" if deer else "horse"
	if cache.has(key):
		return cache[key]
	var g := _g(3 if deer else 4)
	g.slot("a", m("animal"))
	var s := 0.78 if deer else 1.0
	g.xf = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO)
	_p(g, 0, 1)
	g.sphere(Vector3(0, 1.3, 0.05), 0.48, 5, 10, Vector3(0.82, 0.9, 1.75), 0.0)
	_p(g, 1, 1)
	g.cylinder(Vector3(0, 1.4, 0.65), Vector3(0, 1.92 if not deer else 1.95, 1.02), 0.24, 0.13, 8, false)
	g.cylinder(Vector3(0, 1.92 if not deer else 1.95, 1.0), Vector3(0, 1.66, 1.48), 0.13, 0.08, 8, true)
	if not deer:
		_p(g, 1, 4)
		g.box(Vector3(0, 1.78, 0.78), Vector3(0.07, 0.35, 0.5), 1.0, false)
	else:
		_p(g, 1, 3)
		for side in [-1.0, 1.0]:
			g.cylinder(Vector3(0.06 * side, 2.02, 1.02), Vector3(0.25 * side, 2.45, 0.95), 0.025, 0.015, 4)
			g.cylinder(Vector3(0.18 * side, 2.3, 0.97), Vector3(0.22 * side, 2.4, 1.15), 0.015, 0.01, 4)
	for leg in 4:
		var front := leg < 2
		var sx := 0.2 if leg % 2 == 0 else -0.2
		var z := 0.55 if front else -0.5
		_p(g, 2 + leg, 1)
		g.cylinder(Vector3(sx, 1.15, z), Vector3(sx, 0.5, z + (0.02 if front else -0.04)), 0.11 if not deer else 0.08, 0.06, 6, false)
		g.cylinder(Vector3(sx, 0.5, z), Vector3(sx, 0.06, z), 0.055, 0.045, 6, false)
		_p(g, 2 + leg, 3)
		g.cylinder(Vector3(sx, 0.08, z), Vector3(sx, 0.0, z), 0.065, 0.07, 6, false)
	_p(g, 6, 4)
	g.cylinder(Vector3(0, 1.38, -0.78), Vector3(0, 0.75 if not deer else 1.1, -0.98), 0.07, 0.03, 5)
	g.xf = Transform3D.IDENTITY
	var mesh := g.finish()
	cache[key] = mesh
	return mesh


func cannon() -> ArrayMesh:
	if cache.has("cannon"):
		return cache["cannon"]
	var g := _g(5)
	g.slot("wood", m("darkwood"))
	for sx in [-1.0, 1.0]:
		g.obox(Vector3(sx * 0.28, 0.6, -0.3), Vector3(0.1, 0.35, 1.9), Basis(Vector3.RIGHT, -0.12), 1.0)
	g.cylinder(Vector3(-0.7, 0.6, 0.2), Vector3(0.7, 0.6, 0.2), 0.06, 0.06, 6)
	g.obox(Vector3(0, 0.25, -1.4), Vector3(0.3, 0.18, 1.2), Basis(Vector3.RIGHT, 0.3), 1.0)
	for sx in [-1.0, 1.0]:
		g.cylinder(Vector3(sx * 0.6, 0.6, 0.2), Vector3(sx * 0.75, 0.6, 0.2), 0.6, 0.6, 12, true)
	g.slot("metal", m("metal"))
	g.cylinder(Vector3(0, 0.88, -0.6), Vector3(0, 1.0, 1.4), 0.2, 0.13, 10, true)
	g.sphere(Vector3(0, 0.86, -0.65), 0.17, 3, 8)
	var mesh := g.finish()
	cache["cannon"] = mesh
	return mesh


func ram() -> ArrayMesh:
	if cache.has("ram"):
		return cache["ram"]
	var g := _g(6)
	g.slot("logs", m("roughwood"))
	g.cylinder(Vector3(0, 1.0, -2.0), Vector3(0, 1.0, 2.4), 0.26, 0.24, 8, true)
	for sx in [-1.0, 1.0]:
		g.cylinder(Vector3(sx * 0.8, 0.4, -1.8), Vector3(sx * 0.8, 0.4, 1.8), 0.1, 0.1, 5)
		for z in [-1.5, 1.5]:
			g.cylinder(Vector3(sx * 0.8, 0.4, z), Vector3(sx * 0.3, 2.2, z * 0.8), 0.08, 0.07, 5)
	g.slot("planks", m("planks"))
	g.obox(Vector3(0.55, 2.0, 0), Vector3(1.3, 0.08, 4.0), Basis(Vector3.FORWARD, 0.6), 1.0)
	g.obox(Vector3(-0.55, 2.0, 0), Vector3(1.3, 0.08, 4.0), Basis(Vector3.FORWARD, -0.6), 1.0)
	g.slot("metal", m("metal"))
	g.cone(Vector3(0, 1.0, 2.4), Vector3(0, 1.0, 2.8), 0.25, 8)
	for sx in [-1.0, 1.0]:
		for z in [-1.6, 1.6]:
			g.cylinder(Vector3(sx * 0.95, 0.4, z), Vector3(sx * 1.05, 0.4, z), 0.4, 0.4, 10, true)
	var mesh := g.finish()
	cache["ram"] = mesh
	return mesh


func arrow() -> ArrayMesh:
	if cache.has("arrow"):
		return cache["arrow"]
	var g := _g(2)
	g.slot("a", m("arrow"))
	g.cylinder(Vector3(0, 0, -0.4), Vector3(0, 0, 0.4), 0.012, 0.012, 4)
	g.cone(Vector3(0, 0, 0.4), Vector3(0, 0, 0.47), 0.02, 4)
	var mesh := g.finish()
	cache["arrow"] = mesh
	return mesh


func ball() -> ArrayMesh:
	if cache.has("ball"):
		return cache["ball"]
	var g := _g(3)
	g.slot("a", m("ball"))
	g.sphere(Vector3.ZERO, 0.11, 4, 6)
	var mesh := g.finish()
	cache["ball"] = mesh
	return mesh
