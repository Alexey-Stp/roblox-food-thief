-- BaseBuilder.lua
-- Constructs the player's safe base: platform, borders, spawn point,
-- upgradeable refrigerators, food sell stand, speed/jump shop,
-- world money leaderboard, prize box, trees and the food multiplier machine.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ToolUtil = require(script.Parent.ToolUtil)

local BaseBuilder = {}

local GameSystems = nil
local Config = nil
local RemoteEvents = nil

-- Per-player prize box cooldown timestamps
local prizeBoxCooldowns = {}

-- Per-player Food Multiplier jobs: [UserId] = { items = { foodType, ... }, readyAt = os.clock() }
local multiplierJobs = {}

function BaseBuilder.init(gameSystems, config, remoteEvents)
	GameSystems = gameSystems
	Config = config
	RemoteEvents = remoteEvents

	Players.PlayerRemoving:Connect(function(player)
		prizeBoxCooldowns[player.UserId] = nil
		multiplierJobs[player.UserId] = nil
	end)
end

local function notify(player, text)
	if RemoteEvents then
		RemoteEvents.Notify:FireClient(player, text)
	end
end

-- -------------------------------------------------------------------------
-- Shared helpers
-- -------------------------------------------------------------------------

local function addSurfaceLabel(parent, face, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = text
	label.TextColor3 = textColor or Color3.new(0, 0, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = gui

	return label
end

-- -------------------------------------------------------------------------
-- Fridge — builds the physical fridge Part only.
-- Interaction logic (prompts, per-player levels, BillboardGui) is handled by
-- RefrigeratorSystem.lua, which finds fridges via the "Fridge" CollectionService tag.
-- -------------------------------------------------------------------------
local function buildFridge(baseModel, position, fridgeIndex)
	local fridge = Instance.new("Part")
	fridge.Name = "Fridge" .. fridgeIndex
	fridge.Size = Vector3.new(3, 4, 2)
	fridge.Position = position
	fridge.Anchored = true
	fridge.BrickColor = BrickColor.new("Dark grey")
	fridge.Material = Enum.Material.Metal
	-- Tag for RefrigeratorSystem to locate and enhance
	fridge:SetAttribute("FridgeId", fridgeIndex)
	fridge.Parent = baseModel
	CollectionService:AddTag(fridge, "Fridge")

	local door = Instance.new("Part")
	door.Name = "FridgeDoor" .. fridgeIndex
	door.Size = Vector3.new(2.8, 3.5, 0.1)
	door.CFrame = fridge.CFrame * CFrame.new(0, 0, -1.05)
	door.Anchored = true
	door.BrickColor = BrickColor.new("Cyan")
	door.Material = Enum.Material.Glass
	door.Transparency = 0.5
	door.CanCollide = false
	door.Parent = baseModel

	local light = Instance.new("PointLight")
	light.Color = Color3.new(0.5, 0.7, 1)
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = fridge

	addSurfaceLabel(fridge, Enum.NormalId.Front, "Fridge " .. fridgeIndex, Color3.new(0, 1, 1))

	return fridge
end

-- -------------------------------------------------------------------------
-- Sell stand
-- -------------------------------------------------------------------------
local function buildSellStand(baseModel, basePosition)
	local stall = Instance.new("Part")
	stall.Name = "SellStand"
	stall.Size = Vector3.new(12, 6, 5)
	stall.Position = basePosition + Vector3.new(0, 4, -28)
	stall.Anchored = true
	stall.BrickColor = BrickColor.new("Bright yellow")
	stall.Material = Enum.Material.Wood
	stall.Parent = baseModel

	addSurfaceLabel(stall, Enum.NormalId.Front, "SELL FOOD HERE\n[Press E]", Color3.new(0, 0, 0))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sell All Food"
	prompt.ObjectText = "Market Stall"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = stall

	prompt.Triggered:Connect(function(player)
		-- Only food is sold; bat, carpet and weapons are never touched
		local tools = ToolUtil.getFoodTools(player)
		if #tools == 0 then
			notify(player, "You have no food to sell")
			return
		end

		local totalEarned = 0
		for _, tool in ipairs(tools) do
			-- Prefer fridge-boosted CurrentSellPrice attribute; fall back to Config
			local handle = tool:FindFirstChild("Handle")
			local price = handle:GetAttribute("CurrentSellPrice")
			if not price or price == 0 then
				local ft = ToolUtil.findFoodType(Config.FOOD_TYPES, tool.Name)
				price = ft and ft.sellPrice or 0
			end
			totalEarned = totalEarned + price
			tool:Destroy()
		end

		GameSystems.addMoney(player, totalEarned)
		notify(player, "Sold " .. #tools .. " food for $" .. totalEarned)
	end)
end

-- -------------------------------------------------------------------------
-- Speed / Jump shop
-- -------------------------------------------------------------------------
local function buildShop(baseModel, basePosition)
	local booth = Instance.new("Part")
	booth.Name = "ShopBooth"
	booth.Size = Vector3.new(8, 8, 5)
	booth.Position = basePosition + Vector3.new(25, 5, 0)
	booth.Anchored = true
	booth.BrickColor = BrickColor.new("Bright blue")
	booth.Material = Enum.Material.Metal
	booth.Parent = baseModel

	addSurfaceLabel(booth, Enum.NormalId.Front, "SHOP", Color3.new(1, 1, 1))

	-- computeBoost(walkSpeed, jumpPower) -> newWalkSpeed, newJumpPower (from cached settings)
	local function makeShopSign(name, pos, labelText, promptText, cost, computeBoost)
		local signPart = Instance.new("Part")
		signPart.Name = name
		signPart.Size = Vector3.new(6, 3, 0.3)
		signPart.Position = pos
		signPart.Anchored = true
		signPart.BrickColor = BrickColor.new("Black")
		signPart.Material = Enum.Material.SmoothPlastic
		signPart.Parent = baseModel

		addSurfaceLabel(signPart, Enum.NormalId.Front, labelText, Color3.new(0, 1, 0))

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = promptText
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = signPart

		prompt.Triggered:Connect(function(player)
			-- Work from cached settings, never the live Humanoid (it may be stunned)
			local walkSpeed, jumpPower = GameSystems.getSettings(player)
			if not walkSpeed then
				return
			end
			local newWalk, newJump = computeBoost(walkSpeed, jumpPower)
			if newWalk == walkSpeed and newJump == jumpPower then
				notify(player, "Already at the maximum!")
				return
			end
			if not GameSystems.trySpend(player, cost) then
				notify(player, "Need $" .. cost)
				return
			end

			GameSystems.updateSettings(player, newWalk, newJump)
			-- A stunned player gets the new values when the stun ends
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and not humanoid:GetAttribute("Stunned") then
				GameSystems.applySettings(player)
			end
			notify(player, promptText .. " purchased!")
		end)
	end

	makeShopSign(
		"SpeedSign",
		basePosition + Vector3.new(22, 7, -2.5),
		"Speed Boost\n" .. Config.SHOP_SPEED_COST .. "$",
		"Buy Speed Boost",
		Config.SHOP_SPEED_COST,
		function(walkSpeed, jumpPower)
			return math.min(walkSpeed + Config.SPEED_BOOST, Config.MAX_WALK_SPEED), jumpPower
		end
	)

	makeShopSign(
		"JumpSign",
		basePosition + Vector3.new(28, 7, -2.5),
		"Jump Boost\n" .. Config.SHOP_JUMP_COST .. "$",
		"Buy Jump Boost",
		Config.SHOP_JUMP_COST,
		function(walkSpeed, jumpPower)
			return walkSpeed, math.min(jumpPower + Config.JUMP_BOOST, Config.MAX_JUMP_POWER)
		end
	)
end

-- -------------------------------------------------------------------------
-- World money leaderboard
-- -------------------------------------------------------------------------
local function buildWorldLeaderboard(baseModel, basePosition)
	local board = Instance.new("Part")
	board.Name = "MoneyLeaderboard"
	board.Size = Vector3.new(35, 22, 1)
	board.Position = basePosition + Vector3.new(0, 14, 23)
	board.Anchored = true
	board.BrickColor = BrickColor.new("Black")
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = baseModel

	local label = addSurfaceLabel(board, Enum.NormalId.Front, "TOP PLAYERS", Color3.new(1, 1, 0))

	task.spawn(function()
		while board and board.Parent do
			local playerList = Players:GetPlayers()
			table.sort(playerList, function(a, b)
				local am = a:FindFirstChild("leaderstats") and a.leaderstats:FindFirstChild("Money")
				local bm = b:FindFirstChild("leaderstats") and b.leaderstats:FindFirstChild("Money")
				return (am and am.Value or 0) > (bm and bm.Value or 0)
			end)

			local lines = { "   RICHEST THIEVES   " }
			for i = 1, math.min(5, #playerList) do
				local p = playerList[i]
				local m = p:FindFirstChild("leaderstats") and p.leaderstats:FindFirstChild("Money")
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
	trunk.Name = "TreeTrunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(8, 3, 3)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored = true
	trunk.BrickColor = BrickColor.new("Reddish brown")
	trunk.Material = Enum.Material.Wood
	trunk.Parent = parent

	local foliage = Instance.new("Part")
	foliage.Name = "TreeFoliage"
	foliage.Shape = Enum.PartType.Ball
	foliage.Size = Vector3.new(14, 14, 14)
	foliage.Position = position + Vector3.new(0, 12, 0)
	foliage.Anchored = true
	foliage.BrickColor = BrickColor.new("Bright green")
	foliage.Material = Enum.Material.Grass
	foliage.Parent = parent
end

-- Trees placed in the corners and sides around the base platform
local function buildBaseTrees(baseModel, basePosition)
	local offsets = {
		Vector3.new(-38, 0, -38),
		Vector3.new(38, 0, -38),
		Vector3.new(-38, 0, 38),
		Vector3.new(38, 0, 38),
		Vector3.new(0, 0, -45),
		Vector3.new(0, 0, 45),
		Vector3.new(-45, 0, 0),
		Vector3.new(45, 0, 0),
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
	box.Name = "PrizeBox"
	box.Size = Vector3.new(4, 4, 4)
	box.Position = basePosition + Vector3.new(18, 3, 15)
	box.Anchored = true
	box.BrickColor = BrickColor.new("Bright yellow")
	box.Material = Enum.Material.Neon
	box.Parent = baseModel

	-- Decorative lid
	local lid = Instance.new("Part")
	lid.Name = "PrizeBoxLid"
	lid.Size = Vector3.new(4.2, 0.5, 4.2)
	lid.Position = box.Position + Vector3.new(0, 2.25, 0)
	lid.Anchored = true
	lid.BrickColor = BrickColor.new("Bright orange")
	lid.Material = Enum.Material.Neon
	lid.Parent = baseModel

	local sign = Instance.new("Part")
	sign.Name = "PrizeBoxSign"
	sign.Size = Vector3.new(5, 1.5, 0.2)
	sign.Position = box.Position + Vector3.new(0, 3.5, -2.1)
	sign.Anchored = true
	sign.BrickColor = BrickColor.new("Black")
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = baseModel
	addSurfaceLabel(sign, Enum.NormalId.Front, "PRIZE BOX!", Color3.new(1, 1, 0))

	local boxLight = Instance.new("PointLight")
	boxLight.Color = Color3.new(1, 0.8, 0)
	boxLight.Brightness = 2
	boxLight.Range = 12
	boxLight.Parent = box

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Prize Box"
	prompt.ObjectText = "Lucky Prize Box"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Parent = box

	prompt.Triggered:Connect(function(player)
		local now = os.clock()
		local lastOpen = prizeBoxCooldowns[player.UserId]
		if lastOpen and now - lastOpen < Config.PRIZE_BOX_COOLDOWN then
			-- Per-player hint (a prompt's text is shared by everyone)
			local remaining = math.ceil(Config.PRIZE_BOX_COOLDOWN - (now - lastOpen))
			notify(player, "Prize box ready in " .. remaining .. "s")
			return
		end
		prizeBoxCooldowns[player.UserId] = now

		local reward = math.random(Config.PRIZE_BOX_MIN, Config.PRIZE_BOX_MAX)
		GameSystems.addMoney(player, reward)
		notify(player, "Prize box: +$" .. reward .. "!")

		-- Visual pop: brief bright flash
		local origColor = box.BrickColor
		box.BrickColor = BrickColor.new("White")
		task.delay(0.2, function()
			box.BrickColor = origColor
		end)
	end)
end

-- -------------------------------------------------------------------------
-- Main build entry point
-- -------------------------------------------------------------------------
function BaseBuilder.build()
	local basePosition = Config.BASE_POSITION

	local baseModel = Instance.new("Model")
	baseModel.Name = "PlayerBase"
	baseModel.Parent = workspace

	-- Main grass platform
	local platform = Instance.new("Part")
	platform.Name = "BasePlatform"
	platform.Size = Vector3.new(60, 2, 60) -- larger to fit new buildings
	platform.Position = basePosition
	platform.Anchored = true
	platform.BrickColor = BrickColor.new("Bright green")
	platform.Material = Enum.Material.Grass
	platform.Parent = baseModel

	-- Border walls
	local wallHeight = 4
	local wallThickness = 1
	local halfSize = 30

	local function makeBorder(name, size, offset)
		local b = Instance.new("Part")
		b.Name = name
		b.Size = size
		b.Position = basePosition + offset
		b.Anchored = true
		b.BrickColor = BrickColor.new("Bright blue")
		b.Material = Enum.Material.SmoothPlastic
		b.Parent = baseModel
	end

	makeBorder("NorthBorder", Vector3.new(60, wallHeight, wallThickness), Vector3.new(0, wallHeight / 2 + 1, halfSize))
	makeBorder("SouthBorder", Vector3.new(60, wallHeight, wallThickness), Vector3.new(0, wallHeight / 2 + 1, -halfSize))
	makeBorder("EastBorder", Vector3.new(wallThickness, wallHeight, 60), Vector3.new(halfSize, wallHeight / 2 + 1, 0))
	makeBorder("WestBorder", Vector3.new(wallThickness, wallHeight, 60), Vector3.new(-halfSize, wallHeight / 2 + 1, 0))

	-- Spawn point
	local spawnPt = Instance.new("SpawnLocation")
	spawnPt.Name = "BaseSpawn"
	spawnPt.Size = Vector3.new(6, 1, 6)
	spawnPt.Position = basePosition + Vector3.new(0, 2, 0)
	spawnPt.Anchored = true
	spawnPt.BrickColor = BrickColor.new("Really red")
	spawnPt.Material = Enum.Material.Neon
	spawnPt.Transparency = 0.3
	spawnPt.CanCollide = false
	spawnPt.Duration = 0
	spawnPt.Parent = baseModel

	-- Base sign
	local sign = Instance.new("Part")
	sign.Name = "BaseSign"
	sign.Size = Vector3.new(20, 4, 1)
	sign.Position = basePosition + Vector3.new(0, 8, halfSize)
	sign.Anchored = true
	sign.BrickColor = BrickColor.new("Bright yellow")
	sign.Material = Enum.Material.Neon
	sign.Parent = baseModel
	addSurfaceLabel(sign, Enum.NormalId.Front, "YOUR SAFE BASE\nStore & Sell Your Food!", Color3.new(0, 0, 0))

	-- Two fridges; RefrigeratorSystem.lua adds BillboardGui + upgrade interaction
	for i = 1, Config.FRIDGE_COUNT do
		buildFridge(baseModel, basePosition + Vector3.new(-12 + (i - 1) * 7, 3, -15), i)
	end

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
	craftMachine.Name = "CraftMachine"
	craftMachine.Size = Vector3.new(8, 8, 8)
	craftMachine.Position = basePosition + Vector3.new(-20, 4, 10)
	craftMachine.Anchored = true
	craftMachine.BrickColor = BrickColor.new("Dark grey")
	craftMachine.Material = Enum.Material.Metal
	craftMachine.Parent = baseModel

	local chamber = Instance.new("Part")
	chamber.Name = "ProcessingChamber"
	chamber.Size = Vector3.new(6, 2, 6)
	chamber.Position = craftMachine.Position + Vector3.new(0, 5, 0)
	chamber.Anchored = true
	chamber.BrickColor = BrickColor.new("Cyan")
	chamber.Material = Enum.Material.Glass
	chamber.Transparency = 0.3
	chamber.Parent = baseModel

	local indicator = Instance.new("Part")
	indicator.Name = "StatusLight"
	indicator.Size = Vector3.new(1, 1, 1)
	indicator.Position = craftMachine.Position + Vector3.new(0, 4.5, 0)
	indicator.Anchored = true
	indicator.BrickColor = BrickColor.new("Lime green")
	indicator.Material = Enum.Material.Neon
	indicator.Shape = Enum.PartType.Ball
	indicator.Parent = baseModel

	local indicatorLight = Instance.new("PointLight")
	indicatorLight.Color = Color3.new(0, 1, 0)
	indicatorLight.Brightness = 2
	indicatorLight.Range = 10
	indicatorLight.Parent = indicator

	local machineSign = Instance.new("Part")
	machineSign.Name = "MachineSign"
	machineSign.Size = Vector3.new(8, 2, 0.2)
	machineSign.Position = craftMachine.Position + Vector3.new(0, 6, -4.1)
	machineSign.Anchored = true
	machineSign.BrickColor = BrickColor.new("Black")
	machineSign.Material = Enum.Material.SmoothPlastic
	machineSign.Parent = baseModel
	local signLabel = addSurfaceLabel(machineSign, Enum.NormalId.Front, "FOOD MULTIPLIER", Color3.new(0, 1, 0))

	local craftPrompt = Instance.new("ProximityPrompt")
	craftPrompt.ActionText = "Use Food Multiplier"
	craftPrompt.ObjectText = "Food Multiplier"
	craftPrompt.KeyboardKeyCode = Enum.KeyCode.E
	craftPrompt.RequiresLineOfSight = false
	craftPrompt.MaxActivationDistance = 10
	craftPrompt.Parent = craftMachine

	-- Machine visuals reflect whether ANY player has a job running
	local function refreshMachineVisuals()
		local busy = next(multiplierJobs) ~= nil
		indicator.BrickColor = busy and BrickColor.new("Bright yellow") or BrickColor.new("Lime green")
		indicatorLight.Color = busy and Color3.new(1, 1, 0) or Color3.new(0, 1, 0)
		chamber.Transparency = busy and 0.1 or 0.3
		signLabel.Text = busy and "FOOD MULTIPLIER (BUSY)" or "FOOD MULTIPLIER"
	end

	local function collect(player, job)
		local room = Config.MAX_FOOD_CARRIED - ToolUtil.countFood(player)
		local given = 0
		while given < room and #job.items > 0 do
			local ft = table.remove(job.items)
			ToolUtil.makeFoodTool(ft, { multiplied = true }).Parent = player.Backpack
			given = given + 1
		end
		if given > 0 then
			GameSystems.onFoodCollected(player, given)
		end
		if #job.items == 0 then
			multiplierJobs[player.UserId] = nil
			notify(player, "Collected " .. given .. " food from the multiplier")
		else
			notify(player, "Hands full! " .. #job.items .. " food still waiting in the multiplier")
		end
		refreshMachineVisuals()
	end

	craftPrompt.Triggered:Connect(function(player)
		local job = multiplierJobs[player.UserId]
		if job then
			local remaining = job.readyAt - os.clock()
			if remaining > 0 then
				notify(player, string.format("Your food is processing: %ds left", math.ceil(remaining)))
			else
				collect(player, job)
			end
			return
		end

		-- Multiplier output cannot be multiplied again (prevents exponential loops)
		local tool = ToolUtil.findFoodTool(player, function(t)
			return t:FindFirstChild("Handle"):GetAttribute("Multiplied") ~= true
		end)
		if not tool then
			notify(player, "Insert stolen food (multiplied food can't be processed again)")
			return
		end

		local foodType =
			ToolUtil.findFoodType(Config.FOOD_TYPES, tool:FindFirstChild("Handle"):GetAttribute("FoodId") or tool.Name)
		if not foodType then
			return
		end
		tool:Destroy()

		local items = {}
		for _ = 1, Config.MULTIPLIER_FACTOR do
			table.insert(items, foodType)
		end
		multiplierJobs[player.UserId] = { items = items, readyAt = os.clock() + Config.MULTIPLIER_TIME }
		notify(player, foodType.name .. " inserted. Come back in " .. Config.MULTIPLIER_TIME .. "s")
		refreshMachineVisuals()
	end)

	-- Pulse the indicator while any job is running
	task.spawn(function()
		while craftMachine.Parent do
			if next(multiplierJobs) then
				indicator.Transparency = math.abs(math.sin(os.clock() * 3)) * 0.5
			else
				indicator.Transparency = 0
			end
			task.wait(0.2)
		end
	end)

	return baseModel
end

return BaseBuilder
