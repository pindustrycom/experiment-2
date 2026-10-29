-- Boarding School Tycoon: all player UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SchoolMath = require(Shared:WaitForChild("SchoolMath"))
local House = require(Shared:WaitForChild("House"))
local UI = require(script.Parent:WaitForChild("UI"))
local C = UI.Colors
local fmt = SchoolMath.format

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action")

local State = { data = nil, income = 0, satisfaction = 0 }
local currentPanel = nil
local panelState = {}

---------------------------------------------------------------------------
-- Sounds (built-in engine sounds, no uploads needed)
---------------------------------------------------------------------------
local function sound(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end
local SFX = {
	click = function()
		sound("rbxasset://sounds/electronicpingshort.wav", 0.3, 1.4)
	end,
	coin = function()
		sound("rbxasset://sounds/electronicpingshort.wav", 0.5, 1.8)
	end,
	reveal = function(rank)
		sound("rbxasset://sounds/electronicpingshort.wav", 0.6, 0.6 + rank * 0.15)
	end,
	error = function()
		sound("rbxasset://sounds/uuhhh.mp3", 0.3, 1.2)
	end,
}

---------------------------------------------------------------------------
-- Root GUI
---------------------------------------------------------------------------
local gui = UI.new("ScreenGui", {
	Name = "BSTGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local function call(action, args)
	local ok, res = pcall(Action.InvokeServer, Action, action, args)
	if not ok then
		return { ok = false, err = "Connection hiccup, try again." }
	end
	return res or { ok = false }
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------
local toastHolder = UI.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 70),
	Size = UDim2.new(0, 320, 0.6, 0),
	Parent = gui,
})
UI.list(toastHolder, 6, false, Enum.HorizontalAlignment.Right)

local function toast(text, kind)
	local color = ({ error = C.red, cash = C.green, like = C.pink, info = C.panel })[kind or "info"] or C.panel
	local f = UI.card(toastHolder, { BackgroundColor3 = color, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	UI.pad(f, 10)
	UI.text(f, text, 17, C.text, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	UI.pop(f, 0.7)
	if kind == "error" then
		SFX.error()
	end
	task.delay(3.5, function()
		TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		f:Destroy()
	end)
end

local function result(res, successText)
	if res.ok then
		if successText then
			toast(successText, "cash")
		end
		SFX.coin()
	elseif res.err then
		toast(res.err, "error")
	end
	return res.ok
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------
local hud = UI.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(600, 56),
	Parent = gui,
})
UI.list(hud, 8, true, Enum.HorizontalAlignment.Center)

local function pill(icon, color, width)
	local f = UI.card(hud, { Size = UDim2.fromOffset(width or 150, 52), BackgroundColor3 = C.bg, BackgroundTransparency = 0.15 })
	UI.stroke(f, color, 3)
	local t = UI.text(f, icon, 22, C.text, { Size = UDim2.new(1, -10, 0, 28), Position = UDim2.fromOffset(10, 2) })
	local sub = UI.text(f, "", 14, color, { Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(10, 30) })
	return t, sub
end
local cashLabel, incomeLabel = pill("💰 $0", C.green, 190)
local moodLabel, moodSub = pill("😐 0%", C.gold, 130)
local likeLabel, likeSub = pill("❤ 0", C.pink, 120)
moodSub.Text = "satisfaction"
likeSub.Text = "likes"

local function setCash(cash, inc)
	cashLabel.Text = "💰 $" .. fmt(cash)
	local boost = State.mult and State.mult > 1.001 and string.format("  (x%.2f)", State.mult) or ""
	incomeLabel.Text = "+$" .. fmt(inc) .. "/s" .. boost
end

---------------------------------------------------------------------------
-- Side menu
---------------------------------------------------------------------------
local menu = UI.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(120, 520),
	Parent = gui,
})
UI.list(menu, 8)

local openPanel -- forward
local menuButtons = {}
local function menuButton(id, text, color)
	local b = UI.button(menu, text, color, function()
		SFX.click()
		if currentPanel == id then
			openPanel(nil)
		else
			openPanel(id)
		end
	end, { Size = UDim2.fromOffset(120, 50), TextSize = 19 })
	menuButtons[id] = b
	return b
end
menuButton("enroll", "🎓 Enroll", C.purple)
menuButton("rooms", "🛏 Rooms", C.blue)
menuButton("students", "👥 Students", Color3.fromRGB(60, 190, 170))
menuButton("design", "🎨 Build", Color3.fromRGB(240, 140, 60))
UI.button(menu, "🏠 My Room", Color3.fromRGB(90, 120, 200), function()
	SFX.click()
	openPanel(nil)
	call("home")
end, { Size = UDim2.fromOffset(120, 50), TextSize = 19 })
menuButton("visit", "🗺 Visit", C.pink)
local dailyButton = menuButton("daily", "🎁 Daily", C.gold)
local inviteButton = UI.button(menu, "📣 Invite", C.green, function()
	SFX.click()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = "Come see my boarding school! Friends give each other +10% income 💸"
		pcall(SocialService.PromptGameInvite, SocialService, player, opts)
	else
		toast("Invites aren't available right now.", "error")
	end
end, { Size = UDim2.fromOffset(120, 50), TextSize = 19 })
local shopButton = menuButton("shop", "🛒 Shop", C.red)
shopButton.Visible = false

