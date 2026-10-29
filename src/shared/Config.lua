-- Central game tuning. Change numbers here to rebalance the whole game.
local Config = {}

Config.GameName = "Boarding School Tycoon"
Config.StartingCash = 300
-- Testing: in Studio only, start every session with this much cash and skip saving.
-- Set to nil (or false) before release to test the real economy in Studio.
Config.StudioTestCash = 1e12
Config.MaxStudents = 180 -- roster cap (housed + unhoused), must be >= total beds
Config.SaveKey = "BST_Player_v1"

---------------------------------------------------------------------------
-- Rarities
---------------------------------------------------------------------------
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Config.Rarities = {
	Common = { income = 1, color = Color3.fromRGB(190, 190, 190), expel = 40, rank = 1 },
	Uncommon = { income = 3, color = Color3.fromRGB(90, 210, 110), expel = 120, rank = 2 },
	Rare = { income = 8, color = Color3.fromRGB(70, 150, 255), expel = 400, rank = 3 },
	Epic = { income = 20, color = Color3.fromRGB(180, 90, 255), expel = 1500, rank = 4 },
	Legendary = { income = 60, color = Color3.fromRGB(255, 190, 40), expel = 6000, rank = 5 },
	Mythic = { income = 200, color = Color3.fromRGB(255, 70, 120), expel = 30000, rank = 6 },
}

-- Chance a pulled student is "Shiny" (2x income, sparkles)
Config.ShinyChance = 1 / 40
Config.ShinyMultiplier = 2

---------------------------------------------------------------------------
-- Tags. Every student has 1-3. `base` is how well the tag gets along with
-- anyone by default (0.5 = neutral); Vibe below overrides specific pairs.
---------------------------------------------------------------------------
Config.Tags = {
	Alpha = { name = "Alpha", emoji = "🐺", color = Color3.fromRGB(200, 60, 60), text = "Leader, competitive" },
	Chad = { name = "Chad", emoji = "🗿", color = Color3.fromRGB(230, 170, 90), text = "Confident, everyone likes him" },
	Nerd = { name = "Nerd", emoji = "🤓", color = Color3.fromRGB(80, 120, 220), text = "Studies, math, good grades" },
	Gamer = { name = "Gamer", emoji = "🎮", color = Color3.fromRGB(40, 200, 180), text = "Lives on the console" },
	Artistic = { name = "Artistic", emoji = "🎨", color = Color3.fromRGB(240, 150, 200), text = "Draws, paints, aesthetic" },
	Musician = { name = "Musician", emoji = "🎸", color = Color3.fromRGB(150, 80, 200), text = "Guitar, playlists" },
	Funny = { name = "Funny", emoji = "🤪", color = Color3.fromRGB(250, 200, 50), text = "Class clown", base = 0.55 },
	Bully = { name = "Bully", emoji = "😈", color = Color3.fromRGB(90, 40, 40), text = "Picks on others", base = 0.42 },
	Normal = { name = "Normal", emoji = "🙂", color = Color3.fromRGB(150, 160, 170), text = "Easygoing, fits anywhere", base = 0.52 },
	Chud = { name = "Chud", emoji = "😤", color = Color3.fromRGB(110, 120, 80), text = "Online, contrarian, gloomy", base = 0.45 },
	Sleepy = { name = "Sleepy", emoji = "😴", color = Color3.fromRGB(140, 170, 120), text = "Super chill, naps, snacks" },
	Carefree = { name = "Carefree", emoji = "🌈", color = Color3.fromRGB(120, 200, 230), text = "Goes with the flow" },
	Jock = { name = "Jock", emoji = "🏈", color = Color3.fromRGB(220, 70, 60), text = "Sports, early mornings" },
	RichKid = { name = "Rich Kid", emoji = "💎", color = Color3.fromRGB(245, 215, 110), text = "Designer clothes, brags" },
	Charismatic = { name = "Charismatic", emoji = "😎", color = Color3.fromRGB(255, 140, 90), text = "Natural people person", base = 0.6 },
	Indie = { name = "Indie", emoji = "🎧", color = Color3.fromRGB(90, 90, 110), text = "Niche music taste" },
	LaRose = { name = "La Rose", emoji = "🌹", color = Color3.fromRGB(255, 90, 140), text = "Part of the La Rose crew" },
}
Config.TagOrder = { "Alpha", "Chad", "Nerd", "Gamer", "Artistic", "Musician", "Funny", "Bully", "Normal", "Chud", "Sleepy", "Carefree", "Jock", "RichKid", "Charismatic", "Indie", "LaRose" }

