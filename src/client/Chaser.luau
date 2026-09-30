--!strict
-- Tung Tung Tung Sahur, the chaser. Purely visual and local to each client:
-- his distance behind the runner comes from the chase "gap" in the run
-- controller. He is off-screen while you're safe, pops up right behind you
-- when you stumble, and grabs you when the gap hits zero.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local RunController = require(script.Parent.RunController)

local Chaser = {}

local model: Model? = nil
local bat: BasePart? = nil
local batOffset = CFrame.identity
local behind = 30
local x = 0
local mode: "Intro" | "Chase" | "Caught" = "Chase"
local introStart = 0
local tungLabel: TextLabel? = nil
local lastTung = 0

local function build(): Model
	local m = ModelFactory.Brainrot(BrainrotData.ChaserId, 1.15)
	m.Name = "TungTungTungSahur"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local root = m.PrimaryPart :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 60)
	gui.StudsOffset = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	tungLabel = label

	bat = m:FindFirstChild("Bat") :: BasePart?
	if bat then
		batOffset = root.CFrame:ToObjectSpace(bat.CFrame)
	end
	return m
end

local function place(dt: number)
	local m = model
	if not m then
		return
	end
	local state = RunController.State
	local runner = RunController.WorldPosition()
	local t = os.clock()

	local targetBehind: number
	local targetX = runner.X
	if mode == "Intro" then
		-- Rises out of the tunnel behind the player.
		local p = math.clamp((t - introStart) / 1.2, 0, 1)
		targetBehind = 14
		behind = targetBehind
		x = runner.X
		local rise = (1 - p) * -12
		m:PivotTo(CFrame.new(runner.X, state.origin.Y + rise, runner.Z + behind))
		if tungLabel then
			tungLabel.Text = if p > 0.3 then "TUNG TUNG TUNG SAHUR" else ""
		end
		return
	elseif mode == "Caught" then
		targetBehind = 3
	elseif state.gap < Config.Chase.DangerGap then
		-- Close enough to see: 4–11 studs behind, a lane over so he doesn't
		-- block the runner.
		targetBehind = 4 + state.gap * 2
		targetX = runner.X + 3.5
	else
		-- Safe: off-screen behind the camera.
		targetBehind = 30 + state.gap * 3
	end
	behind = Util.Lerp(behind, targetBehind, Util.Damp(4, dt))
	x = Util.Lerp(x, targetX, Util.Damp(6, dt))

	local bounce = math.abs(math.sin(t * 12)) * 0.8
	local groundY = state.origin.Y + math.max(0, state.groundY)
	local cf = CFrame.new(x, groundY + bounce, runner.Z + behind)
	m:PivotTo(cf)

	-- Bat swing
	if bat then
		local swing = if mode == "Caught" then math.sin(t * 20) * 0.9 else math.sin(t * 10) * 0.5
		(bat :: BasePart).CFrame = cf * CFrame.new(0, 0.5, 0) * batOffset * CFrame.Angles(swing, 0, 0)
	end

	-- "TUNG TUNG TUNG" as he closes in
	if tungLabel then
		local close = mode == "Caught" or state.gap < Config.Chase.DangerGap
		if close and t - lastTung > 0.45 then
			lastTung = t
			local words = { "TUNG", "TUNG TUNG", "TUNG TUNG TUNG" }
			tungLabel.Text = words[math.random(1, #words)]
		elseif not close then
			tungLabel.Text = ""
		end
	end
end

function Chaser.Start()
	if model then
		model:Destroy()
	end
	local m = build()
	m.Parent = workspace
	model = m
	behind = 14
	mode = "Chase"
	RunService:BindToRenderStep("BrainrotChaser", Enum.RenderPriority.Camera.Value - 1, place)
end

function Chaser.PlayIntro()
	mode = "Intro"
	introStart = os.clock()
end

function Chaser.EndIntro()
	mode = "Chase"
end

function Chaser.SetCaught(caught: boolean)
	mode = if caught then "Caught" else "Chase"
end

-- World position the intro camera should frame.
function Chaser.Position(): Vector3
	if model then
		return model:GetPivot().Position + Vector3.new(0, 5, 0)
	end
	return RunController.WorldPosition()
end

function Chaser.Stop()
	RunService:UnbindFromRenderStep("BrainrotChaser")
	if model then
		model:Destroy()
		model = nil
	end
	bat = nil
	tungLabel = nil
end

return Chaser
