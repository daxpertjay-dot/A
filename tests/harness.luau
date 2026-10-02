-- Headless test harness for Brainrot Runner (Lune). Loads the game's modules
-- from tests/.mirror/src (a copy of src/ made by tests/mirror.py, with
-- `.Position` reads rewritten to __P(), since Lune can't derive a part's
-- Position from its CFrame) and runs them against mocked Roblox services.
-- Run everything with tests/run.sh.
local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local ROOT = process.env.BRAINROT_MIRROR or "tests/.mirror/src"
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

-- ── Instance shims ──────────────────────────────────────────────
for _, cls in { "BasePart", "Part", "WedgePart", "CornerWedgePart", "SpawnLocation", "MeshPart", "TrussPart" } do
	roblox.implementProperty(cls, "Position", function(p) return p.CFrame.Position end, function(p, v) p.CFrame = CFrame.new(v) * p.CFrame.Rotation end)
	roblox.implementMethod(cls, "GetPivot", function(p) return p.CFrame end)
end
local function getPivot(m)
	if m.PrimaryPart then return m.PrimaryPart.CFrame end
	-- (a new Lune model has no WorldPivot until one is set)
	local ok, pivot = pcall(function() return m.WorldPivot end)
	return if ok then pivot else CFrame.new()
end
roblox.implementMethod("Model", "GetPivot", getPivot)
roblox.implementMethod("Model", "PivotTo", function(m, target)
	local delta = target * getPivot(m):Inverse()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end
	m.WorldPivot = delta * getPivot(m)
end)
local scales = {}
roblox.implementMethod("Model", "GetScale", function(m) return scales[m] or 1 end)
-- Scales every part's size and offset from the pivot, like Roblox.
roblox.implementMethod("Model", "ScaleTo", function(m, target)
	local factor = target / (scales[m] or 1)
	local pivot = getPivot(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size *= factor
			d.CFrame = pivot * (CFrame.new(rel.Position * factor) * rel.Rotation)
		end
	end
	scales[m] = target
end)
roblox.implementMethod("Model", "GetBoundingBox", function(m)
	local minV, maxV
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local p, s = d.CFrame.Position, d.Size / 2
			minV = if minV then minV:Min(p - s) else p - s
			maxV = if maxV then maxV:Max(p + s) else p + s
		end
	end
	assert(minV, "GetBoundingBox on empty model")
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)

-- ── Event shims (Lune instances have no events) ─────────────────
local function evt() return { Connect = function() return { Disconnect = function() end } end, Once = function() end, Wait = function() end } end
for cls, events in { Part = { "Touched" }, SpawnLocation = { "Touched" }, WedgePart = { "Touched" }, Player = { "CharacterAdded" }, Humanoid = { "Died" }, TextButton = { "Activated" } } do
	for _, e in events do
		pcall(roblox.implementProperty, cls, e, function() return evt() end)
	end
end
-- Lune instances have no WaitForChild; everything a test needs already exists.
pcall(roblox.implementMethod, "Folder", "WaitForChild", function(self, name) return self:FindFirstChild(name) end)
-- Folder.DescendantAdded: tests fire H.fireAdded(instance) themselves.
local addedHandlers = {}
pcall(roblox.implementProperty, "Folder", "DescendantAdded", function()
	return { Connect = function(_, fn) table.insert(addedHandlers, fn); return { Disconnect = function() end } end, Once = function() end, Wait = function() end }
end)

-- ── Random shim ─────────────────────────────────────────────────
local Random = {}
Random.__index = Random
function Random.new(seed) math.randomseed(seed or os.time()); return setmetatable({}, Random) end
function Random:NextNumber(a, b) a = a or 0; b = b or 1; return a + math.random() * (b - a) end
function Random:NextInteger(a, b) assert(a <= b, "NextInteger min > max"); return math.random(a, b) end

-- ── Service mocks ───────────────────────────────────────────────
local function signal() return { Connect = function() return { Disconnect = function() end } end, Once = function() end, Wait = function() end } end
local tags = {}
local workspaceFolder = roblox.Instance.new("Folder")
workspaceFolder.Name = "Workspace"
local CollectionService = {
	-- Also tag the instance itself, so tags survive when a map is saved (bake).
	AddTag = function(_, inst, tag) tags[tag] = tags[tag] or {}; table.insert(tags[tag], inst); pcall(inst.AddTag, inst, tag) end,
	-- Tagged via AddTag, plus anything tagged in a loaded map (workspace).
	GetTagged = function(_, tag)
		local out, seen = {}, {}
		for _, inst in tags[tag] or {} do
			if not seen[inst] then seen[inst] = true; table.insert(out, inst) end
		end
		for _, inst in workspaceFolder:GetDescendants() do
			if not seen[inst] and inst:HasTag(tag) then seen[inst] = true; table.insert(out, inst) end
		end
		return out
	end,
	GetInstanceAddedSignal = function() return signal() end,
	GetInstanceRemovedSignal = function() return signal() end,
}
local fired = {}
local function remote(name)
	return {
		FireClient = function(_, ...) fired[name] = (fired[name] or 0) + 1 end,
		FireAllClients = function() end,
		OnServerEvent = signal(),
	}
end
local RemotesMock = {
	Event = function(name) return remote(name) end,
	Function = function(name) return {} end,
	Init = function() end,
}

-- ── fake script tree / require ──────────────────────────────────
local cache = {}
local sources = {}
local Node = {}
Node.__index = function(self, key)
	if key == "Parent" then return rawget(self, "__parent") end
	if key == "WaitForChild" or key == "FindFirstChild" then
		return function(me, child) return me[child] end
	end
	error("no child " .. tostring(key) .. " under " .. rawget(self, "__path"))
end
-- Build the whole tree eagerly (fs calls can't run inside metamethods).
local function node(path, parent, name)
	local n = setmetatable({ __path = path, __parent = parent, Name = name }, Node)
	if fs.isDir(path) then
		for _, entry in fs.readDir(path) do
			local childPath = path .. "/" .. entry
			local childName = entry:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", "")
			rawset(n, childName, node(childPath, n, childName))
		end
	else
		sources[path] = fs.readFile(path)
	end
	return n
end

local sharedNode = node(ROOT .. "/shared", nil, "Shared")
local serverNode = node(ROOT .. "/server", nil, "Server")
local ReplicatedStorage = { WaitForChild = function(_, n) assert(n == "Shared"); return sharedNode end, FindFirstChild = function() return nil end }

local services = {
	ReplicatedStorage = ReplicatedStorage,
	CollectionService = CollectionService,
	ServerStorage = { FindFirstChild = function() return nil end },
	PhysicsService = { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end },
	RunService = { IsServer = function() return true end, IsStudio = function() return true end, Heartbeat = signal() },
	Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end },
	-- (tests may override)
	DataStoreService = { GetDataStore = function() error("no datastores in smoke test") end, GetOrderedDataStore = function() error("none") end },
	MarketplaceService = {},
}
local game = { GetService = function(_, name) return assert(services[name], "unmocked service " .. name) end, BindToClose = function() end }

-- Lune's CFrame.lookAt flips the result when looking along ±Z (it gets ±X
-- right), so game code sees a Roblox-correct one.
local function lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, -1))
	end
	right = right.Unit
	return CFrame.fromMatrix(at, right, right:Cross(look).Unit, -look)
