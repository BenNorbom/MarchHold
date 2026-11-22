extends RefCounted
## Local order parser. Handles common orders instantly with no model call, and
## is the fallback when Terra isn't set up. Returns:
##   {"ok": bool, "steps": [...], "all": bool, "cancel": bool, "confirm": bool}

const Defs = preload("res://scripts/data/defs.gd")

const NUMBERS := {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
	"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
	"forty": 40, "fifty": 50, "hundred": 100, "a couple": 2, "couple": 2, "few": 3, "a few": 3, "dozen": 12}

const DIRECTIONS := {"north": "north", "northeast": "northeast", "north east": "northeast", "east": "east",
	"southeast": "southeast", "south east": "southeast", "south": "south", "southwest": "southwest",
	"south west": "southwest", "west": "west", "northwest": "northwest", "north west": "northwest"}

# Longest names first, so "stone wall" wins over "wall".
const BUILD_WORDS := [
	["stone wall", "stone_wall"], ["stone gate", "stone_gate"], ["palisade gate", "palisade_gate"],
	["wooden wall", "palisade"], ["wood wall", "palisade"], ["palisade", "palisade"], ["wall", "palisade"],
	["gate", "palisade_gate"], ["watch post", "watch_post"], ["watchpost", "watch_post"], ["lookout", "watch_post"],
	["stockpile", "stockpile"], ["storehouse", "stockpile"], ["farm", "farm"], ["field", "farm"],
	["armory", "armory"], ["armoury", "armory"], ["quarry", "quarry"], ["tower", "tower"],
	["hut", "hut"], ["stable", "stable"], ["mine", "mine"], ["smelter", "smelter"],
	["furnace", "smelter"], ["university", "university"], ["college", "university"]]

const ITEM_WORDS := [
	["iron sword", "iron_sword"], ["bronze sword", "bronze_sword"], ["sword", "bronze_sword:generic"],
	["iron spear", "iron_spear"], ["bronze spear", "bronze_spear"], ["wooden spear", "wood_spear"], ["spear", "wood_spear:generic"],
	["iron shield", "iron_shield"], ["bronze shield", "bronze_shield"], ["wooden shield", "wood_shield"], ["shield", "wood_shield:generic"],
	["iron armor", "iron_armor"], ["bronze armor", "bronze_armor"], ["armor", "bronze_armor:generic"], ["armour", "bronze_armor:generic"],
	["iron pike", "iron_pike"], ["pike", "bronze_pike:generic"], ["iron lance", "iron_lance"], ["lance", "bronze_lance:generic"],
	["bow", "bow"], ["arrow", "arrows"], ["cannonball", "shot"], ["cannon shot", "shot"], ["shot", "shot"],
	["cannon", "cannon"], ["battering ram", "ram"], ["ram", "ram"]]

const GATHER_WORDS := [
	["bronze ore", "bronze_ore"], ["iron ore", "iron_ore"], ["coal", "coal"], ["wood", "wood"], ["tree", "wood"],
	["timber", "wood"], ["log", "wood"], ["lumber", "wood"], ["stone", "stone"], ["rock", "stone"],
	["berries", "berries"], ["berry", "berries"], ["deer", "hunt"], ["meat", "hunt"], ["game", "hunt"],
	["grain", "farm"], ["wheat", "farm"], ["crop", "farm"], ["fields", "farm"], ["farm", "farm"],
	["food", "food:generic"], ["bronze", "bronze_ore"], ["iron", "iron_ore"], ["ore", "bronze_ore:generic"]]


