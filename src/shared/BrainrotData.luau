--!strict
-- The Brainrot collection. Brainrots are encountered during runs (special
-- Brainrot sections) and show up in the lobby collection gallery.
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
	minDistance: number, -- earliest distance (m) it can appear in a run
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
		minDistance = 0,
		look = { body = Color3.fromRGB(176, 124, 74), accent = Color3.fromRGB(90, 60, 30), shape = "Log", scale = 1 },
	},
	{
		id = "TralaleroTralala",
		name = "Tralalero Tralala",
		icon = "🦈",
		rarity = "Rare",
		description = "A three-legged shark in Nike sneakers.",
		minDistance = 150,
		look = { body = Color3.fromRGB(80, 140, 200), accent = Color3.fromRGB(255, 255, 255), shape = "Shark", scale = 1 },
	},
	{
		id = "BombardiroCrocodilo",
		name = "Bombardiro Crocodilo",
		icon = "🐊",
		rarity = "Epic",
		description = "Half crocodile, half bomber plane, all chaos.",
		minDistance = 400,
		look = { body = Color3.fromRGB(70, 140, 60), accent = Color3.fromRGB(120, 120, 130), shape = "Croc", scale = 1.1 },
	},
	{
		id = "BallerinaCappuccina",
		name = "Ballerina Cappuccina",
		icon = "☕",
		rarity = "Rare",
		description = "A cappuccino that dances. Mimimi.",
		minDistance = 250,
		look = { body = Color3.fromRGB(255, 190, 220), accent = Color3.fromRGB(150, 100, 60), shape = "Cup", scale = 1 },
	},
	{
		id = "BrrBrrPatapim",
		name = "Brr Brr Patapim",
		icon = "🌳",
		rarity = "Uncommon",
		description = "A forest monkey-tree with enormous feet.",
		minDistance = 100,
		look = { body = Color3.fromRGB(110, 80, 50), accent = Color3.fromRGB(70, 170, 70), shape = "Tree", scale = 1.1 },
	},
	{
		id = "LiriliLarila",
		name = "Lirilì Larilà",
		icon = "🐘",
		rarity = "Epic",
		description = "A cactus elephant in sandals. Controls time, somehow.",
		minDistance = 700,
		look = { body = Color3.fromRGB(90, 170, 90), accent = Color3.fromRGB(200, 200, 200), shape = "Elephant", scale = 1.1 },
	},
	{
		id = "ChimpanziniBananini",
		name = "Chimpanzini Bananini",
		icon = "🍌",
		rarity = "Uncommon",
		description = "A chimp living inside a banana.",
		minDistance = 50,
		look = { body = Color3.fromRGB(250, 220, 60), accent = Color3.fromRGB(90, 60, 40), shape = "Banana", scale = 1 },
	},
	{
		id = "CappuccinoAssassino",
		name = "Cappuccino Assassino",
		icon = "🗡️",
		rarity = "Legendary",
		description = "A coffee cup with katanas. You never see him coming.",
		minDistance = 1200,
		look = { body = Color3.fromRGB(60, 40, 30), accent = Color3.fromRGB(230, 230, 240), shape = "Cup", scale = 1 },
	},
	{
		id = "BombombiniGusini",
		name = "Bombombini Gusini",
		icon = "🪿",
		rarity = "Epic",
		description = "A goose fighter jet. Bombardiro's little cousin.",
		minDistance = 900,
		look = { body = Color3.fromRGB(240, 240, 240), accent = Color3.fromRGB(255, 150, 40), shape = "Goose", scale = 1 },
	},
	{
		id = "TrippiTroppi",
		name = "Trippi Troppi",
		icon = "🦐",
		rarity = "Legendary",
		description = "A shrimp with a cat's face. Nobody knows why.",
		minDistance = 1600,
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

-- Brainrots that can appear in a special section at the given distance.
function BrainrotData.AvailableAt(distance: number): { Brainrot }
	local out = {}
	for _, b in list do
		if b.id ~= BrainrotData.ChaserId and distance >= b.minDistance then
			table.insert(out, b)
		end
	end
	return out
end

return BrainrotData
