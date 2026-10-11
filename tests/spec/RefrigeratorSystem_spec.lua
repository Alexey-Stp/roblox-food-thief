-- RefrigeratorSystem_spec.lua
-- Tests for per-player fridge storing and upgrading, including the
-- anti-farm rules (score once per item, no price compounding).

local realClock = os.clock
local fakeTime = 0

local function loadConfig()
	package.loaded["src.server.modules.Config"] = nil
	return require("src.server.modules.Config")
end

local function loadToolUtil()
	package.loaded["src.server.modules.ToolUtil"] = nil
	return require("src.server.modules.ToolUtil")
end

-- GameSystems stand-in that records calls
local function makeGameSystems(startLevel, money)
	local gs = { level = startLevel or 1, money = money or 0, stored = 0 }
	function gs.getFridgeLevel(_player)
		return gs.level
	end
	function gs.setFridgeLevel(_player, level)
		gs.level = level
	end
	function gs.onFoodStored(_player)
		gs.stored = gs.stored + 1
	end
	function gs.trySpend(_player, amount)
		if gs.money < amount then
			return false
		end
		gs.money = gs.money - amount
		return true
	end
	return gs
end

local function makeRemoteEvents()
	local re = { feedback = nil, notes = {} }
	re.Notify = {
		FireClient = function(_self, _player, text)
			table.insert(re.notes, text)
		end,
	}
	re.FridgeStoredFeedback = {
		FireClient = function(_self, _player, label, base, bonus, final)
			re.feedback = { label = label, base = base, bonus = bonus, final = final }
		end,
	}
	return re
end

local function makePlayer()
	local player = Instance.new("Player")
	player.UserId = 42
	player.Backpack = Instance.new("Backpack")
	return player
end

-- Loads the system, registers one fridge and returns (system, storePrompt, upgradePrompt)
local function setup(gs, re)
	resetServices()
	resetWorkspace()
	local Config = loadConfig()
	package.loaded["src.server.modules.RefrigeratorSystem"] = nil
	local Fridge = require("src.server.modules.RefrigeratorSystem")
	Fridge.init(re, Config, gs)

	local fridgePart = Instance.new("Part")
	fridgePart.Name = "Fridge1"
	fridgePart.Parent = workspace
	game:GetService("CollectionService"):AddTag(fridgePart, "Fridge")
	Fridge.registerFridges()

	return Fridge, fridgePart:FindFirstChild("StorePrompt"), fridgePart:FindFirstChild("UpgradePrompt"), Config
end

-- Fire a prompt after advancing the fake clock past the interaction debounce
local function trigger(prompt, player)
	fakeTime = fakeTime + 1
	prompt.Triggered._fire(prompt.Triggered, player)
end

describe("RefrigeratorSystem", function()
	before_each(function()
		fakeTime = 0
		os.clock = function()
			return fakeTime
		end
	end)

	after_each(function()
		os.clock = realClock
	end)

	it("creates Store and Upgrade prompts on tagged fridges", function()
		local _, storePrompt, upgradePrompt = setup(makeGameSystems(), makeRemoteEvents())
		assert.not_nil(storePrompt)
		assert.not_nil(upgradePrompt)
	end)

	describe("storing food", function()
		it("boosts CurrentSellPrice from the base price and awards score once", function()
			local gs, re = makeGameSystems(3), makeRemoteEvents()
			local _, storePrompt, _, Config = setup(gs, re)
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			local ft = Config.FOOD_TYPES[1]
			local tool = ToolUtil.makeFoodTool(ft)
			tool.Parent = player.Backpack

			trigger(storePrompt, player)

			local expected = math.floor(ft.sellPrice * (1 + Config.FRIDGE_BONUS_PER_LEVEL * 3))
			assert.equals(expected, tool:FindFirstChild("Handle"):GetAttribute("CurrentSellPrice"))
			assert.equals(3, tool:FindFirstChild("Handle"):GetAttribute("StoredAtLevel"))
			assert.equals(1, gs.stored)
			assert.equals(expected, re.feedback.final)
		end)

		it("re-storing at the same level gives no extra score (no farm)", function()
			local gs, re = makeGameSystems(2), makeRemoteEvents()
			local _, storePrompt, _, Config = setup(gs, re)
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = player.Backpack

			for _ = 1, 5 do
				trigger(storePrompt, player)
			end
			assert.equals(1, gs.stored)
		end)

		it("after an upgrade, re-storing raises the price without compounding or new score", function()
			local gs, re = makeGameSystems(1), makeRemoteEvents()
			local _, storePrompt, _, Config = setup(gs, re)
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			local ft = Config.FOOD_TYPES[1]
			local tool = ToolUtil.makeFoodTool(ft)
			tool.Parent = player.Backpack

			trigger(storePrompt, player)
			gs.level = 4
			trigger(storePrompt, player)

			assert.equals(
				math.floor(ft.sellPrice * (1 + Config.FRIDGE_BONUS_PER_LEVEL * 4)),
				tool:FindFirstChild("Handle"):GetAttribute("CurrentSellPrice")
			)
			assert.equals(1, gs.stored)
		end)

		it("ignores bats and weapons", function()
			local gs, re = makeGameSystems(2), makeRemoteEvents()
			local _, storePrompt = setup(gs, re)
			local player = makePlayer()
			local bat = Instance.new("Tool")
			bat.Name = "Bat"
			local handle = Instance.new("Part")
			handle.Name = "Handle"
			handle:SetAttribute("IsBat", true)
			handle.Parent = bat
			bat.Parent = player.Backpack

			trigger(storePrompt, player)
			assert.equals(0, gs.stored)
			assert.is_nil(handle:GetAttribute("CurrentSellPrice"))
		end)

		it("rapid repeat triggers are debounced", function()
			local gs, re = makeGameSystems(1), makeRemoteEvents()
			local _, storePrompt, _, Config = setup(gs, re)
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = player.Backpack

			trigger(storePrompt, player)
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[2]).Parent = player.Backpack
			-- Same instant: second trigger is ignored
			storePrompt.Triggered._fire(storePrompt.Triggered, player)
			assert.equals(1, gs.stored)
		end)
	end)

	describe("upgrading", function()
		it("spends money and raises the player's level", function()
			local gs, re = makeGameSystems(1, 1000), makeRemoteEvents()
			local Fridge, _, upgradePrompt = setup(gs, re)
			local cost = Fridge.upgradeCost(1)

			trigger(upgradePrompt, makePlayer())
			assert.equals(2, gs.level)
			assert.equals(1000 - cost, gs.money)
		end)

		it("does nothing without enough money", function()
			local gs, re = makeGameSystems(1, 0), makeRemoteEvents()
			local _, _, upgradePrompt = setup(gs, re)
			trigger(upgradePrompt, makePlayer())
			assert.equals(1, gs.level)
		end)

		it("does not charge at max level", function()
			local gs, re = makeGameSystems(10, 1000000), makeRemoteEvents()
			local _, _, upgradePrompt, Config = setup(gs, re)
			gs.level = Config.FRIDGE_MAX_LEVEL
			trigger(upgradePrompt, makePlayer())
			assert.equals(Config.FRIDGE_MAX_LEVEL, gs.level)
			assert.equals(1000000, gs.money)
		end)
	end)
end)
