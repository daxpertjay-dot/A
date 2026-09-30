--!strict
-- Central tuning values for Brainrot Runner. Everything that affects "feel"
-- (speeds, camera, chase pressure, destruction) lives here so it can be tuned
-- without touching gameplay code.

local Config = {}

Config.DataStoreName = "BrainrotRunner_PlayerData_v1"
Config.DataStoreEnabled = true -- falls back to session-only data if DataStores are unavailable (e.g. Studio without API access)

-- ───────────────────────────── LOBBY ─────────────────────────────
Config.Lobby = {
	Origin = Vector3.new(0, 0, 0),
	SpawnOffset = Vector3.new(0, 4, 0),
	-- Station positions relative to the lobby origin (matches the layout mockup:
	-- leaderboard north, crates west, shop east, run entrance south).
	Leaderboard = Vector3.new(0, 0, -110),
	Crates = Vector3.new(-100, 0, 0),
	Shop = Vector3.new(100, 0, 0),
	RunEntrance = Vector3.new(0, 0, 110),
	Loadout = Vector3.new(-80, 0, -75),
	Collection = Vector3.new(80, 0, -75),
	DailyReward = Vector3.new(-75, 0, 75),
	Stats = Vector3.new(75, 0, 75),
	Size = 330,
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

	-- Jump / roll
	Gravity = 150,
	JumpVelocity = 52,
	FastFallVelocity = -110, -- pressing roll mid-air slams you down (Subway Surfers style)
	RollDuration = 0.7,
	RollCooldown = 0.1,

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
	IntroDuration = 2.6, -- Tung Tung Tung Sahur reveal
	CountdownStep = 0.75, -- 3 → 2 → 1 → RUN!

	-- Anti-cheat tolerance on server-side distance tracking
	MaxSpeedTolerance = 1.35,
	PickupTolerance = 18,
}

-- ───────────────────────────── CHASE ─────────────────────────────
-- "Gap" is how far (in seconds of running) Tung Tung Tung Sahur is behind you.
Config.Chase = {
	StartGap = 10,
	MaxGap = 12,
	RecoverPerSecond = 0.35,
	DangerGap = 3.5, -- Sahur becomes visible right behind the player below this
	RevivedGap = 9,
	RevivedInvulnerability = 2.5,
	BombPushback = 3,

	-- Gap lost per impact tier
	GapLoss = {
		SmallBreak = 0.8, -- tier 1 object smashed
		CrashThrough = 1.5, -- tier 2 wall broken with momentum
		Bump = 2.5, -- stopped by a wall you could not break
		SideBump = 1.2, -- clipped something while changing lanes
	},
	SlowdownOnSmallBreak = 0.85, -- speed multiplier (recovers)
	StaggerTime = 0.55,
	BumpPushback = 5,
	SpeedRecoveryPerSecond = 0.9,
}

-- ───────────────────────────── DESTRUCTION ─────────────────────────────
Config.Destruction = {
	CrashThroughSpeed = 56, -- studs/sec needed to smash a tier 2 wall without equipment
	MaxDebrisPerEvent = 15,
	DebrisLifetime = 3,
	MaxClientDebris = 120,
}

-- ───────────────────────────── CAMERA ─────────────────────────────
Config.Camera = {
	Distance = 16,
	Height = 7,
	LookAhead = 14,
	LookHeight = 2.5,
	LaneFollowSharpness = 12,
	VerticalFollow = 0.4, -- how much of a jump the camera follows
	VerticalSharpness = 6,
	FOV = { Normal = 72, Fast = 76, VeryFast = 80 },
	FastSpeed = 55,
	VeryFastSpeed = 68,
	FOVSharpness = 3,
}

-- ───────────────────────────── ECONOMY ─────────────────────────────
Config.Economy = {
	StartingCoins = 250,
	ReviveBaseCost = 150, -- doubles every revive in the same run
	MaxRevivesPerRun = 3,
	DistanceCoinBonus = 0.05, -- coins awarded per meter at the end of a run
	CoinValue = 1,
}

-- Loadout slots unlock through progression (total runs)
Config.LoadoutSlotUnlocks = { 0, 5, 20 }

-- Robux developer products. Leave at 0 until you create them on the Creator
-- Dashboard; Robux buttons are disabled for products with id 0.
Config.DeveloperProducts = {
	RareCrate = 0,
	LegendaryCrate = 0,
	CoinPackSmall = 0,
	CoinPackLarge = 0,
	Revive = 0,
}

-- Optional audio. Put your own asset ids here ("rbxassetid://123").
Config.Sounds = {
	Tung = "",
	Crash = "",
	Explosion = "",
	Coin = "",
	Countdown = "",
	Go = "",
	LobbyMusic = "",
	RunMusic = "",
}

return Config
