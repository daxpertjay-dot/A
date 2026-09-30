--!strict
-- Tiny UI construction kit so every screen shares the same chunky,
-- colourful Brainrot style.

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Colors = {
	Panel = Color3.fromRGB(30, 22, 52),
	PanelLight = Color3.fromRGB(52, 40, 88),
	Accent = Color3.fromRGB(255, 70, 160),
	Accent2 = Color3.fromRGB(80, 230, 255),
	Gold = Color3.fromRGB(255, 205, 60),
	Good = Color3.fromRGB(90, 220, 110),
	Bad = Color3.fromRGB(255, 80, 80),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(180, 170, 210),
}

export type Props = { [string]: any }

function UIKit.New(className: string, props: Props, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function UIKit.Corner(radius: number?): UICorner
	return UIKit.New("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UIKit.Stroke(thickness: number?, color: Color3?): UIStroke
	return UIKit.New("UIStroke", { Thickness = thickness or 3, Color = color or Color3.new(0, 0, 0), ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function UIKit.TextStroke(thickness: number?): UIStroke
	return UIKit.New("UIStroke", { Thickness = thickness or 2, Color = Color3.new(0, 0, 0) })
end

function UIKit.Padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return UIKit.New("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function UIKit.List(direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return UIKit.New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.Label(props: Props): TextLabel
	local defaults: Props = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 30),
	}
	for k, v in props do
		defaults[k] = v
	end
	local label = UIKit.New("TextLabel", defaults)
	UIKit.TextStroke(2).Parent = label
	return label
end

function UIKit.Button(props: Props, onClick: () -> ()): TextButton
	local defaults: Props = {
		BackgroundColor3 = UIKit.Colors.Accent,
		Font = Enum.Font.FredokaOne,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(160, 44),
	}
	for k, v in props do
		defaults[k] = v
	end
	local button = UIKit.New("TextButton", defaults)
	UIKit.Corner(10).Parent = button
	UIKit.Stroke(3).Parent = button
	UIKit.TextStroke(2).Parent = button
	UIKit.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = button })
	button.Activated:Connect(function()
		local scale = button:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = button })
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		onClick()
	end)
	return button
end

-- A centred modal panel with a title bar and close button. Returns the
-- panel frame and its content frame.
function UIKit.Panel(parent: Instance, title: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local panel = UIKit.New("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = UIKit.Colors.Panel,
		Visible = false,
		Parent = parent,
	})
	UIKit.Corner(18).Parent = panel
	UIKit.Stroke(4, UIKit.Colors.Accent).Parent = panel
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(860, 620), Parent = panel })

	UIKit.Label({ Text = title, Size = UDim2.new(1, -110, 0, 44), Position = UDim2.fromOffset(18, 10), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
	UIKit.Button({ Text = "X", Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -56, 0, 10), BackgroundColor3 = UIKit.Colors.Bad }, onClose).Parent = panel

	local content = UIKit.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -80),
		Parent = panel,
	})
	return panel, content
end

function UIKit.Scroller(parent: Instance, props: Props?): ScrollingFrame
	local defaults: Props = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
		Parent = parent,
	}
	for k, v in props or {} do
		defaults[k] = v
	end
	return UIKit.New("ScrollingFrame", defaults)
end

function UIKit.Card(props: Props): Frame
	local defaults: Props = { BackgroundColor3 = UIKit.Colors.PanelLight, Size = UDim2.fromOffset(150, 190) }
	for k, v in props do
		defaults[k] = v
	end
	local card = UIKit.New("Frame", defaults)
	UIKit.Corner(12).Parent = card
	UIKit.Stroke(3).Parent = card
	return card
end

function UIKit.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function UIKit.Pop(instance: GuiObject)
	local scale = instance:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = instance })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return UIKit
