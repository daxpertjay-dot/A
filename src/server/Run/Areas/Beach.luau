--!strict
-- 🌊 TSUNAMI BEACH — the second area (score 100,000 →), inspired by Escape
-- Tsunamis for Brainrots. A sandy path along the shore: the sea and a huge
-- wave on one side, palms and beach huts on the other. Sand castles and
-- driftwood to jump, tiki walls to smash, surf shacks and the pier to boost
-- onto.
--
-- These builders make the section templates (Workspace.TrackAreas.Beach);
-- the run is generated from those models, so edits made in Studio win.

local Kit = require(script.Parent.Kit)
local Destruction = require(script.Parent.Parent.Destruction)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = require(Shared.Util)

local Beach = {}

local C = {
	Sand = Color3.fromRGB(240, 214, 150),
	SandDark = Color3.fromRGB(220, 190, 124),
	WetSand = Color3.fromRGB(200, 172, 116),
	Sea = Color3.fromRGB(40, 160, 230),
	SeaLight = Color3.fromRGB(110, 210, 245),
	Foam = Color3.fromRGB(240, 250, 255),
	Wood = Color3.fromRGB(176, 124, 76),
	WoodDark = Color3.fromRGB(120, 82, 50),
	Bamboo = Color3.fromRGB(200, 170, 90),
	Palm = Color3.fromRGB(150, 110, 70),
	PalmLeaves = Color3.fromRGB(60, 170, 80),
	Thatch = Color3.fromRGB(205, 165, 90),
}

local HUT_COLORS = { Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 210, 90), Color3.fromRGB(140, 230, 160) }
local UMBRELLAS = { Color3.fromRGB(240, 70, 70), Color3.fromRGB(60, 140, 240), Color3.fromRGB(250, 200, 50), Color3.fromRGB(240, 120, 200) }

local LANES = Kit.LANES
local LANE_IDS = Kit.LANE_IDS
local EDGE = Kit.EDGE
local HALF = Kit.ROAD_WIDTH / 2
local SEA_SIDE = 1 -- the sea is on the right

-- ───────────────────────────── ground & scenery ─────────────────────────────

-- The sandy path, the beach and the sea (with the tsunami far out).
local function floor(ctx: Kit.Ctx, d0: number, d1: number)
	local len, mid = d1 - d0, (d0 + d1) / 2
	Kit.Ground(ctx, { Name = "Path", Size = Vector3.new(Kit.ROAD_WIDTH, 2, len), CFrame = Kit.CF(ctx, 0, -1, mid), Color = C.SandDark, Material = Enum.Material.Sand })
	for _, x in { -4, 4 } do
		Kit.Scenery(ctx, { Name = "LaneLine", Size = Vector3.new(0.5, 0.05, len), CFrame = Kit.CF(ctx, x, 0.02, mid), Color = C.WetSand, CastShadow = false })
	end
	-- Rope posts along both edges of the path.
	for _, side in { -1, 1 } do
		local x = side * (HALF + 1)
		for d = d0 + 5, d1, 12 do
			Kit.Scenery(ctx, { Name = "RopePost", Size = Vector3.new(0.8, 2.6, 0.8), CFrame = Kit.CF(ctx, x, 1.3, d), Color = C.WoodDark, Material = Enum.Material.Wood })
		end
		Kit.Scenery(ctx, { Name = "Rope", Size = Vector3.new(0.25, 0.25, len), CFrame = Kit.CF(ctx, x, 2.2, mid), Color = Color3.fromRGB(230, 220, 190) })
	end
	-- Land side: dry sand. Sea side: a strip of beach, wet sand, then the sea.
	Kit.Scenery(ctx, { Name = "Beach", Size = Vector3.new(400, 2, len), CFrame = Kit.CF(ctx, -SEA_SIDE * (HALF + 200), -1, mid), Color = C.Sand, Material = Enum.Material.Plastic, Studs = true })
	Kit.Scenery(ctx, { Name = "Beach", Size = Vector3.new(14, 2, len), CFrame = Kit.CF(ctx, SEA_SIDE * (HALF + 7), -1, mid), Color = C.Sand, Material = Enum.Material.Plastic, Studs = true })
	Kit.Scenery(ctx, { Name = "WetSand", Size = Vector3.new(8, 2, len), CFrame = Kit.CF(ctx, SEA_SIDE * (HALF + 18), -1.2, mid), Color = C.WetSand, Material = Enum.Material.Plastic })
	Kit.Scenery(ctx, { Name = "Foam", Size = Vector3.new(2, 1, len), CFrame = Kit.CF(ctx, SEA_SIDE * (HALF + 23), -0.9, mid), Color = C.Foam })
	Kit.Scenery(ctx, { Name = "Sea", Size = Vector3.new(400, 1, len), CFrame = Kit.CF(ctx, SEA_SIDE * (HALF + 24 + 200), -1.4, mid), Color = C.Sea, Material = Enum.Material.Glass, Transparency = 0.15 })
	-- The tsunami, far out at sea.
	Kit.Scenery(ctx, { Name = "Tsunami", Class = "WedgePart", Size = Vector3.new(len, 70, 60), CFrame = Kit.CF(ctx, SEA_SIDE * 230, 34, mid) * CFrame.Angles(0, math.rad(-90 * SEA_SIDE), 0), Color = C.SeaLight, CastShadow = false })
	Kit.Scenery(ctx, { Name = "WaveCrest", Size = Vector3.new(14, 6, len), CFrame = Kit.CF(ctx, SEA_SIDE * 204, 69, mid), Color = C.Foam, CastShadow = false })
