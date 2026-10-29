-- Makes students live in the house: they wander their room, pop mood bubbles
-- (Habbo-style) and now and then walk out the door and along the hallways to
-- hang out in the hallway, the common room or a facility on their floor,
-- then go home.
-- Runs only on the client, so it costs the server nothing.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local House = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("House"))

local walkers = {} -- [model] = state

local HAPPY = { "💖", "😄", "🎉", "✨", "🥰" }
local MEH = { "💭", "🎵", "📚", "😴" }
local ANGRY = { "💢", "😤", "🙄", "😭" }
local SPEED = 5
local OUTING_CHANCE = 0.3

-- Roblox's default R15 walk/idle animations, for avatar students
local WALK_ANIM = "rbxassetid://507777826"
local IDLE_ANIM = "rbxassetid://507766388"

local function loadTracks(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local ok, tracks = pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = hum
		local function load(id)
			local a = Instance.new("Animation")
			a.AnimationId = id
			local t = animator:LoadAnimation(a)
			t.Looped = true
			return t
		end
		return { walk = load(WALK_ANIM), idle = load(IDLE_ANIM) }
	end)
	if not ok then
		return nil
	end
	tracks.idle:Play(0.2)
	return tracks
end

local function bubble(model, sat)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local pool = sat >= 65 and HAPPY or sat >= 40 and MEH or ANGRY
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(40, 40)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.MaxDistance = 80
	bb.Adornee = head
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Text = pool[math.random(1, #pool)]
	t.Parent = bb
	bb.Parent = head
	Debris:AddItem(bb, 2)
end

---------------------------------------------------------------------------
-- The house plan (published by the server as JSON on each house folder).
-- Areas are a room key or "hall"; points are plot-local studs (x, z).
---------------------------------------------------------------------------
local plans = {} -- [plotIndex] = { json, origin, data, floors = { [f] = { owner, stair, well, walk } } }

local function planFor(plotIndex)
	for _, h in ipairs(CollectionService:GetTagged("HousePlan")) do
		if h.Parent and h:GetAttribute("PlotIndex") == plotIndex then
			local json = h:GetAttribute("Plan")
			local cached = plans[plotIndex]
			if cached and cached.json == json then
				return cached
			end
			local ok, p = pcall(function()
				return HttpService:JSONDecode(json)
			end)
			local origin = h.Parent:GetAttribute("Origin")
			if not ok or typeof(p) ~= "table" or not origin then
				return nil
			end
			local data = { floors = #p.floors, plan = { floors = {}, stairs = {} }, layout = {} }
			for f, hall in ipairs(p.floors) do
				data.plan.floors[f] = { hall = hall }
			end
			for f, st in ipairs(p.stairs or {}) do
				data.plan.stairs[f] = st
			end
			for key, r in pairs(p.rooms or {}) do
				data.layout[key] = { floor = r.f, x = r.x, z = r.z, w = r.w, d = r.d, door = r.door }
			end
			cached = { json = json, origin = origin, data = data, floors = {} }
			plans[plotIndex] = cached
			return cached
		end
	end
	return nil
end

local function floorInfo(plan, f)
	local fi = plan.floors[f]
	if not fi then
		local owner, stair, well = House.owners(plan.data, f)
		local walk, list = {}, {}
		for i, o in pairs(owner) do
			if o == "hall" and not stair[i] and not well[i] then
				walk[i] = true
				table.insert(list, i)
			end
		end
		fi = { walk = walk, list = list }
		plan.floors[f] = fi
	end
	return fi
end

local function toWorld(plan, x, z)
	return plan.origin * Vector3.new(x, 0, z)
end

local function jitter()
	return (math.random() * 2 - 1) * 1.4
end

local function tilePoint(t)
	local x, z = House.tileCenter(t[1], t[2])
	return { x + jitter(), z + jitter() }
end

-- somewhere to stand in a room, clear of the beds at the back of dorms
local function roomPoint(plan, key)
	local r = plan.data.layout[key]
	if not r or not r.door then
		return nil
	end
	local fr = House.roomFrame(r, r.door, key)
	local kind = House.describe(key)
	local uMax = kind == "dorm" and math.max(2.5, fr.U - 9) or fr.U - 3
	local u = 2 + math.random() * (uMax - 2)
	local v = (math.random() * 2 - 1) * (fr.V / 2 - 2)
	local x, z = House.framePoint(fr, u, v)
	return { x, z }
end

-- inside and outside the doorway, and the hallway tile it opens onto
local function doorSteps(plan, key)
	local r = plan.data.layout[key]
	local door = r and r.door
	if not door then
		return nil
	end
	local x, z = House.doorPoint(door)
	return { x - door.dx * 1.6, z - door.dz * 1.6 }, { x + door.dx * 1.6, z + door.dz * 1.6 }, { door.x + door.dx, door.z + door.dz }
end

local function pointIn(plan, area)
	if area.key == "hall" then
		return tilePoint(area.tile)
	end
	return roomPoint(plan, area.key)
end

-- plot-local waypoints from one area to another on the same floor, or nil
local function route(plan, floor, from, to)
	local fi = floorInfo(plan, floor)
	local points = {}
	local startTile, goalTile
	if from.key == "hall" then
		startTile = from.tile
	else
		local inside, outside, tile = doorSteps(plan, from.key)
		if not inside then
			return nil
		end
		table.insert(points, inside)
		table.insert(points, outside)
		startTile = tile
	end
	local tail = {}
	if to.key == "hall" then
		goalTile = to.tile
	else
		local inside, outside, tile = doorSteps(plan, to.key)
		if not inside then
			return nil
		end
		goalTile = tile
		tail = { outside, inside }
	end
	local path = House.path(startTile[1], startTile[2], goalTile[1], goalTile[2], function(i)
		return fi.walk[i] == true
	end)
	if not path then
		return nil
	end
	for _, t in ipairs(path) do
		table.insert(points, tilePoint(t))
	end
	for _, p in ipairs(tail) do
		table.insert(points, p)
	end
	local last = pointIn(plan, to)
	if last then
		table.insert(points, last)
	end
	return points
end

-- places to hang out on this floor: the common room, facilities, the hallways
local function hangouts(plan, floor)
	local list = {}
	for key, r in pairs(plan.data.layout) do
		local kind = House.describe(key)
		if r.floor == floor and (kind == "common" or kind == "facility") then
			table.insert(list, { key = key })
		end
	end
	local fi = floorInfo(plan, floor)
	if #fi.list > 0 then
		local i = fi.list[math.random(1, #fi.list)]
		table.insert(list, { key = "hall", tile = { (i - 1) % House.W, (i - 1) // House.W } })
	end
	return list
end

-- living room items: fans of an item's tags walk up and use it for a while
local taken = {} -- [spot] = model
local function findSpot(st, model)
	local tags = string.split(model:GetAttribute("Tags") or "", ",")
	local options = {}
	for _, sp in ipairs(CollectionService:GetTagged("UseSpot")) do
		if sp.Parent and not taken[sp] and sp:GetAttribute("PlotIndex") == st.plot and sp:GetAttribute("Key") == st.area.key then
			local wanted = string.split(sp:GetAttribute("UseTags") or "", ",")
			for _, t in ipairs(tags) do
				if table.find(wanted, t) then
					table.insert(options, sp)
					break
				end
			end
		end
	end
	return #options > 0 and options[math.random(1, #options)] or nil
end

local function useBubble(model, emoji)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(44, 44)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.MaxDistance = 80
	bb.Adornee = head
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Text = emoji
	t.Parent = bb
	bb.Parent = head
	Debris:AddItem(bb, 3)
end

local function worldPoints(plan, list)
	local out = {}
	for _, p in ipairs(list) do
		table.insert(out, toWorld(plan, p[1], p[2]))
	end
	return out
end

local function add(model)
	if not model:IsA("Model") or not model.PrimaryPart then
		return
	end
	local key = model:GetAttribute("HomeKey")
	if not key then
		return
	end
	local st = {
		home = { key = key },
		plot = model:GetAttribute("PlotIndex"),
		floor = model:GetAttribute("Floor"),
		pos = model.PrimaryPart.Position,
		baseY = model.PrimaryPart.Position.Y,
		wait = math.random() * 2,
		phase = math.random() * 10,
		nextBubble = os.clock() + math.random(2, 8),
		queue = {},
		outingStops = 0,
		tracks = loadTracks(model),
		walking = false,
	}
	st.area = st.home
	st.target = st.pos
	walkers[model] = st
end

local function decide(st, model)
	if st.using then
		taken[st.using.spot] = nil
		st.using = nil
	end
	local plan = planFor(st.plot)
	if not plan then
		return
	end
	if plan.json ~= st.planJson then
		-- the house was rebuilt: start over at home
		local first = st.planJson == nil
		st.planJson = plan.json
		st.area = st.home
		if not first then
			local p = roomPoint(plan, st.home.key)
			if p then
				st.pos = toWorld(plan, p[1], p[2])
			end
		end
	end
	if st.area ~= st.home then
		st.outingStops -= 1
		if st.outingStops <= 0 then
			local r = route(plan, st.floor, st.area, st.home)
			st.area = st.home
			if r then
				st.queue = worldPoints(plan, r)
				return
			end
			local p = roomPoint(plan, st.home.key)
			if p then
				st.pos = toWorld(plan, p[1], p[2]) -- lost: just be home
			end
		elseif st.area.key ~= "hall" and math.random() < 0.6 then
			local sp = findSpot(st, model)
			if sp then
				taken[sp] = model
				st.using = { spot = sp, arrived = false }
				st.queue = { sp.Position }
				return
			end
		end
	elseif math.random() < OUTING_CHANCE then
		local spots = hangouts(plan, st.floor)
		if #spots > 0 then
			local to = spots[math.random(1, #spots)]
			local r = route(plan, st.floor, st.home, to)
			if r then
				st.queue = worldPoints(plan, r)
				st.area = to
				st.outingStops = math.random(2, 4)
				return
			end
		end
	end
	if st.area.key == "hall" then
		-- stroll a little way down the hallway
		local fi = floorInfo(plan, st.floor)
		local i = fi.list[math.random(1, #fi.list)]
		local to = { key = "hall", tile = { (i - 1) % House.W, (i - 1) // House.W } }
		local r = route(plan, st.floor, st.area, to)
		if r and #r <= 10 then
			st.queue = worldPoints(plan, r)
			st.area = to
			return
		end
	end
	local p = pointIn(plan, st.area)
	if p then
		st.queue = { toWorld(plan, p[1], p[2]) }
	end
end

-- outing photos: point each ViewportFrame at its own camera (the property
-- doesn't always survive replication)
local function fixPhoto(vp)
	task.defer(function()
		local cam = vp:FindFirstChildOfClass("Camera") or vp:WaitForChild("Camera", 5)
		if cam and vp:IsA("ViewportFrame") then
			vp.CurrentCamera = cam
		end
	end)
end
CollectionService:GetInstanceAddedSignal("PhotoView"):Connect(fixPhoto)
for _, vp in ipairs(CollectionService:GetTagged("PhotoView")) do
	fixPhoto(vp)
end

CollectionService:GetInstanceAddedSignal("Student"):Connect(function(m)
	task.defer(add, m)
end)
CollectionService:GetInstanceRemovedSignal("Student"):Connect(function(m)
	local st = walkers[m]
	if st and st.using then
		taken[st.using.spot] = nil
	end
	walkers[m] = nil
end)
for _, m in ipairs(CollectionService:GetTagged("Student")) do
	add(m)
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for model, st in pairs(walkers) do
		if not model.Parent or not model.PrimaryPart then
			walkers[model] = nil
		else
			st.phase += dt
			local flat = Vector3.new(st.pos.X, 0, st.pos.Z)
			local goal = Vector3.new(st.target.X, 0, st.target.Z)
			local delta = goal - flat
			local moving = false
			if st.wait > 0 then
				st.wait -= dt
			elseif delta.Magnitude < 0.3 then
				if #st.queue > 0 then
					st.target = table.remove(st.queue, 1)
				elseif st.using and not st.using.arrived and st.using.spot.Parent then
					-- at the item: face it and hang out with it for a bit
					st.using.arrived = true
					local face = st.using.spot:GetAttribute("Face")
					if face then
						local f = Vector3.new(face.X - st.pos.X, 0, face.Z - st.pos.Z)
						if f.Magnitude > 0.1 then
							st.dir = f.Unit
						end
					end
					st.wait = 5 + math.random() * 5
					useBubble(model, st.using.spot:GetAttribute("Use") or "✨")
				else
					st.wait = 1 + math.random() * 3
					decide(st, model)
					st.target = table.remove(st.queue, 1) or st.pos
				end
			else
				moving = true
				local step = math.min(delta.Magnitude, SPEED * dt)
				st.pos += delta.Unit * step
				st.dir = delta.Unit
			end
			local bob = 0
			if st.tracks then
				if moving ~= st.walking then
					st.walking = moving
					if moving then
						st.tracks.idle:Stop(0.2)
						st.tracks.walk:Play(0.2)
						st.tracks.walk:AdjustSpeed(SPEED / 12)
					else
						st.tracks.walk:Stop(0.2)
						st.tracks.idle:Play(0.2)
					end
				end
			else
				bob = moving and math.abs(math.sin(st.phase * 10)) * 0.35 or math.sin(st.phase * 2) * 0.08
			end
			local look = st.dir or model.PrimaryPart.CFrame.LookVector
			local p = Vector3.new(st.pos.X, st.baseY + bob, st.pos.Z)
			model:PivotTo(CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z)))
			if now > st.nextBubble then
				st.nextBubble = now + math.random(5, 12)
				bubble(model, model:GetAttribute("Sat") or 50)
			end
		end
	end
end)
