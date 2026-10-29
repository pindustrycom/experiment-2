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
-- Personalities + chemistry (symmetric; -2 hate .. +2 besties)
---------------------------------------------------------------------------
Config.Personalities = {
	Nerd = { color = Color3.fromRGB(80, 120, 220), emoji = "🤓" },
	Jock = { color = Color3.fromRGB(220, 70, 60), emoji = "🏈" },
	Artist = { color = Color3.fromRGB(240, 150, 200), emoji = "🎨" },
	Rebel = { color = Color3.fromRGB(40, 40, 50), emoji = "😎" },
	Prankster = { color = Color3.fromRGB(250, 200, 50), emoji = "🤪" },
	Musician = { color = Color3.fromRGB(150, 80, 200), emoji = "🎸" },
	Gamer = { color = Color3.fromRGB(40, 200, 180), emoji = "🎮" },
	Royal = { color = Color3.fromRGB(245, 215, 110), emoji = "👑" },
}

local chem = {
	Nerd = { Nerd = 1, Jock = -1, Artist = 0, Rebel = -1, Prankster = -2, Musician = 0, Gamer = 2, Royal = 0 },
	Jock = { Jock = 1, Artist = -1, Rebel = 1, Prankster = 1, Musician = 0, Gamer = -1, Royal = 0 },
	Artist = { Artist = 1, Rebel = 1, Prankster = 0, Musician = 2, Gamer = 0, Royal = -1 },
	Rebel = { Rebel = 0, Prankster = 2, Musician = 1, Gamer = 0, Royal = -2 },
	Prankster = { Prankster = -1, Musician = 0, Gamer = 1, Royal = -2 },
	Musician = { Musician = 1, Gamer = 0, Royal = 1 },
	Gamer = { Gamer = 1, Royal = -1 },
	Royal = { Royal = 2 },
}
-- mirror so lookups work both ways
for a, row in pairs(chem) do
	for b, v in pairs(row) do
		chem[b] = chem[b] or {}
		chem[b][a] = v
	end
end
Config.Chemistry = chem
Config.ChemistryPoints = 12 -- satisfaction per chemistry step
Config.BaseSatisfaction = 40

---------------------------------------------------------------------------
-- Students. trait types:
--   Mood     : +value satisfaction to every roommate
--   Gold     : multiplies income of the whole room by value
--   Peace    : negative chemistry in the room is ignored
--   Loner    : +value satisfaction when alone in a room
--   Social   : +value satisfaction per roommate (to self)
---------------------------------------------------------------------------
Config.Students = {
	-- Common
	{ id = "tim", name = "Quiet Tim", rarity = "Common", personality = "Nerd" },
	{ id = "becky", name = "Benchwarmer Becky", rarity = "Common", personality = "Jock" },
	{ id = "dan", name = "Doodle Dan", rarity = "Common", personality = "Artist" },
	{ id = "sam", name = "Skater Sam", rarity = "Common", personality = "Rebel" },
	{ id = "will", name = "Whoopee Will", rarity = "Common", personality = "Prankster" },
	{ id = "kelly", name = "Kazoo Kelly", rarity = "Common", personality = "Musician" },
	{ id = "pete", name = "Pixel Pete", rarity = "Common", personality = "Gamer" },
	{ id = "larry", name = "Lil Lord Larry", rarity = "Common", personality = "Royal" },
	-- Uncommon
	{ id = "mia", name = "Mathlete Mia", rarity = "Uncommon", personality = "Nerd" },
	{ id = "cole", name = "Captain Cole", rarity = "Uncommon", personality = "Jock" },
	{ id = "gia", name = "Graffiti Gia", rarity = "Uncommon", personality = "Artist" },
	{ id = "dex", name = "Detention Dex", rarity = "Uncommon", personality = "Rebel" },
	{ id = "steve", name = "Slime Steve", rarity = "Uncommon", personality = "Prankster" },
	{ id = "dre", name = "Drummer Dre", rarity = "Uncommon", personality = "Musician" },
	{ id = "lulu", name = "Lag-Free Lulu", rarity = "Uncommon", personality = "Gamer" },
	-- Rare
	{ id = "riley", name = "Robo Riley", rarity = "Rare", personality = "Nerd", trait = { kind = "Gold", value = 1.25, text = "Room income x1.25" } },
	{ id = "marcus", name = "MVP Marcus", rarity = "Rare", personality = "Jock", trait = { kind = "Mood", value = 8, text = "+8 mood to roommates" } },
	{ id = "maya", name = "Muralist Maya", rarity = "Rare", personality = "Artist", trait = { kind = "Social", value = 6, text = "+6 mood per roommate" } },
	{ id = "priya", name = "Punk Priya", rarity = "Rare", personality = "Rebel", trait = { kind = "Loner", value = 30, text = "+30 mood when alone" } },
	{ id = "sofia", name = "Speedrun Sofia", rarity = "Rare", personality = "Gamer" },
	{ id = "daisy", name = "Duchess Daisy", rarity = "Rare", personality = "Royal" },
	-- Epic
	{ id = "junior", name = "Prof. Junior", rarity = "Epic", personality = "Nerd", trait = { kind = "Peace", value = 1, text = "Roommates never fight" } },
	{ id = "ollie", name = "Olympic Ollie", rarity = "Epic", personality = "Jock", trait = { kind = "Mood", value = 12, text = "+12 mood to roommates" } },
	{ id = "penny", name = "Pop Star Penny", rarity = "Epic", personality = "Musician", trait = { kind = "Social", value = 10, text = "+10 mood per roommate" } },
	{ id = "hex", name = "Hacker Hex", rarity = "Epic", personality = "Gamer", trait = { kind = "Gold", value = 1.5, text = "Room income x1.5" } },
	{ id = "kai", name = "Chaos Kai", rarity = "Epic", personality = "Prankster", trait = { kind = "Mood", value = 10, text = "+10 mood to roommates" } },
	-- Legendary
	{ id = "heir", name = "Headmaster's Heir", rarity = "Legendary", personality = "Royal", trait = { kind = "Mood", value = 20, text = "+20 mood to roommates" } },
	{ id = "prodigy", name = "Prodigy Pixel", rarity = "Legendary", personality = "Gamer", trait = { kind = "Gold", value = 2, text = "Room income x2" } },
	{ id = "remy", name = "Rockstar Remy", rarity = "Legendary", personality = "Musician", trait = { kind = "Social", value = 15, text = "+15 mood per roommate" } },
	{ id = "ghost", name = "Ghost of Room 13", rarity = "Legendary", personality = "Rebel", trait = { kind = "Peace", value = 1, text = "Roommates never fight" } },
	-- Mythic
	{ id = "tess", name = "Time Traveler Tess", rarity = "Mythic", personality = "Nerd", trait = { kind = "Gold", value = 3, text = "Room income x3" } },
	{ id = "dragon", name = "Dragon Exchange Student", rarity = "Mythic", personality = "Royal", trait = { kind = "Mood", value = 30, text = "+30 mood to roommates" } },
}

