extends Control
## Title screen: new match, the tutorial, settings, credits.

signal start_match(opts: Dictionary)
signal quit_game

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const Defs = preload("res://scripts/data/defs.gd")

var main_box: VBoxContainer
var match_panel: PanelContainer
var credits_panel: PanelContainer
var terra_status: Label
var difficulty: OptionButton
var map_pick: OptionButton
var map_note: Label
var strategy: OptionButton
var seed_edit: LineEdit
var calm: CheckBox
var t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.045, 0.04)
	add_child(bg)
	var art := Control.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.draw.connect(_draw_art.bind(art))
	add_child(art)
	var title := Label.new()
	title.text = "MarchHold"
	title.theme_type_variation = "BigTitle"
	title.add_theme_font_size_override("font_size", 92)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 90)
	title.size = Vector2(1000, 120)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	main_box = VBoxContainer.new()
	main_box.set_anchors_preset(Control.PRESET_CENTER)
	main_box.position = Vector2(-170, -40)
	main_box.size = Vector2(340, 340)
	main_box.add_theme_constant_override("separation", 12)
	add_child(main_box)
	_button(main_box, "New match", _show_match)
	var tut_label := "The Founding (tutorial)" if not Settings.get_val("tutorial_done", false) else "The Founding (tutorial) ✓"
	_button(main_box, tut_label, func(): start_match.emit({"tutorial": true, "seed": 0}))
	_button(main_box, "Settings", _show_settings)
	_button(main_box, "Credits", func(): credits_panel.visible = true)
	_button(main_box, "Quit", func(): quit_game.emit())
	terra_status = Label.new()
	terra_status.theme_type_variation = "Small"
	terra_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	terra_status.position = Vector2(18, -36)
	add_child(terra_status)
	_update_terra_status()
	Settings.changed.connect(_update_terra_status)
	_build_match_panel()
	_build_credits()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 50)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Sfx.play("click", null, -8.0))
	parent.add_child(b)
	return b


func _draw_art(c: Control) -> void:
	# A dusk sky and layered hills, drawn procedurally.
	var w := c.size.x
	var h := c.size.y
	for i in 24:
		var k := float(i) / 24.0
		var col := Color(0.11, 0.09, 0.08).lerp(Color(0.52, 0.33, 0.2), pow(k, 1.6))
		c.draw_rect(Rect2(0, h * 0.25 + k * h * 0.45, w, h * 0.45 / 24.0 + 1), col)
	c.draw_rect(Rect2(0, 0, w, h * 0.25 + 1), Color(0.11, 0.09, 0.08))
	c.draw_circle(Vector2(w * 0.7, h * 0.6), 60, Color(0.95, 0.7, 0.4, 0.5))
	var layers := [[0.62, Color(0.2, 0.15, 0.12)], [0.7, Color(0.14, 0.11, 0.09)], [0.8, Color(0.08, 0.065, 0.055)]]
	for li in layers.size():
		var base: float = layers[li][0]
		var pts := PackedVector2Array()
		pts.append(Vector2(0, h))
		for x in range(0, int(w) + 40, 40):
			var y := h * base + sin(x * 0.004 + li * 1.7) * 40.0 + sin(x * 0.011 + li) * 18.0
			pts.append(Vector2(x, y))
		pts.append(Vector2(w, h))
		c.draw_colored_polygon(pts, layers[li][1])
	# A small camp: tents and a fire glow.
	var cx := w * 0.28
	var cy := h * 0.8 + 6
	c.draw_circle(Vector2(cx, cy), 26, Color(1.0, 0.55, 0.2, 0.16))
	c.draw_circle(Vector2(cx, cy), 5, Color(1.0, 0.7, 0.3))
	for k in 3:
		var tx := cx - 60 + k * 55
		c.draw_colored_polygon(PackedVector2Array([Vector2(tx - 18, cy + 4), Vector2(tx + 18, cy + 4), Vector2(tx, cy - 26)]), Color(0.05, 0.04, 0.035))


