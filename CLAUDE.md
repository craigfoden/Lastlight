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
  - Craig (Windows, retired 2026-07-14): `C:\SourceControl\Godot\Godot_v4.7-stable_win64_console.exe`
  - Craig (Mac, current): `/Applications/Godot.app/Contents/MacOS/Godot` — repo lives at
    `/Users/craigfoden/Documents/SourceControl/Lastlight`; no `_console` variant needed on
    macOS, the binary already writes to stdout. `user://` =
    `~/Library/Application Support/Godot/app_userdata/Lastlight`.
  - Chris: `C:\Users\Chris\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`
    (yes, that folder is named `...exe`)
- Docs ground truth: shallow clone of godot-docs, branch `4.7`, in a **sibling folder**:
  `C:\SourceControl\godot-docs`. **Never trust memory for Godot APIs** — training data lags the
  engine. Grep the clone (`tutorials/`, `classes/`). Best-practices section is the idiom
  authority after this repo's decision log.

## Run & verify commands (PowerShell; macOS variant below)

```powershell
# Your _console.exe path — per-machine installs are listed in Environment above.
$godot = 'C:\SourceControl\Godot\Godot_v4.7-stable_win64_console.exe'

# Import assets / regenerate .uid files (run after adding files; also catches import errors)
& $godot --headless --import --path C:\SourceControl\Lastlight

# Launch the game (F5 equivalent)
& $godot --path C:\SourceControl\Lastlight

# Open the editor
& $godot --editor --path C:\SourceControl\Lastlight
```

macOS (zsh) — same commands, different paths. For any windowed run whose screenshots you
intend to read, add `--always-on-top` (see GOTCHAS: occluded windows stop rendering):

```zsh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJ=~/Documents/SourceControl/Lastlight
"$GODOT" --headless --import --path "$PROJ"          # import
"$GODOT" --path "$PROJ"                              # launch
"$GODOT" --always-on-top --path "$PROJ" -- --host --screenshot-at=4,17
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
chain), `--fast-cycle` (10 s days / 6 s nights — pass to *every* instance; too short for
combat asserts, see GOTCHAS), `--grant-materials=wood:10,stone:10` (host cheat for testing
builds), `--auto-build` (scripted place/reject/sell timeline), `--auto-block-test` (walls in
the tower heart; the sealing wall must be rejected by the path rule), `--tower-hp=N` /
`--final-day=N` / `--cycle=day:night` (short runs), `--auto-fight` (stand on the enemy lane
and cast the kit), `--hurt-test` (host chips every player's hp on a timer — exercises
downed/revive/respawn), `--auto-walk` (the local player strolls in a circle when idle),
`--log-players-after-sec=a,b` (print every player's position at those times — assert a
remote player's position changed between stamps to prove replication),
`--class=<id>` (pick a class without the select screen — scripted `--host`/`--join` skip
that screen entirely, so this is the only way to choose one headlessly; unknown ids are
refused loudly and leave the default in place),
`--spawn-at=x,z` (start the local player at that cell — playtest distance-based things
like the glow edge and roamers without the walk),
`--auto-camp` (stand at the nearest camp's cache and try to loot it every 2 s — refused while
the garrison stands, pays out once it doesn't; runs on host *or* client, and pointing it at a
client is how the two-instance smoke proves a client-initiated loot travels the whole chain),
`--auto-camp-clear` (host cheat: kills every camp garrison after 12 s, so the unlock→loot half
can be exercised without a real fight — pair it with `--auto-camp`),
`--no-pixel-render` (render the 3D world at native resolution instead of low-res + nearest
upscale — the A/B for the pixel look; ignored headless, which renders no frames),
`--screenshot-at=a,b` (save the viewport to `user://game_shot_<t>.png` at those times;
windowed runs only — headless renders no frames; on macOS add `--always-on-top`).

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
- **Sprite art is pixel art, compiled from text.** Every character/decal sprite is authored
  as a pixel map in `tools/art/art_sprites.gd` — one character per pixel, keyed by the single
  shared palette in `tools/art/art_palette.gd` — and compiled to PNGs in
  `assets/sprites/pixel/` (characters 32×48 with feet on the last row, everything else 32×32).
  The PNGs are committed; edit the text and re-run the generator, never the PNGs. World
  solids, buildings, and towers remain small mesh scenes under `scenes/world/visuals/` and
  `scenes/building/visuals/`. No packed spritesheets until real art.
- **The 3D world renders at low resolution and is nearest-upscaled** (`scenes/game/pixel_render.gd`,
  decision log 2026-08-15). That is what makes the mesh half of the game read as pixel art
  next to the sprites. The render height is derived live from the active camera so one sprite
  texel lands on one rendered pixel; do not hardcode it, and do not change `pixel_size` on a
  character Sprite3D without understanding that it sets the whole game's render resolution.
