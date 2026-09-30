--!strict
-- Player bases. Every player gets their own plot on the street:
--
--   back   ┌────────────────────────────┐
--          │  🏃 START RUN (your portal) │  ← mini run area
--          │  ║ lane ║ lane ║ lane ║     │
--          │ [🧠][🧠][🧠][🧠]            │  ← Brainrot pedestals (earn coins/sec)
--          │ [🧠][🧠][🧠][🧠]            │
--          │ 💰collect  🤝buddy  ⚙️⚙️⚙️   │  ← collect pad · run buddy · equipment
--   front  └──────── "Jay's BASE" ──────┘  ← faces the street
--
-- Plot local space: -Z points at the street, +X runs along it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local EquipmentData = require(Shared.EquipmentData)
local ModelFactory = require(Shared.ModelFactory)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local PlayerData = require(script.Parent.Parent.PlayerData)
local LobbyBuilder = require(script.Parent.LobbyBuilder)

local PlotManager = {}

local L = Config.Lobby
local part = LobbyBuilder.Part

type Plot = {
	index: number,
	cf: CFrame,
	folder: Folder,
	dynamic: Folder,
	owner: Player?,
	signLabel: TextLabel,
	bestLabel: TextLabel,
	padLabel: TextLabel,
	pad: BasePart,
	pedestals: { CFrame },
	stands: { BasePart },
	buddyPad: BasePart,
	trigger: BasePart,
	color: Color3,
	signature: string,
}

local plots: { Plot } = {}
local playerPlot: { [Player]: Plot } = {}

local PLOT_COLORS = {
	Color3.fromRGB(255, 205, 120),
	Color3.fromRGB(150, 210, 255),
	Color3.fromRGB(200, 170, 255),
	Color3.fromRGB(255, 170, 200),
	Color3.fromRGB(170, 235, 150),
	Color3.fromRGB(255, 235, 130),
	Color3.fromRGB(140, 230, 220),
	Color3.fromRGB(255, 180, 140),
}

local function notify(player: Player, text: string, color: Color3?)
	Remotes.Event("Notify"):FireClient(player, text, color)
end

-- ───────────────────────────── building ─────────────────────────────

local function fence(parent: Instance, cf: CFrame, from: Vector3, to: Vector3)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local rail = CFrame.lookAt((cf * CFrame.new(mid)).Position, (cf * CFrame.new(to)).Position)
	part({ Parent = parent, Name = "FenceRail", Size = Vector3.new(0.6, 0.6, length), CFrame = rail * CFrame.new(0, 2.4, 0), Color = Color3.fromRGB(255, 255, 255) })
	part({ Parent = parent, Name = "FenceRail", Size = Vector3.new(0.6, 0.6, length), CFrame = rail * CFrame.new(0, 1.3, 0), Color = Color3.fromRGB(255, 255, 255) })
	local posts = math.max(1, math.floor(length / 8))
	for i = 0, posts do
		local p = from:Lerp(to, i / posts)
		part({ Parent = parent, Name = "FencePost", Size = Vector3.new(1, 3.4, 1), CFrame = cf * CFrame.new(p + Vector3.new(0, 1.7, 0)), Color = Color3.fromRGB(255, 255, 255) })
	end
end

