-- Boarding School Tycoon: server entry point.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SchoolMath = require(Shared.SchoolMath)
local House = require(Shared.House)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local ActionFn = remote("RemoteFunction", "Action")
local StateEv = remote("RemoteEvent", "State")
local TickEv = remote("RemoteEvent", "Tick")
local NotifyEv = remote("RemoteEvent", "Notify")
local AnnounceEv = remote("RemoteEvent", "Announce")
local PullResultEv = remote("RemoteEvent", "PullResult")
remotes.Parent = ReplicatedStorage

PlotService.BuildWorld()

---------------------------------------------------------------------------
-- Per-player runtime state
---------------------------------------------------------------------------
local session = {} -- [player] = { plot, totals, mult, passes, friends, dirty, offlinePending }

local function passOwned(player, key)
	local id = Config.GamePasses[key]
	if not id or id == 0 then
		return false
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
	return ok and owns
end

local function computeMult(player)
	local s = session[player]
	local mult = 1
	if s.passes.DoubleCash then
		mult *= 2
	end
	if s.passes.VIP then
		mult *= 1.1
	end
	mult *= 1 + math.min(s.friends * Config.FriendBoostEach, Config.FriendBoostMax)
	s.mult = mult
	return mult
end

local function countStudents(data)
	local n = 0
	for _ in pairs(data.students) do
		n += 1
	end
	return n
end

local function recompute(player)
	local s, data = session[player], DataService.Get(player)
	if not s or not data then
		return
	end
	s.totals = SchoolMath.totals(data, computeMult(player))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Income.Value = math.floor(s.totals.income)
		ls.Likes.Value = data.likes
	end
end

local function pushState(player)
	local s, data = session[player], DataService.Get(player)
	if not s or not data then
		return
	end
	recompute(player)
	s.dirty = true
	StateEv:FireClient(player, {
		data = data,
		income = s.totals.income,
		satisfaction = s.totals.satisfaction,
		mult = s.mult,
		friends = s.friends,
		passes = s.passes,
		gamePasses = Config.GamePasses,
		products = Config.Products,
		dailyIn = math.max(0, data.lastDaily + Config.DailyCooldown - os.time()),
		plotIndex = s.plot and s.plot.index,
	})
end

local function notify(player, text, kind)
	NotifyEv:FireClient(player, text, kind or "info")
end

-- Re-render dirty schools at most twice per second.
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, s in pairs(session) do
			if s.dirty and s.plot then
				s.dirty = false
				local data = DataService.Get(player)
				if data then
					PlotService.Render(s.plot, data, s.totals)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Helpers on data
---------------------------------------------------------------------------
local function roomOf(data, uid)
	for i, room in ipairs(data.rooms) do
		for j, occ in ipairs(room.occupants) do
			if occ == uid then
				return i, j
			end
		end
	end
	return nil
end

local function removeFromRoom(data, uid)
	local i, j = roomOf(data, uid)
	if i then
		table.remove(data.rooms[i].occupants, j)
	end
end

local function spend(data, amount)
	if data.cash < amount then
		return false
	end
	data.cash -= amount
	return true
end

