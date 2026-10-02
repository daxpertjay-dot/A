-- Bakes the maps that live in Workspace from the same code the game uses,
-- headlessly, and saves them for place.project.json:
--
--   map/Lobby.rbxm        Workspace.Lobby        (LobbyBuilder + PlotManager)
--   map/TrackAreas.rbxm   Workspace.TrackAreas   (the run's section templates)
--
-- Run it with tools/bake_map.sh [lobby] [tracks] (both by default).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local H = require("../tests/harness")

local wanted = {}
for _, arg in process.args do
	if arg:sub(1, 1) ~= "-" then
		wanted[arg] = true
	end
end
if next(wanted) == nil then
	wanted = { lobby = true, tracks = true }
end

local function stats(root)
	local parts, models = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Model") then
			models += 1
		end
	end
	return parts, models
end

fs.writeDir("map")

if wanted.lobby then
	local LobbyBuilder = H.require(H.server.Lobby.LobbyBuilder)
	local PlotManager = H.require(H.server.Lobby.PlotManager)
	local lobby = LobbyBuilder.Generate()
	PlotManager.BuildPlots()
	fs.writeFile("map/Lobby.rbxm", roblox.serializeModel({ lobby }))
	print(("baked map/Lobby.rbxm: %d parts, %d models"):format(stats(lobby)))
end

if wanted.tracks then
	local TrackAreas = H.require(H.server.Run.TrackAreas)
	local folder = TrackAreas.Build()
	fs.writeFile("map/TrackAreas.rbxm", roblox.serializeModel({ folder }))
	local sections = 0
	for _, area in folder:GetChildren() do
		sections += #area:GetChildren()
	end
	local parts = stats(folder)
	print(("baked map/TrackAreas.rbxm: %d sections, %d parts"):format(sections, parts))
end

process.exit(0)
