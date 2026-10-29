-- House floor plans. Shared so the server builds exactly what the client's
-- floor plan designer shows, and so the client can find paths for students.
--
-- The lot is a grid of tiles (House.W x House.D, House.TILE studs each).
-- Every floor has:
--   * hallway tiles: data.plan.floors[f + 1].hall, a string of "0"/"1" per tile
--   * rooms: data.layout[key] = { floor, x, z, w, d, door = { x, z, dx, dz } }
--     (x, z = first tile, w along x, d along z; door = the tile inside the room
--     and the direction to the hallway tile it opens onto). Keys: "me" (your
--     room), "common", "r<i>" (dorm i), "fac:<id>" (facility).
--   * stairs up: data.plan.stairs[f + 1] = { x, z, dir } -> House.StairLen tiles
--     of hallway starting at (x, z) going in DIRS[dir]; the floor above has a
--     stairwell over them and a landing tile right after.
--   * supports: data.plan.floors[f + 1].support. The floor above a supported
--     floor may hang out up to House.Overhang tiles past it (columns hold it
--     up); otherwise every floor has to sit on the floor below.
-- Tile (x, z) is 0-based; x runs right -> left as you walk in the front door, z runs front -> back.
local Config = require(script.Parent.Config)

local House = {}

House.TILE = 6
House.W, House.D = 16, 20
House.X0, House.Z0 = -48, -44 -- plot-local corner of tile (0, 0)
House.FloorHeight = 12
House.GroundY = 1.2 -- plot-local height of the ground floor
House.MaxFloors = Config.MaxFloors
House.Overhang = 3
House.StairLen = 3
House.DIRS = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } -- dir 1..4: +z, +x, -z, -x
-- the whole lot in plot space (the client fades floors above you inside it)
House.Bounds = { x = 50, z0 = -46, z1 = 78, floorY = 1.2 }

-- smallest room per kind (tiles); your own room is always exactly 3 x 6
House.MinSize = { dorm = 3, facility = 3, common = 3 }
House.MeSize = { 3, 6 }

local W, D = House.W, House.D

local function id(x, z)
	return z * W + x + 1
end
House.id = id

function House.inLot(x, z)
	return x >= 0 and x < W and z >= 0 and z < D
end

-- plot-local center of a tile at height y
function House.tileCenter(x, z)
	return House.X0 + (x + 0.5) * House.TILE, House.Z0 + (z + 0.5) * House.TILE
end

function House.floorY(f)
	return House.GroundY + f * House.FloorHeight
end

local function describe(key)
	if key == "me" or key == "common" then
		return key
	end
	local i = string.match(key, "^r(%d+)$")
	if i then
		return "dorm", tonumber(i)
	end
	local fid = string.match(key, "^fac:(.+)$")
	if fid then
		return "facility", nil, fid
	end
	return nil
end
House.describe = describe

function House.floorCount(data)
	return data.floors or 1
end

---------------------------------------------------------------------------
-- Plan storage
---------------------------------------------------------------------------
local EMPTY = string.rep("0", W * D)

function House.emptyFloor()
	return { hall = EMPTY, support = false }
end

local function floorPlan(data, f)
	return data.plan and data.plan.floors[f + 1]
end

function House.isHall(data, f, x, z)
	local fp = floorPlan(data, f)
	return fp ~= nil and House.inLot(x, z) and string.sub(fp.hall, id(x, z), id(x, z)) == "1"
end

function House.setHall(data, f, x, z, on)
	local fp = floorPlan(data, f)
	if not fp or not House.inLot(x, z) then
		return
	end
	local i = id(x, z)
	fp.hall = string.sub(fp.hall, 1, i - 1) .. (on and "1" or "0") .. string.sub(fp.hall, i + 1)
end

function House.supported(data, f)
	local fp = floorPlan(data, f)
	return fp ~= nil and fp.support == true
end

-- stairs going up from floor f: { tiles = { {x, z}... }, entry = {x, z}, landing = {x, z}, dir }
function House.stairs(data, f)
	local s = data.plan and data.plan.stairs[f + 1]
	if typeof(s) ~= "table" then
		return nil
	end
	local d = House.DIRS[s.dir] or House.DIRS[1]
	local tiles = {}
	for k = 0, House.StairLen - 1 do
		table.insert(tiles, { s.x + d[1] * k, s.z + d[2] * k })
	end
	return {
		x = s.x,
		z = s.z,
		dir = s.dir,
		tiles = tiles,
		entry = { s.x - d[1], s.z - d[2] },
		landing = { s.x + d[1] * House.StairLen, s.z + d[2] * House.StairLen },
	}
