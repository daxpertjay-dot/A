--!strict
-- Run biomes (Roll a Slime style progression). The further you run, the
-- stranger the world gets: each biome has its own look, lighting, obstacle
-- skins, catchable Brainrots, coin value and a small gameplay twist.
--
--   🌿 Grasslands → 🏙️ Brainrot City → ❄️ Frozen Peaks → 🌋 Volcano → 🌌 Brainrot Void
--
-- The last biome continues forever.

export type Recolor = { color: Color3, material: Enum.Material }

export type Biome = {
	id: string,
	name: string,
	icon: string,
	startMeters: number,
	-- Look
	road: { color: Color3, material: Enum.Material },
	ground: { color: Color3, material: Enum.Material },
	coinColor: Color3,
	recolor: { [string]: Recolor }, -- obstacle kind -> new skin
	lighting: { fog: Color3, ambient: Color3, clockTime: number, brightness: number },
	-- Gameplay
	coinValue: number, -- each coin is worth this much here
	laneChangeScale: number, -- >1 = slower, slidier lane changes (ice)
	gravityScale: number, -- <1 = floatier jumps (void)
	segmentWeights: { [string]: number }, -- which track segments appear here
	brainrots: { { id: string, weight: number } }, -- who you can catch here
	description: string,
}

local BiomeData = {}

