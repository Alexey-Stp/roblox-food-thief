-- Config.lua
-- Single source of truth for all game constants and data.
-- To add a food type: add an entry to FOOD_TYPES (include sellPrice).
-- To update textures: replace the rbxassetid:// values.

local Config = {}

-- -------------------------------------------------------------------------
-- World layout
-- -------------------------------------------------------------------------
Config.HOTEL_CENTER = Vector3.new(0, 0.5, 0)
Config.FLOOR_HEIGHT = 25 -- must be declared before HOTEL_SIZE
Config.FLOOR_COUNT = 3
Config.HOTEL_SIZE = Vector3.new(350, Config.FLOOR_HEIGHT * Config.FLOOR_COUNT, 350)
Config.BASE_POSITION = Vector3.new(500, 1, 0)
Config.GROUND_SIZE = Vector3.new(1000, 2, 1000)

-- -------------------------------------------------------------------------
-- Hotel structure
-- -------------------------------------------------------------------------
Config.WALL_THICKNESS = 5

-- Number of food-bearing tables per floor
Config.TABLES_PER_FLOOR = { 8, 6, 4 }

-- -------------------------------------------------------------------------
-- Enemy behaviour — per level [1]=wolves [2]=bears [3]=occultists
-- -------------------------------------------------------------------------
Config.LEVEL_SPEEDS = {
	{ chase = 12, wander = 7 }, -- Floor 1: Wolves
	{ chase = 18, wander = 12 }, -- Floor 2: Bears
	{ chase = 28, wander = 18 }, -- Floor 3: Occultists
}
Config.CREATURES_PER_LEVEL = 3
Config.DETECTION_RANGE = 80 -- studs; food-carrier detection radius
Config.HIT_DEBOUNCE = 0.5 -- seconds between damage ticks per player
Config.HIT_DAMAGE = 15 -- HP removed per hit

-- Per-floor creature name pools
Config.CREATURE_NAMES_WOLF = { "Growler", "Fang", "Shadow", "Hunter", "Snarl", "Howl" }
Config.CREATURE_NAMES_BEAR = { "Crusher", "Grizzly", "Mauler", "Titan", "Ruin", "Rend" }
Config.CREATURE_NAMES_OCCULTIST = { "Void", "Specter", "Wraith", "Cursed", "Dread", "Ritual" }

-- -------------------------------------------------------------------------
-- Food mechanics
-- -------------------------------------------------------------------------
Config.FOOD_RESPAWN_TIME = 5 -- seconds before a stolen food reappears
Config.MULTIPLIER_TIME = 60 -- seconds to process food in the multiplier
Config.MULTIPLIER_FACTOR = 2 -- duplication factor

-- -------------------------------------------------------------------------
-- Door / lift interaction
-- -------------------------------------------------------------------------
Config.DOOR_DEBOUNCE = 0.5 -- seconds cooldown between door toggles
Config.LIFT_DEBOUNCE = 3.0 -- seconds cooldown between lift rides

-- -------------------------------------------------------------------------
-- Fridge storage (player base) — level-up system
-- -------------------------------------------------------------------------
Config.FRIDGE_CAPACITY = 10 -- items per refrigerator
Config.FRIDGE_COUNT = 2 -- fixed number of fridges at base
Config.FRIDGE_MAX_LEVEL = 10 -- maximum upgrade level
Config.FRIDGE_UPGRADE_BASE_COST = 100 -- money cost; formula: floor(100 * level^1.5)
-- Value bonus formula: finalPrice = basePrice * (1 + 0.3 * fridgeLevel)

-- -------------------------------------------------------------------------
-- Money & shop
-- -------------------------------------------------------------------------
Config.SHOP_SPEED_COST = 100 -- money to buy one speed boost
Config.SHOP_JUMP_COST = 150 -- money to buy one jump boost
Config.SPEED_BOOST = 8 -- WalkSpeed added per purchase (hard cap: 40)
Config.JUMP_BOOST = 15 -- JumpPower added per purchase (hard cap: 100)

-- -------------------------------------------------------------------------
-- Prize box
-- -------------------------------------------------------------------------
Config.PRIZE_BOX_COOLDOWN = 30 -- seconds between opens per player
Config.PRIZE_BOX_MIN = 5 -- minimum money reward
Config.PRIZE_BOX_MAX = 50 -- maximum money reward

-- -------------------------------------------------------------------------
-- Day / Night cycle
-- -------------------------------------------------------------------------
Config.DAY_LENGTH = 240 -- seconds for a full day/night cycle

