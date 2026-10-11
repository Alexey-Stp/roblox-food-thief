-- ToolUtil_spec.lua
-- Tests for ToolUtil.lua: positive food tagging, food-tool construction,
-- and confiscation that spares bats / carpets / weapons.

local function loadConfig()
	package.loaded["src.server.modules.Config"] = nil
	return require("src.server.modules.Config")
end

local function loadToolUtil()
	package.loaded["src.server.modules.ToolUtil"] = nil
	return require("src.server.modules.ToolUtil")
end

-- Tool with a Handle carrying one attribute (IsBat, IsCarpet, IsWeapon, …)
local function makeTaggedTool(name, attribute)
	local tool = Instance.new("Tool")
	tool.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	if attribute then
		handle:SetAttribute(attribute, true)
	end
	handle.Parent = tool
	return tool
end

local function makePlayer()
	local player = Instance.new("Player")
	player.UserId = 1
	player.Backpack = Instance.new("Backpack")
	player.Character = Instance.new("Model")
	return player
end

describe("ToolUtil", function()
	describe("makeFoodTool", function()
		it("tags the handle with IsFood and all price metadata", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			local ft = Config.FOOD_TYPES[1]

			local tool = ToolUtil.makeFoodTool(ft)
			local handle = tool:FindFirstChild("Handle")

			assert.equals(ft.name, tool.Name)
			assert.is_true(handle:GetAttribute("IsFood"))
			assert.equals(ft.name, handle:GetAttribute("FoodId"))
			assert.equals(ft.sellPrice, handle:GetAttribute("BaseSellPrice"))
			assert.equals(ft.sellPrice, handle:GetAttribute("CurrentSellPrice"))
			assert.equals(0, handle:GetAttribute("StoredAtLevel"))
			assert.is_false(handle:GetAttribute("Multiplied"))
		end)

		it("applies overrides for price, stored level and multiplied flag", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			local tool = ToolUtil.makeFoodTool(Config.FOOD_TYPES[1], {
				currentPrice = 99,
				storedAtLevel = 4,
				multiplied = true,
			})
			local handle = tool:FindFirstChild("Handle")
			assert.equals(99, handle:GetAttribute("CurrentSellPrice"))
			assert.equals(4, handle:GetAttribute("StoredAtLevel"))
			assert.is_true(handle:GetAttribute("Multiplied"))
		end)

		it("round-trips through readFoodData", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			local tool = ToolUtil.makeFoodTool(Config.FOOD_TYPES[2], { currentPrice = 33, storedAtLevel = 2 })
			local data = ToolUtil.readFoodData(tool)
			assert.equals(Config.FOOD_TYPES[2].name, data.id)
			assert.equals(33, data.price)
			assert.equals(2, data.stored)
			assert.is_false(data.multiplied)
		end)
	end)

	describe("isFood", function()
		it("is true only for IsFood-tagged tools", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			assert.is_true(ToolUtil.isFood(ToolUtil.makeFoodTool(Config.FOOD_TYPES[1])))
			assert.is_false(ToolUtil.isFood(makeTaggedTool("Pizza", nil)))
			assert.is_false(ToolUtil.isFood(makeTaggedTool("Bat", "IsBat")))
			assert.is_false(ToolUtil.isFood(makeTaggedTool("Pistol", "IsWeapon")))
			assert.is_false(ToolUtil.isFood(makeTaggedTool("FlyingCarpet", "IsCarpet")))
		end)
	end)

	describe("player inventory helpers", function()
		it("getFoodTools finds food in both the character and the backpack", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = player.Character
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[2]).Parent = player.Backpack
			makeTaggedTool("Bat", "IsBat").Parent = player.Backpack

			assert.equals(2, #ToolUtil.getFoodTools(player))
			assert.equals(2, ToolUtil.countFood(player))
			assert.is_true(ToolUtil.hasFood(player))
		end)

		it("confiscateFood removes food and keeps bat, carpet and weapons", function()
			local Config = loadConfig()
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[1]).Parent = player.Backpack
			ToolUtil.makeFoodTool(Config.FOOD_TYPES[2]).Parent = player.Character
			makeTaggedTool("Bat", "IsBat").Parent = player.Backpack
			makeTaggedTool("FlyingCarpet", "IsCarpet").Parent = player.Backpack
			makeTaggedTool("Rifle", "IsWeapon").Parent = player.Backpack

			assert.equals(2, ToolUtil.confiscateFood(player))
			assert.equals(3, #player.Backpack._children)
			assert.is_false(ToolUtil.hasFood(player))
		end)

		it("hasCarpet detects a carpet in the backpack", function()
			local ToolUtil = loadToolUtil()
			local player = makePlayer()
			assert.is_false(ToolUtil.hasCarpet(player))
			makeTaggedTool("FlyingCarpet", "IsCarpet").Parent = player.Backpack
			assert.is_true(ToolUtil.hasCarpet(player))
		end)
	end)
end)
