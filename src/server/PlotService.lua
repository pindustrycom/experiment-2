-- Builds the world (plaza + plots) and renders each player's boarding house
-- from data. Everything is procedural, so the place needs no prebuilt models.
--
-- A house is one walkable building: a hallway runs from the front door to the
-- stairwell at the back, with a row of cells on both sides. Rooms take one
-- or two cells (see shared/House.lua for the layout data). Plot-local axes: -Z is the front (toward the
-- plaza), +X is the right side when you walk in through the front door.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
-- thickness along local Z. holes = { { c, w, b, t, glass, out } } in the same
-- axes; `out` (+1/-1, local Z) marks the outside face for sills and shutters.
local TRIM = Color3.fromRGB(245, 240, 228)
local SHUTTER = Color3.fromRGB(60, 95, 80)

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
			local mid = (h.b + h.t) / 2
			part({ Name = "Window", Size = Vector3.new(h.w, h.t - h.b, 0.15), CFrame = frame * CFrame.new(h.c, mid, 0), Color = Color3.fromRGB(180, 225, 255), Material = Enum.Material.Glass, Transparency = 0.6, Reflectance = 0.2, Parent = parent })
			-- window bars: one cross through the middle
			local bar = { Name = "Mullion", Color = TRIM, CanCollide = false, Parent = parent }
			bar.Size, bar.CFrame = Vector3.new(0.18, h.t - h.b, 0.25), frame * CFrame.new(h.c, mid, 0)
			part(table.clone(bar))
			bar.Size = Vector3.new(h.w, 0.18, 0.25)
			part(bar)
		end
		if h.out then
			-- outside trim: sill, lintel and shutters
			local o = h.out
			part({ Name = "Sill", Size = Vector3.new(h.w + 0.8, 0.3, 0.7), CFrame = frame * CFrame.new(h.c, h.b - 0.15, o * (thick / 2 + 0.25)), Color = TRIM, Parent = parent })
			part({ Name = "Lintel", Size = Vector3.new(h.w + 0.6, 0.45, 0.4), CFrame = frame * CFrame.new(h.c, h.t + 0.22, o * (thick / 2 + 0.15)), Color = TRIM, Parent = parent })
			for _, sgn in ipairs({ -1, 1 }) do
				part({ Name = "Shutter", Size = Vector3.new(1.1, h.t - h.b, 0.15), CFrame = frame * CFrame.new(h.c + sgn * (h.w / 2 + 0.65), (h.b + h.t) / 2, o * (thick / 2 + 0.1)), Color = SHUTTER, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = parent })
			end
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
-- Soft sky, bloom and warm color grading. Lighting.Technology can't be set
-- from a script; default.project.json sets it to Future for built places.
local function setupLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 135, 150)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	local function effect(class, props)
		local e = Lighting:FindFirstChildOfClass(class) or Instance.new(class)
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Parent = Lighting
	end
	effect("Atmosphere", { Density = 0.3, Offset = 0.25, Color = Color3.fromRGB(200, 215, 235), Decay = Color3.fromRGB(110, 120, 140), Glare = 0.4, Haze = 1.2 })
	effect("BloomEffect", { Intensity = 0.6, Size = 28, Threshold = 1.6 })
	effect("SunRaysEffect", { Intensity = 0.06, Spread = 0.8 })
	effect("ColorCorrectionEffect", { Brightness = 0.02, Contrast = 0.08, Saturation = 0.12, TintColor = Color3.fromRGB(255, 248, 240) })
end

