extends CharacterBody3D
## The player's commander, strictly first person.

const Defs = preload("res://scripts/data/defs.gd")
const Geo = preload("res://scripts/view/geo.gd")
const BattlePose = preload("res://scripts/view/battle_pose.gd")
const Crowd = preload("res://scripts/sim/crowd.gd")

const MIN_DRAW := 0.15
const FULL_DRAW := 0.9
const BUFFER_FOR := 1.2           # a click this early still becomes the next blow

# First-person clips, timed like the third-person ones: [time, x, y, z, pitch, yaw, roll]
const VIEW_CLIPS := {
	"sword": [
		[0.0, 0.42, -0.46, -0.66, -0.25, 0.15, 0.0],
		[0.3, 0.58, -0.3, -0.84, -0.1, -0.2, -0.6],
		[0.4, 0.22, -0.28, -0.92, -0.75, 0.2, 0.85],
		[0.56, -0.24, -0.36, -0.84, -0.8, 0.35, 1.3],
		[1.0, 0.42, -0.46, -0.66, -0.25, 0.15, 0.0]],
	"thrust": [
		[0.0, 0.42, -0.46, -0.66, -0.25, 0.15, 0.0],
		[0.28, 0.46, -0.42, -0.34, -0.14, 0.04, 0.0],
		[0.4, 0.14, -0.3, -1.2, -0.16, 0.12, 0.0],
		[0.56, 0.14, -0.3, -1.17, -0.16, 0.12, 0.0],
		[1.0, 0.42, -0.46, -0.66, -0.25, 0.15, 0.0]],
	"fists": [
		[0.0, 0.34, -0.33, -0.66, -0.1, 0.15, 0.0],
		[0.3, 0.38, -0.3, -0.55, -0.05, 0.1, 0.0],
		[0.4, 0.06, -0.22, -1.0, -0.05, 0.2, 0.3],
		[1.0, 0.34, -0.33, -0.66, -0.1, 0.15, 0.0]],
}

signal attacked(result: String)


var m
var mats
var camera: Camera3D
var view_model: Node3D
var vm_weapon: MeshInstance3D
var vm_shield: MeshInstance3D
var vm_bow: MeshInstance3D
var vm_arm: MeshInstance3D    # apart from the weapon, which turns in the hand
var pitch := 0.0
var stamina := 1.0
var look_enabled := true
var move_enabled := true
var bob := 0.0
var now := 0.0                # match time up to this frame, set by the game
var queued_t := -99.0
var guard_held := false
var sprinting := false
var draw := 0.0
var kick := Vector3.ZERO      # camera recoil: pitch, yaw, roll
var struck_t := -99.0
var vm_strings: Array[MeshInstance3D] = []
var vm_arrow: MeshInstance3D
var drawing := false
var use_bow := false
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
	vm_arm = MeshInstance3D.new()
	for mi in [vm_weapon, vm_shield, vm_bow, vm_arm]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view_model.add_child(mi)
	_build_bow_parts()
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
		camera.rotation.x = pitch + kick.x


func _physics_process(delta: float) -> void:
	var u = me()
	if u == null or u.dead:
		return
	# Polled, so the shield also drops when a menu, the chat or another window swallows the release.
	var mounted: bool = u.mounted
	camera.position.y = lerpf(camera.position.y, 2.45 if mounted else 1.68, minf(1.0, delta * 6.0))
	var input := Vector2.ZERO
	if move_enabled:
		input = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	stamina = u.stamina
	var sprint: bool = move_enabled and not u.blocking and Input.is_action_pressed("sprint") and input.y > 0.1 and stamina > 0.05
	sprinting = sprint
	var base := (8.5 if mounted else 4.6)
	var speed := base * (1.55 if sprint else 1.0)
	if u.armor != "":
		speed *= 1.0 - float(Defs.ITEMS[u.armor].get("slow", 0.0))
	if drawing:
		speed *= 0.5
	elif u.blocking:
		speed *= 0.6
	elif u.swing_live:
		speed *= 0.85
	if sprint and input.length() > 0.1:
		stamina = maxf(0.0, stamina - delta * (0.08 if mounted else 0.16))
	else:
		stamina = minf(1.0, stamina + delta * (0.04 if u.blocking else 0.12))
	u.stamina = stamina
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
	_push_out_of_people(u)
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
	if u.blocking or (u.swing_start >= 0.0 and now < u.swing_hit + 0.3):
		anim = 7
	if drawing:
		anim = 8
	if moving and is_on_floor():
		bob += delta * hv.length() * (1.0 if not mounted else 0.6)
		step_acc += hv.length() * delta
		if step_acc > (2.4 if mounted else 1.5):
			step_acc = 0.0
			Sfx.play("step", global_position, -14.0 if not mounted else -8.0, 0.7 if mounted else 1.0)


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

