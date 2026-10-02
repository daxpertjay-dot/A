--!strict
-- Central tuning values for Brainrot Runner. Everything that affects "feel"
-- (speeds, camera, chase pressure, scoring, prices) lives here so it can be
-- tuned without touching gameplay code.
--
-- The game in one line: escape the villain, grab coins and power-ups,
-- rescue caged Brainrots. Brainrots on your base raise your SCORE MULTIPLIER
-- (and level up from your score), style builds a combo, your base charges
-- Hype while you're away; coins buy upgrades.

local Config = {}

Config.DataStoreName = "BrainrotRunner_PlayerData_v1"
Config.DataStoreEnabled = true -- falls back to session-only data if DataStores are unavailable (e.g. Studio without API access)

-- ───────────────────────────── VILLAIN ─────────────────────────────
-- The evil Brainrot guy chasing you. He kidnapped the Brainrots; Tung Tung
-- Tung Sahur is his henchman. To use your own model for him, put a Model
-- named CustomModel in ReplicatedStorage (see ModelFactory.Villain).
Config.Villain = {
	Name = "Verity",
	Title = "VERITY",
	Henchman = "TungTungTungSahur",
	CustomModel = "VerityModel",
}

-- ───────────────────────────── LOBBY ─────────────────────────────
Config.Lobby = {
	Origin = Vector3.new(0, 0, 0),
	-- A big green valley closed in by terraced, checkered cliffs.
	ValleyHalfSize = 340, -- centre to the foot of the cliffs (studs)
	CliffRings = 4, -- terraces, each one higher than the last
	CliffStep = 40, -- width of one terrace (also the ground tile size)
	PlazaHalfSize = 70, -- the SAFE ZONE in the middle (spawn, shops)
	RingRoadHalfSize = 160, -- the conveyor ring road around the plaza
	-- 8 player bases around the ring road: 3 north, 3 south, 1 west, 1 east.
	PlotWidth = 80,
	PlotDepth = 100,
	ConveyorSpeed = 30, -- studs/sec
	ConveyorWidth = 8,
	UseStuds = true, -- blocky stud look on lobby parts
	-- Square stud texture on every face (the Steal a Brainrot / Grow a Garden
	-- look). Upload assets/StudTexture.png in Studio (Asset Manager → Import,
	-- or the Toolbox) and paste its id here, e.g. "rbxassetid://1234567890".
	-- Empty = Roblox's classic round studs on top faces instead.
	StudTexture = "",
	StudTextureSize = 2, -- studs per square
	-- Your own decoration models. Put Models in a folder with this name in
	-- ServerStorage, named after a prop kind below, and they replace the
	-- built-in blocky versions wherever that kind is placed (when the lobby
	-- is generated). Each model is set on the ground (by its bounding box),
	-- turned randomly and anchored.
	PropsFolder = "LobbyProps",
	PropKinds = { "Tree", "PineTree", "Bush", "Rock", "Flowers", "Lamp" },
}

-- ───────────────────────────── SCORE ─────────────────────────────
-- Score = meters run × score multiplier. The multiplier is 1 plus the bonus
-- of every Brainrot standing on your base, doubled while a ✖️2 Score Booster
-- is active.
Config.Score = {
	PointsPerMeter = 1,
	BaseMultiplier = 1,
	-- Pedestals on your base. You start with a few; buy more with coins.
	StartingPedestals = 3,
	MaxPedestals = 10,
	PedestalCosts = { 750, 1500, 3000, 5000, 8000, 12000, 20000 }, -- cost of pedestal #4, #5, ...
}

-- ───────────────────────────── BRAINROT LEVELS ─────────────────────────────
-- After every run, each Brainrot on your base gains XP equal to the run's
-- score. Each level adds BonusPerLevel × its base bonus to the multiplier
-- (a +2x Brainrot is +2.5x at Lv 2, +3x at Lv 3 … +6.5x at Lv 10).
Config.Levels = {
	MaxLevel = 10,
	XPBase = 2500, -- XP from Lv 1 to Lv 2
	XPGrowth = 2.2, -- each level needs this much more than the last (Lv 10 ≈ 2.5M total)
	BonusPerLevel = 0.25,
}

-- ───────────────────────────── MUTATIONS ─────────────────────────────
-- Rare Brainrot variants (Gold x2, Diamond x3, Rainbow x5, Galaxy x10); see
-- MutationData for the chances. Luck multiplies every chance (for events or
-- a "server luck" boost later).
Config.Mutations = {
	Luck = 1,
	-- Rescues announced to the whole server: any mutation marked `announce`
	-- in MutationData, plus every Brainrot of these rarities.
	AnnounceRarities = { Legendary = true } :: { [string]: boolean },
}

