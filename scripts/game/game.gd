extends Node3D
## One match: the simulation, the rival, the world view, the commander, the HUD,
## Terra, and the intro / tutorial / hints. All orders end up in Match.command().

signal finished(action: String)

const Defs = preload("res://scripts/data/defs.gd")
const Terrain = preload("res://scripts/world/terrain.gd")
const Match = preload("res://scripts/sim/match.gd")
const Rival = preload("res://scripts/ai/rival.gd")
const Materials = preload("res://scripts/view/materials.gd")
const Meshes = preload("res://scripts/view/meshes.gd")
const WorldView = preload("res://scripts/view/world_view.gd")
const Commander = preload("res://scripts/view/commander.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Terra = preload("res://scripts/orders/terra.gd")
const Parser = preload("res://scripts/orders/parser.gd")
const Tutorial = preload("res://scripts/game/tutorial.gd")
const Intro = preload("res://scripts/game/intro.gd")
const Hints = preload("res://scripts/game/hints.gd")
const Digest = preload("res://scripts/ui/digest.gd")

const MENU_COLUMNS := 3
const PEOPLE_PER_PAGE := 9      # keys 1-9, with 0 for the next page
const SLASH_ALIASES := {
	"build": "b", "craft": "c", "make": "c", "ledger": "l",
	"people": "p", "crews": "p", "scouts": "s", "reports": "s",
	"map": "m", "tech": "t", "help": "h", "?": "h", "stop": "cancel",
}
const CHAT_HINTS := {
	"b": ["Build · /b", "Type [b]/b hut[/b] or choose a structure below."],
	"c": ["Craft · /c", "Choose a recipe or type [b]/c spears 2[/b] for two batches."],
	"l": ["Ledger · /l", "Press Enter to see supplies, food, housing and crew status."],
	"p": ["People and crews · /p", "Press Enter to list crews. Type [b]@Name[/b] to address one."],
	"s": ["Scout reports · /s", "Press Enter to read reports. To send a scout, type [b]send a scout east[/b]."],
	"m": ["Field map · /m", "Press Enter to toggle the map of places your people have seen."],
	"t": ["Tech tree · /t", "Press Enter to see the unlocks for each age."],
	"h": ["Slash commands", "[b]/b[/b] Build   [b]/c[/b] Craft   [b]/l[/b] Ledger   [b]/p[/b] People   [b]/s[/b] Scouts\n[b]/m[/b] Map   [b]/t[/b] Tech   [b]/cancel[/b] Stop orders   [b]/h[/b] Help"],
	"cancel": ["Stop orders · /cancel", "Press Enter to stop the addressed crew. With no addressee, all crews stop."],
}

var opts := {}
var m
var ai
var mats
var meshes
var view
var cmd
var hud
var terra
var tutorial
var intro
var hints
var digest := Digest.new()
var acc := 0.0
var paused := false
var over_shown := false
var peak_pop := 0
var addressee := {}
var address_label := ""
var chat_crew := -1
var chat_first_member := -1
var terra_ctx := {}
var dialogue: Array = []
var placing := false
var place_req := {}
var place_type := ""
var place_rot := 0.0
var place_pos := Vector2.ZERO
var place_ok := false
var wall_points: Array = []
var placed_ids: Array = []
var menu_kind := ""
var menu_items: Array = []
var people_page := 0
var people_pages := 1
var chat_hint_command := ""
var chat_hint_items: Array = []
var map_open := false
var map_refresh_t := 0.0
var look_unit := -1
var selected: Array[int] = []
var look_bld := -1
var ready_done := false
var start_ms := 0


func start(options: Dictionary) -> void:
	opts = options
	var seed_in := int(opts.get("seed", 0))
	if seed_in == 0:
		seed_in = randi() % 900000 + 1000
	opts["seed"] = seed_in
	var is_tutorial: bool = opts.get("tutorial", false)
	m = Match.new()
	var map_id: String = Defs.MAP_LARGEST if is_tutorial else str(opts.get("map", Defs.MAP_LARGEST))
	m.setup({"seed": seed_in, "map": map_id})
	ai = Rival.new()
	ai.setup(m, {"faction": 1, "difficulty": 0 if is_tutorial else int(opts.get("difficulty", 1)),
		"strategy": "boom" if is_tutorial else str(opts.get("strategy", "random")), "seed": seed_in,
		"calm_start": bool(opts.get("calm_start", false)), "passive": is_tutorial, "max_pop": 14 if is_tutorial else 200})
	var quality := int(Settings.get_val("quality", 1))
	mats = Materials.new()
	meshes = Meshes.new(mats)
	view = WorldView.new()
	add_child(view)
	view.setup(m, mats, meshes, quality)
	var me = m.commander(0)
	cmd = Commander.new()
	add_child(cmd)
	cmd.setup(m, mats, m.terrain.pos3(me.pos, 0.3), me.facing)
	cmd.attacked.connect(_on_attack_result)
	view.hidden_unit = me.id
	hud = Hud.new()
	add_child(hud)
	_update_hud()
	hud.map_view.setup(m, view.map_image())
	hud.chat_submitted.connect(_on_chat)
	hud.chat_changed.connect(_on_chat_changed)
	hud.chat_closed.connect(_on_chat_closed)
	hud.chat_choice.connect(_on_chat_choice)
	hud.chat_cycle.connect(_cycle_chat_address)
	hud.menu_clicked.connect(_menu_select)
	hud.pause_choice.connect(_on_pause_choice)
	terra = Terra.new()
	add_child(terra)
	terra.answered.connect(_on_terra)
	Sfx.set_world(self)
	Sfx.set_fire(m.terrain.pos3(m.home_pos(0), 0.5))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hints = Hints.new()
	hints.setup(self)
	if is_tutorial:
		tutorial = Tutorial.new()
		tutorial.setup(self)
	if not Settings.get_val("intro_seen", false) or opts.get("intro", false):
		intro = Intro.new()
		add_child(intro)
		intro.setup(self)
	else:
		_welcome()
	ready_done = true
	start_ms = Time.get_ticks_msec()


func _welcome() -> void:
	if tutorial:
		tutorial.begin()
		return
	hud.log_line("You stand at your campfire with six villagers. Commander Rook has made camp somewhere across the valley.", "system")
	hud.log_line("Look at a villager and press Enter to give orders. Type /b to build, /h for help.", "system")
	if not terra.available():
		hud.log_line("Simple orders work offline. Choose a Terra connection in Settings for orders in your own words.", "hint")


func intro_done() -> void:
	Settings.set_val("intro_seen", true)
	intro = null
	_welcome()


# --- Frame loop ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_done:
		return
	if paused or intro != null and intro.blocking():
		if intro != null:
			view.update_frame(delta, 0.0, cmd.eye())
		return
	var me = m.commander(0)
	if me and not me.dead:
		m.set_commander(0, Vector2(cmd.position.x, cmd.position.z), cmd.facing(), cmd.anim)
	if not m.over:
		acc += delta
		var n := 0
		while acc >= Defs.TICK and n < 4:
			acc -= Defs.TICK
			m.tick(Defs.TICK)
			ai.update(Defs.TICK)
			if tutorial:
				tutorial.tick(Defs.TICK)
			n += 1
		if n >= 4:
			acc = 0.0
	var alpha := clampf(acc / Defs.TICK, 0.0, 1.0)
	view.handle_events(m.events)
	_sound_events(m.events)
	m.events.clear()
	_show_messages()
	view.update_frame(delta, alpha, cmd.eye())
	Sfx.listener_pos = cmd.eye()
	_update_hud()
	_update_look()
	_update_selection()
	if placing:
		_update_place()
	if map_open:
		map_refresh_t -= delta
		if map_refresh_t <= 0.0:
			map_refresh_t = 1.0
			hud.map_view.refresh()
	hints.tick(delta)
	peak_pop = maxi(peak_pop, m.fac(0).pop)
	if m.over and not over_shown:
		_show_end()


func _show_messages() -> void:
	for msg in m.messages:
		if msg["faction"] != 0:
			continue
		var line: String = digest.take(msg, m.t)
		if line != "":
			hud.log_line(line, msg["kind"])
		if hints:
			hints.on_message(msg)
		if msg["kind"] == "age":
			hud.show_toast(msg["text"].split("!")[0] + "!")
	m.messages.clear()
	for summary in digest.due(m.t):
		hud.log_line(summary[0], summary[1])


func _sound_events(events: Array) -> void:
	for ev in events:
		if ev["type"] != "sound":
			continue
		var name: String = ev["name"]
		var p: Vector2 = ev["pos"]
		if ev.get("faction", -1) == 0 and name in ["bell", "horn", "report", "age", "birth", "complete"]:
			var vol := -4.0 if name in ["bell", "horn"] else -9.0
			Sfx.play(name, null, vol)
			if name == "bell":
				get_tree().create_timer(0.9).timeout.connect(func(): Sfx.play("bell", null, -6.0))
				get_tree().create_timer(1.8).timeout.connect(func(): Sfx.play("bell", null, -8.0))
		else:
			var vol2 := -8.0
			if name in ["cannon", "impact", "collapse"]:
				vol2 = 2.0
			elif name in ["chop", "pick", "hammer", "anvil"]:
				vol2 = -12.0
			Sfx.play(name, m.terrain.pos3(p, 1.0), vol2)


func _update_hud() -> void:
	var faction = m.fac(0)
	hud.update_economy(faction.pop, faction.housing, faction.stock)
	var me = m.commander(0)
	if me == null:
		return
	var held := ""
	if cmd.can_shoot():
		held = "Bow · %d arrows" % me.arrows
	else:
		held = Defs.item_name(me.weapon).capitalize() if me.weapon != "" else "Bare hands"
		if me.shield != "":
			held += " · " + Defs.item_name(me.shield)
		if me.bow:
			held += " · bow (%d)" % me.arrows
	if me.armor != "":
		held += " · " + Defs.item_name(me.armor)
	if me.mounted:
		held = "On horseback · " + held
	var fwd: Vector3 = cmd.look_dir()
	var yaw := rad_to_deg(atan2(fwd.x, -fwd.z))
	var home: Vector2 = m.home_pos(0) - me.pos
	var hb := rad_to_deg(atan2(home.x, -home.y))
	hud.update_status(me.hp, me.max_hp, cmd.stamina, held, fposmod(yaw, 360.0), fposmod(hb, 360.0))


func _update_look() -> void:
	if placing or hud.menu_open:
		return
	look_unit = view.pick_unit(cmd.eye(), cmd.look_dir(), 45.0)
	look_bld = -1
	var text := ""
	if look_unit >= 0:
		var u = m.unit(look_unit)
		text = _describe_unit(u)
	else:
		var hit = view.ground_hit(cmd.eye(), cmd.look_dir(), 14.0)
		var bid := _building_at_ray()
		if bid >= 0:
			look_bld = bid
			text = _describe_building(m.bld(bid))
	hud.set_prompt(text)


func _building_at_ray() -> int:
	var from: Vector3 = cmd.eye()
	var dir: Vector3 = cmd.look_dir()
	var best := -1
	var bd := 14.0
	for b in m.buildings:
		if b.dead or b.pos.distance_to(Vector2(from.x, from.z)) > 20.0:
			continue
		# Sample along the ray against the footprint.
		var t := 0.5
		while t < bd:
			var p := from + dir * t
			var local: Vector2 = (Vector2(p.x, p.z) - b.pos).rotated(-b.rot)
			if absf(local.x) <= b.size.x * 0.5 + 0.2 and absf(local.y) <= b.size.y * 0.5 + 0.2 and p.y < m.terrain.height_at(p.x, p.z) + 8.0:
				bd = t
				best = b.id
				break
			t += 0.5
	return best


func _describe_unit(u) -> String:
	if u == null:
		return ""
	if u.faction == -1:
		return "Wild horse" if u.kind == "horse" else ("Deer" if u.kind == "deer" else "")
	if u.faction == 1:
		if u.kind == "commander":
			return "Commander Rook — kill him to win"
		return "Enemy " + m.describe_person(u) + (" (wounded)" if u.hp < u.max_hp * 0.5 else "")
	if u.kind == "horse":
		return "Your horse in the stable"
	if u.kind in ["cannon", "ram"]:
		return "%s (%d crew)%s" % [Defs.item_name(u.kind).capitalize(), u.crew_ids.size(), (" · %d shot" % u.ammo) if u.kind == "cannon" else ""]
	if u.dead:
		return u.name + " (dead)"
	if u.child:
		return "%s (child, grows up in %d s)" % [u.name, int(maxf(0.0, Defs.MATURE_TIME - (m.t - u.born)))]
	var c = m.crew_of(u)
	var what := "idle"
	if c and c.idx < c.steps.size():
		what = Defs.describe_step(c.steps[c.idx])
	elif c and c.captain:
		what = "captain, standing by"
	elif m.leads_post(u):
		what = "captain of the %s" % m.post_of(u).name
	var gear := ""
	if u.weapon != "" or u.bow:
		gear = " · " + (Defs.item_name(u.weapon) if u.weapon != "" else "bow")
	var who: String = u.name if c == null or c.members.size() <= 1 else "%s (%s)" % [u.name, m.crew_label(c)]
	var action := "Enter to order crew" if c and c.members.size() > 1 else "Enter to give orders"
	if selected.has(u.id):
		action = "selected · Shift+click to drop"
	elif not selected.is_empty():
		action = "click to select · Shift+click to add"
	else:
		action += " · click to select"
	return "%s — %s%s · %s" % [who, what, gear, action]


func _describe_building(b) -> String:
	if b == null:
		return ""
	var name: String = Defs.building_name(b.type)
	if b.type == "armory":
		name += " (%s)" % ["wood", "bronze", "iron"][b.tier]
	if b.type == "smelter" and b.tier >= 1:
		name = "Iron furnace"
	if b.faction == 1:
		return "Enemy " + name.to_lower()
	if not b.complete:
		if not b.paid:
			return "%s — site, waiting for builders (%s)" % [name, Defs.cost_text(Defs.BUILDINGS[b.type]["cost"])]
		return "%s — %d%% built" % [name, int(b.progress * 100)]
	var extra := ""
	match b.type:
		"armory":
			var f = m.fac(0)
			var parts: Array[String] = []
			for k in f.gear:
				if int(f.gear[k]) > 0:
					parts.append("%d %s" % [f.gear[k], Defs.item_name(k, int(f.gear[k]))])
			extra = " · E: take gear · " + (", ".join(parts) if not parts.is_empty() else "empty")
		"stable":
			var n := 0
			for h in m.units:
				if not h.dead and h.kind == "horse" and h.stable == b.id:
					n += 1
			extra = " · %d horses · F: ride" % n
		"mine":
			extra = " · " + Defs.RESOURCE_NAMES.get(b.deposit, "")
		"campfire":
			extra = " · home"
	if b.upgrading != "":
		extra += " · upgrading %d%%" % int(100.0 * b.up_work / float(Defs.UPGRADES[b.upgrading]["work"]))
	if b.research != "":
		extra += " · researching %d%%" % int(100.0 * b.research_t / float(Defs.RESEARCH[b.research]["time"]))
	if b.hp < b.max_hp * 0.98:
		extra += " · %d%% intact" % int(100.0 * b.hp / b.max_hp)
	return name + extra


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not ready_done or over_shown or Time.get_ticks_msec() - start_ms < 600:
		return
	if intro != null and intro.blocking():
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			intro.skip()
			get_viewport().set_input_as_handled()
		return
	if hud.chat_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if paused:
			if k == KEY_ESCAPE:
				_set_paused(false)
			return
		if hud.menu_open:
			if k == KEY_ESCAPE or (k == KEY_TAB and menu_kind == "ledger"):
				_close_menu()
			elif k >= KEY_0 and k <= KEY_9:
				_menu_select(10 if k == KEY_0 else k - KEY_0)
			elif k == KEY_ENTER or k == KEY_T:
				_close_menu()
				open_chat()
			get_viewport().set_input_as_handled()
			return
		match k:
			KEY_ENTER, KEY_KP_ENTER:
				if placing and Defs.BUILDINGS[place_type].get("wall", false):
					_finish_wall()
				else:
					open_chat()
			KEY_T:
				open_chat()
			KEY_SLASH:
				open_chat("/")
			KEY_ESCAPE:
				if placing:
					_cancel_place()
				elif not selected.is_empty():
					_clear_selection()
				elif map_open:
					_toggle_map()
				else:
					_set_paused(true)
			KEY_TAB:
				_menu_ledger()
			KEY_M:
				_toggle_map()
			KEY_B:
				_menu_build()
			KEY_C:
				_menu_craft()
			KEY_F1, KEY_H:
				_menu_help()
			KEY_E:
				if placing:
					place_rot += deg_to_rad(15.0)
				else:
					_interact()
			KEY_Q:
				if placing:
					place_rot -= deg_to_rad(15.0)
				else:
					var msg: String = cmd.toggle_weapon()
					if msg != "":
						hud.show_toast(msg)
			KEY_F:
				var r: String = m.commander_mount(0)
				if r != "":
					hud.log_line(r, "system")
			KEY_R:
				_mark()
			KEY_G:
				var r2: String = m.commander_take_gear(0)
				hud.log_line(r2, "system")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if paused or hud.menu_open:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if placing:
					_place_click()
				elif not _click_select(event.shift_pressed):
					cmd.primary_pressed()
			else:
				cmd.primary_released()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if placing:
				if Defs.BUILDINGS[place_type].get("wall", false) and wall_points.size() >= 1:
					_finish_wall()
				else:
					_cancel_place()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and placing:
			place_rot += deg_to_rad(15.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and placing:
			place_rot -= deg_to_rad(15.0)


func _set_paused(on: bool) -> void:
	paused = on
	hud.show_pause(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	cmd.look_enabled = not on
	get_tree().paused = false


func _on_pause_choice(name: String) -> void:
	match name:
		"resume":
			_set_paused(false)
		"help":
			_set_paused(false)
			_menu_help()
		"settings":
			finished.emit("settings")
		"menu":
			finished.emit("menu")
		"again":
			finished.emit("again")
		"quit":
			finished.emit("quit")


func _interact() -> void:
	if look_unit >= 0:
		var u = m.unit(look_unit)
		if u and u.faction == 0 and u.kind == "villager":
			open_chat()
			return
	var arm = m.nearest_building(0, Vector2(cmd.position.x, cmd.position.z), ["armory"])
	if arm and m.dist_to_building(Vector2(cmd.position.x, cmd.position.z), arm) < 5.0:
		hud.log_line(m.commander_take_gear(0), "system")
		return
	var st = m.nearest_building(0, Vector2(cmd.position.x, cmd.position.z), ["stable"])
	if st and m.dist_to_building(Vector2(cmd.position.x, cmd.position.z), st) < 5.0:
		hud.log_line(m.commander_mount(0), "system")
		return
	hud.show_toast("Look at a villager and press E or Enter to talk. Stand by the armory and press E for gear.")


func _mark() -> void:
	var hit = view.ground_hit(cmd.eye(), cmd.look_dir(), 300.0)
	if hit == null:
		hud.show_toast("Look at the ground to mark a spot.")
		return
	m.set_mark(0, Vector2(hit.x, hit.z))
	hud.log_line("Spot marked. Orders can now say 'there' or 'the mark' (e.g. 'guard the mark').", "system")
	Sfx.play("click", null, -6.0)


# --- Selection -------------------------------------------------------------------------

## Left click on one of your villagers selects them; Shift+click adds or drops them.
## Returns false when the click wasn't on a villager, so it stays an attack.
func _click_select(additive: bool) -> bool:
	if look_unit < 0:
		return false
	var u = m.unit(look_unit)
	if u == null or u.dead or u.faction != 0 or u.kind != "villager":
		return false
	if u.child:
		hud.show_toast("%s is a child and can't work yet." % u.name)
		return true
	if additive:
		if selected.has(u.id):
			selected.erase(u.id)
		else:
			selected.append(u.id)
	elif selected.size() == 1 and selected[0] == u.id:
		selected.clear()
	else:
		selected = [u.id]
	Sfx.play("click", null, -10.0)
	_show_selection()
	return true


func _clear_selection() -> void:
	selected.clear()
	_show_selection()


func _prune_selection() -> void:
	var keep: Array[int] = []
	for id in selected:
		if m.orderable_unit(0, id):
			keep.append(id)
	selected = keep


func _selection_label() -> String:
	if selected.is_empty():
		return ""
	if selected.size() == 1:
		return m.unit(selected[0]).name
	var names: Array[String] = []
	for id in selected.slice(0, 3):
		names.append(m.unit(id).name)
	var more := selected.size() - names.size()
	return ", ".join(names) + (" +%d" % more if more > 0 else "") + " (%d selected)" % selected.size()


func _show_selection() -> void:
	var label := _selection_label()
	if selected.size() == 1:
		var held = _captains_post(selected[0])
		var led = _captains_crew(selected[0])
		if held:
			label = m.post_label(held)
		elif led:
			label = m.crew_label(led)
	hud.set_selection(("Selected: " + label + "  ·  Enter to order · Esc to clear") if not selected.is_empty() else "")
	view.selected_ids = selected


func _update_selection() -> void:
	var before := selected.size()
	_prune_selection()
	if selected.size() != before:
		_show_selection()


func _on_attack_result(text: String) -> void:
	if text.begins_with("hit:"):
		return
	hud.show_toast(text)


# --- Chat and orders -----------------------------------------------------------------

func open_chat(prefill: String = "") -> void:
	chat_crew = -1
	chat_first_member = -1
	addressee = {}
	address_label = "your people"
	_prune_selection()
	var captain_id: int = selected[0] if selected.size() == 1 else (look_unit if selected.is_empty() else -1)
	var held = _captains_post(captain_id)
	if held:
		_open_post_chat(held, prefill)
		return
	if selected.size() == 1:
		var led = _captains_crew(selected[0])
		if led:
			_open_crew_chat(led, selected[0], prefill)
			return
		addressee = {"unit": selected[0], "individual": true}
		address_label = m.unit(selected[0]).name + " alone"
	elif selected.size() > 1:
		addressee = {"units": selected.duplicate()}
		address_label = _selection_label()
	elif look_unit >= 0:
		var u = m.unit(look_unit)
		if u and u.faction == 0 and u.kind == "villager" and not u.dead:
			if u.child:
				hud.show_toast("%s is a child and can't work yet." % u.name)
			else:
				var c = m.crew_of(u)
				if c and c.members.size() > 1:
					_open_crew_chat(c, u.id, prefill)
					return
				addressee = {"unit": u.id}
				address_label = u.name
	cmd.move_enabled = false
	hud.open_chat(address_label, prefill)


func _captains_post(id: int):
	var u = m.unit(id)
	return m.post_of(u) if u and u.faction == 0 and m.leads_post(u) else null


func _open_post_chat(p, prefill: String = "") -> void:
	chat_crew = -1
	addressee = {"post": p.id}
	address_label = m.post_label(p)
	cmd.move_enabled = false
	hud.open_chat(address_label, prefill)


## The crew this person captains, if anyone else is in it.
func _captains_crew(id: int):
	var u = m.unit(id)
	if u == null:
		return null
	var c = m.crew_of(u)
	return c if c and c.captain and c.leader == id and c.members.size() > 1 else null


func _open_crew_chat(c, first_member: int, prefill: String = "") -> void:
	chat_crew = c.id if c.members.size() > 1 else -1
	chat_first_member = first_member
	addressee = {"crew": c.id, "person": first_member}
	address_label = m.crew_label(c)
	cmd.move_enabled = false
	hud.open_chat(address_label, prefill, chat_crew >= 0)


func _cycle_chat_address(backward: bool) -> void:
	if chat_crew < 0:
		return
	var c = m.crews.get(chat_crew)
	var members := []
	if c:
		var first := maxi(0, c.members.find(chat_first_member))
		for offset in c.members.size():
			var id: int = c.members[(first + offset) % c.members.size()]
			if m.orderable_unit(0, id):
				members.append(id)
	if members.is_empty():
		hud.show_toast("That crew is no longer available.")
		return
	# Index 0 addresses the crew. The other entries start with the villager in view.
	var current := members.find(addressee.get("unit", -1)) + 1
	var next := posmod(current + (-1 if backward else 1), members.size() + 1)
	if next == 0:
		addressee = {"crew": c.id, "person": chat_first_member}
		address_label = m.crew_label(c)
	else:
		var u = m.unit(members[next - 1])
		addressee = {"unit": u.id, "individual": true}
		address_label = u.name + " alone"
	hud.set_chat_address(address_label, true)


func _on_chat_changed(text: String) -> void:
	var draft := text.strip_edges()
	if not draft.begins_with("/"):
		return
	var token := draft.substr(1).strip_edges().get_slice(" ", 0).to_lower()
	if token == "" and chat_hint_command != "":
		return
	var command: String = SLASH_ALIASES.get(token, "h" if token == "" else token)
	if command == chat_hint_command or not CHAT_HINTS.has(command):
		return
	chat_hint_command = command
	chat_hint_items = []
	var hint: Array = CHAT_HINTS[command]
	var body: String = hint[1]
	var choices := ""
	match command:
		"b":
			choices = _chat_hint_grid(m.build_menu(0))
		"c":
			var has_armory: bool = m.armory_tier(0) >= 0
			var recipes: Array = m.craft_menu(0)
			if not has_armory:
				body = "Build an armory with [b]/b armory[/b] to unlock these recipes."
				recipes = recipes.filter(func(e): return Defs.ITEMS[e["id"]]["tier"] == 0)
			choices = _chat_hint_grid(recipes, has_armory)
		"t":
			body += "\n" + m.next_age_text(0)
	hud.show_chat_hint(hint[0], body, choices)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _chat_hint_grid(entries: Array, show_lock_reason: bool = true) -> String:
	chat_hint_items = _by_shortfall(entries.filter(func(e): return e["locked"] == ""))
	var cells: Array[String] = []
	for i in chat_hint_items.size():
		var e: Dictionary = chat_hint_items[i]
		cells.append("[url=%d][color=#ffd870]%s[/color]  %s[/url]" % [i, e["name"], _cost_bb(e["cost"], e["missing"])])
	var locked := entries.filter(func(e): return e["locked"] != "")
	if show_lock_reason:
		return _grid_bb(cells, 1) + _locked_bb(locked)
	for e in locked:
		cells.append("[color=#b8b0a0]%s[/color]  %s" % [e["name"], _cost_bb(e["cost"], {})])
	return _grid_bb(cells, 1)


func _on_chat_choice(index: int) -> void:
	if not hud.chat_open or index < 0 or index >= chat_hint_items.size():
		return
	var entry: Dictionary = chat_hint_items[index]
	hud.close_chat()
	_on_chat_closed()
	_choose_order_entry(entry)


func _on_chat_closed() -> void:
	if chat_hint_command != "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chat_hint_command = ""
	chat_hint_items.clear()
	cmd.move_enabled = true


## Who a message names: "@Hal ...", "Captain Hal, ...", "Hal, ..." or "tell Hal to ...".
## {} when it names nobody, otherwise {unit, rest, error}.
func _named_in(text: String) -> Dictionary:
	var low := text.to_lower()
	var found: Dictionary
	if text.begins_with("@"):
		var tag := text.substr(1)
		if tag.to_lower().begins_with("captain "):
			tag = tag.substr(8)
		found = m.find_person(0, tag, true)
		if found["unit"] == null and found["error"] == "":
			found["error"] = "Nobody here is called %s. Type /p to see your people." % tag.get_slice(" ", 0).rstrip(",:").capitalize()
		return found
	if low.begins_with("captain "):
		var said := text.substr(8)
		found = m.find_person(0, said)
		if found["unit"] != null or found["error"] != "":
			return found
		var comma := said.find(",")
		if comma > 0 and said.left(comma).split(" ", false).size() <= 3:
			found["error"] = "There's no Captain %s. Type /p to see your people." % said.left(comma)
			return found
		return {}
	if low.begins_with("tell "):
		found = m.find_person(0, text.substr(5))
		if found["unit"] != null and found["rest"].to_lower().begins_with("to "):
			found["rest"] = found["rest"].substr(3)
			return found
		return found if found["error"] != "" else {}
	var mark := text.find(",") if text.contains(",") else text.find(":")
	if mark > 0:
		var head := text.left(mark).strip_edges()
		found = m.find_person(0, head)
		if found["error"] != "" and not head.contains(" "):
			return found
		if found["unit"] != null and found["rest"] == "":
			found["rest"] = text.substr(mark + 1).strip_edges()
			return found
	return {}


func _on_chat(text: String) -> void:
	_on_chat_closed()
	if text.begins_with("/"):
		_slash(text)
		return
	var req := addressee.duplicate()
	var who := address_label if not addressee.is_empty() and address_label != "" else "your people"
	var first_word := text.get_slice(" ", 0)
	if first_word.to_lower().rstrip(",:") in ["@all", "@everyone", "@everybody"]:
		req = {"all": true}
		who = "everyone"
		text = text.substr(first_word.length()).strip_edges()
	else:
		var named := _named_in(text)
		if not named.is_empty():
			var u = named["unit"]
			if u == null:
				hud.log_line(named["error"], "warn")
				return
			text = named["rest"]
			if u.child:
				hud.log_line("%s is a child and can't work yet." % u.name, "warn")
				return
			var c = m.crew_of(u)
			var held = _captains_post(u.id)
			if held:
				req = {"post": held.id}
				who = m.post_label(held)
			elif c and c.members.size() > 1:
				req = {"crew": c.id, "person": u.id}
				who = m.crew_label(c)
			else:
				req = {"unit": u.id}
				who = u.name
	if text.strip_edges() == "":
		return
	hud.log_line(text, "you", "You → " + who)
	var order := text.strip_edges().to_lower()
	if order.begins_with("join @"):
		var named_dest: Dictionary = m.find_person(0, order.substr(6).strip_edges().trim_suffix("."), true)
		var destination = named_dest["unit"]
		if destination == null:
			hud.log_line(named_dest["error"] if named_dest["error"] != "" else "Use 'join @Name' with the name of someone in the destination crew.", "warn")
			return
		var result: Dictionary = m.reassign_crew(0, req, destination.id)
		if result["ok"]:
			hud.log_line("%s joined %s." % [who.trim_suffix(" alone"), m.crew_label(m.crews[result["crew"]])], "crew")
		else:
			hud.log_line(result["error"], "warn")
		return
	var naming := RegEx.create_from_string("(?i)^(?:call|name) (?:this|that|here)(?: place| spot)? (.+?)[.!]*$").search(text.strip_edges())
	if naming:
		_name_place(naming.get_string(1).strip_edges())
		return
	var parsed: Dictionary = Parser.parse(text, m.places_of(0).keys())
	if parsed.get("cancel", false):
		if _discard_terra_request(req):
			hud.log_line("Order dropped.", "terra", "Terra")
		else:
			_stop_orders(req)
		return
	if parsed.get("confirm", false):
		hud.log_line("Orders start when you give them. For construction, choose a site to start.", "hint")
		return
	if parsed.get("ok", false):
		if parsed.get("all", false) and req.is_empty():
			req = {"all": true}
			who = "everyone"
		_execute(req, parsed["steps"], who)
		return
	if terra.available():
		if terra.busy:
			hud.log_line("Terra is still thinking about your last order.", "warn")
			return
		terra_ctx = {"req": req, "who": who, "text": text}
		hud.set_thinking("Terra is thinking…")
		var crew_id := int(req.get("crew", -1))
		if req.has("unit") and not req.get("individual", false):
			var u2 = m.unit(req["unit"])
			if u2 and u2.crew >= 0:
				crew_id = u2.crew
		terra.ask(m.brief(0, who, crew_id, req.get("individual", false), req.get("units", []).size()), text, dialogue)
	else:
		hud.log_line("I didn't catch that. Try 'gather wood', 'build a hut' or /h for help. Choose a Terra connection in Settings for free-form orders.", "warn")


func _on_terra(result: Dictionary) -> void:
	var ctx := terra_ctx
	terra_ctx = {}
	hud.set_thinking("")
	if ctx.is_empty() or m.over:
		return
	if not result.get("ok", false):
		hud.log_line(result.get("error", "Terra could not answer."), "warn")
		return
	var d: Dictionary = result["data"]
	var reply := str(d.get("reply", ""))
	dialogue.append({"player": ctx["text"], "terra": reply})
	while dialogue.size() > 6:
		dialogue.pop_front()
	if reply != "":
		hud.log_line(reply, "terra", "Terra")
	match str(d.get("kind", "reply")):
		"plan":
			var steps: Array = Match.clean_steps(d.get("steps", []))
			var err := Defs.validate_steps(steps)
			if err == "":
				for s in steps:
					err = m.step_problem(0, s)
					if err != "":
						break
			if err != "":
				hud.log_line("That plan can't be done yet: " + err, "warn")
				return
			_execute(ctx["req"], steps, ctx["who"])
		"cancel":
			_stop_orders(ctx["req"])


func _discard_terra_request(req: Dictionary) -> bool:
	if terra_ctx.is_empty() or (not req.is_empty() and not req.get("all", false) and req != terra_ctx["req"]):
		return false
	terra_ctx = {}
	hud.set_thinking("")
	return true


func _name_place(title: String) -> void:
	if not Parser.can_name_place(title):
		hud.log_line("'%s' already means something in orders. Pick another name." % title, "warn")
		return
	var r: Dictionary = m.name_place(0, title)
	if r["ok"]:
		hud.log_line("This is %s now. Orders can use the name." % title, "system")
	else:
		hud.log_line(r["error"], "warn")


func _stop_orders(req: Dictionary) -> void:
	var n: int = m.cancel(0, req if not req.is_empty() else {"all": true})
	hud.log_line("Stopped." if n > 0 else "Nobody was doing anything.", "crew")


func _execute(req: Dictionary, steps: Array, who: String) -> void:
	steps = m.resolve_steps(0, steps)
	if req.get("individual", false) or req.has("units"):
		for s in steps:
			if s["action"] != "mandate":    # there, the number is the post's size
				s["count"] = 0
	var needs := []
	for i in steps.size():
		if steps[i]["action"] == "build":
			needs.append(i)
	if needs.is_empty():
		_issue(req, steps, who)
		return
	if placing:
		hud.log_line("Finish or cancel the current placement before giving another build order.", "warn")
		return
	for i in needs:
		var why: String = m.unlock_problem(0, steps[i]["subject"])
		if why != "":
			hud.log_line(why, "warn")
			return
	place_req = {"req": req, "steps": steps, "who": who, "needs": needs, "k": 0}
	placed_ids = []
	_begin_place(steps[needs[0]]["subject"])


func _describe_order(step: Dictionary, req: Dictionary) -> String:
	if req.get("individual", false) and step["action"] == "dismiss":
		return "leave the crew"
	return Defs.describe_step(step)


func _issue(req: Dictionary, steps: Array, who: String, sites: Array = []) -> void:
	var full := req.duplicate()
	full["steps"] = steps
	var r: Dictionary = m.command(0, full)
	if r.get("ok", false):
		var parts: Array[String] = []
		for s in steps:
			parts.append(_describe_order(s, req))
		var label := who
		if (label == "your people" or req.has("units")) and not r.get("crews", []).is_empty():
			var c = m.crews.get(r["crews"][0])
			if c:
				label = m.crew_label(c)
		hud.log_line("%s: %s." % [label.capitalize() if label == "everyone" else label, ", then ".join(parts)], "crew")
		Sfx.play("click", null, -10.0)
		if tutorial:
			tutorial.on_command(steps, r)
	else:
		hud.log_line(r.get("error", "That order didn't work."), "warn")
		for id in sites:
			m.remove_site(id)


# --- Placement --------------------------------------------------------------------------

func _begin_place(type: String) -> void:
	placing = true
	place_type = type
	wall_points = []
	var me = m.commander(0)
	# Door (local +Z) faces the commander.
	place_rot = PI - (me.facing if me else 0.0)
	var d: Dictionary = Defs.BUILDINGS[type]
	if d.get("wall", false):
		hud.show_toast("%s: click to set posts, Enter or right-click to finish, Esc to cancel." % d["name"])
	else:
		hud.show_toast("Place the %s: click to confirm, Q/E or the wheel to turn, Esc to cancel." % d["name"].to_lower())


func _aim_point():
	return view.ground_hit(cmd.eye(), cmd.look_dir(), 90.0)


func _update_place() -> void:
	var hit = _aim_point()
	var d: Dictionary = Defs.BUILDINGS[place_type]
	if hit == null:
		view.hide_ghost()
		hud.set_prompt("Look at the ground.")
		return
	place_pos = Vector2(hit.x, hit.z)
	var cost_note := ""
	var miss: Dictionary = m.missing_cost(0, d["cost"])
	if not miss.is_empty():
		cost_note = " · needs %s more" % Defs.cost_text(miss)
	if d.get("wall", false):
		var pts := wall_points.duplicate()
		pts.append(place_pos)
		var pieces := []
		var total := 0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var len := a.distance_to(b)
			if len < 1.0:
				continue
			var n := maxi(1, int(ceil(len / float(d["length"]))))
			var rot := atan2((b - a).y, (b - a).x)
			for k in n:
				var mid := a.lerp(b, (k + 0.5) / n)
				var ok: bool = m.site_problem(0, place_type, mid, rot, Vector2(len / n, d["thick"])) == ""
				pieces.append([mid, rot, len / n, ok])
				total += 1
		view.hide_ghost()
		view.show_wall_ghosts(place_type, pieces)
		var cost_each: Dictionary = d["cost"]
		var all_cost := {}
		for r in cost_each:
			all_cost[r] = int(cost_each[r]) * total
		hud.set_prompt("%s: %d posts, %d pieces (%s) · click: post · Enter: finish · Esc: cancel" % [d["name"], wall_points.size(), total, Defs.cost_text(all_cost)])
		place_ok = total > 0
		return
	var why: String = m.site_problem(0, place_type, place_pos, place_rot)
	place_ok = why == ""
	view.show_ghost(place_type, place_pos, place_rot, place_ok)
	hud.set_prompt(("%s — click to place%s" % [d["name"], cost_note]) if place_ok else why)


func _place_click() -> void:
	var d: Dictionary = Defs.BUILDINGS[place_type]
	if d.get("wall", false):
		if _aim_point() == null:
			return
		wall_points.append(place_pos)
		Sfx.play("click", null, -8.0)
		return
	if not place_ok:
		Sfx.play("click", null, -2.0, 0.6)
		return
	var r: Dictionary = m.place_site(0, place_type, place_pos, place_rot)
	if not r.get("ok", false):
		hud.show_toast(r.get("error", "Can't build there."))
		return
	_site_done([r["id"]])


func _finish_wall() -> void:
	var pts := wall_points.duplicate()
	if pts.size() == 1 and _aim_point() != null:
		pts.append(place_pos)
	if pts.size() < 2:
		hud.show_toast("Set at least two posts.")
		return
	var r: Dictionary = m.place_wall(0, place_type, pts)
	if not r.get("ok", false):
		hud.show_toast(r.get("error", "Can't build a wall there."))
		return
	if int(r.get("skipped", 0)) > 0:
		hud.log_line("%d pieces were left out (%s)." % [r["skipped"], r.get("error", "blocked")], "warn")
	_site_done(r["ids"])


func _site_done(ids: Array) -> void:
	placed_ids.append_array(ids)
	var pr := place_req
	var idx: int = pr["needs"][pr["k"]]
	pr["steps"][idx]["sites"] = ids
	pr["k"] = int(pr["k"]) + 1
	view.hide_ghost()
	Sfx.play("click", null, -6.0)
	if pr["k"] < pr["needs"].size():
		_begin_place(pr["steps"][pr["needs"][pr["k"]]]["subject"])
		return
	placing = false
	hud.set_prompt("")
	place_req = {}
	var sites := placed_ids
	placed_ids = []
	_issue(pr["req"], pr["steps"], pr["who"], sites)


func _cancel_place() -> void:
	placing = false
	view.hide_ghost()
	hud.set_prompt("")
	for id in placed_ids:
		m.remove_site(id)
	placed_ids = []
	place_req = {}
	hud.show_toast("Placement cancelled.")


# --- Slash commands and menus -----------------------------------------------------------

func _slash(text: String) -> void:
	var parts := text.substr(1).strip_edges().split(" ", false)
	var token := parts[0].to_lower() if parts.size() > 0 else "h"
	var c: String = SLASH_ALIASES.get(token, token)
	var arg := " ".join(parts.slice(1)).strip_edges()
	match c:
		"b":
			if arg != "":
				_build_by_name(arg)
			else:
				_menu_build()
		"c":
			if arg != "":
				_craft_by_name(arg)
			else:
				_menu_craft()
		"l":
			_menu_ledger()
		"p":
			_menu_people()
		"s":
			_menu_reports()
		"m":
			_toggle_map()
		"t":
			_menu_tech()
		"h":
			_menu_help()
		"cancel":
			_discard_terra_request(addressee)
			var n: int = m.cancel(0, addressee if not addressee.is_empty() else {"all": true})
			if addressee.get("individual", false):
				hud.log_line("Released %s." % address_label.trim_suffix(" alone") if n > 0 else "They had no assignment.", "crew")
			else:
				hud.log_line("Stopped %d crew%s." % [n, "" if n == 1 else "s"], "crew")
		_:
			hud.log_line("Unknown command /%s. Type /h for the list." % c, "warn")


func _open_menu(kind: String, title: String, body: String, footer: String = "Number keys or click to choose · Esc to close", grid: bool = false) -> void:
	menu_kind = kind
	hud.show_menu(title, body, footer, grid)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cmd.look_enabled = false
	cmd.move_enabled = false


func _close_menu() -> void:
	hud.hide_menu()
	menu_kind = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cmd.look_enabled = true
	cmd.move_enabled = not hud.chat_open


func _cost_bb(cost: Dictionary, miss: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array[String] = []
	for r in cost:
		var col := "ff8070" if miss.has(r) else "e8dcc2"
		parts.append("[color=#%s]%d %s[/color]" % [col, int(cost[r]), Defs.RESOURCE_NAMES.get(r, r)])
	return ", ".join(parts)


## Affordable first. sort_custom isn't stable, so ties are broken by catalog order.
func _by_shortfall(entries: Array) -> Array:
	var order := range(entries.size())
	order.sort_custom(func(a, b):
		var short_a: int = entries[a]["missing"].size()
		var short_b: int = entries[b]["missing"].size()
		return short_a < short_b or (short_a == short_b and a < b))
	return order.map(func(i): return entries[i])


func _grid_bb(cells: Array[String], gap: int) -> String:
	if cells.is_empty():
		return ""
	var out := "[table=%d]" % MENU_COLUMNS
	# Pad the last row, so short lists keep the same column widths.
	for i in ceili(cells.size() / float(MENU_COLUMNS)) * MENU_COLUMNS:
		out += "[cell expand=1 shrink=false padding=0,%d,18,%d]%s[/cell]" % [gap, gap, cells[i] if i < cells.size() else " "]
	return out + "[/table]"


## Locked entries share a few reasons, so name each reason once.
func _locked_bb(locked: Array) -> String:
	var groups := {}
	for e in locked:
		var label: String = e["name"]
		if e["kind"] == "craft":
			label = Defs.item_name(e["id"], 2)
		groups.get_or_add(e["locked"], []).append(label)
	var out := ""
	for reason: String in groups:
		var sentence := reason.left(1).to_upper() + reason.substr(1)
		out += "\n[font_size=16][color=#c0a878]%s[/color]  [color=#948c7e]%s[/color][/font_size]" % [sentence, ", ".join(groups[reason])]
	return out


func _menu_build() -> void:
	var all: Array = m.build_menu(0)
	var ready := _by_shortfall(all.filter(func(e): return e["locked"] == ""))
	var locked := all.filter(func(e): return e["locked"] != "")
	menu_items = ready
	var cells: Array[String] = []
	for i in ready.size():
		var e: Dictionary = ready[i]
		var key := str(i + 1) if i < 9 else ("0" if i == 9 else "·")
		cells.append("[url=%d][b][color=#ffd870]%s  %s[/color][/b]  %s\n[font_size=15][color=#b8b0a0]%s[/color][/font_size][/url]" % [i + 1, key, e["name"], _cost_bb(e["cost"], e["missing"]), e["desc"]])
	var who := ("for " + address_label) if not addressee.is_empty() else "(the nearest free villagers will build)"
	_open_menu("build", "Build  " + who, _grid_bb(cells, 4) + _locked_bb(locked),
		"Number keys or click to choose · red means you're short · Esc to close", true)


func _menu_craft() -> void:
	var all: Array = m.craft_menu(0)
	if m.armory_tier(0) < 0:
		_open_menu("none", "Craft", "You need an [b]armory[/b] first. Open /b to build one (50 wood).", "Esc to close")
		return
	var ready := all.filter(func(e): return e["locked"] == "")
	var locked := all.filter(func(e): return e["locked"] != "")
	menu_items = ready
	var cells: Array[String] = []
	for i in ready.size():
		var e: Dictionary = ready[i]
		var key := str(i + 1) if i < 9 else ("0" if i == 9 else "·")
		cells.append("[url=%d][b][color=#ffd870]%s  %s[/color][/b]\n[font_size=16]%s  [color=#b8b0a0]· %d in armory[/color][/font_size][/url]" % [i + 1, key, e["name"], _cost_bb(e["cost"], e["missing"]), e["stock"]])
	_open_menu("craft", "Armory (%s)" % ["wood", "bronze", "iron"][maxi(0, m.armory_tier(0))], _grid_bb(cells, 4) + _locked_bb(locked),
		"Number keys or click: one batch · type '/c arrows 3' for three batches · Esc to close", true)


func _menu_select(i: int) -> void:
	if menu_kind == "people":
		if i == 10 and people_pages > 1:
			_menu_people((people_page + 1) % people_pages)
		elif i >= 1 and i <= menu_items.size():
			var row: Dictionary = menu_items[i - 1]
			_close_menu()
			if row.has("post") and m.posts.has(row["post"]):
				_open_post_chat(m.posts[row["post"]])
			elif row.has("crew") and m.crews.has(row["crew"]):
				var c = m.crews[row["crew"]]
				_open_crew_chat(c, c.leader)
		return
	if not menu_kind in ["build", "craft"]:
		return
	if i < 1 or i > menu_items.size():
		return
	var e: Dictionary = menu_items[i - 1]
	_close_menu()
	_choose_order_entry(e)


func _choose_order_entry(e: Dictionary) -> void:
	var req := addressee.duplicate()
	var who := address_label if not addressee.is_empty() else "your people"
	match e["kind"]:
		"build":
			_execute(req, [{"action": "build", "subject": e["id"], "count": 0, "amount": 0, "where": ""}], who)
		"upgrade":
			_issue(req, [{"action": "upgrade", "subject": e["id"], "count": 0, "amount": 0, "where": ""}], who)
		"research":
			_issue(req, [{"action": "research", "subject": e["id"], "count": 0, "amount": 0, "where": ""}], who)
		"craft":
			_issue(req, [{"action": "craft", "subject": e["id"], "count": 0, "amount": int(Defs.ITEMS[e["id"]]["batch"]), "where": ""}], who)


func _build_by_name(arg: String) -> void:
	var key := Parser.find_in(Parser.normalize(arg), Parser.BUILD_WORDS)
	if key == "":
		for id in Defs.buildable_ids():
			if Defs.building_name(id).to_lower().begins_with(arg.to_lower()):
				key = id
	if key == "":
		hud.log_line("There's no structure called '%s'. Type /b for the list." % arg, "warn")
		return
	if arg.to_lower().contains("stone") and key == "palisade":
		key = "stone_wall"
	_execute(addressee.duplicate(), [{"action": "build", "subject": key, "count": 0, "amount": 0, "where": ""}], address_label if not addressee.is_empty() else "your people")


func _craft_by_name(arg: String) -> void:
	var s := Parser.normalize(arg)
	var item := Parser.find_in(s, Parser.ITEM_WORDS)
	if item == "":
		hud.log_line("The armory can't make '%s'. Type /c for the list." % arg, "warn")
		return
	var batches := maxi(1, Parser.number_in(s))
	var st := Parser._step("craft", item, 0)
	var steps: Array = m.resolve_steps(0, [st])
	var id: String = steps[0]["subject"]
	steps[0]["amount"] = int(Defs.ITEMS[id]["batch"]) * batches
	_issue(addressee.duplicate(), steps, address_label if not addressee.is_empty() else "your people")


func _menu_ledger() -> void:
	if menu_kind == "ledger":
		_close_menu()
		return
	var f = m.fac(0)
	var lines: Array[String] = []
	lines.append("[b]%s age[/b] · %d:%02d into the match" % [Defs.AGES[f.age], int(m.t) / 60, int(m.t) % 60])
	lines.append("%s" % m.next_age_text(0))
	lines.append("")
	lines.append("[b]People[/b]  %d of %d housing  (%d adults, %d children, %d idle, %d armed)" % [f.pop, f.housing, f.adults, f.children, f.idle, f.soldiers])
	var need := int(ceil(f.pop * Defs.WELL_FED_STOCK))
	var fs: String = Defs.FOOD_STATES[f.food_state]
	var why := ""
	if f.food_state < 3:
		why = "  — well fed needs %d food stored (storage %d)" % [need, f.food_cap]
	elif f.pop >= f.housing:
		why = "  — but housing is full: build huts or houses"
	lines.append("[b]Food[/b]  %d stored · [color=#%s]%s[/color]%s" % [int(f.stock["food"]), "a8d890" if f.food_state == 3 else ("f0c060" if f.food_state >= 1 else "ff6a50"), fs, why])
	lines.append("")
	var res: Array[String] = []
	for r in ["wood", "stone", "bronze_ore", "coal", "iron_ore", "bronze", "iron"]:
		res.append("%s %d" % [Defs.RESOURCE_NAMES[r], int(f.stock.get(r, 0))])
	lines.append("[b]Stores[/b]  " + " · ".join(res))
	var gear: Array[String] = []
	for k in f.gear:
		if int(f.gear[k]) > 0:
			gear.append("%d %s" % [f.gear[k], Defs.item_name(k, int(f.gear[k]))])
	lines.append("[b]Armory[/b]  " + (", ".join(gear) if not gear.is_empty() else "empty"))
	lines.append("[b]Horses[/b]  %d in stables" % f.horses)
	lines.append("")
	lines.append("[b]Crews[/b]")
	for c in m.crews_of(0):
		lines.append("   " + m.crew_status(c))
	lines.append("")
	lines.append("[color=#b8b0a0]Births %d · deaths %d · enemies killed %d · Terra requests left: %s[/color]" % [f.births, f.deaths, f.kills, str(terra.remaining()) if terra.available() else "off"])
	_open_menu("ledger", "Ledger", "\n".join(lines), "Tab or Esc to close")


func _menu_people(page: int = 0) -> void:
	var rows := []
	for p in m.posts_of(0):
		rows.append({"post": p.id, "text": m.post_status(p)})
	for c in m.crews_of(0):
		if c.post < 0:      # a post's own jobs are summed up in its line
			rows.append({"crew": c.id, "text": m.crew_status(c)})
	people_pages = maxi(1, ceili(rows.size() / float(PEOPLE_PER_PAGE)))
	people_page = clampi(page, 0, people_pages - 1)
	menu_items = rows.slice(people_page * PEOPLE_PER_PAGE, (people_page + 1) * PEOPLE_PER_PAGE)
	var lines: Array[String] = []
	for i in menu_items.size():
		lines.append("[url=%d][b][color=#ffd870]%d[/color][/b][/url]  %s" % [i + 1, i + 1, menu_items[i]["text"]])
	if people_pages > 1:
		lines.append("[url=10][b][color=#ffd870]0[/color][/b][/url]  More (page %d of %d)" % [people_page + 1, people_pages])
	var f = m.fac(0)
	lines.append("")
	lines.append("[color=#b8b0a0]%d idle adults, %d children. Choose a crew to talk to it, or say @Name in chat.[/color]" % [f.idle, f.children])
	_open_menu("people", "People and crews", "\n".join(lines))


func _menu_reports() -> void:
	var f = m.fac(0)
	var lines: Array[String] = []
	if f.reports.is_empty():
		lines.append("No reports yet. Send a scout: [b]send a scout east[/b], or [b]scout their camp[/b].")
	for r in f.reports:
		var ago := int((m.t - float(r["t"])) / 60.0)
		lines.append("[color=#9cc8f0]%s[/color]  [color=#b8b0a0](%s)[/color]\n" % [r["text"], "just now" if ago < 1 else "%d min ago" % ago])
	_open_menu("reports", "Scout reports", "\n".join(lines), "Esc to close")


func _menu_tech() -> void:
	var f = m.fac(0)
	var lines: Array[String] = []
	for a in Defs.AGES.size():
		var reached: bool = f.age >= a
		var head := "[b][color=#%s]%s age[/color][/b]" % ["a8d890" if reached else "e8dcc2", Defs.AGES[a]]
		if reached and a > 0:
			head += "  [color=#b8b0a0](reached at %d:%02d)[/color]" % [int(f.age_t[a]) / 60, int(f.age_t[a]) % 60]
		elif not reached:
			head += "  — " + Defs.AGE_HOW[a]
		lines.append(head)
		var bl: Array[String] = []
		for id in Defs.BUILDINGS:
			if int(Defs.BUILDINGS[id]["age"]) == a and Defs.BUILDINGS[id].get("buildable", true):
				bl.append(Defs.BUILDINGS[id]["name"])
		var il: Array[String] = []
		for id in Defs.ITEMS:
			var it: Dictionary = Defs.ITEMS[id]
			var need: int = [0, 2, 3][it["tier"]]
			if it.has("research"):
				need = 4
			if need == a:
				il.append(Defs.item_name(id, 2))
		for id in Defs.UPGRADES:
			if int(Defs.UPGRADES[id]["age"]) == a:
				bl.append(Defs.UPGRADES[id]["name"] + " (upgrade)")
		if not bl.is_empty():
			lines.append("   Build: " + ", ".join(bl))
		if not il.is_empty():
			lines.append("   Armory: " + ", ".join(il))
		lines.append("")
	_open_menu("tech", "Tech tree", "\n".join(lines), "Esc to close")


func _menu_help() -> void:
	var t := """[b]Moving[/b]  WASD · Shift sprint · Space jump · mouse to look
[b]Fighting[/b]  Left click to strike (hold and release with a bow) · Q switch bow/weapon · G or E at the armory: take gear · F at the stable: ride
[b]Selecting[/b]  Look at a villager and [b]click[/b] to select them; [b]Shift+click[/b] adds or drops more. Orders you type then go to exactly the selected people, as one crew. [b]Esc[/b] clears the selection.
[b]Talking[/b]  Look at a villager and press [b]Enter[/b] (or T) to address their crew. In chat, [b]Tab[/b] cycles through individual members and back to the crew. [b]@Name[/b] addresses someone's crew by name, [b]@all[/b] addresses everyone. Idle villagers take orders with no addressee.
[b]Marking[/b]  R marks the spot you look at; orders can then say 'there' or 'the mark'.

[b]Slash commands[/b] (instant, no Terra needed)
   /b  build menu (or B) · /b hut builds a hut directly
   /c  craft menu (or C) · /c spears 2 makes two batches
   /l  ledger (or Tab outside chat) · /p people and crews · /s scout reports
   /m  field map (or M) · /t tech tree · /h this help · /cancel stop a crew

[b]Orders you can type[/b]
   gather wood · gather 30 stone then build a house · pick berries · work the farms · hunt
   build a hut · build a palisade · make 32 arrows · arm 6 with spears · to arms! · fall back
   send two scouts east · scout their camp · attack their camp · guard the mark · follow me · hold
   tame 3 horses · mount up · smelt bronze · upgrade the armory · research gunpowder · man the cannon
   promote (makes a captain) · dismiss · status · then chains steps
   Name, run the village · take twenty and run a mine here · set up a garrison at the mark · raise an army
   call this East Hill names the spot you just marked (R), or where you stand. Then: hold East Hill
   A captain with a post staffs and runs it. Talk to the captain and their people carry out the order.
   join @Name moves the addressed villager or crew to that person's crew.
   Terra starts orders when you send them. For construction, you choose each site.

[b]Winning[/b]  Kill Commander Rook (he wears a crown). If you fall, the match is lost.
[b]Growing[/b]  People are born only when the village is [i]well fed[/i] and there is free housing."""
	_open_menu("help", "Help", t, "Esc to close")


func _toggle_map() -> void:
	map_open = not map_open
	hud.map_view.visible = map_open
	if map_open:
		hud.map_view.refresh()
		map_refresh_t = 1.0


# --- End of the match -----------------------------------------------------------------------

func _show_end() -> void:
	over_shown = true
	if hud.chat_open:
		hud.close_chat()
		_on_chat_closed()
	var win: bool = m.winner == 0
	var f = m.fac(0)
	var mins := int(m.t) / 60
	var secs := int(m.t) % 60
	var body := ""
	if win:
		body = "Commander Rook has fallen after %d:%02d.\n\n" % [mins, secs]
	else:
		body = "You were killed after %d:%02d. Your people scatter.\n\n" % [mins, secs]
	body += "Peak population %d · enemies killed %d · births %d · %s age reached.\nRook played a %s opening." % [peak_pop, f.kills, f.births, Defs.AGES[f.age], ai.strategy]
	hud.show_end(win, body)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cmd.look_enabled = false
	cmd.move_enabled = false
	Sfx.play("age" if win else "horn", null, -4.0)
	Settings.set_val("matches_played", int(Settings.get_val("matches_played", 0)) + 1)
	if tutorial and win:
		Settings.set_val("tutorial_done", true)


func _exit_tree() -> void:
	Sfx.set_world(null)
