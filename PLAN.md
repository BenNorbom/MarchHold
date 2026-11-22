# MarchHold — Game Plan

MarchHold is a realistic medieval strategy game played entirely in first person. You are a commander on foot or horseback. You walk among your people, pick them out by looking and clicking, and talk to them through a chat line. An OpenAI-powered interpreter ("Terra") turns what you type into concrete orders, and the simulation validates and executes them. Slash commands like `/b` give instant menus for the common things. You start with nothing and grow a settlement from a campfire to a gunpowder army of up to 200.

First target: **1v1, player vs AI, single machine.** Later: **online head-to-head, up to 8 players.**

This plan succeeds the prototype at `Documents/MCRTS` (Electron + Three.js voxel game). The prototype proved the command loop; MarchHold is the production game.

**Status (v0.1.0):** first playable build on Godot 4, covering phases 0–10 of the roadmap in a first form. See §13.

The content here is deliberately lean. More buildings, weapons, and abilities can be added once the core is fun.

---

## 1. Design pillars

1. **Strictly first person.** No top-down camera, no overhead map view, no minimap. What you know comes from what you see, what your scouts report, and what you write down.
2. **Command by conversation.** Type to a villager, a captain, or all crews. Terra plans; the game validates; villagers execute. Slash commands cover the frequent, simple actions.
3. **Information is earned.** Scouts must go out, see, and come back. A rush is deadly if unscouted and stoppable if scouted.
4. **Growth is biological.** Villagers are born, not trained. They need food and housing to reproduce. Every soldier is a worker you took out of the economy.
5. **Short to medium matches.** 5–45 minutes. Nothing takes long to build.
6. **Simple to learn, deep to master.** Few resources, few buildings, clear counters. A guided intro teaches the game.
7. **Realism over stylization.** Physically based lighting and materials. Away from the Minecraft look entirely.

---

## 2. Engine and licensing

**Godot 4** (4.7.2).

- **Why not UE5 (the original choice):** UE5 couldn't be set up on the development PC. It needs an Epic login and 40–60 GB of disk (about 26 GB was free), and Iris Xe integrated graphics are too slow for Lumen and Nanite work. Godot was chosen instead.
- **Cost:** Free and open source (MIT). No royalties, ever. The engine's licence notice ships with the game (`LICENSES/`).
- **Why it works for this game:** physically based rendering, a physical sky and fog, SSAO/SSIL/SDFGI on higher settings, MultiMesh instancing for forests and crowds, a headless mode for tests and AI training, and high-level multiplayer (ENet) with dedicated-server exports for online play later.
- **How we work in it:** gameplay and content are **GDScript** and plain-text data tables (`scripts/data/defs.gd`). Scenes and shaders are text, so everything is reviewable and diffable. Models, trees, characters and sounds are generated procedurally at runtime.
- **Source control:** plain Git. The only binary assets are about 35 MB of CC0 textures and two fonts, so Git LFS isn't needed yet. Repo: <https://github.com/BenNorbom/MarchHold>.

---

## 3. Architecture

```text
┌─────────────────────── Godot client ───────────────────────┐
│ First-person commander · minimal HUD · chat line            │
│ Slash commands (/b, /c, ...) handled locally, no model call │
└──────────────┬──────────────────────────────────────────────┘
               │ free-text message + addressed crew + knowledge snapshot
       ┌───────▼─────────┐    structured plan    ┌────────────┐
       │ Command service │◄─────────────────────►│ OpenAI API │
       │ schema generated│                       └────────────┘
       │ from unlocked   │
       │ tech + roster   │
       └───────┬─────────┘
               │ validated commands only
┌──────────────▼──────── Authoritative game server ──────────┐
│ Simulation: population, food, economy, tech tree, crews,    │
│ combat, vision & scouting, AI rival                         │
│ Single player = local listen server. Online = same code on  │
│ a dedicated server.                                         │
└─────────────────────────────────────────────────────────────┘
```

Rules that hold from day one:

