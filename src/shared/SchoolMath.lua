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
