--!strict
-- Shared rules for what happens when the runner hits an obstacle. The client
-- uses them to react instantly (predicted), the server uses the same rules to
-- decide what actually gets damaged/destroyed.
--
--   Small obstacle (tier 1)  → breaks, runner slows a bit
--   Weak wall     (tier 2)  → crash through with enough momentum / boost,
--                              otherwise bump + damage (repeat hits break it)
--   Strong wall   (tier 3)  → bump + damage; needs equipment to clear
--   Indestructible (tier 4) → bump, change lanes!

local Config = require(script.Parent.Config)

export type Outcome = "Smash" | "CrashThrough" | "Bump" | "Absorbed"

export type Result = {
	outcome: Outcome,
	damage: number,
}

local ImpactRules = {}

function ImpactRules.Resolve(tier: number, collisionDamage: number, speed: number, boostActive: boolean, shieldActive: boolean): Result
	if shieldActive then
		if tier <= 2 then
			return { outcome = "Absorbed", damage = math.huge }
		elseif tier == 3 then
			return { outcome = "Absorbed", damage = 60 }
		end
		return { outcome = "Absorbed", damage = 0 }
	end
	if tier <= 1 then
		return { outcome = "Smash", damage = math.huge }
	elseif tier == 2 then
		if boostActive or speed >= Config.Destruction.CrashThroughSpeed then
			return { outcome = "CrashThrough", damage = math.huge }
		end
		return { outcome = "Bump", damage = collisionDamage }
	elseif tier == 3 then
		return { outcome = "Bump", damage = if boostActive then collisionDamage * 2 else collisionDamage }
	end
	return { outcome = "Bump", damage = 0 }
end

-- Forward speed (studs/sec) at a given distance (m), from Config.Run.SpeedCurve.
function ImpactRules.SpeedAt(distance: number): number
	local curve = Config.Run.SpeedCurve
	if distance <= curve[1].distance then
		return curve[1].speed
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if distance <= b.distance then
			local t = (distance - a.distance) / (b.distance - a.distance)
			return a.speed + (b.speed - a.speed) * t
		end
	end
	return curve[#curve].speed
end

-- The jump's shape at a given forward speed. Coin arcs are generated from
-- this so a jump always sweeps straight through them.
export type JumpProfile = { apex: number, airTime: number, length: number }

function ImpactRules.JumpProfile(speed: number, jumpScale: number?): JumpProfile
	local gravity = Config.Run.Gravity
	local v = Config.Run.JumpVelocity * (jumpScale or 1)
	local airTime = 2 * v / gravity
	return {
		apex = v * v / (2 * gravity),
		airTime = airTime,
		length = speed * airTime,
	}
end

return ImpactRules
