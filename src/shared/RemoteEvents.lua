-- RemoteEvents.lua
-- Centralised RemoteEvent setup accessible from both server and client.
-- Server: require this module once during init to create the instances.
-- Client: require this module to get references to the same instances.

local function getOrCreate(parent, name, className)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

-- This module lives at ReplicatedStorage/Shared/RemoteEvents,
-- so script.Parent is the Shared folder directly — no WaitForChild needed.
local Shared = script.Parent
local eventsFolder = getOrCreate(Shared, "Events", "Folder")

local RemoteEvents = {
	-- Server → Client: flash the hit player's screen red
	HitFlash = getOrCreate(eventsFolder, "HitFlash", "RemoteEvent"),

	-- Server → Client: sparkle effect at food position when stolen
	FoodStolen = getOrCreate(eventsFolder, "FoodStolen", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Bat combat
	-- -----------------------------------------------------------------------
	-- Client → Server: player swung the bat (server validates + applies damage)
	BatSwing = getOrCreate(eventsFolder, "BatSwing", "RemoteEvent"),
	-- Server → Client (attacker only): hit confirmed; plays hit-confirm sound
	BatHit = getOrCreate(eventsFolder, "BatHit", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Food inventory (give / drop)
	-- -----------------------------------------------------------------------
	-- Client → Server: give equipped food to a nearby player
	GiveFood = getOrCreate(eventsFolder, "GiveFood", "RemoteEvent"),
	-- Client → Server: drop equipped food as a world pickup
	DropFood = getOrCreate(eventsFolder, "DropFood", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Refrigerator level system
	-- -----------------------------------------------------------------------
	-- Client → Server: upgrade a fridge to the next level (costs Money)
	UpgradeFridge = getOrCreate(eventsFolder, "UpgradeFridge", "RemoteEvent"),
	-- Client → Server: process equipped food in a fridge to boost its value
	StoreFoodInFridge = getOrCreate(eventsFolder, "StoreFoodInFridge", "RemoteEvent"),
	-- Server → Client: price breakdown popup after storing food
	FridgeStoredFeedback = getOrCreate(eventsFolder, "FridgeStoredFeedback", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Flying carpet (night reward)
	-- -----------------------------------------------------------------------
	-- Client → Server: periodic position report while flying (for server validation)
	CarpetPositionUpdate = getOrCreate(eventsFolder, "CarpetPositionUpdate", "RemoteEvent"),
	-- Server → Client: tells the flying client their carpet was revoked (dawn)
	CarpetRevoked = getOrCreate(eventsFolder, "CarpetRevoked", "RemoteEvent"),
	-- Server → All Clients: carpet has spawned; show location hint
	CarpetSpawned = getOrCreate(eventsFolder, "CarpetSpawned", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Server-to-server signal (BindableEvent — never replicated to clients)
	-- Fires when any player steals food; HunterAI listens to alert guards.
	-- -----------------------------------------------------------------------
	FoodStolenServer = getOrCreate(Shared, "FoodStolenServer", "BindableEvent"),
}

return RemoteEvents
