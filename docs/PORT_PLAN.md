# 3D Port Plan — branch `3d-ortho-prototype`

**Status (2026-07-13):** Craig picked the hybrid direction — 3D world under a fixed
orthographic camera, 2D billboard sprites for characters — and handed continuation to Chris.
Main stays 2D and shippable until phase 8 flips the switch. Read the session-8 entry in
`ARCHITECTURE.md` (on this branch) before starting: it records the driver gotchas the
prototype already paid for.

**Try the slice first** (10 minutes, judge the night): run
`godot --path . res://scenes/proto3d/proto3d.tscn`, or open the scene and F6. (The menu
button and `--proto3d` flag mentioned in the session-8 notes were never built — launch the
scene directly.) WASD moves, mouse ghost snaps to cells, LMB places walls, night falls
~14 s in. `-- --screenshot-at=4,17 --quit-after-sec=20` for scripted shots;
`--omni-shadows` turns tower-light shadows on (the phase-1 renderer probe).

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

**Phase 2 — World & WorldGen.** `game3d.tscn` shell: ground, WorldEnvironment, sun, glow
tower scene (mesh + OmniLight + heart). Port WorldGen: same seed, same `Res_%d`/`Prop_%d`
naming (the RPC-by-NodePath contract from the GOTCHAS still applies!), StaticBody3D
collision on solids, meshes for trees/rocks, billboard wisps. Resource nodes keep their
harvest RPC lane unchanged.

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
