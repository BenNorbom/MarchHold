extends Node3D
## Sparks, dust and spent arrows: one MultiMesh each, so a whole battle costs three
## draw calls.

const MAX_BITS := 220
const MAX_STUCK := 120
const STUCK_FOR := 30.0
const NEAR := 70.0                # no point in effects further off than this
const BOUNDS := AABB(Vector3(-100, -100, -100), Vector3(1300, 400, 1300))

var clock := 0.0
var cam := Vector3.ZERO
var layers: Array = []            # sparks, dust
var stuck_mm: MultiMesh
var stuck: Array = []             # [transform, until]
var falls: Array = []             # [when, where]
var rng := RandomNumberGenerator.new()


class Layer:
	var mm: MultiMesh
	var bits: Array = []          # [pos, velocity, age, life, size, colour]
	var gravity := 0.0
	var drag := 0.0
	var grow := 0.0


func setup(mats, meshes) -> void:
	var soft: Texture2D = mats.make_soft_dot()
	var sparks := _layer(soft, true)
	sparks.gravity = -8.0
	sparks.drag = 1.0
	var dust := _layer(soft, false)
	dust.gravity = -0.5
	dust.drag = 3.0
	dust.grow = 1.6
	layers = [sparks, dust]
	stuck_mm = MultiMesh.new()
	stuck_mm.transform_format = MultiMesh.TRANSFORM_3D
	stuck_mm.mesh = meshes.arrow()
	stuck_mm.instance_count = MAX_STUCK
	stuck_mm.visible_instance_count = 0
	_show(stuck_mm)


func _layer(tex: Texture2D, glow: bool) -> Layer:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.material = mat
	var layer := Layer.new()
	layer.mm = MultiMesh.new()
	layer.mm.transform_format = MultiMesh.TRANSFORM_3D
	layer.mm.use_colors = true
	layer.mm.mesh = quad
	layer.mm.instance_count = MAX_BITS
	layer.mm.visible_instance_count = 0
	_show(layer.mm)
	return layer


func _show(mm: MultiMesh) -> void:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = BOUNDS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _burst(layer: Layer, at: Vector3, push: Vector3, n: int, speed: float, life: float, size: float, col: Color) -> void:
	for i in n:
		if layer.bits.size() >= MAX_BITS:
			return
		var scatter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)) * speed
		layer.bits.append([at, push + scatter, 0.0, life * rng.randf_range(0.7, 1.2), size * rng.randf_range(0.7, 1.3), col])


## `feet` is the ground under whoever was hit.
func hit(ev: Dictionary, feet: Vector3) -> void:
	if feet.distance_to(cam) > NEAR:
		return
	var dir: Vector2 = ev["dir"]
	var guard: String = ev["guard"]
	var push := Vector3(dir.x, 0.2, dir.y)
	# On the side the blow came from.
	var at := feet + Vector3(-dir.x * 0.35, 1.25, -dir.y * 0.35)
	if guard == "parry":
		_burst(layers[0], at, -push * 1.5, 22, 3.2, 0.4, 0.09, Color(1.0, 0.9, 0.55))
	elif guard != "":
		_burst(layers[0], at, -push, 12 if guard == "block" else 7, 2.2, 0.3, 0.07, Color(1.0, 0.72, 0.35))
	if guard in ["", "armor"]:
		_burst(layers[1], at, push * 1.2, 6, 0.7, 0.55, 0.28, Color(0.6, 0.52, 0.41, 0.55))


func fallen(feet: Vector3) -> void:
	if feet.distance_to(cam) <= NEAR:
		falls.append([clock + 0.45, feet])


func arrow_landed(at: Vector3, flight: Vector3, in_body: bool) -> void:
	if in_body:
		return                    # the flinch and the hit's own dust show that
	var dir := flight.normalized() if flight.length() > 0.01 else Vector3.DOWN
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	stuck.append([Transform3D(Basis.looking_at(-dir, up), at - dir * 0.3), clock + STUCK_FOR])
	if stuck.size() > MAX_STUCK:
		stuck.pop_front()
	if at.distance_to(cam) < NEAR:
		_burst(layers[1], at, Vector3.UP * 0.6, 3, 0.4, 0.5, 0.22, Color(0.5, 0.42, 0.32, 0.5))


func update_frame(delta: float, eye: Vector3) -> void:
	clock += delta
	cam = eye
	while not falls.is_empty() and float(falls[0][0]) <= clock:
		var fall: Array = falls.pop_front()
		_burst(layers[1], fall[1] + Vector3(0, 0.15, 0), Vector3.UP * 0.4, 9, 1.1, 0.9, 0.4, Color(0.52, 0.45, 0.35, 0.5))
	for layer: Layer in layers:
		var live := []
		for bit: Array in layer.bits:
			bit[2] += delta
			if bit[2] >= bit[3]:
				continue
			bit[1] = (bit[1] as Vector3) * exp(-layer.drag * delta) + Vector3(0, layer.gravity * delta, 0)
			bit[0] = (bit[0] as Vector3) + (bit[1] as Vector3) * delta
			var age: float = bit[2] / bit[3]
			var col: Color = bit[5]
			col.a *= 1.0 - age
			var i := live.size()
			var size: float = bit[4] * (1.0 + layer.grow * age)
			layer.mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), bit[0]))
			layer.mm.set_instance_color(i, col)
			live.append(bit)
		layer.bits = live
		layer.mm.visible_instance_count = live.size()
	while not stuck.is_empty() and float(stuck[0][1]) <= clock:
		stuck.pop_front()
	for i in stuck.size():
		stuck_mm.set_instance_transform(i, stuck[i][0])
	stuck_mm.visible_instance_count = stuck.size()
