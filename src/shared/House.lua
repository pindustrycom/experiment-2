-- House layout: which room sits in which cell of which floor. Shared so the
-- server renders exactly what the client's layout board shows.
--
-- Every floor is a hallway running front to back with House.Rows cells on
-- each side (side -1 = left, +1 = right when you walk in the front door; row 0
-- is at the front). data.layout[key] = { floor, side, row } is the first cell
-- a room uses; a room of size 2 also uses the next row. Keys: "me" (your
-- room), "common", "r<i>" (dorm i), "fac:<id>" (facility).
local Config = require(script.Parent.Config)

local House = {}

-- geometry shared with the client (must match server/PlotService.lua)
House.FloorHeight = 12
House.Bounds = { x = 25, z0 = -45, z1 = 75, floorY = 1.2 } -- house footprint in plot space, ground floor height

House.Rows = Config.SlotsPerFloor / 2
House.MaxFloors = Config.MaxFloors

-- rooms that are always there
House.Fixed = {
	me = { floor = 0, side = 1, row = 0 },
	common = { floor = 0, side = -1, row = 0 },
}
-- where the starting dorms go
House.StartCells = {
	{ floor = 0, side = -1, row = 1 },
	{ floor = 0, side = -1, row = 2 },
}

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

function House.size(data, key)
	if key == "me" then
		return 2
	end
	local kind, index = describe(key)
	if kind == "dorm" then
		local room = data.rooms[index]
		return room and room.size or 1
	end
	return 1
end

function House.floorCount(data)
	return data.floors or 1
end

-- { key, kind, index, id, floor, side, row, size }
function House.placements(data)
	local list = {}
	for key, cell in pairs(data.layout or {}) do
		local kind, index, id = describe(key)
		if kind then
			table.insert(list, { key = key, kind = kind, index = index, id = id, floor = cell.floor, side = cell.side, row = cell.row, size = House.size(data, key) })
		end
	end
	table.sort(list, function(a, b)
		if a.floor ~= b.floor then
			return a.floor < b.floor
		elseif a.row ~= b.row then
			return a.row < b.row
		end
		return a.side < b.side
	end)
	return list
end

-- grid[floor][side][row] = placement
function House.grid(data)
	local grid = {}
	for f = 0, House.floorCount(data) - 1 do
		grid[f] = { [-1] = {}, [1] = {} }
	end
	for _, p in ipairs(House.placements(data)) do
		for r = p.row, p.row + p.size - 1 do
			if grid[p.floor] and grid[p.floor][p.side] then
				grid[p.floor][p.side][r] = p
			end
		end
	end
	return grid
end

function House.validCell(data, floor, side, row, size)
	return typeof(floor) == "number" and typeof(row) == "number" and (side == 1 or side == -1)
		and floor % 1 == 0 and row % 1 == 0
		and floor >= 0 and floor < House.floorCount(data)
		and row >= 0 and row + (size or 1) - 1 < House.Rows
end

function House.isFree(data, floor, side, row, size, ignoreKey)
	if not House.validCell(data, floor, side, row, size) then
		return false
	end
	local grid = House.grid(data)
	for r = row, row + (size or 1) - 1 do
		local p = grid[floor][side][r]
		if p and p.key ~= ignoreKey then
			return false
		end
	end
	return true
end

-- first free cell (front to back, floor by floor), or nil if the house is full
function House.firstFree(data, size)
	for f = 0, House.floorCount(data) - 1 do
		for row = 0, House.Rows - 1 do
			for _, side in ipairs({ 1, -1 }) do
				if House.isFree(data, f, side, row, size) then
					return f, side, row
				end
			end
		end
	end
	return nil
end

-- how dorm i could grow into a neighbouring cell: returns the new first row
function House.expandRow(data, index)
	local key = "r" .. index
	local cell = data.layout[key]
	local room = data.rooms[index]
	if not cell or not room or (room.size or 1) >= 2 then
		return nil
	end
	if House.isFree(data, cell.floor, cell.side, cell.row + 1, 1) then
		return cell.row
	elseif House.isFree(data, cell.floor, cell.side, cell.row - 1, 1) then
		return cell.row - 1
	end
	return nil
end

function House.floorOf(data, key)
	local cell = data.layout and data.layout[key]
	return cell and cell.floor + 1 or 1
end

function House.freeCells(data)
	local n = 0
	for f = 0, House.floorCount(data) - 1 do
		for row = 0, House.Rows - 1 do
			for _, side in ipairs({ 1, -1 }) do
				if House.isFree(data, f, side, row, 1) then
					n += 1
				end
			end
		end
	end
	return n
end

function House.cellName(cell)
	return string.format("Floor %d, %s side, %s", cell.floor + 1, cell.side == 1 and "right" or "left", cell.row == 0 and "by the front door" or ("row " .. (cell.row + 1)))
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
	local big = House.size(data, key) >= 2 and Config.BigRoomDecor or 0
	return (House.style(data, key, "wall").decor or 0) + (House.style(data, key, "floor").decor or 0) + big
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

return House
