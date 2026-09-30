--!strict
-- Builds chunky primitive Brainrot models (no uploaded meshes required).
-- Every model is built around a "Root" part at its feet, so callers can
-- `model:PivotTo(cframe)` to place it standing on the ground. Swap these out
-- for real meshes later by returning a cloned asset from ModelFactory.Brainrot.

local BrainrotData = require(script.Parent.BrainrotData)
local Util = require(script.Parent.Util)

local ModelFactory = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(20, 20, 20)

type Builder = (model: Model, look: BrainrotData.Look, s: number) -> ()

local function add(model: Model, props: Util.PartProps): BasePart
	props.Parent = model
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	return Util.Part(props)
end

local function addEllipsoid(model: Model, props: Util.PartProps): BasePart
	props.Parent = model
	props.CanCollide = false
	props.CanQuery = false
	return Util.Ellipsoid(props)
end

local function addCylinder(model: Model, cf: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	return Util.UprightCylinder({
		Parent = model,
		CFrame = cf,
		Height = height,
		Diameter = diameter,
		Color = color,
		Material = material,
		CanCollide = false,
		CanQuery = false,
	})
end

-- Two googly eyes facing -Z (the model's front).
local function eyes(model: Model, center: CFrame, spacing: number, size: number)
	for _, side in { -1, 1 } do
		local eyeCf = center * CFrame.new(side * spacing, 0, 0)
		add(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = eyeCf, Color = WHITE })
		add(model, {
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size * 0.5,
			CFrame = eyeCf * CFrame.new(0, 0, -size * 0.35),
			Color = BLACK,
		})
	end
end

local function legs(model: Model, s: number, color: Color3, shoe: Color3, count: number?, spread: number?)
	local n = count or 2
	local w = spread or 0.9
	for i = 1, n do
		local x = if n == 1 then 0 else (-w + (2 * w) * (i - 1) / (n - 1)) * s
		addCylinder(model, CFrame.new(x, 1 * s, 0), 2 * s, 0.6 * s, color)
		add(model, { Name = "Shoe", Size = Vector3.new(0.9, 0.5, 1.4) * s, CFrame = CFrame.new(x, 0.25 * s, -0.25 * s), Color = shoe })
	end
end

local builders: { [string]: Builder } = {}

builders.Log = function(model, look, s)
	-- Tung Tung Tung Sahur: a tall log with a face, stubby arms and a bat.
	legs(model, s, look.accent, BLACK)
	addCylinder(model, CFrame.new(0, 5 * s, 0), 6 * s, 3.4 * s, look.body, Enum.Material.Wood)
	addCylinder(model, CFrame.new(0, 8.05 * s, 0), 0.1 * s, 3.2 * s, Color3.fromRGB(220, 180, 120), Enum.Material.Wood)
	eyes(model, CFrame.new(0, 6.3 * s, -1.6 * s), 0.7 * s, 0.9 * s)
	add(model, { Name = "Mouth", Size = Vector3.new(1.4, 0.35, 0.3) * s, CFrame = CFrame.new(0, 4.9 * s, -1.65 * s), Color = BLACK })
	-- arms
	addCylinder(model, CFrame.new(-2 * s, 4.8 * s, 0) * CFrame.Angles(0, 0, math.rad(-20)), 2.4 * s, 0.5 * s, look.accent)
	addCylinder(model, CFrame.new(2 * s, 5.2 * s, -0.4 * s) * CFrame.Angles(math.rad(30), 0, math.rad(30)), 2.4 * s, 0.5 * s, look.accent)
	-- the bat
	local bat = addCylinder(
		model,
		CFrame.new(2.9 * s, 7 * s, -1.2 * s) * CFrame.Angles(math.rad(35), 0, math.rad(-15)),
		4.2 * s,
		0.6 * s,
		Color3.fromRGB(205, 160, 100),
		Enum.Material.Wood
	)
	bat.Name = "Bat"
end

builders.Shark = function(model, look, s)
	legs(model, s, look.body, look.accent, 3, 1.2)
	addEllipsoid(model, { Name = "Body", Size = Vector3.new(3, 3, 7) * s, CFrame = CFrame.new(0, 3.4 * s, 0), Color = look.body })
	add(model, { Name = "Belly", Class = "Part", Size = Vector3.new(2.2, 0.2, 5) * s, CFrame = CFrame.new(0, 2.05 * s, 0), Color = WHITE })
	add(model, {
		Name = "Fin",
		Class = "WedgePart",
		Size = Vector3.new(0.3, 2, 2) * s,
		CFrame = CFrame.new(0, 5.4 * s, 0.4 * s),
		Color = look.body,
	})
	add(model, { Name = "Tail", Class = "WedgePart", Size = Vector3.new(0.3, 2.4, 2) * s, CFrame = CFrame.new(0, 3.8 * s, 4.2 * s) * CFrame.Angles(0, math.rad(180), 0), Color = look.body })
	eyes(model, CFrame.new(0, 4 * s, -2.6 * s), 0.8 * s, 0.6 * s)
	add(model, { Name = "Teeth", Size = Vector3.new(1.6, 0.25, 0.2) * s, CFrame = CFrame.new(0, 2.9 * s, -3.35 * s), Color = WHITE })
end

builders.Croc = function(model, look, s)
	legs(model, s, look.body, BLACK)
	addEllipsoid(model, { Name = "Body", Size = Vector3.new(3, 3, 6) * s, CFrame = CFrame.new(0, 3.6 * s, 0), Color = look.body })
	add(model, { Name = "Snout", Size = Vector3.new(1.8, 1, 3) * s, CFrame = CFrame.new(0, 3.8 * s, -3.8 * s), Color = look.body })
	eyes(model, CFrame.new(0, 4.9 * s, -2.4 * s), 0.7 * s, 0.6 * s)
	for _, side in { -1, 1 } do
		add(model, { Name = "Wing", Size = Vector3.new(5, 0.3, 1.8) * s, CFrame = CFrame.new(side * 3.8 * s, 4 * s, 0), Color = look.accent, Material = Enum.Material.Metal })
		addCylinder(model, CFrame.new(side * 2.4 * s, 3.3 * s, 0.4 * s) * CFrame.Angles(math.rad(90), 0, 0), 1.8 * s, 0.8 * s, look.accent, Enum.Material.Metal)
	end
	add(model, { Name = "Bomb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2 * s, CFrame = CFrame.new(0, 1.8 * s, 0.8 * s), Color = BLACK })
end

builders.Cup = function(model, look, s)
	legs(model, s, Color3.fromRGB(250, 220, 200), look.accent, 2, 0.6)
	add(model, { Name = "Tutu", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4) * s, CFrame = CFrame.new(0, 2.3 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = look.body })
	addCylinder(model, CFrame.new(0, 4 * s, 0), 3 * s, 3 * s, look.accent, Enum.Material.Glass)
	addCylinder(model, CFrame.new(0, 5.55 * s, 0), 0.3 * s, 2.8 * s, Color3.fromRGB(245, 230, 200))
	add(model, { Name = "Handle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.6, 1.6) * s, CFrame = CFrame.new(1.9 * s, 4 * s, 0), Color = look.accent })
	eyes(model, CFrame.new(0, 4.4 * s, -1.5 * s), 0.6 * s, 0.6 * s)
end

builders.Tree = function(model, look, s)
	for _, side in { -1, 1 } do
		add(model, { Name = "BigFoot", Size = Vector3.new(1.6, 0.8, 3) * s, CFrame = CFrame.new(side * 1 * s, 0.4 * s, -0.8 * s), Color = Color3.fromRGB(230, 190, 160) })
	end
	addCylinder(model, CFrame.new(0, 3 * s, 0), 4.5 * s, 1.8 * s, look.body, Enum.Material.Wood)
	addEllipsoid(model, { Name = "Leaves", Size = Vector3.new(5, 4, 5) * s, CFrame = CFrame.new(0, 6.5 * s, 0), Color = look.accent, Material = Enum.Material.Grass })
	eyes(model, CFrame.new(0, 4.2 * s, -0.9 * s), 0.45 * s, 0.5 * s)
	add(model, { Name = "Nose", Size = Vector3.new(0.6, 0.6, 1.2) * s, CFrame = CFrame.new(0, 3.6 * s, -1.2 * s), Color = look.body })
end

builders.Elephant = function(model, look, s)
	legs(model, s, look.body, Color3.fromRGB(160, 110, 60))
	addCylinder(model, CFrame.new(0, 4 * s, 0), 4 * s, 2.6 * s, look.body, Enum.Material.Grass)
	for i = 1, 6 do
		local a = i * math.pi / 3
		add(model, { Name = "Spike", Size = Vector3.new(0.15, 0.15, 0.6) * s, CFrame = CFrame.new(math.cos(a) * 1.35 * s, 3.5 * s + (i % 3) * s, math.sin(a) * 1.35 * s), Color = WHITE })
	end
	add(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 3 * s, CFrame = CFrame.new(0, 7 * s, 0), Color = look.accent })
	for _, side in { -1, 1 } do
		addEllipsoid(model, { Name = "Ear", Size = Vector3.new(0.3, 2.4, 2) * s, CFrame = CFrame.new(side * 1.7 * s, 7 * s, 0.2 * s), Color = look.accent })
	end
	add(model, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 0.7, 0.7) * s, CFrame = CFrame.new(0, 5.8 * s, -1.6 * s) * CFrame.Angles(0, math.rad(90), math.rad(-70)), Color = look.accent })
	eyes(model, CFrame.new(0, 7.4 * s, -1.3 * s), 0.6 * s, 0.5 * s)
end

builders.Banana = function(model, look, s)
	legs(model, s, Color3.fromRGB(90, 60, 40), BLACK)
	for i = 0, 2 do
		addCylinder(model, CFrame.new(0, (2.8 + i * 1.6) * s, (i - 1) ^ 2 * 0.5 * s) * CFrame.Angles(math.rad((i - 1) * 18), 0, 0), 1.9 * s, 2.6 * s, look.body)
	end
	add(model, { Name = "Stem", Size = Vector3.new(0.5, 1, 0.5) * s, CFrame = CFrame.new(0, 7 * s, 0.6 * s), Color = Color3.fromRGB(90, 70, 30) })
	add(model, { Name = "Face", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2) * s, CFrame = CFrame.new(0, 4.4 * s, -0.8 * s), Color = look.accent })
	eyes(model, CFrame.new(0, 4.7 * s, -1.6 * s), 0.45 * s, 0.5 * s)
end

builders.Goose = function(model, look, s)
	legs(model, s, look.accent, look.accent)
	addEllipsoid(model, { Name = "Body", Size = Vector3.new(3, 3, 5) * s, CFrame = CFrame.new(0, 3.4 * s, 0.5 * s), Color = look.body })
	addCylinder(model, CFrame.new(0, 5.5 * s, -1.6 * s), 3 * s, 0.9 * s, look.body)
	add(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6 * s, CFrame = CFrame.new(0, 7.1 * s, -1.6 * s), Color = look.body })
	add(model, { Name = "Beak", Size = Vector3.new(0.6, 0.4, 1.2) * s, CFrame = CFrame.new(0, 7 * s, -2.6 * s), Color = look.accent })
	eyes(model, CFrame.new(0, 7.4 * s, -2.2 * s), 0.4 * s, 0.4 * s)
	for _, side in { -1, 1 } do
		add(model, { Name = "JetWing", Class = "WedgePart", Size = Vector3.new(0.3, 1.5, 3) * s, CFrame = CFrame.new(side * 1.9 * s, 3.6 * s, 0.8 * s) * CFrame.Angles(0, 0, math.rad(side * 80)), Color = Color3.fromRGB(130, 130, 140), Material = Enum.Material.Metal })
	end
