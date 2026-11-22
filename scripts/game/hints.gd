extends RefCounted
## One-line tips for the first few matches, shown once each.

const Defs = preload("res://scripts/data/defs.gd")

const AGE_TIPS := [
	"",
	"Stone age: stone walls, towers, stables and mines are open. Try /b v for advanced structures.",
	"Bronze age: upgrade the armory to bronze for swords, pikes, lances and armor. Then upgrade the smelter to an iron furnace.",
	"Iron age: upgrade the armory to iron, and build a university to research gunpowder.",
	"Gunpowder: the iron armory can now cast cannons and shot. 'man the cannon' then 'attack their camp'.",
]

var g
var shown := {}
var acc := 0.0
var on := true


func setup(game) -> void:
	g = game
	on = bool(Settings.get_val("hints", true)) and int(Settings.get_val("matches_played", 0)) < 3 and not game.opts.get("tutorial", false)


func _hint(key: String, text: String) -> void:
	if not on or shown.has(key):
		return
	shown[key] = true
	g.hud.log_line("Tip: " + text, "hint")


func on_message(msg: Dictionary) -> void:
	if msg["kind"] == "age":
		var f = g.m.fac(0)
		if f.age < AGE_TIPS.size():
			_hint("age%d" % f.age, AGE_TIPS[f.age])
	elif msg["kind"] == "alarm":
		_hint("alarm", "'to arms' arms everyone and guards home; 'fall back' brings everyone back to camp.")
	elif msg["kind"] == "report":
		_hint("report", "Reports are kept under /s, and the field map (M) shows what your scouts saw and when.")


func tick(dt: float) -> void:
	if not on:
		return
	acc += dt
	if acc < 2.0:
		return
	acc = 0.0
	var m = g.m
	var f = m.fac(0)
	var t: float = m.t
	if t > 25.0:
		_hint("talk", "Look at a villager and press Enter to give orders. With nobody addressed, idle people take the job.")
	if float(f.stock["wood"]) >= 20.0 and not m.has_building(0, "hut"):
		_hint("hut", "You have 20 wood: build a hut with /b b h to make room for more people.")
	if f.pop >= f.housing and f.food_state == 3:
		_hint("housing", "Housing is full, so no more births. Build huts (/b b h).")
	if f.food_state <= 1 and t > 60.0:
		_hint("food", "Food is short. Say 'pick berries', build a farm (/b b f), or say 'hunt'.")
	if f.pop * Defs.WELL_FED_STOCK > f.food_cap:
		_hint("storage", "Your stores are too small to keep this many people well fed. Each stockpile (/b b s) holds 50 more food.")
	if m.has_building(0, "armory"):
		_hint("armory", "The armory is up. /c makes gear (/c b w for spears); 'arm 5 with spears' equips people. Stand by it and press E to arm yourself.")
	if t > 170.0 and f.reports.is_empty():
		_hint("scout", "You don't know where Rook is. Say 'send a scout' — the report comes when the scout returns.")
	if t > 300.0 and f.age == 0:
		_hint("quarry", "A quarry next to a big rock outcrop opens the Stone age.")
	if t > 240.0 and not m.has_building(0, "farm"):
		_hint("farm", "Berries run out. Farms feed about five people each for good.")
