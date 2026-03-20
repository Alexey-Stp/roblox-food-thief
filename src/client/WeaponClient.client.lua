-- WeaponClient.client.lua  (LocalScript in StarterPlayerScripts)
-- Fires ShootWeapon to the server whenever the local player activates a
-- Pistol or Rifle tool.  The server (ChestSystem.lua) performs raycast
-- validation, range checks, cooldowns, and applies damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local eventsFolder = Shared:WaitForChild("Events")
local ShootWeapon = eventsFolder:WaitForChild("ShootWeapon")

local WEAPON_NAMES = { Pistol = true, Rifle = true }

local activatedConn = nil

-- -------------------------------------------------------------------------
-- Hook a weapon tool's Activated event
-- -------------------------------------------------------------------------
local function hookWeaponTool(tool)
	if not WEAPON_NAMES[tool.Name] then
		return
	end

	if activatedConn then
		activatedConn:Disconnect()
		activatedConn = nil
	end

	activatedConn = tool.Activated:Connect(function()
		-- Send tool name + camera look vector; server re-validates everything
		local cam = workspace.CurrentCamera
		local aimDir = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
		ShootWeapon:FireServer(tool.Name, aimDir)
	end)

	tool.Unequipped:Connect(function()
		if activatedConn then
			activatedConn:Disconnect()
			activatedConn = nil
		end
	end)
end

-- -------------------------------------------------------------------------
-- Watch the character for weapon tools being equipped
-- -------------------------------------------------------------------------
local function onCharacterAdded(character)
	local existing = character:FindFirstChildOfClass("Tool")
	if existing then
		hookWeaponTool(existing)
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookWeaponTool(child)
		end
	end)
end

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
