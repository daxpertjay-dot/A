--!strict
-- Client-side destruction visuals. The server decides WHAT breaks; this
-- module makes it look physical: it spawns a limited number of local,
-- unanchored debris pieces, flings them with impulses and cleans them up
-- after a few seconds. The local player's own crashes are predicted
-- instantly (hide the object + spawn debris) so impacts feel immediate.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DebrisFX = {}

local folder: Folder? = nil
local active = 0
local predicted: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "LocalDebris"
	f.Parent = workspace
	folder = f
	return f
end

local function spawnPiece(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, impact: Vector3, force: number)
	if active >= Config.Destruction.MaxClientDebris then
		return
	end
	active += 1
	local p = Instance.new("Part")
	p.Name = "Debris"
	p.Size = Vector3.new(math.max(0.2, size.X), math.max(0.2, size.Y), math.max(0.2, size.Z))
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CollisionGroup = "Debris"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = container()

	-- Fling outward from the impact, biased forward (down the track) and up.
	local away = cf.Position - impact
	local dir = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 1, 0)
	local speed = force * rng:NextNumber(0.35, 0.8)
	p.AssemblyLinearVelocity = dir * speed + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(12, 28), -force * 0.5)
	p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))

	local lifetime = Config.Destruction.DebrisLifetime
	task.delay(lifetime - 0.6, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
	task.delay(lifetime, function()
		active -= 1
	end)
	Debris:AddItem(p, lifetime)
end

-- Instantly "breaks" an obstacle locally. The server confirms shortly after.
function DebrisFX.PredictBreak(obstacle: Instance, impact: Vector3, force: number)
	predicted[obstacle] = true
	local spawned = 0
	local parts = {}
	for _, d in obstacle:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "StandTop" then
			d.CanQuery = false -- predicted gone: don't land on it
		elseif d:IsA("BasePart") and d.Name ~= "Rubble" then
			table.insert(parts, d)
		end
	end
	table.sort(parts, function(a, b)
		return (a.Position - impact).Magnitude < (b.Position - impact).Magnitude
	end)
	for _, part in parts do
		if spawned < Config.Destruction.MaxDebrisPerEvent then
			if part.Size.Magnitude > 6 then
				-- Big solid parts shatter into chunks
				for _ = 1, 3 do
					local chunk = part.Size * rng:NextNumber(0.25, 0.4)
					local offset = Vector3.new(rng:NextNumber(-0.4, 0.4) * part.Size.X, rng:NextNumber(-0.4, 0.4) * part.Size.Y, 0)
					spawnPiece(part.CFrame * CFrame.new(offset), chunk, part.Color, part.Material, impact, force)
					spawned += 1
				end
			else
				spawnPiece(part.CFrame, part.Size, part.Color, part.Material, impact, force)
				spawned += 1
			end
		end
		part.Transparency = 1
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceGui") then
				child.Enabled = false
			end
		end
	end
end

-- Debris sent by the server for destruction this client didn't predict
-- (equipment explosions, walls chipped by bumps).
function DebrisFX.FromServer(pieces: { any }, impact: Vector3, force: number, object: Instance?)
	if object and predicted[object] then
		return
	end
	for _, piece in pieces do
		spawnPiece(piece.cf, piece.size, piece.color, piece.material, impact, force)
	end
end

function DebrisFX.Explosion(center: Vector3, radius: number)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 150, 40)
	ball.Size = Vector3.one * 4
	ball.CFrame = CFrame.new(center)
	ball.Parent = container()
	TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 1.6,
		Transparency = 1,
		Color = Color3.fromRGB(255, 60, 160),
	}):Play()
	Debris:AddItem(ball, 0.6)

	-- Visual-only explosion (no pressure: the server already did the damage).
	local explosion = Instance.new("Explosion")
	explosion.Position = center
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = container()
end

function DebrisFX.Init()
	Remotes.Event("RunDebris").OnClientEvent:Connect(DebrisFX.FromServer)
end

return DebrisFX
