-- FoodInventory.lua
-- Handles two food-management actions initiated by the client:
--   GiveFood  — transfer equipped food to a nearby player (12-stud range)
--   DropFood  — drop equipped food as a world Part with a ProximityPrompt pickup
--
-- The server owns all validation; the client only fires the event and reads
-- nearby players from its own character context (target passed as argument).
-- Only tools tagged IsFood can be given or dropped.

local ToolUtil = require(script.Parent.ToolUtil)

local FoodInventory = {}

local Config = nil
local RemoteEvents = nil

local GIVE_RANGE = 12
local DROPPED_FOOD_LIFETIME = 60

local function notify(player, text)
	if RemoteEvents and RemoteEvents.Notify then
		RemoteEvents.Notify:FireClient(player, text)
	end
end

local function canCarryMore(player)
	return ToolUtil.countFood(player) < (Config.MAX_FOOD_CARRIED or math.huge)
end

-- -------------------------------------------------------------------------
-- Helper: recreate a food Part on the ground with a pickup prompt
-- -------------------------------------------------------------------------
local function spawnDroppedFood(foodTool, dropPos)
	local handle = foodTool:FindFirstChild("Handle")
	local data = ToolUtil.readFoodData(foodTool)
	local foodType = data and ToolUtil.findFoodType(Config.FOOD_TYPES, data.id)
	if not handle or not foodType then
		return false
	end

	local part = Instance.new("Part")
	part.Name = foodType.name .. "_Dropped"
	part.Size = handle.Size
	part.BrickColor = handle.BrickColor
	part.Material = Enum.Material.SmoothPlastic
	part.Position = dropPos
	part.Anchored = false
	part.CanCollide = true
	ToolUtil.addFoodDecals(part, foodType)
	part.Parent = workspace
	ToolUtil.claimNetworkOwnership(part)

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Pick Up"
	pp.ObjectText = foodType.name
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = part

	local taken = false
	pp.Triggered:Connect(function(picker)
		if taken or not part.Parent then
			return
		end
		if not canCarryMore(picker) then
			notify(picker, "Your hands are full!")
			return
		end
		taken = true

		ToolUtil.makeFoodTool(foodType, {
			currentPrice = data.price,
			storedAtLevel = data.stored,
			multiplied = data.multiplied,
		}).Parent =
			picker.Backpack
		part:Destroy()
	end)

	-- Safety despawn so dropped food doesn't litter the map forever
	task.delay(DROPPED_FOOD_LIFETIME, function()
		if part.Parent then
			part:Destroy()
		end
	end)
	return true
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function FoodInventory.init(remoteEvents, config)
	Config = config
	RemoteEvents = remoteEvents

	-- GiveFood — sender passes the target Player instance as argument.
	remoteEvents.GiveFood.OnServerEvent:Connect(function(sender, targetPlayer)
		-- Type-check the argument (clients can send anything)
		if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
			return
		end
		if targetPlayer == sender then
			return
		end

		local senderChar = sender.Character
		local targetChar = targetPlayer.Character
		local sHRP = senderChar and senderChar:FindFirstChild("HumanoidRootPart")
		local tHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
		if not sHRP or not tHRP then
			return
		end
		if (sHRP.Position - tHRP.Position).Magnitude > GIVE_RANGE then
			return
		end

		local foodTool = ToolUtil.findFoodTool(sender)
		if not foodTool then
			return
		end
		if not canCarryMore(targetPlayer) then
			notify(sender, targetPlayer.Name .. "'s hands are full!")
			return
		end

		foodTool.Parent = targetPlayer.Backpack
		notify(targetPlayer, sender.Name .. " gave you " .. foodTool.Name)
	end)

	-- DropFood — no argument needed; server drops whatever food the player holds.
	remoteEvents.DropFood.OnServerEvent:Connect(function(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end

		local foodTool = ToolUtil.findFoodTool(player)
		if not foodTool then
			return
		end

		if spawnDroppedFood(foodTool, hrp.Position + Vector3.new(0, -2, 0)) then
			foodTool:Destroy()
		end
	end)
end

return FoodInventory
