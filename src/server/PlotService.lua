-- Builds the world (plaza + plots) and renders each player's boarding house
-- from data. Everything is procedural, so the place needs no prebuilt models.
--
-- A house is one walkable building drawn from the player's floor plan
-- (shared/House.lua): hallway tiles, rectangular rooms, stairs between floors,
-- and floors that may hang out over supported ones. Plot-local axes: -Z is the
-- front (toward the plaza), +X is on your left when you walk in (maps draw it mirrored).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local SchoolMath = require(ReplicatedStorage.Shared.SchoolMath)
local House = require(ReplicatedStorage.Shared.House)

local PlotService = {}
PlotService.Plots = {} -- list of { model, cf, owner, house, live }

local FLOOR_H = House.FloorHeight -- slab top to slab top
local WALL_H = FLOOR_H - 1
-- size of the room being furnished (studs): depth from the furnished wall and
-- width along it. Set per room before its props are built.
local ROOM_U, ROOM_V = 18, 18
local HOUSE_Z0 = House.Z0 -- front of the lot
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
	Lighting.Brightness = 1.6
	Lighting.ExposureCompensation = -0.3
	Lighting.Ambient = Color3.fromRGB(40, 40, 48)
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 105, 118)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	local function effect(class, props)
		local e = Lighting:FindFirstChildOfClass(class) or Instance.new(class)
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Parent = Lighting
	end
	effect("Atmosphere", { Density = 0.3, Offset = 0.25, Color = Color3.fromRGB(200, 215, 235), Decay = Color3.fromRGB(110, 120, 140), Glare = 0.1, Haze = 0.8 })
	effect("BloomEffect", { Intensity = 0.25, Size = 20, Threshold = 2.4 })
	effect("SunRaysEffect", { Intensity = 0.03, Spread = 0.6 })
	effect("ColorCorrectionEffect", { Brightness = -0.04, Contrast = 0.1, Saturation = 0.12, TintColor = Color3.fromRGB(255, 248, 240) })
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
		l.Brightness = 0.55
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
			Size = Vector3.new(PLOT_W, 0.6, PLOT_D + 10),
			CFrame = cf * CFrame.new(0, 0.3, 5),
			Color = Color3.fromRGB(150, 210, 120),
			Material = Enum.Material.Grass,
			Parent = model,
		})
		-- front path + a few trees so the yard doesn't look empty
		part({ Name = "Walk", Size = Vector3.new(8, 0.2, PLOT_D / 2 + HOUSE_Z0), CFrame = cf * CFrame.new(0, 0.7, (-PLOT_D / 2 + HOUSE_Z0) / 2), Color = Color3.fromRGB(205, 195, 175), Material = Enum.Material.Cobblestone, Parent = model })
		for _, t in ipairs({ { -45, -55 }, { 45, -50 }, { -62, 10 }, { 63, 30 }, { -62, 58 }, { 62, 70 } }) do
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

-- default accessories per outfit look (Config.Looks); a student's own `acc` list replaces them
local LOOK_ACC = {
	Royal = { "crown" },
	Nerd = { "glasses" },
	Musician = { "guitar" },
	Jock = { "cap" },
	Gamer = { "headset" },
	Artist = { "beret" },
	Rebel = { "shades", "jacket" },
	Prankster = { "propeller" },
}

local function finishStudent(m, uid, student, head, root)
	local def = Config.StudentById[student.id]
	local rarity = Config.Rarities[def.rarity]
	if rarity.rank >= 5 then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = 10
		light.Brightness = 1.1
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
	label(bb, (student.shiny and "✨" or "") .. (def.crew and "🌹 " or "") .. def.name, def.crew and Config.Tags.LaRose.color or Color3.new(1, 1, 1), UDim2.fromScale(1, 0.55))
	local r = label(bb, Config.TagEmoji(def) .. " " .. def.rarity, rarity.color, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55))
	r.Name = "RarityLabel"
	m:SetAttribute("StudentUid", uid)
	m:SetAttribute("Tags", table.concat(def.tags, ","))
	CollectionService:AddTag(m, "Student")
	return m
end

