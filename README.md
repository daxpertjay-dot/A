# 🧠 Brainrot Runner

A Subway Surfers-style endless runner for Roblox. The evil Brainrot guy **Verity** (with his henchman Tung Tung Tung Sahur) has kidnapped the Brainrots. You escape across the rooftops of Brainrot City, grab coins and power-ups, and rescue caged Brainrots. Rescued Brainrots stand on your base and raise your **score multiplier**, and coins buy upgrades.

```
YOUR BASE (Brainrots on pedestals = ⭐ score multiplier)
  → walk into YOUR RUN PORTAL → Verity bursts out of his rooftop stairwell → 3… 2… 1… RUN!
  → dodge · jump · roll · grab 🪙 coins, 🧲🚀👟✖️2 power-ups, ❓ mystery boxes
  → 🔓 rescue caged Brainrots → caught → SAVE ME (coins) or END
  → RESULTS: score = meters × multiplier, coins, rescues → back to your base
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
- Your multiplier is **1 + the bonus of every Brainrot standing on your base**:

| Rarity | Bonus |
|---|---|
| Uncommon | +1x |
| Rare | +2x |
| Epic | +3x |
| Legendary | +5x |

- Your base starts with **3 pedestals** and holds up to 10. Buying more pedestals with coins raises your multiplier ceiling.
- The **✖️2 Score Booster** power-up doubles the multiplier while it lasts.

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
- Every coin is worth **1**. A run earns a few hundred: coin lines between obstacles, arcs over barriers that match your jump exactly, and train-roof lines.
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
| 👟 Super Sneakers | huge jumps (onto trains) | 10s → 20s |
| ✖️2 Score Booster | doubles your multiplier | 10s → 20s |

A **🛹 Hoverboard** (bought with coins, or from daily rewards and mystery boxes) lasts 30s. It saves you from one crash by breaking instead.

### The chase
Crashes let **Verity** close in. Stumble too much and he's right behind you with his net; one more mistake and he catches you. You can then **SAVE ME** with coins (or Robux) or end the run.

### The track: Brainrot City Rooftops
You run across the roofs of the city at sunset, using Subway Surfers lanes but up high:

- **Roofs change height**: ramps climb to taller buildings, and you drop down to lower ones.
- **Leap** buildings end in a gap. Jump it (the coins show the arc, and sometimes a plank bridges one lane). If you fall in, Verity gets you; a revive puts you on the next roof.
- **You can stand on everything you can reach.** AC units, barriers, walls and billboards all have tops you can land on, and **rooftop sheds** can be run along via their ramps. With 👟 Super Sneakers you can hop onto almost anything.
- Other sections: glass **penthouses**, **smash zones** (wooden walls), **bonus vaults** and **rescue cages**.

Destruction is still in: small things smash, wooden walls break at high speed, and concrete chips with repeated hits.

### Verity
Verity is a big angry Brainrot guy: a giant pink brain with a mustache, a top hat and sneakers, carrying a net, with Tung Tung Tung Sahur running beside him. To use **your own Verity model**, put a Model named `VerityModel` in **ReplicatedStorage**, with its PrimaryPart at the feet and facing forward. The chase and the lobby statue will use it automatically. Optionally, name one of its parts `Bat` to make it swing.

### Flying
With the 🚀 Jetpack your character flies Superman-style: tipped forward, one fist out, with a flaming jetpack on your back. To use a real animation instead, put its ID in `Config.Animations.Fly`.

### Lobby & your base
- The lobby is a blocky street with a conveyor loop, an ⬆️ Upgrades stall, a shop, daily rewards, the leaderboard, and a statue of Verity (WANTED).
- Your base has:
  - your pedestals, with a big **SCORE MULTIPLIER** sign; locked pedestals can be bought right there
  - your high score
  - your personal run portal
- The HUD buttons open everything from anywhere: Upgrades, Brainrots, Shop, Daily, Top, Stats, My Base.

## Project layout

```
src/
├── shared/                    ReplicatedStorage.Shared
│   ├── Config.luau            ← all tuning: villain, score, coins, prices, power-ups, speeds, camera
│   ├── PowerUpData.luau       power-ups, durations per level, upgrade costs
│   ├── BrainrotData.luau      Brainrots: multiplier bonus, rarity, where they appear
│   ├── DailyRewardData.luau   7-day reward track
│   ├── ImpactRules.luau       crash rules + jump physics (shared client/server)
│   ├── ModelFactory.luau      blocky Brainrot + villain models
│   └── Remotes.luau · Signal.luau · Util.luau
├── server/                    ServerScriptService.Server
│   ├── Main.server.luau
│   ├── PlayerData.luau        profiles (coins, Brainrots, pedestals, upgrades, hoverboards, stats)
│   ├── Economy.luau           upgrades, pedestals, hoverboards, daily, Robux receipts
│   ├── Leaderboards.luau      high score + other global boards
│   ├── Lobby/LobbyBuilder.luau  the street, stalls, conveyors, statue
│   ├── Lobby/PlotManager.luau   player bases: pedestals, multiplier sign, run portal
│   └── Run/
│       ├── RunManager.luau    run lifecycle, score, power-ups, rescues, revive, results
│       ├── TrackGenerator.luau  generates segments ahead / recycles behind
│       ├── Segments.luau      Brainrot City Rooftops segment library
│       └── Destruction.luau   breakable walls & debris
└── client/                    StarterPlayerScripts.Client
    ├── Main.client.luau       lobby ⇄ run orchestration
    ├── InputController.luau   lanes / jump / roll / hoverboard (+ swipes, gamepad)
    ├── RunController.luau     movement state machine, power-ups, score, collisions
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
