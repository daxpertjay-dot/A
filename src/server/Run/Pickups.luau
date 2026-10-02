--!strict
-- Things you pick up on the track: power-up boxes, mystery boxes and caged
-- Brainrots. Section templates only mark where they may go (PickupSpot /
-- CageSpot); the track generator rolls what appears there for each run.
--
-- Every pickup is a non-colliding part with a Pickup attribute ("PowerUp",
-- "MysteryBox", "Brainrot"); the client touches it and the server validates.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BrainrotData = require(Shared.BrainrotData)
local ModelFactory = require(Shared.ModelFactory)
local MutationData = require(Shared.MutationData)
local PowerUpData = require(Shared.PowerUpData)
local Util = require(Shared.Util)

local Pickups = {}

-- A floating box. `at` is the ground point under it.
local function box(parent: Instance, at: Vector3, kind: string, color: Color3, label: string): BasePart
	local part = Util.Part({
		Name = kind .. "Pickup",
		Parent = parent,
		Size = Vector3.new(2.8, 2.8, 2.8),
		CFrame = CFrame.new(at + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	part:SetAttribute("Pickup", kind)
	Util.Billboard(part, label, UDim2.fromOffset(70, 70), Vector3.new(0, 3.2, 0))
	return part
end

-- A power-up box: `id`, or a random one.
function Pickups.PowerUp(parent: Instance, at: Vector3, rng: Random, id: string?)
	local p = (if id then PowerUpData.Get(id) else nil) or PowerUpData.Pick(rng)
	local part = box(parent, at, "PowerUp", p.color, p.icon)
	part:SetAttribute("PowerUpId", p.id)
end

function Pickups.MysteryBox(parent: Instance, at: Vector3)
	box(parent, at, "MysteryBox", Color3.fromRGB(255, 180, 30), "❓")
end

-- A caged Brainrot from `area` (sometimes a mutated one, visible in the cage
-- before you get there). Run through the cage to rescue it: rescued
-- Brainrots go to your base and raise your score multiplier.
function Pickups.Cage(parent: Instance, at: Vector3, area: string, rng: Random): boolean
	local brainrot = BrainrotData.PickCatchable(area, rng)
	if not brainrot then
		return false
	end
	local mutation = MutationData.Roll(rng)
	local key = MutationData.Key(brainrot.id, mutation and mutation.id)
	local color = if mutation then mutation.color else (BrainrotData.RarityColors[brainrot.rarity] or Color3.fromRGB(255, 200, 40))
	local bar = Color3.fromRGB(60, 60, 70)
	-- The pickup is the glowing floor plate; the cage and Brainrot hang off it.
	local plate = Util.Part({
		Name = "BrainrotCage",
		Parent = parent,
		Size = Vector3.new(6.5, 0.4, 6.5),
		CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	plate:SetAttribute("Pickup", "Brainrot")
	plate:SetAttribute("BrainrotId", brainrot.id)
	if mutation then
		plate:SetAttribute("Mutation", mutation.id)
	end
	local function cagePart(name: string, size: Vector3, offset: Vector3)
		Util.Part({ Parent = plate, Name = name, Size = size, CFrame = CFrame.new(at + offset), Color = bar, Material = Enum.Material.Metal, CanCollide = false, CanQuery = false })
	end
	for _, corner in { Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) } do
		cagePart("CageBar", Vector3.new(0.4, 9, 0.4), corner + Vector3.new(0, 4.7, 0))
	end
	for i = -1, 1 do
		-- Bars across the side you run into (forward is -Z).
		cagePart("CageBar", Vector3.new(0.25, 9, 0.25), Vector3.new(i * 1.5, 4.7, 3))
	end
	cagePart("CageTop", Vector3.new(6.8, 0.5, 6.8), Vector3.new(0, 9.3, 0))
	local model = ModelFactory.Brainrot(key, 0.9)
	model:PivotTo(CFrame.new(at + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.pi, 0))
	model.Parent = plate
	local bonus = brainrot.bonus * MutationData.Multiplier(mutation and mutation.id)
	ModelFactory.NameTag(model, ("🔓 RESCUE %s %s  (+%dx)"):format(brainrot.icon, string.upper(MutationData.Label(key)), bonus), color, 12)
	return true
end

return Pickups
