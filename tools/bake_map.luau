-- Bakes the lobby into a real map: runs LobbyBuilder + PlotManager (the same
-- code the game uses) headlessly and saves the result as map/Lobby.rbxm,
-- which place.project.json puts in Workspace. Run it with tools/bake_map.sh.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local H = require("../tests/harness")

local LobbyBuilder = H.require(H.server.Lobby.LobbyBuilder)
local PlotManager = H.require(H.server.Lobby.PlotManager)

local lobby = LobbyBuilder.Generate()
PlotManager.BuildPlots()

local parts, models = 0, 0
for _, d in lobby:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	elseif d:IsA("Model") then
		models += 1
	end
end

fs.writeDir("map")
fs.writeFile("map/Lobby.rbxm", roblox.serializeModel({ lobby }))
print(("baked map/Lobby.rbxm: %d parts, %d models"):format(parts, models))
require("@lune/process").exit(0)
