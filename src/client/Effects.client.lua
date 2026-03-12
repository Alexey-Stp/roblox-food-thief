-- Effects.client.lua  (LocalScript in StarterPlayerScripts)
-- Handles all client-side visual effects so they only affect the local player.
-- Bug fix: the original script ran ColorCorrectionEffect on the server,
-- which affected every player's screen. This is now correctly client-only.

local Players        = game:GetService("Players")
local Lighting       = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Wait for the shared RemoteEvents folder (populated by server on start)
local Shared       = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local HitFlash     = eventsFolder:WaitForChild("HitFlash")
local FoodStolen   = eventsFolder:WaitForChild("FoodStolen")

-- -------------------------------------------------------------------------
-- Hit flash: red tint on the local player's screen only
-- -------------------------------------------------------------------------
HitFlash.OnClientEvent:Connect(function()
	local flash = Instance.new("ColorCorrectionEffect")
	flash.TintColor = Color3.new(1, 0.1, 0.1)
	flash.Saturation = -0.3
	flash.Parent    = Lighting

	task.delay(0.15, function()
		flash:Destroy()
	end)
end)

-- -------------------------------------------------------------------------
-- Food stolen sparkle: brief particle burst at the pick-up position
-- -------------------------------------------------------------------------
FoodStolen.OnClientEvent:Connect(function(worldPosition)
	-- Create a temporary part at the food's world position to host the emitter
	local origin = Instance.new("Part")
	origin.Size        = Vector3.new(0.1, 0.1, 0.1)
	origin.Position    = worldPosition
	origin.Anchored    = true
	origin.CanCollide  = false
	origin.Transparency = 1
	origin.Parent      = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture       = "rbxassetid://744949272"  -- sparkle texture
	emitter.Color         = ColorSequence.new(Color3.new(1, 1, 0), Color3.new(0, 1, 0))
	emitter.Size          = NumberSequence.new(0.3, 0)
	emitter.Speed         = NumberRange.new(8, 15)
	emitter.Lifetime      = NumberRange.new(0.4, 0.8)
	emitter.SpreadAngle   = Vector2.new(180, 180)
	emitter.Rate          = 0   -- burst-only; we emit manually
	emitter.Parent        = origin

	-- Emit a one-shot burst then clean up
	emitter:Emit(20)
	task.delay(1, function()
		origin:Destroy()
	end)
end)
