# 3D Port Plan — branch `3d-ortho-prototype`

**Status (2026-07-14):** phases 1–6 done (Chris 1–5, Craig 6). Craig's machine is now a
Mac — the phase-1 matrix re-ran there and passed, so `project.godot` is flipped to
Forward+. Remaining: phase 7 (light as gameplay) and phase 8 (the flip). Main stays 2D
and shippable until phase 8 flips the switch. Read the session-8 entry in
`ARCHITECTURE.md` (on this branch) before starting: it records the driver gotchas the
prototype already paid for.

**Try the slice first** (10 minutes, judge the night): launch normally and press
"3D Prototype (session 8 evaluation)" on the menu, or `godot --path . -- --proto3d`, or open
`scenes/proto3d/proto3d.tscn` and F6. WASD moves, mouse ghost snaps to cells, LMB places
walls, night falls ~14 s in. `-- --screenshot-at=4,17 --quit-after-sec=20` for scripted
shots; add `--omni-shadows` to turn tower-light shadows on (the phase-1 renderer probe).

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

**Phase 7 — Light as gameplay.** DayNightCycle drives sun rotation/energy/ambient (replaces
the CanvasModulate `WorldLight`), sprite tint system from the prototype (billboards warm by
distance to light), roamers respect the light edge visually, minimap gets its new
world→radar transform. This phase is the payoff — budget time to tune it.

**Phase 8 — Flip & retire.** 3D game becomes the main scene; proto button/flag and
`scenes/proto3d/` removed; PLAYTEST.md checklist re-run; full smoke suite; a real 2-player
human playtest; merge to main. Session recap doubles as the port post-mortem.

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
