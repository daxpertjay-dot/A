--!strict
-- Makes the lobby feel alive, entirely client-side (no server bandwidth):
-- spinning crates, bobbing floaters, pulsing neon, NPCs doing stupid dances,
-- random Brainrots wandering around, loadout holograms and the collection
-- gallery (locked Brainrots show as black silhouettes).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local EquipmentData = require(Shared.EquipmentData)

local LobbyFX = {}

type Animated = { instance: Instance, base: CFrame, data: { [string]: any } }

local groups: { [string]: { Animated } } = {}
local enabled = true
local wanderState: { [Instance]: { home: Vector3, target: Vector3, pos: Vector3, yaw: number, rng: Random } } = {}
local originalColors: { [BasePart]: Color3 } = {}

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

-- Loadout holograms show the equipped item icons.
function LobbyFX.UpdateLoadout(loadout: { string }, unlockedSlots: number)
	for _, holo in CollectionService:GetTagged("LoadoutHolo") do
		if holo:IsA("BasePart") then
			local slot = holo:GetAttribute("Slot") or 1
			local gui = holo:FindFirstChild("Icon") :: BillboardGui?
			if not gui then
				local g = Instance.new("BillboardGui")
				g.Name = "Icon"
				g.Size = UDim2.fromOffset(120, 90)
				g.StudsOffset = Vector3.new(0, 3.5, 0)
				g.MaxDistance = 120
				local label = Instance.new("TextLabel")
				label.Name = "Text"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.FredokaOne
				label.TextScaled = true
				label.TextColor3 = Color3.new(1, 1, 1)
				label.Parent = g
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 2
				stroke.Parent = label
				g.Parent = holo
				gui = g
			end
			local label = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
			local item = EquipmentData.Get(loadout[slot])
			if slot > unlockedSlots then
				label.Text = "🔒\nLOCKED"
			elseif item then
				label.Text = item.icon .. "\n" .. item.name
				holo.Color = EquipmentData.RarityColors[item.rarity]
			else
				label.Text = "➕\nEMPTY"
			end
		end
	end
end

-- Collection gallery: unlocked Brainrots in full colour, locked as silhouettes.
function LobbyFX.UpdateCollection(collection: { [string]: boolean })
	for _, model in CollectionService:GetTagged("CollectionDisplay") do
		local id = model:GetAttribute("BrainrotId")
		local unlocked = collection[id] == true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				if originalColors[d] == nil then
					originalColors[d] = d.Color
				end
				d.Color = if unlocked then originalColors[d] else Color3.fromRGB(15, 15, 20)
			end
		end
	end
	for _, label in CollectionService:GetTagged("CollectionLabel") do
		if label:IsA("TextLabel") then
			local data = BrainrotData.Get(label:GetAttribute("BrainrotId") or "")
			if data and collection[data.id] then
				label.Text = data.icon .. " " .. data.name
			else
				label.Text = "??? LOCKED"
			end
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
	RunService.RenderStepped:Connect(step)
end

return LobbyFX
