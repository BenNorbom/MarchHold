# MarchHold

A medieval strategy game played entirely in first person. You are the commander of a small band of settlers. You don't click on units; you walk among your people and **talk to them**. Type an order, and your villagers gather, build, arm themselves, scout and fight. Grow a campfire into a walled town with bronze, iron and finally cannons, and defeat Commander Rook before he defeats you.

- 1 km × 1 km valley, a fresh map every match; the two camps start at least 620 m apart.
- 1v1 against an AI rival with five openings (rush, boom, turtle, cavalry, cannons) and three difficulties.
- Kill the crowned enemy commander to win. If you fall, the match is lost.
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
| Enter or T | Talk to the crew or villager you're looking at (or to your people) |
| Left mouse | Strike; with a bow, hold to draw and release to shoot |
| Q | Switch between bow and weapon (rotates a building while placing) |
| E / G | Talk to the person you look at; take gear at the armory |
| F | Take or leave a horse at your stable |
| R | Mark the spot you're looking at (orders can say "there" or "the mark") |
| Tab | Cycle between the whole crew and individual members in chat. Open the ledger outside chat. |
| M | Field map (only what you and your scouts have seen) |
| B / C | Build menu / craft menu |
| F1 or H | Help |
| Esc | Close menus, cancel placement, pause |
| F11 / F12 | Fullscreen / screenshot |

## Giving orders

Look at a villager and press **Enter** to address their whole crew. Press **Tab** before sending to select that villager alone, then press it again to cycle through the other members and back to the crew. **Shift+Tab** cycles backward. `@Name` addresses someone's crew by name and `@all` addresses everyone. If nobody is addressed, idle villagers take the job.

Give a selected individual a new order to take them out of their current crew, or say `dismiss` to release them. Say `join @Name` to move the addressed individual or crew into that person's crew and pick up its current orders.

Slash commands work instantly and never need Terra:

| Command | Opens |
|---|---|
| `/b` | Build menu: everything you can build now, with costs (`/b hut` builds directly) |
| `/c` | Craft menu: what the armory can make (`/c spears 2` makes two batches) |
| `/l` | Ledger: stores, people, food, housing, crews |
| `/p` | People and crews |
| `/s` | Scout reports, newest first |
| `/m` | Field map |
| `/t` | Tech tree |
| `/h` | Help |

Orders the game understands without Terra, for example:

```
gather wood · gather 30 stone then build a house · pick berries · work the farms · hunt
build a hut · build a palisade · make 32 arrows · arm 6 with spears · to arms! · fall back
send two scouts east · scout their camp · attack their camp · guard the mark · follow me · hold
tame 3 horses · mount up · smelt bronze · upgrade the armory · research gunpowder · man the cannon
promote · dismiss · status · cancel
```

Walls are placed post to post: choose a palisade or stone wall, click each post, press Enter to finish.

### Terra (optional)

In **Settings → Terra connection**, choose **ChatGPT plan → Continue with ChatGPT**. Approve plan use in your browser and return to MarchHold. Terra is selected if your account offers it. You can choose another available order model, manage plan usage, or disconnect from Settings.

You can also choose **OpenAI API key** and paste your own key into the game. This option uses your OpenAI API balance. Choose **Off** to keep orders local.

MarchHold keeps account credentials encrypted on your PC. When you submit a free-form order or question, the game sends the text, recent Terra dialogue and relevant game state to OpenAI. Terra answers questions and uses the village's situation to fill in details you leave open. The game checks orders as soon as Terra returns them. For construction, you choose every building site and set each wall's posts before the crew starts the order. Settings includes a separate per-match request limit (default 120).

## How the game works

- **Growth.** Villagers are born only when the village is *well fed* (3 food stored per person) and there's free housing. The campfire houses 8, each hut 5 and each house 10, up to 200 people.
- **Ages.** Wood (start) → Stone (build a quarry by a rock outcrop) → Bronze (smelt bronze from bronze ore and coal) → Iron (upgrade the smelter to an iron furnace) → Gunpowder (university research). The armory upgrades in place from wood to bronze to iron.
- **Scouting.** You only know what you've seen. Scouts report when they return, and if they die, what they saw dies with them. Watch posts and towers ring the alarm when enemies appear.
- **Combat.** Pikes beat cavalry. Cavalry runs down archers. Shields and armor blunt arrows. Sword and shield beat pikes up close. Cannons smash walls but scatter in the open, reload slowly and need a crew of three. Horses pull cannons faster.

The full design is in [PLAN.md](PLAN.md) and the tech tree in [TECH_TREE.md](TECH_TREE.md).

## Building from source

Requirements: [Godot 4.7.2](https://godotengine.org/download) with the Windows export templates, and [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the installer.

```powershell
# Run the headless tests (simulation, orders parser, schema, AI duel)
godot --headless --path . -s res://tests/run_tests.gd

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
| `scripts/ai/rival.gd` | Commander Rook, playing through the same command interface as the player |
| `scripts/orders/` | Local order parser, Terra schema and the OpenAI client |
| `scripts/view/` | Rendering: terrain, forests, buildings, people (GPU-animated), the commander |
| `scripts/ui/`, `scripts/game/` | HUD, menus, field map, intro, tutorial, hints |
| `shaders/` | Terrain, foliage, grass, people, rocks, sky |
| `tests/run_tests.gd` | Headless test suite, including AI-vs-AI duels |

## Status

Version 0.3.1 lets Terra fill in order details and submit orders immediately, with manual placement for construction. Version 0.3.0 added individual crew orders, slash-command previews, and animated villager models. Version 0.2.0 added ChatGPT plan sign-in and model selection for Terra. Version 0.1.0 introduced the full lean tech tree, chat and slash commands, Terra, scouting, combat, horses, cannons, the AI rival, the intro and the tutorial. Next up: saving and resuming, an art pass on horses, formations and morale tuning, voice orders, and online play for up to 8 players.

## Credits

Built with [Godot Engine](https://godotengine.org) (MIT). Textures from [Poly Haven](https://polyhaven.com) (CC0). Villagers use adapted [Grab3D models](LICENSES/VILLAGERS-CC0.txt) (CC0). Fonts: Cinzel and EB Garamond (SIL Open Font License). The game generates its other models, trees and sounds procedurally. The installer is made with Inno Setup. Licence texts are in [LICENSES/](LICENSES).
