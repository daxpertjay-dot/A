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
--            └─ ROLLING → RUNNING
--   RUNNING → HIT → STAGGERED → RUNNING
--   RUNNING → CAUGHT (Tung Tung Tung Sahur got you)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BiomeData = require(Shared.BiomeData)
local ImpactRules = require(Shared.ImpactRules)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)

local DebrisFX = require(script.Parent.DebrisFX)
local InputController = require(script.Parent.InputController)

local RunController = {}

local R = Config.Run
local C = Config.Chase
local LANES = R.LanePositions

export type Move = "Running" | "Jumping" | "Falling" | "Rolling" | "Staggered" | "Launched"
export type Phase = "Idle" | "Intro" | "Running" | "Caught"

export type LoadoutSlot = {
	slot: number,
	itemId: string,
	name: string,
	icon: string,
	ability: string,
	rarity: string,
	level: number,
	charges: number,
	duration: number?,
	radius: number?,
	speedMultiplier: number?,
}

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
	staggerTime = 0,
	speedFactor = 1,
	speed = 0,
	gap = C.StartGap,
	invulnerableUntil = 0,
	shieldUntil = 0,
	boostUntil = 0,
	boostMultiplier = 1,
	magnetUntil = 0,
	magnetRadius = 0,
	jumpBufferedUntil = 0,
	biome = BiomeData.List[1] :: BiomeData.Biome,
	-- Head start cannon flight
	launch = nil :: { elapsed: number, duration: number, height: number, fromD: number, toD: number, fromY: number, toY: number }?,
	perks = {} :: { [string]: number }, -- run buddy perk totals
	buddy = "",
	doublerUntil = 0,
	coins = 0,
	meters = 0,
	loadout = {} :: { LoadoutSlot },
	shake = 0,
	elapsed = 0,
}
RunController.State = state

RunController.Caught = Signal.new()
RunController.Impact = Signal.new() -- (outcome: string)
RunController.CoinCollected = Signal.new()
RunController.LoadoutChanged = Signal.new()
RunController.Event = Signal.new() -- (message: string, color: Color3?)
RunController.BrainrotCaught = Signal.new() -- (event)
RunController.BiomeChanged = Signal.new() -- (biome)
RunController.Landed = Signal.new() -- () cannon flight finished

local player = Players.LocalPlayer
local character: Model? = nil
local root: BasePart? = nil
local humanoid: Humanoid? = nil
local hipOffset = 3
local trackFolder: Instance? = nil

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
	state.gap -= amount * (1 - math.clamp(state.perks.BumpResist or 0, 0, 0.9))
end

local function isRolling(): boolean
	return state.rollTime > 0
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
		-- Bumping the edge of the track costs a little chase distance.
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
	if state.move == "Staggered" then
		return
	end
	if not state.grounded then
		-- Pressed a little early: jump the moment we land.
		state.jumpBufferedUntil = os.clock() + R.JumpBuffer
		return
	end
	-- Jumping instantly cancels a roll, so roll → jump chains are snappy.
	state.rollTime = 0
	state.queuedRoll = false
	state.jumpBufferedUntil = 0
	state.vy = R.JumpVelocity
	state.grounded = false
end

local function roll()
	if state.move == "Staggered" then
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

function RunController.UseEquipment(slot: number)
	if state.phase ~= "Running" then
		return
	end
	for _, entry in state.loadout do
		if entry.slot == slot and entry.charges > 0 then
			Remotes.Event("UseEquipment"):FireServer(slot)
			return
		end
	end
end

-- ───────────────────────────── collisions ─────────────────────────────

local function predictBreak(obstacle: Instance, impact: Vector3, force: number)
	DebrisFX.PredictBreak(obstacle, impact, force)
