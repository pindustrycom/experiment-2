-- Builds the world (plaza + plots) and renders each player's boarding house
-- from data. Everything is procedural, so the place needs no prebuilt models.
--
-- A house is one walkable building: a hallway runs from the front door to the
-- stairwell at the back, with rooms on both sides (see shared/House.lua for
-- which room goes in which slot). Plot-local axes: -Z is the front (toward the
-- plaza), +X is the right side when you walk in through the front door.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SchoolMath = require(ReplicatedStorage.Shared.SchoolMath)
local House = require(ReplicatedStorage.Shared.House)

local PlotService = {}
PlotService.Plots = {} -- list of { model, cf, owner, house, live }

local FLOOR_H = House.FloorHeight -- slab top to slab top
local WALL_H = FLOOR_H - 1
local HALL_W = 12
local ROOM_U = 18 -- room depth, from the hallway out to the outside wall
local ROOM_V = 16 -- room width along the hallway
local ROWS = Config.SlotsPerFloor / 2
local HOUSE_Z0 = -44 -- front wall
local HOUSE_Z1 = HOUSE_Z0 + ROWS * ROOM_V -- back of the room block
local STAIR_Z0, STAIR_Z1 = HOUSE_Z1 + 1, HOUSE_Z1 + 18 -- ramp bottom/top
local TOWER_Z1 = STAIR_Z1 + 4 -- back wall of the stairwell
local HALF_X = HALL_W / 2 + ROOM_U
local GROUND_Y = 0.6 -- top of the plot base
local PLOT_W, PLOT_D = 150, 150
local DOOR_W, DOOR_H = 5, 8


local PLOT_POSITIONS = {
	Vector3.new(-170, 0, -170),
	Vector3.new(0, 0, -170),
	Vector3.new(170, 0, -170),
	Vector3.new(-170, 0, 170),
	Vector3.new(0, 0, 170),
	Vector3.new(170, 0, 170),
}

local function floorY(f)
	return GROUND_Y + 0.6 + f * FLOOR_H
end

local function mat(name)
	local ok, m = pcall(function()
		return Enum.Material[name]
	end)
	return ok and m or Enum.Material.SmoothPlastic
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Style" then
			p[k] = v
		end
	end
	if props.Style then
		p.Color = props.Style.color
		p.Material = mat(props.Style.material)
		if props.Style.material == "Glass" then
			p.Reflectance = 0.15
		end
	end
	p.Parent = props.Parent
	return p
end

-- Scale sizes are in studs (shrink with distance); Offset sizes are pixels.
local function billboard(adornee, size, offset, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffset = offset or Vector3.zero
	bb.AlwaysOnTop = false
	bb.MaxDistance = maxDist or 150
	bb.LightInfluence = 0
	bb.Adornee = adornee
	bb.Parent = adornee
	return bb
end

local function label(parent, text, color, size, pos, scaled)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size or UDim2.fromScale(1, 1)
	l.Position = pos or UDim2.fromScale(0, 0)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = scaled ~= false
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.Text = text
	l.Parent = parent
	return l
end

local function surface(p, face, canvas)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = canvas
	sg.LightInfluence = 0
	sg.Parent = p
	return sg
end

local function prompt(parent, action, object, dist)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = dist or 8
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = parent
	return pp
end

-- A wall along the local X axis of `frame`, from x=a0 to a1, heights h0..h1,
-- thickness along local Z. holes = { { c, w, b, t, glass } } in the same axes.
local function wall(parent, frame, a0, a1, h0, h1, thick, props, holes)
	holes = holes or {}
	table.sort(holes, function(x, y)
		return x.c < y.c
	end)
	local function piece(x0, x1, y0, y1)
		if x1 - x0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local p = table.clone(props)
		p.Size = Vector3.new(x1 - x0, y1 - y0, thick)
		p.CFrame = frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0)
		p.Parent = parent
		part(p)
	end
	local x = a0
	for _, h in ipairs(holes) do
		local l, r = h.c - h.w / 2, h.c + h.w / 2
		piece(x, l, h0, h1)
		piece(l, r, h0, h.b)
		piece(l, r, h.t, h1)
		if h.glass then
			part({ Name = "Window", Size = Vector3.new(h.w, h.t - h.b, 0.15), CFrame = frame * CFrame.new(h.c, (h.b + h.t) / 2, 0), Color = Color3.fromRGB(180, 225, 255), Material = Enum.Material.Glass, Transparency = 0.6, Parent = parent })
		end
		x = r
	end
	piece(x, a1, h0, h1)
end

-- frame whose local X runs along world/plot Z (for side walls)
local ALONG_Z = CFrame.Angles(0, -math.pi / 2, 0)

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
function PlotService.BuildWorld()
	local world = Instance.new("Folder")
	world.Name = "BSTWorld"
	world.Parent = workspace

	if not workspace:FindFirstChild("Baseplate") then
		part({
			Name = "Baseplate",
			Size = Vector3.new(1200, 2, 1200),
			Position = Vector3.new(0, -1, 0),
			Color = Color3.fromRGB(110, 190, 90),
			Material = Enum.Material.Grass,
			Parent = workspace,
		})
	end

	-- plaza
	part({
		Name = "Plaza",
		Size = Vector3.new(120, 0.4, 120),
		Position = Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(225, 215, 195),
		Material = Enum.Material.Brick,
		Parent = world,
	})
	local spawnLoc = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawnLoc then
		spawnLoc = Instance.new("SpawnLocation")
		spawnLoc.Anchored = true
		spawnLoc.Parent = workspace
	end
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.Position = Vector3.new(0, 0.5, 0)
	spawnLoc.Color = Color3.fromRGB(255, 200, 80)
	spawnLoc.Neutral = true

	-- paths from plaza to the plots
	for _, z in ipairs({ -1, 1 }) do
		part({
			Name = "Path",
			Size = Vector3.new(520, 0.3, 14),
			Position = Vector3.new(0, 0.15, z * 85),
			Color = Color3.fromRGB(200, 190, 170),
			Material = Enum.Material.Cobblestone,
			Parent = world,
		})
	end

	-- leaderboards
	PlotService.Boards = {}
	local boards = {
		{ key = "earned", title = "🏆 Richest Schools", x = -22 },
		{ key = "likes", title = "❤ Most Liked Schools", x = 22 },
	}
	for _, b in ipairs(boards) do
		local board = part({
			Name = "Board_" .. b.key,
			Size = Vector3.new(26, 22, 1),
			CFrame = CFrame.new(b.x, 12, 40), -- front face looks back toward the spawn
			Color = Color3.fromRGB(40, 40, 60),
			Parent = world,
		})
		part({ Size = Vector3.new(1, 12, 1), Position = Vector3.new(b.x, 0.5 + 0.5, 40), Color = Color3.fromRGB(40, 40, 60), Parent = world })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(520, 440)
		sg.LightInfluence = 0
		sg.Parent = board
		label(sg, b.title, Color3.fromRGB(255, 220, 90), UDim2.new(1, 0, 0, 56))
		local rows = {}
		for i = 1, 10 do
			rows[i] = label(sg, "", Color3.new(1, 1, 1), UDim2.new(1, -20, 0, 36), UDim2.new(0, 10, 0, 60 + (i - 1) * 37))
			rows[i].TextXAlignment = Enum.TextXAlignment.Left
		end
		PlotService.Boards[b.key] = rows
	end

	-- welcome sign
	local sign = part({
		Name = "Welcome",
		Size = Vector3.new(40, 10, 1),
		CFrame = CFrame.new(0, 14, -40),
		Color = Color3.fromRGB(255, 120, 80),
		Parent = world,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(800, 200)
	sg.LightInfluence = 0
	sg.Parent = sign
	label(sg, "🏫 " .. Config.GameName, Color3.new(1, 1, 1))
	local sg2 = sg:Clone()
	sg2.Face = Enum.NormalId.Front
	sg2.Parent = sign
	part({ Size = Vector3.new(1, 10, 1), Position = Vector3.new(-15, 4.5, -40), Parent = world })
	part({ Size = Vector3.new(1, 10, 1), Position = Vector3.new(15, 4.5, -40), Parent = world })

	-- plots
	for i, pos in ipairs(PLOT_POSITIONS) do
		local cf = CFrame.lookAt(pos, Vector3.new(pos.X, 0, 0))
		local model = Instance.new("Model")
		model.Name = "Plot" .. i
		model:SetAttribute("PlotIndex", i)
		model:SetAttribute("Origin", cf)
		model.Parent = world
		part({
			Name = "Base",
			Size = Vector3.new(PLOT_W, 0.6, PLOT_D),
			CFrame = cf * CFrame.new(0, 0.3, 0),
			Color = Color3.fromRGB(150, 210, 120),
			Material = Enum.Material.Grass,
			Parent = model,
		})
		-- front path + a few trees so the yard doesn't look empty
		part({ Name = "Walk", Size = Vector3.new(8, 0.2, PLOT_D / 2 + HOUSE_Z0), CFrame = cf * CFrame.new(0, 0.7, (-PLOT_D / 2 + HOUSE_Z0) / 2), Color = Color3.fromRGB(205, 195, 175), Material = Enum.Material.Cobblestone, Parent = model })
		for _, t in ipairs({ { -45, -55 }, { 45, -50 }, { -50, 20 }, { 52, 30 }, { -40, 62 }, { 40, 64 } }) do
			part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 1.6, 1.6), CFrame = cf * CFrame.new(t[1], 4.6, t[2]) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood, Parent = model })
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), CFrame = cf * CFrame.new(t[1], 10, t[2]), Color = Color3.fromRGB(80, 160, 70), Material = Enum.Material.Grass, Parent = model })
		end
		local house = Instance.new("Folder")
		house.Name = "House"
		house.Parent = model
		local live = Instance.new("Folder")
		live.Name = "Live"
		live.Parent = model
		local plot = { index = i, model = model, cf = cf, owner = nil, house = house, live = live }
		PlotService.Plots[i] = plot
		PlotService.RenderEmpty(plot)
	end
