--!strict
-- Everything on screen during a run: the "RUN STARTING..." fade, the
-- starting-area prep card, the Sahur intro caption, 3 → 2 → 1 → RUN!, the
-- distance/coins HUD, the chase meter, equipment buttons, the revive screen
-- and the rewards screen.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EquipmentData = require(Shared.EquipmentData)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local RunController = require(script.Parent.Parent.RunController)
local UIKit = require(script.Parent.UIKit)

local RunHUD = {}

local C = UIKit.Colors
local gui: ScreenGui
local hud: Frame
local fade: Frame
local fadeText: TextLabel
local bigText: TextLabel
local eventText: TextLabel
local distanceLabel: TextLabel
local coinsLabel: TextLabel
local bestLabel: TextLabel
local chaseFill: Frame
local chaseLabel: TextLabel
local equipmentBar: Frame
local effectsLabel: TextLabel
local prepCard: Frame
local caughtPanel: Frame
local resultsPanel: Frame
local updateConnection: RBXScriptConnection? = nil
local bestDistance = 0
local equipmentButtons: { [number]: TextButton } = {}

local function tweenIn(instance: GuiObject)
	UIKit.Pop(instance)
end

-- ───────────────────────────── fade ─────────────────────────────

function RunHUD.ShowStarting()
	gui.Enabled = true
	fade.Visible = true
	fade.BackgroundTransparency = 1
	fadeText.Text = "RUN STARTING..."
	TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	tweenIn(fadeText)
end

local function hideFade()
	local tween = TweenService:Create(fade, TweenInfo.new(0.5), { BackgroundTransparency = 1 })
	tween:Play()
	fadeText.Text = ""
	tween.Completed:Once(function()
		fade.Visible = false
	end)
end

-- ───────────────────────────── big text ─────────────────────────────

function RunHUD.Big(text: string, color: Color3?, duration: number?)
	bigText.Text = text
	bigText.TextColor3 = color or C.Text
	bigText.Visible = true
	tweenIn(bigText)
	local shown = text
	task.delay(duration or 0.7, function()
		if bigText.Text == shown then
			bigText.Visible = false
		end
	end)
end

function RunHUD.Flash(text: string, color: Color3?)
	eventText.Text = text
	eventText.TextColor3 = color or C.Text
	eventText.Visible = true
	tweenIn(eventText)
	local shown = text
	task.delay(1.1, function()
		if eventText.Text == shown then
			eventText.Visible = false
		end
	end)
end

-- ───────────────────────────── equipment ─────────────────────────────

local function rebuildEquipment()
	UIKit.Clear(equipmentBar)
	table.clear(equipmentButtons)
	for _, entry in RunController.State.loadout do
		local color = EquipmentData.RarityColors[entry.rarity] or C.PanelLight
		local button = UIKit.Button({
			Text = ("%s x%d"):format(entry.icon, entry.charges),
			Size = UDim2.fromOffset(110, 70),
			BackgroundColor3 = if entry.charges > 0 then color else C.PanelLight,
			LayoutOrder = entry.slot,
		}, function()
			RunController.UseEquipment(entry.slot)
		end)
		local keyHint = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "" else ("[%d] "):format(entry.slot)
		UIKit.Label({ Text = keyHint .. entry.name, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, 2), Parent = button })
		button.Parent = equipmentBar
		equipmentButtons[entry.slot] = button
	end
end

-- ───────────────────────────── per-frame ─────────────────────────────

local function update()
	local state = RunController.State
	distanceLabel.Text = Util.FormatNumber(state.meters) .. "m"
	coinsLabel.Text = "🪙 " .. Util.FormatNumber(state.coins)
	bestLabel.Text = if state.meters > bestDistance and bestDistance > 0 then "🏆 NEW BEST!" else ("🏆 " .. Util.FormatNumber(bestDistance) .. "m")

	local ratio = math.clamp(state.gap / Config.Chase.MaxGap, 0, 1)
	chaseFill.Size = UDim2.fromScale(ratio, 1)
	local danger = state.gap < Config.Chase.DangerGap
	chaseFill.BackgroundColor3 = if danger then (if os.clock() % 0.3 < 0.15 then C.Bad else C.Gold) else C.Good
	chaseLabel.Text = if danger then "🪵 TUNG TUNG TUNG!" else "🪵 SAHUR DISTANCE"

	local t = os.clock()
	local effects = {}
	if t < state.shieldUntil then
		table.insert(effects, ("🛡️ %.0fs"):format(state.shieldUntil - t))
	end
	if t < state.magnetUntil then
		table.insert(effects, ("🧲 %.0fs"):format(state.magnetUntil - t))
	end
	if t < state.boostUntil then
		table.insert(effects, ("⚡ %.0fs"):format(state.boostUntil - t))
	end
	if t < state.doublerUntil then
		table.insert(effects, ("🪙x2 %.0fs"):format(state.doublerUntil - t))
	end
	if t < state.invulnerableUntil then
		table.insert(effects, "✨ INVINCIBLE")
	end
	effectsLabel.Text = table.concat(effects, "   ")

	for _, entry in state.loadout do
		local button = equipmentButtons[entry.slot]
		if button then
			button.Text = ("%s x%d"):format(entry.icon, entry.charges)
			button.BackgroundColor3 = if entry.charges > 0 then EquipmentData.RarityColors[entry.rarity] else C.PanelLight
		end
	end