---------------------------------------------------------------------------
-- Panel frame
---------------------------------------------------------------------------
local panel = UI.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.52, 0.55),
	Size = UDim2.fromScale(0.62, 0.72),
	BackgroundColor3 = C.panel,
	Visible = false,
	Parent = gui,
})
UI.corner(panel, 18)
UI.stroke(panel, Color3.new(0, 0, 0), 3)
UI.new("UISizeConstraint", { MaxSize = Vector2.new(820, 620), MinSize = Vector2.new(340, 300), Parent = panel })
local panelTitle = UI.text(panel, "", 28, C.gold, {
	Size = UDim2.new(1, -70, 0, 44),
	Position = UDim2.fromOffset(18, 8),
})
UI.button(panel, "✕", C.red, function()
	openPanel(nil)
end, { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), TextSize = 22 })
local toolbar = UI.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 56),
	Size = UDim2.new(1, -32, 0, 44),
	Parent = panel,
})
UI.list(toolbar, 8, true)
local scroll = UI.new("ScrollingFrame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 106),
	Size = UDim2.new(1, -32, 1, -120),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 8,
	BorderSizePixel = 0,
	Parent = panel,
})

local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function resetLayout(kind, cellSize)
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("UIListLayout") or c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
	if kind == "grid" then
		UI.new("UIGridLayout", {
			CellSize = cellSize or UDim2.fromOffset(170, 190),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	else
		UI.list(scroll, 10)
	end
end

---------------------------------------------------------------------------
-- Reusable bits
---------------------------------------------------------------------------
local function roomOf(uid)
	for i, room in ipairs(State.data.rooms) do
		for _, occ in ipairs(room.occupants) do
			if occ == uid then
				return i
			end
		end
	end
	return nil
end

local function studentCard(parent, uid, s, extra)
	local def = Config.StudentById[s.id]
	local rarity = Config.Rarities[def.rarity]
	local pers = Config.Personalities[def.personality]
	local f = UI.card(parent, { BackgroundColor3 = C.card })
	UI.stroke(f, rarity.color, rarity.rank >= 5 and 4 or 2)
	if rarity.rank >= 4 then
		UI.new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), rarity.color:Lerp(Color3.new(1, 1, 1), 0.4)),
			Rotation = 90,
			Parent = f,
		})
	end
	UI.pad(f, 8)
	UI.text(f, pers.emoji, 38, C.text, { Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(f, (s.shiny and "✨" or "") .. def.name, 16, C.text, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 38), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(f, def.rarity .. " • " .. def.personality, 13, rarity.color, { Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	if def.trait then
		UI.text(f, def.trait.text, 12, C.sub, { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	end
	if extra then
		extra(f, def, rarity)
	end
	return f
end

local function smallButton(parent, text, color, onClick, y)
	return UI.button(parent, text, color, onClick, {
		Size = UDim2.new(1, 0, 0, 30),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, y or 0),
		TextSize = 15,
	})
end

---------------------------------------------------------------------------
-- Gacha reveal
---------------------------------------------------------------------------
local overlay = UI.new("TextButton", {
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.25,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 50,
	Parent = gui,
})
local revealGrid = UI.new("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromScale(0.9, 0.7),
	ZIndex = 51,
	Parent = overlay,
})
local revealHint = UI.text(overlay, "Tap to continue", 22, C.sub, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -30),
	Size = UDim2.fromOffset(400, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 52,
})
local revealBusy = false
overlay.Activated:Connect(function()
	if not revealBusy then
		overlay.Visible = false
	end
end)

local function flash(color)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = color
	cc.Brightness = 0.4
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.8), { Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	task.delay(0.9, function()
		cc:Destroy()
	end)
end

local function reveal(results)
	if not results or #results == 0 then
		return
	end
	openPanel(nil)
	clear(revealGrid)
	for _, c in ipairs(revealGrid:GetChildren()) do
		c:Destroy()
	end
	local single = #results == 1
	UI.new("UIGridLayout", {
		CellSize = single and UDim2.fromOffset(240, 300) or UDim2.fromOffset(150, 190),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = revealGrid,
	})
	overlay.Visible = true
	revealBusy = true
	revealHint.Visible = false
	local best = 0
	for i, r in ipairs(results) do
		local def = Config.StudentById[r.id]
		local rarity = Config.Rarities[def.rarity]
		best = math.max(best, rarity.rank)
		-- mystery card first, then flip
		local card = UI.card(revealGrid, { BackgroundColor3 = Color3.fromRGB(70, 60, 110), LayoutOrder = i, ZIndex = 53 })
		UI.stroke(card, Color3.new(1, 1, 1), 3)
		local q = UI.text(card, "?", single and 120 or 70, C.text, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 54 })
		UI.pop(card, 0.3)
		task.wait(single and 0.6 or 0.18)
		q:Destroy()
		card.BackgroundColor3 = rarity.color:Lerp(Color3.new(0, 0, 0), 0.45)
		card:FindFirstChildOfClass("UIStroke").Color = rarity.color
		local pers = Config.Personalities[def.personality]
		local big = single and 1.5 or 1
		UI.text(card, pers.emoji, 54 * big, C.text, { Size = UDim2.new(1, 0, 0, 64 * big), Position = UDim2.fromOffset(0, 8), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 54 })
		UI.text(card, (r.shiny and "✨ " or "") .. def.name, 17 * big, C.text, { Size = UDim2.new(1, -8, 0, 44 * big), Position = UDim2.new(0, 4, 0, 72 * big), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 54 })
		UI.text(card, string.upper(def.rarity), 18 * big, rarity.color, { Size = UDim2.new(1, 0, 0, 24 * big), Position = UDim2.fromOffset(0, 118 * big), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 54 })
		if r.new then
			UI.text(card, "NEW!", 14 * big, C.gold, { Size = UDim2.fromOffset(60, 20), Position = UDim2.fromOffset(6, 4), ZIndex = 55 })
		end
		if def.trait then
			UI.text(card, def.trait.text, 12 * big, Color3.fromRGB(230, 230, 230), { Size = UDim2.new(1, -8, 0, 30 * big), Position = UDim2.new(0, 4, 0, 144 * big), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 54 })
		end
		UI.pop(card, 1.3)
		SFX.reveal(rarity.rank)
		if rarity.rank >= 5 then
			flash(rarity.color)
			task.wait(0.4)
		end
	end
	if best >= 5 then
		local banner = UI.text(overlay, best == 6 and "🌈 MYTHIC!! 🌈" or "⭐ LEGENDARY! ⭐", 56, best == 6 and Config.Rarities.Mythic.color or C.gold, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 40),
			Size = UDim2.fromOffset(700, 70),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 60,
		})
		UI.pop(banner, 0.2)
		task.delay(3, function()
			banner:Destroy()
		end)
	end
	revealBusy = false
	revealHint.Visible = true
