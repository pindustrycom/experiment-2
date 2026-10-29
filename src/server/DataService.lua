-- Loads/saves player data with DataStoreService. Falls back to in-memory data
-- when DataStores are unavailable (e.g. unpublished place in Studio).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

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
		order = {}, -- build order of house slots: "r<i>" dorms, "fac:<id>" facilities
		styles = {}, -- [area] = { wall = id, floor = id, roof = id } (build mode)
		furniture = {}, -- [furnitureId] = true (shown) / false (owned, hidden)
	}
	for i = 1, Config.StartingRooms do
		table.insert(data.rooms, { tier = 1, occupants = {} })
		table.insert(data.order, "r" .. i)
	end
	-- Two free starter students so the loop makes sense immediately.
	for _, id in ipairs({ "tim", "pete" }) do
		local uid = newUid(data)
		data.students[uid] = { id = id, shiny = false }
		data.discovered[id] = true
	end
	return data
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
	for _, room in ipairs(data.rooms) do
		room.tier = math.clamp(room.tier or 1, 1, #Config.RoomTiers)
		local kept = {}
		for _, uid in ipairs(room.occupants or {}) do
			if data.students[uid] and #kept < Config.RoomTiers[room.tier].beds then
				table.insert(kept, uid)
			end
		end
		room.occupants = kept
	end
	-- every room and facility needs exactly one slot in the house
	local seen, order = {}, {}
	for _, key in ipairs(data.order) do
		local i = tonumber(string.match(key, "^r(%d+)$") or "")
		local fid = string.match(key, "^fac:(.+)$")
		local valid = (i and data.rooms[i]) or (fid and data.facilities[fid])
		if valid and not seen[key] then
			seen[key] = true
			table.insert(order, key)
		end
	end
	for i in ipairs(data.rooms) do
		if not seen["r" .. i] then
			table.insert(order, "r" .. i)
		end
	end
	for _, f in ipairs(Config.Facilities) do
		if data.facilities[f.id] and not seen["fac:" .. f.id] then
			table.insert(order, "fac:" .. f.id)
		end
	end
	data.order = order
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
	DataService.Profiles[player] = data
	return data
end

function DataService.Save(player)
	local data = DataService.Profiles[player]
	if not data or not store then
		return
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