local function roll(player, data, banner)
	local s = session[player]
	local weights = table.clone(banner.weights)
	if s.passes.Lucky then
		weights.Legendary *= 1.5
		weights.Mythic *= 1.5
	end
	data.pity += 1
	local rarity
	if data.pity >= Config.PityPulls then
		rarity = math.random() < 0.15 and "Mythic" or "Legendary"
	else
		local total = 0
		for _, r in ipairs(Config.RarityOrder) do
			total += weights[r] or 0
		end
		local pick = math.random() * total
		for _, r in ipairs(Config.RarityOrder) do
			pick -= weights[r] or 0
			if pick <= 0 then
				rarity = r
				break
			end
		end
		rarity = rarity or "Common"
	end
	if Config.Rarities[rarity].rank >= 5 then
		data.pity = 0
	end
	-- the house rule decides who applies; weight makes some students rarer in their tier
	local pool, total = {}, 0
	for _, d in ipairs(Config.StudentsByRarity[rarity]) do
		if data.houseGender == "Mixed" or (data.houseGender == "Boys") == (d.gender == "M") then
			table.insert(pool, d)
			total += d.weight or 1
		end
	end
	local def = pool[#pool]
	local pick = math.random() * total
	for _, d in ipairs(pool) do
		pick -= d.weight or 1
		if pick <= 0 then
			def = d
			break
		end
	end
	local shiny = math.random() < Config.ShinyChance
	local uid = DataService.NewUid(data)
	local isNew = not data.discovered[def.id]
	data.students[uid] = { id = def.id, shiny = shiny }
	data.discovered[def.id] = true
	data.pulls += 1

	if Config.Rarities[rarity].rank >= 5 or (shiny and Config.Rarities[rarity].rank >= 4) then
		AnnounceEv:FireAllClients({
			player = player.DisplayName,
			student = def.name,
			rarity = rarity,
			shiny = shiny,
		})
	end
	return { uid = uid, id = def.id, shiny = shiny, new = isNew }
end

local function doPulls(player, data, banner, count)
	if countStudents(data) + count > Config.MaxStudents then
		return nil, "Your roster is full! Expel some students first."
	end
	local results = {}
	for _ = 1, count do
		table.insert(results, roll(player, data, banner))
	end
	return results
end

-- Greedy auto-arrange: put the best earners into beds, choosing each
-- student's room by the income it adds, then try pairwise swaps.
local function autoArrange(player, data)
	local mult = session[player].mult
	for _, room in ipairs(data.rooms) do
		room.occupants = {}
	end
	local beds = 0
	for _, room in ipairs(data.rooms) do
		beds += Config.Beds(room)
	end
	local list = {}
	for uid, s in pairs(data.students) do
		local def = Config.StudentById[s.id]
		table.insert(list, { uid = uid, value = Config.Rarities[def.rarity].income * (s.shiny and 2 or 1) })
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)

	local indexOf = {}
	for i, room in ipairs(data.rooms) do
		indexOf[room] = i
	end
	local ctx = SchoolMath.context(data)
	local function roomIncome(room)
		return SchoolMath.room(data, indexOf[room], room.occupants, mult, ctx).income
	end
	local function genderOf(uid)
		return Config.StudentById[data.students[uid].id].gender
	end
	-- rooms are single-gender: a room takes its first occupant's gender
	local function fits(room, uid)
		local first = room.occupants[1]
		return first == nil or genderOf(first) == genderOf(uid)
	end

	for n = 1, math.min(beds, #list) do
		local uid = list[n].uid
		local bestRoom, bestGain = nil, -math.huge
		for _, room in ipairs(data.rooms) do
			if #room.occupants < Config.Beds(room) and fits(room, uid) then
				local before = roomIncome(room)
				table.insert(room.occupants, uid)
				local gain = roomIncome(room) - before
				table.remove(room.occupants)
				if gain > bestGain then
					bestGain, bestRoom = gain, room
				end
			end
		end
		if bestRoom then
			table.insert(bestRoom.occupants, uid)
		end
	end

	-- one pass of swaps between rooms
	local rooms = data.rooms
	for a = 1, #rooms do
		for b = a + 1, #rooms do
			local ra, rb = rooms[a], rooms[b]
			for i = 1, #ra.occupants do
				for j = 1, #rb.occupants do
					if genderOf(ra.occupants[i]) ~= genderOf(rb.occupants[j]) and (#ra.occupants > 1 or #rb.occupants > 1) then
						continue
					end
					local before = roomIncome(ra) + roomIncome(rb)
					ra.occupants[i], rb.occupants[j] = rb.occupants[j], ra.occupants[i]
					if roomIncome(ra) + roomIncome(rb) <= before + 1e-6 then
						ra.occupants[i], rb.occupants[j] = rb.occupants[j], ra.occupants[i]
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local Actions = {}

function Actions.pull(player, data, args)
	local banner = Config.BannerById[args.banner]
	local count = args.count == 10 and 10 or 1
	if not banner then
		return { ok = false }
	end
	local cost = Config.PullCost(banner, countStudents(data)) * count
	if count == 10 then
		cost = math.floor(cost * 0.9) -- 10% off multi-pull
	end
	if data.cash < cost then
		return { ok = false, err = "Not enough cash!" }
	end
	if countStudents(data) + count > Config.MaxStudents then
		return { ok = false, err = "Your roster is full! Expel some students first." }
	end
	spend(data, cost)
	local results = doPulls(player, data, banner, count)
	return { ok = true, results = results }
end

function Actions.daily(player, data)
	if os.time() - data.lastDaily < Config.DailyCooldown then
		return { ok = false, err = "Daily admission not ready yet." }
	end
	local results, err = doPulls(player, data, Config.BannerById[Config.DailyFreeBanner], 1)
	if not results then
		return { ok = false, err = err }
	end
	data.lastDaily = os.time()
	return { ok = true, results = results }
end

function Actions.assign(player, data, args)
	local uid, roomIndex = args.uid, args.room
	if typeof(uid) ~= "string" or typeof(roomIndex) ~= "number" then
		return { ok = false }
	end
	local room = data.rooms[roomIndex]
	if not room or not data.students[uid] then
		return { ok = false }
	end
	local current = roomOf(data, uid)
	if current == roomIndex then
		return { ok = true }
	end
	if #room.occupants >= Config.Beds(room) then
		return { ok = false, err = "That room is full. Upgrade or expand it for more beds!" }
	end
	local gender = SchoolMath.roomGender(data, roomIndex)
	if gender and gender ~= Config.StudentById[data.students[uid].id].gender then
		return { ok = false, err = gender == "F" and "That's a girls' room!" or "That's a boys' room!" }
	end
	removeFromRoom(data, uid)
	table.insert(room.occupants, uid)
	return { ok = true }
end

function Actions.unassign(player, data, args)
	if typeof(args.uid) ~= "string" then
		return { ok = false }
	end
	removeFromRoom(data, args.uid)
	return { ok = true }
end

function Actions.livingItem(player, data, args)
	local item = typeof(args.id) == "string" and Config.LivingItemById[args.id]
	if not item or data.livingItems[item.id] then
		return { ok = false }
	end
	if not data.facilities.living then
		return { ok = false, err = "Build a Living Room first (floor plans board)." }
	end
	if item.needs and not data.livingItems[item.needs] then
		return { ok = false, err = "Needs the " .. Config.LivingItemById[item.needs].name .. " first." }
	end
	if not spend(data, item.cost) then
		return { ok = false, err = "Not enough cash!" }
	end
	data.livingItems[item.id] = true
	return { ok = true }
end

function Actions.houseGender(player, data, args)
	if not Config.HouseGenders[args.value] then
		return { ok = false }
	end
	data.houseGender = args.value
	return { ok = true }
end

function Actions.autoArrange(player, data)
	autoArrange(player, data)
	return { ok = true }
end

function Actions.expel(player, data, args)
	local s = typeof(args.uid) == "string" and data.students[args.uid]
	if not s then
		return { ok = false }
	end
	local def = Config.StudentById[s.id]
	local value = Config.Rarities[def.rarity].expel * (s.shiny and 3 or 1)
	removeFromRoom(data, args.uid)
	data.students[args.uid] = nil
	for key in pairs(data.bonds) do
		local x, y = string.match(key, "^(.-)|(.*)$")
		if x == args.uid or y == args.uid then
			data.bonds[key] = nil
		end
	end
	data.cash += value
	return { ok = true, value = value }
end

-- Floor layout board: build a dorm or facility in a chosen cell
function Actions.build(player, data, args)
	local floor, side, row = args.floor, args.side, args.row
	if args.kind == "dorm" then
		local index = #data.rooms + 1
		if index > Config.MaxRooms then
			return { ok = false, err = "You have the most dorm rooms a house can hold!" }
		end
		local size = args.big == true and 2 or 1
		if not House.isFree(data, floor, side, row, size) then
			return { ok = false, err = size == 2 and "A big room needs this cell and the one behind it free." or "That spot is taken." }
		end
		local cost = Config.RoomUnlockCost(index) + (size == 2 and Config.ExpandCost(index) or 0)
		if not spend(data, cost) then
			return { ok = false, err = "Not enough cash!" }
		end
		table.insert(data.rooms, { tier = 1, size = size, occupants = {} })
		data.layout["r" .. index] = { floor = floor, side = side, row = row }
		return { ok = true }
	elseif args.kind == "facility" then
		local f = typeof(args.id) == "string" and Config.FacilityById[args.id]
		if not f or data.facilities[f.id] then
			return { ok = false }
		end
		if not House.isFree(data, floor, side, row, 1) then
			return { ok = false, err = "That spot is taken." }
		end
		if not spend(data, f.cost) then
			return { ok = false, err = "Not enough cash!" }
		end
		data.facilities[f.id] = true
		data.layout["fac:" .. f.id] = { floor = floor, side = side, row = row }
		return { ok = true }
	end
	return { ok = false }
end

function Actions.expandRoom(player, data, args)
	local index = typeof(args.room) == "number" and args.room
	local room = index and data.rooms[index]
	if not room then
		return { ok = false }
	end
	local newRow = House.expandRow(data, index)
	if not newRow then
		return { ok = false, err = "There's no empty cell next to this room." }
	end
	if not spend(data, Config.ExpandCost(index)) then
		return { ok = false, err = "Not enough cash!" }
	end
	room.size = 2
	data.layout["r" .. index].row = newRow
	return { ok = true }
end

function Actions.buyFloor(player, data)
	local n = House.floorCount(data) + 1
	if n > Config.MaxFloors then
		return { ok = false, err = "Your house is as tall as it gets!" }
	end
	if not spend(data, Config.FloorCost(n)) then
		return { ok = false, err = "Not enough cash!" }
	end
	data.floors = n
	AnnounceEv:FireAllClients({ player = player.DisplayName, floor = n })
	return { ok = true }
end

function Actions.upgradeRoom(player, data, args)
	local room = typeof(args.room) == "number" and data.rooms[args.room]
	if not room then
		return { ok = false }
	end
	local cost = Config.RoomUpgradeCost(args.room, room.tier + 1)
	if not cost then
		return { ok = false, err = "Already max tier!" }
	end
	if not spend(data, cost) then
		return { ok = false, err = "Not enough cash!" }
	end
	room.tier += 1
	return { ok = true }
end

-- build mode: paint an area's walls / floor / roof
function Actions.paint(player, data, args)
	local area = typeof(args.area) == "string" and House.validArea(data, args.area)
	local surfacePart = args.part
	if not area or typeof(surfacePart) ~= "string" or not table.find(area.parts, surfacePart) then
		return { ok = false }
	end
	local style = typeof(args.style) == "string" and Config.StyleById[surfacePart][args.style]
	if not style then
		return { ok = false }
	end
	if House.style(data, area.key, surfacePart).id == style.id then
		return { ok = true }
	end
	if not spend(data, style.cost) then
		return { ok = false, err = "Not enough cash!" }
	end
	data.styles[area.key] = data.styles[area.key] or {}
	data.styles[area.key][surfacePart] = style.id
	return { ok = true }
end

-- your room: buy a piece of furniture, or show/hide one you own
function Actions.furniture(player, data, args)
	local f = typeof(args.id) == "string" and Config.FurnitureById[args.id]
	if not f then
		return { ok = false }
	end
	local owned = data.furniture[f.id]
	if owned == nil then
		if not spend(data, f.cost) then
			return { ok = false, err = "Not enough cash!" }
		end
		data.furniture[f.id] = true
	else
		data.furniture[f.id] = not owned
	end
	return { ok = true }
end

function Actions.home(player)
	local s = session[player]
	if not s or not s.plot or not player.Character then
		return { ok = false }
	end
	if not s.plot.rooms then
		PlotService.Render(s.plot, DataService.Get(player), s.totals)
	end
	player.Character:PivotTo(PlotService.MyRoomCFrame(s.plot))
	return { ok = true }
end

function Actions.like(player, data, args)
	local target = typeof(args.userId) == "number" and Players:GetPlayerByUserId(args.userId)
	if not target or target == player then
		return { ok = false, err = "You can't like your own house 😉" }
	end
	local key = "u" .. target.UserId
	if os.time() - (data.likedAt[key] or 0) < Config.LikeCooldown then
		return { ok = false, err = "You already liked this house today!" }
	end
	local tdata = DataService.Get(target)
	if not tdata then
		return { ok = false }
	end
	data.likedAt[key] = os.time()
	tdata.likes += 1
	-- being liked pays: one minute of the target's income
	local bonus = math.max(100, math.floor((session[target].totals and session[target].totals.income or 0) * 60))
	tdata.cash += bonus
	notify(target, string.format("❤ %s liked your house! +$%s", player.DisplayName, SchoolMath.format(bonus)), "like")
	-- liker gets a small tip so liking feels good
	data.cash += 50
	pushState(target)
	return { ok = true }
end

function Actions.visit(player, data, args)
	local target = typeof(args.userId) == "number" and Players:GetPlayerByUserId(args.userId) or player
	local s = session[target]
	if not s or not s.plot or not player.Character then
		return { ok = false }
	end
	player.Character:PivotTo(PlotService.SpawnCFrame(s.plot))
	return { ok = true }
end

-- client asks for a fresh snapshot once its UI is ready
function Actions.state()
	return { ok = true }
end

function Actions.tutorialDone(player, data)
	data.tutorialDone = true
	return { ok = true }
end

local NO_STATE_PUSH = { visit = true, home = true }
local cooldown = {}

ActionFn.OnServerInvoke = function(player, action, args)
	local data = DataService.Get(player)
	local handler = typeof(action) == "string" and Actions[action]
	if not data or not handler then
		return { ok = false }
	end
	local now = os.clock()
	if cooldown[player] and now - cooldown[player] < 0.08 then
		return { ok = false, err = "Slow down!" }
	end
	cooldown[player] = now
	local ok, result = pcall(handler, player, data, typeof(args) == "table" and args or {})
	if not ok then
		warn("[BST] action error", action, result)
		return { ok = false, err = "Something went wrong." }
	end
	if result.ok and not NO_STATE_PUSH[action] then
		pushState(player)
	end
	return result
end

---------------------------------------------------------------------------
-- Monetization
---------------------------------------------------------------------------
local ProductHandlers = {}
local function product(key, fn)
	local id = Config.Products[key]
	if id and id ~= 0 then
		ProductHandlers[id] = fn
	end
end
product("RoyalPull", function(player, data)
	return doPulls(player, data, Config.BannerById.royal, 1)
end)
product("RoyalPull10", function(player, data)
	return doPulls(player, data, Config.BannerById.royal, 10)
end)
product("CashSmall", function(player, data)
	local amount = math.max(5000, math.floor(session[player].totals.income * 600))
	data.cash += amount
	notify(player, "💰 +$" .. SchoolMath.format(amount), "cash")
	return true
end)
product("DoubleOffline", function(player, data)
	local amount = session[player].offlinePending or 0
	data.cash += amount
	session[player].offlinePending = 0
	notify(player, "💰 Doubled! +$" .. SchoolMath.format(amount), "cash")
	return true
end)

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and DataService.Get(player)
	local handler = ProductHandlers[receipt.ProductId]
	if not data or not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, result = pcall(handler, player, data)
	if not ok or not result then
		if player then
			notify(player, "Purchase couldn't be applied yet, it will retry.", "error")
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if typeof(result) == "table" then
		PullResultEv:FireClient(player, result)
	end
	pushState(player)
	DataService.Save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased or not session[player] then
		return
	end
	for key, id in pairs(Config.GamePasses) do
		if id == passId then
			session[player].passes[key] = true
			notify(player, "🎉 Thanks! " .. key .. " unlocked.", "cash")
		end
	end
	pushState(player)
end)

---------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------
local function refreshFriends()
	local list = Players:GetPlayers()
	for _, p in ipairs(list) do
		local s = session[p]
		if s then
			local n = 0
			for _, other in ipairs(list) do
				if other ~= p and s.friendCache[other.UserId] == nil then
					local ok, isFriend = pcall(p.IsFriendsWith, p, other.UserId)
					s.friendCache[other.UserId] = ok and isFriend or false
				end
				if other ~= p and s.friendCache[other.UserId] then
					n += 1
				end
			end
			if n ~= s.friends then
				if n > s.friends then
					notify(p, string.format("👯 Friend boost! +%d%% income", math.floor(math.min(n * Config.FriendBoostEach, Config.FriendBoostMax) * 100)), "cash")
				end
				s.friends = n
				pushState(p)
			end
		end
	end
end

local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local inc = Instance.new("IntValue")
	inc.Name = "Income"
	inc.Parent = ls
	local likes = Instance.new("IntValue")
	likes.Name = "Likes"
	likes.Parent = ls
	ls.Parent = player

	local data = DataService.Load(player)
	if not player.Parent then
		DataService.Profiles[player] = nil
		return
	end
	local plot = PlotService.Claim(player)
	if not plot then
		player:Kick("This server is full! Please join another server.")
		return
	end

	local s = { plot = plot, passes = {}, friends = 0, friendCache = {}, mult = 1, dirty = true, offlinePending = 0 }
	session[player] = s
	for key in pairs(Config.GamePasses) do
		s.passes[key] = passOwned(player, key)
	end
	recompute(player)

	-- idle earnings while away
	if data.lastOnline > 0 then
		local away = math.min(os.time() - data.lastOnline, Config.OfflineMaxSeconds)
		if away > 60 then
			local earned = math.floor(s.totals.income * away * Config.OfflineRate)
			if earned > 0 then
				data.cash += earned
				data.totalEarned += earned
				s.offlinePending = earned
				task.delay(3, function()
					NotifyEv:FireClient(player, { kind = "welcomeBack", amount = earned, seconds = away }, "welcome")
				end)
			end
		end
	end
	data.lastOnline = os.time()

	-- you live here: spawn in your own room once the house is built
	local function onCharacter(char)
		local start = os.clock()
		repeat
			task.wait(0.2)
		until plot.rooms or os.clock() - start > 5
		if char.Parent then
			char:PivotTo(plot.rooms and PlotService.MyRoomCFrame(plot) or PlotService.SpawnCFrame(plot))
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	pushState(player)
	refreshFriends()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	local s = session[player]
	session[player] = nil
	cooldown[player] = nil
	if s and s.plot then
		PlotService.Release(s.plot)
	end
	DataService.Release(player)
	refreshFriends()
end)