end

function PlotService.LocalCF(plot, x, y, z)
	return plot.cf * CFrame.new(x, y, z) -- +z in our layout = toward the back, -z = front
end

function PlotService.SpawnCFrame(plot)
	return PlotService.LocalCF(plot, 8, 4, HOUSE_Z0 - 16) * CFrame.Angles(0, math.pi, 0)
end

function PlotService.Claim(player)
	for _, plot in ipairs(PlotService.Plots) do
		if not plot.owner then
			plot.owner = player
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			plot.model:SetAttribute("OwnerName", player.DisplayName)
			return plot
		end
	end
	return nil
end

function PlotService.Release(plot)
	plot.owner = nil
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.model:SetAttribute("OwnerName", nil)
	PlotService.RenderEmpty(plot)
end

function PlotService.PlotOf(player)
	for _, plot in ipairs(PlotService.Plots) do
		if plot.owner == player then
			return plot
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Rendering helpers
---------------------------------------------------------------------------
local function buildSign(plot, parent, title, subtitle, likes)
	local post = part({
		Name = "SignPost",
		Size = Vector3.new(2, 16, 2),
		CFrame = PlotService.LocalCF(plot, -10, 8, HOUSE_Z0 - 20),
		Color = Color3.fromRGB(90, 60, 40),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local bb = billboard(post, UDim2.fromScale(32, 11), Vector3.new(0, 11, 0), 300)
	label(bb, title, Color3.fromRGB(255, 230, 120), UDim2.new(1, 0, 0.45, 0))
	label(bb, subtitle, Color3.new(1, 1, 1), UDim2.new(1, 0, 0.3, 0), UDim2.fromScale(0, 0.45))
	if likes then
		label(bb, "❤ " .. SchoolMath.format(likes) .. " likes", Color3.fromRGB(255, 120, 150), UDim2.new(1, 0, 0.25, 0), UDim2.fromScale(0, 0.75))
	end
	return post
end

function PlotService.RenderEmpty(plot)
	plot.house:ClearAllChildren()
	plot.live:ClearAllChildren()
	plot.signature = nil
	plot.rooms = nil
	buildSign(plot, plot.live, "🏠 Empty Lot", "Waiting for a new headmaster...")
end

local function bed(parent, cf, color)
	part({ Name = "BedFrame", Size = Vector3.new(3.6, 1.2, 7), CFrame = cf * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(110, 75, 50), Material = Enum.Material.Wood, Parent = parent })
	part({ Name = "Mattress", Size = Vector3.new(3.2, 0.6, 6.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = color, Material = Enum.Material.Fabric, Parent = parent })
	part({ Name = "Pillow", Size = Vector3.new(2.6, 0.5, 1.4), CFrame = cf * CFrame.new(0, 2, 2.4), Color = Color3.new(1, 1, 1), Material = Enum.Material.Fabric, Parent = parent })
end

local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(235, 190, 150),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(150, 100, 70),
	Color3.fromRGB(100, 70, 50),
}

function PlotService.BuildStudentModel(uid, student, cf)
	local def = Config.StudentById[student.id]
	local rarity = Config.Rarities[def.rarity]
	local pers = Config.Personalities[def.personality]
	local seed = 0
	for i = 1, #uid do
		seed += string.byte(uid, i) * i
	end
	local skin = SKIN[(seed % #SKIN) + 1]

	local m = Instance.new("Model")
	m.Name = def.name
	local root = part({ Name = "Root", Size = Vector3.new(2, 2, 1), CFrame = cf * CFrame.new(0, 3, 0), Color = pers.color, Parent = m })
	m.PrimaryPart = root
	local function limb(name, size, offset, color)
		local p = part({ Name = name, Size = size, CFrame = root.CFrame * offset, Color = color, Parent = m })
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
		return p
	end
	root.CanCollide = false
	local head = limb("Head", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 1.65, 0), skin)
	limb("LArm", Vector3.new(0.8, 1.9, 0.8), CFrame.new(-1.4, 0, 0), skin)
	limb("RArm", Vector3.new(0.8, 1.9, 0.8), CFrame.new(1.4, 0, 0), skin)
	limb("LLeg", Vector3.new(0.9, 2, 0.9), CFrame.new(-0.5, -2, 0), Color3.fromRGB(50, 50, 70))
	limb("RLeg", Vector3.new(0.9, 2, 0.9), CFrame.new(0.5, -2, 0), Color3.fromRGB(50, 50, 70))
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	if def.personality == "Royal" then
		limb("Crown", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, 2.55, 0), Color3.fromRGB(255, 210, 60)).Material = Enum.Material.Neon
	elseif def.personality == "Nerd" then
		limb("Glasses", Vector3.new(1.2, 0.3, 0.1), CFrame.new(0, 1.8, -0.7), Color3.fromRGB(20, 20, 20))
	elseif def.personality == "Musician" then
		limb("Guitar", Vector3.new(0.6, 2.2, 0.3), CFrame.new(0.4, -0.2, -0.7) * CFrame.Angles(0, 0, 0.6), Color3.fromRGB(180, 60, 40))
	elseif def.personality == "Jock" then
		limb("Cap", Vector3.new(1.4, 0.4, 1.6), CFrame.new(0, 2.4, -0.2), Color3.fromRGB(220, 50, 50))
	end

	local rank = rarity.rank
	if rank >= 5 then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = 10
		light.Brightness = 2
		light.Parent = root
		local aura = Instance.new("ParticleEmitter")
		aura.Color = ColorSequence.new(rarity.color)
		aura.LightEmission = 1
		aura.Size = NumberSequence.new(0.3, 0)
		aura.Rate = 8
		aura.Lifetime = NumberRange.new(1, 1.5)
		aura.Speed = NumberRange.new(1, 2)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Parent = root
	end
	if student.shiny then
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = Color3.fromRGB(255, 255, 180)
		sp.Parent = head
	end

	local bb = billboard(head, UDim2.fromOffset(160, 44), Vector3.new(0, 2.2, 0), 60)
	label(bb, (student.shiny and "✨" or "") .. def.name, Color3.new(1, 1, 1), UDim2.fromScale(1, 0.55))
	local r = label(bb, pers.emoji .. " " .. def.rarity, rarity.color, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55))
	r.Name = "RarityLabel"

	m:SetAttribute("StudentUid", uid)
	CollectionService:AddTag(m, "Student")
	return m
end

---------------------------------------------------------------------------
-- Room props. Room frame: local X (u) runs from the hallway wall (u = 0) to
-- the outside wall (u = ROOM_U), local Z (v) along the hallway, Y = floor.
---------------------------------------------------------------------------
local WOOD = Color3.fromRGB(130, 90, 60)
local DARK = Color3.fromRGB(40, 40, 50)

local function prop(parent, rcf, u, h, v, size, color, extra)
	local props = { Name = "Prop", Size = size, CFrame = rcf * CFrame.new(u, h, v), Color = color, Parent = parent }
	for k, val in pairs(extra or {}) do
		props[k] = val
	end
	if props.Rot then
		props.CFrame *= props.Rot
		props.Rot = nil
	end
	return part(props)
end

-- cylinder standing upright (Roblox cylinders run along local X)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local function cyl(parent, rcf, u, h, v, height, dia, color, extra)
	local e = { Shape = Enum.PartType.Cylinder, Rot = UPRIGHT }
	for k, val in pairs(extra or {}) do
		e[k] = val
	end
	return prop(parent, rcf, u, h, v, Vector3.new(height, dia, dia), color, e)
end

local function light(p, range, color)
	local l = Instance.new("PointLight")
	l.Range = range or 14
	l.Brightness = 1.2
	l.Color = color or Color3.fromRGB(255, 235, 200)
	l.Parent = p
end

local BED_TURN = CFrame.Angles(0, math.pi / 2, 0) -- bed's long axis along u, pillow toward the outside wall

local FacilityProps = {}

function FacilityProps.cafeteria(m, r)
	prop(m, r, ROOM_U - 1.4, 1.75, 0, Vector3.new(2, 3.5, 13), Color3.fromRGB(230, 230, 235), { Material = Enum.Material.Marble })
	for i, c in ipairs({ Color3.fromRGB(255, 80, 60), Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 220, 90), Color3.fromRGB(255, 150, 200) }) do
		prop(m, r, ROOM_U - 1.4, 3.8, -6 + i * 2.4, Vector3.new(1.2, 0.6, 1.2), c, { Material = Enum.Material.Neon })
	end
	for _, u in ipairs({ 5.5, 11 }) do
		prop(m, r, u, 2.6, 0, Vector3.new(3, 0.3, 8), Color3.fromRGB(240, 240, 240))
		prop(m, r, u, 1.25, 0, Vector3.new(0.6, 2.5, 0.6), DARK)
		for _, side in ipairs({ -1, 1 }) do
			prop(m, r, u + side * 2.2, 1, 0, Vector3.new(1, 0.4, 8), WOOD, { Material = Enum.Material.Wood })
		end
	end
