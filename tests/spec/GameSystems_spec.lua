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

    -- -----------------------------------------------------------------------
    -- Load / save lifecycle (data-loss protection)
    -- -----------------------------------------------------------------------
    describe("load / save lifecycle", function()
        local function loadConfig()
            package.loaded["src.server.modules.Config"] = nil
            return require("src.server.modules.Config")
        end

        -- A player Instance parented under Players (so it counts as "still in game")
        local function makeLivePlayer(userId)
            local Players = game:GetService("Players")
            local player = Instance.new("Player")
            player.Name = "Live" .. userId
            player.UserId = userId
            player.Backpack = Instance.new("Backpack")
            player.CharacterAdded = {
                Connect = function() return { Disconnect = function() end } end,
                Wait = function() end,
            }
            player.Parent = Players
            return player
        end

        local function storeData()
            return game:GetService("DataStoreService")._stores["PlayerData_v3"]._data
        end

        it("never overwrites saved data when the load failed", function()
            local GS = loadGameSystems()
            local Config = loadConfig()
            GS.init(Config)
            local Players = game:GetService("Players")
            local store = game:GetService("DataStoreService")._stores["PlayerData_v3"]
            store._data["555"] = { money = 9000, score = 1234 }
            store.GetAsync = function() error("DataStore throttled") end

            local player = makeLivePlayer(555)
            Players._onPlayerAdded(player)
            GS.addMoney(player, 5)
            Players._onPlayerRemoving(player)

            assert.equals(9000, storeData()["555"].money)
            assert.equals(1234, storeData()["555"].score)
        end)

        it("loads stats and resets legacy 500 WalkSpeed / JumpPower saves to defaults", function()
            local GS = loadGameSystems()
            local Config = loadConfig()
            GS.init(Config)
            local Players = game:GetService("Players")
            storeData()["777"] = { money = 300, score = 50, walkSpeed = 500, jumpPower = 500, fridgeLevel = 4 }

            local player = makeLivePlayer(777)
            Players._onPlayerAdded(player)

            local ls = player:FindFirstChild("leaderstats")
            assert.equals(300, ls:FindFirstChild("Money").Value)
            local walk, jump = GS.getSettings(player)
            assert.equals(Config.DEFAULT_WALK_SPEED, walk)
            assert.equals(Config.DEFAULT_JUMP_POWER, jump)
            assert.equals(4, GS.getFridgeLevel(player))
            assert.equals(4, player:GetAttribute("FridgeLevel"))
        end)

        it("keeps legitimately purchased movement upgrades", function()
            local GS = loadGameSystems()
            local Config = loadConfig()
            GS.init(Config)
            local Players = game:GetService("Players")
            local bought = Config.DEFAULT_WALK_SPEED + Config.SPEED_BOOST
            storeData()["999"] = { walkSpeed = bought, jumpPower = Config.MAX_JUMP_POWER }

            local player = makeLivePlayer(999)
            Players._onPlayerAdded(player)

            local walk, jump = GS.getSettings(player)
            assert.equals(bought, walk)
            assert.equals(Config.MAX_JUMP_POWER, jump)
        end)

        it("saves cached settings and money after a successful load", function()
            local GS = loadGameSystems()
            local Config = loadConfig()
            GS.init(Config)
            local Players = game:GetService("Players")
            storeData()["888"] = { money = 10 }

            local player = makeLivePlayer(888)
            Players._onPlayerAdded(player)
            GS.addMoney(player, 90)
            GS.updateSettings(player, Config.DEFAULT_WALK_SPEED + 8, nil)
            GS.setFridgeLevel(player, 2)
            Players._onPlayerRemoving(player)

            local saved = storeData()["888"]
            assert.equals(100, saved.money)
            assert.equals(Config.DEFAULT_WALK_SPEED + 8, saved.walkSpeed)
            assert.equals(2, saved.fridgeLevel)
        end)

        it("trySpend refuses when money is insufficient", function()
            local GS = loadGameSystems()
            local player = makePlayer()
            GS.addMoney(player, 50)
            assert.is_false(GS.trySpend(player, 60))
            assert.is_true(GS.trySpend(player, 50))
            assert.equals(0, player:FindFirstChild("leaderstats"):FindFirstChild("Money").Value)
        end)
    end)

end)
