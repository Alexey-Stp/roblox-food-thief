-- GameSystems.lua
-- Manages per-player leaderboard stats and DataStore persistence.
-- Saves: Score, Food Stolen, Money, food inventory (with price metadata),
--        WalkSpeed, JumpPower, fridge level, and the persistent collectedFood set.
--
-- Data-safety rules:
--   • A player's data is only saved after it was loaded successfully.
--     If every load attempt fails, the session runs unsaved so the real
--     record is never overwritten with defaults.
--   • Movement settings are saved from the cached settings, never from the
--     live Humanoid (which may be temporarily changed, e.g. by a guard stun).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ToolUtil = require(script.Parent.ToolUtil)

local GameSystems = {}

-- Config injected via init() — needed for FOOD_TYPES lookup during inventory restore
local Config = nil

-- Score values (overridden from Config in init; defaults keep the module usable standalone)
local SCORE_STEAL = 10
local SCORE_STORE = 25
local SCORE_COLLECT = 50

-- DataStore versioned key. v3 shape is backward compatible: inventory entries
-- may be plain food names (old saves) or tables { id, price, stored, multiplied }.
local DATA_STORE_KEY = "PlayerData_v3"
local playerStore = nil

local ok, store = pcall(function()
	return DataStoreService:GetDataStore(DATA_STORE_KEY)
end)
if ok then
	playerStore = store
else
	warn("[GameSystems] DataStore unavailable — progress will not persist: " .. tostring(store))
end

-- Per-player runtime settings keyed by UserId:
-- { walkSpeed, jumpPower, fridgeLevel, collectedFood = {}, loaded = bool }
local playerSettings = {}

-- Saves currently in flight (UserId → true); BindToClose waits for these.
local savesInFlight = {}

local HUMANOID_INIT_DELAY = 0.2
local AUTO_SAVE_INTERVAL = 300
local LOAD_ATTEMPTS = 3
local SAVE_ATTEMPTS = 3

-- -------------------------------------------------------------------------
-- Internal helpers
-- -------------------------------------------------------------------------

local function getStat(player, statName)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(statName)
end

local function addToStat(player, statName, amount)
	local stat = getStat(player, statName)
	if stat then
		stat.Value = stat.Value + amount
	end
end

local function clamp(value, minValue, maxValue)
	return math.max(minValue, math.min(value, maxValue))
end

-- Runs fn with retries and exponential backoff. Returns ok, result.
local function withRetries(attempts, fn)
	local lastErr
	for attempt = 1, attempts do
		local success, result = pcall(fn)
		if success then
			return true, result
		end
		lastErr = result
		if attempt < attempts then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastErr
end

local function publishFridgeAttributes(player, level)
	player:SetAttribute("FridgeLevel", level)
end

local function buildSaveData(player)
	local ls = player:FindFirstChild("leaderstats")
	local settings = playerSettings[player.UserId]
	if not ls or not settings then
		return nil
	end

	local inventory = {}
	for _, tool in ipairs(ToolUtil.getFoodTools(player)) do
		local data = ToolUtil.readFoodData(tool)
		if data then
			table.insert(inventory, data)
		end
	end

	local collectedList = {}
	for foodName in pairs(settings.collectedFood) do
		table.insert(collectedList, foodName)
	end

	return {
		foodStolen = (ls:FindFirstChild("Food Stolen") or {}).Value or 0,
		score = (ls:FindFirstChild("Score") or {}).Value or 0,
		money = (ls:FindFirstChild("Money") or {}).Value or 0,
		inventory = inventory,
		walkSpeed = settings.walkSpeed,
		jumpPower = settings.jumpPower,
		fridgeLevel = settings.fridgeLevel,
		collectedFood = collectedList,
	}
end

