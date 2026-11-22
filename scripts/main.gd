extends Node
## App entry point: input map, title screen, and starting/ending matches.
## Developer flag:  -- --shot=<png path> [--shot-seconds=N]  renders a match and saves a screenshot.

const MainMenu = preload("res://scripts/ui/main_menu.gd")
const Game = preload("res://scripts/game/game.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

var menu: Control
var menu_layer: CanvasLayer
var game: Node
var last_opts := {}
var shot_path := ""
var shot_seconds := 6.0
var shot_view := ""
var shot_demo := false
var shot_battle := 0
var smoke := false
var shot_menu := false
var shot_ui := ""
var smoke_tutorial := false


func _ready() -> void:
	DisplayServer.window_set_title("MarchHold")
	_register_inputs()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--shot-seconds="):
			shot_seconds = float(a.substr(15))
		elif a.begins_with("--shot-view="):
			shot_view = a.substr(12)
		elif a == "--shot-demo":
			shot_demo = true
		elif a == "--shot-battle":
			shot_battle = 12
		elif a.begins_with("--shot-battle="):
			shot_battle = int(a.substr(14))
		elif a == "--smoke":
			smoke = true
		elif a == "--shot-menu":
			shot_menu = true
		elif a.begins_with("--shot-ui="):
			shot_ui = a.substr(10)
		elif a == "--smoke-tutorial":
			smoke_tutorial = true
	if shot_menu:
		_show_menu()
		await get_tree().create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("menu shot saved")
		get_tree().quit()
		return
	if smoke_tutorial:
		Settings.data["intro_seen"] = false
		_start({"tutorial": true, "seed": 0})
		await get_tree().create_timer(4.0).timeout
		if shot_path != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shot_path)
		print("intro running: ", game.intro != null)
		if game.intro:
			game.intro.skip()
		await get_tree().create_timer(1.0).timeout
		print("tutorial step: ", game.tutorial.step)
		game._on_chat("gather wood")
		for i in 50:
			game.m.tick(0.1)
			game.tutorial.tick(0.1)
		print("tutorial step after order: ", game.tutorial.step)
		for e in game.hud.log_lines:
			print("  ", e["node"].get_parsed_text())
		get_tree().quit()
		return
	if smoke:
		Settings.data["intro_seen"] = true
		_start({"seed": 777, "difficulty": 1})
		_smoke()
		return
	if shot_path != "":
		Settings.data["intro_seen"] = true
		_start({"seed": 4242, "difficulty": 1})
		if shot_demo:
			_demo_buildings()
		if shot_battle > 0:
			_demo_battle(shot_battle)
		_take_shot()
		return
	_show_menu()


func _register_inputs() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "jump": [KEY_SPACE],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _show_menu() -> void:
	if game:
		game.queue_free()
		game = null
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	menu = MainMenu.new()
	menu_layer.add_child(menu)
	menu.start_match.connect(_start)
	menu.quit_game.connect(func(): get_tree().quit())


func _start(opts: Dictionary) -> void:
	last_opts = opts
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
		menu = null
	game = Game.new()
	add_child(game)
	game.start(opts)
	game.finished.connect(_on_finished)


func _on_finished(action: String) -> void:
	match action:
		"menu":
			_show_menu()
		"again":
			game.queue_free()
			game = null
			var o := last_opts.duplicate()
			o["seed"] = 0
			_start(o)
		"quit":
			get_tree().quit()
		"settings":
			var p := SettingsPanel.new()
			game.hud.root.add_child(p)
			p.closed.connect(func():
				if game:
					game.cmd.apply_settings())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		Settings.set_val("fullscreen", not Settings.get_val("fullscreen", false))
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		var img := get_viewport().get_texture().get_image()
		var dir := OS.get_user_data_dir() + "/screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir + "/marchhold_%d.png" % Time.get_unix_time_from_system()
		img.save_png(path)
		if game:
			game.hud.show_toast("Screenshot saved")


