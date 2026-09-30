--!strict
-- Brainrots: caught during runs (special Brainrot sections), displayed on
-- your base where they earn coins every second, and one can be your run
-- buddy for its perks.
-- `look` drives the primitive model builder in ModelFactory so every
-- Brainrot has a physical model without needing uploaded meshes.

export type Look = {
	body: Color3,
	accent: Color3,
	shape: "Log" | "Shark" | "Croc" | "Cup" | "Tree" | "Elephant" | "Banana" | "Goose" | "Cat",
	scale: number,
}

-- Run-buddy perks. The Brainrot you pick as your buddy follows you on runs
-- and grants its perks.
export type PerkKind =
	"StartGap" -- +seconds of head start on Sahur
	| "Magnet" -- always-on coin magnet (radius)
	| "ExtraCharges" -- +charges on every equipped item
	| "GapRecovery" -- chase gap recovers faster (fraction)
	| "BumpResist" -- bumps cost less chase gap (fraction)
	| "StartShield" -- start every run shielded (seconds)
	| "CoinBonus" -- more coins (fraction)
	| "CrashThrough" -- smash wooden walls at lower speed (studs/sec)

export type Perk = { kind: PerkKind, value: number }

export type Brainrot = {
	id: string,
	name: string,
	icon: string,
	rarity: string,
	description: string,
	income: number, -- coins per second while displayed on your base
	catchWeight: number, -- 0 = can't be caught (where/how often is set per biome in BiomeData)
	perks: { Perk },
	perkText: string,
	look: Look,
}

local BrainrotData = {}

local list: { Brainrot } = {
	{
		id = "TungTungTungSahur",
		name = "Tung Tung Tung Sahur",
		icon = "🪵",
		rarity = "Mythic",
		description = "The log with a bat. He is always behind you.",
		income = 1, catchWeight = 0, perks = { { kind = "StartGap", value = 2 } }, perkText = "+2s head start on Sahur",
		look = { body = Color3.fromRGB(176, 124, 74), accent = Color3.fromRGB(90, 60, 30), shape = "Log", scale = 1 },
	},
	{
		id = "TralaleroTralala",
		name = "Tralalero Tralala",
		icon = "🦈",
		rarity = "Rare",
		description = "A three-legged shark in Nike sneakers.",
		income = 8, catchWeight = 25, perks = { { kind = "Magnet", value = 10 } }, perkText = "Always-on coin magnet",
		look = { body = Color3.fromRGB(80, 140, 200), accent = Color3.fromRGB(255, 255, 255), shape = "Shark", scale = 1 },
	},
	{
		id = "BombardiroCrocodilo",
		name = "Bombardiro Crocodilo",
		icon = "🐊",
		rarity = "Epic",
		description = "Half crocodile, half bomber plane, all chaos.",
		income = 20, catchWeight = 12, perks = { { kind = "ExtraCharges", value = 1 } }, perkText = "+1 charge on all equipment",
		look = { body = Color3.fromRGB(70, 140, 60), accent = Color3.fromRGB(120, 120, 130), shape = "Croc", scale = 1.1 },
	},
	{
		id = "BallerinaCappuccina",
		name = "Ballerina Cappuccina",
		icon = "☕",
		rarity = "Rare",
		description = "A cappuccino that dances. Mimimi.",
		income = 8, catchWeight = 25, perks = { { kind = "GapRecovery", value = 0.4 } }, perkText = "Escape Sahur 40% faster",
		look = { body = Color3.fromRGB(255, 190, 220), accent = Color3.fromRGB(150, 100, 60), shape = "Cup", scale = 1 },
	},
	{
		id = "BrrBrrPatapim",
		name = "Brr Brr Patapim",
		icon = "🌳",
		rarity = "Uncommon",
		description = "A forest monkey-tree with enormous feet.",
		income = 3, catchWeight = 50, perks = { { kind = "BumpResist", value = 0.3 } }, perkText = "Crashes cost 30% less",
		look = { body = Color3.fromRGB(110, 80, 50), accent = Color3.fromRGB(70, 170, 70), shape = "Tree", scale = 1.1 },
	},
	{
		id = "LiriliLarila",
		name = "Lirilì Larilà",
		icon = "🐘",
		rarity = "Epic",
		description = "A cactus elephant in sandals. Controls time, somehow.",
		income = 20, catchWeight = 12, perks = { { kind = "StartShield", value = 6 } }, perkText = "Start every run with a 6s shield",
		look = { body = Color3.fromRGB(90, 170, 90), accent = Color3.fromRGB(200, 200, 200), shape = "Elephant", scale = 1.1 },
	},
	{
		id = "ChimpanziniBananini",
		name = "Chimpanzini Bananini",
		icon = "🍌",
		rarity = "Uncommon",
		description = "A chimp living inside a banana.",
		income = 3, catchWeight = 50, perks = { { kind = "CoinBonus", value = 0.1 } }, perkText = "+10% coins",
		look = { body = Color3.fromRGB(250, 220, 60), accent = Color3.fromRGB(90, 60, 40), shape = "Banana", scale = 1 },
	},
	{
		id = "CappuccinoAssassino",
		name = "Cappuccino Assassino",
		icon = "🗡️",
		rarity = "Legendary",
		description = "A coffee cup with katanas. You never see him coming.",
		income = 50, catchWeight = 4, perks = { { kind = "CrashThrough", value = 10 } }, perkText = "Smash wooden walls at lower speed",
		look = { body = Color3.fromRGB(60, 40, 30), accent = Color3.fromRGB(230, 230, 240), shape = "Cup", scale = 1 },
	},
	{
		id = "BombombiniGusini",
		name = "Bombombini Gusini",
		icon = "🪿",
		rarity = "Epic",
		description = "A goose fighter jet. Bombardiro's little cousin.",
		income = 20, catchWeight = 12, perks = { { kind = "CoinBonus", value = 0.25 } }, perkText = "+25% coins",
		look = { body = Color3.fromRGB(240, 240, 240), accent = Color3.fromRGB(255, 150, 40), shape = "Goose", scale = 1 },
	},
	{
		id = "TrippiTroppi",
		name = "Trippi Troppi",
		icon = "🦐",
		rarity = "Legendary",
		description = "A shrimp with a cat's face. Nobody knows why.",
		income = 50, catchWeight = 4, perks = { { kind = "Magnet", value = 16 }, { kind = "CoinBonus", value = 0.15 } }, perkText = "Big magnet + 15% coins",
		look = { body = Color3.fromRGB(255, 140, 110), accent = Color3.fromRGB(250, 220, 180), shape = "Cat", scale = 1 },
	},
}

BrainrotData.List = list

local byId: { [string]: Brainrot } = {}
for _, b in list do
	byId[b.id] = b
end
BrainrotData.ById = byId

BrainrotData.ChaserId = "TungTungTungSahur"

function BrainrotData.Get(id: string): Brainrot?
	return byId[id]
end

-- Sums a buddy's perks into one table: { StartGap = 2, Magnet = 10, ... }.
function BrainrotData.PerkTotals(id: string?): { [string]: number }
	local totals = {}
	local b = if id then byId[id] else nil
	if b then
		for _, perk in b.perks do
			totals[perk.kind] = (totals[perk.kind] or 0) + perk.value
		end
	end
	return totals
end

BrainrotData.RarityColors = {
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(60, 150, 255),
	Epic = Color3.fromRGB(190, 90, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
	Mythic = Color3.fromRGB(255, 70, 110),
} :: { [string]: Color3 }

return BrainrotData
