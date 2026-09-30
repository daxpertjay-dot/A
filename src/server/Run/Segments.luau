--!strict
-- The library of prebuilt track segments. Each builder receives a context
-- describing where the segment sits in the run and fills it with road,
-- scenery, obstacles, coins and pickups.
--
-- Track space: `d` is distance along the run (forward = world -Z), `x` is the
-- sideways offset from the centre lane, `y` is height above the road.
--
-- Collision groups (registered in TrackGenerator):
--   RunGround   – anything the runner can stand on (road, ramps, train roofs)
--   RunObstacle – anything the runner can crash into
-- Scenery stays in Default so the runner's probes ignore it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local Destruction = require(script.Parent.Destruction)

local Segments = {}

local LANES = Config.Run.LanePositions
local LANE_IDS = { -1, 0, 1 }
local ROAD_WIDTH = 30

export type Ctx = {
	folder: Model,
	origin: Vector3,
	startD: number,
	length: number,
	rng: Random,
	difficulty: number,
	distance: number,
	isFirst: boolean?,
}

type ObstacleKind = "Barricade" | "SteelBarrier" | "OverheadSign" | "OverheadPipe" | "Crates" | "WoodWall" | "ConcreteWall" | "Car" | "TrainCar"

local OBSTACLE_TYPE: { [string]: string } = {
	Barricade = "Jump",
	SteelBarrier = "Jump",
	OverheadSign = "Roll",
	OverheadPipe = "Roll",
	Crates = "Block",
	WoodWall = "Block",
	ConcreteWall = "Block",
	Car = "Block",
	TrainCar = "Block",
}

-- ───────────────────────────── helpers ─────────────────────────────

local function W(ctx: Ctx, x: number, y: number, d: number): Vector3
	return ctx.origin + Vector3.new(x, y, -(ctx.startD + d))
end

local function CF(ctx: Ctx, x: number, y: number, d: number): CFrame
	return CFrame.new(W(ctx, x, y, d))
end

local function scenery(ctx: Ctx, props: Util.PartProps): BasePart
	props.Parent = props.Parent or ctx.folder
	props.CanQuery = false
	return Util.Part(props)
end

local function ground(ctx: Ctx, props: Util.PartProps): BasePart
	props.Parent = props.Parent or ctx.folder
	local p = Util.Part(props)
	p.CollisionGroup = "RunGround"
	return p
end

local function solid(parent: Instance, props: Util.PartProps): BasePart
	props.Parent = parent
	local p = Util.Part(props)
	p.CollisionGroup = "RunObstacle"
	return p
end

local function obstacleModel(ctx: Ctx, kind: string, lane: number): Model
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("ObstacleType", OBSTACLE_TYPE[kind])
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Lane", lane)
	model.Parent = ctx.folder
	return model
end

-- Road slab, lane markings and kerbs.
local function road(ctx: Ctx, color: Color3?, material: Enum.Material?)
	local len = ctx.length
	ground(ctx, {
		Name = "Road",
		Size = Vector3.new(ROAD_WIDTH, 2, len),
		CFrame = CF(ctx, 0, -1, len / 2),
		Color = color or Color3.fromRGB(55, 55, 65),
		Material = material or Enum.Material.Asphalt,
	})
	for _, x in { -4, 4 } do
		for d = 4, len - 4, 12 do
			scenery(ctx, { Name = "LaneLine", Size = Vector3.new(0.4, 0.05, 6), CFrame = CF(ctx, x, 0.03, d), Color = Color3.fromRGB(240, 240, 240), CanCollide = false })
		end
	end
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "Kerb", Size = Vector3.new(3, 0.8, len), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 - 1.5), 0.4, len / 2), Color = Color3.fromRGB(200, 200, 205) })
	end
end

local PALETTES = {
	City = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 220, 90), Color3.fromRGB(180, 130, 255), Color3.fromRGB(140, 240, 150) },
	Dark = { Color3.fromRGB(70, 60, 90), Color3.fromRGB(60, 70, 80), Color3.fromRGB(90, 70, 60) },
	Industrial = { Color3.fromRGB(230, 140, 40), Color3.fromRGB(120, 120, 130), Color3.fromRGB(240, 200, 60) },
}

