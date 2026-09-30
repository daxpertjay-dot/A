--!strict
-- The track: VERITY'S RAIL YARD. One consistent world (Subway Surfers
-- style): three rail lanes through a night-time freight yard and factory,
-- with the villain chasing you. Every segment is kept deliberately clean:
-- the lanes hold only what you have to react to, scenery stays off to the
-- sides.
--
-- Track space: `d` is distance along the run (forward = world -Z), `x` is the
-- sideways offset from the centre lane, `y` is height above the ground.
--
-- Collision groups (registered in TrackGenerator):
--   RunGround   – anything the runner can stand on (ground, ramps, train roofs)
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

local THEME = {
	Ground = Color3.fromRGB(62, 58, 66),
	Rail = Color3.fromRGB(150, 150, 160),
	Wall = Color3.fromRGB(85, 82, 92),
	Toxic = Color3.fromRGB(120, 255, 80),
	Evil = Color3.fromRGB(150, 60, 220),
	Coin = Color3.fromRGB(255, 200, 40),
	Silhouette = Color3.fromRGB(28, 24, 36),
}

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

-- Gravel bed with a pair of rails in every lane, low walls at the edges.
local function yardFloor(ctx: Ctx)
	local len = ctx.length
	ground(ctx, { Name = "Ground", Size = Vector3.new(ROAD_WIDTH, 2, len), CFrame = CF(ctx, 0, -1, len / 2), Color = THEME.Ground, Material = Enum.Material.Slate })
	for _, lane in LANE_IDS do
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "Rail", Size = Vector3.new(0.35, 0.3, len), CFrame = CF(ctx, LANES[lane] + side * 1.6, 0.15, len / 2), Color = THEME.Rail, Material = Enum.Material.Metal, CanCollide = false })
		end
	end
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "YardWall", Size = Vector3.new(2, 3.5, len), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 + 1), 1.75, len / 2), Color = THEME.Wall, Material = Enum.Material.Concrete })
		-- Wide dark ground beyond the walls
		scenery(ctx, { Name = "Outskirts", Size = Vector3.new(140, 2, len), CFrame = CF(ctx, side * (ROAD_WIDTH / 2 + 72), -1.2, len / 2), Color = Color3.fromRGB(40, 38, 46), Material = Enum.Material.Asphalt })
	end
end

