-- Sims-style cutaway: when you're inside a house, every floor above you (and
-- the roof) fades out so the camera can see into your floor. Purely local:
-- LocalTransparencyModifier only changes what this player sees, and faded
-- parts still collide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local FADE = 0.88

local world = workspace:WaitForChild("BSTWorld")
local plots = {}
for i = 1, 6 do
	table.insert(plots, world:WaitForChild("Plot" .. i))
end

local House = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("House"))
local B = House.Bounds

local applied = {} -- [plot model] = level it was faded for (nil = nothing faded)
local dirty = {}

local function levelOf(inst)
	local node = inst
	while node and node ~= world do
		local lv = node:GetAttribute("Level")
		if lv then
			return lv
		end
		node = node.Parent
	end
	return nil
end

local function setVisible(inst, visible)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = visible and 0 or FADE
		inst.CastShadow = visible
	elseif inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
		inst.Enabled = visible
	elseif inst:IsA("Decal") then
		inst.LocalTransparencyModifier = visible and 0 or 1
	elseif inst:IsA("ClickDetector") then
		inst.MaxActivationDistance = visible and (inst:GetAttribute("BaseDist") or inst.MaxActivationDistance) or 0
	end
end

local function apply(plot, level)
	for _, inst in ipairs(plot:GetDescendants()) do
		if inst:IsA("ClickDetector") and not inst:GetAttribute("BaseDist") then
			inst:SetAttribute("BaseDist", inst.MaxActivationDistance)
		end
		local lv = levelOf(inst)
		if lv then
			setVisible(inst, level == nil or lv <= level)
		end
	end
	applied[plot] = level
	dirty[plot] = nil
end

for _, plot in ipairs(plots) do
	plot.DescendantAdded:Connect(function()
		dirty[plot] = true
	end)
end

while true do
	task.wait(0.2)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	for _, plot in ipairs(plots) do
		local level = nil
		local origin = plot:GetAttribute("Origin")
		if root and origin then
			local p = origin:PointToObjectSpace(root.Position)
			if math.abs(p.X) < B.x and p.Z > B.z0 and p.Z < B.z1 then
				level = math.max(0, math.floor((p.Y - B.floorY) / House.FloorHeight))
			end
		end
		if applied[plot] ~= level or dirty[plot] then
			apply(plot, level)
		end
	end
end
