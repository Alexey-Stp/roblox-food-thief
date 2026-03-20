-- BatClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Fires BatSwing to the server whenever the local player activates the Bat tool.
-- The server (BatCombat.lua) performs spatial validation and applies damage
-- to other players, Hunter NPCs, and destructible Castle parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Wait for the shared RemoteEvents folder (populated by server on start)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local BatSwing = eventsFolder:WaitForChild("BatSwing")

-- Active Activated connection — disconnected when the bat is unequipped
local activatedConn = nil

-- -------------------------------------------------------------------------
-- Hook the Bat tool's Activated event
-- -------------------------------------------------------------------------
local function hookBatTool(tool)
	if tool.Name ~= "Bat" then
		return
	end

	-- Disconnect any previous connection before wiring a new one
	if activatedConn then
		activatedConn:Disconnect()
		activatedConn = nil
	end

	activatedConn = tool.Activated:Connect(function()
		-- Send the local HRP position as a hint; the server re-validates targets
		-- independently and never trusts the client for target selection.
		local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
		BatSwing:FireServer(hrp and hrp.Position or Vector3.zero)
	end)

	-- Clean up when the tool is unequipped or removed
	tool.Unequipped:Connect(function()
		if activatedConn then
			activatedConn:Disconnect()
			activatedConn = nil
		end
	end)
end

-- -------------------------------------------------------------------------
-- Watch the character for the Bat being equipped
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	-- In case the Bat is already in the character (rare but safe to handle)
	local existing = character:FindFirstChildOfClass("Tool")
	if existing then
		hookBatTool(existing)
	end

	-- Watch for any Tool added to the character (including future equips)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookBatTool(child)
		end
	end)
end

-- -------------------------------------------------------------------------
-- Initialise for the current and future characters
-- -------------------------------------------------------------------------
localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