end

Remotes:WaitForChild("PullResult").OnClientEvent:Connect(reveal)

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------
local Render = {}

function Render.enroll()
	panelTitle.Text = "🎓 Admissions Office"
	resetLayout("list")
	local d = State.data
	local owned = 0
	for _ in pairs(d.students) do
		owned += 1
	end
	UI.text(scroll, string.format("⭐ Legendary guaranteed in <b>%d</b> pulls  •  Shiny chance 1 in %d  •  Roster %d/%d (bigger roster = pricier admissions)", Config.PityPulls - d.pity, math.floor(1 / Config.ShinyChance), owned, Config.MaxStudents), 15, C.sub, { Size = UDim2.new(1, 0, 0, 40) })
	for i, banner in ipairs(Config.Banners) do
		local f = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 132), LayoutOrder = i, BackgroundColor3 = banner.color:Lerp(C.card, 0.65) })
		UI.stroke(f, banner.color, 3)
		UI.pad(f, 10)
		UI.text(f, banner.name, 24, C.text, { Size = UDim2.new(0.6, 0, 0, 30) })
		local odds = {}
		for _, r in ipairs(Config.RarityOrder) do
			local w = banner.weights[r]
			if w > 0 then
				local c = Config.Rarities[r].color
				table.insert(odds, string.format('<font color="#%s">%s %s%%</font>', c:ToHex(), r, tostring(w)))
			end
		end
		UI.text(f, table.concat(odds, "  "), 14, C.text, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(0.62, 0, 0, 60) })
		local col = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.36, 0, 1, 0), Parent = f })
		UI.list(col, 6)
		local cost1 = Config.PullCost(banner, owned)
		local afford1 = d.cash >= cost1
		local cost10 = math.floor(cost1 * 10 * 0.9)
		UI.button(col, "x1  $" .. fmt(cost1), afford1 and C.green or Color3.fromRGB(110, 110, 120), function()
			local res = call("pull", { banner = banner.id, count = 1 })
			if result(res) then
				reveal(res.results)
			end
		end, { Size = UDim2.new(1, 0, 0, 34) })
		UI.button(col, "x10  $" .. fmt(cost10) .. " (-10%)", d.cash >= cost10 and C.green or Color3.fromRGB(110, 110, 120), function()
			local res = call("pull", { banner = banner.id, count = 10 })
			if result(res) then
				reveal(res.results)
			end
		end, { Size = UDim2.new(1, 0, 0, 34), TextSize = 15 })
		if banner.id == "royal" then
			for _, p in ipairs({ { key = "RoyalPull", text = "x1  R$" }, { key = "RoyalPull10", text = "x10  R$" } }) do
				local id = State.products and State.products[p.key]
				if id and id ~= 0 then
					UI.button(col, p.text, C.gold, function()
						MarketplaceService:PromptProductPurchase(player, id)
					end, { Size = UDim2.new(0.48, 0, 0, 26), TextSize = 14 })
				end
			end
		end
	end
	UI.text(scroll, "Tip: two students with great chemistry in one room earn way more. Check the Rooms tab!", 15, C.sub, { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 40) })
end

