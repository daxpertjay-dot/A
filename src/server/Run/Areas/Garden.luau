--!strict
-- 🌱 GROW A GARDEN — the first area (score 0 → 100,000). A dirt path through
-- studded grass, fenced garden beds full of crops, seed shop stands and
-- blocky trees. Obstacles are farm things: wooden fences to jump, hay bales
-- and barn walls to smash, hay wagons and greenhouses to boost onto.
--
-- These builders make the section templates (Workspace.TrackAreas.Garden);
-- the run is generated from those models, so edits made in Studio win.

local Kit = require(script.Parent.Kit)
local Destruction = require(script.Parent.Parent.Destruction)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local Garden = {}

local C = {
	Path = Color3.fromRGB(214, 178, 122),
	PathLine = Color3.fromRGB(192, 154, 100),
	Grass = Color3.fromRGB(96, 182, 66),
	Soil = Color3.fromRGB(112, 72, 44),
	Wood = Color3.fromRGB(200, 146, 88),
	WoodDark = Color3.fromRGB(142, 94, 54),
	Leaves = Color3.fromRGB(72, 164, 62),
	LeavesLight = Color3.fromRGB(110, 196, 78),
	Hay = Color3.fromRGB(234, 198, 96),
	HayDark = Color3.fromRGB(206, 166, 70),
	Barn = Color3.fromRGB(178, 54, 44),
	White = Color3.fromRGB(246, 246, 240),
	Glass = Color3.fromRGB(200, 236, 222),
	Shed = Color3.fromRGB(46, 34, 34),
}

local LANES = Kit.LANES
local LANE_IDS = Kit.LANE_IDS
local EDGE = Kit.EDGE
local HALF = Kit.ROAD_WIDTH / 2

local CROPS = {
	{ name = "Carrot", fruit = Color3.fromRGB(255, 140, 30) },
	{ name = "Tomato", fruit = Color3.fromRGB(230, 50, 40) },
	{ name = "Blueberry", fruit = Color3.fromRGB(70, 90, 230) },
	{ name = "Strawberry", fruit = Color3.fromRGB(240, 60, 90) },
	{ name = "Pumpkin", fruit = Color3.fromRGB(245, 150, 40) },
}

local SHOPS = {
	{ text = "SEED SHOP", stripe = Color3.fromRGB(70, 140, 235) },
	{ text = "GEAR SHOP", stripe = Color3.fromRGB(80, 190, 90) },
	{ text = "SELL STAND", stripe = Color3.fromRGB(240, 180, 40) },
}

-- ───────────────────────────── ground & scenery ─────────────────────────────

-- The path (three lanes), studded grass both sides and a low fence along it.
local function floor(ctx: Kit.Ctx, d0: number, d1: number)
	local len, mid = d1 - d0, (d0 + d1) / 2
	Kit.Ground(ctx, { Name = "Path", Size = Vector3.new(Kit.ROAD_WIDTH, 2, len), CFrame = Kit.CF(ctx, 0, -1, mid), Color = C.Path })
	for _, x in { -4, 4 } do
		Kit.Scenery(ctx, { Name = "LaneLine", Size = Vector3.new(0.5, 0.05, len), CFrame = Kit.CF(ctx, x, 0.02, mid), Color = C.PathLine, CastShadow = false })
	end
	for _, side in { -1, 1 } do
		Kit.Scenery(ctx, { Name = "Grass", Size = Vector3.new(400, 2, len), CFrame = Kit.CF(ctx, side * (HALF + 200), -1, mid), Color = C.Grass, Material = Enum.Material.Plastic, Studs = true })
		local x = side * (HALF + 1.5)
		for d = d0 + 5, d1, 10 do
			Kit.Scenery(ctx, { Name = "FencePost", Size = Vector3.new(0.8, 3.2, 0.8), CFrame = Kit.CF(ctx, x, 1.6, d), Color = C.WoodDark, Material = Enum.Material.Wood })
		end
		for _, y in { 1.2, 2.4 } do
			Kit.Scenery(ctx, { Name = "FenceRail", Size = Vector3.new(0.3, 0.5, len), CFrame = Kit.CF(ctx, x, y, mid), Color = C.Wood, Material = Enum.Material.Wood })
		end
	end
end

