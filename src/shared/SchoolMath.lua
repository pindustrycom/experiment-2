-- Pure functions for satisfaction + income. Shared so the client can preview
-- exactly what the server will calculate (e.g. "how would this roommate do?").
local Config = require(script.Parent.Config)
local House = require(script.Parent.House)

local SchoolMath = {}

function SchoolMath.def(student)
	return Config.StudentById[student.id]
end

-- Vibe between two students, 0..1: the geometric mean of every tag pair
-- (multiply all pair percentages, then take the matching root).
function SchoolMath.vibe(defA, defB)
	if defA.crew and defA.crew == defB.crew then
		return Config.LaRoseVibe
	end
	local logSum, n = 0, 0
	for _, a in ipairs(defA.tags) do
		local row = Config.TagVibe[a]
		for _, b in ipairs(defB.tags) do
			logSum += math.log(row[b])
			n += 1
		end
	end
	local v = n > 0 and math.exp(logSum / n) or 0.5
	local chill = (defA.trait and defA.trait.kind == "Chill") or (defB.trait and defB.trait.kind == "Chill")
	if chill and v < 0.5 then
		v = 0.5
	end
	return v
end

function SchoolMath.vibeEmoji(v)
	if v >= 0.75 then
		return "💞"
	elseif v >= 0.58 then
		return "🙂"
	elseif v >= 0.42 then
		return "😶"
	elseif v >= 0.3 then
		return "😒"
	end
	return "💢"
end

-- satisfaction one roommate adds through vibe
function SchoolMath.vibePoints(v)
	return (v * 100 - 50) * Config.VibePoints
end

function SchoolMath.bond(data, a, b)
	return data.bonds and data.bonds[Config.BondKey(a, b)] or 0
end

-- gender a room is locked to (its first occupant), or nil when empty
function SchoolMath.roomGender(data, index, except)
	local room = data.rooms[index]
	for _, uid in ipairs(room and room.occupants or {}) do
		local s = data.students[uid]
		if s and uid ~= except then
			return Config.StudentById[s.id].gender
		end
	end
	return nil
end

local function facilityBonus(data, def)
	local mood, mult = 0, 0
	for fid, owned in pairs(data.facilities or {}) do
		local f = owned and Config.FacilityById[fid]
		if f then
			mood += f.all or 0
			if f.boost and def then
				local best = 0
				for _, t in ipairs(def.tags) do
					best = math.max(best, f.boost[t] or 0)
				end
				mood += best
			end
			mult += f.incomeMult or 0
		end
	end
	-- living room items: +boost per item that matches one of the student's tags
	if def and data.facilities and data.facilities.living then
		for itemId in pairs(data.livingItems or {}) do
			local item = Config.LivingItemById[itemId]
			if item then
				for _, t in ipairs(def.tags) do
					if table.find(item.tags, t) then
						mood += Config.LivingItemBoost
						break
					end
				end
			end
		end
	end
	return mood, mult
end

-- facilities + the furniture in your own room
function SchoolMath.facilityIncomeMult(data)
	local _, mult = facilityBonus(data, nil)
	for fid in pairs(data.furniture or {}) do
		local f = Config.FurnitureById[fid]
		if f then
			mult += f.incomeMult or 0
		end
	end
	return 1 + mult
end

-- Things that depend on the whole roster, computed once and shared by every
-- room calculation in a pass (totals, auto-arrange).
function SchoolMath.context(data)
	local ctx = { siblings = {}, crewMult = 1, floorTraits = false }
	for key, score in pairs(data.bonds or {}) do
		if score >= 95 then
			local a, b = string.match(key, "^(.-)|(.*)$")
			ctx.siblings[a] = ctx.siblings[a] or {}
			ctx.siblings[b] = ctx.siblings[b] or {}
			table.insert(ctx.siblings[a], b)
			table.insert(ctx.siblings[b], a)
		end
	end
	local owned = {}
	for _, s in pairs(data.students) do
		owned[s.id] = true
		local def = Config.StudentById[s.id]
		if def and def.trait and def.trait.kind == "Floor" then
			ctx.floorTraits = true
		end
	end
	for crew, ids in pairs(Config.Crews) do
		local all = #ids > 0
		for _, id in ipairs(ids) do
			all = all and owned[id] == true
		end
		if all then
			ctx.crewMult += Config.CrewBonus[crew] or 0
		end
	end
	return ctx
end

