--!strict
-- Shared toolkit for building run sections (the pieces every area's track
-- is made of). A section is a Model laid out along -Z from its origin (the
-- start of the section, centre lane, road surface), with folders the track
-- generator understands:
--
--   Section (Model)   attributes: Area, Kind, Weight, Cooldown, Difficulty, Length
--   ├── Origin      the PrimaryPart: start of the section, centre lane, road level
--   ├── Ground      everything you can stand on            (RunGround)
--   ├── Obstacles   obstacle Models (ObstacleType = Jump/Block, Kind, Lane)
--   ├── Scenery     looks only, never collides with the runner
--   ├── Coins       coin parts (Coin = true)
--   └── Spots       invisible markers the generator fills in:
--                   PickupSpot (power-up / mystery box) and CageSpot (Brainrot rescue)
--
-- Section space: `d` is distance along the section (forward is -Z), `x` the
-- offset from the centre lane, `y` the height above the road.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local Util = require(Shared.Util)

local Destruction = require(script.Parent.Parent.Destruction)

local Kit = {}

Kit.LANES = Config.Run.LanePositions
Kit.LANE_IDS = { -1, 0, 1 }
Kit.ROAD_WIDTH = 30
Kit.EDGE = Config.Run.SafeZoneAtSegmentEdges

-- Heights the jump-boost rules depend on: a normal jump peaks at ~9 studs
-- (head at ~14.6), boosted jumps reach ~17-19.
Kit.TALL_HEIGHT = 12 -- tall obstacles (wagons, huts); their roof is at 12.5
Kit.TALL_LENGTH = 38
Kit.TUNNEL_CEILING = 15 -- underside of a tunnel roof (a normal jump never touches it)
Kit.TUNNEL_ROOF = 16 -- top of a tunnel roof

export type Ctx = {
	model: Model,
	origin: Vector3,
	length: number,
	rng: Random,
	difficulty: number, -- 0 easy · 1 medium · 2 hard
	ground: Folder,
	obstacles: Folder,
	scenery: Folder,
	coins: Folder,
	spots: Folder,
}

