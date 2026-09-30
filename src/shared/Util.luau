--!strict
-- Small helpers for building parts and labels from code (the lobby, track
-- segments and Brainrot models are all constructed procedurally).

local Util = {}

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	Anchored: boolean?,
	CastShadow: boolean?,
	Reflectance: number?,
	Parent: Instance?,
	Class: string?, -- "Part" (default), "WedgePart", "CornerWedgePart"
}

function Util.Part(props: PartProps): BasePart
	local part: BasePart = Instance.new((props.Class or "Part") :: any)
	part.Name = props.Name or "Part"
	part.Anchored = if props.Anchored == nil then true else props.Anchored
	part.Size = props.Size or Vector3.new(4, 1, 4)
	part.CFrame = props.CFrame or CFrame.identity
	part.Color = props.Color or Color3.fromRGB(200, 200, 200)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	part.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.Reflectance = props.Reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape and part:IsA("Part") then
		(part :: Part).Shape = props.Shape
	end
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

-- A stretched ellipsoid (Part + sphere SpecialMesh) for organic shapes.
function Util.Ellipsoid(props: PartProps): BasePart
	local part = Util.Part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A cylinder standing upright (Roblox cylinders point along X by default).
function Util.UprightCylinder(props: PartProps & { Height: number, Diameter: number }): BasePart
	local cf = props.CFrame or CFrame.identity
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(props.Height, props.Diameter, props.Diameter)
	props.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return Util.Part(props)
end

export type LabelOptions = {
	TextColor: Color3?,
	Background: Color3?,
	BackgroundTransparency: number?,
	Font: Enum.Font?,
	PixelsPerStud: number?,
	Stroke: boolean?,
	Name: string?,
}

function Util.SurfaceLabel(part: BasePart, face: Enum.NormalId, text: string, opts: LabelOptions?): TextLabel
	local o: LabelOptions = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.Name or "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 25
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = o.Background or Color3.new(0, 0, 0)
	label.BackgroundTransparency = if o.BackgroundTransparency == nil then 1 else o.BackgroundTransparency
	label.TextColor3 = o.TextColor or Color3.new(1, 1, 1)
	label.Font = o.Font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.RichText = true
	label.Parent = gui
	if o.Stroke ~= false then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
	end
	return label
end

function Util.Billboard(adornee: Instance, text: string, size: UDim2?, offset: Vector3?, color: Color3?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = size or UDim2.fromOffset(240, 60)
	gui.StudsOffset = offset or Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Adornee = if adornee:IsA("BasePart") then adornee else nil
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	return label
end

function Util.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Util.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential smoothing factor.
function Util.Damp(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

return Util
