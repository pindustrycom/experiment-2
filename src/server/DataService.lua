-- Loads/saves player data with DataStoreService. Falls back to in-memory data
-- when DataStores are unavailable (e.g. unpublished place in Studio).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local House = require(ReplicatedStorage.Shared.House)

local DataService = {}
DataService.Profiles = {} -- [player] = data

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.SaveKey)
	end)
	if ok then
		store = result
	else
		warn("[BST] DataStores unavailable, progress will not save:", result)
	end
end

local function newUid(data)
	data.nextUid += 1
	return "s" .. data.nextUid
end
DataService.NewUid = newUid

function DataService.Default()
	local data = {
		cash = Config.StartingCash,
		totalEarned = 0,
		pulls = 0,
		pity = 0,
		nextUid = 0,
		students = {},
		rooms = {},
		facilities = {},
		likes = 0,
		likedAt = {}, -- [targetUserId] = os.time()
		lastDaily = 0,
		lastOnline = 0,
		discovered = {}, -- [studentId] = true (collection book)
		tutorialDone = false,
		floors = 1, -- floors unlocked
		plan = { floors = { House.defaultHallFloor() }, stairs = {} }, -- hallways, stairs, supports (shared/House.lua)
		layout = {}, -- [roomKey] = { floor, x, z, w, d, door } (shared/House.lua)
		styles = {}, -- [area] = { wall = id, floor = id, roof = id } (build mode)
		furniture = {}, -- [furnitureId] = true (shown) / false (owned, hidden)
		bonds = {}, -- [Config.BondKey(uidA, uidB)] = -50..100
		houseGender = "Mixed", -- Mixed / Boys / Girls (see Config.HouseGenders)
		livingItems = {}, -- [itemId] = true (living room)
		outing = false, -- { activity, members, returnAt } while a group is out
		nextOuting = 0, -- when the headmaster can send another group out
		photos = {}, -- { id, a = activity, m = members, o = outcome, t = time }, oldest first
		photoSeq = 0,
		buffs = {}, -- [uid] = time a great-outing mood boost ends
		applicants = { window = 0, salt = 0, bought = {} }, -- this restock's board (SchoolMath.applicants)
		luckUntil = 0, -- Lucky Hour pass end time
	}
	data.layout.me = { floor = 0, x = House.Default.rightX, z = 0, w = House.MeSize[1], d = House.MeSize[2] }
	data.layout.common = { floor = 0, x = House.Default.leftX, z = 0, w = 3, d = 3 }
	for i = 1, Config.StartingRooms do
		table.insert(data.rooms, { tier = 1, area = 9, occupants = {} })
		data.layout["r" .. i] = { floor = 0, x = House.Default.leftX, z = 3 * i, w = 3, d = 3 }
	end
	-- Two free starter students so the loop makes sense immediately.
	for _, id in ipairs({ "tim", "pete" }) do
		local uid = newUid(data)
		data.students[uid] = { id = id, shiny = false }
		data.discovered[id] = true
	end
	return data
end

