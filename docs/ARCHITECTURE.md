# Lastlight — Architecture & Decision Log

This file is the **running decision log**. Read it before making architectural calls; append to
it (with rationale and date) after making one. Parallel sessions must not silently diverge.

## Engine & project baseline (2026-07-12)

- **Godot 4.7-stable** (standard build, GDScript). Pinned — everyone uses the same version.
  Verified latest stable at kickoff; upgrades are a deliberate, logged decision.
- Renderer: **GL Compatibility** — the recommended choice for 2D, runs everywhere.
- Display: 1280×720 base window, `canvas_items` stretch, `expand` aspect. Pixel art at
  32×32 tiles; `snap_2d_transforms_to_pixel` on; default texture filter **nearest**.
  Camera zoom 2× on players. Provisional — revisit when real art lands.
- Docs ground truth: a shallow clone of `godotengine/godot-docs` at branch `4.7` lives in a
  **sibling folder** (`../godot-docs`). Never trust memory for Godot APIs — grep the clone.

## The multiplayer model (2026-07-12)

**Host-authoritative co-op.** One player hosts; their instance is the single source of truth
for game state. Clients render, predict, and *request*. There is no dedicated server and no
plan for one — infrastructure cost stays zero.

- The host's peer id is always **1** (Godot guarantees this for the server).
- Transport: **ENetMultiplayerPeer** in development (default port 24565), swapped for
  GodotSteam's `SteamMultiplayerPeer` at release. Only `autoload/network.gd` may know which
  peer implementation is active.
- Solo play is a session of one: the solo player hosts a server nobody joins. No offline
  special case — this is what keeps co-op from being a retrofit.

### State sync: three lanes

Pick the lane by the *shape* of the state, and record new state types here as they appear.

1. **Continuous state** (positions, the day/night clock) → **MultiplayerSynchronizer**,
   replicating a few times per second; receivers advance the value locally in between
   (dead reckoning) so motion and clocks look smooth.
2. **Discrete state** (material pool, resource node stock — anything event-like) →
   host-only mutation + a **reliable `authority` RPC broadcasting the new value** to everyone
   (`call_local` so the host takes the same code path). Late joiners get the same RPCs as a
   snapshot push (`host_send_snapshot(peer_id)` convention).
3. **Client requests** (harvest; later: build, attack, join-mid-run) → **`any_peer` RPC to the
   host** (`rpc_id(1, ...)`), which **validates before applying** — range checks, stock checks,
   phase checks. Never trust the client (per the official multiplayer docs' security guidance).

### RPC & authority conventions

- `request_*` — client → host, `@rpc("any_peer", "call_local", "reliable")`. First line guards
  `if not multiplayer.is_server(): return`. Validate sender via
  `multiplayer.get_remote_sender_id()` and game rules before acting.
- `_sync_*` / `_receive_*` — host → everyone, `@rpc("authority", "call_local", "reliable")`.
  Carry the *resulting* state, not the delta, wherever the state is small (trivially consistent).
- `host_*` — plain functions that only the host may call (assert or early-return on clients).
- RPC-bearing nodes must exist at the **same path on every peer** — spawn with
  `force_readable_name` / deterministic names, or place them statically in the scene.

### Exception: player movement is client-authoritative (2026-07-12)

Each player node is named after its owner's peer id, and that peer holds multiplayer authority
over it (`_enter_tree` → `set_multiplayer_authority(name.to_int())`). Players simulate their own
movement locally; a MultiplayerSynchronizer replicates `position`/`velocity` outward.

**Why:** host-simulated movement makes every non-host player feel input latency on every step —
unacceptable for an action game, and client-side prediction with reconciliation is a rewrite-scale
complexity we don't need for friends-only co-op. This is the standard Godot co-op carve-out.
**Boundary:** movement *only*. Anything gameplay-critical the player does (harvest, build, hit)
is still a `request_*` RPC the host validates — including a server-side range check against the
(client-reported) position. Accepted trade-off for friends-only play; revisit only if cheating
ever matters (public lobbies, which are out of scope).

### Join-in-progress: connect from *inside* the game scene (2026-07-12)

Clients load `game.tscn` first and only then open the connection (the menu just records
host/join intent on the `Network` autoload). **Why:** replication packets (spawns, synchronizers)
race scene loading if you connect from the menu and switch scenes afterwards — the packets
target nodes that don't exist yet. Connecting from inside the loaded scene makes that race
impossible, and gives day-phase mid-run joining for free. The host pushes lane-2 snapshots on
`peer_connected`.

### Player spawning: custom `spawn_function` (2026-07-12)

`MultiplayerSpawner.spawn_function` builds player nodes from host-chosen spawn data
(`{peer_id, position}`) identically on every peer. **Why:** testing showed the "add_child on
host + auto-replicate" path applies spawn state *after* the client's `_ready`, and with
client-authority movement the client's default `(0,0)` can win over the host's chosen spawn
point. Explicit spawn data has no such race.

## Scene & code organization (2026-07-12)

- Per the official best-practices docs (required reading, `../godot-docs/tutorials/best_practices`):
  many small single-purpose scenes; **signals up, calls down**; scenes own their data; parents
  mediate siblings (e.g. `game.gd` routes `ResourceNode.harvested` → `TeamMaterials.host_add`);
  dependencies are injected (`hud.setup(day_night, team_materials)`), never grabbed upward.
- Autoloads only for genuinely global, self-contained systems. Currently exactly one:
  **`Network`** (connection lifecycle + player roster). Run state lives in the game scene, not
  in singletons — a new run is a fresh scene.
- Groups as cheap interfaces (per docs): `players`, `resource_nodes`. Declared in scene files.
- Folders: feature-based (`scenes/player/` holds the scene + its script). Assets by category in
  `assets/`, placeholder art quarantined in `assets/sprites/placeholder/`.
- Collision layers: **1 = world/static** (terrain, resource nodes, tower), **2 = players**.
  Players don't collide with each other (mask 1 only). Reserve 3 = enemies, 4 = projectiles.

## Data-driven content (2026-07-12)

Game content is **`.tres` resource files**, not code: `MaterialType` now; towers, enemies,
classes, abilities to follow the same pattern. Ids are `StringName`s and are **save-data stable**
— never rename a shipped id; `display_name` is the changeable one.

## Dev/test hooks (2026-07-12)

User CLI args (after `--`) enable scripted multiplayer verification — keep them working:
`--host`, `--join=<ip>`, `--name=<n>`, `--quit-after-sec=<s>`, `--auto-harvest`, `--fast-cycle`.
Key lifecycle events `print` with a `[System]` prefix so two-instance smoke tests can be
asserted from logs. These hooks are cheap, guarded, and stay in the shipped build (harmless).

## Building system (2026-07-12, session 2)

- **Grid**: 32 px cells (`BuildManager.CELL_SIZE`), one cell per building for now (footprints
  later if needed). `AStarGrid2D` over a 100×100-cell region, orthogonal movement only.
- **Never-block-the-path**: placement hypothetically marks the cell solid, then requires a path
  from *every* spawn-opening cell to the tower's **heart cell** (a reserved, walkable cell at
  the tower base — the cell enemies will path to in session 3). Any opening cut off → rejected.