# Picking construction back up, matched against whole clauses so "finish gathering wood"
# and "keep the wood coming" are left alone. {names} stands for BUILD_WORDS.
const RESUME_LEAD := "^ (?:(?:please|now|ok|okay|you|can you|could you|i want you to|i need you to|let's|everyone|everybody|all of you|all hands|just|go|go and|,) )*(?:(?:send|take|have|get|use) (?:[a-z0-9]+ ){1,3}to )?"
const RESUME_VERB := "(?:(?:continue|resume|restart|finish|finish off|complete|carry on)(?: with)?(?: (?:to build|building|constructing|(?:the )?construction (?:of|on)|(?:work|working) on(?! (?:the |that )?(?:farm|field))))?|(?:keep|keep on|keep at|help|help with|help to|join|get back to|go back to|return to|back to)(?: the)? (?:build|building|constructing|construction(?: of| on)?|finish|finishing))"
const RESUME_WHAT := "(?: (?:the|that|this|those|these|your|our|a|an))?(?: (?:unfinished|half built|half finished))?(?: (?:{names}|construction|building|project|site|job|work|it|that|this|what you started|what you were building)(?:s|es)?)?"
const RESUME_TAIL := "(?: (?:,|please|now|again|first|site|construction|where you left off|you started|you were building|you were working on))*(?: (?:near|by|next to|beside|outside|behind|over there|there|here)(?: [a-z']+){0,4})? $"
const RESUME_BARE := "(?:build (?:it|this|that|again)|start building again|pick up where you left off)(?: (?:please|now))? $"
# The start of a resume order with more to it than the parser knows.
const RESUME_START := "(?:(?:continue|resume|finish|complete)(?: with)? (?:to build|building|constructing|construction|the|that)|(?:keep|keep on|back to|get back to) (?:building|constructing)) "
const RESUME_MENTION := " (?:continue|resume|restart|finish|finish off|complete|carry on|back to|keep building|keep constructing) "
const EXISTING := " (?:build|construct|put up|raise|erect|make|set up) (?:the|that|this|those|these) "
const FRESH := " (?:new|another|second|extra) "

static var _regexes := {}


static func _matches(s: String, pattern: String) -> bool:
	if not _regexes.has(pattern):
		_regexes[pattern] = RegEx.create_from_string(pattern)
	return _regexes[pattern].search(s) != null


static func _resumes(p: String) -> bool:
	var names: Array[String] = []
	for pair in BUILD_WORDS:
		names.append(pair[0])
	var what := RESUME_WHAT.replace("{names}", "|".join(names))
	return _matches(p, RESUME_LEAD + RESUME_VERB + what + RESUME_TAIL) or _matches(p, RESUME_LEAD + RESUME_BARE)


## True when free text talks about carrying on and not about starting something new.
static func mentions_resume(text: String) -> bool:
	var s := normalize(text)
	return _matches(s, RESUME_MENTION) and not _matches(s, FRESH)


## Which standing sites the words fit. A plain "wall" or "gate" can be either material.
static func _site_kind(p: String, build: String) -> String:
	if build in ["palisade", "palisade_gate"]:
		for word in ["palisade", "wood", "wooden", "stone"]:
			if has_word(p, word):
				return build
		return "gate" if build == "palisade_gate" else "wall"
	return build


## Gathering keeps to a place only when the order points at one.
static func _work_place(p: String) -> String:
	if p.contains(" here ") or p.contains(" this spot ") or p.contains(" these "):
		return "here"
	var where := where_in(p)
	return where if where == "marked" or where in DIRECTIONS.values() else ""


# Making someone a captain. The title alone ("Captain Hal, ...") is an address, not an order.
const PROMOTE_RE := "( promote )|( (make|name|appoint|elect)( (?!for |with |to |from |by )[a-z']+){0,3} captains? )|( (be|become|you are|you're)( (a|an|the|my|our))? captains? )|(^ (a )?captain $)"
# "Hold the line" means here. "Hold the ford" names a place the parser doesn't know.
const PLACE_RE := " (hold|guard|defend|protect|watch)( at| by| near| over)? the ([a-z']+) "
const HERE_WORDS := ["line", "position", "ground", "spot", "area"]
const EVERYONE_BACK := ["fall back", "retreat", "recall", "come back", "come home", "go home"]


