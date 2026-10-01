--!strict
-- Builds the blocky "tycoon street" lobby (think Steal a Brainrot / Grow a
-- Garden): classic studs, bright flat colours, a central street with shop
-- stalls down the middle, a conveyor loop around it and player plots on
-- both sides (plots themselves are built by PlotManager).
--
--        [plot] [plot] [plot] [plot]          ← side -1 (west)
--      ═▶═══════════ conveyor ═══════════▶═╗
--        spawn · 📦 crate shop · 🛒 shop     ║   ← hub strip
--        🎁 daily · 🏆 leaderboard           ║
--      ╚═◀═══════════ conveyor ═══════════◀═╝
--        [plot] [plot] [plot] [plot]          ← side +1 (east)

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local LobbyBuilder = {}

local L = Config.Lobby
local ORIGIN = L.Origin

LobbyBuilder.Colors = {
	Grass = Color3.fromRGB(88, 190, 70),
	GrassDark = Color3.fromRGB(70, 160, 55),
	Street = Color3.fromRGB(99, 95, 98),
	Sidewalk = Color3.fromRGB(205, 205, 200),
	Belt = Color3.fromRGB(40, 40, 46),
	BeltEdge = Color3.fromRGB(245, 205, 50),
	Wood = Color3.fromRGB(160, 110, 60),
	Leaves = Color3.fromRGB(60, 170, 60),
	Bright = {
		Color3.fromRGB(255, 89, 89),
		Color3.fromRGB(255, 176, 0),
		Color3.fromRGB(255, 230, 70),
		Color3.fromRGB(90, 200, 90),
		Color3.fromRGB(70, 160, 255),
		Color3.fromRGB(170, 100, 255),
		Color3.fromRGB(255, 120, 200),
	},
}
local COLORS = LobbyBuilder.Colors

local lobby: Folder
local rng = Random.new(2024)

-- Length of the street covered by plots (Z extent).
function LobbyBuilder.StreetLength(): number
	return L.PlotsPerSide * (L.PlotWidth + L.PlotGap) + L.PlotGap
end

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- ───────────────────────────── studs ─────────────────────────────

local STUD_FACES = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local function faceSize(size: Vector3, face: Enum.NormalId): (number, number)
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return size.X, size.Z
	elseif face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return size.X, size.Y
	end
	return size.Z, size.Y
end

-- The square stud texture on every visible face big enough to show it
-- (the bottom is never seen). The image is a transparent overlay, so the
-- part's own colour shows through.
local function studTexture(p: BasePart)
	if p.Transparency >= 1 or p.Material == Enum.Material.Neon then
		return
	end
	if p:IsA("Part") and (p :: Part).Shape ~= Enum.PartType.Block then
		return
	end
	for _, face in STUD_FACES do
		local u, v = faceSize(p.Size, face)
		if u >= 1 and v >= 1 then
			local texture = Instance.new("Texture")
			texture.Name = "Studs"
			texture.Texture = L.StudTexture
			texture.Face = face
			texture.StudsPerTileU = L.StudTextureSize
			texture.StudsPerTileV = L.StudTextureSize
			texture.Parent = p
		end
	end
end

-- Every lobby part gets the stud look unless told otherwise: the square
-- stud texture if one is set up (Config.Lobby.StudTexture), otherwise
-- Roblox's classic round studs.
local function part(props: Util.PartProps): BasePart
	props.Parent = props.Parent or lobby
	local studs = if props.Studs == nil then L.UseStuds else props.Studs
	local textured = studs and L.StudTexture ~= ""
	props.Studs = studs and not textured
	if props.Material == nil then
		props.Material = if textured then Enum.Material.SmoothPlastic else Enum.Material.Plastic
	end
	local p = Util.Part(props)
	if textured then
		studTexture(p)
	end
	return p
end
LobbyBuilder.Part = part

-- ───────────────────────────── your models ─────────────────────────────

