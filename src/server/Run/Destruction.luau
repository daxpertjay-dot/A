--!strict
-- Controlled destruction. Destructible objects are Models (or Parts) with
-- attributes:
--
--   DestructibleObject
--   ├── Health / MaxHealth
--   ├── Tier                 1 Breakable · 2 Heavy · 3 Major · 4 Indestructible
--   ├── Material             (visual)
--   ├── ExplosionResistance  0-100 (% of explosion damage ignored)
--   ├── CollisionDamage      damage a normal player impact deals
--   └── DestructionEffect    "Bricks" | "Shatter"
--
-- Damage → Health → Destruction State. The server is authoritative: it removes
-- bricks and marks the object Destroyed, then sends the removed pieces to the
-- run owner's client, which simulates the flying debris locally (so the
-- server never has hundreds of physics parts in flight).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Destruction = {}

export type DebrisPiece = { cf: CFrame, size: Vector3, color: Color3, material: Enum.Material }

Destruction.TierDefaults = {
	[1] = { Health = 10, ExplosionResistance = 0, CollisionDamage = 100 },
	[2] = { Health = 60, ExplosionResistance = 30, CollisionDamage = 20 },
	[3] = { Health = 100, ExplosionResistance = 80, CollisionDamage = 20 },
	[4] = { Health = math.huge, ExplosionResistance = 100, CollisionDamage = 0 },
} :: { [number]: { Health: number, ExplosionResistance: number, CollisionDamage: number } }

local rng = Random.new()

-- Marks an instance as destructible with tier defaults.
function Destruction.Setup(object: Instance, tier: number, effect: string?, materialName: string?)
	local defaults = Destruction.TierDefaults[tier]
	object:SetAttribute("Tier", tier)
	object:SetAttribute("MaxHealth", defaults.Health)
	object:SetAttribute("Health", defaults.Health)
	object:SetAttribute("ExplosionResistance", defaults.ExplosionResistance)
	object:SetAttribute("CollisionDamage", defaults.CollisionDamage)
	object:SetAttribute("DestructionEffect", effect or "Shatter")
	object:SetAttribute("Material", materialName or "Wood")
	object:SetAttribute("Destroyed", false)
end

-- Builds a wall out of a grid of bricks so it can be chipped away.
function Destruction.BrickWall(parent: Instance, cf: CFrame, size: Vector3, brick: Vector3, color: Color3, material: Enum.Material): Model
	local model = Instance.new("Model")
	model.Name = "BrickWall"
	local cols = math.max(1, math.floor(size.X / brick.X))
	local rows = math.max(1, math.floor(size.Y / brick.Y))
	local bw, bh = size.X / cols, size.Y / rows
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			-- Offset every other row a bit for a brick-bond look
			local shade = 0.85 + rng:NextNumber() * 0.2
			Util.Part({
				Name = "Brick",
				Parent = model,
				Size = Vector3.new(bw - 0.05, bh - 0.05, size.Z),
				CFrame = cf * CFrame.new(-size.X / 2 + bw * (col + 0.5), -size.Y / 2 + bh * (row + 0.5), 0),
				Color = Color3.new(math.min(1, color.R * shade), math.min(1, color.G * shade), math.min(1, color.B * shade)),
				Material = material,
			})
		end
	end
	model.Parent = parent
	return model
end

local function piecesOf(object: Instance): { BasePart }
	local list = {}
	if object:IsA("BasePart") then
		table.insert(list, object)
	end
	for _, d in object:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Rubble" and d.Name ~= "StandTop" then
			table.insert(list, d)
		end
	end
	return list
end

local function toDebris(part: BasePart): DebrisPiece
	return { cf = part.CFrame, size = part.Size, color = part.Color, material = part.Material }
end

-- Splits a solid part into a few chunks for the debris burst.
local function shatter(part: BasePart, count: number): { DebrisPiece }
	local out = {}
	local s = part.Size
	for _ = 1, count do
		local chunk = Vector3.new(s.X * rng:NextNumber(0.2, 0.45), s.Y * rng:NextNumber(0.2, 0.45), s.Z * rng:NextNumber(0.3, 0.6))
		local offset = Vector3.new(rng:NextNumber(-0.4, 0.4) * s.X, rng:NextNumber(-0.4, 0.4) * s.Y, rng:NextNumber(-0.3, 0.3) * s.Z)
		table.insert(out, { cf = part.CFrame * CFrame.new(offset), size = chunk, color = part.Color, material = part.Material })
	end
	return out
end