end

---------------------------------------------------------------------------
-- Rooms
---------------------------------------------------------------------------
function House.rect(data, key)
	return data.layout and data.layout[key]
end

function House.area(data, key)
	local r = House.rect(data, key)
	return r and r.w * r.d or 0
end

-- { key, kind, index, id, floor, x, z, w, d }
function House.placements(data)
	local list = {}
	for key, r in pairs(data.layout or {}) do
		local kind, index, fid = describe(key)
		if kind and typeof(r) == "table" and r.w then
			table.insert(list, { key = key, kind = kind, index = index, id = fid, floor = r.floor, x = r.x, z = r.z, w = r.w, d = r.d })
		end
	end
	table.sort(list, function(a, b)
		if a.floor ~= b.floor then
			return a.floor < b.floor
		elseif a.z ~= b.z then
			return a.z < b.z
		end
		return a.x < b.x
	end)
	return list
end

function House.floorOf(data, key)
	local r = House.rect(data, key)
	return r and r.floor + 1 or 1
end

---------------------------------------------------------------------------
-- Who owns each tile of a floor
---------------------------------------------------------------------------
-- returns owner[id] = "hall" | room key, plus sets of stair tiles (going up
-- from this floor) and well tiles (the hole over the stairs from below)
function House.owners(data, f)
	local owner, stair, well = {}, {}, {}
	local fp = floorPlan(data, f)
	if fp then
		for i = 1, W * D do
			if string.sub(fp.hall, i, i) == "1" then
				owner[i] = "hall"
			end
		end
	end
	for key, r in pairs(data.layout or {}) do
		if typeof(r) == "table" and r.floor == f and r.w then
			for x = r.x, r.x + r.w - 1 do
				for z = r.z, r.z + r.d - 1 do
					if House.inLot(x, z) then
						local cur = owner[id(x, z)]
						-- "!" marks two rooms overlapping, "!h" a room on hallway
						owner[id(x, z)] = cur == nil and key or (cur == "hall" and "!h" or "!")
					end
				end
			end
		end
	end
	local up = House.stairs(data, f)
	if up then
		for _, t in ipairs(up.tiles) do
			if House.inLot(t[1], t[2]) then
				stair[id(t[1], t[2])] = true
			end
		end
	end
	local down = f > 0 and House.stairs(data, f - 1)
	if down then
		for _, t in ipairs(down.tiles) do
			if House.inLot(t[1], t[2]) then
				well[id(t[1], t[2])] = true
			end
		end
	end
	return owner, stair, well
end

function House.footprint(data, f)
	local owner = House.owners(data, f)
	local set = {}
	for i in pairs(owner) do
		set[i] = true
	end
	return set
end

-- How a room is furnished: props line up against one wall (the door wall,
-- or for your room the long wall nearest the door). Returns the plot-local
-- middle of that wall's line { x, z }, the unit direction into the room
-- (ux, uz), and the room's depth U and width V in studs. Local axes:
-- u into the room, v = (-uz, ux) along the wall.
function House.roomFrame(r, door, key)
	local dx, dz = 0, -1
	if door then
		dx, dz = door.dx, door.dz
	end
	if key == "me" and door then
		local wallLen = dx ~= 0 and r.d or r.w
		local across = dx ~= 0 and r.w or r.d
		if wallLen < across then
			if dx ~= 0 then
				dx, dz = 0, (door.z - r.z <= r.z + r.d - 1 - door.z) and -1 or 1
			else
				dx, dz = (door.x - r.x <= r.x + r.w - 1 - door.x) and -1 or 1, 0
			end
		end
	end
	local T = House.TILE
	local x0, z0 = House.X0 + r.x * T, House.Z0 + r.z * T
	local x1, z1 = x0 + r.w * T, z0 + r.d * T
	local ox, oz = (x0 + x1) / 2, (z0 + z1) / 2
	if dx == 1 then
		ox = x1
	elseif dx == -1 then
		ox = x0
	end
	if dz == 1 then
		oz = z1
	elseif dz == -1 then
		oz = z0
	end
	return {
		x = ox,
		z = oz,
		ux = -dx,
		uz = -dz,
		U = (dx ~= 0 and r.w or r.d) * T,
		V = (dx ~= 0 and r.d or r.w) * T,
	}
end

-- plot-local point of a room frame's (u, v)
function House.framePoint(fr, u, v)
	return fr.x + fr.ux * u - fr.uz * v, fr.z + fr.uz * u + fr.ux * v
