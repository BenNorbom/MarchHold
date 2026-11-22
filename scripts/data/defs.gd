extends RefCounted
## MarchHold content tables. This is the single source of truth: the command
## schema sent to Terra, the slash menus, the ledger, the tech tree and the AI
## rival's options are all generated from these tables.

const VERSION := "0.5.0"

# --- World -------------------------------------------------------------------
# size: metres per side, a multiple of 256 so every grid and terrain chunk divides evenly.
# min_start: the camps are never closer than this. margin: camps keep this far from the edge.
# settlements: the most camps the map holds. With three or more they stand on a ring, RING_SPACING or more apart.
# kit: how far each camp's own deposits and deer are. Kept under half of min_start,
# so they always lie on that camp's side of the map.
const MAP_SIZES := {
	"small": {"name": "Small", "size": 512, "min_start": 320.0, "margin": 100.0, "kit": Vector2(90, 150), "settlements": 2},
	"medium": {"name": "Medium", "size": 768, "min_start": 460.0, "margin": 125.0, "kit": Vector2(120, 200), "settlements": 4},
	"large": {"name": "Large", "size": 1024, "min_start": 620.0, "margin": 150.0, "kit": Vector2(120, 200), "settlements": 6},
	"huge": {"name": "Huge", "size": 1536, "min_start": 900.0, "margin": 150.0, "kit": Vector2(120, 200), "settlements": 8},
}
const MAP_DEFAULT := "medium"     # preselected for a new match
const MAP_REFERENCE := "large"    # what size_scale is relative to; also used by the tutorial
const RING_SPACING := 320.0       # closest two neighbours may start with three or more camps
const MAX_SETTLEMENTS := 8
const TICK := 0.1                 # simulation step in seconds (10 Hz)

# --- Commanders --------------------------------------------------------------
# By faction. Colours are picked to differ in lightness as well as hue.
const COMMANDERS := [
	{"name": "", "color": Color(0.05, 0.38, 1.0)},   # the player
	{"name": "Rook", "color": Color(1.0, 0.08, 0.05)},
	{"name": "Varga", "color": Color(0.82, 0.66, 0.14)},
	{"name": "Morrow", "color": Color(0.42, 0.20, 0.56)},
	{"name": "Corvin", "color": Color(0.11, 0.11, 0.12)},
	{"name": "Ashby", "color": Color(0.20, 0.46, 0.22)},
	{"name": "Sorrel", "color": Color(0.86, 0.40, 0.10)},
	{"name": "Kestrel", "color": Color(0.84, 0.84, 0.80)},
]

# --- Population --------------------------------------------------------------
const START_VILLAGERS := 6
const POP_HARD_CAP := 200
const MATURE_TIME := 90.0         # seconds for a child to grow up
const BIRTH_SECONDS_PER_ADULT := 300.0  # one birth per adult every 300 s -> 1 per 5 adults per minute
const RATION_ADULT := 0.025       # food per second
const RATION_CHILD := 0.0125
const WELL_FED_STOCK := 3.0       # food in store per person to count as well fed
const FED_STOCK := 1.0
const QUIVER := 16
const SHOT_LOAD := 8

const FOOD_STATES := ["Starving", "Hungry", "Fed", "Well fed"]
const FOOD_WORK := [0.5, 0.75, 1.0, 1.1]

const AGES := ["Wood", "Stone", "Bronze", "Iron", "Gunpowder"]
const AGE_HOW := [
	"You start here.",
	"Build a quarry next to a rock outcrop.",
	"Smelt your first bronze at a smelter (bronze ore + coal).",
	"Upgrade the smelter to an iron furnace.",
	"Build a university and research gunpowder.",
]

const RESOURCES := ["wood", "stone", "food", "bronze_ore", "coal", "iron_ore", "bronze", "iron"]
const RESOURCE_NAMES := {
	"wood": "wood", "stone": "stone", "food": "food", "bronze_ore": "bronze ore",
	"coal": "coal", "iron_ore": "iron ore", "bronze": "bronze", "iron": "iron",
}

