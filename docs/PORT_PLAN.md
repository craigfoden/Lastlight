# 3D Port Plan — branch `3d-ortho-prototype`

**Status (2026-07-14): ALL PHASES DONE — this document is history.** Chris ran 1–5,
Craig 6–8. The 3D game IS the game: the menu routes into it, the prototype and the whole
2D layer are deleted, and the 3D classes/folders took over the plain names (`Player`,
`scenes/game/game.tscn`, …). The only piece of phase 8 still open when this was written:
the **2-player human playtest** (docs/PLAYTEST.md, updated for port acceptance) and the
**merge to main**, which waits on it. Post-mortem: the phase-8 entry in ARCHITECTURE.md.

(The "try the slice" prototype this section used to describe was deleted with phase 8 —
`git checkout e04d994~2 -- scenes/proto3d` resurrects it if a renderer probe is ever
needed again; its `--omni-shadows` flag was the phase-1 test harness.)

## Ground rules

- Same `CLAUDE.md` definition of done per phase: zero errors/warnings, works solo AND
  host+client, decisions appended to ARCHITECTURE.md, recap written.
- One phase = one session = one ROADMAP claim. Do them in order — phase 3 exists to kill the
  biggest risk early.
- Merge main into this branch at the start of each session (2D fixes keep landing there).
- Port into **parallel scenes** (`scenes/game3d/`, `scenes/player3d/`, …), don't edit the 2D
  scenes in place. The 2D game must run from main until phase 8.

## What carries over untouched (do not rewrite these)

- The entire multiplayer layer: `Network` autoload, RPC naming conventions, host authority,
  the three sync lanes, `host_send_snapshot` late-join pattern. All node-type-agnostic.
- `AStarGrid2D` as the logical grid — it never knew about rendering. 1 world unit = 1 cell
  (the prototype's scale convention; a cell is no longer 32 px, it's 1.0).
- All data-driven content: `data/**/*.tres`, the material/building/enemy/ability/class/talent
  recipes, `Profile`, `Talents`.
- `DayNightCycle` (plain Node state machine) — only its *consumer* changes (phase 7).
- HUD CanvasLayers — except the minimap transform (phase 7).

## What gets rewritten (the phases)

**Phase 1 — Renderer decision + conventions.** ✅ 2026-07-13 (Chris) — **Forward+**, see
the decision log entry. The black-omni-shadow bug reproduced on Chris's ANGLE stack too;
Forward+ rendered them correctly AND ran ~75% faster on the same old GPU. Conventions
landed in CLAUDE.md (1 unit = 1 cell, ground y = 0, `pixel_size 0.036` unshaded billboards
with hand-driven tint, collision layers 1/2/4/8 mirroring 2D). The owed matrix on Craig's
machine ran 2026-07-14 (now a Mac: Metal / M3 Pro — Forward+ correct and fast, see the
phase-1 addendum in the decision log) and `project.godot` is flipped to Forward+.

