-- BatCombat_spec.lua
-- Unit tests for BatCombat.lua.
-- Covers: PvP hit, Hunter-NPC hit, Castle-part hit, out-of-range miss,
-- cooldown enforcement, and Castle-part destruction on HP reaching zero.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function loadConfig()
	package.loaded["src.server.modules.Config"] = nil
	return require("src.server.modules.Config")
end

local function loadBatCombat()
	resetServices()
	resetWorkspace()
	-- workspace needs GetChildren for the Hunter NPC scan
	if not workspace.GetChildren then
		function workspace:GetChildren()
			local copy = {}
			for i, c in ipairs(self._children) do
				copy[i] = c
			end
			return copy
		end
	end
	package.loaded["src.server.modules.BatCombat"] = nil
	return require("src.server.modules.BatCombat")
end

-- Build a minimal mock player + character with a Humanoid and HumanoidRootPart.
-- A Bat tool is already "equipped" (parented into the character).
local function makeAttacker(position)
	position = position or Vector3.new(0, 0, 0)

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Position = position

	-- Bat tool equipped in character
	local batHandle = Instance.new("Part")
	batHandle.Name = "Handle"
	batHandle:SetAttribute("IsBat", true)

	local batTool = Instance.new("Tool")
	batTool.Name = "Bat"
	batHandle.Parent = batTool

	local humanoid = Instance.new("Humanoid")

	local character = {
		Name = "AttackerCharacter",
		_children = { hrp, batTool, humanoid },
	}
	function character:FindFirstChild(n)
		for _, c in ipairs(self._children) do
			if c.Name == n then
				return c
			end
		end
		return nil
	end
	function character:FindFirstChildOfClass(cls)
		for _, c in ipairs(self._children) do
			if c.ClassName == cls then
				return c
			end
		end
		return nil
	end
	-- FindFirstChildWhichIsA — used by BatCombat to find the equipped Tool
	function character:FindFirstChildWhichIsA(cls)
		for _, c in ipairs(self._children) do
			if c.ClassName == cls then
				return c
			end
		end
		return nil
	end
	function character:GetChildren()
		return self._children
	end

	local backpack = { _children = {} }
	function backpack:GetChildren()
		return self._children
	end

	local player = {
		Name = "Attacker",
		UserId = 1,
		Character = character,
		Backpack = backpack,
	}
	return player, character, hrp
end

-- Build a minimal second player (victim) with a Humanoid + HRP.
local function makeVictim(name, position)
	position = position or Vector3.new(5, 0, 0)

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Position = position

	local humanoid = Instance.new("Humanoid")

	local character = {
		Name = (name or "Victim") .. "Character",
		ClassName = "Model",
		_children = { hrp, humanoid },
	}
	function character:IsA(cls)
		return cls == "Model"
	end

	-- Link hrp back to its parent so GetPartBoundsInRadius → part.Parent works correctly.
	-- Manually set _parent (bypasses the Instance metamethod since character is a plain table).
	rawset(hrp, "_parent", character)
	-- Place the character in workspace so the spatial query can discover the HRP.
	table.insert(workspace._children, character)
	function character:FindFirstChild(n)
		for _, c in ipairs(self._children) do
			if c.Name == n then
				return c
			end
		end
		return nil
	end
	function character:FindFirstChildOfClass(cls)
		for _, c in ipairs(self._children) do
			if c.ClassName == cls then
				return c
			end
		end
		return nil
	end
	function character:GetChildren()
		return self._children
	end

	local backpack = { _children = {} }
	function backpack:GetChildren()
		return self._children
	end

	local player = {
		Name = name or "Victim",
		UserId = 2,
		Character = character,
		Backpack = backpack,
	}
	return player, character, humanoid, hrp
end

-- Build a mock Guard_ NPC model in workspace.
-- Returns (model, torso, humanoid).
local function makeGuardNPC(position)
	position = position or Vector3.new(5, 0, 0)

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Position = position

	local humanoid = Instance.new("Humanoid")

	local model = Instance.new("Model")
	model.Name = "Guard_TestOfficer"
	model.PrimaryPart = torso
	torso.Parent = model
	humanoid.Parent = model
	model.Parent = workspace

	return model, torso, humanoid
end

