-- Makes students live in the house: they wander their room, pop mood bubbles
-- (Habbo-style) and now and then walk out the door to hang out in the
-- hallway, the common room or a facility on their floor, then go home.
-- Runs only on the client, so it costs the server nothing.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

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

-- an area is { center, u, v, range, door, hall, isHall }
local function areaFrom(inst)
	local center, u, v, range = inst:GetAttribute("Center"), inst:GetAttribute("U"), inst:GetAttribute("V"), inst:GetAttribute("Range")
	if not (center and u and v and range) then
		return nil
	end
	return {
		center = center,
		u = u,
		v = v,
		range = range,
		door = inst:GetAttribute("Door") or center,
		hall = inst:GetAttribute("Hall") or center,
		isHall = inst:GetAttribute("IsHall") == true,
		key = inst:GetAttribute("Key") or inst:GetAttribute("HomeKey"),
	}
end

local function randomPoint(area)
	local r = area.range
	return area.center + area.u * (math.random() * 2 - 1) * r.X + area.v * (math.random() * 2 - 1) * r.Z
end

-- hangout spots on the same floor of the same house
local function hangouts(st)
	local list = {}
	for _, inst in ipairs(CollectionService:GetTagged("HangoutRoom")) do
		if inst.Parent and inst:GetAttribute("PlotIndex") == st.plot and inst:GetAttribute("Floor") == st.floor then
			local a = areaFrom(inst)
			if a then
				table.insert(list, a)
			end
		end
	end
	return list
end

-- living room items: fans of an item's tags walk up and use it for a while
local taken = {} -- [spot] = model
local function findSpot(st, model)
	local tags = string.split(model:GetAttribute("Tags") or "", ",")
	local options = {}
	for _, sp in ipairs(CollectionService:GetTagged("UseSpot")) do
		if sp.Parent and not taken[sp] and sp:GetAttribute("PlotIndex") == st.plot and sp:GetAttribute("Floor") == st.floor then
			local inArea = (sp.Position - st.area.center).Magnitude < st.area.range.Magnitude + 4
			local wanted = string.split(sp:GetAttribute("UseTags") or "", ",")
			if inArea then
				for _, t in ipairs(tags) do
					if table.find(wanted, t) then
						table.insert(options, sp)
						break
					end
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

-- door-to-door route through the hallway
local function route(from, to)
	local points = {}
	if not from.isHall then
		table.insert(points, from.door)
		table.insert(points, from.hall)
	end
	if not to.isHall then
		table.insert(points, to.hall)
		table.insert(points, to.door)
	end
	table.insert(points, randomPoint(to))
	return points
end

local function add(model)
	if not model:IsA("Model") or not model.PrimaryPart then
		return
	end
	local home = areaFrom(model)
	if not home then
		return
	end
	local st = {
		home = home,
		area = home,
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
	st.target = randomPoint(home)
	walkers[model] = st
end

local function decide(st, model)
	if st.using then
		taken[st.using.spot] = nil
		st.using = nil
	end
	if st.area ~= st.home then
		st.outingStops -= 1
		if st.outingStops <= 0 then
			st.queue = route(st.area, st.home)
			st.area = st.home
			return
		end
		if math.random() < 0.6 then
			local sp = findSpot(st, model)
			if sp then
				taken[sp] = model
				st.using = { spot = sp, arrived = false }
				st.queue = { sp.Position }
				return
			end
		end
	elseif math.random() < OUTING_CHANCE then
		local spots = hangouts(st)
		if #spots > 0 then
			local to = spots[math.random(1, #spots)]
			st.queue = route(st.home, to)
			st.area = to
			st.outingStops = math.random(2, 4)
			return
		end
	end
	st.queue = { randomPoint(st.area) }
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
					st.target = table.remove(st.queue, 1)
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
			local look = st.dir or st.home.u
			local p = Vector3.new(st.pos.X, st.baseY + bob, st.pos.Z)
			model:PivotTo(CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z)))
			if now > st.nextBubble then
				st.nextBubble = now + math.random(5, 12)
				bubble(model, model:GetAttribute("Sat") or 50)
			end
		end
	end
end)