# "Run the village", "take twenty and run a mine here": a place and a purpose for a captain.
const MANDATE_RES := [
	["village", " (run|manage|look after|take charge of|take care of|be in charge of) (the |our )?(village|town|camp|settlement|home camp|base) "],
	["farming", " (run|manage|look after|take charge of|take care of) (the |our |a |some )?(farm|farms|farming) "],
	["industry", " (run|manage|take charge of|set up|look after) (the |our |a |an )?(mine|mines|mining|works|industry|mining outpost) "],
	["garrison", " (run|command|take charge of|set up|lead) (the |our |a )?(garrison|defence|defences|defense|defenses) "],
	["army", " (raise|lead|command|muster|take charge of) (an |the |our )?army "],
]


static func mandate_in(s: String) -> Dictionary:
	if s.contains(" then "):
		return {}
	for pair in MANDATE_RES:
		var found := RegEx.create_from_string(pair[1]).search(s)
		if found == null:
			continue
		# "Don't" only counts in front of the mandate: "run the village and don't build walls" is fine.
		if RegEx.create_from_string(" (don't|do not|never|stop) ").search(s.left(found.get_start() + 1)):
			continue
		if pair[0] == "army" and RegEx.create_from_string(" (attack|raid|charge|march|assault|destroy|follow) ").search(s):
			continue
		var where := "" if pair[0] == "village" else where_in(s)
		return _step("mandate", pair[0], 0, where, clampi(count_in(s), 0, 100))
	return {}


static func limits_in(s: String) -> Array:
	var out := []
	var kept := RegEx.create_from_string(" (?:keep|hold|leave|reserve) ([0-9]+|[a-z]+) (wood|stone|food|bronze ore|coal|iron ore|bronze|iron)( back| in reserve| aside| spare)? ")
	for found in kept.search_all(s):
		if found.get_string(3) == "" and not found.get_string().begins_with(" reserve "):
			continue
		var n: int = NUMBERS.get(found.get_string(1), 0)
		if found.get_string(1).is_valid_int():
			n = int(found.get_string(1))
		if n > 0:
			out.append(_step("reserve", found.get_string(2).replace(" ", "_"), mini(n, 10000)))
	var no := RegEx.create_from_string(" (?:don't|do not|never) (?:build|make|put up) (?:any |a |an |more |any more |the )?([a-z' ]+)").search(s)
	var yes := RegEx.create_from_string(" (?:you can build|you may build|allow) (?:a |an |more |the )?([a-z' ]+)").search(s)
	for pair in [[no, "forbid"], [yes, "allow"]]:
		if pair[0]:
			var what := find_in(" %s " % pair[0].get_string(1).get_slice(" and ", 0).strip_edges(), BUILD_WORDS)
			if what != "":
				out.append(_step(pair[1], what))
	if s.contains(" hold at all costs ") or s.contains(" stand your ground ") or s.contains(" to the last man "):
		out.append(_step("posture", "hold"))
	elif s.contains(" fall back if ") or s.contains(" retreat if "):
		out.append(_step("posture", "fall_back"))
	return out


static func _promotes(p: String) -> bool:
	return RegEx.create_from_string(PROMOTE_RE).search(p) != null


static func _unknown_place(p: String) -> bool:
	var found := RegEx.create_from_string(PLACE_RE).search(p)
	return found != null and not found.get_string(3) in HERE_WORDS and where_in(p) == ""