## Developer view: a finished settlement around the player's camp.
func _demo_buildings() -> void:
	var m = game.m
	var home: Vector2 = m.home_pos(0)
	var f = m.fac(0)
	f.age = 4
	var plan := [["hut", 14, 0.4], ["hut", 16, 1.2], ["house", 22, 2.0], ["house", 24, 2.7], ["armory", 20, 3.5], ["granary", 26, 4.3],
		["stable", 32, 5.0], ["smelter", 30, 5.8], ["watch_post", 36, 0.9], ["tower", 40, 2.4], ["university", 44, 3.1], ["farm", 34, 4.0],
		["stockpile", 18, 5.4], ["lodge", 28, 6.1]]
	for p in plan:
		var pos: Vector2 = home + Vector2.from_angle(p[2]) * float(p[1])
		var r: Dictionary = m.place_site(0, p[0], pos, p[2] + PI)
		if r.get("ok", false):
			var b = m.bld(r["id"])
			if p[0] in ["armory", "smelter"]:
				b.tier = 1
			b.paid = true
			m._complete(b)
	var w: Dictionary = m.place_wall(0, "stone_wall", [home + Vector2(-30, -50), home + Vector2(10, -56), home + Vector2(40, -45)])
	for id in w.get("ids", []):
		m._complete(m.bld(id))
	var pw: Dictionary = m.place_wall(0, "palisade", [home + Vector2(-50, 10), home + Vector2(-56, 40)])
	for id in pw.get("ids", []):
		m._complete(m.bld(id))
	for k in 6:
		var u = m.spawn_unit(0, "villager", home + Vector2(4 + k, 6))
		u.name = "Demo"
		u.weapon = ["wood_spear", "bronze_sword", "iron_pike", "", "club", "bronze_spear"][k]
		u.shield = "bronze_shield" if k == 1 else ""
		u.armor = "bronze_armor" if k == 1 else ""
		u.bow = k == 3
	var cn = m.spawn_unit(0, "cannon", home + Vector2(10, -8))
	var h = m.spawn_unit(-1, "horse", home + Vector2(-6, 9))


## Developer flag --shot-battle[=N]: two lines of N meet in front of the commander.
func _demo_battle(n: int) -> void:
	var m = game.m
	var me = m.commander(0)
	var ahead := Vector2(sin(me.facing), cos(me.facing))
	var middle: Vector2 = me.pos + ahead * 16.0
	var kits := ["club", "wood_spear", "bronze_sword", "bow", "iron_pike", "wood_spear"]
	for side in 2:
		var men := []
		for k in n:
			var back := 7.0 + (k / 12) * 1.8
			var at: Vector2 = middle + ahead * (back if side else -back) + ahead.orthogonal() * (k % 12 - 5.5) * 1.6
			var u = m.spawn_unit(side, "villager", at)
			u.name = "Demo"
			u.bow = kits[k % kits.size()] == "bow"
			u.arrows = 16 if u.bow else 0
			u.weapon = "" if u.bow else kits[k % kits.size()]
			u.shield = "wood_shield" if k % 3 == 2 else ""
			men.append(u)
		var c = m.make_crew(side, men)
		c.steps = [{"action": "attack", "subject": "", "count": 0, "amount": 0, "where": ""}]
		c.state = {"target": middle}
		c.start_size = men.size()
		for u in men:
			m._set_task(u, "attack")
		m._assign_slots(c)


