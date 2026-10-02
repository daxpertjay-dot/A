local H = require("./harness")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local function sig(store, key)
	return { Connect = function(_, fn) if store then store[key] = fn end; return { Disconnect = function() end } end, Once = function() end }
end
local handlers, clientEvents, worldEvents = {}, {}, {}
H.remotes.Event = function(name)
	return {
		FireClient = function(_, player, ...)
			clientEvents[name] = { ... }
			if name == "RunWorld" then table.insert(worldEvents, (...)) end
			if name ~= "DataUpdated" then print("  → client", name, name == "RunWorld" and (...).type or "") end
		end,
		FireAllClients = function(_, ...)
			clientEvents[name] = { ... }
			print("  → everyone", name, (...))
		end,
		OnServerEvent = sig(handlers, name),
	}
end
local fnTables = {}
H.remotes.Function = function(name) fnTables[name] = fnTables[name] or {}; return fnTables[name] end
local services = H.services
local playerAdded = {}
services.Players.PlayerAdded = sig(playerAdded, "fn")
services.Players.PlayerRemoving = sig(playerAdded, "removing")
services.Players.GetPlayerFromCharacter = function() return nil end
services.Players.GetPlayers = function() return {} end
services.Players.RespawnTime = 0
local heartbeat = {}
services.RunService.Heartbeat = sig(heartbeat, "fn")
services.MarketplaceService = { PromptProductPurchase = function() print("  prompt purchase") end }
roblox.implementMethod("Folder", "GetServerTimeNow", function() return os.clock() end)

local player = roblox.Instance.new("Player")
player.Name = "Jay"; player.DisplayName = "Jay"; player.UserId = 12345
player.Parent = roblox.Instance.new("Folder")
roblox.implementMethod("Player", "Kick", function(_, msg) error("kicked: " .. msg) end)
roblox.implementMethod("Player", "RequestStreamAroundAsync", function() end)
local loadCount = 0
roblox.implementMethod("Player", "LoadCharacter", function() loadCount += 1 end)
local character = roblox.Instance.new("Model")
local root = roblox.Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Parent = character
local hum = roblox.Instance.new("Humanoid"); hum.Parent = character; hum.Health = 100
character.PrimaryPart = root
player.Character = character

-- Start with the saved lobby map in Workspace, as in the real place.
local fs = require("@lune/fs")
local map = roblox.deserializeModel(fs.readFile("map/Lobby.rbxm"))[1]
map.Parent = H.workspace

-- An imported Blender tree in ServerStorage.LobbyProps, in centimetres (100x
-- too big): it replaces every blocky tree in the map, sized to match.
local props = roblox.Instance.new("Folder"); props.Name = "LobbyProps"
local meshTree = roblox.Instance.new("Model"); meshTree.Name = "Tree"; meshTree.Parent = props
for _, spec in { { "Trunk", 200, 1100 }, { "Leaves", 1000, 800 }, { "Outline", 1040, 1940 } } do
	local p = roblox.Instance.new("Part"); p.Name = spec[1]; p.Size = Vector3.new(spec[2], spec[3], spec[2])
	p.CFrame = CFrame.new(0, spec[3] / 2, 0); p.Parent = meshTree
end
meshTree.PrimaryPart = meshTree.Trunk
local blockyTrees = 0
for _, d in map:GetDescendants() do if d:IsA("Model") and d.Name == "Tree" then blockyTrees += 1 end end
H.services.ServerStorage.FindFirstChild = function(_, name) return if name == "LobbyProps" then props else nil end

local Main = H.node(H.root .. "/server", nil, "Server")
H.require(Main.Main)
local swapped, wrongSize = 0, 0
for _, d in map:GetDescendants() do
	if d:IsA("Model") and d.Name == "Tree" then
		assert(d:GetAttribute("CustomProp"), "every blocky tree is swapped")
		swapped += 1
		local _, size = d:GetBoundingBox()
		if size.Y < 15 or size.Y > 40 then wrongSize += 1 end
		assert(d.Outline.CanCollide == false and d.Outline.Color == roblox.Color3.new(0, 0, 0), "outline shell set up")
		assert(d.Leaves.Color == H.require(H.shared.Config).Lobby.PropColors.Leaves, "meshes painted by name")
	end
end
print("swapped trees", swapped, "of", blockyTrees, "wrong size", wrongSize)
assert(swapped == blockyTrees and swapped > 0 and wrongSize == 0)
playerAdded.fn(player)
local PlayerData = H.require(Main.PlayerData)
local profile = assert(PlayerData.Get(player), "profile not loaded")
-- The map's own bases were used (not rebuilt), and the player got one.
local plots = 0
for _, child in map:GetChildren() do
	if child.Name:match("^Plot%d+$") then plots += 1 end
