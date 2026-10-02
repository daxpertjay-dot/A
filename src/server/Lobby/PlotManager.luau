--!strict
-- Player bases. Every player gets their own fenced plot off the ring road
-- (positions: LobbyBuilder.PlotSlots; in a saved map, the Plot<n> Models):
--
--   back   ┌────────────────────────────┐
--          │  🏃 START RUN (your portal) │  ← mini run lane
--          │  🏆 high score              │
--          │ [🧠][🧠][🧠][🔒][🔒]         │  ← rescued Brainrots on pedestals:
--          │ [🧠][🧠][🧠][🔒][🔒]         │     each adds to your SCORE MULTIPLIER
--          │   ⭐ SCORE MULTIPLIER x7     │  ← plus ⚡ Hype charging up
--   front  └──────── "Jay's BASE" ──────┘  ← faces the ring road / plaza
--
-- Plot local space: -Z points at the entrance (toward the plaza).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local MutationData = require(Shared.MutationData)
local Progression = require(Shared.Progression)
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
	folder: Model,
	dynamic: Folder,
	owner: Player?,
	signLabel: TextLabel,
	bestLabel: TextLabel,
	multiplierLabel: TextLabel,
	pedestals: { CFrame },
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

-- Wooden fence like the references: brown posts with dark capped tops and
-- two rails.
local function fence(parent: Instance, cf: CFrame, from: Vector3, to: Vector3)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	local rail = CFrame.lookAt((cf * CFrame.new(mid)).Position, (cf * CFrame.new(to)).Position)
	for _, y in { 1.4, 2.8 } do
		part({ Parent = parent, Name = "FenceRail", Size = Vector3.new(0.5, 0.7, length), CFrame = rail * CFrame.new(0, y, 0), Color = LobbyBuilder.Colors.Wood })
	end
	local posts = math.max(1, math.floor(length / 10))
	for i = 0, posts do
		local p = from:Lerp(to, i / posts)
		part({ Parent = parent, Name = "FencePost", Size = Vector3.new(1.2, 3.6, 1.2), CFrame = cf * CFrame.new(p + Vector3.new(0, 1.8, 0)), Color = LobbyBuilder.Colors.FencePost })
		part({ Parent = parent, Name = "FenceCap", Size = Vector3.new(1.7, 1, 1.7), CFrame = cf * CFrame.new(p + Vector3.new(0, 4, 0)), Color = LobbyBuilder.Colors.FenceCap })
	end
end

