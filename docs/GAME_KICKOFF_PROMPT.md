# Project Kickoff: **Lastlight** (working title)

Co-op fantasy survival / tower-defense roguelite. You are helping me build this game from
scratch. This document is the complete brief — **every decision is made**; nothing here is open
for re-litigation by a session. Read the whole file before doing anything, then execute the
session plan (section 6).

---

## 1. The game (canon)

A **1–4 player co-op**, 2D top-down fantasy roguelite mixing survival and tower defense, built
around a day/night loop.

**The fiction:** the players' village is protected by a central **glowing tower** that amplifies
sunlight. A **necromancer** has covered the world in darkness; only the village stays safe — and
only while the sun is up.

**Day phase (~5 min):** players venture out to scavenge materials and loot. The area immediately
around the village is safe; the further out you go, the thicker the darkness, the more (and
harder) the monsters — and the rarer the materials. Distance = risk = reward.

**Build phase (during day):** materials are spent on walls, towers, and gear upgrades in the
village. **There must always remain a valid path for monsters to reach the glowing tower** —
mazing is allowed, full blocking is not (placement is validated against pathfinding).

**Night phase (~3 min):** the glowing tower can no longer amplify the sun; waves attack through
the map's openings. Players fight alongside their towers. If monsters destroy the glowing tower,
the necromancer descends and the run is lost. Each survived night rewards each player a chest.

**Run structure:** survive **7 nights** to win; on the final night the **necromancer himself
assaults the village as a boss fight**. Run XP is granted based on how far you get. Endless mode
is a post-v1 stretch goal. Full run target: **~60 minutes** (all timers are tunable constants).

**Maps:** procedurally generated to a standard — village at center, danger/rarity increasing
with distance. **Difficulty setting controls how many openings** lead into the village
(easiest = 1).

**Meta-progression (local profile, separate from run state):**
- **Class XP** → class levels → **talent points** on that class's talent tree
- **Account XP** → account levels → unlocks (new classes/characters)

## 2. Tech decisions (decided — do not re-litigate)

| Decision | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x** (GDScript) | 2D-first, text-based scenes so Claude authors ~90% directly, free/MIT, proven for the genre (Dome Keeper, Brotato) and indie co-op. Chosen over Unity/TypeScript after full comparison. |
| Perspective | **Top-down 2D** | Free roaming, natural build grid, 360° tower coverage. |
| Multiplayer | **Host-authoritative co-op from day one** (Godot high-level multiplayer: MultiplayerSpawner/Synchronizer). Single player = a session of one. | Retrofitting netcode is a rewrite. Host-authoritative keeps infrastructure at zero. |
| Transport | **ENet in development; GodotSteam `SteamMultiplayerPeer` for release** (same API, swap the peer). Steam relay handles NAT traversal — no port forwarding; invites via overlay. Valve test AppID 480 until we buy ours via Steam Direct. | MultiplayerPeer abstraction makes transport swappable; GodotSteam is the mature shipped standard (e.g. Cassette Beasts co-op). |
| Shipping | **Steam (PC) first**; consoles later via porting house if the game succeeds. Gamepad-friendly input/UI from day one. | Keeps a future port cheap without designing for it now. |
| Data-driven content | Towers, enemies, classes, abilities, materials are **resource files (.tres), not hardcoded** | "Add a tower" = add a resource + sprite, not new code. |
| Art pipeline | **Placeholder art now, real art later** from my artist friend. **Pixel art, 32×32 tiles, characters ~32×48 — confirmed by the artist.** One folder per category, one file per sprite, no packed spritesheets until real art arrives. | Grid, camera, and placeholders built to final specs so art drops in without rework. |
| Scope strategy | **Vertical slice first**: Ranger only, shared towers + Ranger exclusives, small enemy roster. Prove the loop is fun solo AND 2-player before adding content. | Co-op adds ~30–50% effort per system; scope discipline is survival. |

## 3. Design decisions (decided — do not re-litigate)

