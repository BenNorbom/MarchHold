extends CanvasLayer
## Minimal first-person HUD plus the chat line, slash menus and the field map.

signal chat_submitted(text: String)
signal chat_changed(text: String)
signal chat_closed
signal chat_cycle(backward: bool)
signal chat_choice(index: int)
signal menu_clicked(index: int)
signal pause_choice(name: String)

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Defs = preload("res://scripts/data/defs.gd")

const RESOURCE_DISPLAY_ORDER := ["food", "wood", "stone", "bronze_ore", "coal", "iron_ore", "bronze", "iron"]

const KIND_COLORS := {
	"info": "e8dcc2", "warn": "f0c060", "alarm": "ff6a50", "death": "e07060", "done": "a8d890",
	"report": "9cc8f0", "terra": "d8c8ff", "you": "ffffff", "birth": "f0b8d0", "age": "ffd870",
	"system": "b8b0a0", "hint": "a0e0d8", "crew": "e8dcc2",
}

var theme_res: Theme
var root: Control
var crosshair: Control
var compass: Control
var hp_bar: ProgressBar
var st_bar: ProgressBar
var held_label: Label
var prompt_label: Label
var selection_label: Label
var log_box: VBoxContainer
var log_lines: Array = []       # [{node, t}]
var chat_panel: PanelContainer
var chat_to: Label
var chat_edit: LineEdit
var chat_usage: Button
var chat_hint: PanelContainer
var chat_hint_title: Label
var chat_hint_text: RichTextLabel
var chat_hint_choices: RichTextLabel
var menu_panel: PanelContainer
var menu_title: Label
var menu_body: RichTextLabel
var menu_footer: Label
var map_view: Control
var village_widgets: VBoxContainer
var supply_label: Label
var resource_counts: Dictionary[String, Label] = {}
var objective_panel: PanelContainer
var objective_label: RichTextLabel
var caption: Label
var caption_sub: Label
var toast: Label
var toast_t := 0.0
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var thinking: Label
var heading := 0.0
var home_bearing := 0.0
var chat_open := false
var chat_can_cycle := false
var menu_open := false
var history: Array = []
var history_i := -1


func _ready() -> void:
	layer = 5
	theme_res = UiTheme.build()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	_build_crosshair()
	_build_compass()
	_build_status()
	_build_log()
	_build_chat()
	_build_menu()
	_build_map()
	_build_village()
	_build_objective()
	_build_caption()
	_build_pause()
	_build_end()


func _panel(style: String = "panel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = style
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# --- Widgets -------------------------------------------------------------------

func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func():
		crosshair.draw_circle(Vector2.ZERO, 2.6, Color(1, 1, 1, 0.85))
		crosshair.draw_arc(Vector2.ZERO, 5.0, 0, TAU, 20, Color(0, 0, 0, 0.35), 1.2))
	root.add_child(crosshair)
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position = Vector2(-400, 26)
	prompt_label.size = Vector2(800, 30)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.theme_type_variation = "Prompt"
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_label)
	thinking = Label.new()
	thinking.set_anchors_preset(Control.PRESET_CENTER)
	thinking.position = Vector2(-200, 60)
	thinking.size = Vector2(400, 30)
	thinking.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thinking.theme_type_variation = "Prompt"
	thinking.visible = false
	root.add_child(thinking)
	selection_label = Label.new()
	selection_label.set_anchors_preset(Control.PRESET_CENTER)
	selection_label.position = Vector2(-450, 94)
	selection_label.size = Vector2(900, 30)
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.theme_type_variation = "Prompt"
	selection_label.modulate = Color(1.0, 0.86, 0.45)
	selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_label.visible = false
	root.add_child(selection_label)


func _build_compass() -> void:
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-260, 14)
	compass.size = Vector2(520, 34)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)


