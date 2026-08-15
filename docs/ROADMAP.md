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
| 9 | **3D port, phases 1–8** — see `docs/PORT_PLAN.md` on the branch; claim one phase per session (phase 1 = renderer decision, phase 3 = the multiplayer risk-killer). Main stays 2D and shippable until phase 8 flips the main scene. | ⏳ Chris — phase 1 ✅ 2026-07-13 (renderer: Forward+), phase 2 ✅ 2026-07-14 (world shell & WorldGen3D; tower shadows night-only — see decision log), phase 3 ✅ 2026-07-14 (player + multiplayer smoke passed — 3D transform replication works, the port is downhill), phase 4 ✅ 2026-07-14 (harvest chain green solo + host/client; slim Hud3D — the 2D HUD is typed to 2D classes and couldn't carry over, see decision log), phase 5 ✅ 2026-07-14 (building on the XZ grid — path rule, costs, refunds, hotbar all green solo + host/client). phase 6 ✅ 2026-07-14 (Craig, taking over from Chris — enemies/waves/combat/survival/run-end green solo + host/client; night join refusal pulled forward; tower node returned to origin for distance parity, see decision log). Craig is now on a Mac: the owed phase-1 matrix ran there (Metal/M3 Pro — Forward+ correct, 115–145 fps) and `project.godot` is flipped to Forward+. phase 7 ✅ 2026-07-14 (Craig — WorldLight3D sun/ambient/tower-pool/billboard tints with dusk-dawn crossfade, Minimap3D radar, drop shadows; omni shadows refused on Metal too, phase-6 matrix read corrected). phase 8 ✅ 2026-07-14 (Craig — flipped, 2D layer + proto deleted, 3D classes took the plain names; full suite green). **Merged to main 2026-07-14 on Craig's call — the 2-player human playtest (PLAYTEST.md) is still owed and now runs against main.** Scripted visual pre-flight 2026-08-10 (Chris) cleared PLAYTEST's frame-level look checks and caught the owed Chris/Vulkan night-shadow check failing: the night pool floor rendered black on Windows/Vulkan Forward+ too, so shadowed omnis are now vetoed on every stack (see decision log). Still ⏳ — the human feel/tension/pacing session is what remains | Chris, Craig + Claude |
| 10 | **Playtest-prep UX pass** — proper night-join refusal message (app-layer refusal RPC before the kick, verified in a 3-instance smoke); "press E" harvest prompt; hover tooltips on build hotbar + ability bar (new `description` on BuildingType/AbilityType, stats composed from the same fields the game runs on); sell mode: visible [X] Sell hotbar button, orange hover highlight, refund preview from the shared `BuildingType.refund()`. Tooltip hover + sell-mode feel are untestable headless — they're on the playtest checklist. | ✅ 2026-07-15 | Craig + Claude |
| 11 | **Balance & behaviour pass** (playtest feedback, Chris's call) — roamers wander instead of loitering on the light edge; daytime survivors conscripted into the night assault instead of burned off at dusk; towers upgrade walls in place (net cost, wall refunded); days cut 5→3 min; harvesting pays on **felling**, not per chop (flat 4, same chop count); wall 1→2 wood, sentry/turret +1 of each; mob hp doubled and damage +1 | ✅ 2026-08-10 (numbers unjudged by a human — the playtest still owes a verdict on night-1 winnability) | Chris + Claude |
| 12 | **Class roster & the Paladin** — the session-4 class pipe was never joined up at either end: nothing set `Network.local_player_class` and `player.tscn` hardcoded the Ranger, so the roster knew your class and your character didn't. `Classes` registry; class carried in spawn data; **the host now defers a joiner's spawn until their class is in the roster** (it used to spawn inside `peer_connected`, before the client's registration packet arrived); dedicated class-select screen + `--class=<id>`; two new ability kinds (MELEE_ARC, SELF_BUFF); Paladin kit + exclusive tower | ✅ 2026-08-15 (green solo + host/client, incl. a mixed-class party; Paladin numbers are a first draft nobody has played) | Chris + Claude |
| 13 | **The Mage** — third class, built deliberately as a test of session 12's "add a class = a .tres + a preload" recipe: what the data carried, and where it didn't. Verdict: the claim holds for classes and not for abilities, and never distinguished them — the class, tower, card, gating and XP were genuinely zero code; the two abilities wanting *new behaviour* were not. Both were paid by widening existing kinds rather than adding new ones (MELEE_ARC now roots; a deployable with `tick_damage` burns instead of springing). Arcane Spire is the first building that costs essence | ✅ 2026-08-15 (green solo + host/client across all three classes; numbers unplayed) | Chris + Claude |
| 14 | **Tower upgrades, and a sink for the dead essences** — three-tier upgrade lines for all four towers (Sentry/Turret/Brazier/Spire), built as `BuildingType` resources chained by a new `upgrades_to` and hidden from the hotbar by `placeable = false`. No new input mode and no new keys: you hold the base tower's hotbar slot and click a tower already standing, and `BuildManager.resolve_placement` walks it one tier up its line — the session-11 wall→tower replacement path with its rule widened, so upgrades needed no new sync at all. Tier II costs **Bright Essence** and tier III **Radiant Essence**, which before this session were harvestable from the outer rings and bought *nothing whatsoever*. Ghost turns gold over a legal upgrade; the hotbar hint quotes the netted price; base-tower tooltips spell out the whole line. The host now logs what it actually charged. | ✅ 2026-08-15 (green solo + host/client, zero errors/warnings; **numbers wholly unplayed** — see gaps) | Craig + Claude |
| 15+ | **Content & polish** (pattern-following) — enemy variety; gear tiers; per-run map seeds + map-generation depth; balancing; menus; audio; juice; GodotSteam transport swap (test AppID 480) + Steam invite/lobby flow; art swap-in | free | — |

## Known gaps carried out of session 1 (fold into upcoming sessions)

- Gamepad movement is mapped but untested with a physical pad (session 1 recap).
- ~~No "press E" interact prompt near harvestables — players must know.~~ Fixed session 10:
  the HUD shows "E  Harvest <material>" whenever a harvest would land.
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
- ~~A kicked night-joiner sees "The host ended the game" rather than "locked during night
  assaults" — a proper refusal message needs an auth-stage handshake (polish).~~ Fixed
  session 10 without the handshake: the host RPCs the reason first and kicks on a grace
  timer as backstop.
- Enemy spawn data carries the original spawn position; a day-phase late joiner briefly sees
  live enemies at stale positions until the first sync tick (~0.05 s). Harmless today (enemies
  despawn at dawn and night joins are refused), noted for completeness.
- No talent-spending UI yet — points accrue and show on the run-end screen; `Profile.unlock_talent()`
  works but nothing calls it. Session 5 menu work.
- Ability cooldowns are client-enforced (host checks ownership only) — add a host-side rate
  limit if cheating ever matters.
- ~~No class-select screen (Ranger hardcoded as the only class)~~ Fixed session 12: menu →
  class select → game, built from `Classes.ALL`, with `--class=<id>` for scripted runs. Still
  open: in-flight projectiles/traps are not replayed to late joiners. (Player HP +
  downed/respawn landed in session 5.)
- Every projectile in the game shares one mesh and material, so an Arcane Bolt and an arrow are
  the same yellow dart. The deployables' equivalent was fixed in session 13 (`decal_texture` on
  the ability, per-instance material); projectiles want the same treatment.
- The class-select screen lists a class's stats and its three abilities but not its exclusive
  tower — there is no `Buildings` registry to enumerate, and `buildable_types` lives on a node
  in `game.tscn`. The build hotbar's tooltip still says "Paladin exclusive." (session 12).
- `BuildingType.texture` is dead in the 3D game — nothing reads it. The older buildings still
  set it; the Paladin's brazier does not. Harmless, but the field should go when someone is
  next in those files (session 12).
- Bulwark (the Paladin's self-buff) is verified to cast, expire, and tint the sprite; the
  damage-reduction *arithmetic* was reviewed but never measured against a known hit. Worth an
  assertion if buffs multiply (session 12).
- Dodge grants no invulnerability yet — it's a burst move only. Host applies damage and does
  not know a client's dodge state; i-frames need a cheap dodge-state signal to the host (polish).
- World seed is a baked constant: every run has the same map. Per-run variety needs a seed
  synced before WorldGen runs (map-generation work).
- Mini-map is functional but untuned (fixed range, no zoom, no fog); verified headless only —
  give it a visual pass when real art lands.
- Depleted resource nodes never respawn; day-phase respawn/scatter belongs to map-gen work.
  (Softened by session 5: there are ~130 nodes now, so running dry mid-run is unlikely.)
- Menu has no dedicated Quit button; window close only.
- **Upgrade tier numbers are a first draft nobody has played** (session 14). The open questions,
  in order: can you reach Bright Essence early enough for tier II to matter on a night that
  isn't the last one, and is Radiant so far out that tier III is theoretical? The dial is the
  tier costs, not the map. Also unjudged: whether upgrading one tower beats building a second,
  which is the decision the whole feature exists to create.
- Upgrade tiers are marked by a floating emissive orb over the tower (gold = II, violet = III)
  plus a slightly bulkier base. Tier III reads clearly in-frame; **II vs III has never been seen
  side by side**, and an orb over a tower looks a little like a wisp resource node. Placeholder
  art — revisit when real art lands.
- The hotbar greys a slot on its **full** cost, so a tower you can only afford because of the
  refund from what's already on the cell looks unaffordable but still places. Pre-existing for
  wall→tower (session 11); upgrades inherit it, and it bites harder now that every tier is a
  net-cost placement. Fix is to tint per hovered cell, which means the hotbar needs the ghost's
  cell — deliberately not done in session 14.
- Main menu is developer-grade (join by IP). Fine until the Steam lobby session.

## Post-v1 parking lot

Endless mode · found-loot variety · more classes · consoles (porting house) · public lobbies (never?)
