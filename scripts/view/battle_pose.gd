extends RefCounted
## Fighting poses, sampled from the simulation's attack clock. The crowd shader, the
## close-up rigs and the props in people's hands all use these.
##
## Angles in radians. arm: 0 hangs, -PI/2 points forward, -PI is overhead.
## tip: the weapon's elevation, whatever the arm is doing. turn: its swing to the side.

const Defs = preload("res://scripts/data/defs.gd")
const Anim = preload("res://scripts/sim/match_base.gd").Anim

const HIP := Vector3(0, 0.95, 0)
const SHOULDER_R := Vector3(-0.21, 1.42, 0)
const SHOULDER_L := Vector3(0.21, 1.42, 0)
const HAND_R := Vector3(-0.24, 0.77, 0.07)
const HAND_L := Vector3(0.24, 0.77, 0.07)

const IMPACT := 0.4               # where every clip connects
const FOLLOW_THROUGH := 0.55      # seconds of clip after the impact
# The shader gets lean and twist packed beside the animation number, as whole steps
# small enough to survive half-float instance data.
const CODE := 16
const STEP := 0.05
const LEAN_LOW := -0.2
const TWIST_LOW := -0.8

# [time, right arm, left arm, lean, twist, tip, turn]
const CLIPS := {
	"sword": [
		[0.0, -0.95, -0.7, 0.06, -0.1, 0.7, 0.0],
		[0.3, -1.9, -0.9, 0.0, -0.75, 0.9, -1.1],
		[0.4, -1.5, -0.6, 0.15, 0.05, 0.05, 0.1],
		[0.56, -1.1, -0.5, 0.17, 0.7, -0.2, 0.9],
		[1.0, -0.95, -0.7, 0.06, -0.1, 0.7, 0.0]],
	"thrust": [
		[0.0, -0.6, -0.72, 0.06, -0.2, 0.18, 0.0],
		[0.28, 0.1, -0.5, -0.05, -0.5, 0.1, 0.0],
		[0.4, -1.4, -1.2, 0.33, 0.3, 0.0, 0.0],
		[0.56, -1.4, -1.2, 0.33, 0.3, 0.0, 0.0],
		[1.0, -0.6, -0.72, 0.06, -0.2, 0.18, 0.0]],
	"fists": [
		[0.0, -1.1, -1.0, 0.1, -0.2, 0.0, 0.0],
		[0.3, -0.8, -1.2, 0.05, -0.5, 0.0, 0.0],
		[0.4, -1.6, -0.9, 0.2, 0.4, 0.0, 0.0],
		[1.0, -1.1, -1.0, 0.1, -0.2, 0.0, 0.0]],
}


static func clip_for(family: String) -> String:
	return family if CLIPS.has(family) else "thrust"


## How far through its clip a swing is, or -1 when there's none to show.
static func swing_k(start: float, hit: float, end: float, now: float) -> float:
	if start < 0.0 or now < start:
		return -1.0
	var stop := minf(end, hit + FOLLOW_THROUGH)
	if now >= stop:
		return -1.0
	if now < hit:
		return IMPACT * (now - start) / maxf(hit - start, 0.001)
	return IMPACT + (1.0 - IMPACT) * (now - hit) / maxf(stop - hit, 0.001)