-- Room detail (with student picker that previews chemistry)
local function renderRoom(index)
	local d = State.data
	local room = d.rooms[index]
	if not room then
		panelState.room = nil
		return Render.rooms()
	end
	local tier = Config.RoomTiers[room.tier]
	local stats = SchoolMath.room(d, index, room.occupants, State.mult)
	local decor = tier.decor + House.roomDecor(d, index)
	panelTitle.Text = string.format("🛏 Room %d • %s", index, tier.name)
	resetLayout("list")
	UI.button(toolbar, "← All rooms", C.card, function()
		panelState.room = nil
		openPanel("rooms")
	end, { Size = UDim2.fromOffset(130, 40) })
	UI.button(toolbar, "🎨 Decorate", Color3.fromRGB(240, 140, 60), function()
		panelState.area = "r" .. index
		openPanel("design")
	end, { Size = UDim2.fromOffset(140, 40) })
	if Config.RoomTiers[room.tier + 1] then
		UI.text(toolbar, "⬆ Upgrades are pinned on the storyboard in your room", 14, C.sub, { Size = UDim2.fromOffset(240, 40) })
	end

	UI.text(scroll, string.format("%s Satisfaction <b>%d%%</b>   💰 <b>$%s/s</b>   🛏 %d/%d beds   🎀 decor +%d", SchoolMath.moodEmoji(stats.satisfaction), math.floor(stats.satisfaction), fmt(stats.income), #room.occupants, tier.beds, decor), 18, C.text, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26) })

	-- beds
	local bedRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = scroll })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 195), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bedRow })
	for b = 1, tier.beds do
		local uid = room.occupants[b]
		if uid and d.students[uid] then
			local card = studentCard(bedRow, uid, d.students[uid], function(f)
				local st = stats.students[uid]
				UI.text(f, string.format("%s %d%%  $%s/s", SchoolMath.moodEmoji(st.sat), math.floor(st.sat), fmt(st.income)), 14, C.green, { Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
				smallButton(f, "Move out", C.red, function()
					result(call("unassign", { uid = uid }))
				end)
			end)
			card.LayoutOrder = b
		else
			local card = UI.card(bedRow, { LayoutOrder = b, BackgroundColor3 = Color3.fromRGB(50, 48, 75) })
			UI.stroke(card, C.sub, 2).Transparency = 0.5
			UI.text(card, "🛏\nEmpty bed", 22, C.sub, { Size = UDim2.new(1, 0, 1, -40), TextXAlignment = Enum.TextXAlignment.Center })
			local pad = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = card })
			UI.pad(pad, 8)
			smallButton(pad, "+ Add student", C.green, function()
				panelState.picking = true
				openPanel("rooms")
			end)
		end
	end

	-- chemistry between roommates
	if #room.occupants >= 2 then
		local lines = {}
		for a = 1, #room.occupants do
			for b = a + 1, #room.occupants do
				local da = Config.StudentById[d.students[room.occupants[a]].id]
				local db = Config.StudentById[d.students[room.occupants[b]].id]
				local c = SchoolMath.pairChemistry(da, db)
				table.insert(lines, string.format("%s  %s + %s  (%s%d)", SchoolMath.chemEmoji(c), da.name, db.name, c >= 0 and "+" or "", c * Config.ChemistryPoints))
			end
		end
		UI.text(scroll, "<b>Chemistry</b>\n" .. table.concat(lines, "\n"), 16, C.text, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) })
	end

	-- picker
	if panelState.picking and #room.occupants < tier.beds then
		UI.text(scroll, "<b>Pick a roommate</b>  (sorted by how much this room would earn)", 18, C.gold, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 26) })
		local options = {}
		for uid, s in pairs(d.students) do
			local where = roomOf(uid)
			if where ~= index then
				local trial = table.clone(room.occupants)
				table.insert(trial, uid)
				local preview = SchoolMath.room(d, index, trial, State.mult)
				table.insert(options, { uid = uid, s = s, where = where, preview = preview })
			end
		end
		table.sort(options, function(a, b)
			if (a.where == nil) ~= (b.where == nil) then
				return a.where == nil
			end
			return a.preview.income > b.preview.income
		end)
		local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = scroll })
		UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 200), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, o in ipairs(options) do
			if i > 40 then
				break
			end
			local card = studentCard(grid, o.uid, o.s, function(f)
				local delta = o.preview.income - stats.income
				UI.text(f, string.format("%s room → %d%%  (+$%s/s)", SchoolMath.moodEmoji(o.preview.satisfaction), math.floor(o.preview.satisfaction), fmt(delta)), 13, delta > 0 and C.green or C.red, { Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
				smallButton(f, o.where and ("Move from Room " .. o.where) or "Move in", o.where and C.blue or C.green, function()
					result(call("assign", { uid = o.uid, room = index }))
				end)
			end)
			card.LayoutOrder = i
		end
		if #options == 0 then
			UI.text(scroll, "No students available. Enroll more in the Admissions Office!", 16, C.sub, { LayoutOrder = 6 })
		end
	end
end

function Render.rooms()
	if panelState.room then
		return renderRoom(panelState.room)
	end
	local d = State.data
	panelTitle.Text = "🛏 Dorm Rooms"
	resetLayout("list")
	UI.button(toolbar, "⚡ Auto-Arrange", C.purple, function()
		result(call("autoArrange"), "Students rearranged for max income!")
	end, { Size = UDim2.fromOffset(170, 40) })
	UI.text(toolbar, "🔨 New rooms are pinned on the storyboard in your room", 14, C.sub, { Size = UDim2.fromOffset(260, 40) })
	for i, room in ipairs(d.rooms) do
		local tier = Config.RoomTiers[room.tier]
		local stats = SchoolMath.room(d, i, room.occupants, State.mult)
		local f = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 74), LayoutOrder = i })
		UI.pad(f, 10)
		local floor = House.floorOf(d, "r" .. i)
		UI.text(f, string.format("Room %d  <font color=\"#bbb6dc\">Floor %d • %s</font>", i, floor, tier.name), 20, C.text, { Size = UDim2.new(0.7, 0, 0, 26) })
		local names = {}
		for _, uid in ipairs(room.occupants) do
			local s = d.students[uid]
			if s then
				local def = Config.StudentById[s.id]
				table.insert(names, string.format('<font color="#%s">%s %s</font>', Config.Rarities[def.rarity].color:ToHex(), Config.Personalities[def.personality].emoji, def.name))
			end
		end
		for _ = #room.occupants + 1, tier.beds do
			table.insert(names, "🛏 empty")
		end
		UI.text(f, table.concat(names, "   "), 14, C.sub, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(0.72, 0, 0, 28) })
		UI.text(f, #room.occupants > 0 and string.format("%s %d%%\n$%s/s", SchoolMath.moodEmoji(stats.satisfaction), math.floor(stats.satisfaction), fmt(stats.income)) or "empty", 16, C.green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -110, 0, 4), Size = UDim2.fromOffset(110, 48), TextXAlignment = Enum.TextXAlignment.Right })
		UI.button(f, "Open", C.blue, function()
			panelState.room = i
			panelState.picking = #room.occupants < tier.beds
			openPanel("rooms")
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(90, 40) })
	end
end

