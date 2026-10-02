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
--   RUNNING → side bump (switched lanes into something) → bounced back, slowed
--   RUNNING → CAUGHT (the villain got you)
--
-- Power-ups (🧲 magnet, 🚀 jetpack, 👟 super sneakers, ✖️2 booster) and the
-- 🛹 hoverboard are confirmed by the server and applied here. Sneakers and the
-- hoverboard boost your jump high enough to land on buses and tunnel roofs.
--
-- Tricks (clearing obstacles, last-second dodges, landing on a roof) are
-- spotted here and reported to the server, which owns the style combo; the
-- combo state below mirrors the server's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local Progression = require(Shared.Progression)
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
	stumbleTime = 0, -- wobble after bouncing off the side of something
	stumbleDir = 0,
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
	combo = Progression.NewCombo(), -- mirrors the server's style combo
	hype = 0, -- Hype charge left (spent as you run)
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
RunController.Style = Signal.new() -- (kind: string, stacksGained: number) a combo change confirmed by the server

local player = Players.LocalPlayer
local character: Model? = nil
local root: BasePart? = nil
local humanoid: Humanoid? = nil
local hipOffset = 3
local trackFolder: Instance? = nil
local board: BasePart? = nil
local jetpack: Model? = nil
local joints: { [string]: Motor6D } = {}
-- How far the runner steps up onto something without jumping. Low on purpose:
-- you land on roofs by jumping, you don't walk up them.
local STEP_UP = 1.6
-- Top of the runner's head above its feet (for tunnel ceilings).
local HEAD = R.HitboxHeight + 0.6

-- Probe params are configured in Prepare(), once the server has registered
-- the collision groups.
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local ignore: { [Instance]: number } = {}
local coins: { BasePart } = {}
local pickups: { BasePart } = {}
-- Obstacles ahead, for spotting tricks as the runner passes them.
type Tracked = { inst: Instance, d: number, lane: number, kind: string }
local obstacles: { Tracked } = {}
local lastDodge = { from = 0, time = -math.huge }
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
	local set = table.clone(if hum.RigType == Enum.HumanoidRigType.R6 then ANIMS.R6 else ANIMS.R15) :: { [string]: string }
	if ANIMS.Fly ~= "" then
		set.Fly = ANIMS.Fly
	end
	if ANIMS.Hoverboard ~= "" then
		set.Hoverboard = ANIMS.Hoverboard
	end
	for name, id in set do
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
	rootPart.Anchored = false -- Stop() freezes the character between runs
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
	table.clear(joints)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "RunPlayer"
		elseif d:IsA("Motor6D") then
			joints[d.Name] = d
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
	elseif d:IsA("Model") then
		local trackD, lane, kind = d:GetAttribute("TrackD"), d:GetAttribute("Lane"), d:GetAttribute("ObstacleType")
		if type(trackD) == "number" and type(lane) == "number" and type(kind) == "string" and not d:GetAttribute("NoStyle") then
			table.insert(obstacles, { inst = d, d = trackD, lane = lane, kind = kind })
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

-- Current score multiplier: base (Brainrots) × ✖️2 booster × combo × Hype.
function RunController.CurrentMultiplier(): number
	local booster = if now() < state.boosterUntil then 2 else 1
	return state.multiplier * booster * Progression.ComboMultiplier(state.combo) * Progression.HypeMultiplier(state.hype)
end

-- Height of whatever you'd stand on below `fromY` (and the part itself).
local function probeGround(x: number, d: number, fromY: number): (number?, BasePart?)
	if not trackFolder then
		return nil, nil
	end
	local origin = state.origin + Vector3.new(x, fromY, -d)
	local result = workspace:Raycast(origin, Vector3.new(0, -80, 0), rayParams)
	if result then
		return result.Position.Y - state.origin.Y, result.Instance :: BasePart
	end
	return nil, nil
end

-- Underside of anything standable above `fromY` (a tunnel roof).
local function probeCeiling(x: number, d: number, fromY: number): number?
	if not trackFolder then
		return nil
	end
	local origin = state.origin + Vector3.new(x, fromY, -d)
	local result = workspace:Raycast(origin, Vector3.new(0, 40, 0), rayParams)
	if result then
		return result.Position.Y - state.origin.Y
	end
	return nil
end

local function reportTrick(kind: string, object: Instance)
	Remotes.Event("ReportStyle"):FireServer(kind, object)