end

builders.Cat = function(model, look, s)
	-- Trippi Troppi: segmented shrimp body with a cat head.
	for i = 0, 3 do
		addEllipsoid(model, { Name = "Segment", Size = Vector3.new(2.6 - i * 0.4, 1.6, 1.6) * s, CFrame = CFrame.new(0, (1.2 + i * 0.3) * s, (i * 1.2) * s), Color = look.body })
	end
	add(model, { Name = "Tail", Class = "WedgePart", Size = Vector3.new(1.6, 0.3, 1.4) * s, CFrame = CFrame.new(0, 2.3 * s, 5 * s), Color = look.body })
	add(model, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6 * s, CFrame = CFrame.new(0, 3 * s, -1.4 * s), Color = look.accent })
	for _, side in { -1, 1 } do
		add(model, { Name = "Ear", Class = "WedgePart", Size = Vector3.new(0.3, 1, 0.8) * s, CFrame = CFrame.new(side * 0.8 * s, 4.6 * s, -1.4 * s), Color = look.accent })
		add(model, { Name = "Whisker", Size = Vector3.new(1.4, 0.08, 0.08) * s, CFrame = CFrame.new(side * 1.3 * s, 2.7 * s, -2.6 * s), Color = BLACK })
	end
	eyes(model, CFrame.new(0, 3.4 * s, -2.5 * s), 0.55 * s, 0.6 * s)