end

function FacilityProps.library(m, r)
	local colors = { Color3.fromRGB(180, 50, 50), Color3.fromRGB(50, 90, 180), Color3.fromRGB(60, 150, 70), Color3.fromRGB(220, 170, 60), Color3.fromRGB(120, 60, 150) }
	for i, u in ipairs({ 7, 11, 15 }) do
		prop(m, r, u, 3.2, 1.5, Vector3.new(1.2, 6.4, 10), WOOD, { Material = Enum.Material.Wood })
		for row = 1, 3 do
			prop(m, r, u, row * 1.9 - 0.2, 1.5, Vector3.new(1.4, 1.1, 9.4), colors[(i + row) % #colors + 1])
		end
	end
	prop(m, r, 3, 1.2, -5, Vector3.new(2.6, 1.6, 2.6), Color3.fromRGB(140, 40, 50), { Material = Enum.Material.Fabric })
	prop(m, r, 2, 2.6, -5, Vector3.new(0.6, 2.4, 2.6), Color3.fromRGB(140, 40, 50), { Material = Enum.Material.Fabric })
end

function FacilityProps.gym(m, r)
	prop(m, r, 10, 0.3, 0, Vector3.new(14, 0.2, 13), Color3.fromRGB(60, 90, 160), { Material = mat("Rubber") })
	prop(m, r, 8, 1.1, -4, Vector3.new(4, 1, 1.2), DARK)
	prop(m, r, 8, 2.8, -4, Vector3.new(0.25, 0.25, 5), Color3.fromRGB(180, 180, 190), { Material = Enum.Material.Metal })
	for _, side in ipairs({ -1, 1 }) do
		cyl(m, r, 8, 2.8, -4 + side * 2.3, 0.5, 1.6, DARK, { Rot = CFrame.Angles(0, math.pi / 2, 0) })
	end
	prop(m, r, 14, 0.9, 4, Vector3.new(5, 1, 2.4), DARK)
	prop(m, r, 16.2, 2.8, 4, Vector3.new(0.4, 3, 2.4), DARK)
	prop(m, r, 16, 4.2, 4, Vector3.new(0.6, 0.8, 1.6), Color3.fromRGB(60, 255, 120), { Material = Enum.Material.Neon })
	cyl(m, r, 4, 5, 5, 4.5, 1.8, Color3.fromRGB(200, 40, 40), { Material = Enum.Material.Leather })
end

function FacilityProps.arcade(m, r)
	local screens = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 220, 60) }
	for i, v in ipairs({ -5, 0, 5 }) do
		prop(m, r, ROOM_U - 1.6, 3, v, Vector3.new(2.2, 6, 2.8), DARK)
		prop(m, r, ROOM_U - 2.75, 4, v, Vector3.new(0.1, 1.8, 2.2), screens[i], { Material = Enum.Material.Neon })
		prop(m, r, ROOM_U - 3, 2.6, v, Vector3.new(0.8, 0.3, 2.2), screens[i])
	end
	prop(m, r, 6, 1.8, -5, Vector3.new(4.5, 1.2, 2.4), Color3.fromRGB(240, 60, 60))
	prop(m, r, 6, 0.3, 4, Vector3.new(6, 0.1, 6), Color3.fromRGB(120, 60, 255), { Material = Enum.Material.Neon, Transparency = 0.4 })
end

