-- Main.server.lua
-- Entry point for all server-side game logic.
-- Requires and wires up all modules in the correct order.

local modules = script.Parent.modules

local function safeRequire(mod, name)
	local ok, result = pcall(require, mod)
	if not ok then
		error("[Main] Failed to require " .. name .. ": " .. tostring(result), 2)
	end
	return result
end

local Config = safeRequire(modules.Config, "Config")
local GameSystems = safeRequire(modules.GameSystems, "GameSystems")
local RemoteEvents = safeRequire(game:GetService("ReplicatedStorage").Shared.RemoteEvents, "RemoteEvents")
local RestaurantBuilder = safeRequire(modules.RestaurantBuilder, "RestaurantBuilder")
local FoodSystem = safeRequire(modules.FoodSystem, "FoodSystem")
local EnemyAI = safeRequire(modules.EnemyAI, "EnemyAI")
local BaseBuilder = safeRequire(modules.BaseBuilder, "BaseBuilder")
local DayNight = safeRequire(modules.DayNight, "DayNight")
-- New modules
local BatCombat = safeRequire(modules.BatCombat, "BatCombat")
local FoodInventory = safeRequire(modules.FoodInventory, "FoodInventory")
local RefrigeratorSystem = safeRequire(modules.RefrigeratorSystem, "RefrigeratorSystem")
local FlyingCarpet = safeRequire(modules.FlyingCarpet, "FlyingCarpet")
local AirplaneSystem = safeRequire(modules.AirplaneSystem, "AirplaneSystem")
local HunterAI = safeRequire(modules.HunterAI, "HunterAI")
local SkyHotel = safeRequire(modules.SkyHotel, "SkyHotel")

-- 1. Init scoring and DataStore first (players may have already joined)
GameSystems.init(Config)

-- 2. Wire RemoteEvents and dependencies into subsystems
FoodSystem.init(RemoteEvents, GameSystems)
EnemyAI.init(RemoteEvents)
BaseBuilder.init(GameSystems, Config)
BatCombat.init(RemoteEvents, Config)
FoodInventory.init(RemoteEvents, Config)
RefrigeratorSystem.init(RemoteEvents, Config, GameSystems)
FlyingCarpet.init(RemoteEvents, Config)
AirplaneSystem.init(Config, GameSystems)
HunterAI.init(RemoteEvents, Config)
SkyHotel.init(Config)

-- 3. Build the world
print("[Main] Building Grand Hotel...")
local _, floorFoodPositions = RestaurantBuilder.build(Config)

print("[Main] Building player safe base...")
BaseBuilder.build()

print("[Main] Building Sky Hotel Castle...")
SkyHotel.build()

print("[Main] Spawning food on tables...")
task.wait(0.5)
FoodSystem.spawnAll(floorFoodPositions)

print("[Main] Spawning guards...")
HunterAI.spawnAll()

-- 4. Spawn per-floor creature types
print("[Main] Spawning creatures...")
task.wait(1)
local namePools = {
	Config.CREATURE_NAMES_WOLF,
	Config.CREATURE_NAMES_BEAR,
	Config.CREATURE_NAMES_OCCULTIST,
}
for level = 1, Config.FLOOR_COUNT do
	local floorY = Config.HOTEL_CENTER.Y + (level - 1) * Config.FLOOR_HEIGHT + 2
	local pool = namePools[level]
	for i = 1, Config.CREATURES_PER_LEVEL do
		local name = pool[((i - 1) % #pool) + 1]
		local angle = (math.pi * 2 / Config.CREATURES_PER_LEVEL) * i
		local spawnPos = Vector3.new(
			Config.HOTEL_CENTER.X + math.cos(angle) * 60,
			floorY,
			Config.HOTEL_CENTER.Z + math.sin(angle) * 60
		)
		EnemyAI.spawn(name, spawnPos, Config, level)
	end
end

print("[Main] Game ready!")

-- 5. Start day/night cycle
print("[Main] Starting day/night cycle...")
DayNight.start(Config.DAY_LENGTH)

-- 6. Start event-driven systems
AirplaneSystem.start()
FlyingCarpet.start()
