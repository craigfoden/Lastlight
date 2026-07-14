# Lastlight — Roadmap & Session Claims

Strategy: **frontload architecture, leave pattern-following for later.** Multiplayer sync came
first because that ordering is what makes co-op cheap instead of a rewrite. Every session ends
with the project runnable (F5 works) and a recap of what was built and why.

## Claim protocol

Before starting work, claim your system here (name + date, mark ⏳ in progress). Release it
(✅ + date) when done and pushed. One system per person per session. Never two people in the
same scene file.

## Sessions

| # | System | Status | Owner |
|---|---|---|---|
| 1 | **Networked foundation** — repo, docs, project scaffold; host/join (ENet, local); synced players (keyboard+gamepad); camera; day/night cycle with lighting; harvesting → shared pool; HUD | ✅ 2026-07-12 | Craig + Claude |
| 2 | **Building & towers** — grid placement (host-validated, synced): place/cancel/refund; never-block-the-path pathfinding validation; data-driven tower framework; Arrow Turret + one shared basic tower shooting dummy targets | ✅ 2026-07-12 | Craig + Claude |
| 3 | **Night assault** — data-driven enemy framework; pathfinding to the glowing tower; wave scheduler (escalating nights, difficulty-based openings); tower HP; necromancer game-over; reward chests; run-end XP screen. **Full loop playable — stop and evaluate fun, solo and 2-player, before adding content.** | ✅ 2026-07-12 (fun eval pending — players can't fight until the session-4 Ranger kit) | Craig + Claude |
| 4 | **Class & meta skeleton** — class resource (abilities + tower list); ability system with cooldowns (Ranger kit complete); talent-tree framework; profile save (class XP, account XP, unlocks) separate from run save; XP scaling by nights survived | ✅ 2026-07-12 | Craig + Claude |
| 5 | **World feel & danger pass** — deterministic world population (denser materials, solid + decorative scenery); enlarged safe zone (radius, not just art); daytime roaming monsters; player HP + downed/revive/village-respawn; corner mini-map (materials, mobs, teammates, home). First pass at making the day loop feel alive and risky. | ✅ 2026-07-13 | Craig + Claude |
| 6 | **Playtest feedback pass** — build-on-body rejection; player drawn on top; daytime monsters lurk in the dark (never cross into the light); continuous ramping night waves (capped, per-night escalation); ~2× map (extra ring = daytime territory); building removal with per-type refund (wall 100%, tower 50%) + on-screen controls hint | ✅ 2026-07-13 | Chris + Claude |
| 7 | **3/4 top-down view pass** — Y-sort depth across the whole world (players tuck behind props/buildings from the north, stand in front from the south); shared sprite-baseline anchor convention; drop shadows on characters; placeholder art restyled with front faces (walls, towers, trees, rocks); `--screenshot-after-sec` dev hook | ✅ 2026-07-13 | Craig + Claude |
| 8 | **3D-ortho hybrid prototype** (branch `3d-ortho-prototype`) — vertical slice of the "3D world + 2D billboard sprites" direction: ortho camera at iso angle, real day/night directional light + shadows, glow-tower OmniLight pool, billboard ranger/shambler, camera-relative WASD, mouse→cell raycast with ghost + click-to-place walls. Menu button + `--proto3d` to launch. | ✅ 2026-07-13 | Craig + Claude |
| 9 | **3D port, phases 1–8** — see `docs/PORT_PLAN.md` on the branch; claim one phase per session (phase 1 = renderer decision, phase 3 = the multiplayer risk-killer). Main stays 2D and shippable until phase 8 flips the main scene. | ⏳ Chris — phase 1 ✅ 2026-07-13 (renderer: Forward+), phase 2 ✅ 2026-07-14 (world shell & WorldGen3D; tower shadows night-only — see decision log). Craig still owes the phase-1 matrix on his machine — the project.godot renderer flip stays pending until then | Chris + Claude |
| 10+ | **Content & polish** (pattern-following) — Paladin + Mage kits and towers via the recipes; enemy variety; gear tiers; per-run map seeds + map-generation depth; balancing; menus; audio; juice; GodotSteam transport swap (test AppID 480) + Steam invite/lobby flow; art swap-in | free | — |

## Known gaps carried out of session 1 (fold into upcoming sessions)

- Gamepad movement is mapped but untested with a physical pad (session 1 recap).
- No "press E" interact prompt near harvestables — players must know.
- Build placement is mouse-only; gamepad plan: d-pad selects slot, ghost sits on the cell in
  front of the player, accept button places (session 5 polish).
- ~~Buildings can be placed on cells where a player is standing (they overlap visually and can
  trap the player).~~ Fixed session 6: `placement_error` rejects a cell any player occupies.
- No health bars on dummies (they fade with damage); enemies proper get bars in session 3.
- No grid overlay while in build mode — ghost + tint only.
- Night-assault enemies attack only the tower (walls stay pure maze); daytime ROAM enemies
  now attack players (session 5) but never cross into the safe zone / light (session 6).
  Enemies still never attack buildings. (Design ok for v1.)
- Night approach openings are fixed at ±1584 even though the map now reaches ±3000 (session 6):
  the outer ring is deliberately daytime-only territory. If night should threaten from the far
  edge too, add more openings or a spawn-distance tunable (map-generation work).
- Enemies stack on the same cell (no separation steering) — crowds overlap visually.
- A kicked night-joiner sees "The host ended the game" rather than "locked during night
  assaults" — a proper refusal message needs an auth-stage handshake (polish).
- Enemy spawn data carries the original spawn position; a day-phase late joiner briefly sees
  live enemies at stale positions until the first sync tick (~0.05 s). Harmless today (enemies
  despawn at dawn and night joins are refused), noted for completeness.
- No talent-spending UI yet — points accrue and show on the run-end screen; `Profile.unlock_talent()`
  works but nothing calls it. Session 5 menu work.
- Ability cooldowns are client-enforced (host checks ownership only) — add a host-side rate
  limit if cheating ever matters.
- No class-select screen (Ranger hardcoded as the only class); in-flight projectiles/traps are
  not replayed to late joiners. (Player HP + downed/respawn landed in session 5.)
- Dodge grants no invulnerability yet — it's a burst move only. Host applies damage and does
  not know a client's dodge state; i-frames need a cheap dodge-state signal to the host (polish).
- World seed is a baked constant: every run has the same map. Per-run variety needs a seed
  synced before WorldGen runs (map-generation work).
- Mini-map is functional but untuned (fixed range, no zoom, no fog); verified headless only —
  give it a visual pass when real art lands.
- Depleted resource nodes never respawn; day-phase respawn/scatter belongs to map-gen work.
  (Softened by session 5: there are ~130 nodes now, so running dry mid-run is unlikely.)
- Menu has no dedicated Quit button; window close only.
- Main menu is developer-grade (join by IP). Fine until the Steam lobby session.

## Post-v1 parking lot

Endless mode · found-loot variety · more classes · consoles (porting house) · public lobbies (never?)
