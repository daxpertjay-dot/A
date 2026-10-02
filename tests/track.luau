local H = require("./harness")
local req = H.require
local function count(root, pred) local n = 0 for _, d in root:GetDescendants() do if pred(d) then n += 1 end end return n end
local function isPart(d) return d:IsA("BasePart") end

local PowerUpData = req(H.shared.PowerUpData)
print("powerups", #PowerUpData.List, "jetpack L0", PowerUpData.Duration("Jetpack", 0), "L5", PowerUpData.Duration("Jetpack", 5), "next cost L0", PowerUpData.NextCost(0), "L5", PowerUpData.NextCost(5))
local ModelFactory = req(H.shared.ModelFactory)
local v = ModelFactory.Villain(1); v:PivotTo(H.CFrame.new(0, 0, 0)); print("villain parts", #v:GetChildren())

local LobbyBuilder = req(H.server.Lobby.LobbyBuilder)
-- Build the lobby with the square stud texture switched on.
local Config = req(H.shared.Config)
Config.Lobby.StudTexture = "rbxassetid://1"
local lobby = LobbyBuilder.Build()
local PlotManager = req(H.server.Lobby.PlotManager)
PlotManager.Init()
local textures = count(lobby, function(d) return d:IsA("Texture") end)
print("lobby parts", count(lobby, isPart), "prompts", count(lobby, function(d) return d:IsA("ProximityPrompt") end), "stud textures", textures)
assert(textures > 1000, "lobby parts get the stud texture")
local grass = lobby:FindFirstChild("Ground"):FindFirstChild("Grass") :: any
assert(grass and grass:FindFirstChild("Studs") and grass.TopSurface == H.Enum.SurfaceType.Smooth, "textured parts drop the classic studs")

-- The track is generated from the baked section templates in the place
-- file (map/TrackAreas.rbxm → Workspace.TrackAreas), like in the game.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local areasMap = roblox.deserializeModel(fs.readFile("map/TrackAreas.rbxm"))[1]
areasMap.Parent = H.workspace
local library = req(H.server.Run.TrackAreas).Load()
assert(library.Garden.start and library.Garden.start.model:IsDescendantOf(areasMap), "sections come from the saved map")
assert(library.Garden.start.model.Ground:FindFirstChild("Path").CollisionGroup == "RunGround", "saved ground keeps its collision group")
local TrackGenerator = req(H.server.Run.TrackGenerator)
local BrainrotData = req(H.shared.BrainrotData)
-- Generates `untilD` studs of track and gathers what's in it.
local function survey(track, untilD)
	local seen, stats = {}, { coins = 0, powerups = {}, boxes = 0, cages = 0, obstacles = 0, segments = 0, parts = 0, standTops = 0, roofs = 0, tunnelRoofs = 0, areas = {}, firstD = {} }
	local d = 0
	while d < untilD do
		d += 40
		track:Update(d)
		for _, seg in track.segments do
			if not seen[seg.model] then
				seen[seg.model] = true
				stats.segments += 1
				local key = seg.area .. "." .. seg.kind
				stats[key] = (stats[key] or 0) + 1
				stats.areas[seg.area] = (stats.areas[seg.area] or 0) + 1
				stats.firstD[seg.area] = stats.firstD[seg.area] or seg.startD
				assert(seg.model:FindFirstChild("Spots") == nil, "spots are filled and removed")
				for _, inst in seg.model:GetDescendants() do
					if inst:GetAttribute("Coin") then stats.coins += 1 end
					local pk = inst:GetAttribute("Pickup")
					if pk == "PowerUp" then stats.powerups[inst:GetAttribute("PowerUpId")] = (stats.powerups[inst:GetAttribute("PowerUpId")] or 0) + 1 end
					if pk == "MysteryBox" then stats.boxes += 1 end
					if pk == "Brainrot" then
						stats.cages += 1
						local b = BrainrotData.Get(inst:GetAttribute("BrainrotId"))
						assert(b and b.area == seg.area, "caged Brainrots come from the area they're in")
						local m = inst:GetAttribute("Mutation")
						if m then stats["mutated " .. m] = (stats["mutated " .. m] or 0) + 1 end
					end
					if inst:GetAttribute("ObstacleType") then
						stats.obstacles += 1
						local trackD, lane = inst:GetAttribute("TrackD"), inst:GetAttribute("Lane")
						assert(type(trackD) == "number" and trackD >= seg.startD - 1 and trackD <= seg.endD + 1, ("obstacle TrackD inside its section: %s %s d=%s in %s..%s localD=%s"):format(seg.name, inst.Name, tostring(trackD), seg.startD, seg.endD, tostring(inst:GetAttribute("LocalD"))))
						assert(type(lane) == "number", "obstacle has a lane")
					end
					if inst:IsA("BasePart") then stats.parts += 1 end
					if inst.Name == "StandTop" then stats.standTops += 1 end
					if inst.Name == "HayTop" or inst.Name == "ShackRoof" then stats.roofs += 1 end
					if inst.Name == "TunnelRoof" then stats.tunnelRoofs += 1 end
				end
			end
		end
	end
	return stats
end
local function report(stats)
	for k, v in stats do if type(v) ~= "table" then print(k, v) end end
	for k, v in stats.powerups do print("powerup", k, v) end
	for k, v in stats.areas do print("area", k, v, "from d", stats.firstD[k]) end
	print(("per segment: %.1f coins, %.1f obstacles, %.0f parts"):format(stats.coins / stats.segments, stats.obstacles / stats.segments, stats.parts / stats.segments))
end

-- At ×1 the whole 20 km is the Garden (the Beach starts at 100,000 score).
local stats = survey(TrackGenerator.new(H.Instance.new("Folder"), H.Vector3.new(6000, 0, 0), 42), 20000)
report(stats)
assert(stats.segments > 100, "track keeps generating")
assert(stats.coins / stats.segments > 8, "enough coins per segment")
for _, kind in { "Fences", "Shop", "HayWagons", "Greenhouse", "Barn", "Rescue" } do
	assert((stats["Garden." .. kind] or 0) > 0, "garden section appears: " .. kind)
end
assert(not stats.areas.Beach, "no beach before 100,000 score")
assert(stats.parts / stats.segments < 220, "segments stay light")
assert(stats.obstacles / stats.segments < 5, "the track isn't cluttered")
local powerups = 0
for _, n in stats.powerups do powerups += n end
assert(powerups / stats.segments < 0.3, "power-ups aren't too common")

-- At ×20 the score passes 100,000 at 5,000 studs: the Beach gate, then beach sections.
local fast = survey(TrackGenerator.new(H.Instance.new("Folder"), H.Vector3.new(6000, 0, 0), 43, function(d) return d * 20 end), 15000)
report(fast)
assert(fast["Beach.Gate"] == 1, "one beach gate")
assert(fast.firstD.Beach >= 5000 and fast.firstD.Beach < 5000 + 130, "the beach starts at the milestone")
for _, kind in { "Sand", "SurfShacks", "Pier", "Tiki", "Rescue" } do
	assert((fast["Beach." .. kind] or 0) > 0, "beach section appears: " .. kind)
end
assert(fast.roofs > 0 and fast.tunnelRoofs > 0)

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
