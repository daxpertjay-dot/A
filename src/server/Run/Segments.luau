--!strict
-- The track: BRAINROT CITY ROOFTOPS at sunset. You run across the roofs of
-- the city's buildings (Subway Surfers lanes, but up high): roofs change
-- height with ramps, some end in a gap you have to leap, rooftop sheds can be
-- run on, and every obstacle has a top you can land on. Fall into a gap and
-- Verity gets you.
--
-- Track space: `d` is distance along the run (forward = world -Z), `x` is the
-- sideways offset from the centre lane, `y` is height above THIS segment's
-- roof (ctx.height is added automatically).
--
-- Collision groups (registered in TrackGenerator):
--   RunGround   – anything the runner can stand on (roofs, ramps, tops)
--   RunObstacle – anything the runner can crash into
-- Scenery stays in Default so the runner's probes ignore it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local ModelFactory = require(Shared.ModelFactory)
local PowerUpData = require(Shared.PowerUpData)
local Util = require(Shared.Util)

local Destruction = require(script.Parent.Destruction)

local Segments = {}

local LANES = Config.Run.LanePositions
local LANE_IDS = { -1, 0, 1 }
local ROAD_WIDTH = 30
local RAMP_LENGTH = 20
local STREET_Y = -75 -- the street far below (relative to the run origin)

