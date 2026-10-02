--!strict
-- The library of track sections the run is generated from.
--
-- Every area (AreaData) has a folder of section templates:
--
--   Workspace.TrackAreas            (map/TrackAreas.rbxm in the place file)
--   ├── Garden   Start_D0_1, Gate_D0_1, Fences_D0_1, Fences_D0_2, HayWagons_D1_1, …
--   └── Beach    Gate_D0_1, Sand_D0_1, SurfShacks_D2_1, Pier_D1_2, …
--
-- They're real models you can edit, duplicate or add in Studio (see
-- Areas/Kit.luau for the layout and attributes). When the server starts it
-- moves the folder to ServerStorage; runs clone sections from it. Without a
-- saved map (e.g. `rojo serve`), the templates are built from code instead.
--
-- A section's start is its PrimaryPart ("Origin"): the track continues from
-- the section's Length attribute along -Z. Keep sections facing -Z.
--
-- Edits are forgiving: parts in Ground become standable, parts in Obstacles
-- become crashable (an obstacle without attributes is an unbreakable Block),
-- tall obstacles get a roof you can land on, and every obstacle's lane and
-- distance along the track are worked out from where it sits.

local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AreaData = require(Shared.AreaData)
local Config = require(Shared.Config)

local Destruction = require(script.Parent.Destruction)
local Kit = require(script.Parent.Areas.Kit)

local BUILDERS: { [string]: { Build: (parent: Instance, origin: Vector3) -> Folder } } = {
	Garden = require(script.Parent.Areas.Garden),
	Beach = require(script.Parent.Areas.Beach),
}

local TrackAreas = {}

TrackAreas.FolderName = "TrackAreas"

export type Template = {
	model: Model,
	area: string,
	kind: string,
	weight: number,
	cooldown: number,
	difficulty: number,
	length: number,
	pivot: CFrame,
}

export type AreaSet = {
	start: Template?,
	gate: Template?,
	-- kind → difficulty → variants
	kinds: { [string]: { [number]: { Template } } },
	weights: { [string]: number },
	cooldowns: { [string]: number },
}

export type Library = { [string]: AreaSet }

local library: Library? = nil

-- Builds every area's templates from code into a new TrackAreas folder.
function TrackAreas.Build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = TrackAreas.FolderName
	for i, area in AreaData.List do
		local builder = BUILDERS[area.id]
		if builder then
			builder.Build(folder, Config.Areas.EditOrigin + Vector3.new(0, 0, -(i - 1) * Config.Areas.AreaSpacing))
		end
	end
	return folder
end

local function setGroup(part: BasePart, group: string)
	if part.CollisionGroup == "Default" then
		part.CollisionGroup = group
	end
end

local function hasGround(model: Instance): boolean
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CollisionGroup == "RunGround" then
			return true
		end
	end
	return false
end

-- Makes an obstacle from Studio edits behave like a built one, and records
-- where it sits in the section (LocalD: its front, distance from the start).
local function prepareObstacle(model: Model, pivot: CFrame)
	if model:GetAttribute("ObstacleType") == nil then
		model:SetAttribute("ObstacleType", "Block")
	end
	if model:GetAttribute("Kind") == nil then
		model:SetAttribute("Kind", model.Name)
	end
	if model:GetAttribute("Tier") == nil then
		Destruction.Setup(model, 4)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CanQuery then
			setGroup(d, "RunObstacle")
		end
	end
	if not hasGround(model) then
		Kit.StandTop(model, pivot.Y)
	end
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local localPos = pivot:PointToObjectSpace(cf.Position)
	model:SetAttribute("LocalD", -(localPos.Z + size.Z / 2))
	if type(model:GetAttribute("Lane")) ~= "number" then
		local lane = 99 -- off the lanes: touching it is always a side bump
		if size.X > 12 then
			lane = 0 -- across the whole path
		else
			for _, id in Kit.LANE_IDS do
				if math.abs(localPos.X - Kit.LANES[id]) < 4 then
					lane = id
				end
			end
		end
		model:SetAttribute("Lane", lane)
	end
end