-- Vibe between two tags, 0..1 (symmetric). Pairs not listed use the tags' base values.
local vibePairs = {
	{ "Alpha", "Alpha", 0.3 }, { "Alpha", "Chad", 0.75 }, { "Alpha", "Funny", 0.65 }, { "Alpha", "Bully", 0.3 }, { "Alpha", "Sleepy", 0.3 },
	{ "Alpha", "Carefree", 0.35 }, { "Alpha", "RichKid", 0.7 }, { "Alpha", "Jock", 0.65 }, { "Alpha", "Nerd", 0.4 },
	{ "Chad", "Chad", 0.7 }, { "Chad", "Funny", 0.7 }, { "Chad", "Jock", 0.75 }, { "Chad", "Chud", 0.2 }, { "Chad", "Charismatic", 0.7 }, { "Chad", "RichKid", 0.6 },
	{ "Nerd", "Nerd", 0.75 }, { "Nerd", "Gamer", 0.8 }, { "Nerd", "Bully", 0.15 }, { "Nerd", "Jock", 0.3 }, { "Nerd", "Musician", 0.4 }, { "Nerd", "Indie", 0.6 },
	{ "Gamer", "Gamer", 0.75 }, { "Gamer", "Jock", 0.35 }, { "Gamer", "Chud", 0.65 }, { "Gamer", "Funny", 0.65 }, { "Gamer", "Sleepy", 0.6 },
	{ "Artistic", "Artistic", 0.65 }, { "Artistic", "Musician", 0.8 }, { "Artistic", "Carefree", 0.75 }, { "Artistic", "Bully", 0.15 }, { "Artistic", "Indie", 0.75 }, { "Artistic", "Sleepy", 0.6 },
	{ "Musician", "Musician", 0.65 }, { "Musician", "Carefree", 0.7 }, { "Musician", "Sleepy", 0.6 }, { "Musician", "Indie", 0.75 },
	{ "Funny", "Funny", 0.7 }, { "Funny", "Chud", 0.25 }, { "Funny", "Sleepy", 0.65 }, { "Funny", "Bully", 0.4 },
	{ "Bully", "Bully", 0.65 }, { "Bully", "Normal", 0.25 }, { "Bully", "Charismatic", 0.3 }, { "Bully", "Carefree", 0.35 }, { "Bully", "Indie", 0.25 },
	{ "Normal", "Normal", 0.6 },
	{ "Chud", "Chud", 0.7 }, { "Chud", "RichKid", 0.3 }, { "Chud", "Charismatic", 0.35 },
	{ "Sleepy", "Sleepy", 0.7 }, { "Sleepy", "Carefree", 0.8 }, { "Sleepy", "Jock", 0.3 },
	{ "Carefree", "Carefree", 0.7 },
	{ "Jock", "Jock", 0.7 }, { "Jock", "RichKid", 0.55 },
	{ "RichKid", "RichKid", 0.7 }, { "RichKid", "Normal", 0.45 },
	{ "Charismatic", "Charismatic", 0.7 },
	{ "Indie", "Indie", 0.7 },
	{ "LaRose", "LaRose", 0.95 },
}
Config.TagVibe = {}
for _, a in ipairs(Config.TagOrder) do
	Config.TagVibe[a] = {}
	for _, b in ipairs(Config.TagOrder) do
		local ba, bb = Config.Tags[a].base or 0.5, Config.Tags[b].base or 0.5
		Config.TagVibe[a][b] = math.clamp(0.5 + (ba - 0.5) + (bb - 0.5), 0.05, 0.95)
	end
end
for _, p in ipairs(vibePairs) do
	Config.TagVibe[p[1]][p[2]] = p[3]
	Config.TagVibe[p[2]][p[1]] = p[3]
end
Config.LaRoseVibe = 0.95 -- any two La Rose members vibe at least this much
Config.VibePoints = 0.8 -- satisfaction per roommate = (vibe% - 50) * this
Config.BaseSatisfaction = 40

-- Old saves and visuals: the outfit/accessory set a student wears.
Config.Looks = {
	Nerd = { color = Color3.fromRGB(80, 120, 220) },
	Jock = { color = Color3.fromRGB(220, 70, 60) },
	Artist = { color = Color3.fromRGB(240, 150, 200) },
	Rebel = { color = Color3.fromRGB(40, 40, 50) },
	Prankster = { color = Color3.fromRGB(250, 200, 50) },
	Musician = { color = Color3.fromRGB(150, 80, 200) },
	Gamer = { color = Color3.fromRGB(40, 200, 180) },
	Royal = { color = Color3.fromRGB(245, 215, 110) },
}

