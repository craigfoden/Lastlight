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

---

## Template for new entries

```
### <Short title> (YYYY-MM-DD)
<The decision.>
**Why:** <rationale, alternatives rejected>
```