end
assert(plots == 8, "the saved map's 8 bases are used, none added")
assert(#map.Plot1.Dynamic:GetChildren() > 0, "the player's Brainrots stand in their base")
assert(map.Plot1.RunEntranceTrigger:GetAttribute("OwnerUserId") == player.UserId, "the base's portal belongs to the player")
print("new profile: coins", profile.Coins, "boards", profile.Hoverboards, "pedestals", profile.Pedestals, "multiplier", PlayerData.Multiplier(profile))

local function inv(name, ...) local r = fnTables[name].OnServerInvoke(player, ...); print(name, r.ok, r.message or r.level or r.pedestals or r.hoverboards or ""); return r end
inv("BuyUpgrade", "Jetpack")
profile.Coins = 100000
inv("BuyUpgrade", "Jetpack"); inv("BuyUpgrade", "Jetpack")
inv("BuyPedestal"); inv("BuyHoverboards", "Coins"); inv("BuyHoverboards", "Robux")
inv("ClaimDaily"); inv("ClaimDaily")
profile.Brainrots.TrippiTroppi = 2
PlayerData.Changed(player)
print("multiplier with 2 Trippi + Chimp:", PlayerData.Multiplier(profile), "coins", profile.Coins, "boards", profile.Hoverboards)
-- Hype: offline charging
print("new player hype", profile.Hype)
profile.Hype = 0; profile.HypeUpdated = os.time() - 4 * 3600
local added = PlayerData.ChargeHype(profile, false)
print(("4h offline at multiplier %s → hype %.3f"):format(tostring(PlayerData.Multiplier(profile)), profile.Hype))
profile.Hype = 1

local RunManager = H.require(Main.Run.RunManager)
RunManager.StartRun(player)
task.wait(1.3)
local prep = assert(clientEvents.RunPrepare, "no RunPrepare")[1]
print("prepare multiplier", prep.multiplier, "boards", prep.hoverboards, "hype", prep.hype, "area", prep.area)
assert(prep.area == "Garden", "runs start in the first area")
task.wait(prep.goServerTime - os.clock() + 0.1)
local runs = nil
for i = 1, 360 do
	root.CFrame = CFrame.new(prep.origin + Vector3.new(0, 3, -(6 + i * (300 / 360))))
	heartbeat.fn(1 / 60)
end
-- tricks: a valid clear, the same one again (rejected), one far away (rejected)
local near, far
for _, d in prep.trackFolder:GetDescendants() do
	local td = d:GetAttribute("TrackD")
	if td and not d:GetAttribute("NoStyle") then
		if not near and td > 270 and td < 318 and d:GetAttribute("ObstacleType") then near = d end
		if not far and td > 600 then far = d end
	end
end
local nWorld = #worldEvents
if near then handlers.ReportStyle(player, "Clear", near); task.wait(0.15); handlers.ReportStyle(player, "Clear", near) end
if far then task.wait(0.15); handlers.ReportStyle(player, "NearMiss", far) end
handlers.ReportStyle(player, "Bogus", near)
local combos = 0
for i = nWorld + 1, #worldEvents do if worldEvents[i].type == "Combo" then combos += 1 end end
print("trick reports accepted:", combos, "(expected 1)", "near", near ~= nil, "far", far ~= nil)
local function place(attrs)
	local p = roblox.Instance.new("Part")
	p.CFrame = root.CFrame
	for k, v in attrs do p:SetAttribute(k, v) end
	p.Parent = prep.trackFolder
	return p
end
handlers.PickupItem(player, place({ Pickup = "PowerUp", PowerUpId = "Jetpack" }))
local sky = 0
for _, d in prep.trackFolder:GetDescendants() do if d.Parent and d.Parent.Name == "SkyCoins" then sky += 1 end end
print("sky coins spawned", sky)
handlers.PickupItem(player, place({ Pickup = "PowerUp", PowerUpId = "ScoreBooster" }))
handlers.PickupItem(player, place({ Pickup = "MysteryBox" }))
handlers.PickupItem(player, place({ Pickup = "Brainrot", BrainrotId = "CappuccinoAssassino", Mutation = "Rainbow" }))
assert(clientEvents.Announce and clientEvents.Announce[1]:find("Rainbow Cappuccino"), "rare rescue announced to the server")
handlers.CollectCoin(player, place({ Coin = true, Value = 1 }))
-- booster: next 100 studs score double
local before = 0
for i = 1, 120 do
	root.CFrame = CFrame.new(prep.origin + Vector3.new(0, 3, -(306 + i * (100 / 120))))
	heartbeat.fn(1 / 60)
end
handlers.UseHoverboard(player)
local wall
for _, d in prep.trackFolder:GetDescendants() do if d:GetAttribute("Tier") == 3 or d:GetAttribute("Kind") == "ConcreteWall" then wall = d break end end
if not wall then for _, d in prep.trackFolder:GetDescendants() do if d:GetAttribute("ObstacleType") and d:GetAttribute("Tier") == 4 then wall = d break end end end
if wall then local cf = wall:GetBoundingBox(); root.CFrame = cf; handlers.ReportHit(player, wall, { speed = 40, point = cf.Position }) end
handlers.ReportCaught(player)
print("caught info", clientEvents.RunCaught[1].cost, clientEvents.RunCaught[1].score)
handlers.ChooseRevive(player, "Coins")
-- Revive shockwave: nothing left standing around the runner.
local revived = assert(clientEvents.RunRevived, "revived")[1]
local RunsFolder = prep.trackFolder
local standing = 0
local reviveD = revived.at
for _, d in RunsFolder:GetDescendants() do
	local td = d:GetAttribute("TrackD")
	if td and d:GetAttribute("ObstacleType") and not d:GetAttribute("Destroyed") and td > reviveD - 30 and td < reviveD + 90 then
		standing += 1
		print("  still standing:", d:GetAttribute("Kind"), td)
	end
end
print(("revive shockwave cleared %d structures; %d still standing near the runner"):format(revived.cleared, standing))
assert(standing == 0, "revive clears the structures around you")
handlers.ReportCaught(player)
handlers.ChooseRevive(player, false)
local r = clientEvents.RunEnded[1]
print(("results: score=%d high=%s distance=%d mult=%s→%s coins=%d box=%d/%d rescued=%d bestCombo=%.2f hype %.2f→%.2f xp=%d levelUps=%d"):format(r.score, tostring(r.newHighScore), r.distance, tostring(r.multiplier), tostring(r.newMultiplier), r.totalCoins, r.boxCoins, r.boxBoards, #r.rescued, r.bestCombo, r.hypeStart, r.hypeLeft, r.xp, #r.levelUps))
for _, up in r.levelUps do print("  level up", up.name, up.from, "→", up.to, "bonus", up.bonus) end
local P = H.require(H.shared.Progression)
for id, xp in profile.BrainrotXP do print("  xp", id, xp, "level", (P.Level(xp))) end
print("profile hype after run", profile.Hype)
assert(profile.Brainrots["CappuccinoAssassino:Rainbow"] == 1, "mutated rescue stored by key")
local P2 = H.require(H.shared.Progression)
local rainbowBonus = PlayerData.BrainrotBonus(profile, "CappuccinoAssassino:Rainbow")
print("rainbow cappuccino bonus", rainbowBonus, "normal would be", P2.Bonus("CappuccinoAssassino", profile.BrainrotXP.CappuccinoAssassino))
assert(math.abs(rainbowBonus - 5 * P2.Bonus("CappuccinoAssassino", profile.BrainrotXP.CappuccinoAssassino)) < 1e-9)
assert(r.rescued[1].label == "🌈 Rainbow Cappuccino Assassino" and r.rescued[1].isNew)
handlers.LeaveResults(player)
print("profile after: highscore", profile.Stats.HighScore, "rescued", profile.Stats.BrainrotsRescued, "boards", profile.Hoverboards, "load", loadCount)
-- Died during the "RUN STARTING..." fade: the run must not carry on starting.
clientEvents.RunPrepare = nil
RunManager.StartRun(player)
task.wait(0.2)
RunManager.EndRun(player, "Died")
task.wait(1.4)
print("died in fade: RunPrepare sent afterwards?", clientEvents.RunPrepare ~= nil, "results sent", clientEvents.RunEnded ~= nil)
assert(clientEvents.RunPrepare == nil)
task.wait(0.6)
clientEvents.ReturnedToLobby = nil
handlers.LeaveResults(player)
print("back to base after dying:", clientEvents.ReturnedToLobby ~= nil, "InRun", player:GetAttribute("InRun"), "running", RunManager.IsRunning(player))
assert(clientEvents.ReturnedToLobby and not RunManager.IsRunning(player) and not player:GetAttribute("InRun"))
-- Leaving in the middle of a run (client couldn't continue) settles it and goes home.
task.wait(2.1)
RunManager.StartRun(player)
task.wait(1.3)
local runsBefore = profile.Stats.TotalRuns
clientEvents.ReturnedToLobby = nil
handlers.LeaveResults(player)
print("left mid-run:", clientEvents.ReturnedToLobby ~= nil, "running", RunManager.IsRunning(player), "runs counted", profile.Stats.TotalRuns - runsBefore)
assert(clientEvents.ReturnedToLobby and not RunManager.IsRunning(player))
-- 🏠 / client fallback: asking for a respawn in the lobby reloads the character.
local loadsBefore = loadCount
handlers.GoToBase(player, "Respawn")
assert(loadCount == loadsBefore + 1, "Respawn request reloads the character")
handlers.GoToBase(player, "Respawn")
assert(loadCount == loadsBefore + 1, "respawn requests are rate limited")
-- BACK TO BASE with no run on the server at all still works.
task.wait(2.1)
clientEvents.ReturnedToLobby = nil
handlers.LeaveResults(player)
assert(clientEvents.ReturnedToLobby, "no run: still sent home")
print("SERVER OK")
require("@lune/process").exit(0)