function Render.students()
	local d = State.data
	panelTitle.Text = "👥 Students"
	resetLayout("grid", UDim2.fromOffset(160, 200))
	local filter = panelState.filter or "all"
	for _, f in ipairs({ { "all", "All" }, { "unhoused", "Unhoused" }, { "book", "📖 Collection" } }) do
		UI.button(toolbar, f[2], filter == f[1] and C.purple or C.card, function()
			panelState.filter = f[1]
			openPanel("students")
		end, { Size = UDim2.fromOffset(130, 40) })
	end

	if filter == "book" then
		local found = 0
		for i, def in ipairs(Config.Students) do
			local known = d.discovered[def.id]
			if known then
				found += 1
			end
			local rarity = Config.Rarities[def.rarity]
			local f = UI.card(scroll, { LayoutOrder = rarity.rank * 100 + i, BackgroundColor3 = known and C.card or Color3.fromRGB(35, 33, 50) })
			UI.stroke(f, rarity.color, 2)
			UI.pad(f, 8)
			UI.text(f, known and Config.Personalities[def.personality].emoji or "❔", 38, C.text, { Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center })
			UI.text(f, known and def.name or "???", 16, C.text, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 38), TextXAlignment = Enum.TextXAlignment.Center })
			UI.text(f, def.rarity, 13, rarity.color, { Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
			if known and def.trait then
				UI.text(f, def.trait.text, 12, C.sub, { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
			end
		end
		panelTitle.Text = string.format("📖 Collection  %d/%d", found, #Config.Students)
		return
	end

	local list = {}
	for uid, s in pairs(d.students) do
		local where = roomOf(uid)
		if filter == "all" or not where then
			local def = Config.StudentById[s.id]
			table.insert(list, { uid = uid, s = s, where = where, rank = Config.Rarities[def.rarity].rank + (s.shiny and 0.5 or 0) })
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.uid < b.uid
	end)
	panelTitle.Text = string.format("👥 Students  %d/%d", #list, Config.MaxStudents)
	for i, e in ipairs(list) do
		local card = studentCard(scroll, e.uid, e.s, function(f, def, rarity)
			UI.text(f, e.where and ("🛏 Room " .. e.where) or "😴 Unhoused (earns $0)", 13, e.where and C.green or C.red, { Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
			local value = rarity.expel * (e.s.shiny and 3 or 1)
			local armed = panelState.expel == e.uid
			smallButton(f, armed and "Tap again to confirm" or ("Expel +$" .. fmt(value)), armed and C.red or Color3.fromRGB(150, 70, 80), function()
				if panelState.expel == e.uid then
					panelState.expel = nil
					result(call("expel", { uid = e.uid }), def.name .. " was expelled. +$" .. fmt(value))
				else
					panelState.expel = e.uid
					openPanel("students")
				end
			end)
		end)
		card.LayoutOrder = i
	end
	if #list == 0 then
		UI.text(scroll, "Nobody here! 🎉", 18, C.sub)
	end
end

-- the storyboard on the wall of your room: every build is a sticky note
function Render.storyboard()
	local d = State.data
	panelTitle.Text = "📌 School Plans"
	resetLayout("grid", UDim2.fromOffset(180, 170))
	UI.text(toolbar, string.format("🏠 %d dorm rooms on %d floors (max %d rooms)", #d.rooms, House.floorCount(d), Config.MaxRooms), 16, C.sub, { Size = UDim2.fromOffset(420, 40) })
	local notes = House.notes(d)
	for i, n in ipairs(notes) do
		local paper = House.NoteColors[n.kind]
		local f = UI.card(scroll, { LayoutOrder = i, BackgroundColor3 = paper })
		f.Rotation = ((i * 37) % 7 - 3) * 0.6
		local highlight = panelState.note == n.key
		UI.stroke(f, highlight and C.red or Color3.fromRGB(120, 100, 60), highlight and 4 or 1)
		UI.pad(f, 10)
		local ink = Color3.fromRGB(50, 40, 40)
		UI.text(f, "📍", 18, C.text, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -14), Size = UDim2.fromOffset(24, 24), TextXAlignment = Enum.TextXAlignment.Center })
		UI.text(f, n.emoji .. " " .. n.title, 18, ink, { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 44), TextStrokeTransparency = 1 })
		UI.text(f, n.text, 13, Color3.fromRGB(90, 80, 80), { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 40) })
		local afford = d.cash >= n.cost
		smallButton(f, "Do it! $" .. fmt(n.cost), afford and C.green or Color3.fromRGB(130, 130, 140), function()
			local res = call("note", { key = n.key })
			if result(res, (n.newFloor and "🏗 A whole new floor! " or "✅ ") .. n.title .. " done!") then
				panelState.note = nil
			end
		end)
	end
	if #notes == 0 then
		UI.text(scroll, "🎉 Everything is built. You run the fanciest house in town!", 18, C.gold)
	end
end

-- Build mode: paint walls/floors/roof of any area, furnish your own room
local function swatches(kind, area, current)
	local list = Config.StyleLists[kind]
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = scroll })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(118, 104), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, st in ipairs(list) do
		local chosen = current.id == st.id
		local b = UI.button(grid, "", st.color, function()
			if chosen then
				return
			end
			result(call("paint", { area = area, part = kind, style = st.id }), st.cost > 0 and (st.name .. " applied! -$" .. fmt(st.cost)) or nil)
		end, { LayoutOrder = i, Size = UDim2.fromOffset(118, 104) })
		local stroke = b:FindFirstChildOfClass("UIStroke")
		stroke.Color = chosen and C.gold or Color3.new(0, 0, 0)
		stroke.Thickness = chosen and 4 or 2
		stroke.Transparency = 0
		local tag = UI.new("Frame", { BackgroundColor3 = C.bg, BackgroundTransparency = 0.2, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 46), Parent = b })
		UI.corner(tag, 8)
		UI.text(tag, st.name, 13, C.text, { Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 2), TextXAlignment = Enum.TextXAlignment.Center })
		local info = chosen and "✓ current" or (st.cost == 0 and "free" or ("$" .. fmt(st.cost)))
		if st.decor and st.decor > 0 and kind ~= "roof" then
			info ..= "  🎀+" .. st.decor
		end
		UI.text(tag, info, 12, chosen and C.gold or C.green, { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 24), TextXAlignment = Enum.TextXAlignment.Center })
	end
	return grid