local function tree(ctx: Kit.Ctx, x: number, d: number)
	local h = ctx.rng:NextNumber(7, 10)
	Kit.Scenery(ctx, { Name = "Trunk", Size = Vector3.new(2, h, 2), CFrame = Kit.CF(ctx, x, h / 2, d), Color = C.WoodDark, Material = Enum.Material.Wood })
	Kit.Scenery(ctx, { Name = "Leaves", Size = Vector3.new(10, 7, 10), CFrame = Kit.CF(ctx, x, h + 2.5, d), Color = C.Leaves, Material = Enum.Material.Plastic, Studs = true })
	Kit.Scenery(ctx, { Name = "Leaves", Size = Vector3.new(6, 4, 6), CFrame = Kit.CF(ctx, x + 1, h + 7, d - 1), Color = C.LeavesLight, Material = Enum.Material.Plastic, Studs = true })
end

-- A fenced bed of brown soil with rows of one crop.
local function gardenBed(ctx: Kit.Ctx, side: number, d: number, depth: number)
	local x = side * (HALF + 17)
	local width = 18
	Kit.Scenery(ctx, { Name = "Soil", Size = Vector3.new(width, 1, depth), CFrame = Kit.CF(ctx, x, 0.5, d), Color = C.Soil, Material = Enum.Material.Plastic, Studs = true })
	for _, s in { -1, 1 } do
		Kit.Scenery(ctx, { Name = "BedRail", Size = Vector3.new(width + 1, 0.5, 0.3), CFrame = Kit.CF(ctx, x, 2, d + s * depth / 2), Color = C.Wood, Material = Enum.Material.Wood })
		Kit.Scenery(ctx, { Name = "BedRail", Size = Vector3.new(0.3, 0.5, depth), CFrame = Kit.CF(ctx, x + s * width / 2, 2, d), Color = C.Wood, Material = Enum.Material.Wood })
		for _, s2 in { -1, 1 } do
			Kit.Scenery(ctx, { Name = "BedPost", Size = Vector3.new(0.7, 2.6, 0.7), CFrame = Kit.CF(ctx, x + s * width / 2, 1.3, d + s2 * depth / 2), Color = C.WoodDark, Material = Enum.Material.Wood })
		end
	end
	local crop = CROPS[ctx.rng:NextInteger(1, #CROPS)]
	for row = -depth / 2 + 4, depth / 2 - 3, 6 do
		for _, cx in { -4.5, 4.5 } do
			Kit.Scenery(ctx, { Name = crop.name .. "Leaves", Size = Vector3.new(2, 1.6, 2), CFrame = Kit.CF(ctx, x + cx, 1.8, d + row), Color = C.LeavesLight })
			Kit.Scenery(ctx, { Name = crop.name, Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = Kit.CF(ctx, x + cx, 2.9, d + row), Color = crop.fruit })
		end
	end
end

-- A market stand with a striped awning (like the shops in Grow a Garden).
local function shopStand(ctx: Kit.Ctx, side: number, d: number, shop: { text: string, stripe: Color3 })
	local x = side * (HALF + 13)
	Kit.Scenery(ctx, { Name = "Counter", Size = Vector3.new(5, 3.5, 14), CFrame = Kit.CF(ctx, x, 1.75, d), Color = C.Wood, Material = Enum.Material.WoodPlanks })
	for _, sx in { -2.5, 2.5 } do
		for _, sd in { -6.5, 6.5 } do
			Kit.Scenery(ctx, { Name = "StandPost", Size = Vector3.new(0.6, 9, 0.6), CFrame = Kit.CF(ctx, x + sx, 4.5, d + sd), Color = C.WoodDark, Material = Enum.Material.Wood })
		end
	end
	for i = 0, 6 do
		Kit.Scenery(ctx, {
			Name = "Awning",
			Size = Vector3.new(7, 0.4, 2),
			CFrame = Kit.CF(ctx, x - side * 0.5, 9.2, d - 6 + i * 2) * CFrame.Angles(0, 0, math.rad(side * 12)),
			Color = if i % 2 == 0 then shop.stripe else C.White,
		})
	end
	local sign = Kit.Scenery(ctx, { Name = "ShopSign", Size = Vector3.new(0.6, 2.6, 13), CFrame = Kit.CF(ctx, x - side * 3.2, 11.2, d), Color = C.Wood, Material = Enum.Material.WoodPlanks })
	Util.SurfaceLabel(sign, if side < 0 then Enum.NormalId.Right else Enum.NormalId.Left, shop.text, { PixelsPerStud = 14, TextColor = Color3.fromRGB(255, 255, 255) })
	for i, color in { Color3.fromRGB(240, 90, 90), Color3.fromRGB(250, 210, 70), Color3.fromRGB(120, 200, 255) } do
		Kit.Scenery(ctx, { Name = "SeedPack", Size = Vector3.new(1.2, 1.6, 1), CFrame = Kit.CF(ctx, x, 4.3, d - 6 + i * 3), Color = color })
	end
end

-- Beds, trees or nothing in chunks down both sides (kept light on purpose).
local function sideDecor(ctx: Kit.Ctx, d0: number, d1: number, skip: { [number]: boolean }?)
	local rng = ctx.rng
	for _, side in { -1, 1 } do
		if not (skip and skip[side]) then
			local d = d0 + 4
			while d + 30 <= d1 do
				local roll = rng:NextNumber()
				if roll < 0.45 then
					gardenBed(ctx, side, d + 15, 28)
				elseif roll < 0.8 then
					tree(ctx, side * rng:NextNumber(HALF + 34, HALF + 50), d + rng:NextNumber(5, 25))
				end
				d += 36
			end
		end
	end
end

-- ───────────────────────────── obstacles ─────────────────────────────

local defs: { [string]: Kit.ObstacleDef } = {}

-- A wooden fence across the lane: jump it (or smash through).
defs.Fence = {
	type = "Jump",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "Fence", "Jump", lane)
		local x = LANES[lane]
		for _, px in { -3.2, 0, 3.2 } do
			Kit.Solid(m, { Name = "Post", Size = Vector3.new(0.8, 3.4, 0.8), CFrame = Kit.CF(ctx, x + px, 1.7, d), Color = C.WoodDark, Material = Enum.Material.Wood })
		end
		for _, y in { 1.2, 2.5 } do
			Kit.Solid(m, { Name = "Rail", Size = Vector3.new(7.4, 0.6, 0.4), CFrame = Kit.CF(ctx, x, y, d), Color = C.Wood, Material = Enum.Material.Wood })
		end
		Destruction.Setup(m, 1, "Shatter", "Wood")
		return m
	end,
}

-- A raised bed of crops in the path: jump it.
defs.PlanterBox = {
	type = "Jump",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "PlanterBox", "Jump", lane)
		local x = LANES[lane]
		Kit.Solid(m, { Name = "Box", Size = Vector3.new(7, 2.2, 5), CFrame = Kit.CF(ctx, x, 1.1, d + 2.5), Color = C.Wood, Material = Enum.Material.WoodPlanks })
		Kit.Scenery(ctx, { Parent = m, Name = "Soil", Size = Vector3.new(6.4, 0.2, 4.4), CFrame = Kit.CF(ctx, x, 2.25, d + 2.5), Color = C.Soil })
		local crop = CROPS[ctx.rng:NextInteger(1, #CROPS)]
		for _, cx in { -2, 0, 2 } do
			Kit.Scenery(ctx, { Parent = m, Name = crop.name, Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = Kit.CF(ctx, x + cx, 2.9, d + 2.5), Color = crop.fruit })
		end
		Destruction.Setup(m, 1, "Shatter", "Wood")
		return m
	end,
}

-- Stacked hay bales: smash straight through them.
defs.HayBales = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "HayBales", "Block", lane)
		local x = LANES[lane]
		for i = 0, 2 do
			for _, j in { -1, 1 } do
				if i < 2 or j == 1 then
					Kit.Solid(m, {
						Name = "Bale",
						Size = Vector3.new(3.4, 2.8, 4),
						CFrame = Kit.CF(ctx, x + j * 1.8, 1.4 + i * 2.8, d + 2) * CFrame.Angles(0, math.rad(ctx.rng:NextNumber(-8, 8)), 0),
						Color = if (i + j) % 2 == 0 then C.Hay else C.HayDark,
						Material = Enum.Material.Fabric,
					})
				end
			end
		end
		Destruction.Setup(m, 1, "Shatter", "Wood")
		return m
	end,
}