end

local function palm(ctx: Kit.Ctx, x: number, d: number)
	local h = ctx.rng:NextNumber(12, 17)
	local lean = math.rad(ctx.rng:NextNumber(-10, 10))
	local trunk = CFrame.new(Kit.W(ctx, x, 0, d)) * CFrame.Angles(0, 0, lean)
	Kit.Scenery(ctx, { Name = "PalmTrunk", Size = Vector3.new(1.6, h, 1.6), CFrame = trunk * CFrame.new(0, h / 2, 0), Color = C.Palm, Material = Enum.Material.Wood })
	local top = trunk * CFrame.new(0, h, 0)
	for i = 0, 3 do
		Kit.Scenery(ctx, { Name = "PalmLeaf", Size = Vector3.new(9, 0.5, 2.6), CFrame = top * CFrame.Angles(0, math.rad(i * 90 + 45), math.rad(-18)) * CFrame.new(4, 0, 0), Color = C.PalmLeaves })
	end
end

local function umbrella(ctx: Kit.Ctx, x: number, d: number)
	local color = UMBRELLAS[ctx.rng:NextInteger(1, #UMBRELLAS)]
	Kit.Scenery(ctx, { Name = "UmbrellaPole", Size = Vector3.new(0.4, 7, 0.4), CFrame = Kit.CF(ctx, x, 3.5, d), Color = Color3.fromRGB(240, 240, 240) })
	Kit.Scenery(ctx, { Name = "Umbrella", Size = Vector3.new(8, 0.6, 8), CFrame = Kit.CF(ctx, x, 7, d) * CFrame.Angles(0, math.rad(45), 0), Color = color })
	Kit.Scenery(ctx, { Name = "Towel", Size = Vector3.new(3, 0.1, 6), CFrame = Kit.CF(ctx, x + 3, 0.05, d + 1), Color = UMBRELLAS[ctx.rng:NextInteger(1, #UMBRELLAS)] })
end

local function beachHut(ctx: Kit.Ctx, x: number, d: number)
	local color = HUT_COLORS[ctx.rng:NextInteger(1, #HUT_COLORS)]
	Kit.Scenery(ctx, { Name = "Hut", Size = Vector3.new(10, 9, 10), CFrame = Kit.CF(ctx, x, 5.5, d), Color = color, Material = Enum.Material.WoodPlanks })
	Kit.Scenery(ctx, { Name = "HutStilts", Size = Vector3.new(9, 1, 9), CFrame = Kit.CF(ctx, x, 0.5, d), Color = C.WoodDark, Material = Enum.Material.Wood })
	Kit.Scenery(ctx, { Name = "HutRoof", Size = Vector3.new(12, 1.4, 12), CFrame = Kit.CF(ctx, x, 10.7, d), Color = C.Thatch, Material = Enum.Material.Fabric })
	Kit.Scenery(ctx, { Name = "HutDoor", Size = Vector3.new(0.3, 5, 3), CFrame = Kit.CF(ctx, x + (if x < 0 then 5 else -5), 3.5, d), Color = C.WoodDark })
end

-- Palms, umbrellas and huts on the land side; the odd palm by the sea.
local function sideDecor(ctx: Kit.Ctx, d0: number, d1: number, skipLand: boolean?)
	local rng = ctx.rng
	local d = d0 + 4
	while d + 30 <= d1 do
		if not skipLand then
			local roll = rng:NextNumber()
			local x = -SEA_SIDE * rng:NextNumber(HALF + 10, HALF + 26)
			if roll < 0.35 then
				umbrella(ctx, x, d + rng:NextNumber(5, 25))
			elseif roll < 0.6 then
				beachHut(ctx, -SEA_SIDE * (HALF + 30), d + 15)
			elseif roll < 0.9 then
				palm(ctx, x, d + rng:NextNumber(5, 25))
			end
		end
		if rng:NextNumber() < 0.3 then
			palm(ctx, SEA_SIDE * (HALF + 8), d + rng:NextNumber(5, 25))
		end
		d += 36
	end
end

-- ───────────────────────────── obstacles ─────────────────────────────

local defs: { [string]: Kit.ObstacleDef } = {}

-- A sand castle: jump it, or smash it to bits.
defs.SandCastle = {
	type = "Jump",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "SandCastle", "Jump", lane)
		local x = LANES[lane]
		Kit.Solid(m, { Name = "Wall", Size = Vector3.new(7, 2, 3), CFrame = Kit.CF(ctx, x, 1, d + 1.5), Color = C.Sand, Material = Enum.Material.Sand })
		for _, tx in { -2.6, 2.6 } do
			Kit.Solid(m, { Name = "Tower", Size = Vector3.new(1.8, 3.2, 1.8), CFrame = Kit.CF(ctx, x + tx, 1.6, d + 1.5), Color = C.SandDark, Material = Enum.Material.Sand })
		end
		Kit.Scenery(ctx, { Parent = m, Name = "Flag", Size = Vector3.new(0.1, 0.8, 1.2), CFrame = Kit.CF(ctx, x + 2.6, 3.8, d + 1.5), Color = Color3.fromRGB(240, 70, 70) })
		Destruction.Setup(m, 1, "Shatter", "Sand")
		return m
	end,
}

-- A driftwood log across the lane: unbreakable, jump it.
defs.Driftwood = {
	type = "Jump",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "Driftwood", "Jump", lane)
		Kit.Solid(m, { Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.6, 2.6, 2.6), CFrame = Kit.CF(ctx, LANES[lane], 1.3, d + 1.3), Color = Color3.fromRGB(150, 120, 90), Material = Enum.Material.Wood })
		Destruction.Setup(m, 4)
		return m
	end,
}

-- Beach coolers and crates: smash through them.
defs.Coolers = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "Coolers", "Block", lane)
		local x = LANES[lane]
		local colors = { Color3.fromRGB(60, 140, 240), Color3.fromRGB(240, 70, 70), C.Wood }
		for i = 0, 2 do
			for _, j in { -1, 1 } do
				if i < 2 or j == -1 then
					Kit.Solid(m, {
						Name = "Box",
						Size = Vector3.new(3.2, 2.8, 3.2),
						CFrame = Kit.CF(ctx, x + j * 1.7, 1.4 + i * 2.8, d + 1.6) * CFrame.Angles(0, math.rad(ctx.rng:NextNumber(-10, 10)), 0),
						Color = colors[ctx.rng:NextInteger(1, #colors)],
					})
				end
			end
		end
		Destruction.Setup(m, 1, "Shatter", "Wood")
		return m
	end,
}

-- A bamboo tiki wall: crash through it at speed.
defs.TikiWall = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "TikiWall", "Block", lane)
		local wall = Destruction.BrickWall(m, Kit.CF(ctx, LANES[lane], 6, d), Vector3.new(7.6, 12, 1.4), Vector3.new(1.25, 3, 1.4), C.Bamboo, Enum.Material.Wood)
		for _, p in wall:GetChildren() do
			(p :: BasePart).CollisionGroup = "RunObstacle"
		end
		Destruction.Setup(m, 2, "Bricks", "Wood")
		return m
	end,
}

-- A surf shack on wheels: too tall to jump normally. Go round it, or
-- boost-jump onto the roof.
defs.SurfShack = {
	type = "Block",
	build = function(ctx, lane, d)
		local m = Kit.Obstacle(ctx, "SurfShack", "Block", lane)
		local x, L, H = LANES[lane], Kit.TALL_LENGTH, Kit.TALL_HEIGHT
		local mid = d + L / 2
		local color = HUT_COLORS[ctx.rng:NextInteger(1, #HUT_COLORS)]
		Kit.Solid(m, { Name = "Body", Size = Vector3.new(7, H - 1, L), CFrame = Kit.CF(ctx, x, 1 + (H - 1) / 2, mid), Color = color, Material = Enum.Material.WoodPlanks })
		Kit.Ground(ctx, { Parent = m, Name = "ShackRoof", Size = Vector3.new(7.4, 0.5, L), CFrame = Kit.CF(ctx, x, H + 0.25, mid), Color = C.Thatch, Material = Enum.Material.Fabric })
		local sign = Kit.Scenery(ctx, { Parent = m, Name = "Front", Size = Vector3.new(6.4, 2, 0.2), CFrame = Kit.CF(ctx, x, 9.5, d - 0.1), Color = Color3.fromRGB(30, 60, 90) })
		Util.SurfaceLabel(sign, Enum.NormalId.Back, "🏄 SURF", { PixelsPerStud = 15 })
		for _, side in { -1, 1 } do
			Kit.Scenery(ctx, { Parent = m, Name = "Surfboard", Size = Vector3.new(0.3, 8, 2), CFrame = Kit.CF(ctx, x + side * 3.7, 5.5, mid + side * 8) * CFrame.Angles(math.rad(8), 0, 0), Color = UMBRELLAS[ctx.rng:NextInteger(1, #UMBRELLAS)] })
		end
		Destruction.Setup(m, 4)
		return m
	end,
}

local LOW = { SandCastle = 4, Driftwood = 2, Coolers = 2 }

-- ───────────────────────────── sections ─────────────────────────────

local function laneOf(ctx: Kit.Ctx): number
	return LANE_IDS[ctx.rng:NextInteger(1, 3)]
end

local function shacks(ctx: Kit.Ctx)
	local rng = ctx.rng
	local start = EDGE + 24
	local roofLane = laneOf(ctx)
	defs.SurfShack.build(ctx, roofLane, start)
	local convoy = rng:NextNumber() < 0.5
	if convoy then
		defs.SurfShack.build(ctx, roofLane, start + Kit.TALL_LENGTH + 6)
	end
	local roofEnd = start + (if convoy then Kit.TALL_LENGTH * 2 + 6 else Kit.TALL_LENGTH) - 4
	Kit.CoinLine(ctx, roofLane, start + 4, roofEnd, Kit.TALL_HEIGHT + 0.5)
	Kit.PickupSpot(ctx, roofLane, roofEnd - 6, "MysteryBox", Kit.TALL_HEIGHT + 0.5, 0.3)
	local skip = { [roofLane] = true }
	if ctx.difficulty > 0 and rng:NextNumber() < 0.5 then
		local other = LANE_IDS[rng:NextInteger(1, 3)]
		if other ~= roofLane then
			defs.SurfShack.build(ctx, other, start + rng:NextNumber(0, 30))
			skip[other] = true
		end
	end
	Kit.Rows(ctx, start + 12, ctx.length - EDGE, { SandCastle = 2, Driftwood = 1 }, defs, skip)
	Kit.PickupSpot(ctx, roofLane, EDGE * 0.5, "SuperSneakers")
end

-- Under the pier: run through, or boost onto the boardwalk.
local PIER_START, PIER_LENGTH = 40, 66
local function pier(ctx: Kit.Ctx)
	local d0, d1 = PIER_START, PIER_START + PIER_LENGTH
	Kit.Tunnel(ctx, d0, PIER_LENGTH, { Color = C.WoodDark, Material = Enum.Material.Wood, Transparency = 1 }, { Color = C.Wood, Material = Enum.Material.WoodPlanks })
	local wallX = (Kit.ROAD_WIDTH + 4) / 2 + 1
	for d = d0 + 2, d1 - 2, 8 do
		for _, side in { -1, 1 } do
			Kit.Scenery(ctx, { Name = "Pillar", Size = Vector3.new(1.6, Kit.TUNNEL_CEILING, 1.6), CFrame = Kit.CF(ctx, side * wallX, Kit.TUNNEL_CEILING / 2, d), Color = C.WoodDark, Material = Enum.Material.Wood })
			Kit.Scenery(ctx, { Name = "Railing", Size = Vector3.new(0.4, 2.4, 8), CFrame = Kit.CF(ctx, side * (wallX + 1), Kit.TUNNEL_ROOF + 1.2, d + 2), Color = C.Foam })
		end
	end
	local sign = Kit.Scenery(ctx, { Name = "PierSign", Size = Vector3.new(24, 3.5, 0.6), CFrame = Kit.CF(ctx, 0, Kit.TUNNEL_ROOF + 8, d0), Color = Color3.fromRGB(30, 110, 180) })
	Util.SurfaceLabel(sign, Enum.NormalId.Back, "🎡 BRAINROT PIER", { PixelsPerStud = 12 })
	for _, side in { -1, 1 } do
		Kit.Scenery(ctx, { Name = "SignPost", Size = Vector3.new(0.8, 10, 0.8), CFrame = Kit.CF(ctx, side * 10, Kit.TUNNEL_ROOF + 5, d0), Color = C.WoodDark })
	end
	Kit.SideSign(ctx, d0 - 26, "👟🛹 BOOST ONTO THE PIER!", Color3.fromRGB(255, 205, 40), Color3.fromRGB(30, 20, 10))
	local roofLane = laneOf(ctx)
	Kit.CoinLine(ctx, roofLane, d0 + 4, d1 - 4, Kit.TUNNEL_ROOF)
	Kit.PickupSpot(ctx, laneOf(ctx), d1 - 12, "MysteryBox", Kit.TUNNEL_ROOF, 0.4)
	Kit.Rows(ctx, d0 + 10, d1 - 6, LOW, defs)
	Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5, "SuperSneakers")
end

local specs: { Kit.SectionSpec } = {
	{
		kind = "Gate",
		weight = 0,
		difficulties = { 0 },
		variants = 1,
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			Kit.Arch(ctx, 24, "🌊 TSUNAMI BEACH", Color3.fromRGB(40, 150, 230), C.Bamboo)
			Kit.SideSign(ctx, 60, "🌊 RUN FROM THE WAVE!", Color3.fromRGB(40, 150, 230))
			sideDecor(ctx, 0, ctx.length)
			Kit.CoinLine(ctx, 0, 10, 50)
			Kit.Rows(ctx, 70, ctx.length - EDGE, { SandCastle = 1 }, defs)
		end,
	},
	{
		kind = "Sand",
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
		kind = "SurfShacks",
		weight = 7,
		cooldown = 1,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, ctx.length)
			shacks(ctx)
		end,
	},
	{
		kind = "Pier",
		weight = 4,
		cooldown = 2,
		difficulties = { 0, 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, PIER_START - 4)
			sideDecor(ctx, PIER_START + PIER_LENGTH + 4, ctx.length)
			pier(ctx)
		end,
	},
	{
		kind = "Tiki",
		weight = 4,
		cooldown = 2,
		difficulties = { 1, 2 },
		build = function(ctx)
			floor(ctx, 0, ctx.length)
			sideDecor(ctx, 0, ctx.length)
			for d = 20, ctx.length - 10, 26 do
				Kit.Scenery(ctx, { Name = "Torch", Size = Vector3.new(0.6, 7, 0.6), CFrame = Kit.CF(ctx, -SEA_SIDE * (HALF + 4), 3.5, d), Color = C.Bamboo })
				Kit.Scenery(ctx, { Name = "Flame", Size = Vector3.new(1, 1.4, 1), CFrame = Kit.CF(ctx, -SEA_SIDE * (HALF + 4), 7.6, d), Color = Color3.fromRGB(255, 150, 40), Material = Enum.Material.Neon })
			end
			Kit.Rows(ctx, EDGE + 12, ctx.length - EDGE, { TikiWall = 4, Coolers = 2, SandCastle = 2 }, defs)
			Kit.PickupSpot(ctx, laneOf(ctx), EDGE * 0.5)
		end,
	},
	{
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
			Kit.Rows(ctx, d + 16, ctx.length - EDGE, { SandCastle = 1 }, defs)
		end,
	},
}

function Beach.Build(parent: Instance, origin: Vector3): Folder
	return Kit.BuildArea(parent, "Beach", origin, specs, 2002)
end

return Beach
