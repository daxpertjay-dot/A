--!strict
-- Loads, caches and saves player profiles. Profiles are plain tables; call
-- PlayerData.Changed(player) after mutating one to push a snapshot to the
-- client UI, refresh leaderstats and update the player's base.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local PowerUpData = require(Shared.PowerUpData)
local Remotes = require(Shared.Remotes)

export type Stats = {
	HighScore: number,
	BestDistance: number,
	TotalCoins: number,
	TotalRuns: number,
	LongestSurvival: number,
	BrainrotsRescued: number,
	TotalDistance: number,
}

export type Profile = {
	Version: number,
	Coins: number,
	Brainrots: { [string]: number }, -- brainrotId -> copies rescued
	Collection: { [string]: boolean }, -- brainrotId -> ever rescued
	Pedestals: number, -- Brainrot pedestals on your base
	Upgrades: { [string]: number }, -- powerUpId -> level 0..5
	Hoverboards: number,
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
	local upgrades = {}
	for _, p in PowerUpData.List do
		upgrades[p.id] = 0
	end
	return {
		Version = 2,
		Coins = Config.Economy.StartingCoins,
		Brainrots = { [BrainrotData.StarterId] = 1 },
		Collection = { [BrainrotData.StarterId] = true },
		Pedestals = Config.Score.StartingPedestals,
		Upgrades = upgrades,
		Hoverboards = Config.Economy.StartingHoverboards,
		Secrets = {},
		Stats = {
			HighScore = 0,
			BestDistance = 0,
			TotalCoins = 0,
			TotalRuns = 0,
			LongestSurvival = 0,
			BrainrotsRescued = 0,
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

-- v1 saves (crates, equipment, buddies, base income) → v2.
local OBSOLETE = { "Inventory", "Crates", "Loadout", "Buddy", "PendingIncome", "LastOnline" }
local function migrate(data: any): any
	for _, key in OBSOLETE do
		data[key] = nil
	end
	if (data.Version or 1) < 2 then
		data.Version = 2
		data.Pedestals = Config.Score.StartingPedestals
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
	best.Name = "High Score"
	best.Parent = folder
	local multiplier = Instance.new("StringValue")
	multiplier.Name = "Multiplier"
	multiplier.Parent = folder
	folder.Parent = player
end

-- ───────────────────────────── score multiplier ─────────────────────────────

-- Brainrots standing on the base's pedestals, best bonus first. Every rescued
-- copy can take a pedestal.
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
		if da.bonus ~= db.bonus then
			return da.bonus > db.bonus
		end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(#copies, profile.Pedestals) do
		out[i] = copies[i]
	end
	return out
end

-- 1 + the bonus of every Brainrot on a pedestal.
function PlayerData.Multiplier(profile: Profile): number
	local total = Config.Score.BaseMultiplier
	for _, id in PlayerData.DisplayedBrainrots(profile) do
		total += (BrainrotData.Get(id) :: BrainrotData.Brainrot).bonus
	end
	return total
end

-- ───────────────────────────── access ─────────────────────────────

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

function PlayerData.Snapshot(player: Player): any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return {
		Coins = profile.Coins,
		Brainrots = profile.Brainrots,
		Collection = profile.Collection,
		Pedestals = profile.Pedestals,
		Displayed = PlayerData.DisplayedBrainrots(profile),
		Multiplier = PlayerData.Multiplier(profile),
		Upgrades = profile.Upgrades,
		Hoverboards = profile.Hoverboards,
		Stats = profile.Stats,
		Daily = profile.Daily,
		Today = math.floor(os.time() / 86400),
	}
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
	local folder = player:FindFirstChild("leaderstats")
	if folder then
		local best = folder:FindFirstChild("High Score") :: IntValue?
		local multiplier = folder:FindFirstChild("Multiplier") :: StringValue?
		if best then
			best.Value = math.floor(profile.Stats.HighScore)
		end
		if multiplier then
			multiplier.Value = "x" .. PlayerData.Multiplier(profile)
		end
	end
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

function PlayerData.GrantBrainrot(player: Player, id: string, count: number?)
	local profile = profiles[player]
	if not profile or not BrainrotData.Get(id) then
		return
	end
	profile.Brainrots[id] = (profile.Brainrots[id] or 0) + (count or 1)
	profile.Collection[id] = true
	PlayerData.Changed(player)
end

-- ───────────────────────────── saving ─────────────────────────────

function PlayerData.Save(player: Player)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	local dataStore = store :: DataStore
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
			profile = if data then reconcile(migrate(data), newProfile()) else newProfile()
		end
	else
		profile = newProfile()
	end

	if not player.Parent then
		return
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
