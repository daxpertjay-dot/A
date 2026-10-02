# Brainrot Runner — notes for Claude

A Roblox endless runner (Subway Surfers style) written in Luau and synced
with Rojo. README.md describes the game design; this file is how to work on it.

## Commands

```bash
selene src                                            # lint (must be 0 errors / 0 warnings)
tests/run.sh                                          # headless tests (lune), ~2-3 min
tests/run.sh boost sim                                # just some of them
tools/bake_map.sh [lobby] [tracks]                    # → map/Lobby.rbxm, map/TrackAreas.rbxm (both by default)
lune run tools/milestones.luau                        # score milestone math (after tests/mirror.py)
python3.11 tools/blender/props.py                     # lobby props → assets/models/*.fbx (needs `pip install bpy`)
rojo build place.project.json -o build/BrainrotRunner.rbxl     # place file for Studio (with the map)
```

There is no Roblox Studio here: the Lune tests are the only way to run the
code. Run selene and the tests before every commit. After a change the user
will play, rebuild the .rbxl and send it to them.

The lobby is a real map (`Workspace.Lobby`, file `map/Lobby.rbxm`) that the
user edits in Studio. After changing `LobbyBuilder`/`PlotManager` building
code, re-run `tools/bake_map.sh lobby`. That overwrites the map, so first check
whether the user has committed their own edited `map/Lobby.rbxm`.
The run's track sections are a map too (`Workspace.TrackAreas`, file
`map/TrackAreas.rbxm`); after changing `Run/Areas/*`, re-run
`tools/bake_map.sh tracks`, with the same check first. The track test
generates from the saved file, so a stale one shows up there.
`default.project.json` (rojo serve) deliberately leaves Workspace alone.
There's no way to see the maps here except by rendering the part data
(deserialize the rbxm in Lune and draw it). Lune doesn't save a Model's
WorldPivot, so anything that must keep its pivot through a map file needs a
PrimaryPart (track sections have an `Origin` part).

## Layout

- `src/shared` → ReplicatedStorage.Shared: `Config` (all tuning), data
  modules (`AreaData`: run areas and their score thresholds; `BrainrotData`:
  each Brainrot's area), `Progression` (levels, combo, Hype math),
  `ImpactRules`, `ModelFactory`.
- `src/server` → ServerScriptService.Server: `PlayerData` (profiles, saves and
  migrations), `Economy`, `Leaderboards`, `Lobby/*`, `Run/*` (`RunManager`
  owns runs; `TrackGenerator` lays section templates from `TrackAreas`, which
  loads `Workspace.TrackAreas` or builds it with `Areas/Kit` + one builder per
  area; `Pickups` fills each section's spots; `Destruction`).
- `src/client` → StarterPlayerScripts.Client: `RunController` (movement,
  collisions, tricks), `RunCamera`, `Chaser`, `UI/*`, `Main.client` (lobby ⇄ run flow).
- `tests/` → Lune harness and tests (see below).
- `assets/models/*.fbx` are lobby props made in Blender (`tools/blender/props.py`,
  set PROPS_PREVIEW=out.png to render a Cycles preview; EEVEE needs a GPU,
  so use Cycles here). Meshes are named after their colour key in
  `Config.Lobby.PropColors` and the game paints them; "Outline" is an
  inverted-hull toon outline. The user imports them in Studio into
  `ServerStorage.LobbyProps`, and `LobbyBuilder.SwapProps` replaces the
  blocky stand-ins in the map at startup.
- `assets/StudTexture.png` (drawn by `tools/make_stud_texture.py`) is the
  lobby's stud texture. The user uploads it; its id goes in
  `Config.Lobby.StudTexture`. There is no Roblox network access from here,
  so never guess asset ids.

## Conventions

- Every file is `--!strict`. Match the surrounding style: tabs, short header
  comment explaining the module, comments on *why*.
- Tuning numbers go in `Config.luau`, not in gameplay code.
- The server is authoritative: score, coins, pickups, combo, Hype, rewards.
  The client predicts movement, crashes and destruction, and reports what
  happened (`ReportHit`, `ReportStyle`, …). The server validates every
  report (the object belongs to the player's track, it's near the runner,
  and it counts once).
- Track space in `Areas/Kit`: `d` is the distance along a section (forward
  is world -Z), `x` the offset from the centre lane, `y` the height above the
  road. Every obstacle model carries `ObstacleType`, `Kind` and `Lane`; the
  generator adds `TrackD` (its front, distance along the run) when it places
  the section. Templates must stay low-clutter: the user asked for less going on.
- Collision groups: `RunGround` (anything you can stand on), `RunObstacle`
  (anything you can crash into), and scenery stays in Default. The runner is
  kinematic; it never physically collides.
- Profile schema changes: bump `Version` in `PlayerData`, add a step to
  `migrate()`, and give new fields defaults in `newProfile()` (`reconcile`
  fills missing ones).
- Commit messages: a short subject, then a body explaining the player-facing
  change and its cause.

## Tests (tests/)

- `tests/mirror.py` copies `src/` to `tests/.mirror/src` (gitignored) and
  rewrites `x.Position` reads to `__P(x)`, because Lune can't compute a
  part's Position from its CFrame. Write `part.Position` normally in game code.
- `tests/harness.luau` mocks services, remotes and the script tree, and
  gives game code a fixed `CFrame.lookAt` (Lune's flips ±Z directions). Lune
  never fires instance events, so tests call `H.fireAdded(instance)` to
  simulate `DescendantAdded`. The mock `Random` is seeded, so tracks are
  reproducible.
- Each test file prints `<NAME> OK` at the end and asserts along the way:
  - `track`: generation stats over 20 km from the saved map, and the switch to
    the Beach at 100,000 score.
  - `server`: purchases, a full run, tricks, XP, Hype, and the lobby-return paths.
  - `ui`: every panel builds.
  - `boost`: hay wagon and greenhouse roofs, ceilings, side bumps.
  - `sim`: a bot plays 90 seconds.
- A new mechanic should get an assert in the relevant test.