---------------------------------------------------------------------------
-- Students. gender "M"/"F". look = outfit set (Config.Looks), optional
-- shirt/skin/hair colors and extra accessories (`acc`) override it.
-- trait types:
--   Mood     : +value satisfaction to every roommate
--   Gold     : multiplies income of the whole room by value (needs = living room item)
--   Peace    : negative vibe in the room is ignored
--   Chill    : this student never has negative vibe with anyone
--   Loner    : +value satisfaction when alone in a room
--   Social   : +value satisfaction per roommate (to self)
--   Floor    : +value satisfaction to everyone housed on the same floor
--   Rivals   : +value income multiplier per student in the house who can't stand them
-- weight: pull chance inside its rarity (default 1)
---------------------------------------------------------------------------
Config.Students = {
	-- Common
	{ id = "tim", name = "Quiet Tim", rarity = "Common", gender = "M", look = "Nerd", tags = { "Nerd" } },
	{ id = "becky", name = "Benchwarmer Becky", rarity = "Common", gender = "F", look = "Jock", tags = { "Jock" } },
	{ id = "dan", name = "Doodle Dan", rarity = "Common", gender = "M", look = "Artist", tags = { "Artistic" } },
	{ id = "sam", name = "Skater Sam", rarity = "Common", gender = "M", look = "Rebel", tags = { "Carefree" } },
	{ id = "will", name = "Whoopee Will", rarity = "Common", gender = "M", look = "Prankster", tags = { "Funny" } },
	{ id = "kelly", name = "Kazoo Kelly", rarity = "Common", gender = "F", look = "Musician", tags = { "Musician" } },
	{ id = "pete", name = "Pixel Pete", rarity = "Common", gender = "M", look = "Gamer", tags = { "Gamer" } },
	{ id = "larry", name = "Lil Lord Larry", rarity = "Common", gender = "M", look = "Royal", tags = { "RichKid" } },
	{ id = "sue", name = "Sleepy Sue", rarity = "Common", gender = "F", look = "Rebel", shirt = Color3.fromRGB(140, 170, 120), tags = { "Sleepy" } },
	{ id = "dana", name = "Doomscroll Dana", rarity = "Common", gender = "F", look = "Gamer", shirt = Color3.fromRGB(110, 120, 80), tags = { "Chud" } },
	{ id = "nora", name = "Normal Nora", rarity = "Common", gender = "F", look = "Nerd", shirt = Color3.fromRGB(150, 160, 170), acc = {}, tags = { "Normal" } },
	{ id = "bruno", name = "Big Bruno", rarity = "Common", gender = "M", look = "Jock", shirt = Color3.fromRGB(90, 40, 40), tags = { "Bully" } },
	-- Uncommon
	{ id = "mia", name = "Mathlete Mia", rarity = "Uncommon", gender = "F", look = "Nerd", tags = { "Nerd", "Alpha" } },
	{ id = "cole", name = "Captain Cole", rarity = "Uncommon", gender = "M", look = "Jock", tags = { "Jock", "Alpha" } },
	{ id = "gia", name = "Graffiti Gia", rarity = "Uncommon", gender = "F", look = "Artist", tags = { "Artistic", "Carefree" } },
	{ id = "dex", name = "Detention Dex", rarity = "Uncommon", gender = "M", look = "Rebel", tags = { "Bully", "Funny" } },
	{ id = "steve", name = "Slime Steve", rarity = "Uncommon", gender = "M", look = "Prankster", tags = { "Funny", "Gamer" } },
	{ id = "dre", name = "Drummer Dre", rarity = "Uncommon", gender = "M", look = "Musician", tags = { "Musician", "Carefree" } },
	{ id = "lulu", name = "Lag-Free Lulu", rarity = "Uncommon", gender = "F", look = "Gamer", tags = { "Gamer", "Sleepy" } },
	{ id = "gwen", name = "Glitter Gwen", rarity = "Uncommon", gender = "F", look = "Artist", shirt = Color3.fromRGB(245, 215, 110), tags = { "Artistic", "RichKid" } },
	-- Rare
	{ id = "riley", name = "Robo Riley", rarity = "Rare", gender = "F", look = "Nerd", tags = { "Nerd", "Gamer" }, trait = { kind = "Gold", value = 1.25, text = "Room income x1.25" } },
	{ id = "marcus", name = "MVP Marcus", rarity = "Rare", gender = "M", look = "Jock", tags = { "Jock", "Chad" }, trait = { kind = "Mood", value = 8, text = "+8 mood to roommates" } },
	{ id = "maya", name = "Muralist Maya", rarity = "Rare", gender = "F", look = "Artist", tags = { "Artistic", "Indie" }, trait = { kind = "Social", value = 6, text = "+6 mood per roommate" } },
	{ id = "priya", name = "Punk Priya", rarity = "Rare", gender = "F", look = "Rebel", tags = { "Indie", "Alpha" }, trait = { kind = "Loner", value = 30, text = "+30 mood when alone" } },
	{ id = "sofia", name = "Speedrun Sofia", rarity = "Rare", gender = "F", look = "Gamer", tags = { "Gamer", "Alpha" } },
	{ id = "daisy", name = "Duchess Daisy", rarity = "Rare", gender = "F", look = "Royal", tags = { "RichKid", "Charismatic" } },
	{ id = "chloe", name = "Choir Chloe", rarity = "Rare", gender = "F", look = "Musician", tags = { "Musician", "Charismatic" }, trait = { kind = "Mood", value = 6, text = "+6 mood to roommates" } },
	-- Epic
	{ id = "junior", name = "Prof. Junior", rarity = "Epic", gender = "M", look = "Nerd", tags = { "Nerd", "Normal" }, trait = { kind = "Peace", value = 1, text = "Roommates never fight" } },
	{ id = "ollie", name = "Olympic Ollie", rarity = "Epic", gender = "M", look = "Jock", tags = { "Jock", "Chad" }, trait = { kind = "Mood", value = 12, text = "+12 mood to roommates" } },
	{ id = "penny", name = "Pop Star Penny", rarity = "Epic", gender = "F", look = "Musician", tags = { "Musician", "Charismatic" }, trait = { kind = "Social", value = 10, text = "+10 mood per roommate" } },
	{ id = "hex", name = "Hacker Hex", rarity = "Epic", gender = "F", look = "Gamer", tags = { "Gamer", "Chud" }, trait = { kind = "Gold", value = 1.5, text = "Room income x1.5" } },
	{ id = "kai", name = "Chaos Kai", rarity = "Epic", gender = "M", look = "Prankster", tags = { "Funny", "Bully" }, trait = { kind = "Mood", value = 10, text = "+10 mood to roommates" } },
	{ id = "bella", name = "Bossy Bella", rarity = "Epic", gender = "F", look = "Royal", tags = { "Alpha", "RichKid" }, trait = { kind = "Gold", value = 1.4, text = "Room income x1.4" } },
	-- Legendary
	{ id = "heir", name = "Headmaster's Heir", rarity = "Legendary", gender = "M", look = "Royal", tags = { "RichKid", "Alpha", "Charismatic" }, trait = { kind = "Mood", value = 20, text = "+20 mood to roommates" } },
	{ id = "prodigy", name = "Prodigy Pixel", rarity = "Legendary", gender = "F", look = "Gamer", tags = { "Gamer", "Nerd", "Sleepy" }, trait = { kind = "Gold", value = 2, text = "Room income x2" } },
	{ id = "remy", name = "Rockstar Remy", rarity = "Legendary", gender = "M", look = "Musician", tags = { "Musician", "Chad", "Charismatic" }, trait = { kind = "Social", value = 15, text = "+15 mood per roommate" } },
	{ id = "ghost", name = "Ghost of Room 13", rarity = "Legendary", gender = "M", look = "Rebel", tags = { "Indie", "Sleepy", "Carefree" }, trait = { kind = "Peace", value = 1, text = "Roommates never fight" } },
	{ id = "ivy", name = "Influencer Ivy", rarity = "Legendary", gender = "F", look = "Royal", acc = { "shades" }, tags = { "Charismatic", "RichKid", "Funny" }, trait = { kind = "Social", value = 12, text = "+12 mood per roommate" } },
	-- La Rose crew (Legendary, rarer inside the pool)
	{ id = "khan", name = "Khan D", rarity = "Legendary", weight = 0.5, crew = "LaRose", gender = "M", look = "Gamer", acc = { "glasses", "headset" }, shirt = Color3.fromRGB(60, 60, 75), hair = Color3.fromRGB(20, 20, 22), skin = Color3.fromRGB(234, 200, 160), tags = { "LaRose", "Nerd", "Gamer" }, trait = { kind = "Gold", value = 2, needs = "console", text = "Room income x2 with a console in the living room" } },
	{ id = "jp", name = "JP", rarity = "Legendary", weight = 0.5, crew = "LaRose", gender = "M", look = "Musician", acc = { "guitar", "wavy" }, shirt = Color3.fromRGB(235, 235, 230), hair = Color3.fromRGB(45, 30, 20), skin = Color3.fromRGB(196, 140, 100), tags = { "LaRose", "Musician", "Charismatic" }, trait = { kind = "Mood", value = 20, text = "+20 mood to roommates" } },
	{ id = "ed", name = "Ed", rarity = "Legendary", weight = 0.5, crew = "LaRose", gender = "M", look = "Musician", acc = { "headphones", "curly" }, shirt = Color3.fromRGB(25, 25, 30), hair = Color3.fromRGB(40, 28, 20), skin = Color3.fromRGB(190, 135, 95), tags = { "LaRose", "Indie", "Musician" }, trait = { kind = "Chill", value = 1, text = "Never has a bad vibe with anyone" } },
	{ id = "greg", name = "Greg", rarity = "Legendary", weight = 0.5, crew = "LaRose", gender = "M", look = "Jock", acc = { "shades", "bighair" }, shirt = Color3.fromRGB(30, 60, 140), hair = Color3.fromRGB(90, 60, 35), skin = Color3.fromRGB(240, 205, 175), tags = { "LaRose", "Funny", "Charismatic", "Chad" }, trait = { kind = "Floor", value = 5, text = "+5 mood to everyone on his floor" } },
	{ id = "miguel", name = "Miguel", rarity = "Legendary", weight = 0.5, crew = "LaRose", gender = "M", look = "Rebel", acc = { "greenaura" }, shirt = Color3.fromRGB(40, 70, 40), hair = Color3.fromRGB(60, 230, 90), skin = Color3.fromRGB(240, 210, 185), tags = { "LaRose", "Chud" }, trait = { kind = "Rivals", value = 0.1, text = "+10% income per rival in the house" } },
	-- Mythic
	{ id = "tess", name = "Time Traveler Tess", rarity = "Mythic", gender = "F", look = "Nerd", tags = { "Nerd", "Carefree", "Charismatic" }, trait = { kind = "Gold", value = 3, text = "Room income x3" } },
	{ id = "dragon", name = "Dragon Exchange Student", rarity = "Mythic", gender = "M", look = "Royal", tags = { "RichKid", "Alpha", "Chad" }, trait = { kind = "Mood", value = 30, text = "+30 mood to roommates" } },
}
Config.CrewBonus = { LaRose = 0.25 } -- +25% income for the whole house with the full crew
Config.Crews = { LaRose = {} }