-- A few big factory silhouettes and lamp posts, well away from the lanes.
local function yardScenery(ctx: Ctx)
	local rng = ctx.rng
	for _, side in { -1, 1 } do
		for d = 20, ctx.length, 60 do
			local pole = scenery(ctx, { Name = "LampPole", Size = Vector3.new(0.8, 14, 0.8), CFrame = CF(ctx, side * 18.5, 7, d), Color = Color3.fromRGB(45, 45, 55) })
			local lamp = scenery(ctx, { Parent = pole, Name = "Lamp", Size = Vector3.new(3, 0.6, 1.4), CFrame = CF(ctx, side * 17, 14, d), Color = THEME.Toxic, Material = Enum.Material.Neon, CanCollide = false })
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Range = 26
			light.Angle = 80
			light.Brightness = 1.5
			light.Color = THEME.Toxic
			light.Parent = lamp
		end
		if rng:NextNumber() < 0.7 then
			local h = rng:NextNumber(30, 70)
			local w = rng:NextNumber(30, 60)
			local factory = scenery(ctx, { Name = "Factory", Size = Vector3.new(w, h, rng:NextNumber(30, 60)), CFrame = CF(ctx, side * rng:NextNumber(60, 110), h / 2 - 1, rng:NextNumber(0, ctx.length)), Color = THEME.Silhouette })
			scenery(ctx, { Parent = factory, Name = "Windows", Size = Vector3.new(0.2, h * 0.15, w * 0.6), CFrame = factory.CFrame * CFrame.new(-side * (w / 2 + 0.1), h * 0.2, 0) * CFrame.Angles(0, math.rad(90), 0), Color = if rng:NextNumber() < 0.5 then THEME.Toxic else THEME.Evil, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
			if rng:NextNumber() < 0.5 then
				scenery(ctx, { Name = "Chimney", Size = Vector3.new(5, h * 0.6, 5), CFrame = factory.CFrame * CFrame.new(0, h * 0.75, 0), Color = THEME.Silhouette })
			end
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

-- Coins along the exact jump arc over a low obstacle at d, built from the
-- runner's jump physics so a jump sweeps straight through every coin.
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
	local board = solid(m, { Name = "Board", Size = Vector3.new(7, 7, 0.4), CFrame = CF(ctx, x, 3.4 + 3.5, d), Color = Color3.fromRGB(40, 140, 255) })
	local texts = { "VERITY\nINDUSTRIES", "⬇️ ROLL ⬇️", "NO\nESCAPE", "DUCK!", "RESTRICTED" }
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

-- A long subway car. Its roof is walkable (reach it with a ramp).
builders.TrainCar = function(ctx, lane, d)
	local m = obstacleModel(ctx, "TrainCar", lane)
	local x = LANES[lane]
	local len = 40
	local colors = { Color3.fromRGB(70, 60, 90), Color3.fromRGB(110, 40, 60), Color3.fromRGB(50, 80, 70) }
	solid(m, { Name = "Body", Size = Vector3.new(7, 9.8, len), CFrame = CF(ctx, x, 4.9, d + len / 2), Color = colors[ctx.rng:NextInteger(1, #colors)], Material = Enum.Material.Metal })
	ground(ctx, { Parent = m, Name = "Roof", Size = Vector3.new(7, 0.4, len), CFrame = CF(ctx, x, 10, d + len / 2), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.DiamondPlate })
	local front = scenery(ctx, { Parent = m, Name = "Front", Size = Vector3.new(6, 4, 0.2), CFrame = CF(ctx, x, 6, d - 0.1), Color = Color3.fromRGB(30, 30, 40), CanCollide = false })
	Util.SurfaceLabel(front, Enum.NormalId.Back, "☣️ VERITY CARGO", { PixelsPerStud = 15, TextColor = Color3.fromRGB(140, 255, 90) })
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

-- The bread and butter: open yard, barriers to jump, gantries to roll under.
define({
	name = "Yard",
	weight = 10,
	minDistance = 0,
	cooldown = 0,
	build = function(ctx)
		yardFloor(ctx)
		yardScenery(ctx)
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { Barricade = 4, OverheadSign = 3, Crates = 2, SteelBarrier = 1 })
		maybePickups(ctx)
	end,
})

-- Freight trains: switch lanes around them, or take the ramp and run the roofs.
define({
	name = "Trains",
	weight = 8,
	minDistance = 60,
	cooldown = 1,
	build = function(ctx)
		yardFloor(ctx)
		yardScenery(ctx)
		local rampLane = LANE_IDS[ctx.rng:NextInteger(1, 3)]
		ramp(ctx, rampLane, EDGE, 26)
		Segments.Obstacle(ctx, "TrainCar", rampLane, EDGE + 26)
		Segments.Obstacle(ctx, "TrainCar", rampLane, EDGE + 68)
		coinLine(ctx, rampLane, EDGE + 28, EDGE + 104, 10.2)
		local skip = { [rampLane] = true }
		for _, lane in LANE_IDS do
			if lane ~= rampLane and ctx.rng:NextNumber() < 0.55 then
				Segments.Obstacle(ctx, "TrainCar", lane, EDGE + ctx.rng:NextNumber(20, 55))
				skip[lane] = true
			end
		end
		obstacleRows(ctx, EDGE + 25, ctx.length - EDGE, { Barricade = 2, OverheadSign = 2 }, skip)
		maybePickups(ctx)
	end,
})

-- Through one of Verity's factory halls: pipes to roll under, steel to jump.
define({
	name = "Factory",
	weight = 4,
	minDistance = 250,
	cooldown = 2,
	build = function(ctx)
		yardFloor(ctx)
		for _, side in { -1, 1 } do
			scenery(ctx, { Name = "HallWall", Size = Vector3.new(3, 22, ctx.length), CFrame = CF(ctx, side * 16.5, 11, ctx.length / 2), Color = THEME.Silhouette, Material = Enum.Material.DiamondPlate })
			for d = 10, ctx.length - 10, 25 do
				scenery(ctx, { Name = "HallLight", Size = Vector3.new(0.3, 1.2, 6), CFrame = CF(ctx, side * 14.9, 15, d), Color = THEME.Evil, Material = Enum.Material.Neon, CanCollide = false })
			end
		end
		scenery(ctx, { Name = "HallRoof", Size = Vector3.new(36, 2, ctx.length), CFrame = CF(ctx, 0, 23, ctx.length / 2), Color = THEME.Silhouette })
		local sign = scenery(ctx, { Name = "HallSign", Size = Vector3.new(24, 4, 0.5), CFrame = CF(ctx, 0, 18.5, 2), Color = Color3.fromRGB(20, 15, 30) })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, ("☣️ %s INDUSTRIES ☣️"):format(Config.Villain.Title), { PixelsPerStud = 14, TextColor = THEME.Toxic })
		obstacleRows(ctx, EDGE + 12, ctx.length - EDGE, { SteelBarrier = 3, OverheadPipe = 3, Crates = 1 })
		maybePickups(ctx)
	end,
})

-- Smash zone: wooden walls to crash through at speed (or dodge).
define({
	name = "Smash",
	weight = 4,
	minDistance = 400,
	cooldown = 2,
	build = function(ctx)
		yardFloor(ctx)
		yardScenery(ctx)
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
		yardFloor(ctx)
		yardScenery(ctx)
		local vaultStart = EDGE + 20
		local vaultEnd = ctx.length - EDGE - 6
		local entrance = Segments.Obstacle(ctx, if ctx.rng:NextNumber() < 0.6 then "WoodWall" else "ConcreteWall", 0, vaultStart)
		entrance:SetAttribute("Vault", true)
		local sign = scenery(ctx, { Name = "VaultSign", Size = Vector3.new(7, 2.5, 0.3), CFrame = CF(ctx, 0, 13.5, vaultStart), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "💥 BONUS 💥", { PixelsPerStud = 20 })
		for _, side in { -1, 1 } do
			-- Lane 99: never "in front" of the runner, so touching it is always a side bump.
			local divider = obstacleModel(ctx, "VaultDivider", 99)
			divider:SetAttribute("ObstacleType", "Block")
			solid(divider, { Name = "Divider", Size = Vector3.new(0.8, 12, vaultEnd - vaultStart), CFrame = CF(ctx, side * 4, 6, (vaultStart + vaultEnd) / 2), Color = THEME.Wall, Material = Enum.Material.Concrete })
			Destruction.Setup(divider, 4)
		end
		coinLine(ctx, 0, vaultStart + 6, vaultEnd - 6)
		mysteryBox(ctx, 0, (vaultStart + vaultEnd) / 2)
		obstacleRows(ctx, vaultStart + 14, vaultEnd, { Barricade = 2, OverheadSign = 2, Crates = 1 }, { [0] = true })
		Segments.Obstacle(ctx, "Crates", if ctx.rng:NextNumber() < 0.5 then -1 else 1, vaultStart)
	end,
})

-- A caged Brainrot on the tracks: run through the cage to rescue it.
-- Rescued Brainrots go to your base and raise your score multiplier.
define({
	name = "Rescue",
	weight = 5,
	minDistance = 120,
	cooldown = 3,
	build = function(ctx)
		yardFloor(ctx)
		yardScenery(ctx)
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
			coinLine(ctx, lane, d - 32, d - 8)
			obstacleRows(ctx, d + 16, ctx.length - EDGE, { Barricade = 1, OverheadSign = 1 })
		end
	end,
})

Segments.Definitions = defs

-- The start: a clear stretch in front of Verity's factory gate, which the
-- villain bursts out of during the intro.
function Segments.BuildStartArea(ctx: Ctx)
	yardFloor(ctx)
	yardScenery(ctx)
	ground(ctx, { Name = "GroundBehind", Size = Vector3.new(ROAD_WIDTH, 2, 60), CFrame = CF(ctx, 0, -1, -30), Color = THEME.Ground, Material = Enum.Material.Slate })

	-- Factory gate behind the player
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "GateWall", Size = Vector3.new(4, 26, 30), CFrame = CF(ctx, side * 16, 13, -22), Color = THEME.Silhouette, Material = Enum.Material.DiamondPlate })
	end
	scenery(ctx, { Name = "GateRoof", Size = Vector3.new(36, 4, 30), CFrame = CF(ctx, 0, 27, -22), Color = THEME.Silhouette })
	local arch = scenery(ctx, { Name = "GateArch", Size = Vector3.new(36, 5, 3), CFrame = CF(ctx, 0, 27, -7), Color = THEME.Evil, Material = Enum.Material.Neon })
	Util.SurfaceLabel(arch, Enum.NormalId.Back, ("☣️ %s INDUSTRIES"):format(Config.Villain.Title), { PixelsPerStud = 12 })
	scenery(ctx, { Name = "GateDark", Size = Vector3.new(28, 22, 1), CFrame = CF(ctx, 0, 11, -36), Color = Color3.fromRGB(5, 5, 10), CanCollide = false })

	local banner = scenery(ctx, { Name = "StartBanner", Size = Vector3.new(30, 5, 0.5), CFrame = CF(ctx, 0, 19, 32), Color = Color3.fromRGB(20, 15, 30) })
	Util.SurfaceLabel(banner, Enum.NormalId.Back, ("RUN! %s IS COMING"):format(Config.Villain.Title), { PixelsPerStud = 12, TextColor = THEME.Toxic })
	for _, side in { -1, 1 } do
		scenery(ctx, { Name = "BannerPost", Size = Vector3.new(1, 21, 1), CFrame = CF(ctx, side * 15, 10.5, 32), Color = Color3.fromRGB(45, 45, 55) })
	end
	coinLine(ctx, 0, 40, ctx.length - 8)
end

return Segments
