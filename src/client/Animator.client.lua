-- Makes students wander around their rooms, bob, and pop mood bubbles
-- (Habbo-style). Runs only on the client, so it costs the server nothing.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local walkers = {} -- [model] = state

local HAPPY = { "💖", "😄", "🎉", "✨", "🥰" }
local MEH = { "💭", "🎵", "📚", "😴" }
local ANGRY = { "💢", "😤", "🙄", "😭" }

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

local function newTarget(st)
	local r = st.range
	local right = Vector3.new(-st.facing.Z, 0, st.facing.X)
	return st.center + right * (math.random() * 2 - 1) * r.X + st.facing * (math.random() * 2 - 1) * r.Z
end

local function add(model)
	if not model:IsA("Model") then
		return
	end
	local center, range, facing = model:GetAttribute("Center"), model:GetAttribute("Range"), model:GetAttribute("Facing")
	if not (center and range and facing and model.PrimaryPart) then
		return
	end
	local st = {
		center = center,
		range = range,
		facing = facing,
		pos = model.PrimaryPart.Position,
		baseY = model.PrimaryPart.Position.Y,
		wait = math.random() * 2,
		phase = math.random() * 10,
		nextBubble = os.clock() + math.random(2, 8),
	}
	st.target = newTarget(st)
	walkers[model] = st
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
				st.wait = 1 + math.random() * 3
				st.target = newTarget(st)
			else
				moving = true
				local step = math.min(delta.Magnitude, 5 * dt)
				st.pos += delta.Unit * step
				st.dir = delta.Unit
			end
			local bob = moving and math.abs(math.sin(st.phase * 10)) * 0.35 or math.sin(st.phase * 2) * 0.08
			local look = st.dir or st.facing
			local p = Vector3.new(st.pos.X, st.baseY + bob, st.pos.Z)
			model:PivotTo(CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z)))
			if now > st.nextBubble then
				st.nextBubble = now + math.random(5, 12)
				bubble(model, model:GetAttribute("Sat") or 50)
			end
		end
	end
end)
