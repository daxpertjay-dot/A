--!strict
-- Custom endless-runner camera: behind and above the runner, locked to the
-- run direction, smoothly following lane changes, partially following jumps,
-- with a subtle speed-based FOV and impact shake. Also plays the short
-- (≈2.6s) Tung Tung Tung Sahur intro shot at the start of every run.
--
--                    CAMERA 📷
--                        \
--                         🧍 PLAYER  →→→ track

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local RunController = require(script.Parent.RunController)

local RunCamera = {}

local CAM = Config.Camera
local camera = workspace.CurrentCamera

local camX = 0
local camBaseY = 0
local fov = CAM.FOV.Normal
local introStart = 0
local introDuration = 0
local introTarget: (() -> Vector3)? = nil
local running = false

local function lerpVector(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function chaseCFrame(dt: number): CFrame
	local state = RunController.State
	local runner = RunController.WorldPosition()

	-- Sideways: follow the lane smoothly.
	camX = Util.Lerp(camX, runner.X, Util.Damp(CAM.LaneFollowSharpness, dt))
	-- Vertical: follow the ground level (train roofs) and part of each jump.
	local launched = state.move == "Launched"
	local groundY = if state.grounded or launched then runner.Y else camBaseY
	camBaseY = Util.Lerp(camBaseY, groundY, Util.Damp(if launched then 10 else CAM.VerticalSharpness, dt))
	local jumpOffset = (runner.Y - camBaseY) * CAM.VerticalFollow

	local position = Vector3.new(camX, camBaseY + CAM.Height + jumpOffset, runner.Z + CAM.Distance)
	local lookAt = Vector3.new(camX, camBaseY + CAM.LookHeight + jumpOffset * 0.5, runner.Z - CAM.LookAhead)

	-- Impact shake
	if state.shake > 0 then
		local s = state.shake * 0.35
		local t = os.clock() * 40
		position += Vector3.new(math.noise(t, 0) * s, math.noise(0, t) * s, 0)
	end
	return CFrame.lookAt(position, lookAt)
end

-- Intro: swing around in front of the runner to show Sahur appearing behind
-- them, then settle into the chase camera.
local function introCFrame(dt: number, t: number): CFrame
	local runner = RunController.WorldPosition()
	local target = if introTarget then introTarget() else runner + Vector3.new(0, 0, 14)
	local chase = chaseCFrame(dt)
	local reveal = CFrame.lookAt(runner + Vector3.new(7, 5, -13), (runner + target) / 2 + Vector3.new(0, 4, 0))
	if t < 0.55 then
		return reveal
	end
	local blend = math.clamp((t - 0.55) / 0.45, 0, 1)
	blend = blend * blend * (3 - 2 * blend)
	return CFrame.new(lerpVector(reveal.Position, chase.Position, blend)) * reveal.Rotation:Lerp(chase.Rotation, blend)
end

local function update(dt: number)
	local state = RunController.State
	camera.CameraType = Enum.CameraType.Scriptable

	local introT = if introDuration > 0 then (os.clock() - introStart) / introDuration else 1
	if introT < 1 then
		camera.CFrame = introCFrame(dt, introT)
	else
		camera.CFrame = chaseCFrame(dt)
	end

	local targetFov = CAM.FOV.Normal
	if state.speed >= CAM.VeryFastSpeed then
		targetFov = CAM.FOV.VeryFast
	elseif state.speed >= CAM.FastSpeed then
		targetFov = CAM.FOV.Fast
	end
	fov = Util.Lerp(fov, targetFov, Util.Damp(CAM.FOVSharpness, dt))
	camera.FieldOfView = fov
end

function RunCamera.Start()
	if running then
		return
	end
	running = true
	local runner = RunController.WorldPosition()
	camX = runner.X
	camBaseY = runner.Y
	fov = CAM.FOV.Normal
	RunService:BindToRenderStep("BrainrotRunCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

function RunCamera.PlayIntro(duration: number, target: () -> Vector3)
	introStart = os.clock()
	introDuration = duration
	introTarget = target
end

function RunCamera.Stop()
	if not running then
		return
	end
	running = false
	introDuration = 0
	RunService:UnbindFromRenderStep("BrainrotRunCamera")
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

return RunCamera