Config.StudentById = {}
Config.StudentsByRarity = {}
for _, s in ipairs(Config.Students) do
	Config.StudentById[s.id] = s
	Config.StudentsByRarity[s.rarity] = Config.StudentsByRarity[s.rarity] or {}
	table.insert(Config.StudentsByRarity[s.rarity], s)
end

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
-- Facilities: rooms inside the house that boost everyone or a personality.
-- Built from the floor layout board in your room.
---------------------------------------------------------------------------
Config.Facilities = {
	{ id = "cafeteria", name = "Cafeteria", emoji = "🍕", cost = 2000, all = 5, text = "+5 mood for everyone", color = Color3.fromRGB(255, 160, 80) },
	{ id = "library", name = "Library", emoji = "📚", cost = 6000, boost = { Nerd = 10, Royal = 4 }, text = "+10 Nerds, +4 Royals", color = Color3.fromRGB(120, 80, 50) },
	{ id = "gym", name = "Gym", emoji = "🏋", cost = 6000, boost = { Jock = 10, Rebel = 4 }, text = "+10 Jocks, +4 Rebels", color = Color3.fromRGB(200, 60, 60) },
	{ id = "arcade", name = "Arcade", emoji = "🕹", cost = 12000, boost = { Gamer = 10, Prankster = 6 }, text = "+10 Gamers, +6 Pranksters", color = Color3.fromRGB(60, 220, 200) },
	{ id = "artstudio", name = "Art Studio", emoji = "🎨", cost = 12000, boost = { Artist = 10, Rebel = 4 }, text = "+10 Artists, +4 Rebels", color = Color3.fromRGB(240, 140, 200) },
	{ id = "musichall", name = "Music Hall", emoji = "🎹", cost = 30000, boost = { Musician = 10, Artist = 4 }, text = "+10 Musicians, +4 Artists", color = Color3.fromRGB(150, 80, 220) },
	{ id = "pool", name = "Swimming Pool", emoji = "🏊", cost = 80000, all = 3, incomeMult = 0.15, text = "+3 mood, +15% income", color = Color3.fromRGB(60, 160, 255) },
	{ id = "ballroom", name = "Grand Ballroom", emoji = "💃", cost = 200000, boost = { Royal = 12, Musician = 4 }, text = "+12 Royals, +4 Musicians", color = Color3.fromRGB(250, 210, 100) },
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
