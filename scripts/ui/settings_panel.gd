extends PanelContainer
## Settings: Terra (OpenAI key and model), graphics, controls and sound.

signal closed

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var key_edit: LineEdit
var key_status: Label
var model_edit: LineEdit
var quality: OptionButton
var sens: HSlider
var fov: HSlider
var vol: HSlider
var limit: SpinBox
var invert: CheckBox
var full: CheckBox
var hints: CheckBox


func _ready() -> void:
	theme = UiTheme.build()
	theme_type_variation = "MenuPanel"
	custom_minimum_size = Vector2(760, 660)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = -330
	offset_bottom = 330
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var t := Label.new()
	t.text = "Settings"
	t.theme_type_variation = "Title"
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_label(grid, "OpenAI API key")
	var kb := HBoxContainer.new()
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "sk-… (stored encrypted on this PC)"
	key_edit.custom_minimum_size = Vector2(360, 0)
	key_edit.text = Settings.api_key
	kb.add_child(key_edit)
	var get_key := Button.new()
	get_key.text = "Get a key"
	get_key.pressed.connect(func(): OS.shell_open("https://platform.openai.com/api-keys"))
	kb.add_child(get_key)
	grid.add_child(kb)
	_label(grid, "")
	key_status = Label.new()
	key_status.theme_type_variation = "Small"
	key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_status.custom_minimum_size = Vector2(460, 0)
	grid.add_child(key_status)
	_label(grid, "Order model")
	model_edit = LineEdit.new()
	model_edit.text = str(Settings.get_val("model", Settings.DEFAULT_MODEL))
	grid.add_child(model_edit)
	_label(grid, "Terra requests per match")
	limit = SpinBox.new()
	limit.min_value = 10
	limit.max_value = 1000
	limit.step = 10
	limit.value = float(Settings.get_val("request_limit", 120))
	grid.add_child(limit)
	_label(grid, "Graphics")
	quality = OptionButton.new()
	for q in ["Low (integrated graphics)", "Medium", "High"]:
		quality.add_item(q)
	quality.selected = int(Settings.get_val("quality", 1))
	grid.add_child(quality)
	_label(grid, "Mouse sensitivity")
	sens = _slider(grid, 0.03, 0.3, float(Settings.get_val("sensitivity", 0.11)))
	_label(grid, "Field of view")
	fov = _slider(grid, 60.0, 100.0, float(Settings.get_val("fov", 75.0)))
	_label(grid, "Volume")
	vol = _slider(grid, 0.0, 1.0, float(Settings.get_val("volume", 0.8)))
	_label(grid, "")
	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 18)
	invert = CheckBox.new()
	invert.text = "Invert mouse Y"
	invert.button_pressed = bool(Settings.get_val("invert_y", false))
	checks.add_child(invert)
	full = CheckBox.new()
	full.text = "Fullscreen (F11)"
	full.button_pressed = bool(Settings.get_val("fullscreen", false))
	checks.add_child(full)
	hints = CheckBox.new()
	hints.text = "Show tips"
	hints.button_pressed = bool(Settings.get_val("hints", true))
	checks.add_child(hints)
	grid.add_child(checks)
	var note := Label.new()
	note.theme_type_variation = "Small"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Without a key, simple orders and every slash command still work. With a key, Terra turns anything you type into a plan; each request is billed to your OpenAI account. Graphics changes apply to the next match."
	v.add_child(note)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", 14)
	var intro := Button.new()
	intro.text = "Replay intro next match"
	intro.pressed.connect(func():
		Settings.set_val("intro_seen", false)
		intro.text = "Intro will play")
	h.add_child(intro)
	var save := Button.new()
	save.text = "Save and close"
	save.custom_minimum_size = Vector2(200, 44)
	save.pressed.connect(_save)
	h.add_child(save)
	v.add_child(h)
	_update_status()
	key_edit.text_changed.connect(func(_t): _update_status())


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


func _slider(parent: Control, lo: float, hi: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = val
	s.custom_minimum_size = Vector2(360, 24)
	parent.add_child(s)
	return s


func _update_status() -> void:
	var k := key_edit.text.strip_edges()
	if k == "":
		key_status.text = "No key: Terra is off. Simple orders like 'gather wood' and slash commands still work."
	elif not k.begins_with("sk-"):
		key_status.text = "OpenAI keys usually start with 'sk-'."
	else:
		key_status.text = "Key set. Orders in your own words go to Terra."


func _save() -> void:
	Settings.set_api_key(key_edit.text)
	var model := model_edit.text.strip_edges()
	Settings.data["model"] = model if model != "" else Settings.DEFAULT_MODEL
	Settings.data["request_limit"] = int(limit.value)
	Settings.data["quality"] = quality.selected
	Settings.data["sensitivity"] = sens.value
	Settings.data["fov"] = fov.value
	Settings.data["volume"] = vol.value
	Settings.data["invert_y"] = invert.button_pressed
	Settings.data["fullscreen"] = full.button_pressed
	Settings.data["hints"] = hints.button_pressed
	Settings.save_all()
	Settings.apply()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
