--!strict
-- Lobby progression systems: buying/opening crates, the equipment loadout,
-- daily rewards and Robux purchases.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local CrateData = require(Shared.CrateData)
local DailyRewardData = require(Shared.DailyRewardData)
local EquipmentData = require(Shared.EquipmentData)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)

local Economy = {}

local rng = Random.new()

local COIN_PACKS = {
	CoinPackSmall = 2500,
	CoinPackLarge = 12000,
}

-- Hooks the run system registers so Robux revives can resume a run.
Economy.OnReviveProductPurchased = nil :: ((player: Player) -> boolean)?

local function notify(player: Player, text: string, color: Color3?)
	Remotes.Event("Notify"):FireClient(player, text, color)
end

local function productIdFor(key: string?): number
	if not key then
		return 0
	end
	return (Config.DeveloperProducts :: any)[key] or 0
end

local function buyCrate(player: Player, crateId: any, currency: any)
	if type(crateId) ~= "string" then
		return { ok = false, message = "Unknown crate" }
	end
	local crate = CrateData.Get(crateId)
	local profile = PlayerData.Get(player)
	if not crate or not profile then
		return { ok = false, message = "Unknown crate" }
	end

	if currency == "Robux" then
		local productId = productIdFor(crate.productKey)
		if productId == 0 then
			return { ok = false, message = "Robux purchases aren't set up yet" }
		end
		MarketplaceService:PromptProductPurchase(player, productId)
		return { ok = true, pending = true }
	end

	if profile.Coins < crate.coinPrice then
		return { ok = false, message = "Not enough coins!" }
	end
	profile.Coins -= crate.coinPrice
	PlayerData.GrantCrate(player, crate.id)
	notify(player, ("📦 Bought a %s!"):format(crate.name), crate.color)
	return { ok = true }
end

local function openCrate(player: Player, crateId: any)
	if type(crateId) ~= "string" then
		return { ok = false, message = "Unknown crate" }
	end
	local profile = PlayerData.Get(player)
	if not profile or (profile.Crates[crateId] or 0) <= 0 then
		return { ok = false, message = "You don't have that crate. Buy one first!" }
	end
	local item = CrateData.Roll(crateId, rng)
	if not item then
		return { ok = false, message = "Crate was empty?!" }
	end
	profile.Crates[crateId] -= 1
	local isNew = (profile.Inventory[item.id] or 0) == 0
	PlayerData.GrantItem(player, item.id)
	return {
		ok = true,
		itemId = item.id,
		isNew = isNew,
		level = EquipmentData.LevelFromCount(profile.Inventory[item.id]),
	}
end

local function equipItem(player: Player, slot: any, itemId: any)
	local profile = PlayerData.Get(player)
	if not profile or type(slot) ~= "number" then
		return { ok = false }
	end
	slot = math.floor(slot)
	if slot < 1 or slot > PlayerData.UnlockedSlots(player) then
		return { ok = false, message = "That slot is locked. Complete more runs!" }
	end
	if itemId == nil or itemId == "" then
		profile.Loadout[slot] = ""
		PlayerData.Changed(player)
		return { ok = true }
	end
	if type(itemId) ~= "string" or (profile.Inventory[itemId] or 0) <= 0 then
		return { ok = false, message = "You don't own that equipment" }
	end
	-- An item can only sit in one slot.
	for i, existing in profile.Loadout do
		if existing == itemId then
			profile.Loadout[i] = ""
		end
	end
	profile.Loadout[slot] = itemId
	PlayerData.Changed(player)
	return { ok = true }
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

	local grantedItem: string? = nil
	if reward.kind == "Coins" then
		profile.Coins += reward.amount or 0
	elseif reward.kind == "Crate" then
		profile.Crates[reward.crateId or "Common"] = (profile.Crates[reward.crateId or "Common"] or 0) + 1
	elseif reward.kind == "Equipment" then
		local pool = EquipmentData.ByRarity(reward.rarity or "Rare")
		local item = pool[rng:NextInteger(1, #pool)]
		PlayerData.GrantItem(player, item.id)
		grantedItem = item.id
	end
	PlayerData.Changed(player)
	notify(player, ("🎁 DAY %d: %s %s"):format(reward.day, reward.icon, reward.label), Color3.fromRGB(255, 220, 90))
	return { ok = true, day = reward.day, itemId = grantedItem }
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
	local products = Config.DeveloperProducts :: any
	for _, crate in CrateData.Crates do
		if crate.productKey and products[crate.productKey] == productId then
			PlayerData.GrantCrate(player, crate.id)
			notify(player, ("📦 %s added! Open it at the crate area."):format(crate.name), crate.color)
			return true
		end
	end
	for key, amount in COIN_PACKS do
		if products[key] == productId then
			PlayerData.AddCoins(player, amount)
			notify(player, ("🪙 +%d coins!"):format(amount), Color3.fromRGB(255, 220, 90))
			return true
		end
	end
	if products.Revive == productId and Economy.OnReviveProductPurchased then
		return Economy.OnReviveProductPurchased(player)
	end
	return false
end

function Economy.Init()
	Remotes.Function("BuyCrate").OnServerInvoke = buyCrate
	Remotes.Function("OpenCrate").OnServerInvoke = openCrate
	Remotes.Function("EquipItem").OnServerInvoke = equipItem
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
