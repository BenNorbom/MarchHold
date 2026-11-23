extends PanelContainer
## The small window above the chat line: a picture and a key for each thing on the page.

signal page_picked(page: String)
signal key_picked(key: String)

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Defs = preload("res://scripts/data/defs.gd")
const Hotkeys = preload("res://scripts/game/hotkeys.gd")

const ICON := "res://assets/icons/%s_%s.png"
const CELL := Vector2(107, 123)
const PAGE_TILE := Vector2(266, 128)
const GAP := 4
const TITLES := {"b": "Build", "c": "Craft", "r": "Research"}
const DIMMED := Color(1, 1, 1, 0.6)

var title: Label
var grid: GridContainer
var detail: RichTextLabel
var shown_detail := ""
var repeat := Timer.new()
var held_key := ""
const REPEAT_FIRST := 0.35
const REPEAT_NEXT := 0.11


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.07, 0.055, 0.04, 0.97), Color(UiTheme.GOLD, 0.7), 1, 3, 8))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	title = Label.new()
	title.theme_type_variation = "ChatTo"
	rows.add_child(title)
	grid = GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	rows.add_child(grid)
	detail = _text(15)
	detail.custom_minimum_size.y = 42   # two lines, so the window doesn't jump as you hover
	rows.add_child(detail)
	minimum_size_changed.connect(reset_size)
	repeat.one_shot = true
	repeat.timeout.connect(_on_repeat)
	add_child(repeat)


func show_pages(command: String) -> void:
	_clear()
	title.text = "%s · /%s" % [TITLES[command], command]
	grid.columns = Defs.HOTKEYS[command].size()
	for page: String in Defs.HOTKEYS[command]:
		grid.add_child(_page_tile(command, page))
	_set_width(PAGE_TILE.x)
	var example := "[b]/b b h[/b] builds a hut" if command == "b" else "[b]/c 2 b a[/b] makes two batches of arrows. Hold Shift to keep buying"
	_set_detail("[b]B[/b] basic, [b]V[/b] advanced, then one key: %s." % example)


## quick: a key acts the moment it's typed, so the popup never asks for Enter.
func show_entries(command: String, pick: Dictionary, entries: Array, quick: bool) -> void:
	_clear()
	var page: String = pick["page"]
	title.text = "%s · %s" % [Defs.HOTKEYS[command][page]["name"], Hotkeys.draft(command, page).strip_edges()]
	grid.columns = 4 if entries.size() <= 8 else (5 if entries.size() <= 10 else 6)
	var chosen := {}
	for e: Dictionary in entries:
		var picked: bool = e["key"] == pick["key"]
		grid.add_child(_cell(e, picked))
		if picked:
			chosen = e
	_set_width(CELL.x)
	if pick.get("note", "") != "":
		_set_detail(pick["note"])
	elif pick["error"] != "":
		_set_detail("[color=#f0c060]%s[/color]" % pick["error"])
	elif not chosen.is_empty():
		var verb: String = {"build": "place it", "craft": "make it", "upgrade": "upgrade", "research": "research"}[chosen["kind"]]
		var times := " ×%d batches" % pick["batches"] if pick["batches"] > 1 else ""
		_set_detail("[color=#ffd870]%s%s[/color]  %s\n[b]Enter[/b] to %s." % [chosen["name"], times, chosen["desc"], verb])
	elif entries.all(func(e): return e["locked"] != ""):
		_set_detail("[color=#f0c060]%s[/color]" % entries[0]["locked"])
	else:
		var times := "×%d batches. " % pick["batches"] if pick["batches"] > 1 else ""
		_set_detail(times + ("Press a key or click a picture." if quick else "Type a key and press Enter, or click a picture."))


