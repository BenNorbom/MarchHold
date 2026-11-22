extends Control
## What the commander needs to know while fighting: who a blow would hit, blows on
## the way, whether one landed, and where one came from.

const REACH := Color(1.0, 0.42, 0.3)
const PARRY := Color(0.55, 0.85, 1.0)
const HURT := Color(0.9, 0.1, 0.06)
const INCOMING := Color(1.0, 0.62, 0.15)
const PARRY_CUE := 0.25           # a warning turns blue this long before the blow lands

# Set every frame by the game.
var in_reach := false
var target_hp := -1.0
var threats: Array = []           # [angle clockwise from ahead, seconds until it lands]
var guarding := false
var has_shield := false
var draw_power := -1.0
var stamina := 1.0
var health := 1.0

var marker_t := 0.0
var marker_col := Color.WHITE
var marker_big := false
var hurts: Array = []             # [angle, strength]
var flash := 0.0
var edge: GradientTexture2D
var was_drawn := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	edge = GradientTexture2D.new()
	edge.gradient = g
	edge.fill = GradientTexture2D.FILL_RADIAL
	edge.fill_from = Vector2(0.5, 0.5)
	edge.fill_to = Vector2(1.0, 0.95)
	edge.width = 256
	edge.height = 256


func landed(killed: bool, guard: String) -> void:
	marker_t = 0.35 if killed else 0.22
	marker_big = killed
	marker_col = Color.WHITE
	if killed:
		marker_col = REACH
	elif guard != "":
		marker_col = Color(1.0, 0.85, 0.5)


func parried() -> void:
	marker_t = 0.45
	marker_big = true
	marker_col = PARRY


func hurt(angle: float, damage: float) -> void:
	hurts.append([angle, 1.0])
	if hurts.size() > 6:
		hurts.pop_front()
	flash = minf(1.0, flash + 0.25 + damage * 0.03)


func _process(delta: float) -> void:
	marker_t = maxf(0.0, marker_t - delta)
	flash = maxf(0.0, flash - delta * 1.8)
	for h in hurts:
		h[1] -= delta * 1.1
	hurts = hurts.filter(func(h): return h[1] > 0.0)
	var showing := in_reach or guarding or draw_power >= 0.0 or marker_t > 0.0 or flash > 0.0 or health < 0.3 or not threats.is_empty() or not hurts.is_empty()
	if showing or was_drawn:
		queue_redraw()
	was_drawn = showing


func _draw() -> void:
	var mid := size * 0.5
	var red := flash * 0.55
	if health < 0.3:
		red = maxf(red, (0.3 - health) * 1.2 + 0.05 * sin(Time.get_ticks_msec() * 0.006))
	if red > 0.0:
		draw_texture_rect(edge, Rect2(Vector2.ZERO, size), false, Color(HURT, red))
	if in_reach:
		draw_arc(mid, 11.0, 0.0, TAU, 28, Color(REACH, 0.9), 2.0, true)
		if target_hp >= 0.0:
			var bar := Rect2(mid + Vector2(-35, -34), Vector2(70, 5))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(70 * target_hp, 5)), REACH)
	if draw_power >= 0.0:
		var col := Color.WHITE if draw_power < 1.0 else Color(1.0, 0.85, 0.4)
		draw_arc(mid, 17.0, -PI * 0.5, -PI * 0.5 + TAU * maxf(draw_power, 0.01), 32, Color(col, 0.85), 3.0, true)
	if guarding:
		var col := PARRY if stamina > 0.05 else HURT       # red: the guard is broken
		var r := 30.0 if has_shield else 24.0
		draw_arc(mid, r, PI * 0.2, PI * 0.8, 20, Color(0, 0, 0, 0.35), 6.0, true)
		if stamina > 0.05:
			draw_arc(mid, r, PI * 0.5 - PI * 0.3 * stamina, PI * 0.5 + PI * 0.3 * stamina, 20, Color(col, 0.9), 4.0, true)
		else:
			draw_arc(mid, r, PI * 0.2, PI * 0.8, 20, Color(col, 0.9), 4.0, true)
	for th in threats:
		var a: float = float(th[0]) - PI * 0.5
		var dir := Vector2.from_angle(a)
		var across := dir.orthogonal()
		var now_col := PARRY if float(th[1]) <= PARRY_CUE else INCOMING
		var tip := mid + dir * 52.0
		var back := mid + dir * 68.0
		draw_colored_polygon(PackedVector2Array([tip, back + across * 11.0, back - across * 11.0]), Color(now_col, 0.95))
	for h in hurts:
		var a: float = float(h[0]) - PI * 0.5
		draw_arc(mid, 92.0, a - 0.35, a + 0.35, 16, Color(HURT, 0.85 * float(h[1])), 8.0, true)
	if marker_t > 0.0:
		var inner := 8.0
		var outer := 19.0 if marker_big else 14.0
		var col := Color(marker_col, minf(1.0, marker_t * 7.0))
		for q in 4:
			var dir := Vector2.from_angle(PI * 0.25 + q * PI * 0.5)
			draw_line(mid + dir * inner, mid + dir * outer, col, 3.0 if marker_big else 2.0, true)
