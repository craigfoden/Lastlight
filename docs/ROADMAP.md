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
| 15 | **Camps: something to do with a day** — the day loop was walk out, hold E, walk back; all the danger and every decision lived at night. Guarded sites now sit out in the wilds: a footprint of ruined walls stamped by WorldGen, a leashed garrison posted by the host through the WaveDirector's spawner, and a `LootCache` at the middle that refuses to open while a guard still stands. New `CampType` resource (three tiers — Bandit Camp / Ruined Hamlet / Warband Barrow, 10 sites), new `Marauder` enemy kept out of the wave roster, new `Enemy.Behavior.GUARD` with a leash and an `Enemy.died` signal, `ResourceNode` grown three extension points so the cache reuses the whole harvest RPC lane rather than inventing one. **Ambient Radiant Essence cut 15 % → 4 %**: tier-III towers are now gated on clearing a barrow instead of on walking far enough. HUD prompt, minimap camp rings, `--auto-camp` / `--auto-camp-clear`. | ✅ 2026-08-15 (green solo + host/client, zero errors/warnings; **numbers wholly unplayed** — see gaps) | Craig + Claude |
| 16 | **Visual overhaul: pixel art** — the game's whole look, in three parts. (1) **Art is text**: a single shared palette plus every character/decal authored as rows of palette characters in `tools/art/art_sprites.gd`, compiled to PNGs by a `--script` generator that also forces the import settings pixel art cannot survive (`detect_3d/compress_to`), with a contact-sheet previewer for reviewing it. All 15 sprites redrawn — 3 classes, 3 enemies, 5 decals, shadow, wisp, 2 projectiles. (2) **The world is pixelated too**: `PixelRender` sets the root Viewport's `SCALING_3D_MODE_NEAREST` and derives the scale from the live camera so one sprite texel = one rendered pixel, so meshes and sprites share one grid — no SubViewport, so no node paths moved. (3) **Procedural animation**: `SpriteAnimator` adds a walk bob, facing flip, hit flash and attack recoil from already-replicated state, at zero network cost. Also closed: projectiles get per-ability textures (`AbilityType.projectile_texture`) instead of every shot being the same yellow dart, and the dead `BuildingType.texture` field and the whole placeholder SVG folder are gone. | ✅ 2026-08-15 (green solo + host/client incl. mixed classes, zero errors/warnings; **art quality is placeholder and deliberately so** — see gaps) | Craig + Claude |
| 17 | **Five carried gaps, closed** — a deliberate sweep of the small open items rather than one new system. (1) **The ground is drawn**: repeating 32×32 village-turf and wilds-dirt tiles authored in the same text pipeline as the sprites (`ArtSprites.TILES`), sampled by `ground.gdshader` at one texel per rendered pixel with a per-tile brightness jitter to break the repeat — the largest smooth surface left in frame is gone. (2) **Every run gets its own map**: `WorldGen.generate(seed)` replaces the baked constant and generation on `_ready`; the host rolls a seed, sends it on connect, and holds a joiner's spawn until they acknowledge having built it (`--world-seed=N` pins one). (3) **Talents can be spent**: a screen off the main menu, the first caller of `Profile.unlock_talent()`, plus three talents per class on keys that are safe to keep local. (4) **The hotbar prices per cell**: slots grey on `net_cost` at the hovered cell, so a tower you can afford only because of the wall's refund no longer looks unaffordable. (5) **A `Buildings` registry**, replacing the exported array inside `game.tscn` — which is what finally let the class-select screen name the tower your class unlocks. | ✅ 2026-08-16 (green solo + host/client, zero errors/warnings; ground checked in-frame at the village and out in the wilds) | Craig + Claude |
| 18 | **Everything that didn't need a playtest** — a deliberate sweep of every carried gap whose acceptance is a log line or a screenshot rather than a human verdict, done in one session on Craig's call. (1) **Map-generation depth**: the seed now chooses the map's *shape* — 2–4 approach openings rolled per run with a cleared corridor each (the openings left `game.tscn`, because a lane has to be cleared by the pass that decides where it runs), a Voronoi partition of the wilds into four new `BiomeType`s that reweight what grows there and tint the ground to match, and per-run richness and camp counts. The rarity-by-distance bands are deliberately *not* rolled. (2) **Ground detail**: a third hand-authored tile, drawn as beaten roads along every approach corridor and as a trodden ring at the village boundary — the first thing in the world to say where the safe zone ends — plus a dithered biome border so the partition doesn't read as a seam. (3) **Enemies break buildings** when the way round is more than `breach_ratio` times the way through: mazing still works, sealing the map or walling a camp's doorway no longer does. (4) **Separation steering**, which immediately found that every camp garrison had been standing in one stacked cell since session 15 (`_post` vs `_home`). (5) **Regrowth**: felled nodes come back a share per dawn and emptied camps are reoccupied, both host-only and both down existing RPC lanes. (6) **Frame animation** as a pipeline — strip PNGs, `hframes`, a walk cycle derived from the single authored pose until real art lands. (7) Six small gaps: run-end → talents link, menu Quit, enemy death fade, deployable replay to late joiners, the hotbar's fully-upgraded mispricing, and a host-side cast rate limit. | ✅ 2026-08-16 (green solo + host/client, zero errors/warnings; every new number is unplayed — see gaps) | Craig + Claude |
| 19 | **Landmarks: a world you can navigate by sight** — the wilds had biomes but no *features*: one stretch of thicket looked exactly like the next, so the map was navigable by minimap and by nothing else. New `LandmarkType` resource + `Landmarks` registry (the `Camps` shape), five landmarks placed per run by WorldGen with **biome affinity** — the country decides which features it can hold, so a run with no leyfield has no standing stones and *that* is the feature — each stamped into its own reserved clearing so the scatter cannot bury it. Minimap diamonds, and a HUD place banner naming the country underfoot and the landmark you are at, which also closes session 18's "nothing in the UI ever names a biome". Deliberately **non-mechanical** — see gaps. | ✅ 2026-08-21 (green solo + host/client with matching layout hashes, zero errors/warnings; all three landmark shapes checked in-frame) | Chris + Claude |
| 20+ | **Content & polish** (pattern-following) — enemy variety; gear tiers; balancing; menus; audio; juice; GodotSteam transport swap (test AppID 480) + Steam invite/lobby flow; art swap-in | free | — |

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
- Night-assault enemies attack the tower; daytime ROAM enemies attack players (session 5) but
  never cross into the safe zone / light (session 6). ~~Enemies still never attack buildings.~~
  Fixed session 18: any enemy breaks a building when its path is more than `breach_ratio`
  (2.5×) the straight line to its goal. Walls are still a maze — they are just no longer an
  absolute.
