#!/usr/bin/env bash
# Rebuilds map/Lobby.rbxm (the lobby map in Workspace) from LobbyBuilder.
# Note: this replaces the saved map. If you've edited the lobby in Studio,
# save it over map/Lobby.rbxm instead (right-click Workspace.Lobby → Save to
# File…) so your edits are kept.
set -e
cd "$(dirname "$0")/.."
python3 tests/mirror.py
lune run tools/bake_map.luau