local function buildAvatarStudent(template, uid, student, cf, skin, seed)
	local def = Config.StudentById[student.id]
	local m = template:Clone()
	m.Name = def.name
	skin = def.skin or skin
	local shirt = def.shirt or Config.Looks[def.look].color
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
	local function acc(name, size, offset, color, material, base, shape)
		base = base or head
		return weldTo(base, part({ Name = name, Shape = shape, Size = size, CFrame = base.CFrame * offset, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = m }))
	end
	local wear = def.acc or LOOK_ACC[def.look] or {}
	local has = {}
	for _, a in ipairs(wear) do
		has[a] = true
	end
	-- hair: a cap over the top and back of the head; girls get it to the shoulders
	local hairColor = def.hair or HAIR[(seed // 3) % #HAIR + 1]
	local long = def.gender == "F"
	local top = has.bighair and 0.6 or 0.32
	acc("Hair", Vector3.new(hs.X * 1.08, hs.Y * top, hs.Z * 1.08), CFrame.new(0, hs.Y * (0.4 + (top - 0.32) / 2), 0.02), hairColor, Enum.Material.Fabric)
	local backLen = long and 1.35 or 0.7
	acc("HairBack", Vector3.new(hs.X * 1.08, hs.Y * backLen, hs.Z * 0.2), CFrame.new(0, hs.Y * (0.47 - backLen / 2), hs.Z * 0.48), hairColor, Enum.Material.Fabric)
	if long then
		for _, x in ipairs({ -1, 1 }) do
			acc("HairSide", Vector3.new(hs.X * 0.14, hs.Y * 1.1, hs.Z * 0.7), CFrame.new(x * hs.X * 0.5, -hs.Y * 0.12, hs.Z * 0.12), hairColor, Enum.Material.Fabric)
		end
	end
	if seed % 2 == 0 or has.bighair then
		acc("Fringe", Vector3.new(hs.X * 0.9, hs.Y * 0.14, hs.Z * 0.12), CFrame.new(-hs.X * 0.05, hs.Y * 0.3, -hs.Z * 0.5), hairColor, Enum.Material.Fabric)
	end
	if has.curly then
		for i = 0, 7 do
			local ang = i / 8 * math.pi * 2
			acc("Curl", Vector3.new(0.45, 0.45, 0.45), CFrame.new(math.cos(ang) * hs.X * 0.45, hs.Y * 0.55, math.sin(ang) * hs.Z * 0.45), hairColor, Enum.Material.Fabric, nil, Enum.PartType.Ball)
		end
	end
	if has.wavy then
		for _, x in ipairs({ -1, 1 }) do
			acc("Wave", Vector3.new(hs.X * 0.16, hs.Y * 0.55, hs.Z * 0.8), CFrame.new(x * hs.X * 0.52, hs.Y * 0.2, 0.05) * CFrame.Angles(0, 0, x * 0.15), hairColor, Enum.Material.Fabric)
		end
	end
	if has.crown then
		acc("Crown", Vector3.new(hs.X * 0.85, 0.35, hs.Z * 0.85), CFrame.new(0, hs.Y * 0.7, 0), Color3.fromRGB(255, 210, 60), Enum.Material.Foil)
		for i = 0, 3 do
			acc("CrownPoint", Vector3.new(0.18, 0.3, 0.18), CFrame.new(0, hs.Y * 0.7 + 0.3, 0) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, hs.Z * 0.38), Color3.fromRGB(255, 210, 60), Enum.Material.Foil)
		end
	end
	if has.glasses then
		for _, x in ipairs({ -0.25, 0.25 }) do
			acc("Lens", Vector3.new(0.34, 0.3, 0.06), CFrame.new(x * hs.X, hs.Y * 0.08, -hs.Z * 0.53), Color3.fromRGB(200, 230, 255), Enum.Material.Glass).Transparency = 0.4
		end
		acc("Bridge", Vector3.new(hs.X * 0.9, 0.06, 0.06), CFrame.new(0, hs.Y * 0.12, -hs.Z * 0.55), Color3.fromRGB(20, 20, 20))
	end
	if has.guitar then
		acc("GuitarBody", Vector3.new(1.1, 1.3, 0.3), CFrame.new(0.2, -0.3, torso.Size.Z / 2 + 0.25) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(180, 60, 40), Enum.Material.Wood, torso)
		acc("GuitarNeck", Vector3.new(0.18, 1.6, 0.12), CFrame.new(-0.45, 0.75, torso.Size.Z / 2 + 0.25) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(60, 35, 20), Enum.Material.Wood, torso)
	end
	if has.cap then
		acc("Cap", Vector3.new(hs.X * 1.1, 0.35, hs.Z * 1.1), CFrame.new(0, hs.Y * 0.55, 0), Color3.fromRGB(220, 50, 50), Enum.Material.Fabric)
		acc("Brim", Vector3.new(hs.X * 0.95, 0.08, 0.55), CFrame.new(0, hs.Y * 0.42, -hs.Z * 0.75), Color3.fromRGB(220, 50, 50), Enum.Material.Fabric)
	end
	if has.headset then
		acc("Headset", Vector3.new(hs.X * 1.15, 0.12, 0.3), CFrame.new(0, hs.Y * 0.55, 0), Color3.fromRGB(30, 30, 35))
		for _, x in ipairs({ -1, 1 }) do
			acc("Ear", Vector3.new(0.18, 0.5, 0.45), CFrame.new(x * hs.X * 0.56, 0, 0), Color3.fromRGB(40, 220, 200), Enum.Material.Neon)
		end
		acc("Mic", Vector3.new(0.06, 0.06, 0.5), CFrame.new(-hs.X * 0.5, -hs.Y * 0.2, -hs.Z * 0.3) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(30, 30, 35))
	end
	if has.headphones then
		acc("Band", Vector3.new(hs.X * 1.2, 0.16, 0.34), CFrame.new(0, hs.Y * 0.62, 0), Color3.fromRGB(240, 240, 240))
		for _, x in ipairs({ -1, 1 }) do
			acc("Cup", Vector3.new(0.3, 0.75, 0.75), CFrame.new(x * hs.X * 0.58, 0, 0), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, nil, Enum.PartType.Cylinder)
		end
	end
	if has.beret then
		acc("Beret", Vector3.new(hs.X * 1.1, 0.25, hs.Z * 1.1), CFrame.new(0.12, hs.Y * 0.62, 0) * CFrame.Angles(0, 0, -0.2), Color3.fromRGB(150, 30, 60), Enum.Material.Fabric)
	end
	if has.shades then
		acc("Shades", Vector3.new(hs.X * 0.95, 0.24, 0.08), CFrame.new(0, hs.Y * 0.1, -hs.Z * 0.54), Color3.fromRGB(15, 15, 15), Enum.Material.Glass)
	end
	if has.jacket then
		acc("Jacket", Vector3.new(torso.Size.X * 1.06, torso.Size.Y * 0.95, torso.Size.Z * 1.08), CFrame.new(0, 0, 0), Color3.fromRGB(30, 30, 35), Enum.Material.Leather, torso)
	end
	if has.propeller then
		acc("Propeller", Vector3.new(hs.X * 0.9, 0.25, hs.Z * 0.9), CFrame.new(0, hs.Y * 0.6, 0), Color3.fromRGB(255, 200, 50), Enum.Material.Fabric)
		acc("Blade", Vector3.new(1.4, 0.05, 0.22), CFrame.new(0, hs.Y * 0.6 + 0.3, 0), Color3.fromRGB(240, 70, 70))
	end
	if has.greenaura then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "GreenAura"
		aura.Color = ColorSequence.new(Color3.fromRGB(60, 255, 90))
		aura.LightEmission = 0.8
		aura.Transparency = NumberSequence.new(0.3, 1)
		aura.Size = NumberSequence.new(1.6, 0.2)
		aura.Rate = 14
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Parent = torso
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(60, 255, 90)
		glow.Range = 8
		glow.Brightness = 0.8
		glow.Parent = torso
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
	local look = Config.Looks[def.look]
	local seed = 0
	for i = 1, #uid do
		seed += string.byte(uid, i) * i
	end
	local skin = SKIN[(seed % #SKIN) + 1]

	local m = Instance.new("Model")
	m.Name = def.name
	local root = part({ Name = "Root", Size = Vector3.new(2, 2, 1), CFrame = cf * CFrame.new(0, 3, 0), Color = def.shirt or look.color, Parent = m })
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
	if def.look == "Royal" then
		limb("Crown", Vector3.new(1.1, 0.5, 1.1), CFrame.new(0, 2.55, 0), Color3.fromRGB(255, 210, 60)).Material = Enum.Material.Neon
	elseif def.look == "Nerd" then
		limb("Glasses", Vector3.new(1.2, 0.3, 0.1), CFrame.new(0, 1.8, -0.7), Color3.fromRGB(20, 20, 20))
	elseif def.look == "Musician" then
		limb("Guitar", Vector3.new(0.6, 2.2, 0.3), CFrame.new(0.4, -0.2, -0.7) * CFrame.Angles(0, 0, 0.6), Color3.fromRGB(180, 60, 40))
	elseif def.look == "Jock" then
		limb("Cap", Vector3.new(1.4, 0.4, 1.6), CFrame.new(0, 2.4, -0.2), Color3.fromRGB(220, 50, 50))
	end

	return finishStudent(m, uid, student, head, root)
end

---------------------------------------------------------------------------
-- Room props. Room frame: local X (u) runs from the furnished wall, usually
-- the door wall (u = 0), to the back wall (u = ROOM_U); local Z (v) runs
-- along it (-ROOM_V / 2 .. ROOM_V / 2); Y = floor.
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
	l.Brightness = 0.66
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

-- a spot where a student stands to use an item; Animator walks fans of the
-- item's tags here (attributes: Use emoji, UseTags, Face point)
local function useSpot(m, r, u, v, item, faceU, faceV)
	local sp = prop(m, r, u, 0.1, v, Vector3.new(0.5, 0.1, 0.5), Color3.new(1, 1, 1), { Name = "UseSpot", Transparency = 1, CanCollide = false, CanQuery = false })
	sp:SetAttribute("Use", item.use)
	sp:SetAttribute("UseTags", table.concat(item.tags, ","))
	sp:SetAttribute("Face", (r * CFrame.new(faceU, 0, faceV)).Position)
	return sp
end

function FacilityProps.living(m, r, data)
	local items = data.livingItems or {}
	local sofa = Color3.fromRGB(170, 110, 80)
	cyl(m, r, 9, 0.28, 0, 0.1, 10, Color3.fromRGB(200, 170, 130), { Material = Enum.Material.Fabric })
	-- sofa facing the outside wall
	prop(m, r, 5.5, 1.1, 0, Vector3.new(3, 1.2, 8), sofa, { Material = Enum.Material.Fabric })
	prop(m, r, 4.3, 2.3, 0, Vector3.new(0.8, 2.2, 8), sofa, { Material = Enum.Material.Fabric })
	for _, v in ipairs({ -4.3, 4.3 }) do
		prop(m, r, 5.3, 1.8, v, Vector3.new(3.2, 1.6, 0.8), sofa:Lerp(Color3.new(0, 0, 0), 0.1), { Material = Enum.Material.Fabric })
	end
	for i, v in ipairs({ -2, 2 }) do
		prop(m, r, 4.9, 2.6, v, Vector3.new(0.5, 1.3, 1.5), i == 1 and Color3.fromRGB(240, 200, 90) or Color3.fromRGB(120, 170, 220), { Material = Enum.Material.Fabric, Rot = CFrame.Angles(0, 0, -0.2) })
	end
	-- coffee table
	prop(m, r, 9.5, 1.5, 0, Vector3.new(2.6, 0.25, 4.5), WOOD, { Material = Enum.Material.Wood })
	for _, du in ipairs({ -1, 1 }) do
		for _, dv in ipairs({ -1.9, 1.9 }) do
			prop(m, r, 9.5 + du, 0.7, dv, Vector3.new(0.25, 1.4, 0.25), WOOD:Lerp(Color3.new(0, 0, 0), 0.3))
		end
	end
	-- TV wall
	prop(m, r, ROOM_U - 1.2, 1, 0, Vector3.new(1.8, 2, 7), WOOD:Lerp(Color3.new(0, 0, 0), 0.35), { Material = Enum.Material.Wood })
	if items.tv then
		prop(m, r, ROOM_U - 0.7, 4.6, 0, Vector3.new(0.3, 3.4, 6), DARK)
		local screen = prop(m, r, ROOM_U - 0.88, 4.6, 0, Vector3.new(0.05, 3, 5.6), Color3.fromRGB(70, 140, 220), { Material = Enum.Material.Neon, Transparency = 0.15 })
		light(screen, 12, Color3.fromRGB(120, 170, 255))
		useSpot(m, r, 6.4, -1.8, Config.LivingItemById.tv, ROOM_U, -1.8)
	end
	if items.console then
		prop(m, r, ROOM_U - 1.4, 2.2, -2, Vector3.new(1.2, 0.4, 1.6), Color3.fromRGB(240, 240, 245))
		prop(m, r, 9.3, 1.75, -1, Vector3.new(0.6, 0.2, 0.9), DARK)
		prop(m, r, 9.6, 1.75, 1.2, Vector3.new(0.6, 0.2, 0.9), DARK)
		useSpot(m, r, 6.4, 1.8, Config.LivingItemById.console, ROOM_U, 1.8)
	end
	if items.acoustic then
		prop(m, r, ROOM_U - 2, 0.9, -6.5, Vector3.new(0.6, 1.8, 0.6), DARK, { Rot = CFrame.Angles(0, 0, 0.1) })
		prop(m, r, ROOM_U - 2, 2.2, -6.5, Vector3.new(0.4, 2, 1.6), Color3.fromRGB(205, 150, 90), { Material = Enum.Material.Wood })
		prop(m, r, ROOM_U - 2, 4.1, -6.5, Vector3.new(0.25, 2.2, 0.3), Color3.fromRGB(70, 45, 25), { Material = Enum.Material.Wood })
		useSpot(m, r, ROOM_U - 5, -6, Config.LivingItemById.acoustic, ROOM_U - 2, -6.5)
	end
	if items.electric then
		prop(m, r, ROOM_U - 1.6, 1.2, 6.4, Vector3.new(1.6, 2.4, 2.2), Color3.fromRGB(25, 25, 28), { Material = Enum.Material.Leather })
		prop(m, r, ROOM_U - 2.42, 1.2, 6.4, Vector3.new(0.05, 1.6, 1.7), Color3.fromRGB(60, 60, 65), { Material = Enum.Material.Fabric })
		prop(m, r, ROOM_U - 2.44, 2.2, 5.8, Vector3.new(0.05, 0.2, 0.2), Color3.fromRGB(255, 60, 60), { Material = Enum.Material.Neon })
		prop(m, r, ROOM_U - 2.8, 2.2, 4.6, Vector3.new(0.35, 2, 1.4), Color3.fromRGB(200, 30, 40), { Rot = CFrame.Angles(0, 0, -0.15) })
		prop(m, r, ROOM_U - 2.6, 4, 4.6, Vector3.new(0.2, 2, 0.25), Color3.fromRGB(240, 240, 240), { Rot = CFrame.Angles(0, 0, -0.15) })
		useSpot(m, r, ROOM_U - 5, 5.5, Config.LivingItemById.electric, ROOM_U - 2, 6.4)
	end
	if items.vr then
		cyl(m, r, 2.6, 1.5, -6.3, 3, 1.2, Color3.fromRGB(235, 235, 240))
		prop(m, r, 2.6, 3.2, -6.3, Vector3.new(0.9, 0.5, 1.2), Color3.fromRGB(30, 30, 35))
		prop(m, r, 2.6, 3.2, -6.3, Vector3.new(0.95, 0.15, 1.25), Color3.fromRGB(120, 80, 255), { Material = Enum.Material.Neon })
		useSpot(m, r, 4.5, -5.6, Config.LivingItemById.vr, 9, -2)
	end
	if items.canvas then
		prop(m, r, 2.8, 2.6, 6, Vector3.new(0.3, 5.2, 0.3), WOOD, { Rot = CFrame.Angles(0, 0, -0.15) })
		prop(m, r, 2.3, 2.6, 6, Vector3.new(0.3, 5, 0.3), WOOD, { Rot = CFrame.Angles(0, 0, 0.15) })
		prop(m, r, 3, 4, 6, Vector3.new(0.12, 2.8, 2.4), Color3.fromRGB(250, 248, 240), { Material = Enum.Material.Fabric })
		prop(m, r, 3.08, 4.2, 5.6, Vector3.new(0.05, 1, 1), Color3.fromRGB(90, 160, 230))
		prop(m, r, 3.08, 3.6, 6.5, Vector3.new(0.05, 0.9, 0.9), Color3.fromRGB(240, 120, 90))
		useSpot(m, r, 5, 6, Config.LivingItemById.canvas, 3, 6)
	end
	-- floor lamp in the corner
	cyl(m, r, 2, 3, 7.2, 6, 0.25, DARK)
	local shade = cyl(m, r, 2, 6.2, 7.2, 1.2, 1.4, Color3.fromRGB(250, 235, 200), { Material = Enum.Material.Fabric })
	light(shade, 12)
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

-- Your own room (3 x 6 tiles, v from -ROOM_V / 2 to +ROOM_V / 2). The three boards hang
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
-- House render: everything comes from the tile plan (shared/House.lua)
---------------------------------------------------------------------------
local W, D, T = House.W, House.D, House.TILE
local tid = House.id
local UP = Vector3.new(0, 1, 0)
-- which side of a wall line the face's owner tile is on (local Z of the line frame), per direction
local FACE_SIGN = { -1, 1, 1, -1 }

local function tileXZ(i)
	return (i - 1) % W, (i - 1) // W
end

-- plot-local studs of tile corners
local function sx(x)
	return House.X0 + x * T
end
local function sz(z)
	return House.Z0 + z * T
end

local function dirIndex(dx, dz)
	for k, d in ipairs(House.DIRS) do
		if d[1] == dx and d[2] == dz then
			return k
		end
	end
	return 1
end

-- tile edge in direction k -> wall line number and position along it
local function edgeOf(x, z, k)
	if k == 1 then
		return z + 1, x
	elseif k == 3 then
		return z, x
	elseif k == 2 then
		return x + 1, z
	end
	return x, z
end

-- frame of a wall line: local X runs along it, local Z crosses it
local function lineFrame(k, line)
	if k == 1 or k == 3 then
		return CFrame.new(0, 0, sz(line))
	end
	return CFrame.new(sx(line), 0, 0) * ALONG_Z
end

local function alongStud(k, pos)
	return (k == 1 or k == 3) and sx(pos) or sz(pos)
end

-- split a set of tile ids into rectangles { x, z, w, d }
local function rects(set)
	local used, out = {}, {}
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			local i = tid(x, z)
			if set[i] and not used[i] then
				local w = 1
				while x + w < W and set[tid(x + w, z)] and not used[tid(x + w, z)] do
					w += 1
				end
				local d = 1
				while z + d < D do
					local full = true
					for k = 0, w - 1 do
						local j = tid(x + k, z + d)
						if not set[j] or used[j] then
							full = false
							break
						end
					end
					if not full then
						break
					end
					d += 1
				end
				for a = 0, w - 1 do
					for b = 0, d - 1 do
						used[tid(x + a, z + b)] = true
					end
				end
				table.insert(out, { x = x, z = z, w = w, d = d })
			end
		end
	end
	return out
end

-- where students and the client need to know about a room (world space).
-- rcf: room frame (u into the room, v along the furnished wall), dcf: the
-- doorway, X pointing into the room.
local function roomInfo(plot, key, r, door, hangout)
	local fr = House.roomFrame(r, door, key)
	local y = floorY(r.floor)
	local rcf = plot.cf * CFrame.fromMatrix(Vector3.new(fr.x, y, fr.z), Vector3.new(fr.ux, 0, fr.uz), UP)
	local dx, dz = House.doorPoint(door)
	local dcf = plot.cf * CFrame.fromMatrix(Vector3.new(dx, y, dz), Vector3.new(-door.dx, 0, -door.dz), UP)
	return {
		key = key,
		floor = r.floor,
		rect = r,
		U = fr.U,
		V = fr.V,
		rcf = rcf,
		dcf = dcf,
		u = rcf.XVector,
		backDir = dirIndex(fr.ux, fr.uz),
		hangout = hangout,
	}
end

local function tagRoom(model, plot, info)
	model:SetAttribute("PlotIndex", plot.index)
	model:SetAttribute("Floor", info.floor)
	model:SetAttribute("Key", info.key)
	if info.hangout then
		model:SetAttribute("Hangout", true)
		CollectionService:AddTag(model, "HangoutRoom")
	end
end

local CURTAINS = {
	Color3.fromRGB(200, 80, 90), Color3.fromRGB(90, 130, 200), Color3.fromRGB(230, 190, 90), Color3.fromRGB(110, 170, 120), Color3.fromRGB(170, 120, 200), Color3.fromRGB(240, 240, 235),
}

local function signature(plot, data)
	local parts = { plot.owner.DisplayName, tostring(House.floorCount(data)) }
	for _, fp in ipairs(data.plan.floors) do
		table.insert(parts, fp.hall .. (fp.support and "S" or ""))
	end
	local keys = {}
	for f, s in pairs(data.plan.stairs) do
		table.insert(keys, string.format("st%d@%d,%d,%d", f, s.x, s.z, s.dir))
	end
	for _, p in ipairs(House.placements(data)) do
		local door = data.layout[p.key].door
		table.insert(keys, string.format("%s@%d,%d,%d,%d,%d", p.key, p.floor, p.x, p.z, p.w, p.d) .. (door and string.format("/%d,%d,%d,%d", door.x, door.z, door.dx, door.dz) or ""))
	end
	for i, room in ipairs(data.rooms) do
		table.insert(keys, "tier" .. i .. "=" .. room.tier)
	end
	for area, st in pairs(data.styles) do
		table.insert(keys, area .. "=" .. tostring(st.wall) .. "/" .. tostring(st.floor) .. "/" .. tostring(st.roof))
	end
	for fid, shown in pairs(data.furniture) do
		table.insert(keys, "furn:" .. fid .. "=" .. tostring(shown))
	end
	for id in pairs(data.livingItems or {}) do
		table.insert(keys, "living:" .. id)
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

-- the plan as JSON on the house folder, so the client can walk students
-- along the hallways (see client/Animator)
local function publishPlan(plot, data)
	local rooms = {}
	for key, r in pairs(data.layout) do
		rooms[key] = { f = r.floor, x = r.x, z = r.z, w = r.w, d = r.d, door = r.door }
	end
	local floors = {}
	for f, fp in ipairs(data.plan.floors) do
		floors[f] = fp.hall
	end
	local stairs = {}
	for f = 1, House.floorCount(data) - 1 do
		stairs[f] = data.plan.stairs[f]
	end
	plot.house:SetAttribute("Plan", HttpService:JSONEncode({ floors = floors, stairs = stairs, rooms = rooms }))
	plot.house:SetAttribute("PlotIndex", plot.index)
	CollectionService:AddTag(plot.house, "HousePlan")
end

-- room contents (ROOM_U / ROOM_V are set to the room's size first)
local function furnish(m, info, data)
	local rcf = info.rcf
	local kind, index, fid = House.describe(info.key)
	ROOM_U, ROOM_V = info.U, info.V
	if kind == "me" then
		m:SetAttribute("IsMyRoom", true)
		myRoomBasics(m, rcf)
		for id, shown in pairs(data.furniture) do
			if shown and FurnitureProps[id] then
				FurnitureProps[id](m, rcf)
			end
		end
	elseif kind == "common" then
		commonProps(m, rcf)
	elseif kind == "facility" and FacilityProps[fid] then
		FacilityProps[fid](m, rcf, data)
	elseif kind == "dorm" then
		local room = data.rooms[index]
		if room and room.tier >= 2 then
			cyl(m, rcf, ROOM_U * 0.4, 0.28, 0, 0.12, 6, Config.Looks.Artist.color, { Material = Enum.Material.Fabric })
		end
		if room and room.tier >= 3 then
			-- a desk under the side wall and a wall picture
			prop(m, rcf, 4.5, 2.6, -ROOM_V / 2 + 1.4, Vector3.new(3.2, 0.25, 1.6), BED_WOOD, { Material = Enum.Material.Wood })
			prop(m, rcf, 4.5, 1.25, -ROOM_V / 2 + 1.4, Vector3.new(3, 2.5, 1.4), BED_WOOD:Lerp(Color3.new(0, 0, 0), 0.2), { Material = Enum.Material.Wood })
			prop(m, rcf, 4.5, 3.1, -ROOM_V / 2 + 1.2, Vector3.new(1.2, 0.8, 0.08), DARK)
			prop(m, rcf, ROOM_U / 2, 6.5, ROOM_V / 2 - 0.45, Vector3.new(3, 2.2, 0.1), Color3.fromRGB(120, 180, 230), { CanCollide = false })
			prop(m, rcf, ROOM_U / 2, 6.5, ROOM_V / 2 - 0.42, Vector3.new(3.4, 2.6, 0.06), Color3.fromRGB(200, 160, 60), { CanCollide = false, Material = Enum.Material.Foil })
		end
		if room and room.tier >= 4 then
			for _, v in ipairs({ -ROOM_V / 2 + 0.5, ROOM_V / 2 - 0.5 }) do
				prop(m, rcf, ROOM_U / 2, WALL_H - 0.3, v, Vector3.new(ROOM_U - 1, 0.4, 0.3), Color3.fromRGB(255, 210, 60), { Material = Enum.Material.Neon, CanCollide = false })
			end
		end
	end
	-- ceiling light
	local fixture = part({ Name = "CeilingLight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.2, 2.2), CFrame = rcf * CFrame.new(ROOM_U / 2, WALL_H - 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(215, 205, 185), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	local l = Instance.new("PointLight")
	l.Range = math.max(20, math.max(ROOM_U, ROOM_V) * 0.75)
	l.Brightness = kind == "dorm" and 0.5 or 0.8
	l.Color = Color3.fromRGB(255, 225, 180)
	l.Shadows = false
	l.Parent = fixture
end

-- door frame on both faces, and the door standing open flat against the hallway wall
local function doorway(m, info, owner)
	local dcf = info.dcf
	local function strip(name, size, u, h, v, color)
		part({ Name = name, Size = size, CFrame = dcf * CFrame.new(u, h, v), Color = color, CanCollide = false, Parent = m })
	end
	for _, sgn in ipairs({ -1, 1 }) do
		strip("Jamb", Vector3.new(1.1, DOOR_H + 0.3, 0.3), 0, (DOOR_H + 0.3) / 2, sgn * (DOOR_W / 2 + 0.15), TRIM)
	end
	strip("DoorHeader", Vector3.new(1.1, 0.35, DOOR_W + 0.6), 0, DOOR_H + 0.17, 0, TRIM)
	-- swing the leaf toward whichever side has hallway wall to rest on
	local door = info.rect.door
	local hx, hz = door.x + door.dx, door.z + door.dz
	local side = 1
	local nx, nz = hx + info.vPlot[1], hz + info.vPlot[2]
	if not (House.inLot(nx, nz) and owner[tid(nx, nz)] == "hall") then
		side = -1
	end
	local leafW = DOOR_W - 0.2
	local vc = side * (DOOR_W / 2 + 0.35 + leafW / 2)
	strip("Door", Vector3.new(0.18, DOOR_H - 0.15, leafW), -0.52, (DOOR_H - 0.15) / 2, vc, Color3.fromRGB(150, 100, 65))
	for _, h in ipairs({ 2, 5.2 }) do
		strip("DoorPanel", Vector3.new(0.24, 2.4, leafW - 1.4), -0.54, h, vc, Color3.fromRGB(135, 88, 55))
	end
	part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3), CFrame = dcf * CFrame.new(-0.7, 3.6, vc + side * (leafW / 2 - 0.4)), Color = Color3.fromRGB(230, 200, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = m })
end

-- Walls, floors, stairs, roofs, props: only rebuilt when the house itself changes.
local function renderStructure(plot, data)
	local root = plot.house
	root:ClearAllChildren()
	local floors = House.floorCount(data)
	local levels = {}
	for f = 0, floors do
		levels[f] = levelFolder(root, f)
	end
	local ext = House.style(data, "exterior", "wall")
	local roofStyle = House.style(data, "exterior", "roof")
	local hallWall = House.style(data, "hall", "wall")
	local hallFloor = House.style(data, "hall", "floor")
	local concrete = { Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Concrete }
	local L = function(x, y, z)
		return PlotService.LocalCF(plot, x, y, z)
	end
	local function slabRect(parent, r, y0, y1, name, style)
		local x0, x1, z0, z1 = sx(r.x), sx(r.x + r.w), sz(r.z), sz(r.z + r.d)
		local props = { Name = name or "Slab", Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame = L((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Parent = parent }
		if style then
			props.Style = style
		else
			props.Color, props.Material = concrete.Color, concrete.Material
		end
		return part(props)
	end
	plot.rooms = {}
	publishPlan(plot, data)

	local owners, stairSets, wellSets, prints = {}, {}, {}, {}
	for f = 0, floors - 1 do
		owners[f], stairSets[f], wellSets[f] = House.owners(data, f)
		prints[f] = House.footprint(data, f)
	end
	prints[floors] = {}
	prints[-1] = {}
	-- the whole top floor is one rectangle: it gets a gable roof
	local topPrint, topCount = prints[floors - 1], 0
	local bx0, bz0, bx1, bz1 = math.huge, math.huge, -math.huge, -math.huge
	for i in pairs(topPrint) do
		local x, z = tileXZ(i)
		topCount += 1
		bx0, bz0, bx1, bz1 = math.min(bx0, x), math.min(bz0, z), math.max(bx1, x), math.max(bz1, z)
	end
	local gable = topCount > 0 and topCount == (bx1 - bx0 + 1) * (bz1 - bz0 + 1)
	local ent = House.entrance(data)
	local sconceCount = 0

	for f = 0, floors - 1 do
		local lv = levels[f]
		local y = floorY(f)
		local owner, stair, well = owners[f], stairSets[f], wellSets[f]
		local h0 = f == 0 and GROUND_Y or y - 1
		local h1 = y + WALL_H

		-- slabs and floors
		local solid, hallTiles, runnerTiles = {}, {}, {}
		for i, o in pairs(owner) do
			if not well[i] then
				solid[i] = true
				if o == "hall" then
					hallTiles[i] = true
					if not stair[i] then
						runnerTiles[i] = true
					end
				end
			end
		end
		for _, r in ipairs(rects(solid)) do
			slabRect(lv, r, f == 0 and GROUND_Y or y - 1, y)
		end
		for _, r in ipairs(rects(hallTiles)) do
			slabRect(lv, r, y, y + 0.2, "HallFloor", hallFloor)
		end
		for _, r in ipairs(rects(runnerTiles)) do
			local long = math.max(r.w, r.d)
			if long >= 3 then
				local cx, cz = (sx(r.x) + sx(r.x + r.w)) / 2, (sz(r.z) + sz(r.z + r.d)) / 2
				local wide = math.min(4.4, math.min(r.w, r.d) * T - 1.6)
				local len = long * T - 4
				local size = r.w >= r.d and Vector3.new(len, 0.06, wide) or Vector3.new(wide, 0.06, len)
				local inner = r.w >= r.d and Vector3.new(len - 0.8, 0.08, wide - 0.8) or Vector3.new(wide - 0.8, 0.08, len - 0.8)
				part({ Name = "Runner", Size = size, CFrame = L(cx, y + 0.23, cz), Color = Color3.fromRGB(200, 170, 90), Material = Enum.Material.Fabric, CanCollide = false, Parent = lv })
				part({ Name = "Runner", Size = inner, CFrame = L(cx, y + 0.24, cz), Color = Color3.fromRGB(150, 40, 50), Material = Enum.Material.Fabric, CanCollide = false, Parent = lv })
			end
		end

		-- rooms on this floor
		local doorAt = {}
		local infos = {}
		for key, r in pairs(data.layout) do
			if r.floor == f then
				local door = House.door(data, key, owner, stair, well)
				if door then
					r.door = { x = door.x, z = door.z, dx = door.dx, dz = door.dz }
					local k = dirIndex(door.dx, door.dz)
					local line, pos = edgeOf(door.x, door.z, k)
					doorAt[k .. ":" .. line .. ":" .. pos] = true
					local back = (k + 1) % 4 + 1
					line, pos = edgeOf(door.x + door.dx, door.z + door.dz, back)
					doorAt[back .. ":" .. line .. ":" .. pos] = true
					local kind = House.describe(key)
					local info = roomInfo(plot, key, r, door, kind == "common" or kind == "facility")
					-- +v of the doorway in plot tiles (for the door leaf)
					info.vPlot = { door.dz, -door.dx }
					infos[key] = info
					plot.rooms[key] = info
				end
			end
		end

		-- walls: one run per straight stretch between two different owners
		local byLine = {}
		for i, own in pairs(owner) do
			local x, z = tileXZ(i)
			for k, d in ipairs(House.DIRS) do
				local nx, nz = x + d[1], z + d[2]
				local nb = House.inLot(nx, nz) and owner[tid(nx, nz)] or nil
				if nb ~= own then
					local line, pos = edgeOf(x, z, k)
					byLine[k] = byLine[k] or {}
					byLine[k][line] = byLine[k][line] or {}
					byLine[k][line][pos] = { own = own, nb = nb, x = x, z = z, nx = nx, nz = nz }
				end
			end
		end
		local runs = {}
		for k = 1, 4 do
			for line, faces in pairs(byLine[k] or {}) do
				local cur = nil
				for pos = 0, math.max(W, D) do
					local fc = faces[pos]
					if fc and cur and cur.own == fc.own and cur.nb == fc.nb and cur.b == pos then
						cur.b = pos + 1
						table.insert(cur.tiles, fc)
					elseif fc then
						cur = { k = k, line = line, a = pos, b = pos + 1, own = fc.own, nb = fc.nb, tiles = { fc } }
						table.insert(runs, cur)
					else
						cur = nil
					end
				end
			end
		end

		local exProps = { Name = "Outside", Style = ext }
		for _, run in ipairs(runs) do
			local k, s = run.k, FACE_SIGN[run.k]
			local F = plot.cf * lineFrame(k, run.line)
			local A0, A1 = alongStud(k, run.a), alongStud(k, run.b)
			local isRoom = run.own ~= "hall"
			local info = isRoom and infos[run.own]
			local doors = {}
			for pos = run.a, run.b - 1 do
				if doorAt[k .. ":" .. run.line .. ":" .. pos] then
					table.insert(doors, { c = alongStud(k, pos) + T / 2, w = DOOR_W, b = y, t = y + DOOR_H })
				end
			end
			local entrance = nil
			if f == 0 and ent and k == 3 and run.line == ent.z and run.own == "hall" and run.nb == nil and run.a <= ent.x0 and run.b > ent.x1 then
				entrance = { c = (sx(ent.x0) + sx(ent.x1 + 1)) / 2, w = 6, b = y, t = y + DOOR_H + 0.5 }
			end
			local windows = {}
			if run.nb == nil then
				local kind = isRoom and House.describe(run.own)
				local blank = info and kind ~= "dorm" and info.backDir == k -- props and boards hang on the back wall
				if not blank then
					local n = math.max(1, (run.b - run.a) // 2)
					local seg = (A1 - A0) / n
					for j = 1, n do
						local c = A0 + (j - 0.5) * seg
						if not (entrance and math.abs(c - entrance.c) < 6.5) then
							table.insert(windows, { c = c, w = run.b - run.a == 1 and 3 or 4, b = y + 3, t = y + 8 })
						end
					end
				end
			end

			-- inside face
			local holes = {}
			for _, h in ipairs(doors) do
				table.insert(holes, table.clone(h))
			end
			for _, h in ipairs(windows) do
				table.insert(holes, table.clone(h))
			end
			if entrance then
				table.insert(holes, table.clone(entrance))
			end
			local faceStyle = isRoom and House.style(data, run.own, "wall") or hallWall
			wall(lv, F * CFrame.new(0, 0, s * 0.1), A0, A1, y, h1, 0.2, { Name = isRoom and "Wall" or "HallWall", Style = faceStyle }, holes)

			-- outside wall, foundation, floor bands and the parapet of flat roofs
			if run.nb == nil then
				local outHoles = {}
				for _, h in ipairs(windows) do
					local o = table.clone(h)
					o.glass, o.out = true, -s
					table.insert(outHoles, o)
				end
				if entrance then
					local o = table.clone(entrance)
					o.b = h0
					table.insert(outHoles, o)
				end
				wall(lv, F * CFrame.new(0, 0, -s * 0.3), A0, A1, h0, h1, 0.6, exProps, outHoles)
				local function strip(name, a0, a1, hc, tall, thick, out, props)
					if a1 - a0 < 0.05 then
						return
					end
					local p = table.clone(props)
					p.Name, p.Size, p.CFrame, p.CanCollide, p.Parent = name, Vector3.new(a1 - a0, tall, thick), F * CFrame.new((a0 + a1) / 2, hc, -s * out), false, lv
					part(p)
				end
				if f == 0 then
					local stone = { Color = Color3.fromRGB(150, 145, 140), Material = Enum.Material.Cobblestone }
					if entrance then
						strip("Foundation", A0, entrance.c - entrance.w / 2, GROUND_Y + 0.6, 1.2, 0.5, 0.85, stone)
						strip("Foundation", entrance.c + entrance.w / 2, A1, GROUND_Y + 0.6, 1.2, 0.5, 0.85, stone)
					else
						strip("Foundation", A0, A1, GROUND_Y + 0.6, 1.2, 0.5, 0.85, stone)
					end
				else
					strip("Band", A0, A1, y - 0.5, 0.6, 0.3, 0.75, { Color = TRIM })
				end
				local roofHere = f < floors - 1 or not gable
				for idx, fc in ipairs(run.tiles) do
					local i = tid(fc.x, fc.z)
					local nbAbove = House.inLot(fc.nx, fc.nz) and prints[f + 1][tid(fc.nx, fc.nz)]
					if roofHere and not prints[f + 1][i] and not nbAbove then
						local a = alongStud(k, run.a + idx - 1)
						strip("Parapet", a, a + T, h1 + 1, 2, 0.6, 0.3, { Color = TRIM })
					end
				end
			end

			-- trim inside rooms: baseboards around the doors, crown molding, curtains
			if isRoom then
				local base = faceStyle.color:Lerp(Color3.fromRGB(60, 40, 30), 0.55)
				local function strip(name, a0, a1, hc, tall, inset, color)
					if a1 - a0 < 0.05 then
						return
					end
					part({ Name = name, Size = Vector3.new(a1 - a0, tall, 0.14), CFrame = F * CFrame.new((a0 + a1) / 2, hc, s * inset), Color = color, CanCollide = false, Parent = lv })
				end
				local x = A0
				table.sort(doors, function(p, q)
					return p.c < q.c
				end)
				for _, h in ipairs(doors) do
					strip("Baseboard", x, h.c - h.w / 2 - 0.3, y + 0.3, 0.6, 0.27, base)
					x = h.c + h.w / 2 + 0.3
				end
				strip("Baseboard", x, A1, y + 0.3, 0.6, 0.27, base)
				strip("Crown", A0, A1, y + WALL_H - 0.2, 0.4, 0.27, TRIM)
				local curtain = CURTAINS[(#run.own * 7 + run.line * 3 + f) % #CURTAINS + 1]
				for _, wnd in ipairs(windows) do
					local c, ww = wnd.c, wnd.w
					part({ Name = "Sill", Size = Vector3.new(ww + 0.8, 0.25, 0.6), CFrame = F * CFrame.new(c, y + 2.9, s * 0.5), Color = TRIM, CanCollide = false, Parent = lv })
					part({ Name = "WindowTop", Size = Vector3.new(ww + 0.6, 0.3, 0.25), CFrame = F * CFrame.new(c, y + 8.15, s * 0.32), Color = TRIM, CanCollide = false, Parent = lv })
					part({ Name = "CurtainRod", Size = Vector3.new(ww + 3, 0.12, 0.12), CFrame = F * CFrame.new(c, y + 8.7, s * 0.55), Color = Color3.fromRGB(90, 70, 50), CanCollide = false, Parent = lv })
					for _, sgn in ipairs({ -1, 1 }) do
						local cp = part({ Name = "Curtain", Size = Vector3.new(1.3, 6.6, 0.12), CFrame = F * CFrame.new(c + sgn * (ww / 2 + 0.6), y + 5.35, s * 0.62), Color = curtain, Material = Enum.Material.Fabric, CanCollide = false, Parent = lv })
						cp:SetAttribute("Curtain", true)
						part({ Name = "Tie", Size = Vector3.new(1.4, 0.25, 0.2), CFrame = F * CFrame.new(c + sgn * (ww / 2 + 0.6), y + 4, s * 0.64), Color = curtain:Lerp(Color3.new(1, 1, 1), 0.4), CanCollide = false, Parent = lv })
					end
				end
			elseif run.b - run.a >= 2 then
				-- hallway sconces every two tiles, clear of the doors
				for pos = run.a + 1, run.b - 1, 2 do
					local c = alongStud(k, pos)
					local clear = true
					for _, h in ipairs(doors) do
						if math.abs(h.c - c) < h.w / 2 + 1 then
							clear = false
						end
					end
					if entrance and math.abs(entrance.c - c) < 4 then
						clear = false
					end
					if clear then
						sconceCount += 1
						part({ Name = "SconcePlate", Size = Vector3.new(0.6, 1, 0.15), CFrame = F * CFrame.new(c, y + 7, s * 0.28), Color = Color3.fromRGB(200, 170, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = lv })
						local bulb = part({ Name = "Sconce", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = F * CFrame.new(c, y + 7.3, s * 0.6), Color = Color3.fromRGB(255, 235, 190), Material = Enum.Material.Neon, CanCollide = false, Parent = lv })
						if sconceCount % 2 == 0 then
							local l = Instance.new("PointLight")
							l.Range = 16
							l.Brightness = 0.44
							l.Color = Color3.fromRGB(255, 220, 170)
							l.Shadows = false
							l.Parent = bulb
						end
					end
				end
			end
		end

		-- outside corners get a post to close the gap between wall runs
		local fp = prints[f]
		for vx = 0, W do
			for vz = 0, D do
				local a = House.inLot(vx - 1, vz - 1) and fp[tid(vx - 1, vz - 1)] or false
				local b = House.inLot(vx, vz - 1) and fp[tid(vx, vz - 1)] or false
				local c = House.inLot(vx - 1, vz) and fp[tid(vx - 1, vz)] or false
				local d = House.inLot(vx, vz) and fp[tid(vx, vz)] or false
				local n = (a and 1 or 0) + (b and 1 or 0) + (c and 1 or 0) + (d and 1 or 0)
				if n == 1 or (n == 2 and a == d) or n == 3 then
					part({ Name = "Corner", Size = Vector3.new(1.3, h1 - h0, 1.3), CFrame = L(sx(vx), (h0 + h1) / 2, sz(vz)), Color = TRIM, Parent = lv })
				end
			end
		end

		-- columns under the parts of this floor that hang out past the floor below
		if f > 0 then
			local below = prints[f - 1]
			for vx = 0, W do
				for vz = 0, D do
					local around = { { vx - 1, vz - 1 }, { vx, vz - 1 }, { vx - 1, vz }, { vx, vz } }
					local mine, under = 0, false
					for _, t in ipairs(around) do
						if House.inLot(t[1], t[2]) then
							local i = tid(t[1], t[2])
							if fp[i] then
								mine += 1
							end
							if below[i] then
								under = true
							end
						end
					end
					if mine > 0 and mine < 4 and not under and ((vx + vz) % 2 == 0 or mine == 1) then
						-- stand on the highest roof under this corner, or the ground
						local base = GROUND_Y
						for g = f - 2, 0, -1 do
							local hit = false
							for _, t in ipairs(around) do
								if House.inLot(t[1], t[2]) and prints[g][tid(t[1], t[2])] then
									hit = true
								end
							end
							if hit then
								base = floorY(g + 1) + 0.2
								break
							end
						end
						local top = y - 1
						part({ Name = "Column", Size = Vector3.new(1.2, top - base, 1.2), CFrame = L(sx(vx), (base + top) / 2, sz(vz)), Color = TRIM, Material = Enum.Material.Marble, Parent = lv })
						part({ Name = "ColumnFoot", Size = Vector3.new(1.8, 0.5, 1.8), CFrame = L(sx(vx), base + 0.25, sz(vz)), Color = TRIM:Lerp(Color3.new(0, 0, 0), 0.15), Parent = lv })
					end
				end
			end
		end

		-- stairs up: an invisible ramp you walk on, with open steps drawn over it
		local glass = { Name = "Rail", Color = Color3.fromRGB(190, 230, 255), Material = Enum.Material.Glass, Transparency = 0.5 }
		local up = House.stairs(data, f)
		if up and f < floors - 1 then
			local d = House.DIRS[up.dir] or House.DIRS[1]
			local run, rise = House.StairLen * T, FLOOR_H
			local mid = up.tiles[2]
			local cx, cz = House.tileCenter(mid[1], mid[2])
			local side = Vector3.new(d[2], 0, -d[1])
			local base = CFrame.fromMatrix(Vector3.new(cx, 0, cz), side, UP) -- local Z runs up the stairs
			local angle = math.atan2(rise, run)
			part({
				Name = "Ramp",
				Size = Vector3.new(T - 0.4, 0.5, math.sqrt(run * run + rise * rise) + 0.6),
				CFrame = plot.cf * base * CFrame.new(0, y + rise / 2, 0) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, -0.25, 0),
				Transparency = 1,
				Parent = lv,
			})
			local steps = 12
			for i = 1, steps do
				local top = y + (i - 0.5) * rise / steps
				part({ Name = "Step", Size = Vector3.new(T - 0.4, 0.5, run / steps), CFrame = plot.cf * base * CFrame.new(0, top - 0.25, -run / 2 + (i - 0.5) * run / steps), Color = WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = lv })
			end
			-- glass rails on the open sides, following the slope
			for idx, t in ipairs(up.tiles) do
				for _, sgn in ipairs({ -1, 1 }) do
					local nx, nz = t[1] + sgn * side.X, t[2] + sgn * side.Z
					local n = House.inLot(nx, nz) and tid(nx, nz)
					if n and owner[n] == "hall" and not stair[n] then
						local r = table.clone(glass)
						r.Size = Vector3.new(0.3, 3, T)
						r.CFrame = plot.cf * base * CFrame.new(sgn * T / 2, y + rise * (idx - 0.5) / House.StairLen + 1.5, (idx - 2) * T)
						r.Parent = lv
						part(r)
					end
				end
			end
			-- railings around the stairwell upstairs, open at the landing
			local g = f + 1
			local yg = floorY(g)
			local upper = owners[g]
			local wellSet = {}
			for _, t in ipairs(up.tiles) do
				wellSet[tid(t[1], t[2])] = true
			end
			for idx, t in ipairs(up.tiles) do
				for k, dd in ipairs(House.DIRS) do
					local nx, nz = t[1] + dd[1], t[2] + dd[2]
					local n = House.inLot(nx, nz) and tid(nx, nz)
					local landing = idx == House.StairLen and dd[1] == d[1] and dd[2] == d[2]
					if n and not wellSet[n] and upper[n] == "hall" and not landing then
						local line, pos = edgeOf(t[1], t[2], k)
						local r = table.clone(glass)
						r.Size = Vector3.new(T, 3, 0.3)
						r.CFrame = plot.cf * lineFrame(k, line) * CFrame.new(alongStud(k, pos) + T / 2, yg + 1.5, 0)
						r.Parent = levels[g]
						part(r)
					end
				end
			end
		end

		-- rooms: floor, contents, doorway
		for key, info in pairs(infos) do
			local r = info.rect
			local m = Instance.new("Model")
			m.Name = key
			m.Parent = lv
			slabRect(m, { x = r.x, z = r.z, w = r.w, d = r.d }, y, y + 0.2, "Floor", House.style(data, key, "floor"))
			tagRoom(m, plot, info)
			CollectionService:AddTag(m, "HouseRoom")
			furnish(m, info, data)
			for _, sp in ipairs(m:GetDescendants()) do
				if sp:GetAttribute("UseTags") then
					sp:SetAttribute("PlotIndex", plot.index)
					sp:SetAttribute("Floor", info.floor)
					sp:SetAttribute("Key", key)
					CollectionService:AddTag(sp, "UseSpot")
				end
			end
			doorway(m, info, owner)
		end

		-- flat roofs over whatever the next floor doesn't cover
		local open = {}
		for i in pairs(prints[f]) do
			if not prints[f + 1][i] then
				open[i] = true
			end
		end
		local top = y + WALL_H
		for _, r in ipairs(rects(open)) do
			slabRect(levels[f + 1], r, top, top + 1)
			if f < floors - 1 or not gable then
				slabRect(levels[f + 1], r, top + 1, top + 1.2, "Roof", roofStyle)
			end
		end
	end

	-- gable roof on a rectangular top floor
	local lvTop = levels[floors]
	local top = floorY(floors) - 1
	if gable then
		local x0, x1, z0, z1 = sx(bx0), sx(bx1 + 1), sz(bz0), sz(bz1 + 1)
		local alongZ = (z1 - z0) >= (x1 - x0)
		local across = alongZ and (x1 - x0) or (z1 - z0)
		local ridgeLen = alongZ and (z1 - z0) or (x1 - x0)
		local G = plot.cf * CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2) * (alongZ and CFrame.identity or CFrame.Angles(0, math.pi / 2, 0))
		local ridge = math.clamp(across * 0.18, 4, 9)
		local half = across / 2 + 1.5
		local tilt = math.atan2(ridge, half)
		local len = ridgeLen + 2.4
		for _, sd in ipairs({ -1, 1 }) do
			part({ Name = "Roof", Size = Vector3.new(math.sqrt(half * half + ridge * ridge) + 0.4, 0.8, len), CFrame = G * CFrame.new(sd * half / 2, top + 1 + ridge / 2, 0) * CFrame.Angles(0, 0, -sd * tilt), Style = roofStyle, Parent = lvTop })
			part({ Name = "Fascia", Size = Vector3.new(0.4, 0.8, len + 0.2), CFrame = G * CFrame.new(sd * (half + 0.15), top + 0.85, 0), Color = TRIM, Parent = lvTop })
		end
		-- gable ends, drawn as a stack of shrinking boards
		local bars = 7
		for _, zz in ipairs({ -ridgeLen / 2 - 0.3, ridgeLen / 2 + 0.3 }) do
			for k = 0, bars - 1 do
				local w = 2 * (half - 1) * (1 - (k + 0.5) / bars)
				part({ Name = "Gable", Size = Vector3.new(w, ridge / bars, 0.6), CFrame = G * CFrame.new(0, top + 1 + (k + 0.5) * ridge / bars, zz), Style = ext, Parent = lvTop })
			end
		end
		part({ Name = "Ridge", Size = Vector3.new(1, 0.6, len + 0.2), CFrame = G * CFrame.new(0, top + 1 + ridge + 0.2, 0), Color = roofStyle.color:Lerp(Color3.new(0, 0, 0), 0.25), Material = mat(roofStyle.material), Parent = lvTop })
		-- chimney: from under the slope to above the ridge
		local chimX, chimZ = half * 0.45, ridgeLen * 0.25
		local c0, c1 = top + 1 + ridge * 0.55 - 1, top + 1 + ridge + 2
		part({ Name = "Chimney", Size = Vector3.new(3, c1 - c0, 3), CFrame = G * CFrame.new(chimX, (c0 + c1) / 2, chimZ), Color = Color3.fromRGB(150, 70, 55), Material = Enum.Material.Brick, Parent = lvTop })
		part({ Name = "ChimneyCap", Size = Vector3.new(3.6, 0.5, 3.6), CFrame = G * CFrame.new(chimX, top + 1 + ridge + 2.25, chimZ), Color = Color3.fromRGB(80, 80, 85), Material = Enum.Material.Concrete, Parent = lvTop })
	end
	-- sign over the front of the top floor
	if topCount > 0 then
		local front, xs = math.huge, {}
		for i in pairs(topPrint) do
			local _, z = tileXZ(i)
			front = math.min(front, z)
		end
		for i in pairs(topPrint) do
			local x, z = tileXZ(i)
			if z == front then
				table.insert(xs, x)
			end
		end
		local mn, mx = math.huge, -math.huge
		for _, x in ipairs(xs) do
			mn, mx = math.min(mn, x), math.max(mx, x)
		end
		local width = math.min(22, (mx - mn + 1) * T - 1)
		local roofSign = part({ Name = "RoofSign", Size = Vector3.new(width, 3, 0.4), CFrame = L((sx(mn) + sx(mx + 1)) / 2, top + 3.2, sz(front) - 0.9), Color = Color3.fromRGB(40, 40, 60), Parent = lvTop })
		label(surface(roofSign, Enum.NormalId.Front, Vector2.new(880, 120)), plot.owner.DisplayName .. "'s Boarding House", Color3.fromRGB(255, 220, 90))
	end

	-- front porch: steps, a little roof on posts, two lanterns
	if ent then
		local g = levels[0]
		local ex, ez = (sx(ent.x0) + sx(ent.x1 + 1)) / 2, sz(ent.z)
		local stone = { Color = Color3.fromRGB(150, 145, 140), Material = Enum.Material.Cobblestone }
		local function block(name, size, x, yy, z, props)
			local p = table.clone(props)
			p.Name, p.Size, p.CFrame, p.Parent = name, size, L(ex + x, yy, z), g
			return part(p)
		end
		local trimP = { Color = TRIM }
		block("Step", Vector3.new(9, 0.3, 4), 0, GROUND_Y + 0.15, ez - 2.6, stone)
		block("Step", Vector3.new(8, 0.3, 2), 0, GROUND_Y + 0.45, ez - 1.6, stone)
		block("PorchRoof", Vector3.new(10, 0.5, 4.6), 0, floorY(0) + DOOR_H + 1.2, ez - 2.6, { Color = Color3.fromRGB(90, 60, 45), Material = Enum.Material.WoodPlanks })
		block("PorchTrim", Vector3.new(10.4, 0.3, 0.3), 0, floorY(0) + DOOR_H + 0.85, ez - 4.8, trimP)
		for _, sd in ipairs({ -1, 1 }) do
			block("PorchPost", Vector3.new(0.5, DOOR_H + 1.4, 0.5), sd * 4.5, floorY(0) + (DOOR_H + 1.4) / 2, ez - 4.5, trimP)
			block("DoorJamb", Vector3.new(0.6, DOOR_H + 0.9, 0.9), sd * 3.3, floorY(0) + (DOOR_H + 0.9) / 2 - 0.6, ez - 0.3, trimP)
			local lantern = block("Lantern", Vector3.new(0.6, 0.9, 0.6), sd * 4.3, floorY(0) + 6, ez - 0.9, { Color = Color3.fromRGB(255, 220, 150), Material = Enum.Material.Neon })
			block("LanternCap", Vector3.new(0.8, 0.2, 0.8), sd * 4.3, floorY(0) + 6.55, ez - 0.9, { Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal })
			local l = Instance.new("PointLight")
			l.Range = 14
			l.Brightness = 0.55
			l.Color = Color3.fromRGB(255, 210, 150)
			l.Parent = lantern
		end
		block("DoorHeader", Vector3.new(7.2, 0.6, 0.9), 0, floorY(0) + DOOR_H + 0.3, ez - 0.3, trimP)
		block("Doormat", Vector3.new(4, 0.08, 2.4), 0, GROUND_Y + 0.64, ez - 1.6, { Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Fabric, CanCollide = false })
	end
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
	local n = math.max(2, floors + (showLocked and 1 or 0))
	local colW = 880 / n
	local tile = math.floor(math.min((colW - 16) / House.W, 540 / House.D))
	for f = 0, floors - (showLocked and 0 or 1) do
		local x0 = 10 + f * colW
		if f >= floors then
			box(sg, x0 + 6, 120, colW - 12, 540, Color3.fromRGB(200, 195, 185), string.format("🔒 Floor %d\n$%s", f + 1, SchoolMath.format(Config.FloorCost(f + 1))), Color3.fromRGB(90, 80, 80))
		else
			box(sg, x0, 84, colW, 32, nil, "Floor " .. (f + 1) .. (House.supported(data, f) and " 🏛" or ""))
			local gx = x0 + (colW - tile * House.W) / 2
			local gy = 120
			box(sg, gx, gy, tile * House.W, tile * House.D, Color3.fromRGB(235, 230, 220))
			local function at(x, z, w, d)
				-- front of the house (z = 0) at the bottom
				return gx + (House.W - x - w) * tile, gy + (House.D - z - d) * tile, w * tile, d * tile
			end
			local owner, stair = House.owners(data, f)
			local hall = {}
			for i, o in pairs(owner) do
				if o == "hall" and not stair[i] then
					hall[i] = true
				end
			end
			for _, set in ipairs({ { hall, Color3.fromRGB(215, 200, 170) }, { stair, Color3.fromRGB(160, 120, 80) } }) do
				for _, r in ipairs(rects(set[1])) do
					local px, py, pw, ph = at(r.x, r.z, r.w, r.d)
					box(sg, px, py, pw, ph, set[2])
				end
			end
			for _, p in ipairs(House.placements(data)) do
				if p.floor == f then
					local px, py, pw, ph = at(p.x, p.z, p.w, p.d)
					box(sg, px + 1, py + 1, pw - 2, ph - 2, CELL_COLORS[p.kind], PlotService.CellText(p))
				end
			end
		end
	end
	box(sg, 0, 680, 900, 34, nil, "🚪 front door at the bottom  •  🏛 = supported floor", Color3.fromRGB(110, 100, 100))
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
				table.insert(names, string.format('<font color="#%s">%s %s</font>', Config.Rarities[def.rarity].color:Lerp(Color3.new(0, 0, 0), 0.35):ToHex(), Config.TagEmoji(def), string.match(def.name, "%S+$") or def.name))
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
		part({ Name = "BoardFrame", Size = Vector3.new(0.2, BOARD_H + 0.5, BOARD_W + 0.5), CFrame = rcf * CFrame.new(info.U - 0.5, 6.4, b.v), Color = WOOD, Material = Enum.Material.Wood, Parent = parent })
		local board = part({ Name = "Board", Size = Vector3.new(0.2, BOARD_H, BOARD_W), CFrame = rcf * CFrame.new(info.U - 0.65, 6.4, b.v), Color = Color3.fromRGB(250, 246, 235), Parent = parent })
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
		-- pins in the top corners, clear of the title
		for _, dv in ipairs({ -1, 1 }) do
			part({ Name = "Pin", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = rcf * CFrame.new(info.U - 0.8, 6.4 + BOARD_H / 2 - 0.25, b.v + dv * (BOARD_W / 2 - 0.25)), Color = Color3.fromRGB(220, 40, 40), CanCollide = false, Parent = parent })
		end
	end
end

---------------------------------------------------------------------------
-- Outing photos: little framed pictures of the students who went out,
-- rendered with a ViewportFrame, on the inside of each room's door wall.
---------------------------------------------------------------------------
local function seedOf(uid)
	local seed = 0
	for i = 1, #uid do
		seed += string.byte(uid, i) * i
	end
	return seed
end

local function photoPerson(vp, uid, s, x, turned)
	local def = Config.StudentById[s.id]
	local seed = seedOf(uid)
	local skin = def.skin or SKIN[(seed % #SKIN) + 1]
	local hair = def.hair or HAIR[(seed // 3) % #HAIR + 1]
	local shirt = def.shirt or Config.Looks[def.look].color
	local base = CFrame.new(x, 0, 0) * CFrame.Angles(0, turned and math.pi / 2 or 0, 0)
	local function bit(size, offset, color, shape)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Shape = shape or Enum.PartType.Block
		p.Parent = vp
		return p
	end
	bit(Vector3.new(1.6, 1.8, 0.9), CFrame.new(0, 0.9, 0), shirt)
	bit(Vector3.new(0.5, 1.4, 0.5), CFrame.new(-1.05, 1.1, 0) * CFrame.Angles(0, 0, -0.5), skin)
	bit(Vector3.new(0.5, 1.4, 0.5), CFrame.new(1.05, 1.1, 0) * CFrame.Angles(0, 0, 0.5), skin)
	bit(Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 2.45, 0), skin, Enum.PartType.Ball)
	bit(Vector3.new(1.4, 0.5, 1.4), CFrame.new(0, 2.95, 0.05), hair)
	if def.gender == "F" then
		bit(Vector3.new(1.4, 1.3, 0.3), CFrame.new(0, 2.3, 0.6), hair)
	end
	if not turned then
		for _, ex in ipairs({ -0.22, 0.22 }) do
			bit(Vector3.new(0.12, 0.18, 0.05), CFrame.new(ex, 2.55, -0.64), Color3.fromRGB(25, 20, 20))
		end
		bit(Vector3.new(0.45, 0.08, 0.05), CFrame.new(0, 2.2, -0.64), Color3.fromRGB(120, 40, 40))
	end
	if def.crew then
		bit(Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.5, 1.5, -0.5), Config.Tags.LaRose.color, Enum.PartType.Ball)
	end
end

local function photoFrame(parent, cf, photo, data)
	local activity = Config.ActivityById[photo.a]
	local outcome = Config.Outcomes[photo.o] or Config.Outcomes.fun
	local frame = part({ Name = "Photo", Size = Vector3.new(0.12, 1.3, 1.55), CFrame = cf, Color = Color3.fromRGB(60, 40, 28), Material = Enum.Material.Wood, CanCollide = false, Parent = parent })
	local sg = surface(frame, Enum.NormalId.Right, Vector2.new(310, 260))
	local paper = Instance.new("Frame")
	paper.Size = UDim2.new(1, -16, 1, -16)
	paper.Position = UDim2.fromOffset(8, 8)
	paper.BackgroundColor3 = Color3.fromRGB(250, 248, 240)
	paper.BorderSizePixel = 0
	paper.Parent = sg
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, -16, 0.74, 0)
	vp.Position = UDim2.fromOffset(8, 8)
	vp.BackgroundColor3 = activity and activity.sky or Color3.fromRGB(120, 160, 220)
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(200, 200, 200)
	vp.LightColor = Color3.fromRGB(255, 245, 230)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
	vp.Parent = paper
	local ground = Instance.new("Part")
	ground.Anchored = true
	ground.Size = Vector3.new(30, 0.5, 14)
	ground.CFrame = CFrame.new(0, -0.25, 3)
	ground.Color = activity and activity.ground or Color3.fromRGB(100, 170, 90)
	ground.Parent = vp
	local members = {}
	for _, uid in ipairs(photo.m) do
		if data.students[uid] then
			table.insert(members, uid)
		end
	end
	local gap = 2.3
	for k, uid in ipairs(members) do
		local x = (k - (#members + 1) / 2) * gap
		photoPerson(vp, uid, data.students[uid], x, photo.o == "awkward" and k == #members)
	end
	local cam = Instance.new("Camera")
	local width = math.max(#members, 2) * gap + 1.5
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, -width * 1.25), Vector3.new(0, 1.7, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	CollectionService:AddTag(vp, "PhotoView")
	local names = {}
	for _, uid in ipairs(members) do
		local def = Config.StudentById[data.students[uid].id]
		table.insert(names, string.match(def.name, "%S+$") or def.name)
	end
	local cap = label(paper, string.format("%s %s %s", activity and activity.emoji or "📷", activity and activity.name or "Outing", outcome.emoji), Color3.fromRGB(50, 40, 40), UDim2.new(1, -8, 0.13, 0), UDim2.new(0, 4, 0.76, 0))
	cap.TextStrokeTransparency = 1
	local who = label(paper, table.concat(names, ", "), Color3.fromRGB(110, 100, 100), UDim2.new(1, -8, 0.1, 0), UDim2.new(0, 4, 0.89, 0))
	who.TextStrokeTransparency = 1
	return frame
end

local PHOTO_SLOTS = {} -- up to 8 frames: two rows, two columns each side of the door
for _, y in ipairs({ 6.7, 4.8 }) do
	for _, v in ipairs({ 3.9, -3.9, 5.8, -5.8 }) do
		table.insert(PHOTO_SLOTS, { y = y, v = v })
	end
end

local function renderPhotos(plot, data, folder)
	local keep = {}
	for i, room in ipairs(data.rooms) do
		local info = plot.rooms["r" .. i]
		if info then
			local here = {}
			for _, uid in ipairs(room.occupants) do
				here[uid] = true
			end
			local list = {}
			for k = #data.photos, 1, -1 do
				local ph = data.photos[k]
				for _, uid in ipairs(ph.m) do
					if here[uid] then
						table.insert(list, ph)
						break
					end
				end
				if #list >= Config.PhotoWall then
					break
				end
			end
			local ids = {}
			for _, ph in ipairs(list) do
				table.insert(ids, ph.id)
			end
			local sig = info.key .. "@" .. tostring(info.dcf.Position) .. ":" .. table.concat(ids, ",")
			local name = "r" .. i
			local wall = folder:FindFirstChild(name)
			if wall and wall:GetAttribute("Sig") ~= sig then
				wall:Destroy()
				wall = nil
			end
			if not wall and #list > 0 then
				wall = Instance.new("Model")
				wall.Name = name
				wall:SetAttribute("Sig", sig)
				wall:SetAttribute("Level", info.floor)
				for k, ph in ipairs(list) do
					local slot = PHOTO_SLOTS[k]
					photoFrame(wall, info.dcf * CFrame.new(0.5, slot.y, slot.v), ph, data)
				end
				wall.Parent = folder
			end
			if wall then
				keep[name] = true
			end
		end
	end
	for _, c in ipairs(folder:GetChildren()) do
		if not keep[c.Name] then
			c:Destroy()
		end
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
	local photos = live:FindFirstChild("Photos")
	if not photos then
		photos = Instance.new("Folder")
		photos.Name = "Photos"
		photos.Parent = live
	end
	for _, c in ipairs(live:GetChildren()) do
		if c ~= students and c ~= photos then
			c:Destroy()
		end
	end
	-- students out on an outing aren't home
	local away = {}
	if data.outing then
		for _, uid in ipairs(data.outing.members) do
			away[uid] = true
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
			-- beds in rows from the back wall, colored by who sleeps there
			local beds = Config.Beds(room)
			local U, w = info.U, info.V
			local perRow = math.max(1, math.floor((w - 1) / 4.6))
			local rows = math.max(1, math.min(math.ceil(beds / perRow), math.floor((U - 4) / 10)))
			perRow = math.ceil(beds / rows)
			for b = 1, beds do
				local row = (b - 1) // perRow
				local inRow = math.min(perRow, beds - row * perRow)
				local col = (b - 1) % perRow
				local v = -w / 2 + (w / inRow) * (col + 0.5)
				local occ = room.occupants[b]
				local color = Color3.fromRGB(120, 160, 230)
				if occ and data.students[occ] then
					local occDef = Config.StudentById[data.students[occ].id]
					color = occDef.shirt or Config.Looks[occDef.look].color
				end
				bed(lv, rcf * CFrame.new(U - 4.2 - row * 10, 0.2, v) * BED_TURN, color)
				-- nightstand + lamp between beds against the back wall when there's space
				if row == 0 and col < inRow - 1 and w / inRow >= 5.4 then
					local nv = v + w / inRow / 2
					local ns = rcf * CFrame.new(U - 1.4, 0, nv)
					part({ Name = "Nightstand", Size = Vector3.new(1.4, 1.8, 1.3), CFrame = ns * CFrame.new(0, 1.1, 0), Color = BED_WOOD, Material = Enum.Material.Wood, Parent = lv })
					part({ Name = "Drawer", Size = Vector3.new(0.05, 0.5, 1), CFrame = ns * CFrame.new(-0.72, 1.4, 0), Color = BED_WOOD:Lerp(Color3.new(0, 0, 0), 0.25), CanCollide = false, Parent = lv })
					part({ Name = "LampBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 0.25, 0.25), CFrame = ns * CFrame.new(0, 2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(60, 60, 65), CanCollide = false, Parent = lv })
					part({ Name = "LampShade", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.8, 0.8), CFrame = ns * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(255, 235, 200), Material = Enum.Material.Neon, CanCollide = false, Parent = lv })
				end
			end

			-- door plate + prompt in the hallway
			local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.8, 6), CFrame = info.dcf * CFrame.new(-0.45, DOOR_H + 1.3, 0), Color = Color3.fromRGB(40, 40, 60), Parent = lv })
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
			local spot = part({ Name = "DoorSpot", Size = Vector3.new(1, 1, 1), CFrame = info.dcf * CFrame.new(-1.5, 3, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = lv })
			local pp = prompt(spot, "Manage room", "Room " .. i, 7)
			pp:SetAttribute("OwnerUserId", owner.UserId)
			pp:SetAttribute("RoomIndex", i)
			CollectionService:AddTag(pp, "RoomPrompt")

			for _, uid in ipairs(room.occupants) do
				local s = data.students[uid]
				if s and not away[uid] then
					local st = stats and stats.students[uid]
					local satv = st and st.sat or 50
					local m = students:FindFirstChild(uid)
					local r = info.rect
					local where = string.format("%d,%d,%d,%d,%d/%d,%d", r.floor, r.x, r.z, r.w, r.d, r.door.x, r.door.z)
					if m and (m:GetAttribute("HomeKey") ~= info.key or m:GetAttribute("StudentId") ~= s.id or m:GetAttribute("Origin") ~= plot.cf or m:GetAttribute("HomeRect") ~= where) then
						m:Destroy()
						m = nil
					end
					if not m then
						local rng = Random.new()
						local start = rcf * CFrame.new(rng:NextNumber(2.5, math.max(3, U - 8)), 0.2, rng:NextNumber(-w / 2 + 2, w / 2 - 2))
						m = PlotService.BuildStudentModel(uid, s, start)
						m.Name = uid
						m:SetAttribute("StudentId", s.id)
						m:SetAttribute("Origin", plot.cf)
						m:SetAttribute("HomeRect", where)
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

	renderPhotos(plot, data, photos)

	-- plates for the special rooms
	for key, info in pairs(plot.rooms) do
		local kind, _, fid = House.describe(key)
		if kind ~= "dorm" then
			local text = kind == "me" and ("⭐ " .. owner.DisplayName .. "'s Room") or kind == "common" and "🛋 Common Room" or (Config.FacilityById[fid].emoji .. " " .. Config.FacilityById[fid].name)
			local plate = part({ Name = "Plate", Size = Vector3.new(0.1, 1.4, 6), CFrame = info.dcf * CFrame.new(-0.45, DOOR_H + 1.3, 0), Color = Color3.fromRGB(250, 245, 230), Parent = levels[info.floor] })
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
	local pos = (info.rcf * CFrame.new(math.min(7, info.U - 4), 3, 0)).Position
	return CFrame.lookAt(pos, pos + info.u)
end

return PlotService