end

function Render.design()
	local d = State.data
	panelTitle.Text = "🎨 Build Mode"
	resetLayout("list")
	local areas = House.areas(d)
	local area = House.validArea(d, panelState.area or "") or areas[3]
	panelState.area = area.key
	UI.text(toolbar, "Pick a part of your house, then a material. 🎀 decor in dorm rooms makes students happier.", 14, C.sub, { Size = UDim2.new(1, 0, 1, 0) })

	local picker = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = scroll })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 36), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = picker })
	for i, a in ipairs(areas) do
		UI.button(picker, a.name, a.key == area.key and C.purple or C.card, function()
			panelState.area = a.key
			openPanel("design")
		end, { LayoutOrder = i, TextSize = 15 })
	end

	local order = 2
	local names = { wall = "🧱 Walls", floor = "🟫 Floor", roof = "🏠 Roof" }
	for _, kind in ipairs(area.parts) do
		UI.text(scroll, string.format("<b>%s</b> — %s", names[kind], area.name), 20, C.gold, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 28) })
		swatches(kind, area.key, House.style(d, area.key, kind)).LayoutOrder = order + 1
		order += 2
	end

	if area.key == "me" then
		UI.text(scroll, "<b>🛋 Furniture</b> — every piece gives your whole house a small income boost", 20, C.gold, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 28) })
		for i, f in ipairs(Config.Furniture) do
			local owned = d.furniture[f.id]
			local card = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = order + i })
			UI.pad(card, 8)
			UI.text(card, f.emoji .. " " .. f.name, 18, C.text, { Size = UDim2.new(0.6, 0, 0, 22) })
			UI.text(card, string.format("+%d%% income", math.floor(f.incomeMult * 100 + 0.5)), 14, C.green, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(0.6, 0, 0, 18) })
			local text, color
			if owned == nil then
				text, color = "Buy $" .. fmt(f.cost), d.cash >= f.cost and C.green or Color3.fromRGB(110, 110, 120)
			elseif owned then
				text, color = "Hide", C.card
			else
				text, color = "Place", C.blue
			end
			UI.button(card, text, color, function()
				result(call("furniture", { id = f.id }), owned == nil and (f.name .. " added to your room!") or nil)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 36) })
		end
	end
end

function Render.visit()
	panelTitle.Text = "🗺 Visit Houses"
	resetLayout("list")
	UI.button(toolbar, "🏠 Go Home", C.blue, function()
		call("visit", {})
		openPanel(nil)
	end, { Size = UDim2.fromOffset(140, 40) })
	UI.text(scroll, "Visit other houses, steal decorating ideas, and leave a ❤ — every like pays the owner a minute of income!", 16, C.sub, { Size = UDim2.new(1, 0, 0, 44) })
	local plots = workspace:FindFirstChild("BSTWorld")
	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			count += 1
			local f = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 60), LayoutOrder = count })
			UI.pad(f, 10)
			UI.text(f, other.DisplayName .. "'s House", 20, C.text, { Size = UDim2.new(0.5, 0, 0, 24) })
			local ls = other:FindFirstChild("leaderstats")
			local inc = ls and ls:FindFirstChild("Income")
			local likes = ls and ls:FindFirstChild("Likes")
			UI.text(f, string.format("$%s/s  •  ❤ %s", fmt(inc and inc.Value or 0), fmt(likes and likes.Value or 0)), 15, C.sub, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.5, 0, 0, 20) })
			local row = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(240, 40), Parent = f })
			UI.list(row, 8, true, Enum.HorizontalAlignment.Right)
			UI.button(row, "Visit", C.blue, function()
				call("visit", { userId = other.UserId })
				openPanel(nil)
			end, { Size = UDim2.fromOffset(100, 40) })
			UI.button(row, "❤ Like", C.pink, function()
				result(call("like", { userId = other.UserId }), "❤ You liked " .. other.DisplayName .. "'s house! +$50")
			end, { Size = UDim2.fromOffset(100, 40) })
		end
	end
	if count == 0 then
		UI.text(scroll, "You're the only one here... invite friends! Each friend in the server gives you +10% income. 📣", 18, C.gold, { Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1 })
	end
	local _ = plots
end

function Render.daily()
	local d = State.data
	panelTitle.Text = "🎁 Daily Free Admission"
	resetLayout("list")
	local ready = (State.dailyAt or 0) <= os.time()
	UI.text(scroll, "Every day you get one FREE Honors Admission (up to 3% Legendary+). Come back daily!", 18, C.text, { Size = UDim2.new(1, 0, 0, 50) })
	if ready then
		UI.button(scroll, "🎁 Claim free student!", C.gold, function()
			local res = call("daily")
			if result(res) then
				reveal(res.results)
			end
		end, { Size = UDim2.fromOffset(300, 60), TextSize = 22 })
	else
		UI.text(scroll, "Next free admission in " .. UI.formatTime(State.dailyAt - os.time()), 22, C.gold, { Size = UDim2.new(1, 0, 0, 30) })
	end
	local _ = d
