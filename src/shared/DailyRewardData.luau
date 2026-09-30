--!strict
-- 7-day daily reward track. Missing a day resets the streak to day 1.

export type Reward = {
	day: number,
	label: string,
	icon: string,
	kind: "Coins" | "Hoverboard",
	amount: number,
}

local DailyRewardData = {}

DailyRewardData.Rewards = {
	{ day = 1, label = "200", icon = "🪙", kind = "Coins", amount = 200 },
	{ day = 2, label = "1 BOARD", icon = "🛹", kind = "Hoverboard", amount = 1 },
	{ day = 3, label = "500", icon = "🪙", kind = "Coins", amount = 500 },
	{ day = 4, label = "2 BOARDS", icon = "🛹", kind = "Hoverboard", amount = 2 },
	{ day = 5, label = "1,000", icon = "🪙", kind = "Coins", amount = 1000 },
	{ day = 6, label = "3 BOARDS", icon = "🛹", kind = "Hoverboard", amount = 3 },
	{ day = 7, label = "3,000", icon = "💰", kind = "Coins", amount = 3000 },
} :: { Reward }

-- Day index used for streak math (UTC days since epoch).
function DailyRewardData.DayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return DailyRewardData
