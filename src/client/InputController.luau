--!strict
-- Run input: exactly four movement actions (Left, Right, Jump, Roll) plus the
-- equipment slots. Keyboard (A/D/←/→, W/↑/Space, S/↓, 1-3), swipes on mobile,
-- and gamepad (D-pad / thumbstick flicks, A to jump, B to roll, X/Y/RB for equipment).

local UserInputService = game:GetService("UserInputService")

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Signal"))

local InputController = {}

InputController.Action = Signal.new() -- ("Left" | "Right" | "Jump" | "Roll")
InputController.Equipment = Signal.new() -- (slot: number)

local enabled = false

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.D] = "Right",
	[Enum.KeyCode.Right] = "Right",
	[Enum.KeyCode.W] = "Jump",
	[Enum.KeyCode.Up] = "Jump",
	[Enum.KeyCode.Space] = "Jump",
	[Enum.KeyCode.S] = "Roll",
	[Enum.KeyCode.Down] = "Roll",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",
	[Enum.KeyCode.ButtonA] = "Jump",
	[Enum.KeyCode.DPadUp] = "Jump",
	[Enum.KeyCode.ButtonB] = "Roll",
	[Enum.KeyCode.DPadDown] = "Roll",
}

local EQUIP_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonR1] = 3,
}

local SWIPE_MIN_PIXELS = 40
local touchStarts: { [InputObject]: Vector3 } = {}
local stickLatched = false

function InputController.SetEnabled(value: boolean)
	enabled = value
	table.clear(touchStarts)
end

function InputController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			if not processed then
				touchStarts[input] = input.Position
			end
			return
		end
		if processed then
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			InputController.Action:Fire(action)
			return
		end
		local slot = EQUIP_KEYS[input.KeyCode]
		if slot then
			InputController.Equipment:Fire(slot)
		end
	end)

	-- Swipes: decide as soon as the finger has travelled far enough so the
	-- response feels instant, like Subway Surfers.
	UserInputService.InputChanged:Connect(function(input)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			local start = touchStarts[input]
			if not start then
				return
			end
			local delta = input.Position - start
			if delta.Magnitude < SWIPE_MIN_PIXELS then
				return
			end
			touchStarts[input] = nil
			if math.abs(delta.X) > math.abs(delta.Y) then
				InputController.Action:Fire(if delta.X < 0 then "Left" else "Right")
			else
				InputController.Action:Fire(if delta.Y < 0 then "Jump" else "Roll")
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local p = input.Position
			if p.Magnitude < 0.4 then
				stickLatched = false
			elseif not stickLatched and p.Magnitude > 0.75 then
				stickLatched = true
				if math.abs(p.X) > math.abs(p.Y) then
					InputController.Action:Fire(if p.X < 0 then "Left" else "Right")
				else
					InputController.Action:Fire(if p.Y > 0 then "Jump" else "Roll")
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		touchStarts[input] = nil
	end)
end

return InputController