- ~~Night approach openings are fixed at ±1584 even though the map now reaches ±3000~~ Fixed
  session 18: 2–4 openings per run, rolled around the whole compass on a 46–58 cell radius
  band. The outer ring beyond that is still deliberately daytime-only territory.
- ~~Enemies stack on the same cell (no separation steering) — crowds overlap visually.~~ Fixed
  session 18 (and the fix found a worse stacking bug in the camp garrisons — see the decision
  log). Measured: with 47 monsters alive, no pair closer than the separation radius.
- ~~A kicked night-joiner sees "The host ended the game" rather than "locked during night
  assaults" — a proper refusal message needs an auth-stage handshake (polish).~~ Fixed
  session 10 without the handshake: the host RPCs the reason first and kicks on a grace
  timer as backstop.
- Enemy spawn data carries the original spawn position; a day-phase late joiner briefly sees
  live enemies at stale positions until the first sync tick (~0.05 s). Harmless today (enemies
  despawn at dawn and night joins are refused), noted for completeness.
- ~~No talent-spending UI yet — points accrue and show on the run-end screen;~~ Fixed
  session 17: a talent screen off the main menu, three talents per class. Still open: the
  screen is reachable only from the menu, and the run-end screen does not link to it.
- ~~Ability cooldowns are client-enforced (host checks ownership only)~~ Softened session 18:
  the host now refuses a cast that arrives sooner than `host_cooldown_floor` (60 %) of the
  authored cooldown. It cannot be 100 % — talents shorten cooldowns and are never networked —
  so this turns "a modified client can fire every frame" into "a modified client can fire a bit
  faster than intended", which is the right amount of paranoia for a friends' co-op game.
