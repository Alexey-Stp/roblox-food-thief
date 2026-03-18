-- FoodSystem_spec.lua
-- Mock tests for FoodSystem.lua: food part creation and the steal interaction.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function loadFoodSystem()
    package.loaded["src.server.modules.FoodSystem"] = nil
    resetWorkspace()
    return require("src.server.modules.FoodSystem")
end

-- Returns a minimal food type matching Config.FOOD_TYPES shape
local function makeFoodType(overrides)
    local ft = {
        name        = "TestFood",
        color       = BrickColor.new("Bright red"),
        size        = Vector3.new(2, 1, 2),
        texture     = "rbxassetid://1234567890",
        sideTexture = nil,
        sellPrice   = 10,
    }
    if overrides then
        for k, v in pairs(overrides) do ft[k] = v end
    end
    return ft
end

-- Build a mock player with a Backpack
local function makePlayer(name)
    local player = {
        Name     = name or "TestPlayer",
        _children = {},
    }
    function player:FindFirstChild(n)
        for _, c in ipairs(self._children) do
            if c.Name == n then return c end
        end
        return nil
    end
    player.Backpack = {
        _children = {},
        Name      = "Backpack",
        ClassName = "Backpack",
    }
    function player.Backpack:GetChildren()
        return self._children
    end
    return player
end

-- Walk workspace children and return the first Part with a matching name
local function findPartInWorkspace(name)
    for _, c in ipairs(workspace._children) do
        if c.Name == name and c.ClassName == "Part" then
            return c
        end
    end
    return nil
end

-- Find a child of an instance by ClassName
local function findChildByClass(inst, cls)
    for _, c in ipairs(inst._children) do
        if c.ClassName == cls then return c end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("FoodSystem", function()

    -- -----------------------------------------------------------------------
    -- spawnAll / createFood — world object structure
    -- -----------------------------------------------------------------------
    describe("food part creation via spawnAll", function()

        it("creates a Part in workspace with the food type's name", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part = findPartInWorkspace("TestFood")
            assert.not_nil(part)
        end)

        it("food Part is anchored", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part = findPartInWorkspace("TestFood")
            assert.is_true(part.Anchored)
        end)

        it("food Part has correct size from the food type", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType({ size = Vector3.new(3, 2, 3) })
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part = findPartInWorkspace("TestFood")
            assert.equals(3, part.Size.X)
            assert.equals(2, part.Size.Y)
            assert.equals(3, part.Size.Z)
        end)

        it("food Part has a ProximityPrompt child", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part   = findPartInWorkspace("TestFood")
            local prompt = findChildByClass(part, "ProximityPrompt")
            assert.not_nil(prompt)
        end)

        it("ProximityPrompt ActionText is 'Take Food'", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part   = findPartInWorkspace("TestFood")
            local prompt = findChildByClass(part, "ProximityPrompt")
            assert.equals("Take Food", prompt.ActionText)
        end)

        it("ProximityPrompt ObjectText matches the food type name", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType({ name = "Sushi" })
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part   = findPartInWorkspace("Sushi")
            local prompt = findChildByClass(part, "ProximityPrompt")
            assert.equals("Sushi", prompt.ObjectText)
        end)

        it("food Part has a SelectionBox child", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part = findPartInWorkspace("TestFood")
            local box  = findChildByClass(part, "SelectionBox")
            assert.not_nil(box)
        end)

        it("spawns a Decal when texture is set", function()
            local FS = loadFoodSystem()
            local ft = makeFoodType({ texture = "rbxassetid://999" })
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part  = findPartInWorkspace("TestFood")
            local decal = findChildByClass(part, "Decal")
            assert.not_nil(decal)
            assert.equals("rbxassetid://999", decal.Texture)
        end)

        it("spawns multiple food items from multiple entries", function()
            local FS = loadFoodSystem()
            local ft1 = makeFoodType({ name = "Alpha" })
            local ft2 = makeFoodType({ name = "Beta" })
            FS.spawnAll({
                { { foodType = ft1, position = Vector3.new(0, 5, 0) } },
                { { foodType = ft2, position = Vector3.new(10, 5, 0) } },
            })

            assert.not_nil(findPartInWorkspace("Alpha"))
            assert.not_nil(findPartInWorkspace("Beta"))
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Steal interaction (ProximityPrompt.Triggered)
    -- -----------------------------------------------------------------------
    describe("steal interaction", function()

        -- Track calls to mock dependencies
        local mockGameSystems
        local mockRemoteEvents
        local foodStolenFiredWith

        before_each(function()
            foodStolenFiredWith = nil
            mockGameSystems = {
                _stolenCalls = 0,
                onFoodStolen = function(self_or_player)
                    -- Support both GS:onFoodStolen(p) and GS.onFoodStolen(p)
                    mockGameSystems._stolenCalls = mockGameSystems._stolenCalls + 1
                end,
            }
            mockRemoteEvents = {
                FoodStolen = {
                    FireClient = function(_self, player, pos)
                        foodStolenFiredWith = { player = player, pos = pos }
                    end,
                },
            }
        end)

        local function setupAndTrigger(player)
            local FS = loadFoodSystem()
            FS.init(mockRemoteEvents, mockGameSystems)
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part   = findPartInWorkspace("TestFood")
            local prompt = findChildByClass(part, "ProximityPrompt")

            -- Fire the Triggered signal directly (synchronous in tests)
            prompt.Triggered._fire(prompt.Triggered, player)
            return part, prompt
        end

        it("adds a Tool to the player's Backpack on trigger", function()
            local player = makePlayer()
            setupAndTrigger(player)

            local toolFound = false
            for _, c in ipairs(player.Backpack._children) do
                if c.ClassName == "Tool" and c.Name == "TestFood" then
                    toolFound = true
                end
            end
            assert.is_true(toolFound, "Expected a Tool named TestFood in the player's Backpack")
        end)

        it("Tool in Backpack has a Handle child", function()
            local player = makePlayer()
            setupAndTrigger(player)

            local tool = nil
            for _, c in ipairs(player.Backpack._children) do
                if c.ClassName == "Tool" then tool = c end
            end
            assert.not_nil(tool)
            local handle = findChildByClass(tool, "Part")
            assert.not_nil(handle, "Tool should have a Part child named Handle")
            assert.equals("Handle", handle.Name)
        end)

        it("calls GameSystems.onFoodStolen once", function()
            local player = makePlayer()
            setupAndTrigger(player)
            assert.equals(1, mockGameSystems._stolenCalls)
        end)

        it("fires RemoteEvents.FoodStolen:FireClient with the player", function()
            local player = makePlayer()
            setupAndTrigger(player)
            assert.not_nil(foodStolenFiredWith)
            assert.equals(player, foodStolenFiredWith.player)
        end)

        it("removes the food Part from workspace after stealing", function()
            local player = makePlayer()
            local part = setupAndTrigger(player)
            -- Part should be destroyed (Parent = nil after Destroy)
            assert.is_nil(part.Parent)
        end)

        it("does not error when init was not called (no RemoteEvents/GameSystems)", function()
            local FS = loadFoodSystem()
            -- No FS.init() call — RemoteEvents and GameSystems are nil
            local ft = makeFoodType()
            FS.spawnAll({ { { foodType = ft, position = Vector3.new(0, 5, 0) } } })

            local part   = findPartInWorkspace("TestFood")
            local prompt = findChildByClass(part, "ProximityPrompt")
            local player = makePlayer()

            assert.has_no.errors(function()
                prompt.Triggered._fire(prompt.Triggered, player)
            end)
        end)
    end)

end)
