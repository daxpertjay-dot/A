--!strict
-- Lobby UI: wallet (coins · score multiplier · hoverboards), toasts, the big
-- buttons down the left side, and the panels they open: Upgrades, Brainrots,
-- Shop, Daily reward, Leaderboards and Stats. The same panels also open from
-- the world (upgrade stall, locked pedestals, leaderboard…).

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local DailyRewardData = require(Shared.DailyRewardData)
local MutationData = require(Shared.MutationData)
local PowerUpData = require(Shared.PowerUpData)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local UIKit = require(script.Parent.UIKit)

local LobbyUI = {}

local C = UIKit.Colors
local gui: ScreenGui
local hud: Frame
local coinsLabel: TextLabel
local multiplierLabel: TextLabel
local boardsLabel: TextLabel
local hypeLabel: TextLabel
local toastHolder: Frame
local data: any = nil

type PanelDef = { frame: Frame, content: Frame, refresh: (arg: string?) -> () }
local panels: { [string]: PanelDef } = {}
local openName: string? = nil

-- ───────────────────────────── toasts ─────────────────────────────

function LobbyUI.Toast(text: string, color: Color3?)
	local label = UIKit.Label({ Text = text, Size = UDim2.new(1, 0, 0, 38), TextColor3 = color or C.Text, Parent = toastHolder })
	UIKit.Pop(label)
	task.delay(2.6, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		label:Destroy()
	end)
end

local function result(res: any, successText: string?)
	if type(res) ~= "table" then
		return
	end
	if res.ok and successText then
		LobbyUI.Toast(successText, C.Good)
	elseif not res.ok and res.message then
		LobbyUI.Toast(res.message, C.Bad)
	end
end

-- ───────────────────────────── panel plumbing ─────────────────────────────

local function close()
	if openName then
		panels[openName].frame.Visible = false
	end
	openName = nil
end
LobbyUI.Close = close

function LobbyUI.Open(name: string, arg: string?)
	local panel = panels[name]
	if not panel then
		return
	end
	close()
	openName = name
	panel.frame.Visible = true
	UIKit.Pop(panel.frame)
	panel.refresh(arg)
end

local function definePanel(name: string, title: string, refresh: (content: Frame, arg: string?) -> ())
	local frame, content = UIKit.Panel(gui, title, UDim2.fromScale(0.9, 0.82), close)
	panels[name] = {
		frame = frame,
		content = content,
		refresh = function(arg)
			UIKit.Clear(content)
			refresh(content, arg)
		end,
	}
end

local function refreshOpen()
	if openName then
		panels[openName].refresh(nil)
	end
end

local function coins(): number
	return if data then data.Coins else 0
end

-- ───────────────────────────── upgrades ─────────────────────────────

local function levelPips(level: number): string
	local out = {}
	for i = 1, PowerUpData.MaxLevel do
		table.insert(out, if i <= level then "■" else "□")
	end
	return table.concat(out, " ")
end