static func normalize(text: String) -> String:
	var s := text.to_lower().strip_edges()
	for ch in ["!", "?", ".", "\"", "(", ")", ":"]:
		s = s.replace(ch, " ")
	s = s.replace("’", "'").replace(",", " , ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	return " " + s.strip_edges() + " "


static func has_word(s: String, w: String) -> bool:
	return s.contains(" " + w + " ") or s.contains(" " + w + "s ") or s.contains(" " + w + "es ")


static func number_in(s: String) -> int:
	var words := s.strip_edges().split(" ", false)
	for w in words:
		if w.is_valid_int():
			return int(w)
	for k in ["a couple", "a few"]:
		if s.contains(" " + k + " "):
			return NUMBERS[k]
	for w in words:
		if NUMBERS.has(w) and not w in ["a", "an"]:
			return NUMBERS[w]
	return 0


static func count_in(s: String) -> int:
	# "send two scouts", "with 6 men", "take 3 people", "4 of you"
	var words := s.strip_edges().split(" ", false)
	for i in words.size():
		var w: String = words[i]
		var n := 0
		if w.is_valid_int():
			n = int(w)
		elif NUMBERS.has(w):
			n = NUMBERS[w]
		if n <= 0:
			continue
		var nxt: String = words[i + 1] if i + 1 < words.size() else ""
		var nxt2: String = words[i + 2] if i + 2 < words.size() else ""
		if nxt.trim_suffix("s") in ["scout", "men", "man", "people", "person", "villager", "worker", "soldier", "archer",
				"spearmen", "spearman", "rider", "hunter", "builder", "guard", "miner", "farmer", "you", "of", "more", "crew"] or nxt in ["men", "people"] or (nxt == "of" and nxt2 in ["you", "them"]):
			return n
		if i > 0 and words[i - 1] in ["send", "take", "with", "use", "get", "need", "arm"]:
			return n
	return 0


static func where_in(s: String, default_where: String = "") -> String:
	for k in ["north east", "south east", "south west", "north west"]:
		if s.contains(k):
			return DIRECTIONS[k]
	for k in DIRECTIONS:
		if has_word(s, k):
			return DIRECTIONS[k]
	if has_word(s, "enemy") or s.contains("their camp") or s.contains("their base") or s.contains("their village") or has_word(s, "them") or s.contains(" rook"):
		return "enemy"
	if s.contains(" the mark") or s.contains(" marked") or s.contains(" flag") or s.contains(" over there") or s.contains(" there "):
		return "marked"
	if s.contains(" home ") or s.contains(" camp ") or s.contains(" village") or s.contains(" base ") or s.contains("campfire") or s.contains(" town "):
		return "home"
	if s.contains(" here ") or s.contains(" me ") or s.contains(" this spot"):
		return "here"
	return default_where


static func find_in(s: String, table: Array) -> String:
	for pair in table:
		if s.contains(" " + pair[0] + " ") or s.contains(" " + pair[0] + "s ") or s.contains(" " + pair[0] + "es ") or s.contains(" " + pair[0] + "'"):
			return pair[1]
	return ""


static func _step(action: String, subject: String = "", amount: int = 0, where: String = "", count: int = 0) -> Dictionary:
	var generic := ""
	if subject.contains(":generic"):
		subject = subject.replace(":generic", "")
		generic = subject
	var st := {"action": action, "subject": subject, "count": count, "amount": amount, "where": where}
	if generic != "":
		st["generic"] = generic
	return st


## A name that would change what other orders mean can't be a place.
static func can_name_place(title: String) -> bool:
	var key := normalize(title).strip_edges()
	if key == "" or key.length() > 32 or key.split(" ", false).size() > 4:
		return false
	if key in VERBS or key in HERE_WORDS or key in DIRECTIONS or key in Defs.WHERE:
		return false
	if key in ["off", "mark", "the mark", "camp", "village", "base", "town", "campfire", "there", "me", "them", "everyone", "everybody"]:
		return false
	for table in [BUILD_WORDS, ITEM_WORDS, GATHER_WORDS]:
		for pair in table:
			if key in [pair[0], pair[0] + "s", pair[0] + "es"]:
				return false
	return true


## places holds the lower-case names this side knows. One may stand in for "the mark".
static func parse(text: String, places: Array = []) -> Dictionary:
	var s := normalize(text)
	var place := ""
	for key: String in places:
		if key.length() > place.length() and s.contains(normalize(key)):
			place = key
	if place == "" or s.contains(" the mark "):
		return _parse(text)
	var out := _parse(s.replace(normalize(place), " the mark "))
	for st in out["steps"]:
		if st["where"] == "marked" or (st["action"] == "gather" and st["where"] == ""):
			st["where"] = Defs.PLACE + place
	return out


static func _parse(text: String) -> Dictionary:
	var s := normalize(text)
	var out := {"ok": false, "steps": [], "all": false, "cancel": false, "confirm": false}
	var bare := s.strip_edges()
	if bare in ["go", "yes", "y", "ok", "okay", "do it", "go ahead", "proceed", "confirm", "sure", "yes go", "make it so", "aye"]:
		out["ok"] = true
		out["confirm"] = true
		return out
	if bare in ["no", "cancel", "never mind", "nevermind", "stop that", "forget it", "abort", "cancel that", "belay that"]:
		out["ok"] = true
		out["cancel"] = true
		return out
	if s.contains(" everyone ") or s.contains(" everybody ") or s.contains(" all of you ") or s.contains(" all hands "):
		out["all"] = true
	var settings := limits_in(s)
	var charge := mandate_in(s)
	if not charge.is_empty():
		settings.push_front(charge)
	if not settings.is_empty():
		out["steps"] = settings
		out["all"] = false
		out["ok"] = Defs.validate_steps(_clean(settings)) == ""
		return out
	# Split into sequential parts.
	var parts: Array[String] = []
	var tmp := s.replace(" and then ", " | ").replace(" , then ", " | ").replace(" then ", " | ").replace(" after that ", " | ").replace(" ; ", " | ")
	for chunk in tmp.split("|"):
		var piece: String = " " + chunk.strip_edges() + " "
		# "arm with spears and guard home": split on "and" when a new verb follows.
		var sub := piece.split(" and ")
		var acc := ""
		for k in sub.size():
			var bit: String = sub[k]
			if k > 0 and _starts_with_verb(" " + bit.strip_edges() + " "):
				parts.append(" " + acc.strip_edges() + " ")
				acc = bit
			else:
				acc = bit if k == 0 else acc + " and " + bit
		parts.append(" " + acc.strip_edges() + " ")
	var steps := []
	for p in parts:
		if p.strip_edges().replace(",", "") == "":
			continue
		var st = _parse_part(p, out)
		if st == null:
			return {"ok": false, "steps": [], "all": false, "cancel": false, "confirm": false}
		if st is Array:
			steps.append_array(st)
		else:
			steps.append(st)
	if steps.is_empty():
		return out
	out["steps"] = steps
	# A bare "fall back" is for everyone. As the end of a longer order it's only for that crew.
	if steps.size() == 1 and steps[0]["action"] == "recall" and count_in(s) == 0:
		for phrase in EVERYONE_BACK:
			if s.contains(" %s " % phrase):
				out["all"] = true
	out["ok"] = Defs.validate_steps(_clean(steps)) == ""
	return out


static func _clean(steps: Array) -> Array:
	var c := []
	for s in steps:
		c.append({"action": s["action"], "subject": s["subject"], "count": s["count"], "amount": s["amount"], "where": s["where"]})
	return c


const VERBS := ["gather", "collect", "chop", "cut", "harvest", "get", "fetch", "mine", "quarry", "pick", "hunt", "farm", "work",
	"build", "construct", "make", "craft", "forge", "put", "raise", "erect", "set", "arm", "equip", "grab", "take", "scout",
	"explore", "find", "look", "send", "attack", "charge", "raid", "assault", "kill", "guard", "defend", "protect", "hold",
	"stay", "follow", "come", "fall", "retreat", "go", "return", "recall", "mount", "ride", "man", "crew", "tame", "catch",
	"round", "bring", "smelt", "research", "study", "upgrade", "promote", "dismiss", "disband", "report", "status", "keep", "start", "stop",
	"continue", "resume", "finish"]


static func _starts_with_verb(p: String) -> bool:
	var words := p.strip_edges().split(" ", false)
	return not words.is_empty() and words[0] in VERBS


static func _parse_part(p: String, out: Dictionary):
	var count := count_in(p)
	# Back to work: undo "to arms" and return to the earlier tasks.
	if p.contains("back to work") or p.contains("return to work") or p.contains("resume work") or p.contains("resume your work") or p.contains("back to your tasks") or p.contains("back to your jobs") or p.contains("back to what you were doing"):
		out["all"] = out["all"] or count == 0
		return _step("resume_work")
	# Resuming comes first: "finish the farm" isn't farm work.
	var structure := find_in(p, BUILD_WORDS)
	if _resumes(p) and not _matches(p, FRESH):
		var kind := _site_kind(p, structure)
		var again := _step("resume", "" if kind in ["wall", "gate"] else kind, 0, "", count)
		again["match"] = kind
		return again
	if structure != "" and _matches(p, RESUME_LEAD + RESUME_START):
		return null
	# Recall / follow / hold.
	if p.contains("fall back") or p.contains("come back") or p.contains("go home") or p.contains("come home") or has_word(p, "retreat") or has_word(p, "recall") or p.contains("back to camp") or p.contains("return home") or p.contains("return to camp"):
		if p.contains(" don't ") or p.contains(" do not ") or p.contains(" never "):
			return null
		return _step("recall", "", 0, "home")
	if has_word(p, "follow") or p.contains("with me") or p.contains("come with") or p.contains("on me"):
		return _step("follow", "", 0, "", count)
	if p.contains("to arms") or has_word(p, "militia") or p.contains("grab weapons") or p.contains("take up arms") or p.contains("everyone fight"):
		out["all"] = out["all"] or count == 0
		return [_step("arm", "", 0, "", count), _step("guard", "", 0, where_in(p, "home"))]
	if p.contains("status") or p.contains("what are you doing") or p.contains("how are you") or bare_is(p, "report"):
		return _step("status")
	if _promotes(p):
		return _step("promote")
	if has_word(p, "dismiss") or has_word(p, "disband") or p.contains("dismissed"):
		return _step("dismiss")
	if has_word(p, "hold") or has_word(p, "stay") or p.contains("wait here") or p.contains("stand still") or p.contains("stand guard here"):
		if _unknown_place(p):
			return null
		# "Hold here", "stay there" and "hold them off" all mean the crew's own ground.
		var spot := ""
		var named := where_in(p)
		if p.contains(" the mark"):
			spot = "marked"
		elif named == "home" or named in DIRECTIONS.values():
			spot = named
		return _step("hold", "", 0, spot, count)
	# Horses and siege.
	if (has_word(p, "tame") or has_word(p, "catch") or p.contains("round up") or p.contains("bring in") or has_word(p, "capture")) and (has_word(p, "horse") or p.contains("herd")):
		return _step("tame", "horses", number_in(p) if not p.contains(" a horse") else 1, "", 0)
	if p.contains("mount up") or p.contains("take horses") or p.contains("take a horse") or p.contains("get on") or has_word(p, "ride") or has_word(p, "mount"):
		return _step("mount", "", 0, "", count)
	if (has_word(p, "man") or has_word(p, "crew")) and (has_word(p, "cannon") or has_word(p, "ram")):
		return _step("man", "cannon" if has_word(p, "cannon") else "ram")
	if has_word(p, "smelt") or (has_word(p, "make") and (has_word(p, "bronze") or has_word(p, "iron")) and find_in(p, ITEM_WORDS) == ""):
		return _step("smelt", "iron" if has_word(p, "iron") else "bronze", number_in(p), "", count)
	if has_word(p, "research") or has_word(p, "study") or p.contains("learn gunpowder"):
		if p.contains("archery") or p.contains("mounted") or p.contains("horse archer"):
			return _step("research", "mounted_archery")
		if has_word(p, "armory") or has_word(p, "armoury"):
			return _step("research", "armory_iron" if has_word(p, "iron") else "armory_bronze")
		if has_word(p, "bronze") or has_word(p, "iron"):
			return null
		return _step("research", "gunpowder") if p.contains("gunpowder") or p.contains("powder") else null
	if has_word(p, "upgrade") or p.contains("improve the"):
		if has_word(p, "armory") or has_word(p, "armoury"):
			return _step("upgrade", "armory")
		if has_word(p, "smelter") or has_word(p, "furnace"):
			return _step("upgrade", "smelter")
		return null
	# Scouting.
	if has_word(p, "scout") or has_word(p, "explore") or p.contains("find their") or p.contains("find the enemy") or p.contains("look around") or p.contains("spy"):
		return _step("scout", "", 0, where_in(p, ""), maxi(count, 0))
	# Fighting.
	if has_word(p, "attack") or has_word(p, "charge") or has_word(p, "raid") or has_word(p, "assault") or p.contains("kill them") or p.contains("destroy"):
		return _step("attack", "", 0, where_in(p, "enemy"), count)
	if has_word(p, "guard") or has_word(p, "defend") or has_word(p, "protect") or p.contains("watch the"):
		if _unknown_place(p):
			return null
		return _step("guard", "", 0, where_in(p, "here"), count)
	if has_word(p, "arm") or has_word(p, "equip") or p.contains("take up") or p.contains("grab"):
		var item := find_in(p, ITEM_WORDS)
		if item in ["arrows", "shot", "cannon", "ram"]:
			item = ""
		return _step("arm", item, 0, "", count)
	# Making things.
	var build := find_in(p, BUILD_WORDS)
	var item2 := find_in(p, ITEM_WORDS)
	var making := has_word(p, "make") or has_word(p, "craft") or has_word(p, "forge") or has_word(p, "cast") or has_word(p, "build") or has_word(p, "produce")
	if item2 == "ram" and build == "" and has_word(p, "build") and not (has_word(p, "make") or has_word(p, "craft") or has_word(p, "produce")):
		return _step("build", "ram", 0, "", count)    # built in the field by villagers; "make a ram" is the armory's
	if making and item2 != "" and (build == "" or p.find(item2.split("_")[0]) < p.find(build.split("_")[0])):
		return _step("craft", item2, number_in(p), "", count)
	if build != "" and (making or has_word(p, "construct") or p.contains("put up") or has_word(p, "raise") or has_word(p, "erect") or p.contains("set up") or p.strip_edges().begins_with("a ")):
		if build == "palisade_gate" and has_word(p, "stone"):
			build = "stone_gate"
		if build == "palisade" and has_word(p, "stone"):
			build = "stone_wall"
		var st := _step("build", build, 0, "", count)
		if _matches(p, EXISTING) and not _matches(p, FRESH):
			st["match"] = _site_kind(p, build)  # "build the hut" can mean the one already begun
		return st
	# Gathering.
	var res := find_in(p, GATHER_WORDS)
	var verbish := has_word(p, "gather") or has_word(p, "collect") or has_word(p, "chop") or has_word(p, "cut") or has_word(p, "harvest") or has_word(p, "get") or has_word(p, "fetch") or has_word(p, "mine") or has_word(p, "quarry") or has_word(p, "pick") or has_word(p, "hunt") or has_word(p, "farm") or p.contains("work the") or has_word(p, "keep") or p.contains("go for") or has_word(p, "bring")
	if res != "" and verbish:
		if has_word(p, "hunt"):
			res = "hunt"
		elif p.contains("work the farm") or (has_word(p, "farm") and res == "farm"):
			res = "farm"
		var amount := number_in(p) if count == 0 else 0
		var enough := p.find(" enough ")
		if enough >= 0:
			for pair in BUILD_WORDS:
				if p.contains(" " + pair[0] + " "):
					var cost: Dictionary = Defs.BUILDINGS[pair[1]]["cost"]
					var r: String = res.replace(":generic", "")
					if cost.has(r):
						amount = int(cost[r])
					break
		return _step("gather", res, amount, _work_place(p), count)
	if has_word(p, "hunt"):
		return _step("gather", "hunt", 0, "", count)
	if has_word(p, "farm") and not making:
		return _step("gather", "farm", 0, "", count)
	return null


static func bare_is(p: String, w: String) -> bool:
	return p.strip_edges() == w or p.strip_edges() == "give me a " + w or p.strip_edges() == w + " in"