func _process(delta: float) -> void:
	var u = me()
	if u == null or u.dead:
		return
	var in_control := look_enabled and move_enabled
	if not in_control:
		_let_go()
	if now - queued_t < BUFFER_FOR and not can_shoot() and m.commander_swing(0, now):
		queued_t = -99.0
	m.commander_block(0, guard_held, now)
	if drawing:
		draw = minf(1.2, draw + delta)
	kick = kick.lerp(Vector3.ZERO, 1.0 - exp(-delta * 12.0))
	if look_enabled:      # the intro steers the camera itself
		camera.rotation = Vector3(pitch + kick.x, kick.y, kick.z)
	_update_view_model(delta, u)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_let_go()


func _let_go() -> void:
	drawing = false
	draw = 0.0
	guard_held = false
	queued_t = -99.0


func can_shoot() -> bool:
	var u = me()
	return u != null and not guard_held and not u.blocking and m.can_shoot_bow(u) and (u.weapon == "" or use_bow)


func draw_power() -> float:
	return clampf(draw / FULL_DRAW, 0.0, 1.0) if drawing else -1.0


func primary_pressed() -> void:
	var u = me()
	if u == null or u.dead:
		return
	if can_shoot():
		if u.arrows > 0:
			drawing = true
			guard_held = false
			draw = 0.0
		else:
			attacked.emit("Your quiver is empty. Refill it at the armory (E).")
		return
	if u.bow and u.mounted and not guard_held and (u.weapon == "" or use_bow):
		attacked.emit("You can't shoot from the saddle yet. Research mounted archery at the stable (/r).")
		return
	# A click during the last blow becomes the next one, so none are lost.
	if m.commander_swing(0, now):
		queued_t = -99.0
	else:
		queued_t = now


func primary_released() -> void:
	if not drawing:
		return
	drawing = false
	if draw < MIN_DRAW:
		return
	var origin := eye() + look_dir() * 0.6
	var dir := look_dir() + Vector3(0, 0.02, 0)
	if m.commander_shoot(0, origin, dir, clampf(draw / FULL_DRAW, 0.0, 1.0), now):
		kick.x += 0.02
		Sfx.play("bow", global_position, -4.0)
	draw = 0.0


func set_guard(on: bool) -> void:
	if on and drawing:
		# With an arrow on the string, the guard button lowers the bow.
		drawing = false
		draw = 0.0
		return
	guard_held = on
	if on:
		queued_t = -99.0


## Your blow landed.
func on_landed(killed: bool) -> void:
	struck_t = now
	kick += Vector3(-0.035 if killed else -0.022, 0.0, 0.012)


## A blow reached you. dir: the way it was travelling.
func on_struck(dir: Vector2, damage: float, guard: String) -> void:
	var local := global_transform.basis.inverse() * Vector3(dir.x, 0, dir.y)
	var force := 0.35 if guard in ["block", "parry"] else 1.0
	force *= clampf(0.5 + damage * 0.06, 0.5, 1.6)
	kick += Vector3(local.z * 0.05, -local.x * 0.03, -local.x * 0.06) * force
	velocity += Vector3(dir.x, 0, dir.y) * 1.8 * force


