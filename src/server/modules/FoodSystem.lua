-- FoodSystem.lua
-- Handles spawning food on tables, E-key pickup via ProximityPrompt, and respawning.
-- Fires RemoteEvents to the client for visual effects.

local ToolUtil = require(script.Parent.ToolUtil)

local FoodSystem = {}

-- Injected from Main
local RemoteEvents = nil
local GameSystems = nil
local Config = nil

local DEFAULT_RESPAWN_TIME = 5

function FoodSystem.init(remoteEvents, gameSystems, config)
	RemoteEvents = remoteEvents
	GameSystems = gameSystems
	Config = config
end

local function notify(player, text)
	if RemoteEvents and RemoteEvents.Notify then
		RemoteEvents.Notify:FireClient(player, text)
	end
end

local function createFood(foodType, position)
	local food = Instance.new("Part")
	food.Name = foodType.name
	food.Size = foodType.size
	food.Position = position
	food.Anchored = true
	food.BrickColor = foodType.color
	food.Material = Enum.Material.SmoothPlastic
	food.CanCollide = true
	food.Parent = workspace

	ToolUtil.addFoodDecals(food, foodType)

	-- Green selection highlight
	local highlight = Instance.new("SelectionBox")
	highlight.Adornee = food
	highlight.Color3 = Color3.new(0, 1, 0)
	highlight.LineThickness = 0.05
	highlight.Parent = food

	-- E key proximity prompt for stealing
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Food"
	prompt.ObjectText = foodType.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Parent = food

	local taken = false
	prompt.Triggered:Connect(function(player)
		if taken or not food.Parent then
			return
		end

		local limit = Config and Config.MAX_FOOD_CARRIED
		if limit and ToolUtil.countFood(player) >= limit then
			notify(player, "Your hands are full! Sell or store food first.")
			return
		end
		taken = true

		ToolUtil.makeFoodTool(foodType).Parent = player.Backpack

		-- Notify client for sparkle effect
		if RemoteEvents then
			RemoteEvents.FoodStolen:FireClient(player, food.Position)
		end

		-- Notify scoring system
		if GameSystems then
			GameSystems.onFoodStolen(player)
		end

		-- Alert guard NPCs (HunterAI listens on server side)
		if RemoteEvents and RemoteEvents.FoodStolenServer then
			RemoteEvents.FoodStolenServer:Fire(player, food.Position)
		end

		food:Destroy()

		local respawnTime = (Config and Config.FOOD_RESPAWN_TIME) or DEFAULT_RESPAWN_TIME
		task.delay(respawnTime, function()
			createFood(foodType, position)
		end)
	end)

	return food
end

-- floorFoodPositions: table[floor][i] = { position = Vector3, foodType = table }
function FoodSystem.spawnAll(floorFoodPositions)
	for _, floorEntries in ipairs(floorFoodPositions) do
		for _, entry in ipairs(floorEntries) do
			createFood(entry.foodType, entry.position)
		end
	end
end

return FoodSystem