export type ObstacleDef = {
	type: "Jump" | "Block",
	build: (ctx: Ctx, lane: number, d: number) -> Model,
}

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A new, empty section Model at `origin`.
function Kit.Section(parent: Instance, area: string, kind: string, name: string, origin: Vector3, length: number, seed: number, difficulty: number, weight: number): Ctx
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Area", area)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Weight", weight)
	model:SetAttribute("Difficulty", difficulty)
	model:SetAttribute("Length", length)
	-- The section's anchor. A part (not just the model's pivot) so it
	-- survives saving to a map file and moves with the model in Studio.
	local anchor = Util.Part({
		Name = "Origin",
		Parent = model,
		Size = Vector3.new(2, 0.2, 2),
		CFrame = CFrame.new(origin),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	model.PrimaryPart = anchor
	model.Parent = parent
	return {
		model = model,
		origin = origin,
		length = length,
		rng = Random.new(seed),
		difficulty = difficulty,
		ground = folder(model, "Ground"),
		obstacles = folder(model, "Obstacles"),
		scenery = folder(model, "Scenery"),
		coins = folder(model, "Coins"),
		spots = folder(model, "Spots"),
	}
end

function Kit.W(ctx: Ctx, x: number, y: number, d: number): Vector3
	return ctx.origin + Vector3.new(x, y, -d)
end

function Kit.CF(ctx: Ctx, x: number, y: number, d: number): CFrame
	return CFrame.new(Kit.W(ctx, x, y, d))
end

-- Something you can stand on.
function Kit.Ground(ctx: Ctx, props: Util.PartProps): BasePart
	props.Parent = props.Parent or ctx.ground
	props.Material = props.Material or Enum.Material.SmoothPlastic
	local p = Util.Part(props)
	p.CollisionGroup = "RunGround"
	return p
end

-- Looks only: never touched by the runner's probes.
function Kit.Scenery(ctx: Ctx, props: Util.PartProps): BasePart
	props.Parent = props.Parent or ctx.scenery
	props.CanQuery = false
	props.Material = props.Material or Enum.Material.SmoothPlastic
	return Util.Part(props)
end

-- A part of an obstacle (something you crash into).
function Kit.Solid(parent: Instance, props: Util.PartProps): BasePart
	props.Parent = parent
	props.Material = props.Material or Enum.Material.SmoothPlastic
	local p = Util.Part(props)
	p.CollisionGroup = "RunObstacle"
	return p
end

-- An obstacle Model in a lane. The generator works out its distance along
-- the track (TrackD) from where it ends up.
function Kit.Obstacle(ctx: Ctx, kind: string, obstacleType: string, lane: number): Model
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("ObstacleType", obstacleType)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Lane", lane)
	model.Parent = ctx.obstacles
	return model
end

-- An invisible standable top on a tall obstacle, so with a jump boost you can
-- land on it. Low things don't get one: you jump over them.
function Kit.StandTop(model: Model, baseY: number)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	if cf.Position.Y + size.Y / 2 - baseY <= Config.Run.HighGround + 0.5 then
		return
	end
	local slab = Util.Part({
		Name = "StandTop",
		Parent = model,
		Size = Vector3.new(size.X, 0.3, size.Z),
		CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 - 0.15, 0)),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	slab.CollisionGroup = "RunGround"
end

-- ───────────────────────────── coins ─────────────────────────────

function Kit.Coin(ctx: Ctx, lane: number, y: number, d: number)
	local c = Util.Part({
		Name = "Coin",
		Parent = ctx.coins,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2.2, 2.2),
		CFrame = Kit.CF(ctx, Kit.LANES[lane], y + 1.6, d) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	c:SetAttribute("Coin", true)
	c:SetAttribute("Value", Config.Economy.CoinValue)
end

function Kit.CoinLine(ctx: Ctx, lane: number, d0: number, d1: number, y: number?)
	local d = d0
	while d <= d1 do
		Kit.Coin(ctx, lane, y or 0, d)
		d += 5
	end
end

-- Coins along a jump's arc centred on d (at a typical early-run speed).
function Kit.CoinArc(ctx: Ctx, lane: number, d: number)
	local profile = ImpactRules.JumpProfile(ImpactRules.SpeedAt(800))
	local count = math.clamp(math.floor(profile.length / 5), 5, 11)
	for i = 0, count - 1 do
		local t = i / (count - 1)
		Kit.Coin(ctx, lane, 4 * profile.apex * t * (1 - t), d - profile.length / 2 + t * profile.length)
	end
end

-- ───────────────────────────── spots ─────────────────────────────

local function spot(ctx: Ctx, name: string, lane: number, d: number, y: number): BasePart
	local p = Util.Part({
		Name = name,
		Parent = ctx.spots,
		Size = Vector3.new(2, 2, 2),
		CFrame = Kit.CF(ctx, Kit.LANES[lane], y + 1, d),
		-- Visible while you edit the templates; replaced when a run places it.
		Color = if name == "CageSpot" then Color3.fromRGB(255, 0, 255) else Color3.fromRGB(0, 255, 255),
		Transparency = 0.4,
		CanCollide = false,
		CanQuery = false,
	})
	p:SetAttribute("Lane", lane)
	return p
end

-- Where a power-up or mystery box may appear. Each section places at most
-- one pickup among its spots (Config.PowerUps chances); `prefer` is a
-- power-up id to favour there (SuperSneakers before tall obstacles). A spot
-- with its own `chance` is rolled on its own instead, e.g. a mystery box on
-- a roof (prefer = "MysteryBox").
function Kit.PickupSpot(ctx: Ctx, lane: number, d: number, prefer: string?, y: number?, chance: number?)
	local p = spot(ctx, "PickupSpot", lane, d, y or 0)
	if prefer then
		p:SetAttribute("Prefer", prefer)
	end
	if chance then
		p:SetAttribute("Chance", chance)
	end
end

-- Where a caged Brainrot from the area is placed.
function Kit.CageSpot(ctx: Ctx, lane: number, d: number)
	spot(ctx, "CageSpot", lane, d, 0)
end

-- ───────────────────────────── rows ─────────────────────────────

local function pick(rng: Random, weighted: { [string]: number }): string
	local total = 0
	local keys = {}
	for k, w in weighted do
		total += w
		table.insert(keys, k)
	end
	table.sort(keys) -- stable order so the same seed builds the same section
	local roll = rng:NextNumber() * total
	for _, k in keys do
		roll -= weighted[k]
		if roll < 0 then
			return k
		end
	end
	return keys[#keys]
end

-- Rows of obstacles between d0 and d1, kept calm: wide spacing, usually only
-- one or two lanes blocked, always a way through without breaking anything,
-- and a coin line or jump arc showing the way.
function Kit.Rows(ctx: Ctx, d0: number, d1: number, kinds: { [string]: number }, defs: { [string]: ObstacleDef }, skipLanes: { [number]: boolean }?)
	local rng = ctx.rng
	local skip = skipLanes or {}
	local open = {}
	for _, lane in Kit.LANE_IDS do
		if not skip[lane] then
			table.insert(open, lane)
		end
	end
	if #open == 0 then
		return
	end
	local spacing = ({ 80, 65, 52 })[ctx.difficulty + 1]
	local freeChance = ({ 0.7, 0.58, 0.45 })[ctx.difficulty + 1]
	local d = d0
	while d <= d1 do
		local row: { [number]: string? } = {}
		local passable, blocks = 0, 0
		for _, lane in open do
			if rng:NextNumber() < freeChance then
				passable += 1
			else
				local kind = pick(rng, kinds)
				if defs[kind].type == "Block" then
					blocks += 1
				else
					passable += 1
				end
				row[lane] = kind
			end
		end
		if passable == 0 or blocks == #open then
			row[open[rng:NextInteger(1, #open)]] = nil
		end
		local coinLane = open[rng:NextInteger(1, #open)]
		for _, lane in open do
			local kind = row[lane]
			if kind then
				local model = defs[kind].build(ctx, lane, d)
				Kit.StandTop(model, ctx.origin.Y)
				if defs[kind].type == "Jump" and lane == coinLane then
					Kit.CoinArc(ctx, lane, d)
				end
			elseif lane == coinLane then
				Kit.CoinLine(ctx, lane, d - spacing * 0.35, d + spacing * 0.35)
			end
		end
		d += spacing + rng:NextNumber(-4, 4)
	end
end

-- ───────────────────────────── shared pieces ─────────────────────────────

-- A tunnel over all three lanes (Greenhouse, Pier…): walls outside the lanes,
-- a roof you can boost-jump onto, and an entrance lip you crash into if you
-- jump at it too low. `walls` / `roof` style the looks.
function Kit.Tunnel(ctx: Ctx, d0: number, length: number, wallProps: Util.PartProps, roofProps: Util.PartProps)
	local mid = d0 + length / 2
	local width = Kit.ROAD_WIDTH + 4
	for _, side in { -1, 1 } do
		local props = table.clone(wallProps)
		props.Name = props.Name or "TunnelWall"
		props.Size = Vector3.new(2, Kit.TUNNEL_ROOF, length)
		props.CFrame = Kit.CF(ctx, side * (width / 2 + 1), Kit.TUNNEL_ROOF / 2, mid)
		Kit.Scenery(ctx, props)
	end
	local roof = table.clone(roofProps)
	roof.Name = roof.Name or "TunnelRoof"
	roof.Size = Vector3.new(width + 4, Kit.TUNNEL_ROOF - Kit.TUNNEL_CEILING, length)
	roof.CFrame = Kit.CF(ctx, 0, (Kit.TUNNEL_CEILING + Kit.TUNNEL_ROOF) / 2, mid)
	Kit.Ground(ctx, roof)
	for _, lane in Kit.LANE_IDS do
		local lip = Kit.Obstacle(ctx, "TunnelEntrance", "Block", lane)
		lip:SetAttribute("NoStyle", true)
		Kit.Solid(lip, { Name = "Lip", Size = Vector3.new(8, Kit.TUNNEL_ROOF - Kit.TUNNEL_CEILING, 1), CFrame = Kit.CF(ctx, Kit.LANES[lane], (Kit.TUNNEL_CEILING + Kit.TUNNEL_ROOF) / 2, d0 + 0.5), Transparency = 1 })
		Destruction.Setup(lip, 4)
	end
end

-- A big sign on posts beside the track.
function Kit.SideSign(ctx: Ctx, d: number, text: string, color: Color3, textColor: Color3?)
	local x = -Kit.ROAD_WIDTH / 2 - 4
	local sign = Kit.Scenery(ctx, { Name = "Sign", Size = Vector3.new(12, 4, 0.8), CFrame = Kit.CF(ctx, x, 7, d), Color = color })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, text, { PixelsPerStud = 14, TextColor = textColor or Color3.fromRGB(255, 255, 255) })
	for _, sx in { -5, 5 } do
		Kit.Scenery(ctx, { Name = "SignPost", Size = Vector3.new(0.8, 6, 0.8), CFrame = Kit.CF(ctx, x + sx, 3, d), Color = Color3.fromRGB(110, 70, 40) })
	end
end

-- ───────────────────────────── areas ─────────────────────────────

export type SectionSpec = {
	kind: string, -- "Start" and "Gate" are special (the run's start, an area's entrance)
	weight: number, -- how often the generator picks it
	cooldown: number?, -- sections that must pass before this kind repeats
	length: number?, -- default Config.Run.SegmentLength
	difficulties: { number }, -- built once per difficulty (0 easy · 1 medium · 2 hard)
	variants: number?, -- different random layouts per difficulty (default 2)
	build: (ctx: Ctx) -> (),
}

local GRID_COLUMNS = 6
local GRID_X = 900 -- studs between section columns (the ground reaches ~430 each side)
local GRID_Z = 280 -- studs between section rows

-- Builds every section of an area into a Folder named after it, laid out in
-- a grid starting at `origin` so they're easy to find and edit in Studio.
function Kit.BuildArea(parent: Instance, areaId: string, origin: Vector3, specs: { SectionSpec }, seed: number): Folder
	local areaFolder = folder(parent, areaId)
	local i = 0
	for _, spec in specs do
		for _, difficulty in spec.difficulties do
			for variant = 1, spec.variants or 2 do
				local col, row = i % GRID_COLUMNS, i // GRID_COLUMNS
				local at = origin + Vector3.new(col * GRID_X, 0, -row * GRID_Z)
				local name = ("%s_D%d_%d"):format(spec.kind, difficulty, variant)
				local ctx = Kit.Section(areaFolder, areaId, spec.kind, name, at, spec.length or Config.Run.SegmentLength, seed + i * 7919, difficulty, spec.weight)
				ctx.model:SetAttribute("Cooldown", spec.cooldown or 0)
				spec.build(ctx)
				i += 1
			end
		end
	end
	return areaFolder
end

-- An entrance arch over the track with the area's name (area gates).
function Kit.Arch(ctx: Ctx, d: number, text: string, color: Color3, postColor: Color3)
	for _, side in { -1, 1 } do
		Kit.Scenery(ctx, { Name = "ArchPost", Size = Vector3.new(3, 26, 3), CFrame = Kit.CF(ctx, side * (Kit.ROAD_WIDTH / 2 + 2), 13, d), Color = postColor })
	end
	local beam = Kit.Scenery(ctx, { Name = "ArchBeam", Size = Vector3.new(Kit.ROAD_WIDTH + 8, 6, 2), CFrame = Kit.CF(ctx, 0, 27, d), Color = color })
	Util.SurfaceLabel(beam, Enum.NormalId.Back, text, { PixelsPerStud = 10 })
end

return Kit