-- Colourful leaning buildings on both sides of the road.
local function buildings(ctx: Ctx, palette: { Color3 }, minH: number?, maxH: number?, gap: number?)
	local rng = ctx.rng
	local offset = (gap or 0) + ROAD_WIDTH / 2
	for _, side in { -1, 1 } do
		local d = 0
		while d < ctx.length do
			local depth = rng:NextNumber(16, 28)
			local width = rng:NextNumber(14, 24)
			local height = rng:NextNumber(minH or 20, maxH or 60)
			local actualDepth = math.min(depth, ctx.length - d)
			local b = scenery(ctx, {
				Name = "Building",
				Size = Vector3.new(width, height, actualDepth - 1),
				CFrame = CF(ctx, side * (offset + width / 2 + 2), height / 2, d + actualDepth / 2) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-3, 3))),
				Color = palette[rng:NextInteger(1, #palette)],
			})
			-- windows
			if height > 16 then
				scenery(ctx, {
					Name = "Windows",
					Parent = b,
					Size = Vector3.new(0.2, height * 0.7, actualDepth * 0.7),
					CFrame = b.CFrame * CFrame.new(-side * (width / 2 + 0.1), height * 0.05, 0),
					Color = Color3.fromRGB(255, 250, 200),
					Material = Enum.Material.Neon,
					Transparency = 0.4,
					CanCollide = false,
				})
			end
			d += depth
		end
	end
end