function FacilityProps.artstudio(m, r)
	local canvases = { Color3.fromRGB(255, 120, 120), Color3.fromRGB(120, 200, 255), Color3.fromRGB(255, 230, 120) }
	for i, v in ipairs({ -5, 0, 5 }) do
		prop(m, r, 9, 2.5, v, Vector3.new(0.3, 5, 0.3), WOOD, { Rot = CFrame.Angles(0, 0, 0.15) })
		prop(m, r, 8.6, 4, v, Vector3.new(0.15, 2.6, 3), canvases[i])
	end
	for i, c in ipairs({ Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 160, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 220, 120) }) do
		cyl(m, r, 4 + i * 2.5, 0.3, (i % 2 == 0) and 3 or -3, 0.05, 1.6, c)
	end
	prop(m, r, ROOM_U - 2, 1.5, 0, Vector3.new(2.5, 3, 8), WOOD, { Material = Enum.Material.Wood })
end

function FacilityProps.musichall(m, r)
	prop(m, r, ROOM_U - 3.5, 0.6, 0, Vector3.new(6, 1.2, 15), Color3.fromRGB(90, 40, 40), { Material = Enum.Material.WoodPlanks })
	prop(m, r, 9, 1.5, -4, Vector3.new(3, 2.6, 4.5), Color3.fromRGB(15, 15, 20), { Reflectance = 0.2 })
	prop(m, r, 7.4, 2.85, -4, Vector3.new(0.5, 0.1, 4.2), Color3.new(1, 1, 1))
	for i, v in ipairs({ -1.5, 1.5 }) do
		cyl(m, r, ROOM_U - 3.5, 1.9 + i * 0.2, v, 1.2, 1.8, Color3.fromRGB(220, 60, 60))
	end
	for _, v in ipairs({ -6.5, 6.5 }) do
		prop(m, r, ROOM_U - 1.5, 3.2, v, Vector3.new(1.6, 4, 1.6), DARK)
	end
end

function FacilityProps.pool(m, r)
	local water = prop(m, r, 9.5, 0.75, 0, Vector3.new(13, 0.9, 12), Color3.fromRGB(60, 170, 255), { Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false })
	water.Name = "Water"
	for _, rim in ipairs({ { 9.5, -6.4, 14, 0.8 }, { 9.5, 6.4, 14, 0.8 } }) do
		prop(m, r, rim[1], 0.6, rim[2], Vector3.new(rim[3], 1.2, rim[4]), Color3.fromRGB(240, 240, 240))
	end
	for _, u in ipairs({ 2.6, 16.4 }) do
		prop(m, r, u, 0.6, 0, Vector3.new(0.8, 1.2, 13.6), Color3.fromRGB(240, 240, 240))
	end
	prop(m, r, 14, 1.6, 0, Vector3.new(5, 0.3, 1.4), Color3.fromRGB(80, 160, 255))
end

function FacilityProps.ballroom(m, r)
	for i = 0, 3 do
		for j = 0, 3 do
			prop(m, r, 4.5 + i * 3, 0.25, -4.5 + j * 3, Vector3.new(3, 0.1, 3), (i + j) % 2 == 0 and Color3.new(1, 1, 1) or Color3.fromRGB(20, 20, 25), { Reflectance = 0.2 })
		end
	end
	local ch = prop(m, r, 9, 8.6, 0, Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(255, 230, 160), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
	light(ch, 22)
	for _, v in ipairs({ -6.5, 6.5 }) do
		cyl(m, r, ROOM_U - 2, 5.5, v, 11, 1.4, Color3.fromRGB(240, 200, 90), { Material = Enum.Material.Marble })
	end
end

function FacilityProps.observatory(m, r)
	cyl(m, r, 10, 1.5, 0, 3, 2.2, DARK)
	prop(m, r, 11, 4.2, 0, Vector3.new(6, 1.1, 1.1), Color3.fromRGB(200, 200, 215), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Rot = CFrame.Angles(0, 0, 0.6) })
	local rng = Random.new(7)
	for _ = 1, 14 do
		prop(m, r, rng:NextNumber(2, ROOM_U - 2), WALL_H - 0.4, rng:NextNumber(-7, 7), Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(255, 250, 200), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanCollide = false })
	end
	prop(m, r, 4, 1.7, -5, Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(70, 140, 220), { Shape = Enum.PartType.Ball })
end