# --- Buildings -----------------------------------------------------------------
# size: footprint in metres (x, z). work: worker-seconds to build.
# near: placement must be close to a resource node of this kind.
const BUILDINGS := {
	"campfire": {"name": "Campfire", "age": 0, "cost": {}, "work": 0, "hp": 500, "size": Vector2(6, 6),
		"housing": 8, "food_cap": 150, "dropoff": true, "sight": 35, "buildable": false,
		"desc": "Your home. Houses 8 and stores everything."},
	"hut": {"name": "Hut", "age": 0, "cost": {"wood": 50}, "work": 60, "hp": 160, "size": Vector2(5, 5),
		"housing": 6, "desc": "+6 housing."},
	"stockpile": {"name": "Stockpile", "age": 0, "cost": {"wood": 40}, "work": 30, "hp": 120, "size": Vector2(5, 5),
		"dropoff": true, "food_cap": 50, "desc": "Drop-off point near work. +50 food storage."},
	"farm": {"name": "Farm", "age": 0, "cost": {"wood": 65}, "work": 45, "hp": 80, "size": Vector2(14, 14),
		"workers": 2, "walkable": true, "desc": "Grain. One farm with a farmer feeds about five."},
	"armory": {"name": "Armory", "age": 0, "cost": {"wood": 125}, "work": 100, "hp": 320, "size": Vector2(8, 6),
		"workers": 3, "desc": "Makes all weapons, armor, arrows and cannons. Upgrades in place."},
	"palisade": {"name": "Palisade", "age": 0, "cost": {"wood": 4}, "work": 10, "hp": 120, "wall": true,
		"length": 4.0, "thick": 1.2, "height": 3.2, "desc": "Fast, weak wooden wall. Placed post to post."},
	"palisade_gate": {"name": "Palisade gate", "age": 0, "cost": {"wood": 15}, "work": 25, "hp": 160, "wall": true,
		"gate": true, "length": 4.0, "thick": 1.2, "height": 3.4, "desc": "Your people pass; enemies must break it."},
	"watch_post": {"name": "Watch post", "age": 0, "cost": {"wood": 65}, "work": 40, "hp": 120, "size": Vector2(3, 3),
		"sight": 75, "alarm": true, "desc": "Rings the alarm when enemies come into view."},
	"quarry": {"name": "Quarry", "age": 0, "cost": {"wood": 100}, "work": 80, "hp": 220, "size": Vector2(7, 7),
		"workers": 5, "near": "outcrop", "near_dist": 26.0, "opens_age": 1,
		"desc": "Steady stone from a rock outcrop. Opens the Stone age."},
	"stone_wall": {"name": "Stone wall", "age": 1, "cost": {"stone": 12}, "work": 35, "hp": 600, "wall": true,
		"length": 4.0, "thick": 2.0, "height": 4.5, "desc": "Strong wall built in stages. Placed post to post."},
	"stone_gate": {"name": "Stone gate", "age": 1, "cost": {"stone": 25, "wood": 10}, "work": 60, "hp": 520,
		"wall": true, "gate": true, "length": 4.0, "thick": 2.0, "height": 5.0, "desc": "A gate in a stone wall."},
	"tower": {"name": "Stone tower", "age": 1, "cost": {"stone": 125, "wood": 25}, "work": 120, "hp": 900,
		"size": Vector2(5, 5), "sight": 95, "alarm": true, "archers": 3,
		"desc": "Alarm tower with three sheltered archer posts. Approach the door and press E to climb."},
	"stable": {"name": "Stable", "age": 1, "cost": {"wood": 125, "stone": 25}, "work": 90, "hp": 260,
		"size": Vector2(10, 7), "horse_cap": 12, "desc": "Holds horses driven in from the wild and breeds them. Researches mounted archery."},
	"mine": {"name": "Mine", "age": 1, "cost": {"wood": 100, "stone": 50}, "work": 90, "hp": 300, "size": Vector2(6, 6),
		"workers": 5, "near": "deposit", "near_dist": 22.0, "desc": "Placed on a bronze ore, coal or iron ore deposit."},
	"smelter": {"name": "Smelter", "age": 1, "cost": {"stone": 125, "wood": 50}, "work": 100, "hp": 320,
		"size": Vector2(6, 6), "workers": 3, "desc": "Bronze ore + coal -> bronze. Upgrades to an iron furnace."},
	"university": {"name": "University", "age": 3, "cost": {"stone": 300, "wood": 200, "iron": 50}, "work": 200,
		"hp": 650, "size": Vector2(12, 9), "desc": "Researches gunpowder."},
}

