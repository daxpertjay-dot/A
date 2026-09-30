--!strict
-- 7-day daily reward track. Missing a day resets the streak to day 1.

export type Reward = {
	day: number,
	label: string,
	icon: string,
	kind: "Coins" | "Crate" | "Equipment",
	amount: number?,
	crateId: string?,
	rarity: string?, -- Equipment rewards roll a random item of this rarity
}

local DailyRewardData = {}

DailyRewardData.Rewards = {
	{ day = 1, label = "500", icon = "🪙", kind = "Coins", amount = 500 },
	{ day = 2, label = "CRATE", icon = "📦", kind = "Crate", crateId = "Common" },
	{ day = 3, label = "1,000", icon = "🪙", kind = "Coins", amount = 1000 },
	{ day = 4, label = "EQUIPMENT", icon = "⚡", kind = "Equipment", rarity = "Rare" },
	{ day = 5, label = "RARE CRATE", icon = "💎", kind = "Crate", crateId = "Rare" },
	{ day = 6, label = "2,500", icon = "🪙", kind = "Coins", amount = 2500 },
	{ day = 7, label = "SPECIAL ITEM", icon = "🎁", kind = "Equipment", rarity = "Legendary" },
} :: { Reward }

-- Day index used for streak math (UTC days since epoch).
function DailyRewardData.DayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return DailyRewardData