- ~~No class-select screen (Ranger hardcoded as the only class)~~ Fixed session 12: menu →
  class select → game, built from `Classes.ALL`, with `--class=<id>` for scripted runs.
  ~~Still open: in-flight projectiles/traps are not replayed to late joiners.~~ Half-fixed
  session 18: **traps are** replayed (they sit there for their whole lifetime, so a joiner
  would otherwise walk over an invisible one). Projectiles are deliberately **not** — a shot is
  airborne for well under a second, which is shorter than the join handshake that would carry
  it, so a replayed one would arrive somewhere it no longer is. (Player HP + downed/respawn
  landed in session 5.)
- ~~Every projectile in the game shares one mesh and material, so an Arcane Bolt and an arrow
  are the same yellow dart.~~ Fixed session 16: `AbilityType.projectile_texture`, and the
  projectile is a billboard sprite rather than a mesh. Bow Shot and Piercing Arrow share the
  default arrow deliberately — they *are* both arrows.
- ~~The class-select screen lists a class's stats and its three abilities but not its
  exclusive tower — there is no `Buildings` registry to enumerate.~~ Fixed session 17:
  `Buildings.ALL` is now the single roster and the screen lists the exclusive tower with its
  cost, stats and the names of its upgrade tiers (not their prices — those are netted
  against what they replace, so a gross number on this screen would be a lie).
- ~~`BuildingType.texture` is dead in the 3D game — nothing reads it.~~ Removed session 16,
  along with the three `.tres` references and the whole `assets/sprites/placeholder/` folder,
  which the pixel art superseded.