local function buildUpgrades(content: Frame)
	local scroller = UIKit.Scroller(content)
	UIKit.List(nil, 10).Parent = scroller
	UIKit.Label({ Text = ("🪙 %s coins to spend"):format(Util.FormatNumber(coins())), TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), Parent = scroller })

	-- Power-ups: longer and longer with each level (Subway Surfers style)
	for i, p in PowerUpData.List do
		local level = if data then (data.Upgrades[p.id] or 0) else 0
		local cost = PowerUpData.NextCost(level)
		local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 78), LayoutOrder = i + 1, Parent = scroller })
		UIKit.Label({ Text = p.icon, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 7), Parent = row })
		UIKit.Label({ Text = p.name, Size = UDim2.new(0.5, -80, 0, 26), Position = UDim2.fromOffset(80, 8), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = p.color, Parent = row })
		UIKit.Label({
			Text = ("%s   %ss → %ss"):format(levelPips(level), tostring(PowerUpData.Duration(p.id, level)), tostring(PowerUpData.Duration(p.id, math.min(level + 1, PowerUpData.MaxLevel)))),
			Size = UDim2.new(0.5, -80, 0, 20),
			Position = UDim2.fromOffset(80, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Muted,
			Parent = row,
		})
		UIKit.Label({ Text = p.description, Size = UDim2.new(0.5, -80, 0, 16), Position = UDim2.fromOffset(80, 56), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Muted, Parent = row })
		UIKit.Button({
			Text = if cost then ("⬆️ 🪙 %s"):format(Util.FormatNumber(cost)) else "MAXED",
			Size = UDim2.new(0.3, 0, 0, 50),
			Position = UDim2.new(0.68, 0, 0, 14),
			BackgroundColor3 = if cost and coins() >= cost then C.Good else C.PanelLight,
		}, function()
			if cost then
				result(Remotes.Function("BuyUpgrade"):InvokeServer(p.id), ("%s upgraded!"):format(p.name))
			end
		end).Parent = row
	end

	-- Pedestals: room for more Brainrots = a higher multiplier ceiling
	local pedestals = if data then data.Pedestals else Config.Score.StartingPedestals
	local pedestalCost = if pedestals < Config.Score.MaxPedestals then Config.Score.PedestalCosts[pedestals - Config.Score.StartingPedestals + 1] else nil
	local pRow = UIKit.Card({ Size = UDim2.new(1, -12, 0, 78), LayoutOrder = 20, Parent = scroller })
	UIKit.Label({ Text = "🏛️", Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 7), Parent = pRow })
	UIKit.Label({ Text = ("Brainrot Pedestals  %d / %d"):format(pedestals, Config.Score.MaxPedestals), Size = UDim2.new(0.6, -80, 0, 26), Position = UDim2.fromOffset(80, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, Parent = pRow })
	UIKit.Label({ Text = "More pedestals = more Brainrots boosting your multiplier.", Size = UDim2.new(0.6, -80, 0, 18), Position = UDim2.fromOffset(80, 42), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Muted, Parent = pRow })
	UIKit.Button({
		Text = if pedestalCost then ("➕ 🪙 %s"):format(Util.FormatNumber(pedestalCost)) else "FULL",
		Size = UDim2.new(0.3, 0, 0, 50),
		Position = UDim2.new(0.68, 0, 0, 14),
		BackgroundColor3 = if pedestalCost and coins() >= pedestalCost then C.Good else C.PanelLight,
	}, function()
		if pedestalCost then
			result(Remotes.Function("BuyPedestal"):InvokeServer(), "🏛️ New pedestal on your base!")
		end
	end).Parent = pRow

	-- Hoverboards
	local hRow = UIKit.Card({ Size = UDim2.new(1, -12, 0, 78), LayoutOrder = 21, Parent = scroller })
	UIKit.Label({ Text = "🛹", Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 7), Parent = hRow })
	UIKit.Label({ Text = ("Hoverboards  (you have %d)"):format(if data then data.Hoverboards else 0), Size = UDim2.new(0.6, -80, 0, 26), Position = UDim2.fromOffset(80, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(120, 200, 255), Parent = hRow })
	UIKit.Label({ Text = ("Ride for %ds; saves you from one crash. Press E / double-tap."):format(Config.PowerUps.HoverboardDuration), Size = UDim2.new(0.6, -80, 0, 18), Position = UDim2.fromOffset(80, 42), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Muted, Parent = hRow })
	UIKit.Button({
		Text = ("BUY 🪙 %s"):format(Util.FormatNumber(Config.Economy.HoverboardCost)),
		Size = UDim2.new(0.3, 0, 0, 50),
		Position = UDim2.new(0.68, 0, 0, 14),
		BackgroundColor3 = if coins() >= Config.Economy.HoverboardCost then C.Good else C.PanelLight,
	}, function()
		result(Remotes.Function("BuyHoverboards"):InvokeServer("Coins"), "🛹 +1 hoverboard!")
	end).Parent = hRow
end

-- ───────────────────────────── brainrots ─────────────────────────────

local function buildBrainrots(content: Frame)
	local owned = if data then data.Brainrots else {}
	local displayed = if data then data.Displayed else {}
	local pedestals = if data then data.Pedestals else 0
	local xpTable = if data then data.BrainrotXP or {} else {}
	UIKit.Label({
		Text = ("⭐ SCORE MULTIPLIER %s   ·   🏛️ %d / %d pedestals used"):format(Progression.FormatMultiplier(if data then data.Multiplier else 1), #displayed, pedestals),
		TextColor3 = C.Gold,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = content,
	})
	UIKit.Label({
		Text = ("Rescue Brainrots from %s's cages on runs. Your best ones stand on your pedestals and add to your multiplier — and every run's score is XP that levels them up."):format(Config.Villain.Title),
		TextColor3 = C.Muted,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 32),
		Parent = content,
	})
	local odds = {}
	for _, m in MutationData.List do
		table.insert(odds, ("%s %s x%d (%s%%)"):format(m.icon, m.name, m.multiplier, ("%g"):format(m.chance * 100)))
	end
	UIKit.Label({ Text = "Mutations:  " .. table.concat(odds, "   "), TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 68), Parent = content })
	local grid = UIKit.Scroller(content, { Size = UDim2.new(1, 0, 1, -94), Position = UDim2.fromOffset(0, 94) })
	UIKit.New("UIGridLayout", { CellSize = UDim2.fromOffset(170, 222), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	-- Owned copies per Brainrot kind, and which mutations of it you have.
	local onPedestal: { [string]: number } = {}
	for _, key in displayed do
		local id = MutationData.Split(key)
		onPedestal[id] = (onPedestal[id] or 0) + 1
	end
	local counts: { [string]: number } = {}
	local variants: { [string]: { [string]: number } } = {}
	for key, n in owned do
		local id, mutation = MutationData.Split(key)
		counts[id] = (counts[id] or 0) + n
		if mutation and n > 0 then
			variants[id] = variants[id] or {}
			variants[id][mutation] = (variants[id][mutation] or 0) + n
		end
	end
	for i, b in BrainrotData.List do
		local count = counts[b.id] or 0
		local have = count > 0
		local rarityColor = BrainrotData.RarityColors[b.rarity] or C.Gold
		local card = UIKit.Card({ LayoutOrder = i, Parent = grid })
		if (onPedestal[b.id] or 0) > 0 then
			UIKit.Stroke(4, C.Gold).Parent = card
		end
		UIKit.Label({ Text = if have then b.icon else "❓", Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 6), Parent = card })
		UIKit.Label({ Text = if have then ("%s  x%d"):format(b.name, count) else "???", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 64), Parent = card })
		local mutationText = ""
		for _, m in MutationData.List do
			local n = variants[b.id] and variants[b.id][m.id]
			if n then
				mutationText ..= (" %s%d"):format(m.icon, n)
			end
		end
		UIKit.Label({ Text = string.upper(b.rarity) .. mutationText, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 88), TextColor3 = rarityColor, Parent = card })
		local level, into, need = Progression.Level(xpTable[b.id])
		UIKit.Label({
			Text = if have then ("Lv %d  ·  ⭐ +%s"):format(level, Progression.FormatMultiplier(Progression.BonusAt(b.id, level))) else ("⭐ +%s multiplier"):format(Progression.FormatMultiplier(b.bonus)),
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 110),
			TextColor3 = C.Good,
			Parent = card,
		})
		if have then
			-- XP bar towards the next level
			local track = UIKit.New("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 40), Position = UDim2.new(0, 10, 0, 136), Size = UDim2.new(1, -20, 0, 10), Parent = card })
			UIKit.Corner(5).Parent = track
			local fill = UIKit.New("Frame", { BackgroundColor3 = Color3.fromRGB(190, 150, 255), Size = UDim2.fromScale(if need then math.clamp(into / need, 0, 1) else 1, 1), Parent = track })
			UIKit.Corner(5).Parent = fill
			UIKit.Label({ Text = if need then ("%s / %s XP"):format(Util.FormatNumber(into), Util.FormatNumber(need)) else "MAX LEVEL", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 148), TextColor3 = C.Muted, Parent = card })
		end
		local status
		if b.catchWeight == 0 then
			status = ("%s's henchman — can't be rescued"):format(Config.Villain.Title)
		elseif not have then
			status = ("Rescue it on runs after %dm"):format(b.minDistance)
		elseif (onPedestal[b.id] or 0) > 0 then
			status = ("✅ On %d pedestal%s"):format(onPedestal[b.id], if onPedestal[b.id] == 1 then "" else "s")
		else
			status = "Not on a pedestal — buy more!"
		end
		UIKit.Label({ Text = status, Size = UDim2.new(1, -10, 0, 40), Position = UDim2.fromOffset(5, 170), TextColor3 = C.Muted, TextWrapped = true, Parent = card })
	end
