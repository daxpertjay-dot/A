--!strict
-- Builds the persistent Brainrot lobby hub:
--
--                  🏆 LEADERBOARD
--        ⚙️ LOADOUT          🧠 COLLECTION
--        📦 CRATES ─── SPAWN ─── 🛒 SHOP
--        🎁 DAILY             📊 STATS
--                 🏃 RUN ENTRANCE / PORTAL
--
-- Stations are opened by walking up to them (ProximityPrompts carry an
-- "OpenPanel" attribute that the client UI listens for). Decorative motion
-- (spinning, bobbing, wandering Brainrots, silly NPC dances) is tagged here
-- and animated client-side by LobbyFX so it costs no server bandwidth.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local CrateData = require(Shared.CrateData)
local ModelFactory = require(Shared.ModelFactory)
local Util = require(Shared.Util)

local LobbyBuilder = {}

local L = Config.Lobby
local ORIGIN = L.Origin

local COLORS = {
	Floor = Color3.fromRGB(255, 120, 200),
	FloorAlt = Color3.fromRGB(120, 220, 255),
	Path = Color3.fromRGB(255, 240, 120),
	Neon = {
		Color3.fromRGB(255, 70, 160),
		Color3.fromRGB(80, 230, 255),
		Color3.fromRGB(170, 255, 60),
		Color3.fromRGB(255, 200, 40),
		Color3.fromRGB(180, 90, 255),
	},
}

local lobby: Folder
local rng = Random.new(1337)

local function at(offset: Vector3): Vector3
	return ORIGIN + offset
end

local function part(props: Util.PartProps): BasePart
	props.Parent = props.Parent or lobby
	return Util.Part(props)
end

local function tag(instance: Instance, tagName: string, attrs: { [string]: any }?)
	CollectionService:AddTag(instance, tagName)
	if attrs then
		for k, v in attrs do
			instance:SetAttribute(k, v)
		end
	end
end

local function prompt(parent: BasePart, action: string, objectText: string, panel: string, arg: string?)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p:SetAttribute("OpenPanel", panel)
	if arg then
		p:SetAttribute("PanelArg", arg)
	end
	p.Parent = parent
	return p
end

-- A big sign on two posts facing the spawn.
local function sign(position: Vector3, facing: Vector3, text: string, color: Color3, width: number?, height: number?)
	local w, h = width or 26, height or 7
	local cf = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))
	for _, side in { -1, 1 } do
		part({ Name = "SignPost", Size = Vector3.new(1, position.Y, 1), CFrame = cf * CFrame.new(side * (w / 2 - 1), -position.Y / 2 + ORIGIN.Y, 0), Color = Color3.fromRGB(60, 60, 70) })
	end
	local board = part({ Name = "Sign", Size = Vector3.new(w, h, 1), CFrame = cf, Color = color, Material = Enum.Material.Neon })
	local face = part({ Name = "SignFace", Size = Vector3.new(w - 1, h - 1, 0.2), CFrame = cf * CFrame.new(0, 0, -0.6), Color = Color3.fromRGB(25, 20, 40) })
	Util.SurfaceLabel(face, Enum.NormalId.Front, text, { TextColor = color, PixelsPerStud = 30 })
	return board
end

-- A cartoon NPC: a Brainrot model on a pedestal with a speech bubble.
local function npc(brainrotId: string, position: Vector3, lookAt: Vector3, speech: string, panel: string, action: string, dance: string)
	local model = ModelFactory.Brainrot(brainrotId, 1)
	model.Name = "NPC_" .. brainrotId
	-- Models face -Z, which is CFrame.lookAt's LookVector.
	model:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
	model.Parent = lobby
	local root = model.PrimaryPart :: BasePart
	ModelFactory.NameTag(model, speech, Color3.fromRGB(255, 255, 140), 11)
	prompt(root, action, BrainrotData.Get(brainrotId) and (BrainrotData.Get(brainrotId) :: any).name or "", panel)
	tag(model, "LobbyDance", { Style = dance })
	return model
end

