--!strict
-- What coins are for (Subway Surfers style): power-up upgrades, more
-- Brainrot pedestals (a higher score multiplier ceiling) and hoverboards.
-- Also daily rewards and Robux purchases.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyRewardData = require(Shared.DailyRewardData)
local PowerUpData = require(Shared.PowerUpData)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)

local Economy = {}

local COIN_PACKS = {
	CoinPackSmall = 2500,
	CoinPackLarge = 12000,
}
local ROBUX_HOVERBOARDS = 5
local COIN_HOVERBOARD_BUNDLE = 1

-- Hook the run system registers so Robux revives can resume a run.
Economy.OnReviveProductPurchased = nil :: ((player: Player) -> boolean)?

local function notify(player: Player, text: string, color: Color3?)
	Remotes.Event("Notify"):FireClient(player, text, color)
end

local function productIdFor(key: string): number
	return (Config.DeveloperProducts :: any)[key] or 0
end

-- Next pedestal price, or nil when the base is full.
function Economy.NextPedestalCost(pedestals: number): number?
	if pedestals >= Config.Score.MaxPedestals then
		return nil
	end
	return Config.Score.PedestalCosts[pedestals - Config.Score.StartingPedestals + 1]
end

local function buyUpgrade(player: Player, powerUpId: any)
	local profile = PlayerData.Get(player)
	local powerUp = if type(powerUpId) == "string" then PowerUpData.Get(powerUpId) else nil
	if not profile or not powerUp then
		return { ok = false, message = "Unknown power-up" }
	end
	local level = profile.Upgrades[powerUp.id] or 0
	local cost = PowerUpData.NextCost(level)
	if not cost then
		return { ok = false, message = "Already maxed out!" }
	end
	if profile.Coins < cost then
		return { ok = false, message = "Not enough coins!" }
	end
	profile.Coins -= cost
	profile.Upgrades[powerUp.id] = level + 1
	PlayerData.Changed(player)
	return { ok = true, level = level + 1, duration = PowerUpData.Duration(powerUp.id, level + 1) }
end

local function buyPedestal(player: Player)
	local profile = PlayerData.Get(player)
	if not profile then
		return { ok = false }
	end
	local cost = Economy.NextPedestalCost(profile.Pedestals)
	if not cost then
		return { ok = false, message = "Your base is full!" }
	end
	if profile.Coins < cost then
		return { ok = false, message = "Not enough coins!" }
	end
	profile.Coins -= cost
	profile.Pedestals += 1
	PlayerData.Changed(player)
	return { ok = true, pedestals = profile.Pedestals }
end

local function buyHoverboards(player: Player, currency: any)
	local profile = PlayerData.Get(player)
	if not profile then
		return { ok = false }
	end
	if currency == "Robux" then
		local productId = productIdFor("Hoverboards")
		if productId == 0 then
			return { ok = false, message = "Robux purchases aren't set up yet" }
		end
		MarketplaceService:PromptProductPurchase(player, productId)
		return { ok = true, pending = true }
	end
	if profile.Coins < Config.Economy.HoverboardCost then
		return { ok = false, message = "Not enough coins!" }
	end
	profile.Coins -= Config.Economy.HoverboardCost
	profile.Hoverboards += COIN_HOVERBOARD_BUNDLE
	PlayerData.Changed(player)
	return { ok = true, hoverboards = profile.Hoverboards }
end

local function claimDaily(player: Player)
	local profile = PlayerData.Get(player)
	if not profile then
		return { ok = false }
	end
	local today = DailyRewardData.DayNumber(os.time())
	if profile.Daily.LastClaimDay == today then
		return { ok = false, message = "Come back tomorrow!" }
	end
	local streak = if profile.Daily.LastClaimDay == today - 1 then profile.Daily.Streak + 1 else 1
	if streak > #DailyRewardData.Rewards then
		streak = 1
	end
	local reward = DailyRewardData.Rewards[streak]
	profile.Daily.LastClaimDay = today
	profile.Daily.Streak = streak
	if reward.kind == "Coins" then
		profile.Coins += reward.amount
	else
		profile.Hoverboards += reward.amount
	end
	PlayerData.Changed(player)
	notify(player, ("🎁 DAY %d: %s %s"):format(reward.day, reward.icon, reward.label), Color3.fromRGB(255, 220, 90))
	return { ok = true, day = reward.day }
end

local function buyCoinPack(player: Player, key: any)
	if type(key) ~= "string" or not COIN_PACKS[key] then
		return { ok = false }
	end
	local productId = productIdFor(key)
	if productId == 0 then
		return { ok = false, message = "Robux purchases aren't set up yet" }
	end
	MarketplaceService:PromptProductPurchase(player, productId)
	return { ok = true, pending = true }
end

-- Grants a developer product. Returns true when the grant succeeded.
local function grantProduct(player: Player, productId: number): boolean
	for key, amount in COIN_PACKS do
		if productIdFor(key) == productId then
			PlayerData.AddCoins(player, amount)
			notify(player, ("🪙 +%d coins!"):format(amount), Color3.fromRGB(255, 220, 90))
			return true
		end
	end
	if productIdFor("Hoverboards") == productId then
		local profile = PlayerData.Get(player)
		if profile then
			profile.Hoverboards += ROBUX_HOVERBOARDS
			PlayerData.Changed(player)
			notify(player, ("🛹 +%d hoverboards!"):format(ROBUX_HOVERBOARDS), Color3.fromRGB(140, 220, 255))
			return true
		end
	end
	if productIdFor("Revive") == productId and Economy.OnReviveProductPurchased then
		return Economy.OnReviveProductPurchased(player)
	end
	return false
end

function Economy.Init()
	Remotes.Function("BuyUpgrade").OnServerInvoke = buyUpgrade
	Remotes.Function("BuyPedestal").OnServerInvoke = buyPedestal
	Remotes.Function("BuyHoverboards").OnServerInvoke = buyHoverboards
	Remotes.Function("ClaimDaily").OnServerInvoke = claimDaily
	Remotes.Function("BuyCoinPack").OnServerInvoke = buyCoinPack

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player or not PlayerData.Get(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, granted = pcall(grantProduct, player, receipt.ProductId)
		if ok and granted then
			PlayerData.Save(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return Economy