# Upgrades happen in place. tier is the building's tier after the upgrade.
const UPGRADES := {
	"armory_bronze": {"name": "Bronze armory", "building": "armory", "from": 0, "tier": 1, "age": 2,
		"cost": {"wood": 75, "bronze": 65}, "work": 90, "desc": "Bronze spears, swords, shields, armor, pikes, lances, rams."},
	"armory_iron": {"name": "Iron armory", "building": "armory", "from": 1, "tier": 2, "age": 3,
		"cost": {"stone": 100, "iron": 75}, "work": 120, "desc": "Iron gear. With gunpowder: cannons and shot."},
	"iron_furnace": {"name": "Iron furnace", "building": "smelter", "from": 0, "tier": 1, "age": 2,
		"cost": {"stone": 150, "bronze": 50}, "work": 120, "opens_age": 3, "desc": "Smelts iron. Opens the Iron age."},
}

const RESEARCH := {
	"mounted_archery": {"name": "Mounted archery", "building": "stable", "age": 1, "cost": {"food": 60, "wood": 50},
		"time": 60.0, "desc": "Riders can shoot their bows from the saddle."},
	"gunpowder": {"name": "Gunpowder", "building": "university", "age": 3, "cost": {"food": 100, "coal": 40, "iron": 20},
		"time": 90.0, "opens_age": 4, "desc": "The iron armory can cast cannons and make shot."},
}

# --- Gear ----------------------------------------------------------------------
# tier: armory tier required (0 wood, 1 bronze, 2 iron). batch: items per craft.
# block_*: share a carried shield stops. up_*: share it stops when raised, from the front.
const SHIELD_ARC := 0.34          # cosine of the half angle a raised shield covers (70 degrees)
const ITEMS := {
	"wood_spear": {"name": "wooden spear", "plural": "wooden spears", "slot": "weapon", "tier": 0, "cost": {"wood": 40},
		"batch": 4, "time": 12.0, "dmg": 9.0, "reach": 2.4, "rate": 1.2, "vs_mounted": 2.0},
	"wood_shield": {"name": "wooden shield", "plural": "wooden shields", "slot": "shield", "tier": 0, "cost": {"wood": 50},
		"batch": 4, "time": 12.0, "block_arrow": 0.4, "block_melee": 0.15, "up_arrow": 0.75, "up_melee": 0.5, "slow": 0.05},
	"bow": {"name": "bow", "plural": "bows", "slot": "bow", "tier": 0, "cost": {"wood": 50}, "batch": 4, "time": 14.0},
	"arrows": {"name": "arrow", "plural": "arrows", "slot": "ammo", "tier": 0, "cost": {"wood": 4, "stone": 2},
		"batch": 16, "time": 10.0, "tier_cost": [{"wood": 4, "stone": 2}, {"wood": 4, "bronze": 1}, {"wood": 4, "iron": 1}]},
	"bronze_spear": {"name": "bronze spear", "plural": "bronze spears", "slot": "weapon", "tier": 1, "cost": {"wood": 20, "bronze": 15},
		"batch": 4, "time": 12.0, "dmg": 12.0, "reach": 2.4, "rate": 1.2, "vs_mounted": 2.0},
	"bronze_sword": {"name": "bronze sword", "plural": "bronze swords", "slot": "weapon", "tier": 1, "cost": {"bronze": 25},
		"batch": 4, "time": 14.0, "dmg": 15.0, "reach": 1.7, "rate": 1.0},
	"bronze_shield": {"name": "bronze shield", "plural": "bronze shields", "slot": "shield", "tier": 1, "cost": {"wood": 20, "bronze": 15},
		"batch": 4, "time": 12.0, "block_arrow": 0.55, "block_melee": 0.25, "up_arrow": 0.85, "up_melee": 0.65, "slow": 0.06},
	"bronze_armor": {"name": "bronze armor", "plural": "sets of bronze armor", "slot": "armor", "tier": 1, "cost": {"bronze": 40},
		"batch": 4, "time": 16.0, "armor": 0.25, "slow": 0.08},
	"bronze_pike": {"name": "bronze pike", "plural": "bronze pikes", "slot": "weapon", "tier": 1, "cost": {"wood": 30, "bronze": 15},
		"batch": 4, "time": 12.0, "dmg": 11.0, "reach": 4.0, "rate": 1.4, "vs_mounted": 3.0, "close": 0.7},
	"bronze_lance": {"name": "bronze lance", "plural": "bronze lances", "slot": "weapon", "tier": 1, "cost": {"wood": 30, "bronze": 15},
		"batch": 4, "time": 12.0, "dmg": 14.0, "reach": 3.0, "rate": 1.3, "charge": 2.0},
	"ram": {"name": "battering ram", "plural": "battering rams", "slot": "siege", "tier": 1, "cost": {"wood": 40, "bronze": 5},
		"batch": 1, "time": 25.0, "crew": 4},
	"iron_spear": {"name": "iron spear", "plural": "iron spears", "slot": "weapon", "tier": 2, "cost": {"wood": 20, "iron": 15},
		"batch": 4, "time": 12.0, "dmg": 16.0, "reach": 2.4, "rate": 1.2, "vs_mounted": 2.0},
	"iron_sword": {"name": "iron sword", "plural": "iron swords", "slot": "weapon", "tier": 2, "cost": {"iron": 25},
		"batch": 4, "time": 14.0, "dmg": 20.0, "reach": 1.7, "rate": 1.0},
	"iron_shield": {"name": "iron shield", "plural": "iron shields", "slot": "shield", "tier": 2, "cost": {"wood": 20, "iron": 15},
		"batch": 4, "time": 12.0, "block_arrow": 0.65, "block_melee": 0.3, "up_arrow": 0.9, "up_melee": 0.75, "slow": 0.07},
	"iron_armor": {"name": "iron armor", "plural": "sets of iron armor", "slot": "armor", "tier": 2, "cost": {"iron": 40},
		"batch": 4, "time": 16.0, "armor": 0.35, "slow": 0.1},
	"iron_pike": {"name": "iron pike", "plural": "iron pikes", "slot": "weapon", "tier": 2, "cost": {"wood": 30, "iron": 15},
		"batch": 4, "time": 12.0, "dmg": 15.0, "reach": 4.0, "rate": 1.4, "vs_mounted": 3.0, "close": 0.7},
	"iron_lance": {"name": "iron lance", "plural": "iron lances", "slot": "weapon", "tier": 2, "cost": {"wood": 30, "iron": 15},
		"batch": 4, "time": 12.0, "dmg": 18.0, "reach": 3.0, "rate": 1.3, "charge": 2.0},
	"cannon": {"name": "cannon", "plural": "cannons", "slot": "siege", "tier": 2, "research": "gunpowder",
		"cost": {"iron": 12, "wood": 20, "coal": 4}, "batch": 1, "time": 30.0, "crew": 3},
	"shot": {"name": "cannon shot", "plural": "cannon shot", "slot": "shot", "tier": 2, "research": "gunpowder",
		"cost": {"iron": 2, "coal": 2}, "batch": 8, "time": 10.0},
}

