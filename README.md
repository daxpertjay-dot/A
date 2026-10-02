# 🧠 Brainrot Runner

A Subway Surfers-style endless runner for Roblox. The creepy grinning Brainrot **Verity** (with his henchman Tung Tung Tung Sahur) has kidnapped the Brainrots. You escape through areas inspired by Roblox games (🌱 a Grow a Garden farm, then 🌊 an Escape Tsunamis beach), grab coins and power-ups, and rescue caged Brainrots. Rescued Brainrots stand on your base and raise your **score multiplier**. Every run's score levels them up, stylish play builds a **combo**, and your base charges **Hype** while you're away. Coins buy upgrades.

```
YOUR BASE (Brainrots on pedestals = ⭐ score multiplier, ⚡ Hype charging up)
  → walk into YOUR RUN PORTAL → Verity bursts out by his shed → 3… 2… 1… RUN!
  → dodge · jump · roll · 🔥 build a combo · grab 🪙 coins, 🧲🚀👟✖️2 power-ups, ❓ mystery boxes
  → boost-jump onto 🌾 hay wagons and 🌿 greenhouse roofs · 🔓 rescue caged Brainrots
  → score 100,000 → the track turns into 🌊 Tsunami Beach, with better Brainrots
  → caught → SAVE ME (coins) or END
  → RESULTS: score, coins, rescues, Brainrot XP and level-ups → back to your base
```

Everything (lobby, bases, track, characters, UI) is built from code, so it runs in an empty place with no uploaded assets.

## Getting it into Roblox Studio

**Option A: open the built place (quickest)**

```bash
rojo build place.project.json -o BrainrotRunner.rbxl
```

Open the file in Studio and press **Play**. To put it on your experience, use **File → Publish to Roblox As…** and choose your place. The place includes the lobby map, `Workspace.Lobby`, and the run's track sections, `Workspace.TrackAreas`.

**Option B: live-sync the scripts with Rojo**