end

-- plot-local middle of the doorway (on the wall line)
function House.doorPoint(door)
	local cx, cz = House.tileCenter(door.x, door.z)
	return cx + door.dx * House.TILE / 2, cz + door.dz * House.TILE / 2
end

---------------------------------------------------------------------------
-- Doors and the front entrance
---------------------------------------------------------------------------
-- every (inside tile, direction) on the room's edge that opens onto hallway
local function doorOptions(data, key, owner, stair, well)
	local r = House.rect(data, key)
	local list = {}
	for x = r.x, r.x + r.w - 1 do
		for z = r.z, r.z + r.d - 1 do
			for _, d in ipairs(House.DIRS) do
				local nx, nz = x + d[1], z + d[2]
				local inside = nx >= r.x and nx < r.x + r.w and nz >= r.z and nz < r.z + r.d
				if not inside and House.inLot(nx, nz) then
					local n = id(nx, nz)
					if owner[n] == "hall" and not stair[n] and not well[n] then
						table.insert(list, { x = x, z = z, dx = d[1], dz = d[2] })
					end
				end
			end
		end
	end
	return list
end

-- the room's door: the saved one if it still opens onto hallway, otherwise
-- the option closest to the middle of the room's longest hallway-facing side
function House.door(data, key, owner, stair, well)
	local r = House.rect(data, key)
	if not r then
		return nil
	end
	if not owner then
		owner, stair, well = House.owners(data, r.floor)
	end
	local options = doorOptions(data, key, owner, stair, well)
	local saved = r.door
	if typeof(saved) == "table" then
		for _, o in ipairs(options) do
			if o.x == saved.x and o.z == saved.z and o.dx == saved.dx and o.dz == saved.dz then
				return o
			end
		end
	end
	local cx, cz = r.x + (r.w - 1) / 2, r.z + (r.d - 1) / 2
	local best, bestScore = nil, math.huge
	for _, o in ipairs(options) do
		-- prefer the long sides, then the middle of the side
		local alongX = o.dz ~= 0
		local sideLen = alongX and r.w or r.d
		local off = alongX and math.abs(o.x - cx) or math.abs(o.z - cz)
		local score = -sideLen * 10 + off
		if score < bestScore then
			best, bestScore = o, score
		end
	end
	return best
end

-- ground floor front door: the middle of the front-most run of hallway tiles
-- that touch the outside on their -z side. Returns { z, x0, x1 } (tiles) or nil.
function House.entrance(data)
	local owner = House.owners(data, 0)
	for z = 0, D - 1 do
		local runs, cur = {}, nil
		for x = 0, W - 1 do
			local open = owner[id(x, z)] == "hall" and (z == 0 or owner[id(x, z - 1)] == nil)
			if open then
				if cur and cur.x1 == x - 1 then
					cur.x1 = x
				else
					cur = { z = z, x0 = x, x1 = x }
					table.insert(runs, cur)
				end
			end
		end
		if #runs > 0 then
			local mid = (W - 1) / 2
			table.sort(runs, function(a, b)
				return math.abs((a.x0 + a.x1) / 2 - mid) < math.abs((b.x0 + b.x1) / 2 - mid)
			end)
			local run = runs[1]
			-- door at most 2 tiles wide, centered on the run
			if run.x1 - run.x0 >= 2 then
				local c = math.floor((run.x0 + run.x1) / 2)
				run.x0, run.x1 = c, c + ((run.x1 - run.x0) % 2 == 1 and 1 or 0)
			end
			return run
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Validation: is this plan a house you can live in?
---------------------------------------------------------------------------
local function chebyshevNear(set, x, z, dist)
	for dx = -dist, dist do
		for dz = -dist, dist do
			local nx, nz = x + dx, z + dz
			if House.inLot(nx, nz) and set[id(nx, nz)] then
				return true
			end
		end
	end
	return false
end

-- hallway tiles reachable from `start` tiles, walking on hallway that isn't stairs or stairwell
local function reach(owner, stair, well, starts)
	local seen, queue = {}, {}
	for _, s in ipairs(starts) do
		local i = id(s[1], s[2])
		if owner[i] == "hall" and not stair[i] and not well[i] and not seen[i] then
			seen[i] = true
			table.insert(queue, s)
		end
	end
	local head = 1
	while head <= #queue do
		local t = queue[head]
		head += 1
		for _, d in ipairs(House.DIRS) do
			local nx, nz = t[1] + d[1], t[2] + d[2]
			if House.inLot(nx, nz) then
				local i = id(nx, nz)
				if not seen[i] and owner[i] == "hall" and not stair[i] and not well[i] then
					seen[i] = true
					table.insert(queue, { nx, nz })
				end
			end
		end
	end
	return seen
