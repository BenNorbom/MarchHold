extends RefCounted
## Build and craft by hotkey, StarCraft style: a page (b basic, v advanced), then one key.
## Reads what's typed after /b or /c and describes each slot for the popup.

const Defs = preload("res://scripts/data/defs.gd")

const MAX_BATCHES := 99


## With B or C the keys need no spaces: "bh" is page b, key h.
static func split_keys(args: PackedStringArray) -> PackedStringArray:
	var keys := "".join(args).to_lower()
	if keys == "" or not keys[0] in Defs.HOTKEY_PAGES:
		return args
	if keys.length() == 1:
		return PackedStringArray([keys])
	return PackedStringArray([keys[0], keys.substr(1)])


## {page, key, batches, entry, error}, or {} when the words are a name such as "hut".
static func read(m, command: String, args: PackedStringArray) -> Dictionary:
	var pick := {"page": "", "key": "", "batches": 1, "entry": {}, "error": ""}
	if args.is_empty():
		return pick
	var page := args[0].to_lower()
	if not page in Defs.HOTKEY_PAGES:
		return {}
	pick["page"] = page
	if args.size() == 1:
		return pick
	var key := args[1].to_lower()
	pick["key"] = key
	var slots: Dictionary = Defs.HOTKEYS[command][page]["keys"]
	if not slots.has(key):
		pick["error"] = "%s isn't a key on this page." % key.to_upper()
		return pick
	var e := entry(m, command, page, key)
	pick["entry"] = e
	if args.size() > 2:
		if command == "c" and args.size() == 3 and args[2].is_valid_int() and int(args[2]) >= 1 and int(args[2]) <= MAX_BATCHES:
			pick["batches"] = int(args[2])
		elif command == "c":
			pick["error"] = "Batches go from 1 to %d, as in /c %s %s 2." % [MAX_BATCHES, page, key]
		else:
			pick["error"] = "One key builds one structure, as in /b %s %s." % [page, key]
	if e["locked"] != "":
		pick["error"] = e["locked"]
	return pick


static func page_entries(m, command: String, page: String) -> Array:
	var out := []
	for key in Defs.HOTKEYS[command][page]["keys"]:
		out.append(entry(m, command, page, key))
	return out


static func entry(m, command: String, page: String, key: String) -> Dictionary:
	var slot: String = Defs.HOTKEYS[command][page]["keys"][key]
	var kind := slot.get_slice(":", 0)
	var id := slot.get_slice(":", 1)
	var out := {"kind": kind, "id": id, "key": key, "name": "", "cost": {}, "desc": "", "locked": "", "batch": 1}
	match kind:
		"build":
			var d: Dictionary = Defs.BUILDINGS[id]
			out.merge({"name": d["name"], "cost": d["cost"], "desc": d["desc"], "locked": m.unlock_problem(0, id)}, true)
		"craft":
			var it: Dictionary = Defs.ITEMS[id]
			var item := Defs.item_name(id)
			if id == "arrows":
				item = Defs.item_name(id, 2)
			out.merge({"name": _sentence(item), "cost": Defs.item_cost(id, maxi(0, m.armory_tier(0))),
				"desc": "%d in armory." % int(m.fac(0).gear.get(id, 0)),
				"locked": _sentence(m.craft_problem(0, id)), "batch": int(it["batch"])}, true)
		"upgrade":
			var up := _next_upgrade(m, id)
			out.merge({"name": up["name"], "cost": up["cost"], "desc": up["desc"]}, true)
			var problem: String = m._upgrade_for(0, id)
			var b = m.nearest_building(0, m.home_pos(0), [id])
			if problem.begins_with("!"):
				out["locked"] = _sentence(problem.substr(1))
			elif b and b.upgrading != "":
				out["locked"] = "Already being upgraded."
		"research":
			var r: Dictionary = Defs.RESEARCH[id]
			out.merge({"name": r["name"], "cost": r["cost"], "desc": r["desc"]}, true)
			if m.fac(0).researched.has(id):
				out["locked"] = "%s is already researched." % r["name"]
			elif not m.has_building(0, r["building"]):
				out["locked"] = "Needs a %s." % Defs.building_name(r["building"]).to_lower()
	out["missing"] = m.missing_cost(0, out["cost"])
	return out


## The upgrade after the building's current tier. Without one yet it's the first, when maxed the last.
static func _next_upgrade(m, building: String) -> Dictionary:
	var b = m.nearest_building(0, m.home_pos(0), [building])
	var tier: int = b.tier if b else 0
	var found := {}
	for id in Defs.UPGRADES:
		var up: Dictionary = Defs.UPGRADES[id]
		if up["building"] == building and int(up["from"]) <= tier:
			found = up
	return found


static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)
