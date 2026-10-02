--!strict
-- The lobby: a big blocky valley (think Steal a Brainrot / Grow a Garden /
-- Pet Simulator worlds). Bright checkered grass with studs, closed in on
-- every side by terraced, checkered cliffs with trees on the ledges and a
-- giant Verity watching from the north cliff.
--
--   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ cliffs (Verity on top) ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
--   ▓    [base 1]          [base 2]          [base 3]            ▓
--   ▓       ┃                 ┃                 ┃                 ▓
--   ▓    ┏━━┻━━━━━━━━━━ conveyor ring road ━━━━━┻━━┓              ▓
--   ▓[7]━┫          ┌──── SAFE ZONE ────┐         ┣━[8]           ▓
--   ▓    ┃          │ spawn · shops ·🏆 │         ┃               ▓
--   ▓    ┗━━┳━━━━━━━└───────────────────┘━━━━┳━━━━┛              ▓
--   ▓       ┃                 ┃                 ┃                 ▓
--   ▓    [base 4]          [base 5]          [base 6]            ▓
--   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
--
-- It's a real map: Workspace.Lobby in the place file (map/Lobby.rbxm, made
-- from this builder by tools/bake_map.sh), so you can edit it in Studio.
-- At startup the server uses the map it finds and only switches on what a
-- place file can't store (the conveyors' push, the stud texture). With no
-- Workspace.Lobby it generates one from code instead. Player bases are
-- PlotManager's; LobbyBuilder.PlotSlots says where they go.

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
local VALLEY = L.ValleyHalfSize
local STEP = L.CliffStep
local PLAZA = L.PlazaHalfSize
local RING = L.RingRoadHalfSize
local ROAD = 18 -- ring road and spoke width

