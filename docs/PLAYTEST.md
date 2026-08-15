# Playtest Checklist — 3D port acceptance (phase 8)

Everything below has passed scripted headless tests; this run is the **port-acceptance
playtest** — the 3D game replaced the 2D one. The merge to main already happened (Craig's
call, 2026-07-14), so this is acceptance-after-the-fact: what it gates now is whether the
port's feel is good enough to build content on. Work through it at the machine, tick things
off, and bring back the feedback at the bottom. Budget ~30–45 minutes.

**A scripted visual pre-flight ran on 2026-08-10 (Chris, Windows/Vulkan/Vega M)** and
cleared the frame-level look questions below, so this session can spend its time on feel
rather than on "is it rendering right." It also found and fixed one real bug — see the
night-look bullet.

## Setup

Two windows on one machine — PowerShell (Chris):

```powershell
$godot = 'C:\Users\Chris\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe'
Start-Process $godot -ArgumentList '--path','C:\SourceControl\Lastlight','--','--host','--name=Chris','--cycle=90:60'
Start-Process $godot -ArgumentList '--path','C:\SourceControl\Lastlight','--','--join=127.0.0.1','--name=Guest','--cycle=90:60'
```

zsh (Craig's Mac):

```zsh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJ=~/Documents/SourceControl/Lastlight
"$GODOT" --path "$PROJ" -- --host --name=Craig --cycle=90:60 &
"$GODOT" --path "$PROJ" -- --join=127.0.0.1 --name=Guest --cycle=90:60 &
```

Since session 12 both windows land on a **class-select screen** first — pick there, then the
run starts. Add `--class=ranger`, `--class=paladin` or `--class=mage` to skip it (that also
bypasses the screen entirely, which is how the smoke tests run).

`--cycle=90:60` = 90-second days / 60-second nights so a whole run fits the session. Drop the
flag for real pacing (3 min / 3 min) once when judging pacing specifically. Other useful flags:
`--grant-materials=wood:30,stone:20` (skip harvesting when testing building),
`--final-day=2` (short runs), `--tower-hp=10` (fast defeat to see the lose screen).

### Port-specific checks (new this run)

- [ ] **Sun & dusk**: the sun arcs across the day, shadows move; dusk fades warm over ~12 s
      before night — does daybreak/nightfall read clearly enough to plan around?
- [x] **The daylight bubble** — mechanically confirmed in-frame at `--spawn-at=30,0`:
      ground, props, trees and the player billboard all dim together with distance, and the
      bubble contracts through dusk into the night pool. **Still a judgement call for you:**
      at 30 cells out by day it is quite dark — too dark to want to forage, or exactly the
      risk it should be? Play it, don't just look at it.
- [x] **Night look** — ✅ fixed, and this check earned its keep. The pool floor **did** go
      black on Windows/Vulkan Forward+ at night: a hard-edged black diamond (the omni's
      range box) over the whole pool. Shadowed omnis are now vetoed on every stack
      (`GlowTower.SHADOWED_OMNIS_TRUSTED`, decision log 2026-08-10); the shadowless pool
      renders correctly. Nothing left to check here beyond "does it look good to you."
- [x] **Billboards** — characters read well at the village by day and inside the night pool,
      drop shadows sit at the feet. **Note for you:** a player caught out in the wilds *at
      night* is very nearly invisible (a dark silhouette with a grey head). Probably correct
      as a punishment, but judge whether it's playable or just frustrating.
- [x] **Minimap rotation** — verified geometrically rather than by walking: from
      `--spawn-at=30,0` the tower lies in world −X, which this camera maps to screen
      up-left, and the gold home marker sits up-left on the radar. Transform is correct.
      Give the radar a *feel* check while moving anyway.
- [ ] Real 2-machine test (not loopback): one hosts, the other joins by LAN IP.

Controls: WASD/arrows move · mouse aims · **LMB** basic attack · **Q** and **F** the other two
abilities (Ranger: Piercing Arrow / Snare Trap; Paladin: Consecration / Bulwark; Mage: Frost
Nova / Ember Sigil) ·
**Space** dodge · **E** harvest (a prompt appears in range) · **1/2/3** build hotbar ·
**LMB** place · **RMB/Esc** cancel build · **X** (or the hotbar's Sell button) toggles sell
mode — hovered buildings highlight orange with a refund preview, LMB sells. Hover any hotbar
slot or ability for a tooltip. Gamepad: left stick move, right stick aim, RT shoot, RB/LB
abilities, B dodge, A interact.

## The checklist

### 1. Menus & connection (5 min)
- [ ] Host from the menu; join by IP from the second window; names float over both heads.
- [ ] Close the host window mid-game → client bounces to menu with a message.
- [ ] Join with no host running → "Connecting…" curtain, then bounced after ~10 s.
- [ ] Join during a night assault → refused back to menu with "The gates are barred during
      night assaults — try again at dawn." (fixed 2026-07-15 — shout if you still see
      "host ended the game", that means the refusal RPC lost the race to the kick).
- [ ] Join mid-run during the day → world state correct (materials, half-harvested nodes,
      placed buildings, tower HP).

### 2. Movement, camera, dodge (5 min — the most important feel check)
- [ ] Walk around: speed OK for the map size? Is the fixed iso camera (45° yaw, ortho)
      comfortable — zoom distance right, nothing important hidden behind tall meshes?
- [ ] Dodge roll: moves in your movement direction (or aim direction when standing still).
      Distance/cooldown feel?
- [ ] **Gamepad** (first time on real hardware): stick move + aim, all buttons. Note anything
      dead or inverted.
- [ ] Watch the *other* window's character while one moves — jitter, rubber-banding, delay?

### 3. Day loop (5 min)
- [ ] Harvest a tree/rock/wisp with E — counts tick up in **both** windows; nodes fade as
      stock drops and vanish at zero.
- [ ] Dusk: the 12-second light fade — enough warning that night is coming?
- [ ] Is there anything to *do* in the back half of a real-length (5 min) day?

### 4. Building (5 min)
- [ ] Hotbar keys and clicking slots both select; ghost follows grid, green/red tint honest.
- [ ] Hover tooltips: hotbar slots (stats, cost, refund %) and the ability bar (damage,
      cooldown) — do they answer the questions you actually had?
- [ ] Sell mode: X or the [X] Sell button toggles it; hovered buildings highlight orange and
      the hint shows the exact refund; LMB sells; pool refunds match the hint; Esc exits.
- [ ] Try to seal the tower in — the sealing wall must show red and refuse.
- [ ] Build a maze corridor, then watch night enemies actually walk it.
- [ ] In build mode, LMB places (doesn't fire the bow); Esc puts the hammer away.

### 5. Night combat (10 min — the fun question lives here)
- [ ] Waves come from both openings; towers fire on their own.
- [ ] The kit: bow on cooldown-clicks, Piercing Arrow through a line of enemies, trap roots
      what steps on it, dodge through a gap.
- [ ] Let some enemies reach the tower: HP drops, HUD counter, red-tint at low HP.
- [ ] Dawn: leftovers burn, chest materials appear in the pool.
- [ ] Night visibility: can you read the fight in the dark, or is it murky?

### 5b. The rebalance (session 11 — judge these hardest)

Mobs have double hp and +1 damage, buildings cost more, and wood/stone income is much
lower. **A scripted smoke lost the tower on night 1** with 3 towers up and only 6 kills in
a 60 s night — that harness aims badly and isn't proof, but go in expecting it to bite.

- [ ] **Is night 1 now winnable by a competent player?** If it isn't, that's the headline
      finding. Dials, cheapest first: `WaveDirector.max_alive_base` (10),
      `interval_scale_per_night`, then mob `max_hp` back down.
- [ ] **Chop-to-fell economy**: a node pays 4 only when it falls (near trees 14 chops, far
      ones 5 — so far nodes are *faster* income now). Does felling feel like an event, or
      does the back half of a 14-chop tree just feel like a chore? `WorldGen.yield_per_node`
      is the dial; the HUD hint shows `(N left → 4)`.
- [ ] **Can you afford anything?** Wall 2 wood, sentry 3 stone/4 wood, turret 4 stone/5 wood.
      Is one night's prep enough for a real maze, or does building stop being a decision
      because you're always broke?
- [ ] **3-minute days**: still a back half with nothing to do, or now too rushed to prep?
- [ ] **Roamers wander** — watch the light edge from inside the village. They should drift
      through the dark, never park against the glow. (Instrumented, not just eyeballed: all
      roamers circulate and none enter the safe zone.)
- [ ] **Day survivors join the night** — leave roamers alive at dusk and confirm they march
      on the tower with the horde (host log: "N daytime roamer(s) joined the assault").
      Does that make ignoring them by day feel like a real mistake?
- [ ] **Tower over wall**: build a wall, then place a tower on the same cell — it should
      replace it and charge cost minus the wall's refund. Wall onto a tower must refuse.
      Known cosmetic gap: the hotbar slot greys on full cost, so a tower you can only afford
      *because* of the wall refund looks unaffordable but still places.

### 5c. The Paladin and class select (session 12 — new)

There are two classes now. The screen between the menu and the game is where you pick; run the
two windows as **different classes** at least once. Nothing below has been played by a human —
the numbers are a first draft, so react to how it feels, not to whether it's balanced.

- [ ] **Class select**: both cards read clearly? Do the stats and ability lines tell you enough
      to choose, or do you just pick the picture? Back returns to the menu; your last pick is
      still highlighted when you come back.
- [ ] **Does melee work at all in this camera?** The Paladin's whole kit lands within ~2 cells
      and the view is a fixed 45° ortho. Can you tell what you're about to hit, or does the
      angle make range guesswork? This is the headline question — if it's bad, the fix is
      probably `cleave.melee_range`/`arc_degrees`, not the camera.
- [ ] **Cleave** (LMB, 5 damage, 1.75 cells, 100° arc): does the wedge read where you aimed?
      It outranges a wretch's 1.5 cells on purpose — does that gap feel like it exists?
- [ ] **Consecration** (Q, 9 damage, 3 cells, all around, 7 s): worth wading into a pack for,
      or a panic button you never get to use?
- [ ] **Bulwark** (F, −45% damage for 5 s, 14 s): the sprite washes gold while it's up. Long
      enough to matter? Note that dodge still grants no i-frames, so this is currently the
      Paladin's only defensive answer.
- [ ] **140 hp and 120 speed vs the Ranger's 90 and 150** — does the Paladin feel *sturdy*, or
      just slow? Walking the map at 120 is a real tax now days are 3 minutes.
- [ ] **Hallowed Brazier** (4 stone, 4 wood; 7 damage, 2.5 cells, every 1.5 s): a Paladin-only
      slot 3, replacing the Ranger's Arrow Turret. Its reach is deliberately tiny — does
      building a maze that forces enemies past it feel like a plan, or a gimmick?
- [ ] **Two classes at once**: with one of each, does the party divide work naturally (Paladin
      holds the gap, Ranger kites and traps), or do you both end up doing the same thing?
- [ ] Confirm each player sees the *other's* class correctly — the right sprite over the right
      name. (Asserted in the smoke tests, but eyes on it once.)

### 5d. The Mage (session 13 — new)

Third class, and the first thing in the game that spends essence. Same caveat as the Paladin:
nobody has played these numbers.

- [ ] **70 hp at 135 speed** — the Ranger is 90/150 and the Paladin 140/120. Does the Mage feel
      like a deliberate risk, or just fragile? How many hits before you're downed, in practice?
- [ ] **Arcane Bolt** (LMB, 4 damage, 15 cells, every 0.55 s): reaches further than any bow.
      Can you actually *see* far enough to use that range, or does the camera cap it before the
      ability does? That's the interesting question — if the camera wins, the range is a lie.
- [ ] **Frost Nova** (Q, 3 damage, 4 cells all around, roots 2.5 s, every 9 s): the escape
      button, not a damage tool. Does it reliably buy you the room to walk away?
- [ ] **Ember Sigil** (F, burns 3 every 0.7 s for 10 s, every 12 s): unlike the Ranger's trap it
      does *not* spring and vanish — it keeps burning. Lay it in a corridor. Does the difference
      read on the ground? (It has its own orange rune art so it can't be confused with a snare.)
- [ ] **Arcane Spire** (2 Faint Essence + 3 Stone; 3 damage, 8 cells, every 1.1 s): watches far
      more ground than any other tower and chips rather than kills.
- [ ] **The essence question — judge this hardest.** This is the only building that costs
      essence, and essence lives in the mid and outer rings. Can you get enough by night 1 to
      build anything, or does the Mage spend its first night unable to build at all? If it's the
      latter, the dial is the Spire's cost, not the map.
- [ ] **Three classes together** (if you can get a third window up): does the party split into
      real roles — Paladin holds, Ranger kites, Mage covers ground — or does everyone converge?

### 6b. World, daytime danger & survival (session 5 — new)
- [ ] The map no longer feels empty: resource nodes are plentiful and scenery (boulders, dead
      trees, ruined pillars, grass, bones, rubble) dresses the open world. Solid props block
      you and enemies; decor you walk through.
- [ ] Materials are common near the village and rarer/essence-heavy the further out you go.
- [ ] The safe zone (the glow ring) is roomy, and monsters do **not** enter it.
- [ ] Venture past the glow during the day → roaming monsters give chase and hurt you; retreat
      into the glow → they break off at the edge.
- [ ] Take enough hits → **downed** (greyed, prone, banner shows). A teammate standing over you
      revives you; alone, the village recalls you after a few seconds. HP shows on the HUD.
- [ ] Mini-map (bottom-right): resource dots in material colours, red mob dots, cyan teammates,
      a gold marker for home pinned to the rim when the tower is off-screen. Reads correctly as
      you move? (Solo test: `--host` alone. Danger test far from base: wander out and wait.)
- [ ] At nightfall the daytime roamers clear out and the assault takes over as before.

### 6. Run end & meta (5 min)
- [ ] Lose on purpose (`--tower-hp=10`): necromancer screen on both windows, XP banked,
      Return to Menu works from both.
- [ ] Win (`--final-day=1`): victory screen. Relaunch the game — the menu run's profile
      (account/class level on the run-end screen next time) kept your XP.
- [ ] Note: two windows on one PC share one profile file, so XP double-banks locally —
      expected, ignore it.

## What feedback is useful right now

Three headline verdicts (a sentence each is enough):

1. **Feel** — do moving, aiming, shooting, dodging feel good or mushy? What specifically?
2. **Tension** — is night 1 threatening at all? Did you care about the tower?
3. **Pacing** — did the day drag or rush? Was building a real decision or a formality?

Plus, per-item, directional notes, not numbers: "dodge feels weak", "trap radius reads
bigger than it is", "arrows too slow to lead targets". Balancing decimals come later.

Bug reports: which window (host or guest), what you did, what you expected, and the console
text if any (the console window behind each game shows our `[System]` logs — screenshots fine).

**Not useful yet** (known placeholder territory): art quality, missing audio, menu prettiness,
missing Paladin/Mage, night-assault enemies not attacking players/buildings (only the tower),
dodge not granting invulnerability yet, the map being the same every run (fixed seed), exact
damage numbers.

Bring the three verdicts + notes to the next session and they steer Session 5.
