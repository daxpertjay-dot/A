--!strict
-- Track power-ups (Subway Surfers style). They spawn on the track; grab one
-- to use it immediately. Upgrading a power-up with coins (5 levels) makes it
-- last longer.

export type PowerUp = {
	id: string,
	name: string,
	icon: string,
	color: Color3,
	description: string,
	durations: { number }, -- seconds at upgrade level 0..5 (index 1..6)
	spawnWeight: number,
}

local PowerUpData = {}

PowerUpData.MaxLevel = 5
PowerUpData.UpgradeCosts = { 500, 1500, 3500, 7500, 15000 } -- cost to reach level 1..5

local list: { PowerUp } = {
	{
		id = "Magnet",
		name = "Coin Magnet",
		icon = "🧲",
		color = Color3.fromRGB(255, 80, 80),
		description = "Pulls every coin in reach toward you.",
		durations = { 10, 12, 14, 16, 18, 20 },
		spawnWeight = 35,
	},
	{
		id = "Jetpack",
		name = "Jetpack",
		icon = "🚀",
		color = Color3.fromRGB(255, 170, 40),
		description = "Fly high over everything along a trail of sky coins.",
		durations = { 6, 7, 8, 9, 10.5, 12 },
		spawnWeight = 20,
	},
	{
		id = "SuperSneakers",
		name = "Super Sneakers",
		icon = "👟",
		color = Color3.fromRGB(90, 220, 110),
		description = "Huge jumps: hop straight onto trains.",
		durations = { 10, 12, 14, 16, 18, 20 },
		spawnWeight = 25,
	},
	{
		id = "ScoreBooster",
		name = "2x Score Booster",
		icon = "✖️2",
		color = Color3.fromRGB(80, 170, 255),
		description = "Doubles your score multiplier while it lasts.",
		durations = { 10, 12, 14, 16, 18, 20 },
		spawnWeight = 20,
	},
}

PowerUpData.List = list

local byId: { [string]: PowerUp } = {}
for _, p in list do
	byId[p.id] = p
end
PowerUpData.ById = byId

function PowerUpData.Get(id: string?): PowerUp?
	return if id then byId[id] else nil
end

function PowerUpData.Duration(id: string, level: number?): number
	local p = byId[id]
	if not p then
		return 0
	end
	return p.durations[math.clamp((level or 0) + 1, 1, #p.durations)]
end

-- Cost to buy the next level, or nil when maxed.
function PowerUpData.NextCost(level: number?): number?
	return PowerUpData.UpgradeCosts[(level or 0) + 1]
end

function PowerUpData.Pick(rng: Random): PowerUp
	local total = 0
	for _, p in list do
		total += p.spawnWeight
	end
	local roll = rng:NextNumber() * total
	for _, p in list do
		if roll < p.spawnWeight then
			return p
		end
		roll -= p.spawnWeight
	end
	return list[#list]
end

return PowerUpData