local THEME = {
	Roof = Color3.fromRGB(78, 74, 82),
	RoofLine = Color3.fromRGB(235, 220, 170),
	Parapet = Color3.fromRGB(200, 185, 170),
	Coin = Color3.fromRGB(255, 200, 40),
	Buildings = {
		Color3.fromRGB(214, 120, 96),
		Color3.fromRGB(232, 178, 120),
		Color3.fromRGB(150, 120, 170),
		Color3.fromRGB(120, 150, 190),
		Color3.fromRGB(210, 150, 160),
		Color3.fromRGB(170, 160, 140),
	},
	Neon = { Color3.fromRGB(255, 90, 170), Color3.fromRGB(90, 220, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(160, 255, 110) },
}

local BILLBOARDS = { "TRALALERO TRALALA", "BOMBARDIRO CROCODILO", "BRR BRR PATAPIM", "CAPPUCCINO ASSASSINO", "WANTED: VERITY", "CHIMPANZINI BANANINI", "LIRILÌ LARILÀ" }

export type Ctx = {
	folder: Model,
	origin: Vector3,
	startD: number,
	length: number,
	rng: Random,
	difficulty: number,
	distance: number,
	height: number, -- this roof's height above the run origin
	prevHeight: number, -- the previous roof's height (a ramp climbs from it)
	flatFrom: number?, -- where the flat roof starts (after a ramp)
}

local OBSTACLE_TYPE: { [string]: string } = {
	Barricade = "Jump",
	SteelBarrier = "Jump",
	OverheadSign = "Roll",
	OverheadPipe = "Roll",
	Crates = "Block",
	WoodWall = "Block",
	ConcreteWall = "Block",
	Shed = "Block",
}

-- ───────────────────────────── helpers ─────────────────────────────

local function W(ctx: Ctx, x: number, y: number, d: number): Vector3
	return ctx.origin + Vector3.new(x, ctx.height + y, -(ctx.startD + d))
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

-- The roof of this segment's building, the building itself below it, a ramp
-- up from a lower previous roof, and (optionally) a gap at the end.
local function roofFloor(ctx: Ctx, gapAtEnd: number?)
	local len = ctx.length
	local rise = ctx.height - ctx.prevHeight
	local slabStart = 0
	if rise > 0.1 then
		-- Full-width ramp climbing from the previous roof.
		ground(ctx, {
			Class = "WedgePart",
			Name = "RoofRamp",
			Size = Vector3.new(ROAD_WIDTH, rise, RAMP_LENGTH),
			-- A WedgePart's high edge is at +Z; turn it to rise along the track.
			CFrame = CF(ctx, 0, -rise / 2, RAMP_LENGTH / 2) * CFrame.Angles(0, math.pi, 0),
			Color = THEME.Roof,
			Material = Enum.Material.DiamondPlate,
		})
		slabStart = RAMP_LENGTH
		ctx.flatFrom = RAMP_LENGTH
	end
	local slabEnd = len - (gapAtEnd or 0)
	ground(ctx, {
		Name = "Roof",
		Size = Vector3.new(ROAD_WIDTH, 2, slabEnd - slabStart),
		CFrame = CF(ctx, 0, -1, (slabStart + slabEnd) / 2),
		Color = THEME.Roof,
		Material = Enum.Material.Asphalt,
	})
	-- Painted lane guides so the three lanes stay readable up here.
	for _, x in { -4, 4 } do
		scenery(ctx, { Name = "LaneGuide", Size = Vector3.new(0.35, 0.05, slabEnd - slabStart), CFrame = CF(ctx, x, 0.03, (slabStart + slabEnd) / 2), Color = THEME.RoofLine, CanCollide = false })
	end
	-- Low parapet walls along both edges.
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "Parapet", Size = Vector3.new(1.2, 1.6, slabEnd), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 + 0.6), 0.3, slabEnd / 2), Color = THEME.Parapet, Material = Enum.Material.Brick })
	end
	-- The building under the roof, all the way down to the street.
	local depth = ctx.height - STREET_Y - 2
	local color = THEME.Buildings[ctx.rng:NextInteger(1, #THEME.Buildings)]
	local building = scenery(ctx, { Name = "Building", Size = Vector3.new(ROAD_WIDTH + 3, depth, slabEnd), CFrame = CF(ctx, 0, -2 - depth / 2, slabEnd / 2), Color = color, Material = Enum.Material.Brick })
	for _, side in { -1, 1 } do
		scenery(ctx, {
			Parent = building,
			Name = "Windows",
			Size = Vector3.new(0.2, depth * 0.8, slabEnd * 0.85),
			CFrame = building.CFrame * CFrame.new(side * ((ROAD_WIDTH + 3) / 2 + 0.1), -depth * 0.05, 0),
			Color = Color3.fromRGB(255, 230, 170),
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CanCollide = false,
		})
	end
	if gapAtEnd and gapAtEnd > 0 then
		-- Bright warning stripe on the edge before the drop.
		scenery(ctx, { Name = "EdgeStripe", Size = Vector3.new(ROAD_WIDTH, 0.1, 1.2), CFrame = CF(ctx, 0, 0.05, slabEnd - 0.6), Color = Color3.fromRGB(255, 200, 0), Material = Enum.Material.Neon, CanCollide = false })
	end
end

-- The city around you: neighbouring rooftops, billboards and the street far below.
local function skyline(ctx: Ctx)
	local rng = ctx.rng
	scenery(ctx, { Name = "Street", Size = Vector3.new(400, 2, ctx.length), CFrame = CF(ctx, 0, STREET_Y - ctx.height, ctx.length / 2), Color = Color3.fromRGB(60, 60, 68), Material = Enum.Material.Asphalt })
	for _, side in { -1, 1 } do
		local d = 0
		while d < ctx.length do
			local depth = rng:NextNumber(30, 50)
			local width = rng:NextNumber(26, 44)
			local top = rng:NextNumber(-25, 35) -- relative to this roof
			local height = top - (STREET_Y - ctx.height)
			local x = side * (ROAD_WIDTH / 2 + 22 + width / 2 + rng:NextNumber(0, 20))
			local b = scenery(ctx, {
				Name = "Neighbour",
				Size = Vector3.new(width, height, math.min(depth, ctx.length - d)),
				CFrame = CF(ctx, x, top - height / 2, d + depth / 2),
				Color = THEME.Buildings[rng:NextInteger(1, #THEME.Buildings)],
				Material = Enum.Material.Brick,
			})
			if rng:NextNumber() < 0.35 then
				-- Neon billboard on the neighbour's roof
				local board = scenery(ctx, { Parent = b, Name = "Billboard", Size = Vector3.new(width * 0.8, 8, 0.6), CFrame = CF(ctx, x, top + 6, d + depth / 2) * CFrame.Angles(0, math.rad(side * 70), 0), Color = Color3.fromRGB(25, 20, 35) })
				Util.SurfaceLabel(board, Enum.NormalId.Front, BILLBOARDS[rng:NextInteger(1, #BILLBOARDS)], { PixelsPerStud = 8, TextColor = THEME.Neon[rng:NextInteger(1, #THEME.Neon)] })
				for _, px in { -0.3, 0.3 } do
					scenery(ctx, { Parent = b, Name = "BillboardLeg", Size = Vector3.new(0.6, 3, 0.6), CFrame = CF(ctx, x + px * width * 0.5, top + 1.5, d + depth / 2), Color = Color3.fromRGB(50, 50, 60) })
				end
			elseif rng:NextNumber() < 0.4 then
				-- Water tower
				local tower = CF(ctx, x, top, d + depth / 2)
				for _, o in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
					scenery(ctx, { Parent = b, Name = "TowerLeg", Size = Vector3.new(0.5, 6, 0.5), CFrame = tower * CFrame.new(o + Vector3.new(0, 3, 0)), Color = Color3.fromRGB(70, 60, 50) })
				end
				Util.UprightCylinder({ Parent = b, CFrame = tower * CFrame.new(0, 9, 0), Height = 6, Diameter = 6, Color = Color3.fromRGB(140, 100, 70), Material = Enum.Material.WoodPlanks, CanQuery = false })
			end
			d += depth + rng:NextNumber(4, 12)
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
		Color = THEME.Coin,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	c:SetAttribute("Coin", true)
	c:SetAttribute("Value", Config.Economy.CoinValue)
end

local function coinLine(ctx: Ctx, lane: number, d0: number, d1: number, y: number?)
	local d = d0
	while d <= d1 do
		coin(ctx, lane, y or 0, d)
		d += 5
	end
end

-- Coins along the exact jump arc centred on d, built from the runner's jump
-- physics so a jump sweeps straight through every coin.
local function coinArc(ctx: Ctx, lane: number, d: number)
	local meters = (ctx.startD + d) * Config.Run.MetersPerStud
	local profile = ImpactRules.JumpProfile(ImpactRules.SpeedAt(meters))
	local count = math.clamp(math.floor(profile.length / 5), 5, 11)
	for i = 0, count - 1 do
		local t = i / (count - 1)
		coin(ctx, lane, 4 * profile.apex * t * (1 - t), d - profile.length / 2 + t * profile.length)
	end
end

-- Floating pickup box (power-up or mystery box).
local function pickupBox(ctx: Ctx, lane: number, d: number, kind: string, color: Color3, label: string, y: number?): BasePart
	local box = Util.Part({
		Name = kind .. "Pickup",
		Parent = ctx.folder:FindFirstChild("Pickups"),
		Size = Vector3.new(2.8, 2.8, 2.8),
		CFrame = CF(ctx, LANES[lane], (y or 0) + 2.6, d) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	box:SetAttribute("Pickup", kind)
	Util.Billboard(box, label, UDim2.fromOffset(70, 70), Vector3.new(0, 3.2, 0))
	return box
end

local function powerUp(ctx: Ctx, lane: number, d: number, y: number?)
	local p = PowerUpData.Pick(ctx.rng)
	local box = pickupBox(ctx, lane, d, "PowerUp", p.color, p.icon, y)
	box:SetAttribute("PowerUpId", p.id)
end

local function mysteryBox(ctx: Ctx, lane: number, d: number, y: number?)
	pickupBox(ctx, lane, d, "MysteryBox", Color3.fromRGB(255, 180, 30), "❓", y)
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
	local board = solid(m, { Name = "Board", Size = Vector3.new(7, 7, 0.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = ({ Color3.fromRGB(255, 90, 160), Color3.fromRGB(40, 140, 255), Color3.fromRGB(255, 170, 40) })[ctx.rng:NextInteger(1, 3)] })
	local texts = { "VERITY\nWAS HERE", "⬇️ ROLL ⬇️", "TRALALERO\nTRALALA", "DUCK!", "BOMBARDIRO\nAIRLINES" }
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

-- Rooftop AC units: smash straight through them (or hop on top).
builders.Crates = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Crates", lane)
	local x = LANES[lane]
	for _, j in { -1, 1 } do
		local unit = solid(m, { Name = "ACUnit", Size = Vector3.new(3.2, 4, 3.2), CFrame = CF(ctx, x + j * 1.7, 2, d), Color = Color3.fromRGB(205, 210, 215), Material = Enum.Material.Metal })
		scenery(ctx, { Parent = m, Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.4, 2.4), CFrame = unit.CFrame * CFrame.new(0, 2.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 60, 70), CanCollide = false })
	end
	Destruction.Setup(m, 1, "Shatter", "Metal")
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

-- A long rooftop shed / air duct. Its roof is walkable (take the ramp up).
builders.Shed = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Shed", lane)
	local x = LANES[lane]
	local len = 40
	local colors = { Color3.fromRGB(150, 155, 165), Color3.fromRGB(110, 140, 170), Color3.fromRGB(170, 120, 100) }
	solid(m, { Name = "Body", Size = Vector3.new(7, 9.8, len), CFrame = CF(ctx, x, 4.9, d + len / 2), Color = colors[ctx.rng:NextInteger(1, #colors)], Material = Enum.Material.Metal })
	ground(ctx, { Parent = m, Name = "Roof", Size = Vector3.new(7, 0.4, len), CFrame = CF(ctx, x, 10, d + len / 2), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.DiamondPlate })
	local front = scenery(ctx, { Parent = m, Name = "Front", Size = Vector3.new(6, 3, 0.2), CFrame = CF(ctx, x, 6.5, d - 0.1), Color = Color3.fromRGB(30, 30, 40), CanCollide = false })
	Util.SurfaceLabel(front, Enum.NormalId.Back, "🧠 BRAINROT AIR", { PixelsPerStud = 15, TextColor = Color3.fromRGB(120, 220, 255) })
	Destruction.Setup(m, 4)
	return m
end

local function ramp(ctx: Ctx, lane: number, d: number, length: number)
	return ground(ctx, {
		Class = "WedgePart",
		Name = "Ramp",
		Size = Vector3.new(7, 10, length),
		-- A WedgePart's slope faces -Z (high edge at +Z). The track runs toward
		-- -Z, so turn it around to rise toward the shed.
		CFrame = CF(ctx, LANES[lane], 5, d + length / 2) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(120, 120, 130),
		Material = Enum.Material.DiamondPlate,
	})
end

-- Every obstacle gets an invisible standable top, so you can land on (and run
-- across) anything you can reach: AC units, walls, barriers, billboards.
local function addStandTop(model: Model)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local top = Util.Part({
		Name = "StandTop",
		Parent = model,
		Size = Vector3.new(size.X, 0.3, size.Z),
		CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 - 0.15, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = true,
		CastShadow = false,
	})
	top.CollisionGroup = "RunGround"
end

function Segments.Obstacle(ctx: Ctx, kind: string, lane: number, d: number): Model
	local model = builders[kind](ctx, lane, d)
	if kind ~= "Shed" then
		addStandTop(model)
	end
	return model
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

-- Rows of obstacles between d0 and d1. Rows are well spaced (the lanes stay
-- readable), every row leaves a way through without breaking anything, and
-- coin lines guide you through the gaps.
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
	local spacing = Util.Lerp(55, 32, ctx.difficulty)
	local d = math.max(d0, (ctx.flatFrom or 0) + 4)
	while d <= d1 do
		local freeChance = Util.Lerp(0.6, 0.3, ctx.difficulty)
		local row: { [number]: string? } = {}
		local passable = 0
		local blocks = 0
		for _, lane in open do
			if rng:NextNumber() < freeChance then
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
				if (kind == "Barricade" or kind == "SteelBarrier") and lane == coinLane then
					coinArc(ctx, lane, d)
				end
			elseif lane == coinLane then
				coinLine(ctx, lane, d - spacing * 0.4, d + spacing * 0.4)
			end
		end
		d += spacing + rng:NextNumber(-4, 4)
	end
end

local EDGE = Config.Run.SafeZoneAtSegmentEdges

-- Power-ups and mystery boxes sit in the calm stretch at the start of a
-- segment (after any ramp) so they never overlap an obstacle.
local function maybePickups(ctx: Ctx)
	local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
	local d = (ctx.flatFrom or 0) + EDGE * 0.5
	if ctx.rng:NextNumber() < Config.PowerUps.SpawnChancePerSegment then
		powerUp(ctx, lane, d)
	elseif ctx.rng:NextNumber() < 0.15 then
		mysteryBox(ctx, lane, d)
	end
end

-- ───────────────────────────── segment types ─────────────────────────────

export type SegmentDef = {
	name: string,
	weight: number,
	minDistance: number,
	cooldown: number, -- segments that must pass before this can repeat
	gap: number?, -- this segment ends in a gap of this many studs
	build: (ctx: Ctx) -> (),
}

local defs: { SegmentDef } = {}

local function define(def: SegmentDef)
	table.insert(defs, def)
end

-- A plain roof: parapets to jump, billboards to roll under, AC units.
define({
	name = "Rooftop",
	weight = 10,
	minDistance = 0,
	cooldown = 0,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { Barricade = 4, OverheadSign = 3, Crates = 2, SteelBarrier = 1 })
		maybePickups(ctx)
	end,
})

-- The roof ends — leap the gap to the next building! Coins show the arc,
-- and sometimes a plank bridges one lane.
local LEAP_GAP = 10
define({
	name = "Leap",
	weight = 6,
	minDistance = 150,
	cooldown = 1,
	gap = LEAP_GAP,
	build = function(ctx)
		roofFloor(ctx, LEAP_GAP)
		skyline(ctx)
		local edge = ctx.length - LEAP_GAP
		obstacleRows(ctx, EDGE + 12, edge - 30, { Barricade = 3, OverheadSign = 2, Crates = 2 })
		local arcLane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
		coinArc(ctx, arcLane, edge + LEAP_GAP / 2)
		if ctx.rng:NextNumber() < 0.35 then
			local plankLane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
			ground(ctx, { Name = "Plank", Size = Vector3.new(3.4, 0.6, LEAP_GAP + 2), CFrame = CF(ctx, LANES[plankLane], -0.3, edge + LEAP_GAP / 2), Color = Color3.fromRGB(150, 105, 60), Material = Enum.Material.WoodPlanks })
		end
		local sign = scenery(ctx, { Name = "JumpSign", Size = Vector3.new(10, 3, 0.4), CFrame = CF(ctx, -ROAD_WIDTH / 2 - 4, 6, edge - 14), Color = Color3.fromRGB(255, 200, 0) })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "⚠️ JUMP!", { PixelsPerStud = 15, TextColor = Color3.fromRGB(30, 20, 0) })
		maybePickups(ctx)
	end,
})

-- Rooftop sheds: switch lanes around them, or take the ramp and run on top.
define({
	name = "Sheds",
	weight = 7,
	minDistance = 60,
	cooldown = 1,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		local start = (ctx.flatFrom or 0) + EDGE
		local rampLane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
		ramp(ctx, rampLane, start, 26)
		Segments.Obstacle(ctx, "Shed", rampLane, start + 26)
		Segments.Obstacle(ctx, "Shed", rampLane, start + 68)
		coinLine(ctx, rampLane, start + 28, math.min(start + 104, ctx.length - 4), 10.2)
		local skip = { [rampLane] = true }
		for _, lane in LANE_IDS do
			if lane ~= rampLane and ctx.rng:NextNumber() < 0.55 then
				Segments.Obstacle(ctx, "Shed", lane, start + ctx.rng:NextNumber(20, 45))
				skip[lane] = true
			end
		end
		obstacleRows(ctx, start + 25, ctx.length - EDGE, { Barricade = 2, OverheadSign = 2 }, skip)
		maybePickups(ctx)
	end,
})

-- Straight through a glass penthouse: pipes to roll under, vents to jump.
define({
	name = "Penthouse",
	weight = 4,
	minDistance = 250,
	cooldown = 2,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		local from = ctx.flatFrom or 0
		local len = ctx.length - from
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "GlassWall", Size = Vector3.new(1, 16, len), CFrame = CF(ctx, side * 15.5, 8, from + len / 2), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.5 })
			for d = from + 10, ctx.length - 10, 22 do
				scenery(ctx, { Name = "Lamp", Size = Vector3.new(0.3, 1, 5), CFrame = CF(ctx, side * 14.8, 12, d), Color = Color3.fromRGB(255, 230, 160), Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		scenery(ctx, { Name = "GlassRoof", Size = Vector3.new(32, 1, len), CFrame = CF(ctx, 0, 16.5, from + len / 2), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.6 })
		local sign = scenery(ctx, { Name = "PenthouseSign", Size = Vector3.new(24, 3.5, 0.5), CFrame = CF(ctx, 0, 14, from + 2), Color = Color3.fromRGB(25, 20, 35) })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "✨ BRAINROT PENTHOUSE ✨", { PixelsPerStud = 14, TextColor = Color3.fromRGB(255, 200, 90) })
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { SteelBarrier = 3, OverheadPipe = 3, Crates = 1 })
		maybePickups(ctx)
	end,
})

-- Smash zone: wooden walls to crash through at speed (or hop over with sneakers).
define({
	name = "Smash",
	weight = 4,
	minDistance = 400,
	cooldown = 2,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { WoodWall = 4, Crates = 2, Barricade = 2, ConcreteWall = 1 })
		maybePickups(ctx)
	end,
})

-- Bonus vault: the middle lane is sealed by a wall. Break in for loot.
define({
	name = "Vault",
	weight = 3,
	minDistance = 300,
	cooldown = 4,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		local vaultStart = math.max(EDGE + 20, (ctx.flatFrom or 0) + 8)
		local vaultEnd = ctx.length - EDGE - 6
		local entrance = Segments.Obstacle(ctx, if ctx.rng:NextNumber() < 0.6 then "WoodWall" else "ConcreteWall", 0, vaultStart)
		entrance:SetAttribute("Vault", true)
		local sign = scenery(ctx, { Name = "VaultSign", Size = Vector3.new(7, 2.5, 0.3), CFrame = CF(ctx, 0, 13.5, vaultStart), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "💥 BONUS 💥", { PixelsPerStud = 20 })
		for _, side in { -1, 1 } do
			-- Lane 99: never "in front" of the runner, so touching it is always a side bump.
			local divider = obstacleModel(ctx, "VaultDivider", 99)
			divider:SetAttribute("ObstacleType", "Block")
			solid(divider, { Name = "Divider", Size = Vector3.new(0.8, 12, vaultEnd - vaultStart), CFrame = CF(ctx, side * 4, 6, (vaultStart + vaultEnd) / 2), Color = THEME.Parapet, Material = Enum.Material.Brick })
			Destruction.Setup(divider, 4)
		end
		coinLine(ctx, 0, vaultStart + 6, vaultEnd - 6)
		mysteryBox(ctx, 0, (vaultStart + vaultEnd) / 2)
		obstacleRows(ctx, vaultStart + 14, vaultEnd, { Barricade = 2, OverheadSign = 2, Crates = 1 }, { [0] = true })
		Segments.Obstacle(ctx, "Crates", if ctx.rng:NextNumber() < 0.5 then -1 else 1, vaultStart)
	end,
})

-- A caged Brainrot on the roof: run through the cage to rescue it.
-- Rescued Brainrots go to your base and raise your score multiplier.
define({
	name = "Rescue",
	weight = 5,
	minDistance = 120,
	cooldown = 3,
	build = function(ctx)
		roofFloor(ctx)
		skyline(ctx)
		local brainrot = BrainrotData.PickCatchable(ctx.distance, ctx.rng)
		if brainrot then
			local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
			local d = ctx.length / 2
			local color = BrainrotData.RarityColors[brainrot.rarity] or THEME.Coin
			-- The pickup is the glowing floor plate; the cage and Brainrot hang off it.
			local plate = Util.Part({
				Name = "BrainrotCage",
				Parent = ctx.folder:FindFirstChild("Pickups"),
				Size = Vector3.new(6.5, 0.4, 6.5),
				CFrame = CF(ctx, LANES[lane], 0.2, d),
				Color = color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			plate:SetAttribute("Pickup", "Brainrot")
			plate:SetAttribute("BrainrotId", brainrot.id)
			for _, corner in { Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) } do
				Util.Part({ Parent = plate, Name = "CageBar", Size = Vector3.new(0.4, 9, 0.4), CFrame = CF(ctx, LANES[lane] + corner.X, 4.7, d + corner.Z), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			end
			for i = -1, 1 do
				Util.Part({ Parent = plate, Name = "CageBar", Size = Vector3.new(0.25, 9, 0.25), CFrame = CF(ctx, LANES[lane] + i * 1.5, 4.7, d - 3), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			end
			Util.Part({ Parent = plate, Name = "CageTop", Size = Vector3.new(6.8, 0.5, 6.8), CFrame = CF(ctx, LANES[lane], 9.3, d), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			local model = ModelFactory.Brainrot(brainrot.id, 0.9)
			model:PivotTo(CF(ctx, LANES[lane], 0.4, d) * CFrame.Angles(0, math.pi, 0))
			model.Parent = plate
			ModelFactory.NameTag(model, ("🔓 RESCUE %s %s  (+%dx)"):format(brainrot.icon, string.upper(brainrot.name), brainrot.bonus), color, 12)
			coinLine(ctx, lane, math.max(d - 32, (ctx.flatFrom or 0) + 2), d - 8)
			obstacleRows(ctx, d + 16, ctx.length - EDGE, { Barricade = 1, OverheadSign = 1 })
		end
	end,
})

Segments.Definitions = defs

-- The start: the roof of Verity's tower. He bursts out of the stairwell
-- door behind you during the intro.
function Segments.BuildStartArea(ctx: Ctx)
	roofFloor(ctx)
	skyline(ctx)
	ground(ctx, { Name = "RoofBehind", Size = Vector3.new(ROAD_WIDTH, 2, 50), CFrame = CF(ctx, 0, -1, -25), Color = THEME.Roof, Material = Enum.Material.Asphalt })

	-- Stairwell hut behind the player
	local hut = scenery(ctx, { Name = "Stairwell", Size = Vector3.new(26, 18, 18), CFrame = CF(ctx, 0, 9, -26), Color = Color3.fromRGB(120, 90, 130), Material = Enum.Material.Brick })
	scenery(ctx, { Parent = hut, Name = "Door", Size = Vector3.new(12, 13, 0.4), CFrame = CF(ctx, 0, 6.5, -16.9), Color = Color3.fromRGB(10, 8, 14), CanCollide = false })
	local sign = scenery(ctx, { Parent = hut, Name = "HutSign", Size = Vector3.new(22, 3.5, 0.4), CFrame = CF(ctx, 0, 15.5, -16.8), Color = Color3.fromRGB(255, 90, 160), Material = Enum.Material.Neon })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, ("%s'S TOWER"):format(Config.Villain.Title), { PixelsPerStud = 12 })

	local banner = scenery(ctx, { Name = "StartBanner", Size = Vector3.new(30, 5, 0.5), CFrame = CF(ctx, 0, 19, 32), Color = Color3.fromRGB(25, 20, 35) })
	Util.SurfaceLabel(banner, Enum.NormalId.Back, ("RUN! %s IS COMING"):format(Config.Villain.Title), { PixelsPerStud = 12, TextColor = Color3.fromRGB(255, 200, 90) })
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "BannerPost", Size = Vector3.new(1, 21, 1), CFrame = CF(ctx, side * 15, 10.5, 32), Color = Color3.fromRGB(45, 45, 55) })
	end
	coinLine(ctx, 0, 40, ctx.length - 8)
end

return Segments
