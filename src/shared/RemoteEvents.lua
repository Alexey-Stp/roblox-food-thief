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
	-- (store / upgrade use server-side ProximityPrompts — no client remote)
	-- -----------------------------------------------------------------------
	-- Server → Client: price breakdown popup after storing food
	FridgeStoredFeedback = getOrCreate(eventsFolder, "FridgeStoredFeedback", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Flying carpet (night reward)
	-- -----------------------------------------------------------------------
	-- (flight is validated by the server polling HumanoidRootPart — no client report)
	-- Server → Client: tells the flying client their carpet was revoked (dawn)
	CarpetRevoked = getOrCreate(eventsFolder, "CarpetRevoked", "RemoteEvent"),
	-- Server → All Clients: carpet has spawned; show location hint
	CarpetSpawned = getOrCreate(eventsFolder, "CarpetSpawned", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Chest-loot weapons (Pistol / Rifle)
	-- -----------------------------------------------------------------------
	-- Client → Server: player fired a weapon (server raycasts + applies damage)
	ShootWeapon = getOrCreate(eventsFolder, "ShootWeapon", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- UI / cosmetic
	-- -----------------------------------------------------------------------
	-- Server → Client: short toast message (cooldowns, purchases, warnings)
	Notify = getOrCreate(eventsFolder, "Notify", "RemoteEvent"),
	-- Server → All Clients: airplane flight parameters; clients animate the model
	AirplaneFlight = getOrCreate(eventsFolder, "AirplaneFlight", "RemoteEvent"),

	-- -----------------------------------------------------------------------
	-- Server-to-server signal (BindableEvent — never replicated to clients)
	-- Fires when any player steals food; HunterAI listens to alert guards.
	-- -----------------------------------------------------------------------
	FoodStolenServer = getOrCreate(Shared, "FoodStolenServer", "BindableEvent"),
}

return RemoteEvents