end

-- ───────────────────────────── shop ─────────────────────────────

local function buildShop(content: Frame)
	local scroller = UIKit.Scroller(content)
	UIKit.List(nil, 10).Parent = scroller
	UIKit.Label({ Text = "🛹 HOVERBOARDS", TextColor3 = Color3.fromRGB(120, 200, 255), Size = UDim2.new(1, 0, 0, 30), Parent = scroller })
	local boards = UIKit.Card({ Size = UDim2.new(1, -12, 0, 60), Parent = scroller })
	UIKit.Label({ Text = ("🛹 You have %d"):format(if data then data.Hoverboards else 0), Size = UDim2.new(0.4, 0, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = boards })
	UIKit.Button({ Text = ("+1  🪙 %s"):format(Util.FormatNumber(Config.Economy.HoverboardCost)), Size = UDim2.new(0.26, 0, 1, -16), Position = UDim2.new(0.44, 0, 0, 8), BackgroundColor3 = C.Gold, TextColor3 = Color3.new(0, 0, 0) }, function()
		result(Remotes.Function("BuyHoverboards"):InvokeServer("Coins"), "🛹 +1 hoverboard!")
	end).Parent = boards
	UIKit.Button({ Text = "+5  (R$)", Size = UDim2.new(0.26, 0, 1, -16), Position = UDim2.new(0.72, 0, 0, 8), BackgroundColor3 = C.Good }, function()
		result(Remotes.Function("BuyHoverboards"):InvokeServer("Robux"))
	end).Parent = boards

	UIKit.Label({ Text = "🪙 COIN PACKS", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), Parent = scroller })
	for _, pack in { { key = "CoinPackSmall", label = "🪙 2,500 COINS" }, { key = "CoinPackLarge", label = "💰 12,000 COINS" } } do
		local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 60), Parent = scroller })
		UIKit.Label({ Text = pack.label, Size = UDim2.new(0.6, 0, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		UIKit.Button({ Text = "BUY (R$)", Size = UDim2.new(0.3, 0, 1, -16), Position = UDim2.new(0.68, 0, 0, 8), BackgroundColor3 = C.Good }, function()
			result(Remotes.Function("BuyCoinPack"):InvokeServer(pack.key))
		end).Parent = row
	end
	UIKit.Label({ Text = "Spend coins on power-ups and pedestals in ⬆️ Upgrades.", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 22), Parent = scroller })
end

-- ───────────────────────────── leaderboard ─────────────────────────────

local leaderboardTab = 1
local function buildLeaderboard(content: Frame)
	local tabs = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = content })
	UIKit.List(Enum.FillDirection.Horizontal, 6).Parent = tabs
	local list = UIKit.Scroller(content, { Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50) })
	UIKit.List(nil, 6).Parent = list
	UIKit.Label({ Text = "Loading…", Parent = list })

	task.spawn(function()
		local boards = Remotes.Function("GetLeaderboards"):InvokeServer()
		if type(boards) ~= "table" or not list.Parent then
			return
		end
		for i, board in boards do
			UIKit.Button({ Text = board.title, Size = UDim2.new(1 / #boards, -6, 1, 0), BackgroundColor3 = if i == leaderboardTab then C.Accent else C.PanelLight }, function()
				leaderboardTab = i
				refreshOpen()
			end).Parent = tabs
		end
		UIKit.Clear(list)
		local board = boards[leaderboardTab]
		if not board then
			return
		end
		for _, entry in board.entries do
			local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 40), Parent = list })
			local medal = ({ "🥇", "🥈", "🥉" })[entry.rank] or ("%d."):format(entry.rank)
			UIKit.Label({ Text = ("%s  %s"):format(medal, entry.name), Size = UDim2.new(0.65, 0, 1, -10), Position = UDim2.fromOffset(12, 5), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
			UIKit.Label({ Text = Util.FormatNumber(entry.value) .. board.suffix, Size = UDim2.new(0.3, 0, 1, -10), Position = UDim2.new(0.68, 0, 0, 5), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Gold, Parent = row })
		end
		if #board.entries == 0 then
			UIKit.Label({ Text = "No runs yet. Be the first!", Parent = list })
		end
	end)
end

-- ───────────────────────────── daily ─────────────────────────────

local function buildDaily(content: Frame)
	local today = if data then data.Today else 0
	local daily = if data then data.Daily else { LastClaimDay = -1, Streak = 0 }
	local canClaim = daily.LastClaimDay ~= today
	local nextDay = if daily.LastClaimDay == today - 1 then daily.Streak + 1 else 1
	if nextDay > #DailyRewardData.Rewards then
		nextDay = 1
	end
	local claimedThrough = if canClaim then nextDay - 1 else daily.Streak

	local row = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.7, 0), Parent = content })
	UIKit.List(Enum.FillDirection.Horizontal, 8).Parent = row
	for _, reward in DailyRewardData.Rewards do
		local isToday = canClaim and reward.day == nextDay
		local claimed = reward.day <= claimedThrough
		local card = UIKit.Card({
			Size = UDim2.new(1 / 7, -8, 1, 0),
			LayoutOrder = reward.day,
			BackgroundColor3 = if isToday then C.Accent elseif claimed then Color3.fromRGB(40, 90, 60) else C.PanelLight,
			Parent = row,
		})
		UIKit.Label({ Text = ("DAY %d"):format(reward.day), Size = UDim2.new(1, 0, 0.18, 0), Parent = card })
		UIKit.Label({ Text = reward.icon, Size = UDim2.new(1, 0, 0.35, 0), Position = UDim2.fromScale(0, 0.2), Parent = card })
		UIKit.Label({ Text = reward.label, Size = UDim2.new(1, -6, 0.18, 0), Position = UDim2.new(0, 3, 0.58, 0), Parent = card })
		UIKit.Label({ Text = if claimed then "✅" elseif isToday then "TODAY!" else "🔒", Size = UDim2.new(1, 0, 0.18, 0), Position = UDim2.fromScale(0, 0.8), Parent = card })
	end
	UIKit.Button({
		Text = if canClaim then "🎁 CLAIM!" else "COME BACK TOMORROW",
		Size = UDim2.new(0.5, 0, 0, 54),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.76, 0),
		BackgroundColor3 = if canClaim then C.Good else C.PanelLight,
	}, function()
		if canClaim then
			result(Remotes.Function("ClaimDaily"):InvokeServer())
		end
	end).Parent = content
