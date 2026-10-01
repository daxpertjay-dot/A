# 🧠 Brainrot Runner

A Subway Surfers-style endless runner for Roblox. The evil Brainrot guy **Verity** (with his henchman Tung Tung Tung Sahur) has kidnapped the Brainrots. You escape through the streets of Brainrot City, grab coins and power-ups, and rescue caged Brainrots. Rescued Brainrots stand on your base and raise your **score multiplier**. Every run's score levels them up, stylish play builds a **combo**, and your base charges **Hype** while you're away. Coins buy upgrades.

```
YOUR BASE (Brainrots on pedestals = ⭐ score multiplier, ⚡ Hype charging up)
  → walk into YOUR RUN PORTAL → Verity bursts out of his HQ → 3… 2… 1… RUN!
  → dodge · jump · roll · 🔥 build a combo · grab 🪙 coins, 🧲🚀👟✖️2 power-ups, ❓ mystery boxes
  → boost-jump onto 🚌 buses and 🚇 tunnel roofs · 🔓 rescue caged Brainrots
  → caught → SAVE ME (coins) or END
  → RESULTS: score, coins, rescues, Brainrot XP and level-ups → back to your base
```

Everything (lobby, bases, track, characters, UI) is built from code, so it runs in an empty place with no uploaded assets.

## Getting it into Roblox Studio

**Option A: open the built place (quickest)**

```bash
rojo build default.project.json -o BrainrotRunner.rbxl
```

Open the file in Studio and press **Play**. To put it on your experience, use **File → Publish to Roblox As…** and choose your place.

**Option B: live-sync with Rojo**