local function sendDebris(owner: Player?, object: Instance, pieces: { DebrisPiece }, impact: Vector3, force: number)
	if not owner or #pieces == 0 then
		return
	end
	local capped = {}
	for i = 1, math.min(#pieces, Config.Destruction.MaxDebrisPerEvent) do
		capped[i] = pieces[i]
	end
	-- `object` lets the client skip debris it already predicted locally.
	Remotes.Event("RunDebris"):FireClient(owner, capped, impact, force, object)
end

-- Leaves a pile of flat, non-colliding rubble where an object stood.
local function leaveRubble(object: Instance, center: Vector3, width: number, color: Color3)
	for _ = 1, 4 do
		Util.Part({
			Name = "Rubble",
			Parent = object,
			Size = Vector3.new(rng:NextNumber(1, 2.5), rng:NextNumber(0.3, 0.8), rng:NextNumber(1, 2.5)),
			CFrame = CFrame.new(center.X + rng:NextNumber(-width / 2, width / 2), center.Y + 0.3, center.Z + rng:NextNumber(-1.5, 1.5))
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			Color = color,
			Material = Enum.Material.Slate,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Applies damage. Returns true if the object was destroyed by this hit.
function Destruction.ApplyDamage(object: Instance, amount: number, impact: Vector3, owner: Player?, force: number?): boolean
	if object:GetAttribute("Destroyed") then
		return false
	end
	local tier = object:GetAttribute("Tier") or 4
	if tier >= 4 or amount <= 0 then
		return false
	end
	local maxHealth = object:GetAttribute("MaxHealth") or 100
	local health = (object:GetAttribute("Health") or maxHealth) - amount
	object:SetAttribute("Health", math.max(0, health))

	local parts = piecesOf(object)
	if #parts == 0 then
		return false
	end
	local effect = object:GetAttribute("DestructionEffect") or "Shatter"
	local debris: { DebrisPiece } = {}

	if health <= 0 then
		-- Destroyed: everything goes flying, rubble stays behind.
		object:SetAttribute("Destroyed", true)
		for _, d in object:GetDescendants() do
			if d.Name == "StandTop" then
				d:Destroy() -- nothing left to stand on
			end
		end
		local color = parts[1].Color
		local ground = math.huge
		local minX, maxX = math.huge, -math.huge
		local sumZ = 0
		for _, p in parts do
			ground = math.min(ground, p.Position.Y - p.Size.Y / 2)
			minX = math.min(minX, p.Position.X - p.Size.X / 2)
			maxX = math.max(maxX, p.Position.X + p.Size.X / 2)
			sumZ += p.Position.Z
			if effect == "Bricks" then
				table.insert(debris, toDebris(p))
			else
				for _, piece in shatter(p, 3) do
					table.insert(debris, piece)
				end
			end
			p:Destroy()
		end
		-- Sort so the pieces nearest the impact are the ones simulated.
		table.sort(debris, function(a, b)
			return (a.cf.Position - impact).Magnitude < (b.cf.Position - impact).Magnitude
		end)
		leaveRubble(object, Vector3.new((minX + maxX) / 2, ground, sumZ / #parts), maxX - minX, color)
		sendDebris(owner, object, debris, impact, force or 60)
		return true
	end

	-- Damaged: knock out the bricks closest to the impact in proportion to
	-- the damage dealt, leaving a visible hole.
	if effect == "Bricks" then
		local toRemove = math.max(1, math.floor(#parts * (amount / maxHealth)))
		table.sort(parts, function(a, b)
			return (a.Position - impact).Magnitude < (b.Position - impact).Magnitude
		end)
		for i = 1, math.min(toRemove, #parts - 1) do
			table.insert(debris, toDebris(parts[i]))
			parts[i]:Destroy()
		end
		sendDebris(owner, object, debris, impact, (force or 40) * 0.6)
	end
	return false
end

-- Destroys every destructible within `radius` of `center` whose tier is at
-- or below `maxTier`; stronger objects only take resisted damage.
function Destruction.Explode(root: Instance, center: Vector3, radius: number, maxTier: number, owner: Player?): number
	local destroyed = 0
	-- Collect targets first: damaging one removes parts we'd otherwise still
	-- be iterating over.
	local targets = {}
	for _, d in root:GetDescendants() do
		if d:GetAttribute("Tier") and not d:GetAttribute("Destroyed") then
			table.insert(targets, d)
		end
	end
	for _, d in targets do
		local tier = d:GetAttribute("Tier")
		if not d:GetAttribute("Destroyed") then
			local position: Vector3? = nil
			if d:IsA("Model") then
				local ok, cf = pcall(function()
					return (d :: Model):GetBoundingBox()
				end)
				position = if ok then cf.Position else nil
			elseif d:IsA("BasePart") then
				position = d.Position
			end
			if position and (position - center).Magnitude <= radius then
				if tier <= maxTier then
					if Destruction.ApplyDamage(d, math.huge, center, owner, 110) then
						destroyed += 1
					end
				elseif tier < 4 then
					local resistance = (d:GetAttribute("ExplosionResistance") or 0) / 100
					Destruction.ApplyDamage(d, 80 * (1 - resistance), center, owner, 80)
				end
			end
		end
	end
	return destroyed
end

return Destruction