LobbyBuilder.Colors = {
	Grass = Color3.fromRGB(95, 205, 75),
	GrassDark = Color3.fromRGB(80, 185, 62),
	PlotGrass = Color3.fromRGB(120, 220, 95),
	Stone = Color3.fromRGB(200, 205, 215),
	StoneDark = Color3.fromRGB(175, 180, 195),
	Belt = Color3.fromRGB(40, 40, 46),
	BeltEdge = Color3.fromRGB(245, 205, 50),
	Wood = Color3.fromRGB(160, 100, 55),
	FencePost = Color3.fromRGB(140, 85, 45),
	FenceCap = Color3.fromRGB(85, 85, 105),
	Dirt = Color3.fromRGB(190, 125, 70),
	DirtDark = Color3.fromRGB(160, 100, 55),
	Leaves = Color3.fromRGB(60, 170, 60),
	LeavesLight = Color3.fromRGB(110, 205, 70),
	Pine = Color3.fromRGB(40, 125, 60),
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

local lobby: Instance
local rng = Random.new(2024)

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- ───────────────────────────── layout ─────────────────────────────

export type PlotSlot = { center: Vector3, facing: Vector3 }

-- Where the 8 player bases go: 3 north, 3 south (facing the plaza), 1 west,
-- 1 east. Each base's entrance sits just off the ring road.
function LobbyBuilder.PlotSlots(): { PlotSlot }
	local offset = RING + 24 + L.PlotDepth / 2
	local slots = {}
	for _, x in { -RING, 0, RING } do
		table.insert(slots, { center = at(x, 0, -offset), facing = Vector3.zAxis })
	end
	for _, x in { -RING, 0, RING } do
		table.insert(slots, { center = at(x, 0, offset), facing = -Vector3.zAxis })
	end
	table.insert(slots, { center = at(-offset, 0, 0), facing = Vector3.xAxis })
	table.insert(slots, { center = at(offset, 0, 0), facing = -Vector3.xAxis })
	return slots
end

-- How far out a ground cell is, with the corners cut so the valley is
-- roughly round rather than a perfect square.
local function ringDistance(x: number, z: number): number
	return math.max(math.abs(x), math.abs(z), (math.abs(x) + math.abs(z)) * 0.62)
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

-- The square stud texture on every visible face (the bottom is never seen),
-- down to Config.Lobby.StudTextureMinFace: fence posts and caps get studs
-- too. The image is a transparent overlay, so the part's own colour shows
-- through.
local function studTexture(p: BasePart)
	if p.Transparency >= 1 or p.Material == Enum.Material.Neon then
		return
	end
	if p:IsA("Part") and (p :: Part).Shape ~= Enum.PartType.Block then
		return
	end
	for _, face in STUD_FACES do
		local u, v = faceSize(p.Size, face)
		if u >= L.StudTextureMinFace and v >= L.StudTextureMinFace then
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
-- Roblox's classic round studs. Parts built without studs are marked
-- NoStuds so the startup texture pass leaves them alone too.
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
	elseif not studs then
		p:SetAttribute("NoStuds", true)
	end
	return p
end
LobbyBuilder.Part = part

local function tag(instance: Instance, tagName: string, attrs: { [string]: any }?)
	CollectionService:AddTag(instance, tagName)
	if attrs then
		for k, v in attrs do
			instance:SetAttribute(k, v)
		end
	end
end

local function group(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent or lobby
	return model
end

-- ───────────────────────────── your models ─────────────────────────────

-- Where your models are: ServerStorage.LobbyProps, or a LobbyProps model
-- left in Workspace (where Studio's 3D importer puts an import). That one is
-- anchored and taken out of the world, or its unanchored meshes would fall
-- over and come apart when you press Play.
local function propsRoot(): Instance?
	local stored = ServerStorage:FindFirstChild(L.PropsFolder)
	if stored then
		return stored
	end
	local imported = workspace:FindFirstChild(L.PropsFolder)
	if not imported then
		return nil
	end
	for _, d in imported:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	pcall(function()
		imported.Parent = ServerStorage
	end)
	return imported
end

-- Your models of `kind`: Models anywhere in LobbyProps (the importer may
-- nest them) named like the kind, or the kind and a number for variants
-- ("Tree", "Tree_2", "Tree 3").
local function propTemplates(kind: string): { Model }
	local root = propsRoot()
	local found = {}
	if root then
		for _, d in root:GetDescendants() do
			local suffix = d.Name:sub(#kind + 1)
			if d:IsA("Model") and d.Name:sub(1, #kind) == kind and (suffix == "" or suffix:match("^[%s_%-]?%d+$") ~= nil) then
				table.insert(found, d)
			end
		end
	end
	return found
end

-- The colour key in an imported mesh's name: Blender and the importer add
-- prefixes and suffixes ("Tree_2_Leaves", "Leaves.001"), so it's the last
-- piece of the name that is a key in Config.Lobby.PropColors.
local function colorKey(name: string): string?
	local pieces = string.split((name:gsub("%.", "_")), "_")
	for i = #pieces, 1, -1 do
		if L.PropColors[pieces[i]] then
			return pieces[i]
		end
	end
	return nil
end

-- Imported meshes (tools/blender/props.py) are named after their colour:
-- paint them from Config.Lobby.PropColors. "Outline" is the black toon
-- shell, "Bulb" a lamp's light.
local function finishProp(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			local key = colorKey(d.Name)
			if key then
				d.Color = L.PropColors[key]
			end
			if key == "Outline" then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			elseif key == "Bulb" then
				d.Material = Enum.Material.Neon
				if not d:FindFirstChildWhichIsA("Light") then
					local light = Instance.new("PointLight")
					light.Range = 18
					light.Brightness = 1.2
					light.Color = Color3.fromRGB(255, 230, 170)
					light.Parent = d
				end
			end
		end
	end
	-- They bring their own look: no stud texture, no edge boxes.
	model:SetAttribute("NoStuds", true)
	model:SetAttribute("NoOutline", true)
	model:SetAttribute("CustomProp", true)
end

-- Places one of your models of `kind` standing on the ground at `position`
-- (a random variant, turned randomly). `scale` is relative to the built-in
-- prop's size (Config.Lobby.PropHeights); a model that comes in far too big
-- or small (other units in the importer) is fitted to that size. Returns
-- nil when you have none, so the caller builds its blocky stand-in.
function LobbyBuilder.Prop(kind: string, parent: Instance, position: Vector3, scale: number?): Model?
	local templates = propTemplates(kind)
	if #templates == 0 then
		return nil
	end
	local model = templates[rng:NextInteger(1, #templates)]:Clone()
	finishProp(model)
	local s = scale or 1
	local _, size = model:GetBoundingBox()
	local want = (L.PropHeights[kind] or size.Y) * s
	local ratio = want / math.max(size.Y, 0.01)
	if ratio > 2 or ratio < 0.5 then
		model:ScaleTo(model:GetScale() * ratio)
	elseif s ~= 1 then
		model:ScaleTo(model:GetScale() * s)
	end
	-- Stand it on the ground: put the bottom of its bounding box at `position`.
	local pivot = model:GetPivot()
	local box, boxSize = model:GetBoundingBox()
	local pivotAboveBottom = pivot.Position.Y - (box.Position.Y - boxSize.Y / 2)
	model:PivotTo(CFrame.new(position + Vector3.new(0, pivotAboveBottom, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * pivot.Rotation)
	model.Parent = parent
	return model
end

-- Swaps the blocky props in the lobby map (Models named Tree, PineTree,
-- Bush, …) for your models of the same kind, keeping where they stand and
-- how big they are. Returns how many were swapped.
function LobbyBuilder.SwapProps(root: Instance): number
	local kinds = {}
	for _, kind in L.PropKinds do
		if #propTemplates(kind) > 0 then
			kinds[kind] = true
		end
	end
	if next(kinds) == nil then
		return 0
	end
	local stand = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Model") and kinds[d.Name] and not d:GetAttribute("CustomProp") then
			table.insert(stand, d)
		end
	end
	local swapped = 0
	for _, old in stand do
		local ok, box, size = pcall(function()
			return old:GetBoundingBox()
		end)
		if ok and old.Parent then
			local bottom = box.Position - Vector3.new(0, size.Y / 2, 0)
			local scale = size.Y / (L.PropHeights[old.Name] or size.Y)
			if LobbyBuilder.Prop(old.Name, old.Parent :: Instance, bottom, scale) then
				old:Destroy()
				swapped += 1
			end
		end
	end
	return swapped
end

-- ───────────────────────────── building blocks ─────────────────────────────

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

-- A big voxel tree: chunky trunk with a branch, canopy of leafy cubes (or
-- your "Tree" model).
function LobbyBuilder.Tree(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	if LobbyBuilder.Prop("Tree", parent, position, s) then
		return
	end
	local tree = group("Tree", parent)
	part({ Parent = tree, Name = "Trunk", Size = Vector3.new(3, 12, 3) * s, CFrame = CFrame.new(position + Vector3.new(0, 6 * s, 0)), Color = COLORS.Wood })
	part({ Parent = tree, Name = "Branch", Size = Vector3.new(5, 2, 2) * s, CFrame = CFrame.new(position + Vector3.new(2.5 * s, 9 * s, 0)), Color = COLORS.Wood })
	local canopy = {
		{ Vector3.new(0, 14, 0), Vector3.new(11, 6, 11), COLORS.Leaves },
		{ Vector3.new(4, 12, 3), Vector3.new(7, 5, 7), COLORS.LeavesLight },
		{ Vector3.new(-4, 13, -3), Vector3.new(7, 5, 7), COLORS.LeavesLight },
		{ Vector3.new(1, 18, -1), Vector3.new(7, 4, 7), COLORS.Leaves },
		{ Vector3.new(5, 11, -4), Vector3.new(4, 3, 4), COLORS.Leaves },
	}
	for _, c in canopy do
		part({ Parent = tree, Name = "Leaves", Size = c[2] * s, CFrame = CFrame.new(position + c[1] * s), Color = c[3] })
	end
end

-- A stacked-cube pine tree (or your "PineTree" model).
function LobbyBuilder.PineTree(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	if LobbyBuilder.Prop("PineTree", parent, position, s) then
		return
	end
	local tree = group("PineTree", parent)
	part({ Parent = tree, Name = "Trunk", Size = Vector3.new(2, 5, 2) * s, CFrame = CFrame.new(position + Vector3.new(0, 2.5 * s, 0)), Color = COLORS.Wood })
	local y = 5
	for i, width in { 10, 8, 6, 4, 2 } do
		part({ Parent = tree, Name = "Needles", Size = Vector3.new(width, 3, width) * s, CFrame = CFrame.new(position + Vector3.new(0, (y + 1.5) * s, 0)), Color = if i % 2 == 0 then COLORS.Pine else COLORS.Pine:Lerp(COLORS.Leaves, 0.3) })
		y += 3
	end
end

-- A cluster of green cubes (or your "Bush" model).
function LobbyBuilder.Bush(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Bush", parent, position) then
		return
	end
	local bush = group("Bush", parent)
	for i, c in { { Vector3.new(0, 1.75, 0), 3.5 }, { Vector3.new(2.4, 1.25, 1.2), 2.5 }, { Vector3.new(-2, 1.25, -1), 2.5 }, { Vector3.new(0.6, 1, -2.2), 2 } } do
		part({ Parent = bush, Name = "Bush", Size = Vector3.one * c[2], CFrame = CFrame.new(position + c[1]), Color = if i % 2 == 0 then COLORS.LeavesLight else COLORS.Leaves })
	end
end

-- A blocky rock (or your "Rock" model).
function LobbyBuilder.Rock(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Rock", parent, position) then
		return
	end
	local rock = group("Rock", parent)
	local grey = Color3.fromRGB(140, 140, 155)
	part({ Parent = rock, Name = "Rock", Size = Vector3.new(4, 2.4, 3), CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = grey })
	part({ Parent = rock, Name = "Rock", Size = Vector3.new(2, 1.4, 2), CFrame = CFrame.new(position + Vector3.new(2.2, 0.7, 0.6)), Color = grey:Lerp(Color3.new(0, 0, 0), 0.15) })
end

-- A little patch of blocky flowers (or your "Flowers" model).
function LobbyBuilder.Flowers(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Flowers", parent, position) then
		return
	end
	local flowers = group("Flowers", parent)
	for i = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		part({ Parent = flowers, Name = "Stem", Size = Vector3.new(0.3, 1.2, 0.3), CFrame = CFrame.new(position + offset + Vector3.new(0, 0.6, 0)), Color = COLORS.Leaves, Studs = false })
		part({ Parent = flowers, Name = "Petals", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(position + offset + Vector3.new(0, 1.5, 0)), Color = COLORS.Bright[(i % #COLORS.Bright) + 1], Studs = false })
	end
end

function LobbyBuilder.Lamp(parent: Instance, position: Vector3)
	if LobbyBuilder.Prop("Lamp", parent, position) then
		return
	end
	local lamp = group("Lamp", parent)
	part({ Parent = lamp, Name = "LampPost", Size = Vector3.new(1, 12, 1), CFrame = CFrame.new(position + Vector3.new(0, 6, 0)), Color = Color3.fromRGB(50, 50, 60) })
	local bulb = part({ Parent = lamp, Name = "LampBulb", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 13, 0)), Color = Color3.fromRGB(255, 240, 170), Material = Enum.Material.Neon, Studs = false })
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Parent = bulb
end

-- ───────────────────────────── valley & cliffs ─────────────────────────────

-- Checkered grass over the whole valley floor, and terraced cliffs all the
-- way round: each ring of cliff blocks is taller than the one inside it,
-- with brown checker sides and grass on top.
local function buildValley()
	local ground = group("Ground")
	local cliffs = group("Cliffs")
	local rings = L.CliffRings
	local reach = VALLEY + rings * STEP
	local heights = { 18, 44, 78, 118, 160, 200 }
	local i = 0
	for x = -reach + STEP / 2, reach, STEP do
		i += 1
		local j = 0
		for z = -reach + STEP / 2, reach, STEP do
			j += 1
			local d = ringDistance(x, z)
			local checker = (i + j) % 2 == 0
			if d <= VALLEY then
				part({ Parent = ground, Name = "Grass", Size = Vector3.new(STEP, 2, STEP), CFrame = CFrame.new(at(x, -1, z)), Color = if checker then COLORS.Grass else COLORS.GrassDark })
			elseif d <= reach then
				local ring = math.clamp(math.ceil((d - VALLEY) / STEP), 1, rings)
				-- A little height jitter per block so the terraces look carved.
				local h = heights[ring] + rng:NextInteger(-1, 2) * 3
				part({ Parent = cliffs, Name = "Cliff", Size = Vector3.new(STEP, h, STEP), CFrame = CFrame.new(at(x, h / 2 - 2, z)), Color = if checker then COLORS.Dirt else COLORS.DirtDark })
				part({ Parent = cliffs, Name = "CliffTop", Size = Vector3.new(STEP + 0.4, 2, STEP + 0.4), CFrame = CFrame.new(at(x, h - 2, z)), Color = if checker then COLORS.Grass else COLORS.GrassDark })
				-- Trees and bushes on some ledges
				local top = at(x + rng:NextNumber(-10, 10), h - 1, z + rng:NextNumber(-10, 10))
				local roll = rng:NextNumber()
				if roll < 0.22 then
					LobbyBuilder.PineTree(cliffs, top, rng:NextNumber(1, 1.6))
				elseif roll < 0.36 then
					LobbyBuilder.Tree(cliffs, top, rng:NextNumber(1, 1.4))
				elseif roll < 0.5 then
					LobbyBuilder.Bush(cliffs, top)
				end
			end
		end
	end

	-- Verity watches over the valley from the top of the north cliffs.
	local statue = ModelFactory.Villain(9)
	statue.Name = "GiantVerity"
	local topY = heights[rings] - 1
	statue:PivotTo(CFrame.lookAt(at(0, topY, -(VALLEY + (rings - 0.5) * STEP)), at(0, topY, 0)))
	statue.Parent = cliffs
	tag(statue, "LobbyDance", { Style = "Sway" })
end

-- ───────────────────────────── plaza, roads, conveyors ─────────────────────────────

local function flat(parent: Instance, name: string, cx: number, cz: number, sx: number, sz: number, y: number, color: Color3): BasePart
	return part({ Parent = parent, Name = name, Size = Vector3.new(sx, 0.6, sz), CFrame = CFrame.new(at(cx, y, cz)), Color = color })
end

-- A conveyor belt: an anchored part whose velocity carries anything standing
-- on it along its front. The push (AssemblyLinearVelocity) isn't saved in a
-- place file, so it's switched on at startup (see activate). LobbyFX adds the
-- moving stripes client-side.
local function conveyor(parent: Instance, from: Vector3, to: Vector3)
	local dir = to - from
	local length = dir.Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	local belt = part({
		Parent = parent,
		Name = "Conveyor",
		Size = Vector3.new(L.ConveyorWidth, 1, length),
		CFrame = cf,
		Color = COLORS.Belt,
		Material = Enum.Material.SmoothPlastic,
		Studs = false,
	})
	tag(belt, "Conveyor", { Speed = L.ConveyorSpeed })
	for _, side in { -1, 1 } do
		part({ Parent = parent, Name = "ConveyorEdge", Size = Vector3.new(0.6, 1.4, length), CFrame = cf * CFrame.new(side * (L.ConveyorWidth / 2 + 0.3), 0.2, 0), Color = COLORS.BeltEdge })
	end
end

local function buildRoads()
	local roads = group("Roads")
	-- SAFE ZONE plaza: light stone studs with a bright red border
	flat(roads, "Plaza", 0, 0, PLAZA * 2, PLAZA * 2, 0.3, COLORS.Stone)
	for _, side in { -1, 1 } do
		flat(roads, "PlazaBorder", 0, side * (PLAZA + 1), PLAZA * 2 + 4, 2, 0.35, COLORS.Bright[1])
		flat(roads, "PlazaBorder", side * (PLAZA + 1), 0, 2, PLAZA * 2 + 4, 0.35, COLORS.Bright[1])
	end
	local safe = part({ Parent = roads, Name = "SafeZoneText", Size = Vector3.new(60, 0.2, 12), CFrame = CFrame.new(at(0, 0.7, 28)), Transparency = 1, CanCollide = false, Studs = false })
	Util.SurfaceLabel(safe, Enum.NormalId.Top, "SAFE ZONE", { PixelsPerStud = 10, TextColor = Color3.fromRGB(255, 255, 255) })

	-- Ring road around the plaza, with spokes in from the middle of each side
	-- and out to every base's entrance.
	for _, side in { -1, 1 } do
		flat(roads, "RingRoad", 0, side * RING, RING * 2 + ROAD, ROAD, 0.3, COLORS.StoneDark)
		flat(roads, "RingRoad", side * RING, 0, ROAD, RING * 2 + ROAD, 0.3, COLORS.StoneDark)
		flat(roads, "Spoke", 0, side * (PLAZA + RING) / 2, ROAD - 4, RING - PLAZA, 0.28, COLORS.Stone)
		flat(roads, "Spoke", side * (PLAZA + RING) / 2, 0, RING - PLAZA, ROAD - 4, 0.28, COLORS.Stone)
	end
	for _, slot in LobbyBuilder.PlotSlots() do
		-- A base's front (its entrance) faces the plaza.
		local entrance = slot.center + slot.facing * (L.PlotDepth / 2)
		local roadEdge = slot.center + slot.facing * (L.PlotDepth / 2 + 24)
		local mid = (entrance + roadEdge) / 2 - ORIGIN
		local alongX = math.abs(slot.facing.X) > 0.5
		flat(roads, "BasePath", mid.X, mid.Z, if alongX then 24 else ROAD - 4, if alongX then ROAD - 4 else 24, 0.28, COLORS.Stone)
	end

	-- Conveyor loop on the ring road (clockwise, seen from above)
	local belts = group("Conveyors")
	local y, r, w = 0.9, RING, L.ConveyorWidth / 2
	conveyor(belts, at(-r, y, -r), at(r, y, -r))
	conveyor(belts, at(r, y, -r - w), at(r, y, r + w))
	conveyor(belts, at(r, y, r), at(-r, y, r))
	conveyor(belts, at(-r, y, r + w), at(-r, y, -r - w))

	-- Lamps along the spokes
	for _, side in { -1, 1 } do
		for _, along in { PLAZA + 25, PLAZA + 60 } do
			LobbyBuilder.Lamp(roads, at(12, 0.6, side * along))
			LobbyBuilder.Lamp(roads, at(side * along, 0.6, 12))
		end
	end
end

-- ───────────────────────────── the SAFE ZONE ─────────────────────────────

-- A wooden market stand with a coloured roof (Buy / Sell stands).
local function stall(position: Vector3, facing: Vector3, title: string, color: Color3): CFrame
	local stand = group("Stall_" .. title:gsub("[^%w]", ""))
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	part({ Parent = stand, Name = "Deck", Size = Vector3.new(22, 1, 16), CFrame = cf * CFrame.new(0, 0.5, 0), Color = COLORS.Bright[2]:Lerp(COLORS.Wood, 0.6) })
	part({ Parent = stand, Name = "Counter", Size = Vector3.new(20, 4, 3), CFrame = cf * CFrame.new(0, 3, -5), Color = COLORS.Wood })
	part({ Parent = stand, Name = "CounterTop", Size = Vector3.new(21, 0.8, 4), CFrame = cf * CFrame.new(0, 5.4, -5), Color = color })
	for _, sx in { -10, 10 } do
		for _, sz in { -6.5, 6.5 } do
			part({ Parent = stand, Name = "StallPost", Size = Vector3.new(1.4, 12, 1.4), CFrame = cf * CFrame.new(sx, 7, sz), Color = COLORS.Wood })
		end
	end
	part({ Parent = stand, Name = "Roof", Size = Vector3.new(24, 2, 17), CFrame = cf * CFrame.new(0, 14, 0), Color = color })
	part({ Parent = stand, Name = "RoofTop", Size = Vector3.new(18, 2, 11), CFrame = cf * CFrame.new(0, 16, 0), Color = color:Lerp(Color3.new(1, 1, 1), 0.3) })
	LobbyBuilder.Sign(stand, (cf * CFrame.new(0, 20, -6)).Position, facing, title, color, 20, 4)
	return cf
end

local function buildPlaza()
	local hub = group("SafeZone")

	-- Spawn in the middle
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(at(0, 1.1, 0))
	spawnLocation.Anchored = true
	spawnLocation.Color = Color3.fromRGB(255, 255, 255)
	spawnLocation.TopSurface = Enum.SurfaceType.Studs
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = hub

	-- Statue of the villain with a WANTED sign, north side of the plaza
	local statue = ModelFactory.Villain(2.6)
	statue.Name = "VillainStatue"
	part({ Parent = hub, Name = "StatueBase", Size = Vector3.new(16, 3, 16), CFrame = CFrame.new(at(0, 2, -40)), Color = Color3.fromRGB(150, 150, 165) })
	statue:PivotTo(CFrame.lookAt(at(0, 3.5, -40), at(0, 3.5, 0)))
	statue.Parent = hub
	tag(statue, "LobbyDance", { Style = "Sway" })
	LobbyBuilder.Sign(hub, at(0, 3.5, -31.4), at(0, 3.5, 0), ("WANTED: %s\nhe kidnapped the Brainrots!"):format(Config.Villain.Title), Color3.fromRGB(200, 40, 40), 12, 3)
	LobbyBuilder.Sign(hub, at(0, 32, -56), at(0, 32, 0), "🧠 BRAINROT RUNNER 🧠", COLORS.Bright[1], 50, 10, 27)

	-- ⬆️ Upgrade stand (west) and 🛒 shop stand (east), facing the spawn
	local upgradeCf = stall(at(-42, 0.6, -6), at(0, 0.6, -6), "⬆️ UPGRADES", COLORS.Bright[5])
	for i, icon in { "🧲", "🚀", "👟", "✖️2" } do
		local standCf = upgradeCf * CFrame.new((i - 2.5) * 4.5, 0, -5)
		local orb = part({ Parent = hub, Name = "UpgradeOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = standCf * CFrame.new(0, 7.6, 0), Color = COLORS.Bright[i + 1], Material = Enum.Material.Neon, Studs = false })
		tag(orb, "LobbyFloat", { Phase = i, Amplitude = 0.5 })
		Util.Billboard(orb, icon, UDim2.fromOffset(60, 60), Vector3.new(0, 3, 0))
		LobbyBuilder.Prompt(orb, "Upgrade", "Power-ups", "Upgrades")
	end
	local shopCf = stall(at(42, 0.6, -6), at(0, 0.6, -6), "🛒 SHOP", COLORS.Bright[1])
	local counter = part({ Parent = hub, Name = "ShopCounterPrompt", Size = Vector3.new(20, 1, 4), CFrame = shopCf * CFrame.new(0, 6, -5), Transparency = 1, CanCollide = false, Studs = false })
	LobbyBuilder.Prompt(counter, "Shop", "Brainrot Shop", "Shop")
	local seller = ModelFactory.Brainrot("BallerinaCappuccina", 1)
	seller:PivotTo(CFrame.lookAt(shopCf.Position + Vector3.new(0, 1, 0), at(0, 1.6, -6)))
	seller.Parent = hub
	tag(seller, "LobbyDance", { Style = "Twirl" })

	-- 🎁 Daily reward: a giant blocky present (south-west)
	local giftPos = at(-40, 0.6, 40)
	local gift = part({ Parent = hub, Name = "GiftBox", Size = Vector3.new(10, 10, 10), CFrame = CFrame.new(giftPos + Vector3.new(0, 5, 0)), Color = COLORS.Bright[1] })
	part({ Parent = hub, Name = "Ribbon", Size = Vector3.new(10.2, 10.2, 2), CFrame = gift.CFrame, Color = COLORS.Bright[3], CanCollide = false })
	part({ Parent = hub, Name = "Ribbon", Size = Vector3.new(2, 10.2, 10.2), CFrame = gift.CFrame, Color = COLORS.Bright[3], CanCollide = false })
	local bow = part({ Parent = hub, Name = "Bow", Size = Vector3.new(4, 2, 4), CFrame = gift.CFrame * CFrame.new(0, 6, 0), Color = COLORS.Bright[3], CanCollide = false })
	tag(bow, "LobbySpin", { Speed = 2 })
	LobbyBuilder.Prompt(gift, "Claim", "Daily Reward", "Daily")
	Util.Billboard(gift, "🎁 DAILY REWARD", UDim2.fromOffset(200, 40), Vector3.new(0, 10, 0), COLORS.Bright[3])

	-- 🏆 Leaderboard (south-east)
	local boardCf = CFrame.lookAt(at(44, 17, 46), at(0, 17, 0))
	part({ Parent = hub, Name = "BoardFrame", Size = Vector3.new(36, 24, 2), CFrame = boardCf, Color = COLORS.Bright[2] })
	local screen = part({ Parent = hub, Name = "LeaderboardScreen", Size = Vector3.new(32, 20, 0.4), CFrame = boardCf * CFrame.new(0, 0, -1.2), Color = Color3.fromRGB(25, 20, 40), Studs = false })
	tag(screen, "LeaderboardScreen")
	for _, side in { -1, 1 } do
		part({ Parent = hub, Name = "BoardLeg", Size = Vector3.new(3, 17, 3), CFrame = boardCf * CFrame.new(side * 14, -13, 0), Color = COLORS.Wood })
	end
	local leaderboardPrompt = part({ Parent = hub, Name = "LeaderboardPrompt", Size = Vector3.new(10, 6, 4), CFrame = boardCf * CFrame.new(0, -13, -4), Transparency = 1, CanCollide = false, Studs = false })
	LobbyBuilder.Prompt(leaderboardPrompt, "View", "Leaderboards", "Leaderboard")

	-- 🏃 Public run gate (south edge), for anyone without a base
	local gateCf = CFrame.lookAt(at(0, 0.6, PLAZA - 10), at(0, 0.6, 0))
	for _, sx in { -11, 11 } do
		part({ Parent = hub, Name = "GatePost", Size = Vector3.new(3, 18, 3), CFrame = gateCf * CFrame.new(sx, 9, 0), Color = COLORS.Wood })
	end
	local beam = part({ Parent = hub, Name = "GateBeam", Size = Vector3.new(26, 4, 3), CFrame = gateCf * CFrame.new(0, 19, 0), Color = COLORS.Bright[7] })
	Util.SurfaceLabel(beam, Enum.NormalId.Front, "🏃 PUBLIC RUN GATE", { PixelsPerStud = 20 })
	local portal = part({ Parent = hub, Name = "RunPortal", Size = Vector3.new(19, 16, 1), CFrame = gateCf * CFrame.new(0, 8, 1), Color = Color3.fromRGB(130, 70, 255), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Studs = false })
	tag(portal, "LobbyPulse")
	local trigger = part({ Parent = hub, Name = "RunEntranceTrigger", Size = Vector3.new(19, 12, 3), CFrame = gateCf * CFrame.new(0, 6, 0), Transparency = 1, CanCollide = false, Studs = false })
	trigger.CanTouch = true
	tag(trigger, "RunEntranceTrigger")
	part({ Parent = hub, Name = "GateBackstop", Size = Vector3.new(24, 20, 1), CFrame = gateCf * CFrame.new(0, 10, 2.5), Transparency = 1, Studs = false })

	-- Flowers around the plaza corners and a few Brainrots wandering about
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			LobbyBuilder.Flowers(hub, at(cx * (PLAZA - 8), 0.6, cz * (PLAZA - 8)))
		end
	end
	for i, brainrot in BrainrotData.List do
		if i > 1 and i % 2 == 0 then
			local model = ModelFactory.Brainrot(brainrot.id, 1)
			model.Name = "Wanderer_" .. brainrot.id
			model:PivotTo(CFrame.new(at(rng:NextNumber(-25, 25), 0.6, rng:NextNumber(5, 25))))
			model.Parent = hub
			tag(model, "LobbyWander", { Radius = 18, Speed = rng:NextNumber(4, 7), Seed = i })
		end
	end
end

-- ───────────────────────────── scenery ─────────────────────────────

-- Is this spot clear of the plaza, roads and bases?
local function isOpenGround(x: number, z: number): boolean
	if ringDistance(x, z) > VALLEY - 12 then
		return false
	end
	if math.max(math.abs(x), math.abs(z)) < PLAZA + 30 then
		return false
	end
	-- the ring road and the spokes into the plaza
	if math.abs(math.max(math.abs(x), math.abs(z)) - RING) < ROAD and math.min(math.abs(x), math.abs(z)) < RING + ROAD then
		return false
	end
	if (math.abs(x) < 14 or math.abs(z) < 14) and math.max(math.abs(x), math.abs(z)) < RING then
		return false
	end
	for _, slot in LobbyBuilder.PlotSlots() do
		local c = slot.center - ORIGIN
		local alongX = math.abs(slot.facing.X) > 0.5
		local halfX = (if alongX then L.PlotDepth / 2 + 30 else L.PlotWidth / 2) + 8
		local halfZ = (if alongX then L.PlotWidth / 2 else L.PlotDepth / 2 + 30) + 8
		if math.abs(x - c.X) < halfX and math.abs(z - c.Z) < halfZ then
			return false
		end
	end
	return true
end

local function buildScenery()
	local nature = group("Nature")
	local placed = 0
	local tries = 0
	while placed < 230 and tries < 6000 do
		tries += 1
		local x = rng:NextNumber(-VALLEY, VALLEY)
		local z = rng:NextNumber(-VALLEY, VALLEY)
		if isOpenGround(x, z) then
			placed += 1
			local spot = at(x, 0, z)
			-- Bigger trees toward the cliffs, small things nearer the roads
			local outer = ringDistance(x, z) > RING + 90
			local roll = rng:NextNumber()
			if outer and roll < 0.35 then
				LobbyBuilder.PineTree(nature, spot, rng:NextNumber(1, 1.5))
			elseif roll < 0.55 then
				LobbyBuilder.Tree(nature, spot, rng:NextNumber(0.9, 1.3))
			elseif roll < 0.75 then
				LobbyBuilder.Bush(nature, spot)
			elseif roll < 0.88 then
				LobbyBuilder.Flowers(nature, spot)
			else
				LobbyBuilder.Rock(nature, spot)
			end
		end
	end
end

-- ───────────────────────────── build / use ─────────────────────────────

-- Builds the whole lobby from code into a new Workspace.Lobby (used when the
-- place has no lobby map, and by tools/bake_map.sh to make one).
function LobbyBuilder.Generate(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace
	lobby = folder

	buildValley()
	buildRoads()
	buildPlaza()
	buildScenery()
	return folder
end

-- Things a place file can't store, switched on for the map at startup.
local function activate()
	for _, belt in CollectionService:GetTagged("Conveyor") do
		if belt:IsA("BasePart") and belt:IsDescendantOf(lobby) then
			-- Belts push along their front, so you can move and turn them in Studio.
			belt.AssemblyLinearVelocity = belt.CFrame.LookVector * (belt:GetAttribute("Speed") or L.ConveyorSpeed)
		end
	end
	if L.StudTexture ~= "" then
		-- Everything in the lobby, including parts you added in Studio, gets
		-- the stud texture (set a NoStuds attribute on a part or model to
		-- keep it plain).
		for _, d in lobby:GetDescendants() do
			if d:IsA("BasePart") and not d:FindFirstChild("Studs") and not d:GetAttribute("NoStuds") then
				local model = d:FindFirstAncestorWhichIsA("Model")
				if not (model and model:GetAttribute("NoStuds")) and not d:FindFirstAncestor("Dynamic") then
					d.TopSurface = Enum.SurfaceType.Smooth
					d.BottomSurface = Enum.SurfaceType.Smooth
					studTexture(d)
				end
			end
		end
	end
end

-- Uses the lobby map in Workspace (or generates one if there isn't one).
function LobbyBuilder.Build(): Instance
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		lobby = existing
		LobbyBuilder.SwapProps(lobby)
	else
		LobbyBuilder.Generate()
	end
	activate()
	return lobby
end

function LobbyBuilder.Folder(): Instance
	return lobby
end

return LobbyBuilder
