local H = require("./harness")
local roblox = require("@lune/roblox")
local function sig() return { Connect = function() return { Disconnect = function() end } end, Once = function() end } end
local services = H.services
services.TweenService = { Create = function() return { Play = function() end, Completed = sig() } end }
services.ProximityPromptService = { PromptTriggered = sig() }
services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = sig(), InputChanged = sig(), InputEnded = sig() }
services.RunService.RenderStepped = sig()
services.RunService.BindToRenderStep = function() end
services.RunService.UnbindFromRenderStep = function() end
services.Debris = { AddItem = function() end }
services.Players.LocalPlayer = { Character = nil }
local calls = {}
H.remotes.Function = function(name) return { InvokeServer = function() calls[name] = true; return name == "GetLeaderboards" and { { title = "🏆 TOP RUNS", suffix = "m", entries = { { rank = 1, name = "Jay", value = 71882 } } } } or { ok = true } end } end
H.remotes.Event = function(name) return { FireServer = function() end, OnClientEvent = sig() } end

local client = H.node(H.root .. "/client", nil, "Client")
local gui = roblox.Instance.new("Folder")
local LobbyUI = H.require(client.UI.LobbyUI)
LobbyUI.Init(gui)
local snapshot = {
	Coins = 1234, Brainrots = { ChimpanziniBananini = 1, TralaleroTralala = 2, TrippiTroppi = 1, ["TrippiTroppi:Rainbow"] = 1, ["TralaleroTralala:Gold"] = 2 }, Collection = { ChimpanziniBananini = true, TralaleroTralala = true, TrippiTroppi = true },
	Pedestals = 3, Displayed = { "TrippiTroppi:Rainbow", "TralaleroTralala:Gold", "TralaleroTralala:Gold" }, Multiplier = 10,
	Upgrades = { Magnet = 2, Jetpack = 5, SuperSneakers = 0, ScoreBooster = 1 }, Hoverboards = 3,
	Stats = { HighScore = 123456, BestDistance = 2000, TotalCoins = 5000, TotalRuns = 7, LongestSurvival = 300, BrainrotsRescued = 4, TotalDistance = 100000 },
	Daily = { LastClaimDay = 19000, Streak = 3 }, Today = 19001,
	BrainrotXP = { TrippiTroppi = 9000, TralaleroTralala = 100 }, Hype = 0.42, HypePerHour = 0.3,
}
LobbyUI.SetData(snapshot)
for _, name in { "Upgrades", "Brainrots", "Shop", "Leaderboard", "Daily", "Stats" } do
	LobbyUI.Open(name)
	print("panel ok", name)
end
LobbyUI.Toast("hello")
snapshot.Hype = 1; LobbyUI.SetData(snapshot)
local RunController = H.require(client.RunController)
local RunHUD = H.require(client.UI.RunHUD)
RunHUD.Init(gui)
RunHUD.ShowStarting()
RunHUD.Prepare({ multiplier = 10, highScore = 5000, hype = 0.8 })
RunController.Style:Fire("NearMiss", 2)
RunController.Style:Fire("Crash", 0)
RunHUD.Countdown(os.clock(), function() print("go fired") end)
RunHUD.ShowCaught({ canRevive = true, cost = 200, bankCoins = 100, robux = true, timeout = 10, score = 999 })
RunHUD.HideCaught()
RunHUD.ShowCaught({ canRevive = false, cost = 400, bankCoins = 100, robux = false, timeout = 10, score = 1999 })
RunHUD.ShowResults({ score = 12345, newHighScore = true, highScore = 12345, distance = 1200, multiplier = 10, newMultiplier = 12, coins = 80, boxCoins = 250, boxBoards = 1, totalCoins = 330, survival = 40, revives = 1, rescued = { { id = "X", label = "🌈 Rainbow Tralalero", icon = "🦈", bonus = 12.5, isNew = true } }, pedestals = 3, bestCombo = 2.37, hypeStart = 1, hypeLeft = 0.2, xp = 12345, levelUps = { { name = "Trippi Troppi", icon = "🦐", from = 2, to = 3, bonus = 7.5 } } })
RunHUD.ShowResults({ score = 10, newHighScore = false, highScore = 12345, distance = 10, multiplier = 10, newMultiplier = 10, coins = 1, boxCoins = 0, boxBoards = 0, totalCoins = 1, survival = 4, revives = 0, rescued = {}, pedestals = 3 })
RunHUD.Hide()
-- Lobby outlines: on structures, not on the ground tiles or see-through parts.
local lobby = roblox.Instance.new("Folder"); lobby.Name = "Lobby"
local groundModel = roblox.Instance.new("Model"); groundModel.Name = "Ground"; groundModel.Parent = lobby
local grass = roblox.Instance.new("Part"); grass.Name = "Grass"; grass.Parent = groundModel
local post = roblox.Instance.new("Part"); post.Name = "FencePost"; post.Parent = lobby
local glass = roblox.Instance.new("Part"); glass.Transparency = 1; glass.Parent = lobby
lobby.Parent = H.workspace
H.require(client.LobbyFX).Init()
require("@lune/task").wait(0.1)
assert(post:FindFirstChild("Outline") and post.Outline:IsA("SelectionBox"), "structures get a black outline")
assert(not grass:FindFirstChild("Outline") and not glass:FindFirstChild("Outline"), "ground and invisible parts don't")
print("UI OK", #gui:GetDescendants())
require("@lune/process").exit(0)
