--!strict
-- Owns the lifecycle of every run:
--
--   LOBBY → RUN GATE (walk in) → "RUN STARTING..." → STARTING AREA
--   → Tung Tung Tung Sahur intro → 3, 2, 1, RUN! → ENDLESS RUN
--   → caught → REVIVE or END → REWARDS SCREEN → LOBBY
--
-- Each run gets its own strip of world far from the lobby. The server is
-- authoritative over the track, destruction, coins, pickups, equipment
-- charges and rewards; the client owns the moment-to-moment movement.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local EquipmentData = require(Shared.EquipmentData)
local ImpactRules = require(Shared.ImpactRules)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.Parent.PlayerData)
local Leaderboards = require(script.Parent.Parent.Leaderboards)
local Destruction = require(script.Parent.Destruction)
local TrackGenerator = require(script.Parent.TrackGenerator)

local RunManager = {}

type Phase = "Starting" | "Intro" | "Running" | "Caught" | "Results"

type LoadoutEntry = {
	slot: number,
	itemId: string,
	level: number,
	charges: number,
}

type Run = {
	player: Player,
	slot: number,
	origin: Vector3,
	folder: Folder,
	track: TrackGenerator.Track,
	phase: Phase,
	goClock: number,
	d: number, -- server-tracked distance (studs)
	coins: number,
	loadout: { LoadoutEntry },
	shieldUntil: number,
	boostUntil: number,
	boostMultiplier: number,
	magnetUntil: number,
	magnetRadius: number,
	doublerUntil: number,
	revives: number,
	crates: { [string]: number },
	discovered: { string },
	caughtClock: number,
	survival: number,
	ended: boolean,
	connections: { RBXScriptConnection },
}

local runs: { [Player]: Run } = {}
local slotsInUse: { [number]: boolean } = {}
local runsFolder: Folder

local START_D = 6

local function notify(player: Player, text: string, color: Color3?)
	Remotes.Event("Notify"):FireClient(player, text, color)
end

local function allocateSlot(): number
	local slot = 0
	while slotsInUse[slot] do
		slot += 1
	end
	slotsInUse[slot] = true
	return slot
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function trackDistanceOf(run: Run, position: Vector3): number
	return run.origin.Z - position.Z
end

function RunManager.IsRunning(player: Player): boolean
	return runs[player] ~= nil
end

-- ───────────────────────────── start ─────────────────────────────

local function buildLoadout(player: Player): { LoadoutEntry }
	local profile = PlayerData.Get(player)
	local loadout = {}
	if not profile then
		return loadout
	end
	for slot = 1, PlayerData.UnlockedSlots(player) do
		local itemId = profile.Loadout[slot]
		local item = EquipmentData.Get(itemId)
		if item and (profile.Inventory[item.id] or 0) > 0 then
			local level = EquipmentData.LevelFromCount(profile.Inventory[item.id])
			table.insert(loadout, { slot = slot, itemId = item.id, level = level, charges = EquipmentData.ChargesAt(item, level) })
		end
	end
	return loadout
end

local function loadoutForClient(run: Run)
	local out = {}
	for _, entry in run.loadout do
		local item = EquipmentData.Get(entry.itemId) :: EquipmentData.Item
		local scale = EquipmentData.ScaleAt(entry.level)
		table.insert(out, {
			slot = entry.slot,
			itemId = item.id,
			name = item.name,
			icon = item.icon,
			ability = item.ability,
			rarity = item.rarity,
			level = entry.level,
			charges = entry.charges,
			duration = if item.duration then item.duration * scale else nil,
			radius = if item.radius then item.radius * scale else nil,
			speedMultiplier = item.speedMultiplier,
		})
	end
	return out
end

