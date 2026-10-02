local process = require("@lune/process")
local H = require("./harness")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local function sig() return { Connect = function() return { Disconnect = function() end } end, Once = function() end } end
local services = H.services
services.TweenService = { Create = function() return { Play = function() end, Completed = sig() } end }
services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = sig(), InputChanged = sig(), InputEnded = sig() }
services.Debris = { AddItem = function() end }
local bound
services.RunService.BindToRenderStep = function(_, name, _, fn) if name == "BrainrotRunController" then bound = fn end end
services.RunService.UnbindFromRenderStep = function() end
local sent = {}
local styles = {}
H.remotes.Event = function(name) return { FireServer = function(_, a) sent[name] = (sent[name] or 0) + 1; if name == "ReportStyle" then styles[a] = (styles[a] or 0) + 1 end end, OnClientEvent = sig() } end

-- physics-query mocks over the generated track
local trackFolder
local function surfaceY(p, x, z)
	local cf, s = p.CFrame, p.Size
	local l = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
	if math.abs(l.X) > s.X / 2 or math.abs(l.Z) > s.Z / 2 then return nil end
	if p.ClassName == "WedgePart" then
		return cf.Position.Y - s.Y / 2 + s.Y * (l.Z + s.Z / 2) / s.Z
	end
	return cf.Position.Y + s.Y / 2
end
roblox.implementMethod("Folder", "Raycast", function(_, origin, dir, params)
	local best, bestPart
	for _, p in trackFolder:GetDescendants() do
		if p:IsA("BasePart") and p.CollisionGroup == "RunGround" then
			if dir.Y < 0 then
				local y = surfaceY(p, origin.X, origin.Z)
				if y and y <= origin.Y and y >= origin.Y + dir.Y and (not best or y > best) then best, bestPart = y, p end
			else
				local top = surfaceY(p, origin.X, origin.Z)
				if top then
					local y = top - p.Size.Y -- underside (boxes only)
					if y >= origin.Y and y <= origin.Y + dir.Y and (not best or y < best) then best, bestPart = y, p end
				end
			end
		end
	end
	return best and { Position = Vector3.new(origin.X, best, origin.Z), Instance = bestPart } or nil
end)
roblox.implementMethod("Folder", "GetPartBoundsInBox", function(_, cf, size, params)
	local out = {}
	local c, h = cf.Position, size / 2
	for _, p in trackFolder:GetDescendants() do
		if p:IsA("BasePart") and p.CollisionGroup == "RunObstacle" and (p.Transparency < 1 or p.Name == "Lip") then
			local pc, ps = p.CFrame.Position, p.Size / 2
			if math.abs(pc.X - c.X) < ps.X + h.X and math.abs(pc.Y - c.Y) < ps.Y + h.Y and math.abs(pc.Z - c.Z) < ps.Z + h.Z then
				table.insert(out, p)
			end
		end
	end
	return out
end)
-- Lune never fires DescendantAdded: announce new segments ourselves.
local announced = {}
local function announceNew()
	for _, seg in trackFolder:GetChildren() do
		if not announced[seg] then
			announced[seg] = true
			for _, d in seg:GetDescendants() do H.fireAdded(d) end
		end
	end
end
roblox.implementMethod("Humanoid", "SetStateEnabled", function() end)
roblox.implementMethod("Humanoid", "ChangeState", function() end)
for _, prop in { "AssemblyLinearVelocity", "AssemblyAngularVelocity" } do
	roblox.implementProperty("Part", prop, function() return Vector3.zero end, function() end)
end

local character = roblox.Instance.new("Model")
local root = roblox.Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.Parent = character
local hum = roblox.Instance.new("Humanoid"); hum.RigType = roblox.Enum.HumanoidRigType.R15; hum.HipHeight = 2; hum.Parent = character
services.Players.LocalPlayer = { Character = character }

local client = H.node(H.root .. "/client", nil, "Client")
local RunController = H.require(client.RunController)
local InputController = H.require(client.InputController)


