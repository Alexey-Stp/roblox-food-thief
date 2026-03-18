-- EnemyAI_spec.lua
-- Mock tests for EnemyAI.lua: detection range math, touch damage,
-- food confiscation, and debounce behaviour.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function loadConfig()
    package.loaded["src.server.modules.Config"] = nil
    return require("src.server.modules.Config")
end

local function loadEnemyAI()
    resetServices()
    package.loaded["src.server.modules.EnemyAI"] = nil
    resetWorkspace()
    return require("src.server.modules.EnemyAI")
end

-- Build a minimal mock player with a Character, Backpack, and Humanoid
local function makePlayer(name, position)
    position = position or Vector3.new(0, 0, 0)

    local humanoid = Instance.new("Humanoid")

    local hrp = Instance.new("Part")
    hrp.Name     = "HumanoidRootPart"
    hrp.Position = position

    local character = {
        Name      = (name or "Player") .. "Character",
        _children = { humanoid, hrp },
        Humanoid  = humanoid,
        HumanoidRootPart = hrp,
    }
    function character:FindFirstChild(n)
        for _, c in ipairs(self._children) do
            if c.Name == n then return c end
        end
        return nil
    end
    function character:FindFirstChildOfClass(cls)
        for _, c in ipairs(self._children) do
            if c.ClassName == cls then return c end
        end
        return nil
    end
    function character:GetChildren() return self._children end

    local backpack = {
        _children = {},
    }
    function backpack:GetChildren()
        local copy = {}
        for i, c in ipairs(self._children) do copy[i] = c end
        return copy
    end

    local player = {
        Name      = name or "TestPlayer",
        UserId    = math.random(1000, 9999),
        Character = character,
        Backpack  = backpack,
    }

    return player, character, humanoid, backpack, hrp
end

-- Add a food Tool to a player's Backpack
local function addFoodToBackpack(backpack, foodName)
    local tool = Instance.new("Tool")
    tool.Name = foodName or "Pizza"
    tool.Parent = backpack
    return tool
end

-- Add a food Tool to a player's Character (equipped)
local function addFoodToCharacter(character, foodName)
    local tool = Instance.new("Tool")
    tool.Name = foodName or "Pizza"
    tool.Parent = character
    return tool
end

