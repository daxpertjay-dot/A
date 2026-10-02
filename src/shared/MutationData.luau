--!strict
-- Brainrot mutations (Steal a Brainrot / Grow a Garden style). A caged
-- Brainrot sometimes comes in a rare variant that multiplies its score
-- bonus. You can see the variant in the cage before you reach it.
--
-- Owned Brainrots are stored by key: "TrippiTroppi" (normal) or
-- "TrippiTroppi:Rainbow". Levels/XP stay per Brainrot kind, so every
-- variant of a Brainrot shares its level.

local BrainrotData = require(script.Parent.BrainrotData)
local Config = require(script.Parent.Config)

export type Mutation = {
	id: string,
	name: string,
	icon: string,
	multiplier: number, -- × the Brainrot's (levelled) bonus
	chance: number, -- per rescue cage, before luck
	color: Color3,
	material: Enum.Material,
	sparkles: boolean,
	rainbow: boolean, -- colours cycle (client side)
	announce: boolean, -- rescuing one is announced to the whole server
}

local MutationData = {}

-- Rarest last.
local list: { Mutation } = {
	{ id = "Gold", name = "Gold", icon = "🥇", multiplier = 2, chance = 0.10, color = Color3.fromRGB(255, 200, 40), material = Enum.Material.Foil, sparkles = false, rainbow = false, announce = false },
	{ id = "Diamond", name = "Diamond", icon = "💎", multiplier = 3, chance = 0.035, color = Color3.fromRGB(130, 230, 255), material = Enum.Material.Glass, sparkles = true, rainbow = false, announce = true },
	{ id = "Rainbow", name = "Rainbow", icon = "🌈", multiplier = 5, chance = 0.01, color = Color3.fromRGB(255, 120, 200), material = Enum.Material.Neon, sparkles = true, rainbow = true, announce = true },
	{ id = "Galaxy", name = "Galaxy", icon = "🌌", multiplier = 10, chance = 0.002, color = Color3.fromRGB(110, 50, 200), material = Enum.Material.Neon, sparkles = true, rainbow = false, announce = true },
}

local byId: { [string]: Mutation } = {}
for _, m in list do
	byId[m.id] = m
end

MutationData.List = list

function MutationData.Get(id: string?): Mutation?
	return if id then byId[id] else nil
end

-- "TrippiTroppi", "Rainbow" → "TrippiTroppi:Rainbow"
function MutationData.Key(brainrotId: string, mutationId: string?): string
	if mutationId and byId[mutationId] then
		return brainrotId .. ":" .. mutationId
	end
	return brainrotId
end

-- "TrippiTroppi:Rainbow" → "TrippiTroppi", "Rainbow"
function MutationData.Split(key: string): (string, string?)
	local id, mutation = string.match(key, "^([^:]+):(.+)$")
	if id and mutation and byId[mutation] then
		return id, mutation
	end
	return key, nil
end

-- "🌈 Rainbow Trippi Troppi" for "TrippiTroppi:Rainbow" (just the name for
-- a normal one).
function MutationData.Label(key: string): string
	local id, mutationId = MutationData.Split(key)
	local data = BrainrotData.Get(id)
	local name = if data then data.name else id
	local m = MutationData.Get(mutationId)
	return if m then ("%s %s %s"):format(m.icon, m.name, name) else name
end

function MutationData.Multiplier(mutationId: string?): number
	local m = MutationData.Get(mutationId)
	return if m then m.multiplier else 1
end

-- Rolls a mutation for a new cage (nil = normal). `luck` multiplies every
-- chance (events and boosts can raise Config.Mutations.Luck).
function MutationData.Roll(rng: Random, luck: number?): Mutation?
	local scale = (luck or 1) * Config.Mutations.Luck
	local roll = rng:NextNumber()
	-- Rarest first, so luck boosts help the rare ones most.
	for i = #list, 1, -1 do
		local m = list[i]
		local chance = m.chance * scale
		if roll < chance then
			return m
		end
		roll -= chance
	end
	return nil
end

return MutationData
