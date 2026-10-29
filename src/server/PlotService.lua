-- Builds the world (plaza + plots) and renders each player's school from data.
-- Everything is procedural, so the place needs no prebuilt models.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SchoolMath = require(ReplicatedStorage.Shared.SchoolMath)

local PlotService = {}
PlotService.Plots = {} -- list of { model, cf, owner }

local ROOM_W, ROOM_D, FLOOR_H = 18, 18, 13
local BALCONY_D = 7
local BUILDING_Z = 6 -- local z where rooms start (front of rooms)
local PLOT_W, PLOT_D = 150, 130

local PLOT_POSITIONS = {
	Vector3.new(-170, 0, -170),
	Vector3.new(0, 0, -170),
	Vector3.new(170, 0, -170),
	Vector3.new(-170, 0, 170),
	Vector3.new(0, 0, 170),
	Vector3.new(170, 0, 170),
}

local TIER_FLOOR = {
	Color3.fromRGB(196, 160, 120),
	Color3.fromRGB(170, 120, 80),
	Color3.fromRGB(230, 225, 215),
	Color3.fromRGB(30, 30, 40),
}
local TIER_WALL = {
	Color3.fromRGB(235, 225, 200),
	Color3.fromRGB(190, 220, 240),
	Color3.fromRGB(245, 215, 230),
	Color3.fromRGB(250, 220, 120),
}

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" then
			p[k] = v
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
		model.Parent = world
		part({
			Name = "Base",
			Size = Vector3.new(PLOT_W, 0.6, PLOT_D),
			CFrame = cf * CFrame.new(0, 0.3, 0),
			Color = Color3.fromRGB(150, 210, 120),
			Material = Enum.Material.Grass,
			Parent = model,
		})
		local school = Instance.new("Folder")
		school.Name = "School"
		school.Parent = model
		local plot = { index = i, model = model, cf = cf, owner = nil, school = school }
		PlotService.Plots[i] = plot
		PlotService.RenderEmpty(plot)
	end
end

function PlotService.LocalCF(plot, x, y, z)
	return plot.cf * CFrame.new(x, y, z) -- +z in our layout = toward the back, -z = front
end

function PlotService.SpawnCFrame(plot)
	return PlotService.LocalCF(plot, 10, 4, -58) * CFrame.Angles(0, math.pi, 0)
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
local function roomOrigin(plot, index)
	local floor = math.floor((index - 1) / Config.RoomsPerFloor)
	local col = (index - 1) % Config.RoomsPerFloor
	local x = -Config.RoomsPerFloor * ROOM_W / 2 + col * ROOM_W + ROOM_W / 2
	local y = floor * FLOOR_H
	return x, y, floor
end