# How each kind of weapon is fought with.
# stand: centre-to-centre distance to fight at. wind: wind-up before an AI blow lands.
# quick: the same for the commander. arc: half angle of the commander's blow, radians.
# places: how many can fight one target at once. cleave: how many the commander's blow hits.
const MELEE := {
	"fists": {"stand": 0.9, "wind": 0.3, "quick": 0.15, "arc": 0.6, "places": 6},
	"sword": {"stand": 1.2, "wind": 0.3, "quick": 0.16, "arc": 1.0, "places": 6, "cleave": 2},
	"spear": {"stand": 1.9, "wind": 0.3, "quick": 0.2, "arc": 0.4, "places": 8},
	"pike": {"stand": 3.0, "wind": 0.3, "quick": 0.3, "arc": 0.35, "places": 12},
	"lance": {"stand": 2.1, "wind": 0.3, "quick": 0.24, "arc": 0.5, "places": 6},
}
const COMMANDER_SWING := 0.8      # share of the weapon's rate
const CLEAVE_SHARE := 0.6
const PARRY_STAGGER := 1.1
const BLOCK_KEEP := {"weapon": 0.35, "bare": 0.6}   # damage that gets through a block
const BLOCK_STAMINA := 0.08

const FISTS := {"dmg": 3.0, "reach": 1.5, "rate": 1.0}
const ARROW_DMG := [8.0, 11.0, 14.0]
const BOW_RANGE := 55.0
const TOWER_DECK_HEIGHT := 9.6
const TOWER_DECK_RADIUS := 2.55
const TOWER_PARAPET_RADIUS := 2.3
const TOWER_PARAPET_HEIGHT := 1.0
const TOWER_PARAPET_WIDTH := 1.25
const TOWER_PARAPET_THICKNESS := 0.32
const TOWER_MERLON_HEIGHT := 0.5
const TOWER_PARAPET_SIDES := 12
const TOWER_DOOR_REACH := 1.4