-- Build a mock Castle model containing a Wall and a Door.
-- Returns (castleModel, wallPart, doorPart).
local function makeCastle(wallPosition, doorPosition)
	wallPosition = wallPosition or Vector3.new(5, 0, 0)
	doorPosition = doorPosition or Vector3.new(6, 0, 0)

	local castleModel = Instance.new("Model")
	castleModel.Name = "Castle"

	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Position = wallPosition
	wall:SetAttribute("Health", 100)
	wall.Parent = castleModel

	local door = Instance.new("Part")
	door.Name = "Door"
	door.Position = doorPosition
	door:SetAttribute("Health", 100)
	door.Parent = castleModel

	-- Parent into a SkyHotel model that lives in workspace (matches production layout)
	local skyModel = Instance.new("Model")
	skyModel.Name = "SkyHotel"
	castleModel.Parent = skyModel
	skyModel.Parent = workspace

	return castleModel, wall, door
end

-- Build a minimal mock RemoteEvents table.
local function makeRemoteEvents()
	local hitClientPlayer = nil
	local flashClientPlayer = nil
	local serverHandlers = {}

	return {
		BatSwing = {
			OnServerEvent = {
				Connect = function(_self, fn)
					table.insert(serverHandlers, fn)
				end,
				_fire = function(_self, ...)
					for _, fn in ipairs(serverHandlers) do
						fn(...)
					end
				end,
			},
		},
		BatHit = {
			FireClient = function(_self, player)
				hitClientPlayer = player
			end,
			_getLastHitPlayer = function()
				return hitClientPlayer
			end,
		},
		HitFlash = {
			FireClient = function(_self, player)
				flashClientPlayer = player
			end,
			_getLastFlashPlayer = function()
				return flashClientPlayer
			end,
		},
		_getHitPlayer = function()
			return hitClientPlayer
		end,
		_getFlashPlayer = function()
			return flashClientPlayer
		end,
	}
end

-- ---------------------------------------------------------------------------
-- Shared initialise helper
-- ---------------------------------------------------------------------------

local function initBatCombat(BatCombat, remoteEvents, Config)
	BatCombat.init(remoteEvents, Config)
	-- Retrieve the registered OnServerEvent handler by inspecting the table
end

