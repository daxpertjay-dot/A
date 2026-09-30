# 🧠 Brainrot Runner

A Roblox endless runner built around a Brainrot-themed social hub. Players spawn in a chaotic lobby, walk into the run gate, and get chased down a procedurally generated, destructible city by **Tung Tung Tung Sahur**.

```
JOIN → BRAINROT LOBBY → (crates / equipment / shop / collection / leaderboards / daily)
     → walk into RUN GATE → "RUN STARTING..." → STARTING AREA → Sahur intro
     → 3… 2… 1… RUN! → ENDLESS RUN → caught → REVIVE or END → REWARDS → LOBBY
```

The whole game (lobby geometry, track segments, Brainrot models and UI) is built from code, so it runs in an empty place with no uploaded assets.

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

In the lobby you walk around normally and press **E** at stations and NPCs.

## Project layout

```
src/
├── shared/                    ReplicatedStorage.Shared
│   ├── Config.luau            ← all tuning: speeds, camera, chase, destruction, prices
│   ├── EquipmentData.luau     equipment catalog (Shield, Magnet, Speed Boost, Bomb, Coin Doubler)
│   ├── CrateData.luau         crate prices + drop odds
│   ├── BrainrotData.luau      the Brainrot collection
│   ├── DailyRewardData.luau   7-day reward track
│   ├── ImpactRules.luau       what happens when you hit things (shared client/server)
│   ├── ModelFactory.luau      primitive Brainrot models (swap for meshes later)
│   ├── Remotes.luau · Signal.luau · Util.luau
├── server/                    ServerScriptService.Server
│   ├── Main.server.luau
│   ├── PlayerData.luau        DataStore profiles, leaderstats
│   ├── Economy.luau           crates, loadout, daily rewards, Robux receipts
│   ├── Leaderboards.luau      OrderedDataStores + the giant lobby board
│   ├── Lobby/LobbyBuilder.luau  the hub: spawn, stations, NPCs, run gate, decor, secrets
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
    ├── DebrisFX.luau          client-side debris + explosions
    ├── LobbyFX.luau           spinning / dancing / wandering lobby life
    └── UI/ (UIKit, LobbyUI, RunHUD)
```

## How the main systems work

### Lobby hub
`LobbyBuilder` builds the plaza in the layout from the mockup:

- 🏆 leaderboard to the north
- 📦 crates to the west, 🛒 shop to the east
- ⚙️ loadout, 🧠 collection, 🎁 daily reward and 📊 stats stations in the corners
- the 🏃 run gate to the south

The run gate is a giant log-pillared arch with a tunnel and a portal, with a road fading into the distance behind it. Walking into the portal starts a run.

Each station has a Brainrot NPC with a speech bubble and a ProximityPrompt that opens its panel. The lobby is also full of set dressing: a giant Sahur statue, floating props, wonky buildings, animated billboards, wandering Brainrots, and a hidden staircase to a secret golden brain. All of that motion is animated client-side.

### Run controller (client)
- The character is driven kinematically. Default controls are disabled, and the Humanoid is put in the `Physics` state.
- The runner moves forward automatically along 3 fixed lanes at `x = -8 / 0 / 8`, sliding smoothly between them.
- Jumping follows a fixed arc. Rolling shrinks the hitbox and plays a somersault. Pressing roll in the air fast-falls.
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
- **StreamingEnabled**: runs happen far from the lobby (X ≥ 6000). The server calls `RequestStreamAroundAsync` before teleporting, but if you see the track pop in, consider turning streaming off or raising the minimum streaming radius.
