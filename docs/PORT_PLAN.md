# 3D Port Plan — branch `3d-ortho-prototype`

**Status (2026-07-13):** Craig picked the hybrid direction — 3D world under a fixed
orthographic camera, 2D billboard sprites for characters — and handed continuation to Chris.
Main stays 2D and shippable until phase 8 flips the switch. Read the session-8 entry in
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
with hand-driven tint, collision layers 1/2/4/8 mirroring 2D). Still owed before phase 2
flips `project.godot`: the same matrix on Craig's machine (repro command in the decision
log; `--omni-shadows` flag is in `proto3d.gd`).

**Phase 2 — World & WorldGen.** ✅ 2026-07-14 (Chris) — `scenes/game3d/game3d.tscn` shell
(ground, environment, sun, GlowTower3D with heart + OmniLight) and `world_gen_3d.gd`: same
seed, same rng sequence, radii = 2D px / 32 exactly → cell-for-cell the 2D layout, with
`Res_%d`/`Prop_%d` names intact and a printed **layout hash** as the cross-peer
determinism smoke (identical across processes and renderers). Harvest/hp RPC lanes ported
verbatim; solids join group `"obstacles"` (open question #2: contract kept). New finding,
logged: omni shadows also misrender in *daylight* on Vulkan/Vega M (over-darkened range
box) — tower-light shadows are now night-only via `GlowTower3D.set_light_shadows()`,
which phase 7 wires to DayNightCycle.

**Phase 3 — Player + multiplayer smoke. The risk-killer.** CharacterBody3D, camera rig and
camera-relative input from the prototype, Label3D name tags, synchronizer replicating
Vector3. Then the standard two-instance loopback smoke — if replication of 3D transforms
works here, the port is downhill; if something fights us, we learn it in session 3 not 7.

**Phase 4 — Harvest & materials.** Area3D interact range, harvest RPC chain end-to-end,
`--auto-harvest` re-enabled and asserted host+client. HUD pool display should Just Work.

**Phase 5 — Building.** Ray-plane picking + ghost from the prototype, building scene =
mesh + StaticBody3D, BuildManager logic unchanged on the XZ grid, path validation and
`--auto-build` / `--auto-block-test` green.

**Phase 6 — Enemies & waves.** CharacterBody3D + billboard sprite, XZ waypoint following,
WaveDirector logic unchanged, tower HP, `--auto-fight` and `--hurt-test` green. Abilities:
projectile as Area3D, snare as ground decal + Area3D.

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
