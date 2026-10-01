--!strict
-- The track: BRAINROT CITY STREETS at sunset. Three lanes down the middle of
-- the road (Subway Surfers style), shops and apartment blocks on both sides,
-- Verity chasing you.
--
-- Tall things — buses and tunnels — are too high for a normal jump (it peaks
-- at ~9 studs). With a JUMP BOOST (👟 Super Sneakers or 🛹 a hoverboard) you
-- can jump onto their roofs and run across the top, where the best coin lines
-- are. Without one, switch lanes round a bus or run through the tunnel.
--
-- Track space: `d` is distance along the run (forward = world -Z), `x` is the
-- sideways offset from the centre lane, `y` is height above the road.
--
-- Collision groups (registered in TrackGenerator):
--   RunGround   – anything the runner can stand on (road, bus/tunnel roofs)
--   RunObstacle – anything the runner can crash into
-- Scenery stays in Default so the runner's probes ignore it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local ModelFactory = require(Shared.ModelFactory)
local MutationData = require(Shared.MutationData)
local PowerUpData = require(Shared.PowerUpData)
local Util = require(Shared.Util)

local Destruction = require(script.Parent.Destruction)

local Segments = {}

local LANES = Config.Run.LanePositions
local LANE_IDS = { -1, 0, 1 }
local ROAD_WIDTH = 30
local SIDEWALK = 8

-- Boost-only heights. A normal jump peaks at ~9 (head at ~14.6), so the
-- tunnel ceiling sits above that and both roofs sit above the jump.
local BUS_HEIGHT = 12 -- body; the roof you land on is at 12.5
local BUS_LENGTH = 38
local TUNNEL_CEILING = 15 -- underside of the tunnel roof
local TUNNEL_ROOF = 16 -- top of the tunnel roof

local THEME = {
	Road = Color3.fromRGB(58, 58, 66),
	LaneLine = Color3.fromRGB(240, 240, 235),
	Sidewalk = Color3.fromRGB(200, 190, 180),
	Curb = Color3.fromRGB(150, 145, 140),
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
	Bus = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(230, 70, 80), Color3.fromRGB(70, 150, 230) },
}

local SHOP_SIGNS = { "TRALALERO PIZZA", "BOMBARDIRO TRAVEL", "PATAPIM SHOES", "CAPPUCCINO CAFÉ", "LIRILÌ GROCERY", "BANANINI SMOOTHIES", "BALLERINA DANCE", "TRIPPI TOYS" }
local BILLBOARDS = { "TRALALERO TRALALA", "BOMBARDIRO CROCODILO", "BRR BRR PATAPIM", "CAPPUCCINO ASSASSINO", "WANTED: VERITY", "CHIMPANZINI BANANINI" }

export type Ctx = {
	folder: Model,
	origin: Vector3,
	startD: number,
	length: number,
	rng: Random,
	difficulty: number,
	distance: number,
}

local OBSTACLE_TYPE: { [string]: string } = {
	Barricade = "Jump",
	SteelBarrier = "Jump",
	OverheadSign = "Roll",
	OverheadPipe = "Roll",
	Crates = "Block",
	WoodWall = "Block",
	ConcreteWall = "Block",
	Bus = "Block",
	TunnelEntrance = "Block",
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

-- Every obstacle knows its lane and where it starts along the track (the
-- client uses TrackD to spot jumps, rolls and near misses for the combo).
local function obstacleModel(ctx: Ctx, kind: string, lane: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("ObstacleType", OBSTACLE_TYPE[kind])
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Lane", lane)
	model:SetAttribute("TrackD", ctx.startD + d)
	model.Parent = ctx.folder
	return model
end

-- The road: three lanes with dashed lines, curbs and sidewalks.
local function streetFloor(ctx: Ctx)
	local len = ctx.length
	ground(ctx, { Name = "Road", Size = Vector3.new(ROAD_WIDTH, 2, len), CFrame = CF(ctx, 0, -1, len / 2), Color = THEME.Road, Material = Enum.Material.Asphalt })
	for _, x in { -4, 4 } do
		for d = 3, len - 3, 10 do
			scenery(ctx, { Name = "LaneDash", Size = Vector3.new(0.4, 0.05, 5), CFrame = CF(ctx, x, 0.03, d), Color = THEME.LaneLine, CanCollide = false })
		end
	end
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "Curb", Size = Vector3.new(0.8, 0.8, len), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 + 0.4), 0.4, len / 2), Color = THEME.Curb, Material = Enum.Material.Concrete })
		scenery(ctx, { Name = "Sidewalk", Size = Vector3.new(SIDEWALK, 1, len), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 + 0.8 + SIDEWALK / 2), 0.1, len / 2), Color = THEME.Sidewalk, Material = Enum.Material.Concrete })
	end