function SchoolMath.crewComplete(data, crew)
	for _, id in ipairs(Config.Crews[crew] or {}) do
		local found = false
		for _, s in pairs(data.students) do
			if s.id == id then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	return true
end

-- satisfaction from Floor traits (e.g. Greg) living on the same floor as room `index`
local function floorAura(data, index, occupantUids)
	local floor = House.floorOf(data, "r" .. index)
	local total = 0
	for j, room in ipairs(data.rooms) do
		local list = j == index and occupantUids or room.occupants
		if House.floorOf(data, "r" .. j) == floor then
			for _, uid in ipairs(list) do
				local s = data.students[uid]
				local def = s and Config.StudentById[s.id]
				if def and def.trait and def.trait.kind == "Floor" then
					total += def.trait.value
				end
			end
		end
	end
	return total
end

-- students housed anywhere who can't stand `uid` (bond rivals or awful vibe)
local function rivalCount(data, uid, def)
	local n = 0
	for _, room in ipairs(data.rooms) do
		for _, other in ipairs(room.occupants) do
			if other ~= uid then
				local s = data.students[other]
				if s and (SchoolMath.bond(data, uid, other) < 0 or SchoolMath.vibe(def, Config.StudentById[s.id]) < 0.3) then
					n += 1
				end
			end
		end
	end
	return n
end

-- index: room number in data.rooms. occupantUids: students living together
-- (pass a modified list to preview a move). ctx: SchoolMath.context(data),
-- built on demand. Returns
-- { students = { [uid] = { sat, income, parts } }, satisfaction, income }
function SchoolMath.room(data, index, occupantUids, globalMult, ctx)
	globalMult = globalMult or 1
	ctx = ctx or SchoolMath.context(data)
	local tier = data.rooms[index] and data.rooms[index].tier or 1
	local tierInfo = Config.RoomTiers[tier] or Config.RoomTiers[1]
	local decor = tierInfo.decor + House.roomDecor(data, index)
	local defs = {}
	for _, uid in ipairs(occupantUids) do
		local s = data.students[uid]
		if s then
			table.insert(defs, { uid = uid, s = s, def = SchoolMath.def(s) })
		end
	end

	local peace, goldMult, moodAura = false, 1, {}
	for _, d in ipairs(defs) do
		local t = d.def.trait
		if t then
			if t.kind == "Peace" then
				peace = true
			elseif t.kind == "Gold" then
				if not t.needs or (data.livingItems and data.livingItems[t.needs]) then
					goldMult *= t.value
				end
			elseif t.kind == "Mood" then
				moodAura[d.uid] = t.value
			end
		end
	end
	local floorBonus = ctx.floorTraits and floorAura(data, index, occupantUids) or 0

	local result = { students = {}, satisfaction = 0, income = 0 }
	local facMult = SchoolMath.facilityIncomeMult(data)
	local roommates = #defs - 1
	local here = {}
	for _, d in ipairs(defs) do
		here[d.uid] = true
	end

	for _, d in ipairs(defs) do
		-- parts explain the score on the satisfaction board
		local parts = { base = Config.BaseSatisfaction, decor = decor, facilities = 0, vibe = 0, bonds = 0, friends = floorBonus, trait = 0 }
		if data.buffs and (data.buffs[d.uid] or 0) > os.time() then
			parts.friends += Config.OutingBuff.sat
		end
		parts.facilities = facilityBonus(data, d.def)
		for _, other in ipairs(defs) do
			if other.uid ~= d.uid then
				local v = SchoolMath.vibe(d.def, other.def)
				if peace and v < 0.5 then
					v = 0.5
				end
				parts.vibe += SchoolMath.vibePoints(v)
				local level = Config.BondLevel(SchoolMath.bond(data, d.uid, other.uid))
				if not (peace and level.sat < 0) then
					parts.bonds += level.sat
				end
				parts.friends += moodAura[other.uid] or 0
			end
		end
		for _, sib in ipairs(ctx.siblings[d.uid] or {}) do
			if not here[sib] and data.students[sib] then
				parts.bonds -= Config.SiblingSplitPenalty
			end
		end
		local t = d.def.trait
		local selfMult = 1
		if t then
			if t.kind == "Loner" and roommates == 0 then
				parts.trait += t.value
			elseif t.kind == "Social" then
				parts.trait += t.value * roommates
			elseif t.kind == "Rivals" then
				selfMult += t.value * rivalCount(data, d.uid, d.def)
			end
		end
		local sat = parts.base + parts.decor + parts.facilities + parts.vibe + parts.bonds + parts.friends + parts.trait
		sat = math.clamp(sat, 0, 100)

		local rarity = Config.Rarities[d.def.rarity]
		local base = rarity.income * (d.s.shiny and Config.ShinyMultiplier or 1) * SchoolMath.glowMult(d.s) * SchoolMath.eventMult(d.def)
		local income = base * (0.25 + sat / 50) * goldMult * facMult * globalMult * ctx.crewMult * selfMult
		result.students[d.uid] = { sat = sat, income = income, parts = parts }
		result.satisfaction += sat
		result.income += income
	end
	if #defs > 0 then
		result.satisfaction /= #defs
	end
	return result
