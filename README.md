# 🧠 Brainrot Runner

A Roblox endless runner with a blocky, tycoon-style lobby (in the spirit of Steal a Brainrot and Grow a Garden). Every player gets their own base on the street. You catch Brainrots on runs; they earn coins on your base, and one of them runs with you as a buddy with perks. Meanwhile **Tung Tung Tung Sahur** chases you down a procedurally generated, destructible city.

```
JOIN → YOUR BASE (Brainrots earn coins · collect pad · buddy · equipment)
     → walk into YOUR RUN PORTAL → "RUN STARTING..." → Sahur intro → 3… 2… 1… RUN!
     → dodge / smash / CATCH BRAINROTS → caught → REVIVE or END → REWARDS → back to your base
```

The whole game (lobby, plots, track segments, Brainrot models and UI) is built from code, so it runs in an empty place with no uploaded assets.

## Getting it into Roblox Studio

**Option A: open the built place (quickest)**

```bash
rojo build default.project.json -o BrainrotRunner.rbxl
```

Open `BrainrotRunner.rbxl` in Studio and press **Play**. To put it on an existing experience, use **File → Publish to Roblox As…** and pick your place.

**Option B: live-sync into your existing place**

1. Install [Rojo](https://rojo.space) (CLI plus the Studio plugin).
2. In this folder, run `rojo serve`.
3. Open your place in Studio, go to **Plugins → Rojo → Connect**.
4. Press **Play**. Edits to files in `src/` sync into Studio instantly.

Live sync overwrites the synced containers: `ReplicatedStorage.Shared`, `ServerScriptService.Server` and `StarterPlayerScripts.Client`.

To use DataStores and leaderboards in Studio, turn on **Game Settings → Security → Enable Studio Access to API Services**. Without it, the game falls back to session-only data.

## Controls (during a run)

| Action | Keyboard | Mobile | Gamepad |
|---|---|---|---|
| Change lane | A / D or ← / → | swipe left / right | D-pad / left stick |
| Jump | W / ↑ / Space | swipe up | A |
| Roll (fast-fall in the air) | S / ↓ | swipe down | B |
| Equipment slot 1–3 | 1 / 2 / 3 | tap the buttons | X / Y / RB |

In the lobby you walk around normally. Use the HUD buttons, or press **E** at stations.

## Project layout

```
src/
├── shared/                    ReplicatedStorage.Shared
│   ├── Config.luau            ← all tuning: speeds, camera, chase, destruction, prices
│   ├── EquipmentData.luau     equipment catalog (Shield, Magnet, Speed Boost, Bomb, Coin Doubler)
│   ├── CrateData.luau         crate prices + drop odds
│   ├── BrainrotData.luau      Brainrots: income, catch rarity, buddy perks
│   ├── DailyRewardData.luau   7-day reward track
│   ├── ImpactRules.luau       what happens when you hit things (shared client/server)
│   ├── ModelFactory.luau      primitive Brainrot models (swap for meshes later)
│   ├── Remotes.luau · Signal.luau · Util.luau
├── server/                    ServerScriptService.Server
│   ├── Main.server.luau
│   ├── PlayerData.luau        DataStore profiles, leaderstats
│   ├── Economy.luau           crates, loadout, daily rewards, Robux receipts
│   ├── Leaderboards.luau      OrderedDataStores + the giant lobby board
│   ├── Lobby/LobbyBuilder.luau  blocky street, shops, conveyors, public run gate
│   ├── Lobby/PlotManager.luau   player bases: pedestals, income pad, buddy, equipment, run portal
│   └── Run/
│       ├── RunManager.luau    run lifecycle, validation, rewards
│       ├── TrackGenerator.luau  generates segments ahead / recycles behind
│       ├── Segments.luau      segment library + obstacles
│       └── Destruction.luau   health / tiers / damage states / explosions
└── client/                    StarterPlayerScripts.Client
    ├── Main.client.luau       lobby ⇄ run orchestration
    ├── InputController.luau   Left / Right / Jump / Roll (+ swipes, gamepad)
    ├── RunController.luau     Subway Surfers-style movement state machine + collisions
    ├── RunCamera.luau         behind/above chase cam, FOV, shake, Sahur intro shot
    ├── Chaser.luau            Tung Tung Tung Sahur
    ├── Buddy.luau             your run buddy jogging beside you
    ├── DebrisFX.luau          client-side debris + explosions
    ├── LobbyFX.luau           spinning / dancing / wandering lobby life, conveyor stripes
    └── UI/ (UIKit, LobbyUI, RunHUD)
```

## How the main systems work

### Lobby: street, conveyors and bases
- `LobbyBuilder` builds a blocky street with classic studs (`Config.Lobby.UseStuds`). Down the middle are the 📦 crate shop, 🛒 shop, 🎁 daily reward, 🏆 leaderboard and a public run gate.
- A **conveyor loop** runs around the street. The belts are anchored parts with a velocity, so they carry players; the moving yellow stripes are drawn client-side.
- **Everything opens from anywhere** via the HUD buttons on the left (Crates, Gear, Brainrots, Shop, Daily, Top, Stats, My Base). The world stations open the same panels.
- **Crates open where you buy them.** "BUY & OPEN" charges you and plays the reveal immediately. Crates you earned (daily, run vaults) open from the same panel.

### Your base (`PlotManager`)
Each player is assigned one of 8 plots, and you spawn there. A plot has:

- **8 Brainrot pedestals.** Your best earners are displayed and each earns coins per second.
- A **💰 collect pad.** Step on it to bank what they earned. You also get offline earnings at half speed, capped at 2h.
- A **🤝 buddy pad.** Your chosen run buddy stands here; press E to change it.
- **⚙️ Equipment stands** showing your loadout (press E to change it).
- A **mini run lane** ending in your personal **🏃 START RUN portal**. Only the owner can use it.

### Brainrots
- **Catch them in runs.** Brainrot Special sections put a Brainrot inside a glowing ring in one lane; run through it to catch it. Rarer ones appear less often and only further into a run.
- **Income.** They earn coins/sec on your base: Uncommon 3, Rare 8, Epic 20, Legendary 50.
- **Run buddy.** Pick one in the Brainrots panel. It jogs beside you and grants its perk:

| Brainrot | Perk |
|---|---|
| Tung Tung Tung Sahur | +2s head start |
| Tralalero Tralala | always-on coin magnet |
| Bombardiro Crocodilo | +1 charge on all equipment |
| Ballerina Cappuccina | escape Sahur 40% faster |
| Brr Brr Patapim | crashes cost 30% less |
| Lirilì Larilà | start with a 6s shield |
| Chimpanzini Bananini | +10% coins |
| Cappuccino Assassino | smash wooden walls at lower speed |
| Bombombini Gusini | +25% coins |
| Trippi Troppi | big magnet + 15% coins |

### Run controller (client)
- The character is driven kinematically. Default controls are disabled, and the Humanoid is put in the `Physics` state.
- The runner moves forward automatically along 3 fixed lanes at `x = -8 / 0 / 8`, sliding smoothly between them.
- Jumping follows a fixed arc. Rolling shrinks the hitbox and plays a somersault. Pressing roll in the air fast-falls.
- Jumping **instantly cancels a roll**. A jump pressed up to 0.18s before landing fires on touchdown (`Config.Run.JumpBuffer`).
- Run and jump animations come from `Config.Animations`. A list of Roblox animation-pack IDs is in the comments there, so you can swap in any pack or your own uploads.
- Movement states: `Running → Jumping → Falling → Running`, `Rolling → Running`, `Staggered`, `Caught`.
- Speed follows `Config.Run.SpeedCurve` (45 → 48 → 52 → 58 → 70 studs/s at 0 / 500 / 1000 / 2000 / 5000 m).
- Ground and obstacles are found with raycasts and box queries on dedicated collision groups (`RunGround`, `RunObstacle`). This lets the runner go up ramps, run across train roofs, and pass through scenery.

### Chase
The gap to Tung Tung Tung Sahur is measured in seconds.

- It starts at 10s and slowly recovers over time.
- Crashes shrink it.
- A 💣 bomb pushes him back.
- When it drops into the danger zone, he appears right behind you with his bat.
- When it hits 0 you're caught, and you can revive with coins (the cost doubles each time) or with Robux.

### Procedural track (server)
`TrackGenerator` keeps about 600 studs of track generated ahead and deletes segments that are 2 behind.

It picks from a weighted library of segments, each with a minimum distance and a cooldown: Straight, Intersection, Alley, Construction, Parking Lot, Tunnel, Highway, Building, Ramp (trains you can run on), Destruction (vault), and Brainrot Special.

Every obstacle row leaves at least one lane you can get through without breaking anything, and coin trails guide you through the gaps.

### Destruction
Destructible objects carry `Health`, `Tier`, `ExplosionResistance`, `CollisionDamage` and `DestructionEffect` attributes.

| Tier | Examples | Running into it | Equipment |
|---|---|---|---|
| 1 Breakable | barricades, crate stacks, signs | smashes, you slow down a bit | any bomb |
| 2 Heavy | wooden walls, cars | crash through at high speed (≥56 studs/s) or with ⚡ boost; otherwise bump and chip it | any bomb |
| 3 Major | concrete walls | bump + chip (multiple hits break it) | 💣 Brainrot Bomb and up |
| 4 Indestructible | steel barriers, pipes, trains | bump, change lanes! | — |

- Walls are built from bricks. Damage knocks out the bricks nearest the impact, and destroyed objects leave rubble behind.
- The server is authoritative, and debris is simulated only on the owning client (capped and cleaned up after 3s).
- Your own crashes are predicted instantly on the client, so impacts feel immediate.
- **Destruction vaults** are the alternate paths. The middle lane is sealed behind a 💥 BONUS wall, with a bonus crate, an equipment box and a coin line inside.

### Equipment, crates, progression
- Equipment is 14 items across 5 abilities and 3 rarities. Duplicates level an item up, which adds duration/radius and an extra charge at level 3.
- The loadout has 3 slots, unlocked at 0, 5 and 20 runs.
- Crates can be bought with coins or Robux. The opening animation is a slot-machine reel.
- The daily reward is a 7-day streak. The Brainrot collection is unlocked by encountering Brainrots in special segments.
- Five global leaderboards: Distance, Coins, Runs, Survival, Equipment.

## Things to set up

- **Robux products**: create developer products and put their IDs in `Config.DeveloperProducts`. Robux buttons do nothing until then.
- **Sounds**: add asset IDs to `Config.Sounds`. The game is silent until you do.
- **Studs**: the lobby uses classic `Studs`/`Inlet` part surfaces. If your place doesn't show them, set `Config.Lobby.UseStuds = false` or swap in a stud texture.
- **StreamingEnabled**: runs happen far from the lobby (X ≥ 6000). The server calls `RequestStreamAroundAsync` before teleporting, but if you see the track pop in, consider turning streaming off or raising the minimum streaming radius.