-- -------------------------------------------------------------------------
-- Food type definitions
-- texture    : decal shown on the Top face
-- sideTexture: decal shown on Front and Back faces (optional)
-- sellPrice  : money awarded when player sells this food at the sell stand
-- -------------------------------------------------------------------------
Config.FOOD_TYPES = {
	{
		name = "Pizza",
		color = BrickColor.new("Bright yellow"),
		size = Vector3.new(3, 0.5, 3),
		texture = "rbxassetid://6886896591",
		sideTexture = "rbxassetid://6886896591",
		sellPrice = 20,
		rarity = "Common",
	},
	{
		name = "Burger",
		color = BrickColor.new("CGA brown"),
		size = Vector3.new(2, 1.5, 2),
		texture = "rbxassetid://7229442422",
		sideTexture = "rbxassetid://7229442422",
		sellPrice = 15,
		rarity = "Common",
	},
	{
		name = "Cake",
		color = BrickColor.new("Pink"),
		size = Vector3.new(2.5, 2, 2.5),
		texture = "rbxassetid://7495147696",
		sideTexture = "rbxassetid://7495147696",
		sellPrice = 30,
		rarity = "Rare",
	},
	{
		name = "Bread",
		color = BrickColor.new("Nougat"),
		size = Vector3.new(2, 1, 1.5),
		texture = "rbxassetid://6324656637",
		sideTexture = "rbxassetid://6324656637",
		sellPrice = 10,
		rarity = "Common",
	},
	{
		name = "Apple",
		color = BrickColor.new("Bright red"),
		size = Vector3.new(1, 1, 1),
		texture = "rbxassetid://6886896313",
		sideTexture = nil,
		sellPrice = 8,
		rarity = "Common",
	},
	{
		name = "Donut",
		color = BrickColor.new("Bright orange"),
		size = Vector3.new(1.5, 0.5, 1.5),
		texture = "rbxassetid://7229442422",
		sideTexture = nil,
		sellPrice = 12,
		rarity = "Common",
	},
	{
		name = "Sushi",
		color = BrickColor.new("White"),
		size = Vector3.new(1.5, 0.5, 2),
		texture = "rbxassetid://6886896591",
		sideTexture = nil,
		sellPrice = 25,
		rarity = "Rare",
	},
}

-- -------------------------------------------------------------------------
-- Score values per action
-- -------------------------------------------------------------------------
Config.SCORE_STEAL = 10
Config.SCORE_STORE = 25
Config.SCORE_COLLECT = 50

-- -------------------------------------------------------------------------
-- Bat combat (PvP)
-- -------------------------------------------------------------------------
Config.BAT_COOLDOWN = 0.8 -- seconds between swings (server-side)
Config.BAT_DAMAGE = 20 -- HP removed per hit
Config.BAT_RANGE = 10 -- studs; server spatial scan radius

-- -------------------------------------------------------------------------
-- Guard (hunter) NPCs — Floor 1 only
-- -------------------------------------------------------------------------
Config.GUARD_ALERT_RANGE = 60 -- studs: react to theft within this radius
Config.GUARD_CATCH_RANGE = 5 -- studs: triggers catch sequence
Config.GUARD_CHASE_SPEED = 14 -- WalkSpeed while chasing
Config.GUARD_PATROL_SPEED = 6 -- WalkSpeed while patrolling
Config.GUARD_CHASE_TIMEOUT = 20 -- seconds before guard abandons chase
Config.GUARD_COUNT = 3 -- number of guards spawned on floor 1

-- -------------------------------------------------------------------------
-- Flying carpet (night reward)
-- -------------------------------------------------------------------------
Config.CARPET_SPAWN_POS = Vector3.new(-160, 3, 0) -- near restaurant entrance
Config.CARPET_MAX_HEIGHT = 150 -- maximum flight altitude (Y studs)
Config.CARPET_FLIGHT_SPEED = 30 -- horizontal studs/sec
Config.CARPET_ASCENT_SPEED = 15 -- vertical studs/sec
Config.CARPET_MAX_SPEED_VALIDATE = 55 -- server anti-exploit speed cap

-- -------------------------------------------------------------------------
-- Airplanes dropping food
-- -------------------------------------------------------------------------
Config.AIRPLANE_SPAWN_X = -800 -- west map edge spawn X
Config.AIRPLANE_END_X = 800 -- east map edge destination X
Config.AIRPLANE_ALTITUDE = 200 -- Y position during flight
Config.AIRPLANE_SPEED = 100 -- studs/sec
Config.AIRPLANE_INTERVAL_MIN = 90 -- min seconds between airplane events
Config.AIRPLANE_INTERVAL_MAX = 180 -- max seconds between airplane events
Config.AIRPLANE_DROP_INTERVAL = 8 -- seconds between food drops during flight
Config.AIRPLANE_FOOD_DESPAWN = 30 -- seconds before dropped food disappears

return Config
