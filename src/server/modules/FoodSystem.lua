-- FoodSystem.lua
-- Handles spawning food on tables, E-key pickup via ProximityPrompt, and respawning.
-- Fires RemoteEvents to the client for visual effects.

local FoodSystem = {}

-- Injected from Main
local RemoteEvents = nil
local GameSystems  = nil

function FoodSystem.init(remoteEvents, gameSystems)
	RemoteEvents = remoteEvents
	GameSystems  = gameSystems
end

local function addDecals(part, foodType)
	if foodType.texture then
		local d = Instance.new("Decal")
		d.Texture = foodType.texture
		d.Face    = Enum.NormalId.Top
		d.Parent  = part
	end
	if foodType.sideTexture then
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local d = Instance.new("Decal")
			d.Texture = foodType.sideTexture
			d.Face    = face
			d.Parent  = part
		end
	end
end

local function createFood(foodType, position)
	local food = Instance.new("Part")
	food.Name       = foodType.name
	food.Size       = foodType.size
	food.Position   = position
	food.Anchored   = true
	food.BrickColor = foodType.color
	food.Material   = Enum.Material.SmoothPlastic
	food.CanCollide = true
	food.Parent     = workspace

	addDecals(food, foodType)

	-- Green selection highlight
	local highlight = Instance.new("SelectionBox")
	highlight.Adornee       = food
	highlight.Color3        = Color3.new(0, 1, 0)
	highlight.LineThickness = 0.05
	highlight.Parent        = food

	-- E key proximity prompt for stealing
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Take Food"
	prompt.ObjectText            = foodType.name
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.RequiresLineOfSight   = false
	prompt.MaxActivationDistance = 8
	prompt.Parent                = food

	prompt.Triggered:Connect(function(player)
		if not (food and food.Parent) then return end

		-- Build a Tool for the player's backpack
		local tool = Instance.new("Tool")
		tool.Name           = foodType.name
		tool.RequiresHandle = true

		local handle = Instance.new("Part")
		handle.Name      = "Handle"
		handle.Size      = foodType.size * 0.7
		handle.BrickColor = foodType.color
		handle.Material  = Enum.Material.SmoothPlastic
		addDecals(handle, foodType)
		handle.Parent = tool

		tool.Parent = player.Backpack

		-- Notify client for sparkle effect
		if RemoteEvents then
			RemoteEvents.FoodStolen:FireClient(player, food.Position)
		end

		-- Notify scoring system
		if GameSystems then
			GameSystems.onFoodStolen(player)
		end

		local respawnPos = Vector3.new(position.X, position.Y, position.Z)
		food:Destroy()

		task.delay(5, function()
			createFood(foodType, respawnPos)
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