-- A red barn wall: crash through it at speed (or hop it with a boost).
defs.BarnWall = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "BarnWall", "Block", lane)
		local wall = Destruction.BrickWall(m, Kit.CF(ctx, LANES[lane], 6, d), Vector3.new(7.6, 12, 1.4), Vector3.new(1.9, 2, 1.4), C.Barn, Enum.Material.WoodPlanks)
		for _, p in wall:GetChildren() do
			(p :: BasePart).CollisionGroup = "RunObstacle"
		end
		Destruction.Setup(m, 2, "Bricks", "WoodPlanks")
		return m
	end,
}

-- A hay wagon: too tall to jump normally. Go round it, or boost-jump onto the
-- hay and run along the top.
defs.HayWagon = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "HayWagon", "Block", lane)
		local x, L, H = LANES[lane], Kit.TALL_LENGTH, Kit.TALL_HEIGHT
		local mid = d + L / 2
		Kit.Solid(m, { Name = "Bed", Size = Vector3.new(7, 4, L), CFrame = Kit.CF(ctx, x, 3, mid), Color = C.Barn, Material = Enum.Material.WoodPlanks })
		Kit.Solid(m, { Name = "Hay", Size = Vector3.new(6.6, H - 5, L - 1), CFrame = Kit.CF(ctx, x, 5 + (H - 5) / 2, mid), Color = C.Hay, Material = Enum.Material.Fabric })
		Kit.Ground(ctx, { Parent = m, Name = "HayTop", Size = Vector3.new(7, 0.5, L), CFrame = Kit.CF(ctx, x, H + 0.25, mid), Color = C.Hay, Material = Enum.Material.Fabric })
		for _, side in { -1, 1 } do
			for _, wd in { 6, L - 6 } do
				Kit.Scenery(ctx, { Parent = m, Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.6, 3.6), CFrame = Kit.CF(ctx, x + side * 3.7, 1.8, d + wd), Color = C.WoodDark, Material = Enum.Material.Wood })
			end
		end
		Destruction.Setup(m, 4)
		return m
	end,
}

