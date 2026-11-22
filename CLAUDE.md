# MarchHold: instructions for all agents

## Multiple agents work at once

Several agents work on this repo at the same time, and the user may be playtesting the game while they do. Every agent must do its own branch control.

- Work in your own git worktree, on your own branch, started from current `main` (v0.5.0 is released; v0.6.0 is in development). Worktree convention: `%USERPROFILE%\worktrees\MarchHold-<topic>`. Branch convention: `v0.6.0-<topic>`.
- Commit only to your own branch. Never commit directly to `main`, and never switch, reset, or force-push the main checkout.
- Before merging, check what other branches and worktrees changed (especially shared files such as `defs.gd`), then merge deliberately via PR or an explicit merge.
- Don't disturb a running game: while `MarchHold.exe` is running, no windowed Godot or screenshots, no build/installer scripts, no killing processes by name, and no writes to its user data. Run tests headless, one at a time; the dev laptop often has under 2 GB RAM free.
