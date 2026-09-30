--!strict
-- Brainrots: Verity has locked them in cages along the track. Rescue one by
-- running through its cage; it goes to your base, where it raises your
-- SCORE MULTIPLIER while it stands on a pedestal.
-- `look` drives the primitive model builder in ModelFactory so every
-- Brainrot has a physical model without needing uploaded meshes.

export type Look = {
	body: Color3,
	accent: Color3,
	shape: "Log" | "Shark" | "Croc" | "Cup" | "Tree" | "Elephant" | "Banana" | "Goose" | "Cat",
	scale: number,
}

export type Brainrot = {
	id: string,
	name: string,
	icon: string,
	rarity: string,
	description: string,
	bonus: number, -- added to your score multiplier while it stands on your base
	minDistance: number, -- earliest distance (m) its cage can appear in a run
	catchWeight: number, -- how often it shows up (0 = never)
	look: Look,
}

local BrainrotData = {}

local list: { Brainrot } = {
	{
		id = "TungTungTungSahur",
		name = "Tung Tung Tung Sahur",
		icon = "🪵",
		rarity = "Mythic",
		description = "Verity's henchman. You can't catch him — only escape him.",
		bonus = 1, minDistance = 0, catchWeight = 0,
		look = { body = Color3.fromRGB(176, 124, 74), accent = Color3.fromRGB(90, 60, 30), shape = "Log", scale = 1 },
	},
	{
		id = "TralaleroTralala",
		name = "Tralalero Tralala",
		icon = "🦈",
		rarity = "Rare",
		description = "A three-legged shark in Nike sneakers.",
		bonus = 2, minDistance = 250, catchWeight = 25,
		look = { body = Color3.fromRGB(80, 140, 200), accent = Color3.fromRGB(255, 255, 255), shape = "Shark", scale = 1 },
	},
	{
		id = "BombardiroCrocodilo",
		name = "Bombardiro Crocodilo",
		icon = "🐊",
		rarity = "Epic",
		description = "Half crocodile, half bomber plane, all chaos.",
		bonus = 3, minDistance = 700, catchWeight = 12,
		look = { body = Color3.fromRGB(70, 140, 60), accent = Color3.fromRGB(120, 120, 130), shape = "Croc", scale = 1.1 },
	},
	{
		id = "BallerinaCappuccina",
		name = "Ballerina Cappuccina",
		icon = "☕",
		rarity = "Rare",
		description = "A cappuccino that dances. Mimimi.",
		bonus = 2, minDistance = 400, catchWeight = 25,
		look = { body = Color3.fromRGB(255, 190, 220), accent = Color3.fromRGB(150, 100, 60), shape = "Cup", scale = 1 },
	},
	{
		id = "BrrBrrPatapim",
		name = "Brr Brr Patapim",
		icon = "🌳",
		rarity = "Uncommon",
		description = "A forest monkey-tree with enormous feet.",
		bonus = 1, minDistance = 100, catchWeight = 50,
		look = { body = Color3.fromRGB(110, 80, 50), accent = Color3.fromRGB(70, 170, 70), shape = "Tree", scale = 1.1 },
	},
	{
		id = "LiriliLarila",
		name = "Lirilì Larilà",
		icon = "🐘",
		rarity = "Epic",
		description = "A cactus elephant in sandals. Controls time, somehow.",
		bonus = 3, minDistance = 900, catchWeight = 12,
		look = { body = Color3.fromRGB(90, 170, 90), accent = Color3.fromRGB(200, 200, 200), shape = "Elephant", scale = 1.1 },
	},
	{
		id = "ChimpanziniBananini",
		name = "Chimpanzini Bananini",
		icon = "🍌",
		rarity = "Uncommon",
		description = "A chimp living inside a banana.",
		bonus = 1, minDistance = 0, catchWeight = 50,
		look = { body = Color3.fromRGB(250, 220, 60), accent = Color3.fromRGB(90, 60, 40), shape = "Banana", scale = 1 },
	},
	{
		id = "CappuccinoAssassino",
		name = "Cappuccino Assassino",
		icon = "🗡️",
		rarity = "Legendary",
		description = "A coffee cup with katanas. You never see him coming.",
		bonus = 5, minDistance = 1600, catchWeight = 4,
		look = { body = Color3.fromRGB(60, 40, 30), accent = Color3.fromRGB(230, 230, 240), shape = "Cup", scale = 1 },
	},
	{
		id = "BombombiniGusini",
		name = "Bombombini Gusini",
		icon = "🪿",
		rarity = "Epic",
		description = "A goose fighter jet. Bombardiro's little cousin.",
		bonus = 3, minDistance = 1200, catchWeight = 12,
		look = { body = Color3.fromRGB(240, 240, 240), accent = Color3.fromRGB(255, 150, 40), shape = "Goose", scale = 1 },
	},
	{
		id = "TrippiTroppi",
		name = "Trippi Troppi",
		icon = "🦐",
		rarity = "Legendary",
		description = "A shrimp with a cat's face. Nobody knows why.",
		bonus = 5, minDistance = 2200, catchWeight = 4,
		look = { body = Color3.fromRGB(255, 140, 110), accent = Color3.fromRGB(250, 220, 180), shape = "Cat", scale = 1 },
	},
}

BrainrotData.List = list

local byId: { [string]: Brainrot } = {}
for _, b in list do
	byId[b.id] = b
end
BrainrotData.ById = byId

BrainrotData.ChaserId = "TungTungTungSahur" -- the villain's henchman
BrainrotData.StarterId = "ChimpanziniBananini" -- every new base starts with one

function BrainrotData.Get(id: string?): Brainrot?
	return if id then byId[id] else nil
end

-- Weighted pick of a caged Brainrot that can appear at this distance.
function BrainrotData.PickCatchable(distance: number, rng: Random): Brainrot?
	local pool = {}
	local total = 0
	for _, b in list do
		if b.catchWeight > 0 and distance >= b.minDistance then
			table.insert(pool, b)
			total += b.catchWeight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, b in pool do
		if roll < b.catchWeight then
			return b
		end
		roll -= b.catchWeight
	end
	return pool[#pool]
end

BrainrotData.RarityColors = {
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(60, 150, 255),
	Epic = Color3.fromRGB(190, 90, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
	Mythic = Color3.fromRGB(255, 70, 110),
} :: { [string]: Color3 }

return BrainrotData
