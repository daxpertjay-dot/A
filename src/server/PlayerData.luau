--!strict
-- Loads, caches and saves player profiles. Profiles are plain tables; call
-- PlayerData.Changed(player) after mutating one to push a snapshot to the
-- client UI and refresh leaderstats.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local EquipmentData = require(Shared.EquipmentData)
local Remotes = require(Shared.Remotes)

export type Stats = {
	BestDistance: number,
	TotalCoins: number,
	TotalRuns: number,
	LongestSurvival: number,
	EquipmentCollected: number,
	TotalDistance: number,
}

export type Profile = {
	Version: number,
	Coins: number,
	Inventory: { [string]: number }, -- itemId -> copies owned
	Crates: { [string]: number }, -- crateId -> unopened crates
	Loadout: { string }, -- itemIds by slot ("" = empty)
	Collection: { [string]: boolean }, -- brainrotId -> discovered
	Brainrots: { [string]: number }, -- brainrotId -> copies owned
	Buddy: string, -- Brainrot that joins your runs ("" = none)
	PendingIncome: number, -- coins waiting on your base's collect pad
	LastOnline: number, -- os.time() of the last save (offline earnings)
	Secrets: { [string]: boolean },
	Stats: Stats,
	Daily: { LastClaimDay: number, Streak: number },
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}

local store: DataStore? = nil
if Config.DataStoreEnabled then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable, using session data only:", result)
	end
end

local function newProfile(): Profile
	return {
		Version = 1,
		Coins = Config.Economy.StartingCoins,
		Inventory = { [EquipmentData.StarterItem] = 1 },
		Crates = { Common = 1 },
		Loadout = { EquipmentData.StarterItem, "", "" },
		Collection = { [BrainrotData.ChaserId] = true },
		Brainrots = { [BrainrotData.ChaserId] = 1 },
		Buddy = BrainrotData.ChaserId,
		PendingIncome = 0,
		LastOnline = 0,
		Secrets = {},
		Stats = {
			BestDistance = 0,
			TotalCoins = 0,
			TotalRuns = 0,
			LongestSurvival = 0,
			EquipmentCollected = 1,
			TotalDistance = 0,
		},
		Daily = { LastClaimDay = -1, Streak = 0 },
	}
end

-- Fill in any fields missing from older saves.
local function reconcile(data: any, template: any): any
	for key, value in template do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and #value == 0 then
			reconcile(data[key], value)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[PlayerData] %s failed (attempt %d): %s"):format(label, attempt, tostring(result)))
		task.wait(attempt)
	end
	return false, nil
end

local function setupLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Parent = folder
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	folder.Parent = player
end

local function refreshLeaderstats(player: Player, profile: Profile)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local best = folder:FindFirstChild("Best") :: IntValue?
	local coins = folder:FindFirstChild("Coins") :: IntValue?
	if best then
		best.Value = math.floor(profile.Stats.BestDistance)
	end
	if coins then
		coins.Value = math.floor(profile.Coins)
	end
end

function PlayerData.Get(player: Player): Profile?
	return profiles[player]
end