Config.StudentById = {}
Config.StudentsByRarity = {}
for _, s in ipairs(Config.Students) do
	Config.StudentById[s.id] = s
	Config.StudentsByRarity[s.rarity] = Config.StudentsByRarity[s.rarity] or {}
	table.insert(Config.StudentsByRarity[s.rarity], s)
	if s.crew then
		table.insert(Config.Crews[s.crew], s.id)
	end
end

-- "🤓 Nerd  🎮 Gamer"
function Config.TagLine(def, sep)
	local bits = {}
	for _, t in ipairs(def.tags) do
		local tag = Config.Tags[t]
		table.insert(bits, tag.emoji .. " " .. tag.name)
	end
	return table.concat(bits, sep or "  ")
end
function Config.TagEmoji(def)
	return Config.Tags[def.tags[1]].emoji
end

-- Relationships. Every pair who has met has a bond score (-50..100); the
-- level adds satisfaction while they share a room.
Config.BondLevels = {
	{ min = -50, name = "Rivals", emoji = "💢", sat = -10 },
	{ min = 0, name = "Strangers", emoji = "😶", sat = 0 },
	{ min = 20, name = "Acquaintances", emoji = "👋", sat = 2 },
	{ min = 40, name = "Friends", emoji = "🙂", sat = 5 },
	{ min = 60, name = "Close friends", emoji = "😊", sat = 8 },
	{ min = 80, name = "Best friends", emoji = "💞", sat = 12 },
	{ min = 95, name = "Siblings", emoji = "🤝", sat = 15 },
}
Config.BondMin, Config.BondMax = -50, 100
Config.BondTick = 180 -- seconds between roommate bond updates
Config.BondPerTick = 0.1 -- roommates move (vibe% - 50) * this per tick
Config.SiblingSplitPenalty = 15 -- satisfaction lost per sibling living in another room

