# ⚠️ MERGE NOTES — READ BEFORE MERGING `v0.6.0-armory-research`

## ❗ BIG NOTE: field-built rams must NOT make builders put their weapons down

This branch adds the **Battering ram** structure (`/b v` then `B`, `Defs.BUILDINGS["ram"]`).
Villagers build it in the field. It needs the **bronze armory research** (`/r`, `armory_bronze`).
When it is finished the site turns into a ram unit (`_complete()` in `scripts/sim/match_work.gd`).

**The rule: nobody has to stow weapons, armour or horses to build a ram. Every other construction still does.**

That rule (people hand their gear back to the armory before going back to work) lives in
a **different branch**, `v0.6.0-stow-gear` (worktree `MarchHold-stow-gear`), so it is **not
implemented here**. It MUST be added when the two branches are merged.

### What to do when merging with `v0.6.0-stow-gear`
The ram def already carries the flag `"keeps_arms": true` (`scripts/data/defs.gd`, `BUILDINGS["ram"]`).
In `scripts/sim/match_work.gd`, `resume_work()` (stow-gear branch) pushes a `disarm` step first:

```gdscript
var carrying := us.any(func(u): return _needs_stowing(u))
...
if carrying:
    steps.push_front({"action": "disarm", ...})
```

Change it so that the `disarm` step is skipped when the work being returned to is a ram build:

```gdscript
func _keeps_arms(steps: Array) -> bool:
    for s in steps:
        if s.get("action") == "build" and Defs.BUILDINGS.get(s.get("subject", ""), {}).get("keeps_arms", false):
            return true
    return false
...
var carrying := not _keeps_arms(steps) and us.any(func(u): return _needs_stowing(u))
```

Also check that nothing else in that branch forces a disarm before a `build` step of `ram`
(any other place that calls `_needs_stowing` / `_stow_gear` / queues `disarm`).
Add a test: armed villagers sent back to a ram build keep their weapons, and the same
villagers sent back to a hut build hand them in first.

### Done on this branch
- `Defs.BUILDINGS["ram"]` with `keeps_arms: true`, `needs: armory_bronze`, `becomes: ram`.
- Nothing here stows or checks weapons, so on this branch alone armed builders already keep them.
  The rule only bites once `v0.6.0-stow-gear` is merged. **Do not merge it without the change above.**

## Other things to know
- Armory bronze/iron upgrades are now research (`/r`) that upgrades every armory.
- All research (gunpowder, mounted archery, armory tiers) is paid up front and runs by itself in its
  building, with no villagers.
- `/b v` key `A` (upgrade armory) is gone; `B` is the field ram.