const CANNON := {"range": 170.0, "reload": 15.0, "dmg_building": 230.0, "dmg_unit": 70.0, "splash": 3.5,
	"scatter": 0.03, "speed_hand": 1.2, "speed_team": 3.6, "hp": 160.0}
const RAM := {"dmg_building": 75.0, "reload": 3.0, "speed": 1.6, "speed_team": 2.6, "hp": 320.0}

const VILLAGER := {"hp": 50.0, "speed": 4.0, "sight": 32.0}
const CHILD := {"hp": 20.0, "speed": 3.2}
const COMMANDER := {"hp": 200.0, "speed": 5.0, "sight": 55.0}
const MOUNTED := {"hp_bonus": 60.0, "speed": 8.5}
const SCOUT_SIGHT := 62.0
## How far an armed person sees. Enough to recognise a camp they are marching on.
const SOLDIER_SIGHT := 34.0

# --- Work ------------------------------------------------------------------------
# node: a resource node on the map. building: work happens at a building.
const GATHER_SPEED := 0.75
const GATHER := {
	"wood": {"name": "wood", "resource": "wood", "node": "tree", "rate": 1.0, "carry": 5},
	"stone": {"name": "stone", "resource": "stone", "node": "rock", "building": "quarry", "rate": 0.6, "carry": 4, "building_rate": 0.5},
	"berries": {"name": "berries", "resource": "food", "node": "berry", "rate": 1.2, "carry": 5},
	"hunt": {"name": "hunting", "resource": "food", "rate": 1.5, "carry": 5},
	"farm": {"name": "farming", "resource": "food", "building": "farm", "building_rate": 0.14},
	"bronze_ore": {"name": "bronze ore", "resource": "bronze_ore", "building": "mine", "building_rate": 0.4},
	"coal": {"name": "coal", "resource": "coal", "building": "mine", "building_rate": 0.45},
	"iron_ore": {"name": "iron ore", "resource": "iron_ore", "building": "mine", "building_rate": 0.35},
}

const SMELT := {
	"bronze": {"name": "bronze", "inputs": {"bronze_ore": 1, "coal": 1}, "time": 3.0, "tier": 0, "opens_age": 2},
	"iron": {"name": "iron", "inputs": {"iron_ore": 1, "coal": 1}, "time": 4.0, "tier": 1},
}

const DEPOSITS := ["bronze_ore", "coal", "iron_ore"]

# --- Hotkeys ---------------------------------------------------------------------
# /b or /c, then a page (b basic, v advanced), then one key. Shown in this order.
# Every structure, upgrade, research and item has exactly one key.
const HOTKEY_PAGES := ["b", "v"]
const HOTKEYS := {
	"b": {
		"b": {"name": "Basic structures", "keys": {
			"h": "build:hut", "f": "build:farm", "s": "build:stockpile", "a": "build:armory",
			"p": "build:palisade", "g": "build:palisade_gate", "w": "build:watch_post", "q": "build:quarry"}},
		"v": {"name": "Advanced structures", "keys": {
			"w": "build:stone_wall", "g": "build:stone_gate", "t": "build:tower", "h": "build:stable", "m": "build:mine",
			"s": "build:smelter", "u": "build:university",
			"a": "upgrade:armory", "f": "upgrade:smelter", "r": "research:gunpowder"}},
	},
	"c": {
		"b": {"name": "Basic weapons", "keys": {
			"w": "craft:wood_spear", "d": "craft:wood_shield", "b": "craft:bow", "a": "craft:arrows",
			"r": "craft:ram",
			"e": "craft:bronze_spear", "s": "craft:bronze_sword", "h": "craft:bronze_shield", "m": "craft:bronze_armor",
			"p": "craft:bronze_pike", "l": "craft:bronze_lance"}},
		"v": {"name": "Advanced weapons", "keys": {
			"e": "craft:iron_spear", "s": "craft:iron_sword", "h": "craft:iron_shield", "m": "craft:iron_armor",
			"p": "craft:iron_pike", "l": "craft:iron_lance",
			"c": "craft:cannon", "t": "craft:shot"}},
	},
}

