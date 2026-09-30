--!strict
-- Global leaderboards (OrderedDataStores) shown on the giant lobby board,
-- which cycles through categories, and in the leaderboard NPC's panel.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local PlayerData = require(script.Parent.PlayerData)

local Leaderboards = {}

export type Entry = { rank: number, name: string, value: number }

Leaderboards.Categories = {
	{ stat = "HighScore", title = "🏆 HIGH SCORES", suffix = "" },
	{ stat = "BestDistance", title = "📏 FURTHEST RUNS", suffix = "m" },
	{ stat = "BrainrotsRescued", title = "🧠 BRAINROTS RESCUED", suffix = "" },
	{ stat = "TotalCoins", title = "🪙 MOST COINS", suffix = "" },
	{ stat = "TotalRuns", title = "🏃 MOST RUNS", suffix = "" },
}

local TOP_N = 10
local REFRESH_INTERVAL = 90

local cache: { [string]: { Entry } } = {}
local stores: { [string]: OrderedDataStore } = {}
local nameCache: { [number]: string } = {}
local storesAvailable = true

local function storeFor(stat: string): OrderedDataStore?
	if not storesAvailable then
		return nil
	end
	if stores[stat] then
		return stores[stat]
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("Leaderboard_" .. stat)
	end)
	if not ok then
		storesAvailable = false
		return nil
	end
	stores[stat] = store
	return store
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("Player" .. userId)
	nameCache[userId] = result
	return result
end

-- Fallback when DataStores are unavailable: rank the players in this server.
local function localEntries(stat: string): { Entry }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.Get(player)
		if profile then
			table.insert(rows, { name = player.Name, value = (profile.Stats :: any)[stat] or 0 })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	local entries = {}
	for i = 1, math.min(TOP_N, #rows) do
		table.insert(entries, { rank = i, name = rows[i].name, value = rows[i].value })
	end
	return entries
end

local function fetch(stat: string): { Entry }
	local store = storeFor(stat)
	if not store then
		return localEntries(stat)
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		storesAvailable = false
		return localEntries(stat)
	end
	local entries = {}
	for i, row in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(string.match(row.key, "%d+")) or 0
		table.insert(entries, { rank = i, name = nameFor(userId), value = row.value })
	end
	return entries
end

local function submit(player: Player)
	local profile = PlayerData.Get(player)
	if not profile then
		return
	end
	for _, category in Leaderboards.Categories do
		local store = storeFor(category.stat)
		if store then
			local value = math.floor((profile.Stats :: any)[category.stat] or 0)
			pcall(function()
				store:SetAsync("Player_" .. player.UserId, value)
			end)
		end
	end
end
Leaderboards.Submit = submit

local function refresh()
	for _, player in Players:GetPlayers() do
		submit(player)
	end
	for _, category in Leaderboards.Categories do
		cache[category.stat] = fetch(category.stat)
	end
end

-- Renders one category onto the physical lobby board.
local function render(screen: BasePart, categoryIndex: number)
	local category = Leaderboards.Categories[categoryIndex]
	local entries = cache[category.stat] or {}
	local lines = { ('<font color="#FFD23F">%s</font>'):format(category.title), "" }
	for _, entry in entries do
		table.insert(lines, ("%d. %s   %s%s"):format(entry.rank, entry.name, Util.FormatNumber(entry.value), category.suffix))
	end
	if #entries == 0 then
		table.insert(lines, "No runs yet. Be the first!")
	end

	local label = screen:FindFirstChild("Board") and (screen :: any).Board:FindFirstChildOfClass("TextLabel")
	if not label then
		label = Util.SurfaceLabel(screen, Enum.NormalId.Front, "", { PixelsPerStud = 20, Name = "Board" })
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.05, 0)
		padding.PaddingTop = UDim.new(0.04, 0)
		padding.Parent = label
	end
	(label :: TextLabel).Text = table.concat(lines, "\n")
end

function Leaderboards.Init()
	Remotes.Function("GetLeaderboards").OnServerInvoke = function()
		local out = {}
		for _, category in Leaderboards.Categories do
			table.insert(out, { title = category.title, suffix = category.suffix, entries = cache[category.stat] or {} })
		end
		return out
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)

	-- Cycle the big board every 8 seconds.
	task.spawn(function()
		local index = 1
		while true do
			for _, screen in CollectionService:GetTagged("LeaderboardScreen") do
				render(screen :: BasePart, index)
			end
			index = (index % #Leaderboards.Categories) + 1
			task.wait(8)
		end
	end)
end

return Leaderboards
