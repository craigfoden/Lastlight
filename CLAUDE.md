# CLAUDE.md — Lastlight

Co-op fantasy survival / tower-defense roguelite in **Godot 4.7-stable (GDScript)**.
This file + `docs/` are the shared contract for every collaborator's Claude sessions.
Read `docs/ARCHITECTURE.md` (decision log) before architectural calls; append decisions to it.
Canon design: `docs/GAME_DESIGN.md`. Claims/status: `docs/ROADMAP.md`.

## Environment (per machine)

- Engine: **Godot 4.7-stable, standard build (not .NET)** — pinned. On this machine:
  `C:\SourceControl\Godot\Godot_v4.7-stable_win64.exe` (use the `_console.exe` variant from
  scripts/CLI so output is captured). Install yours anywhere; keep the version exact.
- Docs ground truth: shallow clone of godot-docs, branch `4.7`, in a **sibling folder**:
  `C:\SourceControl\godot-docs`. **Never trust memory for Godot APIs** — training data lags the
  engine. Grep the clone (`tutorials/`, `classes/`). Best-practices section is the idiom
  authority after this repo's decision log.

## Run & verify commands (PowerShell)

```powershell
$godot = 'C:\SourceControl\Godot\Godot_v4.7-stable_win64_console.exe'

# Import assets / regenerate .uid files (run after adding files; also catches import errors)
& $godot --headless --import --path C:\SourceControl\Lastlight

# Launch the game (F5 equivalent)
& $godot --path C:\SourceControl\Lastlight

# Open the editor
& $godot --editor --path C:\SourceControl\Lastlight
```

### Testing multiplayer locally (two instances, one machine)

Windowed (human playtest — host in one window, join in the other):

```powershell
Start-Process $godot -ArgumentList '--path','C:\SourceControl\Lastlight','--','--host','--name=Host'
Start-Process $godot -ArgumentList '--path','C:\SourceControl\Lastlight','--','--join=127.0.0.1','--name=Guest'
```

Headless scripted smoke test (assert against the printed `[Network]`/`[Player]`/... logs):

```powershell
$hostLog = "$env:TEMP\ll_host_log.txt"
$p = Start-Process $godot -ArgumentList '--headless','--path','C:\SourceControl\Lastlight','--','--host','--name=HostTest','--quit-after-sec=22' -RedirectStandardOutput $hostLog -PassThru -NoNewWindow
Start-Sleep 3
& $godot --headless --path C:\SourceControl\Lastlight -- --join=127.0.0.1 --name=ClientTest --auto-harvest --quit-after-sec=14
$p.WaitForExit(); Get-Content $hostLog
```

Dev CLI args (after `--`): `--host`, `--join=<ip>`, `--name=<n>`, `--quit-after-sec=<s>`
(wall-clock quit for headless runs), `--auto-harvest` (teleport-harvest loop, exercises the RPC
chain), `--fast-cycle` (10 s days / 6 s nights — pass to *every* instance),
`--grant-materials=wood:10,stone:10` (host cheat for testing builds), `--auto-build`
(scripted place/reject/sell timeline), `--auto-block-test` (walls in the tower heart; the
sealing wall must be rejected by the path rule).

## Definition of done

A system is done when ALL of:
1. It runs: launched via CLI, output captured, **zero errors AND zero warnings — deprecation
   warnings count as failures**.
2. It works **solo AND with a host + one local client** (every feature is network-aware).
3. New code self-reviewed against `docs/ARCHITECTURE.md` conventions and the official
   best-practices docs; borderline calls noted in the session recap.
4. Tunables are exported vars or resources — no magic numbers in logic.
5. Decisions made along the way are appended to `docs/ARCHITECTURE.md`.
6. Session recap written (what was built, why, what it taught).

## Conventions

- **snake_case** files/folders; **PascalCase** node names and `class_name`s (official style).
- Feature folders: a scene and its script live together (`scenes/player/player.tscn` + `.gd`).
- Static typing everywhere (`var x := 0`, typed params/returns). Doc comments (`##`) on every
  script explaining its role in one breath.
- Signals are past tense (`harvested`, `pool_changed`). Signals up, calls down; inject
  dependencies (`hud.setup(...)`), never reach upward from a child.
- Multiplayer naming: `request_*` (client→host RPC), `_sync_*`/`_receive_*` (host→all RPC),
  `host_*` (host-only plain funcs). See ARCHITECTURE.md for the full sync model.
