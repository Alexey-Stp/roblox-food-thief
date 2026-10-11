-- RefrigeratorSystem.lua
-- Per-player fridge levels (1 → FRIDGE_MAX_LEVEL), persisted by GameSystems.
-- Every fridge Part built by BaseBuilder (tagged "Fridge") gets two
-- server-side ProximityPrompts:
--   [E]          Store Food     — boosts every carried food item to the
--                                 player's current fridge level
--   [R] (hold)   Upgrade Fridge — spends Money to raise the player's level
--
-- Storing rules (anti-farm):
--   • An item's price is recomputed from its BaseSellPrice, never compounded:
--       finalPrice = floor(basePrice * (1 + FRIDGE_BONUS_PER_LEVEL * level))
--   • An item is only processed when its StoredAtLevel is below the player's
--     level, so re-storing the same item does nothing.
--   • The store Score bonus is paid once per item (first time it is stored).
--
-- The player's level is published as the Player attribute "FridgeLevel";
-- FridgeClient.client.lua uses it to show per-player prompt text.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ToolUtil = require(script.Parent.ToolUtil)

local RefrigeratorSystem = {}

local Config = nil
local GameSystems = nil
local RemoteEvents = nil

local FRIDGE_TAG = "Fridge"
local INTERACT_DEBOUNCE = 0.3

local lastInteract = {} -- [UserId] = os.clock()

-- -------------------------------------------------------------------------
-- Pure math helpers
-- -------------------------------------------------------------------------
function RefrigeratorSystem.upgradeCost(level)
	return math.floor(Config.FRIDGE_UPGRADE_BASE_COST * level ^ 1.5)
end

function RefrigeratorSystem.applyBonus(basePrice, level)
	return math.floor(basePrice * (1 + Config.FRIDGE_BONUS_PER_LEVEL * level))
end

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
local function notify(player, text)
	RemoteEvents.Notify:FireClient(player, text)
end

local function passesDebounce(player)
	local now = os.clock()
	local last = lastInteract[player.UserId]
	if last and now - last < INTERACT_DEBOUNCE then
		return false
	end
	lastInteract[player.UserId] = now
	return true
end

-- -------------------------------------------------------------------------
-- Actions
-- -------------------------------------------------------------------------
local function storeFood(player)
	if not passesDebounce(player) then
		return
	end

	local level = GameSystems.getFridgeLevel(player)
	local count, totalBase, totalFinal, newItems = 0, 0, 0, 0

	for _, tool in ipairs(ToolUtil.getFoodTools(player)) do
		local handle = tool:FindFirstChild("Handle")
		local storedAt = handle:GetAttribute("StoredAtLevel") or 0
		if storedAt < level then
			local basePrice = handle:GetAttribute("BaseSellPrice")
			if not basePrice then
				local ft = ToolUtil.findFoodType(Config.FOOD_TYPES, tool.Name)
				basePrice = ft and ft.sellPrice or 0
			end
			local finalPrice = RefrigeratorSystem.applyBonus(basePrice, level)

			handle:SetAttribute("CurrentSellPrice", finalPrice)
			handle:SetAttribute("StoredAtLevel", level)

			if storedAt == 0 then
				newItems = newItems + 1
				GameSystems.onFoodStored(player)
			end
			count = count + 1
			totalBase = totalBase + basePrice
			totalFinal = totalFinal + finalPrice
		end
	end

	if count == 0 then
		notify(player, "No food to store — everything is already chilled at Lv " .. level)
		return
	end

	local label = count == 1 and "1 item" or (count .. " items")
	RemoteEvents.FridgeStoredFeedback:FireClient(player, label, totalBase, totalFinal - totalBase, totalFinal)
	if newItems > 0 then
		notify(player, "+" .. (newItems * (Config.SCORE_STORE or 25)) .. " Score")
	end
end

local function upgradeFridge(player)
	if not passesDebounce(player) then
		return
	end

	local level = GameSystems.getFridgeLevel(player)
	if level >= Config.FRIDGE_MAX_LEVEL then
		notify(player, "Your fridge is already at MAX level")
		return
	end

	local cost = RefrigeratorSystem.upgradeCost(level)
	if not GameSystems.trySpend(player, cost) then
		notify(player, "Need $" .. cost .. " to upgrade your fridge")
		return
	end

	GameSystems.setFridgeLevel(player, level + 1)
	notify(player, "Fridge upgraded to Lv " .. (level + 1) .. "!")
end

-- -------------------------------------------------------------------------
-- Fridge decoration
-- -------------------------------------------------------------------------
local function makePrompt(parent, name, actionText, keyCode, holdDuration)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = actionText
	pp.ObjectText = "Your Fridge"
	pp.KeyboardKeyCode = keyCode
	pp.HoldDuration = holdDuration
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 10
	pp.Parent = parent
	return pp
end

local function buildBillboard(fridgePart)
	local bb = Instance.new("BillboardGui")
	bb.Name = "FridgeBB"
	bb.Size = UDim2.new(0, 220, 0, 50)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.MaxDistance = 40
	bb.Parent = fridgePart

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Info"
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 220, 0)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.SourceSansBold
	-- Overwritten per player by FridgeClient
	lbl.Text = "Fridge — [E] store food · hold [R] upgrade"
	lbl.Parent = bb
end

local function setupFridge(fridgePart)
	if fridgePart:GetAttribute("FridgeReady") then
		return
	end
	fridgePart:SetAttribute("FridgeReady", true)

	buildBillboard(fridgePart)

	makePrompt(fridgePart, "StorePrompt", "Store Food", Enum.KeyCode.E, 0).Triggered:Connect(storeFood)
	makePrompt(fridgePart, "UpgradePrompt", "Upgrade Fridge", Enum.KeyCode.R, 0.5).Triggered:Connect(upgradeFridge)
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

-- Publishes display values for FridgeClient (Config is not replicated to clients)
local function publishDisplayAttributes(player)
	local level = player:GetAttribute("FridgeLevel") or 1
	player:SetAttribute("FridgeMaxLevel", Config.FRIDGE_MAX_LEVEL)
	player:SetAttribute("FridgeBonusPct", math.floor(Config.FRIDGE_BONUS_PER_LEVEL * level * 100 + 0.5))
	player:SetAttribute(
		"FridgeNextCost",
		level < Config.FRIDGE_MAX_LEVEL and RefrigeratorSystem.upgradeCost(level) or nil
	)
end

local function watchPlayer(player)
	publishDisplayAttributes(player)
	player:GetAttributeChangedSignal("FridgeLevel"):Connect(function()
		publishDisplayAttributes(player)
	end)
end

function RefrigeratorSystem.init(remoteEvents, config, gameSystems)
	RemoteEvents = remoteEvents
	Config = config
	GameSystems = gameSystems

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastInteract[player.UserId] = nil
	end)
end

-- Call after BaseBuilder.build(). Also picks up fridges tagged later.
function RefrigeratorSystem.registerFridges()
	for _, fridgePart in ipairs(CollectionService:GetTagged(FRIDGE_TAG)) do
		setupFridge(fridgePart)
	end
	CollectionService:GetInstanceAddedSignal(FRIDGE_TAG):Connect(setupFridge)
end

return RefrigeratorSystem
