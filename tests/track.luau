local H = require("./harness")
local req = H.require
local function count(root, pred) local n = 0 for _, d in root:GetDescendants() do if pred(d) then n += 1 end end return n end
local function isPart(d) return d:IsA("BasePart") end

local PowerUpData = req(H.shared.PowerUpData)
print("powerups", #PowerUpData.List, "jetpack L0", PowerUpData.Duration("Jetpack", 0), "L5", PowerUpData.Duration("Jetpack", 5), "next cost L0", PowerUpData.NextCost(0), "L5", PowerUpData.NextCost(5))
local ModelFactory = req(H.shared.ModelFactory)
local v = ModelFactory.Villain(1); v:PivotTo(H.CFrame.new(0, 0, 0)); print("villain parts", #v:GetChildren())

local LobbyBuilder = req(H.server.Lobby.LobbyBuilder)
local lobby = LobbyBuilder.Build()
local PlotManager = req(H.server.Lobby.PlotManager)
PlotManager.Init()
print("lobby parts", count(lobby, isPart), "prompts", count(lobby, function(d) return d:IsA("ProximityPrompt") end))

local TrackGenerator = req(H.server.Run.TrackGenerator)
local track = TrackGenerator.new(H.Instance.new("Folder"), H.Vector3.new(6000, 0, 0), 42)
local seen, stats = {}, { coins = 0, powerups = {}, boxes = 0, cages = 0, obstacles = 0, segments = 0, parts = 0, standTops = 0, busRoofs = 0, tunnelRoofs = 0 }
local d = 0
while d < 20000 do
	d += 40
	track:Update(d)
	for _, seg in track.segments do
		if not seen[seg.model] then
			seen[seg.model] = true
			stats.segments += 1
			stats[seg.name] = (stats[seg.name] or 0) + 1
			for _, inst in seg.model:GetDescendants() do
				if inst:GetAttribute("Coin") then stats.coins += 1 end
				local pk = inst:GetAttribute("Pickup")
				if pk == "PowerUp" then stats.powerups[inst:GetAttribute("PowerUpId")] = (stats.powerups[inst:GetAttribute("PowerUpId")] or 0) + 1 end
				if pk == "MysteryBox" then stats.boxes += 1 end
				if pk == "Brainrot" then stats.cages += 1 end
				if inst:GetAttribute("ObstacleType") then stats.obstacles += 1 end
				if inst:IsA("BasePart") then stats.parts += 1 end
				if inst.Name == "StandTop" then stats.standTops += 1 end
				if inst.Name == "BusRoof" then stats.busRoofs += 1 end
				if inst.Name == "TunnelRoof" then stats.tunnelRoofs += 1 end
			end
		end
	end
end
for k, v in stats do if type(v) ~= "table" then print(k, v) end end
for k, v in stats.powerups do print("powerup", k, v) end
print(("per segment: %.1f coins, %.1f obstacles, %.0f parts"):format(stats.coins / stats.segments, stats.obstacles / stats.segments, stats.parts / stats.segments))
assert(stats.segments > 100, "track keeps generating")
assert(stats.coins / stats.segments > 8, "enough coins per segment")
assert((stats.Buses or 0) > 0 and (stats.Tunnel or 0) > 0 and (stats.Rescue or 0) > 0, "all segment types appear")
assert(stats.parts / stats.segments < 200, "segments stay light")
print("SMOKE OK")
require("@lune/process").exit(0)