end

-- Shops and apartment blocks along both sides, lamp posts on the sidewalk.
local function cityScenery(ctx: Ctx)
	local rng = ctx.rng
	local edge = ROAD_WIDTH / 2 + 0.8 + SIDEWALK
	for _, side in { -1, 1 } do
		for d = 20, ctx.length, 40 do
			local x = side * (ROAD_WIDTH / 2 + 2)
			local pole = scenery(ctx, { Name = "LampPole", Size = Vector3.new(0.6, 13, 0.6), CFrame = CF(ctx, x, 6.5, d), Color = Color3.fromRGB(45, 45, 55) })
			scenery(ctx, { Parent = pole, Name = "Lamp", Size = Vector3.new(2.6, 0.5, 1.2), CFrame = CF(ctx, x - side * 1, 13, d), Color = Color3.fromRGB(255, 230, 160), Material = Enum.Material.Neon, CanCollide = false })
		end
		local d = 0
		while d < ctx.length do
			local depth = math.min(rng:NextNumber(22, 40), ctx.length - d)
			local height = rng:NextNumber(24, 60)
			local width = rng:NextNumber(24, 36)
			local x = side * (edge + width / 2)
			local building = scenery(ctx, {
				Name = "Building",
				Size = Vector3.new(width, height, depth),
				CFrame = CF(ctx, x, height / 2, d + depth / 2),
				Color = THEME.Buildings[rng:NextInteger(1, #THEME.Buildings)],
				Material = Enum.Material.Brick,
			})
			local face = side * -(width / 2 + 0.1)
			-- Shop front with a Brainrot shop sign
			local shopColor = THEME.Neon[rng:NextInteger(1, #THEME.Neon)]
			scenery(ctx, { Parent = building, Name = "ShopWindow", Size = Vector3.new(0.2, 6, depth * 0.7), CFrame = building.CFrame * CFrame.new(face, -height / 2 + 4, 0), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
			local sign = scenery(ctx, { Parent = building, Name = "ShopSign", Size = Vector3.new(0.4, 2.4, depth * 0.8), CFrame = building.CFrame * CFrame.new(face, -height / 2 + 8.6, 0), Color = Color3.fromRGB(25, 20, 35), CanCollide = false })
			Util.SurfaceLabel(sign, if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left, SHOP_SIGNS[rng:NextInteger(1, #SHOP_SIGNS)], { PixelsPerStud = 10, TextColor = shopColor })
			-- Lit apartment windows above
			scenery(ctx, { Parent = building, Name = "Windows", Size = Vector3.new(0.2, height - 16, depth * 0.8), CFrame = building.CFrame * CFrame.new(face, 5, 0), Color = Color3.fromRGB(255, 230, 170), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false })
			if rng:NextNumber() < 0.25 then
				local board = scenery(ctx, { Parent = building, Name = "Billboard", Size = Vector3.new(width * 0.8, 8, 0.6), CFrame = CF(ctx, x, height + 5, d + depth / 2) * CFrame.Angles(0, math.rad(side * 70), 0), Color = Color3.fromRGB(25, 20, 35) })
				Util.SurfaceLabel(board, Enum.NormalId.Front, BILLBOARDS[rng:NextInteger(1, #BILLBOARDS)], { PixelsPerStud = 8, TextColor = THEME.Neon[rng:NextInteger(1, #THEME.Neon)] })
			end
			d += depth + rng:NextNumber(2, 6)
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

local function powerUp(ctx: Ctx, lane: number, d: number, y: number?, id: string?)
	local p = (if id then PowerUpData.Get(id) else nil) or PowerUpData.Pick(ctx.rng)
	local box = pickupBox(ctx, lane, d, "PowerUp", p.color, p.icon, y)
	box:SetAttribute("PowerUpId", p.id)
end

local function mysteryBox(ctx: Ctx, lane: number, d: number, y: number?)
	pickupBox(ctx, lane, d, "MysteryBox", Color3.fromRGB(255, 180, 30), "❓", y)
end

-- ───────────────────────────── obstacles ─────────────────────────────

local builders: { [string]: (ctx: Ctx, lane: number, d: number) -> Model } = {}

builders.Barricade = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Barricade", lane, d)
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

-- Concrete road barrier with warning stripes (unbreakable: jump it).
builders.SteelBarrier = function(ctx, lane, d)
	local m = obstacleModel(ctx, "SteelBarrier", lane, d)
	local x = LANES[lane]
	solid(m, { Name = "Barrier", Size = Vector3.new(7, 3, 1.2), CFrame = CF(ctx, x, 1.5, d), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Concrete })
	for i = -1, 1 do
		scenery(ctx, { Parent = m, Name = "Stripe", Size = Vector3.new(1.2, 3.02, 1.22), CFrame = CF(ctx, x + i * 2.4, 1.5, d), Color = Color3.fromRGB(255, 120, 0), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	Destruction.Setup(m, 4)
	return m
end

builders.OverheadSign = function(ctx, lane, d)
	local m = obstacleModel(ctx, "OverheadSign", lane, d)
	local x = LANES[lane]
	for _, side in { -1, 1 } do
		solid(m, { Name = "Post", Size = Vector3.new(0.4, 10.5, 0.4), CFrame = CF(ctx, x + side * 3.7, 5.25, d), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
	end
	local board = solid(m, { Name = "Board", Size = Vector3.new(7, 7, 0.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = ({ Color3.fromRGB(255, 90, 160), Color3.fromRGB(40, 140, 255), Color3.fromRGB(40, 160, 90) })[ctx.rng:NextInteger(1, 3)] })
	local texts = { "VERITY\nWAS HERE", "⬇️ ROLL ⬇️", "TRALALERO\nAVENUE", "DUCK!", "BRAINROT\nCITY" }
	Util.SurfaceLabel(board, Enum.NormalId.Back, texts[ctx.rng:NextInteger(1, #texts)], { PixelsPerStud = 20 })
	Destruction.Setup(m, 1, "Shatter", "Metal")
	return m
end

-- A scaffolding beam across the lane (unbreakable: roll under it).
builders.OverheadPipe = function(ctx, lane, d)
	local m = obstacleModel(ctx, "OverheadPipe", lane, d)
	local x = LANES[lane]
	for _, side in { -1, 1 } do
		solid(m, { Name = "Support", Size = Vector3.new(0.6, 10.5, 0.6), CFrame = CF(ctx, x + side * 3.7, 5.25, d), Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal })
	end
	solid(m, { Name = "Beam", Size = Vector3.new(7, 7, 1.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = Color3.fromRGB(255, 170, 30), Material = Enum.Material.Metal })
	Destruction.Setup(m, 4)
	return m
end

-- Market crates: smash straight through them.
builders.Crates = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Crates", lane, d)
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
	local m = obstacleModel(ctx, kind, lane, d)
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
	return wall(ctx, lane, d, "ConcreteWall", 3, Color3.fromRGB(175, 175, 180), Enum.Material.Concrete, 2)
end

-- A city bus. Too tall to jump normally: go round it, or boost-jump onto the
-- roof (👟 / 🛹) and run along the top.
builders.Bus = function(ctx, lane, d)
	local m = obstacleModel(ctx, "Bus", lane, d)
	local x = LANES[lane]
	local color = THEME.Bus[ctx.rng:NextInteger(1, #THEME.Bus)]
	solid(m, { Name = "Body", Size = Vector3.new(7, BUS_HEIGHT - 1, BUS_LENGTH), CFrame = CF(ctx, x, 1 + (BUS_HEIGHT - 1) / 2, d + BUS_LENGTH / 2), Color = color, Material = Enum.Material.SmoothPlastic })
	ground(ctx, { Parent = m, Name = "BusRoof", Size = Vector3.new(7, 0.5, BUS_LENGTH), CFrame = CF(ctx, x, BUS_HEIGHT + 0.25, d + BUS_LENGTH / 2), Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.SmoothPlastic })
	for _, side in { -1, 1 } do
		scenery(ctx, { Parent = m, Name = "Windows", Size = Vector3.new(0.2, 3.2, BUS_LENGTH - 6), CFrame = CF(ctx, x + side * 3.55, 7.6, d + BUS_LENGTH / 2 + 1), Color = Color3.fromRGB(60, 80, 110), Material = Enum.Material.Glass, CanCollide = false })
		for _, wd in { 6, BUS_LENGTH - 7 } do
			scenery(ctx, { Parent = m, Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 3, 3), CFrame = CF(ctx, x + side * 3.3, 1.5, d + wd), Color = Color3.fromRGB(25, 25, 30), CanCollide = false })
		end
	end
	scenery(ctx, { Parent = m, Name = "Front", Size = Vector3.new(6.4, 4, 0.2), CFrame = CF(ctx, x, 7.6, d - 0.1), Color = Color3.fromRGB(60, 80, 110), Material = Enum.Material.Glass, CanCollide = false })
	local destination = scenery(ctx, { Parent = m, Name = "Destination", Size = Vector3.new(6.4, 1.4, 0.2), CFrame = CF(ctx, x, 10.6, d - 0.1), Color = Color3.fromRGB(20, 20, 25), CanCollide = false })
	Util.SurfaceLabel(destination, Enum.NormalId.Back, ("🧠 %s EXPRESS"):format(string.upper(Config.Villain.Name)), { PixelsPerStud = 15, TextColor = Color3.fromRGB(255, 180, 40) })
	Destruction.Setup(m, 4)
	return m
end

-- Invisible standable top on tall obstacles (walls, signs), so with a jump
-- boost you can land on those too. Low things don't get one: you jump over
-- them, you don't stand on them.
local function addStandTop(model: Model, baseY: number)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local top = cf.Position.Y + size.Y / 2 - baseY
	if top <= Config.Run.HighGround + 0.5 then
		return
	end
	local slab = Util.Part({
		Name = "StandTop",
		Parent = model,
		Size = Vector3.new(size.X, 0.3, size.Z),
		CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 - 0.15, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = true,
		CastShadow = false,
	})
	slab.CollisionGroup = "RunGround"
end

local HAS_OWN_ROOF = { Bus = true }

function Segments.Obstacle(ctx: Ctx, kind: string, lane: number, d: number): Model
	local model = builders[kind](ctx, lane, d)
	if not HAS_OWN_ROOF[kind] then
		addStandTop(model, ctx.origin.Y)
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
	local d = d0
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
-- segment so they never overlap an obstacle.
local function maybePickups(ctx: Ctx)
	local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
	if ctx.rng:NextNumber() < Config.PowerUps.SpawnChancePerSegment then
		powerUp(ctx, lane, EDGE * 0.5)
	elseif ctx.rng:NextNumber() < 0.15 then
		mysteryBox(ctx, lane, EDGE * 0.5)
	end
end

local function sideSign(ctx: Ctx, d: number, text: string, color: Color3)
	local sign = scenery(ctx, { Name = "Sign", Size = Vector3.new(12, 3, 0.4), CFrame = CF(ctx, -ROAD_WIDTH / 2 - 3, 7, d), Color = color, Material = Enum.Material.Neon })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, text, { PixelsPerStud = 14, TextColor = Color3.fromRGB(20, 15, 10) })
	scenery(ctx, { Name = "SignPost", Size = Vector3.new(0.5, 6, 0.5), CFrame = CF(ctx, -ROAD_WIDTH / 2 - 3, 3, d), Color = Color3.fromRGB(60, 60, 70) })
end

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

-- The bread and butter: barriers to jump, signs to roll under, crates to smash.
define({
	name = "Street",
	weight = 10,
	minDistance = 0,
	cooldown = 0,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { Barricade = 4, OverheadSign = 3, Crates = 2, SteelBarrier = 1 })
		maybePickups(ctx)
	end,
})

-- Buses: switch lanes round them — or boost-jump onto the roof, where a coin
-- line runs along the top.
define({
	name = "Buses",
	weight = 8,
	minDistance = 60,
	cooldown = 1,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
		local rng = ctx.rng
		local start = EDGE + 24
		local roofLane = LANE_IDS[rng:NextInteger(1, 3)]
		Segments.Obstacle(ctx, "Bus", roofLane, start)
		local convoy = rng:NextNumber() < 0.5
		if convoy then
			-- A second bus right behind: jump across the roofs.
			Segments.Obstacle(ctx, "Bus", roofLane, start + BUS_LENGTH + 6)
		end
		local roofEnd = start + (if convoy then BUS_LENGTH * 2 + 6 else BUS_LENGTH) - 4
		coinLine(ctx, roofLane, start + 4, roofEnd, BUS_HEIGHT + 0.5)
		if rng:NextNumber() < 0.3 then
			mysteryBox(ctx, roofLane, roofEnd - 6, BUS_HEIGHT + 0.5)
		end
		local skip = { [roofLane] = true }
		local extraBus = false
		for _, lane in LANE_IDS do
			-- One more bus at most, so there's always a lane on the road.
			if lane ~= roofLane and not extraBus and rng:NextNumber() < 0.4 then
				Segments.Obstacle(ctx, "Bus", lane, start + rng:NextNumber(0, 30))
				skip[lane] = true
				extraBus = true
			end
		end
		obstacleRows(ctx, start + 12, ctx.length - EDGE, { Barricade = 2, OverheadSign = 2 }, skip)
		-- Sometimes the boost is right there before the buses.
		if rng:NextNumber() < 0.35 then
			powerUp(ctx, roofLane, EDGE * 0.5, nil, "SuperSneakers")
		else
			maybePickups(ctx)
		end
	end,
})

-- An underpass. Run through it — or boost-jump onto the roof before the
-- entrance and run across the top (coins and sometimes a mystery box).
local TUNNEL_START = 40
local TUNNEL_LENGTH = 66
define({
	name = "Tunnel",
	weight = 5,
	minDistance = 200,
	cooldown = 2,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
		local rng = ctx.rng
		local d0, d1 = TUNNEL_START, TUNNEL_START + TUNNEL_LENGTH
		local mid = (d0 + d1) / 2
		local width = ROAD_WIDTH + 4
		-- Walls (outside the lanes), the roof you can run on, and its underside.
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "TunnelWall", Size = Vector3.new(4, TUNNEL_ROOF + 4, TUNNEL_LENGTH), CFrame = CF(ctx, side * (width / 2 + 2), (TUNNEL_ROOF + 4) / 2, mid), Color = Color3.fromRGB(120, 110, 105), Material = Enum.Material.Brick })
			for d = d0 + 8, d1 - 8, 14 do
				scenery(ctx, { Name = "TunnelLight", Size = Vector3.new(0.3, 0.8, 6), CFrame = CF(ctx, side * (width / 2 - 0.2), 10, d), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		ground(ctx, { Name = "TunnelRoof", Size = Vector3.new(width + 8, TUNNEL_ROOF - TUNNEL_CEILING, TUNNEL_LENGTH), CFrame = CF(ctx, 0, (TUNNEL_CEILING + TUNNEL_ROOF) / 2, mid), Color = Color3.fromRGB(140, 130, 120), Material = Enum.Material.Concrete })
		-- Railings along the top edges (scenery: purely for looks)
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "RoofRail", Size = Vector3.new(0.4, 2, TUNNEL_LENGTH), CFrame = CF(ctx, side * (width / 2 + 3.5), TUNNEL_ROOF + 1, mid), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
		end
		-- The entrance lip: crash into it if you jump at it without enough height.
		for _, lane in LANE_IDS do
			local lip = obstacleModel(ctx, "TunnelEntrance", lane, d0)
			lip:SetAttribute("NoStyle", true)
			solid(lip, { Name = "Lip", Size = Vector3.new(8, TUNNEL_ROOF - TUNNEL_CEILING, 1), CFrame = CF(ctx, LANES[lane], (TUNNEL_CEILING + TUNNEL_ROOF) / 2, d0 + 0.5), Color = Color3.fromRGB(140, 130, 120), Material = Enum.Material.Concrete, Transparency = 1 })
			Destruction.Setup(lip, 4)
		end
		-- Name sign high above the entrance (you run under it on the roof).
		local facade = scenery(ctx, { Name = "TunnelSign", Size = Vector3.new(width, 3.5, 0.6), CFrame = CF(ctx, 0, TUNNEL_ROOF + 8, d0), Color = Color3.fromRGB(60, 55, 70) })
		Util.SurfaceLabel(facade, Enum.NormalId.Back, "🚇 BRAINROT UNDERPASS", { PixelsPerStud = 12, TextColor = Color3.fromRGB(255, 200, 90) })
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "TunnelSignPost", Size = Vector3.new(0.8, 10, 0.8), CFrame = CF(ctx, side * (width / 2 + 2), TUNNEL_ROOF + 5, d0), Color = Color3.fromRGB(60, 55, 70) })
		end
		sideSign(ctx, d0 - 26, "👟🛹 BOOST ONTO THE ROOF!", Color3.fromRGB(255, 200, 0))

		-- On the roof: a long coin line (and maybe a mystery box).
		local roofLane = LANE_IDS[rng:NextInteger(1, 3)]
		coinLine(ctx, roofLane, d0 + 4, d1 - 4, TUNNEL_ROOF)
		if rng:NextNumber() < 0.4 then
			mysteryBox(ctx, LANE_IDS[rng:NextInteger(1, 3)], d1 - 12, TUNNEL_ROOF)
		end
		-- Inside: low obstacles only.
		obstacleRows(ctx, d0 + 10, d1 - 6, { Barricade = 3, SteelBarrier = 2, Crates = 2 })
		obstacleRows(ctx, d1 + 14, ctx.length - EDGE, { Barricade = 1, OverheadSign = 1 })
		if rng:NextNumber() < 0.35 then
			powerUp(ctx, LANE_IDS[rng:NextInteger(1, 3)], EDGE * 0.5, nil, "SuperSneakers")
		else
			maybePickups(ctx)
		end
	end,
})

-- Road works: scaffolding beams to roll under, barriers to jump.
define({
	name = "RoadWorks",
	weight = 4,
	minDistance = 250,
	cooldown = 2,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
		for _, side in { -1, 1 } do
			for d = 10, ctx.length - 10, 20 do
				scenery(ctx, { Name = "Cone", Size = Vector3.new(1, 1.6, 1), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 - 0.8), 0.8, d), Color = Color3.fromRGB(255, 120, 0) })
			end
		end
		sideSign(ctx, 8, "🚧 ROAD WORKS", Color3.fromRGB(255, 140, 0))
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { SteelBarrier = 3, OverheadPipe = 3, Crates = 1 })
		maybePickups(ctx)
	end,
})

-- Smash zone: wooden walls to crash through at speed (or hop over with a boost).
define({
	name = "Smash",
	weight = 4,
	minDistance = 400,
	cooldown = 2,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
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
		streetFloor(ctx)
		cityScenery(ctx)
		local vaultStart = EDGE + 20
		local vaultEnd = ctx.length - EDGE - 6
		local entrance = Segments.Obstacle(ctx, if ctx.rng:NextNumber() < 0.6 then "WoodWall" else "ConcreteWall", 0, vaultStart)
		entrance:SetAttribute("Vault", true)
		local sign = scenery(ctx, { Name = "VaultSign", Size = Vector3.new(7, 2.5, 0.3), CFrame = CF(ctx, 0, 13.5, vaultStart), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "💥 BONUS 💥", { PixelsPerStud = 20 })
		for _, side in { -1, 1 } do
			-- Lane 99: never "in front" of the runner, so touching it is always a side bump.
			local divider = obstacleModel(ctx, "VaultDivider", 99, vaultStart)
			divider:SetAttribute("ObstacleType", "Block")
			divider:SetAttribute("NoStyle", true)
			solid(divider, { Name = "Divider", Size = Vector3.new(0.8, 12, vaultEnd - vaultStart), CFrame = CF(ctx, side * 4, 6, (vaultStart + vaultEnd) / 2), Color = THEME.Curb, Material = Enum.Material.Brick })
			Destruction.Setup(divider, 4)
		end
		coinLine(ctx, 0, vaultStart + 6, vaultEnd - 6)
		mysteryBox(ctx, 0, (vaultStart + vaultEnd) / 2)
		obstacleRows(ctx, vaultStart + 14, vaultEnd, { Barricade = 2, OverheadSign = 2, Crates = 1 }, { [0] = true })
		Segments.Obstacle(ctx, "Crates", if ctx.rng:NextNumber() < 0.5 then -1 else 1, vaultStart)
	end,
})

-- A caged Brainrot in the road: run through the cage to rescue it.
-- Rescued Brainrots go to your base and raise your score multiplier.
define({
	name = "Rescue",
	weight = 5,
	minDistance = 120,
	cooldown = 3,
	build = function(ctx)
		streetFloor(ctx)
		cityScenery(ctx)
		local brainrot = BrainrotData.PickCatchable(ctx.distance, ctx.rng)
		if brainrot then
			local lane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
			local d = ctx.length / 2
			-- Sometimes it's a rare variant, visible in the cage before you get there.
			local mutation = MutationData.Roll(ctx.rng)
			local key = MutationData.Key(brainrot.id, mutation and mutation.id)
			local color = if mutation then mutation.color else (BrainrotData.RarityColors[brainrot.rarity] or THEME.Coin)
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
			if mutation then
				plate:SetAttribute("Mutation", mutation.id)
			end
			for _, corner in { Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) } do
				Util.Part({ Parent = plate, Name = "CageBar", Size = Vector3.new(0.4, 9, 0.4), CFrame = CF(ctx, LANES[lane] + corner.X, 4.7, d + corner.Z), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			end
			for i = -1, 1 do
				Util.Part({ Parent = plate, Name = "CageBar", Size = Vector3.new(0.25, 9, 0.25), CFrame = CF(ctx, LANES[lane] + i * 1.5, 4.7, d - 3), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			end
			Util.Part({ Parent = plate, Name = "CageTop", Size = Vector3.new(6.8, 0.5, 6.8), CFrame = CF(ctx, LANES[lane], 9.3, d), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
			local model = ModelFactory.Brainrot(key, 0.9)
			model:PivotTo(CF(ctx, LANES[lane], 0.4, d) * CFrame.Angles(0, math.pi, 0))
			model.Parent = plate
			local bonus = brainrot.bonus * MutationData.Multiplier(mutation and mutation.id)
			ModelFactory.NameTag(model, ("🔓 RESCUE %s %s  (+%dx)"):format(brainrot.icon, string.upper(MutationData.Label(key)), bonus), color, 12)
			coinLine(ctx, lane, d - 32, d - 8)
			obstacleRows(ctx, d + 16, ctx.length - EDGE, { Barricade = 1, OverheadSign = 1 })
		end
	end,
})

Segments.Definitions = defs

-- The start: the street in front of Verity's HQ. He bursts out of the garage
-- door behind you during the intro.
function Segments.BuildStartArea(ctx: Ctx)
	streetFloor(ctx)
	cityScenery(ctx)
	ground(ctx, { Name = "RoadBehind", Size = Vector3.new(ROAD_WIDTH, 2, 60), CFrame = CF(ctx, 0, -1, -30), Color = THEME.Road, Material = Enum.Material.Asphalt })

	-- Verity's HQ behind the player
	local hq = scenery(ctx, { Name = "VerityHQ", Size = Vector3.new(60, 40, 30), CFrame = CF(ctx, 0, 20, -34), Color = Color3.fromRGB(120, 70, 140), Material = Enum.Material.Brick })
	scenery(ctx, { Parent = hq, Name = "GarageDoor", Size = Vector3.new(24, 15, 0.4), CFrame = CF(ctx, 0, 7.5, -18.9), Color = Color3.fromRGB(10, 8, 14), CanCollide = false })
	local sign = scenery(ctx, { Parent = hq, Name = "HQSign", Size = Vector3.new(34, 5, 0.4), CFrame = CF(ctx, 0, 20, -18.8), Color = Color3.fromRGB(255, 90, 160), Material = Enum.Material.Neon })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, ("🧠 %s HQ"):format(Config.Villain.Title), { PixelsPerStud = 12 })

	local banner = scenery(ctx, { Name = "StartBanner", Size = Vector3.new(30, 5, 0.5), CFrame = CF(ctx, 0, 19, 32), Color = Color3.fromRGB(25, 20, 35) })
	Util.SurfaceLabel(banner, Enum.NormalId.Back, ("RUN! %s IS COMING"):format(Config.Villain.Title), { PixelsPerStud = 12, TextColor = Color3.fromRGB(255, 200, 90) })
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "BannerPost", Size = Vector3.new(1, 21, 1), CFrame = CF(ctx, side * 15, 10.5, 32), Color = Color3.fromRGB(45, 45, 55) })
	end
	coinLine(ctx, 0, 40, ctx.length - 8)
end

return Segments
