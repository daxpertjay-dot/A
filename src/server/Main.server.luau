--!strict
-- Server entry point for Brainrot Runner.
--   Lobby = progression / social / collection (persistent)
--   Run   = gameplay / risk / rewards (generated per player)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

Remotes.Init()

local PlayerData = require(script.Parent.PlayerData)
local Economy = require(script.Parent.Economy)
local Leaderboards = require(script.Parent.Leaderboards)
local LobbyBuilder = require(script.Parent.Lobby.LobbyBuilder)
local RunManager = require(script.Parent.Run.RunManager)

Players.RespawnTime = 2

LobbyBuilder.Build()
PlayerData.Init()
Economy.Init()
Leaderboards.Init()
RunManager.Init()

Economy.OnReviveProductPurchased = function(player: Player): boolean
	if RunManager.Revive(player, true) then
		return true
	end
	-- The run already ended: refund the revive as coins so the purchase isn't lost.
	PlayerData.AddCoins(player, 300)
	return true
end

-- Hidden lobby collectibles (secret areas).
local function hookSecret(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local profile = player and PlayerData.Get(player)
		if not player or not profile then
			return
		end
		local secretId = part:GetAttribute("SecretId") or part.Name
		if profile.Secrets[secretId] then
			return
		end
		profile.Secrets[secretId] = true
		profile.Coins += part:GetAttribute("Reward") or 500
		PlayerData.Changed(player)
		Remotes.Event("Notify"):FireClient(player, ("🤫 SECRET FOUND! +%d coins"):format(part:GetAttribute("Reward") or 500), Color3.fromRGB(255, 220, 90))
	end)
end
for _, part in CollectionService:GetTagged("SecretCollectible") do
	hookSecret(part)
end
CollectionService:GetInstanceAddedSignal("SecretCollectible"):Connect(hookSecret)