local LOW = { Fence = 4, PlanterBox = 2, HayBales = 2 }

-- ───────────────────────────── sections ─────────────────────────────

local function laneOf(ctx: Kit.Ctx): number
	return LANE_IDS[ctx.rng:NextInteger(1, 3)]
end

-- Tall wagons in a lane (sometimes two in a row), with a coin line on top.
local function wagons(ctx: Kit.Ctx)
	local rng = ctx.rng
	local start = EDGE + 24
	local roofLane = laneOf(ctx)
	defs.HayWagon.build(ctx, roofLane, start)
	local convoy = rng:NextNumber() < 0.5
	if convoy then
		defs.HayWagon.build(ctx, roofLane, start + Kit.TALL_LENGTH + 6)
	end
	local roofEnd = start + (if convoy then Kit.TALL_LENGTH * 2 + 6 else Kit.TALL_LENGTH) - 4
	Kit.CoinLine(ctx, roofLane, start + 4, roofEnd, Kit.TALL_HEIGHT + 0.5)
	Kit.PickupSpot(ctx, roofLane, roofEnd - 6, "MysteryBox", Kit.TALL_HEIGHT + 0.5, 0.3)
	local skip = { [roofLane] = true }
	if ctx.difficulty > 0 and rng:NextNumber() < 0.4 then
		-- One more wagon at most, so there's always a lane on the path.
		local other = LANE_IDS[rng:NextInteger(1, 3)]
		if other ~= roofLane then
			defs.HayWagon.build(ctx, other, start + rng:NextNumber(0, 30))
			skip[other] = true
		end
	end
	Kit.Rows(ctx, start + 12, ctx.length - EDGE, { Fence = 2, PlanterBox = 1 }, defs, skip)
	Kit.PickupSpot(ctx, roofLane, EDGE * 0.5, "SuperSneakers")
end