end

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
	local result = ImpactRules.Resolve(
		tier,
		obstacle:GetAttribute("CollisionDamage") or 0,
		state.speed,
		t < state.boostUntil,
		t < state.shieldUntil,
		state.perks.CrashThrough
	)
	local impact = Vector3.new(part.Position.X, bodyCenter().Y, part.Position.Z)
	Remotes.Event("ReportHit"):FireServer(obstacle, { speed = state.speed, point = impact })

	if result.outcome == "Smash" then
		ignore[obstacle] = math.huge
		predictBreak(obstacle, impact, state.speed)
		state.speedFactor *= C.SlowdownOnSmallBreak
		loseGap(C.GapLoss.SmallBreak)
		addShake(0.5)
	elseif result.outcome == "CrashThrough" then
		ignore[obstacle] = math.huge
		predictBreak(obstacle, impact, state.speed * 1.3)
		loseGap(C.GapLoss.CrashThrough)
		addShake(1)
		RunController.Event:Fire("💥 CRASH!", Color3.fromRGB(255, 160, 60))
	elseif result.outcome == "Absorbed" then
		ignore[obstacle] = math.huge
		state.shieldUntil = 0
		if result.damage == math.huge then
			predictBreak(obstacle, impact, state.speed * 1.3)
		end
		addShake(0.6)
		RunController.Event:Fire("🛡️ BLOCKED!", Color3.fromRGB(120, 200, 255))
	else -- Bump: stopped / staggered, Sahur closes in
		ignore[obstacle] = t + C.StaggerTime
		state.staggerTime = C.StaggerTime
		state.speedFactor = 0
		state.rollTime = 0
		state.d -= C.BumpPushback
		loseGap(C.GapLoss.Bump)
		addShake(1.3)
		local message = if obstacle:GetAttribute("Kind") == "LavaPool" then "🔥 HOT HOT HOT! Jump the lava!" elseif tier >= 4 then "😵 OUCH!" else "😵 CRASH! (keep hitting it…)"
		RunController.Event:Fire(message, Color3.fromRGB(255, 90, 90))
	end
	RunController.Impact:Fire(result.outcome)
end

local function checkCollisions(prevD: number)
	if not trackFolder or now() < state.invulnerableUntil then
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
			if state.move == "Staggered" or state.staggerTime > 0 then
				break
			end
		end
	end
end

-- ───────────────────────────── coins / pickups / encounters ─────────────────────────────