- **Derived state, not synced state**: occupancy and the pathfinding grid are rebuilt locally on
  every peer from the replicated `Buildings` container (child enter/exit hooks) and from
  replicated resource-node stock (`depleted` frees the cell). Nothing to desync; clients tint
  the placement ghost with the exact rules the host enforces (`placement_error()` — one
  function, two jobs).
- **Buildings replicate via MultiplayerSpawner** with a custom spawn function
  (`{type_id, cell}`), names derived from the cell (`Building_x_y`) so RPC paths match.
  Late joiners get placed buildings from the spawner's replay — no snapshot code needed.
- **BuildingType .tres** is the whole definition: id, cost dict, texture, and attack stats
  (walls are just `attacks = false`). `class_id` field exists but is unenforced until classes
  land (session 4). **Selling refunds full cost** (materials are shared; friction adds nothing).
- **Cosmetic-fx pattern**: the host applies damage instantly, then broadcasts an *unreliable*
  `_show_shot` RPC; every peer draws a local projectile tween. Gameplay never depends on fx.
  Real dodgeable projectiles come with player combat (session 4) if design wants them.
- Training dummies stand in for enemies until session 3: group `"enemies"`, duck-typed contract
  `hp` + `host_take_damage()` + `host_send_snapshot()` — real enemies must keep it.

## Night assault (2026-07-12, session 3)

- **Enemies are host-simulated**: the host runs pathfinding (BuildManager's grid,
  `path_to_heart()`), movement, and attacks; clients get position from a MultiplayerSynchronizer
  and hp via the discrete-state RPC lane. Repath on `BuildManager.grid_changed` — mazes update
  under the horde's feet. Enemy kinds are `EnemyType` .tres resources on the WaveDirector.
- **Spawn-function injection**: enemies need live node refs (build manager, tower). Spawn data
  carries only serializable ids; each peer's spawn function injects its *own local* instances.
  Pattern to reuse for anything spawned that needs scene refs.
- **WaveDirector** (host-only logic): waves scale `base + per_night·(n−1) + per_extra_player`,
  spawn through the opening markers on a timer, and **dawn burns all leftovers** (fiction: the
  amplified sunlight) — nights are self-contained, no lingering state.
- **Run lifecycle**: tower hp zero → host broadcasts `_end_run(false)`; surviving the final
  night → `_end_run(true)`. Chests v1 = shared-pool material grant per player at each dawn
  (per-player gear loot arrives with gear tiers). XP formula is a placeholder shown on the
  run-end screen; session 4's profile banks it. Necromancer *boss fight* is session-5 content;
  session 3's loss condition is the descent.
