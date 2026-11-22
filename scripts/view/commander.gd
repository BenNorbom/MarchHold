extends CharacterBody3D
## The player's commander, strictly first person.

const Defs = preload("res://scripts/data/defs.gd")
const Geo = preload("res://scripts/view/geo.gd")

signal attacked(result: String)

const SHIELD_LOW := Vector3(-0.78, -0.56, -0.66)
const SHIELD_LOW_ROT := Vector3(0.25, 0.75, 0.2)
const SHIELD_HIGH := Vector3(-0.16, -0.32, -0.78)
const SHIELD_HIGH_ROT := Vector3(-0.08, 0.12, 0.06)

var m
var mats
var camera: Camera3D
var view_model: Node3D
var vm_weapon: MeshInstance3D
var vm_shield: MeshInstance3D
var vm_bow: MeshInstance3D
var pitch := 0.0
var stamina := 1.0
var look_enabled := true
var move_enabled := true
var bob := 0.0
var swing := 0.0
var draw := 0.0
var drawing := false
var use_bow := false
var shield_held := false    # right mouse is down
var raise_k := 0.0          # 0 carried .. 1 raised, for the view model
var jolt := 0.0
var seen_block_t := -99.0
var step_acc := 0.0
var shown_weapon := "?"
var shown_shield := "?"
var shown_bow := false
var sensitivity := 0.11
var invert := false
var anim := 0


func setup(match_ref, materials, start: Vector3, facing: float) -> void:
	m = match_ref
	mats = materials
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.68, 0)
	camera.near = 0.06
	camera.far = 1600.0
	add_child(camera)
	camera.current = true
	view_model = Node3D.new()
	view_model.scale = Vector3.ONE * 0.6
	camera.add_child(view_model)
	vm_weapon = MeshInstance3D.new()
	vm_shield = MeshInstance3D.new()
	vm_bow = MeshInstance3D.new()
	for mi in [vm_weapon, vm_shield, vm_bow]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view_model.add_child(mi)
	position = start
	rotation.y = atan2(-sin(facing), -cos(facing))
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	apply_settings()


func apply_settings() -> void:
	sensitivity = float(Settings.get_val("sensitivity", 0.11))
	invert = bool(Settings.get_val("invert_y", false))
	camera.fov = float(Settings.get_val("fov", 75.0))


func me():
	return m.commander(0)


func facing() -> float:
	var f := -global_transform.basis.z
	return atan2(f.x, f.z)


func look_dir() -> Vector3:
	return -camera.global_transform.basis.z


func eye() -> Vector3:
	return camera.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not look_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * sensitivity * 0.01
		pitch -= event.relative.y * sensitivity * 0.01 * (-1.0 if invert else 1.0)
		pitch = clampf(pitch, -1.45, 1.45)
		camera.rotation.x = pitch