local function coin(ctx: Ctx, lane: number, y: number, d: number)
	local c = Util.Part({
		Name = "Coin",
		Parent = ctx.folder:FindFirstChild("Coins"),
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2.2, 2.2),
		CFrame = CF(ctx, LANES[lane], y + 1.6, d) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	c:SetAttribute("Coin", true)
end

local function coinLine(ctx: Ctx, lane: number, d0: number, d1: number, y: number?)
	local d = d0
	while d <= d1 do
		coin(ctx, lane, y or 0, d)
		d += 5
	end
end

-- Coins in a jump arc over a low obstacle at d.
local function coinArc(ctx: Ctx, lane: number, d: number)
	for i = -3, 3 do
		local t = i / 3
		coin(ctx, lane, 7.5 * (1 - t * t), d + i * 4)
	end
end

local function pickup(ctx: Ctx, lane: number, d: number, kind: "Equipment" | "Crate", y: number?)
	local color = if kind == "Crate" then Color3.fromRGB(255, 180, 30) else Color3.fromRGB(170, 90, 255)
	local box = Util.Part({
		Name = kind .. "Pickup",
		Parent = ctx.folder:FindFirstChild("Pickups"),
		Size = Vector3.new(2.6, 2.6, 2.6),
		CFrame = CF(ctx, LANES[lane], (y or 0) + 2.4, d) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	box:SetAttribute("Pickup", kind)
	if kind == "Crate" then
		box:SetAttribute("CrateId", "Common")
	end
	Util.SurfaceLabel(box, Enum.NormalId.Front, if kind == "Crate" then "📦" else "?", { PixelsPerStud = 20 })
end

-- ───────────────────────────── obstacles ─────────────────────────────

local builders: { [string]: (ctx: Ctx, lane: number, d: number) -> Model } = {}

builders.Barricade = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Barricade", lane)
	local x = LANES[lane]
	for _, side in { -1, 1 } do
		solid(m, { Name = "Leg", Size = Vector3.new(0.5, 3, 0.5), CFrame = CF(ctx, x + side * 3, 1.5, d), Color = Color3.fromRGB(120, 80, 40), Material = Enum.Material.Wood })
	end
	for i, y in { 1.4, 2.6 } do
		solid(m, {
			Name = "Plank",
			Size = Vector3.new(7, 0.7, 0.4),
			CFrame = CF(ctx, x, y, d),
			Color = if i == 1 then Color3.fromRGB(240, 240, 240) else Color3.fromRGB(230, 60, 60),
			Material = Enum.Material.Wood,
		})
	end
	Destruction.Setup(m, 1, "Shatter", "Wood")
	return m
end

builders.SteelBarrier = function(ctx, lane, d)
	local m = obstacleModel(ctx, "SteelBarrier", lane)
	local x = LANES[lane]
	solid(m, { Name = "Barrier", Size = Vector3.new(7, 3, 1), CFrame = CF(ctx, x, 1.5, d), Color = Color3.fromRGB(150, 155, 165), Material = Enum.Material.DiamondPlate })
	for i = -1, 1 do
		scenery(ctx, { Parent = m, Name = "Stripe", Size = Vector3.new(1.2, 3.02, 1.02), CFrame = CF(ctx, x + i * 2.4, 1.5, d), Color = Color3.fromRGB(255, 210, 0), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	Destruction.Setup(m, 4)
	return m
end

builders.OverheadSign = function(ctx, lane, d)
	local m = obstacleModel(ctx, "OverheadSign", lane)
	local x = LANES[lane]
	for _, side in { -1, 1 } do
		solid(m, { Name = "Post", Size = Vector3.new(0.4, 10.5, 0.4), CFrame = CF(ctx, x + side * 3.7, 5.25, d), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
	end
	local board = solid(m, { Name = "Board", Size = Vector3.new(7, 7, 0.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = Color3.fromRGB(40, 140, 255) })
	local texts = { "SLIDE!", "DUCK!", "SAHUR\nCROSSING", "⬇️ ROLL ⬇️", "NO\nTRALALA" }
	Util.SurfaceLabel(board, Enum.NormalId.Back, texts[ctx.rng:NextInteger(1, #texts)], { PixelsPerStud = 20 })
	Destruction.Setup(m, 1, "Shatter", "Metal")
	return m
end

builders.OverheadPipe = function(ctx, lane, d)
	local m = obstacleModel(ctx, "OverheadPipe", lane)
	local x = LANES[lane]
	for _, side in { -1, 1 } do
		solid(m, { Name = "Support", Size = Vector3.new(0.6, 10.5, 0.6), CFrame = CF(ctx, x + side * 3.7, 5.25, d), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal })
	end
	solid(m, { Name = "Pipe", Size = Vector3.new(7, 7, 1.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = Color3.fromRGB(200, 90, 40), Material = Enum.Material.CorrodedMetal })
	Destruction.Setup(m, 4)
	return m
end

builders.Crates = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Crates", lane)
	local x = LANES[lane]
	for i = 0, 2 do
		for j = -1, 1, 2 do
			if i < 2 or j == 1 then
				solid(m, {
					Name = "Box",
					Size = Vector3.new(3, 3, 3),
					CFrame = CF(ctx, x + j * 1.6, 1.5 + i * 3, d) * CFrame.Angles(0, math.rad(ctx.rng:NextNumber(-10, 10)), 0),
					Color = Color3.fromRGB(190, 140, 80),
					Material = Enum.Material.WoodPlanks,
				})
			end
		end
	end
	Destruction.Setup(m, 1, "Shatter", "Wood")
	return m
end

local function wall(ctx: Ctx, lane: number, d: number, kind: string, tier: number, color: Color3, material: Enum.Material, thickness: number): Model
	local m = obstacleModel(ctx, kind, lane)
	local brickWall = Destruction.BrickWall(m, CF(ctx, LANES[lane], 6, d), Vector3.new(7.6, 12, thickness), Vector3.new(1.9, 2, thickness), color, material)
	for _, p in brickWall:GetChildren() do
		(p :: BasePart).CollisionGroup = "RunObstacle"
	end
	Destruction.Setup(m, tier, "Bricks", material.Name)
	return m
end

builders.WoodWall = function(ctx, lane, d)
	return wall(ctx, lane, d, "WoodWall", 2, Color3.fromRGB(170, 115, 60), Enum.Material.WoodPlanks, 1.4)
end

builders.ConcreteWall = function(ctx, lane, d)
	local m = wall(ctx, lane, d, "ConcreteWall", 3, Color3.fromRGB(175, 175, 180), Enum.Material.Concrete, 2)
	return m
end

builders.Car = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Car", lane)
	local x = LANES[lane]
	local colors = { Color3.fromRGB(230, 50, 60), Color3.fromRGB(50, 120, 230), Color3.fromRGB(250, 200, 40), Color3.fromRGB(240, 240, 240) }
	local color = colors[ctx.rng:NextInteger(1, #colors)]
	solid(m, { Name = "Body", Size = Vector3.new(6, 2.6, 10), CFrame = CF(ctx, x, 2, d + 5), Color = color, Material = Enum.Material.SmoothPlastic })
	solid(m, { Name = "Cabin", Size = Vector3.new(5.4, 2.2, 5.5), CFrame = CF(ctx, x, 4.4, d + 5.8), Color = Color3.fromRGB(120, 190, 230), Material = Enum.Material.Glass })
	for _, sx in { -1, 1 } do
		for _, sz in { 1.8, 8.2 } do
			scenery(ctx, { Parent = m, Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 2, 2), CFrame = CF(ctx, x + sx * 3, 1, d + sz), Color = Color3.fromRGB(25, 25, 25), CanCollide = false })
		end
	end
	Destruction.Setup(m, 2, "Shatter", "Metal")
	return m
end

-- A long subway car. Its roof is walkable (reach it with a ramp).
builders.TrainCar = function(ctx, lane, d)
	local m = obstacleModel(ctx, "TrainCar", lane)
	local x = LANES[lane]
	local len = 40
	local colors = { Color3.fromRGB(240, 70, 70), Color3.fromRGB(60, 170, 240), Color3.fromRGB(250, 190, 40) }
	solid(m, { Name = "Body", Size = Vector3.new(7, 9.8, len), CFrame = CF(ctx, x, 4.9, d + len / 2), Color = colors[ctx.rng:NextInteger(1, #colors)], Material = Enum.Material.Metal })
	ground(ctx, { Parent = m, Name = "Roof", Size = Vector3.new(7, 0.4, len), CFrame = CF(ctx, x, 10, d + len / 2), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.DiamondPlate })
	local front = scenery(ctx, { Parent = m, Name = "Front", Size = Vector3.new(6, 4, 0.2), CFrame = CF(ctx, x, 6, d - 0.1), Color = Color3.fromRGB(30, 30, 40), CanCollide = false })
	Util.SurfaceLabel(front, Enum.NormalId.Back, "🧠 EXPRESS", { PixelsPerStud = 15, TextColor = Color3.fromRGB(255, 220, 90) })
	Destruction.Setup(m, 4)
	return m
end

local function ramp(ctx: Ctx, lane: number, d: number, length: number)
	local r = ground(ctx, {
		Class = "WedgePart",
		Name = "Ramp",
		Size = Vector3.new(7, 10, length),
		-- A WedgePart's slope faces -Z (high edge at +Z). The track runs toward
		-- -Z, so turn it around to rise toward the train.
		CFrame = CF(ctx, LANES[lane], 5, d + length / 2) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(120, 120, 130),
		Material = Enum.Material.DiamondPlate,
	})
	return r
end

function Segments.Obstacle(ctx: Ctx, kind: string, lane: number, d: number): Model
	return builders[kind](ctx, lane, d)
end

-- ───────────────────────────── row generation ─────────────────────────────

local function pick<T>(rng: Random, weighted: { [T]: number }): T
	local total = 0
	for _, w in weighted do
		total += w
	end
	local roll = rng:NextNumber() * total
	local last: T
	for k, w in weighted do
		last = k
		if roll < w then
			return k
		end
		roll -= w
	end
	return last
end

-- Places rows of obstacles between d0 and d1. Every row always leaves at
-- least one lane that can be passed without destroying anything (a free
-- lane, or a jump/roll obstacle), and coins guide the player through gaps.
local function obstacleRows(ctx: Ctx, d0: number, d1: number, kinds: { [string]: number }, skipLanes: { [number]: boolean }?)
	local rng = ctx.rng
	local skip = skipLanes or {}
	local open = {}
	for _, lane in LANE_IDS do
		if not skip[lane] then
			table.insert(open, lane)
		end
	end
	if #open == 0 then
		return
	end
	local spacing = Util.Lerp(42, 26, ctx.difficulty)
	local d = d0
	while d <= d1 do
		local freeChance = Util.Lerp(0.55, 0.25, ctx.difficulty)
		local row: { [number]: string? } = {}
		local passable = 0
		local blocks = 0
		for _, lane in open do
			if rng:NextNumber() < freeChance then
				row[lane] = nil
				passable += 1
			else
				local kind = pick(rng, kinds)
				if OBSTACLE_TYPE[kind] == "Block" then
					blocks += 1
				else
					passable += 1
				end
				row[lane] = kind
			end
		end
		-- Guarantee a way through.
		if passable == 0 or blocks == #open then
			row[open[rng:NextInteger(1, #open)]] = nil
		end

		local coinLane = open[rng:NextInteger(1, #open)]
		for _, lane in open do
			local kind = row[lane]
			if kind then
				Segments.Obstacle(ctx, kind, lane, d)
				if kind == "Barricade" or kind == "SteelBarrier" then
					if lane == coinLane then
						coinArc(ctx, lane, d)
					end
				end
			elseif lane == coinLane then
				coinLine(ctx, lane, d - spacing * 0.35, d + spacing * 0.35)
			end
		end
		d += spacing + rng:NextNumber(-4, 4)
	end
end

local function maybeEquipmentPickup(ctx: Ctx, chance: number)
	if ctx.rng:NextNumber() < chance then
		-- Placed in the safe zone at the start of the segment so it never
		-- overlaps an obstacle.
		pickup(ctx, LANE_IDS[ctx.rng:NextInteger(1, 3)], Config.Run.SafeZoneAtSegmentEdges * 0.5, "Equipment")
	end
end

local EDGE = Config.Run.SafeZoneAtSegmentEdges

-- ───────────────────────────── segment types ─────────────────────────────

export type SegmentDef = {
	name: string,
	weight: number,
	minDistance: number,
	cooldown: number, -- segments that must pass before this can repeat
	build: (ctx: Ctx) -> (),
}

local defs: { SegmentDef } = {}

local function define(def: SegmentDef)
	table.insert(defs, def)
end

define({
	name = "Straight",
	weight = 10,
	minDistance = 0,
	cooldown = 0,
	build = function(ctx)
		road(ctx)
		buildings(ctx, PALETTES.City)
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { Barricade = 3, OverheadSign = 3, Crates = 2, SteelBarrier = 1, WoodWall = 1 })
		maybeEquipmentPickup(ctx, 0.2)
	end,
})

define({
	name = "Intersection",
	weight = 6,
	minDistance = 0,
	cooldown = 1,
	build = function(ctx)
		road(ctx)
		local mid = ctx.length / 2
		-- Cross street and crosswalk stripes
		scenery(ctx, { Name = "CrossRoad", Size = Vector3.new(160, 1.9, 30), CFrame = CF(ctx, 0, -1.02, mid), Color = Color3.fromRGB(55, 55, 65), Material = Enum.Material.Asphalt })
		for i = -6, 6 do
			scenery(ctx, { Name = "Crosswalk", Size = Vector3.new(1.4, 0.06, 6), CFrame = CF(ctx, i * 2.2, 0.03, mid - 10), Color = Color3.fromRGB(245, 245, 245), CanCollide = false })
		end
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "TrafficPole", Size = Vector3.new(0.6, 14, 0.6), CFrame = CF(ctx, side * 16, 7, mid - 14), Color = Color3.fromRGB(60, 60, 60) })
			local light = scenery(ctx, { Name = "TrafficLight", Size = Vector3.new(1.5, 4, 1.5), CFrame = CF(ctx, side * 16, 15, mid - 14), Color = Color3.fromRGB(30, 30, 30) })
			scenery(ctx, { Parent = light, Name = "Red", Shape = Enum.PartType.Ball, Size = Vector3.one, CFrame = light.CFrame * CFrame.new(0, 1, 0.8), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CanCollide = false })
		end
		-- buildings only before/after the crossing
		local saved = ctx.length
		ctx.length = mid - 16
		buildings(ctx, PALETTES.City)
		ctx.length = saved
		obstacleRows(ctx, EDGE + 10, mid - 18, { Car = 3, Barricade = 2, OverheadSign = 1 })
		obstacleRows(ctx, mid + 18, ctx.length - EDGE, { Car = 3, Barricade = 2, Crates = 1 })
	end,
})

define({
	name = "Alley",
	weight = 5,
	minDistance = 100,
	cooldown = 1,
	build = function(ctx)
		road(ctx, Color3.fromRGB(45, 42, 50), Enum.Material.Cobblestone)
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "AlleyWall", Size = Vector3.new(4, 45, ctx.length), CFrame = CF(ctx, side * 15, 22.5, ctx.length / 2), Color = Color3.fromRGB(80, 60, 70), Material = Enum.Material.Brick })
			for d = 10, ctx.length - 10, 30 do
				scenery(ctx, { Name = "Lamp", Size = Vector3.new(0.6, 1.2, 1.2), CFrame = CF(ctx, side * 12.8, 11, d), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { Crates = 3, OverheadPipe = 3, Barricade = 2, WoodWall = 1 })
		maybeEquipmentPickup(ctx, 0.25)
	end,
})

define({
	name = "Construction",
	weight = 5,
	minDistance = 150,
	cooldown = 2,
	build = function(ctx)
		road(ctx, Color3.fromRGB(110, 90, 70), Enum.Material.Ground)
		buildings(ctx, PALETTES.Industrial, 10, 30, 6)
		for d = 6, ctx.length, 14 do
			for _, side in { -1, 1 } do
				scenery(ctx, { Name = "Cone", Size = Vector3.new(1, 2, 1), CFrame = CF(ctx, side * 12.5, 1, d), Color = Color3.fromRGB(255, 120, 20) })
			end
		end
		-- A crane arm over the road for flavour
		scenery(ctx, { Name = "CraneTower", Size = Vector3.new(3, 60, 3), CFrame = CF(ctx, 22, 30, ctx.length / 2), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Metal })
		scenery(ctx, { Name = "CraneArm", Size = Vector3.new(50, 2.5, 2.5), CFrame = CF(ctx, 2, 58, ctx.length / 2), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Metal })
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { WoodWall = 3, Barricade = 3, OverheadSign = 2, ConcreteWall = 1 })
		maybeEquipmentPickup(ctx, 0.3)
	end,
})

define({
	name = "ParkingLot",
	weight = 4,
	minDistance = 100,
	cooldown = 2,
	build = function(ctx)
		road(ctx, Color3.fromRGB(70, 70, 78))
		-- Parked cars in bays on both sides (scenery only)
		for _, side in { -1, 1 } do
			ground(ctx, { Name = "Lot", Size = Vector3.new(40, 1.9, ctx.length), CFrame = CF(ctx, side * 35, -1.02, ctx.length / 2), Color = Color3.fromRGB(80, 80, 88), Material = Enum.Material.Asphalt })
			for d = 8, ctx.length - 8, 12 do
				if ctx.rng:NextNumber() < 0.7 then
					scenery(ctx, { Name = "ParkedCar", Size = Vector3.new(10, 3.5, 5.5), CFrame = CF(ctx, side * 30, 1.75, d), Color = Color3.fromHSV(ctx.rng:NextNumber(), 0.7, 0.9) })
				end
				scenery(ctx, { Name = "BayLine", Size = Vector3.new(12, 0.05, 0.3), CFrame = CF(ctx, side * 30, 0.03, d + 6), Color = Color3.fromRGB(240, 240, 240), CanCollide = false })
			end
		end
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { Car = 4, Barricade = 2, Crates = 1 })
	end,
})

define({
	name = "Tunnel",
	weight = 5,
	minDistance = 200,
	cooldown = 2,
	build = function(ctx)
		road(ctx, Color3.fromRGB(50, 45, 55), Enum.Material.Concrete)
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "TunnelWall", Size = Vector3.new(3, 22, ctx.length), CFrame = CF(ctx, side * 15.5, 11, ctx.length / 2), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Concrete })
			for d = 5, ctx.length - 5, 15 do
				scenery(ctx, { Name = "TunnelLight", Size = Vector3.new(0.3, 1, 5), CFrame = CF(ctx, side * 13.9, 16, d), Color = Color3.fromRGB(200, 255, 255), Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		scenery(ctx, { Name = "TunnelRoof", Size = Vector3.new(34, 2, ctx.length), CFrame = CF(ctx, 0, 23, ctx.length / 2), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Concrete })
		-- Occasionally a parked train with a ramp in one lane.
		local skip = {}
		if ctx.rng:NextNumber() < 0.5 then
			local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
			ramp(ctx, lane, EDGE + 6, 26)
			Segments.Obstacle(ctx, "TrainCar", lane, EDGE + 32)
			coinLine(ctx, lane, EDGE + 36, EDGE + 68, 10.2)
			skip[lane] = true
		end
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { SteelBarrier = 3, OverheadPipe = 3, Crates = 1 }, skip)
	end,
})

define({
	name = "Highway",
	weight = 5,
	minDistance = 300,
	cooldown = 1,
	build = function(ctx)
		road(ctx, Color3.fromRGB(45, 45, 52))
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "GuardRail", Size = Vector3.new(0.6, 2.4, ctx.length), CFrame = CF(ctx, side * 13.5, 1.2, ctx.length / 2), Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal })
			scenery(ctx, { Name = "Drop", Size = Vector3.new(80, 2, ctx.length), CFrame = CF(ctx, side * 56, -30, ctx.length / 2), Color = Color3.fromRGB(90, 160, 90), Material = Enum.Material.Grass })
		end
		-- Overhead gantry sign
		local gantry = scenery(ctx, { Name = "Gantry", Size = Vector3.new(32, 5, 1), CFrame = CF(ctx, 0, 20, ctx.length / 2), Color = Color3.fromRGB(30, 120, 60) })
		Util.SurfaceLabel(gantry, Enum.NormalId.Back, "⬆️ SAHUR CITY  ·  NO EXIT", { PixelsPerStud = 12 })
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { Car = 3, ConcreteWall = 2, SteelBarrier = 2, OverheadSign = 1 })
		maybeEquipmentPickup(ctx, 0.2)
	end,
})

define({
	name = "Building",
	weight = 4,
	minDistance = 250,
	cooldown = 2,
	build = function(ctx)
		road(ctx, Color3.fromRGB(180, 170, 160), Enum.Material.Marble)
		-- Run straight through the ground floor of a building.
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "InnerWall", Size = Vector3.new(2, 16, ctx.length), CFrame = CF(ctx, side * 15, 8, ctx.length / 2), Color = Color3.fromRGB(230, 220, 200) })
		end
		scenery(ctx, { Name = "Ceiling", Size = Vector3.new(32, 2, ctx.length), CFrame = CF(ctx, 0, 17, ctx.length / 2), Color = Color3.fromRGB(240, 235, 225) })
		scenery(ctx, { Name = "Upstairs", Size = Vector3.new(32, 40, ctx.length), CFrame = CF(ctx, 0, 38, ctx.length / 2), Color = PALETTES.City[ctx.rng:NextInteger(1, 5)] })
		for d = 10, ctx.length - 10, 20 do
			scenery(ctx, { Name = "CeilingLight", Size = Vector3.new(20, 0.3, 2), CFrame = CF(ctx, 0, 15.9, d), Color = Color3.fromRGB(255, 255, 230), Material = Enum.Material.Neon, CanCollide = false })
		end
		obstacleRows(ctx, EDGE + 10, ctx.length - EDGE, { WoodWall = 3, ConcreteWall = 2, Crates = 2, OverheadSign = 1 })
	end,
})

define({
	name = "Ramp",
	weight = 5,
	minDistance = 120,
	cooldown = 2,
	build = function(ctx)
		road(ctx)
		buildings(ctx, PALETTES.City)
		-- Two or three train cars; one has a ramp so you can run on the roofs.
		local rampLane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
		ramp(ctx, rampLane, EDGE, 26)
		Segments.Obstacle(ctx, "TrainCar", rampLane, EDGE + 26)
		Segments.Obstacle(ctx, "TrainCar", rampLane, EDGE + 68)
		coinLine(ctx, rampLane, EDGE + 28, EDGE + 104, 10.2)
		local skip = { [rampLane] = true }
		for _, lane in LANE_IDS do
			if lane ~= rampLane and ctx.rng:NextNumber() < 0.6 then
				Segments.Obstacle(ctx, "TrainCar", lane, EDGE + ctx.rng:NextNumber(20, 55))
				skip[lane] = true
			end
		end
		obstacleRows(ctx, EDGE + 20, ctx.length - EDGE, { Barricade = 2, OverheadSign = 2 }, skip)
	end,
})

-- Alternate path: the middle lane is sealed off by a concrete "vault" wall.
-- Blow it up or smash through it and the sealed lane is full of loot.
define({
	name = "Destruction",
	weight = 4,
	minDistance = 200,
	cooldown = 3,
	build = function(ctx)
		road(ctx)
		buildings(ctx, PALETTES.Industrial, 15, 40)
		local vaultStart = EDGE + 20
		local vaultEnd = ctx.length - EDGE - 6
		local entrance = Segments.Obstacle(ctx, if ctx.rng:NextNumber() < 0.5 then "ConcreteWall" else "WoodWall", 0, vaultStart)
		entrance:SetAttribute("Vault", true)
		local sign = scenery(ctx, { Name = "VaultSign", Size = Vector3.new(7, 2.5, 0.3), CFrame = CF(ctx, 0, 13.5, vaultStart), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "💥 BONUS 💥", { PixelsPerStud = 20 })
		-- Indestructible dividers between the vault and the side lanes.
		for _, side in { -1, 1 } do
			-- Lane 99: never "in front" of the runner, so touching it is always a side bump.
			local divider = obstacleModel(ctx, "VaultDivider", 99)
			divider:SetAttribute("ObstacleType", "Block")
			solid(divider, { Name = "Divider", Size = Vector3.new(0.8, 12, vaultEnd - vaultStart), CFrame = CF(ctx, side * 4, 6, (vaultStart + vaultEnd) / 2), Color = Color3.fromRGB(120, 120, 130), Material = Enum.Material.Concrete })
			Destruction.Setup(divider, 4)
		end
		-- Loot inside
		coinLine(ctx, 0, vaultStart + 6, vaultEnd - 6)
		pickup(ctx, 0, (vaultStart + vaultEnd) / 2, "Crate")
		pickup(ctx, 0, vaultEnd - 10, "Equipment")
		-- Weak walls in the side lanes to crash through or dodge.
		obstacleRows(ctx, vaultStart + 14, vaultEnd, { WoodWall = 2, Barricade = 2, OverheadSign = 2, Crates = 2 }, { [0] = true })
		-- One side lane gets smashable crates at the vault entrance, the other stays open.
		Segments.Obstacle(ctx, "Crates", if ctx.rng:NextNumber() < 0.5 then -1 else 1, vaultStart)
	end,
})

define({
	name = "BrainrotSpecial",
	weight = 3,
	minDistance = 150,
	cooldown = 4,
	build = function(ctx)
		road(ctx, Color3.fromRGB(255, 150, 210), Enum.Material.SmoothPlastic)
		-- A Brainrot stands in one lane inside a glowing ring: run through it to
		-- catch it. Caught Brainrots go to your base and earn coins.
		local brainrot = BrainrotData.PickCatchable(ctx.distance, ctx.rng)
		if brainrot then
			local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
			local d = ctx.length / 2
			local ring = Util.Part({
				Name = "BrainrotCatch",
				Parent = ctx.folder:FindFirstChild("Pickups"),
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 7.5, 7.5),
				CFrame = CF(ctx, LANES[lane], 0.25, d) * CFrame.Angles(0, 0, math.rad(90)),
				Color = BrainrotData.RarityColors[brainrot.rarity] or Color3.fromRGB(255, 220, 90),
				Material = Enum.Material.Neon,
				Transparency = 0.2,
				CanCollide = false,
				CanQuery = false,
			})
			ring:SetAttribute("Pickup", "Brainrot")
			ring:SetAttribute("BrainrotId", brainrot.id)
			local model = ModelFactory.Brainrot(brainrot.id, 1.1)
			model:PivotTo(CF(ctx, LANES[lane], 0.4, d) * CFrame.Angles(0, math.pi, 0))
			model.Parent = ring
			ModelFactory.NameTag(model, ("%s %s — CATCH ME!"):format(brainrot.icon, string.upper(brainrot.name)), BrainrotData.RarityColors[brainrot.rarity], 11)
			-- Keep its lane clear right around it.
			coinLine(ctx, lane, d - 30, d - 8)
		end
		buildings(ctx, PALETTES.City, 30, 80, 20)
		-- Gentle obstacles and a coin shower so the player can enjoy the view.
		for _, lane in LANE_IDS do
			coinLine(ctx, lane, EDGE, ctx.length * 0.3)
		end
		obstacleRows(ctx, ctx.length * 0.68, ctx.length - EDGE, { Barricade = 1, OverheadSign = 1 })
	end,
})

Segments.Definitions = defs

-- The calm section right after the run gate: no obstacles, a tunnel mouth
-- behind the player (where Sahur appears) and a big "GET READY" banner.
function Segments.BuildStartArea(ctx: Ctx)
	road(ctx)
	-- Extend the road behind the start line for the tunnel mouth.
	ground(ctx, { Name = "RoadBehind", Size = Vector3.new(ROAD_WIDTH, 2, 60), CFrame = CF(ctx, 0, -1, -30), Color = Color3.fromRGB(55, 55, 65), Material = Enum.Material.Asphalt })
	buildings(ctx, PALETTES.City, 30, 70)

	-- The tunnel the player just came out of
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "GateWall", Size = Vector3.new(3, 24, 30), CFrame = CF(ctx, side * 15.5, 12, -22), Color = Color3.fromRGB(40, 35, 60), Material = Enum.Material.Concrete })
	end
	scenery(ctx, { Name = "GateRoof", Size = Vector3.new(34, 3, 30), CFrame = CF(ctx, 0, 25.5, -22), Color = Color3.fromRGB(40, 35, 60) })
	local arch = scenery(ctx, { Name = "GateArch", Size = Vector3.new(36, 5, 3), CFrame = CF(ctx, 0, 26, -7), Color = Color3.fromRGB(255, 70, 160), Material = Enum.Material.Neon })
	Util.SurfaceLabel(arch, Enum.NormalId.Back, "🏃 RUN GATE", { PixelsPerStud = 12 })
	scenery(ctx, { Name = "TunnelDark", Size = Vector3.new(28, 22, 1), CFrame = CF(ctx, 0, 11, -36), Color = Color3.fromRGB(5, 5, 10), CanCollide = false })

	-- Banner over the start line
	local banner = scenery(ctx, { Name = "StartBanner", Size = Vector3.new(30, 5, 0.5), CFrame = CF(ctx, 0, 19, 30), Color = Color3.fromRGB(30, 25, 50) })
	Util.SurfaceLabel(banner, Enum.NormalId.Back, "GET READY… 🪵 HE'S COMING", { PixelsPerStud = 12, TextColor = Color3.fromRGB(255, 220, 90) })
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "BannerPost", Size = Vector3.new(1, 21, 1), CFrame = CF(ctx, side * 15, 10.5, 30), Color = Color3.fromRGB(60, 60, 70) })
	end
	-- A few warm-up coins down the middle.
	coinLine(ctx, 0, 40, ctx.length - 8)
end

return Segments