1. Install [Rojo](https://rojo.space) (the CLI plus the Studio plugin). VS Code is not needed.
2. Open your place in Studio (the one built in Option A, saved as your own).
3. Run `rojo serve` in this folder.
4. In Studio, go to **Plugins → Rojo → Connect**.
5. Press **Play**.

`rojo serve` (`default.project.json`) syncs only the scripts. It never touches `Workspace.Lobby` or `Workspace.TrackAreas`, so your edits to the maps stay in your place.

**The lobby map.** `Workspace.Lobby` is a normal map: move, recolour, delete or add anything in Studio. If there's no `Workspace.Lobby`, the game generates the default one at startup. The map file `map/Lobby.rbxm` is made from `src/server/Lobby/LobbyBuilder.luau` by `tools/bake_map.sh`.

Rebuilding the place from this repo replaces the map with the repo's copy. To keep your Studio edits, right-click `Workspace.Lobby` → **Save to File…**, save it over `map/Lobby.rbxm` and commit it.

Most of the map is free to change, but a few things are found by name:
- **Bases** are the Models `Plot1`, `Plot2`, … Each needs a `PlotFloor`, `ArchBeam`, `MultiplierSign`, `HighScoreSign`, `RunEntranceTrigger` and `Pedestal1`–`Pedestal10`. Move or rotate a whole base freely; delete one and there's one fewer base.
- **Conveyors** are parts tagged `Conveyor`. They push toward their front at their `Speed` attribute, so you can move and turn them too.
- **Run portals** are parts tagged `RunEntranceTrigger`. The shop, upgrades, daily gift and leaderboard work through their ProximityPrompts, wherever you put them.

**The track sections.** Runs are built from the section Models in `Workspace.TrackAreas` (far off to the side of the lobby, around x = -9000). Edit them like any map; see [The track](#the-track-run-areas) for how they work. They're saved in `map/TrackAreas.rbxm`, made by `tools/bake_map.sh tracks`. Keep your edits the same way as the lobby: right-click `Workspace.TrackAreas` → **Save to File…** over `map/TrackAreas.rbxm`.

To use DataStores and leaderboards in Studio, turn on **Game Settings → Security → Enable Studio Access to API Services**.

## Controls (during a run)

| Action | Keyboard | Mobile | Gamepad |
|---|---|---|---|
| Change lane | A / D or ← / → | swipe left / right | D-pad / left stick |
| Jump | W / ↑ / Space | swipe up | A |
| Roll (fast-fall in the air) | S / ↓ | swipe down | B |
| Hoverboard | E / Q | double-tap | X |

A jump instantly cancels a roll, and a jump pressed just before landing fires on touchdown.

## How the game works

### ⭐ Score & multiplier (the main goal)
- **Score = meters run × score multiplier.** The leaderboard ranks high scores.
- During a run your multiplier is:

  **base (your Brainrots) × ✖️2 Score Booster × 🔥 combo × ⚡ Hype**

  The HUD shows the total, with the combo and Hype meters under your score.
- Your **base multiplier** is **1 + the bonus of every Brainrot standing on your base**:

| Rarity | Bonus at Lv 1 | Bonus at Lv 10 |
|---|---|---|
| Uncommon | +1x | +3.25x |
| Rare | +2x | +6.5x |
| Epic | +3x | +9.75x |
| Legendary | +5x | +16.25x |

- Your base starts with **3 pedestals** and holds up to 10. Buying more pedestals with coins raises your multiplier ceiling.

### 🧠 Brainrot levels: your score feeds your base
- After every run, **each Brainrot on your base gains XP equal to the run's score**.
- Each level adds +25% of its base bonus. Lv 2 needs 2,500 XP, each level needs 2.2 times more than the last, and Lv 10 takes about 2.5M XP in total.
- This is the loop: a higher multiplier means a higher score, which means more XP and level-ups, which means a higher multiplier. Every run improves your base, even a bad one.
- Levels belong to each kind of Brainrot, so every copy of Tralalero shares one level. Pedestals show "Lv 7", and the Brainrots panel shows XP bars.

### 🌈 Mutations
A caged Brainrot is sometimes a rare variant. You can see it in the cage, tinted and sparkling, before you reach it. A mutation multiplies that Brainrot's bonus:

| Mutation | Bonus | Chance per cage |
|---|---|---|
| 🥇 Gold | ×2 | 10% |
| 💎 Diamond | ×3 | 3.5% |
| 🌈 Rainbow (colours cycle) | ×5 | 1% |
| 🌌 Galaxy | ×10 | 0.2% |

- Variants are kept separately, so a Rainbow Tralalero and a normal one are different pedestal entries. They share the same level.
- **Rare rescues are announced to the whole server** in chat and on screen: any Diamond, Rainbow or Galaxy, and every Legendary.
- `Config.Mutations.Luck` multiplies every chance, ready for "lucky hour" events or a server-luck boost later.

### 🔥 Style combo: rewards focus
Playing well builds a combo that multiplies your multiplier, from x1.0 up to **x3.0** (20 stacks):

| Trick | Stacks |
|---|---|
| Clear an obstacle (jump over it) | +1 |
| **Near miss**: change lanes just before hitting something (within 0.5s) | +2 |
| **Roof run**: land on a wagon or tunnel roof | +2 |
| Smash something / crash through a wall | +1 / +2 |
| Every 15 coins | +1 |
| Power-up / mystery box | +1 |
| Rescue a Brainrot | +3 |

The combo starts draining 2.5s after your last trick, a sideswipe halves it, and a crash resets it. The server owns the combo: the client reports tricks, each obstacle counts once, and it has to be where you are.

### ⚡ Hype: your base charges while you're away
- The Brainrots on your base charge **Hype** while you're offline (full in 8h) or hanging out in the lobby (full in 4h). Better bases charge faster, up to 3 times as fast.
- A full charge gives **x2.5** on top of everything at the start of your next run. It's spent as you run, and a full charge lasts 1,000 m. Whatever you don't use is kept.
- New players start fully hyped. The lobby wallet shows your Hype and when it'll be full, and your base sign shows `⚡ HYPE 64%`.

### 🔓 Brainrots
Verity keeps them in cages on the track; run through a cage to rescue it. Each area has its own Brainrots, and later areas have much bigger bonuses:

| Area | Brainrot | Rarity | Bonus |
|---|---|---|---|
| 🌱 Grow a Garden | Chimpanzini Bananini · Brr Brr Patapim | Uncommon | +1x |
| | Lirilì Larilà · Ballerina Cappuccina | Rare | +2x |
| | Bombardiro Crocodilo | Epic | +3x |
| | Cappuccino Assassino | Legendary | +5x |
| 🌊 Tsunami Beach | Tralalero Tralala | Rare | +6x |
| | Trippi Troppi · Bombombini Gusini | Epic | +8x · +9x |
| | Cocofanto Elefanto | Legendary | +14x |
| | Chef Crabracadabra | Legendary | +16x |

Rescues are kept even if you get caught. Your best Brainrots automatically take the pedestals.

### 🪙 Coins (Subway Surfers style)
- Every coin is worth **1**. A run earns a few hundred: coin lines between obstacles, arcs over barriers that match your jump exactly, and coin lines along the tops of wagons, shacks and tunnels.
- The big moments are the **🚀 Jetpack sky trail** (a hundred-plus coins) and **❓ Mystery Boxes** (100–1,500 coins or hoverboards).
- Coins buy:
  - **Power-up upgrades.** 5 levels each, making them last longer: 500 / 1,500 / 3,500 / 7,500 / 15,000 coins.
  - **Pedestals.** 750 → 20,000 coins; this is how you raise your multiplier ceiling.
  - **🛹 Hoverboards.** 300 each.
  - **Revives.** "Save me", 200 coins, doubling each time.

### ⚡ Power-ups (on the track)
| Power-up | What it does | Level 0 → 5 |
|---|---|---|
| 🧲 Coin Magnet | pulls coins in | 10s → 20s |
| 🚀 Jetpack | **fly** high over everything along a sky-coin trail, skipping that stretch | 6s → 12s |
| 👟 Super Sneakers | huge jumps: **onto wagons, shacks and tunnel roofs** | 10s → 20s |
| ✖️2 Score Booster | doubles your multiplier | 10s → 20s |

A **🛹 Hoverboard** (bought with coins, or from daily rewards and mystery boxes) lasts 30s. It **boosts your jump** high enough for wagon and tunnel roofs, and it saves you from one crash by breaking instead. On the board your character surfs: turned sideways, knees bent, arms out. To use a real animation instead, put its ID in `Config.Animations.Hoverboard`.

Power-ups are deliberately rare, so each one feels like a moment:
- A random one appears in about 1 in 7 sections; otherwise there's sometimes a mystery box.
- Super Sneakers sometimes wait just before wagons and tunnels.

### The chase
Crashes let **Verity** close in:
- **Running into the front** of something you can't break stops you dead.
- **Switching lanes into the side** of something (a hay wagon beside you) bounces you back into your lane. You stumble, drop to 60% speed for a moment and lose half your combo, like in Subway Surfers.

Stumble too much and he's right behind you with his net; one more mistake and he catches you. You can then **SAVE ME** with coins (or Robux) or end the run. **Reviving sends out a 💥 shockwave** that blows away every structure around you (wagons, walls, fences, from 45 studs behind to 110 ahead), so you never come back to life staring at a wall. **BACK TO BASE** always gets you home, even if you died mid-run or during the "RUN STARTING…" fade.

### The track: run areas
The track changes as your score climbs. Each area is inspired by a Roblox game, so it feels familiar, yet different. You get a big banner and a new sky when you enter one, and the HUD shows where the next one starts.

| Score | Area | Looks like | Obstacles |
|---|---|---|---|
| 0 | 🌱 **Grow a Garden** | dirt path through studded grass, fenced crop beds, seed / gear shop stands, blocky trees, a red barn | wooden fences and crop planters to jump, hay bales to smash, barn walls to crash through, 🌾 hay wagons and 🌿 greenhouses to boost onto |
| 100,000 | 🌊 **Tsunami Beach** (Escape Tsunamis for Brainrots) | sandy path by the sea with the tsunami out on the water, palms, umbrellas, beach huts | sand castles and driftwood to jump, coolers to smash, tiki walls to crash through, 🏄 surf shacks and 🎡 the pier to boost onto |
| 750,000 | area 3 (to come) | | |
| 2,500,000 | area 4 (to come) | | |

The run starts in front of Verity's shed. Sections are kept calm: rows are well spaced, usually only one or two lanes are blocked, and there's always a way through.

**Jump boosts and roofs.** A normal jump peaks at about 9 studs. That clears fences, but it can't reach a wagon roof (12.5) or a tunnel roof (16). With a **jump boost** (👟 Super Sneakers or 🛹 a hoverboard) you can jump onto them and run across the top, where the best coin lines are. Notes:

- The roof run also scores a combo bonus.
- Time your jump: hit the tunnel entrance too low and you crash into it.
- Inside a tunnel, the ceiling stops boosted jumps.
- Sneakers often spawn just before wagons and tunnels, and a sign marks each tunnel.

Destruction is still in: small things smash, and wooden walls break at high speed.

**Editing the sections.** Each area is a folder of section Models in `Workspace.TrackAreas` (`Garden`, `Beach`). A run lays them end to end, picking at random by kind and difficulty. Every Model has:
- an invisible `Origin` part, its PrimaryPart, at the start of the section; the section runs from there along -Z for its `Length` attribute
- attributes `Kind` (sections of a kind take turns; `Start` and `Gate` are special), `Weight` (how often), `Cooldown`, and `Difficulty` (0 easy, 1 medium from 900 m, 2 hard from 1,800 m)
- folders:
  - `Ground`: what you stand on (the path, roofs)
  - `Obstacles`: one Model per obstacle
  - `Scenery`: looks only
  - `Coins`
  - `Spots`: cyan `PickupSpot`s and magenta `CageSpot`s. Each run rolls power-ups, mystery boxes and caged Brainrots onto them.

Edit, duplicate or add sections freely. Parts you add to `Ground` become standable. Parts you add to `Obstacles` become crashable; an obstacle Model with no attributes is an unbreakable wall, and its lane is worked out from where it stands. To get a fresh copy of the built-in sections, run `tools/bake_map.sh tracks`. To add an area: add it to `src/shared/AreaData.luau`, give it Brainrots in `BrainrotData`, and add a builder in `src/server/Run/Areas/` (see `Garden.luau`), or just build its folder of sections in Studio.

**Milestone math.** How far a run has to go is score ÷ (points per meter × multiplier). `tools/milestones.luau` works it out from the real numbers (speed curve, Brainrot bonuses, levels, area thresholds); re-run it when multipliers change. With an average x1.5 combo and no Hype or booster:

Average catch bonus: Garden +1.6x (best +5), Beach +8.3x (best +16). Combo assumed x1.5.

| Base | Base x | Run x | 🌊 Tsunami Beach at 100k | (area 3) at 750k | (area 4) at 2.5M |
|---|---:|---:|---:|---:|---:|
| Starter: 3 Garden catches, Lv 1 | 5.7 | 8.6 | 11.6k m · 2:54 | 87.2k m · 19:03 | 290.8k m · 1h02m |
| 10 Garden catches, Lv 1 | 16.8 | 25.2 | 3.9k m · 1:10 | 29.8k m · 6:47 | 99.3k m · 21:39 |
| 10 Garden catches, Lv 5 | 32.5 | 48.8 | 2k m · 0:39 | 15.3k m · 3:42 | 51.2k m · 11:22 |
| 10 best Garden, Lv 10 | 163.5 | 245.2 | 407 m · 0:08 | 3k m · 0:56 | 10.1k m · 2:36 |
| 10 Beach catches, Lv 1 | 84.1 | 126.1 | 793 m · 0:16 | 5.9k m · 1:39 | 19.8k m · 4:39 |
| 10 Beach catches, Lv 5 | 167.1 | 250.7 | 398 m · 0:08 | 2.9k m · 0:55 | 9.9k m · 2:33 |
| 10 best Beach, Lv 10 | 521.0 | 781.5 | 127 m · 0:02 | 959 m · 0:19 | 3.1k m · 0:58 |

So far, a starter base needs a ~3 minute run to reach the beach. A Lv 10 Garden base is there in seconds, so the thresholds (or the late-game bonuses) will need tuning once the multipliers are final.

### Verity
Verity is a Minecraft-horror style Brainrot: a grimy yellow smiley ball with black eyes, a huge toothy grin and a red glow, with Tung Tung Tung Sahur running beside him. To use **your own Verity model**, put a Model named `VerityModel` in **ReplicatedStorage**, with its PrimaryPart at the feet and facing forward. The chase and the lobby statue will use it automatically.

### Flying
With the 🚀 Jetpack your character flies Superman-style: tipped forward, one fist out, with a flaming jetpack on your back. To use a real animation instead, put its ID in `Config.Animations.Fly`.

### Lobby & your base
- **The lobby is a big blocky valley** in the style of your references: checkered grass with studs, closed in on every side by terraced, checkered cliffs. The cliffs have brown checker sides, grass tops and trees on the ledges, and a giant Verity watches from the north cliff.
  - **In the middle** is the light-stone **SAFE ZONE**: spawn, the ⬆️ Upgrades and 🛒 Shop stands (wooden, with coloured roofs), the 🎁 daily gift, the 🏆 leaderboard, the WANTED statue of Verity and the public run gate.
  - **Around it** is a stone **ring road with a conveyor loop**. Paths lead to the **8 fenced bases**: 3 north, 3 south, 1 west and 1 east, each 80×100 studs.
  - Voxel trees, pine trees, bushes, flowers and rocks fill the grass in between.
- **Stud texture**: the square studs on every face, the Steal a Brainrot / Grow a Garden look. Turn it on in three steps:
  1. Upload `assets/StudTexture.png` in Studio (**Asset Manager → Import**).
  2. Copy its asset ID.
  3. Paste it into `Config.Lobby.StudTexture` (for example `"rbxassetid://1234567890"`).

  At startup it's applied to every part in `Workspace.Lobby`, including parts you add. Give a part or model a `NoStuds` attribute to keep it plain. It's a transparent overlay, so every part keeps its own colour. It goes on every face at least 1 stud across (`Config.Lobby.StudTextureMinFace`), so fence posts and caps get studs too.
  Until you set it, parts use Roblox's classic round studs. To change the look, edit and re-run `tools/make_stud_texture.py`.
- **Blender props with real outlines**: `assets/models/` has voxel trees, pine trees, bushes, rocks, flowers and a lamp, made in Blender by `tools/blender/props.py` (`preview.png` shows them). Each has a built-in black toon outline, which hides behind things like normal geometry and never doubles up. To use them:
  1. In Studio, **Import 3D** `assets/models/LobbyProps.fbx`. Leave the result named `LobbyProps`. It can stay in Workspace, where the importer puts it: at startup the server anchors it and takes it out of the world. You can also move it to **ServerStorage** yourself. Inside it, wherever the importer nests them, are the Models `Tree`, `Tree_2`, `PineTree`, `PineTree_2`, `Bush`, `Bush_2`, `Rock`, `Rock_2`, `Flowers` and `Lamp`. The single files (`Tree.fbx` …) also work: put each import in `LobbyProps`, named after its kind.
  2. Press Play. At startup every blocky tree, bush, rock, flower patch and lamp in the lobby map is swapped for one of your models, at the same spot and size. Variants are picked at random.

  The colours come from a small palette texture embedded in the FBX (also saved as `assets/models/palette.png`), so the props are coloured as soon as they're imported. When you press Play, the game also paints each mesh by the colour in its name (`Tree_2_Leaves` → `Config.Lobby.PropColors.Leaves`), and sizes the props to match the blocky ones, so the importer's unit setting doesn't matter. The outline is the mesh ending in `Outline`, and it relies on MeshParts being one-sided, so leave `DoubleSided` off.
- **Edge outlines on parts** (`Config.Lobby.Outlines`) are off: those SelectionBox outlines showed on far-away parts and doubled up where parts touched.
- **Your own models**: place them in `Workspace.Lobby` in Studio, or put Models named `Tree`, `PineTree`, `Bush`, `Rock`, `Flowers` or `Lamp` (or `Tree_2` etc. for variants) in `ServerStorage.LobbyProps` to replace the blocky ones, like the Blender props above.
- Your base has:
  - your pedestals, with a big **SCORE MULTIPLIER** sign (showing Hype too), with each Brainrot's level above it; locked pedestals can be bought right there
  - your high score
  - your personal run portal
- The HUD buttons open everything from anywhere: Upgrades, Brainrots, Shop, Daily, Top, Stats, My Base.

## Tests
`tests/run.sh` runs the headless test suite with [Lune](https://lune-org.github.io/docs). It covers track generation, a full server run, the UI, jump boosts and side bumps, and a bot that plays for 90 seconds. See CLAUDE.md for details.

## Project layout

```
map/Lobby.rbxm                 the lobby map (Workspace.Lobby), made by tools/bake_map.sh
map/TrackAreas.rbxm            the run's section templates (Workspace.TrackAreas), tools/bake_map.sh tracks
tools/milestones.luau          score milestone math (distance / time to each area)
place.project.json             builds the place with the map; default.project.json = scripts only (rojo serve)
assets/StudTexture.png         the lobby's stud texture (upload it; see "Lobby & your base")
tools/make_stud_texture.py     draws that texture
tools/blender/props.py         builds the lobby props in Blender → assets/models/*.fbx
tests/                         headless tests (tests/run.sh)
src/
├── shared/                    ReplicatedStorage.Shared
│   ├── Config.luau            ← all tuning: villain, score, levels, combo, Hype, coins, power-ups, speeds, camera
│   ├── PowerUpData.luau       power-ups, durations per level, upgrade costs
│   ├── AreaData.luau          run areas: name, score where each starts, lighting
│   ├── BrainrotData.luau      Brainrots: multiplier bonus, rarity, which area they're caged in
│   ├── Progression.luau       Brainrot levels/XP, style combo, Hype (shared math)
│   ├── MutationData.luau      Gold / Diamond / Rainbow / Galaxy variants
│   ├── DailyRewardData.luau   7-day reward track
│   ├── ImpactRules.luau       crash rules + jump physics (shared client/server)
│   ├── ModelFactory.luau      blocky Brainrot + villain models
│   └── Remotes.luau · Signal.luau · Util.luau
├── server/                    ServerScriptService.Server
│   ├── Main.server.luau
│   ├── PlayerData.luau        profiles (coins, Brainrots + XP, Hype, pedestals, upgrades, hoverboards, stats)
│   ├── Economy.luau           upgrades, pedestals, hoverboards, daily, Robux receipts
│   ├── Leaderboards.luau      high score + other global boards
│   ├── Lobby/LobbyBuilder.luau  the lobby map: valley, cliffs, SAFE ZONE, roads, conveyors (+ using the saved map)
│   ├── Lobby/PlotManager.luau   player bases: pedestals, multiplier sign, run portal
│   └── Run/
│       ├── RunManager.luau    run lifecycle, score, combo, Hype, power-ups, rescues, XP, results
│       ├── TrackGenerator.luau  lays sections ahead (switching area by score) / recycles behind
│       ├── TrackAreas.luau    the section library: Workspace.TrackAreas, or built from code
│       ├── Areas/             Kit (section toolkit), Garden, Beach: the built-in sections
│       ├── Pickups.luau       power-up boxes, mystery boxes, Brainrot cages
│       └── Destruction.luau   breakable walls & debris
└── client/                    StarterPlayerScripts.Client
    ├── Main.client.luau       lobby ⇄ run orchestration
    ├── InputController.luau   lanes / jump / roll / hoverboard (+ swipes, gamepad)
    ├── RunController.luau     movement state machine, power-ups, jump boosts, tricks, collisions
    ├── RunCamera.luau         chase camera (follows jetpack flights)
    ├── Chaser.luau            Verity + Sahur
    ├── DebrisFX.luau · LobbyFX.luau
    └── UI/ (UIKit, LobbyUI, RunHUD)
```

## Things to set up
- **The villain**: rename him in `Config.Villain`, or drop in your own `VerityModel` (see above).
- **Robux products**: put developer product IDs in `Config.DeveloperProducts` (coin packs, revive, hoverboards).
- **Sounds**: add asset IDs to `Config.Sounds`.
- **Animations**: swap run/jump animation IDs in `Config.Animations`, or add flight and hoverboard animations there.
- **Lobby look**: the stud texture ID in `Config.Lobby.StudTexture` and your models in `ServerStorage.LobbyProps` (see above).