function Config.BondLevel(score)
	local level = Config.BondLevels[1]
	for _, l in ipairs(Config.BondLevels) do
		if score >= l.min then
			level = l
		end
	end
	return level
end
-- "Brothers" / "Sisters" / "Siblings" for the top level
function Config.BondName(level, defA, defB)
	if level.min == 95 and defA and defB and defA.gender == defB.gender then
		return defA.gender == "F" and "Sisters" or "Brothers"
	end
	return level.name
end
function Config.BondKey(a, b)
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

-- House rule set on the floor plans board
Config.HouseGenders = { Mixed = "👫 Mixed", Boys = "👦 Boys only", Girls = "👧 Girls only" }

---------------------------------------------------------------------------
-- Admissions (gacha banners). weights are percentages.
---------------------------------------------------------------------------
Config.Banners = {
	{
		id = "standard",
		name = "Open Admission",
		cost = 150,
		color = Color3.fromRGB(110, 170, 255),
		weights = { Common = 62, Uncommon = 25, Rare = 9, Epic = 3, Legendary = 0.9, Mythic = 0.1 },
	},
	{
		id = "honors",
		name = "Honors Admission",
		cost = 2500,
		color = Color3.fromRGB(180, 100, 255),
		weights = { Common = 25, Uncommon = 40, Rare = 22, Epic = 10, Legendary = 2.7, Mythic = 0.3 },
	},
	{
		id = "royal",
		name = "Royal Admission",
		cost = 40000,
		color = Color3.fromRGB(255, 190, 40),
		weights = { Common = 0, Uncommon = 20, Rare = 45, Epic = 25, Legendary = 8.5, Mythic = 1.5 },
	},
}
Config.BannerById = {}
for _, b in ipairs(Config.Banners) do
	Config.BannerById[b.id] = b