local function commonProps(m, r)
	prop(m, r, ROOM_U - 0.6, 4.4, 0, Vector3.new(0.3, 3.2, 6), DARK)
	prop(m, r, ROOM_U - 0.8, 4.4, 0, Vector3.new(0.05, 2.8, 5.6), Color3.fromRGB(90, 160, 255), { Material = Enum.Material.Neon })
	local sofa = Color3.fromRGB(90, 130, 200)
	prop(m, r, 8.5, 0.9, 0, Vector3.new(2.6, 1.4, 8), sofa, { Material = Enum.Material.Fabric })
	prop(m, r, 7.4, 2.2, 0, Vector3.new(0.8, 2, 8), sofa, { Material = Enum.Material.Fabric })
	prop(m, r, 12.5, 1.1, 0, Vector3.new(2.2, 0.3, 4), WOOD, { Material = Enum.Material.Wood })
	cyl(m, r, 11, 0.28, 0, 0.12, 9, Color3.fromRGB(230, 200, 120), { Material = Enum.Material.Fabric })
	for _, v in ipairs({ -6.8, 6.8 }) do
		cyl(m, r, ROOM_U - 1.4, 0.9, v, 1.6, 1.6, Color3.fromRGB(180, 100, 60))
		prop(m, r, ROOM_U - 1.4, 2.8, v, Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(70, 160, 70), { Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
	end
	prop(m, r, 3, 1, -6, Vector3.new(2.6, 2, 2.6), Color3.fromRGB(230, 120, 60), { Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric })
end

-- your own room: furniture pieces at fixed spots
local FurnitureProps = {}
function FurnitureProps.rug(m, r)
	cyl(m, r, 9, 0.28, 1, 0.12, 7, Color3.fromRGB(150, 90, 200), { Material = Enum.Material.Fabric })
end
function FurnitureProps.plant(m, r)
	cyl(m, r, 16.4, 0.9, 7, 1.6, 1.6, Color3.fromRGB(190, 110, 70))
	prop(m, r, 16.4, 2.8, 7, Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(70, 160, 70), { Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
end
function FurnitureProps.lamp(m, r)
	prop(m, r, 1.5, 2.7, 7, Vector3.new(0.3, 5, 0.3), DARK)
	local shade = cyl(m, r, 1.5, 5.5, 7, 1.2, 1.6, Color3.fromRGB(255, 240, 200), { Material = Enum.Material.Neon })
	light(shade, 16)
end
function FurnitureProps.desk(m, r)
	prop(m, r, 11, 3, 6.6, Vector3.new(4, 0.3, 2), WOOD, { Material = Enum.Material.Wood })
	for _, du in ipairs({ -1.8, 1.8 }) do
		prop(m, r, 11 + du, 1.5, 6.6, Vector3.new(0.3, 3, 1.8), WOOD, { Material = Enum.Material.Wood })
	end
	prop(m, r, 11, 3.6, 6.9, Vector3.new(1.6, 1, 0.1), DARK)
	prop(m, r, 11, 1.5, 4.8, Vector3.new(1.6, 0.3, 1.6), Color3.fromRGB(200, 60, 60))
	prop(m, r, 11, 2.6, 4.1, Vector3.new(1.6, 2, 0.3), Color3.fromRGB(200, 60, 60))
end
function FurnitureProps.bookshelf(m, r)
	prop(m, r, 5, 3.2, 7.3, Vector3.new(3, 6.4, 1), WOOD, { Material = Enum.Material.Wood })
	for row, c in ipairs({ Color3.fromRGB(180, 50, 50), Color3.fromRGB(50, 90, 180), Color3.fromRGB(220, 170, 60) }) do
		prop(m, r, 5, row * 1.9 - 0.2, 6.85, Vector3.new(2.6, 1.1, 0.2), c)
	end
end
function FurnitureProps.beanbag(m, r)
	prop(m, r, 6.5, 1.2, -2, Vector3.new(3, 2.2, 3), Color3.fromRGB(255, 150, 50), { Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric })
end
function FurnitureProps.gaming(m, r)
	prop(m, r, 0.6, 4, -5.2, Vector3.new(0.3, 2.4, 4), DARK)
	prop(m, r, 0.78, 4, -5.2, Vector3.new(0.05, 2.1, 3.7), Color3.fromRGB(80, 255, 200), { Material = Enum.Material.Neon })
	prop(m, r, 1, 1.2, -5.2, Vector3.new(1.4, 2.4, 3), WOOD)
	prop(m, r, 4, 1.4, -5.2, Vector3.new(1.6, 0.4, 1.6), Color3.fromRGB(30, 30, 30))
	prop(m, r, 4.8, 2.6, -5.2, Vector3.new(0.3, 2.4, 1.6), Color3.fromRGB(220, 40, 80))
end
function FurnitureProps.aquarium(m, r)
	prop(m, r, 16.8, 0.7, -5.6, Vector3.new(1.6, 1.2, 4), WOOD)
	prop(m, r, 16.8, 2.15, -5.6, Vector3.new(1.5, 1.7, 3.8), Color3.fromRGB(80, 170, 255), { Material = Enum.Material.Glass, Transparency = 0.4 })
	for i, c in ipairs({ Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60) }) do
		prop(m, r, 16.8, 2 + i * 0.3, -6.5 + i * 1.3, Vector3.new(0.3, 0.3, 0.6), c, { Material = Enum.Material.Neon, CanCollide = false })
	end
end
function FurnitureProps.trophy(m, r)
	prop(m, r, 7.9, 2.3, 7.3, Vector3.new(2, 4.6, 1), WOOD, { Material = Enum.Material.Wood })
	for i = 0, 2 do
		cyl(m, r, 7.3 + i * 0.6, 4.95, 7.2, 0.7, 0.5, Color3.fromRGB(255, 210, 60), { Material = Enum.Material.Neon })
	end
	prop(m, r, 7.9, 2.3, 6.75, Vector3.new(1.8, 4.2, 0.1), Color3.fromRGB(200, 230, 255), { Material = Enum.Material.Glass, Transparency = 0.6 })
end

---------------------------------------------------------------------------
-- House render
---------------------------------------------------------------------------
local function roomFrame(plot, slotFloor, side, row)
	local zc = HOUSE_Z0 + ROOM_V * (row + 0.5)
	return PlotService.LocalCF(plot, side * HALL_W / 2, floorY(slotFloor), zc) * CFrame.Angles(0, side == 1 and 0 or math.pi, 0)
end

-- where students and the client need to know about a room (world space)
local function roomInfo(plot, rcf, key, slotFloor, hangout)
	return {
		key = key,
		floor = slotFloor,
		rcf = rcf,
		center = (rcf * CFrame.new(ROOM_U * 0.36, 0, 0)).Position,
		u = rcf.XVector,
		v = rcf.ZVector,
		range = Vector3.new(ROOM_U * 0.22, 0, ROOM_V / 2 - 2.5),
		door = (rcf * CFrame.new(1.5, 0, 0)).Position,
		hall = (rcf * CFrame.new(-3, 0, 0)).Position,
		hangout = hangout,
	}
end

local function tagRoom(model, plot, info)
	model:SetAttribute("PlotIndex", plot.index)
	model:SetAttribute("Floor", info.floor)
	model:SetAttribute("Key", info.key)
	model:SetAttribute("Center", info.center)
	model:SetAttribute("U", info.u)
	model:SetAttribute("V", info.v)
	model:SetAttribute("Range", info.range)
	model:SetAttribute("Door", info.door)
	model:SetAttribute("Hall", info.hall)
	if info.hangout then
		model:SetAttribute("Hangout", true)
		CollectionService:AddTag(model, "HangoutRoom")
	end
end

-- floor, four walls (hallway wall has the door), window in the outside wall
local function buildShell(m, rcf, row, side, wallStyle, floorStyle, hallStyle, opts)
	part({ Name = "Floor", Size = Vector3.new(ROOM_U, 0.2, ROOM_V), CFrame = rcf * CFrame.new(ROOM_U / 2, 0.1, 0), Style = floorStyle, Parent = m })
	local inner = { Name = "Wall", Style = wallStyle }
	local hallSide = { Name = "HallWall", Style = hallStyle }
	local door = opts.door and { { c = 0, w = DOOR_W, b = 0, t = DOOR_H } } or nil
	wall(m, rcf * CFrame.new(0.2, 0, 0) * ALONG_Z, -ROOM_V / 2, ROOM_V / 2, 0, WALL_H, 0.4, inner, door and table.clone(door))
	wall(m, rcf * CFrame.new(-0.2, 0, 0) * ALONG_Z, -ROOM_V / 2, ROOM_V / 2, 0, WALL_H, 0.4, hallSide, door and table.clone(door))
	local window = opts.window ~= false and { { c = 0, w = 6, b = 3, t = 8 } } or nil
	wall(m, rcf * CFrame.new(ROOM_U - 0.2, 0, 0) * ALONG_Z, -ROOM_V / 2, ROOM_V / 2, 0, WALL_H, 0.4, inner, window)
	-- side walls; the one at the front/back of the house gets a window
	local front, back = -side * ROOM_V / 2, side * ROOM_V / 2
	for _, v in ipairs({ front, back }) do
		local outside = (v == front and row == 0) or (v == back and row == ROWS - 1)
		local inset = v > 0 and v - 0.2 or v + 0.2
		wall(m, rcf * CFrame.new(0, 0, inset), 0.4, ROOM_U - 0.4, 0, WALL_H, 0.4, inner, outside and { { c = ROOM_U / 2, w = 6, b = 3, t = 8 } } or nil)
	end
end

local function buildStoryboard(plot, m, rcf, data)
	local frame = part({ Name = "BoardFrame", Size = Vector3.new(0.2, 7.2, 12.6), CFrame = rcf * CFrame.new(ROOM_U - 0.5, 6.3, 0), Color = WOOD, Material = Enum.Material.Wood, Parent = m })
	local board = part({ Name = "Storyboard", Size = Vector3.new(0.2, 6.6, 12), CFrame = rcf * CFrame.new(ROOM_U - 0.65, 6.3, 0), Color = Color3.fromRGB(190, 140, 90), Material = mat("Cardboard"), Parent = m })
	local _ = frame
	local notes = House.notes(data)
	local header = part({ Name = "BoardHeader", Size = Vector3.new(0.2, 1, 8), CFrame = rcf * CFrame.new(ROOM_U - 0.5, 10.3, 0), Color = Color3.fromRGB(250, 245, 230), Parent = m })
	local hg = surface(header, Enum.NormalId.Left, Vector2.new(640, 80))
	local more = #notes > 12 and string.format("  (+%d more)", #notes - 12) or ""
	label(hg, "📌 SCHOOL PLANS" .. more, Color3.fromRGB(60, 40, 30)).TextStrokeTransparency = 1

	local rng = Random.new(#notes * 31 + #data.rooms)
	for i = 1, math.min(12, #notes) do
		local n = notes[i]
		local col, rowIdx = (i - 1) % 4, math.floor((i - 1) / 4)
		local v = -4.5 + col * 3
		local h = 8.6 - rowIdx * 2.25
		local note = part({
			Name = "Note",
			Size = Vector3.new(0.08, 1.95, 2.7),
			CFrame = rcf * CFrame.new(ROOM_U - 0.8, h, v) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, 0),
			Color = House.NoteColors[n.kind],
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = m,
		})
		note:SetAttribute("NoteKey", n.key)
		note:SetAttribute("OwnerUserId", plot.owner.UserId)
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 30
		cd.Parent = note
		CollectionService:AddTag(note, "NoteClick")
		local sg = surface(note, Enum.NormalId.Left, Vector2.new(270, 195))
		local ink = Color3.fromRGB(50, 40, 40)
		local t = label(sg, n.emoji .. " " .. n.title, ink, UDim2.new(1, -16, 0.42, 0), UDim2.new(0, 8, 0, 8))
		t.TextStrokeTransparency = 1
		local d = label(sg, n.text, Color3.fromRGB(90, 80, 80), UDim2.new(1, -16, 0.26, 0), UDim2.new(0, 8, 0.44, 0))
		d.TextStrokeTransparency = 1
		local c = label(sg, "$" .. SchoolMath.format(n.cost), Color3.fromRGB(20, 130, 50), UDim2.new(1, -16, 0.24, 0), UDim2.new(0, 8, 0.72, 0))
		c.TextStrokeTransparency = 1
		part({ Name = "Pin", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = rcf * CFrame.new(ROOM_U - 0.9, h + 0.8, v), Color = Color3.fromRGB(220, 40, 40), CanCollide = false, Parent = m })
	end
	if #notes == 0 then
		local sg = surface(board, Enum.NormalId.Left, Vector2.new(600, 330))
		label(sg, "🎉 Everything is built!", Color3.fromRGB(60, 40, 30)).TextStrokeTransparency = 1
	end
	local pp = prompt(board, "📌 Open storyboard", "School plans", 14)
	pp:SetAttribute("OwnerUserId", plot.owner.UserId)
	CollectionService:AddTag(pp, "StoryboardPrompt")
end

local function signature(plot, data)
	local parts = { plot.owner.DisplayName, table.concat(data.order, ",") }
	for _, room in ipairs(data.rooms) do
		table.insert(parts, tostring(room.tier))
	end
	local keys = {}
	for area, st in pairs(data.styles) do
		table.insert(keys, area .. "=" .. tostring(st.wall) .. "/" .. tostring(st.floor) .. "/" .. tostring(st.roof))
	end
	for fid, shown in pairs(data.furniture) do
		table.insert(keys, "furn:" .. fid .. "=" .. tostring(shown))
	end
	table.sort(keys)
	table.insert(parts, table.concat(keys, ";"))
	for _, n in ipairs(House.notes(data)) do
		table.insert(parts, n.key .. n.cost)
	end
	return table.concat(parts, "|")
end

local function levelFolder(parent, level)
	local f = Instance.new("Folder")
	f.Name = "L" .. level
	f:SetAttribute("Level", level)
	f.Parent = parent
	return f
end

-- Walls, floors, stairs, props: only rebuilt when the house itself changes.
local function renderStructure(plot, data)
	local root = plot.house
	root:ClearAllChildren()
	local floors = House.floorCount(data)
	local levels = {}
	for f = 0, floors do
		levels[f] = levelFolder(root, f)
	end
	local ext = House.style(data, "exterior", "wall")
	local hall = House.style(data, "hall", "wall")
	local hallFloor = House.style(data, "hall", "floor")
	local concrete = { Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Concrete }
	local L = function(x, y, z)
		return PlotService.LocalCF(plot, x, y, z)
	end
	local function slab(parent, x0, x1, z0, z1, y0, y1)
		part({ Name = "Slab", Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame = L((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Color = concrete.Color, Material = concrete.Material, Parent = parent })
	end
	plot.rooms = {}

	for f = 0, floors - 1 do
		local lv = levels[f]
		local y = floorY(f)
		if f == 0 then
			slab(lv, -HALF_X, HALF_X, HOUSE_Z0, HOUSE_Z1, GROUND_Y, y)
			slab(lv, -HALL_W / 2, HALL_W / 2, HOUSE_Z1, TOWER_Z1, GROUND_Y, y)
		else
			slab(lv, -HALF_X, HALF_X, HOUSE_Z0, HOUSE_Z1, y - 1, y)
			slab(lv, 0, HALL_W / 2, HOUSE_Z1, TOWER_Z1, y - 1, y)
			slab(lv, -HALL_W / 2, 0, HOUSE_Z1, STAIR_Z0, y - 1, y)
			slab(lv, -HALL_W / 2, 0, STAIR_Z1, TOWER_Z1, y - 1, y)
		end
		part({ Name = "HallFloor", Size = Vector3.new(HALL_W, 0.2, HOUSE_Z1 - HOUSE_Z0), CFrame = L(0, y + 0.1, (HOUSE_Z0 + HOUSE_Z1) / 2), Style = hallFloor, Parent = lv })

		-- outside walls (cover the slab edge too)
		local h0 = f == 0 and GROUND_Y or y - 1
		local h1 = floorY(f + 1) - 1
		local wb, wt = y + 3, y + 8
		local exProps = { Name = "Outside", Style = ext }
		local frontHoles = { { c = -(HALL_W / 2 + ROOM_U / 2), w = 6, b = wb, t = wt, glass = true }, { c = HALL_W / 2 + ROOM_U / 2, w = 6, b = wb, t = wt, glass = true } }
		if f == 0 then
			table.insert(frontHoles, { c = 0, w = 6, b = h0, t = y + DOOR_H + 0.5 })
		else
			table.insert(frontHoles, { c = 0, w = 6, b = wb, t = wt, glass = true })
		end
		wall(lv, L(0, 0, HOUSE_Z0 - 0.3), -HALF_X - 0.6, HALF_X + 0.6, h0, h1, 0.6, exProps, frontHoles)
		for _, side in ipairs({ -1, 1 }) do
			local holes = {}
			for r = 0, ROWS - 1 do
				table.insert(holes, { c = HOUSE_Z0 + ROOM_V * (r + 0.5), w = 6, b = wb, t = wt, glass = true })
			end
			wall(lv, L(side * (HALF_X + 0.3), 0, 0) * ALONG_Z, HOUSE_Z0, HOUSE_Z1 + 0.6, h0, h1, 0.6, exProps, holes)
			-- back of the room block, beside the stairwell
			local xa, xb = side * (HALL_W / 2 + 0.6), side * (HALF_X + 0.6)
			local mid = (xa + xb) / 2
			wall(lv, L(mid, 0, HOUSE_Z1 + 0.3), -math.abs(xb - xa) / 2, math.abs(xb - xa) / 2, h0, h1, 0.6, exProps, { { c = side * (HALL_W / 2 + ROOM_U / 2) - mid, w = 6, b = wb, t = wt, glass = true } })
			-- stairwell sides
			wall(lv, L(side * (HALL_W / 2 + 0.3), 0, 0) * ALONG_Z, HOUSE_Z1, TOWER_Z1 + 0.6, h0, h1, 0.6, exProps)
		end
		wall(lv, L(0, 0, TOWER_Z1 + 0.3), -HALL_W / 2 - 0.6, HALL_W / 2 + 0.6, h0, h1, 0.6, exProps, { { c = HALL_W / 4, w = 3, b = wb, t = wt, glass = true } })

		-- stairs up: an invisible ramp you walk on, with open steps drawn over it
		local rail = { Name = "Rail", Color = Color3.fromRGB(190, 230, 255), Material = Enum.Material.Glass, Transparency = 0.5 }
		if f < floors - 1 then
			local run, rise = STAIR_Z1 - STAIR_Z0, FLOOR_H
			local angle = math.atan2(rise, run)
			part({
				Name = "Ramp",
				Size = Vector3.new(HALL_W / 2, 0.5, math.sqrt(run * run + rise * rise) + 0.6),
				CFrame = L(-HALL_W / 4, y + rise / 2, (STAIR_Z0 + STAIR_Z1) / 2) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -0.25, 0),
				Transparency = 1,
				Parent = lv,
			})
			local steps = 12
			for i = 1, steps do
				local top = y + (i - 0.5) * rise / steps
				part({ Name = "Step", Size = Vector3.new(HALL_W / 2 - 0.4, 0.5, run / steps), CFrame = L(-HALL_W / 4, top - 0.25, STAIR_Z0 + (i - 0.5) * run / steps), Color = WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = lv })
			end
			local r = table.clone(rail)
			r.Size = Vector3.new(0.3, 3, run)
			r.CFrame = L(0, y + 1.5, (STAIR_Z0 + STAIR_Z1) / 2)
			r.Parent = lv
			part(r)
		end
		if f > 0 and f == floors - 1 then
			-- top floor: fence off the stairwell opening
			local r = table.clone(rail)
			r.Size = Vector3.new(0.3, 3, STAIR_Z1 - STAIR_Z0)
			r.CFrame = L(0, y + 1.5, (STAIR_Z0 + STAIR_Z1) / 2)
			r.Parent = lv
			part(r)
			local cap = table.clone(rail)
			cap.Size = Vector3.new(HALL_W / 2, 3, 0.3)
			cap.CFrame = L(-HALL_W / 4, y + 1.5, STAIR_Z0)
			cap.Parent = lv
			part(cap)
		end

		-- the hallway is a hangout spot too
		local hallModel = Instance.new("Model")
		hallModel.Name = "Hallway"
		hallModel.Parent = lv
		tagRoom(hallModel, plot, {
			key = "hall" .. f,
			floor = f,
			center = L(0, y, (HOUSE_Z0 + HOUSE_Z1) / 2).Position,
			u = plot.cf.XVector,
			v = plot.cf.ZVector,
			range = Vector3.new(HALL_W / 2 - 2, 0, (HOUSE_Z1 - HOUSE_Z0) / 2 - 3),
			door = L(0, y, (HOUSE_Z0 + HOUSE_Z1) / 2).Position,
			hall = L(0, y, (HOUSE_Z0 + HOUSE_Z1) / 2).Position,
			hangout = true,
		})
		hallModel:SetAttribute("IsHall", true)
	end

	-- rooms
	local slots = House.slots(data)
	local used = {}
	for _, s in ipairs(slots) do
		used[s.slot] = s
	end
	for n = 1, floors * Config.SlotsPerFloor do
		local slotFloor, side, row = House.slotPosition(n)
		local s = used[n]
		local rcf = roomFrame(plot, slotFloor, side, row)
		local m = Instance.new("Model")
		m.Parent = levels[slotFloor]
		if not s then
			m.Name = "FutureRoom"
			buildShell(m, rcf, row, side, hall, hallFloor, hall, { door = false })
			local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.6, 6), CFrame = rcf * CFrame.new(-0.45, 5, 0), Color = Color3.fromRGB(250, 220, 120), Parent = m })
			local sg = surface(plate, Enum.NormalId.Left, Vector2.new(600, 160))
			label(sg, "🚧 Space for a new room", Color3.fromRGB(60, 40, 30)).TextStrokeTransparency = 1
		else
			m.Name = s.key
			local wallStyle = House.style(data, s.key, "wall")
			local floorStyle = House.style(data, s.key, "floor")
			local isMe = s.kind == "me"
			buildShell(m, rcf, row, side, wallStyle, floorStyle, hall, { door = true, window = not (isMe or s.kind == "common") })
			local info = roomInfo(plot, rcf, s.key, slotFloor, s.kind == "common" or s.kind == "facility")
			plot.rooms[s.key] = info
			tagRoom(m, plot, info)
			CollectionService:AddTag(m, "HouseRoom")
			if s.kind == "me" then
				m:SetAttribute("IsMyRoom", true)
				m:SetAttribute("OwnerUserId", plot.owner.UserId)
				bed(m, rcf * CFrame.new(12, 0.2, -5.8) * BED_TURN, Color3.fromRGB(255, 200, 80))
				for id, shown in pairs(data.furniture) do
					if shown and FurnitureProps[id] then
						FurnitureProps[id](m, rcf)
					end
				end
				buildStoryboard(plot, m, rcf, data)
			elseif s.kind == "common" then
				commonProps(m, rcf)
			elseif s.kind == "facility" and FacilityProps[s.id] then
				FacilityProps[s.id](m, rcf)
			elseif s.kind == "dorm" then
				local room = data.rooms[s.index]
				if room and room.tier >= 2 then
					cyl(m, rcf, 7, 0.28, 0, 0.12, 6, Config.Personalities.Artist.color, { Material = Enum.Material.Fabric })
				end
				if room and room.tier >= 3 then
					local lamp = prop(m, rcf, ROOM_U / 2, WALL_H - 1.2, 0, Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(255, 240, 200), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanCollide = false })
					light(lamp, 16)
				end
				if room and room.tier >= 4 then
					for _, v in ipairs({ -ROOM_V / 2 + 0.5, ROOM_V / 2 - 0.5 }) do
						prop(m, rcf, ROOM_U / 2, WALL_H - 0.3, v, Vector3.new(ROOM_U - 1, 0.4, 0.3), Color3.fromRGB(255, 210, 60), { Material = Enum.Material.Neon, CanCollide = false })
					end
				end
			end
		end
	end

	-- roof
	local lv = levels[floors]
	local top = floorY(floors) - 1
	local roof = House.style(data, "exterior", "roof")
	slab(lv, -HALF_X - 0.6, HALF_X + 0.6, HOUSE_Z0 - 0.6, HOUSE_Z1 + 0.6, top, top + 1)
	slab(lv, -HALL_W / 2 - 0.6, HALL_W / 2 + 0.6, HOUSE_Z1, TOWER_Z1 + 0.6, top, top + 1)
	local ridge, half = 7, HALF_X + 1.5
	local tilt = math.atan2(ridge, half)
	local len = HOUSE_Z1 - HOUSE_Z0 + 2.4
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Roof", Size = Vector3.new(math.sqrt(half * half + ridge * ridge) + 0.4, 0.8, len), CFrame = L(side * half / 2, top + 1 + ridge / 2, (HOUSE_Z0 + HOUSE_Z1) / 2) * CFrame.Angles(0, 0, -side * tilt), Style = roof, Parent = lv })
	end
	-- gable ends, drawn as a stack of shrinking boards
	local bars = 7
	for _, z in ipairs({ HOUSE_Z0 - 0.3, HOUSE_Z1 + 0.3 }) do
		for k = 0, bars - 1 do
			local w = 2 * (half - 1) * (1 - (k + 0.5) / bars)
			part({ Name = "Gable", Size = Vector3.new(w, ridge / bars, 0.6), CFrame = L(0, top + 1 + (k + 0.5) * ridge / bars, z), Style = ext, Parent = lv })
		end
	end
	local roofSign = part({ Name = "RoofSign", Size = Vector3.new(22, 3, 0.4), CFrame = L(0, top + 3, HOUSE_Z0 - 0.9), Color = Color3.fromRGB(40, 40, 60), Parent = lv })
	label(surface(roofSign, Enum.NormalId.Front, Vector2.new(880, 120)), plot.owner.DisplayName .. "'s Boarding House", Color3.fromRGB(255, 220, 90))
end

---------------------------------------------------------------------------
-- Live layer: students, beds, door plates, the yard sign. Rebuilt on every
-- change, but students keep walking if nothing about them changed.
---------------------------------------------------------------------------
local function setStudentAttrs(m, plot, info, sat)
	m:SetAttribute("PlotIndex", plot.index)
	m:SetAttribute("Floor", info.floor)
	m:SetAttribute("Level", info.floor)
	m:SetAttribute("HomeKey", info.key)
	m:SetAttribute("Center", info.center)
	m:SetAttribute("U", info.u)
	m:SetAttribute("V", info.v)
	m:SetAttribute("Range", info.range)
	m:SetAttribute("Door", info.door)
	m:SetAttribute("Hall", info.hall)
	m:SetAttribute("Sat", sat)
end

local function renderLive(plot, data, totals)
	local live = plot.live
	local students = live:FindFirstChild("Students")
	if not students then
		students = Instance.new("Folder")
		students.Name = "Students"
		students.Parent = live
	end
	for _, c in ipairs(live:GetChildren()) do
		if c ~= students then
			c:Destroy()
		end
	end
	local owner = plot.owner
	local floors = House.floorCount(data)
	local levels = {}
	for f = 0, floors - 1 do
		levels[f] = levelFolder(live, f)
	end

	local keep = {}
	for i, room in ipairs(data.rooms) do
		local info = plot.rooms["r" .. i]
		if info then
			local rcf = info.rcf
			local tier = Config.RoomTiers[room.tier]
			local stats = totals and totals.rooms[i]
			local lv = levels[info.floor]
			-- beds along the outside wall, colored by who sleeps there
			for b = 1, tier.beds do
				local v = -ROOM_V / 2 + (ROOM_V / tier.beds) * (b - 0.5)
				local occ = room.occupants[b]
				local color = Color3.fromRGB(120, 160, 230)
				if occ and data.students[occ] then
					color = Config.Personalities[Config.StudentById[data.students[occ].id].personality].color
				end
				bed(lv, rcf * CFrame.new(ROOM_U - 4.2, 0.2, v) * BED_TURN, color)
			end

			-- door plate + prompt in the hallway
			local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.8, 6), CFrame = rcf * CFrame.new(-0.45, DOOR_H + 1.3, 0), Color = Color3.fromRGB(40, 40, 60), Parent = lv })
			plate:SetAttribute("OwnerUserId", owner.UserId)
			plate:SetAttribute("RoomIndex", i)
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 40
			cd.Parent = plate
			CollectionService:AddTag(plate, "RoomClick")
			local sg = surface(plate, Enum.NormalId.Left, Vector2.new(600, 180))
			local sat = stats and stats.satisfaction or 0
			label(sg, string.format("🛏 Room %d • %s", i, tier.name), Color3.fromRGB(255, 230, 120), UDim2.fromScale(1, 0.5))
			label(sg, #room.occupants == 0 and "empty" or string.format("%s %d%%  •  $%s/s", SchoolMath.moodEmoji(sat), math.floor(sat), SchoolMath.format(stats and stats.income or 0)), Color3.new(1, 1, 1), UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))
			local spot = part({ Name = "DoorSpot", Size = Vector3.new(1, 1, 1), CFrame = rcf * CFrame.new(-1.5, 3, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = lv })
			local pp = prompt(spot, "Manage room", "Room " .. i, 7)
			pp:SetAttribute("OwnerUserId", owner.UserId)
			pp:SetAttribute("RoomIndex", i)
			CollectionService:AddTag(pp, "RoomPrompt")

			for _, uid in ipairs(room.occupants) do
				local s = data.students[uid]
				if s then
					local st = stats and stats.students[uid]
					local satv = st and st.sat or 50
					local m = students:FindFirstChild(uid)
					if m and (m:GetAttribute("HomeKey") ~= info.key or m:GetAttribute("StudentId") ~= s.id or m:GetAttribute("Origin") ~= plot.cf) then
						m:Destroy()
						m = nil
					end
					if not m then
						local rng = Random.new()
						local start = rcf * CFrame.new(rng:NextNumber(3, ROOM_U - 8), 0.2, rng:NextNumber(-ROOM_V / 2 + 2, ROOM_V / 2 - 2))
						m = PlotService.BuildStudentModel(uid, s, start)
						m.Name = uid
						m:SetAttribute("StudentId", s.id)
						m:SetAttribute("Origin", plot.cf)
						setStudentAttrs(m, plot, info, satv)
						m.Parent = students
					else
						m:SetAttribute("Sat", satv)
					end
					keep[uid] = true
				end
			end
		end
	end
	for _, m in ipairs(students:GetChildren()) do
		if not keep[m.Name] then
			m:Destroy()
		end
	end

	-- plates for the special rooms
	for key, info in pairs(plot.rooms) do
		local kind, _, fid = House.describe(key)
		if kind ~= "dorm" then
			local text = kind == "me" and ("⭐ " .. owner.DisplayName .. "'s Room") or kind == "common" and "🛋 Common Room" or (Config.FacilityById[fid].emoji .. " " .. Config.FacilityById[fid].name)
			local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.4, 6), CFrame = info.rcf * CFrame.new(-0.45, DOOR_H + 1.3, 0), Color = Color3.fromRGB(250, 245, 230), Parent = levels[info.floor] })
			label(surface(plate, Enum.NormalId.Left, Vector2.new(600, 140)), text, Color3.fromRGB(60, 40, 30)).TextStrokeTransparency = 1
		end
	end

	local count = 0
	for _ in pairs(data.students) do
		count += 1
	end
	local post = buildSign(
		plot,
		live,
		owner.DisplayName .. "'s Boarding House",
		string.format("$%s/s  •  %d students  •  %s", SchoolMath.format(totals and totals.income or 0), count, SchoolMath.moodEmoji(totals and totals.satisfaction or 0)),
		data.likes
	)
	local like = Instance.new("ProximityPrompt")
	like.Name = "LikePrompt"
	like.ActionText = "❤ Like House"
	like.ObjectText = owner.DisplayName .. "'s Boarding House"
	like.HoldDuration = 0.3
	like.RequiresLineOfSight = false
	like.MaxActivationDistance = 14
	like:SetAttribute("OwnerUserId", owner.UserId)
	like.Parent = post
	CollectionService:AddTag(like, "LikePrompt")
end

function PlotService.Render(plot, data, totals)
	if not plot.owner then
		PlotService.RenderEmpty(plot)
		return
	end
	local sig = signature(plot, data)
	if sig ~= plot.signature then
		plot.signature = sig
		renderStructure(plot, data)
	end
	renderLive(plot, data, totals)
end

-- standing in your room, looking at the storyboard
function PlotService.MyRoomCFrame(plot)
	local info = plot.rooms and plot.rooms.me
	if not info then
		return PlotService.SpawnCFrame(plot)
	end
	local pos = (info.rcf * CFrame.new(7, 3, 0)).Position
	return CFrame.lookAt(pos, pos + info.u)
end

return PlotService