-- A greenhouse over the path. Run through it, or boost onto the glass roof.
local GH_START, GH_LENGTH = 40, 66
local function greenhouse(ctx: Kit.Ctx)
	local d0, d1 = GH_START, GH_START + GH_LENGTH
	Kit.Tunnel(ctx, d0, GH_LENGTH, { Color = C.Glass, Material = Enum.Material.Glass, Transparency = 0.45 }, { Color = C.Glass, Material = Enum.Material.Glass, Transparency = 0.3 })
	local wallX = (Kit.ROAD_WIDTH + 4) / 2 + 1
	for d = d0, d1, 11 do
		for _, side in { -1, 1 } do
			Kit.Scenery(ctx, { Name = "Frame", Size = Vector3.new(2.4, Kit.TUNNEL_ROOF + 0.4, 0.6), CFrame = Kit.CF(ctx, side * wallX, (Kit.TUNNEL_ROOF + 0.4) / 2, d), Color = C.White })
			if d < d1 then
				Kit.Scenery(ctx, { Name = "Pot", Size = Vector3.new(2, 1.6, 2), CFrame = Kit.CF(ctx, side * (wallX - 2.4), 0.8, d + 5.5), Color = Color3.fromRGB(200, 110, 70) })
				Kit.Scenery(ctx, { Name = "Plant", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = Kit.CF(ctx, side * (wallX - 2.4), 2.6, d + 5.5), Color = C.LeavesLight })
			end
		end
		Kit.Scenery(ctx, { Name = "RoofFrame", Size = Vector3.new(Kit.ROAD_WIDTH + 8, 0.1, 0.6), CFrame = Kit.CF(ctx, 0, Kit.TUNNEL_ROOF + 0.05, d), Color = C.White, CastShadow = false })
	end
	local sign = Kit.Scenery(ctx, { Name = "GreenhouseSign", Size = Vector3.new(24, 3.5, 0.6), CFrame = Kit.CF(ctx, 0, Kit.TUNNEL_ROOF + 8, d0), Color = C.Wood, Material = Enum.Material.WoodPlanks })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, "🌿 GREENHOUSE", { PixelsPerStud = 12 })
	for _, side in { -1, 1 } do
		Kit.Scenery(ctx, { Name = "SignPost", Size = Vector3.new(0.8, 10, 0.8), CFrame = Kit.CF(ctx, side * 10, Kit.TUNNEL_ROOF + 5, d0), Color = C.WoodDark })
	end
	Kit.SideSign(ctx, d0 - 26, "👟🛹 BOOST ONTO THE ROOF!", Color3.fromRGB(255, 205, 40), Color3.fromRGB(30, 20, 10))
	local roofLane = laneOf(ctx)
	Kit.CoinLine(ctx, roofLane, d0 + 4, d1 - 4, Kit.TUNNEL_ROOF)
	Kit.PickupSpot(ctx, laneOf(ctx), d1 - 12, "MysteryBox", Kit.TUNNEL_ROOF, 0.4)
	Kit.Rows(ctx, d0 + 10, d1 - 6, LOW, defs)
	Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5, "SuperSneakers")
end

-- The big red barn beside the path, and walls to smash through.
local function barn(ctx: Kit.Ctx)
	local side = if ctx.rng:NextNumber() < 0.5 then -1 else 1
	local x, d = side * (HALF + 24), 60
	Kit.Scenery(ctx, { Name = "Barn", Size = Vector3.new(30, 20, 44), CFrame = Kit.CF(ctx, x, 10, d), Color = C.Barn, Material = Enum.Material.WoodPlanks })
	for _, s in { -1, 1 } do
		Kit.Scenery(ctx, {
			Name = "BarnRoof",
			Class = "WedgePart",
			Size = Vector3.new(44, 9, 16),
			CFrame = Kit.CF(ctx, x + s * 8, 24.5, d) * CFrame.Angles(0, math.rad(-90 * s), 0),
			Color = Color3.fromRGB(90, 70, 60),
		})
	end
	local door = Kit.Scenery(ctx, { Name = "BarnDoor", Size = Vector3.new(0.4, 14, 16), CFrame = Kit.CF(ctx, x - side * 15.1, 7, d), Color = C.Barn, Material = Enum.Material.WoodPlanks })
	for _, a in { 1, -1 } do
		Kit.Scenery(ctx, { Parent = door, Name = "DoorTrim", Size = Vector3.new(0.5, 0.8, 21), CFrame = Kit.CF(ctx, x - side * 15.2, 7, d) * CFrame.Angles(math.atan2(14, 16) * a, 0, 0), Color = C.White })
	end
	sideDecor(ctx, 0, ctx.length, { [side] = true })
	Kit.Rows(ctx, EDGE + 12, ctx.length - EDGE, { BarnWall = 4, HayBales = 2, Fence = 2 }, defs)
	Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5)
end

