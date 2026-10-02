--!strict
-- Makes the lobby feel alive, entirely client-side (no server bandwidth):
-- spinning crates, bobbing floaters, pulsing neon, Brainrots dancing on their
-- pedestals, Brainrots wandering the SAFE ZONE and moving conveyor stripes.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LobbyFX = {}

type Animated = { instance: Instance, base: CFrame, data: { [string]: any } }

local groups: { [string]: { Animated } } = {}
local enabled = true
local wanderState: { [Instance]: { home: Vector3, target: Vector3, pos: Vector3, yaw: number, rng: Random } } = {}

local function baseOf(instance: Instance): CFrame
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	return CFrame.identity
end

local function setCFrame(instance: Instance, cf: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cf)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cf
	end
end

local function track(tag: string)
	groups[tag] = {}
	local function add(instance: Instance)
		local attrs = instance:GetAttributes()
		table.insert(groups[tag], { instance = instance, base = baseOf(instance), data = attrs })
		if tag == "LobbyWander" then
			local home = baseOf(instance).Position
			wanderState[instance] = { home = home, target = home, pos = home, yaw = 0, rng = Random.new(attrs.Seed or 1) }
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	-- Plot Brainrots come and go as bases refresh.
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		local list = groups[tag]
		for i = #list, 1, -1 do
			if list[i].instance == instance then
				table.remove(list, i)
			end
		end
		wanderState[instance] = nil
	end)
end

local DANCES: { [string]: (t: number) -> CFrame } = {
	Spin = function(t)
		return CFrame.Angles(0, t * 2, 0)
	end,
	Wiggle = function(t)
		return CFrame.Angles(0, 0, math.sin(t * 8) * 0.25)
	end,
	Twirl = function(t)
		return CFrame.new(0, math.abs(math.sin(t * 3)) * 1.5, 0) * CFrame.Angles(0, t * 5, 0)
	end,
	Stomp = function(t)
		return CFrame.new(0, math.max(0, math.sin(t * 6)) * 1.2, 0)
	end,
	Sway = function(t)
		return CFrame.Angles(math.sin(t * 2) * 0.12, 0, math.sin(t * 1.5) * 0.18)
	end,
	Hop = function(t)
		return CFrame.new(0, math.abs(math.sin(t * 5)) * 2, 0)
	end,
	Bonk = function(t)
		return CFrame.Angles(math.max(0, math.sin(t * 1.5)) * 0.12, 0, 0)
	end,
}

local function step(dt: number)
	if not enabled then
		return
	end
	local t = os.clock()

	for _, a in groups.LobbySpin do
		local base = baseOf(a.instance)
		setCFrame(a.instance, base * CFrame.Angles(0, (a.data.Speed or 1) * dt, 0))
	end
	for _, a in groups.LobbySpinZ do
		local base = baseOf(a.instance)
		setCFrame(a.instance, base * CFrame.Angles(0, 0, (a.data.Speed or 1) * dt))
	end
	for _, a in groups.LobbyFloat do
		local current = baseOf(a.instance)
		local y = a.base.Position.Y + math.sin(t + (a.data.Phase or 0)) * (a.data.Amplitude or 2)
		setCFrame(a.instance, CFrame.new(current.Position.X, y, current.Position.Z) * current.Rotation)
	end
	for _, a in groups.LobbyPulse do
		if a.instance:IsA("BasePart") then
			a.instance.Transparency = 0.15 + (math.sin(t * 3 + a.base.Position.X) + 1) * 0.12
		end
	end
	for _, a in groups.LobbyDance do
		local dance = DANCES[a.data.Style or "Spin"] or DANCES.Spin
		setCFrame(a.instance, a.base * dance(t + a.base.Position.X))
	end
	for _, a in groups.LobbyWander do
		local w = wanderState[a.instance]
		if w then
			local toTarget = w.target - w.pos
			if toTarget.Magnitude < 1 then
				local angle = w.rng:NextNumber(0, math.pi * 2)
				local radius = w.rng:NextNumber(3, a.data.Radius or 15)
				w.target = w.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			else
				local speed = a.data.Speed or 6
				w.pos += toTarget.Unit * math.min(toTarget.Magnitude, speed * dt)
				local desiredYaw = math.atan2(-toTarget.X, -toTarget.Z)
				local diff = (desiredYaw - w.yaw + math.pi) % (math.pi * 2) - math.pi
				w.yaw += diff * math.min(1, dt * 5)
			end
			local hop = math.abs(math.sin(t * 9 + (a.data.Seed or 0))) * 0.6
			setCFrame(a.instance, CFrame.new(w.pos + Vector3.new(0, hop, 0)) * CFrame.Angles(0, w.yaw, 0))
		end
	end
