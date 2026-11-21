extends Node3D
## Close-range human. Simulation movement drives the imported gait; grip targets
## and props share actor-local coordinates (+Z forward, metres).
const Anim = preload("res://scripts/sim/match_base.gd").Anim
const MODELS = [preload("res://assets/people/villager.glb"), preload("res://assets/people/farmer.glb"), preload("res://assets/people/child.glb")]
const HAND_R := Vector3(-0.24, 0.77, 0.07)
const HAND_L := Vector3(0.24, 0.77, 0.07)
const WOOD := Vector3(-0.215, 1.42, 0.19)
const STONE := Vector3(0, 1.03, 0.27)
const FOOD := Vector3(-0.30, 0.91, 0.12)

var skeleton: Skeleton3D
var player: AnimationPlayer
var bones := {}
var model_index: int
var body_scale := 1.0
var grip_depth := 9.4 # The imported skeletons use centimetres.
var gait := 0.0
var motion := 0.0
var cargo := ""
var load_height := 0.0
var tool_angle := 0.0
var head_turn := 0.0
var face_shape := Vector3.ONE
var rig_space: Transform3D
var last_arm_targets: Array[Vector3] = []
var cloth := ShaderMaterial.new()

static func model_for(u) -> int:
	return 2 if u.child else int(u.female)

func setup(index: int) -> void:
	model_index = index
	var model: Node3D = MODELS[index].instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var mesh_instance: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	# Preserve small facial features at conversation distance.
	mesh_instance.lod_bias = 2.0
	for i in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(i)] = i
	rig_space = global_transform.affine_inverse() * skeleton.global_transform
	body_scale = 0.72 if index == 2 else 1.0
	grip_depth = 5.2 if index == 2 else 9.4

	var mat := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	cloth.shader = preload("res://shaders/villager.gdshader")
	cloth.set_shader_parameter("fabric", mat.albedo_texture)
	cloth.set_shader_parameter("normal_map", mat.normal_texture)
	cloth.set_shader_parameter("plain_linen", model_index != 0)
	mesh_instance.set_surface_override_material(0, cloth)

func customize(seed_value: float, faction_color: Color) -> void:
	cloth.set_shader_parameter("dye", faction_color.lerp(Color(0.54, 0.41, 0.31), seed_value * 0.55))
	cloth.set_shader_parameter("complexion", Color.WHITE.lerp(Color(0.78, 0.65, 0.55), seed_value))
	face_shape = Vector3(lerpf(0.93, 1.09, seed_value), lerpf(1.05, 0.97, seed_value), 1.0)
	gait = seed_value
	motion = 0.0
	load_height = 0.0
	cargo = ""
	head_turn = 0.0
	last_arm_targets.clear()

func joint(bone: String) -> Vector3:
	return rig_space * skeleton.get_bone_global_pose(bones[bone]).origin

func _aim(bone: String, child: String, target: Vector3) -> void:
	var idx: int = bones[bone]
	var pose := skeleton.get_bone_global_pose(idx)
	var direction := skeleton.get_bone_global_pose(bones[child]).origin - pose.origin
	var goal := rig_space.affine_inverse() * target - pose.origin
	_align(idx, direction, goal)

func _align(idx: int, direction: Vector3, goal: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(idx)
	if direction.length_squared() < 0.00001 or goal.length_squared() < 0.00001:
		return
	var rotation := Quaternion(direction.normalized(), goal.normalized())
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(idx)).basis.orthonormalized()
	skeleton.set_bone_pose_rotation(idx, (parent.inverse() * Basis(rotation) * pose.basis.orthonormalized()).get_rotation_quaternion())