func _draw_compass() -> void:
	var w := compass.size.x
	var h := compass.size.y
	compass.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.04, 0.03, 0.45))
	compass.draw_rect(Rect2(0, 0, w, h), Color(0.75, 0.62, 0.35, 0.5), false, 1.0)
	var font := theme_res.default_font
	var span := 110.0   # degrees visible
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for d in range(0, 360, 15):
		var rel := wrapf(d - heading, -180.0, 180.0)
		if absf(rel) > span * 0.5:
			continue
		var x := w * 0.5 + rel / span * w
		if names.has(d):
			var txt: String = names[d]
			var col := Color(1.0, 0.85, 0.55) if d % 90 == 0 else Color(0.9, 0.85, 0.75, 0.8)
			compass.draw_string(font, Vector2(x - 12, h - 9), txt, HORIZONTAL_ALIGNMENT_CENTER, 24, 15 if d % 90 == 0 else 12, col)
		else:
			compass.draw_line(Vector2(x, 4), Vector2(x, 10), Color(0.9, 0.85, 0.7, 0.6), 1.0)
	# Home marker.
	var hr := wrapf(home_bearing - heading, -180.0, 180.0)
	if absf(hr) <= span * 0.5:
		var hx := w * 0.5 + hr / span * w
		compass.draw_colored_polygon(PackedVector2Array([Vector2(hx, h - 2), Vector2(hx - 5, h - 9), Vector2(hx + 5, h - 9)]), Color(1.0, 0.55, 0.2, 0.95))
	compass.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 6), Color(1, 1, 1, 0.9), 2.0)


func _build_status() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(22, -64)
	box.size = Vector2(250, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(250, 14)
	hp_bar.show_percentage = false
	hp_bar.theme_type_variation = "HealthBar"
	box.add_child(hp_bar)
	st_bar = ProgressBar.new()
	st_bar.custom_minimum_size = Vector2(250, 8)
	st_bar.show_percentage = false
	st_bar.theme_type_variation = "StaminaBar"
	box.add_child(st_bar)
	held_label = Label.new()
	held_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	held_label.position = Vector2(-420, -60)
	held_label.size = Vector2(400, 40)
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	held_label.theme_type_variation = "Held"
	held_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(held_label)


func _build_log() -> void:
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.position = Vector2(22, -400)
	log_box.size = Vector2(660, 300)
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 2)
	root.add_child(log_box)


func _build_chat() -> void:
	chat_panel = _panel("ChatPanel")
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.position = Vector2(18, -96)
	chat_panel.size = Vector2(668, 40)
	chat_panel.visible = false
	root.add_child(chat_panel)
	chat_usage = Button.new()
	chat_usage.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_usage.position = Vector2(18, -54)
	chat_usage.text = "Using ChatGPT plan · Manage usage"
	chat_usage.visible = false
	chat_usage.pressed.connect(func(): OS.shell_open(ChatGPT.USAGE_URL))
	root.add_child(chat_usage)
	var h := HBoxContainer.new()
	chat_panel.add_child(h)
	chat_to = Label.new()
	chat_to.theme_type_variation = "ChatTo"
	h.add_child(chat_to)
	chat_edit = LineEdit.new()
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_edit.placeholder_text = "Type an order, or / for menus…"
	chat_edit.max_length = 300
	chat_edit.text_changed.connect(chat_changed.emit)
	chat_edit.text_submitted.connect(_on_chat_submit)
	chat_edit.gui_input.connect(_on_chat_key)
	h.add_child(chat_edit)
	_build_chat_hint()