end

-- Conveyor belts: the server part does the carrying (AssemblyLinearVelocity);
-- here we add yellow stripes that slide along it so you can see which way
-- it goes.
type Belt = { part: BasePart, stripes: { BasePart }, speed: number, spacing: number, offset: number }
local belts: { Belt } = {}
local STRIPE_SPACING = 4

local function addConveyor(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local belt: Belt = { part = instance, stripes = {}, speed = instance:GetAttribute("Speed") or 30, spacing = STRIPE_SPACING, offset = 0 }
	local count = math.floor(instance.Size.Z / STRIPE_SPACING)
	for _ = 1, count do
		local stripe = Instance.new("Part")
		stripe.Name = "ConveyorStripe"
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.CanTouch = false
		stripe.CastShadow = false
		stripe.Material = Enum.Material.Neon
		stripe.Color = Color3.fromRGB(255, 210, 50)
		stripe.Size = Vector3.new(instance.Size.X * 0.7, 0.05, 0.7)
		stripe.Parent = instance
		table.insert(belt.stripes, stripe)
	end
	table.insert(belts, belt)
end

local function stepConveyors(dt: number)
	for _, belt in belts do
		local p = belt.part
		local length = p.Size.Z
		belt.offset = (belt.offset + belt.speed * dt) % belt.spacing
		for i, stripe in belt.stripes do
			-- Stripes move toward the part's -Z (its LookVector = belt direction).
			local z = length / 2 - ((i - 1) * belt.spacing + belt.offset)
			if z < -length / 2 then
				z += length
			end
			stripe.CFrame = p.CFrame * CFrame.new(0, p.Size.Y / 2 + 0.03, z)
		end
	end
end

function LobbyFX.SetEnabled(value: boolean)
	enabled = value
end

function LobbyFX.Init()
	for _, tag in { "LobbySpin", "LobbySpinZ", "LobbyFloat", "LobbyPulse", "LobbyDance", "LobbyWander" } do
		track(tag)
	end
	for _, belt in CollectionService:GetTagged("Conveyor") do
		addConveyor(belt)
	end
	CollectionService:GetInstanceAddedSignal("Conveyor"):Connect(addConveyor)
	-- 🌈 Rainbow-mutated Brainrots cycle their colours (on bases and in cages).
	local rainbow: { [Model]: { BasePart } } = {}
	local function addRainbow(instance: Instance)
		if instance:IsA("Model") then
			local parts = {}
			for _, p in instance:GetChildren() do
				if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "Eye" and p.Name ~= "Pupil" then
					table.insert(parts, p)
				end
			end
			rainbow[instance] = parts
		end
	end
	for _, model in CollectionService:GetTagged("Rainbow") do
		addRainbow(model)
	end
	CollectionService:GetInstanceAddedSignal("Rainbow"):Connect(addRainbow)
	CollectionService:GetInstanceRemovedSignal("Rainbow"):Connect(function(instance)
		rainbow[instance :: Model] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local hue = os.clock() * 0.25
		for _, parts in rainbow do
			for i, p in parts do
				p.Color = Color3.fromHSV((hue + i * 0.07) % 1, 0.75, 1)
			end
		end
		step(dt)
		if enabled then
			stepConveyors(dt)
		end
	end)
end

return LobbyFX