end

-- income multiplier from a student's glow-up level and mutation
function SchoolMath.glowMult(s)
	local mut = s.mut and Config.MutationById[s.mut]
	return (1 + Config.GlowIncome * ((s.lv or 1) - 1)) * (mut and mut.mult or 1)
end

-- income multiplier from the school event running now
function SchoolMath.eventMult(def, now)
	local ev = Config.EventAt(now or os.time())
	if ev and ev.tags then
		for _, t in ipairs(def.tags) do
			if table.find(ev.tags, t) then
				return ev.mult
			end
		end
	end
	return 1
end

-- The Applicants board for a stock window: { { id, shiny, price } ... }.
-- Deterministic, so the client shows exactly what the server sells.
-- salt > 0 is a personal restock; lucky makes rare applicants likelier.
function SchoolMath.applicants(window, salt, lucky, owned)
	local rng = Random.new(window * 7919 + (salt or 0) * 104729 + (lucky and 31 or 0))
	local weights = table.clone(Config.ApplicantWeights)
	if lucky then
		for _, r in ipairs({ "Epic", "Legendary", "Mythic" }) do
			weights[r] *= Config.LuckyHourRare
		end
	end
	local total = 0
	for _, r in ipairs(Config.RarityOrder) do
		total += weights[r]
	end
	local growth = Config.PullCostGrowth ^ math.max(0, (owned or 0) - 2)
	local list = {}
	local ev = Config.EventAt(window * Config.RestockSeconds)
	for slot = 1, Config.ApplicantSlots do
		local def
		if slot == 1 and ev and ev.student then
			def = Config.StudentById[ev.student]
		else
			local pick, rarity = rng:NextNumber() * total, "Common"
			for _, r in ipairs(Config.RarityOrder) do
				pick -= weights[r]
				if pick <= 0 then
					rarity = r
					break
				end
			end
			local pool = Config.StudentsByRarity[rarity]
			def = pool[rng:NextInteger(1, #pool)]
		end
		local shiny = rng:NextNumber() < Config.ShinyChance
		local price = Config.ApplicantPrice[def.rarity] * (shiny and Config.ApplicantShinyPrice or 1) * growth
		table.insert(list, { id = def.id, shiny = shiny, price = math.floor(price / 10 + 0.5) * 10 })
	end
	return list
end

---------------------------------------------------------------------------
-- Audit: explain what happens between students and why. The server writes
-- the log (Main.server `audit`); everything here only reads, so the client
-- and the wall board show exactly the numbers the game used.
---------------------------------------------------------------------------

-- "Tim, Pete and Sue"
function SchoolMath.joinNames(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function SchoolMath.roomIndexOf(data, uid)
	for i, room in ipairs(data.rooms) do
		if table.find(room.occupants, uid) then
			return i
		end
	end
	return nil
end

-- the student whose Peace trait stops a room from fighting, if any
function SchoolMath.roomPeace(data, occupantUids)
	for _, uid in ipairs(occupantUids) do
		local s = data.students[uid]
		local def = s and Config.StudentById[s.id]
		if def and def.trait and def.trait.kind == "Peace" then
			return def
		end
	end
	return nil
end

-- vibe two roommates actually get: SchoolMath.vibe, lifted to neutral when
-- someone in the room keeps the peace. Bonds and satisfaction both use it.
function SchoolMath.roomVibe(data, occupantUids, defA, defB)
	local v = SchoolMath.vibe(defA, defB)
	if v < 0.5 and SchoolMath.roomPeace(data, occupantUids) then
		return 0.5, true
	end
	return v, false
end

-- Vibe step by step: every tag pair, their geometric mean, and the rule that
-- replaced it (rule = "crew" or "chill"), if one did.
function SchoolMath.vibeDetail(defA, defB)
	local detail = { pairs = {}, raw = 0.5 }
	local logSum, n = 0, 0
	for _, a in ipairs(defA.tags) do
		for _, b in ipairs(defB.tags) do
			local p = Config.TagVibe[a][b]
			table.insert(detail.pairs, { a = a, b = b, p = p })
			logSum += math.log(p)
			n += 1
		end
	end
	if n > 0 then
		detail.raw = math.exp(logSum / n)
	end
	detail.final = SchoolMath.vibe(defA, defB)
	if defA.crew and defA.crew == defB.crew then
		detail.rule = "crew"
	elseif detail.final ~= detail.raw then
		detail.rule = "chill"
	end
	return detail
end

-- Everything the game knows about two students: their vibe, their bond, what
-- that does to their happiness right now and where the bond is heading.
function SchoolMath.pairReport(data, a, b)
	local sa, sb = data.students[a], data.students[b]
	if not sa or not sb then
		return nil
	end
	local defA, defB = Config.StudentById[sa.id], Config.StudentById[sb.id]
	local detail = SchoolMath.vibeDetail(defA, defB)
	local roomA, roomB = SchoolMath.roomIndexOf(data, a), SchoolMath.roomIndexOf(data, b)
	local together = roomA ~= nil and roomA == roomB
	local v, rule = detail.final, detail.rule
	local peaceBy = together and SchoolMath.roomPeace(data, data.rooms[roomA].occupants) or nil
	if peaceBy and v < 0.5 then
		v, rule = 0.5, "peace"
	end
	local score = SchoolMath.bond(data, a, b)
	local level = Config.BondLevel(score)
	local rep = {
		a = a, b = b, defA = defA, defB = defB,
		detail = detail, vibe = v, rule = rule, peaceBy = peaceBy,
		score = score, level = level,
		room = together and roomA or nil, roomA = roomA, roomB = roomB,
		vibeSat = 0, bondSat = 0, splitSat = 0, drift = 0,
	}
	if together then
		rep.vibeSat = SchoolMath.vibePoints(v)
		rep.bondSat = (peaceBy and level.sat < 0) and 0 or level.sat
		rep.drift = (v * 100 - 50) * Config.BondPerTick
	elseif score >= 95 then
		rep.splitSat = -Config.SiblingSplitPenalty
	end
	if rep.drift > 0 and score < Config.BondMax then
		for _, l in ipairs(Config.BondLevels) do
			if l.min > score then
				rep.next = l
				break
			end
		end
		rep.eta = math.ceil(((rep.next and rep.next.min or Config.BondMax) - score) / rep.drift) * Config.BondTick
	elseif rep.drift < 0 and score > Config.BondMin then
		for _, l in ipairs(Config.BondLevels) do
			if l.min < level.min then
				rep.next = l
			end
		end
		if rep.next then
			rep.eta = (math.floor((score - level.min) / -rep.drift) + 1) * Config.BondTick
		end
	end
	return rep
end

-- Every pair worth looking at: roommates first (room by room), then anyone
-- else with a history. Each entry is a SchoolMath.pairReport.
function SchoolMath.auditPairs(data)
	local list, seen = {}, {}
	for _, room in ipairs(data.rooms) do
		for i = 1, #room.occupants do
			for j = i + 1, #room.occupants do
				local rep = SchoolMath.pairReport(data, room.occupants[i], room.occupants[j])
				if rep then
					seen[Config.BondKey(rep.a, rep.b)] = true
					table.insert(list, rep)
				end
			end
		end
	end
	local rest = {}
	for key, score in pairs(data.bonds or {}) do
		if not seen[key] and score ~= 0 then
			local a, b = string.match(key, "^(.-)|(.*)$")
			local rep = a and SchoolMath.pairReport(data, a, b)
			if rep then
				table.insert(rest, rep)
			end
		end
	end
	table.sort(rest, function(x, y)
		if math.abs(x.score) ~= math.abs(y.score) then
			return math.abs(x.score) > math.abs(y.score)
		end
		return Config.BondKey(x.a, x.b) < Config.BondKey(y.a, y.b)
	end)
	for _, rep in ipairs(rest) do
		table.insert(list, rep)
	end
	return list
end

local function minutes(seconds)
	local m = math.max(1, math.floor(seconds / 60 + 0.5))
	if m >= 120 then
		return string.format("%d h", math.floor(m / 60 + 0.5))
	end
	return m .. " min"
end
SchoolMath.minutes = minutes

local SEVERITY = { bug = 1, bad = 2, warn = 3, good = 4, tip = 5, info = 6 }

-- The audit itself: walks the whole house and lists what is wrong (or about
-- to go wrong) between students, most serious first. sev is "bug" (the save
-- is inconsistent, should never happen), "bad", "warn", "good", "tip", "info".
function SchoolMath.auditChecks(data, now)
	now = now or os.time()
	local out = {}
	local function add(sev, text, room)
		table.insert(out, { sev = sev, text = text, room = room, order = #out })
	end
	local function name(uid)
		local s = data.students[uid]
		return s and Config.ShortName(Config.StudentById[s.id]) or "someone"
	end

	-- 1. is the data itself consistent?
	local roomOf = {}
	for i, room in ipairs(data.rooms) do
		if #room.occupants > Config.Beds(room) then
			add("bug", string.format("🐞 Room %d has %d students but only %d beds.", i, #room.occupants, Config.Beds(room)), i)
		end
		local gender = nil
		for _, uid in ipairs(room.occupants) do
			local s = data.students[uid]
			if not s then
				add("bug", string.format("🐞 Room %d lists a student who is no longer in the house (%s).", i, tostring(uid)), i)
			else
				if roomOf[uid] then
					add("bug", string.format("🐞 %s is listed in Room %d and Room %d at once.", name(uid), roomOf[uid], i), i)
				end
				roomOf[uid] = i
				local g = Config.StudentById[s.id].gender
				if gender and g ~= gender then
					add("bug", string.format("🐞 Room %d mixes boys and girls.", i), i)
				end
				gender = gender or g
			end
		end
	end
	local orphans, outOfRange = 0, 0
	for key, score in pairs(data.bonds or {}) do
		local a, b = string.match(key, "^(.-)|(.*)$")
		if not (a and data.students[a] and data.students[b]) then
			orphans += 1
		elseif score < Config.BondMin or score > Config.BondMax then
			outOfRange += 1
		end
	end
	if orphans > 0 then
		add("bug", string.format("🐞 %d friendship record%s belong to students who left.", orphans, orphans == 1 and "" or "s"))
	end
	if outOfRange > 0 then
		add("bug", string.format("🐞 %d friendship score%s outside %d..%d.", outOfRange, outOfRange == 1 and " is" or "s are", Config.BondMin, Config.BondMax))
	end

	-- 2. roommates
	local levels = {}
	for _, rep in ipairs(SchoolMath.auditPairs(data)) do
		local A, B = name(rep.a), name(rep.b)
		local levelName = Config.BondName(rep.level, rep.defA, rep.defB)
		if rep.score ~= 0 then
			levels[rep.level.name] = (levels[rep.level.name] or 0) + 1
		end
		local pct = math.floor(rep.vibe * 100 + 0.5)
		if rep.room then
			local each = math.floor(rep.vibeSat + rep.bondSat + 0.5)
			if rep.score < 0 and not rep.peaceBy then
				local trend = rep.drift < 0 and string.format(" Their vibe is %d%%, so it keeps getting worse.", pct) or rep.drift > 0 and string.format(" Their vibe is %d%%, so it is slowly healing (%s to Strangers).", pct, minutes(rep.eta or 0)) or ""
				add("bad", string.format("💢 Room %d: %s and %s are Rivals (%+d mood each).%s", rep.room, A, B, each, trend), rep.room)
			elseif rep.vibe < 0.42 then
				local soon = (rep.next and rep.eta) and string.format(" They drop to %s in about %s.", rep.next.name, minutes(rep.eta)) or ""
				add("warn", string.format("%s Room %d: %s and %s have a %d%% vibe (%+d mood each).%s", SchoolMath.vibeEmoji(rep.vibe), rep.room, A, B, pct, each, soon), rep.room)
			elseif rep.peaceBy and rep.detail.final < 0.42 then
				add("info", string.format("🕊 Room %d: %s and %s would clash (%d%% vibe), but %s keeps the peace.", rep.room, A, B, math.floor(rep.detail.final * 100 + 0.5), Config.ShortName(rep.peaceBy)), rep.room)
			end
		elseif rep.splitSat < 0 then
			add("bad", string.format("%s %s and %s are %s but sleep in different rooms (%d mood each). Put them together.", rep.level.emoji, A, B, levelName, rep.splitSat), rep.roomA or rep.roomB)
		end
	end

	-- 3. students on their own
	local unhoused = {}
	for uid in pairs(data.students) do
		if not roomOf[uid] then
			table.insert(unhoused, uid)
		end
	end
	table.sort(unhoused)
	if #unhoused > 0 then
		local names = {}
		for i = 1, math.min(4, #unhoused) do
			names[i] = name(unhoused[i])
		end
		if #unhoused > 4 then
			table.insert(names, (#unhoused - 4) .. " more")
		end
		add("warn", string.format("😴 %d student%s without a bed (%s). They earn $0 and make no friends.", #unhoused, #unhoused == 1 and " is" or "s are", SchoolMath.joinNames(names)))
	end

	-- 4. traits that aren't doing anything
	for uid, i in pairs(roomOf) do
		local def = Config.StudentById[data.students[uid].id]
		local t = def.trait
		local roommates = #data.rooms[i].occupants - 1
		if t and t.kind == "Loner" and roommates > 0 then
			add("tip", string.format("💡 %s gets +%d mood alone, but shares Room %d.", def.name, t.value, i), i)
		elseif t and t.kind == "Social" and roommates == 0 then
			add("tip", string.format("💡 %s gets +%d mood per roommate, but is alone in Room %d.", def.name, t.value, i), i)
		elseif t and t.kind == "Gold" and t.needs and not (data.livingItems and data.livingItems[t.needs]) then
			add("tip", string.format("💡 %s's room bonus needs a %s in the living room.", def.name, Config.LivingItemById[t.needs].name), i)
		end
	end

	-- 5. good roommates living apart (best three)
	local housed = {}
	for uid in pairs(roomOf) do
		table.insert(housed, uid)
	end
	table.sort(housed)
	local matches = {}
	for x = 1, #housed do
		for y = x + 1, #housed do
			local a, b = housed[x], housed[y]
			if roomOf[a] ~= roomOf[b] then
				local da, db = Config.StudentById[data.students[a].id], Config.StudentById[data.students[b].id]
				if da.gender == db.gender then
					local v = SchoolMath.vibe(da, db)
					if v >= 0.75 then
						table.insert(matches, { a = a, b = b, v = v })
					end
				end
			end
		end
	end
	table.sort(matches, function(p, q)
		if p.v ~= q.v then
			return p.v > q.v
		end
		return Config.BondKey(p.a, p.b) < Config.BondKey(q.a, q.b)
	end)
	for i = 1, math.min(3, #matches) do
		local m = matches[i]
		add("tip", string.format("💡 %s (Room %d) and %s (Room %d) would click: %d%% vibe.", name(m.a), roomOf[m.a], name(m.b), roomOf[m.b], math.floor(m.v * 100 + 0.5)), roomOf[m.a])
	end

	-- 6. what's going on right now
	if data.outing then
		local act = Config.ActivityById[data.outing.activity]
		local names = {}
		for _, uid in ipairs(data.outing.members) do
			if data.students[uid] then
				table.insert(names, name(uid))
			end
		end
		if act and #names > 0 then
			add("info", string.format("%s %s %s out at the %s, back in %s.", act.emoji, SchoolMath.joinNames(names), #names == 1 and "is" or "are", act.name, minutes(math.max(0, data.outing.returnAt - now))))
		end
	end
	local buffed, buffEnd = 0, 0
	for uid, untilTime in pairs(data.buffs or {}) do
		if data.students[uid] and untilTime > now then
			buffed += 1
			buffEnd = math.max(buffEnd, untilTime)
		end
	end
	if buffed > 0 then
		add("info", string.format("🤩 %d student%s +%d mood from a great outing (up to %s left).", buffed, buffed == 1 and " has" or "s have", Config.OutingBuff.sat, minutes(buffEnd - now)))
	end
	local bits = {}
	for i = #Config.BondLevels, 1, -1 do
		local l = Config.BondLevels[i]
		if levels[l.name] and l.name ~= "Strangers" then
			table.insert(bits, string.format("%s %d %s", l.emoji, levels[l.name], l.name))
		end
	end
	if #bits > 0 then
		add("info", "Friendships in the house: " .. table.concat(bits, "  "))
	end

	local trouble = false
	for _, c in ipairs(out) do
		trouble = trouble or SEVERITY[c.sev] <= SEVERITY.warn
	end
	if not trouble then
		add("good", "✅ No problems between your students right now.")
	end
	table.sort(out, function(p, q)
		if SEVERITY[p.sev] ~= SEVERITY[q.sev] then
			return SEVERITY[p.sev] < SEVERITY[q.sev]
		end
		return p.order < q.order
	end)
	return out
end

-- Log entries keep { uid, studentId } pairs so they still read after a
-- student has left.
local function refName(ref)
	local def = ref and Config.StudentById[ref[2]]
	return def and Config.ShortName(def) or "someone"
end

local function refNames(list)
	local names = {}
	for _, ref in ipairs(list or {}) do
		table.insert(names, refName(ref))
	end
	return SchoolMath.joinNames(names)
end

local function activityOf(e)
	return Config.ActivityById[e.act] or { name = "outing", emoji = "📷" }
end

local JOINED = { pull = "Admission pull.", daily = "Daily free admission.", hire = "Hired from the Applicants board.", trade = "Arrived in a trade.", robux = "Royal Admission." }

-- One log entry as { text, why, tone } (tone = "good" / "bad" / "info").
function SchoolMath.auditLine(e)
	local k = e.k
	if k == "level" then
		local l0, l1 = Config.BondLevel(e.s0), Config.BondLevel(e.s1)
		local up = e.s1 > e.s0
		local defA, defB = Config.StudentById[e.a[2]], Config.StudentById[e.b[2]]
		local text = string.format("%s %s and %s %s %s", l1.emoji, refName(e.a), refName(e.b), up and "became" or "dropped to", Config.BondName(l1, defA, defB))
		local why
		local cause = e.c or ""
		local item = string.match(cause, "^item:(.+)$")
		local act, outcome = string.match(cause, "^out:(.-):(.+)$")
		if item then
			local it = Config.LivingItemById[item]
			why = string.format("They hung out at the %s in the living room (%+d bond).", it and it.name or item, math.floor((e.d or 0) + 0.5))
		elseif act then
			local a, o = Config.ActivityById[act], Config.Outcomes[outcome]
			why = string.format("%s at the %s (%+d bond).", o and o.name or "Outing", a and a.name or act, math.floor((e.d or 0) + 0.5))
		else
			why = string.format("Roommates in Room %s with a %d%% vibe, so their bond moves %+.1f every %d min.", tostring(e.r or "?"), e.v or 50, e.d or 0, Config.BondTick // 60)
		end
		why ..= string.format(" Bond %d → %d (%s → %s), worth %+d mood each while they share a room.", math.floor(e.s0 + 0.5), math.floor(e.s1 + 0.5), l0.name, l1.name, l1.sat)
		return { text = text, why = why, tone = up and "good" or "bad" }
	elseif k == "out" then
		local act = activityOf(e)
		local picks = {}
		for _, p in ipairs(e.picks or {}) do
			table.insert(picks, string.format("%s (%d%% vibe, %s)", refName(p.s), p.v, Config.BondLevel(p.b).name))
		end
		return {
			text = string.format("%s %s went to the %s%s", act.emoji, refNames(e.m), act.name, e.auto and "" or " (you sent them)"),
			why = string.format("%s led and took the students they get along with best: %s. The %s had a %d%% chance: %d of their tags like it.", refName(e.lead), table.concat(picks, ", "), act.name, e.pc or 0, e.tags or 0),
			tone = "info",
		}
	elseif k == "back" then
		local act = activityOf(e)
		local o = Config.Outcomes[e.o] or Config.Outcomes.fun
		local why = string.format("Their average vibe was %d%%, which gave a %d%% chance of a great time and %d%% of an awkward one%s. Every pair %+d bond%s.", e.v or 50, e.pg or 0, e.pa or 0, e.pref and (" (+10% great: someone loves the " .. act.name .. ")") or "", math.floor((e.gain or 0) + 0.5), e.o == "great" and string.format(", and everyone gets +%d mood for %s", Config.OutingBuff.sat, minutes(Config.OutingBuff.seconds)) or "")
		return { text = string.format("📸 %s came back from the %s: %s %s", refNames(e.m), act.name, o.name, o.emoji), why = why, tone = e.o == "awkward" and "bad" or "good" }
	elseif k == "tick" then
		local bits = {}
		local function mover(m, label)
			if m then
				table.insert(bits, string.format("%s: %s and %s %+.1f (%d%% vibe, Room %d%s).", label, refName(m.a), refName(m.b), m.d, m.v, m.r, m.peace and ", peace kept" or ""))
			end
		end
		mover(e.best, "Closest")
		if e.worst and (not e.best or e.worst.d < e.best.d) then
			mover(e.worst, e.worst.d < 0 and "Worst" or "Slowest")
		end
		for _, h in ipairs(e.hang or {}) do
			local it = Config.LivingItemById[h.item]
			table.insert(bits, string.format("%s %s and %s hung out at the %s (+%d).", it and it.emoji or "🛋", refName(h.a), refName(h.b), it and it.name or "living room", h.d or 2))
		end
		local text = string.format("⏱ Roommates: %d pair%s grew closer, %d drifted apart", e.up or 0, e.up == 1 and "" or "s", e.down or 0)
		if #(e.hang or {}) > 0 then
			text ..= string.format(", %d living room hangout%s", #e.hang, #e.hang == 1 and "" or "s")
		end
		return { text = text, why = table.concat(bits, " "), tone = "info" }
	elseif k == "move" then
		local who = refName(e.s)
		local text
		if e.to and e.to > 0 then
			text = (e.from and e.from > 0) and string.format("🛏 %s moved from Room %d to Room %d", who, e.from, e.to) or string.format("🛏 %s moved into Room %d", who, e.to)
		else
			text = string.format("🛏 %s moved out of Room %d", who, e.from or 0)
		end
		local why
		if not (e.to and e.to > 0) then
			why = (e.by == "plan" and "The room got smaller and lost a bed. " or "") .. "Without a bed they earn nothing and their friendships stop growing."
		elseif #(e.with or {}) == 0 then
			why = "Alone in the room for now."
		else
			local bits = {}
			for _, w in ipairs(e.with) do
				table.insert(bits, string.format("%s (%d%% %s)", refName(w.s), w.v, SchoolMath.vibeEmoji(w.v / 100)))
			end
			why = "Now rooms with " .. SchoolMath.joinNames(bits) .. "."
		end
		return { text = text, why = why, tone = "info" }
	elseif k == "auto" then
		return {
			text = string.format("🪄 Auto-arrange moved %d student%s", e.n or 0, e.n == 1 and "" or "s"),
			why = string.format("Average happiness went from %d%% to %d%%, income from $%s to $%s a second.", math.floor((e.sat0 or 0) + 0.5), math.floor((e.sat1 or 0) + 0.5), SchoolMath.format(e.inc0 or 0), SchoolMath.format(e.inc1 or 0)),
			tone = (e.sat1 or 0) >= (e.sat0 or 0) and "good" or "bad",
		}
	elseif k == "join" then
		return { text = string.format("🎓 %s enrolled", refNames(e.list)), why = JOINED[e.by] or "", tone = "info" }
	elseif k == "leave" then
		local why = (e.bonds or 0) == 0 and "They had no friendships yet." or string.format("%d friendship%s ended with them%s.", e.bonds, e.bonds == 1 and "" or "s", e.top and string.format(" (closest: %s with %s)", e.top.level, refName(e.top.s)) or "")
		return { text = string.format("👋 %s %s", refName(e.s), e.by == "trade" and "was traded away" or "was expelled"), why = why, tone = (e.bonds or 0) > 0 and "bad" or "info" }
	end
	return { text = "❔ " .. tostring(k), why = "", tone = "info" }
end

-- which filter chip an entry belongs to ("routine" is left out of All)
SchoolMath.AuditGroups = { level = "bonds", tick = "routine", out = "outings", back = "outings", move = "moves", auto = "moves", join = "moves", leave = "moves" }

function SchoolMath.totals(data, globalMult)
	local income, satSum, housed = 0, 0, 0
	local rooms = {}
	local ctx = SchoolMath.context(data)
	for i, room in ipairs(data.rooms) do
		local r = SchoolMath.room(data, i, room.occupants, globalMult, ctx)
		rooms[i] = r
		income += r.income
		satSum += r.satisfaction * #room.occupants
		housed += #room.occupants
	end
	return {
		income = income,
		satisfaction = housed > 0 and satSum / housed or 0,
		housed = housed,
		rooms = rooms,
	}
end

function SchoolMath.moodEmoji(sat)
	if sat >= 85 then
		return "😍"
	elseif sat >= 65 then
		return "😊"
	elseif sat >= 45 then
		return "😐"
	elseif sat >= 25 then
		return "😟"
	end
	return "😡"
end

local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
function SchoolMath.format(n)
	n = math.floor(n)
	local i = 1
	local v = n
	while math.abs(v) >= 1000 and i < #suffixes do
		v /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(n)
	end
	return string.format(v >= 100 and "%.0f%s" or "%.1f%s", v, suffixes[i])
end

return SchoolMath