# --- Orders ----------------------------------------------------------------------
const ACTIONS := ["gather", "build", "resume", "upgrade", "craft", "arm", "mount", "man", "smelt", "research", "tame",
	"scout", "guard", "attack", "follow", "hold", "recall", "promote", "mandate", "reserve", "forbid", "allow", "posture", "dismiss", "status", "resume_work"]
## Orders that pull people off their work. The sim remembers the work they leave so "back to work" can restore it.
const MILITARY_ACTIONS := ["arm", "mount", "man", "scout", "guard", "attack", "follow", "hold", "recall"]
const WORK_ACTIONS := ["gather", "build", "upgrade", "craft", "smelt", "research", "tame"]
# Settings for a captain. They take effect at once and can only be combined with each other.
const SETTINGS := ["mandate", "reserve", "forbid", "allow", "posture"]
const WHERE := ["", "here", "marked", "home", "enemy", "north", "northeast", "east", "southeast",
	"south", "southwest", "west", "northwest"]
const PLACE := "place:"       # a where may also be PLACE + a place the player named
const ONGOING := ["guard", "attack", "follow", "hold"]
const AMOUNT_ACTIONS := ["gather", "craft", "smelt", "tame", "reserve"]
const MAX_STEPS := 8

# What a captain can be put in charge of. size: people when the order gives no number (0 = everyone free).
# builds: what they may site by themselves. The village reaches the camp's outcrop (95-140 m out),
# and works run from home (within HOME_GROUND) reach the camp's deposits (90-200 m out).
const HOME_GROUND := 60.0
const MANDATES := {
	"village": {"name": "village", "does": "run the village", "radius": 152.0, "size": 0,
		"builds": ["hut", "farm", "stockpile", "quarry", "armory", "stable",
			"palisade", "palisade_gate", "stone_wall", "stone_gate", "watch_post", "tower"]},
	"farming": {"name": "farms", "does": "run the farms", "radius": 70.0, "size": 8,
		"builds": ["farm", "stockpile", "hut", "watch_post"]},
	"industry": {"name": "works", "does": "run the mines and works", "radius": 90.0, "home_radius": 210.0, "size": 10,
		"builds": ["mine", "quarry", "smelter", "armory", "university", "stockpile", "watch_post"]},
	"garrison": {"name": "garrison", "does": "hold a garrison", "radius": 45.0, "size": 8,
		"builds": ["armory", "palisade", "palisade_gate", "stone_wall", "stone_gate", "tower", "watch_post"]},
	"army": {"name": "army", "does": "raise an army", "radius": 35.0, "size": 10, "builds": []},
}

const NAMES := ["Hal", "Wren", "Ana", "Bram", "Cora", "Dunstan", "Edda", "Finn", "Gil", "Hilda", "Ivo", "Jory",
	"Kit", "Lena", "Mabel", "Ned", "Osric", "Pell", "Quinn", "Rolf", "Sigrid", "Tam", "Una", "Vance", "Walt",
	"Yara", "Alda", "Bede", "Cyne", "Dora", "Elric", "Freya", "Godric", "Hugh", "Ida", "Joan", "Kenric", "Leof",
	"Maud", "Nell", "Odo", "Piers", "Rowan", "Sabine", "Tilda", "Ulf", "Wynn", "Aldo", "Beth", "Col", "Dag",
	"Esme", "Faye", "Garth", "Hob", "Isolde", "Jago", "Kara", "Lud", "Mags", "Nils", "Orla", "Pip", "Ralf",
	"Saer", "Tove", "Viv", "Wat", "Agnes", "Brun", "Cuth", "Dwyn", "Elsa", "Fritha", "Gunn", "Herne", "Ilse",
	"Jem", "Kell", "Lark", "Mott", "Nan", "Oswin", "Perrin", "Roan", "Sten", "Teg", "Ulric", "Vera", "Wulf"]

# Told apart by byname once the first names run out: "Hal Miller", never "Hal 2".
const BYNAMES := ["Miller", "Reed", "Ash", "Fletcher", "Thatcher", "Cooper", "Wright", "Baker", "Tanner", "Shepherd",
	"Carter", "Mason", "Fisher", "Brewer", "Weaver", "Potter", "Barley", "Thorn", "Hollis", "Birch", "Fenn", "Moss",
	"Dyer", "Sawyer", "Hayward", "Crofter", "Alder", "Rush", "Flint", "Brook"]