end

-- returns true, or false + a message for the player
function House.validate(data)
	local floors = House.floorCount(data)
	if not data.plan or #data.plan.floors < floors then
		return false, "This floor has no plan yet."
	end
	local below = nil
	for f = 0, floors - 1 do
		local owner, stair, well = House.owners(data, f)
		local name = "Floor " .. (f + 1)
		for _, o in pairs(owner) do
			if o == "!" then
				return false, name .. ": two rooms overlap."
			elseif o == "!h" then
				return false, name .. ": a room is on top of hallway."
			end
		end
		for key, r in pairs(data.layout) do
			if r.floor < 0 or r.floor >= floors then
				return false, "That floor isn't built yet."
			end
			if r.floor == f then
				for x = r.x, r.x + r.w - 1 do
					for z = r.z, r.z + r.d - 1 do
						if not House.inLot(x, z) then
							return false, "That doesn't fit on your lot."
						end
						local i = id(x, z)
						if stair[i] or well[i] then
							return false, name .. ": rooms can't go over the stairs."
						end
					end
				end
			end
		end
		-- every floor stands on the one below (or hangs off a supported one)
		if below then
			local reachOut = House.supported(data, f - 1) and House.Overhang or 0
			for i in pairs(owner) do
				local x, z = (i - 1) % W, (i - 1) // W
				if not below[i] and not (reachOut > 0 and chebyshevNear(below, x, z, reachOut)) then
					return false, House.supported(data, f - 1) and (name .. " hangs out too far (" .. House.Overhang .. " tiles max).") or (name .. " sticks out past the floor below. Add supports to " .. "Floor " .. f .. " to let it hang over.")
				end
			end
		end
		-- stairs: on hallway, with hallway to step on at both ends
		local up = House.stairs(data, f)
		if f < floors - 1 then
			if not up then
				return false, name .. " needs stairs up."
			end
			local upper = House.owners(data, f + 1)
			for _, t in ipairs(up.tiles) do
				if not House.inLot(t[1], t[2]) or owner[id(t[1], t[2])] ~= "hall" or upper[id(t[1], t[2])] ~= "hall" then
					return false, name .. ": stairs need hallway under them and above them."
				end
				if well[id(t[1], t[2])] then
					return false, name .. ": stairs can't start over the stairwell from below."
				end
			end
			local e, l = up.entry, up.landing
			if not House.inLot(e[1], e[2]) or owner[id(e[1], e[2])] ~= "hall" or stair[id(e[1], e[2])] or well[id(e[1], e[2])] then
				return false, name .. ": the bottom of the stairs needs a hallway tile in front of it."
			end
			if not House.inLot(l[1], l[2]) or upper[id(l[1], l[2])] ~= "hall" then
				return false, "Floor " .. (f + 2) .. ": the top of the stairs needs a hallway tile to land on."
			end
		end
		-- the hallway has to connect the way in to every door
		local starts = {}
		if f == 0 then
			local ent = House.entrance(data)
			if not ent then
				return false, "Floor 1: the hallway has to reach the front of the house (that's your front door)."
			end
			table.insert(starts, { ent.x0, ent.z })
		else
			local down = House.stairs(data, f - 1)
			table.insert(starts, down.landing)
		end
		local seen = reach(owner, stair, well, starts)
		for key, r in pairs(data.layout) do
			if r.floor == f then
				local door = House.door(data, key, owner, stair, well)
				if not door then
					return false, name .. ": " .. House.label(data, key) .. " needs a hallway next to it for its door."
				end
				if not seen[id(door.x + door.dx, door.z + door.dz)] then
					-- try any other door option that is connected
					local found = false
					for _, o in ipairs(doorOptions(data, key, owner, stair, well)) do
						if seen[id(o.x + o.dx, o.z + o.dz)] then
							found = true
							r.door = { x = o.x, z = o.z, dx = o.dx, dz = o.dz }
							break
						end
					end
					if not found then
						return false, name .. ": you can't walk to " .. House.label(data, key) .. " from the " .. (f == 0 and "front door." or "stairs.")
					end
				end
			end
		end
		if up and not seen[id(up.entry[1], up.entry[2])] then
			return false, name .. ": the stairs aren't connected to the hallway."
		end
		below = House.footprint(data, f)
	end
	return true
end

