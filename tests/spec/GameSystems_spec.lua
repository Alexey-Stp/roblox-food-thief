-- GameSystems_spec.lua
-- Tests for score/stat logic and DataStore error handling in GameSystems.lua.
-- Each test re-requires the module with a fresh service state to avoid
-- bleed-through from the top-level DataStoreService call at module load.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Build a mock player with a leaderstats folder containing IntValue stats.
local function makePlayer(name)
    local player = {
        Name      = name or "TestPlayer",
        UserId    = 12345,
        Backpack  = { _children = {}, GetChildren = function(self) return self._children end },
        Character = nil,
        _children = {},
    }

    function player:FindFirstChild(n)
        for _, c in ipairs(self._children) do
            if c.Name == n then return c end
        end
        return nil
    end

    -- leaderstats folder
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls._parent = player
    table.insert(player._children, ls)

    local function addStat(statName)
        local v = Instance.new("IntValue")
        v.Name = statName
        v._parent = ls
        table.insert(ls._children, v)
        return v
    end

    addStat("Food Stolen")
    addStat("Score")
    addStat("Money")

    return player
end

-- Re-require GameSystems with a clean service environment.
local function loadGameSystems()
    resetServices()
    package.loaded["src.server.modules.GameSystems"] = nil
    return require("src.server.modules.GameSystems")
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("GameSystems", function()

    -- -----------------------------------------------------------------------
    -- onFoodStolen
    -- -----------------------------------------------------------------------
    describe("onFoodStolen", function()
        it("increments Food Stolen by 1", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStolen(player)
            local fs = player:FindFirstChild("leaderstats"):FindFirstChild("Food Stolen")
            assert.equals(1, fs.Value)
        end)

        it("increments Score by 10", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStolen(player)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(10, score.Value)
        end)

        it("accumulates correctly after multiple calls", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStolen(player)
            GS.onFoodStolen(player)
            GS.onFoodStolen(player)
            local fs    = player:FindFirstChild("leaderstats"):FindFirstChild("Food Stolen")
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(3,  fs.Value)
            assert.equals(30, score.Value)
        end)

        it("is safe when player has no leaderstats (no crash)", function()
            local GS = loadGameSystems()
            local bare = { Name = "Bare", _children = {} }
            function bare:FindFirstChild(_n) return nil end
            assert.has_no.errors(function()
                GS.onFoodStolen(bare)
            end)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- onFoodStored
    -- -----------------------------------------------------------------------
    describe("onFoodStored", function()
        it("increments Score by 25", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStored(player)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(25, score.Value)
        end)

        it("does not change Food Stolen", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStored(player)
            local fs = player:FindFirstChild("leaderstats"):FindFirstChild("Food Stolen")
            assert.equals(0, fs.Value)
        end)

        it("accumulates across calls", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodStored(player)
            GS.onFoodStored(player)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(50, score.Value)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- onFoodCollected
    -- -----------------------------------------------------------------------
    describe("onFoodCollected", function()
        it("increments Score by 50 per item (single item)", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodCollected(player, 1)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(50, score.Value)
        end)

        it("increments Score by 50 * count (multiple items)", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodCollected(player, 4)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(200, score.Value)
        end)

        it("count=0 adds no score", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodCollected(player, 0)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(0, score.Value)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- onFoodSold
    -- -----------------------------------------------------------------------
    describe("onFoodSold", function()
        it("adds the given amount to Money", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodSold(player, 75)
            local money = player:FindFirstChild("leaderstats"):FindFirstChild("Money")
            assert.equals(75, money.Value)
        end)

        it("accumulates across calls", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodSold(player, 20)
            GS.onFoodSold(player, 30)
            local money = player:FindFirstChild("leaderstats"):FindFirstChild("Money")
            assert.equals(50, money.Value)
        end)

        it("does not affect Score", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.onFoodSold(player, 100)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(0, score.Value)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Mixed stat interactions
    -- -----------------------------------------------------------------------
    describe("mixed stat accumulation", function()
        it("all stat functions accumulate independently", function()
            local GS = loadGameSystems()
            local player = makePlayer()

            GS.onFoodStolen(player)      -- +1 FS, +10 Score
            GS.onFoodStored(player)      -- +25 Score
            GS.onFoodCollected(player, 2) -- +100 Score
            GS.onFoodSold(player, 50)    -- +50 Money

            local ls    = player:FindFirstChild("leaderstats")
            assert.equals(1,   ls:FindFirstChild("Food Stolen").Value)
            assert.equals(135, ls:FindFirstChild("Score").Value)
            assert.equals(50,  ls:FindFirstChild("Money").Value)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- DataStore resilience
    -- -----------------------------------------------------------------------
    describe("DataStore resilience", function()
        it("loads without crash when DataStoreService.GetDataStore raises an error", function()
            -- Inject a broken DataStoreService BEFORE the module loads
            resetServices()
            local brokenDSS = {
                GetDataStore = function(_self, _key)
                    error("DataStore unavailable in test")
                end,
            }
            -- Override the service singleton directly
            local Players = game:GetService("Players")
            -- Patch DataStoreService to be the broken version
            local _realGetService = getmetatable(game).__index
            -- Temporarily install the broken service
            rawset(game, "_brokenDSS", brokenDSS)
            package.loaded["src.server.modules.GameSystems"] = nil

            -- Replace game:GetService to return broken DSS for DataStoreService
            local origMeta = getmetatable(game)
            local origIndex = origMeta.__index
            origMeta.__index = function(t, k)
                if k == "GetService" then
                    return function(_self, name)
                        if name == "DataStoreService" then return brokenDSS end
                        return origIndex(t, "GetService")(_self, name)
                    end
                end
                return origIndex(t, k)
            end

            local ok, result = pcall(require, "src.server.modules.GameSystems")

            -- Restore original metatable
            origMeta.__index = origIndex

            assert.is_true(ok, "Module should load even when DataStore is broken: " .. tostring(result))
        end)

        it("stat functions still work when DataStore is unavailable", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            -- Even with no real DataStore, score functions must work
            assert.has_no.errors(function()
                GS.onFoodStolen(player)
                GS.onFoodStored(player)
                GS.onFoodCollected(player, 1)
                GS.onFoodSold(player, 10)
            end)
            local score = player:FindFirstChild("leaderstats"):FindFirstChild("Score")
            assert.equals(85, score.Value)  -- 10 + 25 + 50
        end)
    end)

end)
