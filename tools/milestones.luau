-- Score milestone math: how far (and how long) a run has to go to reach
-- each area, for bases of different strength. Reads the real numbers
-- (Config speed curve, combo, AreaData thresholds, Brainrot bonuses and
-- levels), so re-run it whenever multipliers change:
--
--   python3 tests/mirror.py && lune run tools/milestones.luau
--
-- score per meter = PointsPerMeter × base × combo × Hype × booster. The
-- table assumes an average combo of x1.5 and leaves Hype (worth ~750 extra
-- meters at full charge) and the x2 booster out, so real runs are a bit
-- faster than this.
local process = require("@lune/process")

local H = require("../tests/harness")
local AreaData = H.require(H.shared.AreaData)
local BrainrotData = H.require(H.shared.BrainrotData)
local Config = H.require(H.shared.Config)
local ImpactRules = H.require(H.shared.ImpactRules)
local Progression = H.require(H.shared.Progression)

local COMBO = 1.5

-- Score thresholds: where each area starts, plus the planned ones.
local milestones = {}
for _, area in AreaData.List do
	if area.fromScore > 0 then
		table.insert(milestones, { score = area.fromScore, label = area.icon .. " " .. area.name })
	end
end
for _, planned in AreaData.Planned do
	table.insert(milestones, { score = planned.fromScore, label = "(" .. planned.label .. ")" })
end

-- Average and best bonus of the Brainrots caught in an area.
local function areaBonus(areaId: string): (number, number)
	local total, weight, best = 0, 0, 0
	for _, b in BrainrotData.List do
		if b.area == areaId and b.catchWeight > 0 then
			total += b.bonus * b.catchWeight
			weight += b.catchWeight
			best = math.max(best, b.bonus)
		end
	end
	return total / weight, best
end

local function base(perBrainrot: number, count: number, level: number): number
	return Config.Score.BaseMultiplier + count * perBrainrot * (1 + Config.Levels.BonusPerLevel * (level - 1))
end

local gardenAvg, gardenBest = areaBonus("Garden")
local beachAvg, beachBest = areaBonus("Beach")
local bases = {
	{ "Starter: 3 Garden catches, Lv 1", base(gardenAvg, Config.Score.StartingPedestals, 1) },
	{ "10 Garden catches, Lv 1", base(gardenAvg, Config.Score.MaxPedestals, 1) },
	{ "10 Garden catches, Lv 5", base(gardenAvg, Config.Score.MaxPedestals, 5) },
	{ "10 best Garden, Lv 10", base(gardenBest, Config.Score.MaxPedestals, 10) },
	{ "10 Beach catches, Lv 1", base(beachAvg, Config.Score.MaxPedestals, 1) },
	{ "10 Beach catches, Lv 5", base(beachAvg, Config.Score.MaxPedestals, 5) },
	{ "10 best Beach, Lv 10", base(beachBest, Config.Score.MaxPedestals, 10) },
}

-- Seconds to run `meters` from the start, following the speed curve.
local function secondsFor(meters: number): number
	local t, d, step = 0, 0, 5
	while d < meters do
		local dd = math.min(step, meters - d)
		t += dd / (ImpactRules.SpeedAt(d) * Config.Run.MetersPerStud)
		d += dd
	end
	return t
end

local function clock(seconds: number): string
	if seconds >= 3600 then
		return ("%dh%02dm"):format(seconds // 3600, (seconds % 3600) // 60)
	end
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function short(n: number): string
	if n >= 1e6 then
		return ("%.2gM"):format(n / 1e6)
	elseif n >= 1e3 then
		return ("%gk"):format(math.floor(n / 100) / 10)
	end
	return tostring(math.floor(n))
end

print(("Average catch bonus: Garden +%.1fx (best +%d), Beach +%.1fx (best +%d). Combo assumed x%.1f.\n"):format(gardenAvg, gardenBest, beachAvg, beachBest, COMBO))
local header = "| Base | Base x | Run x |"
local rule = "|---|---:|---:|"
for _, m in milestones do
	header ..= (" %s at %s |"):format(m.label, short(m.score))
	rule ..= "---:|"
end
print(header)
print(rule)
for _, b in bases do
	local runX = b[2] * COMBO
	local row = ("| %s | %.1f | %.1f |"):format(b[1], b[2], runX)
	for _, m in milestones do
		local meters = m.score / (Config.Score.PointsPerMeter * runX)
		row ..= (" %s m · %s |"):format(short(meters), clock(secondsFor(meters)))
	end
	print(row)
end
process.exit(0)