| Area | Decision |
|---|---|
| Win condition | Survive 7 nights; night 7 is a necromancer boss assault. Lose = glowing tower destroyed. |
| Combat | **Action combat**: aimed attacks (mouse / right-stick), dodge roll, positioning matters. |
| Pacing | ~5 min day / ~3 min night per cycle, 7 cycles, ~60 min runs. Tunable constants. |
| Players | 1–4. **Solo is first-class**: waves, costs, and rewards scale with player count. |
| Joining | Friends-only invites (Steam overlay; join code fallback in dev). No public lobbies at launch. |
| Mid-run join | Allowed **during day phase only**; locked during night assaults. |
| Materials | **Shared team pool** for building AND gear costs; each player's gear is their own. Types: 2 basics (wood, stone) + 3 rarity tiers of essence found further out. Inventory system kept generic for later expansion. |
| Gear | **Linear tiers per slot** (weapon / armor / trinket), upgraded at the village; higher tiers need rarer materials. Found-loot variety is post-v1. |
| Tower gating | **Shared basic towers + 2–3 class exclusives each.** |
| Class duplicates | Two players may pick the same class. |
| Launch roster | **Ranger, Paladin, Mage** (details below). More classes = post-launch content. |

### Launch classes

**RANGER — ranged skirmisher (BUILD FIRST — the vertical-slice class)**
- Basic: aimed bow shot · Ability 1: Piercing Arrow (line skill-shot) · Ability 2: Snare Trap
  (deployable root — day: catch threats while scavenging; night: hold a choke) · Dodge roll
- Exclusive towers: **Arrow Turret** (single-target DPS), **Trap Launcher** (lobs snares at chokes)
- Built first because ranged projectiles share tech with towers, and kiting works with simple
  early enemy AI.

**PALADIN — holy melee tank/support** (thematically central: channels the same light as the
glowing tower)
- Basic: aimed melee swing · Ability 1: Smite (holy burst) · Ability 2: Consecrated Ground
  (heal allies / damage undead in an area) · Block or short dash
- Exclusive towers: **Blessed Bastion** (wall segment with protective aura), **Radiant Beacon**
  (buffs nearby towers)

**MAGE — AoE elemental glass cannon**
- Basic: aimed magic bolt · Ability 1: Fireball (AoE + burn) · Ability 2: Frost Nova
  (self-centered slow) · Blink instead of dodge
- Exclusive towers: **Flame Brazier** (AoE burn), **Frost Obelisk** (slow aura)

Each class also gets a talent tree (framework in session 4; talent content is pattern-following
work later).

## 4. About me (the developer)

- I want to **ship this game**, not just prototype it.
- I am **learning game development through this project**. Explain the code you write: brief
  comments where the code needs them; after each system, walk me through how it works and why
  it's structured that way. When I ask "what does this do?", teach — don't just fix.
- My programming background: **professional developer, no game-engine experience.** Don't
  explain language basics (variables, functions, classes) — do explain engine concepts (nodes,
  scenes, signals, the game loop, networking model) and game-dev idioms as they come up.
- Time per week: **~10–15 hrs (serious side project).** Sessions can take on a full system each;
  the core loop (sessions 1–3) should be playable within a few weeks.

## 5. Environment

