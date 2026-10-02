--!strict
-- Run areas. The track changes as your score climbs during a run: every
-- area is inspired by a Roblox game (familiar, yet different) and has its
-- own Brainrots to rescue, with bigger multipliers the further you get.
--
--   🌱 Grow a Garden   score 0 →          grassy garden path, fences
--   🌊 Tsunami Beach   score 100,000 →    sandy beach by the sea
--   (area 3 at 750,000, area 4 at 2,500,000: add them here, with their
--    sections in TrackAreas)
--
-- The sections each area is built from are real models you can edit in
-- Studio: Workspace.TrackAreas.<id> (see TrackAreas.luau on the server).

export type Lighting = {
	ClockTime: number,
	Brightness: number,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
}

export type Area = {
	id: string,
	name: string,
	icon: string,
	fromScore: number, -- the run score where this area starts
	inspiredBy: string,
	color: Color3, -- banner / HUD colour
	lighting: Lighting,
}

local AreaData = {}

local list: { Area } = {
	{
		id = "Garden",
		name = "Grow a Garden",
		icon = "🌱",
		fromScore = 0,
		inspiredBy = "Grow a Garden",
		color = Color3.fromRGB(120, 220, 90),
		lighting = {
			ClockTime = 14,
			Brightness = 2.6,
			OutdoorAmbient = Color3.fromRGB(150, 150, 160),
			FogColor = Color3.fromRGB(190, 225, 255),
			FogStart = 300,
			FogEnd = 900,
		},
	},
	{
		id = "Beach",
		name = "Tsunami Beach",
		icon = "🌊",
		fromScore = 100000,
		inspiredBy = "Escape Tsunamis for Brainrots",
		color = Color3.fromRGB(80, 200, 255),
		lighting = {
			ClockTime = 12.5,
			Brightness = 3,
			OutdoorAmbient = Color3.fromRGB(160, 160, 170),
			FogColor = Color3.fromRGB(170, 225, 255),
			FogStart = 300,
			FogEnd = 950,
		},
	},
}

local byId: { [string]: Area } = {}
for i, area in list do
	byId[area.id] = area
	assert(i == 1 or area.fromScore > list[i - 1].fromScore, "areas must be in score order")
end

AreaData.List = list
AreaData.First = list[1]

-- Milestones for areas still to be designed (tools/milestones.luau uses them).
AreaData.Planned = {
	{ fromScore = 750000, label = "area 3" },
	{ fromScore = 2500000, label = "area 4" },
}

function AreaData.Get(id: string?): Area?
	return if id then byId[id] else nil
end

-- The area a run is in at this score.
function AreaData.ForScore(score: number): Area
	local current = list[1]
	for _, area in list do
		if score >= area.fromScore then
			current = area
		end
	end
	return current
end

-- The area after this one (nil for the last).
function AreaData.Next(area: Area): Area?
	for i, a in list do
		if a == area then
			return list[i + 1]
		end
	end
	return nil
end

return AreaData
