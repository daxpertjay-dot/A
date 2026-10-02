#!/usr/bin/env bash
# Rebuilds the Workspace maps from code: map/Lobby.rbxm (the lobby) and
# map/TrackAreas.rbxm (the run's section templates). Usage:
#   tools/bake_map.sh             both
#   tools/bake_map.sh tracks      just the track areas (or: lobby)
# Note: this replaces the saved maps. If you've edited one in Studio, save
# it over its file instead (right-click Workspace.Lobby / Workspace.TrackAreas
# → Save to File…) so your edits are kept.
set -e
cd "$(dirname "$0")/.."
python3 tests/mirror.py
lune run tools/bake_map.luau -- "$@"