-- Places your own model of `kind` (ServerStorage.LobbyProps.<kind>) standing
-- on the ground at `position`. Returns false when there isn't one, so the
-- caller builds its blocky stand-in instead.
function LobbyBuilder.Prop(kind: string, parent: Instance, position: Vector3, scale: number?): boolean
	local folder = ServerStorage:FindFirstChild(L.PropsFolder)
	local template = folder and folder:FindFirstChild(kind)
	if not template or not template:IsA("Model") then
		return false
	end
	local model = template:Clone()
	if scale and scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- Stand it on the ground: put the bottom of its bounding box at `position`.
	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()
	local pivotAboveBottom = pivot.Position.Y - (box.Position.Y - size.Y / 2)
	model:PivotTo(CFrame.new(position + Vector3.new(0, pivotAboveBottom, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * pivot.Rotation)
	model.Parent = parent
	return true
end

local function tag(instance: Instance, tagName: string, attrs: { [string]: any }?)
	CollectionService:AddTag(instance, tagName)
	if attrs then
		for k, v in attrs do
			instance:SetAttribute(k, v)
		end
	end
end

function LobbyBuilder.Prompt(parent: BasePart, action: string, objectText: string, panel: string, arg: string?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p:SetAttribute("OpenPanel", panel)
	if arg then
		p:SetAttribute("PanelArg", arg)
	end
	p.Parent = parent
	return p
end

-- A chunky block sign with a text face pointing toward `facing`.
function LobbyBuilder.Sign(parent: Instance, position: Vector3, facing: Vector3, text: string, color: Color3, width: number, height: number, postHeight: number?): TextLabel
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	if postHeight and postHeight > 0 then
		for _, side in { -1, 1 } do
			part({ Parent = parent, Name = "SignPost", Size = Vector3.new(1, postHeight, 1), CFrame = cf * CFrame.new(side * (width / 2 - 1), -height / 2 - postHeight / 2, 0), Color = COLORS.Wood })
		end
	end
	part({ Parent = parent, Name = "Sign", Size = Vector3.new(width, height, 1), CFrame = cf, Color = color })
	local face = part({ Parent = parent, Name = "SignFace", Size = Vector3.new(width - 1, height - 1, 0.2), CFrame = cf * CFrame.new(0, 0, -0.6), Color = Color3.fromRGB(255, 255, 255), Studs = false })
	return Util.SurfaceLabel(face, Enum.NormalId.Front, text, { TextColor = color, PixelsPerStud = 24 })
end

-- Blocky tree: a trunk and a few leafy cubes (or your "Tree" model).
function LobbyBuilder.Tree(parent: Instance, position: Vector3, scale: number?, kind: string?)
	if LobbyBuilder.Prop(kind or "Tree", parent, position) then
		return
	end
	local s = scale or 1
	part({ Parent = parent, Name = "Trunk", Size = Vector3.new(2, 7, 2) * s, CFrame = CFrame.new(position + Vector3.new(0, 3.5 * s, 0)), Color = COLORS.Wood })
	part({ Parent = parent, Name = "Leaves", Size = Vector3.new(8, 5, 8) * s, CFrame = CFrame.new(position + Vector3.new(0, 9 * s, 0)), Color = COLORS.Leaves })
	part({ Parent = parent, Name = "Leaves", Size = Vector3.new(5, 3, 5) * s, CFrame = CFrame.new(position + Vector3.new(0, 12.5 * s, 0)), Color = COLORS.GrassDark })
end

-- A blocky bush: a few green cubes (or your "Bush" model).
function LobbyBuilder.Bush(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Bush", parent, position) then
		return
	end
	part({ Parent = parent, Name = "Bush", Size = Vector3.new(4, 3, 4), CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)), Color = COLORS.Leaves })
	part({ Parent = parent, Name = "Bush", Size = Vector3.new(3, 2, 3), CFrame = CFrame.new(position + Vector3.new(1.6, 1, 1.2)), Color = COLORS.GrassDark })
end

-- A blocky rock (or your "Rock" model).
function LobbyBuilder.Rock(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Rock", parent, position) then
		return
	end
	local grey = Color3.fromRGB(140, 140, 150)
	part({ Parent = parent, Name = "Rock", Size = Vector3.new(4, 2.4, 3), CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = grey })
	part({ Parent = parent, Name = "Rock", Size = Vector3.new(2, 1.4, 2), CFrame = CFrame.new(position + Vector3.new(2.2, 0.7, 0.6)), Color = grey:Lerp(Color3.new(0, 0, 0), 0.15) })
end

function LobbyBuilder.Lamp(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Lamp", parent, position) then
		return
	end
	part({ Parent = parent, Name = "LampPost", Size = Vector3.new(1, 12, 1), CFrame = CFrame.new(position + Vector3.new(0, 6, 0)), Color = Color3.fromRGB(50, 50, 60) })
	local bulb = part({ Parent = parent, Name = "LampBulb", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 13, 0)), Color = Color3.fromRGB(255, 240, 170), Material = Enum.Material.Neon, Studs = false })
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Parent = bulb
end

-- ───────────────────────────── ground & street ─────────────────────────────

local function buildGround()
	local streetLength = LobbyBuilder.StreetLength()
	local half = streetLength / 2
	local outer = L.StreetHalfWidth + L.PlotDepth + 30
	-- Big grass field (in tiles so studs stay crisp)
	local tile = 60
	local ix = 0
	for x = -outer, outer - 1, tile do
		ix += 1
		local iz = 0
		for z = -half - 60, half + 59, tile do
			iz += 1
			part({ Name = "Grass", Size = Vector3.new(tile, 2, tile), CFrame = CFrame.new(at(x + tile / 2, -1, z + tile / 2)), Color = if (ix + iz) % 2 == 0 then COLORS.Grass else COLORS.GrassDark })
		end
	end
	-- Street down the middle
	part({ Name = "Street", Size = Vector3.new(L.StreetHalfWidth * 2, 0.4, streetLength + 60), CFrame = CFrame.new(at(0, 0.2, 0)), Color = COLORS.Street })
	-- Sidewalk strip in the middle where the shops live
	part({ Name = "HubStrip", Size = Vector3.new(L.StreetHalfWidth * 2 - 24, 0.6, streetLength + 20), CFrame = CFrame.new(at(0, 0.5, 0)), Color = COLORS.Sidewalk })
	-- Invisible walls around the map
	for _, dir in { Vector3.xAxis, -Vector3.xAxis } do
		part({ Name = "Boundary", Size = Vector3.new(2, 100, streetLength + 140), CFrame = CFrame.new(at(dir.X * (outer + 1), 50, 0)), Transparency = 1, Studs = false })
	end
	for _, dir in { 1, -1 } do
		part({ Name = "Boundary", Size = Vector3.new(outer * 2 + 4, 100, 2), CFrame = CFrame.new(at(0, 50, dir * (half + 61))), Transparency = 1, Studs = false })
	end
end

-- ───────────────────────────── conveyors ─────────────────────────────

-- A conveyor belt: an anchored part with a linear velocity carries anything
-- standing on it. LobbyFX adds the moving stripes client-side.
local function conveyor(from: Vector3, to: Vector3)
	local dir = (to - from)
	local length = dir.Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	local belt = part({
		Name = "Conveyor",
		Size = Vector3.new(L.ConveyorWidth, 1, length),
		CFrame = cf,
		Color = COLORS.Belt,
		Material = Enum.Material.SmoothPlastic,
		Studs = false,
	})
	belt.AssemblyLinearVelocity = dir.Unit * L.ConveyorSpeed
	tag(belt, "Conveyor", { Speed = L.ConveyorSpeed })
	for _, side in { -1, 1 } do
		part({ Name = "ConveyorEdge", Size = Vector3.new(0.6, 1.4, length), CFrame = cf * CFrame.new(side * (L.ConveyorWidth / 2 + 0.3), 0.2, 0), Color = COLORS.BeltEdge })
	end
end

local function buildConveyors()
	local half = LobbyBuilder.StreetLength() / 2 + 6
	local x = L.StreetHalfWidth - 7
	local y = 0.9
	-- One loop around the hub strip: up the west side, across, down the east side, back.
	conveyor(at(-x, y, -half), at(-x, y, half))
	conveyor(at(-x - L.ConveyorWidth / 2, y, half + L.ConveyorWidth / 2 + 0.1), at(x + L.ConveyorWidth / 2, y, half + L.ConveyorWidth / 2 + 0.1))
	conveyor(at(x, y, half), at(x, y, -half))
	conveyor(at(x + L.ConveyorWidth / 2, y, -half - L.ConveyorWidth / 2 - 0.1), at(-x - L.ConveyorWidth / 2, y, -half - L.ConveyorWidth / 2 - 0.1))
end

-- ───────────────────────────── hub ─────────────────────────────

local function stall(position: Vector3, facing: Vector3, title: string, color: Color3): CFrame
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	-- Counter, posts and a striped roof, all blocky.
	part({ Name = "Counter", Size = Vector3.new(26, 4, 4), CFrame = cf * CFrame.new(0, 2, -6), Color = color })
	part({ Name = "CounterTop", Size = Vector3.new(27, 0.6, 5), CFrame = cf * CFrame.new(0, 4.3, -6), Color = Color3.fromRGB(255, 255, 255) })
	for _, sx in { -13, 13 } do
		for _, sz in { -7, 7 } do
			part({ Name = "StallPost", Size = Vector3.new(1.2, 13, 1.2), CFrame = cf * CFrame.new(sx, 6.5, sz), Color = COLORS.Wood })
		end
	end
	for i = -6, 6 do
		part({ Name = "Roof", Size = Vector3.new(2.2, 1, 18), CFrame = cf * CFrame.new(i * 2.2, 13.5, 0), Color = if i % 2 == 0 then color else Color3.fromRGB(255, 255, 255) })
	end
	LobbyBuilder.Sign(lobby, (cf * CFrame.new(0, 17, -7)).Position, facing, title, color, 24, 5)
	return cf
end

local function buildHub()
	local half = LobbyBuilder.StreetLength() / 2

	-- Spawn in the middle of the street.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(at(0, 1.3, 0))
	spawnLocation.Anchored = true
	spawnLocation.Color = Color3.fromRGB(255, 255, 255)
	spawnLocation.TopSurface = Enum.SurfaceType.Studs
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = lobby

	-- Giant statue of the villain with a WANTED sign
	local statue = ModelFactory.Villain(2.6)
	statue.Name = "VillainStatue"
	part({ Name = "StatueBase", Size = Vector3.new(14, 3, 14), CFrame = CFrame.new(at(0, 2.3, -22)), Color = Color3.fromRGB(150, 150, 160) })
	statue:PivotTo(CFrame.lookAt(at(0, 3.8, -22), at(0, 3.8, 0)))
	statue.Parent = lobby
	tag(statue, "LobbyDance", { Style = "Sway" })
	LobbyBuilder.Sign(lobby, at(0, 3.3, -14.4), at(0, 3.3, 0), ("WANTED: %s\nhe kidnapped the Brainrots!"):format(Config.Villain.Title), Color3.fromRGB(200, 40, 40), 12, 3)

	-- Title sign across the street
	LobbyBuilder.Sign(lobby, at(0, 30, 16), at(0, 30, 100), "🧠 BRAINROT RUNNER 🧠", COLORS.Bright[1], 44, 9, 25)

	-- ⬆️ Upgrade shop: spend coins on power-ups, pedestals and hoverboards.
	local upgradeCf = stall(at(0, 0.8, 50), at(0, 0.8, 0), "⬆️ UPGRADES", COLORS.Bright[5])
	for i, icon in { "🧲", "🚀", "👟", "✖️2" } do
		local standCf = upgradeCf * CFrame.new((i - 2.5) * 6, 0, -6)
		local orb = part({ Name = "UpgradeOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = standCf * CFrame.new(0, 7, 0), Color = COLORS.Bright[i + 1], Material = Enum.Material.Neon, Studs = false })
		tag(orb, "LobbyFloat", { Phase = i, Amplitude = 0.6 })
		Util.Billboard(orb, icon, UDim2.fromOffset(60, 60), Vector3.new(0, 3, 0))
		LobbyBuilder.Prompt(orb, "Upgrade", "Power-ups", "Upgrades")
	end

	-- 🛒 Coin shop
	local shopCf = stall(at(0, 0.8, -50), at(0, 0.8, 0), "🛒 SHOP", COLORS.Bright[4])
	local counter = part({ Name = "ShopCounterPrompt", Size = Vector3.new(26, 1, 4), CFrame = shopCf * CFrame.new(0, 4.8, -6), Transparency = 1, CanCollide = false, Studs = false })
	LobbyBuilder.Prompt(counter, "Shop", "Brainrot Shop", "Shop")
	local seller = ModelFactory.Brainrot("BallerinaCappuccina", 1)
	seller:PivotTo(CFrame.lookAt(shopCf.Position, at(0, 0.8, 0)))
	seller.Parent = lobby
	tag(seller, "LobbyDance", { Style = "Twirl" })

	-- 🎁 Daily reward: a giant blocky present
	local giftPos = at(0, 0.8, -95)
	local gift = part({ Name = "GiftBox", Size = Vector3.new(10, 10, 10), CFrame = CFrame.new(giftPos + Vector3.new(0, 5, 0)), Color = COLORS.Bright[1] })
	part({ Name = "Ribbon", Size = Vector3.new(10.2, 10.2, 2), CFrame = gift.CFrame, Color = COLORS.Bright[3], CanCollide = false })
	part({ Name = "Ribbon", Size = Vector3.new(2, 10.2, 10.2), CFrame = gift.CFrame, Color = COLORS.Bright[3], CanCollide = false })
	local bow = part({ Name = "Bow", Size = Vector3.new(4, 2, 4), CFrame = gift.CFrame * CFrame.new(0, 6, 0), Color = COLORS.Bright[3], CanCollide = false })
	tag(bow, "LobbySpin", { Speed = 2 })
	LobbyBuilder.Prompt(gift, "Claim", "Daily Reward", "Daily")
	Util.Billboard(gift, "🎁 DAILY REWARD", UDim2.fromOffset(200, 40), Vector3.new(0, 10, 0), COLORS.Bright[3])

	-- 🏆 Leaderboard at the north end of the street
	local boardPos = at(0, 20, half - 4)
	local boardCf = CFrame.lookAt(boardPos, at(0, 20, 0))
	part({ Name = "BoardFrame", Size = Vector3.new(44, 30, 2), CFrame = boardCf, Color = COLORS.Bright[2] })
	local screen = part({ Name = "LeaderboardScreen", Size = Vector3.new(40, 26, 0.4), CFrame = boardCf * CFrame.new(0, 0, -1.2), Color = Color3.fromRGB(25, 20, 40), Studs = false })
	tag(screen, "LeaderboardScreen")
	for _, side in { -1, 1 } do
		part({ Name = "BoardLeg", Size = Vector3.new(3, 20, 3), CFrame = boardCf * CFrame.new(side * 18, -24, 0), Color = COLORS.Wood })
	end
	local leaderboardPrompt = part({ Name = "LeaderboardPrompt", Size = Vector3.new(10, 6, 4), CFrame = CFrame.new(at(0, 3.8, half - 10)), Transparency = 1, CanCollide = false, Studs = false })
	LobbyBuilder.Prompt(leaderboardPrompt, "View", "Leaderboards", "Leaderboard")

	-- Blocky trees, flower beds and lamps down the hub strip
	for z = -half + 10, half - 20, 30 do
		for _, side in { -1, 1 } do
			local x = side * (L.StreetHalfWidth - 17)
			if math.abs(z - 50) > 14 and math.abs(z + 50) > 14 and math.abs(z + 95) > 10 and math.abs(z) > 10 then
				if (z // 30) % 2 == 0 then
					LobbyBuilder.Tree(lobby, at(x, 0.8, z), 0.8)
				else
					LobbyBuilder.Lamp(lobby, at(x, 0.8, z))
				end
			end
		end
	end
	for i, z in { -75, 25, 80, 120 } do
		if not LobbyBuilder.Prop("Flowers", lobby, at(0, 0.8, z)) then
			local bed = part({ Name = "FlowerBed", Size = Vector3.new(10, 1.4, 6), CFrame = CFrame.new(at(0, 1.5, z)), Color = COLORS.Wood })
			for f = -2, 2 do
				part({ Name = "Flower", Size = Vector3.new(1.2, 1.2, 1.2), CFrame = bed.CFrame * CFrame.new(f * 1.8, 1.3, (f % 2) * 1.5 - 0.7), Color = COLORS.Bright[(i + f) % #COLORS.Bright + 1], Studs = false })
			end
		end
	end

	-- A few Brainrots wander the hub for life
	for i, brainrot in BrainrotData.List do
		if i > 1 and i % 2 == 0 then
			local model = ModelFactory.Brainrot(brainrot.id, 1)
			model.Name = "Wanderer_" .. brainrot.id
			model:PivotTo(CFrame.new(at(rng:NextNumber(-10, 10), 0.8, rng:NextNumber(-half + 30, half - 30))))
			model.Parent = lobby
			tag(model, "LobbyWander", { Radius = 14, Speed = rng:NextNumber(4, 7), Seed = i })
		end
	end

	-- Floating blocks in the sky for that chaotic Brainrot feel
	for i = 1, 16 do
		local p = part({
			Name = "Floater",
			Size = Vector3.one * rng:NextNumber(4, 9),
			CFrame = CFrame.new(at(rng:NextNumber(-160, 160), rng:NextNumber(45, 80), rng:NextNumber(-half, half))),
			Color = COLORS.Bright[(i % #COLORS.Bright) + 1],
			CanCollide = false,
		})
		tag(p, "LobbyFloat", { Phase = rng:NextNumber(0, 6), Amplitude = rng:NextNumber(2, 5) })
		tag(p, "LobbySpin", { Speed = rng:NextNumber(0.2, 0.6) })
	end
end

-- Trees, palms, bushes and rocks on the grass around the outside of the
-- plots. Each one is your own model when you've made one (see LobbyProps).
local function buildScenery()
	local half = LobbyBuilder.StreetLength() / 2
	local outer = L.StreetHalfWidth + L.PlotDepth + 30
	local i = 0
	for z = -half - 40, half + 40, 26 do
		for _, side in { -1, 1 } do
			i += 1
			local x = side * (outer - rng:NextNumber(8, 18))
			local spot = at(x, 0, z + rng:NextNumber(-6, 6))
			local roll = i % 4
			if roll == 0 then
				LobbyBuilder.Tree(lobby, spot, 1, "PalmTree")
			elseif roll == 1 then
				LobbyBuilder.Tree(lobby, spot, 1.1)
			elseif roll == 2 then
				LobbyBuilder.Bush(lobby, spot)
			else
				LobbyBuilder.Rock(lobby, spot)
			end
		end
	end
	-- Along the far ends of the street
	for _, zSide in { -1, 1 } do
		for x = -outer + 20, outer - 20, 30 do
			if math.abs(x) > L.StreetHalfWidth + 6 then
				local spot = at(x + rng:NextNumber(-5, 5), 0, zSide * (half + 45))
				if rng:NextNumber() < 0.5 then
					LobbyBuilder.Bush(lobby, spot)
				else
					LobbyBuilder.Tree(lobby, spot, 1, "PalmTree")
				end
			end
		end
	end
end

-- Public run gate at the south end of the street (for anyone without a base).
local function buildPublicGate()
	local half = LobbyBuilder.StreetLength() / 2
	local base = at(0, 0.8, -half + 12)
	local cf = CFrame.lookAt(base, at(0, 0.8, 0))
	for _, sx in { -11, 11 } do
		part({ Name = "GatePost", Size = Vector3.new(3, 18, 3), CFrame = cf * CFrame.new(sx, 9, 0), Color = Color3.fromRGB(176, 124, 74) })
	end
	local beam = part({ Name = "GateBeam", Size = Vector3.new(26, 4, 3), CFrame = cf * CFrame.new(0, 19, 0), Color = COLORS.Bright[7] })
	Util.SurfaceLabel(beam, Enum.NormalId.Front, "🏃 PUBLIC RUN GATE", { PixelsPerStud = 20 })
	local portal = part({ Name = "RunPortal", Size = Vector3.new(19, 16, 1), CFrame = cf * CFrame.new(0, 8, 1), Color = Color3.fromRGB(130, 70, 255), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Studs = false })
	tag(portal, "LobbyPulse")
	local trigger = part({ Name = "RunEntranceTrigger", Size = Vector3.new(19, 12, 3), CFrame = cf * CFrame.new(0, 6, 0), Transparency = 1, CanCollide = false, Studs = false })
	trigger.CanTouch = true
	tag(trigger, "RunEntranceTrigger")
	part({ Name = "GateBackstop", Size = Vector3.new(24, 20, 1), CFrame = cf * CFrame.new(0, 10, 2.5), Transparency = 1, Studs = false })
end

function LobbyBuilder.Build(): Folder
	lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	buildGround()
	buildConveyors()
	buildHub()
	buildPublicGate()
	buildScenery()
	return lobby
end

function LobbyBuilder.Folder(): Folder
	return lobby
end

return LobbyBuilder
