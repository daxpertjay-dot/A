--!strict
-- The chase: Verity (the villain) with his henchman Tung Tung Tung Sahur.
-- Purely visual and local to each client: their distance behind the runner
-- comes from the chase "gap" in the run controller. They stay off-screen
-- while you're safe, appear right behind you when you stumble, and grab you
-- when the gap hits zero.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local RunController = require(script.Parent.RunController)

local Chaser = {}

local villain: Model? = nil
local henchman: Model? = nil
local net: BasePart? = nil
local netOffset = CFrame.identity
local behind = 30
local x = 0
local mode: "Intro" | "Chase" | "Caught" = "Chase"
local introStart = 0
local taunt: TextLabel? = nil
local lastTaunt = 0

local TAUNTS = {
	"COME BACK HERE!",
	"THOSE BRAINROTS ARE MINE!",
	"YOU CAN'T ESCAPE!",
	"TUNG TUNG TUNG!",
	"GET THEM, SAHUR!",
}

local function noCollide(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

local function build()
	local v = ModelFactory.Villain(1.1)
	v.Name = "Verity"
	noCollide(v)
	local root = v.PrimaryPart :: BasePart

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 60)
	gui.StudsOffset = Vector3.new(0, 13, 0)
	gui.AlwaysOnTop = true
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 70, 60)
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	taunt = label

	net = v:FindFirstChild("Bat") :: BasePart?
	if net then
		netOffset = root.CFrame:ToObjectSpace(net.CFrame)
	end

	local h = ModelFactory.Brainrot(Config.Villain.Henchman, 0.9)
	h.Name = "Henchman"
	noCollide(h)
	return v, h
end

local function place(dt: number)
	local v = villain
	local h = henchman
	if not v or not h then
		return
	end
	local state = RunController.State
	local runner = RunController.WorldPosition()
	local t = os.clock()
	local groundY = state.origin.Y + math.max(0, if state.move == "Flying" then 0 else state.groundY)

	if mode == "Intro" then
		-- They burst out of the factory gate behind the player.
		local p = math.clamp((t - introStart) / 1.2, 0, 1)
		behind = 14
		x = runner.X
		local rise = (1 - p) * -12
		v:PivotTo(CFrame.new(runner.X - 2, state.origin.Y + rise, runner.Z + behind))
		h:PivotTo(CFrame.new(runner.X + 4, state.origin.Y + rise, runner.Z + behind + 2))
		if taunt then
			taunt.Text = if p > 0.3 then ("%s: \"THOSE BRAINROTS ARE MINE!\""):format(Config.Villain.Title) else ""
		end
		return
	end

	local targetBehind: number
	local targetX = runner.X
	if mode == "Caught" then
		targetBehind = 3
	elseif state.gap < Config.Chase.DangerGap then
		-- Close enough to see: right behind you, a lane over.
		targetBehind = 4 + state.gap * 2
		targetX = runner.X + 3.5
	else
		-- Safe: off-screen behind the camera.
		targetBehind = 30 + state.gap * 3
	end
	behind = Util.Lerp(behind, targetBehind, Util.Damp(4, dt))
	x = Util.Lerp(x, targetX, Util.Damp(6, dt))

	local bounce = math.abs(math.sin(t * 12)) * 0.8
	local cf = CFrame.new(x, groundY + bounce, runner.Z + behind)
	v:PivotTo(cf)
	h:PivotTo(CFrame.new(x - 6, groundY + math.abs(math.sin(t * 12 + 1.5)) * 0.8, runner.Z + behind + 3))

	-- Net swing
	if net then
		local swing = if mode == "Caught" then math.sin(t * 20) * 0.9 else math.sin(t * 8) * 0.4
		(net :: BasePart).CFrame = cf * CFrame.new(0, 0.5, 0) * netOffset * CFrame.Angles(swing, 0, 0)
	end

	if taunt then
		local close = mode == "Caught" or state.gap < Config.Chase.DangerGap
		if close and t - lastTaunt > 1.4 then
			lastTaunt = t
			taunt.Text = TAUNTS[math.random(1, #TAUNTS)]
		elseif not close then
			taunt.Text = ""
		end
	end
end

function Chaser.Start()
	Chaser.Stop()
	local v, h = build()
	v.Parent = workspace
	h.Parent = workspace
	villain, henchman = v, h
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
	if villain then
		return villain:GetPivot().Position + Vector3.new(0, 5, 0)
	end
	return RunController.WorldPosition()
end

function Chaser.Stop()
	RunService:UnbindFromRenderStep("BrainrotChaser")
	if villain then
		villain:Destroy()
		villain = nil
	end
	if henchman then
		henchman:Destroy()
		henchman = nil
	end
	net = nil
	taunt = nil
end

return Chaser