end
-- Admissions get pricier the bigger your roster is (expelling makes them cheaper).
Config.PullCostGrowth = 1.05
function Config.PullCost(banner, owned)
	return math.floor(banner.cost * Config.PullCostGrowth ^ math.max(0, owned - 2))
end

Config.PityPulls = 75 -- guaranteed Legendary+ after this many pulls without one
Config.DailyFreeBanner = "honors"
Config.DailyCooldown = 20 * 3600

---------------------------------------------------------------------------
-- The house: floors, dorm rooms, upgrades
-- Everything lives in one walkable house. Each floor is a hallway with a row
-- of cells on each side (Config.SlotsPerFloor cells per floor). Your room
-- takes 2 cells and the common room 1, both on the ground floor. You choose
-- which cell every new dorm or facility goes in on the floor layout board,
-- and dorms can be expanded into the cell next to them.
---------------------------------------------------------------------------
Config.SlotsPerFloor = 12
Config.MaxRooms = 40 -- dorm rooms
Config.StartingRooms = 2
Config.MaxFloors = 6

-- price of unlocking floor n (2, 3, ...)
function Config.FloorCost(n)
	return math.floor(5000 * 7 ^ (n - 2) / 100 + 0.5) * 100
end

-- expanding a dorm into the empty cell beside it: more beds and more space
Config.BigRoomBeds = 2
Config.BigRoomDecor = 6
function Config.ExpandCost(index)
	return math.floor(2500 * (1 + 0.4 * (index - 1)) / 10 + 0.5) * 10
end

function Config.Beds(room)
	return Config.RoomTiers[room.tier].beds + ((room.size or 1) >= 2 and Config.BigRoomBeds or 0)
end

function Config.RoomUnlockCost(index)
	-- index is the room number being bought (3, 4, 5 ...)
	local n = index - 2
	return math.floor(300 * n * n * (1.25 ^ (n - 1)) / 10 + 0.5) * 10
end

Config.RoomTiers = {
	{ name = "Basic Dorm", beds = 2, decor = 0, cost = 0 },
	{ name = "Comfy Dorm", beds = 3, decor = 4, cost = 1500 },
	{ name = "Luxury Suite", beds = 4, decor = 8, cost = 20000 },
	{ name = "Penthouse", beds = 4, decor = 14, cost = 250000 },
}

function Config.RoomUpgradeCost(index, toTier)
	local t = Config.RoomTiers[toTier]
	if not t then
		return nil
	end
	return math.floor(t.cost * (1 + 0.35 * (index - 1)))
end

