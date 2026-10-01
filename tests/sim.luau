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
local TrackGenerator = H.require(H.server.Run.TrackGenerator)
local RunController = H.require(client.RunController)
local InputController = H.require(client.InputController)

local origin = Vector3.new(6000, 0, 0)
local track = TrackGenerator.new(roblox.Instance.new("Folder"), origin, tonumber(process and process.args and process.args[1]) or 3)
trackFolder = track.folder
local caught = false
RunController.Caught:Connect(function() caught = true end)
local outcomes = {}
RunController.Impact:Connect(function(o) outcomes[o] = (outcomes[o] or 0) + 1 end)
for _, seg in trackFolder:GetChildren() do announced[seg] = true end
assert(RunController.Prepare({ origin = origin, startD = 6, trackFolder = track.folder, multiplier = 5, hoverboards = 2 }))
for _ = 1, 30 do bound(1 / 60) end -- intro: stand still
local st = RunController.State
print("intro feetY", st.feetY, "phase", st.phase)
RunController.Go()
for _ = 1, 30 do bound(1 / 60) end
-- 🚀 Jetpack: fly high, no collisions
RunController.HandleWorldEvent({ type = "PowerUp", id = "Jetpack", duration = 2 })
local task = require("@lune/task")
local function step() bound(1 / 60); track:Update(st.d); announceNew(); task.wait(1 / 60) end
local peak = 0
for _ = 1, 60 do step(); peak = math.max(peak, st.feetY) end
print(("jetpack: move=%s peakY=%.1f speed=%.1f"):format(st.move, peak, st.speed))
-- wait out the flight (jetpack uses real clock)
local t0 = os.clock()
while os.clock() - t0 < 2.2 do step() end
for _ = 1, 60 do step() end
print(("after jetpack: move=%s feetY=%.1f grounded=%s"):format(st.move, st.feetY, tostring(st.grounded)))
-- 👟 Super sneakers: higher jump
local function jumpPeak()
	for _ = 1, 30 do step() end
	local base = st.feetY
	InputController.Action:Fire("Jump")
	local p = 0
	for _ = 1, 90 do step(); p = math.max(p, st.feetY - base) end
	return p
end
local normal = jumpPeak()
RunController.HandleWorldEvent({ type = "PowerUp", id = "SuperSneakers", duration = 30 })
local super = jumpPeak()
st.sneakersUntil = 0
print(("jump peak normal=%.1f sneakers=%.1f"):format(normal, super))
-- 🛹 hoverboard
RunController.HandleWorldEvent({ type = "Hoverboard", duration = 30, left = 1 })
print("on board:", os.clock() < st.hoverUntil, "boards left", st.hoverboards)
local scoreBefore = st.score
for _ = 1, 60 do step() end
print(("score gained over 1s at x%d: %.0f (speed %.0f)"):format(RunController.CurrentMultiplier(), st.score - scoreBefore, st.speed))
for _ = 1, 10 do bound(1 / 60) end
InputController.Action:Fire("Roll")
for _ = 1, 3 do bound(1 / 60) end
print("rolling?", st.move, "gap", st.gap)
InputController.Action:Fire("Jump")
bound(1 / 60)
print("after jump during roll:", st.move, "vy", st.vy)
-- buffered jump: press jump just before landing
for _ = 1, 200 do bound(1 / 60); if st.vy < 0 and st.feetY < 1.5 then break end end
InputController.Action:Fire("Jump")
local landedJump = false
for _ = 1, 20 do bound(1 / 60); if st.vy > 0 and st.feetY < 3 then landedJump = true break end end
print("buffered jump fired on landing:", landedJump)

-- Simple bot: react to the nearest obstacle in the current lane.
local LANES = { -1, 0, 1 }
local function obstacleAhead(lane, from, to)
	local found, foundD
	for _, inst in track.folder:GetDescendants() do
		local t = inst:GetAttribute("ObstacleType")
		if t and inst:GetAttribute("Lane") == lane and not inst:GetAttribute("Destroyed") and inst:GetAttribute("Kind") ~= "TunnelEntrance" then
			local cf, size = inst:GetBoundingBox()
			local nearD = -(cf.Position.Z + size.Z / 2) + origin.Z
			local farD = nearD + size.Z
			if farD > from and nearD < to and (not foundD or nearD < foundD) then found, foundD = inst, nearD end
		end
	end
	return found, foundD
end
local frames, maxD, lastLog, jumps, rolls, switches = 0, 0, 0, 0, 0, 0
local useBot = not (process and process.args and process.args[2] == "nobot")
local cooldown = 0
while frames < 60 * 90 and not caught do
	frames += 1
	cooldown -= 1
	-- Gap ahead? Jump it.
	if useBot and st.grounded and st.move ~= "Flying" then
		local probeD = st.d + st.speed * 0.12
		local hit = H.workspace:Raycast(origin + Vector3.new(st.x, st.feetY + 1.6, -probeD), Vector3.new(0, -80, 0), nil)
		if not hit then
			InputController.Action:Fire("Jump"); jumps += 1; cooldown = 20
		end
	end
	if useBot and cooldown <= 0 and st.grounded and st.laneT >= 1 then
		local lead = st.speed * 0.45
		local ob, obD = obstacleAhead(st.lane, st.d, st.d + lead)
		if ob and obD - st.d > 1 then
			local kind = ob:GetAttribute("ObstacleType")
			if kind == "Jump" then InputController.Action:Fire("Jump"); jumps += 1; cooldown = 20
			elseif kind == "Roll" then InputController.Action:Fire("Roll"); rolls += 1; cooldown = 20
			else
				-- Head for the nearest lane that isn't blocked (one step at a time).
				for _, dir in { -1, 1, -2, 2 } do
					local target = st.lane + dir
					if target >= -1 and target <= 1 then
						local o2 = obstacleAhead(target, st.d - 4, st.d + lead + 6)
						local between = if math.abs(dir) == 2 then obstacleAhead(st.lane + dir // 2, st.d - 4, st.d + 8) else nil
						if (not o2 or o2:GetAttribute("ObstacleType") ~= "Block") and not between then
							InputController.Action:Fire(dir < 0 and "Left" or "Right"); switches += 1; cooldown = 12
							break
						end
					end
				end
			end
		end
	end
	bound(1 / 60)
	track:Update(st.d)
	announceNew()
	maxD = math.max(maxD, st.d)
	if st.d - lastLog > 1000 then
		lastLog = st.d
		print(("d=%.0f m=%.0f speed=%.1f gap=%.2f y=%.1f lane=%d move=%s coins=%d"):format(st.d, st.meters, st.speed, st.gap, st.feetY, st.lane, st.move, st.coins))
	end
end
if caught then
	local fellAt = st.feetY
	RunController.Revive()
	for _ = 1, 30 do bound(1 / 60) end
	print(("revive: caught at y=%.1f → now y=%.1f grounded=%s phase=%s"):format(fellAt, st.feetY, tostring(st.grounded), st.phase))
end
print(("END frames=%d seconds=%.1f maxMeters=%.0f caught=%s coins=%d score=%d jumps=%d rolls=%d switches=%d"):format(frames, frames / 60, st.meters, tostring(caught), st.coins, st.score, jumps, rolls, switches))
for k, v in outcomes do print("impact", k, v) end
for k, v in sent do print("sent", k, v) end
for k, v in styles do print("trick", k, v) end
assert(st.meters > 2000, "the bot should get well past 2km")
assert((styles.Clear or 0) + (styles.NearMiss or 0) > 10, "tricks are spotted")
print("SIM OK")
process.exit(0)