func _page_tile(command: String, page: String) -> Button:
	var info: Dictionary = Defs.HOTKEYS[command][page]
	var b := _button(PAGE_TILE, false)
	var rows := _rows(b)
	var head := _label("%s   %s" % [page.to_upper(), info["name"]], 19, UiTheme.GOLD)
	rows.add_child(head)
	var pictures := GridContainer.new()
	pictures.columns = 6
	pictures.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pictures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(pictures)
	for slot: String in info["keys"].values():
		pictures.add_child(_picture(slot.get_slice(":", 0), slot.get_slice(":", 1), 38))
	b.pressed.connect(func(): page_picked.emit(page), CONNECT_DEFERRED)
	return b


func _cell(e: Dictionary, picked: bool) -> Button:
	var b := _button(CELL, picked)
	var locked: bool = e["locked"] != ""
	var rows := _rows(b)
	var picture := _picture(e["kind"], e["id"], 60)
	rows.add_child(picture)
	var name_label := _label(e["name"], 14, UiTheme.INK)
	name_label.clip_text = true
	rows.add_child(name_label)
	var cost := _text(13)
	cost.add_theme_constant_override("line_separation", -2)
	cost.text = "[center]%s[/center]" % _cost_bb(e["cost"], {} if locked else e["missing"])
	rows.add_child(cost)
	if locked:
		rows.modulate = DIMMED

	var key := _label(String(e["key"]).to_upper(), 22, UiTheme.GOLD if not locked else Color(0.6, 0.56, 0.5))
	key.position = Vector2(6, 0)
	b.add_child(key)
	if e["batch"] > 1:
		var count := _label("×%d" % e["batch"], 14, UiTheme.INK)
		count.position = Vector2(CELL.x - 30, 3)
		b.add_child(count)

	var about: String = "[color=#ffd870]%s[/color]  %s" % [e["name"], e["desc"]]
	if locked:
		about += "\n[color=#f0c060]%s[/color]" % e["locked"]
	b.mouse_entered.connect(func(): detail.text = about)
	b.mouse_exited.connect(func(): detail.text = shown_detail)
	b.pressed.connect(func():
		if not Input.is_key_pressed(KEY_SHIFT):
			key_picked.emit(e["key"]), CONNECT_DEFERRED)
	if e["kind"] == "craft":
		# Shift buys on the press, then again and again while the button is held.
		b.button_down.connect(func():
			if Input.is_key_pressed(KEY_SHIFT) and not locked:
				held_key = e["key"]
				repeat.start(REPEAT_FIRST)
				key_picked.emit.call_deferred(held_key))
	return b


func _on_repeat() -> void:
	if held_key == "" or not visible or not Input.is_key_pressed(KEY_SHIFT) or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		held_key = ""
		repeat.stop()
		return
	repeat.start(REPEAT_NEXT)
	key_picked.emit(held_key)


## Red means you're short, as elsewhere.
func _cost_bb(cost: Dictionary, missing: Dictionary) -> String:
	var parts: Array[String] = []
	for r in cost:
		var amount := ("%d %s" % [int(cost[r]), Defs.RESOURCE_NAMES[r]]).replace(" ", " ")   # wrap between costs, not inside one
		parts.append("[color=#%s]%s[/color]" % ["ff8070" if missing.has(r) else "e8dcc2", amount])
	return ", ".join(parts)


func _button(min_size: Vector2, picked: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE   # the chat line keeps the keyboard
	b.clip_contents = true
	var edge := UiTheme.GOLD if picked else Color(UiTheme.GOLD, 0.3)
	var normal := UiTheme.box(Color(0.3, 0.22, 0.11) if picked else Color(0.14, 0.11, 0.08), edge, 2 if picked else 1, 3, 2)
	normal.shadow_size = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.1)
	hover.border_color = UiTheme.GOLD
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


func _rows(parent: Button) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rows)
	return rows


func _picture(kind: String, id: String, side: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(ICON % [kind, id])
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _text(font_size: int) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", font_size)
	t.add_theme_font_size_override("bold_font_size", font_size)
	return t


func _set_width(cell_width: float) -> void:
	# fit_content needs a known width, or it measures the text wrapped at zero.
	detail.custom_minimum_size.x = grid.columns * cell_width + (grid.columns - 1) * GAP


func _set_detail(text: String) -> void:
	shown_detail = text
	detail.text = text


func _clear() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