local function savePlayer(player)
	if not playerStore then
		return
	end
	local settings = playerSettings[player.UserId]
	-- Never save a player whose data did not load — that would wipe their record.
	if not settings or not settings.loaded then
		return
	end
	if savesInFlight[player.UserId] then
		return
	end

	local data = buildSaveData(player)
	if not data then
		return
	end

	savesInFlight[player.UserId] = true
	local success, err = withRetries(SAVE_ATTEMPTS, function()
		playerStore:UpdateAsync(tostring(player.UserId), function()
			return data
		end)
	end)
	savesInFlight[player.UserId] = nil

	if not success then
		warn("[GameSystems] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Apply the cached WalkSpeed / JumpPower to a player's humanoid.
local function applySettings(player)
	local settings = playerSettings[player.UserId]
	if not settings then
		return
	end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = settings.walkSpeed
	humanoid.JumpPower = settings.jumpPower
end

-- Saved WalkSpeed / JumpPower. Values above the shop cap can't come from a
-- purchase — they are leftovers of the old 500/500 debug defaults — so they
-- reset to the default instead of granting free max upgrades.
local function loadMovementValue(saved, default, max)
	if type(saved) ~= "number" or saved > max then
		return default
	end
	return clamp(saved, default, max)
end

local function restoreInventory(player, inventory)
	if type(inventory) ~= "table" or #inventory == 0 then
		return
	end
	task.spawn(function()
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(1) -- let character fully initialise
		if not player.Parent then
			return
		end
		local limit = Config.MAX_FOOD_CARRIED or math.huge
		local given = 0
		for _, entry in ipairs(inventory) do
			if given >= limit then
				break
			end
			-- Old saves stored plain names; new saves store metadata tables
			local id = type(entry) == "table" and entry.id or entry
			local ft = ToolUtil.findFoodType(Config.FOOD_TYPES, id)
			if ft then
				local opts = {}
				if type(entry) == "table" then
					local maxPrice =
						math.floor(ft.sellPrice * (1 + Config.FRIDGE_BONUS_PER_LEVEL * Config.FRIDGE_MAX_LEVEL))
					opts.currentPrice = type(entry.price) == "number" and clamp(entry.price, 0, maxPrice) or nil
					opts.storedAtLevel = type(entry.stored) == "number" and entry.stored or 0
					opts.multiplied = entry.multiplied == true
				end
				ToolUtil.makeFoodTool(ft, opts).Parent = player.Backpack
				given = given + 1
			end
		end
	end)
end

local function loadPlayer(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local foodStolen = Instance.new("IntValue")
	foodStolen.Name = "Food Stolen"
	foodStolen.Parent = ls

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Parent = ls

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Parent = ls

	local settings = {
		walkSpeed = Config.DEFAULT_WALK_SPEED,
		jumpPower = Config.DEFAULT_JUMP_POWER,
		fridgeLevel = 1,
		collectedFood = {},
		loaded = false,
	}
	playerSettings[player.UserId] = settings
	publishFridgeAttributes(player, settings.fridgeLevel)

	-- Re-apply WalkSpeed / JumpPower whenever this player's character (re)spawns
	player.CharacterAdded:Connect(function()
		task.wait(HUMANOID_INIT_DELAY)
		applySettings(player)
	end)

	if not playerStore then
		-- Studio without API access: run the session unsaved
		return
	end

	local success, data = withRetries(LOAD_ATTEMPTS, function()
		return playerStore:GetAsync(tostring(player.UserId))
	end)

	-- Player may have left while we were loading
	if not player.Parent or playerSettings[player.UserId] ~= settings then
		return
	end

	if not success then
		warn(
			"[GameSystems] Could not load data for "
				.. player.Name
				.. " — session will NOT be saved to protect existing data: "
				.. tostring(data)
		)
		return
	end

	if type(data) == "table" then
		-- Additive: anything earned during the load window is kept
		foodStolen.Value = foodStolen.Value + (data.foodStolen or 0)
		score.Value = score.Value + (data.score or 0)
		money.Value = money.Value + (data.money or 0)

		settings.walkSpeed = loadMovementValue(data.walkSpeed, Config.DEFAULT_WALK_SPEED, Config.MAX_WALK_SPEED)
		settings.jumpPower = loadMovementValue(data.jumpPower, Config.DEFAULT_JUMP_POWER, Config.MAX_JUMP_POWER)
		settings.fridgeLevel = clamp(math.floor(tonumber(data.fridgeLevel) or 1), 1, Config.FRIDGE_MAX_LEVEL)
		publishFridgeAttributes(player, settings.fridgeLevel)

		if type(data.collectedFood) == "table" then
			for _, foodName in ipairs(data.collectedFood) do
				settings.collectedFood[foodName] = true
			end
		end

		restoreInventory(player, data.inventory)
	end

	settings.loaded = true
	applySettings(player)
end

-- -------------------------------------------------------------------------
-- Public API — stats
-- -------------------------------------------------------------------------

function GameSystems.onFoodStolen(player)
	addToStat(player, "Food Stolen", 1)
	addToStat(player, "Score", SCORE_STEAL)
end

function GameSystems.onFoodStored(player)
	addToStat(player, "Score", SCORE_STORE)
end

function GameSystems.onFoodCollected(player, count)
	addToStat(player, "Score", count * SCORE_COLLECT)
end

function GameSystems.addMoney(player, amount)
	addToStat(player, "Money", amount)
end

-- Kept for existing callers: selling food awards Money
GameSystems.onFoodSold = GameSystems.addMoney

-- Atomically checks and deducts Money. Returns true when the purchase succeeded.
function GameSystems.trySpend(player, amount)
	local m = getStat(player, "Money")
	if not m or m.Value < amount then
		return false
	end
	m.Value = m.Value - amount
	return true
end

-- -------------------------------------------------------------------------
-- Public API — collected food
-- -------------------------------------------------------------------------

-- Returns true the first time a food name is recorded for this player.
function GameSystems.recordFoodCollected(player, foodName)
	local settings = playerSettings[player.UserId]
	if not settings or settings.collectedFood[foodName] then
		return false
	end
	settings.collectedFood[foodName] = true
	return true
end

function GameSystems.getCollectedFood(player)
	local settings = playerSettings[player.UserId]
	if not settings then
		return {}
	end
	return table.clone(settings.collectedFood)
end

-- -------------------------------------------------------------------------
-- Public API — movement settings
-- -------------------------------------------------------------------------

-- Returns walkSpeed, jumpPower from the cache (nil when the player is unknown).
function GameSystems.getSettings(player)
	local settings = playerSettings[player.UserId]
	if not settings then
		return nil, nil
	end
	return settings.walkSpeed, settings.jumpPower
end

-- Updates cached WalkSpeed / JumpPower (clamped to Config limits) so they are
-- saved and re-applied on respawn.
function GameSystems.updateSettings(player, walkSpeed, jumpPower)
	local settings = playerSettings[player.UserId]
	if not settings then
		return
	end
	if walkSpeed then
		settings.walkSpeed = clamp(walkSpeed, Config.DEFAULT_WALK_SPEED, Config.MAX_WALK_SPEED)
	end
	if jumpPower then
		settings.jumpPower = clamp(jumpPower, Config.DEFAULT_JUMP_POWER, Config.MAX_JUMP_POWER)
	end
end

-- Re-applies cached movement settings to the live Humanoid (e.g. after a stun).
GameSystems.applySettings = applySettings

-- -------------------------------------------------------------------------
-- Public API — fridge level (per player, persisted)
-- -------------------------------------------------------------------------

function GameSystems.getFridgeLevel(player)
	local settings = playerSettings[player.UserId]
	return settings and settings.fridgeLevel or 1
end

function GameSystems.setFridgeLevel(player, level)
	local settings = playerSettings[player.UserId]
	if not settings then
		return
	end
	settings.fridgeLevel = level
	publishFridgeAttributes(player, level)
end

-- -------------------------------------------------------------------------
-- Lifecycle
-- -------------------------------------------------------------------------

function GameSystems.init(config)
	Config = config
	SCORE_STEAL = config.SCORE_STEAL or SCORE_STEAL
	SCORE_STORE = config.SCORE_STORE or SCORE_STORE
	SCORE_COLLECT = config.SCORE_COLLECT or SCORE_COLLECT

	Players.PlayerAdded:Connect(loadPlayer)

	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		playerSettings[player.UserId] = nil
	end)

	game:BindToClose(function()
		-- Save everyone in parallel, then wait (bounded) for all writes to finish
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(savePlayer, player)
		end
		local deadline = os.clock() + 25
		while next(savesInFlight) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Handle players already in the server before this module loaded
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:FindFirstChild("leaderstats") then
			task.spawn(loadPlayer, player)
		end
	end

	-- Periodic auto-save to reduce data loss on crash
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(savePlayer, player)
			end
		end
	end)
end

return GameSystems
