--!strict
-- Server-controlled endless track. Generates segments ahead of the runner
-- (the player never sees the end of the map) and removes them once they are
-- far enough behind to keep instance counts flat.
--
--   PLAYER → [current] → [generated] → [generated] → … more map generates

local PhysicsService = game:GetService("PhysicsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BiomeData = require(Shared.BiomeData)
local Config = require(Shared.Config)

local Segments = require(script.Parent.Segments)

local TrackGenerator = {}
TrackGenerator.__index = TrackGenerator

export type SegmentRecord = { model: Model, startD: number, endD: number, name: string, index: number }

export type Track = typeof(setmetatable(
	{} :: {
		folder: Folder,
		origin: Vector3,
		rng: Random,
		segments: { SegmentRecord },
		generatedUntil: number,
		index: number,
		lastUsed: { [string]: number },
		lastName: string,
		lastBiome: string,
	},
	TrackGenerator
))

local groupsRegistered = false

-- Collision groups used by the runner's ground/obstacle probes and debris.
function TrackGenerator.RegisterCollisionGroups()
	if groupsRegistered then
		return
	end
	groupsRegistered = true
	for _, name in { "RunGround", "RunObstacle", "RunPlayer", "Debris", "GroundProbe", "ObstacleProbe" } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	local function set(a: string, b: string, value: boolean)
		PhysicsService:CollisionGroupSetCollidable(a, b, value)
	end
	-- The runner is moved kinematically; it never physically collides.
	for _, other in { "Default", "RunGround", "RunObstacle", "RunPlayer", "Debris", "GroundProbe", "ObstacleProbe" } do
		set("RunPlayer", other, false)
	end
	-- Probes only see their own layer.
	for _, other in { "Default", "RunObstacle", "Debris", "GroundProbe", "ObstacleProbe" } do
		set("GroundProbe", other, false)
	end
	for _, other in { "Default", "RunGround", "Debris", "ObstacleProbe" } do
		set("ObstacleProbe", other, false)
	end
	set("Debris", "Debris", false)
end

function TrackGenerator.new(parent: Instance, origin: Vector3, seed: number): Track
	local folder = Instance.new("Folder")
	folder.Name = "Track"
	folder.Parent = parent

	local self = setmetatable({
		folder = folder,
		origin = origin,
		rng = Random.new(seed),
		segments = {},
		generatedUntil = 0,
		index = 0,
		lastUsed = {},
		lastName = "",
		lastBiome = BiomeData.At(0).id,
	}, TrackGenerator)

	self:_buildStartArea()
	for _ = 1, Config.Run.SegmentsAhead do
		self:_generateNext()
	end
	return self
end

local function newSegmentModel(parent: Instance, name: string, index: number): Model
	local model = Instance.new("Model")
	model.Name = ("%03d_%s"):format(index, name)
	local coins = Instance.new("Folder")
	coins.Name = "Coins"
	coins.Parent = model
	local pickups = Instance.new("Folder")
	pickups.Name = "Pickups"
	pickups.Parent = model
	model.Parent = parent
	return model
end

function TrackGenerator._buildStartArea(self: Track)
	local length = Config.Run.StartAreaLength
	local model = newSegmentModel(self.folder, "StartArea", 0)
	Segments.BuildStartArea({
		folder = model,
		origin = self.origin,
		startD = 0,
		length = length,
		rng = self.rng,
		difficulty = 0,
		distance = 0,
		biome = BiomeData.At(0),
	})
	table.insert(self.segments, { model = model, startD = -60, endD = length, name = "StartArea", index = 0 })
	self.generatedUntil = length
end

local defsByName: { [string]: Segments.SegmentDef } = {}
for _, def in Segments.Definitions do
	defsByName[def.name] = def
end

-- Chooses the next segment: weighted by the current biome's segment table,
-- skipping ones on cooldown and immediate repeats.
function TrackGenerator._choose(self: Track, biome: BiomeData.Biome): Segments.SegmentDef
	local candidates = {}
	local weights = {}
	local total = 0
	for name, weight in biome.segmentWeights do
		local def = defsByName[name]
		if def then
			local last = self.lastUsed[def.name]
			local offCooldown = last == nil or (self.index - last) > def.cooldown
			local notRepeat = def.name ~= self.lastName or def.name == "Straight" or def.name == "Meadow"
			if offCooldown and notRepeat then
				table.insert(candidates, def)
				table.insert(weights, weight)
				total += weight
			end
		end
	end
	if #candidates == 0 then
		return defsByName.Straight
	end
	local roll = self.rng:NextNumber() * total
	for i, def in candidates do
		if roll < weights[i] then
			return def
		end
		roll -= weights[i]
	end
	return candidates[#candidates]
end

function TrackGenerator._generateNext(self: Track)
	self.index += 1
	local startD = self.generatedUntil
	local distance = startD * Config.Run.MetersPerStud
	local biome = BiomeData.At(distance)
	-- Crossing into a new biome always starts with its gate.
	local def = if biome.id ~= self.lastBiome then defsByName.BiomeGate else self:_choose(biome)
	self.lastBiome = biome.id
	local model = newSegmentModel(self.folder, def.name, self.index)
	model:SetAttribute("Biome", biome.id)
	def.build({
		folder = model,
		origin = self.origin,
		startD = startD,
		length = Config.Run.SegmentLength,
		rng = self.rng,
		difficulty = math.clamp(distance / 4000, 0, 1),
		distance = distance,
		biome = biome,
	})
	table.insert(self.segments, { model = model, startD = startD, endD = startD + Config.Run.SegmentLength, name = def.name, index = self.index })
	self.lastUsed[def.name] = self.index
	self.lastName = def.name
	self.generatedUntil = startD + Config.Run.SegmentLength
end

-- Makes sure the track exists up to `targetD` (used before a cannon launch).
function TrackGenerator.EnsureAhead(self: Track, targetD: number)
	local guard = 0
	while self.generatedUntil < targetD and guard < 60 do
		self:_generateNext()
		guard += 1
	end
end

-- Call every frame with the runner's current track distance (studs).
function TrackGenerator.Update(self: Track, playerD: number)
	-- Keep enough track ahead
	local guard = 0
	while self.generatedUntil - playerD < Config.Run.GenerateWhenWithin and guard < 4 do
		self:_generateNext()
		guard += 1
	end
	-- Recycle segments that are far behind
	local cutoff = playerD - Config.Run.SegmentLength * Config.Run.SegmentsBehind
	while #self.segments > 0 and self.segments[1].endD < cutoff do
		local record = table.remove(self.segments, 1) :: SegmentRecord
		record.model:Destroy()
	end
end

-- Finds the segment that owns an instance (used to validate client reports).
function TrackGenerator.Owns(self: Track, instance: Instance): boolean
	return instance:IsDescendantOf(self.folder)
end

function TrackGenerator.Destroy(self: Track)
	self.folder:Destroy()
end

return TrackGenerator
