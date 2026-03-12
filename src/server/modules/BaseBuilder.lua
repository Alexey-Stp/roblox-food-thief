-- BaseBuilder.lua
-- Constructs the player's safe base: platform, borders, spawn point,
-- upgradeable refrigerators, food sell stand, speed/jump shop,
-- world money leaderboard, prize box, trees and the food multiplier machine.

local Players = game:GetService("Players")

local BaseBuilder = {}

local GameSystems = nil
local Config      = nil

-- Per-player prize box cooldown timestamps
local prizeBoxCooldowns = {}

function BaseBuilder.init(gameSystems, config)
	GameSystems = gameSystems
	Config      = config
end

-- -------------------------------------------------------------------------
-- Shared helpers
-- -------------------------------------------------------------------------

local function addSurfaceLabel(parent, face, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face   = face
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size                = UDim2.new(1, 0, 1, 0)
	label.Text                = text
	label.TextColor3          = textColor or Color3.new(0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextScaled          = true
	label.Font                = Enum.Font.SourceSansBold
	label.Parent              = gui

	return label
end

-- -------------------------------------------------------------------------
-- Fridge
-- -------------------------------------------------------------------------
local function buildFridge(baseModel, position, fridgeIndex, fridgesTable)
	local fridge = Instance.new("Part")
	fridge.Name      = "Fridge" .. fridgeIndex
	fridge.Size      = Vector3.new(3, 4, 2)
	fridge.Position  = position
	fridge.Anchored  = true
	fridge.BrickColor = BrickColor.new("Dark grey")
	fridge.Material  = Enum.Material.Metal
	fridge.Parent    = baseModel

	local door = Instance.new("Part")
	door.Name         = "FridgeDoor" .. fridgeIndex
	door.Size         = Vector3.new(2.8, 3.5, 0.1)
	door.CFrame       = fridge.CFrame * CFrame.new(0, 0, -1.05)
	door.Anchored     = true
	door.BrickColor   = BrickColor.new("Cyan")
	door.Material     = Enum.Material.Glass
	door.Transparency = 0.5
	door.CanCollide   = false
	door.Parent       = baseModel

	local light = Instance.new("PointLight")
	light.Color      = Color3.new(0.5, 0.7, 1)
	light.Brightness = 1.5
	light.Range      = 8
	light.Parent     = fridge

	local countLabel = addSurfaceLabel(
		fridge, Enum.NormalId.Front,
		"Fridge " .. fridgeIndex .. ": 0/" .. Config.FRIDGE_CAPACITY,
		Color3.new(0, 1, 1))

	local storedItems = {}
	fridgesTable[fridgeIndex] = { part = fridge, items = storedItems, label = countLabel }

	local storePrompt = Instance.new("ProximityPrompt")
	storePrompt.ActionText            = "Store Food"
	storePrompt.ObjectText            = "Refrigerator"
	storePrompt.KeyboardKeyCode       = Enum.KeyCode.E
	storePrompt.RequiresLineOfSight   = false
	storePrompt.MaxActivationDistance = 8
	storePrompt.Parent                = fridge

	storePrompt.Triggered:Connect(function(player)
		if #storedItems >= Config.FRIDGE_CAPACITY then return end

		local character = player.Character
		if not character then return end

		local tool = character:FindFirstChildOfClass("Tool")
			or player.Backpack:FindFirstChildOfClass("Tool")
		if not tool then return end

		local handle = tool:FindFirstChild("Handle")
		if not handle then return end

		local foodCopy = handle:Clone()
		foodCopy.Size      = handle.Size * 0.5
		foodCopy.Position  = fridge.Position + Vector3.new(math.random(-1, 1) * 0.5, 2.5, 0)
		foodCopy.Anchored  = true
		foodCopy.CanCollide = false
		foodCopy.Parent    = baseModel

		local toolName = tool.Name
		table.insert(storedItems, { name = toolName, visual = foodCopy })
		tool:Destroy()

		countLabel.Text = "Fridge " .. fridgeIndex .. ": "
			.. #storedItems .. "/" .. Config.FRIDGE_CAPACITY

		if GameSystems then
			GameSystems.onFoodStored(player)
		end
	end)
end

local function buildUpgradeStation(baseModel, basePosition, fridgesTable)
	local station = Instance.new("Part")
	station.Name      = "UpgradeStation"
	station.Size      = Vector3.new(4, 4, 4)
	station.Position  = basePosition + Vector3.new(-18, 3, -15)
	station.Anchored  = true
	station.BrickColor = BrickColor.new("Bright blue")
	station.Material  = Enum.Material.Metal
	station.Parent    = baseModel

	addSurfaceLabel(station, Enum.NormalId.Front,
		"Add Fridge\n[50 pts]", Color3.new(1, 1, 1))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Upgrade"
	prompt.ObjectText            = "Fridge Station"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.RequiresLineOfSight   = false
	prompt.MaxActivationDistance = 8
	prompt.Parent                = station

	prompt.Triggered:Connect(function(player)
		local count = #fridgesTable
		if count >= Config.MAX_FRIDGES then return end

		local ls = player:FindFirstChild("leaderstats")
		if not ls then return end
		local score = ls:FindFirstChild("Score")
		if not score or score.Value < Config.FRIDGE_UPGRADE_COST then return end

		score.Value = score.Value - Config.FRIDGE_UPGRADE_COST

		local newIndex = count + 1
		local newPos   = basePosition + Vector3.new(-12 + (newIndex - 1) * 7, 3, -15)
		buildFridge(baseModel, newPos, newIndex, fridgesTable)
	end)
end

-- -------------------------------------------------------------------------
-- Sell stand
-- -------------------------------------------------------------------------
local function buildSellStand(baseModel, basePosition)
	local stall = Instance.new("Part")
	stall.Name      = "SellStand"
	stall.Size      = Vector3.new(12, 6, 5)
	stall.Position  = basePosition + Vector3.new(0, 4, -28)
	stall.Anchored  = true
	stall.BrickColor = BrickColor.new("Bright yellow")
	stall.Material  = Enum.Material.Wood
	stall.Parent    = baseModel

	addSurfaceLabel(stall, Enum.NormalId.Front,
		"SELL FOOD HERE\n[Press E]", Color3.new(0, 0, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Sell All Food"
	prompt.ObjectText            = "Market Stall"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.RequiresLineOfSight   = false
	prompt.MaxActivationDistance = 10
	prompt.Parent                = stall

	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local tools = {}

		if character then
			local eq = character:FindFirstChildOfClass("Tool")
			if eq then table.insert(tools, eq) end
		end
		for _, t in ipairs(player.Backpack:GetChildren()) do
			if t:IsA("Tool") then table.insert(tools, t) end
		end

		if #tools == 0 then return end

		local totalEarned = 0
		for _, tool in ipairs(tools) do
			-- Find sell price from Config.FOOD_TYPES by tool name
			local price = 0
			for _, ft in ipairs(Config.FOOD_TYPES) do
				if ft.name == tool.Name then
					price = ft.sellPrice or 0
					break
				end
			end
			totalEarned = totalEarned + price
			tool:Destroy()
		end

		if totalEarned > 0 and GameSystems then
			GameSystems.onFoodSold(player, totalEarned)
		end
	end)
end

-- -------------------------------------------------------------------------
-- Speed / Jump shop
-- -------------------------------------------------------------------------
local function buildShop(baseModel, basePosition)
	local booth = Instance.new("Part")
	booth.Name      = "ShopBooth"
	booth.Size      = Vector3.new(8, 8, 5)
	booth.Position  = basePosition + Vector3.new(25, 5, 0)
	booth.Anchored  = true
	booth.BrickColor = BrickColor.new("Bright blue")
	booth.Material  = Enum.Material.Metal
	booth.Parent    = baseModel

	addSurfaceLabel(booth, Enum.NormalId.Front, "SHOP", Color3.new(1, 1, 1))

	local function makeShopSign(name, pos, labelText, promptText, cost, applyBoost)
		local signPart = Instance.new("Part")
		signPart.Name      = name
		signPart.Size      = Vector3.new(6, 3, 0.3)
		signPart.Position  = pos
		signPart.Anchored  = true
		signPart.BrickColor = BrickColor.new("Black")
		signPart.Material  = Enum.Material.SmoothPlastic
		signPart.Parent    = baseModel

		addSurfaceLabel(signPart, Enum.NormalId.Front, labelText, Color3.new(0, 1, 0))

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText            = promptText
		prompt.KeyboardKeyCode       = Enum.KeyCode.E
		prompt.RequiresLineOfSight   = false
		prompt.MaxActivationDistance = 8
		prompt.Parent                = signPart

		prompt.Triggered:Connect(function(player)
			local ls = player:FindFirstChild("leaderstats")
			if not ls then return end
			local money = ls:FindFirstChild("Money")
			if not money or money.Value < cost then return end

			local char = player.Character
			if not char then return end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end

			money.Value = money.Value - cost
			applyBoost(humanoid)
		end)
	end

	makeShopSign("SpeedSign",
		basePosition + Vector3.new(22, 7, -2.5),
		"Speed Boost\n" .. Config.SHOP_SPEED_COST .. "$",
		"Buy Speed Boost",
		Config.SHOP_SPEED_COST,
		function(h) h.WalkSpeed = math.min(h.WalkSpeed + Config.SPEED_BOOST, 40) end)

	makeShopSign("JumpSign",
		basePosition + Vector3.new(28, 7, -2.5),
		"Jump Boost\n" .. Config.SHOP_JUMP_COST .. "$",
		"Buy Jump Boost",
		Config.SHOP_JUMP_COST,
		function(h) h.JumpPower = math.min(h.JumpPower + Config.JUMP_BOOST, 100) end)
end

-- -------------------------------------------------------------------------
-- World money leaderboard
-- -------------------------------------------------------------------------
local function buildWorldLeaderboard(baseModel, basePosition)
	local board = Instance.new("Part")
	board.Name      = "MoneyLeaderboard"
	board.Size      = Vector3.new(35, 22, 1)
	board.Position  = basePosition + Vector3.new(0, 14, 23)
	board.Anchored  = true
	board.BrickColor = BrickColor.new("Black")
	board.Material  = Enum.Material.SmoothPlastic
	board.Parent    = baseModel

	local label = addSurfaceLabel(board, Enum.NormalId.Front,
		"TOP PLAYERS", Color3.new(1, 1, 0))

	task.spawn(function()
		while board and board.Parent do
			local playerList = Players:GetPlayers()
			table.sort(playerList, function(a, b)
				local am = a:FindFirstChild("leaderstats") and
					a.leaderstats:FindFirstChild("Money")
				local bm = b:FindFirstChild("leaderstats") and
					b.leaderstats:FindFirstChild("Money")
				return (am and am.Value or 0) > (bm and bm.Value or 0)
			end)

			local lines = { "   RICHEST THIEVES   " }
			for i = 1, math.min(5, #playerList) do
				local p = playerList[i]
				local m = p:FindFirstChild("leaderstats") and
					p.leaderstats:FindFirstChild("Money")
				local val = m and m.Value or 0
				table.insert(lines, i .. ". " .. p.Name .. "  $" .. val)
			end

			label.Text = table.concat(lines, "\n")
			task.wait(5)
		end
	end)
end

-- -------------------------------------------------------------------------
-- Decorative tree
-- -------------------------------------------------------------------------
local function buildTree(parent, position)
	local trunk = Instance.new("Part")
	trunk.Name      = "TreeTrunk"
	trunk.Shape     = Enum.PartType.Cylinder
	trunk.Size      = Vector3.new(8, 3, 3)
	trunk.CFrame    = CFrame.new(position + Vector3.new(0, 4, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored  = true
	trunk.BrickColor = BrickColor.new("Reddish brown")
	trunk.Material  = Enum.Material.Wood
	trunk.Parent    = parent

	local foliage = Instance.new("Part")
	foliage.Name     = "TreeFoliage"
	foliage.Shape    = Enum.PartType.Ball
	foliage.Size     = Vector3.new(14, 14, 14)
	foliage.Position = position + Vector3.new(0, 12, 0)
	foliage.Anchored = true
	foliage.BrickColor = BrickColor.new("Bright green")
	foliage.Material = Enum.Material.Grass
	foliage.Parent   = parent
end

-- Trees placed in the corners and sides around the base platform
local function buildBaseTrees(baseModel, basePosition)
	local offsets = {
		Vector3.new(-38, 0, -38),
		Vector3.new( 38, 0, -38),
		Vector3.new(-38, 0,  38),
		Vector3.new( 38, 0,  38),
		Vector3.new(  0, 0, -45),
		Vector3.new(  0, 0,  45),
		Vector3.new(-45, 0,   0),
		Vector3.new( 45, 0,   0),
	}
	for _, offset in ipairs(offsets) do
		buildTree(baseModel, basePosition + offset + Vector3.new(0, 1, 0))
	end
end

-- -------------------------------------------------------------------------
-- Prize box (random money reward, per-player cooldown)
-- -------------------------------------------------------------------------
local function buildPrizeBox(baseModel, basePosition)
	local box = Instance.new("Part")
	box.Name      = "PrizeBox"
	box.Size      = Vector3.new(4, 4, 4)
	box.Position  = basePosition + Vector3.new(18, 3, 15)
	box.Anchored  = true
	box.BrickColor = BrickColor.new("Bright yellow")
	box.Material  = Enum.Material.Neon
	box.Parent    = baseModel

	-- Decorative lid
	local lid = Instance.new("Part")
	lid.Name      = "PrizeBoxLid"
	lid.Size      = Vector3.new(4.2, 0.5, 4.2)
	lid.Position  = box.Position + Vector3.new(0, 2.25, 0)
	lid.Anchored  = true
	lid.BrickColor = BrickColor.new("Bright orange")
	lid.Material  = Enum.Material.Neon
	lid.Parent    = baseModel

	local sign = Instance.new("Part")
	sign.Name      = "PrizeBoxSign"
	sign.Size      = Vector3.new(5, 1.5, 0.2)
	sign.Position  = box.Position + Vector3.new(0, 3.5, -2.1)
	sign.Anchored  = true
	sign.BrickColor = BrickColor.new("Black")
	sign.Material  = Enum.Material.SmoothPlastic
	sign.Parent    = baseModel
	addSurfaceLabel(sign, Enum.NormalId.Front,
		"PRIZE BOX!", Color3.new(1, 1, 0))

	local boxLight = Instance.new("PointLight")
	boxLight.Color      = Color3.new(1, 0.8, 0)
	boxLight.Brightness = 2
	boxLight.Range      = 12
	boxLight.Parent     = box

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Open Prize Box"
	prompt.ObjectText            = "Lucky Prize Box"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.RequiresLineOfSight   = false
	prompt.MaxActivationDistance = 8
	prompt.Parent                = box

	prompt.Triggered:Connect(function(player)
		local now = tick()
		local lastOpen = prizeBoxCooldowns[player.UserId] or 0
		if now - lastOpen < Config.PRIZE_BOX_COOLDOWN then
			-- Show a hint how long until ready again
			local remaining = math.ceil(Config.PRIZE_BOX_COOLDOWN - (now - lastOpen))
			prompt.ActionText = "Ready in " .. remaining .. "s"
			task.delay(2, function()
				prompt.ActionText = "Open Prize Box"
			end)
			return
		end
		prizeBoxCooldowns[player.UserId] = now

		local reward = math.random(Config.PRIZE_BOX_MIN, Config.PRIZE_BOX_MAX)
		if GameSystems then
			GameSystems.onFoodSold(player, reward)
		end

		-- Visual pop: brief bright flash
		local origColor = box.BrickColor
		box.BrickColor = BrickColor.new("White")
		task.delay(0.2, function()
			box.BrickColor = origColor
		end)

		prompt.ActionText = "Got $" .. reward .. "!"
		task.delay(2, function()
			prompt.ActionText = "Open Prize Box"
		end)
	end)

	-- Cleanup cooldown entry when player leaves
	Players.PlayerRemoving:Connect(function(player)
		prizeBoxCooldowns[player.UserId] = nil
	end)
end

-- -------------------------------------------------------------------------
-- Main build entry point
-- -------------------------------------------------------------------------
function BaseBuilder.build()
	local basePosition = Config.BASE_POSITION

	local baseModel = Instance.new("Model")
	baseModel.Name   = "PlayerBase"
	baseModel.Parent = workspace

	-- Main grass platform
	local platform = Instance.new("Part")
	platform.Name      = "BasePlatform"
	platform.Size      = Vector3.new(60, 2, 60)   -- larger to fit new buildings
	platform.Position  = basePosition
	platform.Anchored  = true
	platform.BrickColor = BrickColor.new("Bright green")
	platform.Material  = Enum.Material.Grass
	platform.Parent    = baseModel

	-- Border walls
	local wallHeight    = 4
	local wallThickness = 1
	local halfSize      = 30

	local function makeBorder(name, size, offset)
		local b = Instance.new("Part")
		b.Name      = name
		b.Size      = size
		b.Position  = basePosition + offset
		b.Anchored  = true
		b.BrickColor = BrickColor.new("Bright blue")
		b.Material  = Enum.Material.SmoothPlastic
		b.Parent    = baseModel
	end

	makeBorder("NorthBorder", Vector3.new(60, wallHeight, wallThickness),
		Vector3.new(0, wallHeight / 2 + 1, halfSize))
	makeBorder("SouthBorder", Vector3.new(60, wallHeight, wallThickness),
		Vector3.new(0, wallHeight / 2 + 1, -halfSize))
	makeBorder("EastBorder",  Vector3.new(wallThickness, wallHeight, 60),
		Vector3.new(halfSize, wallHeight / 2 + 1, 0))
	makeBorder("WestBorder",  Vector3.new(wallThickness, wallHeight, 60),
		Vector3.new(-halfSize, wallHeight / 2 + 1, 0))

	-- Spawn point
	local spawnPt = Instance.new("SpawnLocation")
	spawnPt.Name        = "BaseSpawn"
	spawnPt.Size        = Vector3.new(6, 1, 6)
	spawnPt.Position    = basePosition + Vector3.new(0, 2, 0)
	spawnPt.Anchored    = true
	spawnPt.BrickColor  = BrickColor.new("Really red")
	spawnPt.Material    = Enum.Material.Neon
	spawnPt.Transparency = 0.3
	spawnPt.CanCollide  = false
	spawnPt.Duration    = 0
	spawnPt.Parent      = baseModel

	-- Base sign
	local sign = Instance.new("Part")
	sign.Name      = "BaseSign"
	sign.Size      = Vector3.new(20, 4, 1)
	sign.Position  = basePosition + Vector3.new(0, 8, halfSize)
	sign.Anchored  = true
	sign.BrickColor = BrickColor.new("Bright yellow")
	sign.Material  = Enum.Material.Neon
	sign.Parent    = baseModel
	addSurfaceLabel(sign, Enum.NormalId.Front,
		"YOUR SAFE BASE\nStore & Sell Your Food!", Color3.new(0, 0, 0))

	-- Fridges (start with 1)
	local fridgesTable = {}
	buildFridge(baseModel, basePosition + Vector3.new(-12, 3, -15), 1, fridgesTable)
	buildUpgradeStation(baseModel, basePosition, fridgesTable)

	-- Sell stand
	buildSellStand(baseModel, basePosition)

	-- Shop
	buildShop(baseModel, basePosition)

	-- World leaderboard
	buildWorldLeaderboard(baseModel, basePosition)

	-- Prize box
	buildPrizeBox(baseModel, basePosition)

	-- Decorative trees around the base
	buildBaseTrees(baseModel, basePosition)

	-- -------------------------------------------------------------------------
	-- Food Multiplier machine
	-- -------------------------------------------------------------------------
	local craftMachine = Instance.new("Part")
	craftMachine.Name      = "CraftMachine"
	craftMachine.Size      = Vector3.new(8, 8, 8)
	craftMachine.Position  = basePosition + Vector3.new(-20, 4, 10)
	craftMachine.Anchored  = true
	craftMachine.BrickColor = BrickColor.new("Dark grey")
	craftMachine.Material  = Enum.Material.Metal
	craftMachine.Parent    = baseModel

	local chamber = Instance.new("Part")
	chamber.Name         = "ProcessingChamber"
	chamber.Size         = Vector3.new(6, 2, 6)
	chamber.Position     = craftMachine.Position + Vector3.new(0, 5, 0)
	chamber.Anchored     = true
	chamber.BrickColor   = BrickColor.new("Cyan")
	chamber.Material     = Enum.Material.Glass
	chamber.Transparency = 0.3
	chamber.Parent       = baseModel

	local indicator = Instance.new("Part")
	indicator.Name      = "StatusLight"
	indicator.Size      = Vector3.new(1, 1, 1)
	indicator.Position  = craftMachine.Position + Vector3.new(0, 4.5, 0)
	indicator.Anchored  = true
	indicator.BrickColor = BrickColor.new("Lime green")
	indicator.Material  = Enum.Material.Neon
	indicator.Shape     = Enum.PartType.Ball
	indicator.Parent    = baseModel

	local indicatorLight = Instance.new("PointLight")
	indicatorLight.Color      = Color3.new(0, 1, 0)
	indicatorLight.Brightness = 2
	indicatorLight.Range      = 10
	indicatorLight.Parent     = indicator

	local machineSign = Instance.new("Part")
	machineSign.Name      = "MachineSign"
	machineSign.Size      = Vector3.new(8, 2, 0.2)
	machineSign.Position  = craftMachine.Position + Vector3.new(0, 6, -4.1)
	machineSign.Anchored  = true
	machineSign.BrickColor = BrickColor.new("Black")
	machineSign.Material  = Enum.Material.SmoothPlastic
	machineSign.Parent    = baseModel
	local signLabel = addSurfaceLabel(machineSign, Enum.NormalId.Front,
		"FOOD MULTIPLIER", Color3.new(0, 1, 0))

	local isProcessing = false
	local storedFood   = {}

	local craftPrompt = Instance.new("ProximityPrompt")
	craftPrompt.ActionText            = "Insert Food"
	craftPrompt.ObjectText            = "Food Multiplier"
	craftPrompt.KeyboardKeyCode       = Enum.KeyCode.E
	craftPrompt.RequiresLineOfSight   = false
	craftPrompt.MaxActivationDistance = 10
	craftPrompt.Parent                = craftMachine

	craftPrompt.Triggered:Connect(function(player)
		if isProcessing then
			if #storedFood > 0 then
				for _, foodData in ipairs(storedFood) do
					local tool = Instance.new("Tool")
					tool.Name           = foodData.name
					tool.RequiresHandle = true
					local handle = Instance.new("Part")
					handle.Name      = "Handle"
					handle.Size      = foodData.size
					handle.BrickColor = foodData.color
					handle.Material  = Enum.Material.SmoothPlastic
					if foodData.texture then
						local decal = Instance.new("Decal")
						decal.Texture = foodData.texture
						decal.Face    = Enum.NormalId.Top
						decal.Parent  = handle
					end
					handle.Parent = tool
					tool.Parent   = player.Backpack
				end

				if GameSystems then
					GameSystems.onFoodCollected(player, #storedFood)
				end

				storedFood   = {}
				isProcessing = false
				indicator.BrickColor   = BrickColor.new("Lime green")
				indicatorLight.Color   = Color3.new(0, 1, 0)
				indicator.Transparency = 0
				craftPrompt.ActionText = "Insert Food"
				signLabel.Text         = "FOOD MULTIPLIER"
				signLabel.TextColor3   = Color3.new(0, 1, 0)
				chamber.Transparency   = 0.3
			end
		else
			local character = player.Character
			if not character then return end

			local tool = character:FindFirstChildOfClass("Tool")
				or player.Backpack:FindFirstChildOfClass("Tool")
			if not tool then return end

			local handle = tool:FindFirstChild("Handle")
			if not handle then return end

			local decalInst = handle:FindFirstChildOfClass("Decal")
			table.insert(storedFood, {
				name    = tool.Name,
				size    = handle.Size,
				color   = handle.BrickColor,
				texture = decalInst and decalInst.Texture or nil,
			})
			tool:Destroy()

			isProcessing           = true
			indicator.BrickColor   = BrickColor.new("Bright yellow")
			indicatorLight.Color   = Color3.new(1, 1, 0)
			craftPrompt.ActionText = "Processing..."
			chamber.Transparency   = 0.1

			task.spawn(function()
				local startTime = tick()
				while isProcessing and tick() - startTime < Config.MULTIPLIER_TIME do
					indicator.Transparency = math.abs(math.sin(tick() * 3)) * 0.5
					local timeLeft = Config.MULTIPLIER_TIME - (tick() - startTime)
					signLabel.Text = string.format("PROCESSING: %ds", math.floor(timeLeft))
					task.wait(0.1)
				end

				if isProcessing then
					local origCount = #storedFood
					for _ = 1, origCount * (Config.MULTIPLIER_FACTOR - 1) do
						table.insert(storedFood, storedFood[math.random(1, origCount)])
					end

					indicator.BrickColor        = BrickColor.new("Bright green")
					indicatorLight.Color        = Color3.new(0, 1, 0)
					indicator.Transparency      = 0
					craftPrompt.ActionText      = "Collect Food (x" .. #storedFood .. ")"
					signLabel.Text              = "READY! COLLECT FOOD"
					signLabel.TextColor3        = Color3.new(1, 1, 0)
					chamber.Transparency        = 0
				end
			end)
		end
	end)

	return baseModel
end

return BaseBuilder