end
local GameCFrame = setmetatable({ lookAt = lookAt }, { __index = CFrame })

local loadModule
local function customRequire(n)
	local path = rawget(n, "__path")
	if path:match("Remotes%.luau$") then return RemotesMock end
	if cache[path] == nil then cache[path] = loadModule(n) end
	return cache[path]
end

function loadModule(n)
	local path = rawget(n, "__path")
	local env = setmetatable({
		script = n, game = game, workspace = workspaceFolder, require = customRequire,
		Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = GameCFrame,
		Color3 = roblox.Color3, Font = roblox.Font, UDim = roblox.UDim, UDim2 = roblox.UDim2, Enum = roblox.Enum,
		Random = Random, task = task, typeof = typeof, warn = function(...) print("WARN", ...) end,
		TweenInfo = { new = function() return {} end }, RaycastParams = { new = function() return {} end }, OverlapParams = { new = function() return {} end },
		__P = function(v) if typeof(v) == "Instance" then return v.CFrame.Position end return v.Position end,
	}, { __index = _G })
	local fn = luau.load(luau.compile(sources[path]), { debugName = path, environment = env })
	return fn()
end

return { root = ROOT, Enum = roblox.Enum, Random = Random, fireAdded = function(d) for _, fn in addedHandlers do fn(d) end end, services = services, remotes = RemotesMock, node = node, require = customRequire, shared = sharedNode, server = serverNode, workspace = workspaceFolder, tags = tags, fired = fired, CFrame = CFrame, Vector3 = Vector3, Instance = roblox.Instance }
