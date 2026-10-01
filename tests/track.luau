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
				if pk == "Brainrot" then
					stats.cages += 1
					local m = inst:GetAttribute("Mutation")
					if m then stats["mutated " .. m] = (stats["mutated " .. m] or 0) + 1 end
				end
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
-- Mutation odds over many rolls
local MutationData = req(H.shared.MutationData)
local rng = H.Random.new(7)
local rolls, counts = 200000, {}
for _ = 1, rolls do
	local m = MutationData.Roll(rng)
	local k = if m then m.id else "Normal"
	counts[k] = (counts[k] or 0) + 1
end
for _, m in MutationData.List do
	local got = (counts[m.id] or 0) / rolls
	print(("mutation %-8s expected %.3f%% got %.3f%%"):format(m.id, m.chance * 100, got * 100))
	assert(math.abs(got - m.chance) < m.chance * 0.2 + 0.0005, "mutation odds off for " .. m.id)
end
assert(MutationData.Split("TrippiTroppi:Rainbow") == "TrippiTroppi" and select(2, MutationData.Split("TrippiTroppi:Rainbow")) == "Rainbow")
assert(MutationData.Split("TrippiTroppi") == "TrippiTroppi" and select(2, MutationData.Split("TrippiTroppi")) == nil)
assert(MutationData.Label("TrippiTroppi:Gold") == "🥇 Gold Trippi Troppi")
local model = req(H.shared.ModelFactory).Brainrot("TrippiTroppi:Diamond", 1)
assert(model:GetAttribute("Mutation") == "Diamond" and model:FindFirstChildOfClass("Part") ~= nil)
print("SMOKE OK")
require("@lune/process").exit(0)
