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

---

## Template for new entries

```
### <Short title> (YYYY-MM-DD)
<The decision.>
**Why:** <rationale, alternatives rejected>
```