local TrackAreas = H.require(H.server.Run.TrackAreas)
local library = TrackAreas.Load()
local origin = Vector3.new(6000, 0, 0)
-- A Garden section template placed at the start of a track.
local function build(kind, variant)
	local folder = roblox.Instance.new("Folder")
	local layouts = library.Garden.kinds[kind][0]
	local model = TrackAreas.Place(layouts[(variant - 1) % #layouts + 1], origin, 0)
	model.Parent = folder
	-- floor behind the section start
	local p = roblox.Instance.new("Part"); p.Size = Vector3.new(30, 2, 200); p.CFrame = CFrame.new(origin + Vector3.new(0, -1, 100)); p.CollisionGroup = "RunGround"; p.Parent = folder
	return folder
end
local st = RunController.State
local styles2 = {}
local function setup(folder, startD, lane)
	trackFolder = folder
	assert(RunController.Prepare({ origin = origin, startD = startD, trackFolder = folder, multiplier = 1, hoverboards = 0 }))
	RunController.Go()
	st.speedFactor = 1
	st.lane, st.fromLane, st.laneT = lane, lane, 1
	st.x = ({ [-1] = -8, [0] = 0, [1] = 8 })[lane]
end
-- Removes inside-tunnel obstacles so we only test the tunnel itself.
local function strip(folder, keep)
	for _, d in folder:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("ObstacleType") and not keep[d:GetAttribute("Kind")] then d:Destroy() end
	end
end

-- 1) TUNNEL
local tunnel = build("Greenhouse", 1)
strip(tunnel, { TunnelEntrance = true })
local entrance = 40
local function tryTunnel(offset, boost)
	local bumps = 0
	local con = RunController.Impact:Connect(function(o) if o == "Bump" then bumps += 1 end end)
	setup(tunnel, entrance - offset - 30, 0)
	if boost == "sneakers" then st.sneakersUntil = os.clock() + 100 elseif boost == "board" then st.hoverUntil = os.clock() + 100 end
	local jumped, maxY = false, 0
	for _ = 1, 60 * 4 do
		if not jumped and st.d >= entrance - offset then InputController.Action:Fire("Jump"); jumped = true end
		bound(1 / 60)
		maxY = math.max(maxY, st.feetY)
		if st.d > entrance + 30 then break end
	end
	con:Disconnect()
	RunController.Stop()
	return st.feetY, bumps, maxY
end
local ok = {}
for _, boost in { "none", "sneakers", "board" } do
	local onRoof, crashed, under = 0, 0, 0
	for offset = 2, 40, 2 do
		local y, bumps = tryTunnel(offset, boost)
		if bumps > 0 then crashed += 1 elseif y > 15.9 then onRoof += 1 else under += 1 end
	end
	print(("tunnel %-8s jump offsets 2..40: on roof %d, through %d, crashed into lip %d"):format(boost, onRoof, under, crashed))
	ok[boost] = onRoof
end
assert(ok.none == 0, "normal jump must not reach the tunnel roof")
assert(ok.sneakers > 0 and ok.board > 0, "boosted jumps must reach the tunnel roof")

-- jumping INSIDE the tunnel with sneakers: head stays under the ceiling
setup(tunnel, entrance + 10, 0)
st.sneakersUntil = os.clock() + 100
InputController.Action:Fire("Jump")
local maxY = 0
for _ = 1, 60 do bound(1 / 60); maxY = math.max(maxY, st.feetY) end
print(("sneaker jump inside tunnel: max feet %.2f (ceiling 15 - head 5.6 = 9.4), now y=%.1f"):format(maxY, st.feetY))
assert(maxY <= 9.45 and st.feetY < 1, "must bonk on the ceiling")
RunController.Stop()

-- 2) BUS
local busFolder, busD, busLane
for variant = 1, 2 do
	local f = build("HayWagons", variant)
	for _, d in f:GetDescendants() do
		if d:GetAttribute("Kind") == "HayWagon" then busFolder, busD, busLane = f, d:GetAttribute("TrackD"), d:GetAttribute("Lane") break end
	end
	if busFolder then break end
end
strip(busFolder, { HayWagon = true })
local function tryBus(offset, boost)
	local bumps = 0
	local con = RunController.Impact:Connect(function(o) if o == "Bump" then bumps += 1 end end)
	setup(busFolder, busD - offset - 30, busLane)
	if boost == "sneakers" then st.sneakersUntil = os.clock() + 100 elseif boost == "board" then st.hoverUntil = os.clock() + 100 end
	local jumped, y = false, 0
	for _ = 1, 60 * 3 do
		if not jumped and st.d >= busD - offset then InputController.Action:Fire("Jump"); jumped = true end
		bound(1 / 60)
		if st.d > busD + 15 and st.d < busD + 20 then y = st.feetY end
		if bumps > 0 or st.d > busD + 20 then break end
	end
	con:Disconnect()
	RunController.Stop()
	return y, bumps
end
for _, boost in { "none", "sneakers", "board" } do
	local onRoof, crashed = 0, 0
	for offset = 2, 40, 2 do
		local y, bumps = tryBus(offset, boost)
		if bumps > 0 then crashed += 1 elseif y > 12.4 then onRoof += 1 end
	end
	print(("bus    %-8s jump offsets 2..40: on roof %d, crashed %d"):format(boost, onRoof, crashed))
	ok["bus" .. boost] = onRoof
end
assert(ok.busnone == 0 and ok.bussneakers > 0 and ok.busboard > 0)

-- 3) SIDE BUMP: running beside a bus and switching lanes into it bounces you back.
local outcomes = {}
local con = RunController.Impact:Connect(function(o) outcomes[o] = (outcomes[o] or 0) + 1 end)
local side = if busLane == 1 then 0 elseif busLane == -1 then 0 else 1
local towards = if busLane < side then "Left" else "Right"
setup(busFolder, busD + 4, side)
local startX = st.x
local minSpeed, maxInto = 99, 0
InputController.Action:Fire(towards)
for i = 1, 24 do
	bound(1 / 60)
	minSpeed = math.min(minSpeed, st.speedFactor)
	maxInto = math.max(maxInto, math.abs(st.x - startX))
end
print(("side bump: impacts Side=%d Bump=%d, lane %d→%d, max sideways %.2f studs, x back to %.2f (start %.2f), min speed x%.2f, now x%.2f"):format(outcomes.Side or 0, outcomes.Bump or 0, side, st.lane, maxInto, st.x, startX, minSpeed, st.speedFactor))
assert(outcomes.Side == 1 and not outcomes.Bump, "exactly one side bump, no crash")
assert(st.lane == side and math.abs(st.x - startX) < 0.01, "bounced back into the original lane")
assert(minSpeed <= 0.61, "side bump slows you down")
-- holding into it again bumps again (each time), never phasing through
InputController.Action:Fire(towards)
for _ = 1, 24 do bound(1 / 60) end
print(("second push: Side=%d lane=%d x=%.2f (bus ends at d=%d, runner at d=%.0f)"):format(outcomes.Side, st.lane, st.x, busD + 38, st.d))
assert(outcomes.Side == 2 and st.lane == side)
con:Disconnect()
RunController.Stop()
for k, v in styles do print("trick", k, v) end
print("BOOST OK")
process.exit(0)
