--!strict
-- Your run buddy: the Brainrot you picked on your base jogs beside you
-- during runs (its perks are applied by the run controller / server).

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local RunController = require(script.Parent.RunController)

local Buddy = {}

local model: Model? = nil
local side = -1
local x = 0

local function step(dt: number)
	local m = model
	if not m then
		return
	end
	local state = RunController.State
	local runner = RunController.WorldPosition()
	-- Stay on whichever side of the runner has more room.
	side = if state.lane > 0 then -1 elseif state.lane < 0 then 1 else side
	x = Util.Lerp(x, runner.X + side * 4.5, Util.Damp(8, dt))
	-- Rides along through cannon flights too.
	local groundY = if state.launch then runner.Y else state.origin.Y + math.max(0, state.groundY)
	local hop = math.abs(math.sin(os.clock() * 11)) * 1.2
	m:PivotTo(CFrame.new(x, groundY + hop, runner.Z + 2.5))
end

function Buddy.Start(brainrotId: string?)
	Buddy.Stop()
	if not brainrotId or not BrainrotData.Get(brainrotId) then
		return
	end
	local m = ModelFactory.Brainrot(brainrotId, 0.6)
	m.Name = "RunBuddy"
	m.Parent = workspace
	model = m
	x = RunController.WorldPosition().X
	RunService:BindToRenderStep("BrainrotBuddy", Enum.RenderPriority.Camera.Value - 2, step)
end

function Buddy.Stop()
	RunService:UnbindFromRenderStep("BrainrotBuddy")
	if model then
		model:Destroy()
		model = nil
	end
end

return Buddy