## Nobody walks through the commander, and the commander walks through nobody.
func _push_out_of_people(u) -> void:
	var here := Vector2(position.x, position.z)
	var mine: float = Crowd.radius(u)
	var push := Vector2.ZERO
	for o in m.units_near(here, 2.0, -2):
		if o.id == u.id or o.stable >= 0 or o.in_tower != u.in_tower:
			continue
		var away: Vector2 = here - o.pos
		var d := away.length()
		var gap: float = mine + Crowd.radius(o)
		if d < gap and d > 0.001:
			# Your own people give way. The enemy doesn't.
			push += away / d * (gap - d) * (0.3 if o.faction == u.faction else 0.8)
	if push != Vector2.ZERO:
		push = push.limit_length(0.3)
		move_and_collide(Vector3(push.x, 0, push.y))


func toggle_weapon() -> String:
	var u = me()
	if u == null:
		return ""
	if not u.bow:
		return "You have no bow. Take one from the armory (E)."
	if u.weapon == "":
		return "You only have the bow."
	_let_go()
	use_bow = not use_bow
	return "Bow ready." if use_bow else "%s ready." % Defs.item_name(u.weapon).capitalize()


func _update_view_model(delta: float, u) -> void:
	var weapon: String = "" if can_shoot() else u.weapon
	var bow_out := can_shoot()
	if weapon != shown_weapon or u.shield != shown_shield or bow_out != shown_bow:
		shown_weapon = weapon
		shown_shield = u.shield
		shown_bow = bow_out
		vm_weapon.mesh = _vm_weapon_mesh(weapon) if weapon != "" else null
		vm_arm.mesh = _vm_arm_mesh()
		vm_shield.mesh = _vm_shield_mesh(u.shield) if u.shield != "" else null
		vm_bow.mesh = _vm_bow_mesh() if bow_out else null
	var b := sin(bob * 2.2) * 0.012
	var family: String = Defs.weapon_family(weapon)
	var keys: Array = VIEW_CLIPS[BattlePose.clip_for(family)]
	var k: float = BattlePose.swing_k(u.swing_start, u.swing_hit, u.swing_end, now)
	var swinging := k >= 0.0
	var f: Array = BattlePose.frame_at(keys, k) if swinging else (keys[0] as Array).slice(1)
	# The shield drops out of the way of a swing.
	var shield_at := Vector3(-0.62, -0.66, -0.66) if swinging else Vector3(-0.52, -0.46 + b, -0.64)
	var shield_turn := Vector3(0.1, 0.5, 0.05)
	var blocking: bool = u.blocking
	if blocking:
		if u.shield != "":
			shield_at = Vector3(-0.12, -0.24, -0.62)
			shield_turn = Vector3(0.05, 0.08, 0.02)
			f = [0.52, -0.5, -0.6, -0.1, 0.1, -0.2]
		else:
			f = [0.3, -0.24, -0.74, -0.2, 0.2, 1.25]     # across the body
	elif bow_out:
		f = [0.3, -0.62, -0.5, -0.5, 0.2, 0.0]
	var at := Vector3(f[0], f[1] + b, f[2])
	var turn := Vector3(f[3], f[4], f[5])
	# A short jolt when the blow bites.
	var jolt := maxf(0.0, 1.0 - (now - struck_t) / 0.12) if now >= struck_t else 0.0
	at.z += jolt * 0.06
	var ease := 1.0 - exp(-delta * (60.0 if swinging else 22.0))
	vm_weapon.position = vm_weapon.position.lerp(at, ease)
	vm_weapon.rotation = vm_weapon.rotation.lerp(turn, ease)
	vm_weapon.visible = not bow_out
	vm_shield.position = vm_shield.position.lerp(shield_at, ease)
	vm_shield.rotation = vm_shield.rotation.lerp(shield_turn, ease)
	vm_shield.visible = not bow_out or blocking
	vm_bow.visible = bow_out and not blocking
	if vm_bow.visible:
		_update_bow(b, u)
		# The bow hand comes up from the left.
		vm_arm.transform = Transform3D(Basis.from_euler(Vector3(-0.15, -0.45, 0.0)) * Basis.from_scale(Vector3(-1, 1, 1)), vm_bow.position)
	else:
		# The forearm follows the hand and only hints at how the weapon is turned,
		# so the elbow stays down out of sight.
		var held := vm_weapon.rotation
		var bend := Vector3(clampf(held.x * 0.15, -0.22, 0.1), 0.1 + absf(held.z) * 0.2, clampf(held.z * 0.12, -0.12, 0.12))
		vm_arm.transform = Transform3D(Basis.from_euler(bend), vm_weapon.position)


