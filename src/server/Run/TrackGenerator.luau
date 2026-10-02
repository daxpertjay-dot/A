--!strict
-- Server-controlled endless track. Lays section templates (TrackAreas) end
-- to end ahead of the runner — the player never sees the end of the map —
-- and removes them once they're far enough behind to keep instance counts
-- flat.
--
--   PLAYER → [current] → [section] → [section] → … more track is placed
--
-- The area changes as the run's score climbs (AreaData): when the projected
-- score at the next section reaches the next area, its Gate section goes
-- down and the track continues with that area's sections. Each section
-- gets its own roll of power-ups, mystery boxes and caged Brainrots.

local PhysicsService = game:GetService("PhysicsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AreaData = require(Shared.AreaData)
local Config = require(Shared.Config)

local Pickups = require(script.Parent.Pickups)
local TrackAreas = require(script.Parent.TrackAreas)

local TrackGenerator = {}
TrackGenerator.__index = TrackGenerator

export type SegmentRecord = { model: Model, startD: number, endD: number, name: string, kind: string, area: string, index: number }

export type Track = typeof(setmetatable(
	{} :: {
		folder: Folder,
		origin: Vector3,
		rng: Random,
		library: TrackAreas.Library,
		segments: { SegmentRecord },
		generatedUntil: number,
		index: number,
		areaIndex: number,
		lastKindAt: { [string]: number },
		lastKind: string,
		recent: { Model },
		scoreAt: (d: number) -> number,
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

-- `scoreAt(d)` predicts the run's score when the runner reaches track
-- distance d (studs); it decides which area each new section belongs to.
-- Without it, score = meters run (a ×1 multiplier).
function TrackGenerator.new(parent: Instance, origin: Vector3, seed: number, scoreAt: ((d: number) -> number)?): Track
	local folder = Instance.new("Folder")
	folder.Name = "Track"
	folder.Parent = parent

	local self = setmetatable({
		folder = folder,
		origin = origin,
		rng = Random.new(seed),
		library = TrackAreas.Load(),
		segments = {},
		generatedUntil = 0,
		index = 0,
		areaIndex = 1,
		lastKindAt = {},
		lastKind = "",
		recent = {},
		scoreAt = scoreAt or function(d: number): number
			return d * Config.Run.MetersPerStud * Config.Score.PointsPerMeter
		end,
	}, TrackGenerator)

	local first = self.library[AreaData.First.id]
	local start = first.start or first.gate
	if start then
		self:_place(start, 0)
	end
	for _ = 1, Config.Run.SegmentsAhead do
		self:_generateNext()
	end
	return self
end

-- Fills a placed section's spots: at most one power-up / mystery box from the
-- shared spots, the spots with their own chance, and a caged Brainrot.
function TrackGenerator._fillSpots(self: Track, model: Model, area: string)
	local spots = model:FindFirstChild("Spots")
	if not spots then
		return
	end
	local rng = self.rng
	local pickups = Instance.new("Folder")
	pickups.Name = "Pickups"
	pickups.Parent = model
	local shared: { BasePart } = {}
	local preferred: { BasePart } = {}
	local cages: { BasePart } = {}
	for _, s in spots:GetChildren() do
		if not s:IsA("BasePart") then
			continue
		end
		if s.Name == "CageSpot" then
			table.insert(cages, s)
		elseif s.Name == "PickupSpot" then
			local chance = s:GetAttribute("Chance")
			local prefer = s:GetAttribute("Prefer")
			local at = s.Position - Vector3.new(0, 1, 0)
			if type(chance) == "number" then
				if rng:NextNumber() < chance then
					if prefer == "MysteryBox" then
						Pickups.MysteryBox(pickups, at)
					else
						Pickups.PowerUp(pickups, at, rng, if type(prefer) == "string" then prefer else nil)
					end
				end
			else
				table.insert(shared, s)
				if type(prefer) == "string" then
					table.insert(preferred, s)
				end
			end
		end
	end
	local P = Config.PowerUps
	if #preferred > 0 and rng:NextNumber() < P.BoostBeforeTallChance then
		local s = preferred[rng:NextInteger(1, #preferred)]
		Pickups.PowerUp(pickups, s.Position - Vector3.new(0, 1, 0), rng, s:GetAttribute("Prefer") :: string)
	elseif #shared > 0 then
		local at = shared[rng:NextInteger(1, #shared)].Position - Vector3.new(0, 1, 0)
		if rng:NextNumber() < P.SpawnChancePerSegment then
			Pickups.PowerUp(pickups, at, rng)
		elseif rng:NextNumber() < P.MysteryBoxChancePerSegment then
			Pickups.MysteryBox(pickups, at)
		end
	end
	if #cages > 0 then
		local s = cages[rng:NextInteger(1, #cages)]
		Pickups.Cage(pickups, s.Position - Vector3.new(0, 1, 0), area, rng)
	end
	spots:Destroy()
end

function TrackGenerator._place(self: Track, template: TrackAreas.Template, startD: number)
	local model = TrackAreas.Place(template, self.origin, startD)
	model.Name = ("%03d_%s"):format(self.index, template.model.Name)
	self:_fillSpots(model, template.area)
	-- Parent last: the client registers obstacles as they replicate, so
	-- their attributes must already be set.
	model.Parent = self.folder
	table.insert(self.segments, { model = model, startD = startD, endD = startD + template.length, name = template.model.Name, kind = template.kind, area = template.area, index = self.index })
	self.lastKindAt[template.kind] = self.index
	self.lastKind = template.kind
	table.insert(self.recent, template.model)
	if #self.recent > Config.Areas.RecentTemplates then
		table.remove(self.recent, 1)
	end
	self.generatedUntil = startD + template.length
end

-- Difficulty 0-2: rises with the distance run; later areas start at medium.
function TrackGenerator._difficulty(self: Track, startD: number): number
	local meters = startD * Config.Run.MetersPerStud
	local difficulty = math.clamp(math.floor(meters / Config.Areas.DifficultyStep), 0, 2)
	if self.areaIndex > 1 then
		difficulty = math.max(difficulty, 1)
	end
	return difficulty
end

local function pickWeighted<T>(rng: Random, items: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, item in items do
		total += weightOf(item)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, item in items do
		roll -= weightOf(item)
		if roll < 0 then
			return item
		end
	end
	return items[#items]
end

-- Picks the next section of an area: a kind by weight (off cooldown, and not
-- the same kind twice unless it has no cooldown), then one of that kind's
-- layouts at the hardest difficulty unlocked, avoiding recent repeats.
function TrackGenerator._choose(self: Track, set: TrackAreas.AreaSet, difficulty: number): TrackAreas.Template?
	local kinds = {}
	for kind in set.kinds do
		local cooldown = set.cooldowns[kind] or 0
		local last = self.lastKindAt[kind]
		local offCooldown = last == nil or (self.index - last) > cooldown
		local repeatOk = kind ~= self.lastKind or cooldown == 0
		if offCooldown and repeatOk then
			table.insert(kinds, kind)
		end
	end
	table.sort(kinds) -- same seed, same track
	local kind = pickWeighted(self.rng, kinds, function(k)
		return set.weights[k] or 0
	end)
	if not kind then
		return nil
	end
	local byDifficulty = set.kinds[kind]
	local layouts: { TrackAreas.Template }? = nil
	for level = difficulty, 0, -1 do
		if byDifficulty[level] then
			layouts = byDifficulty[level]
			break
		end
	end
	if not layouts then
		-- Only harder layouts exist for this kind: use the easiest of them.
		for level = difficulty + 1, 2 do
			if byDifficulty[level] then
				layouts = byDifficulty[level]
				break
			end
		end
	end
	if not layouts then
		return nil
	end
	local fresh = {}
	for _, t in layouts do
		if not table.find(self.recent, t.model) then
			table.insert(fresh, t)
		end
	end
	local pool = if #fresh > 0 then fresh else layouts
	return pool[self.rng:NextInteger(1, #pool)]
end

function TrackGenerator._generateNext(self: Track)
	self.index += 1
	local startD = self.generatedUntil
	-- Move on to the next area once the score there would reach it.
	local nextArea = AreaData.List[self.areaIndex + 1]
	if nextArea and self.library[nextArea.id] and self.scoreAt(startD) >= nextArea.fromScore then
		self.areaIndex += 1
		local gate = self.library[nextArea.id].gate
		if gate then
			self:_place(gate, startD)
			return
		end
	end
	local set = self.library[AreaData.List[self.areaIndex].id]
	local template = self:_choose(set, self:_difficulty(startD))
	if not template then
		-- Everything's on cooldown (a tiny edited library): allow anything.
		self.lastKindAt = {}
		self.lastKind = ""
		template = self:_choose(set, self:_difficulty(startD))
	end
	assert(template, "area has no sections")
	self:_place(template, startD)
end

-- The area of the section at track distance d (studs).
function TrackGenerator.AreaAt(self: Track, d: number): string?
	for _, record in self.segments do
		if d >= record.startD and d < record.endD then
			return record.area
		end
	end
	return nil
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
