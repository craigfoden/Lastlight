# CLAUDE.md — Lastlight

Co-op fantasy survival / tower-defense roguelite in **Godot 4.7-stable (GDScript)**.
This file + `docs/` are the shared contract for every collaborator's Claude sessions.
Read `docs/ARCHITECTURE.md` (decision log) before architectural calls; append decisions to it.
Canon design: `docs/GAME_DESIGN.md`. Claims/status: `docs/ROADMAP.md`.

## Environment (per machine)

- Engine: **Godot 4.7-stable, standard build (not .NET)** — pinned; install yours anywhere,
  keep the version exact, and use the `_console.exe` variant from scripts/CLI so output is
  captured. Known installs (this section kept clobbering itself machine-to-machine — list
  yours, don't replace others'):
  - Craig: `C:\SourceControl\Godot\Godot_v4.7-stable_win64_console.exe`
  - Chris: `C:\Users\Chris\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`
    (yes, that folder is named `...exe`)
- Docs ground truth: shallow clone of godot-docs, branch `4.7`, in a **sibling folder**:
  `C:\SourceControl\godot-docs`. **Never trust memory for Godot APIs** — training data lags the
  engine. Grep the clone (`tutorials/`, `classes/`). Best-practices section is the idiom
  authority after this repo's decision log.

## Run & verify commands (PowerShell)

```powershell
# Your _console.exe path — per-machine installs are listed in Environment above.
$godot = 'C:\SourceControl\Godot\Godot_v4.7-stable_win64_console.exe'  # Craig's

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
sealing wall must be rejected by the path rule), `--tower-hp=N` / `--final-day=N` /
`--cycle=day:night` (short runs), `--auto-fight` (stand on the enemy lane and cast the kit),
`--hurt-test` (host chips every player's hp on a timer — exercises downed/revive/respawn),
`--screenshot-after-sec=N` (save the viewport to `user://screenshot.png`; windowed runs only —
lets visual passes be eyeballed from scripted launches).

3D-branch extras: `--game3d` (host/join loads the 3D port scene instead of the 2D game;
`--auto-harvest` works there too), `--auto-walk` (the local 3D player strolls in a circle
when idle), `--log-players-after-sec=a,b`
(print every player's position at those times — assert a remote player's position changed
between stamps to prove replication), `--screenshot-at=a,b` (3D scenes' screenshot hook,
saves `user://game3d_shot_<t>.png`).

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
- Placeholder art: SVGs at final sprite dimensions in `assets/sprites/placeholder/`, one file
  per sprite. No packed spritesheets until real art. 3/4-view conventions (session 7): flat
  ground decals 32×32; characters and standing props/towers 32×48; walls 32×40; standing art
  shows a lit top + darker front face and reaches the bottom edge (the base line).
- 3/4 depth: the world Y-sorts as one space. Standing sprites bottom-anchor via
  `SpriteAnchor.apply(sprite)` **after** assigning the texture (baseline = origin.y + 16, the
  cell's bottom edge). Flat decals skip the anchor and use `z_index = -1`. Don't hand-set
  z_index to force draw order on world objects — fix the Y instead (the layer table lives in
  ARCHITECTURE.md).
- **3D port** (branch `3d-ortho-prototype`, phases in `docs/PORT_PLAN.md`): renderer is
  **Forward+** (decision log 2026-07-13). Omni-light shadows are **night-only and gated**:
  drive them through `GlowTower3D.set_light_shadows()`, which refuses them on the
  Compatibility fallback (lit region renders black) — and never leave them on in daylight,
  where the light's whole range box over-darkens on some Vulkan drivers (decision log
  2026-07-14). Scale: **1 world unit = 1 grid cell** (= 32 px of 2D art); ground
  plane is y = 0; the 2D grid's XY maps to XZ (cell `(x, y)` → world `(x + 0.5, ·, y + 0.5)`).
  Characters are `Sprite3D` billboards: `pixel_size = 0.036`, `BILLBOARD_FIXED_Y`,
  `shaded = false`, day/night lighting hand-driven via `modulate` each frame (the 3D
  CanvasModulate — `shaded` billboards vary by driver). Collision layers mirror the 2D
  scheme exactly: 1 world/solids, 2 players, 4 enemies, 8 hitboxes. 2D `.tres` data stays
  px-denominated — 3D consumers divide by 32 (`PX_PER_UNIT`) at the boundary.

## Recipes

**Add a material:** create `data/materials/<id>.tres` (script `material_type.gd`; set a
never-to-change `id`, a `display_name`, `hud_color`) → add a `preload` to `Materials.ALL`
in `data/materials/materials.gd` (both HUDs build their rows from it) → point `ResourceNode`s
at it via WorldGen's material slots.

**Populate the world (materials & scenery):** the map is scattered at load by `World/WorldGen`
(`scenes/world/world_gen.gd`) from a fixed seed — identical on every peer, never synced. Tune
its exports for density/rarity/amounts (`resource_count`, `near_amount`/`far_amount`, the ring
radii, `plaza_radius`/`safe_radius`), or point its material/texture slots at new resources.
Don't hand-place `ResourceNode`s in `game.tscn` anymore — WorldGen owns the layout. Keep grid-
solid content off the `y == 0` row (the guaranteed opening→heart corridor).
**3D branch:** `World/WorldGen` in `scenes/game3d/game3d.tscn` (`world_gen_3d.gd`) scatters
the identical layout — same seed, same cells, radii in cells (2D px / 32 exactly; keep new
radii binary-exact if parity should hold). Resource looks are the `tree_scene`/`rock_scene`/
`wisp_scene` exports; solids are mesh scenes in `solid_scenes` (they join group
`"obstacles"`), decor is flat 32×32 decal textures in `decor_textures` (scenes under
`scenes/world3d/visuals/`).