func _build_match_panel() -> void:
	match_panel = PanelContainer.new()
	match_panel.theme_type_variation = "MenuPanel"
	match_panel.set_anchors_preset(Control.PRESET_CENTER)
	match_panel.custom_minimum_size = Vector2(560, 420)
	match_panel.position = Vector2(-280, -150)
	match_panel.visible = false
	add_child(match_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	match_panel.add_child(v)
	var t2 := Label.new()
	t2.text = "New match — you against Commander Rook"
	t2.theme_type_variation = "Title"
	v.add_child(t2)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	var l1 := Label.new()
	l1.text = "Difficulty"
	g.add_child(l1)
	difficulty = OptionButton.new()
	for d in ["Easy", "Normal", "Hard"]:
		difficulty.add_item(d)
	difficulty.selected = int(Settings.get_val("difficulty", 1))
	g.add_child(difficulty)
	var map_label := Label.new()
	map_label.text = "Map size"
	g.add_child(map_label)
	map_pick = OptionButton.new()
	var saved_map := str(Settings.get_val("map", Defs.MAP_DEFAULT))
	if not Defs.MAP_SIZES.has(saved_map):
		saved_map = Defs.MAP_DEFAULT
	for id in Defs.MAP_SIZES:
		var info: Dictionary = Defs.MAP_SIZES[id]
		var side: String = "1 km × 1 km" if info["size"] >= 1000 else "%d × %d m" % [info["size"], info["size"]]
		map_pick.add_item("%s (%s)" % [info["name"], side])
		map_pick.set_item_metadata(map_pick.item_count - 1, id)
		if id == saved_map:
			map_pick.select(map_pick.item_count - 1)
	map_pick.item_selected.connect(func(_i: int): _update_map_note())
	g.add_child(map_pick)
	var l2 := Label.new()
	l2.text = "Rook's opening"
	g.add_child(l2)
	strategy = OptionButton.new()
	for s in ["Random", "Rush", "Boom", "Turtle", "Cavalry", "Cannons"]:
		strategy.add_item(s)
	g.add_child(strategy)
	var l3 := Label.new()
	l3.text = "Map seed"
	g.add_child(l3)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	g.add_child(seed_edit)
	var l4 := Label.new()
	l4.text = ""
	g.add_child(l4)
	calm = CheckBox.new()
	calm.text = "Calm start: Rook won't attack for 10 minutes"
	calm.button_pressed = bool(Settings.get_val("calm_start", false))
	g.add_child(calm)
	map_note = Label.new()
	map_note.theme_type_variation = "Small"
	map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(map_note)
	_update_map_note()
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		match_panel.visible = false
		main_box.visible = true)
	h.add_child(back)
	var go := Button.new()
	go.text = "Start"
	go.custom_minimum_size = Vector2(180, 46)
	go.pressed.connect(_start)
	h.add_child(go)
	v.add_child(h)


func _update_map_note() -> void:
	var info: Dictionary = Defs.MAP_SIZES[map_pick.get_selected_metadata()]
	map_note.text = "The camps start at least %d m apart. Kill the crowned commander to win." % info["min_start"]


func _show_match() -> void:
	main_box.visible = false
	match_panel.visible = true


func _start() -> void:
	Settings.data["difficulty"] = difficulty.selected
	Settings.data["map"] = map_pick.get_selected_metadata()
	Settings.data["calm_start"] = calm.button_pressed
	Settings.save_all()
	var s := seed_edit.text.strip_edges()
	var seed_val := int(s) if s.is_valid_int() else (hash(s) % 900000 + 1000 if s != "" else 0)
	start_match.emit({"difficulty": difficulty.selected, "map": map_pick.get_selected_metadata(), "strategy": strategy.get_item_text(strategy.selected).to_lower(),
		"seed": absi(seed_val), "calm_start": calm.button_pressed})


func _show_settings() -> void:
	main_box.visible = false
	var p := SettingsPanel.new()
	add_child(p)
	p.closed.connect(func(): main_box.visible = true)
	p.closed.connect(_update_terra_status)


func _update_terra_status() -> void:
	terra_status.text = "v" + Defs.VERSION + (" · Terra on" if Settings.terra_available() else " · Terra off")


func _build_credits() -> void:
	credits_panel = PanelContainer.new()
	credits_panel.theme_type_variation = "MenuPanel"
	credits_panel.set_anchors_preset(Control.PRESET_CENTER)
	credits_panel.custom_minimum_size = Vector2(700, 430)
	credits_panel.position = Vector2(-350, -160)
	credits_panel.visible = false
	add_child(credits_panel)
	var v := VBoxContainer.new()
	credits_panel.add_child(v)
	var t3 := Label.new()
	t3.text = "Credits"
	t3.theme_type_variation = "Title"
	v.add_child(t3)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(660, 300)
	body.text = "MarchHold v%s\n\nMade with Godot Engine (MIT licence, godotengine.org).\nTextures: Poly Haven (CC0, polyhaven.com).\nFonts: Cinzel and EB Garamond (SIL Open Font License).\nAll models, sounds, trees and characters are generated procedurally by the game.\nInstaller: Inno Setup (jrsoftware.org).\n\nTerra can use your ChatGPT plan or your OpenAI API key." % Defs.VERSION
	v.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): credits_panel.visible = false)
	v.add_child(close)
