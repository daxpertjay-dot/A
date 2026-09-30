--!strict
-- The run controller owns the player's movement during a run. Normal Roblox
-- movement is disabled; the character is driven kinematically:
--
--   * automatically pushed forward (speed ramps up with distance)
--   * exactly 3 lanes, smooth interpolation between them
--   * jump with a predictable arc, roll to slide under things
--   * no walking backward, strafing, turning or stopping
--
-- Movement state machine:
--   RUNNING ─┬─ JUMPING → FALLING → RUNNING
--            ├─ ROLLING → RUNNING
--            └─ FLYING (🚀 jetpack) → FALLING → RUNNING
--   RUNNING → HIT → STAGGERED → RUNNING
--   RUNNING → CAUGHT (the villain got you)
--
-- Power-ups (🧲 magnet, 🚀 jetpack, 👟 super sneakers, ✖️2 booster) and the
-- 🛹 hoverboard are confirmed by the server and applied here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)

local DebrisFX = require(script.Parent.DebrisFX)
local InputController = require(script.Parent.InputController)

local RunController = {}

local R = Config.Run
local C = Config.Chase
local P = Config.PowerUps
local LANES = R.LanePositions

export type Move = "Running" | "Jumping" | "Falling" | "Rolling" | "Staggered" | "Flying"
export type Phase = "Idle" | "Intro" | "Running" | "Caught"

local state = {
	phase = "Idle" :: Phase,
	move = "Running" :: Move,
	origin = Vector3.zero,
	startD = 0,
	d = 0,
	x = 0,
	feetY = 0,
	vy = 0,
	grounded = true,
	groundY = 0,
	lane = 0,
	fromLane = 0,
	laneT = 1,
	rollTime = 0,
	queuedRoll = false,
	jumpBufferedUntil = 0,
	staggerTime = 0,
	speedFactor = 1,
	speed = 0,
	gap = C.StartGap,
	invulnerableUntil = 0,
	-- Power-ups (os.clock() when they end) and their durations for the HUD bars
	magnetUntil = 0,
	jetpackUntil = 0,
	sneakersUntil = 0,
	boosterUntil = 0,
	hoverUntil = 0,
	durations = {} :: { [string]: number },
	hoverboards = 0,
	-- Score
	multiplier = 1, -- from Brainrots on your base
	score = 0,
	coins = 0,
	meters = 0,
	shake = 0,
	elapsed = 0,
}
RunController.State = state

RunController.Caught = Signal.new()
RunController.Impact = Signal.new() -- (outcome: string)
RunController.CoinCollected = Signal.new()
RunController.Event = Signal.new() -- (message: string, color: Color3?)
RunController.PowerUpStarted = Signal.new() -- (id: string)

local player = Players.LocalPlayer
local character: Model? = nil
local root: BasePart? = nil
local humanoid: Humanoid? = nil
local hipOffset = 3
local trackFolder: Instance? = nil
local board: BasePart? = nil

-- Probe params are configured in Prepare(), once the server has registered
-- the collision groups.
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local ignore: { [Instance]: number } = {}
local coins: { BasePart } = {}
local pickups: { BasePart } = {}
local connections: { RBXScriptConnection } = {}
local tracks: { [string]: AnimationTrack } = {}

local ANIMS = Config.Animations

local function now(): number
	return os.clock()
end

-- ───────────────────────────── character setup ─────────────────────────────

local function loadAnimations(hum: Humanoid)
	table.clear(tracks)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, playing in (animator :: Animator):GetPlayingAnimationTracks() do
		playing:Stop(0)
	end
	local set = if hum.RigType == Enum.HumanoidRigType.R6 then ANIMS.R6 else ANIMS.R15
	for name, id in set :: { [string]: string } do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = name ~= "Jump"
			tracks[name] = track
		end
	end
end

local currentAnim = ""
local function playAnim(name: string, speed: number?)
	local track = tracks[name]
	if currentAnim ~= name then
		for other, t in tracks do
			if other ~= name then
				t:Stop(0.1)
			end
		end
		if track then
			track:Play(0.1)
		end
		currentAnim = name
	end
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

