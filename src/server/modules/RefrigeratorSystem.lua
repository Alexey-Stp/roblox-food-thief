-- RefrigeratorSystem.lua
-- Manages the refrigerator level-up system at the Safe Base.
-- Each fridge Part (built by BaseBuilder) can be upgraded 1→10 with Money.
-- Storing food in a fridge boosts its CurrentSellPrice attribute:
--   finalPrice = floor(basePrice * (1 + 0.3 * fridgeLevel))
-- A BillboardGui above each fridge shows the current level, bonus %, and upgrade cost.
-- The FridgeStoredFeedback RemoteEvent sends a price breakdown to the client.

local Players = game:GetService("Players")

local RefrigeratorSystem = {}

local Config = nil
local GameSystems = nil
local RemoteEvents = nil

-- Registry: fridgeId (integer) → state table
-- state = { part, level, nextCost, billLevel, billBonus, billCost }
local fridges = {}

-- Per-player, per-fridge interaction debounce (0.3 s)
local debounce = {} -- [userId_fridgeId] = tick()

-- -------------------------------------------------------------------------
-- Pure math helpers
-- -------------------------------------------------------------------------
local function upgradeCost(level)
	return math.floor(100 * level ^ 1.5)
end

local function applyBonus(basePrice, level)
	return math.floor(basePrice * (1 + 0.3 * level))
end

local function bonusPct(level)
	return math.floor(0.3 * level * 100) -- e.g. level 3 → 90
end

-- -------------------------------------------------------------------------
-- BillboardGui construction
-- -------------------------------------------------------------------------
local function buildBillboard(fridgePart, fridgeId)
	local bb = Instance.new("BillboardGui")
	bb.Name = "FridgeBB_" .. fridgeId
	bb.Size = UDim2.new(0, 220, 0, 90)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 40
	bb.Parent = fridgePart

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.Parent = bb

	local function makeLabel(color)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 24)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = color
		lbl.TextScaled = true
		lbl.Font = Enum.Font.SourceSansBold
		lbl.Parent = bb
		return lbl
	end

	local lvlLabel = makeLabel(Color3.fromRGB(255, 220, 0)) -- yellow
	local bonusLabel = makeLabel(Color3.fromRGB(80, 255, 80)) -- green
	local costLabel = makeLabel(Color3.fromRGB(255, 255, 255)) -- white

	return lvlLabel, bonusLabel, costLabel
end

local function refreshBillboard(fridgeId)
	local f = fridges[fridgeId]
	if not f then
		return
	end

	f.billLevel.Text = "Level " .. f.level .. " / " .. Config.FRIDGE_MAX_LEVEL
	f.billBonus.Text = "+" .. bonusPct(f.level) .. "% Price Bonus"

	if f.level >= Config.FRIDGE_MAX_LEVEL then
		f.billCost.Text = "MAX LEVEL"
	else
		f.billCost.Text = "Upgrade: $" .. f.nextCost
	end
end

-- -------------------------------------------------------------------------
-- Locate fridge Parts built by BaseBuilder and initialise registry
-- -------------------------------------------------------------------------
local function registerFridges()
	-- BaseBuilder parents fridge Parts to workspace (inside a Model or directly).
	-- We find them by the FridgeId attribute set in buildFridge().
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Part") and obj:GetAttribute("FridgeId") then
			local id = obj:GetAttribute("FridgeId")
			local level = obj:GetAttribute("FridgeLevel") or 1
			local cost = upgradeCost(level)

			local lvlL, bonusL, costL = buildBillboard(obj, id)

			fridges[id] = {
				part = obj,
				level = level,
				nextCost = cost,
				billLevel = lvlL,
				billBonus = bonusL,
				billCost = costL,
			}

			refreshBillboard(id)
		end
	end
end

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function getDebounceKey(userId, fridgeId)
	return tostring(userId) .. "_" .. tostring(fridgeId)
end

local function checkDebounce(userId, fridgeId)
	local key = getDebounceKey(userId, fridgeId)
	local now = tick()
	if now - (debounce[key] or 0) < 0.3 then
		return false
	end
	debounce[key] = now
	return true
end

local function isProtectedTool(item)
	if not item or not item:IsA("Tool") then
		return true
	end
	local h = item:FindFirstChild("Handle")
	return h and (h:GetAttribute("IsBat") == true or h:GetAttribute("IsCarpet") == true)
end

local function findFoodTool(player)
	local char = player.Character
	if char then
		local eq = char:FindFirstChildOfClass("Tool")
		if eq and not isProtectedTool(eq) then
			return eq
		end
	end
	for _, item in ipairs(player.Backpack:GetChildren()) do
		if not isProtectedTool(item) then
			return item
		end
	end
	return nil
end

local function getMoney(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money")
end

-- -------------------------------------------------------------------------
-- Remote handlers
-- -------------------------------------------------------------------------
local function onUpgradeFridge(player, fridgeId)
	if type(fridgeId) ~= "number" then
		return
	end
	local f = fridges[fridgeId]
	if not f then
		return
	end
	if not checkDebounce(player.UserId, fridgeId) then
		return
	end

	-- Proximity check
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if (hrp.Position - f.part.Position).Magnitude > 12 then
		return
	end

	-- Level cap
	if f.level >= Config.FRIDGE_MAX_LEVEL then
		return
	end

	-- Money check and deduction
	local moneyVal = getMoney(player)
	if not moneyVal or moneyVal.Value < f.nextCost then
		return
	end
	moneyVal.Value = moneyVal.Value - f.nextCost

	-- Level up
	f.level = f.level + 1
	f.nextCost = upgradeCost(f.level)

	-- Persist on Part so restarts can read it
	f.part:SetAttribute("FridgeLevel", f.level)
	f.part:SetAttribute("NextUpgradeCost", f.nextCost)

	refreshBillboard(fridgeId)
end

local function onStoreFoodInFridge(player, fridgeId)
	if type(fridgeId) ~= "number" then
		return
	end
	local f = fridges[fridgeId]
	if not f then
		return
	end
	if not checkDebounce(player.UserId, fridgeId) then
		return
	end

	-- Proximity check
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if (hrp.Position - f.part.Position).Magnitude > 12 then
		return
	end

	-- Find food tool
	local tool = findFoodTool(player)
	if not tool then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end

	-- Look up base price from handle attribute; fall back to Config
	local basePrice = handle:GetAttribute("BaseSellPrice") or 0
	if basePrice == 0 then
		for _, ft in ipairs(Config.FOOD_TYPES) do
			if ft.name == tool.Name then
				basePrice = ft.sellPrice or 0
				break
			end
		end
	end

	local finalPrice = applyBonus(basePrice, f.level)
	local bonusAmt = finalPrice - basePrice

	-- Update the tool's CurrentSellPrice attribute (tool stays in backpack)
	handle:SetAttribute("CurrentSellPrice", finalPrice)

	-- Score reward
	if GameSystems then
		GameSystems.onFoodStored(player)
	end

	-- Send price breakdown to client for popup
	RemoteEvents.FridgeStoredFeedback:FireClient(player, tool.Name, basePrice, bonusAmt, finalPrice)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function RefrigeratorSystem.init(remoteEvents, config, gameSystems)
	RemoteEvents = remoteEvents
	Config = config
	GameSystems = gameSystems

	-- Wait one frame for BaseBuilder to finish parenting fridge Parts
	task.defer(registerFridges)

	remoteEvents.UpgradeFridge.OnServerEvent:Connect(onUpgradeFridge)
	remoteEvents.StoreFoodInFridge.OnServerEvent:Connect(onStoreFoodInFridge)
end

return RefrigeratorSystem
