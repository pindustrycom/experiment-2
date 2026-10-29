-- House layout + storyboard notes. Shared so the server renders exactly what
-- the client panels describe.
--
-- Every floor is a hallway running front to back with rooms on both sides.
-- Slot 1 is your own room, slot 2 the common room, then dorms and facility
-- rooms fill the house in the order you build them (data.order).
local Config = require(script.Parent.Config)

local House = {}

-- geometry shared with the client (must match server/PlotService.lua)
House.FloorHeight = 12
House.Bounds = { x = 25, z0 = -45, z1 = 75, floorY = 1.2 } -- house footprint in plot space, ground floor height

House.MaxSlots = 2 + Config.MaxRooms + #Config.Facilities
House.MaxFloors = math.ceil(House.MaxSlots / Config.SlotsPerFloor)

function House.slotPosition(n)
	local floor = math.floor((n - 1) / Config.SlotsPerFloor)
	local k = (n - 1) % Config.SlotsPerFloor
	return floor, (k % 2 == 0) and 1 or -1, math.floor(k / 2) -- floor, side (+1 right / -1 left), row (0 = front)
end

local function describe(key)
	if key == "me" or key == "common" then
		return key
	end
	local i = string.match(key, "^r(%d+)$")
	if i then
		return "dorm", tonumber(i)
	end
	local id = string.match(key, "^fac:(.+)$")
	if id then
		return "facility", nil, id
	end
	return nil
end
House.describe = describe

-- { key, kind, index, id, slot, floor, side, row }
function House.slots(data)
	local list = {}
	local keys = { "me", "common" }
	for _, key in ipairs(data.order or {}) do
		table.insert(keys, key)
	end
	for n, key in ipairs(keys) do
		local kind, index, id = describe(key)
		local floor, side, row = House.slotPosition(n)
		table.insert(list, { key = key, kind = kind, index = index, id = id, slot = n, floor = floor, side = side, row = row })
	end
	return list
end

function House.floorOf(data, key)
	for _, s in ipairs(House.slots(data)) do
		if s.key == key then
			return s.floor + 1
		end
	end
	return 1
end

function House.floorCount(data)
	return math.ceil((2 + #(data.order or {})) / Config.SlotsPerFloor)
end

-- would building one more room/facility open a new floor?
function House.nextIsNewFloor(data)
	local n = 2 + #(data.order or {}) + 1
	return n > 1 and (n - 1) % Config.SlotsPerFloor == 0
end

function House.areaDefaults(key)
	if key == "exterior" or key == "hall" or key == "me" or key == "common" then
		return Config.DefaultStyles[key]
	end
	local kind = describe(key)
	return Config.DefaultStyles[kind] or Config.DefaultStyles.dorm
end

-- part is "wall", "floor" or "roof"; returns the style definition
function House.style(data, key, part)
	local chosen = data.styles and data.styles[key] and data.styles[key][part]
	local def = Config.StyleById[part][chosen or ""]
	if def then
		return def
	end
	local fallback = House.areaDefaults(key)[part]
	return Config.StyleById[part][fallback] or Config.StyleLists[part][1]
end

-- extra satisfaction a dorm room gets from its walls and floor
function House.roomDecor(data, index)
	local key = "r" .. index
	return (House.style(data, key, "wall").decor or 0) + (House.style(data, key, "floor").decor or 0)
end

-- every area the player can paint, in display order
function House.areas(data)
	local list = {
		{ key = "exterior", name = "🏠 Outside", parts = { "wall", "roof" } },
		{ key = "hall", name = "🚪 Hallways", parts = { "wall", "floor" } },
		{ key = "me", name = "⭐ My Room", parts = { "wall", "floor" } },
		{ key = "common", name = "🛋 Common Room", parts = { "wall", "floor" } },
	}
	for i in ipairs(data.rooms) do
		table.insert(list, { key = "r" .. i, name = "🛏 Room " .. i, parts = { "wall", "floor" } })
	end
	for _, f in ipairs(Config.Facilities) do
		if data.facilities[f.id] then
			table.insert(list, { key = "fac:" .. f.id, name = f.emoji .. " " .. f.name, parts = { "wall", "floor" } })
		end
	end
	return list
end

function House.validArea(data, key)
	for _, a in ipairs(House.areas(data)) do
		if a.key == key then
			return a
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Storyboard notes: everything you can build, pinned to the wall of your room
---------------------------------------------------------------------------
House.NoteColors = {
	room = Color3.fromRGB(255, 235, 120),
	upgrade = Color3.fromRGB(150, 220, 255),
	facility = Color3.fromRGB(255, 180, 210),
}

-- { key, kind, emoji, title, text, cost, newFloor }, cheapest first
function House.notes(data)
	local notes = {}
	local newFloor = House.nextIsNewFloor(data)
	local nextFloor = House.floorCount(data) + 1
	local roomIndex = #data.rooms + 1
	if roomIndex <= Config.MaxRooms then
		table.insert(notes, {
			key = "room",
			kind = "room",
			emoji = newFloor and "🏗" or "🛏",
			title = newFloor and ("Build floor " .. nextFloor) or ("New dorm room"),
			text = newFloor and ("Opens floor " .. nextFloor .. " with Room " .. roomIndex) or ("Room " .. roomIndex .. " • 2 beds"),
			cost = Config.RoomUnlockCost(roomIndex),
			newFloor = newFloor,
		})
	end
	for i, room in ipairs(data.rooms) do
		local nextTier = Config.RoomTiers[room.tier + 1]
		if nextTier then
			table.insert(notes, {
				key = "up:" .. i,
				kind = "upgrade",
				emoji = "⬆",
				title = "Upgrade Room " .. i,
				text = nextTier.name .. " • " .. nextTier.beds .. " beds",
				cost = Config.RoomUpgradeCost(i, room.tier + 1),
			})
		end
	end
	for _, f in ipairs(Config.Facilities) do
		if not data.facilities[f.id] then
			table.insert(notes, {
				key = "fac:" .. f.id,
				kind = "facility",
				emoji = f.emoji,
				title = "Build the " .. f.name,
				text = f.text .. (newFloor and " • opens a new floor" or ""),
				cost = f.cost,
				newFloor = newFloor,
			})
		end
	end
	table.sort(notes, function(a, b)
		if a.cost ~= b.cost then
			return a.cost < b.cost
		end
		return a.key < b.key
	end)
	return notes
end

return House