end

-- ───────────────────────────── stats ─────────────────────────────

local function buildStats(content: Frame)
	local stats = if data then data.Stats else {}
	local found = 0
	if data then
		for _, b in BrainrotData.List do
			if data.Collection[b.id] then
				found += 1
			end
		end
	end
	local rows = {
		{ "🏆 High Score", Util.FormatNumber(stats.HighScore or 0) },
		{ "⭐ Score Multiplier", Progression.FormatMultiplier(if data then data.Multiplier else 1) },
		{ "⚡ Hype", ("%d%%  (%s next run)"):format(math.floor((if data then data.Hype or 0 else 0) * 100), Progression.FormatMultiplier(Progression.HypeMultiplier(if data then data.Hype or 0 else 0))) },
		{ "📏 Furthest Run", Util.FormatNumber(stats.BestDistance or 0) .. "m" },
		{ "🔓 Brainrots Rescued", Util.FormatNumber(stats.BrainrotsRescued or 0) },
		{ "🧠 Different Brainrots", ("%d / %d"):format(found, #BrainrotData.List) },
		{ "🏃 Total Runs", Util.FormatNumber(stats.TotalRuns or 0) },
		{ "🪙 Coins Collected", Util.FormatNumber(stats.TotalCoins or 0) },
		{ "⏱️ Longest Survival", Util.FormatNumber(stats.LongestSurvival or 0) .. "s" },
	}
	local list = UIKit.Scroller(content)
	UIKit.List(nil, 8).Parent = list
	for _, r in rows do
		local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 48), Parent = list })
		UIKit.Label({ Text = r[1], Size = UDim2.new(0.6, 0, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		UIKit.Label({ Text = r[2], Size = UDim2.new(0.35, 0, 1, -12), Position = UDim2.new(0.62, 0, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Gold, Parent = row })
	end
end

-- ───────────────────────────── HUD / init ─────────────────────────────

function LobbyUI.SetData(snapshot: any)
	if not snapshot then
		return
	end
	data = snapshot
	coinsLabel.Text = "🪙 " .. Util.FormatNumber(snapshot.Coins)
	multiplierLabel.Text = ("⭐ Score multiplier %s"):format(Progression.FormatMultiplier(snapshot.Multiplier or 1))
	local hype = snapshot.Hype or 0
	if hype >= 1 then
		hypeLabel.Text = ("⚡ FULLY HYPED! %s next run"):format(Progression.FormatMultiplier(Progression.HypeMultiplier(1)))
	else
		local hoursLeft = (1 - hype) / math.max(snapshot.HypePerHour or 0.25, 1e-6)
		hypeLabel.Text = ("⚡ Hype %d%%  ·  full in %s"):format(math.floor(hype * 100), if hoursLeft >= 1 then ("%.1fh"):format(hoursLeft) else ("%dm"):format(math.max(1, math.ceil(hoursLeft * 60))))
	end
	boardsLabel.Text = ("🛹 %d hoverboard%s"):format(snapshot.Hoverboards or 0, if snapshot.Hoverboards == 1 then "" else "s")
	refreshOpen()
end

function LobbyUI.SetVisible(visible: boolean)
	hud.Visible = visible
	if not visible then
		close()
	end
end

function LobbyUI.Init(playerGui: PlayerGui)
	gui = UIKit.New("ScreenGui", { Name = "LobbyUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	hud = UIKit.New("Frame", { Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })

	-- Wallet (top left)
	local wallet = UIKit.New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, Position = UDim2.fromOffset(16, 60), Size = UDim2.fromOffset(290, 130), Parent = hud })
	UIKit.Corner(14).Parent = wallet
	UIKit.Stroke(3, C.Gold).Parent = wallet
	UIKit.Padding(8).Parent = wallet
	UIKit.List(nil, 4, Enum.HorizontalAlignment.Left).Parent = wallet
	coinsLabel = UIKit.Label({ Text = "🪙 …", Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, Parent = wallet })
	multiplierLabel = UIKit.Label({ Text = "⭐ …", Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 200, 60), Parent = wallet })
	boardsLabel = UIKit.Label({ Text = "🛹 …", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(120, 200, 255), Parent = wallet })
	hypeLabel = UIKit.Label({ Text = "⚡ …", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent2, Parent = wallet })

	-- Big simulator-style buttons down the left side.
	local bar = UIKit.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.58, 0), Size = UDim2.fromOffset(170, 360), Parent = hud })
	UIKit.New("UIGridLayout", { CellSize = UDim2.fromOffset(80, 80), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	local buttons = {
		{ "⬆️\nUPGRADES", "Upgrades", C.Good },
		{ "🧠\nBRAINROTS", "Brainrots", C.Accent },
		{ "🛒\nSHOP", "Shop", C.Accent2 },
		{ "🎁\nDAILY", "Daily", C.Bad },
		{ "🏆\nTOP", "Leaderboard", C.Gold },
		{ "📊\nSTATS", "Stats", Color3.fromRGB(90, 160, 255) },
		{ "🏠\nMY BASE", "", Color3.fromRGB(255, 150, 60) },
	}
	for i, def in buttons do
		UIKit.Button({ Text = def[1], LayoutOrder = i, BackgroundColor3 = def[3], Size = UDim2.fromOffset(80, 80) }, function()
			if def[2] == "" then
				close()
				Remotes.Event("GoToBase"):FireServer()
			elseif openName == def[2] then
				close()
			else
				LobbyUI.Open(def[2])
			end
		end).Parent = bar
	end

	UIKit.Label({
		Text = ("🏃 Walk into the portal at the back of <b>your base</b> to escape %s!"):format(Config.Villain.Title),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0.6, 0, 0, 28),
		Parent = hud,
	})

	toastHolder = UIKit.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.new(0.6, 0, 0, 200), ZIndex = 20, Parent = gui })
	UIKit.List(nil, 4).Parent = toastHolder

	definePanel("Upgrades", "⬆️ UPGRADES", function(content)
		buildUpgrades(content)
	end)
	definePanel("Brainrots", "🧠 MY BRAINROTS", function(content)
		buildBrainrots(content)
	end)
	definePanel("Shop", "🛒 SHOP", function(content)
		buildShop(content)
	end)
	definePanel("Leaderboard", "🏆 LEADERBOARDS", function(content)
		buildLeaderboard(content)
	end)
	definePanel("Daily", "🎁 DAILY REWARD", function(content)
		buildDaily(content)
	end)
	definePanel("Stats", "📊 MY STATS", function(content)
		buildStats(content)
	end)

	-- World stations (upgrade stall, locked pedestals, leaderboard…) open panels too.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local panel = prompt:GetAttribute("OpenPanel")
		if panel then
			LobbyUI.Open(panel, prompt:GetAttribute("PanelArg"))
		end
	end)
end

return LobbyUI
