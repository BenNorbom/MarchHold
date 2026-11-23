# MarchHold

A medieval strategy game played entirely in first person. You are the commander of a small band of settlers. There's no overhead view; you walk among your people and **talk to them**. Type an order, and your villagers gather, build, arm themselves, scout and fight. Grow a campfire into a walled town with bronze, iron and finally cannons, and outlast the rival commanders.

- A fresh valley every match in four sizes. Small (512 m) holds 2 settlements, Medium (768 m) holds 4, Large (1,024 m) holds 6, and Huge (1,536 m) holds 8. Medium is the default.
- Play against one to seven AI rivals with five openings (rush, boom, turtle, cavalry, cannons) and three difficulties.
- Be the last commander standing. Your death ends the match.
- **Grand army** mode: every side starts with 200 villagers behind stone walls, every technology, 20 armories, 10 full stables and big stores, for battles between maxed-out armies.
- Optional **Terra**: connect your ChatGPT plan or enter your own OpenAI API key to give orders in plain language ("get thirty wood, then put up a hut by the berries").

## Install

1. Download `MarchHold-Setup-<version>.exe` from [Releases](https://github.com/BenNorbom/MarchHold/releases).
2. Run it. It installs for your user (no admin needed) and adds a Start-menu shortcut.
3. Windows SmartScreen may warn that the publisher is unknown, because the installer isn't code-signed yet. Choose **More info → Run anyway**.

Requires Windows 10 or 11 (64-bit) and a GPU with Vulkan support. Integrated graphics (e.g. Intel Iris Xe) start on the Low preset automatically.

## First match

Start with **The Founding** (tutorial) from the main menu. Terra, your steward, walks you through ten short goals: giving orders, building, feeding the village, arming people, scouting, surviving a raid, captains, stone walls, and finally taking Rook's camp. It takes about 15 minutes.

## Controls

| Key | Action |
|---|---|
| WASD, mouse | Move, look |
| Shift / Space | Sprint / jump |
| Enter or T | Talk to your selected villagers, or the crew or villager you're looking at (or to your people) |
| Left mouse | Select the villager you're looking at (Shift+click adds or drops more); otherwise strike, or with a bow hold to draw and release to shoot. With enemies close, a click always strikes |
| Right mouse or V (hold) | Block from the front, which costs stamina. Raise it just as a blow lands, when the marker turns blue, to parry. While placing, right-click finishes a wall or cancels |
| Q | Switch between bow and weapon (rotates a building while placing) |
| E / G | E talks or uses a stone tower door. E or G takes gear at the armory. |
| F | Take or leave a horse at your stable |
| R | Mark the spot you're looking at (orders can say "there" or "the mark") |
| Tab | Cycle between the whole crew and individual members in chat. Open the ledger outside chat. |
| M | Field map (only what you and your scouts have seen) |
| B / C | Build / craft. Then B (basic) or V (advanced), then one key: B, B, H is a hut |
| F1 or H | Help |
| Esc | Close menus, cancel placement, clear the selection, pause |
| F11 / F12 | Fullscreen / screenshot |

## Giving orders

Look at a villager and **click** to select them. **Shift+click** adds more people or drops someone already selected, and a gold ring marks everyone selected. Press **Enter** and your order goes to exactly those people, working as one crew. **Esc** clears the selection.

Look at a villager and press **Enter** to address their whole crew. Press **Tab** before sending to select that villager alone, then press it again to cycle through the other members and back to the crew. **Shift+Tab** cycles backward. `@Name` addresses someone's crew by name and `@all` addresses everyone. If nobody is addressed, idle villagers take the job.

Promote a villager to captain and give them a post, such as “run the village” or “take charge of farming here.” Captains staff jobs, build within their mandate, and respond to threats. Use the people menu to talk to a post.

Give a captain a strategy: “get to the Iron age ASAP” has them build the mines, smelter, furnace and university and staff them; “focus on pike production” keeps 20 pikes in the armory (“focus on 40 pikes” for more), doing the research and building the armories it takes. Focuses: pikes, swords, archers, cavalry, cannons, spears, growth, defence. An age and a focus can both stand. “Go back to normal” drops them.

Give a selected individual a new order to take them out of their current crew, or say `dismiss` to release them. Say `join @Name` to move the addressed individual or crew into that person's crew and pick up its current orders.

Slash commands work instantly and never need Terra:

| Command | Opens |
|---|---|
| `/b` | Build popup with pictures and keys. `b` is basic and `v` advanced, then one key: `/b b h` is a hut (`/b hut` also works) |
| `/c` | Weapons popup, keyed the same way: `/c b w` is a wooden spear, `/c 5 b w` five (`/c spears 5` also works). Hold **Shift** and keep pressing the key or clicking the picture to keep buying, or hold it down |
| `/l` | Ledger: stores, people, food, housing, crews |
| `/p` | People and crews |
| `/s` | Scout reports, newest first |
| `/r` | Research: bronze and iron armory, mounted archery (stable) and gunpowder (university). Picked like `/b` and `/c`; `/r gunpowder` works too. Research is paid up front and runs by itself, with no villagers |
| `/m` | Field map |
| `/t` | Tech tree |
| `/h` | Help |

Orders the game understands without Terra, for example:

```
gather wood · gather 30 wood then build a hut · pick berries · work the farms · hunt
build a hut · build a palisade · make 32 arrows · arm 6 with spears · to arms! · fall back
send two scouts east · scout their camp · attack their camp · guard the mark · follow me · hold
tame 3 horses · mount up · smelt bronze · research the bronze armory · research gunpowder · man the cannon
promote · dismiss · status · cancel
continue construction · finish the wall · gather wood here · back to work
```

### Hotkeys

`/b`, `/c` and `/r` open a popup of pictures. A hotkey acts the moment it is complete, with no Enter: typing `/b b h` (or pressing B, B, H) lets you place a hut. You can also click a picture. An order recalled with the Up arrow still waits for Enter. Crafting takes its count first: `/c 2 b a` makes two batches of arrows.

| | Keys |
|---|---|
| `/b b` Basic structures | **H** hut · **F** farm · **S** stockpile · **A** armory · **P** palisade · **G** palisade gate · **W** watch post · **Q** quarry |
| `/b v` Advanced structures | **W** stone wall · **G** stone gate · **T** tower · **H** stable · **M** mine · **S** smelter · **U** university · **B** battering ram · **F** iron furnace |
| `/c b` Basic weapons | **W** wooden spear · **D** wooden shield · **B** bow · **A** arrows · **R** ram · bronze: **S** sword, **H** shield, **M** armor, **P** pike, **L** lance |
| `/c v` Advanced weapons | iron: **S** sword, **H** shield, **M** armor, **P** pike, **L** lance · **C** cannon · **T** cannon shot |
| `/r` Research | **B** bronze armory · **I** iron armory · **M** mounted archery · **G** gunpowder |

Walls are placed post to post: choose a palisade or stone wall, click each post, press Enter to finish.

Mark a finished stone tower with **R** and tell your archers to `guard the mark`. Up to three will walk to the door and take rooftop posts. They shoot farther from the roof, and the stone parapet shelters them. Press **E** at the door to join them, then **E** on the roof to return to the door.

### Terra (optional)

In **Settings → Terra connection**, choose **ChatGPT plan → Continue with ChatGPT**. Approve plan use in your browser and return to MarchHold. Terra is selected if your account offers it. You can choose another available order model, manage plan usage, or disconnect from Settings.

You can also choose **OpenAI API key** and paste your own key into the game. This option uses your OpenAI API balance. Choose **Off** to keep orders local.

MarchHold keeps account credentials encrypted on your PC. When you submit a free-form order or question, the game sends the text, recent Terra dialogue and relevant game state to OpenAI. Terra answers questions and uses the village's situation to fill in details you leave open. The game checks orders as soon as Terra returns them. For new construction, choose each building site and wall's posts. Captains with a post can choose sites inside their area. Settings includes a separate per-match request limit (default 120).

## How the game works

- **Growth.** Villagers are born when the village is *fed* (1 food stored per person, 75% of the birth rate) or *well fed* (3 food per person, full rate) and there's free housing. Births keep building up while housing is full (up to half a birth per adult), so a new hut or a death is filled at once. The campfire houses 8 and each hut 6, up to 200 people. The campfire stores 150 food and each stockpile 50 more.
- **Ages.** Wood (start) → Stone (build a quarry by a rock outcrop) → Bronze (smelt bronze from bronze ore and coal) → Iron (upgrade the smelter to an iron furnace) → Gunpowder (university research). Researching the bronze and then the iron armory (`/r`) upgrades every armory at once, including ones built later.
- **Scouting.** You only know what you've seen. Scouts report when they return, and if they die, what they saw dies with them. Watch posts and towers ring the alarm when enemies appear.
- **Armories.** Each armory works through a queue by itself, one item at a time, paying for each as it starts. An order is shared out among all your armories, so more armories make it sooner. Once the armory is researched to bronze it stops making wooden shields, and at iron it stops making bronze gear; wooden spears, bows, arrows and rams are always made.
- **Combat.** Pikes beat cavalry. Cavalry runs down archers. Shields and armor blunt arrows. Sword and shield beat pikes up close. A raised shield protects you from blows and arrows from the front. Blocking costs stamina, and a well-timed parry staggers the attacker. Pikemen and archers need both hands, so they carry no shield. A cannonball kills whatever it lands on, even another cannon, but only one target, and it misses more the further it flies. Cannons smash walls, reload slowly and need a crew of three. Horses pull cannons faster.

The full design is in [PLAN.md](PLAN.md) and the tech tree in [TECH_TREE.md](TECH_TREE.md).

## Building from source

Requirements: [Godot 4.7.2](https://godotengine.org/download) with the Windows export templates, and [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the installer.

```powershell
# Run the headless tests (simulation, orders parser, schema, AI duel)
godot --headless --path . -s res://tests/run_tests.gd
# Battle tests (bodies, blows, the commander's fighting, matchups)
godot --headless --path . -s res://tests/test_battle.gd

# Redraw the popup's pictures after changing a model
godot --headless --path . -s res://tools/make_icons.gd

# Play from source
godot --path .

# Test, export and build the installer into dist/
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

`tools/build.ps1` expects Godot and Inno Setup under `%USERPROFILE%\Tools` and takes `-Godot` and `-Iscc` parameters if they live elsewhere. `python tools/fetch_textures.py` re-downloads the CC0 textures.

### Layout

| Path | What's there |
|---|---|
| `scripts/data/defs.gd` | Content tables: buildings, items, ages, resources, orders. The single source of truth |
| `scripts/sim/` | Authoritative simulation (no rendering): economy, crews, combat, vision, scouting |
| `scripts/ai/rival.gd` | AI commanders, using the same command interface as the player |
| `scripts/orders/` | Local order parser, Terra schema and the OpenAI client |
| `scripts/view/` | Rendering: terrain, forests, buildings, people (GPU-animated), the commander |
| `scripts/ui/`, `scripts/game/` | HUD, menus, hotkeys, field map, intro, tutorial, hints |
| `shaders/` | Terrain, foliage, grass, people, rocks, sky |
| `tests/run_tests.gd` | Headless test suite, including AI-vs-AI duels |
| `tests/test_battle.gd` | Battle tests on a flat test field |

## Status

Version 0.6.0 adds the Grand army mode, strategy orders for captains (“get to the Iron age ASAP”, “focus on pike production”), armories that work through queues by themselves, armory upgrades as research in a new `/r` popup, battering rams built in the field, Shift to keep buying, and births while only fed. Berries run out sooner, so farms matter. Weapons are bought one at a time and cost more; metal spears are gone, and pikemen and archers carry no shield. Cannonballs kill one target outright. Rook defends far better against rushes, and big battles no longer freeze the game.

Version 0.5.0 added multi-rival matches, captain posts, combat timing and parries, stone tower garrisons, and build and craft hotkeys.

Version 0.4.0 added three map sizes, grid build and craft menus, named stone and ore landmarks, and clearer berry bushes and ore, and slows births slightly. Version 0.3.2 added click and Shift+click selection of villagers. Version 0.3.1 let Terra fill in order details and submit orders immediately, with manual placement for construction. Version 0.3.0 added individual crew orders, slash-command previews, and animated villager models. Version 0.2.0 added ChatGPT plan sign-in and model selection for Terra. Version 0.1.0 introduced the full lean tech tree, chat and slash commands, Terra, scouting, combat, horses, cannons, the AI rival, the intro and the tutorial. Next up: saving and resuming, an art pass on horses, formations and morale tuning, voice orders, and online play for up to 8 players.

## Credits

Built with [Godot Engine](https://godotengine.org) (MIT). Textures from [Poly Haven](https://polyhaven.com) (CC0). Villagers use adapted [Grab3D models](LICENSES/VILLAGERS-CC0.txt) (CC0). Fonts: Cinzel and EB Garamond (SIL Open Font License). The game generates its other models, trees and sounds procedurally. The installer is made with Inno Setup. Licence texts are in [LICENSES/](LICENSES).
