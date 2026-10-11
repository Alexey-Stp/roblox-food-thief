-- BaseBuilder_spec.lua
-- Tests for the safe-base economy: sell stand (food only), shop caps,
-- and per-player Food Multiplier jobs.

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

local function makeGameSystems(Config)
	local gs = { money = {}, collected = 0, settings = {} }
	function gs.addMoney(player, amount)
		gs.money[player] = (gs.money[player] or 0) + amount
	end
	function gs.trySpend(player, amount)
		if (gs.money[player] or 0) < amount then
			return false
		end
		gs.money[player] = gs.money[player] - amount
		return true
	end
	function gs.onFoodCollected(_player, count)
		gs.collected = gs.collected + count
	end
	function gs.getSettings(player)
		local s = gs.settings[player] or { walk = Config.DEFAULT_WALK_SPEED, jump = Config.DEFAULT_JUMP_POWER }
		gs.settings[player] = s
		return s.walk, s.jump
	end
	function gs.updateSettings(player, walk, jump)
		gs.settings[player] = { walk = walk, jump = jump }
	end
	function gs.applySettings(_player) end
	return gs
end

local function makeRemoteEvents()
	local re = { notes = {} }
	re.Notify = {
		FireClient = function(_self, _player, text)
			table.insert(re.notes, text)
		end,
	}
	return re
end

local nextUserId = 100
local function makePlayer()
	nextUserId = nextUserId + 1
	local player = Instance.new("Player")
	player.UserId = nextUserId
	player.Backpack = Instance.new("Backpack")
	return player
end

local function findPrompt(partName)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == partName then
			return d:FindFirstChildOfClass("ProximityPrompt")
		end
	end
	return nil
end

local function fire(prompt, player)
	prompt.Triggered._fire(prompt.Triggered, player)
end

local function setup()
	resetServices()
	resetWorkspace()
	local Config = loadConfig()
	package.loaded["src.server.modules.BaseBuilder"] = nil
	local BaseBuilder = require("src.server.modules.BaseBuilder")
	local gs, re = makeGameSystems(Config), makeRemoteEvents()
	BaseBuilder.init(gs, Config, re)
	BaseBuilder.build()
	return Config, gs, re
end

describe("BaseBuilder", function()
	before_each(function()
		fakeTime = 1000
		os.clock = function()
			return fakeTime
		end
	end)

	after_each(function()
		os.clock = realClock
	end)

	describe("sell stand", function()
		it("sells food at CurrentSellPrice and keeps the bat", function()
			local Config, gs = setup()
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1], { currentPrice = 40 }).Parent = player.Backpack
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[2]).Parent = player.Backpack
			local bat = Instance.new("Tool")
			bat.Name = "Bat"
			bat.Parent = player.Backpack

			fire(findPrompt("SellStand"), player)

			assert.equals(40 + Config.FOOD_TYPES[2].sellPrice, gs.money[player])
			assert.equals(1, #player.Backpack._children)
			assert.equals("Bat", player.Backpack._children[1].Name)
		end)

		it("pays nothing and destroys nothing when the player has no food", function()
			local _, gs = setup()
			local player = makePlayer()
			local rifle = Instance.new("Tool")
			rifle.Name = "Rifle"
			rifle.Parent = player.Backpack

			fire(findPrompt("SellStand"), player)
			assert.is_nil(gs.money[player])
			assert.equals(1, #player.Backpack._children)
		end)
	end)

	describe("shop", function()
		it("does not charge when speed is already at the cap", function()
			local Config, gs = setup()
			local player = makePlayer()
			gs.settings[player] = { walk = Config.MAX_WALK_SPEED, jump = Config.DEFAULT_JUMP_POWER }
			gs.money[player] = 10000

			fire(findPrompt("SpeedSign"), player)
			assert.equals(10000, gs.money[player])
		end)

		it("raises speed from cached settings, clamped to MAX_WALK_SPEED", function()
			local Config, gs = setup()
			local player = makePlayer()
			gs.settings[player] = { walk = Config.MAX_WALK_SPEED - 1, jump = Config.DEFAULT_JUMP_POWER }
			gs.money[player] = Config.SHOP_SPEED_COST

			fire(findPrompt("SpeedSign"), player)
			assert.equals(Config.MAX_WALK_SPEED, gs.settings[player].walk)
			assert.equals(0, gs.money[player])
		end)
	end)

	describe("food multiplier", function()
		it("only the inserting player can collect the output", function()
			local Config, gs = setup()
			local ToolUtil = loadToolUtil()
			local alice, bob = makePlayer(), makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = alice.Backpack
			local prompt = findPrompt("CraftMachine")

			fire(prompt, alice)
			assert.equals(0, #alice.Backpack._children)

			fakeTime = fakeTime + Config.MULTIPLIER_TIME + 1
			fire(prompt, bob) -- bob has no job and no food
			assert.equals(0, #bob.Backpack._children)

			fire(prompt, alice)
			assert.equals(Config.MULTIPLIER_FACTOR, #alice.Backpack._children)
			assert.equals(Config.MULTIPLIER_FACTOR, gs.collected)
		end)

		it("output is tagged Multiplied and cannot be inserted again", function()
			local Config = setup()
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = player.Backpack
			local prompt = findPrompt("CraftMachine")

			fire(prompt, player)
			fakeTime = fakeTime + Config.MULTIPLIER_TIME + 1
			fire(prompt, player)

			local outputs = #player.Backpack._children
			for _, tool in ipairs(player.Backpack._children) do
				assert.is_true(tool:FindFirstChild("Handle"):GetAttribute("Multiplied"))
			end

			fire(prompt, player) -- tries to insert multiplied food
			assert.equals(outputs, #player.Backpack._children)
		end)

		it("does not accept weapons", function()
			local _ = setup()
			local player = makePlayer()
			local pistol = Instance.new("Tool")
			pistol.Name = "Pistol"
			pistol.Parent = player.Backpack

			fire(findPrompt("CraftMachine"), player)
			assert.equals(1, #player.Backpack._children)
		end)
	end)
end)