---------------------------------------------------------------------------
-- Income tick
---------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for player, s in pairs(session) do
			local data = DataService.Get(player)
			if data and s.totals then
				local inc = s.totals.income
				data.cash += inc
				data.totalEarned += inc
				local ls = player:FindFirstChild("leaderstats")
				if ls then
					ls.Cash.Value = "$" .. SchoolMath.format(data.cash)
				end
				TickEv:FireClient(player, data.cash, inc)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Bonds: roommates grow closer (or apart) depending on their vibe
---------------------------------------------------------------------------
local function tickBonds(data)
	for _, room in ipairs(data.rooms) do
		local occ = room.occupants
		for a = 1, #occ do
			for b = a + 1, #occ do
				local sa, sb = data.students[occ[a]], data.students[occ[b]]
				if sa and sb then
					local v = SchoolMath.vibe(Config.StudentById[sa.id], Config.StudentById[sb.id])
					local key = Config.BondKey(occ[a], occ[b])
					local before = data.bonds[key] or 0
					local after = math.clamp(before + (v * 100 - 50) * Config.BondPerTick, Config.BondMin, Config.BondMax)
					data.bonds[key] = after
				end
			end
		end
	end
end

-- students who love the same living room item hang out there and bond a little
local function tickHangouts(data)
	if not data.facilities.living then
		return
	end
	local housed = {}
	for _, room in ipairs(data.rooms) do
		for _, uid in ipairs(room.occupants) do
			table.insert(housed, uid)
		end
	end
	for itemId in pairs(data.livingItems) do
		local item = Config.LivingItemById[itemId]
		local fans = {}
		for _, uid in ipairs(housed) do
			local def = Config.StudentById[data.students[uid].id]
			for _, t in ipairs(def.tags) do
				if item and table.find(item.tags, t) then
					table.insert(fans, uid)
					break
				end
			end
		end
		for _ = 1, math.min(4, #fans // 2) do
			local a, b = fans[math.random(1, #fans)], fans[math.random(1, #fans)]
			if a ~= b then
				local key = Config.BondKey(a, b)
				data.bonds[key] = math.clamp((data.bonds[key] or 0) + 2, Config.BondMin, Config.BondMax)
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(Config.BondTick)
		for player in pairs(session) do
			local data = DataService.Get(player)
			if data then
				tickBonds(data)
				tickHangouts(data)
				recompute(player)
				pushState(player)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Global leaderboards (need a published place with API access enabled)
---------------------------------------------------------------------------
local boardsOk, earnedStore, likesStore = pcall(function()
	return DataStoreService:GetOrderedDataStore("BST_Earned_v1"), DataStoreService:GetOrderedDataStore("BST_Likes_v1")
end)
if not boardsOk then
	earnedStore, likesStore = nil, nil
end

local nameCache = {}
local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("User" .. userId)
	return nameCache[userId]
end

local function refreshBoard(store, key, fmt)
	local rows = PlotService.Boards[key]
	local ok, pages = pcall(store.GetSortedAsync, store, false, 10)
	if not ok then
		return
	end
	local entries = pages:GetCurrentPage()
	local medals = { "🥇", "🥈", "🥉" }
	for i = 1, 10 do
		local e = entries[i]
		if e then
			local id = tonumber(string.sub(e.key, 2))
			rows[i].Text = string.format("%s %s  —  %s", medals[i] or ("#" .. i), id and nameOf(id) or e.key, fmt(e.value))
		else
			rows[i].Text = ""
		end
	end
end

task.spawn(function()
	if not earnedStore then
		return
	end
	while true do
		for player in pairs(session) do
			local data = DataService.Get(player)
			if data then
				pcall(earnedStore.SetAsync, earnedStore, "u" .. player.UserId, math.floor(data.totalEarned))
				pcall(likesStore.SetAsync, likesStore, "u" .. player.UserId, data.likes)
			end
		end
		refreshBoard(earnedStore, "earned", function(v)
			return "$" .. SchoolMath.format(v)
		end)
		refreshBoard(likesStore, "likes", function(v)
			return "❤ " .. SchoolMath.format(v)
		end)
		task.wait(90)
	end
end)