func _reach(side: String, target: Vector3, sign_x: float) -> void:
	var arm := side + "Arm"
	var elbow := side + "ForeArm"
	var hand := side + "Hand"
	var shoulder := joint(arm)
	var a := shoulder.distance_to(joint(elbow))
	var b := joint(elbow).distance_to(joint(hand))
	var axis := shoulder.direction_to(target)
	var d := clampf(shoulder.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var along := (a * a - b * b + d * d) / (2.0 * d)
	var pole := Vector3(sign_x * 0.7, -1.0, -0.55).slide(axis).normalized()
	_aim(arm, elbow, shoulder + axis * along + pole * sqrt(maxf(0.0, a*a-along*along)))
	_aim(elbow, hand, target)

func palm(side: String) -> Vector3:
	var pose := skeleton.get_bone_global_pose(bones[side + "Hand"])
	return rig_space * (pose * (Vector3.UP * grip_depth))

func _place_hand(side: String, target: Vector3, outward: float, direction: Vector3) -> void:
	if direction.is_zero_approx():
		_reach(side, target, outward)
		return
	# IK solves for the wrist. Back up by the wrist-to-grip distance so the
	# handle lands inside the curved fingers.
	direction = direction.normalized()
	var reach := joint(side + "Hand").distance_to(palm(side))
	_reach(side, target - direction * reach, outward)
	var hand: int = bones[side + "Hand"]
	var pose := skeleton.get_bone_global_pose(hand)
	_align(hand, pose.basis.y, rig_space.basis.inverse() * direction)

func pose(anim: int, phase: float, speed: float, resource: String, delta: float, eye: Vector3, dead: bool) -> void:
	# Lower the load for pickup and delivery. Interrupt instantly for work/combat.
	if resource != "":
		cargo = resource
	elif anim not in [Anim.IDLE, Anim.WALK, Anim.CARRY] or dead:
		cargo = ""
	load_height = move_toward(load_height, float(resource != ""), delta * 4.5)
	if load_height == 0.0:
		cargo = ""
	var walking := anim in [Anim.WALK, Anim.RUN, Anim.CARRY]
	motion = move_toward(motion, speed if walking else 0.0, delta * 18.0)
	var clip := "run" if anim == Anim.RUN else "walk"
	var stride := 2.6 if clip == "run" else (1.20 if cargo != "" else 1.48)
	gait = fposmod(gait + delta * motion / (stride * body_scale), 1.0)
	skeleton.reset_bone_poses()
	if motion > 0.015:
		player.play(clip)
		player.seek(gait * player.get_animation(clip).length, true)
		# The simulation already supplies horizontal translation.
		var hips: int = bones["Hips"]
		var p := skeleton.get_bone_pose_position(hips)
		var rest := skeleton.get_bone_rest(hips).origin
		p.x = rest.x
		p.z = rest.z
		skeleton.set_bone_pose_position(hips, p)
	var beat := sin(phase)
	var swing := 0.5 + 0.5 * beat
	var working := anim in [Anim.CHOP, Anim.HAMMER, Anim.DIG, Anim.PICK, Anim.LOAD, Anim.MELEE]
	var lean := 0.012 * sin(phase * 0.6)
	if working:
		lean = 0.12 + 0.23 * swing
	if cargo != "":
		lean = 0.10 + 0.32 * (1.0 - load_height)
	var spine: int = bones["Spine02"]
	skeleton.set_bone_pose_rotation(spine, skeleton.get_bone_pose_rotation(spine) * Quaternion(Vector3.RIGHT, lean))
	var glance := clampf(atan2(eye.x, eye.z), -0.45, 0.45) if anim == Anim.IDLE and eye.z > 0 and eye.length() < 5.0 and not dead else 0.0
	head_turn = lerpf(head_turn, glance, minf(delta*4.0, 1.0))
	var head: int = bones["Head"]
	skeleton.set_bone_pose_scale(head, face_shape)
	skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head)*Quaternion(Vector3.UP, head_turn))
	var shoulders := (joint("LeftArm") + joint("RightArm")) * 0.5
	var wave := sin(TAU*gait) * minf(motion/2.0, 1.0)
	var right := shoulders + Vector3(-0.24, -0.45, 0.08+0.15*wave)*body_scale
	var left := shoulders + Vector3(0.24, -0.45, 0.08-0.15*wave)*body_scale
	tool_angle = 0.0
	if cargo != "":
		var grip_origin: Vector3
		var lift := -0.28*(1.0-smoothstep(0.0, 1.0, load_height))
		if cargo == "wood":
			grip_origin = shoulders + Vector3(-0.215, 0.075+lift, 0.19)*body_scale
			right = grip_origin - Vector3(0, 0.06, 0.04)*body_scale
		elif cargo == "food":
			right = shoulders + Vector3(-0.31, -0.41+lift*0.3, 0.13+0.05*wave)*body_scale
			grip_origin = right
		else:
			grip_origin = shoulders + Vector3(0, -0.28+lift, 0.28)*body_scale
			right = grip_origin + Vector3(-0.14, -0.04, -0.05)*body_scale
			left = grip_origin + Vector3(0.14, -0.04, -0.05)*body_scale
	elif working:
		if anim == Anim.PICK:
			right = shoulders + Vector3(-0.20, -0.31, 0.21)*body_scale
			left = shoulders + Vector3(0.12, -0.24, 0.24+0.14*swing)*body_scale
		else:
			right = shoulders + Vector3(-0.14, lerpf(0.19, -0.22, swing), lerpf(0.19, 0.33, swing))*body_scale
			tool_angle = lerpf(-1.65, 0.25, swing)
			if anim in [Anim.CHOP, Anim.DIG]:
				left = right + Basis(Vector3.RIGHT, tool_angle)*Vector3(0.10, 0.015, 0.14)*body_scale
	elif anim == Anim.SHOOT:
		left = shoulders + Vector3(0.12, 0.02, 0.40)*body_scale
		right = shoulders + Vector3(-0.11, 0.09, 0.08)*body_scale
	elif anim == Anim.RIDE:
		for side in ["Left", "Right"]:
			var leg: int = bones[side+"UpLeg"]
			skeleton.set_bone_pose_rotation(leg, skeleton.get_bone_pose_rotation(leg)*Quaternion(Vector3.RIGHT, 1.05))
			var knee: int = bones[side+"Leg"]
			skeleton.set_bone_pose_rotation(knee, skeleton.get_bone_pose_rotation(knee)*Quaternion(Vector3.RIGHT, -1.3))
		right = shoulders + Vector3(-0.19, -0.27, 0.29)*body_scale
		left = shoulders + Vector3(0.19, -0.27, 0.29)*body_scale
	if last_arm_targets.is_empty():
		last_arm_targets = [right, left]
	var weight := 1.0-exp(-delta*24.0)
	last_arm_targets[0] = last_arm_targets[0].lerp(right, weight)
	last_arm_targets[1] = last_arm_targets[1].lerp(left, weight)
	var right_dir := Vector3.ZERO
	var left_dir := Vector3.ZERO
	if cargo == "wood":
		right_dir = Vector3(0.15, 0.90, 0.35)
	elif cargo == "food" or anim == Anim.PICK:
		right_dir = Vector3(0.2, -1.0, 0.1)
	elif cargo != "":
		right_dir = Vector3(0.85, 0.28, 0.3)
		left_dir = Vector3(-0.85, 0.28, 0.3)
	elif working:
		right_dir = Vector3(0.60, -0.15, 0.5)
		if anim in [Anim.CHOP, Anim.DIG]:
			left_dir = Vector3(-0.60, -0.15, 0.5)
	_place_hand("Right", last_arm_targets[0], -1, right_dir)
	_place_hand("Left", last_arm_targets[1], 1, left_dir)

func item_pose(item: String) -> Transform3D:
	var src := HAND_R
	var target := palm("Right")
	var angle := tool_angle if item in ["axe", "hoe", "hammer", "pick"] or item.ends_with("sword") else 0.0
	if item == "bundle_wood":
		src = WOOD
		target = palm("Right") + Vector3(0, 0.06, 0.04)*body_scale
	elif item == "bundle_food":
		src = FOOD
	elif item == "bundle_stone":
		src = STONE
		target = (palm("Right")+palm("Left"))*0.5 + Vector3(0, 0.04, 0.05)*body_scale
	elif item.ends_with("shield") or item == "bow":
		src = HAND_L
		target = palm("Left")
	elif item.ends_with("helmet") or item == "crown":
		src = Vector3(0, 1.73, 0)
		target = joint("head_end")
	elif item.ends_with("armor") or item == "cloak":
		src = Vector3(0, 1.42, 0)
		target = (joint("LeftArm")+joint("RightArm"))*0.5
	var basis := Basis(Vector3.RIGHT, angle).scaled(Vector3.ONE*body_scale)
	return transform * Transform3D(basis, target-basis*src)
