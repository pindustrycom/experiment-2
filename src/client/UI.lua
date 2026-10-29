-- Tiny helper library for building bubbly, mobile-friendly UI in code.
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	bg = Color3.fromRGB(30, 28, 48),
	panel = Color3.fromRGB(45, 42, 70),
	card = Color3.fromRGB(62, 58, 95),
	text = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(190, 185, 220),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(240, 80, 90),
	gold = Color3.fromRGB(255, 200, 60),
	blue = Color3.fromRGB(80, 160, 255),
	pink = Color3.fromRGB(255, 110, 170),
	purple = Color3.fromRGB(160, 100, 255),
}

function UI.new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(parent, r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 12), Parent = parent })
end

function UI.stroke(parent, color, thickness)
	return UI.new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.pad(parent, px)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.list(parent, padding, horizontal, align)
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function UI.text(parent, text, size, color, props)
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color or UI.Colors.text,
		TextSize = size or 18,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, (size or 18) + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

function UI.button(parent, text, color, onClick, props)
	local b = UI.new("TextButton", {
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = color or UI.Colors.blue,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(140, 40),
		Parent = parent,
	})
	UI.corner(b, 10)
	UI.stroke(b, Color3.new(0, 0, 0), 2).Transparency = 0.5
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = b,
	})
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local scale = UI.new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function UI.card(parent, props)
	local f = UI.new("Frame", {
		BackgroundColor3 = UI.Colors.card,
		Size = UDim2.new(1, 0, 0, 80),
		Parent = parent,
	})
	UI.corner(f, 12)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	return f
end

function UI.pop(inst, from)
	local scale = inst:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = inst })
	scale.Scale = from or 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function UI.formatTime(sec)
	sec = math.max(0, math.floor(sec))
	local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return s .. "s"
end

return UI