function RunManager.StartRun(player: Player)
	if runs[player] then
		return
	end
	local profile = PlayerData.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local slot = allocateSlot()
	local origin = Vector3.new(Config.Run.WorldOriginX + slot * Config.Run.SlotSpacing, Config.Run.WorldY, 0)
	local folder = Instance.new("Folder")
	folder.Name = "Run_" .. player.UserId
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder.Parent = runsFolder

	local run: Run = {
		player = player,
		slot = slot,
		origin = origin,
		folder = folder,
		track = nil :: any,
		phase = "Starting",
		goClock = math.huge,
		d = START_D,
		coins = 0,
		loadout = buildLoadout(player),
		shieldUntil = 0,
		boostUntil = 0,
		boostMultiplier = 1,
		magnetUntil = 0,
		magnetRadius = 0,
		doublerUntil = 0,
		revives = 0,
		crates = {},
		discovered = {},
		caughtClock = 0,
		survival = 0,
		ended = false,
		connections = {},
	}
	runs[player] = run

	-- 1) "RUN STARTING..." fade on the client while the world is built.
	Remotes.Event("RunStarting"):FireClient(player)
	run.track = TrackGenerator.new(folder, origin, math.random(1, 2 ^ 30))

	table.insert(run.connections, humanoid.Died:Connect(function()
		RunManager.EndRun(player, "Died")
	end))

	task.delay(Config.Run.RunStartingFade, function()
		if runs[player] ~= run or not player.Parent then
			return
		end
		local startCf = CFrame.new(origin + Vector3.new(0, 3, -START_D))
		pcall(function()
			player:RequestStreamAroundAsync(startCf.Position, 5)
		end)
		local currentCharacter = player.Character
		if not currentCharacter then
			RunManager.EndRun(player, "NoCharacter")
			return
		end
		-- The client switches its own character to the "RunPlayer" collision
		-- group when its run controller takes over (it simulates the character).
		currentCharacter:PivotTo(startCf)

		-- The first run introduces Tung Tung Tung Sahur to the collection.
		if not profile.Collection[BrainrotData.ChaserId] then
			profile.Collection[BrainrotData.ChaserId] = true
			table.insert(run.discovered, BrainrotData.ChaserId)
			PlayerData.Changed(player)
		end

		run.phase = "Intro"
		local leadIn = Config.Run.IntroDuration + Config.Run.CountdownStep * 3 + 0.25
		run.goClock = os.clock() + leadIn
		Remotes.Event("RunPrepare"):FireClient(player, {
			origin = origin,
			startD = START_D,
			loadout = loadoutForClient(run),
			bankCoins = profile.Coins,
			bestDistance = profile.Stats.BestDistance,
			goServerTime = workspace:GetServerTimeNow() + leadIn,
			trackFolder = run.track.folder,
		})
		task.delay(leadIn, function()
			if runs[player] == run and run.phase == "Intro" then
				run.phase = "Running"
			end
		end)
	end)
end

-- ───────────────────────────── per-frame ─────────────────────────────

local function updateRun(run: Run, dt: number)
	if run.phase ~= "Running" then
		return
	end
	local root = rootOf(run.player)
	if not root then
		return
	end
	run.survival += dt
	-- Cap progress by the fastest legal speed so teleporting ahead is useless.
	local reported = trackDistanceOf(run, root.Position)
	local maxSpeed = ImpactRules.SpeedAt(run.d * Config.Run.MetersPerStud) * math.max(1.6, run.boostMultiplier) * Config.Run.MaxSpeedTolerance
	local allowed = run.d + maxSpeed * dt + 2
	run.d = math.clamp(reported, run.d - 20, allowed)
	run.track:Update(run.d)
end

-- ───────────────────────────── client reports ─────────────────────────────

local function validObject(run: Run, object: any): boolean
	return typeof(object) == "Instance" and run.track:Owns(object) and object.Parent ~= nil
end

local function nearRunner(run: Run, position: Vector3, tolerance: number): boolean
	local root = rootOf(run.player)
	if not root then
		return false
	end
	return (root.Position - position).Magnitude <= tolerance
end

local function objectPosition(object: Instance): Vector3?
	if object:IsA("BasePart") then
		return object.Position
	elseif object:IsA("Model") then
		local ok, cf = pcall(function()
			return object:GetBoundingBox()
		end)
		if ok then
			return cf.Position
		end
	end
	return nil
end