- **Day-phase-only joining** is enforced by the host kicking night joiners in `peer_connected`
  (app layer). ENet's `refuse_new_connections` was tried and rejected — see GOTCHAS.

## Classes, abilities & meta-progression (2026-07-12, session 4)

- **ClassType / AbilityType .tres**: a class = sprite, speed, dodge stats, and three ability
  slots; an ability = cooldown + a `kind` (PROJECTILE with damage/speed/range/pierce, or
  DEPLOYABLE with root/lifetime). Exclusive towers point at the class via
  `BuildingType.class_id` — a building belongs to exactly one place, never listed twice.
- **Casting flow**: owner client enforces its own cooldowns and sends `request_cast` to the
  host (ownership-checked); the host broadcasts a spawn RPC; **every peer spawns an identical
  local projectile/trap and only the host's copy deals damage** (host's enemies are the
  authoritative ones). Cooldowns are client-enforced — accepted friends-co-op trade-off;
  a host-side rate limit is the upgrade path if it ever matters.
- **RPC authority lesson**: `@rpc("authority")` on a *player-owned* node authorizes the owning
  CLIENT, not the host — host broadcasts get rejected. Host→all RPCs on player nodes must be
  `any_peer` + an explicit sender-is-host guard. (Server-owned nodes keep plain `authority`.)
- **Deployables** get deterministic names (`Trap_<peer>_<seq>`) so the host's consume RPC
  resolves on every peer. In-flight projectiles/traps are NOT sent to late joiners (sub-minute
  lifetimes, day-phase joins only — acceptable).
- **Profile (autoload)**: local-only meta-progression in `user://profile.cfg` — account XP,
  per-class XP, unlocked talents. Levels on a sqrt curve; one talent point per class level
  past 1. Run end banks XP on every peer into *its own* profile; talents apply only to the
  character the local peer simulates, so meta needs zero networking.
- **TalentType .tres**: effects are a modifiers dictionary (`&"move_speed_mult": 1.1`);
  consumers (player.gd) define the keys. Framework + one sample talent; spend-points UI is a
  session-5 item.

## World population, daytime threats & player survival (2026-07-13, session 5)

