extends RefCounted
## The game's look: dark oak panels with gilt edges, Cinzel for titles and
## EB Garamond for text (both SIL Open Font License).

const GOLD := Color(0.86, 0.7, 0.4)
const INK := Color(0.93, 0.88, 0.78)


static func font(path: String, weight: int = 400) -> Font:
	var base: FontFile = load(path)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	return fv


static func box(bg: Color, border: Color, bw: int = 1, radius: int = 3, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func build() -> Theme:
	var t := Theme.new()
	var body := font("res://assets/fonts/EBGaramond.ttf", 500)
	var bold := font("res://assets/fonts/EBGaramond.ttf", 700)
	var title := font("res://assets/fonts/Cinzel.ttf", 600)
	t.default_font = body
	t.default_font_size = 19
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	# Panels.
	t.set_stylebox("panel", "PanelContainer", box(Color(0.075, 0.06, 0.045, 0.88), Color(GOLD, 0.7)))
	for v in ["MenuPanel", "ChatPanel", "ObjectivePanel"]:
		t.set_type_variation(v, "PanelContainer")
	t.set_stylebox("panel", "MenuPanel", box(Color(0.07, 0.055, 0.04, 0.93), Color(GOLD, 0.8), 2, 4, 20))
	t.set_stylebox("panel", "ChatPanel", box(Color(0.05, 0.04, 0.03, 0.82), Color(GOLD, 0.55), 1, 3, 6))
	t.set_stylebox("panel", "ObjectivePanel", box(Color(0.06, 0.05, 0.035, 0.8), Color(GOLD, 0.6), 1, 3, 12))
	# Buttons.
	t.set_stylebox("normal", "Button", box(Color(0.16, 0.12, 0.08, 0.95), Color(GOLD, 0.6), 1, 3, 10))
	t.set_stylebox("hover", "Button", box(Color(0.26, 0.19, 0.11, 0.98), Color(GOLD, 0.95), 1, 3, 10))
	t.set_stylebox("pressed", "Button", box(Color(0.34, 0.24, 0.12, 1.0), GOLD, 1, 3, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(GOLD, 0.9), 1, 3, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.09, 0.08, 0.8), Color(0.4, 0.38, 0.34, 0.5), 1, 3, 10))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 0.94, 0.8))
	t.set_font("font", "Button", title)
	t.set_font_size("font_size", "Button", 18)
	# Text entry.
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.025, 0.02, 0.9), Color(GOLD, 0.45), 1, 2, 7))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.025, 0.02, 0.95), Color(GOLD, 0.9), 1, 2, 7))
	t.set_color("font_color", "LineEdit", Color(1, 0.97, 0.9))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.65, 0.6, 0.52))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_font_size("font_size", "LineEdit", 20)
	# Checkboxes, sliders, option buttons.
	t.set_stylebox("normal", "OptionButton", box(Color(0.16, 0.12, 0.08, 0.95), Color(GOLD, 0.6), 1, 3, 8))
	t.set_stylebox("hover", "OptionButton", box(Color(0.26, 0.19, 0.11, 0.98), Color(GOLD, 0.95), 1, 3, 8))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.34, 0.24, 0.12, 1.0), GOLD, 1, 3, 8))
	t.set_font("font", "OptionButton", body)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.065, 0.05, 0.98), Color(GOLD, 0.7), 1, 3, 6))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_font("font", "CheckBox", body)
	# Bars.
	t.set_type_variation("HealthBar", "ProgressBar")
	t.set_stylebox("background", "HealthBar", box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.6), 1, 2, 0))
	t.set_stylebox("fill", "HealthBar", box(Color(0.7, 0.16, 0.12, 0.95), Color(0, 0, 0, 0), 0, 2, 0))
	t.set_type_variation("StaminaBar", "ProgressBar")
	t.set_stylebox("background", "StaminaBar", box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.6), 1, 2, 0))
	t.set_stylebox("fill", "StaminaBar", box(Color(0.82, 0.68, 0.3, 0.9), Color(0, 0, 0, 0), 0, 2, 0))
	# Label variations.
	for v in ["Prompt", "Held", "Caption", "CaptionSub", "Toast", "Title", "BigTitle", "Footer", "ChatTo", "Small"]:
		t.set_type_variation(v, "Label")
	t.set_font_size("font_size", "Prompt", 18)
	t.set_font_size("font_size", "Held", 20)
	t.set_font("font", "Caption", title)
	t.set_font_size("font_size", "Caption", 40)
	t.set_color("font_color", "Caption", Color(1.0, 0.93, 0.78))
	t.set_constant("outline_size", "Caption", 8)
	t.set_color("font_outline_color", "Caption", Color(0, 0, 0, 0.55))
	t.set_font_size("font_size", "CaptionSub", 25)
	t.set_constant("outline_size", "CaptionSub", 6)
	t.set_color("font_outline_color", "CaptionSub", Color(0, 0, 0, 0.6))
	t.set_font("font", "Toast", title)
	t.set_font_size("font_size", "Toast", 26)
	t.set_color("font_color", "Toast", GOLD)
	t.set_constant("outline_size", "Toast", 6)
	t.set_color("font_outline_color", "Toast", Color(0, 0, 0, 0.6))
	t.set_font("font", "Title", title)
	t.set_font_size("font_size", "Title", 28)
	t.set_color("font_color", "Title", GOLD)
	t.set_font("font", "BigTitle", title)
	t.set_font_size("font_size", "BigTitle", 60)
	t.set_color("font_color", "BigTitle", GOLD)
	t.set_font_size("font_size", "Footer", 16)
	t.set_color("font_color", "Footer", Color(0.72, 0.68, 0.6))
	t.set_color("font_color", "ChatTo", GOLD)
	t.set_font("font", "ChatTo", bold)
	t.set_font_size("font_size", "Small", 15)
	t.set_color("font_color", "Small", Color(0.75, 0.7, 0.62))
	t.set_type_variation("LogLine", "RichTextLabel")
	return t