-- ───────────────────────────── STYLE COMBO ─────────────────────────────
-- Playing well during a run builds a combo that multiplies your multiplier.
-- It drains if you play it safe and resets when you crash.
Config.Combo = {
	PerStack = 0.1, -- multiplier per stack (20 stacks = x3)
	MaxStacks = 20,
	Grace = 2.5, -- seconds after a trick before the combo starts draining
	DecayPerSecond = 2.5, -- stacks lost per second once draining
	CoinsPerStack = 15, -- every this many coins in a row = +1
	NearMissWindow = 0.5, -- dodge within this many seconds of reaching it
	Points = {
		Clear = 1, -- jumped over / rolled under something
		NearMiss = 2, -- last-second lane dodge
		Roof = 2, -- landed on a bus / tunnel roof
		Smash = 1,
		CrashThrough = 2,
		Coins = 1,
		PowerUp = 1,
		MysteryBox = 1,
		Rescue = 3,
	} :: { [string]: number },
}

-- ───────────────────────────── HYPE ─────────────────────────────
-- The Brainrots on your base charge up Hype while you're offline or hanging
-- out in the lobby. Hype boosts the start of your next run and is spent as
-- you run (a full charge lasts MetersAtFull meters).
Config.Hype = {
	MaxBonus = 1.5, -- full Hype = x2.5 on top of your multiplier
	MetersAtFull = 1000,
	OfflineHoursToFull = 8,
	LobbyHoursToFull = 4, -- charges twice as fast while you're in the server
	SpeedupPerMultiplier = 0.05, -- better bases charge faster…
	MaxSpeedup = 3, -- …up to 3x as fast
	StartingHype = 1, -- new players start fully hyped
}

-- ───────────────────────────── COINS ─────────────────────────────
-- Every coin is worth 1 (like Subway Surfers). A normal run gives a few
-- hundred; Mystery Boxes and the Jetpack's sky trail are the big moments.
-- Coins are spent on upgrades, pedestals and hoverboards.
Config.Economy = {
	StartingCoins = 200,
	CoinValue = 1,
	ReviveBaseCost = 200, -- doubles every revive in the same run
	MaxRevivesPerRun = 3,
	-- Reviving sends out a shockwave that destroys every structure (buses,
	-- walls, barriers…) from this far behind you to this far ahead (studs).
	ReviveClearBehind = 45,
	ReviveClearAhead = 110,
	HoverboardCost = 300,
	StartingHoverboards = 2,
	MysteryBox = {
		{ kind = "Coins", amount = 100, weight = 40 },
		{ kind = "Coins", amount = 250, weight = 25 },
		{ kind = "Coins", amount = 500, weight = 12 },
		{ kind = "Coins", amount = 1500, weight = 3 },
		{ kind = "Hoverboard", amount = 1, weight = 15 },
		{ kind = "Hoverboard", amount = 3, weight = 5 },
	},
}

-- ───────────────────────────── RUN WORLD ─────────────────────────────
Config.Run = {
	-- Every run gets its own strip of world far away from the lobby.
	WorldOriginX = 6000,
	SlotSpacing = 600,
	WorldY = 0,

	LanePositions = { [-1] = -8, [0] = 0, [1] = 8 } :: { [number]: number },
	LaneChangeTime = 0.14, -- seconds to slide between lanes

	-- Forward speed (studs/sec) keyed by distance (m). Linearly interpolated.
	SpeedCurve = {
		{ distance = 0, speed = 45 },
		{ distance = 500, speed = 48 },
		{ distance = 1000, speed = 52 },
		{ distance = 2000, speed = 58 },
		{ distance = 5000, speed = 70 },
		{ distance = 10000, speed = 78 },
	},
	MetersPerStud = 1,

	-- Jump / roll. A normal jump peaks at ~9 studs: enough for barriers, not
	-- for buses (12.5) or tunnel roofs (16) — those need a jump boost.
	Gravity = 150,
	JumpVelocity = 52,
	HighGround = 9, -- anything you stand on this high counts as a "roof"
	FastFallVelocity = -110, -- pressing roll mid-air slams you down (Subway Surfers style)
	RollDuration = 0.7,
	JumpBuffer = 0.18, -- a jump pressed this long before landing still fires on landing

	-- Hitboxes (studs)
	HitboxWidth = 2.6,
	HitboxHeight = 5,
	RollHitboxHeight = 2.2,
	HitboxDepth = 1.6,

	-- Segment generation
	SegmentLength = 120,
	SegmentsAhead = 6,
	SegmentsBehind = 2,
	GenerateWhenWithin = 600, -- keep at least this many studs of track generated ahead
	StartAreaLength = 90,
	SafeZoneAtSegmentEdges = 12,

	-- Timings for the run intro (seconds)
	RunStartingFade = 1.2,
	IntroDuration = 2.6, -- villain reveal
	CountdownStep = 0.75, -- 3 → 2 → 1 → RUN!

	-- Anti-cheat tolerance on server-side distance tracking
	MaxSpeedTolerance = 1.35,
	PickupTolerance = 18,
}

