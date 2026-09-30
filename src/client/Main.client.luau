--!strict
-- Client entry point. Switches between the two halves of the game:
--   LOBBY: free Roblox movement, stations, lobby FX, lobby UI
--   RUN:   custom run controller + camera + Sahur + run HUD

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BiomeData = require(Shared.BiomeData)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Buddy = require(script.Parent.Buddy)
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

-- Each biome has its own sky: fog colour, ambient light and time of day.
-- Fog also hides the far end of the generated track.
local lobbyLighting = {
	ClockTime = Lighting.ClockTime,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
}

local function setBiomeLighting(biome: any)
	local l = biome.lighting
	TweenService:Create(Lighting, TweenInfo.new(1.5), {
		FogColor = l.fog,
		OutdoorAmbient = l.ambient,
		ClockTime = l.clockTime,
		Brightness = l.brightness,
	}):Play()
	Lighting.FogStart = 220
	Lighting.FogEnd = 650
end

local function setRunAtmosphere(enabled: boolean)
	if enabled then
		setBiomeLighting(BiomeData.At(0))
	else
		Lighting.FogStart = 0
		Lighting.FogEnd = 100000
		for key, value in lobbyLighting do
			(Lighting :: any)[key] = value
		end
	end
end

local function applyData(snapshot: any)
	if not snapshot then
		return
	end
	LobbyUI.SetData(snapshot)
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
	Buddy.Start(info.buddy)
	RunCamera.Start()
	RunCamera.PlayIntro(Config.Run.IntroDuration, Chaser.Position)
	playSound(Config.Sounds.Tung, 0.9)

	RunHUD.SetBiome(BiomeData.At(0), false)
	RunHUD.Big("🪵 TUNG TUNG TUNG SAHUR 🪵", Color3.fromRGB(255, 200, 120), Config.Run.IntroDuration - 0.2)

	-- After the intro: the head start cannon offer in the starting area.
	task.delay(Config.Run.IntroDuration, function()
		Chaser.EndIntro()
		if RunController.State.phase ~= "Intro" then
			return
		end
		RunHUD.ShowCannon(info, function(currency)
			local res = Remotes.Function("BuyHeadStart"):InvokeServer(currency)
			if type(res) == "table" and res.ok and res.index then
				RunHUD.PlaySpin(res.index, res.meters, function()
					Remotes.Event("RunReady"):FireServer()
				end)
			elseif type(res) == "table" and not res.ok then
				RunHUD.CannonFailed(res.message)
			end
		end, function()
			Remotes.Event("RunReady"):FireServer()
		end)
	end)
end)

-- Robux cannon spins come back asynchronously.
Remotes.Event("HeadStartResult").OnClientEvent:Connect(function(res)
	if type(res) == "table" and res.ok then
		RunHUD.PlaySpin(res.index, res.meters, function()
			Remotes.Event("RunReady"):FireServer()
		end)
	end
end)

-- The server starts the countdown (after RUN!, a spin, or the timer).
Remotes.Event("RunGo").OnClientEvent:Connect(function(go)
	local goClock = os.clock() + math.max(0, go.goServerTime - workspace:GetServerTimeNow())
	RunHUD.Countdown(goClock, go.headStart or 0, function()
		if (go.headStart or 0) > 0 then
			playSound(Config.Sounds.Explosion)
			local startArea = RunController.WorldPosition() + Vector3.new(0, 5, 9)
			DebrisFX.Explosion(startArea, 10)
		else
			playSound(Config.Sounds.Go)
		end
		RunController.Go(go.headStart)
	end)
end)

RunController.BiomeChanged:Connect(function(biome)
	setBiomeLighting(biome)
	RunHUD.SetBiome(biome, true)
end)

RunController.Landed:Connect(function()
	RunHUD.Big("🎯 LANDED!", Color3.fromRGB(255, 200, 60), 0.9)
end)

-- ───────────────────────────── during the run ─────────────────────────────

Remotes.Event("RunWorld").OnClientEvent:Connect(function(event)
	RunController.HandleWorldEvent(event)
	if event.type == "EquipmentUsed" and event.ability == "Bomb" then
		playSound(Config.Sounds.Explosion)
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
	RunHUD.Big("🪵 BONK!", Color3.fromRGB(255, 90, 90), 1)
	playSound(Config.Sounds.Tung, 1)
end)

Remotes.Event("RunCaught").OnClientEvent:Connect(function(info)
	RunHUD.ShowCaught(info)
end)

Remotes.Event("RunRevived").OnClientEvent:Connect(function()
	RunHUD.HideCaught()
	Chaser.SetCaught(false)
	RunController.Revive()
end)

-- ───────────────────────────── run → rewards → lobby ─────────────────────────────

Remotes.Event("RunEnded").OnClientEvent:Connect(function(results)
	RunController.Stop()
	RunHUD.ShowResults(results)
end)

local function backToLobby()
	inRun = false
	RunController.Stop()
	RunCamera.Stop()
	Chaser.Stop()
	Buddy.Stop()
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
Remotes.Event("CrateRevealed").OnClientEvent:Connect(function(reveal)
	LobbyUI.Reveal(reveal)
end)
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