func _physics_process(delta: float) -> void:
	var u = me()
	if u == null or u.dead:
		return
	# Polled, so the shield also drops when a menu, the chat or another window swallows the release.
	if shield_held and (not look_enabled or not move_enabled or u.shield == "" or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		shield_held = false
	var mounted: bool = u.mounted
	camera.position.y = lerpf(camera.position.y, 2.45 if mounted else 1.68, minf(1.0, delta * 6.0))
	var input := Vector2.ZERO
	if move_enabled:
		input = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	var sprint := move_enabled and Input.is_action_pressed("sprint") and input.y > 0.1 and stamina > 0.05 and not shield_held
	var base := (8.5 if mounted else 4.6)
	var speed := base * (1.55 if sprint else 1.0)
	if u.armor != "":
		speed *= 1.0 - float(Defs.ITEMS[u.armor].get("slow", 0.0))
	if drawing:
		speed *= 0.5
	if shield_held:
		speed *= 0.6
	if sprint and input.length() > 0.1:
		stamina = maxf(0.0, stamina - delta * (0.08 if mounted else 0.16))
	else:
		stamina = minf(1.0, stamina + delta * 0.12)
	var basis2 := global_transform.basis
	var dir := (basis2 * Vector3(input.x, 0, -input.y))
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target := dir * speed
	var accel := 10.0 if is_on_floor() else 2.5
	hv = hv.lerp(target, minf(1.0, accel * delta))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif move_enabled and Input.is_action_just_pressed("jump"):
		velocity.y = 6.2
	move_and_slide()
	_push_out_of_trees()
	# Keep inside the land.
	position.x = clampf(position.x, 6.0, m.map_size - 6.0)
	position.z = clampf(position.z, 6.0, m.map_size - 6.0)
	var ground: float = m.terrain.height_at(position.x, position.z)
	if position.y < ground - 0.5:
		position.y = ground + 0.2
		velocity.y = 0
	var moving := hv.length() > 0.6
	anim = 0
	if moving:
		anim = 10 if mounted else (2 if sprint else 1)
	if swing > 0.0:
		anim = 7
	if drawing:
		anim = 8
	if moving and is_on_floor():
		bob += delta * hv.length() * (1.0 if not mounted else 0.6)
		step_acc += hv.length() * delta
		if step_acc > (2.4 if mounted else 1.5):
			step_acc = 0.0
			Sfx.play("step", global_position, -14.0 if not mounted else -8.0, 0.7 if mounted else 1.0)
	_update_view_model(delta, u)


func _push_out_of_trees() -> void:
	var p := Vector2(position.x, position.z)
	for n in m._nodes_within(p, 2.0):
		if n.amount == 0.0:
			continue
		var r := 0.0
		match n.kind:
			"tree":
				r = 0.45 * n.scale + 0.35
			"rock":
				r = (0.85 if n.sub == "boulder" else 3.6) * n.scale
			"deposit":
				r = 1.8
		if r <= 0.0:
			continue
		var d: Vector2 = p - n.pos
		var dist := d.length()
		if dist < r and dist > 0.001:
			p = n.pos + d / dist * r
	position.x = p.x
	position.z = p.y


# --- Combat -------------------------------------------------------------------------

func can_shoot() -> bool:
	var u = me()
	return u != null and not shield_held and m.can_shoot_bow(u) and (u.weapon == "" or use_bow)


## Right mouse went down. Returns why the shield can't come up, or "".
func raise_shield() -> String:
	var u = me()
	if u == null or u.dead or not look_enabled or not move_enabled:
		return ""
	if u.shield == "":
		return "You have no shield. Take one from the armory (E)."
	shield_held = true
	drawing = false
	draw = 0.0
	return ""


func lower_shield() -> void:
	shield_held = false


## The guard opens for the length of a swing.
func shield_up() -> bool:
	return shield_held and swing <= 0.0


func primary_pressed() -> void:
	var u = me()
	if u == null or u.dead:
		return
	if can_shoot():
		if u.arrows > 0:
			drawing = true
			draw = 0.0
		else:
			attacked.emit("Your quiver is empty. Refill it at the armory (E).")
		return
	if u.bow and u.mounted and not shield_held and (u.weapon == "" or use_bow):
		attacked.emit("You can't shoot from the saddle yet. Research mounted archery at the stable (/r).")
		return
	if swing > 0.0:
		return
	swing = 0.45
	var hit: String = m.commander_strike(0)
	if hit != "":
		attacked.emit("hit:" + hit)


func primary_released() -> void:
	if not drawing:
		return
	drawing = false
	if draw < 0.15:
		return
	var origin := eye() + look_dir() * 0.6
	var dir := look_dir() + Vector3(0, 0.02, 0)
	if m.commander_shoot(0, origin, dir, clampf(draw / 0.9, 0.0, 1.0)):
		Sfx.play("bow", global_position, -4.0)
	draw = 0.0


func toggle_weapon() -> String:
	var u = me()
	if u == null:
		return ""
	if not u.bow:
		return "You have no bow. Take one from the armory (E)."
	if u.weapon == "":
		return "You only have the bow."
	use_bow = not use_bow
	return "Bow ready." if use_bow else "%s ready." % Defs.item_name(u.weapon).capitalize()


func _update_view_model(delta: float, u) -> void:
	var weapon: String = "" if can_shoot() else u.weapon
	var bow_out := can_shoot()
	if weapon != shown_weapon or u.shield != shown_shield or bow_out != shown_bow:
		shown_weapon = weapon
		shown_shield = u.shield
		shown_bow = bow_out
		vm_weapon.mesh = _vm_weapon_mesh(weapon)
		vm_shield.mesh = _vm_shield_mesh(u.shield) if u.shield != "" and not bow_out else null
		vm_bow.mesh = _vm_bow_mesh() if bow_out else null
	swing = maxf(0.0, swing - delta)
	if drawing:
		draw = minf(1.2, draw + delta)
	var b := sin(bob * 2.2) * 0.012
	var k := 0.0
	if swing > 0.0:
		var p := 1.0 - swing / 0.45
		k = sin(p * PI)
	vm_weapon.position = Vector3(0.42, -0.46 + b - k * 0.1, -0.66 - k * 0.25)
	vm_weapon.rotation = Vector3(-0.25 - k * 1.5, 0.15 - k * 0.6, 0.0)
	if u.block_t > seen_block_t:
		seen_block_t = u.block_t
		jolt = 1.0
	jolt = maxf(0.0, jolt - delta * 5.0)
	raise_k = move_toward(raise_k, 1.0 if shield_up() else 0.0, delta * 7.0)
	var up := smoothstep(0.0, 1.0, raise_k)
	# Carried low in the corner; raised across the body, just under the crosshair.
	vm_shield.position = SHIELD_LOW.lerp(SHIELD_HIGH, up) + Vector3(0, b * (1.0 - up) - jolt * 0.03, jolt * 0.07)
	vm_shield.rotation = SHIELD_LOW_ROT.lerp(SHIELD_HIGH_ROT, up) + Vector3(jolt * 0.15, 0, 0)
	vm_shield.scale = Vector3.ONE * lerpf(0.55, 0.8, up)
	vm_bow.position = Vector3(-0.05, -0.18 + b, -0.6 + draw * 0.05)
	vm_bow.rotation = Vector3(0.0, 0.0, -0.15)


func _vm_weapon_mesh(weapon: String) -> Mesh:
	var g := Geo.new()
	g.slot("skin", _flat(Color(0.72, 0.55, 0.42), 0.7))
	g.cylinder(Vector3(0.05, -0.15, 0.35), Vector3(0, 0, 0), 0.045, 0.04, 7, true)
	g.sphere(Vector3(0, 0.0, -0.02), 0.055, 3, 6)
	g.slot("sleeve", _flat(m.fac(0).color, 0.9))
	g.cylinder(Vector3(0.08, -0.25, 0.65), Vector3(0.05, -0.15, 0.35), 0.06, 0.055, 7, true)
	var wood: Material = mats.get_mat("roughwood")
	var metal := _flat(Color(0.6, 0.61, 0.64), 0.35, 0.9)
	var bronze := _flat(Color(0.72, 0.48, 0.24), 0.35, 0.9)
	var tip := metal if weapon.begins_with("iron") else (bronze if weapon.begins_with("bronze") else wood)
	match weapon:
		"club":
			g.slot("wood", wood)
			g.cylinder(Vector3(0, -0.06, 0.05), Vector3(0, 0.5, -0.05), 0.022, 0.045, 7, true, 4.0)
		"wood_spear", "bronze_spear", "iron_spear", "bronze_pike", "iron_pike":
			g.slot("wood", wood)
			g.cylinder(Vector3(0, -0.2, 0.5), Vector3(0, 0.3, -1.6), 0.022, 0.02, 6)
			g.slot("tip", tip)
			g.cone(Vector3(0, 0.3, -1.6), Vector3(0, 0.36, -1.85), 0.04, 4)
		"bronze_sword", "iron_sword":
			g.slot("grip", _flat(Color(0.2, 0.13, 0.08), 0.7))
			g.cylinder(Vector3(0, -0.06, 0.02), Vector3(0, 0.06, -0.02), 0.024, 0.024, 6)
			g.slot("tip", tip)
			g.box(Vector3(0, 0.08, -0.03), Vector3(0.18, 0.025, 0.03), 1.0, false)
			g.obox(Vector3(0, 0.45, -0.12), Vector3(0.05, 0.75, 0.012), Basis(Vector3.RIGHT, -0.3), 1.0)
		"bronze_lance", "iron_lance":
			g.slot("wood", wood)
			g.cylinder(Vector3(0, -0.1, 0.8), Vector3(0, 0.2, -2.2), 0.05, 0.025, 7)
			g.slot("tip", tip)
			g.cone(Vector3(0, 0.2, -2.2), Vector3(0, 0.22, -2.5), 0.035, 4)
	return g.finish()


func _vm_shield_mesh(shield: String) -> Mesh:
	var g := Geo.new()
	var c := Color(0.45, 0.32, 0.18) if shield == "wood_shield" else (Color(0.72, 0.48, 0.24) if shield == "bronze_shield" else Color(0.55, 0.56, 0.6))
	g.slot("s", _flat(c, 0.6 if shield == "wood_shield" else 0.35, 0.0 if shield == "wood_shield" else 0.85))
	g.cylinder(Vector3(0, 0, 0.05), Vector3(0, 0, -0.03), 0.36, 0.36, 14, true)
	g.slot("boss", _flat(Color(0.5, 0.5, 0.52), 0.3, 0.9))
	g.sphere(Vector3(0, 0, -0.04), 0.07, 3, 6, Vector3(1, 1, 0.6))
	# The back, which is the side the player sees: boards inside the rim, a team-coloured band and the arm in its straps.
	const SIDES := 28
	const BOARDS := 7
	g.slot("gap", _flat(Color(0.14, 0.09, 0.05), 0.9))
	g.cylinder(Vector3(0, 0, 0.0), Vector3(0, 0, 0.008), 0.34, 0.34, SIDES, true)
	var board_w := 0.64 / BOARDS
	for i in BOARDS:
		var x := -0.32 + (i + 0.5) * board_w
		var half := sqrt(0.335 * 0.335 - x * x)
		g.slot("board%d" % (i % 2), _flat(Color(0.40, 0.27, 0.15) if i % 2 == 0 else Color(0.34, 0.22, 0.12), 0.85))
		g.box(Vector3(x, 0, 0.014), Vector3(board_w - 0.008, half * 2.0, 0.012), 1.0)
	for i in SIDES:
		var a := Vector3(cos(TAU * i / SIDES), sin(TAU * i / SIDES), 0)
		var b := Vector3(cos(TAU * (i + 1) / SIDES), sin(TAU * (i + 1) / SIDES), 0)
		var z := Vector3(0, 0, 0.052)
		g.slot("rim", _flat(c, 0.5, 0.0 if shield == "wood_shield" else 0.6))
		g.quad(a * 0.335 + z, b * 0.335 + z, b * 0.365 + z, a * 0.365 + z, Vector3.BACK)
		g.slot("band", _flat(m.fac(0).color, 0.8))
		g.quad(a * 0.295 + z, b * 0.295 + z, b * 0.335 + z, a * 0.335 + z, Vector3.BACK)
		g.quad(a * 0.295 + z, b * 0.295 + z, b * 0.295, a * 0.295, -(a + b).normalized())
	g.slot("strap", _flat(Color(0.2, 0.12, 0.07), 0.7))
	g.box(Vector3(0.08, 0.02, 0.07), Vector3(0.035, 0.22, 0.03), 1.0, false)
	g.slot("sleeve", _flat(m.fac(0).color, 0.9))
	g.cylinder(Vector3(-0.30, -0.30, 0.17), Vector3(-0.07, -0.08, 0.10), 0.075, 0.055, 10, true)
	g.slot("skin", _flat(Color(0.72, 0.55, 0.42), 0.7))
	g.cylinder(Vector3(-0.07, -0.08, 0.10), Vector3(0.06, 0.01, 0.09), 0.045, 0.037, 10, true)
	g.sphere(Vector3(0.08, 0.02, 0.09), 0.052, 5, 10)
	g.slot("strap", null)
	g.cylinder(Vector3(-0.15, -0.155, 0.12), Vector3(-0.11, -0.117, 0.11), 0.074, 0.07, 10, false)
	return g.finish()


func _vm_bow_mesh() -> Mesh:
	var g := Geo.new()
	g.slot("wood", _flat(Color(0.42, 0.29, 0.17), 0.7))
	for i in 8:
		var a0 := -1.0 + 2.0 * i / 8.0
		var a1 := -1.0 + 2.0 * (i + 1) / 8.0
		g.cylinder(Vector3(sin(a0) * 0.05, a0 * 0.55, -cos(a0) * 0.12), Vector3(sin(a1) * 0.05, a1 * 0.55, -cos(a1) * 0.12), 0.015, 0.015, 4, false)
	g.slot("string", _flat(Color(0.85, 0.82, 0.75), 0.8))
	var pull := draw * 0.25
	g.cylinder(Vector3(0, -0.55, -0.065), Vector3(0, 0, 0.12 + pull), 0.003, 0.003, 3, false)
	g.cylinder(Vector3(0, 0, 0.12 + pull), Vector3(0, 0.55, -0.065), 0.003, 0.003, 3, false)
	if draw > 0.0 or drawing:
		g.slot("arrow", _flat(Color(0.5, 0.38, 0.22), 0.7))
		g.cylinder(Vector3(0.0, 0.0, 0.12 + pull), Vector3(0.0, 0.0, -0.6), 0.008, 0.008, 4, false)
	return g.finish()


func _flat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	mat.metallic = metal
	return mat


func refresh_bow() -> void:
	if shown_bow:
		vm_bow.mesh = _vm_bow_mesh()
