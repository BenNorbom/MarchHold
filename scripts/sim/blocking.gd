extends RefCounted
## What can be walked on: one path grid shared by every faction. Every blocker is
## solid in it, and each faction keeps the set of gate cells it may pass through.
## Memory therefore doesn't grow with the number of settlements.

const NOT_A_GATE := -1

var n := 0                      # cells per side
var grid := AStarGrid2D.new()
var terrain_solid := PackedByteArray()
var blockers := {}              # cell index -> owners of what stands there (NOT_A_GATE, or a gate's faction)
var open_gates: Array = []      # faction -> {cell: true}


func setup(cells_per_side: int, ground: PackedByteArray, faction_count: int) -> void:
	n = cells_per_side
	terrain_solid = ground
	grid.region = Rect2i(0, 0, n, n)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.jumping_enabled = true
	grid.update()
	for j in n:
		for i in n:
			if terrain_solid[j * n + i] == 1:
				grid.set_point_solid(Vector2i(i, j), true)
	blockers.clear()
	open_gates.clear()
	for f in faction_count:
		open_gates.append({})


## Wild animals (faction below 0) move like faction 0.
func is_solid(faction: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return true
	if not grid.is_point_solid(c):
		return false
	return not open_gates[maxi(faction, 0)].has(c)


func add(cells: PackedInt32Array, owner: int) -> void:
	for k in cells:
		var list: Array = blockers.get(k, [])
		list.append(owner)
		blockers[k] = list
		_refresh(k, list)


func remove(cells: PackedInt32Array, owner: int) -> void:
	for k in cells:
		var list: Array = blockers.get(k, [])
		list.erase(owner)
		if list.is_empty():
			blockers.erase(k)
		_refresh(k, list)


## A cell is open to a faction only if all that stands on it is that faction's gates.
func _refresh(k: int, list: Array) -> void:
	var c := Vector2i(k % n, k / n)
	var ground: bool = terrain_solid[k] == 1
	grid.set_point_solid(c, ground or not list.is_empty())
	var passable := NOT_A_GATE
	if not ground and not list.is_empty() and list.count(list[0]) == list.size():
		passable = list[0]
	for f in open_gates.size():
		if f == passable:
			open_gates[f][c] = true
		else:
			open_gates[f].erase(c)


func route(faction: int, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var gates: Dictionary = open_gates[maxi(faction, 0)]
	for c: Vector2i in gates:
		grid.set_point_solid(c, false)
	var ids: Array[Vector2i] = grid.get_id_path(from, to, true)
	for c: Vector2i in gates:
		grid.set_point_solid(c, true)
	return ids
