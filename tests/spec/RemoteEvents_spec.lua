-- RemoteEvents_spec.lua
-- Mock tests for src/shared/RemoteEvents.lua.
-- Verifies that the module creates correctly named RemoteEvent instances
-- and that getOrCreate is idempotent (returns the same object on re-load).

describe("RemoteEvents", function()

    before_each(function()
        -- Reset the shared folder mock so each test gets a clean slate
        _G._mockSharedFolder._children = {}
        -- Reset module cache so the module re-evaluates on next require
        package.loaded["src.shared.RemoteEvents"] = nil
    end)

    -- -----------------------------------------------------------------------
    -- Event names
    -- -----------------------------------------------------------------------
    describe("event names", function()
        it("HitFlash event has the correct Name", function()
            local RE = require("src.shared.RemoteEvents")
            assert.equals("HitFlash", RE.HitFlash.Name)
        end)

        it("FoodStolen event has the correct Name", function()
            local RE = require("src.shared.RemoteEvents")
            assert.equals("FoodStolen", RE.FoodStolen.Name)
        end)

        it("both events are RemoteEvent instances", function()
            local RE = require("src.shared.RemoteEvents")
            assert.equals("RemoteEvent", RE.HitFlash.ClassName)
            assert.equals("RemoteEvent", RE.FoodStolen.ClassName)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Event container (Events folder)
    -- -----------------------------------------------------------------------
    describe("events folder", function()
        it("creates an Events folder under Shared", function()
            require("src.shared.RemoteEvents")
            local eventsFolder = _G._mockSharedFolder:FindFirstChild("Events")
            assert.not_nil(eventsFolder)
            assert.equals("Events", eventsFolder.Name)
        end)

        it("HitFlash is parented inside the Events folder", function()
            local RE = require("src.shared.RemoteEvents")
            local eventsFolder = _G._mockSharedFolder:FindFirstChild("Events")
            assert.not_nil(eventsFolder)
            local found = eventsFolder:FindFirstChild("HitFlash")
            assert.not_nil(found)
            assert.equals(RE.HitFlash, found)
        end)

        it("FoodStolen is parented inside the Events folder", function()
            local RE = require("src.shared.RemoteEvents")
            local eventsFolder = _G._mockSharedFolder:FindFirstChild("Events")
            assert.not_nil(eventsFolder)
            local found = eventsFolder:FindFirstChild("FoodStolen")
            assert.not_nil(found)
            assert.equals(RE.FoodStolen, found)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Idempotence — getOrCreate must not duplicate children
    -- -----------------------------------------------------------------------
    describe("getOrCreate idempotence", function()
        it("requiring the module twice returns the same HitFlash object", function()
            local RE1 = require("src.shared.RemoteEvents")
            -- Do NOT clear the shared folder — simulate a second require of the
            -- same running server (cache cleared but folder still populated)
            package.loaded["src.shared.RemoteEvents"] = nil
            local RE2 = require("src.shared.RemoteEvents")

            -- Both should point to the same underlying instance in the folder
            assert.equals(RE1.HitFlash.Name, RE2.HitFlash.Name)
        end)

        it("second require does not add duplicate Events folder", function()
            require("src.shared.RemoteEvents")
            package.loaded["src.shared.RemoteEvents"] = nil
            require("src.shared.RemoteEvents")

            local count = 0
            for _, c in ipairs(_G._mockSharedFolder._children) do
                if c.Name == "Events" then count = count + 1 end
            end
            assert.equals(1, count)
        end)

        it("second require does not add duplicate HitFlash child", function()
            require("src.shared.RemoteEvents")
            package.loaded["src.shared.RemoteEvents"] = nil
            require("src.shared.RemoteEvents")

            local eventsFolder = _G._mockSharedFolder:FindFirstChild("Events")
            local count = 0
            for _, c in ipairs(eventsFolder._children) do
                if c.Name == "HitFlash" then count = count + 1 end
            end
            assert.equals(1, count)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Signal interface
    -- -----------------------------------------------------------------------
    describe("RemoteEvent signal interface", function()
        it("HitFlash exposes OnServerEvent.Connect", function()
            local RE = require("src.shared.RemoteEvents")
            assert.is_function(RE.HitFlash.OnServerEvent.Connect)
        end)

        it("FoodStolen exposes FireClient", function()
            local RE = require("src.shared.RemoteEvents")
            assert.is_function(RE.FoodStolen.FireClient)
        end)
    end)

end)