- Bulwark (the Paladin's self-buff) is verified to cast, expire, and tint the sprite; the
  damage-reduction *arithmetic* was reviewed but never measured against a known hit. Worth an
  assertion if buffs multiply (session 12).
- Dodge grants no invulnerability yet — it's a burst move only. Host applies damage and does
  not know a client's dodge state; i-frames need a cheap dodge-state signal to the host (polish).
- ~~World seed is a baked constant: every run has the same map.~~ Fixed session 17 (the seed),
  and the generation *depth* it did not buy was fixed session 18: biomes, 2–4 rolled openings,
  per-run richness and camp counts. The *landmarks* it did not buy
  landed session 19: five features tied to biomes, each in a reserved clearing, named by a HUD
  banner and marked on the radar. Still open, and now the obvious next layer: **there is no
  terrain**. Everything the generator places is an object standing on a flat plane — no river,
  no cliff, no elevation, nothing impassable — so nothing divides the map into regions you have
  to go *around*, and a landmark is something you walk past rather than something that shapes
  the walk.
- Mini-map is functional but untuned (fixed range, no zoom, no fog); verified headless only —
  give it a visual pass when real art lands.
- ~~Depleted resource nodes never respawn~~ Fixed session 18: `Regrowth` brings back a share
  of the felled nodes each dawn, at reduced stock, and only onto cells that are still free and
  still safe to block (`BuildManager.can_grow_at`).
- ~~Menu has no dedicated Quit button; window close only.~~ Fixed session 18.
- **Upgrade tier numbers are a first draft nobody has played** (session 14). The open questions,
  in order: can you reach Bright Essence early enough for tier II to matter on a night that
  isn't the last one, and is Radiant so far out that tier III is theoretical? The dial is the
  tier costs, not the map. Also unjudged: whether upgrading one tower beats building a second,
  which is the decision the whole feature exists to create.
- Upgrade tiers are marked by a floating emissive orb over the tower (gold = II, violet = III)
  plus a slightly bulkier base. Tier III reads clearly in-frame; **II vs III has never been seen
  side by side**, and an orb over a tower looks a little like a wisp resource node. Placeholder
  art — revisit when real art lands.
- ~~The hotbar greys a slot on its **full** cost, so a tower you can only afford because of
  the refund from what's already on the cell looks unaffordable but still places.~~ Fixed
  session 17: `BuildController` publishes the hovered cell and the bar prices every slot
  through `net_cost` at it. ~~One rough edge left: a tower already at its final tier greys
  its slot on the top tier's full price.~~ Also fixed, session 18: a cell holding something
  this click could not replace is priced as bare ground, so the grey means exactly one thing.
- Main menu is developer-grade (join by IP). Fine until the Steam lobby session.
- **Camp numbers are wholly unplayed** (session 15). In order: is a 3-wretch bandit camp worth
  a third of a 3-minute day; is a 5-marauder barrow survivable at all before the tower has
  towers; and — the one the whole feature turns on — does cutting ambient Radiant to 4 % make
  tier III *earned* or *unreachable*? The dial for the last one is the 4 %, not the camp loot.
- ~~Camps never repopulate~~ Fixed session 18: a site emptied `repopulate_days` (3) ago is
  reoccupied with a full garrison and a restocked cache — the same price for the same reward,
  you just get the chance again. A cleared-but-unlooted site is left alone.
- ~~Guards ignore buildings, like every other enemy.~~ Fixed session 18 by the same breach rule
  the horde uses: seal a camp's doorway and the garrison takes the wall down.
- ~40 guards stand host-simulated from the first frame of every run. Still cheap, but session
  18 added a per-monster separation pass that asks every other monster where it is (staggered
  to ~10 Hz, and skipped by a squared-distance test). It is the first thing in the game whose
  cost is quadratic in enemy count, and the number to watch if camps ever multiply.
- Camp footprints are stamped from two placeholder meshes (palisade, hut) picked per cell, so
  every camp is architecturally the same ruin in a different order. Tier is readable from the
  garrison and the cache, not from the buildings. Revisit when real art lands.
- **The pixel art is placeholder and should be replaced** (session 16). It is coherent, it
  reads at gameplay distance, and it is not the work of an artist — Claude hand-placed every
  pixel. The *pipeline* is the deliverable: swapping in real art means dropping PNGs of the
  same dimensions into `assets/sprites/pixel/` (or editing the text and regenerating), and
  nothing else changes. Weakest first: the Marauder's axe reads as a cleaver, the Mage's arms
  are stubs, and the undead still read as green people more than as corpses.
- ~~**No frame animation**~~ Half-fixed session 18: the *pipeline* is done — a sprite may be
  authored as several pixel maps, they compile to a strip, and `SpriteAnimator` walks it. What
  is still open is the **drawing**: no character has a hand-drawn walk cycle, so every one of
  them uses the generator's derived two-step (one leg lifted a pixel). It reads as walking at
  gameplay distance and it reads as a stopgap on the contact sheet. Also still true: the bow
  never draws and a swing never swings — attacks are carried by the recoil alone.
- ~~No death animation: enemies vanish on death.~~ Fixed session 18: the corpse fades and sinks
  for `death_fade` (0.5 s) before the host frees it. The network implication turned out to be
  nothing — everything that counts monsters already tests `hp > 0`.
- Buildings, towers, trees and rocks are still smooth meshes — they *read* as pixel art only
  because the whole 3D buffer is rendered low-res and nearest-upscaled. That works well, but
  it means their silhouettes are still modelled, not drawn, and no amount of sprite work will
  change their shapes (session 16).
- ~~The ground is a flat untextured shader plane, which is the largest remaining smooth
  surface in frame.~~ Fixed session 17: two hand-authored 32×32 tiles, blended by the same
  village→wilds gradient the shader always painted. Still open: it is *one* tile per zone
  with no paths, no rock, no transition detail, and nothing marks where the safe zone ends.
- A cleared cache leaves the camp standing and empty for the rest of the run — there is no
  "looted" state on the site itself beyond the minimap ring turning green.
- **Talents are unbalanced and untested by a human** (session 17). Nine talents, three shapes,
  all flat multipliers on the same three numbers — deliberately dull, because the interesting
  ones (max hp, damage) are exactly the ones the local-only model forbids. The open question is
  whether a talent tree can be interesting at all under that constraint, or whether talents are
  the feature that finally forces profile state onto the host.
- A joining client now waits on the host's seed before it builds anything, so **a joiner sees an
  empty world for a moment longer than before** — measured in packets, not seconds, but on a
  bad connection it is a visible blank. The HUD's "connecting" overlay covers it (it now lifts
  when the world is built rather than when the transport connects) (session 17).
- ~~The talent screen is reachable only from the main menu.~~ Fixed session 18: the run-end
  screen offers a "Spend Talent Points" button, shown only when there is something to spend.
- ~~The ground is one tile per zone with nothing marking where the safe zone ends.~~ Fixed
  session 18: a third tile drawn as roads along every approach corridor and as a trodden ring
  at the safe radius. Still open: no paths *between* places (camps are not connected to
  anything), and no rock, water or transition detail inside a biome.

