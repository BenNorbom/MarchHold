extends Node
## The opening: about 45 seconds in first person at the campfire. Skippable.

const LINES := [
	[0.0, 6.0, "MarchHold", "A borderland, a campfire, and six people who trust you."],
	[6.0, 7.0, "You are their commander", "You don't click on people. You talk to them: look at someone, press Enter, and type what you want done."],
	[13.0, 7.0, "A village grows when it is fed, fastest when well fed", "Feed your people and house them, and they will have children. Every soldier is a worker taken from the fields."],
	[20.0, 7.0, "Across the valley: Commander Rook", "He is building too. You will only know what he is doing if you send scouts, and they come back alive."],
	[27.0, 7.5, "Wood, stone, bronze, iron… gunpowder", "Build an armory and walls, mine metal. Pikes stop cavalry, cavalry runs down archers, cannons crack walls."],
	[34.5, 6.5, "Kill the crowned commander to win", "If you fall, all is lost. Your own crown marks you too."],
	[41.0, 4.0, "Press Enter to talk to your people", "Type /h at any time for help."],
]
const TOTAL := 45.0
const RIVAL_LINE := "Across the valley: Commander Rook"

var g
var t := 0.0
var yaw0 := 0.0
var pitch0 := 0.0
var done := false


func setup(game) -> void:
	g = game
	g.cmd.look_enabled = false
	g.cmd.move_enabled = false
	yaw0 = g.cmd.rotation.y
	pitch0 = g.cmd.pitch
	g.hud.compass.visible = false
	g.hud.crosshair.visible = false


func blocking() -> bool:
	return not done


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	# A slow look around the camp, ending on the fire.
	g.cmd.rotation.y = yaw0 + sin(t * 0.07) * 1.1
	g.cmd.camera.rotation.x = pitch0 - 0.12 + sin(t * 0.05) * 0.06
	for l in LINES:
		if t >= l[0] and t < l[0] + l[1]:
			var k: float = (t - l[0]) / l[1]
			var a := clampf(minf(k * 4.0, (1.0 - k) * 4.0), 0.0, 1.0)
			if g.rivals.size() > 1 and l[2] == RIVAL_LINE:
				g.hud.show_caption("Across the land: rival commanders", "They are building too, and fighting each other. You will only know what they are doing if you send scouts.")
			else:
				g.hud.show_caption(l[2], l[3])
			g.hud.caption.modulate.a = a
			g.hud.caption_sub.modulate.a = a
	if t >= TOTAL:
		skip()


func skip() -> void:
	if done:
		return
	done = true
	g.hud.show_caption("", "")
	g.hud.compass.visible = true
	g.hud.crosshair.visible = true
	g.cmd.rotation.y = yaw0
	g.cmd.camera.rotation.x = pitch0
	g.cmd.look_enabled = true
	g.cmd.move_enabled = true
	g.intro_done()
	queue_free()