function House.label(data, key)
	local kind, index, fid = describe(key)
	if kind == "me" then
		return "your room"
	elseif kind == "common" then
		return "the common room"
	elseif kind == "dorm" then
		return "Room " .. index
	elseif kind == "facility" then
		local f = Config.FacilityById[fid]
		return f and ("the " .. f.name) or fid
	end
	return key
end

-- can `key` (existing or new) take this rectangle? Applies it to a copy of the
-- plan and validates the whole house.
function House.tryRect(data, key, f, x, z, w, d)
	local copy = House.clonePlan(data)
	copy.layout[key] = { floor = f, x = x, z = z, w = w, d = d, door = nil }
	local ok, err = House.validate(copy)
	return ok, err, copy
end

-- shallow copy of everything the plan check reads
function House.clonePlan(data)
	local copy = { floors = data.floors, layout = {}, plan = { floors = {}, stairs = {} }, rooms = data.rooms, facilities = data.facilities }
	for key, r in pairs(data.layout or {}) do
		copy.layout[key] = table.clone(r)
	end
	for i, fp in ipairs(data.plan.floors) do
		copy.plan.floors[i] = table.clone(fp)
	end
	for i, s in pairs(data.plan.stairs) do
		copy.plan.stairs[i] = typeof(s) == "table" and table.clone(s) or s
	end
	return copy
end

---------------------------------------------------------------------------
-- Defaults: the classic house. A 2-tile hallway down the middle, 3 x 3
-- rooms on both sides, stairs climbing toward the front one floor at a time.
---------------------------------------------------------------------------
House.Default = {
	hallX = { 7, 8 },
	hallZ = { 0, 17 },
	leftX = 4,
	rightX = 9,
	rows = 6,
}

function House.defaultHallFloor()
	local fp = House.emptyFloor()
	local tmp = { plan = { floors = { fp }, stairs = {} } }
	for _, x in ipairs(House.Default.hallX) do
		for z = House.Default.hallZ[1], House.Default.hallZ[2] do
			House.setHall(tmp, 0, x, z, true)
		end
	end
	return fp
end

-- stairs from floor f in the default house
function House.defaultStairs(f)
	return { x = 7 + (f % 2), z = 15 - 3 * f, dir = 3 }
end

-- old saves: rooms were cells { floor, side, row } on a fixed hallway
function House.fromCell(cell, size)
	return {
		floor = cell.floor,
		x = cell.side == 1 and House.Default.rightX or House.Default.leftX,
		z = cell.row * 3,
		w = 3,
		d = 3 * (size or 1),
	}
end

-- first place on any floor where a w x d room fits next to a hallway
function House.findSpot(data, key, w, d)
	for f = 0, House.floorCount(data) - 1 do
		for z = 0, D - d do
			for x = 0, W - w do
				for _, dims in ipairs({ { w, d }, { d, w } }) do
					local ok = House.tryRect(data, key, f, x, z, dims[1], dims[2])
					if ok then
						return f, x, z, dims[1], dims[2]
					end
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Look and feel (build mode)
---------------------------------------------------------------------------
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

-- extra satisfaction a dorm room gets from its walls, floor and size
function House.roomDecor(data, index)
	local key = "r" .. index
	local area = House.area(data, key)
	local space = math.floor(math.max(0, area - 9) * Config.BigRoomDecor / 9)
	return (House.style(data, key, "wall").decor or 0) + (House.style(data, key, "floor").decor or 0) + space
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
-- Walking (client): shortest path over hallway tiles between two tiles.
-- `walkable(i)` says whether tile id i can be walked on.
---------------------------------------------------------------------------
function House.path(fromX, fromZ, toX, toZ, walkable)
	local start, goal = id(fromX, fromZ), id(toX, toZ)
	if start == goal then
		return { { toX, toZ } }
	end
	local prev, queue = { [start] = 0 }, { start }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		if cur == goal then
			break
		end
		local x, z = (cur - 1) % W, (cur - 1) // W
		for _, d in ipairs(House.DIRS) do
			local nx, nz = x + d[1], z + d[2]
			if House.inLot(nx, nz) then
				local n = id(nx, nz)
				if prev[n] == nil and (n == goal or walkable(n)) then
					prev[n] = cur
					table.insert(queue, n)
				end
			end
		end
	end
	if prev[goal] == nil then
		return nil
	end
	local out = {}
	local cur = goal
	while cur ~= start do
		table.insert(out, 1, { (cur - 1) % W, (cur - 1) // W })
		cur = prev[cur]
	end
	return out
end

return House