---------------------------------------------------------------------------
-- Facilities: rooms inside the house that boost everyone or certain tags
-- (a student gets the best boost among their tags).
-- Built from the floor layout board in your room.
---------------------------------------------------------------------------
Config.Facilities = {
	{ id = "cafeteria", name = "Cafeteria", emoji = "🍕", cost = 2000, all = 5, text = "+5 mood for everyone", color = Color3.fromRGB(255, 160, 80) },
	{ id = "library", name = "Library", emoji = "📚", cost = 6000, boost = { Nerd = 10, Indie = 4 }, text = "+10 Nerds, +4 Indies", color = Color3.fromRGB(120, 80, 50) },
	{ id = "gym", name = "Gym", emoji = "🏋", cost = 6000, boost = { Jock = 10, Alpha = 4, Chad = 4 }, text = "+10 Jocks, +4 Alphas and Chads", color = Color3.fromRGB(200, 60, 60) },
	{ id = "arcade", name = "Arcade", emoji = "🕹", cost = 12000, boost = { Gamer = 10, Funny = 6, Chud = 4 }, text = "+10 Gamers, +6 Funnies, +4 Chuds", color = Color3.fromRGB(60, 220, 200) },
	{ id = "artstudio", name = "Art Studio", emoji = "🎨", cost = 12000, boost = { Artistic = 10, Indie = 4 }, text = "+10 Artistics, +4 Indies", color = Color3.fromRGB(240, 140, 200) },
	{ id = "musichall", name = "Music Hall", emoji = "🎹", cost = 30000, boost = { Musician = 10, Artistic = 4 }, text = "+10 Musicians, +4 Artistics", color = Color3.fromRGB(150, 80, 220) },
	{ id = "pool", name = "Swimming Pool", emoji = "🏊", cost = 80000, all = 3, incomeMult = 0.15, text = "+3 mood, +15% income", color = Color3.fromRGB(60, 160, 255) },
	{ id = "ballroom", name = "Grand Ballroom", emoji = "💃", cost = 200000, boost = { RichKid = 12, Charismatic = 6 }, text = "+12 Rich Kids, +6 Charismatics", color = Color3.fromRGB(250, 210, 100) },
	{ id = "observatory", name = "Observatory", emoji = "🔭", cost = 1000000, all = 5, incomeMult = 0.3, text = "+5 mood, +30% income", color = Color3.fromRGB(70, 60, 140) },
}
Config.FacilityById = {}
for _, f in ipairs(Config.Facilities) do
	Config.FacilityById[f.id] = f
end

---------------------------------------------------------------------------
-- Build mode materials (Sims-style). Paint any room's walls and floor, the
-- outside walls and the roof. Each coat costs `cost`. In dorm rooms, `decor`
-- adds satisfaction for everyone living there (walls + floor stack).
-- `material` is an Enum.Material name.
---------------------------------------------------------------------------
Config.WallStyles = {
	{ id = "cream", name = "Cream Paint", material = "SmoothPlastic", color = Color3.fromRGB(235, 225, 200), cost = 0, decor = 0 },
	{ id = "sky", name = "Sky Paint", material = "SmoothPlastic", color = Color3.fromRGB(180, 215, 240), cost = 50, decor = 0 },
	{ id = "mint", name = "Mint Paint", material = "SmoothPlastic", color = Color3.fromRGB(185, 235, 205), cost = 50, decor = 0 },
	{ id = "blush", name = "Blush Paint", material = "SmoothPlastic", color = Color3.fromRGB(245, 200, 215), cost = 50, decor = 0 },
	{ id = "plaster", name = "Plaster", material = "Plaster", color = Color3.fromRGB(240, 238, 230), cost = 250, decor = 1 },
	{ id = "redbrick", name = "Red Brick", material = "Brick", color = Color3.fromRGB(170, 80, 60), cost = 400, decor = 1 },
	{ id = "whitebrick", name = "White Brick", material = "Brick", color = Color3.fromRGB(230, 225, 220), cost = 600, decor = 2 },
	{ id = "woodpanel", name = "Wood Panels", material = "WoodPlanks", color = Color3.fromRGB(160, 110, 70), cost = 1200, decor = 2 },
	{ id = "stone", name = "Castle Stone", material = "Slate", color = Color3.fromRGB(140, 140, 150), cost = 3000, decor = 3 },
	{ id = "velvet", name = "Velvet Wallpaper", material = "Fabric", color = Color3.fromRGB(120, 30, 60), cost = 8000, decor = 4 },
	{ id = "marble", name = "Marble", material = "Marble", color = Color3.fromRGB(240, 240, 245), cost = 25000, decor = 5 },
	{ id = "gold", name = "Gold Leaf", material = "Foil", color = Color3.fromRGB(240, 200, 90), cost = 120000, decor = 7 },
}
Config.FloorStyles = {
	{ id = "oak", name = "Oak Boards", material = "WoodPlanks", color = Color3.fromRGB(196, 160, 120), cost = 0, decor = 0 },
	{ id = "walnut", name = "Walnut Boards", material = "WoodPlanks", color = Color3.fromRGB(120, 80, 50), cost = 150, decor = 0 },
	{ id = "bluecarpet", name = "Blue Carpet", material = "Carpet", color = Color3.fromRGB(70, 100, 170), cost = 300, decor = 1 },
	{ id = "pinkcarpet", name = "Pink Carpet", material = "Carpet", color = Color3.fromRGB(230, 150, 190), cost = 300, decor = 1 },
	{ id = "tiles", name = "Checker Tiles", material = "CeramicTiles", color = Color3.fromRGB(230, 230, 235), cost = 700, decor = 1 },
	{ id = "cobble", name = "Cobblestone", material = "Cobblestone", color = Color3.fromRGB(150, 145, 140), cost = 1200, decor = 2 },
	{ id = "granite", name = "Granite", material = "Granite", color = Color3.fromRGB(90, 90, 100), cost = 4000, decor = 3 },
	{ id = "marble", name = "Marble", material = "Marble", color = Color3.fromRGB(235, 235, 240), cost = 20000, decor = 4 },
	{ id = "night", name = "Starry Night", material = "Glass", color = Color3.fromRGB(25, 25, 50), cost = 90000, decor = 6 },
}
Config.RoofStyles = {
	{ id = "red", name = "Red Shingles", material = "RoofShingles", color = Color3.fromRGB(170, 60, 50), cost = 0 },
	{ id = "slate", name = "Slate Shingles", material = "RoofShingles", color = Color3.fromRGB(70, 75, 90), cost = 300 },
	{ id = "green", name = "Green Shingles", material = "RoofShingles", color = Color3.fromRGB(70, 130, 80), cost = 300 },
	{ id = "clay", name = "Clay Tiles", material = "ClayRoofTiles", color = Color3.fromRGB(200, 110, 70), cost = 1500 },
	{ id = "copper", name = "Copper", material = "Metal", color = Color3.fromRGB(90, 170, 150), cost = 10000 },
}
Config.StyleLists = { wall = Config.WallStyles, floor = Config.FloorStyles, roof = Config.RoofStyles }
Config.StyleById = {}
for kind, list in pairs(Config.StyleLists) do
	Config.StyleById[kind] = {}
	for _, st in ipairs(list) do
		Config.StyleById[kind][st.id] = st
	end