1. **Server-authoritative even in single player.** The 1v1 vs AI runs on a local server so online play is adding clients, not rewriting the game.
2. **The model never mutates state.** Terra only proposes. The server checks every step against unlocked tech, stockpiles, crew availability, and placement rules.
3. **One source of truth for content.** Items, buildings, recipes, prerequisites, build times, unit stats live in data tables. The command schema sent to the model, the slash-command menus, the in-game ledger, and the AI rival's options are all generated from them.
4. **Slash commands and Terra produce the same commands.** `/b b h` → place it is the same validated "build hut here" command Terra would emit.
5. **The AI rival uses the same command interface as the player.** No cheating paths; one validation layer to test.
6. **Headless simulation mode.** The sim runs without rendering for automated tests, balance runs, and AI training (as in the prototype).
7. **Scale target:** 200 population per side (400 in 1v1, up to 1,600 in 8-player). People and animals are drawn with a few MultiMeshes and animated on the GPU (vertex-shader limbs), so hundreds of figures cost a handful of draw calls.

---

## 4. The player's role (strictly first person)

- **You are the commander.** Walk, sprint, ride (once you have horses), fight with what the armory gives you. Your death ends the match; killing the enemy commander wins.
- **Minimal HUD:** compass, health/stamina, held item, quiver count, and the chat log. Menus opened by slash commands overlay the first-person view; the camera never leaves the commander's eyes.
- **Diegetic tools:**
  - **Ledger** (`/l` or hotkey): stockpiles, population, food status, housing, crews and their current plans.
  - **Field map** (`/m` or hotkey, held parchment): starts nearly blank. Fills in only with terrain you have personally seen or that scouts have reported, each mark stamped with *when* it was seen. Never shows live enemy positions.
  - **Alarm bell:** you hear it when a watch post spots enemies.
- **Placing structures:** look at the ground and confirm, as in the prototype. **Walls** are placed by marking posts: mark a start post, walk the line, mark the end post (or more posts for a path).

### Scouting and intelligence

- **Scout** is a role you assign: *"Send two scouts east to find their camp and report back."*
- Scouts record what they see as they travel: enemy buildings, troop counts (estimated, e.g. "about eight spearmen"), resources, terrain. **Information is not shared instantly.** A report reaches you when the scout returns to you or to the settlement; it appears in chat: *"Wren is back from the east. Two minutes ago their camp had about eight men with spears and no wall."*
- Scouts can be caught and killed; their knowledge dies with them.
- **Faster information:**
  - **Watch posts / towers:** instant alarm for anything inside their sight radius.
  - **Mounted scouts:** once you have horses, scouts go and return much faster.
- Rush detection is the core skill this creates: early scouting must be cheap enough that a careful player can afford it, and costly enough that skipping it is tempting.

---

## 5. Population, food, and housing

### Housing cap (supply)

Like supply in StarCraft: you can't grow beyond the housing you've built.

| Source | Housing | Build (3 workers) |
|---|---|---|
| Starting campfire | 8 | — |
| Hut (wood) | +6 | ~20 s |
| **Hard cap** | **200** | |

### Food and well-being

Each person eats on a ration cycle; children eat half.

| State | Effect |
|---|---|
| **Well fed** | Births happen. +10% work speed. |
| **Fed** | No births. Normal work. |
| **Hungry** | −25% work speed. |
| **Starving** | Health loss, then deaths. |

### Births

- Births happen only when the settlement is **well fed** *and* there is **free housing**.
- Rate scales with well-fed adults (target: roughly one birth per 4–5 adults per minute; tunable).
- Children mature in ~90 s and can carry light loads.
- **Pacing targets** (tuning goals): a strong economy reaches ~60 pop by minute 10, ~120 by minute 18, and can hit 200 by minute 25–30. Food, not housing, is meant to be the usual brake.

### Food sources

| Source | Notes |
|---|---|
| Berry bushes | Fast, finite, near start |
| Hunting | Deer and boar; animals flee. Hunters work out from the campfire or a stockpile |
| Farm | Sow → grow → harvest; one farm and farmer feed ~5 |
| Stockpile | +50 food reserve each, so you stay well fed through raids |

