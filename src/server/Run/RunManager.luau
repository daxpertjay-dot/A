--!strict
-- Owns the lifecycle of every run:
--
--   BASE → RUN PORTAL (walk in) → "RUN STARTING..." → villain intro
--   → 3, 2, 1, RUN! → escape: coins, power-ups, rescue caged Brainrots
--   → caught → REVIVE or END → RESULTS (score, coins, rescues, Brainrot XP) → BASE
--
-- Score multiplier = base (Brainrots) × ✖️2 booster × style combo × Hype.
--
-- Each run gets its own strip of world far from the lobby. The server is
-- authoritative over the track, destruction, coins, power-ups, hoverboards,
-- the score and rewards; the client owns moment-to-moment movement.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local Config = require(Shared.Config)
local ImpactRules = require(Shared.ImpactRules)
local MutationData = require(Shared.MutationData)
local PowerUpData = require(Shared.PowerUpData)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local PlayerData = require(script.Parent.Parent.PlayerData)
local Leaderboards = require(script.Parent.Parent.Leaderboards)
local Destruction = require(script.Parent.Destruction)
local TrackGenerator = require(script.Parent.TrackGenerator)

local RunManager = {}

type Phase = "Starting" | "Intro" | "Running" | "Caught" | "Results"

type Run = {
	player: Player,
	slot: number,
	origin: Vector3,
	folder: Folder,
	track: TrackGenerator.Track,
	phase: Phase,
	d: number, -- server-tracked distance (studs)
	score: number,
	baseMultiplier: number, -- from Brainrots on the base, fixed for the run
	combo: Progression.Combo,
	bestCombo: number,
	coinStreak: number, -- coins towards the next combo stack
	lastStyle: number, -- os.clock() of the last client-reported trick
	hype: number, -- Hype charge left (spent as you run)
	hypeStart: number,
	coins: number,
	-- Power-up timers (os.clock())
	magnetUntil: number,
	jetpackUntil: number,
	sneakersUntil: number,
	boosterUntil: number,
	hoverUntil: number,
	hoverboardsUsed: number,
	revives: number,
	rescued: { string }, -- keys: "Id" or "Id:Mutation"
	boxRewards: { { kind: string, amount: number } },
	caughtClock: number,
	survival: number,
	ended: boolean,
	connections: { RBXScriptConnection },
}

local runs: { [Player]: Run } = {}
local slotsInUse: { [number]: boolean } = {}
local runsFolder: Folder
local rng = Random.new()

local START_D = 6

local function notify(player: Player, text: string, color: Color3?)
	Remotes.Event("Notify"):FireClient(player, text, color)
end

local function world(player: Player, event: { [string]: any })
	Remotes.Event("RunWorld"):FireClient(player, event)
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

function RunManager.IsRunning(player: Player): boolean
	return runs[player] ~= nil
end

-- Current score multiplier: Brainrots on your base × booster × combo × Hype.
local function currentMultiplier(run: Run): number
	local booster = if os.clock() < run.boosterUntil then 2 else 1
	return run.baseMultiplier * booster * Progression.ComboMultiplier(run.combo) * Progression.HypeMultiplier(run.hype)
end