## The map to play on: the one asked for, or the smallest bigger one that holds that many camps.
static func map_for(settlements: int, wanted: String) -> String:
	var id := wanted if MAP_SIZES.has(wanted) else MAP_DEFAULT
	if int(MAP_SIZES[id]["settlements"]) >= settlements:
		return id
	for other in MAP_SIZES:
		if int(MAP_SIZES[other]["settlements"]) >= settlements:
			return other
	return id


static func building_name(id: String) -> String:
	if BUILDINGS.has(id):
		return BUILDINGS[id]["name"]
	if UPGRADES.has(id):
		return UPGRADES[id]["name"]
	return id.capitalize()


static func item_name(id: String, count: int = 1) -> String:
	if not ITEMS.has(id):
		return id.replace("_", " ")
	return ITEMS[id]["name"] if count == 1 else ITEMS[id]["plural"]


static func item_cost(id: String, armory_tier: int) -> Dictionary:
	var it: Dictionary = ITEMS[id]
	var cost: Dictionary = it["cost"]
	if it.has("tier_cost"):
		cost = it["tier_cost"][clampi(armory_tier, 0, 2)]
	if it.get("slot", "") == "siege":
		return cost  # rams and cannons keep their listed costs
	return _even_cost(cost)


## Weapons, shields and armor: a fractional amount rounds to the nearest even
## number (12.5 -> 12). Whole numbers are left exactly as written.
static func _even_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for r in cost:
		var v := float(cost[r])
		out[r] = cost[r] if is_equal_approx(v, roundf(v)) else int(roundf(v / 2.0)) * 2
	return out


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array[String] = []
	for r in cost:
		parts.append("%d %s" % [int(cost[r]), RESOURCE_NAMES.get(r, r)])
	return ", ".join(parts)


## Every building that can be placed with /b or a build step.
static func buildable_ids() -> Array[String]:
	var out: Array[String] = []
	for id in BUILDINGS:
		if BUILDINGS[id].get("buildable", true):
			out.append(id)
	return out


static func subjects_for(action: String) -> Array[String]:
	var out: Array[String] = []
	match action:
		"gather":
			for k in GATHER:
				out.append(k)
		"build":
			out = buildable_ids()
		"resume":
			out.append("")
			out.append_array(buildable_ids())
		"upgrade":
			out = ["armory", "smelter"]
		"craft":
			for k in ITEMS:
				out.append(k)
		"arm":
			out.append("")
			for k in ITEMS:
				if ITEMS[k]["slot"] in ["weapon", "shield", "armor", "bow"]:
					out.append(k)
		"man":
			out = ["cannon", "ram"]
		"smelt":
			for k in SMELT:
				out.append(k)
		"research":
			for k in RESEARCH:
				out.append(k)
		"tame":
			out = ["horses", ""]
		"mandate":
			for k in MANDATES:
				out.append(k)
		"reserve":
			for r in RESOURCES:
				out.append(r)
		"forbid", "allow":
			out = buildable_ids()
		"posture":
			out = ["hold", "fall_back"]
		_:
			out = [""]
	return out


static func all_subjects() -> Array[String]:
	var seen := {}
	var out: Array[String] = []
	for a in ACTIONS:
		for s in subjects_for(a):
			if not seen.has(s):
				seen[s] = true
				out.append(s)
	return out


## A step is "ongoing" when it never finishes by itself, so it must be last.
static func step_is_ongoing(step: Dictionary) -> bool:
	var a: String = step.get("action", "")
	if a in ONGOING:
		return true
	if a in ["gather", "smelt", "tame"] and int(step.get("amount", 0)) <= 0:
		return true
	return false


