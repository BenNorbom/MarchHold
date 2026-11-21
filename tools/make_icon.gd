extends SceneTree
## Rasterizes icon.svg to PNGs for the Windows .ico (run: godot --headless -s res://tools/make_icon.gd).
func _initialize():
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	for s in [16, 24, 32, 48, 64, 128, 256]:
		var img := Image.new()
		img.load_svg_from_string(svg, s / 256.0)
		img.save_png("res://build/icon_%d.png" % s)
	quit()