end

-- Returns a model whose pivot sits at its feet, facing -Z.
function ModelFactory.Brainrot(id: string, scale: number?): Model
	local data = BrainrotData.Get(id) or BrainrotData.Get(BrainrotData.ChaserId)
	assert(data, "missing brainrot data")
	local s = (scale or 1) * data.look.scale

	local model = Instance.new("Model")
	model.Name = data.id

	local root = add(model, { Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 0.5 * s, 0), Transparency = 1, CastShadow = false })
	model.PrimaryPart = root

	local builder = builders[data.look.shape] or builders.Log
	builder(model, data.look, s)

	model.WorldPivot = CFrame.identity
	model:SetAttribute("BrainrotId", data.id)
	return model
end

-- The villain: a blocky evil scientist in a lab coat with glowing goggles,
-- wild hair and a giant net for catching Brainrots. Pivot at the feet,
-- facing -Z.
function ModelFactory.Villain(scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Villain"
	local root = add(model, { Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 0.5 * s, 0), Transparency = 1, CastShadow = false })
	model.PrimaryPart = root

	local coat = Color3.fromRGB(235, 235, 240)
	local dark = Color3.fromRGB(35, 25, 45)
	local skin = Color3.fromRGB(200, 170, 150)
	local purple = Color3.fromRGB(120, 40, 170)
	-- Legs & boots
	for _, side in { -0.7, 0.7 } do
		add(model, { Name = "Leg", Size = Vector3.new(1.2, 3, 1.2) * s, CFrame = CFrame.new(side * s, 1.9 * s, 0), Color = dark })
		add(model, { Name = "Boot", Size = Vector3.new(1.4, 0.8, 1.9) * s, CFrame = CFrame.new(side * s, 0.4 * s, -0.25 * s), Color = Color3.fromRGB(20, 20, 20) })
	end
	-- Lab coat body with a long tail
	add(model, { Name = "Coat", Size = Vector3.new(3.2, 3.8, 1.9) * s, CFrame = CFrame.new(0, 5.2 * s, 0), Color = coat })
	add(model, { Name = "CoatTail", Size = Vector3.new(3.3, 1.6, 1.5) * s, CFrame = CFrame.new(0, 3.0 * s, 0.2 * s), Color = coat })
	add(model, { Name = "Tie", Size = Vector3.new(0.5, 2.2, 0.2) * s, CFrame = CFrame.new(0, 5.6 * s, -1 * s), Color = purple })
	-- Arms with purple gloves
	for _, side in { -1, 1 } do
		add(model, { Name = "Arm", Size = Vector3.new(1, 3.2, 1) * s, CFrame = CFrame.new(side * 2.1 * s, 5.2 * s, -0.3 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color = coat })
		add(model, { Name = "Glove", Size = Vector3.new(1.1, 1, 1.1) * s, CFrame = CFrame.new(side * 2.1 * s, 3.9 * s, -1.3 * s), Color = purple })
	end
	-- Head, goggles, grin, hair
	add(model, { Name = "Head", Size = Vector3.new(2.2, 2.2, 2.2) * s, CFrame = CFrame.new(0, 8.2 * s, 0), Color = skin })
	add(model, { Name = "GoggleStrap", Size = Vector3.new(2.3, 0.45, 2.3) * s, CFrame = CFrame.new(0, 8.5 * s, 0), Color = Color3.fromRGB(40, 40, 40) })
	for _, side in { -0.5, 0.5 } do
		add(model, { Name = "Goggle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.9, 0.9) * s, CFrame = CFrame.new(side * s, 8.5 * s, -1.15 * s) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(120, 255, 90), Material = Enum.Material.Neon })
	end
	add(model, { Name = "Grin", Size = Vector3.new(1.3, 0.25, 0.1) * s, CFrame = CFrame.new(0, 7.6 * s, -1.12 * s), Color = Color3.fromRGB(20, 20, 20) })
	for i = -2, 2 do
		add(model, { Name = "Hair", Class = "WedgePart", Size = Vector3.new(0.5, 1.4, 1.2) * s, CFrame = CFrame.new(i * 0.45 * s, 9.9 * s, 0.1 * s) * CFrame.Angles(math.rad(i * 8), 0, math.rad(i * 12)), Color = purple })
	end
	-- The Brainrot-catching net
	local pole = add(model, { Name = "NetPole", Size = Vector3.new(0.3, 5, 0.3) * s, CFrame = CFrame.new(2.4 * s, 6 * s, -2 * s) * CFrame.Angles(math.rad(-40), 0, 0), Color = Color3.fromRGB(120, 90, 60) })
	pole.Name = "Bat" -- the chaser swings its "Bat" part
	add(model, { Name = "NetRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.6, 2.6) * s, CFrame = CFrame.new(2.4 * s, 8.3 * s, -4 * s) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(230, 230, 230), Transparency = 0.3 })

	model.WorldPivot = CFrame.identity
	return model
end

-- A floating name tag above a model.
function ModelFactory.NameTag(model: Model, text: string, color: Color3?, height: number?)
	local root = model.PrimaryPart
	if not root then
		return
	end
	Util.Billboard(root, text, UDim2.fromOffset(260, 50), Vector3.new(0, height or 10, 0), color)
end

return ModelFactory
