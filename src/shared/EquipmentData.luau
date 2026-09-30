--!strict
-- Equipment catalog. Equipment is taken into a run through the loadout and
-- activated with a limited number of charges. Abilities interact with the
-- world (bombs destroy walls, speed boosts crash through them) instead of just
-- being stat bumps.

export type Ability = "Shield" | "Magnet" | "SpeedBoost" | "Bomb" | "CoinDoubler"
export type Rarity = "Common" | "Rare" | "Legendary"

export type Item = {
	id: string,
	name: string,
	icon: string,
	ability: Ability,
	rarity: Rarity,
	charges: number,
	duration: number?, -- seconds (timed abilities)
	radius: number?, -- studs (Magnet / Bomb)
	maxTier: number?, -- highest destruction tier a Bomb breaks
	speedMultiplier: number?,
	description: string,
}

local EquipmentData = {}

EquipmentData.RarityColors = {
	Common = Color3.fromRGB(170, 180, 190),
	Rare = Color3.fromRGB(60, 150, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
} :: { [string]: Color3 }

EquipmentData.RarityOrder = { Common = 1, Rare = 2, Legendary = 3 } :: { [string]: number }

EquipmentData.AbilityIcons = {
	Shield = "🛡️",
	Magnet = "🧲",
	SpeedBoost = "⚡",
	Bomb = "💣",
	CoinDoubler = "🪙",
} :: { [string]: string }

local items: { Item } = {
	-- Common
	{ id = "CardboardShield", name = "Cardboard Shield", icon = "🛡️", ability = "Shield", rarity = "Common", charges = 1, duration = 6, description = "Blocks the next crash. Probably." },
	{ id = "FridgeMagnet", name = "Fridge Magnet", icon = "🧲", ability = "Magnet", rarity = "Common", charges = 1, duration = 8, radius = 22, description = "Pulls nearby coins toward you." },
	{ id = "EspressoShot", name = "Espresso Shot", icon = "⚡", ability = "SpeedBoost", rarity = "Common", charges = 1, duration = 4, speedMultiplier = 1.35, description = "Zoom. Smash through weak walls while active." },
	{ id = "Firecracker", name = "Firecracker", icon = "🧨", ability = "Bomb", rarity = "Common", charges = 1, radius = 22, maxTier = 2, description = "Blows up small props and wooden walls ahead." },

	-- Rare
	{ id = "RiotShield", name = "Riot Shield", icon = "🛡️", ability = "Shield", rarity = "Rare", charges = 2, duration = 8, description = "Absorbs a crash and smashes the obstacle." },
	{ id = "HorseshoeMagnet", name = "Horseshoe Magnet", icon = "🧲", ability = "Magnet", rarity = "Rare", charges = 2, duration = 12, radius = 30, description = "A stronger coin magnet." },
	{ id = "CappuccinoRocket", name = "Cappuccino Rocket", icon = "☕", ability = "SpeedBoost", rarity = "Rare", charges = 2, duration = 6, speedMultiplier = 1.45, description = "Ballerina-approved caffeine rush." },
	{ id = "BrainrotBomb", name = "Brainrot Bomb", icon = "💣", ability = "Bomb", rarity = "Rare", charges = 2, radius = 32, maxTier = 3, description = "Levels concrete walls and pushes Sahur back." },
	{ id = "CoinDoubler", name = "Coin Doubler", icon = "🪙", ability = "CoinDoubler", rarity = "Rare", charges = 2, duration = 10, description = "Coins are worth double for a while." },

	-- Legendary
	{ id = "SahurProofShield", name = "Sahur-Proof Shield", icon = "🪵", ability = "Shield", rarity = "Legendary", charges = 3, duration = 12, description = "Even the bat can't get through this." },
	{ id = "BlackHoleMagnet", name = "Black Hole Magnet", icon = "🌀", ability = "Magnet", rarity = "Legendary", charges = 3, duration = 18, radius = 45, description = "Every coin in sight is yours." },
	{ id = "BombardiroJet", name = "Bombardiro Jet", icon = "🐊", ability = "SpeedBoost", rarity = "Legendary", charges = 3, duration = 8, speedMultiplier = 1.6, description = "Strap a crocodile bomber to your back." },
	{ id = "NuclearBrainrotBomb", name = "Nuclear Brainrot Bomb", icon = "☢️", ability = "Bomb", rarity = "Legendary", charges = 3, radius = 48, maxTier = 3, description = "Huge blast. Opens every alternate path." },
	{ id = "GoldenTralalero", name = "Golden Tralalero", icon = "🦈", ability = "CoinDoubler", rarity = "Legendary", charges = 3, duration = 15, description = "A shark in sneakers that doubles your coins." },
}

EquipmentData.Items = items

local byId: { [string]: Item } = {}
for _, item in items do
	byId[item.id] = item
end
EquipmentData.ById = byId

function EquipmentData.Get(id: string?): Item?
	if id == nil then
		return nil
	end
	return byId[id]
end

function EquipmentData.ByRarity(rarity: string): { Item }
	local list = {}
	for _, item in items do
		if item.rarity == rarity then
			table.insert(list, item)
		end
	end
	return list
end

-- Duplicates level an item up (max level 5). Each level adds 8% duration /
-- radius, and level 3+ grants one extra charge.
EquipmentData.MaxLevel = 5

function EquipmentData.LevelFromCount(count: number): number
	return math.clamp(count, 1, EquipmentData.MaxLevel)
end

function EquipmentData.ChargesAt(item: Item, level: number): number
	return item.charges + (if level >= 3 then 1 else 0)
end

function EquipmentData.ScaleAt(level: number): number
	return 1 + (level - 1) * 0.08
end

-- Starter item every new player owns so the loadout is never empty.
EquipmentData.StarterItem = "CardboardShield"

return EquipmentData
