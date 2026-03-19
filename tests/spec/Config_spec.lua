-- Config_spec.lua
-- Pure unit tests for Config.lua.
-- RobloxMock.lua (loaded as busted helper) provides Vector3 and BrickColor
-- so Config can be required without Roblox Studio.

local Config = require("src.server.modules.Config")

describe("Config", function()

    -- -----------------------------------------------------------------------
    -- World constants
    -- -----------------------------------------------------------------------
    describe("world constants", function()
        it("FLOOR_HEIGHT is 25", function()
            assert.equals(25, Config.FLOOR_HEIGHT)
        end)

        it("FLOOR_COUNT is 3", function()
            assert.equals(3, Config.FLOOR_COUNT)
        end)

        it("HOTEL_SIZE Y equals FLOOR_HEIGHT * FLOOR_COUNT", function()
            assert.equals(Config.FLOOR_HEIGHT * Config.FLOOR_COUNT, Config.HOTEL_SIZE.Y)
        end)

        it("WALL_THICKNESS is positive", function()
            assert.is_true(Config.WALL_THICKNESS > 0)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Enemy behaviour
    -- -----------------------------------------------------------------------
    describe("enemy behaviour", function()
        it("DETECTION_RANGE is 80", function()
            assert.equals(80, Config.DETECTION_RANGE)
        end)

        it("HIT_DAMAGE is 15", function()
            assert.equals(15, Config.HIT_DAMAGE)
        end)

        it("HIT_DEBOUNCE is positive", function()
            assert.is_true(Config.HIT_DEBOUNCE > 0)
        end)

        it("CREATURES_PER_LEVEL is 3", function()
            assert.equals(3, Config.CREATURES_PER_LEVEL)
        end)

        it("each LEVEL_SPEEDS entry has chase > wander", function()
            for i, speeds in ipairs(Config.LEVEL_SPEEDS) do
                assert.is_true(
                    speeds.chase > speeds.wander,
                    ("LEVEL_SPEEDS[%d]: chase (%d) must be > wander (%d)"):format(
                        i, speeds.chase, speeds.wander
                    )
                )
            end
        end)

        it("LEVEL_SPEEDS has exactly 3 entries (one per floor)", function()
            assert.equals(3, #Config.LEVEL_SPEEDS)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Food mechanics
    -- -----------------------------------------------------------------------
    describe("food mechanics", function()
        it("FOOD_RESPAWN_TIME is positive", function()
            assert.is_true(Config.FOOD_RESPAWN_TIME > 0)
        end)

        it("MULTIPLIER_TIME is 60", function()
            assert.equals(60, Config.MULTIPLIER_TIME)
        end)

        it("MULTIPLIER_FACTOR is 2", function()
            assert.equals(2, Config.MULTIPLIER_FACTOR)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Score values
    -- -----------------------------------------------------------------------
    describe("score values", function()
        it("SCORE_STEAL is 10", function()
            assert.equals(10, Config.SCORE_STEAL)
        end)

        it("SCORE_STORE is 25", function()
            assert.equals(25, Config.SCORE_STORE)
        end)

        it("SCORE_COLLECT is 50", function()
            assert.equals(50, Config.SCORE_COLLECT)
        end)

        it("all score values are positive", function()
            assert.is_true(Config.SCORE_STEAL   > 0)
            assert.is_true(Config.SCORE_STORE   > 0)
            assert.is_true(Config.SCORE_COLLECT > 0)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Fridge / shop
    -- -----------------------------------------------------------------------
    describe("fridge and shop", function()
        it("FRIDGE_UPGRADE_BASE_COST is positive", function()
            assert.is_true(Config.FRIDGE_UPGRADE_BASE_COST > 0)
        end)

        it("FRIDGE_COUNT is positive", function()
            assert.is_true(Config.FRIDGE_COUNT > 0)
        end)

        it("FRIDGE_CAPACITY is positive", function()
            assert.is_true(Config.FRIDGE_CAPACITY > 0)
        end)

        it("SHOP_SPEED_COST is positive", function()
            assert.is_true(Config.SHOP_SPEED_COST > 0)
        end)

        it("SHOP_JUMP_COST is positive", function()
            assert.is_true(Config.SHOP_JUMP_COST > 0)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- FOOD_TYPES
    -- -----------------------------------------------------------------------
    describe("FOOD_TYPES", function()
        it("has exactly 7 entries", function()
            assert.equals(7, #Config.FOOD_TYPES)
        end)

        it("every entry has a non-empty name", function()
            for i, ft in ipairs(Config.FOOD_TYPES) do
                assert.is_string(ft.name, ("FOOD_TYPES[%d].name should be a string"):format(i))
                assert.is_true(#ft.name > 0, ("FOOD_TYPES[%d].name must not be empty"):format(i))
            end
        end)

        it("every entry has a color (BrickColor)", function()
            for i, ft in ipairs(Config.FOOD_TYPES) do
                assert.not_nil(ft.color, ("FOOD_TYPES[%d].color must not be nil"):format(i))
            end
        end)

        it("every entry has a size (Vector3)", function()
            for i, ft in ipairs(Config.FOOD_TYPES) do
                assert.not_nil(ft.size, ("FOOD_TYPES[%d].size must not be nil"):format(i))
                assert.is_true(
                    ft.size.X > 0 and ft.size.Y > 0 and ft.size.Z > 0,
                    ("FOOD_TYPES[%d].size components must be positive"):format(i)
                )
            end
        end)

        it("every entry has a non-empty texture string", function()
            for i, ft in ipairs(Config.FOOD_TYPES) do
                assert.is_string(ft.texture, ("FOOD_TYPES[%d].texture should be a string"):format(i))
                assert.is_true(#ft.texture > 0, ("FOOD_TYPES[%d].texture must not be empty"):format(i))
            end
        end)

        it("every entry has a positive sellPrice", function()
            for i, ft in ipairs(Config.FOOD_TYPES) do
                assert.is_number(ft.sellPrice, ("FOOD_TYPES[%d].sellPrice should be a number"):format(i))
                assert.is_true(
                    ft.sellPrice > 0,
                    ("FOOD_TYPES[%d].sellPrice must be positive"):format(i)
                )
            end
        end)

        it("all food names are unique", function()
            local seen = {}
            for _, ft in ipairs(Config.FOOD_TYPES) do
                assert.is_nil(seen[ft.name], "Duplicate food name: " .. ft.name)
                seen[ft.name] = true
            end
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Door / lift debounce
    -- -----------------------------------------------------------------------
    describe("debounce times", function()
        it("DOOR_DEBOUNCE is positive", function()
            assert.is_true(Config.DOOR_DEBOUNCE > 0)
        end)

        it("LIFT_DEBOUNCE is positive", function()
            assert.is_true(Config.LIFT_DEBOUNCE > 0)
        end)

        it("LIFT_DEBOUNCE is longer than DOOR_DEBOUNCE", function()
            assert.is_true(Config.LIFT_DEBOUNCE > Config.DOOR_DEBOUNCE)
        end)
    end)

end)
