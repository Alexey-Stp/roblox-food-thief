-- GameSystems.lua
-- Manages per-player leaderboard stats and DataStore persistence.
-- Saves: Score, Food Stolen, Money, and backpack inventory (food tool names).

local Players         = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local GameSystems = {}

-- Config injected via init() — needed for FOOD_TYPES lookup during inventory restore
local Config = nil

-- DataStore versioned key (bumped to v2 for Money + inventory schema)
local DATA_STORE_KEY = "PlayerData_v2"
local playerStore    = nil

local ok, store = pcall(function()
	return DataStoreService:GetDataStore(DATA_STORE_KEY)
end)
if ok then
	playerStore = store
else
	warn("[GameSystems] DataStore unavailable — progress will not persist: " .. tostring(store))
end

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

	local data = {
		foodStolen = (ls:FindFirstChild("Food Stolen") or {}).Value or 0,
		score      = (ls:FindFirstChild("Score")       or {}).Value or 0,
		money      = (ls:FindFirstChild("Money")       or {}).Value or 0,
		inventory  = invNames,
	}

	local success, err = pcall(function()
		playerStore:SetAsync(tostring(player.UserId), data)
	end)
	if not success then
		warn("[GameSystems] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
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

	if not playerStore then return end

	local success, data = pcall(function()
		return playerStore:GetAsync(tostring(player.UserId))
	end)

	if success and type(data) == "table" then
		foodStolen.Value = data.foodStolen or 0
		score.Value      = data.score      or 0
		money.Value      = data.money      or 0

		-- Restore inventory tools after the character has spawned
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

-- -------------------------------------------------------------------------
-- Lifecycle
-- -------------------------------------------------------------------------

function GameSystems.init(config)
	Config = config

	Players.PlayerAdded:Connect(loadPlayer)

	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
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
end

return GameSystems