-- Builds base number `index` as a Model ("Plot<index>") in the lobby. The
-- pieces the game needs later are found again by name (see adoptPlot), so a
-- base saved in the map and edited in Studio works the same way.
local function buildPlot(index: number, slot: LobbyBuilder.PlotSlot): Model
	local center, facing = slot.center, slot.facing
	local cf = CFrame.lookAt(center, center + facing)
	local folder = Instance.new("Model")
	folder.Name = ("Plot%d"):format(index)
	folder.Parent = LobbyBuilder.Folder()

	local W, D = L.PlotWidth, L.PlotDepth
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]

	-- Grass floor with a coloured border, fenced (gap at the front)
	local floor = part({ Parent = folder, Name = "PlotFloor", Size = Vector3.new(W, 1.2, D), CFrame = cf, Color = LobbyBuilder.Colors.PlotGrass })
	folder.PrimaryPart = floor
	for _, side in { -1, 1 } do
		part({ Parent = folder, Name = "PlotBorder", Size = Vector3.new(2, 1.3, D), CFrame = cf * CFrame.new(side * (W / 2 - 1), 0.05, 0), Color = color })
		part({ Parent = folder, Name = "PlotBorder", Size = Vector3.new(W, 1.3, 2), CFrame = cf * CFrame.new(0, 0.05, side * (D / 2 - 1)), Color = color })
	end
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
	Util.SurfaceLabel(beam, Enum.NormalId.Front, "EMPTY PLOT", { PixelsPerStud = 20 })

	-- A bush in each corner (your "Bush" model if you've made one)
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		LobbyBuilder.Bush(folder, (cf * CFrame.new(corner.X * (W / 2 - 5), y, corner.Y * (D / 2 - 6))).Position)
	end

	-- ⭐ Big score multiplier sign facing the entrance
	local multiplierSign = Instance.new("Model")
	multiplierSign.Name = "MultiplierSign"
	multiplierSign.Parent = folder
	LobbyBuilder.Sign(multiplierSign, (cf * CFrame.new(0, y + 9, -32)).Position, (cf * CFrame.new(0, y + 9, -60)).Position, "⭐ SCORE MULTIPLIER x1", Color3.fromRGB(255, 190, 0), 26, 5, 6.5)

	-- 🧠 Brainrot pedestals (2 rows of 5), numbered in the order they fill up.
	-- Locked ones can be bought with coins.
	local n = 0
	for _, z in { -18, -4 } do
		for _, x in { -24, -12, 0, 12, 24 } do
			n += 1
			local pedestal = part({ Parent = folder, Name = ("Pedestal%d"):format(n), Size = Vector3.new(7, 2, 7), CFrame = cf * CFrame.new(x, y + 1, z), Color = Color3.fromRGB(245, 245, 245) })
			part({ Parent = folder, Name = "PedestalTrim", Size = Vector3.new(7.4, 0.4, 7.4), CFrame = pedestal.CFrame * CFrame.new(0, 1.1, 0), Color = color:Lerp(Color3.new(0, 0, 0), 0.2) })
		end
	end

	-- 🏃 Mini run area: a little 3-lane track leading to your own run portal.
	local trackCf = cf * CFrame.new(0, y, 30)
	part({ Parent = folder, Name = "MiniTrack", Size = Vector3.new(24, 0.4, 26), CFrame = trackCf * CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(70, 70, 80) })
	for _, lx in { -4, 4 } do
		for dz = -11, 11, 5 do
			part({ Parent = folder, Name = "MiniLaneLine", Size = Vector3.new(0.4, 0.1, 2.5), CFrame = trackCf * CFrame.new(lx, 0.45, dz), Color = Color3.fromRGB(255, 255, 255), Studs = false })
		end
	end
	part({ Parent = folder, Name = "MiniBarricade", Size = Vector3.new(6, 2, 0.6), CFrame = trackCf * CFrame.new(-8, 1.4, -6), Color = Color3.fromRGB(230, 60, 60) })
	for dz = -10, 6, 4 do
		local coin = part({ Parent = folder, Name = "MiniCoin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6), CFrame = trackCf * CFrame.new(0, 2, dz) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon, CanCollide = false, Studs = false })
		CollectionService:AddTag(coin, "LobbySpin")
		coin:SetAttribute("Speed", 3)
	end
	-- High score sign beside the track
	local highScoreSign = Instance.new("Model")
	highScoreSign.Name = "HighScoreSign"
	highScoreSign.Parent = folder
	LobbyBuilder.Sign(highScoreSign, (cf * CFrame.new(-24, y + 7, 26)).Position, (cf * CFrame.new(-24, y + 7, 0)).Position, "🏆 HIGH SCORE: 0", Color3.fromRGB(255, 170, 0), 14, 4, 5)

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
	CollectionService:AddTag(trigger, "RunEntranceTrigger")
	part({ Parent = folder, Name = "PortalBackstop", Size = Vector3.new(26, 18, 1), CFrame = trackCf * CFrame.new(0, 9, 13.5), Transparency = 1, Studs = false })

	local dynamic = Instance.new("Folder")
	dynamic.Name = "Dynamic"
	dynamic.Parent = folder
	return folder
end

-- Builds every base into the lobby (when it's generated from code, and when
-- the map is baked).
function PlotManager.BuildPlots()
	for i, slot in LobbyBuilder.PlotSlots() do
		buildPlot(i, slot)
	end
end

local function textIn(container: Instance?): TextLabel?
	return if container then container:FindFirstChildWhichIsA("TextLabel", true) else nil
end

-- Picks up a base from the map by the names buildPlot gave its pieces.
local function adoptPlot(index: number, model: Model): Plot?
	local floor = model:FindFirstChild("PlotFloor")
	local trigger = model:FindFirstChild("RunEntranceTrigger")
	local signLabel = textIn(model:FindFirstChild("ArchBeam"))
	local multiplierLabel = textIn(model:FindFirstChild("MultiplierSign"))
	local bestLabel = textIn(model:FindFirstChild("HighScoreSign"))
	if not (floor and floor:IsA("BasePart") and trigger and trigger:IsA("BasePart") and signLabel and multiplierLabel and bestLabel) then
		warn(("[PlotManager] %s is missing pieces (PlotFloor, RunEntranceTrigger, ArchBeam, MultiplierSign, HighScoreSign); skipping it"):format(model.Name))
		return nil
	end
	local pedestals = {}
	for n = 1, Config.Score.MaxPedestals do
		local pedestal = model:FindFirstChild(("Pedestal%d"):format(n))
		if pedestal and pedestal:IsA("BasePart") then
			-- Brainrots stand on top of the pedestal, facing the way it faces.
			table.insert(pedestals, pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2 + 0.3, 0))
		end
	end
	local dynamic = model:FindFirstChild("Dynamic")
	if not dynamic then
		dynamic = Instance.new("Folder")
		dynamic.Name = "Dynamic"
		dynamic.Parent = model
	end
	dynamic:ClearAllChildren()
	trigger:SetAttribute("OwnerUserId", 0)
	trigger:SetAttribute("PlotIndex", index)
	return {
		index = index,
		cf = floor.CFrame,
		folder = model,
		dynamic = dynamic :: Folder,
		owner = nil,
		signLabel = signLabel,
		bestLabel = bestLabel,
		multiplierLabel = multiplierLabel,
		pedestals = pedestals,
		trigger = trigger,
		color = floor.Color,
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

	-- Signs update every time (Hype charges continuously).
	plot.signLabel.Text = if owner then ("%s's BASE"):format(owner.DisplayName) else "EMPTY PLOT"
	plot.bestLabel.Text = if profile then ("🏆 HIGH SCORE: %s"):format(Util.FormatNumber(profile.Stats.HighScore)) else "🏆 HIGH SCORE: -"
	plot.multiplierLabel.Text = if profile
		then ("⭐ SCORE MULTIPLIER %s\n⚡ HYPE %d%%"):format(Progression.FormatMultiplier(PlayerData.Multiplier(profile)), math.floor(profile.Hype * 100))
		else "⭐ SCORE MULTIPLIER"
	plot.trigger:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)

	-- The Brainrots themselves are only rebuilt when they change.
	local levels = {}
	if profile then
		for _, key in displayed do
			local id = MutationData.Split(key)
			table.insert(levels, tostring((Progression.Level(profile.BrainrotXP[id]))))
		end
	end
	local signature = if owner and profile then table.concat({ owner.Name, table.concat(displayed, ","), table.concat(levels, ","), tostring(profile.Pedestals) }, "|") else ""
	if signature == plot.signature then
		return
	end
	plot.signature = signature
	plot.dynamic:ClearAllChildren()
	if not owner or not profile then
		return
	end

	for i, pedestalCf in plot.pedestals do
		local key = displayed[i]
		local data = if key then BrainrotData.Get((MutationData.Split(key))) else nil
		if key and data then
			-- A rescued Brainrot showing the multiplier it adds.
			local mutation = MutationData.Get(select(2, MutationData.Split(key)))
			local model = ModelFactory.Brainrot(key, 0.9)
			model:PivotTo(pedestalCf)
			model.Parent = plot.dynamic
			CollectionService:AddTag(model, "LobbyDance")
			model:SetAttribute("Style", "Hop")
			local level = Progression.Level(profile.BrainrotXP[data.id])
			label(
				model,
				("%s %s  Lv %d\n+%s SCORE"):format(data.icon, MutationData.Label(key), level, Progression.FormatMultiplier(PlayerData.BrainrotBonus(profile, key))),
				if mutation then mutation.color else BrainrotData.RarityColors[data.rarity],
				9
			)
		else
			local marker = part({ Parent = plot.dynamic, Name = "SlotMarker", Size = Vector3.new(6.6, 0.2, 6.6), CFrame = pedestalCf * CFrame.new(0, -0.15, 0), Transparency = 0.5, CanCollide = false, Studs = false, Color = Color3.fromRGB(255, 255, 255) })
			if i <= profile.Pedestals then
				label(marker, "EMPTY\nrescue Brainrots on runs!", Color3.fromRGB(210, 210, 210), 3)
			else
				-- Locked: buy it at the upgrade shop / Upgrades button.
				marker.Color = Color3.fromRGB(60, 60, 70)
				marker.Transparency = 0.1
				label(marker, "🔒 LOCKED PEDESTAL\nbuy more in ⬆️ Upgrades", Color3.fromRGB(255, 200, 90), 3)
				LobbyBuilder.Prompt(marker, "Buy Pedestal", "Locked", "Upgrades")
			end
		end
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
			notify(player, "🏠 This is your base! Rescued Brainrots here boost your score multiplier.", Color3.fromRGB(140, 255, 140))
			return
		end
	end
	notify(player, "All bases are taken — use the public run gate in the SAFE ZONE!", Color3.fromRGB(255, 200, 90))
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
	-- Use the bases in the lobby map (Plot1, Plot2, …); build them if the
	-- map has none.
	local lobby = LobbyBuilder.Folder()
	if not lobby:FindFirstChild("Plot1") then
		PlotManager.BuildPlots()
	end
	local index = 1
	while true do
		local model = lobby:FindFirstChild(("Plot%d"):format(index))
		if not model then
			break
		end
		local plot = if model:IsA("Model") then adoptPlot(#plots + 1, model) else nil
		if plot then
			table.insert(plots, plot)
		end
		index += 1
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

	-- 🏠 MY BASE button, and the client's fallback when it has no usable
	-- character after a run ("Respawn"): respawn if needed, otherwise just
	-- teleport home.
	local lastRespawn: { [Player]: number } = {}
	Remotes.Event("GoToBase").OnServerEvent:Connect(function(player, request)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0 and character ~= nil and character:IsDescendantOf(workspace)
		if (not alive or request == "Respawn") and not player:GetAttribute("InRun") then
			local now = os.clock()
			if (lastRespawn[player] or 0) < now then
				lastRespawn[player] = now + 3
				player:LoadCharacter() -- CharacterAdded sends them home
			end
			return
		end
		PlotManager.SendHome(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRespawn[player] = nil
	end)
end

return PlotManager