## Structural validation, ported from the prototype's validPlan().
static func validate_steps(steps) -> String:
	if not (steps is Array) or steps.is_empty():
		return "The plan has no steps."
	if steps.size() > MAX_STEPS:
		return "A plan can have at most %d steps." % MAX_STEPS
	for i in steps.size():
		var s = steps[i]
		if not (s is Dictionary):
			return "Step %d is malformed." % (i + 1)
		var a: String = str(s.get("action", ""))
		if not a in ACTIONS:
			return "Step %d has an unknown action '%s'." % [i + 1, a]
		if a == "resume_work" and steps.size() > 1:
			return "Going back to work can't be combined with other steps."
		var subj: String = str(s.get("subject", ""))
		if not subj in subjects_for(a):
			return "Step %d: '%s' can't be used with %s." % [i + 1, subj, a]
		var count = s.get("count", 0)
		var amount = s.get("amount", 0)
		if not (count is int or count is float) or int(count) < 0 or int(count) > 100:
			return "Step %d has a bad count." % (i + 1)
		if not (amount is int or amount is float) or int(amount) < 0 or int(amount) > 10000:
			return "Step %d has a bad amount." % (i + 1)
		if int(amount) > 0 and not a in AMOUNT_ACTIONS:
			return "Step %d: amounts only apply to gathering, crafting, smelting and taming." % (i + 1)
		var w: String = str(s.get("where", ""))
		if not w in WHERE and not (w.begins_with(PLACE) and w.length() > PLACE.length()):
			return "Step %d has an unknown place '%s'." % [i + 1, w]
		if a == "mandate" and i > 0:
			return "A mandate comes first."
		if i > 0 and (a in SETTINGS) != (str(steps[0].get("action", "")) in SETTINGS):
			return "A captain's mandate and limits are an order by themselves."
		if i < steps.size() - 1 and step_is_ongoing(s):
			return "Step %d (%s) never finishes, so it has to be the last step." % [i + 1, describe_step(s)]
	return ""


static func describe_step(s: Dictionary) -> String:
	var a: String = s.get("action", "")
	var subj: String = s.get("subject", "")
	var amount := int(s.get("amount", 0))
	var count := int(s.get("count", 0))
	var where: String = s.get("where", "")
	if where.begins_with(PLACE):
		where = where.substr(PLACE.length()).capitalize()
	var txt := ""
	match a:
		"gather":
			var g: String = GATHER.get(subj, {}).get("name", subj)
			txt = ("gather %d %s" % [amount, g]) if amount > 0 else ("keep gathering %s" % g if subj != "hunt" and subj != "farm" else "keep " + g)
		"build":
			txt = "build a " + building_name(subj).to_lower()
		"resume":
			txt = ("continue building the " + building_name(subj).to_lower()) if subj != "" else "continue construction"
		"upgrade":
			txt = "upgrade the " + subj
		"craft":
			txt = ("make %d %s" % [amount, item_name(subj, amount)]) if amount > 0 else ("make a batch of " + item_name(subj, 2))
		"arm":
			txt = "arm with " + item_name(subj, 2) if subj != "" else "arm with the best gear in the armory"
		"mount":
			txt = "take horses from the stable"
		"man":
			txt = "crew a " + item_name(subj)
		"smelt":
			txt = ("smelt %d %s" % [amount, subj]) if amount > 0 else ("keep smelting " + subj)
		"research":
			txt = "research " + subj
		"tame":
			txt = ("bring in %d wild horses" % amount) if amount > 0 else "keep bringing in wild horses"
		"scout":
			txt = "scout" + ((" " + where) if where != "" and where != "here" else "") + " and report back"
		"guard":
			txt = "guard " + (where if where != "" else "here")
		"attack":
			txt = "attack" + ((" " + ("the enemy camp" if where == "enemy" else where)) if where != "" else " the enemy camp")
		"follow":
			txt = "follow you"
		"hold":
			txt = "hold position"
		"recall":
			txt = "come home"
		"promote":
			txt = "become a captain"
		"mandate":
			txt = "take charge: " + MANDATES.get(subj, {}).get("does", subj)
		"reserve":
			txt = ("keep %d %s back" % [amount, RESOURCE_NAMES.get(subj, subj)]) if amount > 0 else "spend %s freely" % RESOURCE_NAMES.get(subj, subj)
		"forbid":
			txt = "build no " + building_name(subj).to_lower()
		"allow":
			txt = "build a %s when needed" % building_name(subj).to_lower()
		"posture":
			txt = "hold at all costs" if subj == "hold" else "fall back if outnumbered"
		"dismiss":
			txt = "disband the crew"
		"status":
			txt = "report status"
		"resume_work":
			txt = "go back to work"
		_:
			txt = a
	if count > 0:
		txt += " (%d people)" % count
	return txt


static func weapon_family(weapon: String) -> String:
	for family in ["sword", "spear", "pike", "lance"]:
		if weapon.ends_with(family):
			return family
	return "fists"
