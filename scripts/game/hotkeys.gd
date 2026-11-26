extends RefCounted
## Read fixed shortcuts and typed item names for the build, armory and research grids.
## Reads what's typed after /b or /c and describes each slot for the popup.

const Defs = preload("res://scripts/data/defs.gd")

const MAX_BATCHES := 99


## The page a command has when it has only one, such as /r. Otherwise "".
static func only_page(command: String) -> String:
	var pages: Array = Defs.HOTKEYS[command].keys()
	return pages[0] if pages.size() == 1 else ""


## What follows the command in the chat line for this page: "/b v" but just "/r".
static func draft(command: String, page: String) -> String:
	return "/%s " % command if only_page(command) != "" else "/%s %s" % [command, page]


## With B or C the keys need no spaces: "bh" is page b, key h.
static func split_keys(command: String, args: PackedStringArray) -> PackedStringArray:
	var keys := "".join(args).to_lower()
	if only_page(command) != "":
		return PackedStringArray([keys]) if keys.length() == 1 else args
	if keys == "" or not keys[0] in Defs.HOTKEYS[command]:
		return args
	if keys.length() == 1:
		return PackedStringArray([keys])
	return PackedStringArray([keys[0], keys.substr(1)])


## {page, key, batches, entry, error}, or {} when the words are a name such as "hut".
## Crafting takes its count first, so the key can act the moment it's typed: /c 2 w.
static func read(m, command: String, args: PackedStringArray) -> Dictionary:
	var pick := {"page": "", "key": "", "batches": 1, "entry": {}, "error": ""}
	var words := Array(args)
	if command == "c" and not words.is_empty() and str(words[0]).is_valid_int():
		var count := int(words.pop_front())
		if count < 1 or count > MAX_BATCHES:
			pick["error"] = "Batches go from 1 to %d, as in /c 2 w." % MAX_BATCHES
			return pick
		pick["batches"] = count
	var sole := only_page(command)
	if sole != "":
		# One page: the first word is the key, or it's a name such as "gunpowder".
		if not words.is_empty() and str(words[0]).length() != 1:
			return {}
		words.push_front(sole)
	if words.is_empty():
		return pick
	var page := str(words[0]).to_lower()
	if not Defs.HOTKEYS[command].has(page):
		return {}
	pick["page"] = page
	if words.size() == 1:
		return pick
	var key := str(words[1]).to_lower()
	pick["key"] = key
	var slots: Dictionary = Defs.HOTKEYS[command][page]["keys"]
	if not slots.has(key):
		pick["error"] = "%s isn't a key on this page." % key.to_upper()
		return pick
	var e := entry(m, command, page, key)
	pick["entry"] = e
	if words.size() > 2:
		var last := str(words[2])
		if command == "c" and words.size() == 3 and last.is_valid_int() and int(last) >= 1 and int(last) <= MAX_BATCHES:
			pick["batches"] = int(last)   # still read when Enter sends the line, as with a recalled order
		elif command == "c":
			pick["error"] = "Batches go from 1 to %d, as in /c 2 %s." % [MAX_BATCHES, key]
		else:
			pick["error"] = "One key does one thing, as in %s%s." % [draft(command, page), key]
	if e["locked"] != "":
		pick["error"] = e["locked"]
	return pick


static func page_entries(m, command: String, page: String) -> Array:
	var out := []
	for key in Defs.HOTKEYS[command][page]["keys"]:
		out.append(entry(m, command, page, key))
	if command == "c":
		var overview: Dictionary = m.armory_overview(0)
		for row in out:
			row["inventory"] = overview[row["id"]]
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
			out.merge({"name": _sentence(item), "cost": Defs.item_cost(id, maxi(0, m.armory_tier(0))),
				"desc": "%d operators per engine." % int(it.crew) if it.has("crew") else "%d seconds to make." % int(it.time),
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
			else:
				for e: Dictionary in m.research_menu(0):
					if e["id"] == id:
						out["locked"] = e["locked"]   # no building yet, or too early an age
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