end

-- ───────────────────────────── prep / countdown ─────────────────────────────

function RunHUD.Prepare(info: any)
	gui.Enabled = true
	hud.Visible = true
	caughtPanel.Visible = false
	resultsPanel.Visible = false
	bestDistance = info.bestDistance or 0
	hideFade()
	rebuildEquipment()

	-- Starting area card: equipment, charges, coins, distance, and who's behind you.
	UIKit.Clear(prepCard)
	UIKit.Label({ Text = "🏁 STARTING AREA", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), Parent = prepCard })
	if #info.loadout == 0 then
		UIKit.Label({ Text = "No equipment equipped", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 22), Parent = prepCard })
	end
	for _, entry in info.loadout do
		UIKit.Label({ Text = ("Slot %d: %s %s  ·  x%d charges"):format(entry.slot, entry.icon, entry.name, entry.charges), Size = UDim2.new(1, 0, 0, 22), Parent = prepCard })
	end
	UIKit.Label({ Text = ("🪙 Coins: %s"):format(Util.FormatNumber(info.bankCoins or 0)), Size = UDim2.new(1, 0, 0, 22), Parent = prepCard })
	UIKit.Label({ Text = ("📏 Run distance: 0m   ·   🏆 Best: %sm"):format(Util.FormatNumber(bestDistance)), Size = UDim2.new(1, 0, 0, 22), Parent = prepCard })
	local controls = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "Swipe ⬅️ ➡️ to change lanes · ⬆️ jump · ⬇️ roll"
		else "A/D or ←/→ lanes · W/Space jump · S roll · 1-3 equipment"
	UIKit.Label({ Text = controls, TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 20), Parent = prepCard })
	prepCard.Visible = true
	tweenIn(prepCard)

	if updateConnection then
		updateConnection:Disconnect()
	end
	updateConnection = RunService.RenderStepped:Connect(update)
end

-- Runs the intro caption and 3 → 2 → 1 → RUN! against the server's go time.
function RunHUD.Countdown(goClock: number, onGo: () -> ())
	task.spawn(function()
		local step = Config.Run.CountdownStep
		RunHUD.Big("🪵 TUNG TUNG TUNG SAHUR 🪵", Color3.fromRGB(255, 200, 120), Config.Run.IntroDuration - 0.2)
		for i = 3, 1, -1 do
			local at = goClock - step * i
			local wait = at - os.clock()
			if wait > 0 then
				task.wait(wait)
			end
			RunHUD.Big(tostring(i), C.Gold, step * 0.9)
		end
		local wait = goClock - os.clock()
		if wait > 0 then
			task.wait(wait)
		end
		prepCard.Visible = false
		RunHUD.Big("RUN!", C.Good, 0.8)
		onGo()
	end)
end

-- ───────────────────────────── caught / revive ─────────────────────────────

function RunHUD.ShowCaught(info: any)
	UIKit.Clear(caughtPanel)
	UIKit.List(nil, 10).Parent = caughtPanel
	UIKit.Padding(14).Parent = caughtPanel
	UIKit.Label({ Text = "🪵 CAUGHT BY TUNG TUNG TUNG SAHUR!", TextColor3 = C.Bad, Size = UDim2.new(1, 0, 0, 40), Parent = caughtPanel })
	local timerLabel = UIKit.Label({ Text = "", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 24), Parent = caughtPanel })
	if info.canRevive then
		UIKit.Button({
			Text = ("💪 REVIVE  🪙 %s"):format(Util.FormatNumber(info.cost)),
			Size = UDim2.new(0.8, 0, 0, 54),
			BackgroundColor3 = if info.bankCoins >= info.cost then C.Good else C.PanelLight,
		}, function()
			Remotes.Event("ChooseRevive"):FireServer("Coins")
		end).Parent = caughtPanel
		if info.robux then
			UIKit.Button({ Text = "💪 REVIVE (R$)", Size = UDim2.new(0.8, 0, 0, 48), BackgroundColor3 = C.Accent2 }, function()
				Remotes.Event("ChooseRevive"):FireServer("Robux")
			end).Parent = caughtPanel
		end
	end
	UIKit.Button({ Text = "END RUN", Size = UDim2.new(0.8, 0, 0, 48), BackgroundColor3 = C.Bad }, function()
		Remotes.Event("ChooseRevive"):FireServer(false)
	end).Parent = caughtPanel
	caughtPanel.Visible = true
	tweenIn(caughtPanel)

	local deadline = os.clock() + (info.timeout or 10)
	task.spawn(function()
		while caughtPanel.Visible and os.clock() < deadline do
			timerLabel.Text = ("Run ends in %ds"):format(math.ceil(deadline - os.clock()))
			task.wait(0.2)
		end
	end)
end

function RunHUD.HideCaught()
	caughtPanel.Visible = false
end

-- ───────────────────────────── results ─────────────────────────────

