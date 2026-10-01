--!strict
-- Server-controlled endless track. Generates segments ahead of the runner
-- (the player never sees the end of the map) and removes them once they are
-- far enough behind to keep instance counts flat.
--
--   PLAYER → [current] → [generated] → [generated] → … more map generates

local PhysicsService = game:GetService("PhysicsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
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
	})
	table.insert(self.segments, { model = model, startD = -60, endD = length, name = "StartArea", index = 0 })
	self.generatedUntil = length
end

-- Chooses the next segment: weighted random among definitions unlocked at
-- this distance, off cooldown and not an immediate repeat.
function TrackGenerator._choose(self: Track, distance: number): Segments.SegmentDef
	local candidates = {}
	local total = 0
	for _, def in Segments.Definitions do
		local last = self.lastUsed[def.name]
		local offCooldown = last == nil or (self.index - last) > def.cooldown
		local notRepeat = def.name ~= self.lastName or def.name == "Street"
		if distance >= def.minDistance and offCooldown and notRepeat then
			table.insert(candidates, def)
			total += def.weight
		end
	end
	if #candidates == 0 then
		return Segments.Definitions[1]
	end
	local roll = self.rng:NextNumber() * total
	for _, def in candidates do
		if roll < def.weight then
			return def
		end
		roll -= def.weight
	end
	return candidates[#candidates]
end

function TrackGenerator._generateNext(self: Track)
	self.index += 1
	local startD = self.generatedUntil
	local distance = startD * Config.Run.MetersPerStud
	local def = self:_choose(distance)
	local model = newSegmentModel(self.folder, def.name, self.index)
	def.build({
		folder = model,
		origin = self.origin,
		startD = startD,
		length = Config.Run.SegmentLength,
		rng = self.rng,
		difficulty = math.clamp(distance / 4000, 0, 1),
		distance = distance,
	})
	table.insert(self.segments, { model = model, startD = startD, endD = startD + Config.Run.SegmentLength, name = def.name, index = self.index })
	self.lastUsed[def.name] = self.index
	self.lastName = def.name
	self.generatedUntil = startD + Config.Run.SegmentLength
end

-- Makes sure the track exists up to `targetD`.
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