-- Fire the swing as a given player (optionally reset cooldown first)
local function swing(remoteEvents, player, skipCooldownReset)
	-- The first swing is always accepted (no prior timestamp).
	-- `skipCooldownReset` can be used to test cooldown behaviour.
	remoteEvents.BatSwing.OnServerEvent._fire(remoteEvents.BatSwing.OnServerEvent, player, Vector3.new(0, 0, 0))
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("BatCombat", function()
	-- -----------------------------------------------------------------------
	-- PvP damage
	-- -----------------------------------------------------------------------
	describe("PvP: damaging another player", function()
		it("deals BAT_DAMAGE to a nearby player's Humanoid", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker, _, attackerHRP = makeAttacker(Vector3.new(0, 0, 0))
			local victim, _, victimHumanoid, _ = makeVictim("Victim1", Vector3.new(5, 0, 0))

			Players._playerList = { attacker, victim }
			Players._charMap[victim.Character] = victim

			initBatCombat(BatCombat, remoteEvents, Config)

			swing(remoteEvents, attacker)

			assert.equals(100 - Config.BAT_DAMAGE, victimHumanoid.Health)
		end)

		it("does not damage a player who is out of BAT_RANGE", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			local victim, _, victimHumanoid = makeVictim("FarVictim", Vector3.new(Config.BAT_RANGE + 50, 0, 0))

			Players._playerList = { attacker, victim }
			Players._charMap[victim.Character] = victim

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			-- Should be untouched
			assert.equals(100, victimHumanoid.Health)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Hunter NPC damage
	-- -----------------------------------------------------------------------
	describe("Hunter NPC: damaging Guard_ models", function()
		it("deals BAT_DAMAGE to a nearby Guard_ NPC Humanoid", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			makeGuardNPC(Vector3.new(5, 0, 0))

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			-- Find the guard in workspace and check its Humanoid
			local guardModel = workspace:FindFirstChild("Guard_TestOfficer")
			assert.not_nil(guardModel)
			local guardHumanoid = guardModel:FindFirstChildOfClass("Humanoid")
			assert.not_nil(guardHumanoid)
			assert.equals(100 - Config.BAT_DAMAGE, guardHumanoid.Health)
		end)

		it("does not damage a Guard_ NPC that is out of BAT_RANGE", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			makeGuardNPC(Vector3.new(Config.BAT_RANGE + 50, 0, 0))

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			local guardModel = workspace:FindFirstChild("Guard_TestOfficer")
			local guardHumanoid = guardModel:FindFirstChildOfClass("Humanoid")
			assert.equals(100, guardHumanoid.Health)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Castle part damage and destruction
	-- -----------------------------------------------------------------------
	describe("Castle part: Wall / Door destruction", function()
		it("reduces Wall Health attribute by BAT_DAMAGE when in range", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			local _, wall, _ = makeCastle(Vector3.new(5, 0, 0), Vector3.new(6, 0, 0))
			wall:SetAttribute("Health", 100)

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			assert.equals(100 - Config.BAT_DAMAGE, wall:GetAttribute("Health"))
		end)

		it("makes a Wall transparent and non-collidable when Health reaches zero", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			-- Start with health equal to exactly one swing of damage
			local _, wall, _ = makeCastle(Vector3.new(5, 0, 0), Vector3.new(100, 0, 100))
			wall:SetAttribute("Health", Config.BAT_DAMAGE)

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			-- Part should be made intangible immediately
			assert.equals(1, wall.Transparency)
			assert.is_false(wall.CanCollide)
		end)

		it("does not affect a Wall that is out of BAT_RANGE", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			local farPos = Vector3.new(Config.BAT_RANGE + 50, 0, 0)
			local _, wall, _ = makeCastle(farPos, Vector3.new(100, 0, 100))
			wall:SetAttribute("Health", 100)

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			-- Health unchanged
			assert.equals(100, wall:GetAttribute("Health"))
		end)

		it("reduces Door Health attribute by BAT_DAMAGE when Wall is out of range but Door is in range", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			Players._playerList = { attacker }

			-- Wall far away, door close
			local farWall = Vector3.new(Config.BAT_RANGE + 50, 0, 0)
			local closeDoor = Vector3.new(5, 0, 0)
			local _, wall, door = makeCastle(farWall, closeDoor)
			wall:SetAttribute("Health", 100)
			door:SetAttribute("Health", 100)

			initBatCombat(BatCombat, remoteEvents, Config)
			swing(remoteEvents, attacker)

			-- Wall untouched, Door damaged
			assert.equals(100, wall:GetAttribute("Health"))
			assert.equals(100 - Config.BAT_DAMAGE, door:GetAttribute("Health"))
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Cooldown enforcement
	-- -----------------------------------------------------------------------
	describe("cooldown", function()
		it("a second swing within BAT_COOLDOWN does not deal damage again", function()
			local BatCombat = loadBatCombat()
			local Config = loadConfig()
			local Players = game:GetService("Players")
			local remoteEvents = makeRemoteEvents()

			local attacker = makeAttacker(Vector3.new(0, 0, 0))
			local victim, _, victimHumanoid = makeVictim("CooldownVictim", Vector3.new(5, 0, 0))

			Players._playerList = { attacker, victim }
			Players._charMap[victim.Character] = victim

			initBatCombat(BatCombat, remoteEvents, Config)

			-- First swing: should damage
			swing(remoteEvents, attacker)
			assert.equals(100 - Config.BAT_DAMAGE, victimHumanoid.Health)

			-- Immediate second swing (same tick() value — within cooldown)
			swing(remoteEvents, attacker)
			-- Health must NOT decrease further
			assert.equals(100 - Config.BAT_DAMAGE, victimHumanoid.Health)
		end)
	end)

	-- -----------------------------------------------------------------------
	-- Config constant validation
	-- -----------------------------------------------------------------------
	describe("Config", function()
		it("CASTLE_PART_HEALTH is a positive integer", function()
			local Config = loadConfig()
			assert.is_true(Config.CASTLE_PART_HEALTH > 0)
			assert.equals("number", type(Config.CASTLE_PART_HEALTH))
		end)

		it("BAT_DAMAGE is less than CASTLE_PART_HEALTH (one swing never insta-kills)", function()
			local Config = loadConfig()
			assert.is_true(Config.BAT_DAMAGE < Config.CASTLE_PART_HEALTH)
		end)
	end)
end)