func _build_chat_hint() -> void:
	chat_hint = _panel("ChatPanel")
	chat_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_hint.custom_minimum_size.x = 460
	chat_hint.add_theme_stylebox_override("panel", UiTheme.box(Color(0.07, 0.055, 0.04, 0.97), Color(UiTheme.GOLD, 0.7), 1, 3, 10))
	chat_hint.hide()
	root.add_child(chat_hint)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	chat_hint.add_child(rows)
	chat_hint_title = Label.new()
	chat_hint_title.theme_type_variation = "ChatTo"
	rows.add_child(chat_hint_title)
	chat_hint_text = RichTextLabel.new()
	chat_hint_text.bbcode_enabled = true
	chat_hint_text.fit_content = true
	chat_hint_text.scroll_active = false
	chat_hint_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(chat_hint_text)
	chat_hint_choices = RichTextLabel.new()
	chat_hint_choices.bbcode_enabled = true
	chat_hint_choices.focus_mode = Control.FOCUS_NONE
	chat_hint_choices.meta_clicked.connect(func(meta): chat_choice.emit(int(str(meta))))
	rows.add_child(chat_hint_choices)
	for label in [chat_hint_text, chat_hint_choices]:
		label.add_theme_font_size_override("normal_font_size", 17)
		label.add_theme_font_size_override("bold_font_size", 17)
		label.add_theme_constant_override("line_separation", 0)
	chat_hint.resized.connect(_position_chat_hint)
	chat_panel.item_rect_changed.connect(_position_chat_hint)


func _position_chat_hint() -> void:
	chat_hint.position = chat_panel.position - Vector2(0, chat_hint.size.y + 6)


func show_chat_hint(title: String, body: String, choices: Array[String]) -> void:
	chat_hint_title.text = title
	chat_hint_text.text = body
	chat_hint_choices.visible = not choices.is_empty()
	chat_hint_choices.custom_minimum_size.y = mini(choices.size(), 5) * 23
	chat_hint_choices.text = "\n".join(choices)
	chat_hint_choices.scroll_to_line(0)
	chat_hint.show()
	chat_hint.reset_size()
	_position_chat_hint()


func _on_chat_submit(text: String) -> void:
	var t := text.strip_edges()
	close_chat()
	if t == "":
		chat_closed.emit()
		return
	history.push_front(t)
	if history.size() > 30:
		history.pop_back()
	chat_submitted.emit(t)


func _on_chat_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ESCAPE:
			close_chat()
			chat_closed.emit()
			chat_edit.accept_event()
		elif ev.keycode == KEY_UP and not history.is_empty():
			history_i = mini(history_i + 1, history.size() - 1)
			chat_edit.text = history[history_i]
			chat_edit.caret_column = chat_edit.text.length()
			chat_changed.emit(chat_edit.text)
			chat_edit.accept_event()
		elif ev.keycode == KEY_DOWN:
			history_i = maxi(history_i - 1, -1)
			chat_edit.text = history[history_i] if history_i >= 0 else ""
			chat_edit.caret_column = chat_edit.text.length()
			chat_changed.emit(chat_edit.text)
			chat_edit.accept_event()


func _input(ev: InputEvent) -> void:
	if chat_open and chat_can_cycle and ev is InputEventKey and ev.keycode == KEY_TAB:
		if ev.pressed and not ev.echo:
			chat_cycle.emit(ev.shift_pressed)
		get_viewport().set_input_as_handled()


func set_chat_address(to_text: String, can_cycle: bool) -> void:
	chat_can_cycle = can_cycle
	chat_to.text = "  To %s%s  " % [to_text, " · Tab to switch" if can_cycle else ""]


func open_chat(to_text: String, prefill: String = "", can_cycle: bool = false) -> void:
	chat_open = true
	history_i = -1
	set_chat_address(to_text, can_cycle)
	chat_panel.visible = true
	chat_usage.visible = Settings.get_val("terra_provider") == Settings.CHATGPT_PLAN and ChatGPT.can_use_plan()
	chat_usage.text = "ChatGPT usage limit reached · Manage usage" if ChatGPT.usage_limited else "Using ChatGPT plan · Manage usage"
	chat_edit.text = prefill
	chat_edit.grab_focus()
	chat_edit.caret_column = prefill.length()
	_refresh_log_visibility()
	chat_changed.emit(prefill)


func close_chat() -> void:
	chat_open = false
	chat_panel.visible = false
	chat_usage.visible = false
	chat_hint.hide()
	chat_edit.release_focus()
	_refresh_log_visibility()