local function buildPlot(index: number, center: Vector3, facing: Vector3): Plot
	local cf = CFrame.lookAt(center, center + facing)
	local folder = Instance.new("Folder")
	folder.Name = ("Plot%d"):format(index)
	folder.Parent = LobbyBuilder.Folder()
	local dynamic = Instance.new("Folder")
	dynamic.Name = "Dynamic"
	dynamic.Parent = folder

	local W, D = L.PlotWidth, L.PlotDepth
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]

	-- Floor + fence (gap at the front for the entrance)
	part({ Parent = folder, Name = "PlotFloor", Size = Vector3.new(W, 1.2, D), CFrame = cf * CFrame.new(0, 0, 0), Color = color })
	local y = 0.6
	fence(folder, cf, Vector3.new(-W / 2, y, D / 2), Vector3.new(W / 2, y, D / 2))
	fence(folder, cf, Vector3.new(-W / 2, y, -D / 2), Vector3.new(-W / 2, y, D / 2))
	fence(folder, cf, Vector3.new(W / 2, y, -D / 2), Vector3.new(W / 2, y, D / 2))
	fence(folder, cf, Vector3.new(-W / 2, y, -D / 2), Vector3.new(-9, y, -D / 2))
	fence(folder, cf, Vector3.new(9, y, -D / 2), Vector3.new(W / 2, y, -D / 2))

	-- Name arch over the entrance
	for _, sx in { -9, 9 } do
		part({ Parent = folder, Name = "ArchPost", Size = Vector3.new(2, 14, 2), CFrame = cf * CFrame.new(sx, y + 7, -D / 2), Color = LobbyBuilder.Colors.Wood })
	end
	local beam = part({ Parent = folder, Name = "ArchBeam", Size = Vector3.new(22, 4, 2), CFrame = cf * CFrame.new(0, y + 15, -D / 2), Color = color:Lerp(Color3.new(0, 0, 0), 0.25) })
	local signLabel = Util.SurfaceLabel(beam, Enum.NormalId.Front, "EMPTY PLOT", { PixelsPerStud = 20 })

	-- 💰 Collect pad
	local pad = part({ Parent = folder, Name = "CollectPad", Size = Vector3.new(9, 1, 9), CFrame = cf * CFrame.new(-20, y + 0.5, -30), Color = Color3.fromRGB(80, 220, 90), Material = Enum.Material.Neon, Studs = false })
	pad.CanTouch = true
	local padLabel = Util.Billboard(pad, "💰 COLLECT", UDim2.fromOffset(220, 70), Vector3.new(0, 5, 0), Color3.fromRGB(140, 255, 140))

	-- 🤝 Run buddy pad
	local buddyPad = part({ Parent = folder, Name = "BuddyPad", Size = Vector3.new(8, 1, 8), CFrame = cf * CFrame.new(0, y + 0.5, -28), Color = Color3.fromRGB(255, 255, 255) })
	LobbyBuilder.Prompt(buddyPad, "Change Buddy", "Run Buddy", "Brainrots")

	-- 🧠 Brainrot pedestals (2 rows of 4)
	local pedestals = {}
	for _, z in { -12, 4 } do
		for _, x in { -21, -7, 7, 21 } do
			local pedestal = part({ Parent = folder, Name = "Pedestal", Size = Vector3.new(7, 2, 7), CFrame = cf * CFrame.new(x, y + 1, z), Color = Color3.fromRGB(245, 245, 245) })
			part({ Parent = folder, Name = "PedestalTrim", Size = Vector3.new(7.4, 0.4, 7.4), CFrame = pedestal.CFrame * CFrame.new(0, 1.1, 0), Color = color:Lerp(Color3.new(0, 0, 0), 0.2) })
			table.insert(pedestals, cf * CFrame.new(x, y + 2.3, z))
		end
	end

	-- ⚙️ Equipment stands (your loadout on display)
	local stands = {}
	for i, x in { 15, 21.5, 28 } do
		local stand = part({ Parent = folder, Name = "EquipmentStand", Size = Vector3.new(4.5, 4, 4.5), CFrame = cf * CFrame.new(x, y + 2, -30), Color = Color3.fromRGB(90, 90, 110) })
		local holo = part({ Parent = folder, Name = "EquipmentHolo", Size = Vector3.new(2.5, 2.5, 2.5), CFrame = stand.CFrame * CFrame.new(0, 4, 0), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.ForceField, CanCollide = false, Studs = false })
		CollectionService:AddTag(holo, "LobbySpin")
		holo:SetAttribute("Speed", 1.5)
		stand:SetAttribute("Slot", i)
		table.insert(stands, stand)
	end
	LobbyBuilder.Prompt(stands[2], "Equipment", "Your Loadout", "Loadout")

	-- 🏃 Mini run area: a little 3-lane track leading to your own run portal.
	local trackCf = cf * CFrame.new(0, y, 27)
	part({ Parent = folder, Name = "MiniTrack", Size = Vector3.new(24, 0.4, 26), CFrame = trackCf * CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(70, 70, 80) })
	for _, lx in { -4, 4 } do
		for dz = -11, 11, 5 do
			part({ Parent = folder, Name = "MiniLaneLine", Size = Vector3.new(0.4, 0.1, 2.5), CFrame = trackCf * CFrame.new(lx, 0.45, dz), Color = Color3.fromRGB(255, 255, 255), Studs = false })
		end
	end
	part({ Parent = folder, Name = "MiniBarricade", Size = Vector3.new(6, 2, 0.6), CFrame = trackCf * CFrame.new(-8, 1.4, -6), Color = Color3.fromRGB(230, 60, 60) })
	part({ Parent = folder, Name = "MiniSign", Size = Vector3.new(6, 3, 0.4), CFrame = trackCf * CFrame.new(8, 4.5, 0), Color = Color3.fromRGB(40, 140, 255) })
	for _, sx in { 5.2, 10.8 } do
		part({ Parent = folder, Name = "MiniSignPost", Size = Vector3.new(0.4, 6, 0.4), CFrame = trackCf * CFrame.new(sx, 3, 0), Color = Color3.fromRGB(80, 80, 90) })
	end
	for dz = -10, 6, 4 do
		local coin = part({ Parent = folder, Name = "MiniCoin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6), CFrame = trackCf * CFrame.new(0, 2, dz) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon, CanCollide = false, Studs = false })
		CollectionService:AddTag(coin, "LobbySpin")
		coin:SetAttribute("Speed", 3)
	end
	-- Best-distance sign beside the track
	local bestLabel = LobbyBuilder.Sign(folder, (cf * CFrame.new(-21, y + 7, 24)).Position, (cf * CFrame.new(-21, y + 7, 0)).Position, "🏆 BEST: 0m", Color3.fromRGB(255, 170, 0), 12, 4, 5)

	-- The portal
	for _, sx in { -12, 12 } do
		part({ Parent = folder, Name = "PortalPost", Size = Vector3.new(2, 16, 2), CFrame = trackCf * CFrame.new(sx, 8, 12), Color = Color3.fromRGB(176, 124, 74) })
	end
	local portalBeam = part({ Parent = folder, Name = "PortalBeam", Size = Vector3.new(26, 4, 2), CFrame = trackCf * CFrame.new(0, 17, 12), Color = Color3.fromRGB(255, 70, 160) })
	Util.SurfaceLabel(portalBeam, Enum.NormalId.Front, "🏃 START RUN", { PixelsPerStud = 20 })
	local portal = part({ Parent = folder, Name = "RunPortal", Size = Vector3.new(22, 15, 1), CFrame = trackCf * CFrame.new(0, 7.5, 12.5), Color = Color3.fromRGB(130, 70, 255), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Studs = false })
	CollectionService:AddTag(portal, "LobbyPulse")
	local trigger = part({ Parent = folder, Name = "RunEntranceTrigger", Size = Vector3.new(22, 12, 3), CFrame = trackCf * CFrame.new(0, 6, 11), Transparency = 1, CanCollide = false, Studs = false })
	trigger.CanTouch = true
	trigger:SetAttribute("OwnerUserId", 0)
	trigger:SetAttribute("PlotIndex", index)
	CollectionService:AddTag(trigger, "RunEntranceTrigger")
	part({ Parent = folder, Name = "PortalBackstop", Size = Vector3.new(26, 18, 1), CFrame = trackCf * CFrame.new(0, 9, 13.5), Transparency = 1, Studs = false })

	return {
		index = index,
		cf = cf,
		folder = folder,
		dynamic = dynamic,
		owner = nil,
		signLabel = signLabel,
		bestLabel = bestLabel,
		padLabel = padLabel,
		pad = pad,
		pedestals = pedestals,
		stands = stands,
		buddyPad = buddyPad,
		trigger = trigger,
		color = color,
		signature = "",
	}
end

-- ───────────────────────────── contents ─────────────────────────────

local function label(parent: Instance, text: string, color: Color3?, offset: number?)
	local anchor = parent
	if parent:IsA("Model") and parent.PrimaryPart then
		anchor = parent.PrimaryPart
	end
	Util.Billboard(anchor, text, UDim2.fromOffset(200, 54), Vector3.new(0, offset or 7, 0), color)
end

local function refresh(plot: Plot)
	local owner = plot.owner
	local profile = if owner then PlayerData.Get(owner) else nil
	local displayed = if profile then PlayerData.DisplayedBrainrots(profile) else {}
	local signature = if owner and profile
		then table.concat({
			owner.Name,
			table.concat(displayed, ","),
			profile.Buddy,
			table.concat(profile.Loadout, ","),
			tostring(PlayerData.UnlockedSlots(owner)),
			tostring(math.floor(profile.Stats.BestDistance)),
		}, "|")
		else ""
	if signature == plot.signature then
		return
	end
	plot.signature = signature
	plot.dynamic:ClearAllChildren()

	plot.signLabel.Text = if owner then ("%s's BASE"):format(owner.DisplayName) else "EMPTY PLOT"
	plot.bestLabel.Text = if profile then ("🏆 BEST: %sm"):format(Util.FormatNumber(profile.Stats.BestDistance)) else "🏆 BEST: -"
	plot.trigger:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	if not owner or not profile then
		plot.padLabel.Text = "💰 COLLECT"
		for _, stand in plot.stands do
			local gui = stand:FindFirstChild("Billboard")
			if gui then
				gui:Destroy()
			end
		end
		return
	end

	-- Brainrots on pedestals, each showing what it earns.
	for i, pedestalCf in plot.pedestals do
		local id = displayed[i]
		local data = if id then BrainrotData.Get(id) else nil
		if data then
			local model = ModelFactory.Brainrot(data.id, 0.9)
			model:PivotTo(pedestalCf)
			model.Parent = plot.dynamic
			CollectionService:AddTag(model, "LobbyDance")
			model:SetAttribute("Style", "Hop")
			label(model, ("%s %s\n+%s/s"):format(data.icon, data.name, Util.FormatNumber(data.income)), BrainrotData.RarityColors[data.rarity], 9)
		else
			local marker = part({ Parent = plot.dynamic, Name = "EmptySlot", Size = Vector3.new(1, 1, 1), CFrame = pedestalCf, Transparency = 1, CanCollide = false, Studs = false })
			label(marker, "EMPTY\ncatch Brainrots in runs!", Color3.fromRGB(200, 200, 200), 3)
		end
	end

	-- The run buddy stands on its pad.
	local buddy = BrainrotData.Get(profile.Buddy)
	if buddy then
		local model = ModelFactory.Brainrot(buddy.id, 1.1)
		model:PivotTo(plot.buddyPad.CFrame * CFrame.new(0, 0.5, 0))
		model.Parent = plot.dynamic
		CollectionService:AddTag(model, "LobbyDance")
		model:SetAttribute("Style", "Twirl")
		label(model, ("🤝 RUN BUDDY\n%s"):format(buddy.perkText), Color3.fromRGB(255, 240, 140), 11)
	end

	-- Equipment stands show the loadout.
	local unlocked = PlayerData.UnlockedSlots(owner)
	for i, stand in plot.stands do
		local old = stand:FindFirstChild("Billboard")
		if old then
			old:Destroy()
		end
		local item = EquipmentData.Get(profile.Loadout[i])
		local text, color
		if i > unlocked then
			text, color = ("🔒 SLOT %d\n%d runs"):format(i, Config.LoadoutSlotUnlocks[i]), Color3.fromRGB(180, 180, 180)
		elseif item then
			text, color = ("%s\n%s"):format(item.icon, item.name), EquipmentData.RarityColors[item.rarity]
		else
			text, color = ("➕ SLOT %d"):format(i), Color3.fromRGB(230, 230, 230)
		end
		Util.Billboard(stand, text, UDim2.fromOffset(150, 60), Vector3.new(0, 8, 0), color)
	end
end

-- ───────────────────────────── players ─────────────────────────────

function PlotManager.SpawnCFrame(player: Player): CFrame?
	local plot = playerPlot[player]
	if not plot then
		return nil
	end
	-- Just inside the entrance, facing into the base.
	return plot.cf * CFrame.new(0, 4, -L.PlotDepth / 2 + 6) * CFrame.Angles(0, math.pi, 0)
end

function PlotManager.SendHome(player: Player)
	local target = PlotManager.SpawnCFrame(player)
	local character = player.Character
	if target and character and not player:GetAttribute("InRun") then
		character:PivotTo(target)
	end
end

local function assign(player: Player)
	if playerPlot[player] then
		return
	end
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			playerPlot[player] = plot
			refresh(plot)
			PlotManager.SendHome(player)
			notify(player, "🏠 This is your base! Brainrots you catch earn coins here.", Color3.fromRGB(140, 255, 140))
			return
		end
	end
	notify(player, "All bases are taken — use the public run gate at the end of the street!", Color3.fromRGB(255, 200, 90))
end

local function release(player: Player)
	local plot = playerPlot[player]
	if plot then
		plot.owner = nil
		playerPlot[player] = nil
		refresh(plot)
	end
end

function PlotManager.Init()
	local half = LobbyBuilder.StreetLength() / 2
	for side = -1, 1, 2 do
		for i = 1, L.PlotsPerSide do
			local z = -half + L.PlotGap + L.PlotWidth / 2 + (i - 1) * (L.PlotWidth + L.PlotGap)
			local x = side * (L.StreetHalfWidth + L.PlotDepth / 2)
			local center = L.Origin + Vector3.new(x, 0, z)
			table.insert(plots, buildPlot(#plots + 1, center, Vector3.new(-side, 0, 0)))
		end
	end

	-- Refresh a player's base whenever their data changes (first change = loaded).
	PlayerData.OnChanged(function(player)
		if not playerPlot[player] then
			assign(player)
		else
			refresh(playerPlot[player])
		end
	end)
	Players.PlayerRemoving:Connect(release)

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.1)
			PlotManager.SendHome(player)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end

	Remotes.Event("GoToBase").OnServerEvent:Connect(PlotManager.SendHome)

	-- Collect pads: step on your own pad to bank what your Brainrots earned.
	local padDebounce: { [Player]: number } = {}
	for _, plot in plots do
		plot.pad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or player ~= plot.owner or (padDebounce[player] or 0) > os.clock() then
				return
			end
			padDebounce[player] = os.clock() + 1
			local amount = PlayerData.CollectIncome(player)
			if amount > 0 then
				notify(player, ("💰 +%s coins collected!"):format(Util.FormatNumber(amount)), Color3.fromRGB(140, 255, 140))
			end
		end)
	end

	-- Live "pending coins" display on every pad.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, plot in plots do
				local profile = if plot.owner then PlayerData.Get(plot.owner) else nil
				if profile then
					plot.padLabel.Text = ("💰 COLLECT\n%s  (+%s/s)"):format(Util.FormatNumber(profile.PendingIncome), Util.FormatNumber(PlayerData.IncomePerSecond(profile)))
				end
			end
		end
	end)
end

return PlotManager