func _build_bow_parts() -> void:
	var cord := CylinderMesh.new()
	cord.top_radius = 0.002
	cord.bottom_radius = 0.002
	cord.height = 1.0
	cord.radial_segments = 3
	cord.rings = 0
	cord.material = _flat(Color(0.85, 0.82, 0.75), 0.8)
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = cord
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vm_bow.add_child(mi)
		vm_strings.append(mi)
	var g := Geo.new()
	g.slot("arrow", _flat(Color(0.5, 0.38, 0.22), 0.7))
	g.cylinder(Vector3(0, 0, 0), Vector3(0, 0, -0.75), 0.008, 0.008, 4, false)
	g.slot("head", _flat(Color(0.42, 0.42, 0.44), 0.4, 0.6))
	g.cone(Vector3(0, 0, -0.75), Vector3(0, 0, -0.84), 0.022, 4)
	vm_arrow = MeshInstance3D.new()
	vm_arrow.mesh = g.finish()
	vm_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vm_bow.add_child(vm_arrow)


func _update_bow(b: float, u) -> void:
	var pull := maxf(0.0, draw_power())
	# Canted right, so it frames the crosshair instead of covering it.
	vm_bow.position = Vector3(lerpf(0.32, 0.17, pull), lerpf(-0.36, -0.25, pull) + b, -0.72)
	vm_bow.rotation = Vector3(0.0, lerpf(0.05, 0.12, pull), lerpf(-0.6, -0.4, pull))
	var ends := [Vector3(0, -0.55, -0.065), Vector3(0, 0.55, -0.065)]
	var nock := Vector3(0, 0, -0.065 + pull * 0.4)
	for i in 2:
		var low: Vector3 = ends[0] if i == 0 else nock
		var high: Vector3 = nock if i == 0 else ends[1]
		var along := high - low
		var stretch := Basis(Quaternion(Vector3.UP, along.normalized())) * Basis.from_scale(Vector3(1, along.length(), 1))
		vm_strings[i].transform = Transform3D(stretch, (low + high) * 0.5)
	vm_arrow.position = nock
	vm_arrow.visible = u.arrows > 0 and (drawing or now - u.shot_t > 0.35)


func _vm_arm_mesh() -> Mesh:
	var g := Geo.new()
	g.slot("skin", _flat(Color(0.72, 0.55, 0.42), 0.7))
	g.cylinder(Vector3(0.05, -0.15, 0.35), Vector3(0, 0, 0), 0.045, 0.04, 7, true)
	g.sphere(Vector3(0, 0.0, -0.02), 0.055, 3, 6)
	g.slot("sleeve", _flat(m.fac(0).color, 0.9))
	g.cylinder(Vector3(0.08, -0.25, 0.65), Vector3(0.05, -0.15, 0.35), 0.06, 0.055, 7, true)
	return g.finish()


func _vm_weapon_mesh(weapon: String) -> Mesh:
	var g := Geo.new()
	var wood: Material = mats.get_mat("roughwood")
	var metal := _flat(Color(0.6, 0.61, 0.64), 0.35, 0.9)
	var bronze := _flat(Color(0.72, 0.48, 0.24), 0.35, 0.9)
	var tip := metal if weapon.begins_with("iron") else (bronze if weapon.begins_with("bronze") else wood)
	match weapon:
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
	return g.finish()


func _flat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = rough
	mat.metallic = metal
	return mat
