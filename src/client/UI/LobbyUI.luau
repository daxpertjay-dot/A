--!strict
-- Lobby UI: the coin HUD, toasts, and the station panels that open when you
-- walk up to a lobby NPC/machine and press E (Crates, Shop, Loadout,
-- Collection, Leaderboard, Daily Reward, Stats).

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BiomeData = require(Shared.BiomeData)
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local CrateData = require(Shared.CrateData)
local DailyRewardData = require(Shared.DailyRewardData)
local EquipmentData = require(Shared.EquipmentData)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local UIKit = require(script.Parent.UIKit)

local LobbyUI = {}

local C = UIKit.Colors
local gui: ScreenGui
local hud: Frame
local coinsLabel: TextLabel
local toastHolder: Frame
local data: any = nil

type PanelDef = { frame: Frame, content: Frame, refresh: (arg: string?) -> () }
local panels: { [string]: PanelDef } = {}
local openName: string? = nil
local selectedSlot = 1
local revealing = false -- true while the crate reveal animation plays

-- ───────────────────────────── toasts ─────────────────────────────

function LobbyUI.Toast(text: string, color: Color3?)
	local label = UIKit.Label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 38),
		TextColor3 = color or C.Text,
		Parent = toastHolder,
	})
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
	revealing = false
	if openName then
		panels[openName].frame.Visible = false
	end
	openName = nil
end

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

LobbyUI.Close = close

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
	if openName and not revealing then
		panels[openName].refresh(nil)
	end
end

-- ───────────────────────────── crates ─────────────────────────────

local function oddsText(crate: CrateData.Crate): string
	local total = 0
	for _, w in crate.weights do
		total += w
	end
	local parts = {}
	for _, rarity in { "Common", "Rare", "Legendary" } do
		local w = crate.weights[rarity]
		if w then
			table.insert(parts, ("%s %d%%"):format(rarity, math.floor(w / total * 100 + 0.5)))
		end
	end
	return table.concat(parts, " · ")
end

local revealLayer: Frame

