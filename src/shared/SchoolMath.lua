-- Pure functions for satisfaction + income. Shared so the client can preview
-- exactly what the server will calculate (e.g. "how would this roommate do?").
local Config = require(script.Parent.Config)

local SchoolMath = {}

function SchoolMath.def(student)
	return Config.StudentById[student.id]
end

function SchoolMath.pairChemistry(defA, defB)
	local row = Config.Chemistry[defA.personality]
	return (row and row[defB.personality]) or 0
end

local function facilityBonus(data, personality)
	local mood, mult = 0, 0
	for fid, owned in pairs(data.facilities or {}) do
		local f = owned and Config.FacilityById[fid]
		if f then
			mood += f.all or 0
			if f.boost and f.boost[personality] then
				mood += f.boost[personality]
			end
			mult += f.incomeMult or 0
		end
	end
	return mood, mult
end

function SchoolMath.facilityIncomeMult(data)
	local _, mult = facilityBonus(data, "")
	return 1 + mult
end

-- occupantUids: list of student uids living together. Returns
-- { students = { [uid] = { sat, income } }, satisfaction, income }
function SchoolMath.room(data, tier, occupantUids, globalMult)
	globalMult = globalMult or 1
	local tierInfo = Config.RoomTiers[tier] or Config.RoomTiers[1]
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
				goldMult *= t.value
			elseif t.kind == "Mood" then
				moodAura[d.uid] = t.value
			end
		end
	end

	local result = { students = {}, satisfaction = 0, income = 0 }
	local facMult = SchoolMath.facilityIncomeMult(data)
	local roommates = #defs - 1

	for _, d in ipairs(defs) do
		local sat = Config.BaseSatisfaction + tierInfo.decor
		local fMood = facilityBonus(data, d.def.personality)
		sat += fMood
		for _, other in ipairs(defs) do
			if other.uid ~= d.uid then
				local c = SchoolMath.pairChemistry(d.def, other.def)
				if peace and c < 0 then
					c = 0
				end
				sat += c * Config.ChemistryPoints
				sat += moodAura[other.uid] or 0
			end
		end
		local t = d.def.trait
		if t then
			if t.kind == "Loner" and roommates == 0 then
				sat += t.value
			elseif t.kind == "Social" then
				sat += t.value * roommates
			end
		end
		sat = math.clamp(sat, 0, 100)

		local rarity = Config.Rarities[d.def.rarity]
		local base = rarity.income * (d.s.shiny and Config.ShinyMultiplier or 1)
		local income = base * (0.25 + sat / 50) * goldMult * facMult * globalMult
		result.students[d.uid] = { sat = sat, income = income }
		result.satisfaction += sat
		result.income += income
	end
	if #defs > 0 then
		result.satisfaction /= #defs
	end
	return result
end

function SchoolMath.totals(data, globalMult)
	local income, satSum, housed = 0, 0, 0
	local rooms = {}
	for i, room in ipairs(data.rooms) do
		local r = SchoolMath.room(data, room.tier, room.occupants, globalMult)
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

function SchoolMath.chemEmoji(c)
	if c >= 2 then
		return "💞"
	elseif c == 1 then
		return "🙂"
	elseif c == 0 then
		return "😶"
	elseif c == -1 then
		return "😒"
	end
	return "💢"
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