**Phase 2 — World & WorldGen.** ✅ 2026-07-14 (Chris) — `scenes/game3d/game3d.tscn` shell
(ground, environment, sun, GlowTower3D with heart + OmniLight) and `world_gen_3d.gd`: same
seed, same rng sequence, radii = 2D px / 32 exactly → cell-for-cell the 2D layout, with
`Res_%d`/`Prop_%d` names intact and a printed **layout hash** as the cross-peer
determinism smoke (identical across processes and renderers). Harvest/hp RPC lanes ported
verbatim; solids join group `"obstacles"` (open question #2: contract kept). New finding,
logged: omni shadows also misrender in *daylight* on Vulkan/Vega M (over-darkened range
box) — tower-light shadows are now night-only via `GlowTower3D.set_light_shadows()`,
which phase 7 wires to DayNightCycle.

**Phase 3 — Player + multiplayer smoke. The risk-killer.** ✅ 2026-07-14 (Chris) — the
risk is dead: Player3D (CharacterBody3D, owner authority, capsule on layer 2, FLOATING
motion, no gravity) with the prototype's camera rig and a Label3D name tag; synchronizer
replicates Vector3 position/velocity through the unchanged `spawn_function` pattern. The
two-instance loopback smoke passed first run — identical layout hashes, client observed
the host's `--auto-walk` player moving live, clean join/leave, zero errors/warnings.
`--game3d` (menu script flag) routes host/join into the 3D scene. Player drop shadows
deferred to phase 7 (unshaded billboards cast none).

**Phase 4 — Harvest & materials.** ✅ 2026-07-14 (Chris) — Area3D interact range on the
player, harvest RPC chain green end-to-end (`--auto-harvest` asserted solo AND
host+client, incl. the pool snapshot to a late joiner). One correction to this plan: the
HUD did NOT Just Work — `hud.gd` is statically typed to the 2D Player/GlowTower classes,
so the port grows a slim parallel `Hud3D` instead (pool + players + connecting curtain
now; clock/tower/abilities/minimap arrive with phases 6-7). TeamMaterials + the Materials
registry did carry over with zero changes.

**Phase 5 — Building.** ✅ 2026-07-14 (Chris) — BuildManager3D carries the 2D grid logic
verbatim (AStarGrid2D, cell_size 1 → paths return world XZ directly); ray-plane picking +
box ghost; Building3D = mesh scene (new additive `BuildingType.visual_3d`) +
StaticBody3D; BuildMenu3D/controller are parallel ports (2D menu is 2D-typed, same as the
HUD). The glow tower moved to (0, 0, -1) so the 2D TOWER_CELLS/heart-cell contract holds.
`--auto-build` and `--auto-block-test` green solo AND host+client, zero errors/warnings.

**Phase 6 — Enemies & waves.** ✅ 2026-07-14 (Craig) — the full threat layer:
Enemy3D/WaveDirector3D with the 2D scheduling verbatim (geometry in cells), abilities as
planned (projectile Area3D at chest height, snare as ground decal + trigger), Player3D
combat + survival, tower damage/defeat/victory/run-end, night join refusal (pulled
forward from 7 — the night exists now). `DayNightCycle` and `RunEndScreen` instanced
UNCHANGED — the first 2D scenes reused as-is. `--auto-fight` and `--hurt-test` green solo
AND host+client. One parity trap found and fixed: the tower NODE must sit at the origin
like the 2D one (children carry the -1 z offset) or verbatim distance checks put the
heart outside enemy attack range — see the decision log.

**Phase 7 — Light as gameplay.** ✅ 2026-07-14 (Craig) — WorldLight3D drives sun
arc/energy/color, sky, ambient, the tower pool (pulsing, night-shadowed where the stack
allows), and the per-frame billboard tint (warm by distance into the pool, composed with
the survival tints by multiplication); dusk/dawn crossfade over the cycle's
`transition_time`; Minimap3D with the world→radar transform (XZ in cells, rotated by the
45° camera yaw so radar-up = screen-up); character drop-shadow decals. All curves are
exports at prototype defaults. Finding: shadowed omnis over-darken their range box on
macOS/Metal too — Metal joined the `set_light_shadows()` refusal list, and the phase-6
matrix claim was corrected in the decision log.

**Phase 8 — Flip & retire.** ✅ 2026-07-14 (Craig) — three commits: (a) the flip — menu
routes host/join into the 3D game, `--game3d`/`--proto3d` flags and the proto button gone,
`scenes/proto3d/` deleted; (b) the 2D layer deleted (game/player/enemy/building/hud/
abilities/world scenes — `day_night_cycle.gd`, `team_materials.gd`, `run_end_screen`
survive, the 3D game instances them); (c) the takeover rename — every `*3D` class and
`*3d` folder/file takes the plain name, data `.tres` paths updated, CLAUDE.md conventions/
recipes/args rewritten for the single game. Full smoke suite green after each commit.
Outstanding: the human 2-player playtest (PLAYTEST.md) → merge to main.

## Known rough edges in the slice (fix in phases, not up front)

No collision anywhere (walk through everything); shambler ghosts through props; dark
grazing-angle patches at the tower's base (light sits directly above the column — move the
light or add a second low fill); `--quit-after-sec` is reimplemented locally in proto3d.gd;
the gem is a placeholder sphere.

## Open questions for whoever runs phase 1

- ~~Forward+ or Compatibility?~~ **Forward+** (phase 1, 2026-07-13): omni shadows correct
  and faster even on our lowest-spec machine; Godot ≥4.4 auto-falls-back to Compatibility
  so nobody is stranded — gate omni shadows off at runtime on the fallback.
- Do scenery obstacles keep the group-`"obstacles"` build-grid contract, or does the 3D
  WorldGen register cells directly?
- Billboards forever, or billboards-now-meshes-later for characters? (Billboards preserve
  the 2D art pipeline — the reason this direction won. Recommend: billboards, revisit only
  after the port ships.)