-- Make data.plan + data.layout a valid house: convert old cell layouts, add
-- missing floors, and re-place any room that no longer fits.
local function fixPlan(data)
	local floors = data.floors
	local oldCells = data.plan == nil
	if oldCells then
		data.plan = { floors = {}, stairs = {} }
	end
	for f = 1, floors do
		if typeof(data.plan.floors[f]) ~= "table" or typeof(data.plan.floors[f].hall) ~= "string" or #data.plan.floors[f].hall ~= House.W * House.D then
			data.plan.floors[f] = House.defaultHallFloor()
			data.plan.stairs[f] = nil
		end
	end
	for f = #data.plan.floors, floors + 1, -1 do
		data.plan.floors[f] = nil
	end
	for f = 1, floors - 1 do
		if typeof(data.plan.stairs[f]) ~= "table" then
			data.plan.stairs[f] = House.defaultStairs(f - 1)
		end
	end
	for f = floors, Config.MaxFloors do
		data.plan.stairs[f] = nil
	end

	-- which rooms should exist, with the size they had
	local wanted = { { key = "me", w = House.MeSize[1], d = House.MeSize[2] }, { key = "common", w = 3, d = 3 } }
	for i, room in ipairs(data.rooms) do
		table.insert(wanted, { key = "r" .. i, w = 3, d = 3 * ((room.size == 2) and 2 or 1) })
	end
	for _, fac in ipairs(Config.Facilities) do
		if data.facilities[fac.id] then
			table.insert(wanted, { key = "fac:" .. fac.id, w = 3, d = 3 })
		end
	end
	local old = data.layout or {}
	local function startRect(want)
		local r = old[want.key]
		if typeof(r) ~= "table" then
			return nil
		end
		if oldCells or r.w == nil then
			if typeof(r.side) == "number" and typeof(r.row) == "number" and typeof(r.floor) == "number" then
				return House.fromCell(r, want.d // 3)
			end
			return nil
		end
		return { floor = r.floor, x = r.x, z = r.z, w = r.w, d = r.d, door = r.door }
	end

	-- the hallways and stairs must work on their own; otherwise reset them
	data.layout = {}
	if not House.validate(data) then
		for f = 1, floors do
			data.plan.floors[f].hall = House.defaultHallFloor().hall
		end
		for f = 1, floors - 1 do
			data.plan.stairs[f] = House.defaultStairs(f - 1)
		end
	end

	local homeless = {}
	for _, want in ipairs(wanted) do
		local r = startRect(want)
		if r then
			data.layout[want.key] = r
			if not House.validate(data) then
				data.layout[want.key] = nil
				table.insert(homeless, want)
			end
		else
			table.insert(homeless, want)
		end
	end
	for _, want in ipairs(homeless) do
		local placed = false
		while not placed do
			for _, dims in ipairs({ { want.w, want.d }, { 3, 3 } }) do
				if not placed and (want.key ~= "me" or dims[1] == want.w) then
					local f, x, z, w, d = House.findSpot(data, want.key, dims[1], dims[2])
					if f then
						data.layout[want.key] = { floor = f, x = x, z = z, w = w, d = d }
						placed = true
					end
				end
			end
			if not placed then
				if data.floors >= Config.MaxFloors then
					warn("[BST] no space in the house for", want.key)
					break
				end
				-- grow the house by a floor with the default hallway
				data.floors += 1
				data.plan.floors[data.floors] = House.defaultHallFloor()
				data.plan.stairs[data.floors - 1] = House.defaultStairs(data.floors - 2)
			end
		end
	end
	House.validate(data) -- settles every door
	for key, r in pairs(data.layout) do
		r.door = House.door(data, key)
	end
end

-- Fill in fields added in later versions and drop broken references.
local function reconcile(data)
	local default = DataService.Default()
	for k, v in pairs(default) do
		if data[k] == nil then
			data[k] = v
		end
	end
	for uid, s in pairs(data.students) do
		if not Config.StudentById[s.id] then
			data.students[uid] = nil
		end
	end
	for key in pairs(data.bonds) do
		local a, b = string.match(key, "^(.-)|(.*)$")
		if not (a and data.students[a] and data.students[b]) then
			data.bonds[key] = nil
		end
	end
	for uid, untilTime in pairs(data.buffs) do
		if not data.students[uid] or untilTime < os.time() then
			data.buffs[uid] = nil
		end
	end
	if not Config.HouseGenders[data.houseGender] then
		data.houseGender = "Mixed"
	end
	data.order = nil
	data.floors = math.clamp(math.floor(data.floors or 1), 1, Config.MaxFloors)
	fixPlan(data)
	for i, room in ipairs(data.rooms) do
		room.tier = math.clamp(room.tier or 1, 1, #Config.RoomTiers)
		room.size = nil
		room.area = House.area(data, "r" .. i)
		-- rooms are single-gender: keep the first occupant's gender
		local kept, gender = {}, nil
		for _, uid in ipairs(room.occupants or {}) do
			local s = data.students[uid]
			local g = s and Config.StudentById[s.id].gender
			gender = gender or g
			if s and g == gender and #kept < Config.Beds(room) then
				table.insert(kept, uid)
			end
		end
		room.occupants = kept
	end
	return data
end

function DataService.Load(player)
	local data
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				data = result
				break
			end
			warn("[BST] load failed, retrying", attempt, result)
			task.wait(attempt)
		end
	end
	data = reconcile(data or DataService.Default())
	if Config.StudioTestCash and RunService:IsStudio() then
		data.cash = math.max(data.cash, Config.StudioTestCash)
	end
	DataService.Profiles[player] = data
	return data
end

function DataService.Save(player)
	local data = DataService.Profiles[player]
	if not data or not store then
		return
	end
	if Config.StudioTestCash and RunService:IsStudio() then
		return -- don't write test cash into the real save
	end
	data.lastOnline = os.time()
	local ok, err = pcall(function()
		store:SetAsync("u" .. player.UserId, data)
	end)
	if not ok then
		warn("[BST] save failed for", player.Name, err)
	end
end

function DataService.Get(player)
	return DataService.Profiles[player]
end

function DataService.Release(player)
	DataService.Save(player)
	DataService.Profiles[player] = nil
end

-- Autosave loop + shutdown flush
task.spawn(function()
	while true do
		task.wait(90)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(DataService.Save, player)
		end
	end
end)

game:BindToClose(function()
	local threads = 0
	for _, player in ipairs(Players:GetPlayers()) do
		threads += 1
		task.spawn(function()
			DataService.Save(player)
			threads -= 1
		end)
	end
	local start = os.clock()
	while threads > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)

return DataService