-- Waits (briefly) for a profile to finish loading.
function PlayerData.Await(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Brainrots shown on the player's base (and earning), best earners first.
-- Every owned copy takes a pedestal, up to Config.Plot.Pedestals.
function PlayerData.DisplayedBrainrots(profile: Profile): { string }
	local copies = {}
	for id, count in profile.Brainrots do
		if BrainrotData.Get(id) then
			for _ = 1, count do
				table.insert(copies, id)
			end
		end
	end
	table.sort(copies, function(a, b)
		local da, db = BrainrotData.Get(a) :: BrainrotData.Brainrot, BrainrotData.Get(b) :: BrainrotData.Brainrot
		if da.income ~= db.income then
			return da.income > db.income
		end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(#copies, Config.Plot.Pedestals) do
		out[i] = copies[i]
	end
	return out
end

function PlayerData.IncomePerSecond(profile: Profile): number
	local total = 0
	for _, id in PlayerData.DisplayedBrainrots(profile) do
		total += (BrainrotData.Get(id) :: BrainrotData.Brainrot).income
	end
	return total
end

function PlayerData.GrantBrainrot(player: Player, id: string, count: number?)
	local profile = profiles[player]
	if not profile or not BrainrotData.Get(id) then
		return
	end
	profile.Brainrots[id] = (profile.Brainrots[id] or 0) + (count or 1)
	profile.Collection[id] = true
	if profile.Buddy == "" then
		profile.Buddy = id
	end
	PlayerData.Changed(player)
end

function PlayerData.Snapshot(player: Player): any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local unlockedSlots = 0
	for _, requiredRuns in Config.LoadoutSlotUnlocks do
		if profile.Stats.TotalRuns >= requiredRuns then
			unlockedSlots += 1
		end
	end
	return {
		Coins = profile.Coins,
		Inventory = profile.Inventory,
		Crates = profile.Crates,
		Loadout = profile.Loadout,
		Collection = profile.Collection,
		Brainrots = profile.Brainrots,
		Buddy = profile.Buddy,
		Displayed = PlayerData.DisplayedBrainrots(profile),
		IncomePerSecond = PlayerData.IncomePerSecond(profile),
		PendingIncome = math.floor(profile.PendingIncome),
		Stats = profile.Stats,
		Daily = profile.Daily,
		UnlockedSlots = unlockedSlots,
		Today = math.floor(os.time() / 86400),
	}
end

function PlayerData.UnlockedSlots(player: Player): number
	local snapshot = PlayerData.Snapshot(player)
	return if snapshot then snapshot.UnlockedSlots else 1
end

local changedListeners: { (Player) -> () } = {}

-- Called after every profile change (the first call means "just loaded").
function PlayerData.OnChanged(callback: (Player) -> ())
	table.insert(changedListeners, callback)
end

function PlayerData.Changed(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	refreshLeaderstats(player, profile)
	Remotes.Event("DataUpdated"):FireClient(player, PlayerData.Snapshot(player))
	for _, callback in changedListeners do
		task.spawn(callback, player)
	end
end

function PlayerData.AddCoins(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Coins = math.max(0, profile.Coins + amount)
	PlayerData.Changed(player)
end

-- Moves the coins waiting on the base's collect pad into the wallet.
function PlayerData.CollectIncome(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local amount = math.floor(profile.PendingIncome)
	if amount <= 0 then
		return 0
	end
	profile.PendingIncome -= amount
	profile.Coins += amount
	PlayerData.Changed(player)
	return amount
end

function PlayerData.GrantItem(player: Player, itemId: string)
	local profile = profiles[player]
	if not profile or not EquipmentData.Get(itemId) then
		return
	end
	local wasNew = (profile.Inventory[itemId] or 0) == 0
	profile.Inventory[itemId] = (profile.Inventory[itemId] or 0) + 1
	profile.Stats.EquipmentCollected += 1
	-- Auto-equip into an empty unlocked slot the first time an item is found.
	if wasNew then
		for slot = 1, PlayerData.UnlockedSlots(player) do
			if (profile.Loadout[slot] or "") == "" then
				profile.Loadout[slot] = itemId
				break
			end
		end
	end
	PlayerData.Changed(player)
end

function PlayerData.GrantCrate(player: Player, crateId: string, count: number?)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Crates[crateId] = (profile.Crates[crateId] or 0) + (count or 1)
	PlayerData.Changed(player)
end

function PlayerData.Save(player: Player)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	local dataStore = store :: DataStore
	profile.LastOnline = os.time()
	retry("Save " .. player.Name, function()
		dataStore:SetAsync(keyFor(player), profile, { player.UserId })
		return true
	end)
end

local function onPlayerAdded(player: Player)
	setupLeaderstats(player)

	local profile: Profile
	if store then
		local dataStore = store :: DataStore
		local ok, data = retry("Load " .. player.Name, function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if not ok and RunService:IsStudio() then
			-- Studio without "Enable Studio Access to API Services": play with
			-- session-only data and stop trying to save.
			warn("[PlayerData] DataStore load failed in Studio; switching to session-only data.")
			store = nil
			profile = newProfile()
		elseif not ok then
			-- Never overwrite a save we failed to read.
			player:Kick("Could not load your data. Please rejoin!")
			return
		else
			profile = if data then reconcile(data, newProfile()) else newProfile()
		end
	else
		profile = newProfile()
	end

	if not player.Parent then
		return
	end
	-- Older saves: everyone owns Sahur, and a discovered-but-unowned chaser
	-- from v1 becomes owned.
	if (profile.Brainrots[BrainrotData.ChaserId] or 0) == 0 then
		profile.Brainrots[BrainrotData.ChaserId] = 1
		profile.Collection[BrainrotData.ChaserId] = true
	end
	if profile.Buddy ~= "" and (profile.Brainrots[profile.Buddy] or 0) == 0 then
		profile.Buddy = BrainrotData.ChaserId
	end
	-- Offline earnings (half speed, capped).
	if profile.LastOnline > 0 then
		local away = math.clamp(os.time() - profile.LastOnline, 0, Config.Plot.OfflineIncomeCap)
		profile.PendingIncome += away * PlayerData.IncomePerSecond(profile) * Config.Plot.OfflineIncomeRate
	end
	profiles[player] = profile
	PlayerData.Changed(player)
end

-- Systems that must write to a profile before the final save (e.g. ending an
-- in-progress run) register here.
local beforeRemove: { (Player) -> () } = {}
function PlayerData.BeforeRemove(callback: (Player) -> ())
	table.insert(beforeRemove, callback)
end

local function onPlayerRemoving(player: Player)
	for _, callback in beforeRemove do
		pcall(callback, player)
	end
	PlayerData.Save(player)
	profiles[player] = nil
end

function PlayerData.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Remotes.Function("GetData").OnServerInvoke = function(player)
		PlayerData.Await(player, 10)
		return PlayerData.Snapshot(player)
	end

	-- Base income: every displayed Brainrot earns coins each second; players
	-- collect them from the pad on their base.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, profile in profiles do
				profile.PendingIncome += PlayerData.IncomePerSecond(profile)
			end
		end
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(120)
			for player in profiles do
				task.spawn(PlayerData.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerData.Save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return PlayerData