- Godot: **not installed yet.** First order of business in session 1: verify the actual latest
  stable 4.x release (believed to be ~4.7 as of July 2026 — check, don't assume) and walk me
  through installing it — standard build (not .NET), from godotengine.org. Pin the chosen
  version in CLAUDE.md so all collaborators use the same one.
- Project location: **C:\SourceControl\Lastlight**
- Git: **private repo on my personal GitHub account** from the first commit; collaborators
  invited by username. (Use the `gh` CLI if available; otherwise tell me the manual steps.)
- Docs ground truth: **shallow-clone github.com/godotengine/godot-docs at the branch matching
  our pinned engine version**, into a sibling folder (NOT inside the game repo). Record the
  path in CLAUDE.md.
- Deliberately NOT installed (evaluated and declined — don't add unprompted): **Godot MCP
  servers** (CLI launching + human playtesting cover their value; reconsider if visual bugs
  slip through sessions or error-ferrying gets tedious — hi-godot/godot-ai looked best as of
  July 2026) and **third-party skill libraries** like GodotPrompter (our ARCHITECTURE.md and
  the official docs are the pattern authorities; reconsider only if code quality feels
  unidiomatic).

## 6. Session plan (follow this order)

Strategy: **frontload architecture, leave pattern-following for later.** Multiplayer sync
foundations come first — that ordering is what makes co-op cheap instead of a rewrite. Each
session ends with the project runnable (F5 works) and a short recap of what was built and why.

1. **Session 1 — Networked foundation.** Git repo (private GitHub, Godot .gitignore: exclude
   `.godot/`, commit `.uid` files; copy this brief into `docs/`); Godot project scaffold; write
   `docs/GAME_DESIGN.md` (from this brief), `docs/ARCHITECTURE.md` (esp. the multiplayer model:
   host authority, what syncs, RPC conventions — this file is the running DECISION LOG: read it
   before making architectural calls, append to it after), `docs/ROADMAP.md`, and `CLAUDE.md`
   containing: exact run/verify commands (launch game, headless import check, **how to test
   multiplayer locally** — two instances, one hosts, one joins), the definition of done,
   project conventions, "how to add a tower/enemy/class/material" recipes, a GOTCHAS section
   that grows whenever a session loses time to a pitfall, and the team rules from section 7.
   Then the slice: host/join
   (ENet, local), 2+ synced players moving (keyboard + gamepad), camera, day/night cycle with
   lighting, harvesting a resource node into the shared material pool, HUD (clock + materials).
2. **Session 2 — Building & towers.** Grid placement (host-validated, synced): place/cancel/
   refund, the never-block-the-path pathfinding validation, data-driven tower framework, Arrow
   Turret + one shared basic tower shooting dummy targets.
3. **Session 3 — Night assault.** Data-driven enemy framework, pathfinding to the glowing tower,
   wave scheduler (escalating nights, difficulty-based openings), glowing tower HP, necromancer
   game-over, reward chests, run-end XP screen. **Full loop playable — stop and evaluate fun,
   solo and 2-player, before adding content.**
4. **Session 4 — Class & meta skeleton.** Class resource (abilities + tower list), ability
   system with cooldowns (Ranger kit complete), talent-tree framework, profile save (class XP,
   account XP, unlocks) separate from run save, XP scaling by nights survived.
5. **Session 5+ — Content & polish** (pattern-following): Paladin + Mage kits and towers via the
   recipes, enemy variety, gear tiers, map-generation depth, balancing, menus, audio, juice;
   swap in GodotSteam transport (test AppID 480) + Steam invite/lobby flow; art swap-in when the
   real art arrives.

## 7. Team workflow (MULTIPLE PEOPLE will build this with Claude — these rules go in CLAUDE.md)

- **CLAUDE.md and `docs/` are the shared contract.** They live in the repo so every person's
  Claude sessions inherit the same conventions, recipes, and definition of done. When a
  convention changes, the change lands in CLAUDE.md in the same commit.
- **Sync discipline:** pull before every session, push (or PR) after. If two people are active
  at once, work on branches.
- **One system per person per session.** Claim what you're working on in `docs/ROADMAP.md`
  (mark it in-progress with your name) before starting, release it when done.
- **Never two people in the same scene file.** Godot `.tscn` files merge badly. Mitigations:
  many small single-purpose scenes (already our convention), system ownership above, and treat
  `project.godot` edits (input map, autoloads) as merge-sensitive — mention them in the commit
  message.
- **Decisions go in the log.** Any architectural call not covered by the docs: make it, append
  it with rationale to `docs/ARCHITECTURE.md`, so parallel sessions don't silently diverge.

## 8. Standing working preferences

- Plain-English commit messages; the git history doubles as my learning log.
- Many small scenes/scripts with single responsibilities over clever monoliths.
- Tunable numbers (speeds, timers, costs, damage, wave sizes, day/night lengths) live in
  exported variables or resource files — never as magic numbers in logic.
- Every gameplay feature is built network-aware (host-authoritative) but testable solo.
  **"Done" = works solo AND with a host + one local client.**
- When you finish a system: verify it actually runs (launch via the Godot CLI, capture the
  output; **deprecation warnings count as failures**), then self-review the new code — does it
  follow our conventions and decision log, does it match the official best-practices docs, is
  anything a dated-but-working idiom? Fix what fails; note borderline calls in the session
  recap so I learn too.
- **Never trust memory for Godot APIs** — training data lags the engine. When unsure, Grep the
  local godot-docs clone. Memory is for ideas; the docs clone and the compiler are for facts.
  The clone's "Best practices" section is required session-1 reading and the idiom authority
  after our own decision log.
- If an architectural decision isn't covered here or in the docs, make the call and record it
  with rationale in `docs/ARCHITECTURE.md`.