local function setupCharacter(): boolean
	character = player.Character
	if not character then
		return false
	end
	local char = character :: Model
	root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	humanoid = char:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false
	end
	local hum = humanoid :: Humanoid
	local rootPart = root :: BasePart
	hipOffset = if hum.RigType == Enum.HumanoidRigType.R6 then 3 else hum.HipHeight + rootPart.Size.Y / 2

	-- The run controller owns movement: turn off everything that would fight it.
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = false
	end
	hum.AutoRotate = false
	for _, s in {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.Landed,
	} do
		hum:SetStateEnabled(s, false)
	end
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "RunPlayer"
		end
	end
	loadAnimations(hum)
	return true
end

-- ───────────────────────────── track bookkeeping ─────────────────────────────

local function register(d: Instance)
	if d:IsA("BasePart") then
		if d:GetAttribute("Coin") then
			table.insert(coins, d)
		elseif d:GetAttribute("Pickup") then
			table.insert(pickups, d)
		end
	end
end

local function obstacleOf(part: BasePart): Instance?
	local node: Instance? = part
	while node and node ~= trackFolder do
		if node:GetAttribute("ObstacleType") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- ───────────────────────────── helpers ─────────────────────────────

local function worldPosition(): Vector3
	return state.origin + Vector3.new(state.x, state.feetY, -state.d)
end

local function bodyCenter(): Vector3
	return worldPosition() + Vector3.new(0, 2.5, 0)
end

local function addShake(amount: number)
	state.shake = math.min(2, state.shake + amount)
end

local function loseGap(amount: number)
	state.gap -= amount
end

local function isRolling(): boolean
	return state.rollTime > 0
end

local function isFlying(): boolean
	return now() < state.jetpackUntil
end

local function onBoard(): boolean
	return now() < state.hoverUntil
end

-- Current score multiplier: base (Brainrots) × 2 while the booster runs.
function RunController.CurrentMultiplier(): number
	return state.multiplier * (if now() < state.boosterUntil then 2 else 1)
end

local function probeGround(x: number, d: number, fromY: number): number?
	if not trackFolder then
		return nil
	end
	local origin = state.origin + Vector3.new(x, fromY, -d)
	local result = workspace:Raycast(origin, Vector3.new(0, -80, 0), rayParams)
	if result then
		return result.Position.Y - state.origin.Y
	end
	return nil
end

-- ───────────────────────────── actions ─────────────────────────────

local function changeLane(dir: number)
	local target = math.clamp(state.lane + dir, -1, 1)
	if target == state.lane then
		addShake(0.25)
		return
	end
	-- Start from wherever we currently are between lanes.
	local currentX = state.x
	state.fromLane = state.lane
	state.lane = target
	local fromX = LANES[state.fromLane]
	local toX = LANES[state.lane]
	state.laneT = if toX ~= fromX then math.clamp((currentX - fromX) / (toX - fromX), 0, 0.9) else 1
end

local function jump()
	if state.move == "Staggered" or isFlying() then
		return
	end
	if not state.grounded then
		-- Pressed a little early: jump the moment we land.
		state.jumpBufferedUntil = now() + R.JumpBuffer
		return
	end
	-- Jumping instantly cancels a roll, so roll → jump chains are snappy.
	state.rollTime = 0
	state.queuedRoll = false
	state.jumpBufferedUntil = 0
	local sneakers = now() < state.sneakersUntil
	state.vy = R.JumpVelocity * (if sneakers then P.SneakersJumpMultiplier else 1)
	state.grounded = false
end

local function roll()
	if state.move == "Staggered" or isFlying() then
		return
	end
	state.jumpBufferedUntil = 0
	if state.grounded then
		state.rollTime = R.RollDuration
	else
		-- Mid-air roll slams you down and rolls on landing.
		state.vy = math.min(state.vy, R.FastFallVelocity)
		state.queuedRoll = true
	end
end

local function onAction(action: string)
	if state.phase ~= "Running" then
		return
	end
	if action == "Left" then
		changeLane(-1)
	elseif action == "Right" then
		changeLane(1)
	elseif action == "Jump" then
		jump()
	elseif action == "Roll" then
		roll()
	end
end

function RunController.UseHoverboard()
	if state.phase ~= "Running" or onBoard() or state.hoverboards <= 0 then
		return
	end
	Remotes.Event("UseHoverboard"):FireServer()
end

-- ───────────────────────────── collisions ─────────────────────────────

