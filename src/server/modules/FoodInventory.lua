-- FoodInventory.lua
-- Handles two food-management actions initiated by the client:
--   GiveFood  — transfer equipped food to a nearby player (12-stud range)
--   DropFood  — drop equipped food as a world Part with a ProximityPrompt pickup
--
-- The server owns all validation; the client only fires the event and reads
-- nearby players from its own character context (target passed as argument).

local Players = game:GetService("Players")

local FoodInventory = {}

local Config = nil

-- -------------------------------------------------------------------------
-- Helper: returns true for bat / carpet tools that must never be transferred
-- -------------------------------------------------------------------------
local function isProtectedTool(item)
	if not item or not item:IsA("Tool") then return true end
	local h = item:FindFirstChild("Handle")
	return h and (h:GetAttribute("IsBat") == true or h:GetAttribute("IsCarpet") == true)
end

-- -------------------------------------------------------------------------
-- Helper: find the first food tool in character + backpack
-- -------------------------------------------------------------------------
local function findFoodTool(player)
	local char = player.Character
	if char then
		local eq = char:FindFirstChildOfClass("Tool")
		if eq and not isProtectedTool(eq) then return eq end
	end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if not isProtectedTool(item) then return item end
	end
	return nil
end

-- -------------------------------------------------------------------------
-- Helper: recreate a food Part on the ground with a pickup prompt
-- -------------------------------------------------------------------------
local function spawnDroppedFood(foodTool, dropPos)
	local handle = foodTool:FindFirstChild("Handle")
	local foodName = foodTool.Name
	local basePrice    = (handle and handle:GetAttribute("BaseSellPrice"))    or 0
	local currentPrice = (handle and handle:GetAttribute("CurrentSellPrice")) or 0
	local rarity       = (handle and handle:GetAttribute("Rarity"))           or "Common"

	local part = Instance.new("Part")
	part.Name       = foodName .. "_Dropped"
	part.Size       = handle and handle.Size or Vector3.new(1, 1, 1)
	part.BrickColor = handle and handle.BrickColor or BrickColor.new("White")
	part.Material   = Enum.Material.SmoothPlastic
	part.Position   = dropPos
	part.Anchored   = false
	part.CanCollide = true
	part:SetAttribute("BaseSellPrice",    basePrice)
	part:SetAttribute("CurrentSellPrice", currentPrice)
	part:SetAttribute("Rarity",           rarity)
	part:SetAttribute("FoodId",           foodName)
	part.Parent = workspace

	-- Copy decals from handle
	if handle then
		for _, d in ipairs(handle:GetDescendants()) do
			if d:IsA("Decal") then
				d:Clone().Parent = part
			end
		end
	end

	-- Pickup ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText             = "Pick Up"
	pp.ObjectText             = foodName
	pp.KeyboardKeyCode        = Enum.KeyCode.E
	pp.RequiresLineOfSight    = false
	pp.MaxActivationDistance  = 8
	pp.Parent = part

	pp.Triggered:Connect(function(picker)
		if not part.Parent then return end

		-- Rebuild as a proper Tool
		local tool = Instance.new("Tool")
		tool.Name            = foodName
		tool.RequiresHandle  = true

		local newHandle = Instance.new("Part")
		newHandle.Name       = "Handle"
		newHandle.Size       = part.Size
		newHandle.BrickColor = part.BrickColor
		newHandle.Material   = Enum.Material.SmoothPlastic
		newHandle.CanCollide = false
		newHandle:SetAttribute("BaseSellPrice",    basePrice)
		newHandle:SetAttribute("CurrentSellPrice", currentPrice)
		newHandle:SetAttribute("Rarity",           rarity)
		newHandle:SetAttribute("FoodId",           foodName)

		-- Copy decals to new handle
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("Decal") then
				d:Clone().Parent = newHandle
			end
		end

		newHandle.Parent = tool
		tool.Parent = picker.Backpack
		part:Destroy()
	end)

	-- Safety despawn after 60 s so dropped food doesn't litter the map forever
	task.delay(60, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function FoodInventory.init(remoteEvents, config)
	Config = config

	-- -------------------------------------------------------------------
	-- GiveFood — sender passes the target Player instance as argument.
	-- Server validates proximity then moves the food tool.
	-- -------------------------------------------------------------------
	remoteEvents.GiveFood.OnServerEvent:Connect(function(sender, targetPlayer)
		-- Type-check the argument (clients can send anything)
		if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then return end
		if targetPlayer == sender then return end

		local senderChar = sender.Character
		local targetChar = targetPlayer.Character
		if not senderChar or not targetChar then return end

		local sHRP = senderChar:FindFirstChild("HumanoidRootPart")
		local tHRP = targetChar:FindFirstChild("HumanoidRootPart")
		if not sHRP or not tHRP then return end

		-- Proximity gate: 12 studs
		if (sHRP.Position - tHRP.Position).Magnitude > 12 then return end

		local foodTool = findFoodTool(sender)
		if not foodTool then return end

		-- Move to target's backpack
		foodTool.Parent = targetPlayer.Backpack
	end)

	-- -------------------------------------------------------------------
	-- DropFood — no argument needed; server drops whatever the player holds.
	-- -------------------------------------------------------------------
	remoteEvents.DropFood.OnServerEvent:Connect(function(player)
		local char = player.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local foodTool = findFoodTool(player)
		if not foodTool then return end

		local dropPos = hrp.Position + Vector3.new(0, -2, 0)
		spawnDroppedFood(foodTool, dropPos)
		foodTool:Destroy()
	end)
end

return FoodInventory
