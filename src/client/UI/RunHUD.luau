--!strict
-- Everything on screen during a run (Subway Surfers layout):
--
--   top-left: distance · high score      top-right: SCORE + xMULTIPLIER, coins,
--   top-centre: how close the villain is            🔥 combo and ⚡ hype meters
--   right side: active power-up timers    bottom-right: 🛹 hoverboard button
--   trick pop-ups ("NEAR MISS! +2") next to the combo meter
--
-- Plus the "RUN STARTING..." fade, countdown, revive screen and results.
-- Panels are built once in Init and only updated afterwards, so showing
-- them repeatedly can't stack up layouts.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUpData = require(Shared.PowerUpData)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)

local RunController = require(script.Parent.Parent.RunController)
local UIKit = require(script.Parent.UIKit)

local RunHUD = {}

-- Fired by "BACK TO BASE" on the results screen.
RunHUD.Leave = Signal.new()

local C = UIKit.Colors
local gui: ScreenGui
local hud: Frame
local fade: Frame
local fadeText: TextLabel
local bigText: TextLabel
local eventText: TextLabel
local scoreLabel: TextLabel
local multiplierBadge: TextLabel
local coinsLabel: TextLabel
local distanceLabel: TextLabel
local highLabel: TextLabel
local chaseFill: Frame
local chaseLabel: TextLabel
local powerBars: Frame
local hoverButton: TextButton
local tipLabel: TextLabel
local comboRow: Frame
local comboLabel: TextLabel
local comboFill: Frame
local hypeRow: Frame
local hypeLabel: TextLabel
local hypeFill: Frame
local popupHolder: Frame
local updateConnection: RBXScriptConnection? = nil
local highScore = 0

-- Revive panel pieces (built once)
local caughtPanel: Frame
local caughtScore: TextLabel
local caughtTimer: TextLabel
local caughtTimerFill: Frame
local reviveCoinsButton: TextButton
local reviveRobuxButton: TextButton
local caughtToken = 0

-- Results panel pieces (built once)
local resultsPanel: Frame
local resultsBody: ScrollingFrame

local function tweenIn(instance: GuiObject)
	UIKit.Pop(instance)
end

-- Live multipliers change every frame: keep them short (x12.3, x154).
local function shortMultiplier(n: number): string
	if n >= 100 then
		return ("x%d"):format(math.floor(n))
	end
	local s = ("%.1f"):format(n):gsub("%.0$", "")
	return "x" .. s
end

local TRICK_LABELS: { [string]: string } = {
	Clear = "NICE!",
	NearMiss = "NEAR MISS!",
	Roof = "ROOF RUN!",
	Smash = "SMASH!",
	CrashThrough = "CRASH THROUGH!",
	Coins = "COIN STREAK!",
	PowerUp = "POWER-UP!",
	MysteryBox = "LOOT!",
	Rescue = "RESCUE!",
}

-- "NEAR MISS! +2" floating up next to the combo meter.
local function trickPopup(kind: string, gained: number)
	local text = TRICK_LABELS[kind]
	if not text or gained <= 0 then
		return
	end
	local label = UIKit.Label({
		Text = ("%s  +%s"):format(text, if gained == math.floor(gained) then tostring(gained) else ("%.1f"):format(gained)),
		TextColor3 = if kind == "NearMiss" or kind == "Roof" then C.Accent2 else Color3.fromRGB(255, 170, 60),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = popupHolder,
	})
	UIKit.Pop(label)
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(1, 0, 0, -46), TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.9), { Transparency = 1 }):Play()
	end
	task.delay(0.95, function()
		label:Destroy()
	end)
end

-- ───────────────────────────── fade / text ─────────────────────────────

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
	task.delay(1.4, function()
		if eventText.Text == shown then
			eventText.Visible = false
		end
	end)
end

-- ───────────────────────────── per-frame ─────────────────────────────

local POWER_ORDER = { "Jetpack", "Magnet", "SuperSneakers", "ScoreBooster", "Hoverboard" }
local barRows: { [string]: { frame: Frame, fill: Frame } } = {}