local specs: { Kit.SectionSpec } = {
	{
		-- The run starts here, in front of Verity's shed. He bursts out of the
		-- ground behind you during the intro.
		kind = "Start",
		weight = 0,
		length = Config.Run.StartAreaLength,
		difficulties = { 0 },
		variants = 1,
		build = function(ctx)
			floor(ctx, -60, ctx.length)
			local shed = Kit.Scenery(ctx, { Name = "VerityShed", Size = Vector3.new(60, 30, 28), CFrame = Kit.CF(ctx, 0, 15, -34), Color = C.Shed, Material = Enum.Material.WoodPlanks })
			Kit.Scenery(ctx, { Parent = shed, Name = "ShedDoor", Size = Vector3.new(24, 15, 0.4), CFrame = Kit.CF(ctx, 0, 7.5, -19.9), Color = Color3.fromRGB(10, 6, 6) })
			for _, s in { -1, 1 } do
				Kit.Scenery(ctx, { Parent = shed, Name = "ShedRoof", Class = "WedgePart", Size = Vector3.new(28, 8, 31), CFrame = Kit.CF(ctx, s * 15.5, 34, -34) * CFrame.Angles(0, math.rad(-90 * s), 0), Color = Color3.fromRGB(70, 20, 20) })
			end
			local sign = Kit.Scenery(ctx, { Parent = shed, Name = "ShedSign", Size = Vector3.new(30, 4.5, 0.4), CFrame = Kit.CF(ctx, 0, 21, -19.8), Color = Color3.fromRGB(255, 214, 40) })
			Util.SurfaceLabel(sign, Enum.NormalId.Back, ("😁 %s'S SHED"):format(Config.Villain.Title), { PixelsPerStud = 12, TextColor = Color3.fromRGB(20, 10, 10), Stroke = false })
			local banner = Kit.Scenery(ctx, { Name = "StartBanner", Size = Vector3.new(30, 5, 0.5), CFrame = Kit.CF(ctx, 0, 19, 32), Color = Color3.fromRGB(35, 20, 20) })
			Util.SurfaceLabel(banner, Enum.NormalId.Back, ("RUN! %s IS COMING"):format(Config.Villain.Title), { PixelsPerStud = 12, TextColor = Color3.fromRGB(255, 214, 40) })
			for _, side in { -1, 1 } do
				Kit.Scenery(ctx, { Name = "BannerPost", Size = Vector3.new(1, 21, 1), CFrame = Kit.CF(ctx, side * 15, 10.5, 32), Color = C.WoodDark })
			end
			sideDecor(ctx, 0, ctx.length)
			Kit.CoinLine(ctx, 0, 40, ctx.length - 8)
		end,
	},
	{
		-- The entrance to the garden (the first section of the area).
		kind = "Gate",
		weight = 0,
		difficulties = { 0 },
		variants = 1,
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			Kit.Arch(ctx, 24, "🌱 GROW A GARDEN", Color3.fromRGB(90, 190, 70), C.WoodDark)
			sideDecor(ctx, 0, ctx.length)
			Kit.CoinLine(ctx, 0, 10, 50)
			Kit.Rows(ctx, 70, ctx.length - EDGE, { Fence = 1 }, defs)
		end,
	},
	{
		kind = "Fences",
		weight = 10,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, ctx.length)
			Kit.Rows(ctx, EDGE + 12, ctx.length - EDGE, LOW, defs)
			Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5)
		end,
	},
	{
		kind = "Shop",
		weight = 5,
		cooldown = 2,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			local side = if ctx.rng:NextNumber() < 0.5 then -1 else 1
			shopStand(ctx, side, 50, SHOPS[ctx.rng:NextInteger(1, #SHOPS)])
			tree(ctx, side * (HALF + 40), 20)
			sideDecor(ctx, 0, ctx.length, { [side] = true })
			Kit.Rows(ctx, EDGE + 12, ctx.length - EDGE, { Fence = 3, HayBales = 1 }, defs)
			Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5)
		end,
	},
	{
		kind = "HayWagons",
		weight = 7,
		cooldown = 1,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, ctx.length)
			wagons(ctx)
		end,
	},
	{
		kind = "Greenhouse",
		weight = 4,
		cooldown = 2,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, GH_START - 4)
			sideDecor(ctx, GH_START + GH_LENGTH + 4, ctx.length)
			greenhouse(ctx)
		end,
	},
	{
		kind = "Barn",
		weight = 4,
		cooldown = 2,
		difficulties = { 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			barn(ctx)
		end,
	},
	{
		-- A caged Brainrot from this area: run through the cage to rescue it.
		kind = "Rescue",
		weight = 5,
		cooldown = 3,
		difficulties = { 0 },
		variants = 3,
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, ctx.length)
			local lane = laneOf(ctx)
			local d = ctx.length / 2
			Kit.CageSpot(ctx, lane, d)
			Kit.CoinLine(ctx, lane, d - 32, d - 8)
			Kit.Rows(ctx, d + 16, ctx.length - EDGE, { Fence = 1 }, defs)
		end,
	},
}

function Garden.Build(parent: Instance, origin: Vector3): Folder
	return Kit.BuildArea(parent, "Garden", origin, specs, 1001)
end

return Garden