1. Install [Rojo](https://rojo.space) (the CLI plus the Studio plugin). VS Code is not needed.
2. Run `rojo serve` in this folder.
3. In Studio, go to **Plugins → Rojo → Connect**.
4. Press **Play**.

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

### 🔥 Style combo: rewards focus
Playing well builds a combo that multiplies your multiplier, from x1.0 up to **x3.0** (20 stacks):

| Trick | Stacks |
|---|---|
| Clear an obstacle (jump over / roll under) | +1 |
| **Near miss**: change lanes just before hitting something (within 0.5s) | +2 |
| **Roof run**: land on a bus or tunnel roof | +2 |
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
Verity keeps them in cages on the tracks; run through a cage to rescue it. Rarer Brainrots only appear further into a run:

| Brainrot | Appears after |
|---|---|
| Chimpanzini | 0m |
| Patapim | 100m |
| Tralalero | 250m |
| Ballerina | 400m |
| Bombardiro | 700m |
| Lirilì | 900m |
| Bombombini | 1,200m |
| Cappuccino Assassino | 1,600m |
| Trippi Troppi | 2,200m |

Rescues are kept even if you get caught. Your best Brainrots automatically take the pedestals.

### 🪙 Coins (Subway Surfers style)
- Every coin is worth **1**. A run earns a few hundred: coin lines between obstacles, arcs over barriers that match your jump exactly, and coin lines along the tops of buses and tunnels.
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
| 👟 Super Sneakers | huge jumps: **onto buses and tunnel roofs** | 10s → 20s |
| ✖️2 Score Booster | doubles your multiplier | 10s → 20s |

A **🛹 Hoverboard** (bought with coins, or from daily rewards and mystery boxes) lasts 30s. It **boosts your jump** high enough for buses and tunnel roofs, and it saves you from one crash by breaking instead.

### The chase
Crashes let **Verity** close in:
- **Running into the front** of something you can't break stops you dead.
- **Switching lanes into the side** of something (a bus beside you, a vault wall) bounces you back into your lane. You stumble, drop to 60% speed for a moment and lose half your combo, like in Subway Surfers.

Stumble too much and he's right behind you with his net; one more mistake and he catches you. You can then **SAVE ME** with coins (or Robux) or end the run. **BACK TO BASE** always gets you home, even if you died mid-run or during the "RUN STARTING…" fade.

### The track: Brainrot City streets
You run down the middle of the road at sunset, with shops and apartment blocks on both sides. Sections:

- **Streets**: barriers to jump, signs to roll under, crates to smash.
- **🚌 Buses**: switch lanes around them.
- **🚇 Underpasses**: run straight through.
- **Road works**: scaffolding beams to roll under, barriers to jump.
- **Smash zones**: wooden walls.
- **Bonus vaults** and **rescue cages**.

**Jump boosts and roofs.** A normal jump peaks at about 9 studs. That clears barriers, but it can't reach a bus roof (12.5) or a tunnel roof (16). With a **jump boost** (👟 Super Sneakers or 🛹 a hoverboard) you can jump onto them and run across the top, where the best coin lines are. Notes:

- The roof run also scores a combo bonus.
- Time your jump: hit the tunnel entrance too low and you crash into it.
- Inside a tunnel, the ceiling stops boosted jumps.
- Sneakers often spawn just before buses and tunnels, and a sign marks each tunnel.

Destruction is still in: small things smash, wooden walls break at high speed, and concrete chips with repeated hits.

### Verity
Verity is a big angry Brainrot guy: a giant pink brain with a mustache, a top hat and sneakers, carrying a net, with Tung Tung Tung Sahur running beside him. To use **your own Verity model**, put a Model named `VerityModel` in **ReplicatedStorage**, with its PrimaryPart at the feet and facing forward. The chase and the lobby statue will use it automatically. Optionally, name one of its parts `Bat` to make it swing.

### Flying
With the 🚀 Jetpack your character flies Superman-style: tipped forward, one fist out, with a flaming jetpack on your back. To use a real animation instead, put its ID in `Config.Animations.Fly`.

### Lobby & your base
- The lobby is a blocky street with a conveyor loop, an ⬆️ Upgrades stall, a shop, daily rewards, the leaderboard, and a statue of Verity (WANTED).
- Your base has:
  - your pedestals, with a big **SCORE MULTIPLIER** sign (showing Hype too), with each Brainrot's level above it; locked pedestals can be bought right there
  - your high score
  - your personal run portal
- The HUD buttons open everything from anywhere: Upgrades, Brainrots, Shop, Daily, Top, Stats, My Base.

## Project layout

```
src/
├── shared/                    ReplicatedStorage.Shared
│   ├── Config.luau            ← all tuning: villain, score, levels, combo, Hype, coins, power-ups, speeds, camera
│   ├── PowerUpData.luau       power-ups, durations per level, upgrade costs
│   ├── BrainrotData.luau      Brainrots: multiplier bonus, rarity, where they appear
│   ├── Progression.luau       Brainrot levels/XP, style combo, Hype (shared math)
│   ├── DailyRewardData.luau   7-day reward track
│   ├── ImpactRules.luau       crash rules + jump physics (shared client/server)
│   ├── ModelFactory.luau      blocky Brainrot + villain models
│   └── Remotes.luau · Signal.luau · Util.luau
├── server/                    ServerScriptService.Server
│   ├── Main.server.luau
│   ├── PlayerData.luau        profiles (coins, Brainrots + XP, Hype, pedestals, upgrades, hoverboards, stats)
│   ├── Economy.luau           upgrades, pedestals, hoverboards, daily, Robux receipts
│   ├── Leaderboards.luau      high score + other global boards
│   ├── Lobby/LobbyBuilder.luau  the street, stalls, conveyors, statue
│   ├── Lobby/PlotManager.luau   player bases: pedestals, multiplier sign, run portal
│   └── Run/
│       ├── RunManager.luau    run lifecycle, score, combo, Hype, power-ups, rescues, XP, results
│       ├── TrackGenerator.luau  generates segments ahead / recycles behind
│       ├── Segments.luau      Brainrot City streets: buses, tunnels, obstacles
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
- **Animations**: swap run/jump animation IDs in `Config.Animations`.