local function buildPlazaDecor(world)
	local stone = Color3.fromRGB(215, 210, 200)
	-- fountain
	part({ Name = "FountainBasin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 16, 16), CFrame = CFrame.new(0, 1.2, 18) * CFrame.Angles(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Marble, Parent = world })
	part({ Name = "FountainWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 14.4, 14.4), CFrame = CFrame.new(0, 1.95, 18) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(70, 160, 230), Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.2, Parent = world })
	part({ Name = "FountainPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 1.6, 1.6), CFrame = CFrame.new(0, 4, 18) * CFrame.Angles(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Marble, Parent = world })
	local bowl = part({ Name = "FountainBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 6, 6), CFrame = CFrame.new(0, 6.6, 18) * CFrame.Angles(0, 0, math.pi / 2), Color = stone, Material = Enum.Material.Marble, Parent = world })
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	spray.Size = NumberSequence.new(0.5, 0.1)
	spray.Transparency = NumberSequence.new(0.3, 1)
	spray.Rate = 40
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Speed = NumberRange.new(6, 8)
	spray.SpreadAngle = Vector2.new(20, 20)
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.EmissionDirection = Enum.NormalId.Right -- the bowl's local X points up
	spray.Parent = bowl
	-- benches and lamp posts around the plaza
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local pos = Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30)
		local cf = CFrame.lookAt(pos, Vector3.zero)
		part({ Name = "BenchSeat", Size = Vector3.new(6, 0.4, 1.8), CFrame = cf * CFrame.new(0, 1.9, 0), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks, Parent = world })
		part({ Name = "BenchBack", Size = Vector3.new(6, 1.6, 0.3), CFrame = cf * CFrame.new(0, 3, 0.9) * CFrame.Angles(-0.15, 0, 0), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.WoodPlanks, Parent = world })
		for _, x in ipairs({ -2.6, 2.6 }) do
			part({ Name = "BenchLeg", Size = Vector3.new(0.3, 1.5, 1.6), CFrame = cf * CFrame.new(x, 1.15, 0), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = world })
		end
		local lp = Vector3.new(math.cos(a) * 52, 0, math.sin(a) * 52)
		part({ Name = "LampPost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 0.5, 0.5), CFrame = CFrame.new(lp + Vector3.new(0, 5.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = world })
		local globe = part({ Name = "LampGlobe", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(lp + Vector3.new(0, 10.9, 0)), Color = Color3.fromRGB(255, 235, 190), Material = Enum.Material.Neon, Parent = world })
		local l = Instance.new("PointLight")
		l.Range = 20
		l.Brightness = 1
		l.Color = Color3.fromRGB(255, 220, 170)
		l.Parent = globe
	end
	-- low hedges along the plaza edge, with gaps for the paths
	for _, sd in ipairs({ -1, 1 }) do
		for _, half in ipairs({ -1, 1 }) do
			part({ Name = "Hedge", Size = Vector3.new(2.4, 2.4, 44), CFrame = CFrame.new(sd * 59, 1.6, half * 32), Color = Color3.fromRGB(70, 140, 70), Material = Enum.Material.Grass, Parent = world })
		end
	end
end

function PlotService.BuildWorld()
	setupLighting()
	local world = Instance.new("Folder")
	world.Name = "BSTWorld"
	world.Parent = workspace
	buildPlazaDecor(world)

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

-- cf: bed center on the floor, pillow end toward local +Z. `color` is the blanket.
local BED_WOOD = Color3.fromRGB(120, 82, 55)
local function bed(parent, cf, color)
	local wood = { Color = BED_WOOD, Material = Enum.Material.Wood, Parent = parent }
	local function piece(name, size, offset, props)
		local p = table.clone(props or wood)
		p.Name, p.Size, p.CFrame = name, size, cf * offset
		return part(p)
	end
	for _, x in ipairs({ -1.6, 1.6 }) do
		for _, z in ipairs({ -3.3, 3.3 }) do
			piece("Leg", Vector3.new(0.3, 0.5, 0.3), CFrame.new(x, 0.25, z))
		end
	end
	piece("BedFrame", Vector3.new(3.6, 0.5, 7), CFrame.new(0, 0.75, 0))
	piece("Headboard", Vector3.new(3.8, 2.6, 0.3), CFrame.new(0, 1.8, 3.55))
	piece("HeadboardCap", Vector3.new(4, 0.25, 0.45), CFrame.new(0, 3.2, 3.55))
	piece("Footboard", Vector3.new(3.8, 1.5, 0.3), CFrame.new(0, 1.25, -3.55))
	piece("Mattress", Vector3.new(3.3, 0.55, 6.7), CFrame.new(0, 1.27, 0), { Color = Color3.fromRGB(245, 245, 240), Material = Enum.Material.Fabric, Parent = parent })
	piece("Blanket", Vector3.new(3.45, 0.2, 4.6), CFrame.new(0, 1.62, -1), { Color = color, Material = Enum.Material.Fabric, Parent = parent })
	piece("BlanketSide", Vector3.new(0.1, 0.55, 4.6), CFrame.new(1.72, 1.35, -1), { Color = color, Material = Enum.Material.Fabric, Parent = parent })
	piece("BlanketSide", Vector3.new(0.1, 0.55, 4.6), CFrame.new(-1.72, 1.35, -1), { Color = color, Material = Enum.Material.Fabric, Parent = parent })
	piece("Fold", Vector3.new(3.5, 0.28, 0.6), CFrame.new(0, 1.7, 1.3), { Color = Color3.fromRGB(250, 250, 250), Material = Enum.Material.Fabric, Parent = parent })
	piece("Pillow", Vector3.new(2.6, 0.5, 1.2), CFrame.new(0, 1.75, 2.6), { Color = Color3.new(1, 1, 1), Material = Enum.Material.Fabric, Parent = parent })
end

local SKIN = {
	Color3.fromRGB(255, 220, 185),
	Color3.fromRGB(235, 190, 150),
	Color3.fromRGB(200, 150, 110),
	Color3.fromRGB(150, 100, 70),
	Color3.fromRGB(100, 70, 50),
}

local HAIR = { Color3.fromRGB(30, 25, 25), Color3.fromRGB(90, 55, 30), Color3.fromRGB(230, 190, 110), Color3.fromRGB(170, 70, 40), Color3.fromRGB(60, 40, 30) }
local PANTS = { Color3.fromRGB(50, 70, 120), Color3.fromRGB(35, 35, 45), Color3.fromRGB(170, 150, 110), Color3.fromRGB(80, 80, 90) }

-- One R15 avatar rig, cloned for every student. Needs Roblox's avatar
-- service (works in Studio when you're online); falls back to block people.
local avatarTemplate, rootAboveFeet
local function getAvatarTemplate()
	if avatarTemplate == nil then
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if ok and model and model:FindFirstChild("HumanoidRootPart") then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Massless = true
				elseif d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.EvaluateStateMachine = false
			hum.BreakJointsOnDeath = false
			model.HumanoidRootPart.Anchored = true
			model.PrimaryPart = model.HumanoidRootPart
			model:PivotTo(CFrame.new())
			local bbCF, bbSize = model:GetBoundingBox()
			rootAboveFeet = model.HumanoidRootPart.Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
			avatarTemplate = model
		else
			warn("[BST] avatar rigs unavailable, using block students:", model)
			avatarTemplate = false
		end
	end
	return avatarTemplate or nil
end

local function weldTo(base, p)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	return p
end

local function finishStudent(m, uid, student, head, root)
	local def = Config.StudentById[student.id]
	local rarity = Config.Rarities[def.rarity]
	local pers = Config.Personalities[def.personality]
	if rarity.rank >= 5 then
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

local function buildAvatarStudent(template, uid, student, cf, skin, seed)
	local def = Config.StudentById[student.id]
	local pers = Config.Personalities[def.personality]
	local m = template:Clone()
	m.Name = def.name
	local shirt = pers.color
	local pants = PANTS[(seed % #PANTS) + 1]
	local shoes = (seed % 3 == 0) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(30, 30, 35)
	local colors = {
		Head = skin, UpperTorso = shirt, LowerTorso = pants,
		LeftUpperArm = shirt, RightUpperArm = shirt, LeftLowerArm = skin, RightLowerArm = skin, LeftHand = skin, RightHand = skin,
		LeftUpperLeg = pants, RightUpperLeg = pants, LeftLowerLeg = pants, RightLowerLeg = pants, LeftFoot = shoes, RightFoot = shoes,
	}
	local bodyColors = m:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
	for name, color in pairs(colors) do
		local p = m:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = color
			p.Material = (p.Name == "UpperTorso" or p.Name:find("UpperArm")) and Enum.Material.Fabric or Enum.Material.SmoothPlastic
		end
	end
	local head = m:FindFirstChild("Head")
	local torso = m:FindFirstChild("UpperTorso")
	local hs = head.Size
	-- hair: a cap over the top and back of the head
	local hairColor = HAIR[(seed // 3) % #HAIR + 1]
	local hair = { Name = "Hair", Color = hairColor, Material = Enum.Material.Fabric, Parent = m }
	hair.Size = Vector3.new(hs.X * 1.08, hs.Y * 0.32, hs.Z * 1.08)
	hair.CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.4, 0.02)
	weldTo(head, part(hair))
	local back = table.clone(hair)
	back.Size = Vector3.new(hs.X * 1.08, hs.Y * 0.7, hs.Z * 0.2)
	back.CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.12, hs.Z * 0.48)
	weldTo(head, part(back))
	if seed % 2 == 0 then
		local fringe = table.clone(hair)
		fringe.Size = Vector3.new(hs.X * 0.9, hs.Y * 0.14, hs.Z * 0.12)
		fringe.CFrame = head.CFrame * CFrame.new(-hs.X * 0.05, hs.Y * 0.3, -hs.Z * 0.5)
		weldTo(head, part(fringe))
	end
	-- personality accessories
	local function acc(name, size, offset, color, material, base)
		base = base or head
		return weldTo(base, part({ Name = name, Size = size, CFrame = base.CFrame * offset, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = m }))
	end
	if def.personality == "Royal" then
		acc("Crown", Vector3.new(hs.X * 0.85, 0.35, hs.Z * 0.85), CFrame.new(0, hs.Y * 0.7, 0), Color3.fromRGB(255, 210, 60), Enum.Material.Foil)
		for i = 0, 3 do
			acc("CrownPoint", Vector3.new(0.18, 0.3, 0.18), CFrame.new(0, hs.Y * 0.7 + 0.3, 0) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, hs.Z * 0.38), Color3.fromRGB(255, 210, 60), Enum.Material.Foil)
		end
	elseif def.personality == "Nerd" then
		for _, x in ipairs({ -0.25, 0.25 }) do
			acc("Lens", Vector3.new(0.34, 0.3, 0.06), CFrame.new(x * hs.X, hs.Y * 0.08, -hs.Z * 0.53), Color3.fromRGB(200, 230, 255), Enum.Material.Glass).Transparency = 0.4
		end
		acc("Bridge", Vector3.new(hs.X * 0.9, 0.06, 0.06), CFrame.new(0, hs.Y * 0.12, -hs.Z * 0.55), Color3.fromRGB(20, 20, 20))
	elseif def.personality == "Musician" then
		acc("GuitarBody", Vector3.new(1.1, 1.3, 0.3), CFrame.new(0.2, -0.3, torso.Size.Z / 2 + 0.25) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(180, 60, 40), Enum.Material.Wood, torso)
		acc("GuitarNeck", Vector3.new(0.18, 1.6, 0.12), CFrame.new(-0.45, 0.75, torso.Size.Z / 2 + 0.25) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(60, 35, 20), Enum.Material.Wood, torso)
	elseif def.personality == "Jock" then
		acc("Cap", Vector3.new(hs.X * 1.1, 0.35, hs.Z * 1.1), CFrame.new(0, hs.Y * 0.55, 0), Color3.fromRGB(220, 50, 50), Enum.Material.Fabric)
		acc("Brim", Vector3.new(hs.X * 0.95, 0.08, 0.55), CFrame.new(0, hs.Y * 0.42, -hs.Z * 0.75), Color3.fromRGB(220, 50, 50), Enum.Material.Fabric)
	elseif def.personality == "Gamer" then
		acc("Headset", Vector3.new(hs.X * 1.15, 0.12, 0.3), CFrame.new(0, hs.Y * 0.55, 0), Color3.fromRGB(30, 30, 35))
		for _, x in ipairs({ -1, 1 }) do
			acc("Ear", Vector3.new(0.18, 0.5, 0.45), CFrame.new(x * hs.X * 0.56, 0, 0), Color3.fromRGB(40, 220, 200), Enum.Material.Neon)
		end
	elseif def.personality == "Artist" then
		acc("Beret", Vector3.new(hs.X * 1.1, 0.25, hs.Z * 1.1), CFrame.new(0.12, hs.Y * 0.62, 0) * CFrame.Angles(0, 0, -0.2), Color3.fromRGB(150, 30, 60), Enum.Material.Fabric)
	elseif def.personality == "Rebel" then
		acc("Shades", Vector3.new(hs.X * 0.95, 0.24, 0.08), CFrame.new(0, hs.Y * 0.1, -hs.Z * 0.54), Color3.fromRGB(15, 15, 15), Enum.Material.Glass)
		acc("Jacket", Vector3.new(torso.Size.X * 1.06, torso.Size.Y * 0.95, torso.Size.Z * 1.08), CFrame.new(0, 0, 0), Color3.fromRGB(30, 30, 35), Enum.Material.Leather, torso).Transparency = 0
	elseif def.personality == "Prankster" then
		acc("Propeller", Vector3.new(hs.X * 0.9, 0.25, hs.Z * 0.9), CFrame.new(0, hs.Y * 0.6, 0), Color3.fromRGB(255, 200, 50), Enum.Material.Fabric)
		acc("Blade", Vector3.new(1.4, 0.05, 0.22), CFrame.new(0, hs.Y * 0.6 + 0.3, 0), Color3.fromRGB(240, 70, 70))
	end
	local root = m.HumanoidRootPart
	m:PivotTo(cf * CFrame.new(0, rootAboveFeet, 0))
	m:SetAttribute("Rig", "R15")
	return finishStudent(m, uid, student, head, root)
end

function PlotService.BuildStudentModel(uid, student, cf)
	local seed0 = 0
	for i = 1, #uid do
		seed0 += string.byte(uid, i) * i
	end
	local template = getAvatarTemplate()
	if template then
		return buildAvatarStudent(template, uid, student, cf, SKIN[(seed0 % #SKIN) + 1], seed0)
	end
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

	return finishStudent(m, uid, student, head, root)
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
	for _, u in ipairs({ 6, 11.5 }) do
		prop(m, r, u, 2.6, 0, Vector3.new(3, 0.3, 8), Color3.fromRGB(240, 240, 240))
		for _, dv in ipairs({ -3.4, 3.4 }) do
			prop(m, r, u, 1.25, dv, Vector3.new(0.4, 2.5, 0.4), DARK)
		end
		for _, side in ipairs({ -1, 1 }) do
			prop(m, r, u + side * 2.2, 1, 0, Vector3.new(1, 0.4, 8), WOOD, { Material = Enum.Material.Wood })
		end
		for k = -1, 1 do
			prop(m, r, u + 0.6, 2.85, k * 2.6, Vector3.new(0.12, 0.9, 0.9), Color3.fromRGB(255, 255, 255), { Shape = Enum.PartType.Cylinder, Rot = UPRIGHT, CanCollide = false })
			prop(m, r, u - 0.6, 2.85, k * 2.6 + 1, Vector3.new(0.12, 0.9, 0.9), Color3.fromRGB(255, 255, 255), { Shape = Enum.PartType.Cylinder, Rot = UPRIGHT, CanCollide = false })
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
	local fabric = { Material = Enum.Material.Fabric }
	prop(m, r, 8.5, 0.7, 0, Vector3.new(2.6, 1, 8), sofa, fabric)
	for _, dv in ipairs({ -2, 2 }) do
		prop(m, r, 8.7, 1.35, dv, Vector3.new(2.2, 0.45, 3.8), sofa:Lerp(Color3.new(1, 1, 1), 0.15), fabric) -- seat cushions
		prop(m, r, 7.65, 2.4, dv, Vector3.new(0.6, 1.6, 3.7), sofa:Lerp(Color3.new(1, 1, 1), 0.1), fabric) -- back cushions
	end
	prop(m, r, 7.4, 2.1, 0, Vector3.new(0.6, 2.2, 8), sofa, fabric)
	for _, sgn in ipairs({ -1, 1 }) do
		prop(m, r, 8.5, 1.6, sgn * 4.3, Vector3.new(2.6, 1.8, 0.7), sofa, fabric) -- arms
		prop(m, r, 8.6, 1.85, sgn * 3.2, Vector3.new(0.9, 0.9, 0.35), Color3.fromRGB(240, 200, 90), fabric) -- throw pillows
	end
	-- coffee table with legs, a plant and mugs
	prop(m, r, 12.5, 1.5, 0, Vector3.new(2.2, 0.25, 4), WOOD, { Material = Enum.Material.Wood })
	for _, du in ipairs({ -0.9, 0.9 }) do
		for _, dv in ipairs({ -1.7, 1.7 }) do
			prop(m, r, 12.5 + du, 0.7, dv, Vector3.new(0.2, 1.4, 0.2), WOOD)
		end
	end
	cyl(m, r, 12.5, 1.95, -1, 0.6, 0.45, Color3.fromRGB(240, 240, 240))
	cyl(m, r, 12.3, 1.95, 1.2, 0.6, 0.45, Color3.fromRGB(220, 90, 80))
	-- TV stand under the TV
	prop(m, r, ROOM_U - 1.2, 1, 0, Vector3.new(1.6, 2, 6.5), WOOD:Lerp(Color3.new(0, 0, 0), 0.3), { Material = Enum.Material.Wood })
	cyl(m, r, 11, 0.28, 0, 0.12, 9, Color3.fromRGB(230, 200, 120), { Material = Enum.Material.Fabric })
	for _, v in ipairs({ -6.8, 6.8 }) do
		cyl(m, r, ROOM_U - 1.4, 0.9, v, 1.6, 1.6, Color3.fromRGB(180, 100, 60))
		prop(m, r, ROOM_U - 1.4, 2.8, v, Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(70, 160, 70), { Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
	end
	prop(m, r, 3, 1, -6, Vector3.new(2.6, 2, 2.6), Color3.fromRGB(230, 120, 60), { Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric })
end

-- Your own room (2 cells: v from -ROOM_V to +ROOM_V). The three boards hang
-- on the outside wall; the bed, desk and wardrobe are always there.
local function myRoomBasics(m, r)
	bed(m, r * CFrame.new(4.5, 0.2, -12.2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(255, 200, 80))
	prop(m, r, 1.6, 1.4, -15.2, Vector3.new(1.6, 1.2, 1.4), WOOD, { Material = Enum.Material.Wood }) -- nightstand
	-- desk + chair
	prop(m, r, 10.5, 3, 14.6, Vector3.new(4, 0.3, 2), WOOD, { Material = Enum.Material.Wood })
	for _, du in ipairs({ -1.8, 1.8 }) do
		prop(m, r, 10.5 + du, 1.5, 14.6, Vector3.new(0.3, 3, 1.8), WOOD, { Material = Enum.Material.Wood })
	end
	prop(m, r, 10.5, 3.6, 15.1, Vector3.new(1.6, 1, 0.1), DARK)
	prop(m, r, 10.5, 1.5, 12.8, Vector3.new(1.6, 0.3, 1.6), Color3.fromRGB(200, 60, 60))
	prop(m, r, 10.5, 2.6, 12.1, Vector3.new(1.6, 2, 0.3), Color3.fromRGB(200, 60, 60))
	-- wardrobe
	prop(m, r, 3, 3.5, 15.1, Vector3.new(3.5, 7, 1.6), Color3.fromRGB(150, 105, 70), { Material = Enum.Material.Wood })
	prop(m, r, 3, 3.5, 14.28, Vector3.new(0.08, 6.6, 0.05), DARK)
	for _, du in ipairs({ -0.35, 0.35 }) do
		prop(m, r, 3 + du, 3.6, 14.25, Vector3.new(0.15, 0.6, 0.1), Color3.fromRGB(230, 200, 90), { Material = Enum.Material.Metal })
	end
end

local FurnitureProps = {}
function FurnitureProps.rug(m, r)
	cyl(m, r, 10, 0.28, -2, 0.12, 8, Color3.fromRGB(150, 90, 200), { Material = Enum.Material.Fabric })
end
function FurnitureProps.plant(m, r)
	cyl(m, r, 15.5, 0.9, -14.4, 1.6, 1.6, Color3.fromRGB(190, 110, 70))
	prop(m, r, 15.5, 2.8, -14.4, Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(70, 160, 70), { Shape = Enum.PartType.Ball, Material = Enum.Material.Grass })
end
function FurnitureProps.lamp(m, r)
	prop(m, r, 8, 2.7, -15, Vector3.new(0.3, 5, 0.3), DARK)
	local shade = cyl(m, r, 8, 5.5, -15, 1.2, 1.6, Color3.fromRGB(255, 240, 200), { Material = Enum.Material.Neon })
	light(shade, 18)
end
function FurnitureProps.posters(m, r)
	local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 210, 70) }
	for i, c in ipairs(colors) do
		prop(m, r, 0.45, 6, -14 + i * 2.6, Vector3.new(0.05, 2.6, 2), c, { CanCollide = false })
	end
end
function FurnitureProps.bookshelf(m, r)
	prop(m, r, 6.5, 3.2, 15.3, Vector3.new(3, 6.4, 1), WOOD, { Material = Enum.Material.Wood })
	for row, c in ipairs({ Color3.fromRGB(180, 50, 50), Color3.fromRGB(50, 90, 180), Color3.fromRGB(220, 170, 60) }) do
		prop(m, r, 6.5, row * 1.9 - 0.2, 14.85, Vector3.new(2.6, 1.1, 0.2), c)
	end
end
function FurnitureProps.beanbag(m, r)
	prop(m, r, 12, 1.2, -9, Vector3.new(3, 2.2, 3), Color3.fromRGB(255, 150, 50), { Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric })
end
function FurnitureProps.gaming(m, r)
	prop(m, r, 0.6, 4, 8, Vector3.new(0.3, 2.4, 4), DARK)
	prop(m, r, 0.78, 4, 8, Vector3.new(0.05, 2.1, 3.7), Color3.fromRGB(80, 255, 200), { Material = Enum.Material.Neon })
	prop(m, r, 1, 1.2, 8, Vector3.new(1.4, 2.4, 3), WOOD)
	prop(m, r, 4, 1.4, 8, Vector3.new(1.6, 0.4, 1.6), Color3.fromRGB(30, 30, 30))
	prop(m, r, 4.8, 2.6, 8, Vector3.new(0.3, 2.4, 1.6), Color3.fromRGB(220, 40, 80))
end
function FurnitureProps.aquarium(m, r)
	prop(m, r, 16.8, 0.7, 12.5, Vector3.new(1.6, 1.2, 4), WOOD)
	prop(m, r, 16.8, 2, 12.5, Vector3.new(1.5, 1.5, 3.8), Color3.fromRGB(80, 170, 255), { Material = Enum.Material.Glass, Transparency = 0.4 })
	for i, c in ipairs({ Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 230, 60) }) do
		prop(m, r, 16.8, 1.9 + i * 0.3, 11.6 + i * 1.3, Vector3.new(0.3, 0.3, 0.6), c, { Material = Enum.Material.Neon, CanCollide = false })
	end
end
function FurnitureProps.trophy(m, r)
	prop(m, r, 14, 2.3, 15.3, Vector3.new(2, 4.6, 1), WOOD, { Material = Enum.Material.Wood })
	for i = 0, 2 do
		cyl(m, r, 13.4 + i * 0.6, 4.95, 15.2, 0.7, 0.5, Color3.fromRGB(255, 210, 60), { Material = Enum.Material.Neon })
	end
	prop(m, r, 14, 2.3, 14.75, Vector3.new(1.8, 4.2, 0.1), Color3.fromRGB(200, 230, 255), { Material = Enum.Material.Glass, Transparency = 0.6 })
end

---------------------------------------------------------------------------
-- House render
---------------------------------------------------------------------------
local function roomFrame(plot, slotFloor, side, row, size)
	local zc = HOUSE_Z0 + ROOM_V * (row + size / 2)
	return PlotService.LocalCF(plot, side * HALL_W / 2, floorY(slotFloor), zc) * CFrame.Angles(0, side == 1 and 0 or math.pi, 0)
end

-- where students and the client need to know about a room (world space)
local function roomInfo(plot, rcf, key, slotFloor, size, hangout)
	return {
		key = key,
		floor = slotFloor,
		size = size,
		rcf = rcf,
		center = (rcf * CFrame.new(ROOM_U * 0.36, 0, 0)).Position,
		u = rcf.XVector,
		v = rcf.ZVector,
		range = Vector3.new(ROOM_U * 0.22, 0, ROOM_V * size / 2 - 2.5),
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

-- floor, four walls (hallway wall has the door), a window per cell in the
-- outside wall. size = how many cells along the hallway the room spans.
local function buildShell(m, rcf, row, side, size, wallStyle, floorStyle, hallStyle, opts)
	local w = ROOM_V * size
	part({ Name = "Floor", Size = Vector3.new(ROOM_U, 0.2, w), CFrame = rcf * CFrame.new(ROOM_U / 2, 0.1, 0), Style = floorStyle, Parent = m })
	local inner = { Name = "Wall", Style = wallStyle }
	local hallSide = { Name = "HallWall", Style = hallStyle }
	local door = opts.door and { { c = 0, w = DOOR_W, b = 0, t = DOOR_H } } or nil
	wall(m, rcf * CFrame.new(0.2, 0, 0) * ALONG_Z, -w / 2, w / 2, 0, WALL_H, 0.4, inner, door and table.clone(door))
	wall(m, rcf * CFrame.new(-0.2, 0, 0) * ALONG_Z, -w / 2, w / 2, 0, WALL_H, 0.4, hallSide, door and table.clone(door))
	local windows = nil
	if opts.window ~= false then
		windows = {}
		for k = 0, size - 1 do
			table.insert(windows, { c = -w / 2 + ROOM_V * (k + 0.5), w = 6, b = 3, t = 8 })
		end
	end
	wall(m, rcf * CFrame.new(ROOM_U - 0.2, 0, 0) * ALONG_Z, -w / 2, w / 2, 0, WALL_H, 0.4, inner, windows)
	-- side walls; the one at the front/back of the house gets a window
	local front, back = -side * w / 2, side * w / 2
	local sideWindows = {}
	for _, v in ipairs({ front, back }) do
		local outside = (v == front and row == 0) or (v == back and row + size - 1 == ROWS - 1)
		local inset = v > 0 and v - 0.2 or v + 0.2
		wall(m, rcf * CFrame.new(0, 0, inset), 0.4, ROOM_U - 0.4, 0, WALL_H, 0.4, inner, outside and { { c = ROOM_U / 2, w = 6, b = 3, t = 8 } } or nil)
		if outside then
			table.insert(sideWindows, v)
		end
	end
	if opts.plain then
		return
	end

	-- trim: baseboards and crown molding on every inside wall
	local base = (wallStyle.color):Lerp(Color3.fromRGB(60, 40, 30), 0.55)
	local function strip(name, size, u, h, v, color)
		part({ Name = name, Size = size, CFrame = rcf * CFrame.new(u, h, v), Color = color, CanCollide = false, Parent = m })
	end
	for _, t in ipairs({ { "Baseboard", 0.3, 0.6, base }, { "Crown", WALL_H - 0.2, 0.4, TRIM } }) do
		local name, h, tall, color = t[1], t[2], t[3], t[4]
		strip(name, Vector3.new(0.14, tall, w - 0.8), ROOM_U - 0.47, h, 0, color)
		strip(name, Vector3.new(ROOM_U - 0.8, tall, 0.14), ROOM_U / 2, h, -w / 2 + 0.47, color)
		strip(name, Vector3.new(ROOM_U - 0.8, tall, 0.14), ROOM_U / 2, h, w / 2 - 0.47, color)
		if opts.door and name == "Baseboard" then
			local seg = (w - 0.8) / 2 - DOOR_W / 2 - 0.3
			for _, sgn in ipairs({ -1, 1 }) do
				strip(name, Vector3.new(0.14, tall, seg), 0.47, h, sgn * (DOOR_W / 2 + 0.3 + seg / 2), color)
			end
		else
			strip(name, Vector3.new(0.14, tall, w - 0.8), 0.47, h, 0, color)
		end
	end

	-- door frame on both faces, and the door standing open flat against the
	-- hallway wall
	if opts.door then
		for _, sgn in ipairs({ -1, 1 }) do
			strip("Jamb", Vector3.new(1.1, DOOR_H + 0.3, 0.3), 0, (DOOR_H + 0.3) / 2, sgn * (DOOR_W / 2 + 0.15), TRIM)
		end
		strip("DoorHeader", Vector3.new(1.1, 0.35, DOOR_W + 0.6), 0, DOOR_H + 0.17, 0, TRIM)
		local leafW = DOOR_W - 0.2
		local vc = DOOR_W / 2 + 0.35 + leafW / 2
		strip("Door", Vector3.new(0.18, DOOR_H - 0.15, leafW), -0.52, (DOOR_H - 0.15) / 2, vc, Color3.fromRGB(150, 100, 65))
		for _, h in ipairs({ 2, 5.2 }) do
			strip("DoorPanel", Vector3.new(0.24, 2.4, leafW - 1.4), -0.54, h, vc, Color3.fromRGB(135, 88, 55))
		end
		part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = rcf * CFrame.new(-0.7, 3.6, vc + leafW / 2 - 0.4), Color = Color3.fromRGB(230, 200, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = m })
	end

	-- window trim and curtains
	local curtain = opts.curtain or Color3.fromRGB(200, 80, 90)
	for _, wnd in ipairs(windows or {}) do
		local v = wnd.c
		strip("Sill", Vector3.new(0.6, 0.25, 6.8), ROOM_U - 0.6, 2.9, v, TRIM)
		strip("WindowTop", Vector3.new(0.25, 0.3, 6.6), ROOM_U - 0.5, 8.15, v, TRIM)
		strip("CurtainRod", Vector3.new(0.12, 0.12, 9), ROOM_U - 0.75, 8.7, v, Color3.fromRGB(90, 70, 50))
		for _, sgn in ipairs({ -1, 1 }) do
			local c = part({ Name = "Curtain", Size = Vector3.new(0.12, 6.6, 1.5), CFrame = rcf * CFrame.new(ROOM_U - 0.8, 5.35, v + sgn * 3.7), Color = curtain, Material = Enum.Material.Fabric, CanCollide = false, Parent = m })
			c:SetAttribute("Curtain", true)
			strip("Tie", Vector3.new(0.2, 0.25, 1.6), ROOM_U - 0.82, 4, v + sgn * 3.7, curtain:Lerp(Color3.new(1, 1, 1), 0.4))
		end
	end
	for _, v in ipairs(sideWindows) do
		local inward = v > 0 and -1 or 1
		strip("Sill", Vector3.new(6.8, 0.25, 0.6), ROOM_U / 2, 2.9, v + inward * 0.6, TRIM)
		strip("WindowTop", Vector3.new(6.6, 0.3, 0.25), ROOM_U / 2, 8.15, v + inward * 0.5, TRIM)
	end

	-- ceiling light
	local fixture = part({ Name = "CeilingLight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.2, 2.2), CFrame = rcf * CFrame.new(ROOM_U / 2, WALL_H - 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(255, 244, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	local l = Instance.new("PointLight")
	l.Range = 20
	l.Brightness = opts.bright and 1.4 or 0.9
	l.Color = Color3.fromRGB(255, 225, 180)
	l.Shadows = false
	l.Parent = fixture
end

local CURTAINS = {
	Color3.fromRGB(200, 80, 90), Color3.fromRGB(90, 130, 200), Color3.fromRGB(230, 190, 90), Color3.fromRGB(110, 170, 120), Color3.fromRGB(170, 120, 200), Color3.fromRGB(240, 240, 235),
}

local function signature(plot, data)
	local parts = { plot.owner.DisplayName, tostring(House.floorCount(data)) }
	for _, p in ipairs(House.placements(data)) do
		table.insert(parts, string.format("%s@%d,%d,%d,%d", p.key, p.floor, p.side, p.row, p.size))
	end
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
		-- runner rug with a border, wall sconces between the doors
		part({ Name = "Runner", Size = Vector3.new(4.4, 0.06, HOUSE_Z1 - HOUSE_Z0 - 4), CFrame = L(0, y + 0.23, (HOUSE_Z0 + HOUSE_Z1) / 2), Color = Color3.fromRGB(200, 170, 90), Material = Enum.Material.Fabric, CanCollide = false, Parent = lv })
		part({ Name = "Runner", Size = Vector3.new(3.6, 0.08, HOUSE_Z1 - HOUSE_Z0 - 4.8), CFrame = L(0, y + 0.24, (HOUSE_Z0 + HOUSE_Z1) / 2), Color = Color3.fromRGB(150, 40, 50), Material = Enum.Material.Fabric, CanCollide = false, Parent = lv })
		for r = 1, ROWS - 1 do
			local z = HOUSE_Z0 + r * ROOM_V
			for _, sd in ipairs({ -1, 1 }) do
				local x = sd * (HALL_W / 2 - 0.5)
				part({ Name = "SconcePlate", Size = Vector3.new(0.15, 1, 0.6), CFrame = L(x, y + 7, z), Color = Color3.fromRGB(200, 170, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = lv })
				local bulb = part({ Name = "Sconce", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = L(x - sd * 0.35, y + 7.3, z), Color = Color3.fromRGB(255, 235, 190), Material = Enum.Material.Neon, CanCollide = false, Parent = lv })
				if (r + (sd == 1 and 1 or 0)) % 2 == 0 then
					local l = Instance.new("PointLight")
					l.Range = 16
					l.Brightness = 0.8
					l.Color = Color3.fromRGB(255, 220, 170)
					l.Shadows = false
					l.Parent = bulb
				end
			end
		end
		-- outside: a trim band at every floor line
		if f > 0 then
			for _, b in ipairs({
				{ HALF_X * 2 + 2, 0.6, HOUSE_Z0 - 0.75, 0 },
				{ HALF_X * 2 + 2, 0.6, HOUSE_Z1 + 0.75, 0 },
			}) do
				part({ Name = "Band", Size = Vector3.new(b[1], b[2], 0.3), CFrame = L(b[4], y - 0.5, b[3]), Color = TRIM, CanCollide = false, Parent = lv })
			end
			for _, sd in ipairs({ -1, 1 }) do
				part({ Name = "Band", Size = Vector3.new(0.3, 0.6, HOUSE_Z1 - HOUSE_Z0 + 1.8), CFrame = L(sd * (HALF_X + 0.75), y - 0.5, (HOUSE_Z0 + HOUSE_Z1) / 2), Color = TRIM, CanCollide = false, Parent = lv })
			end
		end

		-- outside walls (cover the slab edge too)
		local h0 = f == 0 and GROUND_Y or y - 1
		local h1 = floorY(f + 1) - 1
		local wb, wt = y + 3, y + 8
		local exProps = { Name = "Outside", Style = ext }
		local frontHoles = { { c = -(HALL_W / 2 + ROOM_U / 2), w = 6, b = wb, t = wt, glass = true, out = -1 }, { c = HALL_W / 2 + ROOM_U / 2, w = 6, b = wb, t = wt, glass = true, out = -1 } }
		if f == 0 then
			table.insert(frontHoles, { c = 0, w = 6, b = h0, t = y + DOOR_H + 0.5 })
		else
			table.insert(frontHoles, { c = 0, w = 6, b = wb, t = wt, glass = true, out = -1 })
		end
		wall(lv, L(0, 0, HOUSE_Z0 - 0.3), -HALF_X - 0.6, HALF_X + 0.6, h0, h1, 0.6, exProps, frontHoles)
		for _, side in ipairs({ -1, 1 }) do
			local holes = {}
			for r = 0, ROWS - 1 do
				table.insert(holes, { c = HOUSE_Z0 + ROOM_V * (r + 0.5), w = 6, b = wb, t = wt, glass = true, out = -side })
			end
			wall(lv, L(side * (HALF_X + 0.3), 0, 0) * ALONG_Z, HOUSE_Z0, HOUSE_Z1 + 0.6, h0, h1, 0.6, exProps, holes)
			-- back of the room block, beside the stairwell
			local xa, xb = side * (HALL_W / 2 + 0.6), side * (HALF_X + 0.6)
			local mid = (xa + xb) / 2
			wall(lv, L(mid, 0, HOUSE_Z1 + 0.3), -math.abs(xb - xa) / 2, math.abs(xb - xa) / 2, h0, h1, 0.6, exProps, { { c = side * (HALL_W / 2 + ROOM_U / 2) - mid, w = 6, b = wb, t = wt, glass = true, out = 1 } })
			-- stairwell sides
			wall(lv, L(side * (HALL_W / 2 + 0.3), 0, 0) * ALONG_Z, HOUSE_Z1, TOWER_Z1 + 0.6, h0, h1, 0.6, exProps)
		end
		wall(lv, L(0, 0, TOWER_Z1 + 0.3), -HALL_W / 2 - 0.6, HALL_W / 2 + 0.6, h0, h1, 0.6, exProps, { { c = HALL_W / 4, w = 3, b = wb, t = wt, glass = true, out = 1 } })

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

	-- foundation, corner posts, front porch
	local g = levels[0]
	local stone = { Color = Color3.fromRGB(150, 145, 140), Material = Enum.Material.Cobblestone }
	local function block(parent, name, size, x, y, z, props)
		local p = table.clone(props)
		p.Name, p.Size, p.CFrame, p.Parent = name, size, L(x, y, z), parent
		return part(p)
	end
	block(g, "Foundation", Vector3.new(HALF_X * 2 + 2, 1.2, 0.5), 0, GROUND_Y + 0.6, HOUSE_Z0 - 0.8, stone)
	block(g, "Foundation", Vector3.new(HALF_X * 2 + 2, 1.2, 0.5), 0, GROUND_Y + 0.6, HOUSE_Z1 + 0.85, stone)
	for _, sd in ipairs({ -1, 1 }) do
		block(g, "Foundation", Vector3.new(0.5, 1.2, HOUSE_Z1 - HOUSE_Z0 + 2), sd * (HALF_X + 0.8), GROUND_Y + 0.6, (HOUSE_Z0 + HOUSE_Z1) / 2, stone)
		block(g, "Foundation", Vector3.new(0.5, 1.2, TOWER_Z1 - HOUSE_Z1 + 1), sd * (HALL_W / 2 + 0.8), GROUND_Y + 0.6, (HOUSE_Z1 + TOWER_Z1) / 2 + 0.5, stone)
	end
	local tall = floorY(floors) - 1 - GROUND_Y
	for _, c in ipairs({ { -1, HOUSE_Z0 }, { 1, HOUSE_Z0 }, { -1, HOUSE_Z1 }, { 1, HOUSE_Z1 } }) do
		block(g, "Corner", Vector3.new(1.3, tall, 1.3), c[1] * (HALF_X + 0.5), GROUND_Y + tall / 2, c[2] + (c[2] < 0 and -0.5 or 0.5), { Color = TRIM })
	end
	-- porch: steps, a little roof on posts, two lanterns
	local trimP = { Color = TRIM }
	block(g, "Step", Vector3.new(9, 0.3, 4), 0, GROUND_Y + 0.15, HOUSE_Z0 - 2.6, stone)
	block(g, "Step", Vector3.new(8, 0.3, 2), 0, GROUND_Y + 0.45, HOUSE_Z0 - 1.6, stone)
	block(g, "PorchRoof", Vector3.new(10, 0.5, 4.6), 0, floorY(0) + DOOR_H + 1.2, HOUSE_Z0 - 2.6, { Color = Color3.fromRGB(90, 60, 45), Material = Enum.Material.WoodPlanks })
	block(g, "PorchTrim", Vector3.new(10.4, 0.3, 0.3), 0, floorY(0) + DOOR_H + 0.85, HOUSE_Z0 - 4.8, trimP)
	for _, sd in ipairs({ -1, 1 }) do
		block(g, "PorchPost", Vector3.new(0.5, DOOR_H + 1.4, 0.5), sd * 4.5, floorY(0) + (DOOR_H + 1.4) / 2, HOUSE_Z0 - 4.5, trimP)
		block(g, "DoorJamb", Vector3.new(0.6, DOOR_H + 0.9, 0.9), sd * 3.3, floorY(0) + (DOOR_H + 0.9) / 2 - 0.6, HOUSE_Z0 - 0.3, trimP)
		local lantern = block(g, "Lantern", Vector3.new(0.6, 0.9, 0.6), sd * 4.3, floorY(0) + 6, HOUSE_Z0 - 0.9, { Color = Color3.fromRGB(255, 220, 150), Material = Enum.Material.Neon })
		block(g, "LanternCap", Vector3.new(0.8, 0.2, 0.8), sd * 4.3, floorY(0) + 6.55, HOUSE_Z0 - 0.9, { Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal })
		local l = Instance.new("PointLight")
		l.Range = 14
		l.Brightness = 1
		l.Color = Color3.fromRGB(255, 210, 150)
		l.Parent = lantern
	end
	block(g, "DoorHeader", Vector3.new(7.2, 0.6, 0.9), 0, floorY(0) + DOOR_H + 0.3, HOUSE_Z0 - 0.3, trimP)
	block(g, "Doormat", Vector3.new(4, 0.08, 2.4), 0, GROUND_Y + 0.64, HOUSE_Z0 - 1.6, { Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Fabric, CanCollide = false })

	-- rooms: walk every cell of every floor
	local grid = House.grid(data)
	for f = 0, floors - 1 do
		for _, side in ipairs({ -1, 1 }) do
			for row = 0, ROWS - 1 do
				local s = grid[f][side][row]
				local m = Instance.new("Model")
				m.Parent = levels[f]
				if not s then
					m.Name = "EmptyCell"
					local rcf = roomFrame(plot, f, side, row, 1)
					buildShell(m, rcf, row, side, 1, hall, hallFloor, hall, { door = false, plain = true })
					local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.6, 6), CFrame = rcf * CFrame.new(-0.45, 5, 0), Color = Color3.fromRGB(250, 220, 120), Parent = m })
					local sg = surface(plate, Enum.NormalId.Left, Vector2.new(600, 160))
					label(sg, "🚧 Empty: plan it on your layout board", Color3.fromRGB(60, 40, 30)).TextStrokeTransparency = 1
				elseif s.row ~= row then
					m:Destroy() -- second cell of a big room, already built
				else
					m.Name = s.key
					local rcf = roomFrame(plot, f, side, row, s.size)
					local wallStyle = House.style(data, s.key, "wall")
					local floorStyle = House.style(data, s.key, "floor")
					local isMe = s.kind == "me"
					local tier = s.kind == "dorm" and data.rooms[s.index] and data.rooms[s.index].tier or 1
					buildShell(m, rcf, row, side, s.size, wallStyle, floorStyle, hall, { door = true, window = not (isMe or s.kind == "common"), curtain = CURTAINS[(#s.key * 7 + row * 3 + f) % #CURTAINS + 1], bright = tier >= 3 or s.kind ~= "dorm" })
					local info = roomInfo(plot, rcf, s.key, f, s.size, s.kind == "common" or s.kind == "facility")
					plot.rooms[s.key] = info
					tagRoom(m, plot, info)
					CollectionService:AddTag(m, "HouseRoom")
					if isMe then
						m:SetAttribute("IsMyRoom", true)
						m:SetAttribute("OwnerUserId", plot.owner.UserId)
						myRoomBasics(m, rcf)
						for id, shown in pairs(data.furniture) do
							if shown and FurnitureProps[id] then
								FurnitureProps[id](m, rcf)
							end
						end
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
							-- a desk under the side wall and a wall picture
							prop(m, rcf, 4.5, 2.6, -ROOM_V * s.size / 2 + 1.4, Vector3.new(3.2, 0.25, 1.6), BED_WOOD, { Material = Enum.Material.Wood })
							prop(m, rcf, 4.5, 1.25, -ROOM_V * s.size / 2 + 1.4, Vector3.new(3, 2.5, 1.4), BED_WOOD:Lerp(Color3.new(0, 0, 0), 0.2), { Material = Enum.Material.Wood })
							prop(m, rcf, 4.5, 3.1, -ROOM_V * s.size / 2 + 1.2, Vector3.new(1.2, 0.8, 0.08), DARK)
							prop(m, rcf, 9, 6.5, ROOM_V * s.size / 2 - 0.45, Vector3.new(3, 2.2, 0.1), Color3.fromRGB(120, 180, 230), { CanCollide = false })
							prop(m, rcf, 9, 6.5, ROOM_V * s.size / 2 - 0.42, Vector3.new(3.4, 2.6, 0.06), Color3.fromRGB(200, 160, 60), { CanCollide = false, Material = Enum.Material.Foil })
						end
						if room and room.tier >= 4 then
							local w = ROOM_V * s.size
							for _, v in ipairs({ -w / 2 + 0.5, w / 2 - 0.5 }) do
								prop(m, rcf, ROOM_U / 2, WALL_H - 0.3, v, Vector3.new(ROOM_U - 1, 0.4, 0.3), Color3.fromRGB(255, 210, 60), { Material = Enum.Material.Neon, CanCollide = false })
							end
						end
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
	-- eave boards and a chimney
	for _, sd in ipairs({ -1, 1 }) do
		part({ Name = "Fascia", Size = Vector3.new(0.4, 0.8, len + 0.2), CFrame = L(sd * (half + 0.15), top + 0.85, (HOUSE_Z0 + HOUSE_Z1) / 2), Color = TRIM, Parent = lv })
	end
	part({ Name = "Ridge", Size = Vector3.new(1, 0.6, len + 0.2), CFrame = L(0, top + 1 + ridge + 0.2, (HOUSE_Z0 + HOUSE_Z1) / 2), Color = roof.color:Lerp(Color3.new(0, 0, 0), 0.25), Material = mat(roof.material), Parent = lv })
	part({ Name = "Chimney", Size = Vector3.new(3, ridge + 3, 3), CFrame = L(13, top + 1 + (ridge + 3) / 2, 22), Color = Color3.fromRGB(150, 70, 55), Material = Enum.Material.Brick, Parent = lv })
	part({ Name = "ChimneyCap", Size = Vector3.new(3.6, 0.5, 3.6), CFrame = L(13, top + 1 + ridge + 3.25, 22), Color = Color3.fromRGB(80, 80, 85), Material = Enum.Material.Concrete, Parent = lv })
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

---------------------------------------------------------------------------
-- The three boards on the wall of your room: floor layout, who lives where,
-- and how happy everyone is. Walk up and press E (or click) to open each.
---------------------------------------------------------------------------
local INK = Color3.fromRGB(50, 40, 40)

local function box(parent, x, y, w, h, color, text, textColor)
	local f = Instance.new("TextLabel")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color or Color3.new(1, 1, 1)
	f.BackgroundTransparency = color and 0 or 1
	f.BorderSizePixel = 0
	f.Font = Enum.Font.FredokaOne
	f.TextScaled = true
	f.RichText = true
	f.TextColor3 = textColor or INK
	f.Text = text or ""
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	return f
end

local BOARD_W, BOARD_H = 9, 7.2
local CANVAS = Vector2.new(900, 720)

local CELL_COLORS = {
	me = Color3.fromRGB(255, 220, 110),
	common = Color3.fromRGB(170, 230, 190),
	dorm = Color3.fromRGB(170, 205, 255),
	facility = Color3.fromRGB(255, 185, 215),
}

function PlotService.CellText(p)
	if p.kind == "me" then
		return "⭐"
	elseif p.kind == "common" then
		return "🛋"
	elseif p.kind == "dorm" then
		return "🛏" .. p.index
	end
	return Config.FacilityById[p.id].emoji
end

local function layoutBoard(sg, data)
	box(sg, 0, 0, 900, 80, nil, "🏗 FLOOR PLANS")
	local floors = House.floorCount(data)
	local showLocked = floors < Config.MaxFloors
	local n = math.max(3, floors + (showLocked and 1 or 0))
	local colW = 880 / n
	local grid = House.grid(data)
	local cellW = math.min(70, (colW - 30) / 2)
	local cellH = 88
	for f = 0, floors - (showLocked and 0 or 1) do
		local x0 = 10 + f * colW
		if f >= floors then
			box(sg, x0 + 6, 120, colW - 12, 560, Color3.fromRGB(200, 195, 185), string.format("🔒 Floor %d\n$%s", f + 1, SchoolMath.format(Config.FloorCost(f + 1))), Color3.fromRGB(90, 80, 80))
		else
			box(sg, x0, 84, colW, 32, nil, "Floor " .. (f + 1))
			for _, side in ipairs({ -1, 1 }) do
				local cx = side == -1 and (x0 + colW / 2 - 8 - cellW) or (x0 + colW / 2 + 8)
				for row = 0, ROWS - 1 do
					local p = grid[f][side][row]
					local y = 120 + (ROWS - 1 - row) * (cellH + 6) -- front door at the bottom
					if not p then
						box(sg, cx, y, cellW, cellH, Color3.fromRGB(235, 230, 220), "＋", Color3.fromRGB(150, 140, 130))
					elseif p.row == row then
						local h = cellH * p.size + 6 * (p.size - 1)
						box(sg, cx, y - (p.size - 1) * (cellH + 6), cellW, h, CELL_COLORS[p.kind], PlotService.CellText(p))
					end
				end
			end
			box(sg, x0 + colW / 2 - 6, 120, 12, ROWS * (cellH + 6) - 6, Color3.fromRGB(215, 200, 170))
		end
	end
	box(sg, 0, 690, 900, 30, nil, "🚪 front door at the bottom  •  ＋ = empty cell", Color3.fromRGB(110, 100, 100))
end

local function studentsBoard(sg, data)
	box(sg, 0, 0, 900, 80, nil, "👥 WHO LIVES WHERE")
	local housed = {}
	local lines = {}
	for i, room in ipairs(data.rooms) do
		local names = {}
		for _, uid in ipairs(room.occupants) do
			local s = data.students[uid]
			if s then
				housed[uid] = true
				local def = Config.StudentById[s.id]
				table.insert(names, string.format('<font color="#%s">%s %s</font>', Config.Rarities[def.rarity].color:Lerp(Color3.new(0, 0, 0), 0.35):ToHex(), Config.Personalities[def.personality].emoji, string.match(def.name, "%S+$") or def.name))
			end
		end
		table.insert(lines, string.format("<b>Room %d</b> (%d/%d)  %s", i, #room.occupants, Config.Beds(room), #names > 0 and table.concat(names, ", ") or "empty"))
	end
	local unhoused = 0
	for uid in pairs(data.students) do
		if not housed[uid] then
			unhoused += 1
		end
	end
	local maxLines = 13
	for i = 1, math.min(maxLines, #lines) do
		local l = box(sg, 24, 84 + (i - 1) * 44, 852, 40, nil, lines[i])
		l.TextXAlignment = Enum.TextXAlignment.Left
	end
	if #lines > maxLines then
		box(sg, 24, 84 + maxLines * 44, 852, 30, nil, string.format("+%d more rooms", #lines - maxLines), Color3.fromRGB(110, 100, 100))
	end
	box(sg, 0, 670, 900, 44, unhoused > 0 and Color3.fromRGB(255, 200, 190) or nil, unhoused > 0 and string.format("😴 %d student%s without a bed (earning $0)", unhoused, unhoused == 1 and "" or "s") or "✅ Everyone has a bed")
end

local function satisfactionBoard(sg, data, totals)
	local avg = totals and totals.satisfaction or 0
	box(sg, 0, 0, 900, 80, nil, string.format("😊 HAPPINESS  %s %d%%", SchoolMath.moodEmoji(avg), math.floor(avg)))
	local list = {}
	for i, room in ipairs(data.rooms) do
		if #room.occupants > 0 then
			local st = totals and totals.rooms[i]
			table.insert(list, { i = i, sat = st and st.satisfaction or 0 })
		end
	end
	table.sort(list, function(a, b)
		return a.sat < b.sat
	end)
	for k = 1, math.min(11, #list) do
		local e = list[k]
		local y = 90 + (k - 1) * 52
		local l = box(sg, 20, y, 250, 44, nil, string.format("%s Room %d", SchoolMath.moodEmoji(e.sat), e.i))
		l.TextXAlignment = Enum.TextXAlignment.Left
		box(sg, 280, y + 6, 520, 32, Color3.fromRGB(225, 215, 200))
		local color = Color3.fromRGB(240, 80, 80):Lerp(Color3.fromRGB(80, 210, 110), math.clamp(e.sat / 100, 0, 1))
		box(sg, 280, y + 6, math.max(12, 520 * e.sat / 100), 32, color)
		box(sg, 810, y, 80, 44, nil, math.floor(e.sat) .. "%")
	end
	box(sg, 0, 670, 900, 44, nil, #list > 0 and "Unhappiest rooms first. Press E for the details." or "Move students into rooms to see how they feel.", Color3.fromRGB(110, 100, 100))
end

local BOARDS = {
	{ id = "layout", title = "Floor plans", action = "🏗 Change layout", v = -10.5, draw = layoutBoard },
	{ id = "rooms", title = "Students", action = "👥 Move students", v = 0, draw = studentsBoard },
	{ id = "satisfaction", title = "Happiness", action = "😊 Check happiness", v = 10.5, draw = satisfactionBoard },
}

local function buildBoards(plot, parent, info, data, totals)
	local rcf = info.rcf
	for _, b in ipairs(BOARDS) do
		part({ Name = "BoardFrame", Size = Vector3.new(0.2, BOARD_H + 0.5, BOARD_W + 0.5), CFrame = rcf * CFrame.new(ROOM_U - 0.5, 6.4, b.v), Color = WOOD, Material = Enum.Material.Wood, Parent = parent })
		local board = part({ Name = "Board", Size = Vector3.new(0.2, BOARD_H, BOARD_W), CFrame = rcf * CFrame.new(ROOM_U - 0.65, 6.4, b.v), Color = Color3.fromRGB(250, 246, 235), Parent = parent })
		board:SetAttribute("Board", b.id)
		board:SetAttribute("OwnerUserId", plot.owner.UserId)
		b.draw(surface(board, Enum.NormalId.Left, CANVAS), data, totals)
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 30
		cd.Parent = board
		CollectionService:AddTag(board, "BoardClick")
		local pp = prompt(board, b.action, b.title, 9)
		pp:SetAttribute("OwnerUserId", plot.owner.UserId)
		pp:SetAttribute("Board", b.id)
		CollectionService:AddTag(pp, "BoardPrompt")
		-- pin
		part({ Name = "Pin", Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), CFrame = rcf * CFrame.new(ROOM_U - 0.8, 6.4 + BOARD_H / 2 - 0.3, b.v), Color = Color3.fromRGB(220, 40, 40), CanCollide = false, Parent = parent })
	end
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
			local beds = Config.Beds(room)
			local w = ROOM_V * info.size
			for b = 1, beds do
				local v = -w / 2 + (w / beds) * (b - 0.5)
				local occ = room.occupants[b]
				local color = Color3.fromRGB(120, 160, 230)
				if occ and data.students[occ] then
					color = Config.Personalities[Config.StudentById[data.students[occ].id].personality].color
				end
				bed(lv, rcf * CFrame.new(ROOM_U - 4.2, 0.2, v) * BED_TURN, color)
				-- nightstand + lamp between beds when there's space
				if b < beds and w / beds >= 5.4 then
					local nv = v + w / beds / 2
					local ns = rcf * CFrame.new(ROOM_U - 1.4, 0, nv)
					part({ Name = "Nightstand", Size = Vector3.new(1.4, 1.8, 1.3), CFrame = ns * CFrame.new(0, 1.1, 0), Color = BED_WOOD, Material = Enum.Material.Wood, Parent = lv })
					part({ Name = "Drawer", Size = Vector3.new(0.05, 0.5, 1), CFrame = ns * CFrame.new(-0.72, 1.4, 0), Color = BED_WOOD:Lerp(Color3.new(0, 0, 0), 0.25), CanCollide = false, Parent = lv })
					part({ Name = "LampBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 0.25, 0.25), CFrame = ns * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(60, 60, 65), CanCollide = false, Parent = lv })
					part({ Name = "LampShade", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.8, 0.8), CFrame = ns * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(255, 235, 200), Material = Enum.Material.Neon, CanCollide = false, Parent = lv })
				end
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
						local start = rcf * CFrame.new(rng:NextNumber(3, ROOM_U - 8), 0.2, rng:NextNumber(-w / 2 + 2, w / 2 - 2))
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

	if plot.rooms.me then
		buildBoards(plot, levels[plot.rooms.me.floor], plot.rooms.me, data, totals)
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

-- standing in your room, looking at the boards
function PlotService.MyRoomCFrame(plot)
	local info = plot.rooms and plot.rooms.me
	if not info then
		return PlotService.SpawnCFrame(plot)
	end
	local pos = (info.rcf * CFrame.new(7, 3, 0)).Position
	return CFrame.lookAt(pos, pos + info.u)
end

return PlotService