---

## 6. Tech tree

Diagrams: [TECH_TREE.md](TECH_TREE.md).

There's no separate "age up" button. Each age opens when you build its key building.

| Age | Opened by | Typical reach |
|---|---|---|
| Wood | Start | 0:00 |
| Stone | Quarry | ~3–5 min |
| Bronze | Smelter making bronze | ~10–13 min |
| Iron | Smelter upgraded to iron furnace | ~17–22 min |
| Gunpowder | University + gunpowder research | ~25–30 min |

### Resources

Seven raw resources and two refined ones:

- **Gathered:** wood, stone, food, wild horses.
- **Mined:** bronze ore, coal, iron ore. Each camp has one of each nearby, and more deposits are contested in the middle of the map.
- **Smelted:** bronze (bronze ore + coal), iron (iron ore + coal).

### Buildings

| Building | Age | Purpose |
|---|---|---|
| Campfire | Start | Housing 8, drop-off |
| Hut | Wood | +6 housing |
| Stockpile | Wood | Drop-off point near work |
| Farm | Wood | Grain |
| Armory | Wood → Bronze → Iron | Makes all weapons, armor, arrows and cannons. Upgrades in place each age |
| Palisade + gate | Wood | Fast, weak, burnable walls |
| Watch post | Wood | Early-warning alarm |
| Quarry | Stone | Stone; opens the Stone age |
| Stone wall + gate | Stone | Strong walls, built in stages |
| Stone tower | Stone | Alarm + archer position |
| Stable | Stone | Holds captured horses, breeds them |
| Mine | Stone | Placed on a bronze ore, coal or iron ore deposit |
| Smelter | Stone → Iron | Makes bronze; upgrades to an iron furnace |
| University | Gunpowder | Researches gunpowder |

### What each age gives you

**Wood (start with nothing).** 6 villagers, a campfire, empty hands. Gather berries and wood, then build the **Armory**: wooden spears, wooden shields, bows and stone-tipped arrows. Palisades and watch posts.
- **Rush window:** with the armory at 125 wood and a batch of four spears at 40, a rush fields about five armed men by minute 6–7. If you've scouted it, the counter is a palisade, a watch post, and villagers armed from the armory's stock as **militia**.

**Stone.** Stone walls show up early but take a lot of labor. They're built in stages (foundation → courses → walkway → battlements) and every stage needs stone quarried and hauled. A partly built wall still gives partial cover. Cost grows with length, so you choose between a tight walled core and fields spread outside it. Target: ~30–40 s per segment with 4 masons once the stone is on site. Also: stone towers, stable, siege ladders.

**Bronze.** Mines on bronze ore and coal, then a smelter. The armory upgrades to bronze: spears, swords, shields, armor, arrowheads, pikes, lances. Battering rams.

**Iron.** The smelter upgrades to an iron furnace; the armory upgrades to iron: the same weapon set, stronger and more durable, plus iron armor.

**Gunpowder.** The University researches gunpowder (~90 s). The iron armory can then cast **cannons** and make **shot** (iron + coal). See §8.

### Arrows (the archer constraint)

- Arrows are made at the armory from wood + stone (later bronze or iron heads), in batches that take a crafter's time.
- Archers carry a limited quiver (16) and refill at the armory. Some arrows can be recovered from the field after a fight.
- The constraint is crafting labor and walking back to refill, not a long supply chain.

---

## 7. Horses

- **Wild herds** roam the map. Villagers drive them into a **Stable** (needs the Stone age).
- The stable breeds them over time (mare + stallion; ~60 s gestation, ~90 s for the foal to mature). Herd size is a long-term investment, but no single step takes long.
- **Uses:**
  - **Mounted scouts:** faster intelligence.
  - **Commander's horse.**
  - **Cavalry:** horse + lance (Bronze age).
  - **Cannon teams:** horses move cannons much faster than crews hauling them.

