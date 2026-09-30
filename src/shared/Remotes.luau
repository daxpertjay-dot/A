--!strict
-- Declares every remote used by the game. The server creates them on startup;
-- clients wait for them. Use Remotes.Event(name) / Remotes.Function(name).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- server → client
	"DataUpdated", -- (snapshot) full profile snapshot for UI
	"Notify", -- (text, color?) toast message
	"RunStarting", -- () fade to "RUN STARTING..."
	"RunPrepare", -- (runInfo) sets up the client run controller
	"RunWorld", -- (event) world events: Destroyed, Explosion, ItemCollected
	"RunDebris", -- (pieces) client-side debris to simulate
	"RunCaught", -- (reviveInfo) the player was caught; offer revive
	"RunRevived", -- () continue running
	"RunEnded", -- (results) rewards screen
	"ReturnedToLobby", -- ()

	-- client → server
	"ReportHit", -- (object, impactInfo)
	"CollectCoin", -- (coinPart)
	"PickupItem", -- (pickupPart)
	"UseEquipment", -- (slotIndex)
	"ReportCaught", -- ()
	"ChooseRevive", -- (useRevive: boolean)
	"LeaveResults", -- () back to lobby from the rewards screen
	"EncounterBrainrot", -- (brainrotId)
}

local FUNCTIONS = {
	"GetData",
	"BuyCrate", -- (crateId, currency "Coins"|"Robux")
	"OpenCrate", -- (crateId) -> rolled item
	"EquipItem", -- (slotIndex, itemId?)
	"ClaimDaily",
	"GetLeaderboards",
	"BuyCoinPack", -- (productKey)
}

local Remotes = {}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in EVENTS do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		for _, name in FUNCTIONS do
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Remotes.Init()
	getFolder()
end

return Remotes