end
-- default look per area when the player never painted it
Config.DefaultStyles = {
	exterior = { wall = "redbrick", roof = "red" },
	hall = { wall = "cream", floor = "oak" },
	me = { wall = "sky", floor = "bluecarpet" },
	common = { wall = "mint", floor = "walnut" },
	dorm = { wall = "cream", floor = "oak" },
	facility = { wall = "plaster", floor = "tiles" },
}

---------------------------------------------------------------------------
-- Your own room. It always has a bed, a desk and a wardrobe. Extra furniture is bought once and can be hidden/shown for free.
-- Each piece makes the whole school a little more productive (+income).
---------------------------------------------------------------------------
Config.Furniture = {
	{ id = "rug", name = "Round Rug", emoji = "🟣", cost = 200, incomeMult = 0.01 },
	{ id = "plant", name = "Potted Plant", emoji = "🪴", cost = 350, incomeMult = 0.01 },
	{ id = "lamp", name = "Floor Lamp", emoji = "💡", cost = 600, incomeMult = 0.01 },
	{ id = "posters", name = "Band Posters", emoji = "🖼", cost = 1500, incomeMult = 0.02 },
	{ id = "bookshelf", name = "Bookshelf", emoji = "📚", cost = 4000, incomeMult = 0.02 },
	{ id = "beanbag", name = "Beanbag", emoji = "🛋", cost = 8000, incomeMult = 0.02 },
	{ id = "gaming", name = "Gaming Setup", emoji = "🎮", cost = 25000, incomeMult = 0.03 },
	{ id = "aquarium", name = "Aquarium", emoji = "🐠", cost = 75000, incomeMult = 0.04 },
	{ id = "trophy", name = "Trophy Cabinet", emoji = "🏆", cost = 250000, incomeMult = 0.05 },
}
Config.FurnitureById = {}
for _, f in ipairs(Config.Furniture) do
	Config.FurnitureById[f.id] = f
end

---------------------------------------------------------------------------
-- Social / idle
---------------------------------------------------------------------------
Config.OfflineMaxSeconds = 8 * 3600
Config.OfflineRate = 0.5 -- fraction of income earned while away
Config.FriendBoostEach = 0.1 -- +10% income per friend in the server
Config.FriendBoostMax = 0.5
Config.LikeCooldown = 20 * 3600 -- per target school

---------------------------------------------------------------------------
-- Monetization. Create these in the Creator Dashboard and paste the IDs.
-- Anything left at 0 is hidden in-game.
---------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCash = 0, -- 2x income forever
	Lucky = 0, -- +50% Legendary/Mythic odds
	VIP = 0, -- golden name tag + 10% income
}
Config.Products = {
	RoyalPull = 0, -- one Royal Admission
	RoyalPull10 = 0, -- ten Royal Admissions
	CashSmall = 0, -- 10 minutes of income (min 5,000)
	DoubleOffline = 0, -- doubles welcome-back earnings
}

return Config
