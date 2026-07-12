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
| 4 | **Class & meta skeleton** — class resource (abilities + tower list); ability system with cooldowns (Ranger kit complete); talent-tree framework; profile save (class XP, account XP, unlocks) separate from run save; XP scaling by nights survived | free | — |
| 5+ | **Content & polish** (pattern-following) — Paladin + Mage kits and towers via the recipes; enemy variety; gear tiers; map-generation depth; balancing; menus; audio; juice; GodotSteam transport swap (test AppID 480) + Steam invite/lobby flow; art swap-in | free | — |

## Known gaps carried out of session 1 (fold into upcoming sessions)

- Gamepad movement is mapped but untested with a physical pad (session 1 recap).
- No "press E" interact prompt near harvestables — players must know.
- Build placement is mouse-only; gamepad plan: d-pad selects slot, ghost sits on the cell in
  front of the player, accept button places (session 5 polish).
- Buildings can be placed on cells where a player or dummy is standing (they overlap visually
  and can trap the player). Needs an occupancy check against bodies.
- No health bars on dummies (they fade with damage); enemies proper get bars in session 3.
- No grid overlay while in build mode — ghost + tint only.
- Enemies don't attack players or buildings, only the tower; walls are pure maze. (Design ok
  for v1; revisit after fun eval.)
- Enemies stack on the same cell (no separation steering) — crowds overlap visually.
- A kicked night-joiner sees "The host ended the game" rather than "locked during night
  assaults" — a proper refusal message needs an auth-stage handshake (polish).
- Enemy spawn data carries the original spawn position; a day-phase late joiner briefly sees
  live enemies at stale positions until the first sync tick (~0.05 s). Harmless today (enemies
  despawn at dawn and night joins are refused), noted for completeness.
- Depleted resource nodes never respawn; day-phase respawn/scatter belongs to map-gen work.
- Menu has no dedicated Quit button; window close only.
- Main menu is developer-grade (join by IP). Fine until the Steam lobby session.

## Post-v1 parking lot

Endless mode · found-loot variety · more classes · consoles (porting house) · public lobbies (never?)