local function updateCollectibles(dt: number)
	local center = bodyCenter()
	local t = now()
	local magnetRadius = math.max(state.perks.Magnet or 0, if t < state.magnetUntil then state.magnetRadius else 0)
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
					state.coins += (coin:GetAttribute("Value") or 1) * (if t < state.doublerUntil then 2 else 1) * (1 + (state.perks.CoinBonus or 0))
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
			local isBrainrot = box:GetAttribute("Pickup") == "Brainrot"
			local reach = if isBrainrot then 5 else 4
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
			elseif not isBrainrot then
				box.CFrame = CFrame.new(pos) * CFrame.Angles(0, spin * 0.7, 0)
			end
			i += 1
		end
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
	if state.launch then
		-- Tumbling through the air after the cannon.
		rollPitch = -state.elapsed * 7
	end
	local stagger = if state.staggerTime > 0 then math.sin(state.staggerTime / C.StaggerTime * math.pi) * 0.35 else 0
	local lean = math.clamp(-xVelocity * 0.006, -0.3, 0.3)
	local pos = worldPosition() + Vector3.new(0, hipOffset - rollDrop, 0)
	rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(rollPitch + stagger, 0, lean)
	rootPart.AssemblyLinearVelocity = Vector3.new(xVelocity, state.vy, -state.speed)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Animation selection
	if state.phase ~= "Running" then
		playAnim("Idle")
	elseif not state.grounded then
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

	-- 🎯 Cannon flight: a big scripted arc down the track, no collisions.
	local launch = state.launch
	if launch then
		launch.elapsed += dt
		local p = math.clamp(launch.elapsed / launch.duration, 0, 1)
		state.d = launch.fromD + (launch.toD - launch.fromD) * p
		state.feetY = launch.fromY + (launch.toY - launch.fromY) * p + 4 * launch.height * p * (1 - p)
		state.vy = 0
		state.speed = (launch.toD - launch.fromD) / launch.duration
		state.meters = math.max(0, (state.d - state.startD) * R.MetersPerStud)
		state.grounded = false
		state.move = "Launched"
		if p >= 1 then
			state.launch = nil
			state.grounded = true
			state.move = "Running"
			state.speedFactor = 1
			state.invulnerableUntil = t + Config.HeadStart.LandingInvulnerability
			state.gap = math.max(state.gap, C.StartGap + (state.perks.StartGap or 0))
			addShake(1.2)
			RunController.Landed:Fire()
		end
		applyCharacter(0)
		return
	end

	-- Biome effects (slippery ice, floaty void)
	local biome = BiomeData.At(state.meters)
	if biome ~= state.biome then
		state.biome = biome
		RunController.BiomeChanged:Fire(biome)
	end

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
	local boost = if t < state.boostUntil then state.boostMultiplier else 1
	state.speed = ImpactRules.SpeedAt(state.meters) * state.speedFactor * boost
	local prevD = state.d
	state.d += state.speed * dt

	-- Lane interpolation
	local prevX = state.x
	if state.laneT < 1 then
		state.laneT = math.min(1, state.laneT + dt / (R.LaneChangeTime * state.biome.laneChangeScale))
	end
	local s = state.laneT * state.laneT * (3 - 2 * state.laneT)
	state.x = Util.Lerp(LANES[state.fromLane], LANES[state.lane], s)
	local xVelocity = (state.x - prevX) / math.max(dt, 1e-4)

	-- Vertical movement against the ground
	state.vy -= R.Gravity * state.biome.gravityScale * dt
	state.feetY += state.vy * dt
	local ground = probeGround(state.x, state.d, math.max(state.feetY, state.feetY - state.vy * dt) + 3.5)
	state.groundY = ground or -math.huge
	if ground and state.vy <= 0 and state.feetY <= ground + 0.05 then
		state.feetY = ground
		state.vy = 0
		local justLanded = not state.grounded
		state.grounded = true
		if justLanded and os.clock() < state.jumpBufferedUntil then
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

	-- Movement state
	if state.staggerTime > 0 then
		state.move = "Staggered"
	elseif isRolling() then
		state.move = "Rolling"
	elseif not state.grounded then
		state.move = if state.vy > 0 then "Jumping" else "Falling"
	else
		state.move = "Running"
	end

	checkCollisions(prevD)
	updateCollectibles(dt)

	-- Chase pressure
	if state.staggerTime <= 0 then
		state.gap = math.min(C.MaxGap, state.gap + C.RecoverPerSecond * (1 + (state.perks.GapRecovery or 0)) * dt)
	end
	if state.feetY < -40 then
		state.gap = 0
	end
	if state.gap <= 0 then
		state.gap = 0
		state.phase = "Caught"
		state.speed = 0
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
	state.speedFactor = 1
	state.speed = 0
	state.perks = info.perks or {}
	state.buddy = info.buddy or ""
	state.gap = C.StartGap + (state.perks.StartGap or 0)
	state.jumpBufferedUntil = 0
	state.launch = nil
	state.biome = BiomeData.At(0)
	state.invulnerableUntil = 0
	state.shieldUntil, state.boostUntil, state.magnetUntil, state.doublerUntil = 0, 0, 0, 0
	state.coins = 0
	state.meters = 0
	state.elapsed = 0
	state.shake = 0
	state.loadout = info.loadout
	table.clear(ignore)
	table.clear(coins)
	table.clear(pickups)

	for _, d in (info.trackFolder :: Instance):GetDescendants() do
		register(d)
	end
	table.insert(connections, (info.trackFolder :: Instance).DescendantAdded:Connect(register))
	table.insert(connections, InputController.Action:Connect(onAction) :: any)
	table.insert(connections, InputController.Equipment:Connect(RunController.UseEquipment) :: any)

	RunService:BindToRenderStep("BrainrotRunController", Enum.RenderPriority.Input.Value + 1, update)
	InputController.SetEnabled(true)
	return true
