# Playtest Checklist — 3D port acceptance (phase 8)

Everything below has passed scripted headless tests; this run is the **port-acceptance
playtest** — the 3D game replaced the 2D one, and this checklist plus the two-machine
session is what gates the merge to main. Work through it at the machine, tick things off,
and bring back the feedback at the bottom. Budget ~30–45 minutes.

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

`--cycle=90:60` = 90-second days / 60-second nights so a whole run fits the session. Drop the
flag for real pacing (5 min / 3 min) once when judging pacing specifically. Other useful flags:
`--grant-materials=wood:30,stone:20` (skip harvesting when testing building),
`--final-day=2` (short runs), `--tower-hp=10` (fast defeat to see the lose screen).

### Port-specific checks (new this run)

- [ ] **Sun & dusk**: the sun arcs across the day, shadows move; dusk fades warm over ~12 s
      before night — does daybreak/nightfall read clearly enough to plan around?
- [ ] **The daylight bubble**: by day the world gets continuously darker as you walk out
      (`--spawn-at=30,0` to start out there) — everything darkens, not just the floor; at
      dusk the bubble visibly contracts into the night pool. Too dark to forage out there,
      or exactly the risk it should be?
- [ ] **Night look**: the tower pool breathes; the world outside is cold and dark but the
      fight is still readable. **Chris/Vulkan only**: props inside the pool should cast
      radial shadows away from the tower with NO black region (if the pool floor goes black,
      shout — that's the Metal bug appearing on Vulkan too and it must be gated).
- [ ] **Billboards**: characters read well against the meshed world at all times of day;
      sprites warm up as you walk into the tower pool; drop shadows sit at the feet.
- [ ] **Minimap rotation**: walk toward the top of the screen — the dot field should move
      DOWN the radar (radar-up = screen-up). In 2D it was axis-aligned; this transform is new.
- [ ] Real 2-machine test (not loopback): one hosts, the other joins by LAN IP.

Controls: WASD/arrows move · mouse aims · **LMB** shoot · **Q** Piercing Arrow · **F** Snare
Trap · **Space** dodge · **E** harvest · **1/2/3** build hotbar · **LMB** place · **RMB/Esc**
cancel build · **X** sell (hover a building). Gamepad: left stick move, right stick aim,
RT shoot, RB/LB abilities, B dodge, A interact.

## The checklist

### 1. Menus & connection (5 min)
- [ ] Host from the menu; join by IP from the second window; names float over both heads.
- [ ] Close the host window mid-game → client bounces to menu with a message.
- [ ] Join with no host running → "Connecting…" curtain, then bounced after ~10 s.
- [ ] Join during a night assault → refused back to menu (message wrongly says "host ended
      the game" — known gap, just confirm the bounce works).
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
- [ ] Place walls/towers; sell with X; pool refunds; slots grey out when unaffordable.
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
