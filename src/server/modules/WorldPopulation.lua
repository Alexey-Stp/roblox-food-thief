-- WorldPopulation.lua
-- Positions the imported static buildings (McDonald's, Dodo's Pizza, castle)
-- on the open map and spawns hostile enemies inside and around them.
-- Map reference:
--   Hotel       (0,   0,    0)  size 350×350
--   Safe Base   (500, 1,    0)
--   McDonald's  (-500, 1,   0)   west
--   Dodo's Pizza (0,  1, -500)   north
--   Castle/Model (-500, 1, -500) northwest
--   NPC zombie  (-350, 1,  300)  south-west roaming
--   Ram Monster  (300, 1, -350)  north-east roaming

local WorldPopulation = {}

local Config = nil
local EnemyAI = nil

-- -------------------------------------------------------------------------
-- Where to move each imported building (pivot / origin point)
-- -------------------------------------------------------------------------
local BUILDING_ANCHORS = {
	["McDonald's"] = Vector3.new(-500, 1, 0),
	["Dodo's pizza Restaurant"] = Vector3.new(0, 1, -500),
	["Model"] = Vector3.new(-500, 1, -500), -- castle/lights
}

-- -------------------------------------------------------------------------
-- Where to move the NPC / monster models from Studio
-- -------------------------------------------------------------------------
local NPC_ANCHORS = {
	["NPC"] = Vector3.new(-350, 1, 300),
	["Ram Monster"] = Vector3.new(300, 1, -350),
}

-- -------------------------------------------------------------------------
-- Enemies to spawn per building
-- { name, offset from building anchor, difficulty level (1=wolf 2=bear 3=occultist) }
-- -------------------------------------------------------------------------
local BUILDING_ENEMIES = {
	["McDonald's"] = {
		{ name = "McGuard1", offset = Vector3.new(0, 5, 0), level = 1 },
		{ name = "McGuard2", offset = Vector3.new(30, 5, 0), level = 1 },
		{ name = "McHunter", offset = Vector3.new(-30, 5, 20), level = 2 },
	},
	["Dodo's pizza Restaurant"] = {
		{ name = "PizzaWolf1", offset = Vector3.new(0, 5, 0), level = 1 },
		{ name = "PizzaWolf2", offset = Vector3.new(20, 5, 20), level = 1 },
		{ name = "PizzaBear", offset = Vector3.new(-20, 5, -20), level = 2 },
	},
	["Model"] = { -- castle
		{ name = "CastleGuard1", offset = Vector3.new(0, 5, 0), level = 2 },
		{ name = "CastleGuard2", offset = Vector3.new(50, 5, 0), level = 2 },
		{ name = "CastleOccultist", offset = Vector3.new(-50, 5, 0), level = 3 },
		{ name = "CastleWraith", offset = Vector3.new(0, 5, 50), level = 3 },
	},
}

-- -------------------------------------------------------------------------
-- Open-map roaming enemies (patrol the area between buildings)
-- -------------------------------------------------------------------------
local MAP_ENEMIES = {
	{ name = "Drifter1", pos = Vector3.new(-280, 5, -280), level = 1 },
	{ name = "Drifter2", pos = Vector3.new(280, 5, -280), level = 1 },
	{ name = "Stalker1", pos = Vector3.new(-280, 5, 280), level = 2 },
	{ name = "Stalker2", pos = Vector3.new(280, 5, 280), level = 2 },
	{ name = "Phantom1", pos = Vector3.new(-420, 5, 0), level = 3 },
	{ name = "Phantom2", pos = Vector3.new(0, 5, -420), level = 3 },
}

-- -------------------------------------------------------------------------

function WorldPopulation.init(config, enemyAI)
	Config = config
	EnemyAI = enemyAI
end

function WorldPopulation.populate()
	-- Give Rojo-synced models a moment to fully load into Workspace
	task.wait(2)

	-- Move imported buildings to their map positions
	for modelName, anchor in pairs(BUILDING_ANCHORS) do
		local model = workspace:FindFirstChild(modelName)
		if model then
			local ok, err = pcall(function()
				model:PivotTo(CFrame.new(anchor))
			end)
			if not ok then
				warn("[WorldPopulation] Could not reposition '" .. modelName .. "': " .. tostring(err))
			else
				print("[WorldPopulation] Placed '" .. modelName .. "' at " .. tostring(anchor))
			end
		else
			warn("[WorldPopulation] Building not found in Workspace: '" .. modelName .. "'")
		end
	end

	-- Move NPC / monster models to their map positions
	for npcName, anchor in pairs(NPC_ANCHORS) do
		local model = workspace:FindFirstChild(npcName)
		if model then
			local ok = pcall(function()
				model:PivotTo(CFrame.new(anchor))
			end)
			if ok then
				print("[WorldPopulation] Placed '" .. npcName .. "' at " .. tostring(anchor))
			end
		end
	end

	-- Spawn game enemies around each building
	for modelName, enemies in pairs(BUILDING_ENEMIES) do
		local anchor = BUILDING_ANCHORS[modelName]
		local model = workspace:FindFirstChild(modelName)
		local basePos = model and model:GetPivot().Position or anchor

		for _, def in ipairs(enemies) do
			local spawnPos = basePos + def.offset
			task.spawn(function()
				EnemyAI.spawn(def.name, spawnPos, Config, def.level)
			end)
		end
	end

	-- Spawn open-map roaming enemies
	for _, def in ipairs(MAP_ENEMIES) do
		task.spawn(function()
			EnemyAI.spawn(def.name, def.pos, Config, def.level)
		end)
	end

	print("[WorldPopulation] World populated.")
end

return WorldPopulation
