extends PanelContainer
## Settings: Terra connection and model, graphics, controls and sound.

signal closed

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var key_edit: LineEdit
var model_edit: LineEdit
var provider: OptionButton
var chatgpt_models: OptionButton
var chatgpt_model_label: Label
var chatgpt_model_buttons: HBoxContainer
var connect_account: Button
var disconnect_account: Button
var refresh_models: Button
var account_status: Label
var chatgpt_controls: Array[Control] = []
var api_controls: Array[Control] = []
var connection_busy := false
var models_loaded := false
var account_feedback := ""
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
	_build_terra(grid)
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
	note.text = "Simple orders and slash commands work offline. Graphics changes apply to the next match."
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


func _build_terra(grid: Control) -> void:
	_label(grid, "Terra connection")
	provider = OptionButton.new()
	provider.add_item("ChatGPT plan", Settings.CHATGPT_PLAN)
	provider.add_item("OpenAI API key", Settings.API_KEY)
	provider.add_item("Off", Settings.TERRA_OFF)
	provider.select(int(Settings.get_val("terra_provider", Settings.CHATGPT_PLAN)))
	provider.item_selected.connect(_show_provider)
	grid.add_child(provider)

	api_controls.append(_label(grid, "OpenAI API key"))
	var kb := HBoxContainer.new()
	api_controls.append(kb)
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "sk-… (stored encrypted on this PC)"
	key_edit.custom_minimum_size = Vector2(360, 0)
	key_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	key_edit.text = Settings.api_key
	kb.add_child(key_edit)
	var get_key := Button.new()
	get_key.text = "Get a key"
	get_key.pressed.connect(func(): OS.shell_open("https://platform.openai.com/api-keys"))
	kb.add_child(get_key)
	grid.add_child(kb)
	api_controls.append(_label(grid, "Order model"))
	model_edit = LineEdit.new()
	model_edit.text = str(Settings.get_val("model", Settings.DEFAULT_MODEL))
	api_controls.append(model_edit)
	grid.add_child(model_edit)
	api_controls.append(_label(grid, ""))
	var api_note := _note("API requests use your OpenAI API balance.")
	api_controls.append(api_note)
	grid.add_child(api_note)

	chatgpt_controls.append(_label(grid, "ChatGPT account"))
	var buttons := HBoxContainer.new()
	connect_account = Button.new()
	connect_account.pressed.connect(_sign_in)
	buttons.add_child(connect_account)
	disconnect_account = Button.new()
	disconnect_account.text = "Disconnect"
	disconnect_account.pressed.connect(_disconnect)
	buttons.add_child(disconnect_account)
	var manage := Button.new()
	manage.text = "Manage usage"
	manage.pressed.connect(func(): OS.shell_open(ChatGPT.USAGE_URL))
	buttons.add_child(manage)
	chatgpt_controls.append(buttons)
	grid.add_child(buttons)

	chatgpt_controls.append(_label(grid, ""))
	account_status = _note("")
	chatgpt_controls.append(account_status)
	grid.add_child(account_status)
	chatgpt_model_label = _label(grid, "Order model")
	chatgpt_model_buttons = HBoxContainer.new()
	chatgpt_models = OptionButton.new()
	chatgpt_models.fit_to_longest_item = false
	chatgpt_models.size_flags_horizontal = SIZE_EXPAND_FILL
	chatgpt_model_buttons.add_child(chatgpt_models)
	refresh_models = Button.new()
	refresh_models.pressed.connect(_resume_or_refresh)
	chatgpt_model_buttons.add_child(refresh_models)
	grid.add_child(chatgpt_model_buttons)
	_show_provider.call_deferred(provider.selected)


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Small"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(460, 0)
	return label


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _slider(parent: Control, lo: float, hi: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = val
	s.custom_minimum_size = Vector2(360, 24)
	parent.add_child(s)
	return s


func _show_provider(choice: int) -> void:
	for control in api_controls:
		control.visible = choice == Settings.API_KEY
	for control in chatgpt_controls:
		control.visible = choice == Settings.CHATGPT_PLAN
	_update_account_status()
	if choice == Settings.CHATGPT_PLAN and ChatGPT.can_use_plan() and not ChatGPT.usage_limited and not models_loaded and not connection_busy:
		_load_models()


func _update_account_status() -> void:
	connect_account.disabled = connection_busy and not ChatGPT.waiting_for_browser
	connect_account.visible = not ChatGPT.can_use_plan() or ChatGPT.waiting_for_browser
	disconnect_account.visible = ChatGPT.registered() and not ChatGPT.waiting_for_browser
	disconnect_account.disabled = connection_busy
	provider.disabled = ChatGPT.waiting_for_browser
	if ChatGPT.waiting_for_browser:
		connect_account.text = "Cancel sign-in"
	else:
		connect_account.text = "Continue with ChatGPT"
	chatgpt_model_buttons.visible = provider.selected == Settings.CHATGPT_PLAN and ChatGPT.can_use_plan()
	chatgpt_model_label.visible = chatgpt_model_buttons.visible
	refresh_models.text = "Resume Terra" if ChatGPT.usage_limited else "Refresh models"
	refresh_models.disabled = connection_busy or not ChatGPT.can_use_plan()
	chatgpt_models.disabled = connection_busy or not ChatGPT.can_use_plan() or chatgpt_models.item_count == 0
	if account_feedback != "":
		account_status.text = account_feedback
	elif ChatGPT.usage_limited:
		account_status.text = ChatGPT.USAGE_LIMIT
	elif ChatGPT.can_use_plan():
		var account := ChatGPT.email()
		account_status.text = "Using ChatGPT plan" + (" · " + account if account != "" else "") + "."
	elif ChatGPT.signed_in():
		account_status.text = "Plan access is off. Continue with ChatGPT to grant permission, or choose OpenAI API key."
	else:
		account_status.text = "Use your ChatGPT plan for Terra. MarchHold sends your order, recent Terra dialogue and relevant village state to OpenAI."


func _disconnect() -> void:
	connection_busy = true
	account_feedback = "Disconnecting ChatGPT…"
	_update_account_status()
	account_feedback = await ChatGPT.disconnect_account()
	models_loaded = false
	chatgpt_models.clear()
	connection_busy = false
	_update_account_status()


func _sign_in() -> void:
	if ChatGPT.waiting_for_browser:
		ChatGPT.cancel_sign_in()
		return
	if connection_busy:
		return
	connection_busy = true
	account_feedback = "Finish connecting in your browser."
	_update_account_status.call_deferred()
	account_feedback = await ChatGPT.sign_in()
	connection_busy = false
	_update_account_status()
	if account_feedback != "" or not ChatGPT.can_use_plan():
		return
	Settings.set_val("terra_provider", Settings.CHATGPT_PLAN)
	if not Settings.get_val("chatgpt_usage_seen", false):
		Settings.set_val("chatgpt_usage_seen", true)
		var confirmation := AcceptDialog.new()
		confirmation.title = "Using your ChatGPT plan"
		confirmation.dialog_text = "Terra's eligible requests use your ChatGPT plan. Review or adjust usage with Manage usage in Settings."
		confirmation.ok_button_text = "Got it"
		add_child(confirmation)
		confirmation.popup_centered()
	await _load_models()


func _resume_or_refresh() -> void:
	ChatGPT.usage_limited = false
	_load_models()


func _load_models() -> void:
	connection_busy = true
	account_feedback = "Loading your ChatGPT models…"
	_update_account_status()
	var selected := _selected_model()
	var result := await ChatGPT.models()
	connection_busy = false
	account_feedback = str(result.get("error", ""))
	if result.has("models"):
		models_loaded = true
		chatgpt_models.clear()
		var preferred := -1
		var terra := -1
		for model in result["models"]:
			var index := chatgpt_models.item_count
			chatgpt_models.add_item(model["name"])
			chatgpt_models.set_item_metadata(index, model["id"])
			if model["id"] == selected:
				preferred = index
			if model["id"] == Settings.DEFAULT_MODEL or (terra < 0 and model["id"].ends_with("-terra")):
				terra = index
		if chatgpt_models.item_count == 0:
			account_feedback = "This ChatGPT account did not list any eligible order models."
		else:
			chatgpt_models.select(preferred if preferred >= 0 else maxi(terra, 0))
			Settings.set_val("chatgpt_model", _selected_model())
	_update_account_status()


func _selected_model() -> String:
	if chatgpt_models.selected >= 0:
		return str(chatgpt_models.get_selected_metadata())
	return str(Settings.get_val("chatgpt_model", ""))


func _save() -> void:
	if key_edit.text.strip_edges() != Settings.api_key:
		Settings.set_api_key(key_edit.text)
	var model := model_edit.text.strip_edges()
	Settings.data["model"] = model if model != "" else Settings.DEFAULT_MODEL
	Settings.data["terra_provider"] = provider.get_selected_id()
	Settings.data["chatgpt_model"] = _selected_model()
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
	_close()


func _close() -> void:
	if ChatGPT.waiting_for_browser:
		ChatGPT.cancel_sign_in()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