- **Billboarded sprites ignore node scale** (`billboard_keep_scale` is false and Sprite3D does
  not expose it). Animate a billboard by moving it, tinting it, or flipping it — never by
  scaling it, which compiles and silently does nothing.
- **World & rendering** (the 3D-ortho hybrid, ported sessions 9–11 — history in
  `docs/PORT_PLAN.md`): renderer is **Forward+** (decision log 2026-07-13). Scale:
  **1 world unit = 1 grid cell** (= 32 px of 2D-era art); ground plane is y = 0; the
  logical grid's XY maps to XZ (cell `(x, y)` → world `(x + 0.5, ·, y + 0.5)`).
  Characters are `Sprite3D` billboards: `pixel_size = 0.036`, `BILLBOARD_FIXED_Y`,
  `shaded = false` — billboards don't react to lights, so `WorldLight` hand-drives their
  `modulate` every frame (compose with it, never overwrite it; survival tints multiply).
  Collision layers: 1 world/solids, 2 players, 4 enemies, 8 hitboxes. `.tres` data stays
  px-denominated — consumers divide by 32 (`PX_PER_UNIT`) at the boundary.
- **The tower light never casts shadows — on any stack.** Every stack we have put eyes on
  renders the shadowed omni's whole range box below ambient, so the pool floor goes BLACK:
  Compatibility, macOS/Metal (cube *and* dual-paraboloid), Windows/Vulkan Forward+ by day,
  and — checked last, 2026-08-10 — Windows/Vulkan Forward+ at night too. The allowlist is
  therefore empty and expressed as `GlowTower.SHADOWED_OMNIS_TRUSTED = false`; keep
  `set_light_shadows()` as the single gate WorldLight drives, and flip the const only for a
  stack whose **night pool has been eyeballed in an actual frame** (decision log
  2026-08-10). Shadowless, the pool reads correctly — we lose radial prop shadows, nothing
  else.

## Recipes

**Add a material:** create `data/materials/<id>.tres` (script `material_type.gd`; set a
never-to-change `id`, a `display_name`, `hud_color`) → add a `preload` to `Materials.ALL`
in `data/materials/materials.gd` (both HUDs build their rows from it) → point `ResourceNode`s
at it via WorldGen's material slots.

**Populate the world (materials & scenery):** the map is scattered at load by `World/WorldGen`
(`scenes/world/world_gen.gd`) from a fixed seed — identical on every peer, never synced. Tune
its exports for density/rarity/amounts (`resource_count`, the ring radii,
`plaza_radius`/`safe_radius` — all in cells). Note `near_amount`/`far_amount` are **chops to
fell**, not income: harvesting pays nothing per chop and banks `yield_per_node` (flat 4) when
the node falls, so those two dials set how *fast* a node pays, and `yield_per_node` sets how
*much*. Or point its slots at new resources:
resource looks are the `tree_scene`/`rock_scene`/`wisp_scene` exports, solids are mesh scenes
in `solid_scenes` (they join group `"obstacles"`), decor is flat 32×32 decal textures in
`decor_textures` (scenes under `scenes/world/visuals/`). Don't hand-place `ResourceNode`s in
`game.tscn` — WorldGen owns the layout. Keep grid-solid content off the `y == 0` row (the
guaranteed opening→heart corridor).

**Add a scenery prop:** solid props are small mesh scenes (add to `solid_scenes` on
`World/WorldGen`; they block movement + register in the build grid via group `"obstacles"`);
decor is a flat 32×32 SVG decal texture (add to `decor_textures`, visual only).
`scenes/world/scenery_prop.tscn` is the shared body; solid vs decor is one export.

**Add a building/tower:** create `data/buildings/<id>.tres` (script `building_type.gd`; stable
`id`, `display_name`, `cost` dict, attack stats — walls just leave `attacks` false;
set `class_id` for class exclusives; set `refund_fraction` for salvage-on-removal — defaults to
1.0/full, towers use 0.5; set `visual_3d` to a small mesh scene under
`scenes/building/visuals/`) → add the resource to `buildable_types` on the BuildManager node
in `game.tscn`. Hotbar, ghost, costs, path validation, removal refund, and sync all follow
from the data. `attacks` also decides **wall replacement**: anything that attacks may be built
straight over anything that doesn't (tower replaces wall, charged at cost minus the wall's
refund), never the reverse — so a new non-attacking building is automatically replaceable and
a new tower automatically replaces walls, with no code change.