end

function Render.shop()
	panelTitle.Text = "🛒 Shop"
	resetLayout("list")
	local passes = {
		{ key = "DoubleCash", name = "💸 2x Cash", text = "Double ALL income forever" },
		{ key = "Lucky", name = "🍀 Lucky Admissions", text = "+50% Legendary & Mythic odds" },
		{ key = "VIP", name = "👑 VIP", text = "+10% income and VIP status" },
	}
	for i, p in ipairs(passes) do
		local id = State.gamePasses and State.gamePasses[p.key]
		if id and id ~= 0 then
			local f = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i })
			UI.pad(f, 10)
			UI.text(f, p.name, 20, C.gold, { Size = UDim2.new(0.6, 0, 0, 24) })
			UI.text(f, p.text, 15, C.sub, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.6, 0, 0, 20) })
			if State.passes and State.passes[p.key] then
				UI.text(f, "✅ Owned", 18, C.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(140, 30), TextXAlignment = Enum.TextXAlignment.Right })
			else
				UI.button(f, "Buy", C.green, function()
					MarketplaceService:PromptGamePassPurchase(player, id)
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(120, 40) })
			end
		end
	end
	local products = {
		{ key = "CashSmall", name = "💰 Cash Bag", text = "10 minutes of income instantly" },
		{ key = "RoyalPull", name = "👑 Royal Admission", text = "One Royal pull (8.5% Legendary)" },
		{ key = "RoyalPull10", name = "👑 Royal Admission x10", text = "Ten Royal pulls" },
	}
	for i, p in ipairs(products) do
		local id = State.products and State.products[p.key]
		if id and id ~= 0 then
			local f = UI.card(scroll, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 10 + i })
			UI.pad(f, 10)
			UI.text(f, p.name, 20, C.gold, { Size = UDim2.new(0.6, 0, 0, 24) })
			UI.text(f, p.text, 15, C.sub, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.6, 0, 0, 20) })
			UI.button(f, "Buy", C.green, function()
				MarketplaceService:PromptProductPurchase(player, id)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(120, 40) })
		end
	end
end

openPanel = function(id)
	if id ~= currentPanel then
		if id ~= "rooms" then
			panelState.room = nil
		end
		if id ~= "storyboard" then
			panelState.note = nil
		end
		panelState.expel = nil
		scroll.CanvasPosition = Vector2.zero
	end
	currentPanel = id
	for key, b in pairs(menuButtons) do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		stroke.Color = key == id and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		stroke.Transparency = key == id and 0 or 0.5
	end
	if not id or not State.data then
		panel.Visible = false
		currentPanel = nil
		return
	end
	clear(toolbar)
	clear(scroll)
	local keep = scroll.CanvasPosition
	local wasVisible = panel.Visible
	panel.Visible = true
	Render[id]()
	scroll.CanvasPosition = keep
	if not wasVisible then
		UI.pop(panel, 0.85)
	end
end

local function refresh()
	if currentPanel then
		openPanel(currentPanel)
	end
end

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------
Remotes:WaitForChild("State").OnClientEvent:Connect(function(st)
	local first = State.data == nil
	State.data = st.data
	State.income = st.income
	State.satisfaction = st.satisfaction
	State.mult = st.mult
	State.passes = st.passes
	State.gamePasses = st.gamePasses
	State.products = st.products
	State.dailyAt = os.time() + st.dailyIn
	setCash(st.data.cash, st.income)
	moodLabel.Text = SchoolMath.moodEmoji(st.satisfaction) .. " " .. math.floor(st.satisfaction) .. "%"
	likeLabel.Text = "❤ " .. fmt(st.data.likes)
	local anyShop = false
	for _, id in pairs(st.gamePasses) do
		anyShop = anyShop or id ~= 0
	end
	for _, id in pairs(st.products) do
		anyShop = anyShop or id ~= 0
	end
	shopButton.Visible = anyShop
	refresh()
	if first and not st.data.tutorialDone then
		task.delay(1.5, function()
			local steps = {
				"🏠 Welcome, Headmaster! This is your room. You live in this boarding house with your students.",
				"🛏 Walk out into the hallway, go to a dorm door and press <b>E</b> (or open <b>Rooms</b>) to move your 2 students in. Housed students earn cash every second.",
				"💞 Roommates have <b>chemistry</b>! Nerds + Gamers are besties, Royals hate Rebels. Happy rooms earn up to 2x more.",
				"🎓 Use <b>Enroll</b> to recruit new students. Find Legendary & Mythic ones and shiny ✨ variants!",
				"📌 Your <b>storyboard</b> (the corkboard on your wall) holds every plan: new rooms, upgrades, a Gym, a Pool... Walk up to it and press <b>E</b>.",
				"🎨 Use <b>Build</b> to pick materials for walls, floors and the roof, and to furnish your room. Nicer dorms = happier students!",
			}
			local box = UI.card(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(520, 110), BackgroundColor3 = C.bg })
			UI.stroke(box, C.gold, 3)
			UI.pad(box, 12)
			local t = UI.text(box, steps[1], 18, C.text, { Size = UDim2.new(1, 0, 1, -40) })
			local i = 1
			UI.button(box, "Next ▶", C.green, function()
				i += 1
				if steps[i] then
					t.Text = steps[i]
				else
					box:Destroy()
					call("tutorialDone")
				end
			end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(110, 34) })
			UI.pop(box)
		end)
	end
end)

Remotes:WaitForChild("Tick").OnClientEvent:Connect(function(cash, inc)
	if State.data then
		State.data.cash = cash
	end
	setCash(cash, inc)
end)