-- ───────────────────────────── POWER-UPS ─────────────────────────────
-- Picked up on the track (Subway Surfers style). Upgrading one with coins
-- makes it last longer. See PowerUpData for the list.
Config.PowerUps = {
	SpawnChancePerSegment = 0.15, -- a random power-up at the start of a segment
	MysteryBoxChancePerSegment = 0.06, -- otherwise, a mystery box
	BoostBeforeTallChance = 0.2, -- 👟 sneakers placed just before buses / tunnels
	MagnetRadius = 26,
	JetpackHeight = 32, -- studs above the street while flying (tunnel roofs are 16)
	JetpackSpeedMultiplier = 1.25,
	JetpackLandingInvulnerability = 1.5,
	SneakersJumpMultiplier = 1.45, -- jump velocity with Super Sneakers (reach ~19 studs)
	HoverboardJumpMultiplier = 1.4, -- riding a hoverboard also boosts jumps (~17.7 studs)
	HoverboardDuration = 30,
	HoverboardInvulnerability = 1.5, -- after the board breaks
}

-- ───────────────────────────── CHASE ─────────────────────────────
-- "Gap" is how far (in seconds of running) the villain is behind you.
Config.Chase = {
	StartGap = 10,
	MaxGap = 12,
	RecoverPerSecond = 0.35,
	DangerGap = 3.5, -- the villain becomes visible right behind the player below this
	RevivedGap = 9,
	RevivedInvulnerability = 2.5,

	-- Gap lost per impact tier
	GapLoss = {
		SmallBreak = 0.8, -- tier 1 object smashed
		CrashThrough = 1.5, -- tier 2 wall broken with momentum
		Bump = 2.5, -- stopped by a wall you could not break
		SideBump = 2, -- switched lanes into the side of something
	},
	SlowdownOnSmallBreak = 0.85, -- speed multiplier (recovers)
	SideBumpSpeed = 0.6, -- bouncing off the side of something drops you to this much speed (recovers)
	SideBumpStumble = 0.35, -- seconds of sideways wobble after a side bump
	StaggerTime = 0.55,
	BumpPushback = 5,
	SpeedRecoveryPerSecond = 0.9,
}

-- ───────────────────────────── DESTRUCTION ─────────────────────────────
Config.Destruction = {
	CrashThroughSpeed = 56, -- studs/sec needed to smash a wooden wall by running into it
	MaxDebrisPerEvent = 15,
	DebrisLifetime = 3,
	MaxClientDebris = 120,
}

-- ───────────────────────────── CAMERA ─────────────────────────────
Config.Camera = {
	-- Higher up, tilted down at the track (Subway Surfers angle).
	Distance = 15,
	Height = 12,
	LookAhead = 12,
	LookHeight = -1.5,
	LaneFollowSharpness = 12,
	VerticalFollow = 0.4, -- how much of a jump the camera follows
	VerticalSharpness = 6,
	FOV = { Normal = 86, Fast = 91, VeryFast = 96 },
	FastSpeed = 55,
	VeryFastSpeed = 68,
	FOVSharpness = 3,
}

-- ───────────────────────────── ANIMATIONS ─────────────────────────────
-- Run-time animations (R15). Any animation owned by Roblox or by you works.
-- Handy Roblox animation-pack IDs to try:
--   Ninja      run 656118852   jump 656117878
--   Cartoony   run 742638842   jump 742637942
--   Superhero  run 616117076   jump 616115533
--   Stylish    run 616140816   jump 616139451
--   Toy        run 782842708   jump 782847020
--   Robot      run 616091570   jump 616090535
--   Rthro      run 2510198475  jump 2510197830
Config.Animations = {
	R15 = {
		Run = "rbxassetid://656118852", -- Ninja sprint
		Jump = "rbxassetid://742637942", -- Cartoony jump
		Idle = "rbxassetid://507766388",
	},
	R6 = {
		Run = "rbxassetid://180426354",
		Jump = "rbxassetid://125750702",
		Idle = "rbxassetid://180435571",
	},
	RunSpeedDivisor = 34, -- playback speed = run speed / this
	-- Optional jetpack flight animation id. Leave "" to use the built-in
	-- Superman pose (one fist forward, legs trailing, jetpack flames).
	Fly = "",
	-- Optional hoverboard animation id. Leave "" to use the built-in surf
	-- stance (turned sideways, knees bent, arms out).
	Hoverboard = "",
}

-- Robux developer products. Leave at 0 until you create them on the Creator
-- Dashboard; Robux buttons are disabled for products with id 0.
Config.DeveloperProducts = {
	CoinPackSmall = 0,
	CoinPackLarge = 0,
	Revive = 0,
	Hoverboards = 0, -- 5 hoverboards
}

-- Optional audio. Put your own asset ids here ("rbxassetid://123").
Config.Sounds = {
	Villain = "",
	Crash = "",
	Coin = "",
	PowerUp = "",
	Countdown = "",
	Go = "",
	LobbyMusic = "",
	RunMusic = "",
}

return Config