function RunHUD.ShowResults(results: any)
	caughtPanel.Visible = false
	prepCard.Visible = false
	hud.Visible = false
	UIKit.Clear(resultsPanel)
	UIKit.List(nil, 8).Parent = resultsPanel
	UIKit.Padding(16).Parent = resultsPanel
	UIKit.Label({ Text = if results.newBest then "🏆 NEW BEST RUN! 🏆" else "RUN OVER", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 44), Parent = resultsPanel })
	local rows = {
		("📏 Distance: %sm"):format(Util.FormatNumber(results.distance)),
		("🪙 Coins collected: %s"):format(Util.FormatNumber(results.coins)),
		("🏃 Distance bonus: +%s"):format(Util.FormatNumber(results.distanceBonus)),
		("💰 Total earned: %s"):format(Util.FormatNumber(results.totalCoins)),
		("⏱️ Survived: %ss  ·  💪 Revives: %d"):format(Util.FormatNumber(results.survival), results.revives),
		("🏆 Best: %sm"):format(Util.FormatNumber(results.best)),
	}
	for crateId, count in results.crates do
		table.insert(rows, ("📦 Found %d %s crate%s!"):format(count, crateId, if count == 1 then "" else "s"))
	end
	for _, b in results.caught or {} do
		table.insert(rows, ("🧠 Caught %s %s%s  (+%s/s on your base)"):format(b.icon, b.name, if b.isNew then " — NEW!" else "", Util.FormatNumber(b.income)))
	end
	for i, text in rows do
		local label = UIKit.Label({ Text = text, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i + 1, Parent = resultsPanel })
		label.TextTransparency = 1
		task.delay(0.12 * i, function()
			TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		end)
	end
	UIKit.Button({ Text = "BACK TO LOBBY", Size = UDim2.new(0.7, 0, 0, 54), BackgroundColor3 = C.Good, LayoutOrder = 100 }, function()
		Remotes.Event("LeaveResults"):FireServer()
	end).Parent = resultsPanel
	resultsPanel.Visible = true
	tweenIn(resultsPanel)
end

function RunHUD.Hide()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	gui.Enabled = false
	hud.Visible = false
	fade.Visible = false
	caughtPanel.Visible = false
	resultsPanel.Visible = false
	prepCard.Visible = false
	bigText.Visible = false
	eventText.Visible = false
end

-- ───────────────────────────── build ─────────────────────────────

function RunHUD.Init(playerGui: PlayerGui)
	gui = UIKit.New("ScreenGui", { Name = "RunHUD", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = true, DisplayOrder = 5, Parent = playerGui })

	hud = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })

	distanceLabel = UIKit.Label({ Text = "0m", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(320, 54), Parent = hud })
	coinsLabel = UIKit.Label({ Text = "🪙 0", Position = UDim2.fromOffset(20, 50), Size = UDim2.fromOffset(200, 42), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, Parent = hud })
	bestLabel = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 50), Size = UDim2.fromOffset(240, 34), TextXAlignment = Enum.TextXAlignment.Right, Parent = hud })

	-- Chase meter
	local chase = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(320, 18), BackgroundColor3 = Color3.fromRGB(40, 20, 20), Parent = hud })
	UIKit.Corner(9).Parent = chase
	UIKit.Stroke(2).Parent = chase
	chaseFill = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Good, Parent = chase })
	UIKit.Corner(9).Parent = chaseFill
	chaseLabel = UIKit.Label({ Text = "🪵 SAHUR DISTANCE", Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 18), Parent = chase })

	effectsLabel = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118), Size = UDim2.new(0.8, 0, 0, 28), TextColor3 = C.Accent2, Parent = hud })

	equipmentBar = UIKit.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(0.8, 0, 0, 70), Parent = hud })
	UIKit.List(Enum.FillDirection.Horizontal, 16).Parent = equipmentBar

	bigText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.new(0.8, 0, 0, 110), Visible = false, ZIndex = 5, Parent = gui })
	eventText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.new(0.6, 0, 0, 50), Visible = false, ZIndex = 5, Parent = gui })

	prepCard = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.55, 0),
		Size = UDim2.fromOffset(380, 230),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	UIKit.Corner(14).Parent = prepCard
	UIKit.Stroke(3, C.Gold).Parent = prepCard
	UIKit.Padding(12).Parent = prepCard
	UIKit.List(nil, 4, Enum.HorizontalAlignment.Left).Parent = prepCard

	caughtPanel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(460, 290), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 8, Parent = gui })
	UIKit.Corner(18).Parent = caughtPanel
	UIKit.Stroke(4, C.Bad).Parent = caughtPanel

	resultsPanel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 470), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 8, Parent = gui })
	UIKit.Corner(18).Parent = resultsPanel
	UIKit.Stroke(4, C.Gold).Parent = resultsPanel

	fade = UIKit.New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 50, Parent = gui })
	fadeText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.8, 0, 0, 90), ZIndex = 51, Parent = fade })

	RunController.LoadoutChanged:Connect(update)
	RunController.Event:Connect(function(text: string, color: Color3?)
		RunHUD.Flash(text, color)
	end)
end

return RunHUD