static func frame_at(keys: Array, k: float) -> Array:
	var i := 0
	while i < keys.size() - 2 and k > float(keys[i + 1][0]):
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var w := clampf((k - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	var out := []
	for c in range(1, a.size()):
		out.append(lerpf(a[c], b[c], w))
	return out


## The pose to draw, or {} when the ordinary animation will do.
static func sample(u, now: float) -> Dictionary:
	if u.dead:
		return {}
	var k := swing_k(u.swing_start, u.swing_hit, u.swing_end, now)
	var reeling: bool = now < u.stun_t
	var shooting: bool = u.anim == Anim.SHOOT
	if k < 0.0 and not reeling and not shooting and not u.blocking and u.anim != Anim.MELEE:
		return {}
	var family := Defs.weapon_family(u.weapon)
	var p := {"family": family, "ride": u.mounted, "guard": false, "bow": false, "draw": 0.0}
	var f: Array
	if u.blocking:
		p["guard"] = true
		if u.shield != "":
			f = [-0.7, -1.05, 0.12, 0.1, 1.2, 0.0]
		else:
			f = [-1.55, -1.2, 0.05, 0.15, 0.4, 1.3]
	elif reeling:
		f = [-0.35, -0.2, -0.2, 0.35, 0.9, -0.5]
	elif k >= 0.0:
		f = frame_at(CLIPS[clip_for(family)], k)
	elif shooting:
		p["bow"] = true
		var since: float = now - u.shot_t
		if since < 0.35:
			f = [-1.15, -1.57, 0.02, 0.6, 0.0, 0.0]     # just loosed
		else:
			var draw := clampf((since - 0.35) / 1.2, 0.0, 1.0)
			p["draw"] = draw
			f = [lerpf(-1.65, -1.4, draw), -1.57, 0.04, lerpf(0.1, 0.55, draw), 0.0, 0.0]
	else:
		f = (CLIPS[clip_for(family)][0] as Array).slice(1)
		var breath := sin(now * 3.2 + float(u.id))
		f[0] += breath * 0.05
		f[1] -= breath * 0.03
	p["arm_r"] = f[0]
	p["arm_l"] = f[1]
	p["lean"] = f[2]
	p["twist"] = f[3]
	# From the saddle the point has to come down to a man's chest.
	p["tip"] = float(f[4]) - (0.2 if u.mounted and clip_for(family) == "thrust" else 0.0)
	p["turn"] = f[5]
	return p


## Instance data for the crowd shader (see person.gdshader).
static func encode(p: Dictionary, seed_value: float) -> Color:
	var lean := clampi(roundi((float(p["lean"]) - LEAN_LOW) / STEP), 0, 15)
	var twist := clampi(roundi((float(p["twist"]) - TWIST_LOW) / STEP), 0, 31)
	var code := CODE + (1 if p["ride"] else 0) + lean * 2 + twist * 32
	return Color(code, p["arm_r"], p["arm_l"], seed_value)


## Where the crowd shader puts a hand.
static func crowd_hand(p: Dictionary, right: bool) -> Vector3:
	var pivot := SHOULDER_R if right else SHOULDER_L
	var rest := HAND_R if right else HAND_L
	var v := Basis(Vector3.RIGHT, p["arm_r" if right else "arm_l"]) * (rest - pivot) + pivot
	return Basis(Vector3.UP, p["twist"]) * (Basis(Vector3.RIGHT, p["lean"]) * (v - HIP)) + HIP


static func in_left_hand(item: String) -> bool:
	return item == "bow" or item.ends_with("shield")


## A held prop's transform inside its owner, with the grip at `hand`.
static func prop(p: Dictionary, item: String, hand: Vector3, scale_by: float = 1.0) -> Transform3D:
	var body := Basis(Vector3.UP, p["twist"])
	var src := HAND_R
	var turned: Basis
	if item.ends_with("shield"):
		src = HAND_L
		turned = body * Basis(Vector3.UP, -PI * 0.5 if p["guard"] else -0.8)
	elif item == "bow":
		src = HAND_L
		turned = body
	else:
		var tip: float = p["tip"]
		var pitch := -tip
		if item.ends_with("spear") or item.ends_with("pike"):
			pitch = PI * 0.5 - tip        # these are modelled point up
			# Long shafts are held further along.
			src += Vector3(0, 0.9 if item.ends_with("pike") else 0.2, 0)
		elif item.ends_with("lance"):
			pitch += 0.17
		turned = body * Basis(Vector3.UP, p["turn"]) * Basis(Vector3.RIGHT, pitch)
	var b := turned.scaled(Vector3.ONE * scale_by)
	return Transform3D(b, hand - b * src)