- Lifecycle events `print("[System] ...")` — the smoke tests assert on these logs.
- Tunable numbers live in `@export` vars or `.tres` resources, never inline.
- Placeholder art: SVGs at final sprite dimensions (32×32 tiles, 32×48 characters) in
  `assets/sprites/placeholder/`, one file per sprite. No packed spritesheets until real art.

## Recipes

**Add a material:** create `data/materials/<id>.tres` (script `material_type.gd`; set a
never-to-change `id`, a `display_name`, `hud_color`) → add a `preload` to `TRACKED_MATERIALS`
in `scenes/hud/hud.gd` → place `ResourceNode`s in the world with `material_type` pointing at it.

**Add a harvestable node to the map:** instance `scenes/world/resource_node.tscn` under
`World/ResourceNodes` in `game.tscn`; override `material_type`, `starting_amount`, and the
`Sprite2D` texture per instance.

**Add a building/tower:** create `data/buildings/<id>.tres` (script `building_type.gd`; stable
`id`, `display_name`, `cost` dict, `texture`, attack stats — walls just leave `attacks` false;
set `class_id` for class exclusives) → add its sprite SVG → add the resource to
`buildable_types` on the BuildManager node in `game.tscn`. Hotbar, ghost, costs, path
validation, and sync all follow from the data.

**Add an enemy:** create `data/enemies/<id>.tres` (script `enemy_type.gd`; stable `id`, hp,
speed, attack stats) → add its 32×48 sprite SVG → add the resource to `enemy_types` on the
WaveDirector node in `game.tscn`. Movement, pathing, targeting-by-towers, hp sync, and wave
composition all follow. (Contract: group `"enemies"` + `hp` + `host_take_damage()` +
`host_send_snapshot()`.)

**Add a class:** framework lands in session 4; write the recipe here in the same commit.

## GOTCHAS (append whenever a session loses time to a pitfall)

- `change_scene_to_file()` cannot run inside `_ready()` — "parent node is busy" error.
  `call_deferred` anything in `_ready` that changes scene.
- `--quit-after N` counts **frames**, and headless mode runs frames **uncapped** — a "10 second"
  run exits in under a second and your host dies before the client connects. Use our
  `--quit-after-sec=N` user arg for wall-clock timing.
- MultiplayerSpawner's auto-replicate path can apply spawn state *after* the client's `_ready`;
  with client-authority sync the client's defaults can overwrite host-chosen state. Use
  `spawn_function` with explicit spawn data (see ARCHITECTURE.md).
- Clients must **load the game scene first, then connect** — never connect from the menu and
  change scenes after, or replication packets race the load.
- All RPCs in a script are checksummed together across peers — RPC-bearing scripts must be
  identical on host and client (they are, in co-op; matters if we ever split builds).
- Commit `.uid` files; gitignore only `.godot/` and `*.translation` (Godot 4.1+ rules).
- Two shell-sandboxed processes may not reach each other over loopback UDP when launched from
  separate Claude tool calls — launch both smoke-test instances from **one** command.
- ENet clients take 30+ seconds to emit `connection_failed` when nothing is listening — it reads
  as a hang. `game.gd` enforces its own `join_timeout` (10 s) and bounces to the menu.
- "Could not host (is the port already in use?)" usually means a leftover Godot instance from an
  earlier playtest still holds port 24565 — check for running `Godot*` processes before testing.
- `refuse_new_connections` on an ENet server does NOT reject connections — the ENet handshake
  still completes (the client fires `connected_to_server` and waits forever) while the host
  never fires `peer_connected`. Enforce join rules at the app layer: kick in `peer_connected`
  via `SceneMultiplayer.disconnect_peer()`.

## Team rules

- **Pull before every session; push (or PR) after.** Two people active at once → branches.
- **One system per person per session.** Claim it in `docs/ROADMAP.md` (name + ⏳) before
  starting; release (✅) when done.
- **Never two people in the same scene file** — `.tscn` merges badly. Many small scenes;
  treat `project.godot` edits (input map, autoloads) as merge-sensitive and call them out in
  the commit message.
- **Decisions go in the log** (`docs/ARCHITECTURE.md`), with rationale, same day.
- When a convention changes, the change lands in CLAUDE.md **in the same commit**.
- Plain-English commit messages — the git history doubles as a learning log.
