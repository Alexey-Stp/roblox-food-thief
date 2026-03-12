-- GameSystems.lua
-- Manages per-player leaderboard stats and DataStore persistence.
-- Saves: Score, Food Stolen, Money, backpack inventory (food tool names),
--        WalkSpeed, JumpPower, and the persistent collectedFood set.

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local GameSystems = {}

-- Config injected via init() — needed for FOOD_TYPES lookup during inventory restore
local Config = nil

-- DataStore versioned key (bumped to v3 for WalkSpeed, JumpPower, collectedFood)
local DATA_STORE_KEY = "PlayerData_v3"
local playerStore    = nil

local ok, store = pcall(function()
	return DataStoreService:GetDataStore(DATA_STORE_KEY)
end)
if ok then
	playerStore = store
else
	warn("[GameSystems] DataStore unavailable — progress will not persist: " .. tostring(store))
end

-- Per-player runtime settings (WalkSpeed, JumpPower, collectedFood set).
-- Keyed by player.UserId so they survive character respawns.
local playerSettings = {}

-- Delay (seconds) after CharacterAdded before applying settings.
-- Gives the Humanoid time to fully initialise.
local HUMANOID_INIT_DELAY = 0.2

-- How often (seconds) to auto-save all players' data as a crash safeguard.
local AUTO_SAVE_INTERVAL = 300

-- -------------------------------------------------------------------------
-- Internal helpers
-- -------------------------------------------------------------------------

local function getStat(player, statName)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(statName)
end

local function findFoodType(name)
	if not Config then return nil end
	for _, ft in ipairs(Config.FOOD_TYPES) do
		if ft.name == name then return ft end
	end
	return nil
end

local function makeFoodTool(ft)
	local tool = Instance.new("Tool")
	tool.Name           = ft.name
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name      = "Handle"
	handle.Size      = ft.size * 0.7
	handle.BrickColor = ft.color
	handle.Material  = Enum.Material.SmoothPlastic

	if ft.texture then
		local decal = Instance.new("Decal")
		decal.Texture = ft.texture
		decal.Face    = Enum.NormalId.Top
		decal.Parent  = handle
	end

	handle.Parent = tool
	return tool
end