-- Crate reveal: a full-screen slot-machine reel that plays wherever you are.
function LobbyUI.Reveal(res: any)
	if revealing or type(res) ~= "table" or not res.itemId then
		return
	end
	revealing = true
	local overlay = UIKit.New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), Parent = revealLayer })
	local card = UIKit.Card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 360), BackgroundColor3 = C.Panel, Parent = overlay })
	local crate = CrateData.Get(res.crateId or "")
	UIKit.Label({ Text = if crate then "📦 " .. crate.name else "📦 CRATE", TextColor3 = if crate then crate.color else C.Gold, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 10), Parent = card })
	local reel = UIKit.Label({ Text = "📦", Size = UDim2.new(1, 0, 0, 130), Position = UDim2.fromOffset(0, 54), Parent = card })
	local nameLabel = UIKit.Label({ Text = "OPENING…", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 196), Parent = card })
	local detail = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 240), TextColor3 = C.Muted, Parent = card })

	-- Reel slows down before the reveal.
	local delay = 0.05
	while delay < 0.28 do
		local item = EquipmentData.Items[math.random(1, #EquipmentData.Items)]
		reel.Text = item.icon
		reel.TextColor3 = EquipmentData.RarityColors[item.rarity]
		task.wait(delay)
		delay *= 1.18
	end

	local item = EquipmentData.Get(res.itemId) :: EquipmentData.Item
	reel.Text = item.icon
	reel.TextColor3 = EquipmentData.RarityColors[item.rarity]
	UIKit.Pop(reel)
	nameLabel.Text = ("%s%s"):format(if res.isNew then "✨ NEW! " else "", item.name)
	nameLabel.TextColor3 = EquipmentData.RarityColors[item.rarity]
	detail.Text = ("%s · %s %s · Level %d%s"):format(
		string.upper(item.rarity),
		EquipmentData.AbilityIcons[item.ability],
		item.ability,
		res.level or 1,
		if res.isNew then " (auto-equipped if a slot was free)" else " — duplicate levels it up!"
	)
	UIKit.Button({ Text = "NICE!", Size = UDim2.fromOffset(180, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 290), BackgroundColor3 = C.Good }, function()
		overlay:Destroy()
		revealing = false
		refreshOpen()
	end).Parent = card
end

local busy = false
local function crateAction(fn: () -> any)
	if busy or revealing then
		return
	end
	busy = true
	local res = fn()
	busy = false
	if type(res) == "table" and res.ok and res.itemId then
		task.spawn(LobbyUI.Reveal, res)
	else
		result(res)
	end
end

local function buildCrates(content: Frame, highlight: string?)
	local row = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
	UIKit.List(Enum.FillDirection.Horizontal, 14).Parent = row
	for i, crate in CrateData.Crates do
		local owned = if data then (data.Crates[crate.id] or 0) else 0
		local card = UIKit.Card({ Size = UDim2.new(1 / 3, -10, 1, 0), LayoutOrder = i, Parent = row })
		if highlight == crate.id then
			UIKit.Stroke(5, crate.color).Parent = card
		end
		UIKit.List(nil, 6).Parent = card
		UIKit.Padding(10).Parent = card
		UIKit.Label({ Text = "📦", Size = UDim2.new(1, 0, 0.24, 0), Parent = card })
		UIKit.Label({ Text = crate.name, TextColor3 = crate.color, Size = UDim2.new(1, 0, 0, 30), Parent = card })
		UIKit.Label({ Text = oddsText(crate), TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 18), Parent = card })

		-- Buying opens it right here.
		UIKit.Button({ Text = ("BUY & OPEN  🪙 %s"):format(Util.FormatNumber(crate.coinPrice)), Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.Gold, TextColor3 = Color3.new(0, 0, 0) }, function()
			crateAction(function()
				return Remotes.Function("BuyCrate"):InvokeServer(crate.id, "Coins")
			end)
		end).Parent = card

		if crate.robuxLabel then
			local configured = crate.productKey and (Config.DeveloperProducts :: any)[crate.productKey] ~= 0
			UIKit.Button({ Text = ("BUY & OPEN  %s"):format(crate.robuxLabel), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = if configured then C.Good else C.PanelLight }, function()
				result(Remotes.Function("BuyCrate"):InvokeServer(crate.id, "Robux"))
			end).Parent = card
		end

		if owned > 0 then
			UIKit.Button({ Text = ("OPEN FREE (%d)"):format(owned), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.Accent }, function()
				crateAction(function()
					return Remotes.Function("OpenCrate"):InvokeServer(crate.id)
				end)
			end).Parent = card
		end
	end
end

-- ───────────────────────────── shop ─────────────────────────────

local function buildShop(content: Frame)
	local scroller = UIKit.Scroller(content)
	UIKit.List(nil, 10).Parent = scroller
	UIKit.Label({ Text = "📦 CRATES", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34), Parent = scroller })
	for _, crate in CrateData.Crates do
		local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 60), Parent = scroller })
		UIKit.Label({ Text = "📦 " .. crate.name, TextColor3 = crate.color, Size = UDim2.new(0.5, 0, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		UIKit.Button({ Text = "🪙 " .. Util.FormatNumber(crate.coinPrice), Size = UDim2.new(0.22, 0, 1, -16), Position = UDim2.new(0.52, 0, 0, 8), BackgroundColor3 = C.Gold, TextColor3 = Color3.new(0, 0, 0) }, function()
			result(Remotes.Function("BuyCrate"):InvokeServer(crate.id, "Coins"))
		end).Parent = row
		if crate.robuxLabel then
			UIKit.Button({ Text = crate.robuxLabel, Size = UDim2.new(0.22, 0, 1, -16), Position = UDim2.new(0.76, 0, 0, 8), BackgroundColor3 = C.Good }, function()
				result(Remotes.Function("BuyCrate"):InvokeServer(crate.id, "Robux"))
			end).Parent = row
		end
	end
	UIKit.Label({ Text = "🪙 COIN PACKS", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34), Parent = scroller })
	for _, pack in { { key = "CoinPackSmall", label = "🪙 2,500 COINS" }, { key = "CoinPackLarge", label = "💰 12,000 COINS" } } do
		local row = UIKit.Card({ Size = UDim2.new(1, -12, 0, 60), Parent = scroller })
		UIKit.Label({ Text = pack.label, Size = UDim2.new(0.6, 0, 1, -16), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		UIKit.Button({ Text = "BUY (R$)", Size = UDim2.new(0.3, 0, 1, -16), Position = UDim2.new(0.68, 0, 0, 8), BackgroundColor3 = C.Good }, function()
			result(Remotes.Function("BuyCoinPack"):InvokeServer(pack.key))
		end).Parent = row
	end
	UIKit.Label({ Text = "Tip: crates also drop from 💥 BONUS vaults during runs!", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 24), Parent = scroller })
end

-- ───────────────────────────── loadout ─────────────────────────────

local function buildLoadout(content: Frame)
	local unlocked = if data then data.UnlockedSlots else 1
	local left = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.36, 0, 1, 0), Parent = content })
	UIKit.List(nil, 10).Parent = left
	UIKit.Label({ Text = "LOADOUT", TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 32), Parent = left })
	for slot = 1, 3 do
		local itemId = if data then data.Loadout[slot] else ""
		local item = EquipmentData.Get(itemId)
		local isLocked = slot > unlocked
		local text
		if isLocked then
			text = ("🔒 Slot %d — unlocks after %d runs"):format(slot, Config.LoadoutSlotUnlocks[slot])
		elseif item then
			local level = EquipmentData.LevelFromCount(data.Inventory[item.id] or 1)
			text = ("Slot %d: %s %s  (x%d)"):format(slot, item.icon, item.name, EquipmentData.ChargesAt(item, level))
		else
			text = ("Slot %d: ➕ empty"):format(slot)
		end
		local button = UIKit.Button({
			Text = text,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = if isLocked then C.PanelLight elseif slot == selectedSlot then C.Accent else Color3.fromRGB(90, 70, 140),
		}, function()
			if not isLocked then
				selectedSlot = slot
				refreshOpen()
			end
		end)
		button.Parent = left
	end
	UIKit.Button({ Text = "UNEQUIP SLOT", Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.Bad }, function()
		result(Remotes.Function("EquipItem"):InvokeServer(selectedSlot, ""))
	end).Parent = left
	UIKit.Label({ Text = "Select a slot, then pick equipment →", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 20), Parent = left })

	local right = UIKit.Scroller(content, { Size = UDim2.new(0.62, 0, 1, 0), Position = UDim2.fromScale(0.38, 0) })
	UIKit.New("UIGridLayout", { CellSize = UDim2.fromOffset(150, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = right })
	local owned = {}
	for _, item in EquipmentData.Items do
		if data and (data.Inventory[item.id] or 0) > 0 then
			table.insert(owned, item)
		end
	end
	table.sort(owned, function(a, b)
		return EquipmentData.RarityOrder[a.rarity] > EquipmentData.RarityOrder[b.rarity]
	end)
	for i, item in owned do
		local level = EquipmentData.LevelFromCount(data.Inventory[item.id])
		local equippedSlot = table.find(data.Loadout, item.id)
		local card = UIKit.New("TextButton", { Text = "", BackgroundColor3 = C.PanelLight, LayoutOrder = i, AutoButtonColor = true, Parent = right })
		UIKit.Corner(12).Parent = card
		UIKit.Stroke(3, EquipmentData.RarityColors[item.rarity]).Parent = card
		UIKit.Label({ Text = item.icon, Size = UDim2.new(1, 0, 0.42, 0), Parent = card })
		UIKit.Label({ Text = item.name, Size = UDim2.new(1, -8, 0, 24), Position = UDim2.new(0, 4, 0.44, 0), TextColor3 = EquipmentData.RarityColors[item.rarity], Parent = card })
		UIKit.Label({ Text = ("Lv %d · x%d charges"):format(level, EquipmentData.ChargesAt(item, level)), Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0.63, 0), TextColor3 = C.Muted, Parent = card })
		UIKit.Label({ Text = if equippedSlot then ("✅ SLOT %d"):format(equippedSlot) else "", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0.8, 0), TextColor3 = C.Good, Parent = card })
		card.Activated:Connect(function()
			result(Remotes.Function("EquipItem"):InvokeServer(selectedSlot, item.id), ("Equipped %s %s"):format(item.icon, item.name))
		end)
	end
	if #owned == 0 then
		UIKit.Label({ Text = "No equipment yet — open crates!", Parent = right })
	end