func _build_menu() -> void:
	menu_panel = _panel("MenuPanel")
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.position = Vector2(-380, -300)
	menu_panel.size = Vector2(760, 600)
	menu_panel.visible = false
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	menu_panel.add_child(v)
	menu_title = Label.new()
	menu_title.theme_type_variation = "Title"
	v.add_child(menu_title)
	menu_body = RichTextLabel.new()
	menu_body.bbcode_enabled = true
	menu_body.fit_content = false
	menu_body.scroll_active = true
	menu_body.custom_minimum_size = Vector2(720, 470)
	menu_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_body.meta_clicked.connect(func(meta): menu_clicked.emit(int(str(meta))))
	v.add_child(menu_body)
	menu_footer = Label.new()
	menu_footer.theme_type_variation = "Footer"
	v.add_child(menu_footer)


func show_menu(title: String, bbcode: String, footer: String = "Number keys or click to choose · Esc to close") -> void:
	menu_open = true
	menu_title.text = title
	menu_body.text = bbcode
	menu_body.scroll_to_line(0)
	menu_footer.text = footer
	menu_panel.visible = true


func hide_menu() -> void:
	menu_open = false
	menu_panel.visible = false


func _build_map() -> void:
	map_view = preload("res://scripts/ui/field_map.gd").new()
	map_view.visible = false
	root.add_child(map_view)


func _build_village() -> void:
	village_widgets = VBoxContainer.new()
	village_widgets.position = Vector2(18, 14)
	village_widgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	village_widgets.add_theme_constant_override("separation", 12)
	root.add_child(village_widgets)
	var panel := _panel()
	panel.custom_minimum_size.x = 180
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	village_widgets.add_child(panel)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	supply_label = Label.new()
	supply_label.add_theme_color_override("font_color", UiTheme.GOLD)
	supply_label.add_theme_font_size_override("font_size", 22)
	rows.add_child(supply_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 0)
	rows.add_child(grid)
	for resource: String in RESOURCE_DISPLAY_ORDER:
		var label := Label.new()
		label.text = Defs.RESOURCE_NAMES[resource].capitalize()
		grid.add_child(label)
		var count := Label.new()
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(count)
		resource_counts[resource] = count


func _build_objective() -> void:
	objective_panel = _panel("ObjectivePanel")
	objective_panel.custom_minimum_size = Vector2(430, 80)
	objective_panel.visible = false
	village_widgets.add_child(objective_panel)
	objective_label = RichTextLabel.new()
	objective_label.bbcode_enabled = true
	objective_label.fit_content = true
	objective_label.custom_minimum_size = Vector2(410, 30)
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_child(objective_label)


func set_objective(text: String) -> void:
	objective_panel.visible = text != ""
	objective_label.text = text


func _build_caption() -> void:
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_CENTER)
	caption.position = Vector2(-640, -170)
	caption.size = Vector2(1280, 90)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.theme_type_variation = "Caption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	caption_sub = Label.new()
	caption_sub.set_anchors_preset(Control.PRESET_CENTER)
	caption_sub.position = Vector2(-560, -80)
	caption_sub.size = Vector2(1120, 90)
	caption_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_sub.theme_type_variation = "CaptionSub"
	caption_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption_sub)
	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-500, 70)
	toast.size = Vector2(1000, 40)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.theme_type_variation = "Toast"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)


func show_caption(text: String, sub: String = "") -> void:
	caption.text = text
	caption_sub.text = sub
	caption.modulate.a = 1.0
	caption_sub.modulate.a = 1.0


func show_toast(text: String) -> void:
	toast.text = text
	toast_t = 4.5