---

## 8. Military

### Weapons and gear

| Item | Tiers | Role |
|---|---|---|
| Spear | Wood → bronze → iron | General infantry, decent vs cavalry |
| Bow + arrows | Wood (stone tips) → bronze → iron tips | Ranged; quiver-limited |
| Shield | Wood → bronze → iron | Blocks arrows and blows, slows the bearer |
| Sword | Bronze → iron | Strong in melee with a shield |
| Pike | Bronze → iron | Hard counter to cavalry, weak in close melee |
| Lance | Bronze → iron | Mounted charge damage |
| Armor | Bronze → iron | Heavier means slower |
| Cannon | Gunpowder | Siege weapon; see below |

### Matchups

- Pikes beat cavalry.
- Cavalry beats archers and anything caught in the open.
- Archers beat unshielded infantry.
- Shields and armor blunt archers.
- Sword and shield beats pikes up close.
- **Cannons beat walls and buildings.**

Material tier scales damage and durability.

### Cannons

The most advanced weapon in the game, and deliberately a siege tool first.

- **Against walls and buildings:** devastating. A few hits bring down a stone wall segment; palisades and huts go down in one or two.
- **In the open field:** inaccurate. Shots scatter more with range, and reload is slow (~15 s), so a cannon can hit a packed formation hard but often misses a spread-out one.
- **Crew:** 3 villagers. Slow to move by hand; much faster with a horse team.
- **Vulnerable:** cavalry that reaches the guns wins. Cannons need an escort.
- **Ammunition:** shot (iron + coal) from the armory, carried with the gun, like arrows.

### Soldiers are villagers

Arming someone takes them off work. Soldiers still eat. Captains lead squads: *"Captain Hal, take ten spearmen and hold the ford."*

### Combat systems

Formations (line, wedge, shield wall, loose), morale and routing, wall assaults (ladders, rams, cannons), fire against palisades, and first-person commander combat (swing, thrust, block, bow draw) carried over from the prototype.

---

## 9. Giving orders

### The chat line

Press **Enter** (or **T**) to open the chat line. Who you're talking to:

- The villagers you've selected (click someone you're looking at; Shift+click adds or drops more; Esc clears). Selected people take the order as one crew, or
- The villager or captain you're looking at when you open it, or
- A name: `@Hal take ten spearmen to the ford`, or
- `@all` for every crew.

Free text goes to **Terra**. Text starting with `/` is a **slash command**, handled instantly by the game with no model call.

### Slash commands

| Command | Opens |
|---|---|
| `/b` | **Build popup** above the chat: pictures, keys and costs. `b` basic or `v` advanced, then one key (`/b b h` = hut). Locked ones are dimmed, and red means you're short. Pick one → place it → the addressed crew (or the nearest idle villagers) builds it |
| `/c` | **Weapons popup:** what the armory makes, keyed the same way (`/c b w` = wooden spears) |
| `/l` | Ledger: stockpiles, population, food, housing |
| `/p` | People: crews, captains, and what each is doing |
| `/s` | Scout reports, newest first |
| `/m` | Field map |
| `/t` | Tech tree: what's next and what it needs |
| `/h` | Help and the full command list |

The build and weapons popups use letters or the mouse. Other menus are navigated with number keys or the mouse and can be closed with **Esc**.

### Terra