-- Adds a trick to the combo and tells the client (it mirrors the server's combo).
local function comboAdd(run: Run, kind: string)
	local gained = Progression.ComboAdd(run.combo, kind, os.clock())
	run.bestCombo = math.max(run.bestCombo, Progression.ComboMultiplier(run.combo))
	world(run.player, { type = "Combo", kind = kind, gained = gained, stacks = run.combo.stacks })
end

local function comboSet(run: Run, kind: string, stacks: number)
	run.combo.stacks = stacks
	world(run.player, { type = "Combo", kind = kind, gained = 0, stacks = stacks })
end

-- ───────────────────────────── start ─────────────────────────────

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
		d = START_D,
		score = 0,
		baseMultiplier = PlayerData.Multiplier(profile),
		combo = Progression.NewCombo(),
		bestCombo = 1,
		coinStreak = 0,
		lastStyle = 0,
		hype = 0,
		hypeStart = 0,
		coins = 0,
		magnetUntil = 0,
		jetpackUntil = 0,
		sneakersUntil = 0,
		boosterUntil = 0,
		hoverUntil = 0,
		hoverboardsUsed = 0,
		revives = 0,
		rescued = {},
		boxRewards = {},
		caughtClock = 0,
		survival = 0,
		ended = false,
		connections = {},
	}
	runs[player] = run
	player:SetAttribute("InRun", true)
	-- Hype charged up until now; it's spent during this run.
	PlayerData.ChargeHype(profile, true)
	run.hype = profile.Hype
	run.hypeStart = profile.Hype

	-- 1) "RUN STARTING..." fade on the client while the world is built.
	Remotes.Event("RunStarting"):FireClient(player)
	run.track = TrackGenerator.new(folder, origin, rng:NextInteger(1, 2 ^ 30))

	table.insert(run.connections, humanoid.Died:Connect(function()
		RunManager.EndRun(player, "Died")
	end))

	task.delay(Config.Run.RunStartingFade, function()
		-- The run may already be over (e.g. the character died during the fade).
		if runs[player] ~= run or run.ended or not player.Parent then
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

		run.phase = "Intro"
		local leadIn = Config.Run.IntroDuration + Config.Run.CountdownStep * 3 + 0.25
		Remotes.Event("RunPrepare"):FireClient(player, {
			origin = origin,
			startD = START_D,
			trackFolder = run.track.folder,
			multiplier = run.baseMultiplier,
			hype = run.hype,
			hoverboards = profile.Hoverboards,
			highScore = profile.Stats.HighScore,
			bankCoins = profile.Coins,
			goServerTime = workspace:GetServerTimeNow() + leadIn,
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
	Progression.ComboDecay(run.combo, os.clock(), dt)
	-- Cap progress by the fastest legal speed so teleporting ahead is useless.
	local reported = run.origin.Z - root.Position.Z
	local maxSpeed = ImpactRules.SpeedAt(run.d * Config.Run.MetersPerStud) * 1.6 * Config.Run.MaxSpeedTolerance
	local allowed = run.d + maxSpeed * dt + 2
	local newD = math.clamp(reported, run.d - 20, allowed)
	-- Score: every meter forward is worth PointsPerMeter × multiplier; Hype is
	-- spent as you go.
	if newD > run.d then
		local meters = (newD - run.d) * Config.Run.MetersPerStud
		run.score += meters * Config.Score.PointsPerMeter * currentMultiplier(run)
		run.hype = math.max(0, run.hype - meters * Progression.HypeDrainPerMeter())
	end
	run.d = newD
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
	-- Long objects (buses, vault walls) have far-away centres; allow generous slack.
	if not position or not nearRunner(run, position, 40) then
		return
	end
	if info.side then
		-- Clipped something while changing lanes: the combo is halved.
		comboSet(run, "Side", run.combo.stacks / 2)
		return
	end

	local now = os.clock()
	local tier = obstacle:GetAttribute("Tier") or 4
	local collisionDamage = obstacle:GetAttribute("CollisionDamage") or 0
	local expected = ImpactRules.SpeedAt(run.d * Config.Run.MetersPerStud)
	local speed = math.clamp(tonumber(info.speed) or 0, 0, expected * 1.1)
	local onBoard = now < run.hoverUntil + 0.25

	-- A hoverboard takes the hit and breaks (the obstacle gets smashed).
	local result = ImpactRules.Resolve(tier, collisionDamage, speed, false, onBoard)
	if result.outcome == "Absorbed" then
		run.hoverUntil = 0
		world(player, { type = "HoverboardBroken" })
	elseif result.outcome == "Smash" or result.outcome == "CrashThrough" then
		comboAdd(run, result.outcome)
	elseif result.outcome == "Bump" then
		comboSet(run, "Crash", 0)
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
	local magnet = if now < run.magnetUntil + 0.5 then Config.PowerUps.MagnetRadius else 0
	if not nearRunner(run, part.Position, Config.Run.PickupTolerance + magnet) then
		return
	end
	local value = part:GetAttribute("Value") or Config.Economy.CoinValue
	part:Destroy()
	run.coins += value
	run.coinStreak += value
	if run.coinStreak >= Config.Combo.CoinsPerStack and run.phase == "Running" then
		run.coinStreak -= Config.Combo.CoinsPerStack
		comboAdd(run, "Coins")
	end
end

-- Tricks the client spots (clearing obstacles, near misses, landing on a
-- roof). Each object can only count once and has to be where the runner is.
local CLIENT_TRICKS = { Clear = true, NearMiss = true, Roof = true }
local function onReportStyle(player: Player, kind: any, object: any)
	local run = runs[player]
	if not run or run.phase ~= "Running" or type(kind) ~= "string" or not CLIENT_TRICKS[kind] or not validObject(run, object) then
		return
	end
	local now = os.clock()
	if now - run.lastStyle < 0.12 or now < run.jetpackUntil then
		return
	end
	local target = object :: Instance
	if target:GetAttribute("Styled") or target:GetAttribute("NoStyle") or target:GetAttribute("Destroyed") then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	if kind == "Roof" then
		if not target:IsA("BasePart") or target.CollisionGroup ~= "RunGround" then
			return
		end
		local top = target.Position.Y + target.Size.Y / 2 - run.origin.Y
		local high = Config.Run.HighGround
		if top < high or root.Position.Y - run.origin.Y < high or not nearRunner(run, target.Position, 60) then
			return
		end
	else
		local trackD = target:GetAttribute("TrackD")
		if not target:GetAttribute("ObstacleType") or type(trackD) ~= "number" or trackD < run.d - 40 or trackD > run.d + 15 then
			return
		end
	end
	target:SetAttribute("Styled", true)
	run.lastStyle = now
	comboAdd(run, kind)
end

local function rollMysteryBox(): { kind: string, amount: number }
	local total = 0
	for _, r in Config.Economy.MysteryBox do
		total += r.weight
	end
	local roll = rng:NextNumber() * total
	for _, r in Config.Economy.MysteryBox do
		if roll < r.weight then
			return { kind = r.kind, amount = r.amount }
		end
		roll -= r.weight
	end
	return { kind = "Coins", amount = 100 }
end

-- Jetpack: a trail of coins up in the sky for the whole flight.
local function spawnSkyCoins(run: Run, duration: number)
	local folder = Instance.new("Folder")
	folder.Name = "SkyCoins"
	folder.Parent = run.track.folder
	local speed = ImpactRules.SpeedAt(run.d * Config.Run.MetersPerStud) * Config.PowerUps.JetpackSpeedMultiplier
	local fromD = run.d + 25
	local toD = run.d + speed * duration - 10
	local lane = 0
	local d = fromD
	local i = 0
	while d < toD do
		i += 1
		if i % 12 == 0 then
			lane = math.clamp(lane + (if rng:NextNumber() < 0.5 then -1 else 1), -1, 1)
		end
		local c = Util.Part({
			Name = "Coin",
			Parent = folder,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2.2, 2.2),
			CFrame = CFrame.new(run.origin + Vector3.new(Config.Run.LanePositions[lane], Config.PowerUps.JetpackHeight + 2.5, -d)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		c:SetAttribute("Coin", true)
		c:SetAttribute("Value", Config.Economy.CoinValue)
		d += 4
	end
	task.delay(duration + 8, function()
		folder:Destroy()
	end)
end

local function onPickupItem(player: Player, pickupPart: any)
	local run = runs[player]
	local profile = PlayerData.Get(player)
	if not run or not profile or run.phase ~= "Running" or not validObject(run, pickupPart) then
		return
	end
	local part = pickupPart :: Instance
	local kind = part:GetAttribute("Pickup")
	if not part:IsA("BasePart") or not kind or not nearRunner(run, part.Position, Config.Run.PickupTolerance) then
		return
	end
	-- Read everything we need before the part is destroyed.
	local brainrotId = part:GetAttribute("BrainrotId")
	local mutationId = part:GetAttribute("Mutation")
	local powerUpId = part:GetAttribute("PowerUpId")
	part:Destroy()

	local now = os.clock()
	if kind == "Brainrot" then
		local data = BrainrotData.Get(if type(brainrotId) == "string" then brainrotId else nil)
		if data then
			-- The mutation was rolled (server side) when the cage was built.
			local mutation = MutationData.Get(if type(mutationId) == "string" then mutationId else nil)
			local key = MutationData.Key(data.id, mutation and mutation.id)
			table.insert(run.rescued, key)
			world(player, { type = "BrainrotRescued", id = data.id, label = MutationData.Label(key), rarity = data.rarity, mutation = mutation and mutation.id })
			comboAdd(run, "Rescue")
			-- Rare rescues are announced to everyone in the server.
			if (mutation and mutation.announce) or Config.Mutations.AnnounceRarities[data.rarity] then
				local color = if mutation then mutation.color else BrainrotData.RarityColors[data.rarity]
				Remotes.Event("Announce"):FireAllClients(("🔓 %s rescued a %s! (%s)"):format(player.DisplayName, MutationData.Label(key), string.upper(data.rarity)), color)
			end
		end
	elseif kind == "PowerUp" then
		local powerUp = PowerUpData.Get(if type(powerUpId) == "string" then powerUpId else nil)
		if not powerUp then
			return
		end
		local duration = PowerUpData.Duration(powerUp.id, profile.Upgrades[powerUp.id])
		if powerUp.id == "Magnet" then
			run.magnetUntil = now + duration
		elseif powerUp.id == "Jetpack" then
			run.jetpackUntil = now + duration
			spawnSkyCoins(run, duration)
		elseif powerUp.id == "SuperSneakers" then
			run.sneakersUntil = now + duration
		elseif powerUp.id == "ScoreBooster" then
			run.boosterUntil = now + duration
		end
		world(player, { type = "PowerUp", id = powerUp.id, duration = duration })
		comboAdd(run, "PowerUp")
	elseif kind == "MysteryBox" then
		local reward = rollMysteryBox()
		table.insert(run.boxRewards, reward)
		world(player, { type = "MysteryBox", kind = reward.kind, amount = reward.amount })
		comboAdd(run, "MysteryBox")
	end
end

local function onUseHoverboard(player: Player)
	local run = runs[player]
	local profile = PlayerData.Get(player)
	if not run or not profile or run.phase ~= "Running" then
		return
	end
	local now = os.clock()
	if now < run.hoverUntil or profile.Hoverboards <= 0 then
		return
	end
	profile.Hoverboards -= 1
	run.hoverboardsUsed += 1
	run.hoverUntil = now + Config.PowerUps.HoverboardDuration
	world(player, { type = "Hoverboard", duration = Config.PowerUps.HoverboardDuration, left = profile.Hoverboards })
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
	run.combo.stacks = 0
	local profile = PlayerData.Get(player)
	Remotes.Event("RunCaught"):FireClient(player, {
		canRevive = run.revives < Config.Economy.MaxRevivesPerRun,
		cost = reviveCost(run),
		bankCoins = if profile then profile.Coins else 0,
		robux = Config.DeveloperProducts.Revive ~= 0,
		timeout = 10,
		score = math.floor(run.score),
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
		MarketplaceService:PromptProductPurchase(player, Config.DeveloperProducts.Revive)
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

-- Always gets the player back to their base with a fresh character, from any
-- state (results screen, a broken run, a run the server already cleaned up).
function RunManager.ReturnToLobby(player: Player)
	local run = runs[player]
	if run then
		runs[player] = nil
		cleanup(run)
	end
	player:SetAttribute("InRun", false)
	if player.Parent then
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn("[RunManager] LoadCharacter failed:", err)
		end
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
	local score = math.floor(run.score)
	local boxCoins = 0
	local boxBoards = 0
	for _, reward in run.boxRewards do
		if reward.kind == "Coins" then
			boxCoins += reward.amount
		else
			boxBoards += reward.amount
		end
	end
	local totalCoins = run.coins + boxCoins
	local newHighScore = false
	local rescued = {}
	local levelUps = {}
	local oldMultiplier = run.baseMultiplier
	local newMultiplier = oldMultiplier

	if profile then
		local stats = profile.Stats
		stats.TotalRuns += 1
		stats.TotalDistance += meters
		stats.TotalCoins += totalCoins
		stats.BestDistance = math.max(stats.BestDistance, meters)
		stats.LongestSurvival = math.max(stats.LongestSurvival, math.floor(run.survival))
		if score > stats.HighScore then
			stats.HighScore = score
			newHighScore = true
		end
		profile.Coins += totalCoins
		profile.Hoverboards += boxBoards
		-- Hype left over stays for next time; it starts charging again now.
		profile.Hype = run.hype
		profile.HypeUpdated = os.time()
		-- The score is XP for every Brainrot that was on the base this run.
		for _, up in PlayerData.AwardBrainrotXP(profile, score) do
			local data = BrainrotData.Get(up.id) :: BrainrotData.Brainrot
			table.insert(levelUps, { name = data.name, icon = data.icon, from = up.from, to = up.to, bonus = up.bonus })
		end
		-- Rescued Brainrots go straight to your base (kept even if you're caught).
		for _, key in run.rescued do
			local id, mutation = MutationData.Split(key)
			local data = BrainrotData.Get(id) :: BrainrotData.Brainrot
			table.insert(rescued, {
				id = id,
				mutation = mutation,
				label = MutationData.Label(key),
				icon = data.icon,
				bonus = PlayerData.BrainrotBonus(profile, key),
				isNew = (profile.Brainrots[key] or 0) == 0, -- first of this kind/variant
			})
			profile.Brainrots[key] = (profile.Brainrots[key] or 0) + 1
			profile.Collection[id] = true
			stats.BrainrotsRescued += 1
		end
		newMultiplier = PlayerData.Multiplier(profile)
		PlayerData.Changed(player)
		task.spawn(Leaderboards.Submit, player)
	end

	if not player.Parent or reason == "Left" then
		runs[player] = nil
		cleanup(run)
		return
	end

	Remotes.Event("RunEnded"):FireClient(player, {
		reason = reason,
		score = score,
		newHighScore = newHighScore,
		highScore = if profile then profile.Stats.HighScore else score,
		distance = meters,
		multiplier = oldMultiplier,
		newMultiplier = newMultiplier,
		bestCombo = run.bestCombo,
		hypeStart = run.hypeStart,
		hypeLeft = run.hype,
		xp = if profile then score else 0,
		levelUps = levelUps,
		coins = run.coins,
		boxCoins = boxCoins,
		boxBoards = boxBoards,
		totalCoins = totalCoins,
		survival = math.floor(run.survival),
		revives = run.revives,
		rescued = rescued,
		pedestals = if profile then profile.Pedestals else 0,
	})

	-- Back to the base when the player closes the results (or after 30s).
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
	Remotes.Event("ReportStyle").OnServerEvent:Connect(onReportStyle)
	Remotes.Event("UseHoverboard").OnServerEvent:Connect(onUseHoverboard)
	Remotes.Event("ReportCaught").OnServerEvent:Connect(onReportCaught)
	Remotes.Event("ChooseRevive").OnServerEvent:Connect(onChooseRevive)
	-- "BACK TO BASE" on the results screen. Also the client's way out of a run
	-- it can't continue: an unfinished run is settled first (like being caught).
	local lastLeave: { [Player]: number } = {}
	Remotes.Event("LeaveResults").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if (lastLeave[player] or 0) > now then
			return
		end
		lastLeave[player] = now + 2
		local run = runs[player]
		if run and not run.ended then
			RunManager.EndRun(player, "Left")
		end
		RunManager.ReturnToLobby(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastLeave[player] = nil
	end)

	-- Walk into a run portal to start. Plot portals only work for their owner.
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
			local owner = trigger:GetAttribute("OwnerUserId")
			if owner ~= nil and owner ~= player.UserId then
				notify(player, "That's someone else's run portal — use your own base!", Color3.fromRGB(255, 200, 90))
				return
			end
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