end

-- ───────────────────────────── collection ─────────────────────────────

local function whereToFind(brainrotId: string): string
	local names = {}
	for _, biome in BiomeData.WhereToFind(brainrotId) do
		table.insert(names, biome.icon .. " " .. biome.name)
	end
	return if #names > 0 then "Catch in: " .. table.concat(names, ", ") else "???"
end

-- Brainrots: what you own, what they earn on your base, and which one is
-- your run buddy.
local function buildBrainrots(content: Frame)
	local owned = if data then data.Brainrots else {}
	local found = 0
	for _, b in BrainrotData.List do
		if (owned[b.id] or 0) > 0 then
			found += 1
		end
	end
	UIKit.Label({
		Text = ("🧠 %d / %d owned   ·   💰 base income +%s/s   ·   🤝 buddy: %s"):format(
			found,
			#BrainrotData.List,
			Util.FormatNumber(if data then data.IncomePerSecond else 0),
			if data and BrainrotData.Get(data.Buddy) then (BrainrotData.Get(data.Buddy) :: any).name else "none"
		),
		TextColor3 = C.Gold,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = content,
	})
	UIKit.Label({ Text = ("Your best %d Brainrots stand on your base and earn coins. Catch more in runs!"):format(Config.Plot.Pedestals), TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 30), Parent = content })
	local grid = UIKit.Scroller(content, { Size = UDim2.new(1, 0, 1, -56), Position = UDim2.fromOffset(0, 56) })
	UIKit.New("UIGridLayout", { CellSize = UDim2.fromOffset(170, 220), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, b in BrainrotData.List do
		local count = owned[b.id] or 0
		local have = count > 0
		local isBuddy = data and data.Buddy == b.id
		local rarityColor = BrainrotData.RarityColors[b.rarity] or C.Gold
		local card = UIKit.Card({ LayoutOrder = i, Parent = grid })
		if isBuddy then
			UIKit.Stroke(4, C.Gold).Parent = card
		end
		UIKit.Label({ Text = if have then b.icon else "❓", Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 6), Parent = card })
		UIKit.Label({ Text = if have then ("%s  x%d"):format(b.name, count) else "???", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 64), Parent = card })
		UIKit.Label({ Text = string.upper(b.rarity), Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 88), TextColor3 = rarityColor, Parent = card })
		UIKit.Label({ Text = ("💰 +%s/s each"):format(Util.FormatNumber(b.income)), Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 108), TextColor3 = C.Good, Parent = card })
		UIKit.Label({ Text = "🤝 " .. b.perkText, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 130), TextColor3 = C.Accent2, TextWrapped = true, Parent = card })
		if isBuddy then
			UIKit.Label({ Text = "✅ RUN BUDDY", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 176), TextColor3 = C.Gold, Parent = card })
		elseif have then
			UIKit.Button({ Text = "SET AS BUDDY", Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 176), BackgroundColor3 = C.Accent }, function()
				result(Remotes.Function("SetBuddy"):InvokeServer(b.id), ("🤝 %s will run with you!"):format(b.name))
			end).Parent = card
		else
			UIKit.Label({
				Text = whereToFind(b.id),
				Size = UDim2.new(1, -10, 0, 30),
				Position = UDim2.fromOffset(5, 176),
				TextColor3 = C.Muted,
				TextWrapped = true,
				Parent = card,
			})
		end
	end
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
		for _, count in data.Brainrots do
			if count > 0 then
				found += 1
			end
		end
	end
	local rows = {
		{ "🏆 Best Distance", Util.FormatNumber(stats.BestDistance or 0) .. "m" },
		{ "🛣️ Total Distance", Util.FormatNumber(stats.TotalDistance or 0) .. "m" },
		{ "🏃 Total Runs", Util.FormatNumber(stats.TotalRuns or 0) },
		{ "⏱️ Longest Survival", Util.FormatNumber(stats.LongestSurvival or 0) .. "s" },
		{ "🪙 Coins Earned", Util.FormatNumber(stats.TotalCoins or 0) },
		{ "⚡ Equipment Collected", Util.FormatNumber(stats.EquipmentCollected or 0) },
		{ "🧠 Brainrots Owned", ("%d / %d"):format(found, #BrainrotData.List) },
		{ "💰 Base Income", "+" .. Util.FormatNumber(if data then data.IncomePerSecond else 0) .. "/s" },
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

local incomeLabel: TextLabel
local crateBadge: TextLabel

function LobbyUI.SetData(snapshot: any)
	if not snapshot then
		return
	end
	data = snapshot
	coinsLabel.Text = "🪙 " .. Util.FormatNumber(snapshot.Coins)
	incomeLabel.Text = ("💰 +%s/s on your base"):format(Util.FormatNumber(snapshot.IncomePerSecond or 0))
	local crates = 0
	for _, n in snapshot.Crates do
		crates += n
	end
	crateBadge.Text = tostring(crates)
	crateBadge.Visible = crates > 0
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
	local wallet = UIKit.New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, Position = UDim2.fromOffset(16, 60), Size = UDim2.fromOffset(250, 84), Parent = hud })
	UIKit.Corner(14).Parent = wallet
	UIKit.Stroke(3, C.Gold).Parent = wallet
	UIKit.Padding(8).Parent = wallet
	UIKit.List(nil, 4, Enum.HorizontalAlignment.Left).Parent = wallet
	coinsLabel = UIKit.Label({ Text = "🪙 …", Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, Parent = wallet })
	incomeLabel = UIKit.Label({ Text = "💰 …", Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Good, Parent = wallet })

	-- Big simulator-style buttons down the left side: everything opens from anywhere.
	local bar = UIKit.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.55, 0), Size = UDim2.fromOffset(170, 470), Parent = hud })
	UIKit.New("UIGridLayout", { CellSize = UDim2.fromOffset(80, 80), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	local buttons = {
		{ "📦\nCRATES", "Crates", C.Accent2 },
		{ "⚙️\nGEAR", "Loadout", Color3.fromRGB(120, 120, 160) },
		{ "🧠\nBRAINROTS", "Brainrots", C.Accent },
		{ "🛒\nSHOP", "Shop", C.Good },
		{ "🎁\nDAILY", "Daily", C.Bad },
		{ "🏆\nTOP", "Leaderboard", C.Gold },
		{ "📊\nSTATS", "Stats", Color3.fromRGB(90, 160, 255) },
		{ "🏠\nMY BASE", "", Color3.fromRGB(255, 150, 60) },
	}
	for i, def in buttons do
		local button = UIKit.Button({ Text = def[1], LayoutOrder = i, BackgroundColor3 = def[3], Size = UDim2.fromOffset(80, 80) }, function()
			if def[2] == "" then
				close()
				Remotes.Event("GoToBase"):FireServer()
			elseif openName == def[2] then
				close()
			else
				LobbyUI.Open(def[2])
			end
		end)
		button.Parent = bar
		if def[2] == "Crates" then
			crateBadge = UIKit.Label({ Text = "0", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 0, BackgroundColor3 = C.Bad, ZIndex = 3, Parent = button })
			UIKit.Corner(14).Parent = crateBadge
		end
	end

	UIKit.Label({
		Text = "🏃 Walk into the portal at the back of <b>your base</b> to run!",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0.6, 0, 0, 28),
		Parent = hud,
	})

	toastHolder = UIKit.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.new(0.6, 0, 0, 200), ZIndex = 20, Parent = gui })
	UIKit.List(nil, 4).Parent = toastHolder

	definePanel("Crates", "📦 EQUIPMENT CRATES", buildCrates)
	definePanel("Shop", "🛒 BRAINROT SHOP", function(content)
		buildShop(content)
	end)
	definePanel("Loadout", "⚙️ EQUIPMENT", function(content)
		buildLoadout(content)
	end)
	definePanel("Brainrots", "🧠 MY BRAINROTS", function(content)
		buildBrainrots(content)
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

	-- Crate reveals sit above everything else.
	revealLayer = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = UIKit.New("ScreenGui", { Name = "CrateReveal", ResetOnSpawn = false, DisplayOrder = 20, Parent = playerGui }) })

	-- World stations (crate stands, buddy pad, equipment stands…) open panels too.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local panel = prompt:GetAttribute("OpenPanel")
		if panel then
			LobbyUI.Open(panel, prompt:GetAttribute("PanelArg"))
		end
	end)
end

return LobbyUI