end

-- ───────────────────────────── actions ─────────────────────────────

local function changeLane(dir: number)
	local target = math.clamp(state.lane + dir, -1, 1)
	if target == state.lane then
		addShake(0.25)
		return
	end
	-- Remember the dodge: passing something in the old lane right after
	-- leaving it is a near miss.
	lastDodge.from = state.lane
	lastDodge.time = now()
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
	-- Jump boosts: 👟 sneakers or riding a 🛹 hoverboard (high enough for
	-- bus and tunnel roofs).
	local boost = 1
	if now() < state.sneakersUntil then
		boost = math.max(boost, P.SneakersJumpMultiplier)
	end
	if onBoard() then
		boost = math.max(boost, P.HoverboardJumpMultiplier)
	end
	state.vy = R.JumpVelocity * boost
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

-- Did we touch this from the side rather than run into its front? Either we
-- weren't lined up with it last frame (we moved sideways into it), or we're
-- already alongside it, past its front (e.g. running next to a bus).
local function hitFromSide(obstacle: Instance, part: BasePart, prevX: number): boolean
	local partX = part.Position.X - state.origin.X
	local reach = part.Size.X / 2 + R.HitboxWidth / 2
	if math.abs(partX - prevX) >= reach - 0.05 then
		return true
	end
	local trackD = obstacle:GetAttribute("TrackD")
	return type(trackD) == "number" and state.d - trackD > R.HitboxDepth + 1.5
end

