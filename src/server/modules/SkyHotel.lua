-- SkyHotel.lua
-- Generates the "Sky Hotel Castle" — a platform high in the sky containing:
--   • A stone floor platform (120 × 120 studs at Config.SKY_HOTEL_Y)
--   • A "Castle" Model with breakable Walls and a Door
--     (targeted by the Bat's Castle-destruction logic in BatCombat.lua)
--   • Three healing food stations — players press E to consume and restore HP
--   • A Magic Carpet Chest — opens every 30 s per player and awards bonus Money
--
-- Visual improvements applied throughout:
--   • Cobblestone / SmoothPlastic materials
--   • Non-zero Reflectance on stone and wood surfaces
--   • Neon accents on food-station indicators

local Players = game:GetService("Players")

local SkyHotel = {}

local Config = nil

-- -------------------------------------------------------------------------
-- Internal helper: create an anchored BasePart
-- -------------------------------------------------------------------------
local function makePart(name, size, position, brickColorName, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.BrickColor = BrickColor.new(brickColorName)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent = parent
	return p
end

-- -------------------------------------------------------------------------
-- Platform floor
-- -------------------------------------------------------------------------
local function buildPlatform(parent)
	local center = Config.SKY_HOTEL_CENTER
	local y = Config.SKY_HOTEL_Y

	-- Main stone floor
	local floor = makePart(
		"SkyFloor",
		Vector3.new(120, 4, 120),
		Vector3.new(center.X, y, center.Z),
		"Medium stone grey",
		Enum.Material.Cobblestone,
		parent
	)
	floor.Reflectance = 0.05

	-- Decorative edge trim (four strips, Neon yellow)
	local trimDefs = {
		{ size = Vector3.new(120, 0.5, 1), offset = Vector3.new(0, 2, 60) },
		{ size = Vector3.new(120, 0.5, 1), offset = Vector3.new(0, 2, -60) },
		{ size = Vector3.new(1, 0.5, 120), offset = Vector3.new(60, 2, 0) },
		{ size = Vector3.new(1, 0.5, 120), offset = Vector3.new(-60, 2, 0) },
	}
	for _, def in ipairs(trimDefs) do
		local trim = makePart(
			"EdgeTrim",
			def.size,
			Vector3.new(center.X + def.offset.X, y + def.offset.Y, center.Z + def.offset.Z),
			"Bright yellow",
			Enum.Material.Neon,
			parent
		)
		trim.CanCollide = false
	end

	return floor
end

-- -------------------------------------------------------------------------
-- Castle model with breakable Walls and a Door
-- -------------------------------------------------------------------------
local function buildCastle(parent)
	local center = Config.SKY_HOTEL_CENTER
	local y = Config.SKY_HOTEL_Y
	local hp = Config.CASTLE_PART_HEALTH

	local castle = Instance.new("Model")
	castle.Name = "Castle"
	castle.Parent = parent

	-- Four perimeter walls
	local wallDefs = {
		{ size = Vector3.new(80, 20, 5), pos = Vector3.new(center.X, y + 12, center.Z - 40) }, -- north
		{ size = Vector3.new(80, 20, 5), pos = Vector3.new(center.X, y + 12, center.Z + 40) }, -- south
		{ size = Vector3.new(5, 20, 80), pos = Vector3.new(center.X - 40, y + 12, center.Z) }, -- west
		{ size = Vector3.new(5, 20, 80), pos = Vector3.new(center.X + 40, y + 12, center.Z) }, -- east
	}
	for _, def in ipairs(wallDefs) do
		local wall = makePart("Wall", def.size, def.pos, "Medium stone grey", Enum.Material.SmoothPlastic, castle)
		wall.Reflectance = 0.08
		wall:SetAttribute("Health", hp)
	end

	-- Entrance door (centred in the north wall, shorter so players can see the gap)
	local door = makePart(
		"Door",
		Vector3.new(10, 14, 5),
		Vector3.new(center.X, y + 9, center.Z - 40),
		"Dark orange",
		Enum.Material.Wood,
		castle
	)
	door.Reflectance = 0.04
	door:SetAttribute("Health", hp)

	-- Corner towers (4 × decorative cylinders)
	local towerOffsets = {
		Vector3.new(-40, 0, -40),
		Vector3.new(40, 0, -40),
		Vector3.new(-40, 0, 40),
		Vector3.new(40, 0, 40),
	}
	for _, off in ipairs(towerOffsets) do
		local tower = makePart(
			"Tower",
			Vector3.new(8, 26, 8),
			Vector3.new(center.X + off.X, y + 15, center.Z + off.Z),
			"Medium stone grey",
			Enum.Material.Cobblestone,
			castle
		)
		tower.Reflectance = 0.06
	end
end

-- -------------------------------------------------------------------------
-- Healing food stations
-- -------------------------------------------------------------------------
local function buildHealingFoods(parent)
	local center = Config.SKY_HOTEL_CENTER
	local y = Config.SKY_HOTEL_Y
	local healValues = Config.SKY_HOTEL_FOOD_HEAL
	local respawnTime = Config.SKY_HOTEL_FOOD_RESPAWN

	local foodDefs = {
		{ name = "Sky Apple", color = "Bright red", heal = healValues[1], pos = Vector3.new(center.X - 20, y + 4, center.Z - 20) },
		{ name = "Star Berry", color = "Bright violet", heal = healValues[2], pos = Vector3.new(center.X + 20, y + 4, center.Z - 20) },
		{ name = "Cloud Cake", color = "White", heal = healValues[3], pos = Vector3.new(center.X, y + 4, center.Z + 20) },
	}

	for _, def in ipairs(foodDefs) do
		-- Base pedestal
		local pedestal = makePart(
			"FoodPedestal",
			Vector3.new(2, 1, 2),
			def.pos - Vector3.new(0, 0.5, 0),
			"Light stone grey",
			Enum.Material.SmoothPlastic,
			parent
		)
		pedestal.Reflectance = 0.1

		-- Food visual sphere
		local foodPart = makePart("HealingFood_" .. def.name, Vector3.new(1.8, 1.8, 1.8), def.pos, def.color, Enum.Material.SmoothPlastic, parent)
		foodPart.Shape = Enum.PartType.Ball
		foodPart.Reflectance = 0.25
		foodPart.CastShadow = false

		-- Neon glow dot above the food
		local glow = makePart("FoodGlow", Vector3.new(0.5, 0.5, 0.5), def.pos + Vector3.new(0, 1.5, 0), "Bright green", Enum.Material.Neon, parent)
		glow.Shape = Enum.PartType.Ball
		glow.CanCollide = false

		-- Floating label
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 120, 0, 36)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop = false
		bb.Parent = foodPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.Text = def.name .. "\n+" .. def.heal .. " HP"
		lbl.TextColor3 = Color3.fromRGB(100, 255, 120)
		lbl.BackgroundTransparency = 1
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = bb

		-- ProximityPrompt — server-side health restoration
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Eat"
		pp.ObjectText = def.name .. " (+" .. def.heal .. " HP)"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 6
		pp.Parent = foodPart

		pp.Triggered:Connect(function(player)
			-- Disable immediately to prevent any player from eating while respawning
			pp.Enabled = false
			foodPart.Transparency = 0.9
			glow.Transparency = 0.9

			local char = player.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = math.min(humanoid.Health + def.heal, humanoid.MaxHealth)
				end
			end

			-- Re-enable for all players once the food has respawned
			task.delay(respawnTime, function()
				if foodPart and foodPart.Parent then
					foodPart.Transparency = 0
					glow.Transparency = 0
					pp.Enabled = true
				end
			end)
		end)
	end
end

-- -------------------------------------------------------------------------
-- Magic Carpet Chest — awards bonus Money; hints at the night carpet
-- -------------------------------------------------------------------------
local function buildChest(parent)
	local center = Config.SKY_HOTEL_CENTER
	local y = Config.SKY_HOTEL_Y
	local chestPos = Vector3.new(center.X - 35, y + 4, center.Z)

	-- Chest body (wood box)
	local body = makePart("MagicCarpetChest", Vector3.new(3, 2.5, 2), chestPos, "CGA brown", Enum.Material.Wood, parent)
	body.Reflectance = 0.05

	-- Lid
	local lid = makePart("ChestLid", Vector3.new(3, 0.5, 2), chestPos + Vector3.new(0, 1.5, 0), "Bright yellow", Enum.Material.Wood, parent)
	lid.Reflectance = 0.08
	lid.CanCollide = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = lid
	weld.Parent = body

	-- Floating label
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 160, 0, 30)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = false
	bb.Parent = body

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Text = "✨ Magic Carpet Chest"
	lbl.TextColor3 = Color3.fromRGB(255, 220, 60)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb

	-- ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open"
	pp.ObjectText = "Magic Carpet Chest"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 8
	pp.Parent = body

	local chestCooldowns = {}

	pp.Triggered:Connect(function(player)
		local now = tick()
		if now - (chestCooldowns[player.UserId] or 0) < Config.SKY_HOTEL_CHEST_COOLDOWN then
			return
		end
		chestCooldowns[player.UserId] = now

		-- Award bonus Money
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local money = ls:FindFirstChild("Money")
			if money then
				money.Value = money.Value + Config.SKY_HOTEL_CHEST_REWARD
			end
		end

		-- Give the player a FlyingCarpet tool directly
		-- (independent copy — works even during daytime unlike the night spawn)
		local carpetTool = Instance.new("Tool")
		carpetTool.Name = "FlyingCarpet"
		carpetTool.RequiresHandle = true
		carpetTool.ToolTip = "A magical flying carpet!"

		local carpetHandle = Instance.new("Part")
		carpetHandle.Name = "Handle"
		carpetHandle.Size = Vector3.new(6, 0.3, 4)
		carpetHandle.BrickColor = BrickColor.new("Bright red")
		carpetHandle.Material = Enum.Material.Fabric
		carpetHandle.Reflectance = 0.12
		carpetHandle.CanCollide = false
		carpetHandle:SetAttribute("IsCarpet", true)
		carpetHandle.Parent = carpetTool

		-- Decorative neon borders on the handle
		for _, b in ipairs({
			{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, 1.85) },
			{ size = Vector3.new(6, 0.3, 0.3), offset = Vector3.new(0, 0, -1.85) },
			{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(2.85, 0, 0) },
			{ size = Vector3.new(0.3, 0.3, 4), offset = Vector3.new(-2.85, 0, 0) },
		}) do
			local strip = Instance.new("Part")
			strip.Size = b.size
			strip.BrickColor = BrickColor.new("Bright yellow")
			strip.Material = Enum.Material.Neon
			strip.CanCollide = false
			strip.CFrame = CFrame.new(b.offset)
			strip.Parent = carpetTool
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = carpetHandle, strip
			w.Parent = carpetHandle
		end

		carpetTool.Parent = player.Backpack

		-- Brief visual feedback: golden flash on the chest
		local flash = Instance.new("PointLight")
		flash.Color = Color3.fromRGB(255, 220, 50)
		flash.Brightness = 6
		flash.Range = 18
		flash.Parent = body
		task.delay(1.5, function()
			if flash and flash.Parent then
				flash:Destroy()
			end
		end)
	end)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function SkyHotel.init(config)
	Config = config
end

function SkyHotel.build()
	local skyModel = Instance.new("Model")
	skyModel.Name = "SkyHotel"
	skyModel.Parent = workspace

	buildPlatform(skyModel)
	buildCastle(skyModel)
	buildHealingFoods(skyModel)
	buildChest(skyModel)

	print("[SkyHotel] Sky Hotel Castle built at Y=" .. Config.SKY_HOTEL_Y)
end

return SkyHotel