end

-- GO! With a head start the cannon fires you `headStart` meters down the track.
function RunController.Go(headStart: number?)
	if state.phase ~= "Intro" then
		return
	end
	state.phase = "Running"
	state.speedFactor = 0.5 -- quick burst off the line
	if state.perks.StartShield then
		state.shieldUntil = os.clock() + state.perks.StartShield
		RunController.Event:Fire("🛡️ BUDDY SHIELD!", Color3.fromRGB(120, 200, 255))
	end
	if headStart and headStart > 0 then
		local duration, height = ImpactRules.LaunchProfile(headStart)
		local toD = state.startD + headStart / R.MetersPerStud
		local landingY = probeGround(0, toD, 60) or 0
		state.lane, state.fromLane, state.laneT, state.x = 0, 0, 1, 0
		state.rollTime = 0
		state.launch = {
			elapsed = 0,
			duration = duration,
			height = height,
			fromD = state.d,
			toD = toD,
			fromY = state.feetY,
			toY = landingY,
		}
		addShake(1.8)
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

-- Server-confirmed world/equipment events.
function RunController.HandleWorldEvent(event: any)
	local t = now()
	if event.type == "EquipmentUsed" then
		for _, entry in state.loadout do
			if entry.slot == event.slot then
				entry.charges = event.charges
			end
		end
		local ability = event.ability
		if ability == "Shield" then
			state.shieldUntil = t + event.duration
			RunController.Event:Fire("🛡️ SHIELD UP!", Color3.fromRGB(120, 200, 255))
		elseif ability == "Magnet" then
			state.magnetUntil = t + event.duration
			state.magnetRadius = event.radius or 20
			RunController.Event:Fire("🧲 MAGNET!", Color3.fromRGB(255, 120, 120))
		elseif ability == "SpeedBoost" then
			state.boostUntil = t + event.duration
			state.boostMultiplier = event.multiplier or 1.3
			RunController.Event:Fire("⚡ SPEED BOOST!", Color3.fromRGB(255, 240, 80))
		elseif ability == "CoinDoubler" then
			state.doublerUntil = t + event.duration
			RunController.Event:Fire("🪙 DOUBLE COINS!", Color3.fromRGB(255, 210, 60))
		elseif ability == "Bomb" then
			state.gap = math.min(C.MaxGap, state.gap + C.BombPushback)
			addShake(1.6)
			DebrisFX.Explosion(event.center, event.radius)
			RunController.Event:Fire("💣 BOOM!", Color3.fromRGB(255, 120, 40))
		end
		RunController.LoadoutChanged:Fire()
	elseif event.type == "ShieldUsed" then
		state.shieldUntil = 0
	elseif event.type == "Charges" then
		for _, entry in state.loadout do
			if entry.slot == event.slot then
				entry.charges = event.charges
				RunController.Event:Fire(("%s +1 CHARGE!"):format(entry.icon), Color3.fromRGB(200, 140, 255))
			end
		end
		RunController.LoadoutChanged:Fire()
	elseif event.type == "BrainrotCaught" then
		RunController.Event:Fire(("%s CAUGHT %s!"):format(event.icon, string.upper(event.name)), Color3.fromRGB(255, 140, 230))
		RunController.BrainrotCaught:Fire(event)
	elseif event.type == "CrateFound" then
		RunController.Event:Fire("📦 BONUS CRATE FOUND!", Color3.fromRGB(255, 190, 40))
	elseif event.type == "BonusCoins" then
		state.coins += event.amount * (1 + (state.perks.CoinBonus or 0))
		RunController.Event:Fire(("🪙 +%d"):format(event.amount), Color3.fromRGB(255, 210, 60))
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
end

-- World-space position of the runner (for the camera and the chaser).
function RunController.WorldPosition(): Vector3
	return worldPosition()
end

return RunController
