--!strict
-- Progression math shared by the server (authoritative) and the UI:
--
--   * BRAINROT LEVELS  every run's score is XP for the Brainrots on your
--                      base; levels raise the multiplier bonus they give.
--   * STYLE COMBO      tricks during a run build a temporary multiplier that
--                      drains when you play it safe and resets on a crash.
--   * HYPE             your base charges up while you're away and boosts the
--                      start of your next run.
--
-- Score multiplier during a run = base (Brainrots) × ✖️2 booster × combo × hype.

local BrainrotData = require(script.Parent.BrainrotData)
local Config = require(script.Parent.Config)

local Progression = {}

local LV = Config.Levels
local CB = Config.Combo
local HY = Config.Hype

-- ───────────────────────────── formatting ─────────────────────────────

-- 12 → "x12", 12.5 → "x12.5", 3.25 → "x3.25"
function Progression.FormatMultiplier(n: number): string
	local rounded = math.floor(n * 100 + 0.5) / 100
	if rounded == math.floor(rounded) then
		return ("x%d"):format(rounded)
	end
	local s = ("%.2f"):format(rounded):gsub("0+$", "")
	return "x" .. s
end

-- ───────────────────────────── Brainrot levels ─────────────────────────────

-- XP needed to go from `level` to `level + 1` (nil at max level).
function Progression.XPToNext(level: number): number?
	if level >= LV.MaxLevel then
		return nil
	end
	return math.floor(LV.XPBase * LV.XPGrowth ^ (level - 1))
end

-- Level for a total XP amount, plus progress into the current level.
function Progression.Level(xp: number?): (number, number, number?)
	local level = 1
	local left = math.max(0, xp or 0)
	while true do
		local need = Progression.XPToNext(level)
		if not need or left < need then
			return level, left, need
		end
		left -= need
		level += 1
	end
end

-- Multiplier bonus of a Brainrot at a level.
function Progression.BonusAt(id: string, level: number): number
	local data = BrainrotData.Get(id)
	if not data then
		return 0
	end
	return data.bonus * (1 + LV.BonusPerLevel * (level - 1))
end

function Progression.Bonus(id: string, xp: number?): number
	return Progression.BonusAt(id, (Progression.Level(xp)))
end

-- ───────────────────────────── style combo ─────────────────────────────

export type Combo = { stacks: number, lastAction: number }

function Progression.NewCombo(): Combo
	return { stacks = 0, lastAction = 0 }
end

-- Adds the points for a trick; returns how many stacks it gave.
function Progression.ComboAdd(combo: Combo, kind: string, now: number): number
	local points = CB.Points[kind] or 0
	local before = combo.stacks
	combo.stacks = math.min(CB.MaxStacks, combo.stacks + points)
	combo.lastAction = now
	return combo.stacks - before
end

function Progression.ComboDecay(combo: Combo, now: number, dt: number)
	if combo.stacks > 0 and now - combo.lastAction > CB.Grace then
		combo.stacks = math.max(0, combo.stacks - CB.DecayPerSecond * dt)
	end
end

function Progression.ComboMultiplier(combo: Combo): number
	return 1 + CB.PerStack * combo.stacks
end

-- ───────────────────────────── hype ─────────────────────────────

-- Charge gained per second (0..1 scale) for a base with this multiplier.
function Progression.HypeRate(baseMultiplier: number, inLobby: boolean): number
	local hours = if inLobby then HY.LobbyHoursToFull else HY.OfflineHoursToFull
	local speedup = math.min(HY.MaxSpeedup, 1 + HY.SpeedupPerMultiplier * math.max(0, baseMultiplier - 1))
	return speedup / (hours * 3600)
end

function Progression.HypeMultiplier(charge: number): number
	return 1 + HY.MaxBonus * math.clamp(charge, 0, 1)
end

-- Charge spent per meter run.
function Progression.HypeDrainPerMeter(): number
	return 1 / HY.MetersAtFull
end

return Progression