local function buildSign(plot, parent, title, subtitle, likes)
	local post = part({
		Name = "SignPost",
		Size = Vector3.new(2, 16, 2),
		CFrame = PlotService.LocalCF(plot, 0, 8, -56),
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
	plot.school:ClearAllChildren()
	buildSign(plot, plot.school, "🏫 Empty Campus", "Waiting for a new headmaster...")
end

local function bed(parent, cf, color)
	part({ Name = "BedFrame", Size = Vector3.new(4, 1.2, 7), CFrame = cf * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(110, 75, 50), Material = Enum.Material.Wood, Parent = parent })
	part({ Name = "Mattress", Size = Vector3.new(3.6, 0.6, 6.6), CFrame = cf * CFrame.new(0, 1.5, 0), Color = color, Material = Enum.Material.Fabric, Parent = parent })
	part({ Name = "Pillow", Size = Vector3.new(3, 0.5, 1.4), CFrame = cf * CFrame.new(0, 2, 2.4), Color = Color3.new(1, 1, 1), Material = Enum.Material.Fabric, Parent = parent })
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
-- Full school render
---------------------------------------------------------------------------
function PlotService.Render(plot, data, totals)
	local folder = plot.school
	folder:ClearAllChildren()
	local owner = plot.owner
	if not owner then
		PlotService.RenderEmpty(plot)
		return
	end

	local unlocked = #data.rooms
	local maxRooms = Config.RoomsPerFloor * Config.MaxFloors
	local showSale = unlocked < maxRooms
	local slots = showSale and unlocked + 1 or unlocked
	local floors = math.ceil(slots / Config.RoomsPerFloor)
	local fullW = Config.RoomsPerFloor * ROOM_W

	-- floors, balconies, elevator
	for f = 0, floors - 1 do
		local y = f * FLOOR_H
		part({ Name = "Slab", Size = Vector3.new(fullW + 14, 1, ROOM_D + BALCONY_D), CFrame = PlotService.LocalCF(plot, -7, y + 0.5 + 0.6, BUILDING_Z + (ROOM_D - BALCONY_D) / 2), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Concrete, Parent = folder })
		if f > 0 then
			part({ Name = "Railing", Size = Vector3.new(fullW + 14, 3, 0.4), CFrame = PlotService.LocalCF(plot, -7, y + 3.1, BUILDING_Z - BALCONY_D + 0.2), Color = Color3.fromRGB(180, 230, 255), Transparency = 0.55, Material = Enum.Material.Glass, Parent = folder })
		end
		local pad = part({
			Name = "Elevator",
			Size = Vector3.new(8, 0.4, 6),
			CFrame = PlotService.LocalCF(plot, -fullW / 2 - 7, y + 1.3, BUILDING_Z + 4),
			Color = Color3.fromRGB(255, 200, 60),
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		pad:SetAttribute("Floor", f)
		local up = Instance.new("ProximityPrompt")
		up.ActionText = f < floors - 1 and "Go up" or "Back to ground"
		up.ObjectText = "Elevator (floor " .. (f + 1) .. ")"
		up.KeyboardKeyCode = Enum.KeyCode.E
		up.HoldDuration = 0
		up.RequiresLineOfSight = false
		up.Parent = pad
		up.Triggered:Connect(function(who)
			local char = who.Character
			if char then
				local target = f < floors - 1 and f + 1 or 0
				char:PivotTo(PlotService.LocalCF(plot, -fullW / 2 - 7, target * FLOOR_H + 5, BUILDING_Z + 4))
			end
		end)
		if f > 0 then
			local down = Instance.new("ProximityPrompt")
			down.ActionText = "Go down"
			down.ObjectText = "Elevator"
			down.KeyboardKeyCode = Enum.KeyCode.Q
			down.HoldDuration = 0
			down.RequiresLineOfSight = false
			down.UIOffset = Vector2.new(0, 60)
			down.Parent = pad
			down.Triggered:Connect(function(who)
				if who.Character then
					who.Character:PivotTo(PlotService.LocalCF(plot, -fullW / 2 - 7, (f - 1) * FLOOR_H + 5, BUILDING_Z + 4))
				end
			end)
		end
	end
	-- roof
	part({ Name = "Roof", Size = Vector3.new(fullW + 2, 1.5, ROOM_D + 2), CFrame = PlotService.LocalCF(plot, 0, floors * FLOOR_H + 1.3, BUILDING_Z + ROOM_D / 2), Color = Color3.fromRGB(170, 60, 50), Parent = folder })
	local roofSign = part({ Name = "RoofSign", Size = Vector3.new(40, 6, 1), CFrame = PlotService.LocalCF(plot, 0, floors * FLOOR_H + 5, BUILDING_Z + 2), Color = Color3.fromRGB(40, 40, 60), Parent = folder })
	local rsg = Instance.new("SurfaceGui")
	rsg.Face = Enum.NormalId.Back
	rsg.CanvasSize = Vector2.new(800, 120)
	rsg.LightInfluence = 0
	rsg.Parent = roofSign
	label(rsg, owner.DisplayName .. "'s Academy", Color3.fromRGB(255, 220, 90))
	-- face the right way regardless of which side the plot is on
	local rsg2 = rsg:Clone()
	rsg2.Face = Enum.NormalId.Front
	rsg2.Parent = roofSign

	-- rooms
	for i = 1, slots do
		local x, y = roomOrigin(plot, i)
		local room = data.rooms[i]
		local roomFolder = Instance.new("Model")
		roomFolder.Name = "Room" .. i
		roomFolder.Parent = folder
		local zc = BUILDING_Z + ROOM_D / 2

		if room then
			local tier = room.tier
			part({ Name = "Floor", Size = Vector3.new(ROOM_W - 0.4, 0.2, ROOM_D - 0.4), CFrame = PlotService.LocalCF(plot, x, y + 1.2, zc), Color = TIER_FLOOR[tier], Material = tier >= 3 and Enum.Material.Marble or Enum.Material.WoodPlanks, Parent = roomFolder })
			part({ Name = "BackWall", Size = Vector3.new(ROOM_W, FLOOR_H - 1, 0.6), CFrame = PlotService.LocalCF(plot, x, y + 1.1 + (FLOOR_H - 1) / 2, BUILDING_Z + ROOM_D - 0.3), Color = TIER_WALL[tier], Parent = roomFolder })
			for _, side in ipairs({ -1, 1 }) do
				part({ Name = "SideWall", Size = Vector3.new(0.5, FLOOR_H - 1, ROOM_D), CFrame = PlotService.LocalCF(plot, x + side * (ROOM_W / 2 - 0.25), y + 1.1 + (FLOOR_H - 1) / 2, zc), Color = TIER_WALL[tier], Parent = roomFolder })
			end
			-- door frame top beam so it reads as a room
			part({ Name = "Header", Size = Vector3.new(ROOM_W, 2, 0.6), CFrame = PlotService.LocalCF(plot, x, y + FLOOR_H - 0.5, BUILDING_Z + 0.3), Color = TIER_WALL[tier], Parent = roomFolder })
			if tier >= 3 then
				local lamp = part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), CFrame = PlotService.LocalCF(plot, x, y + FLOOR_H - 1.5, zc), Color = Color3.fromRGB(255, 240, 200), Material = Enum.Material.Neon, CanCollide = false, Parent = roomFolder })
				local l = Instance.new("PointLight")
				l.Range = 16
				l.Parent = lamp
			end

			local beds = Config.RoomTiers[tier].beds
			local occupants = room.occupants
			for b = 1, beds do
				local bx = x - ROOM_W / 2 + (ROOM_W / beds) * (b - 0.5)
				local occ = occupants[b]
				local color = Color3.fromRGB(120, 160, 230)
				if occ and data.students[occ] then
					local def = Config.StudentById[data.students[occ].id]
					color = Config.Personalities[def.personality].color
				end
				bed(roomFolder, PlotService.LocalCF(plot, bx, y + 1.2, BUILDING_Z + ROOM_D - 4.5), color)
			end

			local stats = totals and totals.rooms[i]
			for idx, uid in ipairs(occupants) do
				local s = data.students[uid]
				if s then
					local px = x - ROOM_W / 2 + (ROOM_W / (#occupants + 1)) * idx
					local cf = PlotService.LocalCF(plot, px, y + 1.3, zc - 2)
					local m = PlotService.BuildStudentModel(uid, s, cf)
					local center = PlotService.LocalCF(plot, x, y + 1.3, zc - 1.5).Position
					m:SetAttribute("Center", center)
					m:SetAttribute("Range", Vector3.new(ROOM_W / 2 - 3, 0, ROOM_D / 2 - 6))
					m:SetAttribute("Facing", plot.cf.LookVector)
					m:SetAttribute("Sat", stats and stats.students[uid] and stats.students[uid].sat or 50)
					m.Parent = roomFolder
				end
			end

			-- clickable hitbox + floating status
			local hit = part({ Name = "Hitbox", Size = Vector3.new(ROOM_W, FLOOR_H - 1, ROOM_D), CFrame = PlotService.LocalCF(plot, x, y + 1.1 + (FLOOR_H - 1) / 2, zc), Transparency = 1, CanCollide = false, Parent = roomFolder })
			hit:SetAttribute("OwnerUserId", owner.UserId)
			hit:SetAttribute("RoomIndex", i)
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 400
			cd.Parent = hit
			CollectionService:AddTag(hit, "RoomClick")

			local bb = billboard(hit, UDim2.fromScale(10, 1.8), Vector3.new(0, 3, -ROOM_D / 2 - 4), 220)
			local sat = stats and stats.satisfaction or 0
			local txt
			if #occupants == 0 then
				txt = "Room " .. i .. " • empty"
			else
				txt = string.format("%s %d%%  •  $%s/s", SchoolMath.moodEmoji(sat), math.floor(sat), SchoolMath.format(stats and stats.income or 0))
			end
			label(bb, txt, Color3.new(1, 1, 1))
		else
			-- the next room for sale
			local cost = Config.RoomUnlockCost(i)
			local box = part({ Name = "ForSale", Size = Vector3.new(ROOM_W - 0.5, FLOOR_H - 1, ROOM_D - 0.5), CFrame = PlotService.LocalCF(plot, x, y + 1.1 + (FLOOR_H - 1) / 2, zc), Color = Color3.fromRGB(255, 210, 80), Transparency = 0.75, Material = Enum.Material.ForceField, CanCollide = false, Parent = roomFolder })
			box:SetAttribute("OwnerUserId", owner.UserId)
			box:SetAttribute("RoomIndex", i)
			box:SetAttribute("Cost", cost)
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 400
			cd.Parent = box
			CollectionService:AddTag(box, "BuyRoomClick")
			local bb = billboard(box, UDim2.fromScale(14, 4.5), Vector3.zero, 260)
			label(bb, "🔨 New Room", Color3.fromRGB(255, 230, 120), UDim2.fromScale(1, 0.5))
			label(bb, "$" .. SchoolMath.format(cost), Color3.fromRGB(120, 255, 140), UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))
		end
	end

	-- facilities in two rows in front of the school
	for idx, fac in ipairs(Config.Facilities) do
		local row = idx <= 5 and 0 or 1
		local col = row == 0 and idx - 1 or idx - 6
		local perRow = row == 0 and 5 or 4
		local fx = -((perRow - 1) * 26) / 2 + col * 26
		local fz = -14 - row * 24
		local owned = data.facilities[fac.id]
		if owned then
			local bld = part({ Name = fac.id, Size = Vector3.new(18, 9, 14), CFrame = PlotService.LocalCF(plot, fx, 5.1, fz), Color = fac.color, Parent = folder })
			part({ Size = Vector3.new(19, 1, 15), CFrame = PlotService.LocalCF(plot, fx, 10.1, fz), Color = Color3.fromRGB(240, 240, 240), Parent = folder })
			part({ Size = Vector3.new(4, 6, 0.4), CFrame = PlotService.LocalCF(plot, fx, 3.6, fz - 7), Color = Color3.fromRGB(80, 50, 30), Parent = folder })
			local bb = billboard(bld, UDim2.fromScale(14, 2.6), Vector3.new(0, 7.5, 0), 220)
			label(bb, fac.name, Color3.new(1, 1, 1))
		else
			local pad = part({ Name = "FacilityLot", Size = Vector3.new(18, 0.3, 14), CFrame = PlotService.LocalCF(plot, fx, 0.75, fz), Color = Color3.fromRGB(230, 200, 120), Material = Enum.Material.Sand, Parent = folder })
			local hit = part({ Name = "FacilityHit", Size = Vector3.new(18, 6, 14), CFrame = PlotService.LocalCF(plot, fx, 3.6, fz), Transparency = 1, CanCollide = false, Parent = folder })
			hit:SetAttribute("OwnerUserId", owner.UserId)
			hit:SetAttribute("FacilityId", fac.id)
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 400
			cd.Parent = hit
			CollectionService:AddTag(hit, "BuyFacilityClick")
			local bb = billboard(pad, UDim2.fromScale(14, 4), Vector3.new(0, 4, 0), 220)
			label(bb, "🔒 " .. fac.name, Color3.fromRGB(255, 230, 150), UDim2.fromScale(1, 0.5))
			label(bb, "$" .. SchoolMath.format(fac.cost), Color3.fromRGB(120, 255, 140), UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))
		end
	end

	local count = 0
	for _ in pairs(data.students) do
		count += 1
	end
	local post = buildSign(
		plot,
		folder,
		owner.DisplayName .. "'s Academy",
		string.format("$%s/s  •  %d students  •  %s", SchoolMath.format(totals and totals.income or 0), count, SchoolMath.moodEmoji(totals and totals.satisfaction or 0)),
		data.likes
	)
	local like = Instance.new("ProximityPrompt")
	like.Name = "LikePrompt"
	like.ActionText = "❤ Like School"
	like.ObjectText = owner.DisplayName .. "'s Academy"
	like.HoldDuration = 0.3
	like.RequiresLineOfSight = false
	like.MaxActivationDistance = 14
	like:SetAttribute("OwnerUserId", owner.UserId)
	like.Parent = post
	CollectionService:AddTag(like, "LikePrompt")
end

return PlotService