local list: { Biome } = {
	{
		id = "Grasslands",
		name = "Grasslands",
		icon = "🌿",
		startMeters = 0,
		road = { color = Color3.fromRGB(196, 160, 110), material = Enum.Material.Ground },
		ground = { color = Color3.fromRGB(95, 190, 75), material = Enum.Material.Grass },
		coinColor = Color3.fromRGB(255, 200, 40),
		recolor = {
			SteelBarrier = { color = Color3.fromRGB(150, 110, 70), material = Enum.Material.WoodPlanks },
			ConcreteWall = { color = Color3.fromRGB(140, 140, 150), material = Enum.Material.Slate },
			Crates = { color = Color3.fromRGB(230, 200, 90), material = Enum.Material.Fabric }, -- hay bales
		},
		lighting = { fog = Color3.fromRGB(190, 230, 255), ambient = Color3.fromRGB(150, 150, 150), clockTime = 13, brightness = 3 },
		coinValue = 1,
		laneChangeScale = 1,
		gravityScale = 1,
		segmentWeights = { Meadow = 10, Straight = 6, Ramp = 4, Destruction = 3, BrainrotSpecial = 4 },
		brainrots = {
			{ id = "ChimpanziniBananini", weight = 50 },
			{ id = "BrrBrrPatapim", weight = 50 },
			{ id = "TralaleroTralala", weight = 15 },
		},
		description = "Sunny fields and hay bales. A gentle warm-up.",
	},
	{
		id = "City",
		name = "Brainrot City",
		icon = "🏙️",
		startMeters = 800,
		road = { color = Color3.fromRGB(55, 55, 65), material = Enum.Material.Asphalt },
		ground = { color = Color3.fromRGB(200, 200, 205), material = Enum.Material.Concrete },
		coinColor = Color3.fromRGB(255, 200, 40),
		recolor = {},
		lighting = { fog = Color3.fromRGB(255, 190, 230), ambient = Color3.fromRGB(140, 130, 160), clockTime = 16, brightness = 3 },
		coinValue = 2,
		laneChangeScale = 1,
		gravityScale = 1,
		segmentWeights = { Straight = 8, Intersection = 6, Alley = 5, Construction = 4, ParkingLot = 4, Tunnel = 4, Highway = 4, Building = 4, Ramp = 5, Destruction = 4, BrainrotSpecial = 4 },
		brainrots = {
			{ id = "TralaleroTralala", weight = 30 },
			{ id = "BallerinaCappuccina", weight = 30 },
			{ id = "BrrBrrPatapim", weight = 15 },
			{ id = "BombardiroCrocodilo", weight = 8 },
		},
		description = "Traffic, trains and walls to smash.",
	},
	{
		id = "Ice",
		name = "Frozen Peaks",
		icon = "❄️",
		startMeters = 1800,
		road = { color = Color3.fromRGB(190, 230, 255), material = Enum.Material.Ice },
		ground = { color = Color3.fromRGB(245, 250, 255), material = Enum.Material.Snow },
		coinColor = Color3.fromRGB(120, 230, 255),
		recolor = {
			WoodWall = { color = Color3.fromRGB(160, 220, 255), material = Enum.Material.Ice },
			ConcreteWall = { color = Color3.fromRGB(110, 170, 230), material = Enum.Material.Glacier },
			Barricade = { color = Color3.fromRGB(235, 245, 255), material = Enum.Material.Snow },
			Crates = { color = Color3.fromRGB(200, 235, 255), material = Enum.Material.Ice },
			Car = { color = Color3.fromRGB(170, 210, 240), material = Enum.Material.Ice },
			SteelBarrier = { color = Color3.fromRGB(140, 200, 240), material = Enum.Material.Glacier },
		},
		lighting = { fog = Color3.fromRGB(225, 240, 255), ambient = Color3.fromRGB(170, 190, 220), clockTime = 11, brightness = 3.5 },
		coinValue = 3,
		laneChangeScale = 1.7, -- slippery!
		gravityScale = 1,
		segmentWeights = { Straight = 6, IceSlide = 6, Ramp = 4, Tunnel = 3, Destruction = 4, BrainrotSpecial = 4 },
		brainrots = {
			{ id = "BallerinaCappuccina", weight = 25 },
			{ id = "LiriliLarila", weight = 25 },
			{ id = "BombombiniGusini", weight = 20 },
			{ id = "TralaleroTralala", weight = 10 },
		},
		description = "Slippery ice: lane changes slide.",
	},
	{
		id = "Volcano",
		name = "Volcano",
		icon = "🌋",
		startMeters = 3000,
		road = { color = Color3.fromRGB(55, 45, 45), material = Enum.Material.Basalt },
		ground = { color = Color3.fromRGB(40, 30, 30), material = Enum.Material.CrackedLava },
		coinColor = Color3.fromRGB(255, 130, 40),
		recolor = {
			WoodWall = { color = Color3.fromRGB(90, 60, 50), material = Enum.Material.Basalt },
			ConcreteWall = { color = Color3.fromRGB(30, 25, 30), material = Enum.Material.Basalt },
			Barricade = { color = Color3.fromRGB(120, 70, 50), material = Enum.Material.Rock },
			Crates = { color = Color3.fromRGB(110, 80, 60), material = Enum.Material.Rock },
			SteelBarrier = { color = Color3.fromRGB(60, 50, 50), material = Enum.Material.Basalt },
		},
		lighting = { fog = Color3.fromRGB(255, 120, 60), ambient = Color3.fromRGB(170, 90, 70), clockTime = 18.2, brightness = 2.5 },
		coinValue = 5,
		laneChangeScale = 1,
		gravityScale = 1,
		segmentWeights = { Straight = 6, LavaRiver = 7, Ramp = 3, Destruction = 4, BrainrotSpecial = 4 },
		brainrots = {
			{ id = "BombardiroCrocodilo", weight = 25 },
			{ id = "BombombiniGusini", weight = 15 },
			{ id = "CappuccinoAssassino", weight = 8 },
			{ id = "TrippiTroppi", weight = 4 },
		},
		description = "Jump the lava pools!",
	},
	{
		id = "Void",
		name = "Brainrot Void",
		icon = "🌌",
		startMeters = 4500,
		road = { color = Color3.fromRGB(60, 30, 100), material = Enum.Material.Neon },
		ground = { color = Color3.fromRGB(20, 10, 40), material = Enum.Material.SmoothPlastic },
		coinColor = Color3.fromRGB(220, 120, 255),
		recolor = {
			WoodWall = { color = Color3.fromRGB(150, 80, 255), material = Enum.Material.Glass },
			ConcreteWall = { color = Color3.fromRGB(80, 40, 160), material = Enum.Material.ForceField },
			Barricade = { color = Color3.fromRGB(255, 100, 220), material = Enum.Material.Neon },
			Crates = { color = Color3.fromRGB(120, 255, 230), material = Enum.Material.Glass },
			Car = { color = Color3.fromRGB(200, 120, 255), material = Enum.Material.Glass },
			SteelBarrier = { color = Color3.fromRGB(90, 60, 140), material = Enum.Material.Metal },
		},
		lighting = { fog = Color3.fromRGB(90, 40, 150), ambient = Color3.fromRGB(150, 110, 200), clockTime = 0, brightness = 2 },
		coinValue = 8,
		laneChangeScale = 1,
		gravityScale = 0.72, -- floaty jumps
		segmentWeights = { Straight = 7, Highway = 3, Ramp = 4, Destruction = 4, BrainrotSpecial = 5 },
		brainrots = {
			{ id = "CappuccinoAssassino", weight = 20 },
			{ id = "TrippiTroppi", weight = 20 },
			{ id = "LiriliLarila", weight = 10 },
			{ id = "BombardiroCrocodilo", weight = 10 },
		},
		description = "Low gravity. Legendary Brainrots. No way back.",
	},
}

BiomeData.List = list

local byId: { [string]: Biome } = {}
for _, b in list do
	byId[b.id] = b
end
BiomeData.ById = byId

-- Biome at a given run distance (meters).
function BiomeData.At(meters: number): Biome
	local current = list[1]
	for _, b in list do
		if meters >= b.startMeters then
			current = b
		end
	end
	return current
end

-- Weighted pick of a Brainrot you can catch in this biome.
function BiomeData.PickBrainrot(biome: Biome, rng: Random): string?
	local total = 0
	for _, entry in biome.brainrots do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, entry in biome.brainrots do
		if roll < entry.weight then
			return entry.id
		end
		roll -= entry.weight
	end
	return biome.brainrots[#biome.brainrots].id
end

-- Biomes a Brainrot can be caught in (for the collection UI).
function BiomeData.WhereToFind(brainrotId: string): { Biome }
	local out = {}
	for _, b in list do
		for _, entry in b.brainrots do
			if entry.id == brainrotId then
				table.insert(out, b)
				break
			end
		end
	end
	return out
end

return BiomeData