**Add an upgrade tier to a tower:** create the tier the same way as any building, then set
`placeable = false` on it (tiers are reached by upgrading, never from the hotbar — and
`placement_error` refuses a direct request for one) and point the tier *below* it at it via
`upgrades_to`. Build the line top-down so each `.tres` can reference the next. Add **every**
tier to `buildable_types` in `game.tscn` regardless — `type_by_id` has to resolve them out of
spawn packets — and give each its own `visual_3d` so a tower's rank is readable on the ground.
In play you hold the base tower's hotbar slot and click a tower already standing: it walks one
tier up its line per click (`BuildManager.resolve_placement`). **Costs are authored gross and
paid net** — the tier states its full price and the player pays that minus the refund for the
tier beneath, so an upgrade is never worse than selling and rebuilding. `net_cost` floors at
zero per material and cannot give change, so if a tier refunds a material the next one doesn't
charge for, that refund is silently lost — spend it back by having the next tier cost 1 of it.

**Add an enemy:** create `data/enemies/<id>.tres` (script `enemy_type.gd`; stable `id`, hp,
speed, attack stats — px-denominated) → add its 32×48 sprite SVG → add the resource to
`enemy_types` on the WaveDirector node in `game.tscn`. Movement, pathing, targeting-by-towers,
hp sync, and wave composition all follow. (Contract: group `"enemies"` + `hp` +
`host_take_damage()` + `host_send_snapshot()`.)