func _build_pause() -> void:
	pause_panel = _panel("MenuPanel")
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-180, -170)
	pause_panel.size = Vector2(360, 340)
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	var t := Label.new()
	t.text = "Paused"
	t.theme_type_variation = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for pair in [["resume", "Resume"], ["help", "Help (/h)"], ["settings", "Settings"], ["menu", "Leave match"], ["quit", "Quit game"]]:
		var b := Button.new()
		b.text = pair[1]
		b.custom_minimum_size = Vector2(300, 44)
		var nm: String = pair[0]
		b.pressed.connect(func(): pause_choice.emit(nm))
		v.add_child(b)


func show_pause(on: bool) -> void:
	pause_panel.visible = on


func _build_end() -> void:
	end_panel = _panel("MenuPanel")
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.position = Vector2(-330, -200)
	end_panel.size = Vector2(660, 400)
	end_panel.visible = false
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	end_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	end_panel.add_child(v)
	end_title = Label.new()
	end_title.theme_type_variation = "BigTitle"
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_body = Label.new()
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_body.custom_minimum_size = Vector2(620, 180)
	v.add_child(end_body)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	for pair in [["menu", "Main menu"], ["again", "Play again"], ["quit", "Quit"]]:
		var b := Button.new()
		b.text = pair[1]
		b.custom_minimum_size = Vector2(180, 46)
		var nm: String = pair[0]
		b.pressed.connect(func(): pause_choice.emit(nm))
		h.add_child(b)


func show_end(win: bool, body: String) -> void:
	end_title.text = "Victory" if win else "Defeat"
	end_title.modulate = Color(1.0, 0.85, 0.45) if win else Color(0.9, 0.35, 0.3)
	end_body.text = body
	end_panel.visible = true


# --- Chat log --------------------------------------------------------------------

func log_line(text: String, kind: String = "info", who: String = "") -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(660, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = "LogLine"
	var col: String = KIND_COLORS.get(kind, "e8dcc2")
	var prefix := ""
	if who != "":
		prefix = "[b]%s:[/b] " % who
	l.text = "[color=#%s]%s%s[/color]" % [col, prefix, _escape(text)]
	log_box.add_child(l)
	log_lines.append({"node": l, "t": Time.get_ticks_msec() / 1000.0})
	while log_lines.size() > 40:
		var old: Dictionary = log_lines.pop_front()
		old["node"].queue_free()
	_refresh_log_visibility()


func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


func _refresh_log_visibility() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var shown := 0
	for i in range(log_lines.size() - 1, -1, -1):
		var e: Dictionary = log_lines[i]
		var age: float = now - e["t"]
		var node: RichTextLabel = e["node"]
		var max_lines := 16 if chat_open else 8
		if shown >= max_lines:
			node.visible = false
			continue
		if chat_open:
			node.visible = true
			node.modulate.a = 1.0
			shown += 1
		elif age < 14.0:
			node.visible = true
			node.modulate.a = clampf((14.0 - age) / 2.0, 0.0, 1.0)
			shown += 1
		else:
			node.visible = false


# --- Per frame ----------------------------------------------------------------------

func update_economy(population: int, housing: int, stock: Dictionary) -> void:
	supply_label.text = "Villagers  %d/%d" % [population, housing]
	for resource: String in RESOURCE_DISPLAY_ORDER:
		resource_counts[resource].text = str(int(stock.get(resource, 0)))


func update_status(hp: float, max_hp: float, stamina: float, held: String, yaw_deg: float, home_deg: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	st_bar.value = stamina * 100.0
	held_label.text = held
	heading = yaw_deg
	home_bearing = home_deg
	compass.queue_redraw()


func set_prompt(text: String) -> void:
	prompt_label.text = text


func set_selection(text: String) -> void:
	selection_label.visible = text != ""
	selection_label.text = text


func set_thinking(text: String) -> void:
	thinking.visible = text != ""
	thinking.text = text


func _process(delta: float) -> void:
	if Engine.get_process_frames() % 15 == 0:
		_refresh_log_visibility()
	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t, 0.0, 1.0)
	if caption.text != "" and caption.modulate.a > 0.0:
		pass
