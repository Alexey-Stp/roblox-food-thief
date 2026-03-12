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
}

return RemoteEvents
