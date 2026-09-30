--!strict
-- Equipment crates. Crates are bought (coins or Robux) or earned (daily
-- rewards, run pickups), stored unopened, and opened at the lobby crate area.

local EquipmentData = require(script.Parent.EquipmentData)

export type Crate = {
	id: string,
	name: string,
	color: Color3,
	coinPrice: number,
	robuxLabel: string?, -- shown on the physical display, e.g. "99 R$"
	productKey: string?, -- key into Config.DeveloperProducts
	weights: { [string]: number }, -- rarity -> weight
}

local CrateData = {}

local crates: { Crate } = {
	{
		id = "Common",
		name = "COMMON CRATE",
		color = Color3.fromRGB(150, 160, 170),
		coinPrice = 400,
		weights = { Common = 80, Rare = 18, Legendary = 2 },
	},
	{
		id = "Rare",
		name = "RARE CRATE",
		color = Color3.fromRGB(60, 150, 255),
		coinPrice = 2000,
		robuxLabel = "99 R$",
		productKey = "RareCrate",
		weights = { Common = 45, Rare = 45, Legendary = 10 },
	},
	{
		id = "Legendary",
		name = "LEGENDARY CRATE",
		color = Color3.fromRGB(255, 180, 30),
		coinPrice = 6000,
		robuxLabel = "249 R$",
		productKey = "LegendaryCrate",
		weights = { Rare = 60, Legendary = 40 },
	},
}

CrateData.Crates = crates

local byId: { [string]: Crate } = {}
for _, crate in crates do
	byId[crate.id] = crate
end
CrateData.ById = byId

function CrateData.Get(id: string): Crate?
	return byId[id]
end

-- Rolls an item from a crate. `rng` lets the server use its own Random.
function CrateData.Roll(crateId: string, rng: Random): EquipmentData.Item?
	local crate = byId[crateId]
	if not crate then
		return nil
	end

	local total = 0
	for _, weight in crate.weights do
		total += weight
	end
	local roll = rng:NextNumber() * total
	local rarity = "Common"
	for _, name in { "Common", "Rare", "Legendary" } do
		local weight = crate.weights[name] or 0
		if roll < weight then
			rarity = name
			break
		end
		roll -= weight
	end

	local pool = EquipmentData.ByRarity(rarity)
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

return CrateData
