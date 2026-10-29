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
	}
	st.target = randomPoint(home)
	walkers[model] = st
end

local function decide(st)
	if st.area ~= st.home then
		st.outingStops -= 1
		if st.outingStops <= 0 then
			st.queue = route(st.area, st.home)
			st.area = st.home
			return
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
				else
					st.wait = 1 + math.random() * 3
					decide(st)
					st.target = table.remove(st.queue, 1)
				end
			else
				moving = true
				local step = math.min(delta.Magnitude, SPEED * dt)
				st.pos += delta.Unit * step
				st.dir = delta.Unit
			end
			local bob = moving and math.abs(math.sin(st.phase * 10)) * 0.35 or math.sin(st.phase * 2) * 0.08
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