- **Deterministic world generation (`WorldGen`, derived-not-synced)**: a fixed
  seed drives one `RandomNumberGenerator`; every peer runs the same `_ready`
  and builds an identical scatter of resource nodes and scenery. Nothing about
  the layout is networked — same principle as the build grid. Because the nodes
  land at identical paths (`Res_%d`, `Prop_%d`) on every peer, the existing
  client→host harvest RPC resolves untouched (verified: a client's harvest lands
  on the host's matching node). Resource *stock* still syncs via ResourceNode's
  discrete-state RPC lane. **Why not a MultiplayerSpawner?** Resource nodes are
  static-equivalent content, not runtime spawns; deterministic generation gives
  late joiners the world for free (they generate it before connecting) with zero
  spawn traffic. **Trade-off:** the seed is a baked constant, so every run has
  the same map. A per-run seed must be *synced before generation* — deferred to
  real map-generation work.
- **A clear corridor guarantees connectivity.** WorldGen never places a
  grid-solid thing (resource or solid prop) on the row `y == 0`; the spawn
  openings and the tower heart all sit on that row, so a straight walkable lane
  always exists before anyone builds. This lets scattered obstacles register as
  grid-solid (enemies path around them via A*) without any risk of sealing the
  map at generation time.
- **Solid vs decorative scenery.** `SceneryProp` (one scene) is solid or decor
  by an export. Solids join group `"obstacles"`; `game.gd` collects their cells
  and passes them to `BuildManager.setup` as permanent scenery cells (same
  channel as the tower footprint — never cleared). Decor drops its collision
  entirely. Enemies collide physically (layer 1) as a backstop to A*.
- **Bigger safe zone is a radius, not just art.** `WorldGen.safe_radius` (the
  enlarged VillageGlow matches it visually) keeps solid props and *all* monster
  activity out of the village ring: roamers won't spawn inside it and deaggro at
  its edge (`Enemy._in_safe_zone`). The village is a genuine haven.
- **Daytime threats reuse the night machinery.** `WaveDirector` now runs a
  second loop: during the day it tops a small roamer population (scaled per
  player) back up on a timer, spawning `Enemy`s with `Behavior.ROAM` outside the
  safe zone. Roamers wander via A* and chase/attack the nearest exposed player;
  they are cleared at nightfall so the night assault stays self-contained. One
  spawner, one enemy scene, a behavior flag in the spawn data.
- **Player HP is host-authoritative on a client-authoritative node.** Movement
  stays client-authored; hp/downed/revive/respawn are decided by the host (it
  simulates the enemies). Because a player node's authority is the owning
  *client*, host→all state broadcasts use the `any_peer` + sender-is-host guard
  pattern (NOT `authority`) — the same carve-out projectiles use (see GOTCHAS).
  The host runs survival logic for *every* player via `set_process(is_server())`
  (movement still simulates only on the owner). Respawn repositioning is an RPC
  to the owning peer, which moves *itself* (it holds position authority). Downed
  players are revived by a living teammate in range, else recalled to the village
  on a timer. Verified across two instances: downed, respawn, and revive all fire
  with no RPC-authority errors.

## Playtest feedback pass — feel, danger & QoL (2026-07-13, session 6)

Eight items from the first real playtest. All verified headless: import clean (zero
errors/warnings), solo host run, and a host + one client run (harvest RPC chain, both players
spawned, day/night cycled — no RPC-authority errors).

- **Never build on a body.** `BuildManager.placement_error()` now rejects a cell any player
  stands on ("Someone is standing here"), iterating group `"players"` and comparing
  `world_to_cell`. Runs on every peer (positions are replicated) so the client's ghost tint and
  the host's gate agree — same one-function-two-jobs pattern as the rest of placement. Closes a
  known session-1 gap (buildings could trap a player).
- **Player is the top sprite.** The project had no y-sort/z_index at all; players drew *under*
  buildings and enemies purely by tree order. Fix: a flat `z_index = 20` on the Player root
  (children inherit via `z_as_relative`). Deliberately not full Y-sorting — the ask was "player
  always visible", and a fixed high z-band delivers that without the per-frame sort cost or the
  scene restructure YSort containers would need. Revisit if depth-sorting becomes a broader need.
- **Daytime monsters lurk in the dark, never enter the light.** "The light" = the existing
  `safe_radius` (no new light system — cheapest thing that matches the mental model). ROAM
  behaviour already aggroed only within `aggro_range` and deaggroed when a player re-entered the
  safe zone; the missing piece was that a *chasing* roamer could physically cross the boundary
  (the safe zone isn't a solid in the A* grid). Added a movement clamp in `Enemy._advance_path`:
  for ROAM only, if the next step would land inside the safe zone, stop and drop the path.
  ASSAULT is exempt — the night horde is *meant* to march through the village to the tower.
- **Nights are a continuous, ramping stream, not a fixed count.** `WaveDirector` no longer
  computes a per-night total. It spawns until dawn on a self-rescheduling one-shot timer whose
  interval eases from `spawn_interval_start` → `spawn_interval_end` across the night (via
  `time_in_phase / phase_length`) and shortens per night (`interval_scale_per_night`). A living-
  ASSAULT cap (`max_alive_base` + per-night + per-extra-player) keeps it fair-but-relentless:
  thin the horde and more pour in, up to the cap. Verified the ramp (spawn intervals shrink) and
  the cap (holds at 10 on night 1 until defenders kill). Daytime roamers are unchanged in kind,
  just spread wider (`roamer_spawn_max_radius` 1300 → 2400) to populate the larger dark.
- **Map ~2×.** `WorldGen.world_extent` 1500 → 3000, `mid_radius` 1000 → 2000, grid
  `grid_half_extent` 50 → 100 (200×200 cells), `Ground` polygon and scatter counts (resources
  130 → 380, scenery 170 → 460) scaled to keep density up; mini-map `world_range` 720 → 1000.
  **Night spawn openings stay at ±1584** (not pushed to the new edge): enemy approach time is a
  pacing lever, and a ~58 s trek from the far edge would gut the "dangerous from dusk" feel. The
  doubled outer ring is daytime exploration/gathering territory instead — dangerous by roamer,
  empty at night. No camera limits exist (camera just follows the player), so a bigger world
  needed no camera work.
- **Removal with a per-building refund fraction.** Selling used to refund 100 % of everything.
  Added `BuildingType.refund_fraction` (data-driven, no magic numbers): walls keep the 1.0
  default (full refund), towers set 0.5. `request_sell` floors the refund (no free rounding-up).
  The removal control (`X` over a building) already existed but was undiscoverable — added a
  controls hint row to the build bar spelling out select/place/cancel/remove + the refund split.

## 3/4 top-down view pass (2026-07-13, session 7)

**Decision: the game presents in 3/4 top-down ("fake perspective", Zelda/Stardew style), not
isometric.** The square logic grid stays exactly as it was; depth comes from Y-sorting plus art
conventions. **Why:** placement precision is the core verb of a tower defense, and screen-
aligned square cells are the most readable grid there is. True 2D isometric was rejected for a
permanent ~2–3× art cost (two faces per prop, diagonal character facings, diamond tiles), a
harder mouse-to-cell story, and the classic multi-cell sorting problem — while most of what iso
buys (volume, depth) is available in 2D via Y-sort + front-face art. If we ever want the real
iso look, the modern route is 3D with a fixed ortho camera, i.e. a different project phase, and
nothing in this pass forecloses it.

- **Y-sort chain.** `y_sort_enabled` on `Game` and every world container (`World`, `WorldGen`,
  `Players`, `Buildings`, `Enemies`). Nested Y-sorted CanvasItems merge into one sort space, so
  players, enemies, props, and buildings all interleave by Y. UI is untouched: every UI root is
  a `CanvasLayer`, outside the canvas-item sort entirely.
- **GOTCHA that shaped the tree: a CanvasItem under a plain `Node` parent is a "topmost" canvas
  item** (docs: `CanvasItem.get_global_transform`) — it escapes the ancestor Y-sort space.
  `BuildManager` and `WaveDirector` were plain `Node`s holding the `Buildings`/`Enemies`
  containers, so both were retyped to `Node2D` (scripts now `extends Node2D`) purely to keep the
  chain unbroken. NodePaths (and therefore RPC routing) are unchanged.
- **Baseline anchor convention.** Y-sort compares node *origins*, so every standing sprite
  plants its bottom edge 16 px below its origin — the bottom edge of its cell
  (`SpriteAnchor.apply()`, `scenes/world/sprite_anchor.gd`). Applied after texture assignment in
  player/enemy/building/resource node/solid scenery/build ghost. WorldGen now assigns resource
  textures *before* `add_child` so `_ready` anchors against the real texture height.
- **Z-index layers** (Y-sort only orders items on the same z_index): ground −10, village glow
  −9, flat decals −1 (decor scenery, snare traps), the whole sorted world 0, player projectiles
  +1, build ghost 25. Player no longer carries `z_index = 20` (session 6's "player drawn on
  top" fix) — Y-sort now produces the correct answer in both directions: in front when south of
  a prop, tucked behind when north.
- **Art conventions.** Characters and standing props/towers are 32×48, walls 32×40 (top surface
  spills into the cell behind), harvest rocks/boulders stay 32×32 with a lit top + darker front
  face. Decor (grass/bones/rubble) stays a flat 32×32 decal. Characters get a shared
  `shadow.svg` decal at the feet; standing props bake a ground-shadow ellipse into the SVG.
- **Dev hook `--screenshot-after-sec=N`** saves the viewport to `user://screenshot.png` from a
  windowed CLI run — visual passes can now be eyeballed from scripted runs (headless renders no
  frames, so pair it with a normal windowed launch).

## 3D-ortho hybrid prototype (2026-07-13, session 8, branch `3d-ortho-prototype`)

**Decision: evaluate the "3D world + 2D billboard sprites" direction with a look-and-feel
slice before committing to any port. Main stays 2D and playable.** The slice lives in
`scenes/proto3d/` and is launched directly
(`godot --path . res://scenes/proto3d/proto3d.tscn -- --screenshot-at=4,17`).
**Why:** the hybrid keeps hand-drawn character art (3 facings, fast iteration) while the
renderer provides what 2D fakes: a real sun with cast shadows, the glow tower as an actual
light source, and night as absence-of-light instead of a modulate tint.

- **Scale: 1 world unit = 1 grid cell** (= 32 px of 2D art). Sprites at
  `pixel_size ≈ 0.036` so 48 px characters hold their own against meshed trees.
- **Billboards are `shaded = false` + hand-tinted** via `modulate` each frame (a 3D
  CanvasModulate). `shaded` billboards vary by driver — full-bright on some Compatibility
  stacks, double-dimmed on others — so the tint is the single deterministic light path for
  sprites. Sprites near the tower lerp toward its warmth by distance.
- **OmniLight shadows stay OFF on the Compatibility renderer** — with them on, the entire
  lit region renders black (seen on an ANGLE/D3D11 fallback; do not trust omni shadows on
  Compatibility). Directional (sun) shadows work fine and carry the look.
- **Input ports cleanly:** WASD is rotated by the camera yaw (screen-up = world 45°), and
  mouse→cell is `project_ray_origin/normal` intersected with the ground plane, then
  `floori` — the 3D equivalents of the 2D grid math, each ~3 lines.
- **What a real port would keep:** the entire multiplayer architecture (RPCs, host
  authority, sync lanes are node-type-agnostic), `AStarGrid2D` as the logical grid, all
  data-driven `.tres` content. What it replaces: scenes, physics bodies, camera, WorldGen's
  node types, and the HUD's minimap math.
- **Go/no-go:** play the slice (walk the light edge at night, place walls by mouse) and
  decide. If go: port lands as sessions on this branch with the same
  definition-of-done; if no-go: the branch stays as reference and main's 3/4 view remains
  the shipped look.

---

## 3D port phase 1 — renderer decision: Forward+ (2026-07-13, session 9, branch `3d-ortho-prototype`)

**Decision: the 3D port targets the Forward+ renderer (Vulkan). Compatibility remains only
as Godot's automatic fallback, never the target.** Verified on Chris's machine (Radeon RX
Vega M GH + Intel HD 630, 2020-era drivers, tested over an RDP session) with a 4-way matrix
on the prototype scene — {Compatibility/ANGLE, Forward+} × {omni shadows off, on} — using
`--screenshot-at=4,17` (day/night frames) and the new `--omni-shadows` dev flag in
`proto3d.gd`.

**Why:**
- **Omni shadows — the tower light, the heart of phase 7 — are broken on Compatibility and
  correct on Forward+.** On ANGLE/D3D11 the entire lit pool renders solid black, exactly
  Craig's session-8 bug, now reproduced on a second machine and GPU vendor. On Forward+ the
  same frame is the intended look: a warm graded pool with props casting radial shadows
  away from the tower.
- **Forward+ was ~75% faster here**: 55–59 fps vs 32 fps on the identical scene and
  machine — and this is a 2018 iGPU-class GPU on a Vulkan 1.2.131 driver from 2020. The
  "Compatibility is kinder to low-spec machines" assumption failed on our actual
  low-spec machine.
- **Choosing Forward+ strands nobody**: since Godot 4.4, Forward+ falls back
  Vulkan → D3D12 → Compatibility automatically (godot-docs
  `tutorials/rendering/renderers.rst`). Worst case a machine gets today's Compatibility
  look. Consequence: **omni-light shadows must be gated at runtime** — check the active
  rendering method and keep `shadow_enabled = false` when it is `gl_compatibility` —
  never assumed on.
- **Baseline parity confirmed**: with omni shadows off, ANGLE and Forward+ frames are
  near-identical at day and night, so fallback machines regress nothing; they only miss
  the tower-light shadows (and, later, glow/bloom on the gem).

**Still owed:** the same matrix on Craig's machine before phase 2 flips
`renderer/rendering_method` in `project.godot` (merge-sensitive — call it out in the
commit). Repro:
`$godot --rendering-method forward_plus --path . res://scenes/proto3d/proto3d.tscn -- --screenshot-at=4,17 --quit-after-sec=20 --omni-shadows`
vs the same with `--rendering-driver opengl3_angle` instead of the method override; shots
land in `user://proto_shot_*.png`. Driver fact found on the way: native OpenGL
(Compatibility's first-choice driver) hard-crashes at context creation over RDP on this
machine — see GOTCHAS in CLAUDE.md.

---

## 3D port phase 2 — world shell & WorldGen3D (2026-07-14, session 10, branch `3d-ortho-prototype`)

**Decision: the 3D world lives in parallel scenes (`scenes/game3d/`, `scenes/world3d/`)
with the 2D WorldGen's logic deliberately duplicated, not shared.** A common base class
would touch 2D files main still ships from; the 2D copy retires wholesale in phase 8.

- **Cell-for-cell layout parity with the 2D map, by construction.** WorldGen3D runs the
  identical rng call sequence, and every radius is the 2D pixel value / 32 — an exact
  binary scaling that commutes with float rounding (multiply-by-2^k, sqrt, and floor all
  preserve it), so every scatter lands in the same grid cell as 2D. Same seed → the map
  players know.
- **Determinism smoke: the layout hash.** `[WorldGen3D] ... layout hash N` digests every
  spawned node (name:material:cell). Identical hash across peers ⇒ the NodePath RPC
  contract (GOTCHAS) holds. Verified identical across three separate processes and both
  renderers. (True host+client join lands with phase 3's player port — the hash is the
  world-side half of that smoke.)
- **The `"obstacles"` group contract is kept** (PORT_PLAN open question #2): solid
  SceneryProp3D joins group `"obstacles"`; the phase-5 build-grid port reads it unchanged.
- **Omni-shadow daylight finding — amends phase 1:** with `shadow_enabled` on, the tower
  OmniLight's *entire range box* renders over-darkened in daylight on the Vega M Vulkan
  driver (a dark world-space square; physically impossible — shadowed-from-omni ground
  must equal ground outside the range). It is in the phase-1 `fwd_on` day shot too; phase
  1 eyeballed the night frame, where the artifact has nothing to subtract and the look is
  correct. **Policy: tower-light shadows are night-only**, driven through
  `GlowTower3D.set_light_shadows()` (phase 7 wires it to DayNightCycle), and always off on
  the Compatibility fallback (black-pool bug). Re-evaluate when Craig's machine matrix
  lands. Forward+ remains the right renderer — day and night both render correctly with
  the policy applied.
- Ground plane is visual-only (no collision): the game is top-down, players stay pinned to
  y = 0 — phase 3 either confirms no-gravity movement or adds a floor body then.
- Decor props are flat `PlaneMesh` decals with alpha-scissor materials, lifted 0.01 above
  the ground (the 3D twin of the 2D decal's `z_index = -1`).
- Harvest/hp RPC lanes ported verbatim (`request_harvest`, `_sync_amount`, `_sync_hp`,
  `host_send_snapshot`); ResourceNode3D reads meshes' remaining stock as scale (2D used
  sprite alpha). `game3d.gd` carries a local dev-args parser (screenshot/quit) until the
  real game args port over — same rough edge proto3d has.

---

## 3D port phase 3 — player + multiplayer smoke: the risk is dead (2026-07-14, session 10, branch `3d-ortho-prototype`)

**Verdict: the entire multiplayer architecture ports to 3D unchanged.** Player3D is a
CharacterBody3D with the same owner-authority exception, the same `spawn_function`
explicit-spawn-data pattern, and a MultiplayerSynchronizer replicating `position`/`velocity`
as Vector3 — and the two-instance loopback smoke passed first run: identical layout hash on
both peers, client watched the host's auto-walking player move live
(t=8 → t=14 positions differ on the *client*), clean join/leave, zero errors/warnings.

- **2D data stays px-denominated; 3D consumers convert.** `.tres` resources carry over
  untouched (the plan's rule); speeds divide by `PX_PER_UNIT := 32.0` at the consumer
  (`player_3d.gd`). Phase 8 can re-bake the data to units if the 2D game retires cleanly.
- **`--game3d` CLI flag** (main_menu.gd only — no scene edit): routes a scripted host/join
  into `game3d.tscn`; the menu buttons stay on the 2D game until phase 8 flips the default.
- **FallbackCamera** in game3d.tscn covers the pre-spawn/joining window; the local player's
  rig takes over via `camera.current = true` on spawn. Same rig angles as the prototype.
- Player body: capsule, layer 2 / mask 1 (mirrors 2D), `MOTION_MODE_FLOATING`, velocity
  stays on XZ — no gravity, so the collisionless ground plane from phase 2 is confirmed.
- Unshaded billboards cast no sun shadows — players have no drop shadow yet; that joins the
  phase-7 visual pass (2D used a decal sprite; same trick works as a flat quad).
- Replication-assertion pattern for smokes: host runs `--auto-walk` (local player strolls
  when idle), client runs `--log-players-after-sec=a,b` and the test asserts the remote
  player's position changed between stamps.

---

## 3D port phase 4 — harvest & materials; the HUD "carries over" caveat (2026-07-14, session 10, branch `3d-ortho-prototype`)

**The harvest lane runs end-to-end in 3D with zero logic changes**: Player3D gained the
Area3D interact range (2D's 52 px → a 1.63 u sphere) and `try_harvest`; ResourceNode3D's
ported RPCs did the rest. Smoke evidence, solo and host+client: the host validated a
*client's* harvest using the client player's replicated position (two systems meeting
correctly), stock counted down, the pool broadcast stayed in lockstep on both peers, and
the join-time snapshot delivered the pool to a late joiner. `--auto-harvest` re-enabled
for the 3D scene.

- **TeamMaterials and the Materials registry ported with literally zero changes** — plain
  Node + RefCounted namespace, exactly as the plan promised for the data/logic layer.
- **PORT_PLAN's "HUD CanvasLayers carry over untouched" turned out wrong**: `hud.gd` is
  statically typed to the 2D `Player`/`GlowTower` classes (`_local_player: Player`,
  `setup(..., GlowTower)`), so instancing it in the 3D scene type-errors at runtime, and
  loosening its types would edit the 2D game the plan says not to touch. **Decision: a
  slim parallel `Hud3D`** (same injection style) carrying what phase 4 owns — material
  pool, player count, connecting curtain. Day clock/tower hp/ability bar/minimap join it
  with their systems in phases 6–7; at the phase-8 flip the 2D Hud retires and Hud3D
  becomes just "Hud".
- CLAUDE.md's material recipe pointed at a `TRACKED_MATERIALS` list in hud.gd that no
  longer exists (the registry moved to `Materials.ALL`); fixed in the same commit.

---

## 3D port phase 5 — building on the XZ grid (2026-07-14, session 10, branch `3d-ortho-prototype`)

**BuildManager's grid logic ported verbatim** — AStarGrid2D never knew about rendering.
With `cell_size = 1` and `offset = 0.5`, point paths return cell centers that ARE world XZ
coordinates; consumers lift `(x, y)` → `(x, 0, y)`. `--auto-build` and `--auto-block-test`
are green solo AND host+client: placements validated and spawner-replicated to both peers,
costs/refunds in lockstep, occupied-cell rejection, and the never-block-the-path rule
rejected the sealing wall.

- **BuildingType gains an additive `visual_3d: PackedScene`** (the 2D game ignores it) —
  buildings stay data-driven in 3D: a .tres + a mesh scene under
  `scenes/building3d/visuals/`. Recipe updated in CLAUDE.md, same commit. `attack_range`
  and shot speed stay px-denominated in data; Building3D divides by 32 at the boundary
  (the phase-3 `PX_PER_UNIT` rule).
- **The glow tower moved to world (0, 0, -1)** so its 2×2 base covers the 2D game's
  `TOWER_CELLS` ((-1,-2)…(0,-1)) and the heart cell (0,0) stays walkable at its base —
  the grid contract (and `--auto-block-test` geometry) now matches 2D exactly. Phase 2
  had it centered on the origin, which would have put the heart *inside* the tower.
- BuildController3D picks cells with the prototype's ray-plane trick; a missed ray maps to
  `CELL_NOWHERE` (far outside the region → "Out of bounds"), never to cell (0,0). The
  ghost is a translucent one-cell box for now (placeholder until an art pass).
- BuildMenu3D is a parallel port for the same reason as Hud3D (the 2D menu is typed to the
  2D build classes). Building3D keeps the enemy-targeting contract (group `"enemies"`,
  `hp`, `host_take_damage`) — it dry-fires until phase 6 delivers targets.

---

## 3D port phase 1 addendum — the matrix on Craig's machine, now a Mac (2026-07-14, session 11, branch `3d-ortho-prototype`)

**The pending phase-1 matrix ran on Craig's new machine (macOS, Apple M3 Pro, Metal) and
Forward+ passed: `project.godot` is flipped to `forward_plus`** (mobile fallback
`"mobile"`). The 4-way probe — {Compatibility, Forward+} × {omni shadows off, on},
day/night screenshots — showed Forward+ rendering the intended night (dark world, warm
tower pool, radial prop shadows) at 115–145 fps windowed. Compatibility also ran without
the Windows black-pool bug (macOS ANGLE sits on Metal, not D3D11), but the target stays
Forward+ per the phase-1 decision; omni shadows remain runtime-gated for fallback stacks.

- **macOS suspends rendering for fully-occluded windows**, which broke the probe twice
  before it ran clean: scripted windowed runs launched from a shell can sit behind other
  windows, the engine stops presenting frames, and the screenshot hook silently saved a
  stale early frame (two shots 13 s apart, byte-identical). Two fixes, both landed:
  the three `--screenshot-*` hooks now `await RenderingServer.frame_post_draw` before
  `get_image()` (the documented capture idiom — a stalled await is now a *visible* miss
  instead of a silently wrong frame), and scripted visual runs on macOS pass Godot's
  `--always-on-top` so the window keeps rendering. GOTCHAS entry added.

---

## 3D port phase 6 — enemies, waves, combat, survival (2026-07-14, session 11, branch `3d-ortho-prototype`)

**The whole threat layer is parallel ports with the 2D scheduling and RPC lanes verbatim**:
WaveDirector3D (continuous night stream + day roamers, same tunables, geometry in cells),
Enemy3D (CharacterBody3D FLOATING at y = 0, billboard sprite, XZ waypoints lifted from the
grid paths), Projectile3D / SnareTrap3D (Area3D at chest height / ground-decal + squat
cylinder trigger), Player3D combat + survival (aim/cast/dodge, hp/downed/revive/respawn),
and the run-end flow. `RunEndScreen` and `DayNightCycle` instanced **unchanged** — the
first 2D scene files reused as-is in the 3D game. Smokes green solo AND host+client:
kit kills, trap roots, tower battered, defeat, victory, downed→respawn, late-join
snapshots (players/enemies/tower), and night join refusal.

- **GlowTower3D's node moved back to the origin; its column/gem/light/collision children
  carry the z = -1 offset instead.** Phase 5 moved the *node* to (0, 0, -1) for the
  footprint, but verbatim enemy/safe-zone ports measure `tower.global_position` — the 2D
  tower node sits at the origin, and with the node at (0, 0, -1) an enemy at the heart
  cell is 1.58 u away, outside its 1.5 u (48 px) attack range: enemies would path
  perfectly and never swing. Node at origin restores 2D distance parity everywhere;
  children at z = -1 keep the footprint/heart geometry phase 5 fixed.
- **Night join refusal came forward from phase 7 to 6** — the rule guards the *night
  assault*, which exists as soon as waves do. Same app-layer kick as 2D.
- Enemy billboards skip `alpha_cut` (players use DISCARD): the hp fade needs alpha blend.
  Player survival tinting reuses the 2D modulate scheme minus the downed slump rotation
  (meaningless on a Y-billboard); phase 7's tint-by-light must compose with it.
- `--fast-cycle`'s 6 s night is too short for enemies to cross ~46 cells to the tower —
  combat smokes use `--cycle=8:60`-style pacing instead. Same math as 2D (the map is the
  same 50-cell crossing); noted here because the first smoke "passed" with zero combat.

---

## Template for new entries

```
### <Short title> (YYYY-MM-DD)
<The decision.>
**Why:** <rationale, alternatives rejected>
```