local function onReportHit(player: Player, object: any, info: any)
	local run = runs[player]
	if not run or run.phase ~= "Running" or not validObject(run, object) or type(info) ~= "table" then
		return
	end
	local obstacle = object :: Instance
	if obstacle:GetAttribute("Destroyed") or not obstacle:GetAttribute("ObstacleType") then
		return
	end
	local position = objectPosition(obstacle)
	if not position then
		return
	end
	-- Long objects (train cars) have far-away centres; allow generous slack.
	if not nearRunner(run, position, 40) then
		return
	end

	local now = os.clock()
	local tier = obstacle:GetAttribute("Tier") or 4
	local collisionDamage = obstacle:GetAttribute("CollisionDamage") or 0
	local expected = ImpactRules.SpeedAt(run.d * Config.Run.MetersPerStud)
	local speed = math.clamp(tonumber(info.speed) or 0, 0, expected * 1.1)
	local boost = now < run.boostUntil + 0.25
	local shield = now < run.shieldUntil + 0.25

	if info.side then
		-- Clipped something while changing lanes; nothing breaks.
		return
	end

	local result = ImpactRules.Resolve(tier, collisionDamage, speed, boost, shield)
	if result.outcome == "Absorbed" then
		run.shieldUntil = 0
		Remotes.Event("RunWorld"):FireClient(player, { type = "ShieldUsed" })
	end
	local impact = if typeof(info.point) == "Vector3" then info.point else position
	Destruction.ApplyDamage(obstacle, result.damage, impact, player, speed)
end

local function onCollectCoin(player: Player, coin: any)
	local run = runs[player]
	if not run or (run.phase ~= "Running" and run.phase ~= "Intro") or not validObject(run, coin) then
		return
	end
	local part = coin :: Instance
	if not part:IsA("BasePart") or not part:GetAttribute("Coin") then
		return
	end
	local now = os.clock()
	local tolerance = Config.Run.PickupTolerance + (if now < run.magnetUntil + 0.5 then run.magnetRadius else 0)
	if not nearRunner(run, part.Position, tolerance) then
		return
	end
	part:Destroy()
	local value = Config.Economy.CoinValue * (if now < run.doublerUntil then 2 else 1)
	run.coins += value
end