**Add a scenery prop:** add an SVG to `assets/sprites/placeholder/` (solid/standing: 32×48
with a front face, bottom-anchored automatically; decor: flat 32×32 decal), then add the
texture to `solid_textures` (blocks movement + registers in the build grid via group
`"obstacles"`) or `decor_textures` (visual only) on the `World/WorldGen` node.
`scenes/world/scenery_prop.tscn` is the shared body; solid vs decor is one export.

**Add a building/tower:** create `data/buildings/<id>.tres` (script `building_type.gd`; stable
`id`, `display_name`, `cost` dict, `texture`, attack stats — walls just leave `attacks` false;
set `class_id` for class exclusives; set `refund_fraction` for salvage-on-removal — defaults to
1.0/full, towers use 0.5) → add its sprite SVG → add the resource to `buildable_types` on the
BuildManager node in `game.tscn`. Hotbar, ghost, costs, path validation, removal refund, and
sync all follow from the data.

**Add an enemy:** create `data/enemies/<id>.tres` (script `enemy_type.gd`; stable `id`, hp,
speed, attack stats) → add its 32×48 sprite SVG → add the resource to `enemy_types` on the
WaveDirector node in `game.tscn`. Movement, pathing, targeting-by-towers, hp sync, and wave
composition all follow. (Contract: group `"enemies"` + `hp` + `host_take_damage()` +
`host_send_snapshot()`.)

**Add an ability:** create `data/abilities/<id>.tres` (script `ability_type.gd`; `kind` =
projectile or deployable + stats) and slot it into a class resource.

**Add a class:** create `data/classes/<id>.tres` (script `class_type.gd`; sprite, speed, dodge
stats, three ability slots) → mark its exclusive towers via `BuildingType.class_id` → set
`Network.local_player_class` from the (future) class-select screen. Player combat, gating,
HUD, talents, and XP banking all key off the class id.

**Add a talent:** create `data/talents/<id>.tres` (script `talent_type.gd`; `class_id`,
`modifiers` dict) → add its preload to `Talents.ALL`. Player.gd consumes the modifier keys.

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
- `@rpc("authority")` on a node whose multiplayer authority is a CLIENT (player nodes!) rejects
  calls from the host. Host→all broadcasts on such nodes need `any_peer` + a sender-is-host
  guard. Symptom: "RPC ... not allowed ... Mode is 'authority', authority is <peer>".
- Enemies detour around scenery rocks — a lane you eyeballed may be one cell off. When an
  overlap "isn't detected", first verify the overlap actually happens (ask `path_to_heart()`),
  before blaming physics.
- Two local test instances share the same `user://profile.cfg` — both bank run XP into it, so
  local multiplayer tests double-bank. Real players on separate machines are unaffected.
- WorldGen is deterministic *only* if every peer runs the same code with the same seed. Its
  generated nodes carry no MultiplayerSpawner — their RPCs (harvest) resolve by NodePath, which
  matches across peers because names are seed-deterministic (`Res_%d`/`Prop_%d`). Introduce any
  per-peer nondeterminism (a real random seed, `Time`-based values, Dictionary-iteration-order
  placement) and paths diverge → harvest RPCs silently target a non-existent node. If you need a
  per-run seed, sync it to all peers *before* generation.
- Host→all state broadcasts on a **player** node (hp, downed) must be `any_peer` + a
  sender-is-host guard, never `@rpc("authority")` — the node's authority is the owning client,
  so a plain-authority host broadcast is rejected (same rule as player projectiles). Player
  survival logic runs on the host for every player via `set_process(is_server())`; movement
  still simulates only on the owner, so host respawns reposition by RPCing the owner to move
  *itself*.
- A CanvasItem whose parent is a plain `Node` is a **"topmost" canvas item** — it silently
  escapes every ancestor's Y-sort and transform. That's why BuildManager and WaveDirector are
  Node2D despite being pure logic: their Buildings/Enemies containers must stay inside the
  world's Y-sort chain. Any new manager that owns visible children must extend Node2D too.
- PowerShell 5.1 `Get-Content` → `Set-Content`/`Add-Content` round-trips **corrupt UTF-8 repo
  docs** (em-dashes → mojibake, adds a BOM and CRLF): it reads BOM-less UTF-8 as ANSI. Edit
  repo text files with proper file tools; if a shell write is unavoidable, check `git diff`
  for encoding damage immediately after.
- Native OpenGL (the Compatibility renderer's first-choice driver) can hard-crash at context
  creation — seen over an RDP session: the process dies silently with only the engine header
  in the log (last line `Accessibility: AccessKit driver loaded`), which reads as "the game
  never launched". Force `--rendering-driver opengl3_angle` (or Forward+) when testing over
  remote desktop.
- PowerShell `... | Select-Object -First N` **kills the upstream native process** the moment
  N objects have arrived (pipeline stop). A Godot run filtered that way dies mid-startup with
  exit −1 and looks exactly like a renderer crash. Redirect to a file and filter after the
  process exits instead.

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