local function savePlayer(player)
	if not playerStore then return end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end

	-- Collect backpack inventory tool names
	local invNames = {}
	local char = player.Character
	if char then
		local eq = char:FindFirstChildOfClass("Tool")
		if eq then table.insert(invNames, eq.Name) end
	end
	for _, t in ipairs(player.Backpack:GetChildren()) do
		if t:IsA("Tool") then table.insert(invNames, t.Name) end
	end

	-- Read current WalkSpeed / JumpPower from the live humanoid (or fall back to
	-- the cached settings if the character has already been destroyed).
	local settings  = playerSettings[player.UserId] or {}
	local humanoid  = char and char:FindFirstChildOfClass("Humanoid")
	local walkSpeed = (humanoid and humanoid.WalkSpeed) or settings.walkSpeed or 16
	local jumpPower = (humanoid and humanoid.JumpPower) or settings.jumpPower or 50

	-- Build a serialisable list from the collectedFood set
	local collectedList = {}
	for foodName in pairs(settings.collectedFood or {}) do
		table.insert(collectedList, foodName)
	end

	local data = {
		foodStolen    = (ls:FindFirstChild("Food Stolen") or {}).Value or 0,
		score         = (ls:FindFirstChild("Score")       or {}).Value or 0,
		money         = (ls:FindFirstChild("Money")       or {}).Value or 0,
		inventory     = invNames,
		walkSpeed     = walkSpeed,
		jumpPower     = jumpPower,
		collectedFood = collectedList,
	}

	local success, err = pcall(function()
		playerStore:SetAsync(tostring(player.UserId), data)
	end)
	if not success then
		warn("[GameSystems] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Apply the cached WalkSpeed / JumpPower to a player's humanoid.
-- Called on CharacterAdded so settings survive respawn.
local function applySettings(player)
	local settings = playerSettings[player.UserId]
	if not settings then return end

	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.WalkSpeed = settings.walkSpeed
	humanoid.JumpPower = settings.jumpPower
end

local function loadPlayer(player)
	local ls = Instance.new("Folder")
	ls.Name   = "leaderstats"
	ls.Parent = player

	local foodStolen = Instance.new("IntValue")
	foodStolen.Name   = "Food Stolen"
	foodStolen.Value  = 0
	foodStolen.Parent = ls

	local score = Instance.new("IntValue")
	score.Name   = "Score"
	score.Value  = 0
	score.Parent = ls

	local money = Instance.new("IntValue")
	money.Name   = "Money"
	money.Value  = 0
	money.Parent = ls

	-- Initialise runtime settings with safe defaults (WalkSpeed=16, JumpPower=50)
	playerSettings[player.UserId] = {
		walkSpeed     = 16,
		jumpPower     = 50,
		collectedFood = {},
	}

	if playerStore then
		local success, data = pcall(function()
			return playerStore:GetAsync(tostring(player.UserId))
		end)

		if success and type(data) == "table" then
			foodStolen.Value = data.foodStolen or 0
			score.Value      = data.score      or 0
			money.Value      = data.money      or 0

			-- Restore WalkSpeed / JumpPower (default to Roblox defaults if absent)
			playerSettings[player.UserId].walkSpeed = data.walkSpeed or 16
			playerSettings[player.UserId].jumpPower = data.jumpPower or 50

			-- Restore collectedFood set from the saved list
			if type(data.collectedFood) == "table" then
				for _, foodName in ipairs(data.collectedFood) do
					playerSettings[player.UserId].collectedFood[foodName] = true
				end
			end

			-- Restore backpack inventory tools after the character has spawned
			if type(data.inventory) == "table" and #data.inventory > 0 then
				task.spawn(function()
					if not player.Character then
						player.CharacterAdded:Wait()
					end
					task.wait(1)  -- let character fully initialise
					for _, foodName in ipairs(data.inventory) do
						local ft = findFoodType(foodName)
						if ft then
							local tool = makeFoodTool(ft)
							tool.Parent = player.Backpack
						end
					end
				end)
			end
		end
	end

	-- Re-apply WalkSpeed / JumpPower whenever this player's character (re)spawns
	player.CharacterAdded:Connect(function()
		task.wait(HUMANOID_INIT_DELAY)
		applySettings(player)
	end)

	-- Apply immediately if the character is already present (e.g. late-loaded module)
	if player.Character then
		task.spawn(function()
			task.wait(HUMANOID_INIT_DELAY)
			applySettings(player)
		end)
	end
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function GameSystems.onFoodStolen(player)
	local stat = getStat(player, "Food Stolen")
	if stat then stat.Value = stat.Value + 1 end
	local score = getStat(player, "Score")
	if score then score.Value = score.Value + 10 end
end

function GameSystems.onFoodStored(player)
	local score = getStat(player, "Score")
	if score then score.Value = score.Value + 25 end
end

function GameSystems.onFoodCollected(player, count)
	local score = getStat(player, "Score")
	if score then score.Value = score.Value + count * 50 end
end

function GameSystems.onFoodSold(player, amount)
	local m = getStat(player, "Money")
	if m then m.Value = m.Value + amount end
end

-- Record that a player has collected a specific food item.
-- Returns true the first time that food name is recorded (new discovery),
-- false if it was already in the player's collected set (duplicate).
function GameSystems.recordFoodCollected(player, foodName)
	local settings = playerSettings[player.UserId]
	if not settings then return false end
	if settings.collectedFood[foodName] then
		return false  -- already collected — duplicate
	end
	settings.collectedFood[foodName] = true
	return true  -- newly collected
end

-- Returns a copy of the player's collected food set (table of foodName → true).
function GameSystems.getCollectedFood(player)
	local settings = playerSettings[player.UserId]
	if not settings then return {} end
	local copy = {}
	for k, v in pairs(settings.collectedFood) do
		copy[k] = v
	end
	return copy
end

-- Update cached WalkSpeed / JumpPower so they are saved correctly on next save.
-- Called by BaseBuilder's shop whenever a player buys a boost.
function GameSystems.updateSettings(player, walkSpeed, jumpPower)
	local settings = playerSettings[player.UserId]
	if not settings then return end
	if walkSpeed then settings.walkSpeed = walkSpeed end
	if jumpPower then settings.jumpPower = jumpPower end
end

-- -------------------------------------------------------------------------
-- Lifecycle
-- -------------------------------------------------------------------------

function GameSystems.init(config)
	Config = config

	Players.PlayerAdded:Connect(loadPlayer)

	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		-- Clean up runtime settings after saving
		playerSettings[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
	end)

	-- Handle players already in the server before this module loaded
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:FindFirstChild("leaderstats") then
			loadPlayer(player)
		end
	end

	-- Periodic auto-save every AUTO_SAVE_INTERVAL seconds to reduce data loss on crash
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				savePlayer(player)
			end
		end
	end)
end

return GameSystems