local function prepare(model: Model, areaId: string): Template?
	local length = model:GetAttribute("Length")
	if type(length) ~= "number" or length <= 0 then
		warn(("TrackAreas: %s.%s has no Length attribute, skipped"):format(areaId, model.Name))
		return nil
	end
	local pivot = model:GetPivot()
	local ground = model:FindFirstChild("Ground")
	if ground then
		for _, d in ground:GetDescendants() do
			if d:IsA("BasePart") then
				setGroup(d, "RunGround")
			end
		end
	end
	local obstacles = model:FindFirstChild("Obstacles")
	if obstacles then
		for _, child in obstacles:GetChildren() do
			local obstacle: Model
			if child:IsA("BasePart") then
				-- A loose part dropped in Obstacles: give it a model of its own.
				obstacle = Instance.new("Model")
				obstacle.Name = child.Name
				obstacle.Parent = obstacles
				child.Parent = obstacle
			elseif child:IsA("Model") then
				obstacle = child
			else
				continue
			end
			prepareObstacle(obstacle, pivot)
		end
	end
	local coins = model:FindFirstChild("Coins")
	if coins then
		for _, d in coins:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Coin") == nil then
				d:SetAttribute("Coin", true)
				d:SetAttribute("Value", Config.Economy.CoinValue)
			end
		end
	end
	local kind = model:GetAttribute("Kind")
	local weight = model:GetAttribute("Weight")
	local cooldown = model:GetAttribute("Cooldown")
	local difficulty = model:GetAttribute("Difficulty")
	return {
		model = model,
		area = areaId,
		kind = if type(kind) == "string" then kind else model.Name,
		weight = if type(weight) == "number" then weight else 1,
		cooldown = if type(cooldown) == "number" then cooldown else 0,
		difficulty = if type(difficulty) == "number" then math.clamp(math.floor(difficulty), 0, 2) else 0,
		length = length,
		pivot = pivot,
	}
end

local function index(folder: Instance): Library
	local lib: Library = {}
	for _, areaFolder in folder:GetChildren() do
		local areaId = areaFolder.Name
		if not AreaData.Get(areaId) then
			continue
		end
		local set: AreaSet = { kinds = {}, weights = {}, cooldowns = {} }
		for _, child in areaFolder:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local t = prepare(child, areaId)
			if not t then
				continue
			end
			if t.kind == "Start" then
				set.start = t
			elseif t.kind == "Gate" then
				set.gate = t
			elseif t.weight > 0 then
				local byDifficulty = set.kinds[t.kind] or {}
				set.kinds[t.kind] = byDifficulty
				byDifficulty[t.difficulty] = byDifficulty[t.difficulty] or {}
				table.insert(byDifficulty[t.difficulty], t)
				set.weights[t.kind] = math.max(set.weights[t.kind] or 0, t.weight)
				set.cooldowns[t.kind] = math.max(set.cooldowns[t.kind] or 0, t.cooldown)
			end
		end
		if next(set.kinds) then
			lib[areaId] = set
		end
	end
	return lib
end

-- The section library: the saved map's templates if the place has them,
-- otherwise built from code. Loaded once.
function TrackAreas.Load(): Library
	if library then
		return library
	end
	local folder = workspace:FindFirstChild(TrackAreas.FolderName) or ServerStorage:FindFirstChild(TrackAreas.FolderName)
	if not folder then
		folder = TrackAreas.Build()
	end
	assert(folder, "no track areas")
	-- Out of the world: players never see the templates, only runs' clones.
	pcall(function()
		folder.Parent = ServerStorage
	end)
	local lib = index(folder)
	assert(lib[AreaData.First.id], "the first area has no sections")
	library = lib
	return lib
end

-- A copy of a template placed at `startD` along a run's track. Obstacles
-- get their TrackD; the copy isn't parented yet.
function TrackAreas.Place(template: Template, origin: Vector3, startD: number): Model
	local clone = template.model:Clone()
	local target = CFrame.new(origin + Vector3.new(0, 0, -startD))
	local delta = target * template.pivot:Inverse()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	local obstacles = clone:FindFirstChild("Obstacles")
	if obstacles then
		for _, m in obstacles:GetChildren() do
			local localD = m:GetAttribute("LocalD")
			if type(localD) == "number" then
				m:SetAttribute("TrackD", startD + localD)
			end
		end
	end
	return clone
end

return TrackAreas