## Known gaps carried out of session 18

- **Every number in session 18 is unplayed**, and they are unusually load-bearing because
  several of them change how the game is *played* rather than how it looks. In rough order of
  how badly a human verdict is needed:
  1. `Enemy.breach_ratio` = 2.5 and wall hp = 90. Together they decide whether mazing is still
	 worth doing. Too low a ratio and walls stop working at all; too high and the exploit is
	 back. Neither has been seen by a player.
  2. Openings: a run with four approaches spreads the same living-cap across four lanes, which
	 may be *easier* rather than harder. `opening_count_max` is the dial.
  3. `Regrowth.regrow_share` (22 % a dawn) and `repopulate_days` (3). The point was that a
	 seven-night run should not end with a strip-mined map — but regrowth that outpaces
	 harvesting removes the reason to walk further out, which is the thing camps exist for.
  4. Biome weights and densities: an ashfield is deliberately a poor place, and a run whose
	 nearest country is all ashfield may simply be a bad run.
- Biome colour reads clearly in the band around the village and barely at all far out in the
  wilds, because the wilds are genuinely dark by design and the tint is multiplicative. That
  is arguably correct — you cannot see the colour of the ground at night — but it means a lot
  of the biome work is only visible on the walk out.
- The scatter uses a hard Voronoi border while the ground shader dithers it over ~5 cells, so
  right at a boundary the trees belong to one biome and the ground to a mix of both. Deliberate
  (borders interleave), but nobody has looked at whether it reads that way.
- ~~Nothing in the UI ever *names* a biome. The data carries a `display_name` and a description
  and no screen shows either.~~ Fixed session 19: a HUD place banner names the country underfoot
  and the landmark you are at, bright for a beat when it changes and quiet after. Still open:
  the `description` on both `BiomeType` and `LandmarkType` is still shown nowhere — the banner
  has room for a name and no more.
- A breaching enemy walks straight at the building in its way, ignoring the pathfinder. If
  something solid sits between it and that building it will grind against it until the recheck
  timer picks a different target. Not seen in testing; the geometry that would cause it (a
  prop directly between a monster and the wall it chose) is rare and self-correcting.

## Known gaps carried out of session 19

- **Landmarks are dark, because the wilds are dark.** The daylight bubble means a landmark 40
  cells out is a silhouette by day and nearly nothing at night, so most of this session's work
  is legible on the walk out and barely at all once you are deep in it. The same complaint the
  biome tints have. It is arguably correct — you cannot see across a dark wood — but a feature
  whose entire job is being visible from a distance is worth a second look once the playtest
  says whether the bubble's radius is right at all.
- **The meshes are placeholders and read as primitives.** Every landmark is boxes, cylinders
  and a torus, exactly like the rest of the world's geometry, so they are *big* rather than
  *distinctive*. The crag and the standing stones survive that best (a spire and a ring are
  shapes); the elder tree is a large ordinary tree and the bone field's ribs read as pale
  hoops. Session 16's note applies unchanged: silhouettes here are modelled, not drawn, and no
  sprite work will change them.
- **The numbers are unplayed, as usual, but cheaply reversible.** In order: `site_count` puts
  two crags and two broken spires in every run, which may be one too many of each for something
  that is supposed to be singular; `landmark_separation` (14 cells) has never been tested
  against a map that is short of room; and `sight_radius` (14–16 cells) decides how early the
  banner claims you have arrived somewhere, which is the one number a player will actually
  notice being wrong.
- Landmark pieces are solid, so they bend enemy paths like any boulder. Nothing is placed with
  that in mind and the corridor rule keeps them off the approaches, but no run has been watched
  with a horde crossing a bone field, and a 9x9 clearing ringed with solids near a lane is a
  shape the pathfinder has not been stress-tested on.
- The banner names a landmark by proximity alone — stand behind a hill you cannot see over (if
  we ever have hills) and it will still claim you are there. Fine today; it is a line to
  revisit the moment anything blocks line of sight.
- Nothing connects landmarks to anything. The carried "no paths *between* places" gap is
  untouched: camps and landmarks are still unlinked points, and the ground shader still draws
  roads only along the approach corridors and the village ring.

## Post-v1 parking lot

Endless mode · found-loot variety · more classes · consoles (porting house) · public lobbies (never?)