local function powerRow(icon: string, color: Color3): { frame: Frame, fill: Frame }
	local row = UIKit.New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 34), Visible = false, Parent = powerBars })
	UIKit.Corner(10).Parent = row
	UIKit.Label({ Text = icon, Size = UDim2.fromOffset(34, 34), Parent = row })
	local track = UIKit.New("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 40), Position = UDim2.fromOffset(40, 11), Size = UDim2.new(1, -48, 0, 12), Parent = row })
	UIKit.Corner(6).Parent = track
	local fill = UIKit.New("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(1, 1), Parent = track })
	UIKit.Corner(6).Parent = fill
	return { frame = row, fill = fill }
end

local function update()
	local state = RunController.State
	local t = os.clock()
	scoreLabel.Text = Util.FormatNumber(state.score)
	local multiplier = RunController.CurrentMultiplier()
	multiplierBadge.Text = shortMultiplier(multiplier)
	multiplierBadge.BackgroundColor3 = if t < state.boosterUntil then Color3.fromRGB(80, 170, 255) else C.Accent

	-- 🔥 Combo and ⚡ Hype meters
	local stacks = state.combo.stacks
	comboRow.Visible = stacks > 0.05
	if comboRow.Visible then
		comboLabel.Text = ("🔥 COMBO %s"):format(shortMultiplier(Progression.ComboMultiplier(state.combo)))
		comboFill.Size = UDim2.fromScale(math.clamp(stacks / Config.Combo.MaxStacks, 0, 1), 1)
		local draining = t - state.combo.lastAction > Config.Combo.Grace
		comboFill.BackgroundColor3 = if draining and t % 0.4 < 0.2 then C.Bad else Color3.fromRGB(255, 140, 40)
	end
	hypeRow.Visible = state.hype > 0.001
	if hypeRow.Visible then
		hypeLabel.Text = ("⚡ HYPE %s"):format(shortMultiplier(Progression.HypeMultiplier(state.hype)))
		hypeFill.Size = UDim2.fromScale(math.clamp(state.hype, 0, 1), 1)
	end
	coinsLabel.Text = "🪙 " .. Util.FormatNumber(state.coins)
	distanceLabel.Text = Util.FormatNumber(state.meters) .. "m"
	highLabel.Text = if state.score > highScore and highScore > 0 then "🏆 NEW HIGH SCORE!" else ("🏆 " .. Util.FormatNumber(highScore))

	local ratio = math.clamp(state.gap / Config.Chase.MaxGap, 0, 1)
	chaseFill.Size = UDim2.fromScale(ratio, 1)
	local danger = state.gap < Config.Chase.DangerGap
	chaseFill.BackgroundColor3 = if danger then (if t % 0.3 < 0.15 then C.Bad else C.Gold) else C.Good
	chaseLabel.Text = if danger then ("🧠 %s IS RIGHT BEHIND YOU!"):format(Config.Villain.Title) else ("🧠 %s"):format(Config.Villain.Title)

	local timers = {
		Jetpack = state.jetpackUntil,
		Magnet = state.magnetUntil,
		SuperSneakers = state.sneakersUntil,
		ScoreBooster = state.boosterUntil,
		Hoverboard = state.hoverUntil,
	}
	for id, row in barRows do
		local left = timers[id] - t
		local duration = state.durations[id] or 1
		row.frame.Visible = left > 0
		if left > 0 then
			row.fill.Size = UDim2.fromScale(math.clamp(left / duration, 0, 1), 1)
		end
	end

	local canBoard = state.hoverboards > 0 and t >= state.hoverUntil
	hoverButton.Text = ("🛹 x%d"):format(state.hoverboards)
	hoverButton.BackgroundColor3 = if canBoard then Color3.fromRGB(80, 200, 255) else C.PanelLight
end

-- ───────────────────────────── prep / countdown ─────────────────────────────

function RunHUD.Prepare(info: any)
	gui.Enabled = true
	hud.Visible = true
	caughtPanel.Visible = false
	resultsPanel.Visible = false
	highScore = info.highScore or 0
	hideFade()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hype = info.hype or 0
	tipLabel.Text = ("⭐ Multiplier %s%s  ·  %s"):format(
		Progression.FormatMultiplier(info.multiplier or 1),
		if hype > 0.01 then ("  ·  ⚡ HYPED %s"):format(shortMultiplier(Progression.HypeMultiplier(hype))) else "",
		if touch then "swipe to move · double-tap for 🛹" else "A/D lanes · W jump · S roll · E hoverboard"
	)
	tipLabel.Visible = true

	if updateConnection then
		updateConnection:Disconnect()
	end
	updateConnection = RunService.RenderStepped:Connect(update)
end

-- 3 → 2 → 1 → RUN! against the server's go time.
function RunHUD.Countdown(goClock: number, onGo: () -> ())
	task.spawn(function()
		local step = Config.Run.CountdownStep
		for i = 3, 1, -1 do
			local wait = goClock - step * i - os.clock()
			if wait > 0 then
				task.wait(wait)
			end
			RunHUD.Big(tostring(i), C.Gold, step * 0.9)
		end
		local wait = goClock - os.clock()
		if wait > 0 then
			task.wait(wait)
		end
		tipLabel.Visible = false
		RunHUD.Big("RUN!", C.Good, 0.8)
		onGo()
	end)
end

-- ───────────────────────────── caught / revive ─────────────────────────────

function RunHUD.ShowCaught(info: any)
	caughtToken += 1
	local token = caughtToken
	caughtScore.Text = ("SCORE  %s"):format(Util.FormatNumber(info.score or RunController.State.score))
	reviveCoinsButton.Visible = info.canRevive == true
	reviveCoinsButton.Text = ("💪 SAVE ME  🪙 %s"):format(Util.FormatNumber(info.cost or 0))
	reviveCoinsButton.BackgroundColor3 = if (info.bankCoins or 0) >= (info.cost or 0) then C.Good else C.PanelLight
	reviveRobuxButton.Visible = info.canRevive == true and info.robux == true
	caughtPanel.Visible = true
	tweenIn(caughtPanel)

	local duration = info.timeout or 10
	local deadline = os.clock() + duration
	task.spawn(function()
		while caughtToken == token and caughtPanel.Visible do
			local left = deadline - os.clock()
			if left <= 0 then
				break
			end
			caughtTimer.Text = ("%ds"):format(math.ceil(left))
			caughtTimerFill.Size = UDim2.fromScale(math.clamp(left / duration, 0, 1), 1)
			task.wait(0.05)
		end
	end)
end

function RunHUD.HideCaught()
	caughtToken += 1
	caughtPanel.Visible = false
end

-- ───────────────────────────── results ─────────────────────────────

function RunHUD.ShowResults(results: any)
	RunHUD.HideCaught()
	hud.Visible = false
	tipLabel.Visible = false
	fade.Visible = false -- the run may have ended during the "RUN STARTING..." fade
	UIKit.Clear(resultsBody)
	resultsBody.CanvasPosition = Vector2.zero

	local order = 0
	local function line(text: string, color: Color3?, height: number?)
		order += 1
		local label = UIKit.Label({ Text = text, TextColor3 = color or C.Text, Size = UDim2.new(1, 0, 0, height or 26), LayoutOrder = order, Parent = resultsBody })
		label.TextTransparency = 1
		task.delay(0.1 * order, function()
			TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		end)
	end

	line(if results.newHighScore then "🏆 NEW HIGH SCORE! 🏆" else "RUN OVER", C.Gold, 36)
	line(Util.FormatNumber(results.score), C.Text, 54)
	line(("📏 %sm  ×  ⭐ %s multiplier"):format(Util.FormatNumber(results.distance), Progression.FormatMultiplier(results.multiplier)), C.Muted)
	if (results.bestCombo or 1) > 1.05 then
		line(("🔥 Best combo %s"):format(shortMultiplier(results.bestCombo)), Color3.fromRGB(255, 160, 60))
	end
	if (results.hypeStart or 0) > 0.01 then
		line(
			("⚡ Hype %s → %s"):format(shortMultiplier(Progression.HypeMultiplier(results.hypeStart)), shortMultiplier(Progression.HypeMultiplier(results.hypeLeft or 0))),
			C.Accent2
		)
	end
	line(("🪙 +%s coins"):format(Util.FormatNumber(results.totalCoins)) .. (if results.boxCoins > 0 then ("  (❓ %s from mystery boxes)"):format(Util.FormatNumber(results.boxCoins)) else ""), C.Gold)
	if results.boxBoards > 0 then
		line(("🛹 +%d hoverboard%s"):format(results.boxBoards, if results.boxBoards == 1 then "" else "s"), Color3.fromRGB(120, 200, 255))
	end
	for _, b in results.rescued do
		line(("🔓 Rescued %s %s  (+%s)%s"):format(b.icon, b.name, Progression.FormatMultiplier(b.bonus), if b.isNew then " — NEW!" else ""), Color3.fromRGB(255, 140, 230))
	end
	if (results.xp or 0) > 0 then
		line(("🧠 Your Brainrots gained +%s XP"):format(Util.FormatNumber(results.xp)), Color3.fromRGB(190, 150, 255))
	end
	for _, up in results.levelUps or {} do
		line(("⬆️ %s %s reached Lv %d!  (+%s)"):format(up.icon, up.name, up.to, Progression.FormatMultiplier(up.bonus)), C.Good)
	end
	if results.newMultiplier > results.multiplier + 0.001 then
		line(("⭐ Your multiplier is now %s!"):format(Progression.FormatMultiplier(results.newMultiplier)), Color3.fromRGB(255, 200, 60))
	elseif #results.rescued > 0 then
		line("Your pedestals are full — buy more in ⬆️ Upgrades to use them!", C.Muted)
	end
	line(("🏆 High score: %s"):format(Util.FormatNumber(results.highScore)), C.Muted)

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
	RunHUD.HideCaught()
	resultsPanel.Visible = false
	tipLabel.Visible = false
	bigText.Visible = false
	eventText.Visible = false
end

-- ───────────────────────────── build ─────────────────────────────

function RunHUD.Init(playerGui: PlayerGui)
	gui = UIKit.New("ScreenGui", { Name = "RunHUD", ResetOnSpawn = false, Enabled = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })

	hud = UIKit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })

	-- Score (top right)
	local scoreBox = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 46), Size = UDim2.fromOffset(280, 100), BackgroundTransparency = 1, Parent = hud })
	scoreLabel = UIKit.Label({ Text = "0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 0), Size = UDim2.new(1, -70, 0, 52), TextXAlignment = Enum.TextXAlignment.Right, Parent = scoreBox })
	multiplierBadge = UIKit.Label({ Text = "x1", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(84, 44), BackgroundTransparency = 0, BackgroundColor3 = C.Accent, Parent = scoreBox })
	UIKit.Corner(12).Parent = multiplierBadge
	scoreLabel.Position = UDim2.new(1, -92, 0, 0)
	scoreLabel.Size = UDim2.new(1, -92, 0, 52)
	coinsLabel = UIKit.Label({ Text = "🪙 0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 58), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Gold, Parent = scoreBox })

	-- 🔥 Combo and ⚡ Hype meters under the score
	local function meter(order: number, color: Color3): (Frame, TextLabel, Frame)
		local row = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 150 + (order - 1) * 46), Size = UDim2.fromOffset(220, 40), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, Visible = false, Parent = hud })
		UIKit.Corner(10).Parent = row
		local text = UIKit.Label({ Text = "", Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local track = UIKit.New("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 40), Position = UDim2.fromOffset(8, 27), Size = UDim2.new(1, -16, 0, 8), Parent = row })
		UIKit.Corner(4).Parent = track
		local fill = UIKit.New("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(0, 1), Parent = track })
		UIKit.Corner(4).Parent = fill
		return row, text, fill
	end
	comboRow, comboLabel, comboFill = meter(1, Color3.fromRGB(255, 140, 40))
	hypeRow, hypeLabel, hypeFill = meter(2, C.Accent2)
	popupHolder = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -244, 0, 152), Size = UDim2.fromOffset(240, 30), BackgroundTransparency = 1, Parent = hud })

	-- Distance + high score (top left)
	distanceLabel = UIKit.Label({ Text = "0m", Position = UDim2.fromOffset(20, 50), Size = UDim2.fromOffset(200, 36), TextXAlignment = Enum.TextXAlignment.Left, Parent = hud })
	highLabel = UIKit.Label({ Text = "", Position = UDim2.fromOffset(20, 88), Size = UDim2.fromOffset(240, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Muted, Parent = hud })

	-- Villain proximity (top centre)
	local chase = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(300, 16), BackgroundColor3 = Color3.fromRGB(40, 20, 20), Parent = hud })
	UIKit.Corner(8).Parent = chase
	UIKit.Stroke(2).Parent = chase
	chaseFill = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Good, Parent = chase })
	UIKit.Corner(8).Parent = chaseFill
	chaseLabel = UIKit.Label({ Text = "", Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 18), Parent = chase })

	-- Power-up timers (right side)
	powerBars = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(190, 200), BackgroundTransparency = 1, Parent = hud })
	UIKit.List(nil, 6).Parent = powerBars
	for i, id in POWER_ORDER do
		local def = PowerUpData.Get(id)
		local row = if def then powerRow(def.icon, def.color) else powerRow("🛹", Color3.fromRGB(80, 200, 255))
		row.frame.LayoutOrder = i
		barRows[id] = row
	end

	-- Hoverboard button (bottom right)
	hoverButton = UIKit.Button({ Text = "🛹 x0", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -24), Size = UDim2.fromOffset(120, 64), BackgroundColor3 = C.PanelLight }, function()
		RunController.UseHoverboard()
	end)
	hoverButton.Parent = hud

	bigText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(0.8, 0, 0, 110), Visible = false, ZIndex = 5, Parent = gui })
	eventText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.new(0.7, 0, 0, 44), Visible = false, ZIndex = 5, Parent = gui })
	tipLabel = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.new(0.7, 0, 0, 28), Visible = false, TextColor3 = C.Accent2, Parent = gui })

	-- ── Revive panel ("SAVE ME!") ──
	caughtPanel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(420, 300), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 10, Parent = gui })
	UIKit.Corner(18).Parent = caughtPanel
	UIKit.Stroke(4, C.Bad).Parent = caughtPanel
	UIKit.Padding(14).Parent = caughtPanel
	UIKit.List(nil, 10).Parent = caughtPanel
	UIKit.Label({ Text = ("🧠 %s CAUGHT YOU!"):format(Config.Villain.Title), TextColor3 = C.Bad, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, ZIndex = 11, Parent = caughtPanel })
	caughtScore = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2, ZIndex = 11, Parent = caughtPanel })
	local timerTrack = UIKit.New("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 40), Size = UDim2.new(0.8, 0, 0, 14), LayoutOrder = 3, ZIndex = 11, Parent = caughtPanel })
	UIKit.Corner(7).Parent = timerTrack
	caughtTimerFill = UIKit.New("Frame", { BackgroundColor3 = C.Gold, Size = UDim2.fromScale(1, 1), ZIndex = 12, Parent = timerTrack })
	UIKit.Corner(7).Parent = caughtTimerFill
	caughtTimer = UIKit.Label({ Text = "", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4, ZIndex = 11, Parent = caughtPanel })
	reviveCoinsButton = UIKit.Button({ Text = "💪 SAVE ME", Size = UDim2.new(0.85, 0, 0, 52), BackgroundColor3 = C.Good, LayoutOrder = 5, ZIndex = 11 }, function()
		Remotes.Event("ChooseRevive"):FireServer("Coins")
	end)
	reviveCoinsButton.Parent = caughtPanel
	reviveRobuxButton = UIKit.Button({ Text = "💪 SAVE ME (R$)", Size = UDim2.new(0.85, 0, 0, 44), BackgroundColor3 = C.Accent2, LayoutOrder = 6, ZIndex = 11 }, function()
		Remotes.Event("ChooseRevive"):FireServer("Robux")
	end)
	reviveRobuxButton.Parent = caughtPanel
	UIKit.Button({ Text = "END RUN", Size = UDim2.new(0.85, 0, 0, 44), BackgroundColor3 = C.Bad, LayoutOrder = 7, ZIndex = 11 }, function()
		Remotes.Event("ChooseRevive"):FireServer(false)
	end).Parent = caughtPanel

	-- ── Results panel ──
	resultsPanel = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 540, 0.86, 0), BackgroundColor3 = C.Panel, Visible = false, ZIndex = 10, Parent = gui })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(540, 600), Parent = resultsPanel })
	UIKit.Corner(18).Parent = resultsPanel
	UIKit.Stroke(4, C.Gold).Parent = resultsPanel
	resultsBody = UIKit.Scroller(resultsPanel, { Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32, 1, -90) })
	UIKit.List(nil, 6).Parent = resultsBody
	UIKit.Button({ Text = "BACK TO BASE", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0.7, 0, 0, 54), BackgroundColor3 = C.Good }, function()
		RunHUD.Leave:Fire()
	end).Parent = resultsPanel

	fade = UIKit.New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 50, Parent = gui })
	fadeText = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.8, 0, 0, 90), ZIndex = 51, Parent = fade })

	RunController.Event:Connect(function(text: string, color: Color3?)
		RunHUD.Flash(text, color)
	end)
	RunController.Style:Connect(trickPopup)
end

return RunHUD