local function onObstacle(obstacle: Instance, part: BasePart)
	local t = now()
	if (ignore[obstacle] or 0) > t or obstacle:GetAttribute("Destroyed") then
		return
	end

	-- Clipped something while changing lanes → bounce back to the old lane.
	local obstacleLane = obstacle:GetAttribute("Lane")
	if obstacleLane ~= state.lane then
		if state.laneT < 1 then
			state.lane, state.fromLane = state.fromLane, state.lane
			state.laneT = 1 - state.laneT
		end
		ignore[obstacle] = t + 0.5
		loseGap(C.GapLoss.SideBump)
		addShake(0.4)
		RunController.Impact:Fire("Side")
		Remotes.Event("ReportHit"):FireServer(obstacle, { side = true })
		return
	end

	local tier = obstacle:GetAttribute("Tier") or 4
	local result = ImpactRules.Resolve(tier, obstacle:GetAttribute("CollisionDamage") or 0, state.speed, false, onBoard())
	local impact = Vector3.new(part.Position.X, bodyCenter().Y, part.Position.Z)
	Remotes.Event("ReportHit"):FireServer(obstacle, { speed = state.speed, point = impact })

	if result.outcome == "Smash" then
		ignore[obstacle] = math.huge
		DebrisFX.PredictBreak(obstacle, impact, state.speed)
		state.speedFactor *= C.SlowdownOnSmallBreak
		loseGap(C.GapLoss.SmallBreak)
		addShake(0.5)
	elseif result.outcome == "CrashThrough" then
		ignore[obstacle] = math.huge
		DebrisFX.PredictBreak(obstacle, impact, state.speed * 1.3)
		loseGap(C.GapLoss.CrashThrough)
		addShake(1)
		RunController.Event:Fire("💥 CRASH!", Color3.fromRGB(255, 160, 60))
	elseif result.outcome == "Absorbed" then
		-- 🛹 The hoverboard takes the hit and breaks.
		ignore[obstacle] = math.huge
		state.hoverUntil = 0
		state.invulnerableUntil = t + P.HoverboardInvulnerability
		if result.damage == math.huge then
			DebrisFX.PredictBreak(obstacle, impact, state.speed * 1.3)
		end
		addShake(0.8)
		RunController.Event:Fire("🛹 BOARD SMASHED — SAVED!", Color3.fromRGB(120, 200, 255))
	else -- Bump: stopped / staggered, the villain closes in
		ignore[obstacle] = t + C.StaggerTime
		state.staggerTime = C.StaggerTime
		state.speedFactor = 0
		state.rollTime = 0
		state.d -= C.BumpPushback
		loseGap(C.GapLoss.Bump)
		addShake(1.3)
		RunController.Event:Fire(if tier >= 4 then "😵 OUCH!" else "😵 CRASH! (keep hitting it…)", Color3.fromRGB(255, 90, 90))
	end
	RunController.Impact:Fire(result.outcome)
end

local function checkCollisions(prevD: number)
	if not trackFolder or now() < state.invulnerableUntil or isFlying() then
		return
	end
	local h = if isRolling() then R.RollHitboxHeight else R.HitboxHeight
	local travelled = math.max(0, state.d - prevD)
	local centerD = (state.d + prevD) / 2
	local center = state.origin + Vector3.new(state.x, state.feetY + 0.6 + h / 2, -centerD)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(R.HitboxWidth, h, R.HitboxDepth + travelled), overlapParams)
	local seen: { [Instance]: boolean } = {}
	for _, part in parts do
		local obstacle = obstacleOf(part)
		if obstacle and not seen[obstacle] then
			seen[obstacle] = true
			onObstacle(obstacle, part)
			if state.staggerTime > 0 then
				break
			end
		end
	end
end

-- ───────────────────────────── coins / pickups ─────────────────────────────