local function buildGround()
	-- Main plaza: a checkerboard of candy colors.
	local tile = 30
	local half = math.floor(L.Size / tile / 2)
	for x = -half, half do
		for z = -half, half do
			local alt = (x + z) % 2 == 0
			part({
				Name = "Floor",
				Size = Vector3.new(tile, 2, tile),
				CFrame = CFrame.new(at(Vector3.new(x * tile, -1, z * tile))),
				Color = if alt then COLORS.Floor else COLORS.FloorAlt,
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
	-- Yellow brick paths from spawn to every station.
	for _, target in { L.Leaderboard, L.Crates, L.Shop, L.RunEntrance, L.Loadout, L.Collection, L.DailyReward, L.Stats } do
		local mid = target / 2
		local length = target.Magnitude
		part({
			Name = "Path",
			Size = Vector3.new(10, 0.2, length),
			CFrame = CFrame.lookAt(at(Vector3.new(mid.X, 0.1, mid.Z)), at(Vector3.new(target.X, 0.1, target.Z))),
			Color = COLORS.Path,
			Material = Enum.Material.Brick,
			CanQuery = false,
		})
	end
	-- Invisible walls so nobody wanders off the edge.
	local edge = L.Size / 2 + 1
	for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		part({
			Name = "Boundary",
			Size = if dir.X ~= 0 then Vector3.new(2, 80, L.Size + tile * 2) else Vector3.new(L.Size + tile * 2, 80, 2),
			CFrame = CFrame.new(at(dir * edge + Vector3.new(0, 40, 0))),
			Transparency = 1,
		})
	end
end

local function buildSpawn()
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Size = Vector3.new(16, 1, 16)
	spawnLocation.CFrame = CFrame.new(at(Vector3.new(0, 0.5, 0)))
	spawnLocation.Anchored = true
	spawnLocation.Color = Color3.fromRGB(255, 255, 255)
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = lobby

	-- Giant Tung Tung Tung Sahur statue looming over spawn.
	local statue = ModelFactory.Brainrot(BrainrotData.ChaserId, 4.5)
	statue.Name = "SahurStatue"
	statue:PivotTo(CFrame.new(at(Vector3.new(0, 0, -35))))
	statue.Parent = lobby
	part({ Name = "StatueBase", Size = Vector3.new(26, 3, 26), CFrame = CFrame.new(at(Vector3.new(0, 1.5, -35))), Color = Color3.fromRGB(80, 80, 95), Material = Enum.Material.Marble })
	statue:PivotTo(CFrame.new(at(Vector3.new(0, 3, -35))))
	local plaque = part({ Name = "Plaque", Size = Vector3.new(24, 3, 0.4), CFrame = CFrame.new(at(Vector3.new(0, 1.5, -21.9))), Color = Color3.fromRGB(80, 80, 95) })
	Util.SurfaceLabel(plaque, Enum.NormalId.Back, "TUNG TUNG TUNG SAHUR", { TextColor = Color3.fromRGB(255, 220, 90) })
	tag(statue, "LobbyDance", { Style = "Bonk" })

	sign(at(Vector3.new(0, 28, -60)), at(Vector3.new(0, 28, 0)), "🧠 BRAINROT RUNNER 🧠", COLORS.Neon[1], 60, 12)
end

local function buildLeaderboard()
	local pos = at(L.Leaderboard)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos + Vector3.new(0, 22, 0), Vector3.new(facing.X, pos.Y + 22, facing.Z))
	-- Frame
	part({ Name = "BoardFrame", Size = Vector3.new(60, 40, 3), CFrame = cf, Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon })
	local screen = part({ Name = "LeaderboardScreen", Size = Vector3.new(56, 36, 0.4), CFrame = cf * CFrame.new(0, 0, -1.7), Color = Color3.fromRGB(15, 10, 30) })
	tag(screen, "LeaderboardScreen")
	for _, side in { -1, 1 } do
		part({ Name = "Pillar", Size = Vector3.new(4, 42, 4), CFrame = CFrame.new(pos + Vector3.new(side * 32, 21, 0)), Color = Color3.fromRGB(60, 60, 80) })
	end
	local npcPos = pos + Vector3.new(-22, 0, 16)
	npc("CappuccinoAssassino", npcPos, facing, "🏆 WHO'S THE FASTEST?", "Leaderboard", "View", "Spin")
end

local function buildCrateArea()
	local pos = at(L.Crates)
	local facing = at(Vector3.zero)
	sign(pos + Vector3.new(-20, 20, 0), facing, "📦 EQUIPMENT CRATES", Color3.fromRGB(80, 230, 255), 40, 8)

	-- One physical machine per crate type, lined up facing spawn.
	for i, crate in CrateData.Crates do
		local offset = (i - 2) * 22
		local machinePos = pos + Vector3.new(0, 0, offset)
		local cf = CFrame.lookAt(machinePos, Vector3.new(facing.X, machinePos.Y, facing.Z))
		part({ Name = "MachineBase", Size = Vector3.new(14, 2, 12), CFrame = cf * CFrame.new(0, 1, 0), Color = Color3.fromRGB(50, 45, 70) })
		local display = part({ Name = "CrateDisplay", Size = Vector3.new(12, 12, 10), CFrame = cf * CFrame.new(0, 8, 0), Color = crate.color, Material = Enum.Material.Glass, Transparency = 0.35 })
		-- The spinning crate inside the glass
		local box = part({ Name = "Crate_" .. crate.id, Size = Vector3.new(6, 6, 6), CFrame = cf * CFrame.new(0, 8, 0), Color = crate.color, Material = Enum.Material.Neon, CanCollide = false })
		tag(box, "LobbySpin", { Speed = 1 + i * 0.4 })
		local label = part({ Name = "PriceBoard", Size = Vector3.new(12, 5, 0.4), CFrame = cf * CFrame.new(0, 16.5, -4.8), Color = Color3.fromRGB(20, 15, 35) })
		local price = if crate.robuxLabel then crate.robuxLabel else ("🪙 " .. Util.FormatNumber(crate.coinPrice))
		Util.SurfaceLabel(label, Enum.NormalId.Front, ("📦 %s\n%s"):format(crate.name, price), { TextColor = crate.color, PixelsPerStud = 30 })
		prompt(display, "Open / Buy", crate.name, "Crates", crate.id)
	end
	npc("ChimpanziniBananini", pos + Vector3.new(18, 0, 34), facing, "📦 OPEN YOUR CRATES!", "Crates", "Talk", "Wiggle")
end

local function buildShop()
	local pos = at(L.Shop)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	-- A wonky candy-striped market stall
	part({ Name = "Counter", Size = Vector3.new(30, 5, 6), CFrame = cf * CFrame.new(0, 2.5, -4), Color = Color3.fromRGB(255, 255, 255) })
	for i = -3, 3 do
		part({
			Name = "Awning",
			Size = Vector3.new(4.3, 0.6, 14),
			CFrame = cf * CFrame.new(i * 4.3, 16, 0) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(255, 70, 110) else Color3.fromRGB(255, 255, 255),
		})
	end
	for _, side in { -1, 1 } do
		part({ Name = "StallPost", Size = Vector3.new(1.2, 16, 1.2), CFrame = cf * CFrame.new(side * 14.5, 8, -6), Color = Color3.fromRGB(255, 200, 40) })
	end
	sign(pos + Vector3.new(0, 26, 12), facing, "🛒 BRAINROT SHOP", COLORS.Neon[3], 30, 7)
	local counterTop = part({ Name = "ShopCounter", Size = Vector3.new(30, 0.4, 6), CFrame = cf * CFrame.new(0, 5.2, -4), Color = Color3.fromRGB(255, 200, 40) })
	prompt(counterTop, "Shop", "Brainrot Shop", "Shop")
	part({ Name = "NPCPlatform", Size = Vector3.new(10, 5, 8), CFrame = cf * CFrame.new(0, 2.5, 3), Color = Color3.fromRGB(255, 200, 40) })
	npc("BallerinaCappuccina", (cf * CFrame.new(0, 5, 3)).Position, facing, "🛒 BUY SOME BRAINROT!", "Shop", "Talk", "Twirl")
end

local function buildLoadoutStation()
	local pos = at(L.Loadout)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	part({ Name = "LoadoutPad", Size = Vector3.new(20, 1, 20), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(60, 60, 80), Material = Enum.Material.DiamondPlate })
	-- Three pedestals = three loadout slots
	for slot = 1, 3 do
		local pedestal = part({ Name = "SlotPedestal" .. slot, Size = Vector3.new(4, 4, 4), CFrame = cf * CFrame.new((slot - 2) * 6, 3, 2), Color = Color3.fromRGB(90, 90, 120), Material = Enum.Material.Metal })
		local holo = part({ Name = "SlotHolo" .. slot, Size = Vector3.new(3, 3, 3), CFrame = cf * CFrame.new((slot - 2) * 6, 7, 2), Color = COLORS.Neon[slot + 1], Material = Enum.Material.ForceField, CanCollide = false })
		tag(holo, "LobbySpin", { Speed = 1.5 })
		tag(holo, "LoadoutHolo", { Slot = slot })
		prompt(pedestal, "Change", ("Slot %d"):format(slot), "Loadout")
	end
	sign(pos + Vector3.new(0, 16, 0) - (cf.LookVector * 8), facing, "⚙️ EQUIPMENT", COLORS.Neon[2], 22, 6)
	npc("BrrBrrPatapim", pos + cf.RightVector * 12, facing, "⚙️ GEAR UP!", "Loadout", "Talk", "Stomp")
end

local function buildCollection()
	local pos = at(L.Collection)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	part({ Name = "GalleryFloor", Size = Vector3.new(44, 1, 20), CFrame = cf * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(40, 30, 60), Material = Enum.Material.Marble })
	-- A row of glass cases, one per Brainrot. The client shows a silhouette
	-- ("???") until the player has unlocked it.
	local count = #BrainrotData.List
	for i, brainrot in BrainrotData.List do
		local x = (i - (count + 1) / 2) * 4.2
		local caseCf = cf * CFrame.new(x, 3, 4)
		local case = part({ Name = "Case_" .. brainrot.id, Size = Vector3.new(3.6, 5, 3.6), CFrame = caseCf, Color = Color3.fromRGB(180, 220, 255), Material = Enum.Material.Glass, Transparency = 0.6, CanCollide = true })
		local model = ModelFactory.Brainrot(brainrot.id, 0.45)
		model:PivotTo(caseCf * CFrame.new(0, -2.4, 0))
		model.Parent = case
		tag(model, "CollectionDisplay", { BrainrotId = brainrot.id })
		local nameplate = part({ Name = "Nameplate", Size = Vector3.new(3.6, 1, 0.2), CFrame = caseCf * CFrame.new(0, -2.1, -1.9), Color = Color3.fromRGB(20, 15, 35) })
		local label = Util.SurfaceLabel(nameplate, Enum.NormalId.Front, "???", { TextColor = Color3.fromRGB(255, 255, 255), PixelsPerStud = 40 })
		label.Name = "CollectionLabel"
		tag(label, "CollectionLabel", { BrainrotId = brainrot.id })
	end
	sign(pos + Vector3.new(0, 16, 0) - cf.LookVector * 8, facing, "🧠 BRAINROT COLLECTION", COLORS.Neon[5], 34, 6)
	npc("LiriliLarila", pos + cf.RightVector * -26, facing, "🧠 CHECK YOUR BRAINROTS!", "Collection", "Talk", "Sway")
end

local function buildDailyReward()
	local pos = at(L.DailyReward)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	local gift = part({ Name = "GiftBox", Size = Vector3.new(10, 10, 10), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(255, 70, 110) })
	part({ Name = "Ribbon", Size = Vector3.new(10.2, 10.2, 2), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(255, 220, 90), CanCollide = false })
	part({ Name = "Ribbon", Size = Vector3.new(2, 10.2, 10.2), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(255, 220, 90), CanCollide = false })
	local bow = part({ Name = "Bow", Size = Vector3.new(4, 2, 4), CFrame = cf * CFrame.new(0, 11, 0), Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.Neon, CanCollide = false })
	tag(bow, "LobbySpin", { Speed = 2 })
	prompt(gift, "Claim", "Daily Reward", "Daily")
	sign(pos + Vector3.new(0, 18, 0) - cf.LookVector * 8, facing, "🎁 DAILY REWARD", COLORS.Neon[4], 22, 6)
end

local function buildStats()
	local pos = at(L.Stats)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	local kiosk = part({ Name = "StatsKiosk", Size = Vector3.new(8, 10, 3), CFrame = cf * CFrame.new(0, 5, 0), Color = Color3.fromRGB(60, 60, 80) })
	local screen = part({ Name = "KioskScreen", Size = Vector3.new(7, 6, 0.2), CFrame = cf * CFrame.new(0, 6.5, -1.6), Color = Color3.fromRGB(20, 15, 35) })
	Util.SurfaceLabel(screen, Enum.NormalId.Front, "📊\nMY STATS", { TextColor = COLORS.Neon[2], PixelsPerStud = 30 })
	prompt(kiosk, "Check", "My Stats", "Stats")
	npc("TrippiTroppi", pos + cf.RightVector * -10, facing, "📊 HOW ARE YOU DOING?", "Stats", "Talk", "Hop")
end

-- The most important part of the lobby: a giant gate with a road
-- disappearing into the distance behind it.
local function buildRunEntrance()
	local pos = at(L.RunEntrance)
	local facing = at(Vector3.zero)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z)) -- front faces spawn

	-- Gate pillars shaped like giant logs (Sahur's cousins).
	for _, side in { -1, 1 } do
		Util.UprightCylinder({ Parent = lobby, CFrame = cf * CFrame.new(side * 18, 17, 0), Height = 34, Diameter = 8, Color = Color3.fromRGB(176, 124, 74), Material = Enum.Material.Wood })
	end
	local arch = part({ Name = "GateArch", Size = Vector3.new(46, 8, 8), CFrame = cf * CFrame.new(0, 36, 0), Color = Color3.fromRGB(255, 70, 160), Material = Enum.Material.Neon })
	local archFace = part({ Name = "GateArchFace", Size = Vector3.new(44, 7, 0.2), CFrame = cf * CFrame.new(0, 36, -4.2), Color = Color3.fromRGB(25, 20, 40) })
	Util.SurfaceLabel(archFace, Enum.NormalId.Front, "🏃 ENTER RUN", { TextColor = Color3.fromRGB(255, 255, 255), PixelsPerStud = 30 })
	tag(arch, "LobbyPulse")

	-- Tunnel walls forming a short walkway into the portal.
	for _, side in { -1, 1 } do
		part({ Name = "TunnelWall", Size = Vector3.new(2, 30, 40), CFrame = cf * CFrame.new(side * 15, 15, 22), Color = Color3.fromRGB(40, 35, 60), Material = Enum.Material.Concrete })
		for i = 0, 4 do
			local light = part({ Name = "TunnelLight", Size = Vector3.new(0.4, 2, 2), CFrame = cf * CFrame.new(side * 13.9, 12, 6 + i * 8), Color = COLORS.Neon[(i % #COLORS.Neon) + 1], Material = Enum.Material.Neon, CanCollide = false })
			tag(light, "LobbyPulse")
		end
	end
	part({ Name = "TunnelRoof", Size = Vector3.new(32, 2, 40), CFrame = cf * CFrame.new(0, 31, 22), Color = Color3.fromRGB(40, 35, 60) })

	-- The swirling portal. Touching this starts a run.
	local portal = part({
		Name = "RunPortal",
		Size = Vector3.new(26, 26, 2),
		CFrame = cf * CFrame.new(0, 14, 40),
		Color = Color3.fromRGB(120, 60, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
	})
	tag(portal, "LobbySpinZ", { Speed = 1.2 })
	local trigger = part({ Name = "RunEntranceTrigger", Size = Vector3.new(28, 20, 8), CFrame = cf * CFrame.new(0, 10, 36), Transparency = 1, CanCollide = false, CanTouch = true })
	tag(trigger, "RunEntranceTrigger")

	-- Road into the distance behind the gate (visual only, fades out).
	for i = 0, 14 do
		local seg = part({
			Name = "DistantRoad",
			Size = Vector3.new(24, 1, 40),
			CFrame = cf * CFrame.new(0, -0.4, 60 + i * 40),
			Color = Color3.fromRGB(60, 60, 70),
			Transparency = math.min(0.95, i * 0.065),
			CanCollide = false,
		})
		for _, lane in { -4, 4 } do
			part({ Name = "LaneLine", Size = Vector3.new(0.5, 0.1, 10), CFrame = seg.CFrame * CFrame.new(lane, 0.55, 0), Color = Color3.fromRGB(255, 255, 255), Transparency = seg.Transparency, CanCollide = false, CanQuery = false })
		end
	end
	-- Block players from walking past the portal into the fake road.
	part({ Name = "PortalBackstop", Size = Vector3.new(34, 40, 2), CFrame = cf * CFrame.new(0, 20, 44), Transparency = 1 })

	sign(pos + Vector3.new(0, 8, 0) - cf.LookVector * 22 + cf.RightVector * 20, facing, "WALK IN TO RUN ➜", COLORS.Neon[3], 18, 4)
end

-- Absurd set dressing: giant statues, floating junk, weird buildings,
-- billboards, wandering Brainrots and a hidden secret.
local function buildDecor()
	-- Floating oversized props
	local floaters = {
		{ size = Vector3.new(8, 8, 8), color = Color3.fromRGB(250, 220, 60), shape = Enum.PartType.Ball },
		{ size = Vector3.new(4, 14, 4), color = Color3.fromRGB(176, 124, 74), shape = Enum.PartType.Cylinder },
		{ size = Vector3.new(10, 3, 10), color = Color3.fromRGB(255, 120, 200), shape = Enum.PartType.Block },
	}
	for i = 1, 14 do
		local def = floaters[(i % #floaters) + 1]
		local angle = i / 14 * math.pi * 2
		local radius = rng:NextNumber(55, 140)
		local p = part({
			Name = "Floater",
			Size = def.size,
			Shape = def.shape,
			CFrame = CFrame.new(at(Vector3.new(math.cos(angle) * radius, rng:NextNumber(25, 55), math.sin(angle) * radius))),
			Color = def.color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		tag(p, "LobbyFloat", { Phase = rng:NextNumber(0, 6), Amplitude = rng:NextNumber(2, 5) })
		tag(p, "LobbySpin", { Speed = rng:NextNumber(0.2, 0.8) })
	end

	-- Weird leaning buildings around the edge
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2 + 0.3
		local radius = L.Size / 2 - 12
		local height = rng:NextNumber(30, 70)
		local basePos = at(Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		-- keep the run entrance clear
		if (basePos - at(L.RunEntrance)).Magnitude > 45 then
			part({
				Name = "WonkyBuilding",
				Size = Vector3.new(18, height, 18),
				CFrame = CFrame.new(basePos) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-8, 8))),
				Color = COLORS.Neon[(i % #COLORS.Neon) + 1],
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end

	-- Animated billboards
	local billboardText = { "TRALALERO TRALALA", "SAHUR IS COMING", "BOMBARDIRO CROCODILO", "RUN. JUST RUN.", "BRR BRR PATAPIM" }
	-- Angles (degrees) chosen to sit between the stations.
	local billboardAngles = { -115, -65, -20, 20, 160 }
	for i, text in billboardText do
		local angle = math.rad(billboardAngles[i])
		local pos = at(Vector3.new(math.cos(angle) * 125, 40, math.sin(angle) * 125))
		local board = sign(pos, at(Vector3.zero), text, COLORS.Neon[i], 34, 10)
		tag(board, "LobbyPulse")
	end

	-- Random Brainrots wandering the plaza
	for i, brainrot in BrainrotData.List do
		if i > 1 then
			local model = ModelFactory.Brainrot(brainrot.id, 1.2)
			model.Name = "Wanderer_" .. brainrot.id
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(30, 70)
			model:PivotTo(CFrame.new(at(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))))
			model.Parent = lobby
			tag(model, "LobbyWander", { Radius = rng:NextNumber(12, 25), Speed = rng:NextNumber(4, 9), Seed = i })
		end
	end

	-- Secret area: a golden brain hidden on top of a floating platform,
	-- reachable by a hidden stair of faint steps behind the Sahur statue.
	local stepStart = at(Vector3.new(30, 0, -60))
	for i = 1, 12 do
		part({
			Name = "SecretStep",
			Size = Vector3.new(6, 1, 6),
			CFrame = CFrame.new(stepStart + Vector3.new(i * 3, i * 3.2, -i * 2)),
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.85,
		})
	end
	local platformPos = stepStart + Vector3.new(42, 40, -28)
	part({ Name = "SecretPlatform", Size = Vector3.new(14, 1, 14), CFrame = CFrame.new(platformPos), Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.Neon })
	local brain = part({
		Name = "GoldenBrain",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(platformPos + Vector3.new(0, 3, 0)),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanTouch = true,
	})
	tag(brain, "SecretCollectible", { SecretId = "GoldenBrain", Reward = 1000 })
	tag(brain, "LobbyFloat", { Phase = 0, Amplitude = 1 })
end

function LobbyBuilder.Build(): Folder
	lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	buildGround()
	buildSpawn()
	buildLeaderboard()
	buildCrateArea()
	buildShop()
	buildLoadoutStation()
	buildCollection()
	buildDailyReward()
	buildStats()
	buildRunEntrance()
	buildDecor()

	return lobby
end

function LobbyBuilder.SpawnCFrame(): CFrame
	return CFrame.new(at(L.SpawnOffset)) * CFrame.Angles(0, math.rad(180), 0)
end

return LobbyBuilder