**Add an ability:** create `data/abilities/<id>.tres` (script `ability_type.gd`; `kind` =
projectile, deployable, melee arc, or self buff + that kind's stat group) and slot it into a
class resource. A new *kind* is the one part that needs code: a scene under `scenes/abilities/`
following `projectile.gd` (spawned on every peer, host-only damage) plus an arm in
`Player.request_cast`, the HUD tooltip's `match`, and the class screen's stat line. `Kind` is
append-only — the enum is stored as an int in every `.tres`.
**Prefer widening a kind to adding one.** Fields already read across kinds: `root_duration`
holds for both DEPLOYABLE and MELEE_ARC, and `tick_damage` turns a snare into a burning sigil
that never springs. Two behaviours out of one node beat two nodes — but both branches must
then be reachable from data alone, and **both tooltips must tell the truth**, so widen the
`match` arms in `hud.gd` and `class_select.gd` in the same change. All deployables share one
scene: set `decal_texture` or a new one looks exactly like the Ranger's trap.

**Add a class:** create `data/classes/<id>.tres` (script `class_type.gd`; sprite, `description`,
speed, hp, dodge stats, three ability slots) → add its preload to `Classes.ALL` in
`data/classes/classes.gd` → mark its exclusive towers via `BuildingType.class_id`. That is all:
the select screen builds its own card, spawn data carries the id, and player combat, build
gating, the hotbar filter, the HUD, talents, and XP banking all key off it. `Classes.by_id()`
never returns null — an unknown id warns and falls back to `ALL[0]`.
**But a class is only as data-driven as its abilities are** (learned building the Mage,
session 13). Slotting *existing behaviour* with new numbers is genuinely zero code. Wanting a
behaviour no kind performs yet is code every time, and that is the axis to estimate on — count
the new *behaviours*, not the new classes. Cheapest first: a new number on an existing kind
(Frost Nova = MELEE_ARC that also reads `root_duration`), then a new kind, then a new system.
Give a class a **fourth** placeable and it appears in the hotbar but stays click-only until a
`build_select_4` action is added to `project.godot` (see `BuildController.HOTBAR_KEYS`).

**Add a camp:** create `data/camps/<id>.tres` (script `camp_type.gd`; stable `id`,
`display_name`, `description`, `site_count`, the `radius_min`/`radius_max` ring band in cells,
`footprint_radius`, a `guard_type` + `guard_count` + `guard_leash`, and a `loot` dict) → add it
to `camp_types` on `World/WorldGen` in `game.tscn`. Placement, the ruined-wall footprint, the
cache, the lock, the garrison, the minimap ring and all the sync follow from the data.
**If the guard is a new enemy**, add its `.tres` to `guard_types` on the WaveDirector — *not*
`enemy_types`, which is the night's composition and would draft your guard into the horde.
Camps are stamped **before** the resource/scenery scatter (they are the only content with a
footprint), so adding one shifts the whole map layout — expected, and the startup layout hash
will change on every peer together.

**Add or edit a sprite:** open `tools/art/art_sprites.gd` and draw it as rows of palette
characters (`CHARACTERS` is 32×48, `SMALL` is 32×32; `.` is transparent, and every colour must
already exist in `ArtPalette.COLORS` — a stray key renders magenta and warns rather than
quietly picking a slightly wrong brown). Then:

```powershell
& $godot --headless --path C:\SourceControl\Lastlight --script res://tools/art/generate_art.gd
& $godot --headless --import --path C:\SourceControl\Lastlight
```

A row of the wrong length fails the whole run naming the sprite and row — that validator is
the reason hand-drawing in text is practical at all. The generator also forces the import
settings pixel art cannot survive without (chiefly `detect_3d/compress_to=0`; see its comments
for why), so a new sprite cannot silently get them wrong. To actually *look* at the result,
build a zoomed contact sheet of every sprite on a checkerboard:

```powershell
& $godot --headless --path C:\SourceControl\Lastlight --script res://tools/art/preview_art.gd -- --out=C:\some\where\sheet.png
```

Three rules keep the set coherent, and breaking one makes a new sprite look wrong beside the
others even when it looks fine alone: **one skeleton** (every humanoid shares head rows 4-19,
torso 20-31, legs 32-47, body within columns 7-24 — class is carried by headgear, colour and
weapon), **feet on the last row** (the Sprite3D anchors put row 47 on the ground plane, so a
figure that ends early floats), and **key light top-left**. Outlines: pure black `0` on the
outer silhouette only — use a ramp's dark step for internal lines, or the sprite grows a
black box on its chest. And a held weapon needs an arm of solid pixels reaching it, or it
hangs in space (this is exactly what happened, twice).

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
- **macOS suspends rendering for fully-occluded windows.** A scripted windowed run launched
  from a shell can sit behind other windows, stop presenting frames, and the screenshot
  hooks then capture a stale early frame (two shots taken 13 s apart came back
  byte-identical). The hooks now `await RenderingServer.frame_post_draw` (a stalled run
  misses the save *visibly* instead of saving the wrong frame); pass `--always-on-top` on
  any macOS run whose screenshots you intend to read.
- `--fast-cycle`'s 6 s night ends before enemies can cross the ~46 cells from an opening to
  the tower — a combat smoke on it "passes" with zero combat. Use `--cycle=8:60`-style
  pacing (long night) when asserting on `[Enemy]`/`[Trap]`/`[Tower]` logs.
- A freshly `add_child`ed **Area3D reports no overlaps on its first `_physics_process` tick** —
  it has not been through a physics step yet. Anything that spawns and immediately asks
  `get_overlapping_bodies()` (a melee hitbox, a burst) silently hits nothing while every log
  says the cast fired. Poll for the whole lifetime and track already-hit bodies instead
  (`melee_arc.gd`, `snare_trap.gd`).
- `multiplayer.peer_connected` fires when the **transport** connects, which is strictly before
  the joiner's `Network._register_player` RPC lands — so `Network.players[peer_id]` is still
  empty there. Anything that needs a joiner's name or class must wait for the
  `Network.player_registered` signal (that is why the host defers spawning; see the decision
  log 2026-08-15).
- Sub-resources authored in a `.tscn` (shapes, meshes, materials) are **shared across every
  instance** of that scene unless `resource_local_to_scene` is set. Sizing one from per-instance
  data resizes every other live instance too — build it in code instead.
- **`multiplayer.is_server()` returns TRUE before a peer is assigned.** A joining client runs
  all of `Game._ready()` *before* `Network.join_game()` creates its peer, and a peerless
  `SceneMultiplayer` reports itself as the server — so any `if multiplayer.is_server():` in
  that window fires on clients too. Symptom seen in session 15: 39 `!_has_authority(spawner)`
  errors, then 39 `parent->has_node(name)` collisions as the host's real spawns landed on
  names the client had already taken, then a flood of `!pinfo.recv_nodes.has(net_id)`. One
  cause, three unrelated-looking error storms. Host-only work in `_ready` must be *called from*
  the start-mode branch, not self-guarded before it.
- Godot silently **re-imports any texture it detects being used in 3D with VRAM compression**
  (`detect_3d/compress_to`, default on). It is a lossy block codec: invisible on photographic
  art, ruinous on 32 px art, where it smears every hard edge and mottles the alpha. Worse, it
  happens on the *second* run, so the art appears to break by itself. Every generated sprite
  is forced to `detect_3d/compress_to=0` by ArtGenerator; hand-added textures need it set too.
- `class_name` globals are not registered until the project has been imported, so a
  `--script` tool that references one dies with "Identifier not declared in the current scope"
  on a fresh clone. Run `--headless --import` first.
- Windowed runs on this Windows box log `WASAPI: init_output_device error` and fall back to the
  dummy audio driver — there is no audio device over RDP. Environmental, not a code fault; it
  does not appear in `--headless` runs.

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