local function updateCollectibles(dt: number)
	local center = bodyCenter()
	local t = now()
	local magnetRadius = if t < state.magnetUntil then P.MagnetRadius else 0
	local spin = state.elapsed * 3

	local i = 1
	while i <= #coins do
		local coin = coins[i]
		if coin.Parent == nil or coin.Transparency >= 1 then
			coins[i] = coins[#coins]
			coins[#coins] = nil
		else
			local pos = coin.Position
			local ahead = center.Z - pos.Z -- positive when the coin is in front
			if ahead > -6 and ahead < 220 then
				local distance = (pos - center).Magnitude
				if magnetRadius > 0 and distance < magnetRadius then
					pos = pos:Lerp(center, Util.Damp(9, dt))
					distance = (pos - center).Magnitude
				end
				if distance < 3.4 then
					coin.Transparency = 1
					state.coins += coin:GetAttribute("Value") or 1
					RunController.CoinCollected:Fire()
					Remotes.Event("CollectCoin"):FireServer(coin)
				else
					coin.CFrame = CFrame.new(pos) * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, math.rad(90), 0)
				end
			end
			i += 1
		end
	end

	i = 1
	while i <= #pickups do
		local box = pickups[i]
		if box.Parent == nil or box.Transparency >= 1 then
			pickups[i] = pickups[#pickups]
			pickups[#pickups] = nil
		else
			local pos = box.Position
			local isCage = box:GetAttribute("Pickup") == "Brainrot"
			local reach = if isCage then 5 else 4
			if (pos - center).Magnitude < reach then
				box.Transparency = 1
				for _, d in box:GetDescendants() do
					if d:IsA("BasePart") then
						d.Transparency = 1
					elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
						d.Enabled = false
					end
				end
				Remotes.Event("PickupItem"):FireServer(box)
			elseif not isCage then
				box.CFrame = CFrame.new(pos) * CFrame.Angles(0, spin * 0.7, 0)
			end
			i += 1
		end
	end
end

-- ───────────────────────────── hoverboard visual ─────────────────────────────

local function setBoardVisible(visible: boolean)
	if visible and not board then
		local b = Instance.new("Part")
		b.Name = "Hoverboard"
		b.Size = Vector3.new(2.6, 0.35, 5.5)
		b.Color = Color3.fromRGB(80, 200, 255)
		b.Material = Enum.Material.Neon
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.Parent = workspace
		board = b
	elseif not visible and board then
		board:Destroy()
		board = nil
	end
end

-- ───────────────────────────── main update ─────────────────────────────

local function applyCharacter(xVelocity: number)
	local rootPart = root
	if not rootPart or not rootPart.Parent then
		return
	end
	local rollPitch, rollDrop = 0, 0
	if isRolling() then
		local p = 1 - state.rollTime / R.RollDuration
		rollPitch = -math.pi * 2 * p
		rollDrop = 1.4 * math.sin(math.pi * p)
	end
	local stagger = if state.staggerTime > 0 then math.sin(state.staggerTime / C.StaggerTime * math.pi) * 0.35 else 0
	local lean = math.clamp(-xVelocity * 0.006, -0.3, 0.3)
	local flyTilt = if state.move == "Flying" then -0.35 else 0
	local boardLift = if onBoard() then 0.8 else 0
	local pos = worldPosition() + Vector3.new(0, hipOffset - rollDrop + boardLift, 0)
	rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(rollPitch + stagger + flyTilt, 0, lean)
	rootPart.AssemblyLinearVelocity = Vector3.new(xVelocity, state.vy, -state.speed)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	setBoardVisible(onBoard() and state.phase == "Running")
	if board then
		board.CFrame = CFrame.new(worldPosition() + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, lean)
	end

	-- Animation selection
	if state.phase ~= "Running" then
		playAnim("Idle")
	elseif state.move == "Flying" or not state.grounded then
		if currentAnim ~= "Jump" then
			playAnim("Jump")
		end
	else
		playAnim("Run", math.clamp(state.speed / ANIMS.RunSpeedDivisor, 0.8, 2.4))
	end
end

local function update(dt: number)
	if state.phase == "Idle" then
		return
	end
	dt = math.min(dt, 1 / 20)
	state.elapsed += dt
	state.shake = math.max(0, state.shake - dt * 3)

	if state.phase ~= "Running" then
		-- Intro / caught: stand still on the ground.
		local g = probeGround(state.x, state.d, state.feetY + 3.5)
		if g then
			state.feetY = g
		end
		state.vy = 0
		state.speed = 0
		applyCharacter(0)
		return
	end

	local t = now()
	-- Timers
	if state.staggerTime > 0 then
		state.staggerTime = math.max(0, state.staggerTime - dt)
	end
	if state.rollTime > 0 then
		state.rollTime = math.max(0, state.rollTime - dt)
	end

	-- Forward speed
	state.meters = math.max(0, (state.d - state.startD) * R.MetersPerStud)
	if state.staggerTime <= 0 then
		state.speedFactor = math.min(1, state.speedFactor + C.SpeedRecoveryPerSecond * dt)
	end
	local flying = isFlying()
	state.speed = ImpactRules.SpeedAt(state.meters) * state.speedFactor * (if flying then P.JetpackSpeedMultiplier else 1)
	local prevD = state.d
	state.d += state.speed * dt

	-- Score: meters × multiplier (mirrors the server, which is authoritative).
	local gained = math.max(0, state.d - prevD) * R.MetersPerStud * Config.Score.PointsPerMeter
	state.score += gained * RunController.CurrentMultiplier()

	-- Lane interpolation
	local prevX = state.x
	if state.laneT < 1 then
		state.laneT = math.min(1, state.laneT + dt / R.LaneChangeTime)
	end
	local s = state.laneT * state.laneT * (3 - 2 * state.laneT)
	state.x = Util.Lerp(LANES[state.fromLane], LANES[state.lane], s)
	local xVelocity = (state.x - prevX) / math.max(dt, 1e-4)

	if flying then
		-- 🚀 Cruise high above the track; nothing down there can touch you.
		state.feetY = Util.Lerp(state.feetY, P.JetpackHeight, Util.Damp(4, dt))
		state.vy = 0
		state.grounded = false
		state.rollTime = 0
		state.move = "Flying"
		-- Keep a little invulnerability for the landing.
		state.invulnerableUntil = math.max(state.invulnerableUntil, state.jetpackUntil + P.JetpackLandingInvulnerability)
	else
		-- Vertical movement against the ground
		state.vy -= R.Gravity * dt
		state.feetY += state.vy * dt
		local ground = probeGround(state.x, state.d, math.max(state.feetY, state.feetY - state.vy * dt) + 3.5)
		state.groundY = ground or -math.huge
		if ground and state.vy <= 0 and state.feetY <= ground + 0.05 then
			state.feetY = ground
			state.vy = 0
			local justLanded = not state.grounded
			state.grounded = true
			if justLanded and t < state.jumpBufferedUntil then
				jump()
			elseif justLanded and state.queuedRoll then
				state.rollTime = R.RollDuration
			end
			state.queuedRoll = false
		elseif ground and state.grounded and state.feetY - ground < 1.2 and state.vy <= 0 then
			-- Stick to slopes going down (ramps) instead of hopping off them.
			state.feetY = ground
			state.vy = 0
		else
			state.grounded = false
		end

		if state.staggerTime > 0 then
			state.move = "Staggered"
		elseif isRolling() then
			state.move = "Rolling"
		elseif not state.grounded then
			state.move = if state.vy > 0 then "Jumping" else "Falling"
		else
			state.move = "Running"
		end
	end

	checkCollisions(prevD)
	updateCollectibles(dt)

	-- Chase pressure
	if state.staggerTime <= 0 then
		state.gap = math.min(C.MaxGap, state.gap + C.RecoverPerSecond * dt)
	end
	if state.feetY < -40 then
		state.gap = 0
	end
	if state.gap <= 0 then
		state.gap = 0
		state.phase = "Caught"
		state.speed = 0
		state.hoverUntil = 0
		RunController.Caught:Fire()
		Remotes.Event("ReportCaught"):FireServer()
	end

	applyCharacter(xVelocity)
end

-- ───────────────────────────── lifecycle ─────────────────────────────

function RunController.Prepare(info: any): boolean
	if not setupCharacter() then
		return false
	end
	trackFolder = info.trackFolder
	overlapParams.CollisionGroup = "ObstacleProbe"
	rayParams.CollisionGroup = "GroundProbe"
	overlapParams.FilterDescendantsInstances = { info.trackFolder }
	rayParams.FilterDescendantsInstances = { info.trackFolder }

	state.phase = "Intro"
	state.move = "Running"
	state.origin = info.origin
	state.startD = info.startD
	state.d = info.startD
	state.x = 0
	state.feetY = 0
	state.vy = 0
	state.grounded = true
	state.lane, state.fromLane, state.laneT = 0, 0, 1
	state.rollTime, state.staggerTime = 0, 0
	state.queuedRoll = false
	state.jumpBufferedUntil = 0
	state.speedFactor = 1
	state.speed = 0
	state.gap = C.StartGap
	state.invulnerableUntil = 0
	state.magnetUntil, state.jetpackUntil, state.sneakersUntil, state.boosterUntil, state.hoverUntil = 0, 0, 0, 0, 0
	table.clear(state.durations)
	state.hoverboards = info.hoverboards or 0
	state.multiplier = info.multiplier or 1
	state.score = 0
	state.coins = 0
	state.meters = 0
	state.elapsed = 0
	state.shake = 0
	table.clear(ignore)
	table.clear(coins)
	table.clear(pickups)

	for _, d in (info.trackFolder :: Instance):GetDescendants() do
		register(d)
	end
	table.insert(connections, (info.trackFolder :: Instance).DescendantAdded:Connect(register))
	table.insert(connections, InputController.Action:Connect(onAction) :: any)
	table.insert(connections, InputController.Hoverboard:Connect(RunController.UseHoverboard) :: any)

	RunService:BindToRenderStep("BrainrotRunController", Enum.RenderPriority.Input.Value + 1, update)
	InputController.SetEnabled(true)
	return true
end

function RunController.Go()
	if state.phase == "Intro" then
		state.phase = "Running"
		state.speedFactor = 0.5 -- quick burst off the line
	end
end

function RunController.Revive()
	state.phase = "Running"
	state.gap = C.RevivedGap
	state.invulnerableUntil = now() + C.RevivedInvulnerability
	state.staggerTime = 0
	state.speedFactor = 0.6
	RunController.Event:Fire("💪 REVIVED!", Color3.fromRGB(140, 255, 140))
end

-- Server-confirmed events.
function RunController.HandleWorldEvent(event: any)
	local t = now()
	if event.type == "PowerUp" then
		local until_ = t + event.duration
		state.durations[event.id] = event.duration
		if event.id == "Magnet" then
			state.magnetUntil = until_
			RunController.Event:Fire("🧲 COIN MAGNET!", Color3.fromRGB(255, 120, 120))
		elseif event.id == "Jetpack" then
			state.jetpackUntil = until_
			state.rollTime = 0
			RunController.Event:Fire("🚀 JETPACK!", Color3.fromRGB(255, 190, 60))
		elseif event.id == "SuperSneakers" then
			state.sneakersUntil = until_
			RunController.Event:Fire("👟 SUPER SNEAKERS!", Color3.fromRGB(120, 255, 140))
		elseif event.id == "ScoreBooster" then
			state.boosterUntil = until_
			RunController.Event:Fire(("✖️2 SCORE BOOSTER! (x%d)"):format(state.multiplier * 2), Color3.fromRGB(110, 190, 255))
		end
		RunController.PowerUpStarted:Fire(event.id)
	elseif event.type == "Hoverboard" then
		state.hoverUntil = t + event.duration
		state.durations.Hoverboard = event.duration
		state.hoverboards = event.left
		RunController.Event:Fire("🛹 HOVERBOARD!", Color3.fromRGB(120, 200, 255))
	elseif event.type == "HoverboardBroken" then
		state.hoverUntil = 0
	elseif event.type == "MysteryBox" then
		local text = if event.kind == "Coins" then ("❓ MYSTERY BOX: 🪙 %d!"):format(event.amount) else ("❓ MYSTERY BOX: 🛹 x%d!"):format(event.amount)
		if event.kind == "Coins" then
			state.coins += event.amount
		end
		RunController.Event:Fire(text, Color3.fromRGB(255, 200, 60))
	elseif event.type == "BrainrotRescued" then
		RunController.Event:Fire(("🔓 RESCUED %s %s! (+%dx multiplier)"):format(event.icon, string.upper(event.name), event.bonus), Color3.fromRGB(255, 140, 230))
	end
end

function RunController.Stop()
	state.phase = "Idle"
	RunService:UnbindFromRenderStep("BrainrotRunController")
	InputController.SetEnabled(false)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, track in tracks do
		track:Stop(0.2)
	end
	table.clear(tracks)
	currentAnim = ""
	trackFolder = nil
	setBoardVisible(false)
end

-- World-space position of the runner (for the camera and the chaser).
function RunController.WorldPosition(): Vector3
	return worldPosition()
end

return RunController