-- Switched lanes into the side of something: bounce back off it into the
-- lane you came from (Subway Surfers style), stumble and lose speed. The
-- villain closes in, but it's not a crash. Returns false for a touch while
-- already bouncing away (that one doesn't count).
local function sideBump(obstacle: Instance, part: BasePart, t: number): boolean
	local partX = part.Position.X - state.origin.X
	local heading = LANES[state.lane] - state.x
	if heading * (partX - state.x) <= 0 then
		return false
	end
	local dir = if heading > 0 then 1 else -1
	if state.lane ~= state.fromLane then
		-- Reverse the lane change from wherever we are between the lanes.
		state.lane, state.fromLane = state.fromLane, state.lane
		state.laneT = 1 - state.laneT
	end
	ignore[obstacle] = t -- no near-miss credit for this one (doesn't block hits)
	state.stumbleTime = C.SideBumpStumble
	state.stumbleDir = dir
	state.speedFactor = math.min(state.speedFactor, C.SideBumpSpeed)
	loseGap(C.GapLoss.SideBump)
	state.combo.stacks /= 2 -- predicted; the server confirms
	addShake(0.6)
	RunController.Event:Fire("💥 BUMP!", Color3.fromRGB(255, 170, 90))
	RunController.Impact:Fire("Side")
	Remotes.Event("ReportHit"):FireServer(obstacle, { side = true })
	return true
end

-- Returns true when the hit stopped or bounced the runner (no more checks
-- this frame).
local function onObstacle(obstacle: Instance, part: BasePart, prevX: number): boolean
	local t = now()
	if (ignore[obstacle] or 0) > t or obstacle:GetAttribute("Destroyed") then
		return false
	end

	if hitFromSide(obstacle, part, prevX) then
		return sideBump(obstacle, part, t)
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
		state.combo.stacks = 0 -- predicted; the server confirms
		addShake(1.3)
		RunController.Event:Fire(if tier >= 4 then "😵 OUCH!" else "😵 CRASH! (keep hitting it…)", Color3.fromRGB(255, 90, 90))
	end
	RunController.Impact:Fire(result.outcome)
	return result.outcome == "Bump"
end

local function checkCollisions(prevD: number, prevX: number)
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
			if onObstacle(obstacle, part, prevX) then
				break
			end
		end
	end
end

-- ───────────────────────────── tricks (style combo) ─────────────────────────────

-- Called when the runner passes the front of an obstacle it didn't hit.
local function judgePass(o: Tracked, t: number)
	if ignore[o.inst] or o.inst:GetAttribute("Destroyed") or t < state.invulnerableUntil then
		return
	end
	if o.lane == state.lane then
		local cleared = if o.kind == "Jump" then (not state.grounded or state.feetY > 2)
			elseif o.kind == "Roll" then isRolling()
			else state.feetY > 3 -- over a wall / bus with a jump boost
		if cleared then
			reportTrick("Clear", o.inst)
		end
	elseif o.lane == lastDodge.from and t - lastDodge.time <= Config.Combo.NearMissWindow then
		reportTrick("NearMiss", o.inst)
	end
end

local function checkTricks(prevD: number)
	local flying = isFlying()
	local t = now()
	local i = 1
	while i <= #obstacles do
		local o = obstacles[i]
		if o.inst.Parent == nil or o.d < state.d - 30 then
			obstacles[i] = obstacles[#obstacles]
			obstacles[#obstacles] = nil
		else
			if not flying and prevD < o.d and state.d >= o.d then
				judgePass(o, t)
			end
			i += 1
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

-- ───────────────────────────── jetpack flight look ─────────────────────────────

-- A little jetpack with fire, strapped on while flying.
local function setJetpackVisible(visible: boolean)
	if visible and not jetpack then
		local m = Instance.new("Model")
		m.Name = "Jetpack"
		local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = material or Enum.Material.Metal
			if shape then
				p.Shape = shape
			end
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p:SetAttribute("Offset", offset)
			p.Parent = m
			return p
		end
		piece("Pack", Vector3.new(2.2, 2.4, 0.8), CFrame.new(0, 0.3, 0.9), Color3.fromRGB(200, 60, 60))
		for _, side in { -0.6, 0.6 } do
			piece("Tank", Vector3.new(2.6, 0.9, 0.9), CFrame.new(side, 0.3, 1.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 190, 200), nil, Enum.PartType.Cylinder)
			local flame = piece("Flame", Vector3.new(0.7, 1.8, 0.7), CFrame.new(side, -1.9, 1.5), Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 12
			fire.Color = Color3.fromRGB(255, 140, 40)
			fire.SecondaryColor = Color3.fromRGB(255, 230, 120)
			fire.Parent = flame
		end
		m.Parent = workspace
		jetpack = m
	elseif not visible and jetpack then
		jetpack:Destroy()
		jetpack = nil
	end
end

-- Built-in poses, held by setting joint Transforms every frame (with the
-- other animations stopped). Used unless Config.Animations has an id for
-- them. R15 joint frames line up with the character (X pitch, Y yaw, Z roll);
-- R6 limb joints are turned 90° so their axes differ.
local rad = math.rad
local POSES: { [string]: { R15: { [string]: CFrame }, R6: { [string]: CFrame } } } = {
	-- 🚀 Superman: one fist out in front, the other arm back, legs trailing.
	Fly = {
		R15 = {
			RightShoulder = CFrame.Angles(rad(170), 0, 0),
			LeftShoulder = CFrame.Angles(rad(-25), 0, rad(-8)),
			RightHip = CFrame.Angles(rad(-12), 0, 0),
			LeftHip = CFrame.Angles(rad(8), 0, 0),
		},
		R6 = {
			["Right Shoulder"] = CFrame.Angles(0, 0, rad(170)),
			["Left Shoulder"] = CFrame.Angles(0, 0, rad(25)),
		},
	},
	-- 🛹 Surf stance: body turned sideways on the board (the root is turned
	-- too, see BOARD_YAW), upper body and head twisted back to face forward,
	-- knees bent, arms out for balance.
	Board = {
		R15 = {
			Waist = CFrame.Angles(0, rad(-35), 0),
			Neck = CFrame.Angles(0, rad(-20), 0),
			RightShoulder = CFrame.Angles(0, 0, rad(70)),
			LeftShoulder = CFrame.Angles(0, 0, rad(-70)),
			RightElbow = CFrame.Angles(0, 0, rad(15)),
			LeftElbow = CFrame.Angles(0, 0, rad(-15)),
			RightHip = CFrame.Angles(rad(30), 0, rad(10)),
			LeftHip = CFrame.Angles(rad(30), 0, rad(-10)),
			RightKnee = CFrame.Angles(rad(-45), 0, 0),
			LeftKnee = CFrame.Angles(rad(-45), 0, 0),
		},
		R6 = {
			["Right Shoulder"] = CFrame.Angles(rad(-70), 0, 0),
			["Left Shoulder"] = CFrame.Angles(rad(-70), 0, 0),
			["Right Hip"] = CFrame.Angles(rad(-12), 0, 0),
			["Left Hip"] = CFrame.Angles(rad(-12), 0, 0),
		},
	},
}
local BOARD_YAW = rad(55) -- surfing sideways
local BOARD_CROUCH = 0.3 -- bent knees lower the hips

local posedJoints: { [string]: boolean } = {}
local currentPose: string? = nil

-- Holds a built-in pose (nil releases every posed joint).
local function applyPose(name: string?)
	local r15 = humanoid ~= nil and (humanoid :: Humanoid).RigType == Enum.HumanoidRigType.R15
	local pose = if name then (if r15 then POSES[name].R15 else POSES[name].R6) else {}
	for jointName in posedJoints do
		if not pose[jointName] then
			local j = joints[jointName]
			if j then
				j.Transform = CFrame.identity
			end
			posedJoints[jointName] = nil
		end
	end
	for jointName, cf in pose do
		local j = joints[jointName]
		if j then
			j.Transform = cf
			posedJoints[jointName] = true
		end
	end
	currentPose = name
end

-- Plays the animation `trackName` if one is configured, otherwise holds the
-- built-in pose `poseName`.
local function animOrPose(trackName: string, poseName: string)
	if tracks[trackName] then
		if currentPose then
			applyPose(nil)
		end
		playAnim(trackName)
		return
	end
	if currentAnim ~= poseName then
		for _, t in tracks do
			t:Stop(0.1)
		end
		currentAnim = poseName
	end
	applyPose(poseName)
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
	if state.stumbleTime > 0 then
		-- Knocked sideways off the thing we bumped into.
		lean += state.stumbleDir * math.sin(state.stumbleTime / C.SideBumpStumble * math.pi) * 0.45
	end
	local flying = state.move == "Flying"
	local flyTilt = if flying then -1.15 else 0
	-- Surfing: on the board, not flying or mid-roll.
	local surfing = onBoard() and state.phase == "Running" and not flying and not isRolling()
	local boardLift = if onBoard() then 0.8 - (if surfing then BOARD_CROUCH else 0) else 0
	local yaw = if surfing then BOARD_YAW else 0
	local pos = worldPosition() + Vector3.new(0, hipOffset - rollDrop + boardLift, 0)
	rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(rollPitch + stagger + flyTilt, 0, lean)
	rootPart.AssemblyLinearVelocity = Vector3.new(xVelocity, state.vy, -state.speed)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	setBoardVisible(onBoard() and state.phase == "Running")
	setJetpackVisible(flying)
	if jetpack then
		local bob = CFrame.new(0, math.sin(state.elapsed * 6) * 0.15, 0)
		for _, p in (jetpack :: Model):GetChildren() do
			if p:IsA("BasePart") then
				p.CFrame = rootPart.CFrame * bob * (p:GetAttribute("Offset") :: CFrame)
			end
		end
	end
	if board then
		board.CFrame = CFrame.new(worldPosition() + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, lean)
	end

	-- Animation selection
	if state.phase ~= "Running" then
		applyPose(nil)
		playAnim("Idle")
	elseif flying then
		animOrPose("Fly", "Fly")
	elseif surfing then
		-- Same stance on the ground and in the air: surfers don't run.
		animOrPose("Hoverboard", "Board")
	elseif not state.grounded then
		applyPose(nil)
		if currentAnim ~= "Jump" then
			playAnim("Jump")
		end
	else
		applyPose(nil)
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
	if state.stumbleTime > 0 then
		state.stumbleTime = math.max(0, state.stumbleTime - dt)
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
	-- Hype is spent as you go; the combo drains when you play it safe.
	local meters = math.max(0, state.d - prevD) * R.MetersPerStud
	state.score += meters * Config.Score.PointsPerMeter * RunController.CurrentMultiplier()
	state.hype = math.max(0, state.hype - meters * Progression.HypeDrainPerMeter())
	Progression.ComboDecay(state.combo, t, dt)

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
		local prevFeet = state.feetY
		state.vy -= R.Gravity * dt
		state.feetY += state.vy * dt
		if state.vy > 0 then
			-- Bonk your head on a tunnel ceiling instead of passing through it.
			local ceiling = probeCeiling(state.x, state.d, prevFeet + 0.5)
			if ceiling and state.feetY + HEAD > ceiling and prevFeet + HEAD <= ceiling + 0.05 then
				state.feetY = ceiling - HEAD
				state.vy = 0
			end
		end
		local ground, groundPart = probeGround(state.x, state.d, math.max(state.feetY, prevFeet) + STEP_UP)
		state.groundY = ground or -math.huge
		if ground and state.vy <= 0 and state.feetY <= ground + 0.05 then
			state.feetY = ground
			state.vy = 0
			local justLanded = not state.grounded
			state.grounded = true
			if justLanded and ground >= R.HighGround and groundPart then
				-- Landed on a bus / tunnel roof.
				reportTrick("Roof", groundPart)
			end
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

	checkCollisions(prevD, prevX)
	checkTricks(prevD)
	updateCollectibles(dt)

	-- Chase pressure
	if state.staggerTime <= 0 then
		state.gap = math.min(C.MaxGap, state.gap + C.RecoverPerSecond * dt)
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
	state.rollTime, state.staggerTime, state.stumbleTime = 0, 0, 0
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
	state.combo = Progression.NewCombo()
	state.hype = info.hype or 0
	state.score = 0
	state.coins = 0
	state.meters = 0
	state.elapsed = 0
	state.shake = 0
	table.clear(ignore)
	table.clear(coins)
	table.clear(pickups)
	table.clear(obstacles)
	lastDodge.time = -math.huge

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

-- A ring of light bursting out from the runner (the server blows away the
-- structures around you at the same moment).
local function shockwave()
	local ball = Instance.new("Part")
	ball.Name = "ReviveShockwave"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 4
	ball.CFrame = CFrame.new(bodyCenter())
	ball.Color = Color3.fromRGB(140, 255, 160)
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.2
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Parent = workspace
	local tween = TweenService:Create(ball, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 140, Transparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		ball:Destroy()
	end)
end

function RunController.Revive()
	state.phase = "Running"
	state.combo.stacks = 0
	state.gap = C.RevivedGap
	state.invulnerableUntil = now() + C.RevivedInvulnerability
	state.staggerTime = 0
	state.speedFactor = 0.6
	addShake(1.6)
	shockwave()
	RunController.Event:Fire("💪 REVIVED! 💥 SHOCKWAVE!", Color3.fromRGB(140, 255, 140))
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
			RunController.Event:Fire("👟 SUPER SNEAKERS! Jump onto wagons & roofs!", Color3.fromRGB(120, 255, 140))
		elseif event.id == "ScoreBooster" then
			state.boosterUntil = until_
			RunController.Event:Fire("✖️2 SCORE BOOSTER!", Color3.fromRGB(110, 190, 255))
		end
		RunController.PowerUpStarted:Fire(event.id)
	elseif event.type == "Hoverboard" then
		state.hoverUntil = t + event.duration
		state.durations.Hoverboard = event.duration
		state.hoverboards = event.left
		RunController.Event:Fire("🛹 HOVERBOARD! Big jumps + one free crash", Color3.fromRGB(120, 200, 255))
	elseif event.type == "HoverboardBroken" then
		state.hoverUntil = 0
	elseif event.type == "MysteryBox" then
		local text = if event.kind == "Coins" then ("❓ MYSTERY BOX: 🪙 %d!"):format(event.amount) else ("❓ MYSTERY BOX: 🛹 x%d!"):format(event.amount)
		if event.kind == "Coins" then
			state.coins += event.amount
		end
		RunController.Event:Fire(text, Color3.fromRGB(255, 200, 60))
	elseif event.type == "BrainrotRescued" then
		RunController.Event:Fire(("🔓 RESCUED %s!"):format(string.upper(event.label)), Color3.fromRGB(255, 140, 230))
	elseif event.type == "Combo" then
		-- The server owns the combo; adopt its value.
		state.combo.stacks = event.stacks
		if (event.gained or 0) > 0 then
			state.combo.lastAction = t
		end
		RunController.Style:Fire(event.kind, event.gained or 0)
	end
end

function RunController.Stop()
	state.phase = "Idle"
	RunService:UnbindFromRenderStep("BrainrotRunController")
	-- Freeze the character where it is. During a run it collides with
	-- nothing, so left alone it would drop out of the world (and die) while
	-- the results are up. Going back to the base gives a fresh character.
	local rootPart = root
	if rootPart and rootPart.Parent then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.Anchored = true
	end
	if character then
		character:SetAttribute("RunFinished", true) -- the lobby waits for the fresh one
	end
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
	setJetpackVisible(false)
	applyPose(nil)
end

-- World-space position of the runner (for the camera and the chaser).
function RunController.WorldPosition(): Vector3
	return worldPosition()
end

return RunController
