-- Config.lua
-- Single source of truth for all game constants and data.
-- To add a food type: add an entry to FOOD_TYPES (include sellPrice).
-- To update textures: replace the rbxassetid:// values.

local Config = {}

-- -------------------------------------------------------------------------
-- World layout
-- -------------------------------------------------------------------------
Config.HOTEL_CENTER   = Vector3.new(0, 0.5, 0)
Config.FLOOR_HEIGHT   = 25    -- must be declared before HOTEL_SIZE
Config.FLOOR_COUNT    = 3
Config.HOTEL_SIZE     = Vector3.new(350, Config.FLOOR_HEIGHT * Config.FLOOR_COUNT, 350)
Config.BASE_POSITION  = Vector3.new(500, 1, 0)
Config.GROUND_SIZE    = Vector3.new(1000, 2, 1000)

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
	{ chase = 12, wander = 7  },   -- Floor 1: Wolves
	{ chase = 18, wander = 12 },   -- Floor 2: Bears
	{ chase = 28, wander = 18 },   -- Floor 3: Occultists
}
Config.CREATURES_PER_LEVEL = 3
Config.DETECTION_RANGE     = 80   -- studs; food-carrier detection radius
Config.HIT_DEBOUNCE        = 0.5  -- seconds between damage ticks per player
Config.HIT_DAMAGE          = 15   -- HP removed per hit

-- Per-floor creature name pools
Config.CREATURE_NAMES_WOLF      = { "Growler", "Fang", "Shadow", "Hunter", "Snarl", "Howl" }
Config.CREATURE_NAMES_BEAR      = { "Crusher", "Grizzly", "Mauler", "Titan", "Ruin", "Rend" }
Config.CREATURE_NAMES_OCCULTIST = { "Void", "Specter", "Wraith", "Cursed", "Dread", "Ritual" }

-- -------------------------------------------------------------------------
-- Food mechanics
-- -------------------------------------------------------------------------
Config.FOOD_RESPAWN_TIME = 5    -- seconds before a stolen food reappears
Config.MULTIPLIER_TIME   = 60   -- seconds to process food in the multiplier
Config.MULTIPLIER_FACTOR = 2    -- duplication factor

-- -------------------------------------------------------------------------
-- Door / lift interaction
-- -------------------------------------------------------------------------
Config.DOOR_DEBOUNCE = 0.5   -- seconds cooldown between door toggles
Config.LIFT_DEBOUNCE = 3.0   -- seconds cooldown between lift rides

-- -------------------------------------------------------------------------
-- Fridge storage (player base)
-- -------------------------------------------------------------------------
Config.FRIDGE_CAPACITY     = 10   -- items per refrigerator
Config.FRIDGE_UPGRADE_COST = 50   -- score points to buy an additional fridge
Config.MAX_FRIDGES         = 5

-- -------------------------------------------------------------------------
-- Money & shop
-- -------------------------------------------------------------------------
Config.SHOP_SPEED_COST = 100    -- money to buy one speed boost
Config.SHOP_JUMP_COST  = 150    -- money to buy one jump boost
Config.SPEED_BOOST     = 8      -- WalkSpeed added per purchase (hard cap: 40)
Config.JUMP_BOOST      = 15     -- JumpPower added per purchase (hard cap: 100)

-- -------------------------------------------------------------------------
-- Prize box
-- -------------------------------------------------------------------------
Config.PRIZE_BOX_COOLDOWN  = 30    -- seconds between opens per player
Config.PRIZE_BOX_MIN       = 5     -- minimum money reward
Config.PRIZE_BOX_MAX       = 50    -- maximum money reward

-- -------------------------------------------------------------------------
-- Day / Night cycle
-- -------------------------------------------------------------------------
Config.DAY_LENGTH = 240    -- seconds for a full day/night cycle

-- -------------------------------------------------------------------------
-- Food type definitions
-- texture    : decal shown on the Top face
-- sideTexture: decal shown on Front and Back faces (optional)
-- sellPrice  : money awarded when player sells this food at the sell stand
-- -------------------------------------------------------------------------
Config.FOOD_TYPES = {
	{
		name        = "Pizza",
		color       = BrickColor.new("Bright yellow"),
		size        = Vector3.new(3, 0.5, 3),
		texture     = "rbxassetid://6886896591",
		sideTexture = "rbxassetid://6886896591",
		sellPrice   = 20,
	},
	{
		name        = "Burger",
		color       = BrickColor.new("CGA brown"),
		size        = Vector3.new(2, 1.5, 2),
		texture     = "rbxassetid://7229442422",
		sideTexture = "rbxassetid://7229442422",
		sellPrice   = 15,
	},
	{
		name        = "Cake",
		color       = BrickColor.new("Pink"),
		size        = Vector3.new(2.5, 2, 2.5),
		texture     = "rbxassetid://7495147696",
		sideTexture = "rbxassetid://7495147696",
		sellPrice   = 30,
	},
	{
		name        = "Bread",
		color       = BrickColor.new("Nougat"),
		size        = Vector3.new(2, 1, 1.5),
		texture     = "rbxassetid://6324656637",
		sideTexture = "rbxassetid://6324656637",
		sellPrice   = 10,
	},
	{
		name        = "Apple",
		color       = BrickColor.new("Bright red"),
		size        = Vector3.new(1, 1, 1),
		texture     = "rbxassetid://6886896313",
		sideTexture = nil,
		sellPrice   = 8,
	},
	{
		name        = "Donut",
		color       = BrickColor.new("Bright orange"),
		size        = Vector3.new(1.5, 0.5, 1.5),
		texture     = "rbxassetid://7229442422",
		sideTexture = nil,
		sellPrice   = 12,
	},
	{
		name        = "Sushi",
		color       = BrickColor.new("White"),
		size        = Vector3.new(1.5, 0.5, 2),
		texture     = "rbxassetid://6886896591",
		sideTexture = nil,
		sellPrice   = 25,
	},
}

-- -------------------------------------------------------------------------
-- Score values per action
-- -------------------------------------------------------------------------
Config.SCORE_STEAL   = 10
Config.SCORE_STORE   = 25
Config.SCORE_COLLECT = 50

return Config
