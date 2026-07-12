# Lastlight — Game Design (canon)

Working title: **Lastlight**. A 1–4 player co-op, 2D top-down fantasy roguelite mixing survival
and tower defense, built around a day/night loop. This document is canon: sessions build what is
written here and do not re-litigate it. The full original brief lives in
[GAME_KICKOFF_PROMPT.md](GAME_KICKOFF_PROMPT.md).

## Fiction

The players' village is protected by a central **glowing tower** that amplifies sunlight.
A **necromancer** has covered the world in darkness; only the village stays safe — and only
while the sun is up.

## The loop

| Phase | Length* | What happens |
|---|---|---|
| **Day** | ~5 min | Venture out to scavenge materials and loot. Near the village is safe; further out = thicker darkness, harder monsters, rarer materials. Distance = risk = reward. |
| **Build** (during day) | — | Spend the shared material pool on walls, towers, and gear upgrades in the village. **A valid path to the glowing tower must always remain** — mazing yes, full blocking no (validated against pathfinding). |
| **Night** | ~3 min | The tower can't amplify the sun; waves attack through the map's openings. Players fight alongside their towers. Tower destroyed = the necromancer descends = run lost. Each survived night: one chest per player. |

\* All timers are tunable constants.

## Run structure

- Survive **7 nights** to win. Night 7: **the necromancer assaults the village himself (boss fight)**.
- Full run target: **~60 minutes**.
- Run XP granted by how far you get. Endless mode is a post-v1 stretch goal.

## Maps

Procedurally generated to a standard: village at the center, danger and rarity increasing with
distance. **The difficulty setting controls how many openings** lead into the village (easiest = 1).

## Multiplayer rules

- 1–4 players; **solo is first-class** (waves, costs, rewards scale with player count).
- Friends-only invites (Steam overlay; join-by-IP in dev). No public lobbies at launch.
- Mid-run join allowed **during the day phase only**; locked during night assaults.
- Two players may pick the same class.

## Economy

- **Shared team pool** for building AND gear costs; each player's gear is their own.
- Materials: 2 basics (**wood**, **stone**) + 3 rarity tiers of essence found further out
  (**Faint / Bright / Radiant Essence** — tier names chosen session 1). Inventory kept generic
  for later expansion.
- Gear: **linear tiers per slot** (weapon / armor / trinket), upgraded at the village; higher
  tiers need rarer materials. Found-loot variety is post-v1.

## Towers

**Shared basic towers + 2–3 class exclusives each.** Data-driven (.tres): adding a tower is a
resource + sprite, not new code.

## Launch classes

**RANGER — ranged skirmisher (BUILD FIRST — the vertical-slice class)**
- Basic: aimed bow shot · Ability 1: Piercing Arrow (line skill-shot) · Ability 2: Snare Trap
  (deployable root — day: catch threats while scavenging; night: hold a choke) · Dodge roll
- Exclusive towers: **Arrow Turret** (single-target DPS), **Trap Launcher** (lobs snares at chokes)

**PALADIN — holy melee tank/support** (channels the same light as the glowing tower)
- Basic: aimed melee swing · Ability 1: Smite (holy burst) · Ability 2: Consecrated Ground
  (heal allies / damage undead in an area) · Block or short dash
- Exclusive towers: **Blessed Bastion** (wall segment with protective aura), **Radiant Beacon**
  (buffs nearby towers)

**MAGE — AoE elemental glass cannon**
- Basic: aimed magic bolt · Ability 1: Fireball (AoE + burn) · Ability 2: Frost Nova
  (self-centered slow) · Blink instead of dodge
- Exclusive towers: **Flame Brazier** (AoE burn), **Frost Obelisk** (slow aura)

Combat is **action combat**: aimed attacks (mouse / right stick), dodge roll, positioning matters.

## Meta-progression (local profile, separate from run state)

- **Class XP** → class levels → talent points on that class's talent tree
- **Account XP** → account levels → unlocks (new classes/characters)

## Scope strategy

**Vertical slice first**: Ranger only, shared towers + Ranger exclusives, small enemy roster.
Prove the loop is fun solo AND 2-player before adding content. Ship on **Steam (PC) first**;
gamepad-friendly input/UI from day one; consoles later via porting house if the game succeeds.