-- Spawn a creature, return the model and the torso Part
local function spawnCreature(EnemyAI, Config, level)
    level = level or 1
    local startPos = Vector3.new(0, 5, 0)
    local model = EnemyAI.spawn("TestCreature", startPos, Config, level)

    -- Find the torso Part in workspace
    local torso
    for _, c in ipairs(workspace._children) do
        if c.ClassName == "Model" and c.Name == "TestCreature" then
            for _, child in ipairs(c._children) do
                if child.Name == "Torso" then torso = child end
            end
        end
    end
    return model, torso
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("EnemyAI", function()

    -- -----------------------------------------------------------------------
    -- Detection range — pure math (no AI loop needed)
    -- -----------------------------------------------------------------------
    describe("detection range", function()
        it("Config.DETECTION_RANGE is 80 studs", function()
            local Config = loadConfig()
            assert.equals(80, Config.DETECTION_RANGE)
        end)

        it("a player 50 studs away is within detection range", function()
            local Config = loadConfig()
            local creaturePos = Vector3.new(0, 0, 0)
            local playerPos   = Vector3.new(50, 0, 0)
            local dist = (playerPos - creaturePos).Magnitude
            assert.is_true(dist < Config.DETECTION_RANGE)
        end)

        it("a player 90 studs away is outside detection range", function()
            local Config = loadConfig()
            local creaturePos = Vector3.new(0, 0, 0)
            local playerPos   = Vector3.new(90, 0, 0)
            local dist = (playerPos - creaturePos).Magnitude
            assert.is_false(dist < Config.DETECTION_RANGE)
        end)

        it("a player exactly at DETECTION_RANGE is NOT within range (strict <)", function()
            local Config = loadConfig()
            local dist = Config.DETECTION_RANGE  -- exactly 80
            assert.is_false(dist < Config.DETECTION_RANGE)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Creature spawning
    -- -----------------------------------------------------------------------
    describe("spawn", function()
        it("returns a Model placed in workspace", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local model   = EnemyAI.spawn("Growler", Vector3.new(0, 5, 0), Config, 1)

            assert.not_nil(model)
            -- Model should be parented to workspace
            local found = workspace:FindFirstChild("Growler")
            assert.not_nil(found)
        end)

        it("spawned model has a Humanoid child", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            EnemyAI.spawn("Growler", Vector3.new(0, 5, 0), Config, 1)

            local model = workspace:FindFirstChild("Growler")
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            assert.not_nil(humanoid)
        end)

        it("spawned model has a Torso Part", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            EnemyAI.spawn("Growler", Vector3.new(0, 5, 0), Config, 1)

            local model = workspace:FindFirstChild("Growler")
            local torso = model:FindFirstChild("Torso")
            assert.not_nil(torso)
        end)

        it("level 2 spawns a Bear model (has RightArm)", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            EnemyAI.spawn("Crusher", Vector3.new(10, 5, 0), Config, 2)

            local model = workspace:FindFirstChild("Crusher")
            local arm   = model:FindFirstChild("RightArm")
            assert.not_nil(arm, "Bear should have a RightArm part")
        end)

        it("level 3 spawns an Occultist model (has Staff)", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            EnemyAI.spawn("Void", Vector3.new(20, 5, 0), Config, 3)

            local model = workspace:FindFirstChild("Void")
            local staff = model:FindFirstChild("Staff")
            assert.not_nil(staff, "Occultist should have a Staff part")
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Touch handler — damage
    -- -----------------------------------------------------------------------
    describe("touch handler: damage", function()

        it("reduces the player humanoid Health by HIT_DAMAGE (15)", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local Players = game:GetService("Players")
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            local player, character, humanoid = makePlayer("Alice", Vector3.new(0, 5, 0))
            Players:_registerCharacter(player, character)

            -- Simulate a hit part belonging to Alice's character
            local hitPart = Instance.new("Part")
            hitPart.Name   = "HitPart"
            hitPart.Parent = character

            assert.equals(100, humanoid.Health)
            model_torso.Touched._fire(model_torso.Touched, hitPart)
            assert.equals(85, humanoid.Health)   -- 100 - 15
        end)

        it("does not damage when hit Part has no Humanoid parent", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            -- A Part whose parent is NOT a character
            local randomPart = Instance.new("Part")
            randomPart.Name = "Floor"
            randomPart.Parent = workspace  -- parent has no Humanoid

            -- Should not crash, no damage dealt to anyone
            assert.has_no.errors(function()
                model_torso.Touched._fire(model_torso.Touched, randomPart)
            end)
        end)

        it("does not damage when hit Part's parent is not a registered player character", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            local humanoid = Instance.new("Humanoid")
            local npcChar  = { Name = "NPC", _children = { humanoid }, Humanoid = humanoid }
            function npcChar:FindFirstChildOfClass(cls)
                for _, c in ipairs(self._children) do
                    if c.ClassName == cls then return c end
                end
                return nil
            end

            local hitPart = Instance.new("Part")
            hitPart.Parent = npcChar

            -- GetPlayerFromCharacter returns nil for NPC → no damage
            model_torso.Touched._fire(model_torso.Touched, hitPart)
            assert.equals(100, humanoid.Health)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Touch handler — food confiscation
    -- -----------------------------------------------------------------------
    describe("touch handler: food confiscation", function()

        it("removes Tool items from the player's Backpack", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local Players = game:GetService("Players")
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            local player, character, _, backpack = makePlayer("Bob", Vector3.new(0, 5, 0))
            Players:_registerCharacter(player, character)
            addFoodToBackpack(backpack, "Pizza")
            addFoodToBackpack(backpack, "Cake")

            local hitPart = Instance.new("Part")
            hitPart.Parent = character

            assert.equals(2, #backpack._children)
            model_torso.Touched._fire(model_torso.Touched, hitPart)
            assert.equals(0, #backpack._children)
        end)

        it("removes an equipped Tool from the player's Character", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local Players = game:GetService("Players")
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            local player, character = makePlayer("Carol", Vector3.new(0, 5, 0))
            Players:_registerCharacter(player, character)
            addFoodToCharacter(character, "Burger")

            local hitPart = Instance.new("Part")
            hitPart.Parent = character

            model_torso.Touched._fire(model_torso.Touched, hitPart)

            -- Character should have no Tools remaining
            local toolLeft = character:FindFirstChildOfClass("Tool")
            assert.is_nil(toolLeft)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Touch handler — debounce
    -- -----------------------------------------------------------------------
    describe("touch handler: debounce", function()

        it("a second touch within HIT_DEBOUNCE does not deal damage again", function()
            local EnemyAI = loadEnemyAI()
            local Config  = loadConfig()
            local Players = game:GetService("Players")
            local _, model_torso = spawnCreature(EnemyAI, Config, 1)

            local player, character, humanoid = makePlayer("Dave", Vector3.new(0, 5, 0))
            Players:_registerCharacter(player, character)

            local hitPart = Instance.new("Part")
            hitPart.Parent = character

            -- First hit: 100 → 85
            model_torso.Touched._fire(model_torso.Touched, hitPart)
            assert.equals(85, humanoid.Health)

            -- Second hit immediately (same tick() value) — should be debounced
            model_torso.Touched._fire(model_torso.Touched, hitPart)
            assert.equals(85, humanoid.Health)   -- unchanged
        end)

    end)

end)