- **Per-request snapshot:** unlocked tech and costs, stockpiles, food state, housing, crews and their plans, and *known* map features (from the commander's own knowledge and scout reports only, never hidden truth).
- **Response kinds** are `plan`, `clarify`, `reply`, and `cancel`. Plans are up to 8 steps per crew, and the step schema is generated from the data tables.
- **Order execution** uses reasonable defaults for details the player leaves open. The game validates and submits the plan when Terra responds. Construction opens manual placement for every structure or wall before the crew receives its orders.
- **Prerequisite reasoning:** *"Make iron swords"* before you have iron → Terra explains what's needed and offers to plan it.
- **Standing orders:** captains keep jobs running, e.g. *"keep the archers stocked with arrows"*, *"keep two scouts watching the east road."*
- **Cost and latency:** slash commands and a local parser handle simple orders ("hold", "follow me", "fall back") with no model call; per-match request limits; model names are configuration, not code.
- **Online:** model calls go through a backend proxy; player API keys never reach other clients or the game server logs.

### Voice (later, optional)

Push-to-talk with speech-to-text can be added on top of the chat line later. Spoken text goes through exactly the same path as typed text.

---

## 10. Learning the game

### Intro

- A short, skippable opening (~60 s) when the game is first launched: who you are, who the rival is, what winning means. It's in first person, in-engine, and ends with you standing at the campfire.

### Tutorial match: "The Founding"

A guided match against a passive rival. Terra acts as your steward and gives one goal at a time, waiting until you've done it:

1. Walk, look around, and find your villagers.
2. Open the chat, look at a villager, and type *"gather wood."*
3. Use `/b b h` to build a hut and watch the housing cap rise.
4. Feed the village: berries, then a farm. See "Well fed" and the first birth.
5. Build the armory, use `/c` to make spears, and arm a few villagers.
6. Send a scout. Read the report with `/s`.
7. A small raid is coming (the scout warned you): build a palisade, call militia, survive.
8. Promote a captain and give a multi-step order in plain language.
9. Build a quarry and start a stone wall.
10. Final goal: find and defeat the rival's weak camp.

Each step is short. The full tutorial should take ~15 minutes, and later ages (bronze, iron, horses, cannons) are introduced as optional short lessons.

### In regular matches

- **Hints** for the first few matches: one-line tips in chat when something new becomes possible ("You can now build stone walls — try `/b v w`").
- Ask Terra anything: *"why aren't we growing?"* → *"Food is only 'Fed', not 'Well fed', and housing is full."*
- **Calm start option:** the AI won't attack for the first 10 minutes. Good for learning; off by default in normal matches.

---

## 11. AI rival

- Plays through the same validated command interface.
- **v1:** a utility/behavior AI with build-order templates (rush, boom, turtle, cavalry, cannon push) and difficulty levels that vary scouting diligence, reaction time, and economic efficiency. It is **not** allowed to see through fog of war.
- **v2:** weights trained in headless simulation (as in the prototype), evaluated in held-out duels.

---

## 12. Graphics without art packs

The first goal was to see how far built-in tools, procedural generation and free libraries go. Packs come later, only where the gap is obvious.

**In v0.1.0 (all free):**

- **Lighting and atmosphere:** a procedural sky shader with drifting clouds, a sun with soft 4-split shadows, AgX tone mapping, aerial-perspective fog, glow, and SSAO (Medium) or SSIL and volumetric fog (High).
- **Terrain:** a heightmap per seed (512 m, 768 m or 1 km across), chunked with levels of detail. A splat-mapped shader blends grass, forest floor, dirt and triplanar rock by slope, height and noise, using CC0 **Poly Haven** photo textures. The ground wears to dirt around buildings.
- **Vegetation:** about 10,000 procedurally modelled oaks and pines (alpha-cut leaf and needle cards, wind sway, two levels of detail), instanced grass around the commander, and berry bushes.
- **Buildings and walls:** all 17 structures modelled in code from parts (timber frames, planks, thatch, dressed stone, plaster), with PBR textures. Construction is shown as the building rising course by course. Armory and smelter tiers look different.
- **People and animals:** procedural mannequins and quadrupeds, animated on the GPU (walking, running, chopping, hammering, fighting, shooting, riding, grazing), with tools, weapons, shields, armour, carried loads, and the commander's crown and cloak.
- **Sound:** every effect is synthesized at startup (wind, birds, fire, chopping, hammering, bells, horns, clashes, bows and cannons).

**Where it still looks like a placeholder:** people and horses read as mannequins up close. **Likely first purchases if needed:** rigged people with animations, horses, then a tree set. Decide after playtesting.

---

## 13. Roadmap

Each phase ends playable. A phase isn't done until its "done when" is demonstrated in-game and covered by headless tests where possible.

| # | Phase | v0.1.0 status |
|---|---|---|
| 0 | **Foundation**: project, data tables, headless sim, tests | Done |
| 1 | **Core loop**: terrain, lighting, forests, commander, chat, `/b` `/h`, Terra, gather, build | Done |
| 2 | **Survival economy**: food states, housing, births, berries, hunting, farms, `/l` `/p` | Done |
| 3 | **Wood and Stone ages**: armory, `/c`, weapons, bows and arrows, militia, palisades by posts, quarry, stone walls, towers | Done |
| 4 | **Scouting and knowledge**: fog of war, scouts, timestamped reports, `/s`, field map, alarms | Done |
| 5 | **Combat**: unit stats and matchups, morale (routing, wounded retreat), commander combat, arrows | Done; formations are basic |
| 6 | **AI rival v1**: rush/boom/turtle/cavalry/cannon openings, difficulty, win by commander death | Done |
| 7 | **Intro and tutorial**: opening, "The Founding", hints, calm start | Done |
| 8 | **Bronze and iron**: mines, smelter, armory upgrades, pikes, swords, lances, armor, rams | Done (siege ladders not yet) |
| 9 | **Horses**: wild herds, stable, breeding, mounted scouts, cavalry | Done |
| 10 | **Gunpowder**: university, research, cannons, shot, horse teams | Done |
| 11 | **Polish**: animation, audio, VFX, day/night, saves/resume, settings, Windows installer | Installer, settings and audio done; saves, day/night and the art pass are next |
| 12 | **Online**: dedicated server, online 1v1, then up to 8 players; lobby; backend proxy for model calls | Not started |
| — | **Voice (optional)**: push-to-talk speech-to-text into the chat line | Not started |

**Art review gate:** now that v0.1.0 is playable, review the visuals and decide which (if any) art packs to buy.

---

## 14. Carried over from MCRTS

Rewritten in GDScript for Godot 4, keeping the design:

- Strict JSON-schema order format generated from the job list (`game/orders.mjs`), and plan validation before execution.
- `plan / clarify / reply / confirm / cancel` dialogue flow and crew questions ("only 2 workers free — proceed?").
- Captains, crews, and recruits; plans resume after a save.
- Aim-and-confirm site placement with re-validation at build start (`game/buildings.mjs`).
- Encrypted local credential storage; ChatGPT sign-in or API-key usage source.
- Headless training/evaluation harness for the AI rival.
- Autosave and resume.

**Dropped:** voxel world, Three.js renderer, Electron shell, Windows-only speech.

---

## 15. Risks

| Risk | Mitigation |
|---|---|
| Realistic characters and horses without art packs | Art review gate after Phase 1; budget for targeted purchases |
| 200 units per side in first person | GPU-animated MultiMesh crowds, distance culling, Low preset for integrated graphics |
| LLM latency (1–3 s) during combat | Slash commands and a local parser for urgent orders; standing orders; captains act autonomously |
| LLM cost per match | Request caps, compact snapshots |
| Balance across a 5–45 min range | Headless sim balance runs on every content change |
| GDScript performance at 400 units | 10 Hz fixed-step simulation, spatial hashing, throttled pathfinding; profiled at about 8× real time with 200 people |

---

## 16. Decisions (formerly open questions)

1. **Map:** a random seed every match, in three sizes. Small is 512 m (camps at least 320 m apart, 100 m from the edge), Medium is 768 m (460 m, 125 m) and is the default, Large is 1 km (620 m, 150 m) and is the biggest for 1v1. The tutorial always uses Large.
2. **Commander death:** ends the match. Both commanders wear a **crown**, so you can find and kill Rook.
3. **Rivers:** none at first. Worth adding later as obstacles with fords and bridges.
4. **Tin:** dropped. Copper and tin are merged into a single **bronze ore**.
5. **Platform:** Windows first, shipped as an installer from GitHub Releases.