## Developer smoke test: drives the real game through its main paths.
func _smoke() -> void:
	var g = game
	var m = g.m
	await get_tree().create_timer(2.0).timeout
	var home: Vector2 = m.home_pos(0)
	var say := func(t: String):
		print("> ", t)
		g._on_chat(t)
	say.call("gather wood")
	say.call("pick berries")
	for i in 600:
		m.tick(0.1)
		g.ai.update(0.1)
	g._process(0.016)
	say.call("/b")
	print("menu open: ", g.hud.menu_open, " items: ", g.menu_items.size())
	g._menu_select(1)
	print("placing: ", g.placing, " type: ", g.place_type)
	for k in 30:
		var p: Vector2 = home + Vector2.from_angle(k * 0.7) * (16.0 + k)
		if m.site_problem(0, g.place_type, p, 0.0) == "":
			g.place_pos = p
			g.place_rot = 0.0
			g.place_ok = true
			break
	g._place_click()
	print("placing after click: ", g.placing)
	say.call("build a palisade")
	g.wall_points = [home + Vector2(-25, 30), home + Vector2(0, 36)]
	g.place_pos = home + Vector2(20, 32)
	g._finish_wall()
	say.call("make spears")
	print("log lines before scout: ", g.hud.log_lines.size(), " crews: ", m.crews_of(0).size())
	say.call("send a scout east")
	print("log lines after scout: ", g.hud.log_lines.size(), " crews: ", m.crews_of(0).size(), " last: ", g.hud.log_lines[-1]["node"].text)
	say.call("@all fall back")
	say.call("to arms")
	say.call("cancel")
	say.call("what is the meaning of the weather")
	for cmdtxt in ["/l", "/p", "/s", "/t", "/h", "/c", "/b hut", "/c arrows 2"]:
		say.call(cmdtxt)
		if g.hud.menu_open:
			g._close_menu()
		if g.placing:
			g._cancel_place()
	g._toggle_map()
	g._process(0.016)
	g._toggle_map()
	g.cmd.primary_pressed()
	print("gear: ", m.commander_take_gear(0))
	print("mount: ", m.commander_mount(0))
	m.fac(0).stock["wood"] = 400.0
	m.fac(0).stock["stone"] = 200.0
	say.call("gather 30 wood then build a hut")
	if g.placing:
		for k in 40:
			var p2: Vector2 = home + Vector2.from_angle(k * 0.9) * (20.0 + k)
			if m.site_problem(0, "hut", p2, 0.0) == "":
				g.place_pos = p2
				g.place_ok = true
				break
		g._place_click()
	for i in 1200:
		m.tick(0.1)
		g.ai.update(0.1)
		if i % 20 == 0:
			g._process(0.05)
	g._process(0.016)
	print("--- log")
	for e in g.hud.log_lines:
		print("  ", e["node"].get_parsed_text())
	var f = m.fac(0)
	print("pop %d housing %d wood %d buildings %d crews %d t=%.0f" % [f.pop, f.housing, f.stock["wood"], m.buildings_of(0).size(), m.crews_of(0).size(), m.t])
	get_tree().quit()


func _take_shot() -> void:
	await get_tree().create_timer(shot_seconds).timeout
	if shot_view != "" and game:
		var parts := shot_view.split(",")
		if parts.size() >= 5:
			game.cmd.set_physics_process(false)
			game.cmd.position = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			game.cmd.rotation.y = deg_to_rad(float(parts[3]))
			game.cmd.pitch = deg_to_rad(float(parts[4]))
			game.cmd.camera.rotation.x = game.cmd.pitch
			await get_tree().create_timer(2.0).timeout
	if game and shot_ui != "":
		match shot_ui:
			"map":
				game.m.fac(0).knowledge.fill(game.m.t - 120.0)
				game._toggle_map()
			"build":
				game._menu_build()
			"ledger":
				game._menu_ledger()
			"chat":
				game.hud.log_line("Hal is back from the east. Just now: their camp is about 650 m northeast; I saw about 8 spearmen.", "report")
				game.open_chat()
		await get_tree().create_timer(1.0).timeout
	if game:
		print("home: ", game.m.home_pos(0), " enemy: ", game.m.home_pos(1), " cmd: ", game.cmd.position, " paused: ", game.paused)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	print("shot saved: ", shot_path, " fps=", Engine.get_frames_per_second())
	get_tree().quit()