local function welcomeBack(info)
	local box = UI.card(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 230), BackgroundColor3 = C.panel, ZIndex = 40 })
	UI.stroke(box, C.gold, 4)
	UI.pad(box, 16)
	UI.text(box, "👋 Welcome back, Headmaster!", 26, C.gold, { Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	UI.text(box, string.format("While you were away for %s your students earned", UI.formatTime(info.seconds)), 17, C.text, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	UI.text(box, "$" .. fmt(info.amount), 40, C.green, { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 48), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	local row = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 44), Parent = box, ZIndex = 41 })
	UI.list(row, 10, true, Enum.HorizontalAlignment.Center)
	UI.button(row, "Collect", C.green, function()
		SFX.coin()
		box:Destroy()
	end, { Size = UDim2.fromOffset(150, 44), ZIndex = 42 })
	local id = State.products and State.products.DoubleOffline
	if id and id ~= 0 then
		UI.button(row, "2x it! (R$)", C.gold, function()
			MarketplaceService:PromptProductPurchase(player, id)
			box:Destroy()
		end, { Size = UDim2.fromOffset(150, 44), ZIndex = 42 })
	end
	UI.pop(box)
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, kind)
	if typeof(text) == "table" and text.kind == "welcomeBack" then
		welcomeBack(text)
	else
		toast(text, kind)
		if kind == "like" then
			SFX.coin()
		end
	end
end)

local announceBar = UI.text(gui, "", 24, C.gold, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 72),
	Size = UDim2.fromOffset(800, 34),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0,
	Visible = false,
})
local announceToken = 0
Remotes:WaitForChild("Announce").OnClientEvent:Connect(function(info)
	local text
	if info.floor then
		text = string.format("🏢 %s's boarding house just grew to %d floors!", info.player, info.floor)
	else
		local color = Config.Rarities[info.rarity].color
		announceBar.TextColor3 = color
		text = string.format("🌟 %s enrolled %s%s %s!", info.player, info.shiny and "✨SHINY " or "", string.upper(info.rarity), info.student)
	end
	announceBar.Text = text
	announceBar.Visible = true
	UI.pop(announceBar, 0.5)
	announceToken += 1
	local token = announceToken
	task.delay(5, function()
		if token == announceToken then
			announceBar.Visible = false
			announceBar.TextColor3 = C.gold
		end
	end)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:DisplaySystemMessage(text)
		end
	end)
end)

---------------------------------------------------------------------------
-- World interactions (click rooms / lots in 3D)
---------------------------------------------------------------------------
local function hookClick(tag, fn)
	local function hook(inst)
		local cd = inst:FindFirstChildOfClass("ClickDetector") or inst:WaitForChild("ClickDetector", 5)
		if cd then
			cd.MouseClick:Connect(function()
				fn(inst)
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		task.spawn(hook, inst)
	end
end

local function openRoom(index)
	panelState.room = index
	local room = State.data and State.data.rooms[index]
	panelState.picking = room and #room.occupants < Config.RoomTiers[room.tier].beds
	SFX.click()
	openPanel("rooms")
end

hookClick("RoomClick", function(plate)
	if plate:GetAttribute("OwnerUserId") == player.UserId then
		openRoom(plate:GetAttribute("RoomIndex"))
	end
end)

hookClick("NoteClick", function(note)
	if note:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	panelState.note = note:GetAttribute("NoteKey")
	SFX.click()
	openPanel("storyboard")
end)

-- prompts only work in your own house
local function hookPrompt(tag, fn)
	local function hook(pp)
		if pp:GetAttribute("OwnerUserId") ~= player.UserId then
			pp.Enabled = false
			return
		end
		pp.Triggered:Connect(function()
			fn(pp)
		end)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(hook)
	for _, pp in ipairs(CollectionService:GetTagged(tag)) do
		hook(pp)
	end
end

hookPrompt("RoomPrompt", function(pp)
	openRoom(pp:GetAttribute("RoomIndex"))
end)

hookPrompt("StoryboardPrompt", function()
	panelState.note = nil
	SFX.click()
	openPanel("storyboard")
end)

local function hookLike(prompt)
	if prompt:GetAttribute("OwnerUserId") == player.UserId then
		prompt.Enabled = false
		return
	end
	prompt.Triggered:Connect(function()
		local owner = Players:GetPlayerByUserId(prompt:GetAttribute("OwnerUserId"))
		result(call("like", { userId = prompt:GetAttribute("OwnerUserId") }), "❤ You liked " .. (owner and owner.DisplayName or "this") .. "'s house! +$50")
	end)
end
CollectionService:GetInstanceAddedSignal("LikePrompt"):Connect(hookLike)
for _, p in ipairs(CollectionService:GetTagged("LikePrompt")) do
	hookLike(p)
end

-- live daily timer on the menu button
task.spawn(function()
	while true do
		task.wait(1)
		if State.dailyAt then
			local left = State.dailyAt - os.time()
			dailyButton.Text = left <= 0 and "🎁 FREE!" or ("🎁 " .. UI.formatTime(left))
			if currentPanel == "daily" and left >= -1 and left <= 0 then
				refresh()
			end
		end
	end
end)

-- keep the HUD readable on small phones
local camera = workspace.CurrentCamera
local function rescale()
	local w = camera.ViewportSize.X
	local s = math.clamp(w / 1100, 0.6, 1)
	for _, f in ipairs({ hud, menu }) do
		local sc = f:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = f })
		sc.Scale = s
	end
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

local _ = inviteButton

-- handlers are connected; ask for our state in case we missed the first push
call("state")
