--!strict
-- Client entry point. Switches between the two halves of the game:
--   LOBBY: free Roblox movement, your base, upgrade shop, lobby UI
--   RUN:   custom run controller + camera + the villain chase + run HUD

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Chaser = require(script.Parent.Chaser)
local DebrisFX = require(script.Parent.DebrisFX)
local InputController = require(script.Parent.InputController)
local LobbyFX = require(script.Parent.LobbyFX)
local RunCamera = require(script.Parent.RunCamera)
local RunController = require(script.Parent.RunController)
local LobbyUI = require(script.Parent.UI.LobbyUI)
local RunHUD = require(script.Parent.UI.RunHUD)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

InputController.Init()
DebrisFX.Init()
LobbyFX.Init()
LobbyUI.Init(playerGui)
RunHUD.Init(playerGui)

local inRun = false

local function controls(): any?
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(playerModule):GetControls()
	end)
	return if ok then module else nil
end

local function playSound(id: string, volume: number?)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- Runs happen at night in Verity's rail yard: dark sky, toxic green haze.
local lobbyLighting = {
	ClockTime = Lighting.ClockTime,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
	FogColor = Lighting.FogColor,
}

local function setRunAtmosphere(enabled: boolean)
	if enabled then
		TweenService:Create(Lighting, TweenInfo.new(1), {
			ClockTime = 20.5,
			OutdoorAmbient = Color3.fromRGB(110, 100, 140),
			Brightness = 2,
			FogColor = Color3.fromRGB(40, 55, 45),
		}):Play()
		Lighting.FogStart = 200
		Lighting.FogEnd = 620
	else
		Lighting.FogStart = 0
		Lighting.FogEnd = 100000
		for key, value in lobbyLighting do
			(Lighting :: any)[key] = value
		end
	end
end

local function applyData(snapshot: any)
	if snapshot then
		LobbyUI.SetData(snapshot)
	end
end

-- ───────────────────────────── lobby → run ─────────────────────────────

Remotes.Event("RunStarting").OnClientEvent:Connect(function()
	inRun = true
	LobbyUI.SetVisible(false)
	RunHUD.ShowStarting()
	local c = controls()
	if c then
		c:Disable()
	end
end)

Remotes.Event("RunPrepare").OnClientEvent:Connect(function(info)
	if not RunController.Prepare(info) then
		warn("[BrainrotRunner] could not set up the run controller")
		return
	end
	LobbyFX.SetEnabled(false)
	setRunAtmosphere(true)
	RunHUD.Prepare(info)
	Chaser.Start()
	Chaser.PlayIntro()
	RunCamera.Start()
	RunCamera.PlayIntro(Config.Run.IntroDuration, Chaser.Position)
	playSound(Config.Sounds.Villain, 0.9)
	RunHUD.Big(("☣️ %s IS COMING ☣️"):format(Config.Villain.Title), Color3.fromRGB(150, 255, 110), Config.Run.IntroDuration - 0.2)

	-- Convert the server's go time into local clock time.
	local goClock = os.clock() + math.max(0, info.goServerTime - workspace:GetServerTimeNow())
	task.delay(Config.Run.IntroDuration, Chaser.EndIntro)
	RunHUD.Countdown(goClock, function()
		playSound(Config.Sounds.Go)
		RunController.Go()
	end)
end)

-- ───────────────────────────── during the run ─────────────────────────────

Remotes.Event("RunWorld").OnClientEvent:Connect(function(event)
	RunController.HandleWorldEvent(event)
	if event.type == "PowerUp" or event.type == "Hoverboard" or event.type == "MysteryBox" then
		playSound(Config.Sounds.PowerUp)
	end
end)

RunController.Impact:Connect(function(outcome: string)
	if outcome ~= "Side" then
		playSound(Config.Sounds.Crash, 0.5)
	end
end)

RunController.CoinCollected:Connect(function()
	playSound(Config.Sounds.Coin, 0.3)
end)

RunController.Caught:Connect(function()
	Chaser.SetCaught(true)
	RunHUD.Big("☣️ GOTCHA!", Color3.fromRGB(255, 90, 90), 1)
	playSound(Config.Sounds.Villain, 1)
end)

Remotes.Event("RunCaught").OnClientEvent:Connect(function(info)
	RunHUD.ShowCaught(info)
end)

Remotes.Event("RunRevived").OnClientEvent:Connect(function()
	RunHUD.HideCaught()
	Chaser.SetCaught(false)
	RunController.Revive()
end)

-- ───────────────────────────── run → results → base ─────────────────────────────

Remotes.Event("RunEnded").OnClientEvent:Connect(function(results)
	RunController.Stop()
	RunHUD.ShowResults(results)
end)

local function backToLobby()
	inRun = false
	RunController.Stop()
	RunCamera.Stop()
	Chaser.Stop()
	RunHUD.Hide()
	setRunAtmosphere(false)
	LobbyFX.SetEnabled(true)
	LobbyUI.SetVisible(true)
	local c = controls()
	if c then
		c:Enable()
	end
end

Remotes.Event("ReturnedToLobby").OnClientEvent:Connect(backToLobby)

-- If the character respawns mid-run (reset, etc.) make sure lobby controls come back
-- once the server has ended the run.
player.CharacterAdded:Connect(function()
	if not inRun then
		backToLobby()
	end
end)

-- ───────────────────────────── data / notifications ─────────────────────────────

Remotes.Event("DataUpdated").OnClientEvent:Connect(applyData)
Remotes.Event("Notify").OnClientEvent:Connect(function(text: string, color: Color3?)
	if inRun then
		RunHUD.Flash(text, color)
	else
		LobbyUI.Toast(text, color)
	end
end)

task.spawn(function()
	applyData(Remotes.Function("GetData"):InvokeServer())
end)

if Config.Sounds.LobbyMusic ~= "" then
	local music = Instance.new("Sound")
	music.SoundId = Config.Sounds.LobbyMusic
	music.Looped = true
	music.Volume = 0.3
	music.Parent = SoundService
	music:Play()
end