local function onPickupItem(player: Player, pickupPart: any)
	local run = runs[player]
	if not run or run.phase ~= "Running" or not validObject(run, pickupPart) then
		return
	end
	local part = pickupPart :: Instance
	local kind = part:GetAttribute("Pickup")
	if not part:IsA("BasePart") or not kind or not nearRunner(run, part.Position, Config.Run.PickupTolerance) then
		return
	end
	part:Destroy()

	if kind == "Crate" then
		local crateId = part:GetAttribute("CrateId") or "Common"
		run.crates[crateId] = (run.crates[crateId] or 0) + 1
		Remotes.Event("RunWorld"):FireClient(player, { type = "CrateFound", crateId = crateId })
	elseif #run.loadout > 0 then
		local entry = run.loadout[math.random(1, #run.loadout)]
		entry.charges += 1
		Remotes.Event("RunWorld"):FireClient(player, { type = "Charges", slot = entry.slot, charges = entry.charges, gained = true })
	else
		run.coins += 25
		Remotes.Event("RunWorld"):FireClient(player, { type = "BonusCoins", amount = 25 })
	end
end

local function onUseEquipment(player: Player, slot: any)
	local run = runs[player]
	if not run or run.phase ~= "Running" or type(slot) ~= "number" then
		return
	end
	local entry: LoadoutEntry? = nil
	for _, e in run.loadout do
		if e.slot == slot then
			entry = e
		end
	end
	if not entry or entry.charges <= 0 then
		return
	end
	local item = EquipmentData.Get(entry.itemId) :: EquipmentData.Item
	local scale = EquipmentData.ScaleAt(entry.level)
	local duration = (item.duration or 0) * scale
	local now = os.clock()
	entry.charges -= 1

	local event: { [string]: any } = { type = "EquipmentUsed", slot = entry.slot, ability = item.ability, charges = entry.charges, duration = duration }
	if item.ability == "Shield" then
		run.shieldUntil = now + duration
	elseif item.ability == "Magnet" then
		run.magnetUntil = now + duration
		run.magnetRadius = (item.radius or 20) * scale
		event.radius = run.magnetRadius
	elseif item.ability == "SpeedBoost" then
		run.boostUntil = now + duration
		run.boostMultiplier = item.speedMultiplier or 1.3
		event.multiplier = run.boostMultiplier
	elseif item.ability == "CoinDoubler" then
		run.doublerUntil = now + duration
	elseif item.ability == "Bomb" then
		local root = rootOf(player)
		local radius = (item.radius or 25) * scale
		local basePosition = if root then root.Position else run.origin + Vector3.new(0, 3, -run.d)
		local center = basePosition + Vector3.new(0, 0, -radius * 0.6)
		local destroyed = Destruction.Explode(run.track.folder, center, radius, item.maxTier or 2, player)
		event.center = center
		event.radius = radius
		event.destroyed = destroyed
	end
	Remotes.Event("RunWorld"):FireClient(player, event)
end

local function onEncounter(player: Player, brainrotId: any)
	local run = runs[player]
	if not run or type(brainrotId) ~= "string" or not BrainrotData.Get(brainrotId) then
		return
	end
	local found = false
	for _, d in run.track.folder:GetDescendants() do
		if d:GetAttribute("Encounter") == brainrotId and math.abs((d:GetAttribute("EncounterD") or 0) - run.d) < 120 then
			found = true
			break
		end
	end
	local profile = PlayerData.Get(player)
	if not found or not profile or profile.Collection[brainrotId] then
		return
	end
	profile.Collection[brainrotId] = true
	table.insert(run.discovered, brainrotId)
	PlayerData.Changed(player)
	local data = BrainrotData.Get(brainrotId) :: BrainrotData.Brainrot
	notify(player, ("🧠 NEW BRAINROT: %s %s!"):format(data.icon, data.name), Color3.fromRGB(255, 120, 220))
end

-- ───────────────────────────── caught / revive / end ─────────────────────────────

local function reviveCost(run: Run): number
	return Config.Economy.ReviveBaseCost * 2 ^ run.revives
end

local function onReportCaught(player: Player)
	local run = runs[player]
	if not run or run.phase ~= "Running" then
		return
	end
	run.phase = "Caught"
	run.caughtClock = os.clock()
	local profile = PlayerData.Get(player)
	local canRevive = run.revives < Config.Economy.MaxRevivesPerRun
	Remotes.Event("RunCaught"):FireClient(player, {
		canRevive = canRevive,
		cost = reviveCost(run),
		bankCoins = if profile then profile.Coins else 0,
		robux = Config.DeveloperProducts.Revive ~= 0,
		timeout = 10,
	})
	local caughtAt = run.caughtClock
	task.delay(10.5, function()
		if runs[player] == run and run.phase == "Caught" and run.caughtClock == caughtAt then
			RunManager.EndRun(player, "Caught")
		end
	end)
end

function RunManager.Revive(player: Player, paidWithRobux: boolean?): boolean
	local run = runs[player]
	if not run or run.phase ~= "Caught" then
		return false
	end
	if not paidWithRobux then
		local profile = PlayerData.Get(player)
		local cost = reviveCost(run)
		if not profile or profile.Coins < cost or run.revives >= Config.Economy.MaxRevivesPerRun then
			return false
		end
		profile.Coins -= cost
		PlayerData.Changed(player)
	end
	run.revives += 1
	run.phase = "Running"
	Remotes.Event("RunRevived"):FireClient(player)
	return true
end

local function onChooseRevive(player: Player, choice: any)
	local run = runs[player]
	if not run or run.phase ~= "Caught" then
		return
	end
	if choice == "Coins" then
		if not RunManager.Revive(player, false) then
			notify(player, "Not enough coins to revive!", Color3.fromRGB(255, 90, 90))
		end
	elseif choice == "Robux" and Config.DeveloperProducts.Revive ~= 0 then
		game:GetService("MarketplaceService"):PromptProductPurchase(player, Config.DeveloperProducts.Revive)
	else
		RunManager.EndRun(player, "Caught")
	end
end

local function cleanup(run: Run)
	for _, connection in run.connections do
		connection:Disconnect()
	end
	run.folder:Destroy()
	slotsInUse[run.slot] = nil
end

function RunManager.ReturnToLobby(player: Player)
	local run = runs[player]
	if run then
		runs[player] = nil
		cleanup(run)
	end
	if player.Parent then
		player:LoadCharacter()
		Remotes.Event("ReturnedToLobby"):FireClient(player)
	end
end

function RunManager.EndRun(player: Player, reason: string)
	local run = runs[player]
	if not run or run.ended then
		return
	end
	run.ended = true
	run.phase = "Results"

	local profile = PlayerData.Get(player)
	local meters = math.floor(math.max(0, run.d - START_D) * Config.Run.MetersPerStud)
	local distanceBonus = math.floor(meters * Config.Economy.DistanceCoinBonus)
	local total = run.coins + distanceBonus
	local newBest = false

	if profile then
		local stats = profile.Stats
		stats.TotalRuns += 1
		stats.TotalDistance += meters
		stats.TotalCoins += total
		if meters > stats.BestDistance then
			stats.BestDistance = meters
			newBest = true
		end
		stats.LongestSurvival = math.max(stats.LongestSurvival, math.floor(run.survival))
		profile.Coins += total
		for crateId, count in run.crates do
			profile.Crates[crateId] = (profile.Crates[crateId] or 0) + count
		end
		PlayerData.Changed(player)
		task.spawn(Leaderboards.Submit, player)
	end

	if not player.Parent or reason == "Left" then
		runs[player] = nil
		cleanup(run)
		return
	end

	local discovered = {}
	for _, id in run.discovered do
		local data = BrainrotData.Get(id)
		if data then
			table.insert(discovered, { id = id, name = data.name, icon = data.icon })
		end
	end

	Remotes.Event("RunEnded"):FireClient(player, {
		reason = reason,
		distance = meters,
		coins = run.coins,
		distanceBonus = distanceBonus,
		totalCoins = total,
		newBest = newBest,
		best = if profile then profile.Stats.BestDistance else meters,
		survival = math.floor(run.survival),
		revives = run.revives,
		crates = run.crates,
		discovered = discovered,
	})

	-- Back to the lobby when the player closes the results (or after 30s).
	task.delay(30, function()
		if runs[player] == run then
			RunManager.ReturnToLobby(player)
		end
	end)
end

-- ───────────────────────────── init ─────────────────────────────

function RunManager.Init()
	TrackGenerator.RegisterCollisionGroups()

	runsFolder = Instance.new("Folder")
	runsFolder.Name = "Runs"
	runsFolder.Parent = workspace

	Remotes.Event("ReportHit").OnServerEvent:Connect(onReportHit)
	Remotes.Event("CollectCoin").OnServerEvent:Connect(onCollectCoin)
	Remotes.Event("PickupItem").OnServerEvent:Connect(onPickupItem)
	Remotes.Event("UseEquipment").OnServerEvent:Connect(onUseEquipment)
	Remotes.Event("EncounterBrainrot").OnServerEvent:Connect(onEncounter)
	Remotes.Event("ReportCaught").OnServerEvent:Connect(onReportCaught)
	Remotes.Event("ChooseRevive").OnServerEvent:Connect(onChooseRevive)
	Remotes.Event("LeaveResults").OnServerEvent:Connect(function(player)
		local run = runs[player]
		if run and run.phase == "Results" then
			RunManager.ReturnToLobby(player)
		end
	end)

	-- Physical run entrance: walk into the portal to start.
	local debounce: { [Player]: number } = {}
	local function hookTrigger(trigger: Instance)
		if not trigger:IsA("BasePart") then
			return
		end
		trigger.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or runs[player] then
				return
			end
			local now = os.clock()
			if (debounce[player] or 0) > now then
				return
			end
			debounce[player] = now + 3
			RunManager.StartRun(player)
		end)
	end
	for _, trigger in CollectionService:GetTagged("RunEntranceTrigger") do
		hookTrigger(trigger)
	end
	CollectionService:GetInstanceAddedSignal("RunEntranceTrigger"):Connect(hookTrigger)

	RunService.Heartbeat:Connect(function(dt)
		for _, run in runs do
			updateRun(run, dt)
		end
	end)

	-- Runs in progress are settled before the player's final save.
	PlayerData.BeforeRemove(function(player)
		debounce[player] = nil
		if runs[player] then
			RunManager.EndRun(player, "Left")
			local run = runs[player]
			if run then
				runs[player] = nil
				cleanup(run)
			end
		end
	end)
end

return RunManager
